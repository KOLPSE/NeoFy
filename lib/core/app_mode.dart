/// Los dos modos completos de la app: NeoFy (Spotify) y NeoTube (YouTube
/// Music). Cada uno tiene su propia sesión, biblioteca y reproducción — no es
/// una pestaña dentro del otro.
enum AppMode {
  neofy,
  neotube;

  bool get esNeoTube => this == AppMode.neotube;

  static AppMode fromNombre(String? nombre) =>
      nombre == 'neotube' ? AppMode.neotube : AppMode.neofy;

  String get nombre => this == AppMode.neotube ? 'neotube' : 'neofy';
}
