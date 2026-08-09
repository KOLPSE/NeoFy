import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';
// `WebviewCookie` es parte de la API pública (`Webview.getAllCookies()` la
// devuelve) pero el paquete no la reexporta desde su barrel — sin este
// import directo a `src/` ni siquiera se puede nombrar el tipo del valor que
// el propio paquete obliga a manejar.
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

/// Sesión de NeoTube capturada de una WebView de verdad — no OAuth.
///
/// Decisión tomada con el usuario tras ver el coste de la alternativa: la
/// única forma de que sea "solo te logeas y ya" (como en Metrolist/
/// InnerTune, y como pide el usuario) es dejar que el propio Google pinte su
/// pantalla de login en una ventana de verdad y quedarse con las cookies de
/// la sesión resultante — un registro de app en Google Cloud (lo que se
/// intentó primero) es más "nativo" en el sentido de no traer un motor de
/// navegador, pero no es "solo logearse": exige que cada usuario configure
/// su propio proyecto antes de poder entrar.
///
/// La WebView (`desktop_webview_window`, WebView2 en Windows / WebKitGTK en
/// Linux) se usa **solo para esta pantalla**: el resto de NeoTube sigue
/// siendo Flutter nativo, tal como se pidió. Una vez capturada la sesión no
/// vuelve a abrirse ninguna ventana de navegador para nada.
///
/// La API interna de YouTube Music, en su variante de cookies, autentica con
/// la cabecera `Cookie` de la sesión más una firma `SAPISIDHASH` calculada a
/// partir de la cookie `SAPISID` (o su equivalente moderno
/// `__Secure-3PAPISID`) — es el mismo mecanismo que usa el propio
/// `music.youtube.com` en el navegador, y el que reutilizan `ytmusicapi`/
/// InnerTune cuando no usan OAuth.
class YtAuth {
  List<WebviewCookie> _cookies = [];

  bool get isLoggedIn => _sapisid != null;

  /// Los nombres con los que Google manda la cookie que firma las peticiones,
  /// **por orden de preferencia**.
  ///
  /// ⚠️ `APISID` a secas **no está en la lista y no puede estarlo**: es una
  /// cookie distinta de `SAPISID`, con otro valor, y aquí estuvo escondido el
  /// fallo de "estoy logueado pero no salen mis playlists".
  ///
  /// Esto se buscaba antes por sufijo (`name.endsWith('APISID')`) para tolerar
  /// las variantes `__Secure-*`. Pero `APISID` **también** acaba en `APISID`, y
  /// llega antes que `SAPISID` en la lista que devuelve la WebView: se firmaba
  /// con el valor equivocado. Lo peor es cómo falla — Google no contesta 401 ni
  /// 403: contesta **200 con la sesión anónima**, así que la portada llegaba
  /// llena (de recomendaciones genéricas) y la biblioteca llegaba con un
  /// mensaje de "Inicia sesión para escuchar tus canciones favoritas" en vez de
  /// con las listas del usuario. Todo parecía funcionar salvo lo único que
  /// depende de saber quién eres.
  ///
  /// Verificado con `tool/probe_yt.dart` contra la cuenta real: firmando con
  /// `APISID`, `FEmusic_liked_playlists` devuelve el mensaje de "inicia
  /// sesión"; firmando con `SAPISID`, devuelve las playlists.
  static const _nombresDeFirma = ['SAPISID', '__Secure-3PAPISID', '__Secure-1PAPISID'];

  String? get _sapisid {
    for (final nombre in _nombresDeFirma) {
      for (final c in _cookies) {
        if (c.name == nombre && c.value.isNotEmpty) return c.value;
      }
    }
    return null;
  }

  /// ¿Traen estas cookies con qué firmar? Es lo que decide que el login ha
  /// terminado de verdad, y por eso mira exactamente lo mismo que [_sapisid]:
  /// darlo por bueno con una cookie que luego no sirve para firmar es
  /// justamente cómo se llegaba a una sesión que parecía iniciada y no lo
  /// estaba.
  static bool _sirvenParaFirmar(List<WebviewCookie> cookies) => cookies
      .any((c) => _nombresDeFirma.contains(c.name) && c.value.isNotEmpty);

