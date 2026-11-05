import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_config.dart';

/// Cliente de NeoReport. La identidad Discord se establece en el portal con
/// OAuth; nunca se acepta un UID aportado por el cliente.
class NeoReport {
  NeoReport({http.Client? cliente, String? clave, this.obtenerInstalacion})
    : _http = cliente ?? http.Client(),
      _clave = clave ?? _appKey;

  static const _base = 'https://report.neogex.xyz';
  static const _appKey = String.fromEnvironment('NEOREPORT_APP_KEY');
  static final _random = Random.secure();
  static const _storage = FlutterSecureStorage();
  static const _installationKey = 'neoreport_installation';
  final http.Client _http;
  final String _clave;
  final Future<Map<String, String>> Function()? obtenerInstalacion;
  String? _pendingPayload;
  String? _pendingKey;

  bool get disponible => _clave.startsWith('nr_neofy_');

  Future<Map<String, String>> _installation() async {
    final raw = await _storage.read(key: _installationKey);
    if (raw != null) {
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      final id = saved['installId'] as String?;
      final credential = saved['installationCredential'] as String?;
      if (id != null && credential != null) {
        return {'installId': id, 'installationCredential': credential};
      }
      throw Exception('La credencial de NeoReport no es válida.');
    }

    String randomToken(int bytes) => base64Url
        .encode(List<int>.generate(bytes, (_) => _random.nextInt(256)))
        .replaceAll('=', '');
    final result = {
      'installId': randomToken(16),
      'installationCredential': randomToken(32),
    };
    await _storage.write(key: _installationKey, value: jsonEncode(result));
    return result;
  }

  Future<Uri> enviar({
    required String title,
    required String body,
    required String category,
    required String? trackUri,
  }) async {
    if (!disponible) {
      throw Exception('NeoReport no está configurado en esta versión.');
    }
    final installation = await (obtenerInstalacion?.call() ?? _installation());
    final trackId = trackUri?.split(':').last;
    final payload = jsonEncode({
      ...installation,
      'title': title.trim(),
      'body': body.trim(),
      'category': category,
      'appVersion': kVersion,
      'os': Platform.operatingSystem,
      'meta': {
        'client': 'NeoFy',
        if (trackId != null && RegExp(r'^[A-Za-z0-9]+$').hasMatch(trackId))
          'trackUri': 'https://open.spotify.com/track/$trackId',
      },
    });
    if (_pendingPayload != payload) {
      _pendingPayload = payload;
      _pendingKey = base64Url
          .encode(List<int>.generate(18, (_) => _random.nextInt(256)))
          .replaceAll('=', '');
    }
    final response = await _http
        .post(
          Uri.parse('$_base/api/v1/ingest'),
          headers: {
            'Authorization': 'Bearer $_clave',
            'Content-Type': 'application/json',
            'Idempotency-Key': _pendingKey!,
          },
          body: payload,
        )
        .timeout(const Duration(seconds: 20));
    Map<String, dynamic> result;
    try {
      result = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception(
        'NeoReport respondió ${response.statusCode}. Inténtalo de nuevo más tarde.',
      );
    }
    if (response.statusCode != 201 && response.statusCode != 200) {
      final error = result['error'] as Map<String, dynamic>?;
      throw Exception(
        error?['message'] ?? 'NeoReport respondió ${response.statusCode}.',
      );
    }
    _pendingPayload = null;
    _pendingKey = null;
    var link = result['linkCodeUrl'] as String?;
    if (link == null && response.headers['idempotent-replay'] == 'true') {
      try {
        final recovery = await _http
            .post(
              Uri.parse('$_base/api/v1/link-code'),
              headers: {
                'Authorization': 'Bearer $_clave',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(installation),
            )
            .timeout(const Duration(seconds: 20));
        if (recovery.statusCode == 200 || recovery.statusCode == 201) {
          link =
              (jsonDecode(recovery.body) as Map<String, dynamic>)['linkCodeUrl']
                  as String?;
        }
      } catch (_) {
        // El reporte ya existe; conserva el enlace al reporte si falla la recuperación.
      }
    }
    return Uri.parse(link ?? result['linkUrl'] as String);
  }

  Future<void> abrir(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('No se pudo abrir el enlace de NeoReport.');
    }
  }
}
