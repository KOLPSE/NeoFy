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
use axum::http::StatusCode;
use axum::routing::get;
use axum::{Json, Router};
use librespot_core::cache::Cache;
use librespot_core::config::SessionConfig;
use librespot_core::session::Session;
use librespot_core::SpotifyUri;
use librespot_metadata::{Metadata, Playlist, Track};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tokio::sync::Mutex;

const PUERTO_POR_DEFECTO: u16 = 8900;

/// Una playlist ya resuelta. `Playlist::get` trae la lista entera de una vez,
/// asi que se guarda: pedir la pagina 2 no debe volver a descargar las 3.000
/// referencias.
struct ListaCacheada {
    nombre: String,
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

#[tokio::main]
async fn main() {
    let puerto: u16 = std::env::args()
        .nth(1)
        .and_then(|p| p.parse().ok())
        .unwrap_or(PUERTO_POR_DEFECTO);

    let appdata = match std::env::var("APPDATA") {
        Ok(v) => v,
        Err(_) => {
            eprintln!("ERROR: no hay APPDATA en el entorno");
            std::process::exit(2);
        }
    };
    let cache_dir = PathBuf::from(appdata).join("spotify-native").join("librespot");

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
        total: lista.pistas.len(),
        items: recogidas.into_iter().map(|(_, v)| v).collect(),
    }))
}

async fn obtener_lista(estado: &Estado, id: &str) -> Result<Arc<ListaCacheada>, Fallo> {
    if let Some(l) = estado.listas.lock().await.get(id) {
        return Ok(l.clone());
    }

    let uri = SpotifyUri::from_uri(&format!("spotify:playlist:{id}"))
        .map_err(|e| fallo(StatusCode::BAD_REQUEST, format!("id de playlist invalido: {e}")))?;

    let pl = Playlist::get(&estado.session, &uri)
        .await
        .map_err(|e| fallo(StatusCode::BAD_GATEWAY, format!("Spotify no devolvio la playlist: {e}")))?;

    let lista = Arc::new(ListaCacheada {
        nombre: pl.name().to_string(),
        pistas: pl.tracks().cloned().collect(),
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
