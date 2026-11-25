use std::collections::{HashMap, VecDeque};
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
use librespot_metadata::artist::{AlbumGroups, ArtistRole};
use librespot_metadata::image::Images;
use librespot_metadata::{Album, Artist, Metadata, Playlist, Track};
use librespot_protocol as protocol;
use librespot_protocol::extension_kind::ExtensionKind;
use protobuf::Message;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tokio::sync::Mutex;

const PUERTO_POR_DEFECTO: u16 = 8900;
const MAX_LISTAS_CACHEADAS: usize = 16;
const MAX_ENTRADAS_METADATOS: usize = 64;

struct ListaCacheada {
    nombre: String,
    total: usize,
    pistas: Vec<SpotifyUri>,
}

struct CacheAcotada<V> {
    capacidad: usize,
    mapa: HashMap<String, V>,
    orden: VecDeque<String>,
}

impl<V: Clone> CacheAcotada<V> {
    fn nueva(capacidad: usize) -> Self {
        Self {
            capacidad: capacidad.max(1),
            mapa: HashMap::new(),
            orden: VecDeque::new(),
        }
    }

    fn get(&mut self, id: &str) -> Option<V> {
        let encontrada = self.mapa.get(id).cloned()?;
        if let Some(pos) = self.orden.iter().position(|k| k == id) {
            self.orden.remove(pos);
        }
        self.orden.push_back(id.to_string());
        Some(encontrada)
    }

    fn insert(&mut self, id: String, valor: V) {
        if self.mapa.contains_key(&id) {
            if let Some(pos) = self.orden.iter().position(|k| k == &id) {
                self.orden.remove(pos);
            }
        } else if self.mapa.len() >= self.capacidad {
            if let Some(vieja) = self.orden.pop_front() {
                self.mapa.remove(&vieja);
            }
        }
        self.orden.push_back(id.clone());
        self.mapa.insert(id, valor);
    }
}

#[derive(Clone)]
struct Estado {
    session: Session,
    listas: Arc<Mutex<CacheAcotada<Arc<ListaCacheada>>>>,
    creditos: Arc<Mutex<CacheAcotada<Value>>>,
    insights: Arc<Mutex<CacheAcotada<Value>>>,
    canvas: Arc<Mutex<CacheAcotada<Value>>>,
}

#[derive(Deserialize)]
struct Paginacion {
    offset: Option<usize>,
    limit: Option<usize>,
}

#[derive(Deserialize)]
struct ConsultaArtista {
    locale: Option<String>,
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

#[tokio::main(flavor = "current_thread")]
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

    let cache = match Cache::new(Some(&cache_dir), None, None, None) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("ERROR: no se pudo abrir la cache de librespot: {e}");
            std::process::exit(2);
        }
    };
    let creds = match cache.credentials() {
        Some(c) => c,
        None => {

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
        listas: Arc::new(Mutex::new(CacheAcotada::nueva(MAX_LISTAS_CACHEADAS))),
        creditos: Arc::new(Mutex::new(CacheAcotada::nueva(MAX_ENTRADAS_METADATOS))),
        insights: Arc::new(Mutex::new(CacheAcotada::nueva(MAX_ENTRADAS_METADATOS))),
        canvas: Arc::new(Mutex::new(CacheAcotada::nueva(MAX_ENTRADAS_METADATOS))),
    };

    let app = Router::new()
        .route("/health", get(|| async { "ok" }))
        .route("/playlist/{id}", get(playlist))
        .route("/artist/{id}", get(artista))
        .route("/artist/{id}/insights", get(artista_insights))
        .route("/album/{id}", get(album))
        .route("/track/{id}/credits", get(creditos_pista))
        .route("/track/{id}/canvas", get(canvas_pista))
        .with_state(estado);

    let listener = match tokio::net::TcpListener::bind(("127.0.0.1", puerto)).await {
        Ok(l) => l,
        Err(e) => {
            eprintln!("ERROR: no se pudo escuchar en 127.0.0.1:{puerto}: {e}");
            std::process::exit(5);
        }
    };

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

    let mut tareas = tokio::task::JoinSet::new();
    for (i, uri) in pagina.into_iter().enumerate() {
        let s = estado.session.clone();
        tareas.spawn(async move { (i, Track::get(&s, &uri).await) });
    }

    let mut recogidas: Vec<(usize, Value)> = Vec::new();
    while let Some(res) = tareas.join_next().await {

        if let Ok((i, Ok(t))) = res {
            recogidas.push((i, track_a_json(&t)));
        }
    }

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
            "images": imagenes_de(&t.album.covers),
        },
    })
}

