import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const String kDefaultClientId = '';

bool get hayClientId => kDefaultClientId.isNotEmpty;

const String kDiscordClientId = '1537557680024199198';

const String kVersion = '0.3.6';

const String kRepoGitHub = 'KOLPSE/NeoFy';

const int kRedirectPort = 8898;

const int kLibrespotOAuthPort = 8899;

const String kDeviceName = 'NeoFy';

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
  } catch (_) {
  }
}

class AppConfig {
  String clientId;
  int initialVolume;
  int bitrate;

  bool performanceMode;

  int volumenNeoTube;

  bool discordRpcEnabled;

  String discordClientId;

  AppConfig({
    this.clientId = kDefaultClientId,
    this.initialVolume = 60,
    this.bitrate = 320,
    this.performanceMode = false,
    this.volumenNeoTube = 60,
    this.discordRpcEnabled = false,
    this.discordClientId = kDiscordClientId,
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
        discordRpcEnabled: (map['discordRpcEnabled'] as bool?) ?? false,
        discordClientId: (map['discordClientId'] as String?) ?? kDiscordClientId,
      );
    } catch (_) {
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
      'discordRpcEnabled': discordRpcEnabled,
      'discordClientId': discordClientId,
    }));
  }
}
