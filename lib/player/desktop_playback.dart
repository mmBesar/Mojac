import 'dart:async';

import '../core/playback.dart';
import 'mpv_client.dart';

/// Owns the system mpv process that plays channels on desktop.
///
/// Mojac never shows mpv's controls: the player window is the whole
/// interface and the user's own `~/.config/mpv` applies. Keeping the process
/// in one place guarantees that only one channel is open at a time, and that
/// Mojac itself never holds a stream connection, so closing the mpv window
/// also ends the server-side transcode instead of leaving it running for an
/// app that is no longer watching.
class DesktopPlayback {
  DesktopPlayback._();

  static final DesktopPlayback instance = DesktopPlayback._();

  MpvClient? _client;
  StreamSubscription<MpvEvent>? _events;

  /// Bumped on every start/stop so a slow launch cannot resurrect a player
  /// the user has already replaced.
  int _generation = 0;

  /// Called when mpv gives up on a stream while the app is still running.
  /// The launcher uses it to show a snack bar.
  void Function(String detail)? onError;

  /// Replaces the current player with one playing [uri].
  ///
  /// The previous mpv is closed first, so switching channels does not leave
  /// the old stream open on the server. Throws when mpv cannot be started;
  /// callers fall back to the built-in player.
  Future<void> play({
    required Uri uri,
    required String title,
    required String userAgent,
    required bool allowInsecure,
  }) async {
    final generation = ++_generation;
    await _release();
    if (generation != _generation) {
      return;
    }

    final client = await MpvClient.launch(
      uri: uri,
      title: title,
      userAgent: userAgent,
      allowInsecure: allowInsecure,
      demuxerOptions: kMpvDemuxerLavfOptions,
    );
    if (generation != _generation) {
      await client.quit();
      return;
    }

    _client = client;
    _events = client.events.listen(_onEvent);
    unawaited(
      client.done.whenComplete(() {
        if (identical(_client, client)) {
          unawaited(_release());
        }
      }),
    );
  }

  /// Stops playback, if any. Called when the app exits so no orphan mpv keeps
  /// a channel open after Mojac is gone.
  Future<void> stop() async {
    _generation++;
    await _release();
  }

  void _onEvent(MpvEvent event) {
    if (event.name != 'end-file') {
      return;
    }
    final reason = event.data['reason']?.toString();
    if (reason != 'error') {
      return;
    }
    final detail = event.data['file_error'];
    // mpv sometimes reports only `reason=error`; the tail of its own output
    // then holds the actual cause (TLS, 404, unsupported codec).
    final tail = _client?.logTail ?? const <String>[];
    unawaited(
      _release().then((_) {
        final fileError = detail is String ? detail.trim() : '';
        final message = fileError.isNotEmpty
            ? fileError
            : tail.isNotEmpty
            ? tail.last
            : 'mpv could not play this stream';
        onError?.call(message);
      }),
    );
  }

  /// Drops the client reference before awaiting, so the exit handler does not
  /// try to release the same player again.
  Future<void> _release() async {
    final subscription = _events;
    _events = null;
    final client = _client;
    _client = null;
    await subscription?.cancel();
    await client?.quit();
  }
}