fn id_base62(uri: &SpotifyUri) -> String {
    uri.to_uri()
        .ok()
        .and_then(|u| u.rsplit(':').next().map(|s| s.to_string()))
        .unwrap_or_default()
}

const MAX_TOP: usize = 8;
const MAX_ALBUMES: usize = 12;
const MAX_SINGLES: usize = 12;
const MAX_APARECE: usize = 10;
const MAX_RELACIONADOS: usize = 12;

async fn artista(
    State(estado): State<Estado>,
    Path(id): Path<String>,
    Query(consulta): Query<ConsultaArtista>,
) -> Result<Json<Value>, Fallo> {
    let uri = SpotifyUri::from_uri(&format!("spotify:artist:{id}"))
        .map_err(|e| fallo(StatusCode::BAD_REQUEST, format!("id de artista invalido: {e}")))?;

    let a = Artist::get(&estado.session, &uri)
        .await
        .map_err(|e| fallo(StatusCode::BAD_GATEWAY, format!("Spotify no devolvio el artista: {e}")))?;

    let retratos = if a.portrait_group.is_empty() {
        &a.portraits
    } else {
        &a.portrait_group
    };
    let biografias: Vec<String> = a
        .biographies
        .iter()
        .map(|b| b.text.trim())
        .filter(|t| !t.is_empty())
        .map(|t| t.to_string())
        .collect();

    let top_uris: Vec<SpotifyUri> = uris_top(&a, consulta.locale.as_deref());
    let album_uris: Vec<SpotifyUri> = uris_de(&a.albums, MAX_ALBUMES);
    let single_uris: Vec<SpotifyUri> = uris_de(&a.singles, MAX_SINGLES);
    let aparece_uris: Vec<SpotifyUri> = uris_de(&a.appears_on_albums, MAX_APARECE);

    let (top, albumes, singles, aparece_en) = tokio::join!(
        pistas_de(estado.session.clone(), top_uris),
        albumes_de(estado.session.clone(), album_uris, "album"),
        albumes_de(estado.session.clone(), single_uris, "single"),
        albumes_de(estado.session.clone(), aparece_uris, "appears_on"),
    );

    let relacionados: Vec<Value> = a
        .related
        .iter()
        .take(MAX_RELACIONADOS)
        .map(artista_resumen)
        .collect();

    Ok(Json(json!({
        "id": id_base62(&a.id),
        "uri": a.id.to_uri().unwrap_or_default(),
        "name": a.name,
        "popularity": a.popularity,
        "biographies": biografias,
        "biography": biografias.first().cloned().unwrap_or_default(),
        "images": imagenes_de(retratos),
        "top_tracks": top,
        "albums": albumes,
        "singles": singles,
        "appears_on": aparece_en,
        "related": relacionados,
    })))
}

async fn album(
    State(estado): State<Estado>,
    Path(id): Path<String>,
) -> Result<Json<Value>, Fallo> {
    let uri = SpotifyUri::from_uri(&format!("spotify:album:{id}"))
        .map_err(|e| fallo(StatusCode::BAD_REQUEST, format!("id de album invalido: {e}")))?;

    let a = Album::get(&estado.session, &uri)
        .await
        .map_err(|e| fallo(StatusCode::BAD_GATEWAY, format!("Spotify no devolvio el album: {e}")))?;

    let uris: Vec<SpotifyUri> = a.tracks().cloned().collect();
    let items = pistas_de(estado.session.clone(), uris).await;
    let total = items.len();

    Ok(Json(json!({
        "id": id_base62(&a.id),
        "uri": a.id.to_uri().unwrap_or_default(),
        "name": a.name,
        "artists": artistas_a_json(&a.artists),
        "images": imagenes_de(&a.covers),
        "release_date": fecha_iso(&a.date),
        "album_type": tipo_de_album(&a),
        "total_tracks": total,
        "tracks": {
            "items": items,
            "total": total,
        },
    })))
}

fn uris_de(grupos: &AlbumGroups, max: usize) -> Vec<SpotifyUri> {
    grupos.current_releases().take(max).cloned().collect()
}

