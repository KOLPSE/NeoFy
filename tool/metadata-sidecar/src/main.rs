//! Sidecar de metadatos: lee por el protocolo interno de Spotify lo que la Web
//! API deniega en Modo Desarrollo (el contenido de playlists ajenas), y lo sirve
//! en localhost con la misma forma de JSON que la Web API.
//!
//!   metadata-sidecar.exe [puerto]
//!
//! Reutiliza las credenciales que librespot ya dejo cacheadas; no pide login.
//! Escribe la linea "READY <puerto>" en stdout cuando esta listo para atender.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;

use axum::extract::{Path, Query, State};
use axum::http::{Method, StatusCode};
use axum::routing::get;
use axum::{Json, Router};
use librespot_core::cache::Cache;
use librespot_core::config::SessionConfig;
use librespot_core::session::Session;
use librespot_core::SpotifyUri;
use librespot_metadata::{Metadata, Playlist, Track};
use librespot_protocol as protocol;
use protobuf::Message;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tokio::sync::Mutex;

const PUERTO_POR_DEFECTO: u16 = 8900;

/// Una playlist ya resuelta. `obtener_lista` trae la lista completa (paginando
/// por el protocolo interno si Spotify la devolvió truncada), así que se guarda
/// para que pedir páginas sucesivas no vuelva a consultar a Spotify.
struct ListaCacheada {
    nombre: String,
    total: usize,
    pistas: Vec<SpotifyUri>,
}

#[derive(Clone)]
struct Estado {
    session: Session,
    listas: Arc<Mutex<HashMap<String, Arc<ListaCacheada>>>>,
}

#[derive(Deserialize)]
struct Paginacion {
    offset: Option<usize>,
    limit: Option<usize>,
}

#[derive(Serialize)]
struct RespuestaPlaylist {
    name: String,
    total: usize,
    items: Vec<Value>,
}

type Fallo = (StatusCode, Json<Value>);

fn fallo(code: StatusCode, msg: impl Into<String>) -> Fallo {
    (code, Json(json!({ "error": msg.into() })))
}

fn resolver_cache_dir() -> Result<PathBuf, String> {
    if let Ok(appdata) = std::env::var("APPDATA") {
        let neofy = PathBuf::from(&appdata).join("neofy").join("librespot");
        if neofy.exists() {
            return Ok(neofy);
        }
        let legacy = PathBuf::from(&appdata).join("spotify-native").join("librespot");
        if legacy.exists() {
            return Ok(legacy);
        }
        return Ok(neofy);
    }
    if let Ok(xdg) = std::env::var("XDG_CONFIG_HOME") {
        if !xdg.is_empty() {
            return Ok(PathBuf::from(xdg).join("neofy").join("librespot"));
        }
    }
    if let Ok(home) = std::env::var("HOME") {
        if !home.is_empty() {
            return Ok(PathBuf::from(home).join(".config").join("neofy").join("librespot"));
        }
    }
    Err("No se pudo determinar el directorio de datos (APPDATA o HOME no definidos)".into())
}

