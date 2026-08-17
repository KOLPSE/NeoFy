import 'package:flutter/foundation.dart';

import 'app_config.dart';
import 'auth.dart';
import 'spotify_api.dart';

class FollowedPlaylistsStore extends ChangeNotifier {
  FollowedPlaylistsStore({
    required this.api,
    required this.auth,
    required this.obtenerUserId,
    this.onReauth,
  });

  final SpotifyApi api;
  final SpotifyAuth auth;

  final String? Function() obtenerUserId;
  final Future<void> Function()? onReauth;

  final Set<String> _seguidas = {};
  final Set<String> _conocidas = {};
  final Set<String> _consultando = {};

  bool _disposed = false;

  bool get canModify => auth.hasScope(kScopePlaylistModify);

  bool? isFollowed(String id) =>
      _conocidas.contains(id) ? _seguidas.contains(id) : null;

  void seedFollowed(Iterable<String> ids) {
    var nuevas = false;
    for (final id in ids) {
      if (_conocidas.add(id)) nuevas = true;
      _seguidas.add(id);
    }
    if (nuevas) notifyListeners();
  }

  Future<void> ensureKnown(String id) async {
    if (id.isEmpty || _conocidas.contains(id) || _consultando.contains(id)) {
      return;
    }
    final userId = obtenerUserId();
    if (userId == null || userId.isEmpty) return;
    _consultando.add(id);
    try {
      final sigue = await api.isFollowingPlaylist(id, userId);
      if (_disposed) return;
      _conocidas.add(id);
      if (sigue) {
        _seguidas.add(id);
      } else {
        _seguidas.remove(id);
      }
      notifyListeners();
    } catch (_) {
    } finally {
      _consultando.remove(id);
    }
  }

  Future<void> toggle(String id) async {
    if (!canModify) {
      throw ApiException(403, 'Falta el permiso para editar tus playlists.');
    }
    final seguia = isFollowed(id) ?? false;
    _aplicar(id, !seguia);
    try {
      if (seguia) {
        await api.unfollowPlaylist(id);
      } else {
        await api.followPlaylist(id);
      }
    } catch (e) {
      _aplicar(id, seguia);
      rethrow;
    }
  }

  void _aplicar(String id, bool seguida) {
    _conocidas.add(id);
    if (seguida) {
      _seguidas.add(id);
    } else {
      _seguidas.remove(id);
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