/// Las top tracks de mercury van por país. `for_country("")` solo acierta si
/// hay cubo global; si no, la lista sale vacía aunque ES/US estén llenos.
fn uris_top(a: &Artist, locale: Option<&str>) -> Vec<SpotifyUri> {
    let mut paises: Vec<&str> = Vec::new();
    if let Some(loc) = locale {
        if let Some((_, pais)) = loc.split_once('_') {
            if !pais.is_empty() {
                paises.push(pais);
            }
        }
    }
    for pais in ["ES", "US", "GB", ""] {
        if !paises.contains(&pais) {
            paises.push(pais);
        }
    }
    for pais in paises {
        let tracks = a.top_tracks.for_country(pais);
        if !tracks.is_empty() {
            return tracks.iter().cloned().take(MAX_TOP).collect();
        }
    }
    a.top_tracks
        .iter()
        .find(|g| !g.tracks.is_empty())
        .map(|g| g.tracks.iter().cloned().take(MAX_TOP).collect())
        .unwrap_or_default()
}

async fn pistas_de(session: librespot_core::session::Session, uris: Vec<SpotifyUri>) -> Vec<Value> {
    let mut tareas = tokio::task::JoinSet::new();
    for (i, uri) in uris.into_iter().enumerate() {
        let s = session.clone();
        tareas.spawn(async move { (i, Track::get(&s, &uri).await) });
    }
    recoger(tareas, |t| track_a_json(&t)).await
}

async fn albumes_de(
    session: librespot_core::session::Session,
    uris: Vec<SpotifyUri>,
    grupo: &'static str,
) -> Vec<Value> {
    let mut tareas = tokio::task::JoinSet::new();
    for (i, uri) in uris.into_iter().enumerate() {
        let s = session.clone();
        tareas.spawn(async move { (i, Album::get(&s, &uri).await) });
    }
    recoger(tareas, |a| album_a_json(&a, grupo)).await
}

async fn recoger<T, F>(
    mut tareas: tokio::task::JoinSet<(usize, Result<T, librespot_core::Error>)>,
    a_json: F,
) -> Vec<Value>
where
    T: Send + 'static,
    F: Fn(&T) -> Value,
{
    let mut recogidas: Vec<(usize, Value)> = Vec::new();
    while let Some(res) = tareas.join_next().await {
        if let Ok((i, Ok(v))) = res {
            recogidas.push((i, a_json(&v)));
        }
    }
    recogidas.sort_by_key(|(i, _)| *i);
    recogidas.into_iter().map(|(_, v)| v).collect()
}

fn artista_resumen(a: &Artist) -> Value {
    let retratos = if a.portrait_group.is_empty() {
        &a.portraits
    } else {
        &a.portrait_group
    };
    json!({
        "id": id_base62(&a.id),
        "uri": a.id.to_uri().unwrap_or_default(),
        "name": a.name,
        "popularity": a.popularity,
        "images": imagenes_de(retratos),
    })
}

fn artistas_a_json(artistas: &librespot_metadata::artist::Artists) -> Vec<Value> {
    artistas
        .iter()
        .map(|a| {
            json!({
                "id": id_base62(&a.id),
                "uri": a.id.to_uri().unwrap_or_default(),
                "name": a.name,
            })
        })
        .collect()
}

fn album_a_json(a: &Album, grupo: &str) -> Value {
    json!({
        "id": id_base62(&a.id),
        "uri": a.id.to_uri().unwrap_or_default(),
        "name": a.name,
        "artists": artistas_a_json(&a.artists),
        "images": imagenes_de(&a.covers),
        "release_date": fecha_iso(&a.date),
        "album_group": grupo,
        "album_type": tipo_de_album(a),
        "total_tracks": a.tracks().count(),
    })
}

fn tipo_de_album(a: &Album) -> String {
    let t = a.type_str.trim().to_lowercase();
    if t.is_empty() { "album".into() } else { t }
}

fn fecha_iso(d: &librespot_core::date::Date) -> String {
    format!("{:04}-{:02}-{:02}", d.year(), u8::from(d.month()), d.day())
}