#[tokio::main]
async fn main() {
    let puerto: u16 = std::env::args()
        .nth(1)
        .and_then(|p| p.parse().ok())
        .unwrap_or(PUERTO_POR_DEFECTO);

    let cache_dir = match resolver_cache_dir() {
        Ok(d) => d,
        Err(e) => {
            eprintln!("ERROR: {e}");
            std::process::exit(2);
        }
    };

    let cache = match Cache::new(Some(&cache_dir), Some(&cache_dir), None, None) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("ERROR: no se pudo abrir la cache de librespot: {e}");
            std::process::exit(2);
        }
    };
    let creds = match cache.credentials() {
        Some(c) => c,
        None => {
            // Normal en el primer arranque: la app lanza antes librespot, que
            // hace el login y deja las credenciales aqui.
            eprintln!("ERROR: no hay credenciales cacheadas todavia");
            std::process::exit(3);
        }
    };

    let session = Session::new(SessionConfig::default(), Some(cache));
    if let Err(e) = session.connect(creds, false).await {
        eprintln!("ERROR: no se pudo conectar con Spotify: {e}");
        std::process::exit(4);
    }

    let estado = Estado {
        session,
        listas: Arc::new(Mutex::new(HashMap::new())),
    };

    let app = Router::new()
        .route("/health", get(|| async { "ok" }))
        .route("/playlist/{id}", get(playlist))
        .with_state(estado);

    let listener = match tokio::net::TcpListener::bind(("127.0.0.1", puerto)).await {
        Ok(l) => l,
        Err(e) => {
            eprintln!("ERROR: no se pudo escuchar en 127.0.0.1:{puerto}: {e}");
            std::process::exit(5);
        }
    };

    // El proceso padre espera esta linea para saber que ya puede preguntar.
    println!("READY {puerto}");

    if let Err(e) = axum::serve(listener, app).await {
        eprintln!("ERROR: el servidor se detuvo: {e}");
        std::process::exit(6);
    }
}

async fn playlist(
    State(estado): State<Estado>,
    Path(id): Path<String>,
    Query(pag): Query<Paginacion>,
) -> Result<Json<RespuestaPlaylist>, Fallo> {
    let lista = obtener_lista(&estado, &id).await?;

    let offset = pag.offset.unwrap_or(0);
    let limit = pag.limit.unwrap_or(50).clamp(1, 100);

    let pagina: Vec<SpotifyUri> = lista
        .pistas
        .iter()
        .skip(offset)
        .take(limit)
        .cloned()
        .collect();

    // En paralelo: 50 pistas tardan ~85 ms sobre la sesion ya abierta.
    let mut tareas = tokio::task::JoinSet::new();
    for (i, uri) in pagina.into_iter().enumerate() {
        let s = estado.session.clone();
        tareas.spawn(async move { (i, Track::get(&s, &uri).await) });
    }

    let mut recogidas: Vec<(usize, Value)> = Vec::new();
    while let Some(res) = tareas.join_next().await {
        // Una pista que no se puede leer (retirada del catalogo, region) se
        // omite en vez de tumbar la pagina entera.
        if let Ok((i, Ok(t))) = res {
            recogidas.push((i, track_a_json(&t)));
        }
    }
    // JoinSet devuelve en orden de finalizacion; hay que restaurar el de la playlist.
    recogidas.sort_by_key(|(i, _)| *i);

    Ok(Json(RespuestaPlaylist {
        name: lista.nombre.clone(),
        total: lista.total,
        items: recogidas.into_iter().map(|(_, v)| v).collect(),
    }))
}

