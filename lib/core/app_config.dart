import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'idiomas_spotify.dart';

const String kDefaultClientId = '';

const String kDiscordClientId = '1537557680024199198';

const String kVersion = '1.6.0.301';

const String kHostActualizaciones = 'git.neogex.xyz';

const String kProyectoActualizaciones = 'apps/neofy';

const String kProyectoActualizacionesPreview = 'apps/neofy-preview';

const String kUrlRepositorio =
    'https://$kHostActualizaciones/$kProyectoActualizaciones';

enum CanalActualizacion {
  estable,
  preview;

  String get valor => name;

  String get proyecto => switch (this) {
        CanalActualizacion.estable => kProyectoActualizaciones,
        CanalActualizacion.preview => kProyectoActualizacionesPreview,
      };

  static CanalActualizacion desdeValor(
    String? valor, {
    CanalActualizacion? respaldo,
  }) {
    if (valor == preview.valor) return preview;
    if (valor == estable.valor) return estable;
    return respaldo ?? canalDeVersion(kVersion);
  }
}

final RegExp kRegexVersionEstable = RegExp(r'^\d+\.\d+\.\d+$');
final RegExp kRegexVersionPreview = RegExp(r'^\d+\.\d+\.\d+\.\d{3}$');
final RegExp kRegexVersionValida = RegExp(r'^\d+\.\d+\.\d+(?:\.\d{3})?$');

bool esVersionPreview(String version) => kRegexVersionPreview.hasMatch(version);

CanalActualizacion canalDeVersion(String version) =>
    esVersionPreview(version) ? CanalActualizacion.preview : CanalActualizacion.estable;

bool get kEsCompilacionPreview => esVersionPreview(kVersion);

String nombreVentanaNeoFy({required bool preview, bool debug = false}) {
  final base = preview ? 'NeoFy (PREVIEW)' : 'NeoFy';
  return debug ? '$base (debug)' : base;
}

const int kRedirectPort = 8898;

const int kLibrespotOAuthPort = 8899;

const String kDeviceName = 'NeoFy';

const String kIdTemaNocturno = 'neofy-nocturno';

const String kIdTemaClaro = 'neofy-claro';

const String kTemaPorDefecto = kIdTemaNocturno;

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

const String kScopeLibraryModify = 'user-library-modify';

const String kScopePlaylistModify = 'playlist-modify-private';

const String kScopeLibraryRead = 'user-library-read';

const String kScopeTopRead = 'user-top-read';
const String kScopeRecentlyPlayed = 'user-read-recently-played';

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

Directory cacheDir() {
  if (Platform.isWindows) return appDataDir();
  final base = _xdg('XDG_CACHE_HOME', '.cache') ?? Directory.systemTemp.path;
  final dir = Directory(p.join(base, 'neofy'));
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}

String? _xdg(String variable, String respaldo) {
  final valor = Platform.environment[variable];
  if (valor != null && valor.isNotEmpty && p.isAbsolute(valor)) return valor;
  final home = Platform.environment['HOME'];
  return home == null || home.isEmpty ? null : p.join(home, respaldo);
}

void _migrarDesdeElNombreViejo(Directory nueva) {
  if (!Platform.isWindows) return;
  try {
    final vieja = Directory(p.join(nueva.parent.path, 'spotify-native'));
    if (!vieja.existsSync()) return;
    vieja.renameSync(nueva.path);
  } catch (_) {}
}

const kLimiteDesfaseLetraMs = 5000;

class AppConfig {
  String clientId;
  int initialVolume;
  int bitrate;

  bool performanceMode;

  int volumenNeoTube;

  bool discordRpcEnabled;

  String discordClientId;

  String tema;
  bool temaElegido;

  /// Vacío = sigue el idioma del PC. Formato Spotify: `es_ES`, `en_US`…
  String idiomaPreferido;

  /// Colores propios para los temas de Material: id del tema → clave de la
  /// paleta ('primario', 'fondo', 'panel') → color '#RRGGBB'.
  Map<String, Map<String, String>> temaColores;
  final Map<String, int> desfasesLetraMs;
  bool modoLetraPorPalabras;
  bool sincronizacionPorVoz;

  /// Los menús se abren ocupando el rectángulo del elemento en vez de
  /// flotar encima (estilo Material Expressive).
  bool menusEnElemento;

  /// La barra lateral se muestra como rail de iconos en vez de panel ancho.
  bool sidebarPlegado;

  /// El panel derecho de Reproducción Actual se muestra plegado en el borde.
  bool sidebarDerechoPlegado;

  /// Rama de actualizaciones preferida (`estable` o `preview`).
  CanalActualizacion canalActualizacion;