fn imagenes_de(imgs: &Images) -> Vec<Value> {
    imgs.iter()
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

async fn creditos_pista(
    State(estado): State<Estado>,
    Path(id): Path<String>,
) -> Result<Json<Value>, Fallo> {
    if let Some(en_cache) = estado.creditos.lock().await.get(&id) {
        return Ok(Json(en_cache));
    }

    let endpoint = format!("/track-credits-view/v0/experimental/{id}/credits");
    let mut respuesta = match estado
        .session
        .spclient()
        .request_as_json(&Method::GET, &endpoint, None, None)
        .await
    {
        Ok(bytes) => serde_json::from_slice::<Value>(&bytes)
            .ok()
            .map(|v| parsear_creditos_json(&v)),
        Err(_) => None,
    };

    let vacio = respuesta
        .as_ref()
        .and_then(|v| v.get("credits").and_then(|c| c.as_array()))
        .is_none_or(|c| c.is_empty());

    if vacio {
        if let Ok(uri) = SpotifyUri::from_uri(&format!("spotify:track:{id}")) {
            if let Ok(track) = Track::get(&estado.session, &uri).await {
                respuesta = Some(creditos_desde_track(&track));
            }
        }
    }

    let salida = respuesta.unwrap_or_else(|| json!({ "credits": [], "sources": [] }));
    estado.creditos.lock().await.insert(id, salida.clone());
    Ok(Json(salida))
}

fn creditos_desde_track(track: &Track) -> Value {
    let mut orden: Vec<String> = Vec::new();
    let mut personas: HashMap<String, (String, String, Vec<String>)> = HashMap::new();

    for a in track.artists_with_role.iter() {
        let nombre = a.name.trim();
        if nombre.is_empty() {
            continue;
        }
        let clave = nombre.to_lowercase();
        let rol = match a.role {
            ArtistRole::ARTIST_ROLE_MAIN_ARTIST => "Main Artist",
            ArtistRole::ARTIST_ROLE_FEATURED_ARTIST => "Featured Artist",
            ArtistRole::ARTIST_ROLE_REMIXER => "Remixer",
            ArtistRole::ARTIST_ROLE_ACTOR => "Actor",
            ArtistRole::ARTIST_ROLE_COMPOSER => "Composer",
            ArtistRole::ARTIST_ROLE_CONDUCTOR => "Conductor",
            ArtistRole::ARTIST_ROLE_ORCHESTRA => "Orchestra",
            ArtistRole::ARTIST_ROLE_UNKNOWN => "Performer",
        };
        if !personas.contains_key(&clave) {
            orden.push(clave.clone());
            personas.insert(
                clave.clone(),
                (
                    nombre.to_string(),
                    id_base62(&a.id),
                    Vec::new(),
                ),
            );
        }
        if let Some((_, _, roles)) = personas.get_mut(&clave) {
            if !roles.iter().any(|r| r == rol) {
                roles.push(rol.to_string());
            }
        }
    }

    if personas.is_empty() {
        for a in track.artists.iter() {
            let nombre = a.name.trim();
            if nombre.is_empty() {
                continue;
            }
            let clave = nombre.to_lowercase();
            if !personas.contains_key(&clave) {
                orden.push(clave.clone());
                personas.insert(
                    clave,
                    (
                        nombre.to_string(),
                        id_base62(&a.id),
                        vec!["Main Artist".to_string()],
                    ),
                );
            }
        }
    }

    let credits: Vec<Value> = orden
        .into_iter()
        .filter_map(|k| personas.remove(&k))
        .map(|(name, aid, roles)| {
            let uri = if aid.is_empty() {
                String::new()
            } else {
                format!("spotify:artist:{aid}")
            };
            json!({
                "name": name,
                "id": aid,
                "uri": uri,
                "roles": roles,
            })
        })
        .collect();

    json!({
        "credits": credits,
        "sources": [],
    })
}

fn parsear_creditos_json(raw: &Value) -> Value {
    let mut orden: Vec<String> = Vec::new();
    let mut mapa: HashMap<String, (String, String, String, Vec<String>)> = HashMap::new();

    if let Some(grupos) = raw.get("roleCredits").and_then(|v| v.as_array()) {
        for grupo in grupos {
            let titulo_grupo = grupo
                .get("roleTitle")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .trim();
            let Some(artistas) = grupo.get("artists").and_then(|v| v.as_array()) else {
                continue;
            };
            for artista in artistas {
                let nombre = artista
                    .get("name")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .trim();
                if nombre.is_empty() {
                    continue;
                }
                let uri = artista
                    .get("uri")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .trim()
                    .to_string();
                let artist_id = if uri.starts_with("spotify:artist:") {
                    uri.rsplit(':').next().unwrap_or("").to_string()
                } else {
                    String::new()
                };
                let clave = if !artist_id.is_empty() {
                    format!("id:{artist_id}")
                } else {
                    format!("name:{}", nombre.to_lowercase())
                };

                if !mapa.contains_key(&clave) {
                    orden.push(clave.clone());
                    mapa.insert(
                        clave.clone(),
                        (nombre.to_string(), artist_id, uri, Vec::new()),
                    );
                }

                let Some((_, _, _, roles)) = mapa.get_mut(&clave) else {
                    continue;
                };

                let mut subroles: Vec<&str> = artista
                    .get("subroles")
                    .and_then(|v| v.as_array())
                    .map(|arr| {
                        arr.iter()
                            .filter_map(|s| s.as_str().map(str::trim))
                            .filter(|s| !s.is_empty())
                            .collect()
                    })
                    .unwrap_or_default();

                if subroles.is_empty() && !titulo_grupo.is_empty() {
                    subroles.push(titulo_grupo);
                }

                for r in subroles {
                    if !roles.iter().any(|existente| existente.eq_ignore_ascii_case(r)) {
                        roles.push(r.to_string());
                    }
                }
            }
        }
    }

    let credits: Vec<Value> = orden
        .into_iter()
        .filter_map(|k| mapa.remove(&k))
        .map(|(name, id, uri, roles)| {
            json!({
                "name": name,
                "id": id,
                "uri": uri,
                "roles": roles,
            })
        })
        .collect();

    let sources: Vec<String> = raw
        .get("sourceNames")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|s| s.as_str().map(str::trim))
                .filter(|s| !s.is_empty())
                .map(|s| s.to_string())
                .collect()
        })
        .unwrap_or_default();

    json!({
        "credits": credits,
        "sources": sources,
    })
}

