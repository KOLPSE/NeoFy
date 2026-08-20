import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart';
import '../core/auth.dart';
import '../core/yt_auth.dart';
import 'conectar_youtube.dart';

String _resumen(String id) => id.length <= 12
    ? id
    : '${id.substring(0, 6)}…${id.substring(id.length - 4)}';

@visibleForTesting
String resumenDeClientId(String id) => _resumen(id);

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.auth,
    required this.config,
    required this.onLoggedIn,
    required this.ytAuth,
  });

  final SpotifyAuth auth;
  final AppConfig config;
  final Future<void> Function() onLoggedIn;

  final YtAuth ytAuth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _error;

  final _clientIdCtrl = TextEditingController();
  String? _errorClientId;
  bool _guardando = false;
  late bool _pasosAbiertos;

  static const _redirect = 'http://127.0.0.1:$kRedirectPort/callback';

  static const _panel = 'https://developer.spotify.com/dashboard';

  @override
  void initState() {
    super.initState();
    _clientIdCtrl.text = widget.config.clientId;
    _pasosAbiertos = widget.config.clientId.isEmpty;
  }

  @override
  void dispose() {
    _clientIdCtrl.dispose();
    super.dispose();
  }

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
    if (!mounted) return;
    setState(() {
      _guardando = false;
      _pasosAbiertos = false;
      _error = null;
    });
  }

  Future<void> _olvidarClientId() async {
    widget.config.clientId = '';
    await widget.config.save();
    if (!mounted) return;
    _clientIdCtrl.clear();
    setState(() {
      _errorClientId = null;
      _pasosAbiertos = true;
      _error = null;
    });
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configurada = widget.config.clientId.isNotEmpty;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
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
                  'API oficial de Spotify. Con cuenta Premium suena por sí solo; '
                  'sin ella, puede sonar por YouTube Music.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                _bloqueDeLaApp(theme, configurada),
                const SizedBox(height: 24),
                _bloqueDeSesion(theme, configurada),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                ConectarYouTubeMusic(auth: widget.ytAuth),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bloqueDeLaApp(ThemeData theme, bool configurada) {
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.key,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Tu app de Spotify',
                      style: theme.textTheme.titleSmall),
                ),
                if (configurada && !_pasosAbiertos)
                  TextButton(
                    onPressed: () => setState(() => _pasosAbiertos = true),
                    child: const Text('Cambiar'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (configurada && !_pasosAbiertos)
              Row(
                children: [
                  Icon(Icons.check_circle,
                      size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Client ID guardado: '
                      '${_resumen(widget.config.clientId)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              )
            else
              _pasos(theme, configurada),
          ],
        ),
      ),
    );
  }

  Widget _pasos(ThemeData theme, bool configurada) {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Spotify solo deja que una app de terceros funcione para los usuarios '
          'que su creador da de alta a mano, así que NeoFy no puede traer una '
          'configurada: necesitas la tuya. Son dos minutos y se hace una sola vez.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        paso(
            1,
            'Crea una app en el panel de Spotify y marca «Web API».',
            OutlinedButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(_panel),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Abrir el panel'),
            )),
        paso(
            2,
            'Pon este Redirect URI, exactamente así. Spotify ya no acepta '
            '«localhost», solo el 127.0.0.1 literal.',
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
                  onPressed: () =>
                      Clipboard.setData(const ClipboardData(text: _redirect)),
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
                  autofocus: !configurada,
                  decoration: InputDecoration(
                    hintText: '32 caracteres, letras y números',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    errorText: _errorClientId,
                    suffixIcon: IconButton(
                      tooltip: 'Pegar',
                      icon: const Icon(Icons.content_paste, size: 18),
                      onPressed: () async {
                        final d = await Clipboard.getData('text/plain');
                        final t = d?.text?.trim();
                        if (t != null && t.isNotEmpty) _clientIdCtrl.text = t;
                      },
                    ),
                  ),
                  onSubmitted: (_) => _guardarClientId(),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
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
                    if (configurada)
                      TextButton(
                        onPressed: _guardando
                            ? null
                            : () => setState(() => _pasosAbiertos = false),
                        child: const Text('Cancelar'),
                      ),
                  ],
                ),
                if (configurada) ...[
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: _guardando ? null : _olvidarClientId,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Olvidar el Client ID guardado'),
                  ),
                ],
              ],
            )),
      ],
    );
  }

  Widget _bloqueDeSesion(ThemeData theme, bool configurada) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.link, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text('Enlazar tu cuenta', style: theme.textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          configurada
              ? 'La primera vez se abrirá el navegador dos veces: una para la '
                  'app y otra para el reproductor. Después queda guardado y no '
                  'se vuelve a pedir.'
              : 'Guarda antes el Client ID de tu app: sin él, Spotify no tiene '
                  'a quién dar permiso.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy || !configurada ? null : _login,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.login),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_busy
                  ? 'Esperando al navegador…'
                  : 'Iniciar sesión con Spotify'),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          SelectableText(
            _error!,
            style:
                theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'Hace falta una cuenta Spotify Premium: es la propia API la que exige '
          'Premium para controlar la reproducción.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
