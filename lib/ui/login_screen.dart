import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart';
import '../core/auth.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.auth,
    required this.config,
    required this.onLoggedIn,
  });

  final SpotifyAuth auth;
  final AppConfig config;
  final Future<void> Function() onLoggedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _error;

  final _clientIdCtrl = TextEditingController();
  String? _errorClientId;
  bool _guardando = false;

  @override
  void dispose() {
    _clientIdCtrl.dispose();
    super.dispose();
  }

  /// Guarda el Client ID y deja la app lista para el login.
  ///
  /// Se valida la forma antes de guardar: un Client ID de Spotify son 32
  /// caracteres hexadecimales. Sin esta comprobación, pegar mal el valor —o
  /// pegar el Client *Secret* por error, que es igual de largo pero no vale—
  /// se manifestaría como un error críptico de Spotify a mitad del login.
  Future<void> _guardarClientId() async {
    final valor = _clientIdCtrl.text.trim();
    if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(valor)) {
      setState(() => _errorClientId =
          'Un Client ID son 32 caracteres hexadecimales. Revisa que lo hayas '
          'copiado entero y que no sea el Client Secret.');
      return;
    }
    setState(() {
      _errorClientId = null;
      _guardando = true;
    });
    widget.config.clientId = valor;
    await widget.config.save();
    if (mounted) setState(() => _guardando = false);
  }

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

  /// Redirect URI que hay que dar de alta, palabra por palabra.
  static const _redirect = 'http://127.0.0.1:$kRedirectPort/callback';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Sin Client ID no hay nada que intentar: primero hay que crear una app en
    // el panel de Spotify. Le pasa a todo el que clona el repositorio.
    if (widget.config.clientId.isEmpty) return _primerosPasos(theme);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.graphic_eq, size: 56, color: theme.colorScheme.primary),
                const SizedBox(height: 20),
                Text('NeoFy', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Un cliente ligero que reproduce en local y se controla con la '
                  'API oficial de Spotify. Necesita una cuenta Premium.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                // Conviene decirlo antes y no que parezca un fallo: el primer
                // arranque abre el navegador dos veces porque son dos flujos
                // OAuth distintos y sus tokens no son intercambiables.
                Card(
                  color: theme.colorScheme.surfaceContainerHighest,
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            size: 18, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'La primera vez se abrirá el navegador dos veces: una para '
                            'la app y otra para el reproductor. Después queda guardado '
                            'y no se vuelve a pedir.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
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
                      child: Text(_busy ? 'Esperando al navegador…' : 'Iniciar sesión con Spotify'),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  SelectableText(
                    _error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Qué hacer la primera vez. No se puede evitar este paso: en Modo Desarrollo
  /// una app de Spotify solo vale para los 25 usuarios que su dueño da de alta,
  /// así que **cada uno necesita la suya**.
  Widget _primerosPasos(ThemeData theme) {
    Widget paso(int n, String titulo, Widget contenido) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text('$n',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 6),
                    contenido,
                  ],
                ),
              ),
            ],
          ),
        );

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Configurar NeoFy', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Spotify solo deja que una app de terceros funcione para los '
                    'usuarios que su creador da de alta a mano, así que NeoFy no '
                    'puede traer una configurada: necesitas la tuya. Son dos '
                    'minutos y se hace una sola vez.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  paso(1, 'Crea una app en el panel de Spotify y marca «Web API».',
                      OutlinedButton.icon(
                        onPressed: () => launchUrl(
                          Uri.parse('https://developer.spotify.com/dashboard'),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('Abrir el panel'),
                      )),
                  paso(
                      2,
                      'Pon este Redirect URI, exactamente así. Spotify ya no '
                      'acepta «localhost», solo el 127.0.0.1 literal.',
                      Row(
                        children: [
                          Expanded(
                            child: SelectableText(_redirect,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(fontFamily: 'monospace')),
                          ),
                          IconButton(
                            tooltip: 'Copiar',
                            icon: const Icon(Icons.copy, size: 16),
                            onPressed: () => Clipboard.setData(
                                const ClipboardData(text: _redirect)),
                          ),
                        ],
                      )),
                  paso(
                      3,
                      'Copia el Client ID de tu app y pégalo aquí.',
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _clientIdCtrl,
                            autofocus: true,
                            decoration: InputDecoration(
                              hintText: '32 caracteres, letras y números',
                              isDense: true,
                              border: const OutlineInputBorder(),
                              errorText: _errorClientId,
                              // Pegar es lo que hará todo el mundo; el botón
                              // ahorra el atajo de teclado.
                              suffixIcon: IconButton(
                                tooltip: 'Pegar',
                                icon: const Icon(Icons.content_paste, size: 18),
                                onPressed: () async {
                                  final d = await Clipboard.getData('text/plain');
                                  final t = d?.text?.trim();
                                  if (t != null && t.isNotEmpty) {
                                    _clientIdCtrl.text = t;
                                  }
                                },
                              ),
                            ),
                            onSubmitted: (_) => _guardarClientId(),
                          ),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: _guardando ? null : _guardarClientId,
                            icon: _guardando
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.check, size: 18),
                            label: const Text('Guardar y continuar'),
                          ),
                        ],
                      )),
                  const Divider(height: 32),
                  Text(
                    'Hace falta una cuenta Spotify Premium: es la propia API la '
                    'que exige Premium para controlar la reproducción.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
