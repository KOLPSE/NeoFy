import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Client ID de la app registrada en el Spotify Developer Dashboard.
///
/// En un flujo PKCE el Client ID **no es secreto**: está diseñado para vivir
/// dentro de clientes públicos, así que va compilado. Se puede sobrescribir
/// desde `config.json` sin recompilar.
///
/// Va **vacío en el repositorio a propósito**. En Modo Desarrollo, una app de
/// Spotify solo funciona para los 25 usuarios que su dueño da de alta a mano,
/// así que un Client ID publicado no le sirve a nadie más que a su dueño — y en
/// cambio deja que cualquiera le agote la cuota. Cada usuario crea el suyo y lo
/// pone en `config.json`; la pantalla de inicio explica cómo.
const String kDefaultClientId = '';

/// ¿Hay Client ID configurado? Sin él no se puede ni empezar el login.
bool get hayClientId => kDefaultClientId.isNotEmpty;

/// Versión de NeoFy.
///
/// ⚠️ **Esta constante es la única fuente de la verdad.** `build_installer.ps1`
/// la lee de aquí y se la pasa a Inno Setup, así que el instalador y el
/// actualizador no pueden desincronizarse: subir la versión es tocar esta línea
/// y nada más.
const String kVersion = '0.2.9';

/// Repositorio de donde salen las actualizaciones.
const String kRepoGitHub = 'KOLPSE/NeoFy';

/// Puerto del servidor de loopback que recibe el callback de OAuth.
///
/// Tiene que coincidir **carácter por carácter** con el Redirect URI dado de
/// alta en el Dashboard: `http://127.0.0.1:8898/callback`. Ojo: Spotify ya no
/// acepta `localhost`, solo la IP de loopback literal.
const int kRedirectPort = 8898;

/// Puerto para el login OAuth *de librespot*, que es un flujo aparte del
/// nuestro (usa el client_id del cliente de escritorio de Spotify, no el
/// nuestro, y por eso los tokens no son intercambiables).
const int kLibrespotOAuthPort = 8899;

/// Nombre con el que aparece este equipo en la lista de dispositivos de
/// Spotify Connect. Es también la clave para localizar nuestro `device_id`.
const String kDeviceName = 'NeoFy';

/// Permisos que pedimos en el consentimiento.
///
/// `user-library-read` hace falta para "Canciones que te gustan", que no es una
/// playlist y no sale en `/me/playlists`; `user-library-modify`, para el botón
/// del corazón de cada fila.
///
/// ⚠️ Añadir un scope a esta lista obliga a **volver a pasar por el
/// consentimiento**: renovar un refresh token no le añade permisos nuevos. Cada
/// pantalla comprueba con `auth.hasScope` el permiso que necesita, para que un
/// scope nuevo no bloquee de golpe lo que ya funcionaba.
const List<String> kScopes = [
  'user-read-private',
  'user-read-playback-state',
  'user-modify-playback-state',
  'user-read-currently-playing',
  'playlist-read-private',
  'playlist-read-collaborative',
  'playlist-modify-private',
  'playlist-modify-public',
  'user-library-read',
  'user-library-modify',
  'user-top-read',
  'user-read-recently-played',
];

/// Permiso para guardar y quitar favoritos. Se nombra aparte porque hay que
/// comprobarlo por su cuenta: es el último en llegar y las sesiones anteriores
/// no lo tienen.
const String kScopeLibraryModify = 'user-library-modify';

/// Permiso para leer la biblioteca guardada.
const String kScopeLibraryRead = 'user-library-read';

/// Permisos de la portada. Comprobado con `tool/probe_home.dart`: los endpoints
/// de "hecho para ti" de Spotify (`/browse/*`) dan 403 en Modo Desarrollo y
/// `/recommendations` está retirado, pero estos dos siguen vivos y solo piden
/// su permiso.
const String kScopeTopRead = 'user-top-read';
const String kScopeRecentlyPlayed = 'user-read-recently-played';

