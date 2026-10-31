import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// Drives a system `mpv` process over its JSON IPC protocol.
///
/// Desktop Linux uses the distribution's own mpv instead of media_kit's
/// embedded libmpv. The system player decodes with the GPU, goes properly
/// fullscreen on Wayland and X11, and keeps mpv's native controls (scroll
/// wheel volume, keyboard shortcuts, on-screen controller). The embedded
/// engine remains the fallback when no `mpv` binary is installed.
class MpvClient {
  MpvClient._(this._process, this._socket, this._socketPath);

  /// Overrides the binary search, for wrappers such as
  /// `MOJAC_MPV_BIN=/usr/local/bin/mpv`.
  static const String binaryEnvironmentVariable = 'MOJAC_MPV_BIN';

  static final math.Random _random = math.Random();
  static String? _resolvedBinary;
  static bool _resolveAttempted = false;

  final Process _process;
  final Socket _socket;
  final String _socketPath;

  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  final StreamController<MpvEvent> _events =
      StreamController<MpvEvent>.broadcast();
  final StreamController<String> _logs = StreamController<String>.broadcast();
  final List<String> _logLines = <String>[];

  int _requestId = 0;
  int _observeId = 0;
  bool _tearingDown = false;
  bool _quitting = false;

  /// The raw events mpv pushes: `start-file`, `file-loaded`, `end-file`,
  /// `property-change`, `shutdown`.
  Stream<MpvEvent> get events => _events.stream;

  /// Diagnostics from mpv's stdout/stderr, for the error panel and for
  /// `MOJAC_MPV_LOG=1`.
  Stream<String> get logs => _logs.stream;

  /// The most recent lines, newest last.
  List<String> get logTail => List<String>.unmodifiable(_logLines);

  bool get isRunning => !_tearingDown;

  /// Completes with mpv's exit code when the window closes.
  Future<int> get done => _process.exitCode;

  /// Resolves the mpv executable once. Returns null when mpv is not
  /// installed, which makes the caller fall back to media_kit.
  static String? resolveBinary() {
    if (_resolveAttempted) {
      return _resolvedBinary;
    }
    _resolveAttempted = true;

    String? explicit;
    try {
      final value = Platform.environment[binaryEnvironmentVariable]?.trim();
      if (value != null && value.isNotEmpty) {
        explicit = value;
      }
    } catch (_) {
      // Some platforms do not expose the environment.
    }

    if (explicit != null) {
      if (_isExecutableFile(explicit)) {
        _resolvedBinary = explicit;
        return _resolvedBinary;
      }
      // A bare name resolves through PATH below.
      if (!explicit.contains('/')) {
        final onPath = _searchPath(explicit);
        if (onPath != null) {
          _resolvedBinary = onPath;
          return _resolvedBinary;
        }
      }
    }

    // The AppImage's bubblewrap rootfs does not inherit NixOS's PATH, but it
    // does bind-mount /run, /etc and /home from the host. Check the usual
    // absolute locations before falling back to PATH.
    final home = Platform.environment['HOME'];
    final user = Platform.environment['USER'];
    final candidates = <String>[
      if (home != null && home.isNotEmpty) '$home/.nix-profile/bin/mpv',
      '/run/current-system/sw/bin/mpv',
      if (user != null && user.isNotEmpty)
        '/etc/profiles/per-user/$user/bin/mpv',
      '/usr/local/bin/mpv',
      '/usr/bin/mpv',
      '/bin/mpv',
      '/snap/bin/mpv',
      '/var/lib/flatpak/exports/bin/mpv',
    ];
    for (final candidate in candidates) {
      if (_isExecutableFile(candidate)) {
        _resolvedBinary = candidate;
        return _resolvedBinary;
      }
    }

    _resolvedBinary = _searchPath('mpv');
    return _resolvedBinary;
  }

