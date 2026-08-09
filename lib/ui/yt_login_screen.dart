import 'package:flutter/material.dart';

import '../core/yt_auth.dart';

/// Login de NeoTube: "solo te logeas y ya", como en Metrolist/InnerTune.
///
/// Por dentro abre una ventana de WebView de verdad (`YtAuth.login()`) donde
/// Google pinta su propia pantalla de inicio de sesión — nada dibujado a
/// mano, nada de cookies pegadas por el usuario. Es la única pantalla de
/// toda la app que usa un motor de navegador; el resto de NeoTube sigue
/// siendo Flutter nativo.
class YtLoginScreen extends StatefulWidget {
  const YtLoginScreen({super.key, required this.auth, required this.onLoggedIn});

  final YtAuth auth;
  final Future<void> Function() onLoggedIn;

  @override
  State<YtLoginScreen> createState() => _YtLoginScreenState();
}

class _YtLoginScreenState extends State<YtLoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.login();
      await widget.onLoggedIn();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.play_circle, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 20),
              Text('NeoTube', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'YouTube Music sin necesitar cuenta Premium. Solo hace falta '
                'iniciar sesión con Google.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _login,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.login),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_busy ? 'Esperando el login…' : 'Conectar con Google'),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                SelectableText(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