/// Dónde viven los datos que **no se pueden perder**: `config.json`, el refresh
/// token y las credenciales de librespot.
///
/// - Windows: `%APPDATA%\neofy`.
/// - Linux: `$XDG_CONFIG_HOME/neofy`, o `~/.config/neofy` si no está definida.
///
/// Se lee del entorno en vez de usar `path_provider` para ahorrarnos un plugin
/// nativo entero — en Windows `APPDATA` siempre está definido, y en Linux la
/// especificación XDG obliga a que `HOME` lo esté.
Directory appDataDir() {
  final base = Platform.isWindows
      ? Platform.environment['APPDATA']
      : _xdg('XDG_CONFIG_HOME', '.config');
  final dir = Directory(p.join(base ?? Directory.systemTemp.path, 'neofy'));
  if (!dir.existsSync()) {
    _migrarDesdeElNombreViejo(dir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
  }
  return dir;
}

/// Dónde va lo que se puede tirar sin consecuencias: las carátulas y la caché
/// de audio de librespot.
///
/// - Windows: la misma carpeta que [appDataDir], **a propósito**. Separarlas
///   obligaría a migrar la caché de quien ya tiene la app instalada, y a cambio
///   de nada: Windows no distingue entre datos y caché.
/// - Linux: `$XDG_CACHE_HOME/neofy`, o `~/.cache/neofy`. Ahí sí importa —
///   meter cientos de megas de carátulas en `~/.config` está mal, y hay
///   herramientas que dan por hecho que `~/.cache` se puede borrar entero.
Directory cacheDir() {
  if (Platform.isWindows) return appDataDir();
  final base = _xdg('XDG_CACHE_HOME', '.cache') ?? Directory.systemTemp.path;
  final dir = Directory(p.join(base, 'neofy'));
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}

/// Una ruta base de XDG: la variable si está definida y es absoluta, y si no el
/// respaldo bajo `$HOME`.
///
/// La especificación es explícita en que un valor relativo hay que ignorarlo,
/// no interpretarlo desde el directorio actual.
String? _xdg(String variable, String respaldo) {
  final valor = Platform.environment[variable];
  if (valor != null && valor.isNotEmpty && p.isAbsolute(valor)) return valor;
  final home = Platform.environment['HOME'];
  return home == null || home.isEmpty ? null : p.join(home, respaldo);
}

/// La app se llamaba "spotify-native" y sus datos vivían en otra carpeta.
///
/// Ahí están el refresh token, las credenciales de librespot y la caché de
/// carátulas: perderlos significaría **dos logins otra vez** por un simple
/// cambio de nombre. Se mueve la carpeta entera la primera vez y no se vuelve a
/// tocar el asunto.
///
/// Solo aplica a Windows: es historia de una instalación que en Linux no ha
/// existido nunca, porque el port es posterior al cambio de nombre.
void _migrarDesdeElNombreViejo(Directory nueva) {
  if (!Platform.isWindows) return;
  try {
    final vieja = Directory(p.join(nueva.parent.path, 'spotify-native'));
    if (!vieja.existsSync()) return;
    vieja.renameSync(nueva.path);
  } catch (_) {
    // Si el renombrado falla (carpeta en uso, permisos), no se rompe nada: se
    // empieza de cero y como mucho toca volver a iniciar sesión.
  }
}

/// Preferencias persistidas en `config.json`, dentro de [appDataDir].
class AppConfig {
  String clientId;
  int initialVolume;
  int bitrate;

  /// Modo rendimiento: sacrifica las carátulas para bajar la memoria. Ver
  /// `core/settings.dart`.
  bool performanceMode;

  /// Volumen de NeoTube, 0..100.
  ///
  /// Aparte de [initialVolume] porque son dos reproductores distintos: aquel
  /// se le pasa a librespot al arrancar y lo acaba mandando Spotify Connect;
  /// este lo aplica `media_kit` en este mismo proceso. Compartir el campo
  /// haría que bajar el volumen en un modo bajara el del otro.
  int volumenNeoTube;

  /// Modo activo: `'neofy'` o `'neotube'`. Se guarda como cadena y no como el
  /// `enum AppMode` porque este fichero no depende de `core/app_mode.dart` —
  /// `AppMode.fromNombre`/`.nombre` hacen la conversión en el lado de
  /// `Settings`.
  String modo;

  AppConfig({
    this.clientId = kDefaultClientId,
    this.initialVolume = 60,
    this.bitrate = 320,
    this.performanceMode = false,
    this.volumenNeoTube = 60,
    this.modo = 'neofy',
  });

  static File get _file => File(p.join(appDataDir().path, 'config.json'));

  static Future<AppConfig> load() async {
    try {
      final f = _file;
      if (!await f.exists()) return AppConfig();
      final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return AppConfig(
        clientId: (map['clientId'] as String?) ?? kDefaultClientId,
        initialVolume: (map['initialVolume'] as int?) ?? 60,
        bitrate: (map['bitrate'] as int?) ?? 320,
        performanceMode: (map['performanceMode'] as bool?) ?? false,
        volumenNeoTube: (map['volumenNeoTube'] as int?) ?? 60,
        modo: (map['modo'] as String?) ?? 'neofy',
      );
    } catch (_) {
      // Un config corrupto no debe impedir arrancar: se vuelve a los valores
      // por defecto y se reescribirá en el próximo save().
      return AppConfig();
    }
  }

  Future<void> save() async {
    await _file.writeAsString(jsonEncode({
      'clientId': clientId,
      'initialVolume': initialVolume,
      'bitrate': bitrate,
      'performanceMode': performanceMode,
      'volumenNeoTube': volumenNeoTube,
      'modo': modo,
    }));
  }
}
