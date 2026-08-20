import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'app_config.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

class SpotifyAuth {
  SpotifyAuth(this.config);

  final AppConfig config;
  final http.Client _http = http.Client();

  String? _accessToken;
  DateTime _expiresAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _refreshToken;
  Set<String> _grantedScopes = const {};

  bool get isLoggedIn => _refreshToken != null;

  bool get needsReauth =>
      isLoggedIn && !kScopes.every(_grantedScopes.contains);

  List<String> get missingScopes =>
      kScopes.where((s) => !_grantedScopes.contains(s)).toList();

  bool hasScope(String scope) => _grantedScopes.contains(scope);

  static File get _tokenFile => File(p.join(appDataDir().path, 'tokens.json'));

  Future<void> loadStored() async {
    try {
      final f = _tokenFile;
      if (!await f.exists()) return;
      final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _refreshToken = map['refresh_token'] as String?;
      final scopes = map['scope'] as String?;
      _grantedScopes = scopes == null ? const {} : scopes.split(' ').toSet();
    } catch (_) {
      _refreshToken = null;
      _grantedScopes = const {};
    }
  }

  Future<void> _persist() async {
    if (_refreshToken == null) return;
    await _tokenFile.writeAsString(jsonEncode({
      'refresh_token': _refreshToken,
      'scope': _grantedScopes.join(' '),
    }));
  }

  Future<void> logout() async {
    _accessToken = null;
    _refreshToken = null;
    _grantedScopes = const {};
    _expiresAt = DateTime.fromMillisecondsSinceEpoch(0);
    final f = _tokenFile;
    if (await f.exists()) await f.delete();
  }

  Future<String> accessToken() async {
    if (_accessToken != null &&
        DateTime.now().isBefore(_expiresAt.subtract(const Duration(seconds: 60)))) {
      return _accessToken!;
    }
    if (_refreshToken == null) {
      throw AuthException('No hay sesión iniciada.');
    }
    await _refresh();
    return _accessToken!;
  }

  Future<void> forceRefresh() async {
    if (_refreshToken == null) throw AuthException('No hay sesión iniciada.');
    await _refresh();
  }

  Future<void> _refresh() async {
    final res = await _http.post(
      Uri.parse('https://accounts.spotify.com/api/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': _refreshToken!,
        'client_id': config.clientId,
      },
    );
    if (res.statusCode != 200) {
      if (res.statusCode == 400) await logout();
      throw AuthException('No se pudo renovar la sesión (${res.statusCode}): ${res.body}');
    }
    _applyTokenResponse(jsonDecode(res.body) as Map<String, dynamic>);
    await _persist();
  }

  void _applyTokenResponse(Map<String, dynamic> body) {
    _accessToken = body['access_token'] as String;
    final expiresIn = (body['expires_in'] as num?)?.toInt() ?? 3600;
    _expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
    final newRefresh = body['refresh_token'] as String?;
    if (newRefresh != null) _refreshToken = newRefresh;
    final scope = body['scope'] as String?;
    if (scope != null) _grantedScopes = scope.split(' ').toSet();
  }

  Future<void> login() async {
    final verifier = _randomVerifier();
    final challenge = base64Url
        .encode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');
    final state = _randomVerifier().substring(0, 16);
    final redirectUri = 'http://127.0.0.1:$kRedirectPort/callback';

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, kRedirectPort);
    final completer = Completer<String>();

    unawaited(() async {
      await for (final req in server) {
        if (req.uri.path != '/callback') {
          req.response.statusCode = 404;
          await req.response.close();
          continue;
        }
        final error = req.uri.queryParameters['error'];
        final code = req.uri.queryParameters['code'];
        final gotState = req.uri.queryParameters['state'];

        final ok = error == null && code != null && gotState == state;
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write(_resultPage(ok, error));
        await req.response.close();

        if (completer.isCompleted) continue;
        if (error != null) {
          completer.completeError(AuthException('Spotify rechazó el login: $error'));
        } else if (gotState != state) {
          completer.completeError(AuthException('El parámetro state no coincide.'));
        } else if (code != null) {
          completer.complete(code);
        }
      }
    }());

    try {
      final authUrl = Uri.https('accounts.spotify.com', '/authorize', {
        'client_id': config.clientId,
        'response_type': 'code',
        'redirect_uri': redirectUri,
        'code_challenge_method': 'S256',
        'code_challenge': challenge,
        'state': state,
        'scope': kScopes.join(' '),
      });
      if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
        throw AuthException('No se pudo abrir el navegador.');
      }

      final code = await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => throw AuthException('Se agotó el tiempo esperando el login.'),
      );

      final res = await _http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': redirectUri,
          'client_id': config.clientId,
          'code_verifier': verifier,
        },
      );
      if (res.statusCode != 200) {
        throw AuthException(_explainTokenError(res.statusCode, res.body));
      }
      _applyTokenResponse(jsonDecode(res.body) as Map<String, dynamic>);
      await _persist();
    } finally {
      await server.close(force: true);
    }
  }

  String _explainTokenError(int status, String body) {
    if (body.contains('redirect_uri') || body.contains('INVALID_CLIENT')) {
      return 'Spotify rechazó el Redirect URI. Comprueba que en el Dashboard '
          '(Settings → Redirect URIs) está exactamente:\n\n'
          '  http://127.0.0.1:$kRedirectPort/callback\n\n'
          'Con 127.0.0.1 literal (no "localhost") y sin barra final.';
    }
    return 'No se pudo canjear el código ($status): $body';
  }

  String _randomVerifier() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rnd = Random.secure();
    return List.generate(64, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  String _resultPage(bool ok, String? error) {
    final title = ok ? 'Sesión iniciada' : 'Algo ha fallado';
    final msg = ok
        ? 'Ya puedes cerrar esta pestaña y volver a NeoFy.'
        : 'Spotify devolvió: ${error ?? "respuesta inesperada"}';
    return '''
<!doctype html><html lang="es"><head><meta charset="utf-8">
<title>$title</title>
<style>
  body{font-family:system-ui,-apple-system,Segoe UI,sans-serif;background:#121212;color:#fff;
       display:flex;align-items:center;justify-content:center;height:100vh;margin:0}
  .c{text-align:center;max-width:32rem;padding:2rem}
  h1{color:#1DB954;font-size:1.5rem;margin:0 0 .5rem}
  p{color:#b3b3b3;line-height:1.5}
</style></head>
<body><div class="c"><h1>$title</h1><p>$msg</p></div></body></html>''';
  }
}