  AppConfig({
    this.clientId = kDefaultClientId,
    this.initialVolume = 60,
    this.bitrate = 320,
    this.performanceMode = false,
    this.volumenNeoTube = 60,
    this.discordRpcEnabled = false,
    this.discordClientId = kDiscordClientId,
    this.tema = kTemaPorDefecto,
    this.temaElegido = false,
    this.idiomaPreferido = kIdiomaSistema,
    Map<String, Map<String, String>>? temaColores,
    Map<String, int>? desfasesLetraMs,
    this.modoLetraPorPalabras = false,
    this.sincronizacionPorVoz = false,
    this.menusEnElemento = true,
    this.sidebarPlegado = false,
    this.sidebarDerechoPlegado = false,
    CanalActualizacion? canalActualizacion,
  }) : temaColores = temaColores ?? {},
       desfasesLetraMs = desfasesLetraMs ?? {},
       canalActualizacion = canalActualizacion ?? canalDeVersion(kVersion);

  static File get _file => File(p.join(appDataDir().path, 'config.json'));

  static Future<AppConfig> load() async {
    try {
      final f = _file;
      if (!await f.exists()) return AppConfig();
      final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final temaGuardado = map['tema'] as String?;
      final temaElegido = map['temaElegido'] == true;
      final materialPersonalizado =
          (map['temaColores'] as Map?)?['material-oscuro'] is Map &&
          ((map['temaColores'] as Map)['material-oscuro'] as Map).isNotEmpty;
      return AppConfig(
        clientId: (map['clientId'] as String?) ?? kDefaultClientId,
        initialVolume: (map['initialVolume'] as int?) ?? 60,
        bitrate: (map['bitrate'] as int?) ?? 320,
        performanceMode: (map['performanceMode'] as bool?) ?? false,
        volumenNeoTube: (map['volumenNeoTube'] as int?) ?? 60,
        discordRpcEnabled: (map['discordRpcEnabled'] as bool?) ?? false,
        discordClientId:
            (map['discordClientId'] as String?) ?? kDiscordClientId,
        tema:
            temaGuardado == 'material-oscuro' &&
                !temaElegido &&
                !materialPersonalizado
            ? kTemaPorDefecto
            : temaGuardado ?? kTemaPorDefecto,
        temaElegido: temaElegido,
        idiomaPreferido: (map['idiomaPreferido'] as String?) ?? kIdiomaSistema,
        temaColores: {
          for (final entrada
              in ((map['temaColores'] as Map?) ?? const {}).entries)
            entrada.key.toString(): {
              for (final color in (entrada.value as Map).entries)
                color.key.toString(): color.value.toString(),
            },
        },
        menusEnElemento: (map['menusEnElemento'] as bool?) ?? true,
        sidebarPlegado: (map['sidebarPlegado'] as bool?) ?? false,
        sidebarDerechoPlegado: (map['sidebarDerechoPlegado'] as bool?) ?? false,
        canalActualizacion: CanalActualizacion.desdeValor(
          map['canalActualizacion'] as String?,
        ),
        modoLetraPorPalabras: (map['modoLetraPorPalabras'] as bool?) ?? false,
        sincronizacionPorVoz: (map['sincronizacionPorVoz'] as bool?) ?? false,
        desfasesLetraMs: {
          if (map['desfasesLetraMs'] case Map<String, dynamic> desfases)
            for (final entrada in desfases.entries)
              if (entrada.value case int ms when ms != 0)
                entrada.key: ms.clamp(
                  -kLimiteDesfaseLetraMs,
                  kLimiteDesfaseLetraMs,
                ),
        },
      );
    } catch (_) {
      return AppConfig();
    }
  }

  Future<void> save() async {
    await _file.writeAsString(
      jsonEncode({
        'clientId': clientId,
        'initialVolume': initialVolume,
        'bitrate': bitrate,
        'performanceMode': performanceMode,
        'volumenNeoTube': volumenNeoTube,
        'discordRpcEnabled': discordRpcEnabled,
        'discordClientId': discordClientId,
        'tema': tema,
        'temaElegido': temaElegido,
        'idiomaPreferido': idiomaPreferido,
        if (temaColores.isNotEmpty) 'temaColores': temaColores,
        if (desfasesLetraMs.isNotEmpty) 'desfasesLetraMs': desfasesLetraMs,
        'modoLetraPorPalabras': modoLetraPorPalabras,
        'sincronizacionPorVoz': sincronizacionPorVoz,
        'menusEnElemento': menusEnElemento,
        'sidebarPlegado': sidebarPlegado,
        'sidebarDerechoPlegado': sidebarDerechoPlegado,
        'canalActualizacion': canalActualizacion.valor,
      }),
    );
  }
}
