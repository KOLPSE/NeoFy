import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/yt_models.dart';
import 'package:neofy/ui/yt_browse_screen.dart';

/// Lo reportado: desde la portada no había forma de **entrar** en una lista a
/// ver qué canciones tenía. La culpa era del botón de reproducir, que se
/// pintaba centrado sobre la carátula y se quedaba justo el sitio donde todo
/// el mundo pulsa para abrir: reproducía en vez de abrir.
///
/// Aquí se fija el reparto: la tarjeta abre, y solo la esquina reproduce.
void main() {
  const lista = YtItem(
    tipo: YtTipo.lista,
    titulo: 'Rock de casa',
    subtitulo: 'Lista • 42 canciones',
    playlistId: 'PLabc',
  );

  const cancion = YtItem(
    tipo: YtTipo.cancion,
    titulo: 'Take On Me',
    subtitulo: 'a-ha',
    videoId: 'djV11Xbc914',
  );

  Future<void> montar(
    WidgetTester tester,
    YtItem item, {
    required VoidCallback onTap,
    VoidCallback? onReproducir,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: TarjetaDeYtItem(
            item: item,
            cargando: false,
            sonando: false,
            onTap: onTap,
            onReproducir: onReproducir,
          ),
        ),
      ),
    ));
  }

  /// Pone el ratón encima, que es lo que saca el botón de reproducir.
  Future<TestGesture> pasarElRaton(WidgetTester tester, Finder sobre) async {
    final raton = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await raton.addPointer(location: Offset.zero);
    addTearDown(raton.removePointer);
    await tester.pump();
    await raton.moveTo(tester.getCenter(sobre));
    await tester.pumpAndSettle();
    return raton;
  }

  testWidgets('pulsar el centro de una lista la abre, no la reproduce',
      (tester) async {
    var abierta = 0;
    var reproducida = 0;
    await montar(tester, lista,
        onTap: () => abierta++, onReproducir: () => reproducida++);

    // Con el ratón encima (que es cuando aparece el play) y pulsando el
    // centro: antes esto reproducía.
    await pasarElRaton(tester, find.byType(TarjetaDeYtItem));
    await tester.tap(find.byType(TarjetaDeYtItem));
    await tester.pump();

    expect(abierta, 1);
    expect(reproducida, 0);
  });

  testWidgets('el botón de la esquina reproduce sin abrir', (tester) async {
    var abierta = 0;
    var reproducida = 0;
    await montar(tester, lista,
        onTap: () => abierta++, onReproducir: () => reproducida++);

    await pasarElRaton(tester, find.byType(TarjetaDeYtItem));
    final play = find.byKey(claveDelPlayDeTarjeta);
    expect(play, findsOneWidget, reason: 'el play sale al pasar el ratón');
    await tester.tap(play);
    await tester.pump();

    expect(reproducida, 1);
    expect(abierta, 0, reason: 'el play no debe abrir la lista además');
  });

  testWidgets('sin el ratón encima no hay botón que tape la tarjeta',
      (tester) async {
    await montar(tester, lista, onTap: () {}, onReproducir: () {});
    expect(find.byKey(claveDelPlayDeTarjeta), findsNothing);
  });

  testWidgets('una canción no tiene botón aparte: la tarjeta entera la pone',
      (tester) async {
    var sono = 0;
    // `onReproducir` en null es lo que distingue una canción de una lista.
    await montar(tester, cancion, onTap: () => sono++);

    await pasarElRaton(tester, find.byType(TarjetaDeYtItem));
    expect(find.byKey(claveDelPlayDeTarjeta), findsNothing,
        reason: 'una canción suelta no se "abre", así que no hay dos acciones');

    await tester.tap(find.byType(TarjetaDeYtItem));
    await tester.pump();
    expect(sono, 1);
  });
}
