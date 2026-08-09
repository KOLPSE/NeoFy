import 'dart:async';

import 'package:flutter/material.dart';

import '../core/yt_player.dart';

/// El bloque de Ajustes propio de NeoTube: el estado del descodificador.
///
/// Es el equivalente de "Reiniciar audio" en NeoFy — los dos contestan a la
/// misma pregunta ("¿por qué no suena nada?") — pero por motivos distintos:
/// allí el audio lo saca librespot, un proceso aparte que se puede quedar
/// mudo; aquí lo saca `media_kit` en este mismo proceso y lo único que puede
/// faltar es **yt-dlp**, que es quien resuelve la URL del stream de cada pista.
///
/// Merece un sitio en Ajustes porque sin él NeoTube no reproduce **nada** y el
/// error solo se ve al pulsar una canción, una por una. Y porque un binario
/// presente pero roto se ve igual que uno bueno hasta que lo ejecutas: de ahí
/// que se compruebe la versión de verdad y no solo que el fichero exista.
class EstadoDeYtDlp extends StatefulWidget {
  const EstadoDeYtDlp({super.key});

  @override
  State<EstadoDeYtDlp> createState() => _EstadoDeYtDlpState();
}

class _EstadoDeYtDlpState extends State<EstadoDeYtDlp> {
  bool _comprobando = true;
  String? _version;
  String? _ruta;

  @override
  void initState() {
    super.initState();
    unawaited(_comprobar());
  }

  Future<void> _comprobar() async {
    setState(() => _comprobando = true);
    final ruta = YtPlayer.findYtDlpBinary()?.path;
    final version = await YtPlayer.versionDeYtDlp();
    if (!mounted) return;
    setState(() {
      _ruta = ruta;
      _version = version;
      _comprobando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (mensaje, color) = switch ((_comprobando, _ruta, _version)) {
      (true, _, _) => ('Comprobando…', theme.colorScheme.onSurfaceVariant),
      (_, null, _) => (
          'No se encuentra. NeoTube no puede reproducir sin él: ejecuta '
              'tool/fetch_ytdlp.ps1 (o .sh en Linux).',
          theme.colorScheme.error,
        ),
      (_, _, null) => (
          'Está en el disco pero no responde; puede estar a medio descargar o '
              'bloqueado por el antivirus.',
          theme.colorScheme.error,
        ),
      (_, _, final v) => ('Versión $v', theme.colorScheme.onSurfaceVariant),
    };

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Descodificador (yt-dlp)', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 2),
              Text(mensaje, style: theme.textTheme.bodySmall?.copyWith(color: color)),
              if (_ruta != null && !_comprobando) ...[
                const SizedBox(height: 2),
                Text(
                  _ruta!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: _comprobando ? null : () => unawaited(_comprobar()),
          child: const Text('Comprobar'),
        ),
      ],
    );
  }
}
