import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/traductor.dart';

/// Texto de la UI en español; se traduce al idioma de Ajustes en tiempo real.
class T extends StatefulWidget {
  const T(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
  });

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;

  @override
  State<T> createState() => _TState();
}

class _TState extends State<T> {
  String _visible = '';
  int _peticion = 0;

  @override
  void initState() {
    super.initState();
    _visible = widget.data;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _actualizar();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) _actualizar();
  }

  void _actualizar() {
    final traductor = TraductorScope.of(context);
    final cache = traductor.cacheUi(widget.data);
    _visible = cache ?? widget.data;
    if (!traductor.traduceUi) return;

    final id = ++_peticion;
    unawaited(() async {
      final traducido = await traductor.traducirUi(widget.data);
      if (!mounted || id != _peticion) return;
      setState(() => _visible = traducido);
    }());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: TraductorScope.of(context),
      builder: (context, _) {
        final traductor = TraductorScope.of(context);
        final cache = traductor.cacheUi(widget.data);
        final texto = cache ?? _visible;
        return Text(
          texto,
          style: widget.style,
          textAlign: widget.textAlign,
          maxLines: widget.maxLines,
          overflow: widget.overflow,
          softWrap: widget.softWrap,
        );
      },
    );
  }
}

/// Biografía de artista: traduce al idioma de Ajustes si Spotify no manda una
/// en ese idioma.
class BiografiaTraducida extends StatefulWidget {
  const BiografiaTraducida({
    super.key,
    required this.texto,
    this.alternativas = const [],
  });

  final String texto;
  final Iterable<String> alternativas;

  @override
  State<BiografiaTraducida> createState() => _BiografiaTraducidaState();
}

class _BiografiaTraducidaState extends State<BiografiaTraducida> {
  String? _traducida;
  int _peticion = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _traducir();
  }

  @override
  void didUpdateWidget(covariant BiografiaTraducida oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.texto != widget.texto ||
        oldWidget.alternativas != widget.alternativas) {
      _traducir();
    }
  }

  void _traducir() {
    final id = ++_peticion;
    unawaited(() async {
      final traductor = TraductorScope.of(context);
      final t = await traductor.biografia(
        widget.texto,
        alternativas: widget.alternativas,
      );
      if (!mounted || id != _peticion) return;
      setState(() => _traducida = t);
    }());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: TraductorScope.of(context),
      builder: (context, _) {
        final texto = _traducida ?? widget.texto;
        final theme = Theme.of(context);
        final bio = formatearBiografia(texto);
        if (bio.parrafos.isEmpty) return const SizedBox.shrink();

        final cuerpo = theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.45,
        );
        final atrib = theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
          fontStyle: FontStyle.italic,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < bio.parrafos.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              Text(bio.parrafos[i], style: cuerpo),
            ],
            if (bio.atribucion != null) ...[
              const SizedBox(height: 10),
              Text('— ${bio.atribucion}', style: atrib),
            ],
          ],
        );
      },
    );
  }
}

/// Para SnackBars, diálogos y otros sitios fuera de un [T].
Future<String> traducirTexto(BuildContext context, String espanol) {
  return TraductorScope.of(context).traducirUi(espanol);
}

/// Los [showDialog] quedan fuera del árbol de la ruta; reenvuelve el traductor.
Future<T?> showDialogTraducido<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final traductor = TraductorScope.of(context);
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => TraductorScope(
      notifier: traductor,
      child: builder(ctx),
    ),
  );
}

/// [InputDecoration] exige [String]; traduce label, hint y helper al vuelo.
class CampoTextoTraducido extends StatefulWidget {
  const CampoTextoTraducido({
    super.key,
    required this.controller,
    this.focusNode,
    required this.label,
    this.hint,
    this.helper,
    this.helperMaxLines,
    this.helperStyle,
    this.prefixIcon,
    this.onSubmitted,
    this.isDense = true,
    this.border = const OutlineInputBorder(),
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final String? hint;
  final String? helper;
  final int? helperMaxLines;
  final TextStyle? helperStyle;
  final Widget? prefixIcon;
  final ValueChanged<String>? onSubmitted;
  final bool isDense;
  final InputBorder border;

  @override
  State<CampoTextoTraducido> createState() => _CampoTextoTraducidoState();
}

class _CampoTextoTraducidoState extends State<CampoTextoTraducido> {
  String _label = '';
  String? _hint;
  String? _helper;
  int _peticion = 0;

  @override
  void initState() {
    super.initState();
    _label = widget.label;
    _hint = widget.hint;
    _helper = widget.helper;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _traducir();
  }

  @override
  void didUpdateWidget(covariant CampoTextoTraducido oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.label != widget.label ||
        oldWidget.hint != widget.hint ||
        oldWidget.helper != widget.helper) {
      _traducir();
    }
  }

  void _traducir() {
    final traductor = TraductorScope.of(context);
    _label = traductor.cacheUi(widget.label) ?? widget.label;
    _hint = widget.hint == null
        ? null
        : traductor.cacheUi(widget.hint!) ?? widget.hint;
    _helper = widget.helper == null
        ? null
        : traductor.cacheUi(widget.helper!) ?? widget.helper;
    if (!traductor.traduceUi) return;

    final id = ++_peticion;
    unawaited(() async {
      final label = await traductor.traducirUi(widget.label);
      final hint = widget.hint == null
          ? null
          : await traductor.traducirUi(widget.hint!);
      final helper = widget.helper == null
          ? null
          : await traductor.traducirUi(widget.helper!);
      if (!mounted || id != _peticion) return;
      setState(() {
        _label = label;
        _hint = hint;
        _helper = helper;
      });
    }());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: TraductorScope.of(context),
      builder: (context, _) {
        final traductor = TraductorScope.of(context);
        final label = traductor.cacheUi(widget.label) ?? _label;
        final hint = widget.hint == null
            ? null
            : traductor.cacheUi(widget.hint!) ?? _hint;
        final helper = widget.helper == null
            ? null
            : traductor.cacheUi(widget.helper!) ?? _helper;
        return TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          decoration: InputDecoration(
            labelText: label.isEmpty ? null : label,
            hintText: hint,
            helperText: helper,
            helperMaxLines: widget.helperMaxLines,
            helperStyle: widget.helperStyle,
            prefixIcon: widget.prefixIcon,
            isDense: widget.isDense,
            border: widget.border,
          ),
          onSubmitted: widget.onSubmitted,
        );
      },
    );
  }
}
