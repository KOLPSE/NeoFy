import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';
// ignore: implementation_imports
import 'package:desktop_webview_window/src/cookie.dart';
import 'package:path/path.dart' as p;

import 'app_config.dart';

class YtAuthException implements Exception {
  final String message;
  YtAuthException(this.message);
  @override
  String toString() => message;
}

class YtAuth {
  List<WebviewCookie> _cookies = [];

  bool get isLoggedIn => _sapisid != null;

  static const _nombresDeFirma = ['SAPISID', '__Secure-3PAPISID', '__Secure-1PAPISID'];

  String? get _sapisid {
    for (final nombre in _nombresDeFirma) {
      for (final c in _cookies) {
        if (c.name == nombre && c.value.isNotEmpty) return c.value;
      }
    }
    return null;
  }

  static bool _sirvenParaFirmar(List<WebviewCookie> cookies) => cookies
      .any((c) => _nombresDeFirma.contains(c.name) && c.value.isNotEmpty);

  static List<WebviewCookie> _paraYoutube(List<WebviewCookie> cookies) {
    final vistas = <String>{};
    final resultado = <WebviewCookie>[];
    for (final c in cookies) {
      if (!c.domain.contains('youtube.com')) continue;
      final basura = RegExp(r'[^\x21-\x7E]');
      final nombre = c.name.replaceAll(basura, '');
      final valor = c.value.replaceAll(basura, '');
      if (!vistas.add(nombre)) continue;
      resultado.add(nombre == c.name && valor == c.value
          ? c
          : WebviewCookie(
              name: nombre,
              value: valor,
              domain: c.domain,
              path: c.path,
              expires: c.expires,
              secure: c.secure,
              httpOnly: c.httpOnly,
              sessionOnly: c.sessionOnly,
            ));
    }
    return resultado;
  }

  static File get _cookieFile => File(p.join(appDataDir().path, 'yt_cookies.json'));

  Future<void> loadStored() async {
    try {
      final f = _cookieFile;
      if (!await f.exists()) return;
      final list = jsonDecode(await f.readAsString()) as List<dynamic>;
      _cookies = list
          .cast<Map<String, dynamic>>()
          .map(WebviewCookie.fromJson)
          .toList();
    } catch (_) {
      _cookies = [];
    }
  }

  Future<void> _persist() async {
    await _cookieFile.writeAsString(jsonEncode(_cookies.map((c) => c.toJson()).toList()));
  }

  Future<void> logout() async {
    _cookies = [];
    final f = _cookieFile;
    if (await f.exists()) await f.delete();
  }

  String cookieHeader() => _cookies.map((c) => '${c.name}=${c.value}').join('; ');

  String authorizationHeader({String origin = 'https://music.youtube.com'}) {
    final sapisid = _sapisid;
    if (sapisid == null) throw YtAuthException('No hay sesión de NeoTube iniciada.');
    final epoch = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final hash = sha1.convert(utf8.encode('$epoch $sapisid $origin')).toString();
    return 'SAPISIDHASH ${epoch}_$hash';
  }

  Future<void> login() async {
    if (!await WebviewWindow.isWebviewAvailable()) {
      throw YtAuthException(
          'No hay motor de WebView disponible (falta el WebView2 Runtime en Windows, '
          'o WebKitGTK en Linux).');
    }
    final webview = await WebviewWindow.create(
      configuration: const CreateConfiguration(
        title: 'Iniciar sesión en YouTube Music',
        windowWidth: 480,
        windowHeight: 700,
      ),
    );
    webview.launch(
      'https://accounts.google.com/ServiceLogin?ltmpl=music&service=youtube&passive=true'
      '&continue=https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue'
      '%26next%3Dhttps%253A%252F%252Fmusic.youtube.com%252F',
    );

    final completer = Completer<void>();
    unawaited(webview.onClose.then((_) {
      if (!completer.isCompleted) {
        completer.completeError(YtAuthException('Se cerró la ventana antes de iniciar sesión.'));
      }
    }));

    webview.setOnUrlRequestCallback((url) {
      if (!completer.isCompleted && url.startsWith('https://music.youtube.com')) {
        unawaited(() async {
          final cookies = _paraYoutube(await webview.getAllCookies());
          if (_sirvenParaFirmar(cookies)) {
            _cookies = cookies;
            await _persist();
            webview.close();
            if (!completer.isCompleted) completer.complete();
          }
        }());
      }
      return true;
    });

    await completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () => throw YtAuthException('Se agotó el tiempo esperando el login.'),
    );
  }
}