  /// Se queda solo con las cookies de `.youtube.com` (o subdominios como
  /// `music.youtube.com`) y descarta las de `.google.com`/
  /// `accounts.google.com` de por medio del login.
  ///
  /// `getAllCookies()` de esta WebView devuelve **toda** la sesión de golpe
  /// — Google, cuentas, YouTube, todo mezclado — con el mismo nombre de
  /// cookie repetido varias veces para dominios distintos (`SAPISID` de
  /// `.google.com` y otro `SAPISID` de `.youtube.com`, cada uno con su
  /// propio valor). InnerTune no tiene este problema porque
  /// `CookieManager.getCookie(url)` de Android ya devuelve la cookie
  /// acotada a la URL que le pasas; aquí hay que acotarla a mano, o la
  /// cabecera `Cookie:` sale con el mismo nombre repetido dos veces —
  /// **eso** es lo que probablemente estaba provocando el "400: solicitud
  /// mal formada".
  ///
  /// También limpia nombre **y valor**: la implementación de Windows de
  /// `getAllCookies()` los devuelve con un `\0` de más pegado al final de
  /// los dos — con toda probabilidad de la conversión de cadena ancha de
  /// Windows a UTF-8 en el lado nativo (C++), que copia un carácter de más.
  /// Con el del nombre, ni `endsWith('APISID')` encajaba; con el del valor,
  /// el paquete `http` rechazaba la cabecera `Cookie:` entera con
  /// `FormatException: Invalid HTTP header field value` — así se vio de
  /// verdad, no solo se sospechó. Nombre y valor de cookie válidos
  /// (RFC 6265) son ASCII imprimible, así que basta con tirar cualquier
  /// cosa fuera de ese rango en los dos.
  static List<WebviewCookie> _paraYoutube(List<WebviewCookie> cookies) {
    final vistas = <String>{};
    final resultado = <WebviewCookie>[];
    for (final c in cookies) {
      if (!c.domain.contains('youtube.com')) continue;
      final basura = RegExp(r'[^\x21-\x7E]');
      final nombre = c.name.replaceAll(basura, '');
      final valor = c.value.replaceAll(basura, '');
      if (!vistas.add(nombre)) continue; // ya hay una de este nombre
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

  /// Cabecera `Cookie:` completa para las peticiones a la API interna.
  String cookieHeader() => _cookies.map((c) => '${c.name}=${c.value}').join('; ');

  /// Firma `SAPISIDHASH` que exige la API cuando se autentica por cookies:
  /// `sha1("$epoch $sapisid $origin")`, con el mismo epoch como prefijo del
  /// valor de la cabecera `Authorization`.
  String authorizationHeader({String origin = 'https://music.youtube.com'}) {
    final sapisid = _sapisid;
    if (sapisid == null) throw YtAuthException('No hay sesión de NeoTube iniciada.');
    final epoch = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final hash = sha1.convert(utf8.encode('$epoch $sapisid $origin')).toString();
    return 'SAPISIDHASH ${epoch}_$hash';
  }

  /// Abre la ventana de login de Google de verdad y espera a que la
  /// navegación llegue a `music.youtube.com` (igual que InnerTune), momento
  /// en el que captura y filtra las cookies y se cierra sola.
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
    // Mismo punto de entrada que usa InnerTune (`ltmpl=music&service=youtube`
    // con el `continue` apuntando al signin de YouTube, que a su vez acaba en
    // music.youtube.com): entrar ya por accounts.google.com con esta forma
    // exacta evita que sea YouTube quien construya la redirección al login
    // por su cuenta, que es donde salía el "400: solicitud mal formada".
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

    // Igual que InnerTune: el login se da por bueno cuando la navegación
    // llega a music.youtube.com, no sondeando cookies a ciegas — esa fue la
    // pieza que faltaba, sondear solo decía si Google ya había puesto la
    // cookie, no si el usuario había terminado de verdad.
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
