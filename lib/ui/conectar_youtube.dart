import 'package:flutter/material.dart';

import '../core/yt_auth.dart';

class ConectarYouTubeMusic extends StatefulWidget {
  const ConectarYouTubeMusic({
    super.key,
    required this.auth,
    this.onLoggedIn,
  });

  final YtAuth auth;

  final Future<void> Function()? onLoggedIn;

  @override
  State<ConectarYouTubeMusic> createState() => _ConectarYouTubeMusicState();
}

class _ConectarYouTubeMusicState extends State<ConectarYouTubeMusic> {
  bool _busy = false;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.login();
      await widget.onLoggedIn?.call();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conectado = widget.auth.isLoggedIn;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.play_circle,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text('¿Sin Premium?', style: theme.textTheme.bodyMedium),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          conectado
              ? 'YouTube Music está conectado. Si tu cuenta de Spotify no es '
                  'Premium, la música sonará desde aquí.'
              : 'La API de Spotify exige Premium para controlar la '
                  'reproducción, pero NeoFy puede sonar igual: conecta YouTube '
                  'Music y de ahí saldrá el audio. Las listas, la biblioteca y '
                  'las carátulas siguen siendo las de tu cuenta de Spotify.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _login,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(conectado ? Icons.refresh : Icons.play_circle_outline),
            label: Text(switch ((_busy, conectado)) {
              (true, _) => 'Esperando el login…',
              (false, true) => 'Volver a conectar YouTube Music',
              (false, false) => 'Conectar YouTube Music',
            }),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          SelectableText(
            _error!,
            style:
                theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
          ),
        ],
      ],
    );
  }
}
