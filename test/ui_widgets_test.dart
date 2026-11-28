import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/models.dart';
import 'package:neofy/core/temas.dart';
import 'package:neofy/core/temas_incluidos.dart';
import 'package:neofy/ui/cristal.dart';
import 'package:neofy/ui/home_screen.dart';
import 'package:neofy/ui/icono_de_volumen.dart';
import 'package:neofy/ui/linea_de_artistas.dart';

const _pista = Track(
  id: '1',
  uri: 'spotify:track:1',
  name: 'Un título de canción bastante largo para una tarjeta',
  artists: 'Un artista, Otro artista, Un tercero',
  album: 'Un álbum',
  artSmall: null,
  artMedium: null,
  durationMs: 185000,
  isLocal: false,
);

const _artista = Artist(
  id: '1',
  uri: 'spotify:artist:1',
  name: 'Un nombre de artista largo',
  art: null,
);

const _album = Album(
  id: '1',
  uri: 'spotify:album:1',
  name: 'Un título de álbum bastante largo para una tarjeta',
  artists: 'Un artista, Otro artista, Un tercero',
  art: null,
);

const _temaCristalPrueba = Tema(
  id: 'cristal-prueba',
  nombre: 'Cristal',
  brillo: BrilloDeTema.oscuro,
  cristal: Cristal(activo: true),
  colores: Paleta(
    primario: Color(0xFF55DF79),
    sobrePrimario: Color(0xFF0C1910),
    fondo: Color(0xFF090909),
    superficie: Color(0xFF252525),
    panel: Color(0xFF161616),
    texto: Color(0xFFF7F7F7),
    textoTenue: Color(0xFFB8B8B8),
    borde: Color(0xFF595959),
    error: Color(0xFFFFA0AA),
  ),
);

Widget _envVolumen({required double volumen, required bool muteado}) {
  return MaterialApp(
    theme: construirThemeData(temaNeoFyNocturno),
    home: Scaffold(
      body: IconoDeVolumen(volumen: volumen, muteado: muteado),
    ),
  );
}

PintorDeVolumen _pintorVolumen(WidgetTester t) {
  final paint = t.widget<CustomPaint>(
    find.descendant(
      of: find.byType(IconoDeVolumen),
      matching: find.byType(CustomPaint),
    ),
  );
  return paint.painter! as PintorDeVolumen;
}

Future<void> _pintarTira(
  WidgetTester tester,
  Widget tira,
  double escala,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(escala)),
        child: Scaffold(body: Center(child: tira)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('PanelDeCristal', () {
    testWidgets(
      'con altura acotada el pie del cristal llega abajo, no se queda arriba',
      (t) async {
        await t.pumpWidget(
          MaterialApp(
            theme: construirThemeData(_temaCristalPrueba),
            home: const Center(
              child: SizedBox(
                width: 244,
                height: 400,
                child: PanelDeCristal(
                  child: Column(
                    children: [
                      Expanded(child: SizedBox.expand()),
                      Text('pie'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pump();

        final caja = t.getRect(find.byType(PanelDeCristal));
        final pie = t.getRect(find.text('pie'));
        expect(pie.bottom, closeTo(caja.bottom, 2));
      },
    );
  });

  group('IconoDeVolumen', () {
    testWidgets('silenciado y a cero pintan el mismo estado, no otro icono', (
      t,
    ) async {
      await t.pumpWidget(_envVolumen(volumen: 80, muteado: true));
      expect(_pintorVolumen(t).nivel, 0);

      await t.pumpWidget(_envVolumen(volumen: 0, muteado: false));
      expect(_pintorVolumen(t).nivel, 0);
    });

    testWidgets('al cambiar el volumen el dibujo se mueve, no se sustituye', (
      t,
    ) async {
      await t.pumpWidget(_envVolumen(volumen: 10, muteado: false));
      final bajo = _pintorVolumen(t).nivel;

      await t.pumpWidget(_envVolumen(volumen: 90, muteado: false));
      await t.pump(const Duration(milliseconds: 50));
      final aMitad = _pintorVolumen(t).nivel;
      await t.pump(const Duration(milliseconds: 400));
      final alto = _pintorVolumen(t).nivel;

      expect(bajo, lessThan(1));
      expect(alto, greaterThan(bajo));
      expect(aMitad, inExclusiveRange(bajo, alto + 0.01));
    });
  });

  group('LineaDeArtistas', () {
    testWidgets('pulsar un nombre llama con ese artista', (t) async {
      ArtistaDePista? abierto;
      await t.pumpWidget(
        MaterialApp(
          theme: construirThemeData(temaNeoFyNocturno),
          home: Scaffold(
            body: LineaDeArtistas(
              artistas: const [
                ArtistaDePista(id: 'a1', uri: 'spotify:artist:a1', name: 'fnonose'),
                ArtistaDePista(id: 'a2', uri: 'spotify:artist:a2', name: 'morningtime'),
              ],
              texto: 'fnonose, morningtime',
              onAbrir: (a) => abierto = a,
            ),
          ),
        ),
      );

      await t.tap(find.text('morningtime'));
      expect(abierto?.id, 'a2');
    });

    testWidgets('sin id no es pulsable', (t) async {
      var toques = 0;
      await t.pumpWidget(
        MaterialApp(
          theme: construirThemeData(temaNeoFyNocturno),
          home: Scaffold(
            body: LineaDeArtistas(
              artistas: const [
                ArtistaDePista(id: '', uri: '', name: 'Desconocido'),
              ],
              texto: 'Desconocido',
              onAbrir: (_) => toques++,
            ),
          ),
        ),
      );

      await t.tap(find.text('Desconocido'));
      expect(toques, 0);
    });
  });

  group('tiras de portada con distintas escalas de texto', () {
    for (final escala in [1.0, 1.25, 1.5]) {
      testWidgets('canciones, artistas y álbumes caben al ${escala}x', (
        tester,
      ) async {
        await _pintarTira(
          tester,
          TiraDeCanciones(tracks: const [_pista, _pista], onPlay: (_) {}),
          escala,
        );
        expect(tester.takeException(), isNull);

        await _pintarTira(
          tester,
          TiraDeArtistas(artistas: const [_artista, _artista], onAbrir: (_) {}),
          escala,
        );
        expect(tester.takeException(), isNull);

        await _pintarTira(
          tester,
          TiraDeAlbumes(albumes: const [_album, _album], onAbrir: (_) {}),
          escala,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