async fn obtener_lista(estado: &Estado, id: &str) -> Result<Arc<ListaCacheada>, Fallo> {
    if let Some(l) = estado.listas.lock().await.get(id) {
        return Ok(l.clone());
    }

    let uri = SpotifyUri::from_uri(&format!("spotify:playlist:{id}"))
        .map_err(|e| fallo(StatusCode::BAD_REQUEST, format!("id de playlist invalido: {e}")))?;

    let playlist_id = match uri {
        SpotifyUri::Playlist { id: pid, .. } => pid,
        _ => return Err(fallo(StatusCode::BAD_REQUEST, "no es una URI de playlist")),
    };

    let pl = Playlist::get(&estado.session, &uri)
        .await
        .map_err(|e| fallo(StatusCode::BAD_GATEWAY, format!("Spotify no devolvio la playlist: {e}")))?;

    let total_declarado = pl.length.max(0) as usize;
    let mut pistas: Vec<SpotifyUri> = pl.contents.items.iter().map(|item| item.id.clone()).collect();

    // Paginación interna para playlists grandes o truncadas:
    //
    // Spotify trunca o devuelve solo la primera ventana en peticiones estándar a
    // `/playlist/v2/playlist/{id}`. Tras verificación empírica contra la API real:
    // - Cabecera `Range: items=X-Y` o `Range: items=X-`: ignorada por Spotify (devuelve desde 0).
    // - Sufijo de ruta `/range/X/Y`: devuelve 404 Not Found.
    // - Query params `?offset=X&limit=Y`: ignorados por Spotify (devuelve desde 0).
    // - Query params `?from=X&length=Y`: SÍ responde devolviendo la ventana exacta solicitada
    //   (con `contents.pos = X` y hasta `length` elementos).
    //
    // Solicitamos en bloques de hasta 100 canciones mientras falten pistas para completar
    // el `total_declarado` o mientras `pl.contents.is_truncated` sea `true`.
    let batch_size = 100;
    while pl.contents.is_truncated || pistas.len() < total_declarado {
        let from = pistas.len();
        if from >= total_declarado && !pl.contents.is_truncated {
            break;
        }
        let length = if total_declarado > from {
            (total_declarado - from).min(batch_size)
        } else {
            batch_size
        };

        let playlist_b62 = match playlist_id.to_base62() {
            Ok(b) => b,
            Err(e) => {
                eprintln!("Error codificando playlist id en base62: {e}");
                break;
            }
        };

        let endpoint = format!("/playlist/v2/playlist/{playlist_b62}?from={from}&length={length}");
        let bytes = match estado.session.spclient().request(&Method::GET, &endpoint, None, None).await {
            Ok(b) => b,
            Err(e) => {
                eprintln!("Aviso: fallo al paginar playlist {id} en from={from}: {e}");
                break;
            }
        };

        let proto = match protocol::playlist4_external::SelectedListContent::parse_from_bytes(&bytes) {
            Ok(p) => p,
            Err(e) => {
                eprintln!("Aviso: error parseando respuesta proto de playlist {id}: {e}");
                break;
            }
        };

        let contents = proto.contents.unwrap_or_default();
        if contents.items.is_empty() {
            break;
        }

        let mut anadidas = 0;
        for item in contents.items.iter() {
            if let Ok(t_uri) = SpotifyUri::from_uri(item.uri()) {
                pistas.push(t_uri);
                anadidas += 1;
            }
        }

        // Salvaguarda contra bucle infinito si la respuesta no aportó elementos nuevos
        if anadidas == 0 {
            break;
        }

        if !contents.truncated() && pistas.len() >= total_declarado {
            break;
        }
    }

    let lista = Arc::new(ListaCacheada {
        nombre: pl.name().to_string(),
        total: total_declarado.max(pistas.len()),
        pistas,
    });
    estado.listas.lock().await.insert(id.to_string(), lista.clone());
    Ok(lista)
}

/// Convierte una pista al JSON de la Web API, para que el cliente Flutter la
/// parsee con el mismo `Track.fromJson` que usa para todo lo demas.
fn track_a_json(t: &Track) -> Value {
    let artistas: Vec<Value> = t
        .artists
        .iter()
        .map(|a| json!({ "name": a.name }))
        .collect();

    json!({
        "id": id_base62(&t.id),
        "uri": t.id.to_uri().unwrap_or_default(),
        "name": t.name,
        "duration_ms": t.duration,
        "is_local": false,
        "artists": artistas,
        "album": {
            "name": t.album.name,
            "images": imagenes(t),
        },
    })
}

/// Spotify sirve las caratulas en `https://i.scdn.co/image/<file_id en hex>`.
/// librespot da el file_id; la URL se construye a mano.
fn imagenes(t: &Track) -> Vec<Value> {
    t.album
        .covers
        .iter()
        .filter_map(|img| {
            let hex = img.id.to_base16().ok()?;
            Some(json!({
                "url": format!("https://i.scdn.co/image/{hex}"),
                "width": img.width,
                "height": img.height,
            }))
        })
        .collect()
}

fn id_base62(uri: &SpotifyUri) -> String {
    uri.to_uri()
        .ok()
        .and_then(|u| u.rsplit(':').next().map(|s| s.to_string()))
        .unwrap_or_default()
}