async fn artista_insights(
    State(estado): State<Estado>,
    Path(id): Path<String>,
    Query(consulta): Query<ConsultaArtista>,
) -> Result<Json<Value>, Fallo> {
    let clave_cache = format!("{}:{}", id, consulta.locale.as_deref().unwrap_or(""));
    if let Some(en_cache) = estado.insights.lock().await.get(&clave_cache) {
        return Ok(Json(en_cache));
    }

    let uri = SpotifyUri::from_uri(&format!("spotify:artist:{id}"))
        .map_err(|e| fallo(StatusCode::BAD_REQUEST, format!("id de artista invalido: {e}")))?;

    let a = Artist::get(&estado.session, &uri)
        .await
        .map_err(|e| fallo(StatusCode::BAD_GATEWAY, format!("Spotify no devolvio el artista: {e}")))?;

    let retratos = if a.portrait_group.is_empty() {
        &a.portraits
    } else {
        &a.portrait_group
    };
    let biografias: Vec<String> = a
        .biographies
        .iter()
        .map(|b| b.text.trim())
        .filter(|t| !t.is_empty())
        .map(|t| t.to_string())
        .collect();

    let mut base = json!({
        "id": id_base62(&a.id),
        "uri": a.id.to_uri().unwrap_or_default(),
        "name": a.name,
        "verified": false,
        "monthly_listeners": Value::Null,
        "biographies": biografias,
        "biography": biografias.first().cloned().unwrap_or_default(),
        "images": imagenes_de(retratos),
        "concerts": [],
    });

    let endpoint = match consulta.locale.as_deref() {
        Some(loc) if !loc.is_empty() => format!("/artistview/v1/artist/{id}?locale={loc}"),
        _ => format!("/artistview/v1/artist/{id}"),
    };
    if let Ok(bytes) = estado
        .session
        .spclient()
        .request_as_json(&Method::GET, &endpoint, None, None)
        .await
    {
        if let Ok(vista) = serde_json::from_slice::<Value>(&bytes) {
            fusionar_insights_json(&mut base, &vista, &a.name);
        }
    }

    estado.insights.lock().await.insert(clave_cache, base.clone());
    Ok(Json(base))
}