  static String? _searchPath(String executable) {
    String? path;
    try {
      path = Platform.environment['PATH'];
    } catch (_) {
      return null;
    }
    if (path == null || path.isEmpty) {
      return null;
    }
    for (final directory in path.split(':')) {
      if (directory.isEmpty) {
        continue;
      }
      final candidate = '$directory/$executable';
      if (_isExecutableFile(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  static bool _isExecutableFile(String path) {
    try {
      final stat = File(path).statSync();
      if (stat.type != FileSystemEntityType.file) {
        return false;
      }
      // POSIX execute bits: Dart has no octal literals.
      return (stat.mode & 73) != 0;
    } on FileSystemException {
      return false;
    }
  }

  /// Starts mpv, connects to its IPC socket, and loads [uri].
  ///
  /// The process keeps the user's own mpv configuration (`~/.config/mpv`), so
  /// shaders, fonts and OSC scripts carry over. Only the options needed for a
  /// predictable IPTV session are forced on the command line.
  static Future<MpvClient> launch({
    required Uri uri,
    required String title,
    required String userAgent,
    bool allowInsecure = false,
    String? demuxerOptions,
    bool verbose = false,
  }) async {
    final binary = resolveBinary();
    if (binary == null) {
      throw const MpvUnavailableException();
    }

    final socketPath = _newSocketPath();
    final arguments = <String>[
      // Keep mpv away from our stdin/stdout; the IPC socket is the only
      // control channel.
      '--no-terminal',
      '--idle=yes',
      '--force-window=yes',
      '--keep-open=yes',
      '--save-position-on-quit=no',
      // The system player can use the GPU. This is the whole point of moving
      // desktop playback out of media_kit's software texture.
      '--hwdec=auto-safe',
      '--network-timeout=60',
      '--input-ipc-server=$socketPath',
      '--title=$title',
      '--user-agent=$userAgent',
      '--tls-verify=${allowInsecure ? 'no' : 'yes'}',
      '--msg-level=all=${verbose ? 'info' : 'error'}',
      // The media_kit options minus `strict=experimental`, which switches on
      // ffmpeg's unfinished HLS EXT-X-MEDIA handling and makes ErsatzTV's
      // subtitle rendition take over the variant playlist.
      if (demuxerOptions != null && demuxerOptions.isNotEmpty)
        '--demuxer-lavf-o=$demuxerOptions',
    ];

    // The AppImage prepends its bundled libmpv/ffmpeg to LD_LIBRARY_PATH.
    // The host player must not load those older libraries, so scrub the
    // loader overrides instead of inheriting the AppImage environment.
    final environment = <String, String>{...Platform.environment};
    for (final variable in const <String>[
      'LD_LIBRARY_PATH',
      'LD_LIBRARY_PATH_ORIG',
      'LD_PRELOAD',
      'LD_AUDIT',
    ]) {
      environment.remove(variable);
    }

    Process process;
    try {
      process = await Process.start(
        binary,
        arguments,
        environment: environment,
        includeParentEnvironment: false,
      );
    } on ProcessException catch (error) {
      throw MpvLaunchException('Could not start $binary: ${error.message}');
    }

    final socket = await _connect(socketPath, process);
    final client = MpvClient._(process, socket, socketPath);
    client._forwardOutput();
    client._listen();
    unawaited(process.exitCode.then(client._handleProcessExit));

    try {
      await client.command(<Object?>['loadfile', uri.toString(), 'replace']);
    } catch (error) {
      await client.quit();
      rethrow;
    }
    return client;
  }

  static String _newSocketPath() {
    final suffix =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'
        '-${_random.nextInt(1 << 20).toRadixString(16)}';
    final name = 'mojac-mpv-$suffix.sock';
    var directory = Directory.systemTemp.path;
    // Unix domain socket paths are limited to about 108 bytes.
    if (directory.length + name.length + 1 > 100) {
      directory = '/tmp';
    }
    return '$directory/$name';
  }

  static Future<Socket> _connect(String path, Process process) async {
    final address = InternetAddress(path, type: InternetAddressType.unix);
    final deadline = DateTime.now().add(const Duration(seconds: 6));
    Object? lastError;
    var exited = false;
    unawaited(
      process.exitCode.then((_) {
        exited = true;
      }),
    );
    while (DateTime.now().isBefore(deadline)) {
      if (exited) {
        lastError = 'mpv exited before opening its control socket';
        break;
      }
      try {
        return await Socket.connect(
          address,
          0,
        ).timeout(const Duration(seconds: 2));
      } on SocketException catch (error) {
        lastError = error;
      } on TimeoutException catch (error) {
        lastError = error;
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    process.kill();
    throw MpvLaunchException('mpv did not open its control socket: $lastError');
  }

  void _forwardOutput() {
    void collect(String line) {
      final text = line.trim();
      if (text.isEmpty) {
        return;
      }
      _logLines.add(text);
      if (_logLines.length > 80) {
        _logLines.removeRange(0, _logLines.length - 80);
      }
      if (!_logs.isClosed) {
        _logs.add(text);
      }
    }

    _process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(collect, onError: (Object _) {});
    _process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(collect, onError: (Object _) {});
  }

  void _listen() {
    _socket
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(
          _handleLine,
          onError: (Object _) => _handleDisconnect(),
          onDone: _handleDisconnect,
          cancelOnError: true,
        );
  }

  void _handleLine(String line) {
    if (line.trim().isEmpty) {
      return;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic>) {
      return;
    }

    final requestId = decoded['request_id'];
    if (requestId is int) {
      final completer = _pending.remove(requestId);
      if (completer == null) {
        return;
      }
      final error = decoded['error'];
      if (error is String && error != 'success') {
        completer.completeError(MpvCommandException(error));
      } else {
        completer.complete(decoded['data']);
      }
      return;
    }

    final name = decoded['event'];
    if (name is String && !_events.isClosed) {
      _events.add(MpvEvent(name, decoded));
    }
  }

  void _handleDisconnect() {
    if (!_quitting) {
      // Without the control channel the window cannot be controlled any more,
      // so do not leave an orphan player behind.
      _process.kill();
    }
    _tearDown();
  }

  void _handleProcessExit(int code) {
    if (!_events.isClosed) {
      _events.add(
        MpvEvent('exit', <String, dynamic>{'event': 'exit', 'data': code}),
      );
    }
    _tearDown();
  }

  /// Sends one IPC command and waits for mpv's reply.
  Future<Object?> command(List<Object?> arguments) {
    if (_tearingDown) {
      return Future<Object?>.error(
        const MpvCommandException('mpv is no longer running'),
      );
    }
    final id = ++_requestId;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _socket.write(
      '${jsonEncode(<String, Object?>{'command': arguments, 'request_id': id})}\n',
    );
    unawaited(_socket.flush());
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _pending.remove(id);
        throw const MpvCommandException('mpv did not answer in time');
      },
    );
  }

  Future<Object?> getProperty(String name) {
    return command(<Object?>['get_property', name]);
  }

  Future<void> setProperty(String name, Object value) async {
    await command(<Object?>['set_property', name, value]);
  }

  /// Watches [name]; changes arrive as `property-change` events.
  Future<void> observe(String name) async {
    try {
      await command(<Object?>['observe_property', ++_observeId, name]);
    } on MpvCommandException {
      // Not every property exists in every mpv build; watching is optional.
    }
  }

  /// Stops playback and waits for the window to close.
  Future<void> quit() async {
    _quitting = true;
    if (!_tearingDown) {
      try {
        await command(<Object?>['quit']);
      } catch (_) {
        // mpv frequently closes the socket before answering `quit`.
      }
    }
    try {
      await _process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      _process.kill();
    }
    _tearDown();
  }

  void _tearDown() {
    if (_tearingDown) {
      return;
    }
    _tearingDown = true;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          const MpvCommandException('mpv stopped before answering'),
        );
      }
    }
    _pending.clear();
    _socket.destroy();
    if (!_events.isClosed) {
      unawaited(_events.close());
    }
    if (!_logs.isClosed) {
      unawaited(_logs.close());
    }
    try {
      File(_socketPath).deleteSync();
    } on FileSystemException {
      // Already gone, or never created.
    }
  }
}

/// One decoded IPC event. `property-change` events expose [property] and
/// [value]; `end-file` carries `data['reason']`.
class MpvEvent {
  const MpvEvent(this.name, this.data);

  final String name;
  final Map<String, dynamic> data;

  String? get property => data['name'] as String?;

  Object? get value => data['data'];
}

class MpvUnavailableException implements Exception {
  const MpvUnavailableException();

  @override
  String toString() => 'mpv is not installed';
}

class MpvLaunchException implements Exception {
  const MpvLaunchException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MpvCommandException implements Exception {
  const MpvCommandException(this.message);

  final String message;

  @override
  String toString() => message;
}
