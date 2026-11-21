import '../ui/letra_sincronizada.dart';
import 'app_config.dart' show kLimiteDesfaseLetraMs;

/// Ajusta dinámicamente el reloj de la letra según la detección de voz en el
/// audio: retiene el avance al siguiente paso (palabra o letra) si no hay voz,
/// y adelanta el desfase adaptativo si la voz empieza durante una pausa previa.
class ControladorSincronizacionPorVoz {
  ControladorSincronizacionPorVoz({
    this.margenEsperaVozMs = 150,
    this.retardoAdelantoVozMs = 140,
    this.maxSaltoAdelantoMs = 4500,
    this.velocidadCorreccion = 0.25,
  });

  final int margenEsperaVozMs;
  final int retardoAdelantoVozMs;
  final int maxSaltoAdelantoMs;
  final double velocidadCorreccion;

  int _desfaseAdaptativoMs = 0;
  int? _ultimoTiempoEfectivoMs;
  int? _ultimoPosicionBaseMs;
  int? _inicioVozEnPausaMs;
  int? _inicioSilencioMs;

  int get desfaseAdaptativoMs => _desfaseAdaptativoMs;

  void reiniciar() {
    _desfaseAdaptativoMs = 0;
    _ultimoTiempoEfectivoMs = null;
    _ultimoPosicionBaseMs = null;
    _inicioVozEnPausaMs = null;
    _inicioSilencioMs = null;
  }

  int actualizar({
    required int posicionBaseMs,
    required bool reproduciendo,
    required bool hayVoz,
    required List<LineaDeLetra> lineas,
    required ModoVisualizacionLetra modo,
  }) {
    if (lineas.isEmpty) {
      _ultimoPosicionBaseMs = posicionBaseMs;
      _ultimoTiempoEfectivoMs = posicionBaseMs;
      return posicionBaseMs;
    }

    if (!reproduciendo) {
      _ultimoPosicionBaseMs = posicionBaseMs;
      final detenido = _ultimoTiempoEfectivoMs ?? posicionBaseMs;
      return detenido;
    }

    // Si hubo un salto brusco externo en la pista, reiniciamos la deriva previa.
    if (_ultimoPosicionBaseMs != null &&
        (posicionBaseMs - _ultimoPosicionBaseMs!).abs() > 2000) {
      reiniciar();
    }
    _ultimoPosicionBaseMs = posicionBaseMs;

    var candidatoMs =
        (posicionBaseMs + _desfaseAdaptativoMs).clamp(0, 1 << 30);
    final previoMs = _ultimoTiempoEfectivoMs ?? candidatoMs;

    final idxLinea =
        lineas.lastIndexWhere((linea) => linea.inicioMs <= candidatoMs);
    final lineaActual = idxLinea >= 0 ? lineas[idxLinea] : null;
    final enPausa = lineaActual == null || lineaActual.estaEnPausa(candidatoMs);

    if (hayVoz) {
      _inicioSilencioMs = null;
      // Letra atrasada: el cantante ya está cantando pero la letra sigue en pausa.
      if (enPausa) {
        _inicioVozEnPausaMs ??= posicionBaseMs;
        if (posicionBaseMs - _inicioVozEnPausaMs! >= retardoAdelantoVozMs) {
          final objetivoMs = _buscarSiguienteInicio(
            lineas,
            candidatoMs,
            modo: modo,
          );
          if (objetivoMs != null &&
              objetivoMs > candidatoMs &&
              objetivoMs - candidatoMs <= maxSaltoAdelantoMs) {
            final paso = ((objetivoMs - candidatoMs) * velocidadCorreccion)
                .ceil()
                .clamp(1, objetivoMs - candidatoMs);
            candidatoMs += paso;
            _desfaseAdaptativoMs = (candidatoMs - posicionBaseMs).clamp(
              -kLimiteDesfaseLetraMs,
              kLimiteDesfaseLetraMs,
            );
          }
        }
      } else {
        _inicioVozEnPausaMs = null;
      }
      _ultimoTiempoEfectivoMs = candidatoMs;
      return candidatoMs;
    }

    // Sin voz detectada: esperamos brevemente por respiraciones o consonantes.
    _inicioVozEnPausaMs = null;
    _inicioSilencioMs ??= posicionBaseMs;
    if (posicionBaseMs - _inicioSilencioMs! < margenEsperaVozMs) {
      _ultimoTiempoEfectivoMs = candidatoMs;
      return candidatoMs;
    }

    // Si sin voz el reloj cruzaría hacia una nueva línea, palabra o letra,
    // lo retenemos en la frontera hasta que vuelva a detectarse voz.
    final frontera = _primeraFronteraCruzada(
      lineas,
      desdeMs: previoMs,
      hastaMs: candidatoMs,
      modo: modo,
    );
    if (frontera != null) {
      final retenido = frontera.clamp(0, candidatoMs);
      _desfaseAdaptativoMs = (retenido - posicionBaseMs).clamp(
        -kLimiteDesfaseLetraMs,
        kLimiteDesfaseLetraMs,
      );
      _ultimoTiempoEfectivoMs = retenido;
      return retenido;
    }

    // Si ya estamos en el tramo activo de una palabra/letra y sigue sin haber voz,
    // evitamos seguir avanzando hacia la siguiente unidad.
    if (!enPausa && previoMs < candidatoMs) {
      _desfaseAdaptativoMs = (previoMs - posicionBaseMs).clamp(
        -kLimiteDesfaseLetraMs,
        kLimiteDesfaseLetraMs,
      );
      _ultimoTiempoEfectivoMs = previoMs;
      return previoMs;
    }

    _ultimoTiempoEfectivoMs = candidatoMs;
    return candidatoMs;
  }

  int? _buscarSiguienteInicio(
    List<LineaDeLetra> lineas,
    int desdeMs, {
    required ModoVisualizacionLetra modo,
  }) {
    for (final linea in lineas) {
      if (linea.inicioMs > desdeMs) return linea.inicioMs;
      final siguiente = linea.siguientePasoMs(desdeMs, modo: modo);
      if (siguiente != null && siguiente > desdeMs) return siguiente;
    }
    return null;
  }

  int? _primeraFronteraCruzada(
    List<LineaDeLetra> lineas, {
    required int desdeMs,
    required int hastaMs,
    required ModoVisualizacionLetra modo,
  }) {
    if (hastaMs <= desdeMs) return null;
    for (final linea in lineas) {
      if (linea.inicioMs > desdeMs && linea.inicioMs <= hastaMs) {
        return linea.inicioMs;
      }
      final paso = linea.siguientePasoMs(desdeMs, modo: modo);
      if (paso != null && paso > desdeMs && paso <= hastaMs) {
        return paso;
      }
    }
    return null;
  }
}