fn fusionar_insights_json(base: &mut Value, vista: &Value, nombre_artista: &str) {
    let verificado = vista
        .get("verified")
        .and_then(|v| v.as_bool())
        .or_else(|| {
            vista
                .get("profile")
                .and_then(|p| p.get("verified"))
                .and_then(|v| v.as_bool())
        })
        .unwrap_or(false);
    if let Some(obj) = base.as_object_mut() {
        obj.insert("verified".to_string(), json!(verificado));

        let oyentes = vista
            .get("monthly_listeners")
            .and_then(|v| v.as_u64())
            .or_else(|| {
                vista
                    .get("monthlyListeners")
                    .and_then(|v| v.as_u64())
            })
            .or_else(|| {
                vista
                    .pointer("/statistics/monthlyListeners")
                    .and_then(|v| v.as_u64())
            })
            .or_else(|| {
                vista
                    .pointer("/insights/monthly_listeners")
                    .and_then(|v| v.as_u64())
            });
        if let Some(n) = oyentes {
            obj.insert("monthly_listeners".to_string(), json!(n));
        }

        let bio_vista = vista
            .pointer("/biography/text")
            .and_then(|v| v.as_str())
            .or_else(|| vista.get("biography").and_then(|v| v.as_str()))
            .or_else(|| vista.pointer("/profile/biography/text").and_then(|v| v.as_str()))
            .map(str::trim)
            .filter(|s| !s.is_empty());
        if let Some(b) = bio_vista {
            let actual = obj
                .get("biography")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .trim()
                .is_empty();
            if actual {
                obj.insert("biography".to_string(), json!(b));
            }
        }

        let conciertos = extraer_conciertos(vista, nombre_artista);
        if !conciertos.is_empty() {
            obj.insert("concerts".to_string(), Value::Array(conciertos));
        }
    }
}

fn extraer_conciertos(vista: &Value, nombre_artista: &str) -> Vec<Value> {
    let lista = vista
        .pointer("/goods/concerts/items")
        .and_then(|v| v.as_array())
        .or_else(|| vista.pointer("/goods/events/items").and_then(|v| v.as_array()))
        .or_else(|| vista.pointer("/concerts/items").and_then(|v| v.as_array()))
        .or_else(|| vista.get("concerts").and_then(|v| v.as_array()))
        .or_else(|| vista.get("upcoming_concerts").and_then(|v| v.as_array()));

    let Some(items) = lista else {
        return Vec::new();
    };

    items
        .iter()
        .filter_map(|item| {
            let fecha = item
                .get("date")
                .and_then(|v| v.as_str())
                .or_else(|| item.pointer("/date/isoString").and_then(|v| v.as_str()))
                .or_else(|| item.get("date_iso").and_then(|v| v.as_str()))
                .or_else(|| item.get("startDate").and_then(|v| v.as_str()))?
                .trim();
            if fecha.is_empty() {
                return None;
            }
            let ciudad = item
                .get("city")
                .and_then(|v| v.as_str())
                .or_else(|| item.pointer("/venue/location/name").and_then(|v| v.as_str()))
                .or_else(|| item.get("location").and_then(|v| v.as_str()))
                .or_else(|| item.get("title").and_then(|v| v.as_str()))
                .unwrap_or("")
                .trim();
            let recinto = item
                .pointer("/venue/name")
                .and_then(|v| v.as_str())
                .or_else(|| item.get("venue").and_then(|v| v.as_str()))
                .unwrap_or("")
                .trim();
            if ciudad.is_empty() && recinto.is_empty() {
                return None;
            }
            let id = item
                .get("id")
                .and_then(|v| v.as_str())
                .or_else(|| item.get("uri").and_then(|v| v.as_str()))
                .unwrap_or("")
                .to_string();
            let artista = item
                .get("artist")
                .and_then(|v| v.as_str())
                .filter(|s| !s.trim().is_empty())
                .unwrap_or(nombre_artista);
            let url = item
                .get("uri")
                .and_then(|v| v.as_str())
                .or_else(|| item.get("url").and_then(|v| v.as_str()))
                .or_else(|| item.get("ticket_url").and_then(|v| v.as_str()))
                .unwrap_or("")
                .to_string();

            Some(json!({
                "id": id,
                "city": if ciudad.is_empty() { recinto } else { ciudad },
                "artist": artista,
                "venue": recinto,
                "date_iso": fecha,
                "url": url,
            }))
        })
        .collect()
}

async fn canvas_pista(
    State(estado): State<Estado>,
    Path(id): Path<String>,
) -> Result<Json<Value>, Fallo> {
    if let Some(en_cache) = estado.canvas.lock().await.get(&id) {
        return Ok(Json(en_cache));
    }

    let uri = SpotifyUri::from_uri(&format!("spotify:track:{id}"))
        .map_err(|e| fallo(StatusCode::BAD_REQUEST, format!("id de pista invalido: {e}")))?;

    let mut salida = json!({
        "canvas_url": Value::Null,
        "type": Value::Null,
    });

    for ext in [ExtensionKind::CANVAS_V1, ExtensionKind::CANVAZ] {
        let Ok(bytes) = estado.session.spclient().get_metadata(ext, &uri).await else {
            continue;
        };
        if let Ok(canvaz) =
            protocol::canvaz::entity_canvaz_response::Canvaz::parse_from_bytes(&bytes)
        {
            if !canvaz.url.trim().is_empty() {
                let tipo = format!("{:?}", canvaz.type_.enum_value_or_default());
                salida = json!({
                    "canvas_url": canvaz.url,
                    "type": tipo,
                });
                break;
            }
        }
        if let Ok(resp) = protocol::canvaz::EntityCanvazResponse::parse_from_bytes(&bytes) {
            let _ = resp;
        }
    }

    estado.canvas.lock().await.insert(id, salida.clone());
    Ok(Json(salida))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parsea_y_agrupa_creditos_por_persona() {
        let entrada = json!({
            "roleCredits": [
                {
                    "roleTitle": "Performers",
                    "artists": [
                        {
                            "name": "Dani Martín",
                            "uri": "spotify:artist:abc123",
                            "subroles": ["Main Artist"]
                        }
                    ]
                },
                {
                    "roleTitle": "Writers",
                    "artists": [
                        {
                            "name": "Dani Martín",
                            "uri": "spotify:artist:abc123",
                            "subroles": ["Composer", "Lyricist"]
                        },
                        {
                            "name": "Luis Fernando Ochoa",
                            "uri": "",
                            "subroles": ["Composer"]
                        }
                    ]
                }
            ],
            "sourceNames": ["Sony Music"]
        });

        let salida = parsear_creditos_json(&entrada);
        let creditos = salida["credits"].as_array().unwrap();
        assert_eq!(creditos.len(), 2);
        assert_eq!(creditos[0]["name"], "Dani Martín");
        assert_eq!(creditos[0]["id"], "abc123");
        assert_eq!(
            creditos[0]["roles"],
            json!(["Main Artist", "Composer", "Lyricist"])
        );
        assert_eq!(creditos[1]["name"], "Luis Fernando Ochoa");
        assert_eq!(creditos[1]["roles"], json!(["Composer"]));
        assert_eq!(salida["sources"], json!(["Sony Music"]));
    }

    #[test]
    fn fusiona_insights_con_oyentes_verificado_y_gira() {
        let mut base = json!({
            "id": "art1",
            "name": "Dani Martín",
            "verified": false,
            "monthly_listeners": Value::Null,
            "biography": "",
            "concerts": [],
        });

        let vista = json!({
            "verified": true,
            "monthly_listeners": 1811092,
            "biography": { "text": "Cantante español." },
            "goods": {
                "concerts": {
                    "items": [
                        {
                            "id": "c1",
                            "city": "Barcelona",
                            "venue": { "name": "Palau Sant Jordi" },
                            "date": "2027-03-19T21:00:00Z",
                            "url": "https://example.com/barcelona"
                        }
                    ]
                }
            }
        });

        fusionar_insights_json(&mut base, &vista, "Dani Martín");
        assert_eq!(base["verified"], json!(true));
        assert_eq!(base["monthly_listeners"], json!(1811092));
        assert_eq!(base["biography"], json!("Cantante español."));
        let conciertos = base["concerts"].as_array().unwrap();
        assert_eq!(conciertos.len(), 1);
        assert_eq!(conciertos[0]["city"], json!("Barcelona"));
        assert_eq!(conciertos[0]["venue"], json!("Palau Sant Jordi"));
        assert_eq!(conciertos[0]["date_iso"], json!("2027-03-19T21:00:00Z"));
    }

    #[test]
    fn cache_acotada_expulsa_el_mas_antiguo() {
        let mut cache = CacheAcotada::nueva(2);
        cache.insert("a".into(), 1);
        cache.insert("b".into(), 2);
        assert_eq!(cache.get("a"), Some(1));
        cache.insert("c".into(), 3);
        assert_eq!(cache.get("b"), None);
        assert_eq!(cache.get("a"), Some(1));
        assert_eq!(cache.get("c"), Some(3));
    }
}
