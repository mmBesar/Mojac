import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/bidi.dart';
import '../core/network_image.dart';
import '../core/playback.dart';
import '../core/theme.dart';
import '../core/track_language.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../l10n/strings.dart';
import 'widgets/channel_logo.dart';
import 'widgets/group_filter_bar.dart';
import 'widgets/player_sheets.dart';
import 'widgets/player_stats_overlay.dart';
import 'widgets/programme_sheet.dart';
import 'widgets/stb_browser.dart';
import 'widgets/stb_osd.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.channel});

  final Channel channel;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  /// Set `MOJAC_MPV_LOG=1` to get libmpv's informational log on stderr when
  /// diagnosing a stream that will not start. An installed APK has no easy way
  /// to set environment variables, so on Android errors go to `adb logcat`
  /// instead, where they are rare enough not to flood the log.
  static final MPVLogLevel _mpvLogLevel = _resolveMpvLogLevel();

  static MPVLogLevel _resolveMpvLogLevel() {
    if (Platform.isAndroid) {
      return MPVLogLevel.error;
    }
    try {
      final flag = (Platform.environment['MOJAC_MPV_LOG'] ?? '').trim();
      return flag.isEmpty ? MPVLogLevel.error : MPVLogLevel.info;
    } catch (_) {
      // Not every platform exposes the environment.
      return MPVLogLevel.error;
    }
  }

  /// media_kit_video's Linux software renderer only renders a frame once it
  /// knows the output size, but it reads that size from the frame it refuses
  /// to render, so a controller without a fixed size never starts. Seed it
  /// with 720p and follow the stream's own aspect ratio from then on.
  static const int _softwareVideoWidth = 1280;
  static const int _softwareVideoHeight = 720;

  /// `true` when the built-in player uses media_kit's CPU upload path instead
  /// of the EGLImage hardware texture. On Linux the default is the GPU path,
  /// which is smooth on current Mesa drivers; the software path stays
  /// available for desktops where the hardware texture freezes. Set
  /// `MOJAC_PLAYER_RENDERER=software` to override the persisted choice.
  bool _softwareRenderer = false;

  static String _resolveRenderer(String preference) {
    if (!Platform.isLinux) {
      return 'gpu';
    }
    try {
      final override =
          (Platform.environment['MOJAC_PLAYER_RENDERER'] ?? '').trim();
      if (override == 'gpu' || override == 'software') {
        return override;
      }
    } catch (_) {
      // Not every platform exposes the environment.
    }
    return preference == 'software' ? 'software' : 'gpu';
  }

  late final Player _player;
  late final VideoController _controller;
  late final FocusNode _focusNode;
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<VideoParams>? _videoParamsSubscription;
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription<double>? _volumeSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerLog>? _logSubscription;
  StreamSubscription<Tracks>? _tracksSubscription;
  StreamSubscription<Track>? _trackSubscription;
  (int, int)? _softwareVideoSize;
  Timer? _bufferingWatchdog;

  /// HLS servers can take several seconds to produce their first segment, and
  /// libmpv reports an error for the first failed open attempt even when the
  /// retry succeeds a moment later. Keep the failure overlay hidden and retry
  /// quietly twice before admitting that the channel will not start.
  static const Duration _startupGrace = Duration(seconds: 12);
  static const Duration _retryGrace = Duration(seconds: 8);
  static const int _maxQuietRetries = 2;
  static const Duration _postStartErrorWindow = Duration(seconds: 5);
  Timer? _startupTimer;
  bool _started = false;
  DateTime? _startedAt;
  String? _lastStreamError;
  int _retryCount = 0;

  String? _error;
  bool _buffering = false;
  bool _fullscreen = false;

  /// The channel currently tuned. It starts as [PlayerPage.channel] and changes
  /// when the user surfs with the remote, swipes or picks from the browser.
  late Channel _channel;

  /// Playback gestures: the left half of the video controls brightness and the
  /// right half controls volume. Brightness uses the Android application
  /// brightness API; on Linux an overlay dims the video instead.
  bool _brightnessSupported = false;
  double _brightness = 1;
  double _volume = 100;
  double _lastAudibleVolume = 100;
  bool _adjustingBrightness = true;
  _OsdKind? _osdKind;
  double _osdValue = 0;
  Timer? _osdTimer;
  Timer? _volumeSaveTimer;

  /// STB overlay state. The chrome (buttons) and banner are shown together by a
  /// tap, and the banner can be pinned so it never fades on its own.
  bool _showChrome = false;
  bool _bannerVisible = false;
  bool _bannerPinned = false;
  Timer? _bannerTimer;
  bool _browserOpen = false;
  bool _showStats = false;
  _MessageData? _message;
  Timer? _messageTimer;

  /// Picture state, mirrored into mpv and persisted in the settings.
  String _aspect = 'auto';
  String _deinterlace = 'auto';
  double _audioDelay = 0;
  double _subtitleDelay = 0;

  /// Sleep timer. [sleepMinutes] is null when the timer is off or set to the
  /// end of the current programme.
  int? _sleepMinutes;
  bool _sleepAtEnd = false;
  DateTime? _sleepDeadline;
  Timer? _sleepTimer;

  /// Type-ahead channel entry: digits collect for 1.7 seconds, then tune.
  String _numberEntry = '';
  Timer? _numberTimer;

  /// Per-channel audio/subtitle memory. Persisting is suppressed briefly while
  /// the page applies the stored choices, so restoring defaults does not
  /// immediately re-save them.
  bool _trackPrefsApplied = false;
  bool _rememberTracks = false;
  String? _persistedTracks;
  Timer? _trackMemoryTimer;

  @override
  void initState() {
    super.initState();
    _channel = widget.channel;
    _focusNode = FocusNode(debugLabel: 'mojac-player');

    final settings = context.read<AppState>().settings;
    _aspect = settings.playerAspect;
    _deinterlace = settings.playerDeinterlace;
    _volume = settings.playerVolume;
    _lastAudibleVolume = _volume > 1 ? _volume : 100;
    _persistedTracks = settings.channelTracks[_channel.id];
    _softwareRenderer = _resolveRenderer(settings.playerRenderer) == 'software';

    _player = Player(
      configuration: PlayerConfiguration(
        title: 'Mojac — ${_channel.name}',
        logLevel: _mpvLogLevel,
      ),
    );
    _controller = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        // Decode and present through the GPU by default. The software path
        // keeps the old 1280x720 CPU texture as an escape hatch for machines
        // whose EGL/Mesa stack cannot present the hardware texture.
        enableHardwareAcceleration: !_softwareRenderer,
        width: _softwareRenderer ? _softwareVideoWidth : null,
        height: _softwareRenderer ? _softwareVideoHeight : null,
      ),
    );
    unawaited(_player.setVolume(_volume));
    if (_softwareRenderer) {
      _videoParamsSubscription = _player.stream.videoParams.listen(
        _resizeSoftwareVideo,
      );
    }

    _errorSubscription = _player.stream.error.listen((message) {
      if (!mounted || message.trim().isEmpty) {
        return;
      }
      _lastStreamError = message.trim();
      if (!_started) {
        // Still inside the startup grace window: mpv may be retrying the
        // segment. Do not cover a stream that is about to appear.
        return;
      }
      final startedAt = _startedAt;
      if (startedAt != null &&
          DateTime.now().difference(startedAt) < _postStartErrorWindow) {
        return;
      }
      setState(() => _error = _lastStreamError);
    });
    _playingSubscription = _player.stream.playing.listen((playing) {
      if (playing) {
        _markStarted();
      }
    });
    _positionSubscription = _player.stream.position.listen((position) {
      // Position advances only once libmpv has actually decoded a frame.
      if (position > Duration.zero) {
        _markStarted();
      }
    });
    _bufferingSubscription = _player.stream.buffering.listen((buffering) {
      if (mounted && _buffering != buffering) {
        setState(() => _buffering = buffering);
      }
      _watchBuffering(buffering);
    });
    _volumeSubscription = _player.stream.volume.listen((volume) {
      _volume = volume;
      if (volume > 1) {
        _lastAudibleVolume = volume;
      }
      _scheduleVolumeSave(volume);
    });
    _tracksSubscription = _player.stream.tracks.listen((tracks) {
      if (!mounted || _trackPrefsApplied) {
        return;
      }
      if (tracks.audio.isEmpty && tracks.subtitle.isEmpty) {
        return;
      }
      unawaited(_applyTrackSelection(tracks: tracks));
    });
    _trackSubscription = _player.stream.track.listen((track) {
      if (!mounted || !_rememberTracks) {
        return;
      }
      final audioId = track.audio.id;
      if (audioId.isEmpty || audioId == 'auto') {
        return;
      }
      final subtitleId =
          track.subtitle.id.isEmpty ? 'no' : track.subtitle.id;
      final value = '$audioId|$subtitleId';
      if (_persistedTracks == value) {
        return;
      }
      _persistedTracks = value;
      unawaited(
        context.read<AppState>().rememberChannelTracks(
              _channel.id,
              audioId: audioId,
              subtitleId: subtitleId,
            ),
      );
    });
    if (Platform.isAndroid) {
      // libmpv's messages are only exposed through this stream; without it
      // `adb logcat` shows nothing about a stalled HLS stream.
      _logSubscription = _player.stream.log.listen((log) {
        final text = log.text.trim();
        if (text.isEmpty) {
          return;
        }
        debugPrint('mpv[${log.level}] ${log.prefix}: $text');
      });
    }

    unawaited(
      WakelockPlus.enable().catchError((Object error) {
        debugPrint('Could not enable the wakelock: $error');
      }),
    );
    unawaited(_initializeBrightness());
    unawaited(_open());
    if (settings.showChannelBanner) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showBanner();
        }
      });
    }
  }

  /// Called on the first real sign of playback (playing, a decoded frame or a
  /// non-zero position). It cancels the startup deadline and removes any
  /// in-flight error so a slow start does not leave a failure overlay behind.
  void _markStarted() {
    if (_started || !mounted) {
      return;
    }
    _started = true;
    _startedAt = DateTime.now();
    _retryCount = 0;
    _startupTimer?.cancel();
    _startupTimer = null;
    setState(() {
      _error = null;
      _lastStreamError = null;
      _buffering = false;
    });
  }

  Future<void> _initializeBrightness() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      final current = await ScreenBrightness().application;
      if (!mounted) {
        return;
      }
      setState(() {
        _brightnessSupported = true;
        if (current > 0) {
          _brightness = current.clamp(0.05, 1.0).toDouble();
        }
      });
    } catch (error) {
      debugPrint('Application brightness is unavailable: $error');
    }
  }

  Future<void> _applyBrightness(double value) async {
    if (!_brightnessSupported) {
      return;
    }
    try {
      await ScreenBrightness().setApplicationScreenBrightness(value);
    } catch (error) {
      debugPrint('Could not change application brightness: $error');
    }
  }

  void _startGesture(Offset position, double width) {
    _adjustingBrightness = position.dx < width / 2;
    _showOsd(
      _adjustingBrightness ? _OsdKind.brightness : _OsdKind.volume,
      _adjustingBrightness ? _brightness : _volume / 100,
    );
  }

  void _updateGesture(DragUpdateDetails details, double height) {
    final delta = -(details.primaryDelta ?? 0) / (height * 0.55);
    if (_adjustingBrightness) {
      final next = (_brightness + delta).clamp(0.05, 1.0).toDouble();
      setState(() => _brightness = next);
      unawaited(_applyBrightness(next));
      _showOsd(_OsdKind.brightness, next);
    } else {
      final next = (_volume + delta * 100).clamp(0.0, 100.0).toDouble();
      setState(() => _volume = next);
      unawaited(_player.setVolume(next));
      _showOsd(_OsdKind.volume, next / 100);
    }
  }

  void _showOsd(_OsdKind kind, double value) {
    _osdTimer?.cancel();
    setState(() {
      _osdKind = kind;
      _osdValue = value.clamp(0.0, 1.0).toDouble();
    });
    _osdTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) {
        return;
      }
      setState(() => _osdKind = null);
    });
  }

  void _showMessage(
    IconData icon,
    String title, {
    String? subtitle,
    Color? accent,
  }) {
    _messageTimer?.cancel();
    setState(() {
      _message = _MessageData(
        icon: icon,
        title: title,
        subtitle: subtitle,
        accent: accent ?? context.mojacColors.accent,
      );
    });
    _messageTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) {
        setState(() => _message = null);
      }
    });
  }

  void _showBanner({bool autoHide = true}) {
    _bannerTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() => _bannerVisible = true);
    if (!autoHide || _bannerPinned) {
      return;
    }
    _bannerTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted || _bannerPinned) {
        return;
      }
      setState(() => _bannerVisible = false);
    });
  }

  void _toggleOverlay() {
    if (_showChrome || _bannerVisible) {
      setState(() {
        _showChrome = false;
        if (!_bannerPinned) {
          _bannerVisible = false;
        }
      });
      _bannerTimer?.cancel();
      return;
    }
    setState(() => _showChrome = true);
    _showBanner(autoHide: !_bannerPinned);
  }

  void _toggleBanner() {
    if (_bannerVisible) {
      _bannerTimer?.cancel();
      setState(() {
        _bannerVisible = false;
        _bannerPinned = false;
      });
      return;
    }
    _showBanner(autoHide: false);
  }

  void _togglePin() {
    final pinned = !_bannerPinned;
    _bannerTimer?.cancel();
    setState(() {
      _bannerPinned = pinned;
      _bannerVisible = true;
    });
    if (!pinned) {
      _showBanner();
    }
  }

  Future<void> _toggleFullscreen() async {
    final next = !_fullscreen;
    setState(() => _fullscreen = next);
    await _setSystemUi(immersive: next);
    await _setOrientation(landscape: next);
  }

  Future<void> _setSystemUi({required bool immersive}) async {
    try {
      await SystemChrome.setEnabledSystemUIMode(
        immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    } catch (_) {
      // Desktop platforms do not have system chrome to hide.
    }
  }

  Future<void> _setOrientation({required bool landscape}) async {
    try {
      await SystemChrome.setPreferredOrientations(
        landscape
            ? const <DeviceOrientation>[
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : DeviceOrientation.values,
      );
    } catch (_) {
      // Desktop platforms do not rotate.
    }
  }

  /// Live HLS can sit in buffering for a long time. Dump libmpv's state while
  /// that happens, so `adb logcat` shows where playback is stuck instead of
  /// only an endless spinner in the UI.
  void _watchBuffering(bool buffering) {
    _bufferingWatchdog?.cancel();
    _bufferingWatchdog = null;
    if (!buffering) {
      return;
    }
    var ticks = 0;
    _bufferingWatchdog = Timer.periodic(const Duration(seconds: 10), (timer) {
      ticks += 1;
      unawaited(_logPlaybackState(ticks));
      if (ticks >= 3) {
        timer.cancel();
      }
    });
  }

  Future<void> _logPlaybackState(int tick) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) {
      return;
    }
    const properties = <String>[
      'path',
      'idle-active',
      'core-idle',
      'paused-for-cache',
      'cache-buffering-state',
      'demuxer-cache-state/underrun',
      'demuxer-cache-state/fw-bytes',
      'video-params/w',
      'video-params/codec',
      'video-codec',
      'audio-codec-name',
      'current-tracks/audio/id',
      'track-list/count',
      'seeking',
      'eof-reached',
      'time-pos',
    ];
    final snapshot = StringBuffer('Playback stalled for ${tick * 10}s:');
    for (final property in properties) {
      try {
        final value = await platform.getProperty(property);
        snapshot.write(' $property=$value');
      } catch (_) {
        // The property is not available in this libmpv build.
      }
    }
    debugPrint(snapshot.toString());
  }

  /// Keeps the software texture at the stream's aspect ratio without
  /// exceeding media_kit's 1920x1080 software buffer.
  void _resizeSoftwareVideo(VideoParams params) {
    final double width = (params.dw ?? params.w ?? 0).toDouble();
    final double height = (params.dh ?? params.h ?? 0).toDouble();
    if (width <= 0 || height <= 0) {
      return;
    }
    final double scale = math.min(1.0, math.min(1920 / width, 1080 / height));
    final int targetWidth = (width * scale).round() & ~1;
    final int targetHeight = (height * scale).round() & ~1;
    if (targetWidth <= 0 || targetHeight <= 0) {
      return;
    }
    if (_softwareVideoSize == (targetWidth, targetHeight)) {
      return;
    }
    _softwareVideoSize = (targetWidth, targetHeight);
    unawaited(_controller.setSize(width: targetWidth, height: targetHeight));
  }

  Future<void> _setMpvProperty(String name, String value) async {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty(name, value);
    }
  }

  Future<void> _open() async {
    _retryCount = 0;
    _started = false;
    _startedAt = null;
    _lastStreamError = null;
    _trackPrefsApplied = false;
    if (mounted) {
      setState(() {
        _error = null;
        _buffering = true;
      });
    }
    _armStartup(_startupGrace);
    await _attemptOpen();
  }

  void _armStartup(Duration grace) {
    _startupTimer?.cancel();
    _startupTimer = Timer(grace, _onStartupTimeout);
  }

  void _onStartupTimeout() {
    if (!mounted || _started) {
      return;
    }
    if (_retryCount < _maxQuietRetries) {
      _retryCount += 1;
      setState(() => _buffering = true);
      _armStartup(_retryGrace);
      unawaited(_attemptOpen());
      return;
    }
    setState(() {
      _buffering = false;
      _error = _lastStreamError ?? context.strings.streamStartTimeout;
    });
  }

  Future<void> _attemptOpen() async {
    final state = context.read<AppState>();
    final allowInsecure = state.activeSource?.allowInsecureCerts ?? false;
    try {
      // The software video path avoids the EGLImage texture entirely, so keep
      // decoding on the CPU too and let libmpv convert directly. The GPU path
      // uses the platform's safe hardware decoder list.
      await _setMpvProperty('hwdec', _softwareRenderer ? 'no' : 'auto-safe');
      await _setMpvProperty('keep-open', 'yes');
      await _setMpvProperty('network-timeout', '60');
      await _setMpvProperty('tls-verify', allowInsecure ? 'no' : 'yes');
      await _setMpvProperty('demuxer-lavf-o', kMpvDemuxerLavfOptions);
      await _setMpvProperty('title', 'Mojac — ${_channel.name}');
      await _applyPicture();
      await _player.open(
        Media(
          _channel.url,
          httpHeaders: const <String, String>{
            'User-Agent': kMojacUserAgent,
          },
        ),
        play: true,
      );
      if (!mounted) {
        return;
      }
      setState(() => _buffering = false);
      unawaited(_applyTrackSelection());
    } catch (error) {
      _lastStreamError = error.toString();
      // The startup timer owns the overlay; a slow HLS cold start can still
      // recover after this command reports a failure.
    }
  }

  /// Applies the aspect override, deinterlacing and audio/subtitle delays to
  /// mpv. `auto` is a real value: it clears `video-aspect-override` so the
  /// stream's own ratio comes back after any experiment. `fill` and `stretch`
  /// are handled by the Flutter surface ([_VideoPane]), which crops or
  /// distorts the stream's own texture, so they also clear the override.
  Future<void> _applyPicture() async {
    final override = switch (_aspect) {
      'auto' || 'fill' || 'stretch' => 'no',
      _ => _aspect,
    };
    await _setMpvProperty('video-aspect-override', override);
    await _setMpvProperty('panscan', _aspect == 'fill' ? '1.0' : '0.0');
    await _setMpvProperty('keepaspect', _aspect == 'stretch' ? 'no' : 'yes');
    await _setMpvProperty(
      'deinterlace',
      switch (_deinterlace) {
        'on' => 'yes',
        'off' => 'no',
        _ => 'auto',
      },
    );
    await _setMpvProperty('audio-delay', _audioDelay.toStringAsFixed(3));
    await _setMpvProperty('sub-delay', _subtitleDelay.toStringAsFixed(3));
  }

  Future<void> _applyTrackSelection({
    Tracks? tracks,
    bool force = false,
  }) async {
    if (_trackPrefsApplied && !force) {
      return;
    }
    final available = tracks ?? _player.state.tracks;
    if (available.audio.isEmpty && available.subtitle.isEmpty) {
      return;
    }
    _trackPrefsApplied = true;
    final state = context.read<AppState>();

    AudioTrack? audio;
    SubtitleTrack? subtitle;
    if (!force) {
      final remembered = state.settings.channelTracks[_channel.id];
      if (remembered != null) {
        final parts = remembered.split('|');
        audio = _findAudio(available, parts.first);
        if (parts.length > 1) {
          subtitle = _findSubtitle(available, parts[1]);
        }
      }
    }
    audio ??= _pickAudio(available, state.settings.defaultAudioLanguage);
    if (subtitle == null) {
      final preference = state.settings.defaultSubtitleLanguage;
      if (preference == 'off') {
        subtitle = _findSubtitle(available, 'no');
      } else if (preference != null) {
        subtitle = _pickSubtitle(available, preference);
      }
    }
    if (audio != null) {
      await _player.setAudioTrack(audio);
    }
    if (subtitle != null) {
      await _player.setSubtitleTrack(subtitle);
    }
    _rememberTracks = !force;
  }

  AudioTrack? _findAudio(Tracks tracks, String id) {
    for (final track in tracks.audio) {
      if (track.id == id) {
        return track;
      }
    }
    return null;
  }

  SubtitleTrack? _findSubtitle(Tracks tracks, String id) {
    for (final track in tracks.subtitle) {
      if (track.id == id) {
        return track;
      }
    }
    return null;
  }

  AudioTrack? _pickAudio(Tracks tracks, String? preference) {
    if (preference == null) {
      return null;
    }
    AudioTrack? best;
    var bestScore = 0;
    for (final track in tracks.audio) {
      if (track.id == 'auto' || track.id == 'no') {
        continue;
      }
      final score = languageScore(
        language: track.language,
        title: track.title,
        preference: preference,
      );
      if (score > bestScore) {
        bestScore = score;
        best = track;
      }
    }
    return best;
  }

  SubtitleTrack? _pickSubtitle(Tracks tracks, String preference) {
    SubtitleTrack? best;
    var bestScore = 0;
    for (final track in tracks.subtitle) {
      if (track.id == 'auto' || track.id == 'no') {
        continue;
      }
      final score = languageScore(
        language: track.language,
        title: track.title,
        preference: preference,
      );
      if (score > bestScore) {
        bestScore = score;
        best = track;
      }
    }
    return best;
  }

  String _trackLabel(
    String id,
    String? title,
    String? language,
    AppStrings strings,
  ) {
    final parts = <String>[
      if (title != null && title.trim().isNotEmpty) title.trim(),
      if (language != null && language.trim().isNotEmpty) language.trim(),
    ];
    if (parts.isEmpty) {
      return id == 'no' ? strings.subtitlesOff : strings.trackNumber(1);
    }
    return parts.join(' · ');
  }

  void _restoreTrackDefaults() {
    final state = context.read<AppState>();
    unawaited(state.forgetChannelTracks(_channel.id));
    _persistedTracks = null;
    _trackPrefsApplied = false;
    _rememberTracks = false;
    unawaited(_applyTrackSelection(force: true));
    _showMessage(
      Icons.restart_alt_rounded,
      context.strings.trackDefaultsRestored,
    );
    _trackMemoryTimer?.cancel();
    _trackMemoryTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        _rememberTracks = true;
      }
    });
  }

  Future<void> _cycleAudio() async {
    final strings = context.strings;
    final tracks = _player.state.tracks.audio
        .where((track) => track.id != 'auto')
        .toList(growable: false);
    if (tracks.length <= 1) {
      _showMessage(Icons.graphic_eq_rounded, strings.onlyOneAudio);
      return;
    }
    final current = _player.state.track.audio.id;
    final index = tracks.indexWhere((track) => track.id == current);
    final next = tracks[(index + 1) % tracks.length];
    await _player.setAudioTrack(next);
    _showMessage(
      Icons.graphic_eq_rounded,
      strings.audioTrackChanged,
      subtitle: _trackLabel(next.id, next.title, next.language, strings),
    );
  }

  Future<void> _cycleSubtitle() async {
    final strings = context.strings;
    final tracks = _player.state.tracks.subtitle
        .where((track) => track.id != 'auto')
        .toList(growable: false);
    if (tracks.isEmpty) {
      _showMessage(Icons.subtitles_off_rounded, strings.noSubtitleTracks);
      return;
    }
    final current = _player.state.track.subtitle.id;
    final index = tracks.indexWhere((track) => track.id == current);
    final next = tracks[(index + 1) % tracks.length];
    await _player.setSubtitleTrack(next);
    _showMessage(
      Icons.subtitles_rounded,
      strings.subtitleChanged,
      subtitle: next.id == 'no'
          ? strings.subtitlesOff
          : _trackLabel(next.id, next.title, next.language, strings),
    );
  }

  void _scheduleVolumeSave(double volume) {
    _volumeSaveTimer?.cancel();
    _volumeSaveTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) {
        unawaited(context.read<AppState>().setPlayerVolume(volume));
      }
    });
  }

  void _adjustVolume(double delta) {
    final next = (_volume + delta).clamp(0.0, 100.0).toDouble();
    setState(() => _volume = next);
    unawaited(_player.setVolume(next));
    _showOsd(_OsdKind.volume, next / 100);
  }

  void _toggleMute() {
    final muted = _volume <= 0.5;
    final next = muted ? _lastAudibleVolume : 0.0;
    setState(() => _volume = next);
    unawaited(_player.setVolume(next));
    _showOsd(_OsdKind.volume, next / 100);
    _showMessage(
      next <= 0.5 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
      next <= 0.5 ? context.strings.muted : context.strings.volume,
    );
  }

  void _setAspect(String value) {
    setState(() => _aspect = value);
    unawaited(context.read<AppState>().setPlayerAspect(value));
    unawaited(_applyPicture());
    _showMessage(
      Icons.aspect_ratio_rounded,
      context.strings.aspectRatio,
      subtitle: _aspectLabel(context.strings, value),
    );
  }

  void _cycleAspect() {
    final index = kPlayerAspects.indexOf(_aspect);
    final next = kPlayerAspects[(index + 1) % kPlayerAspects.length];
    _setAspect(next);
  }

  void _setDeinterlace(String value) {
    setState(() => _deinterlace = value);
    unawaited(context.read<AppState>().setPlayerDeinterlace(value));
    unawaited(_applyPicture());
    _showMessage(
      Icons.auto_fix_high_rounded,
      context.strings.deinterlace,
      subtitle: switch (value) {
        'on' => context.strings.deinterlaceOn,
        'off' => context.strings.deinterlaceOff,
        _ => context.strings.deinterlaceAuto,
      },
    );
  }

  void _cycleDeinterlace() {
    final index = kPlayerDeinterlaceModes.indexOf(_deinterlace);
    final next = kPlayerDeinterlaceModes[
        (index + 1) % kPlayerDeinterlaceModes.length];
    _setDeinterlace(next);
  }

  void _setAudioDelay(double value) {
    final next = value.clamp(-10.0, 10.0).toDouble();
    setState(() => _audioDelay = next);
    unawaited(_applyPicture());
    _showMessage(
      Icons.graphic_eq_rounded,
      context.strings.audioDelay,
      subtitle: _formatDelay(next),
    );
  }

  void _setSubtitleDelay(double value) {
    final next = value.clamp(-10.0, 10.0).toDouble();
    setState(() => _subtitleDelay = next);
    unawaited(_applyPicture());
    _showMessage(
      Icons.subtitles_rounded,
      context.strings.subtitleDelay,
      subtitle: _formatDelay(next),
    );
  }

  void _resetPicture() {
    setState(() {
      _aspect = 'auto';
      _deinterlace = 'auto';
      _audioDelay = 0;
      _subtitleDelay = 0;
    });
    final state = context.read<AppState>();
    unawaited(state.setPlayerAspect('auto'));
    unawaited(state.setPlayerDeinterlace('auto'));
    unawaited(_applyPicture());
    _showMessage(Icons.restart_alt_rounded, context.strings.pictureReset);
  }

  void _setSleepMinutes(int? minutes) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    if (minutes == null) {
      setState(() {
        _sleepMinutes = null;
        _sleepAtEnd = false;
        _sleepDeadline = null;
      });
      _showMessage(Icons.bedtime_off_rounded, context.strings.sleepOff);
      return;
    }
    final deadline = DateTime.now().add(Duration(minutes: minutes));
    setState(() {
      _sleepMinutes = minutes;
      _sleepAtEnd = false;
      _sleepDeadline = deadline;
    });
    _sleepTimer = Timer(Duration(minutes: minutes), _sleepNow);
    _showMessage(
      Icons.bedtime_rounded,
      context.strings.sleepTimerSet(minutes),
    );
  }

  void _setSleepEndOfProgramme() {
    final now = DateTime.now();
    final programme = context.read<AppState>().epg.nowFor(_channel, now);
    if (programme == null) {
      _showMessage(
        Icons.bedtime_rounded,
        context.strings.noProgrammeInfo,
      );
      return;
    }
    final delay = programme.stop.difference(now);
    if (delay <= Duration.zero) {
      return;
    }
    _sleepTimer?.cancel();
    setState(() {
      _sleepMinutes = null;
      _sleepAtEnd = true;
      _sleepDeadline = programme.stop;
    });
    _sleepTimer = Timer(delay, _sleepNow);
    _showMessage(
      Icons.bedtime_rounded,
      context.strings.sleepEndOfProgramme,
      subtitle: context.strings.formatTime(
        programme.stop,
        use24HourTime: context.read<AppState>().settings.use24HourTime,
      ),
    );
  }

  void _sleepNow() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    if (!mounted) {
      return;
    }
    setState(() {
      _sleepMinutes = null;
      _sleepAtEnd = false;
      _sleepDeadline = null;
    });
    unawaited(_player.pause());
    _showMessage(Icons.bedtime_rounded, context.strings.sleepTimerFinished);
  }

  String? _sleepLabel() {
    final deadline = _sleepDeadline;
    if (deadline == null) {
      return null;
    }
    final remaining = deadline.difference(DateTime.now());
    final minutes = remaining.inMinutes < 1 ? 1 : remaining.inMinutes;
    return context.strings.sleepIn(minutes);
  }

  void _handleDigit(String digit) {
    _numberEntry = '$_numberEntry$digit';
    _numberTimer?.cancel();
    _numberTimer = Timer(const Duration(milliseconds: 1700), _commitNumber);
    _showMessage(
      Icons.dialpad_rounded,
      context.strings.enterChannelNumber,
      subtitle: _numberEntry,
    );
  }

  void _commitNumber() {
    final digits = _numberEntry;
    _numberEntry = '';
    _numberTimer = null;
    if (digits.isEmpty) {
      return;
    }
    final channels = context.read<AppState>().channels;
    final wanted = int.tryParse(digits);
    Channel? match;
    if (wanted != null) {
      for (final channel in channels) {
        if (int.tryParse(channel.number.trim()) == wanted) {
          match = channel;
          break;
        }
      }
    }
    if (match == null) {
      _showMessage(
        Icons.search_off_rounded,
        context.strings.channelNotFound,
        subtitle: digits,
      );
      return;
    }
    _tune(match);
  }

  void _tune(Channel channel) {
    if (channel.id == _channel.id) {
      setState(() => _browserOpen = false);
      return;
    }
    _retryCount = 0;
    _trackPrefsApplied = false;
    _rememberTracks = false;
    _persistedTracks = context.read<AppState>().settings.channelTracks[channel.id];
    _started = false;
    _startedAt = null;
    _error = null;
    setState(() {
      _channel = channel;
      _browserOpen = false;
      _showChrome = false;
    });
    _showMessage(
      Icons.live_tv_rounded,
      context.strings.tunedTo,
      subtitle: '${channel.displayNumber} · ${channel.name}',
    );
    if (_bannerVisible || context.read<AppState>().settings.showChannelBanner) {
      _showBanner();
    }
    unawaited(_open());
  }

  void _nextChannel(int delta) {
    final channels = context.read<AppState>().channels;
    if (channels.length < 2) {
      return;
    }
    final index = channels.indexWhere((channel) => channel.id == _channel.id);
    final next = index < 0
        ? channels.first
        : channels[(index + delta + channels.length) % channels.length];
    _tune(next);
  }

  void _openBrowser() {
    setState(() {
      _browserOpen = true;
      _showChrome = false;
      _bannerVisible = false;
    });
    _bannerTimer?.cancel();
  }

  void _closeBrowser() {
    if (!_browserOpen) {
      return;
    }
    setState(() => _browserOpen = false);
    _focusNode.requestFocus();
  }

  void _openProgrammeSheet(Programme? programme) {
    if (programme == null) {
      return;
    }
    final state = context.read<AppState>();
    unawaited(
      showProgrammeSheet(
        context,
        channel: _channel,
        programme: programme,
        allowInsecure: state.activeSource?.allowInsecureCerts ?? false,
        onWatch: () {},
      ),
    );
  }

  Future<void> _showTracks() async {
    if (_bannerVisible) {
      setState(() => _bannerVisible = false);
    }
    await showTrackSheet(
      context,
      player: _player,
      strings: context.strings,
      onRestoreDefaults: _restoreTrackDefaults,
    );
    if (mounted) {
      _focusNode.requestFocus();
    }
  }

  void _showPicture() {
    unawaited(
      showPictureSheet(
        context,
        aspect: _aspect,
        deinterlace: _deinterlace,
        audioDelay: _audioDelay,
        subtitleDelay: _subtitleDelay,
        onAspect: _setAspect,
        onDeinterlace: _setDeinterlace,
        onAudioDelay: _setAudioDelay,
        onSubtitleDelay: _setSubtitleDelay,
        onReset: _resetPicture,
      ).then((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      }),
    );
  }

  void _showSleepTimer() {
    unawaited(
      showSleepTimerSheet(
        context,
        minutes: _sleepMinutes,
        endOfProgramme: _sleepAtEnd,
        onMinutes: _setSleepMinutes,
        onEndOfProgramme: _setSleepEndOfProgramme,
      ).then((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      }),
    );
  }

  void _showShortcuts() {
    unawaited(
      showShortcutsSheet(context).then((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      }),
    );
  }

  void _showDiagnostics() {
    unawaited(
      showDiagnosticsSheet(
        context,
        player: _player,
        channel: _channel,
        lastError: _lastStreamError,
      ).then((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      }),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape) {
      if (_browserOpen) {
        _closeBrowser();
      } else if (_fullscreen) {
        unawaited(_toggleFullscreen());
      } else {
        Navigator.of(context).maybePop();
      }
      return KeyEventResult.handled;
    }
    if (_numberEntry.isNotEmpty &&
        key == LogicalKeyboardKey.enter) {
      _numberTimer?.cancel();
      _commitNumber();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
      unawaited(_player.playOrPause());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF || key == LogicalKeyboardKey.f11) {
      unawaited(_toggleFullscreen());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM) {
      _toggleMute();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _adjustVolume(5);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _adjustVolume(-5);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.pageUp) {
      _nextChannel(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.pageDown) {
      _nextChannel(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC || key == LogicalKeyboardKey.keyB) {
      _browserOpen ? _closeBrowser() : _openBrowser();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS) {
      unawaited(_showTracks());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyA) {
      unawaited(_cycleAudio());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyJ) {
      unawaited(_cycleSubtitle());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyP) {
      _showPicture();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyZ) {
      _cycleAspect();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyT) {
      _cycleDeinterlace();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyI) {
      _toggleBanner();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyN) {
      _showSleepTimer();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyD) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _showDiagnostics();
      } else {
        setState(() => _showStats = !_showStats);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyH || key == LogicalKeyboardKey.f1) {
      _showShortcuts();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.bracketLeft) {
      _setAudioDelay(_audioDelay - 0.05);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.bracketRight) {
      _setAudioDelay(_audioDelay + 0.05);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.comma) {
      _setSubtitleDelay(_subtitleDelay - 0.05);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.period) {
      _setSubtitleDelay(_subtitleDelay + 0.05);
      return KeyEventResult.handled;
    }
    final digit = _digitFor(key);
    if (digit != null) {
      _handleDigit(digit);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String? _digitFor(LogicalKeyboardKey key) {
    // LogicalKeyboardKey overrides == and hashCode, so this map cannot be
    // const; the Flutter analyzer rejects non-primitive const map keys.
    final digits = <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.digit0: '0',
      LogicalKeyboardKey.digit1: '1',
      LogicalKeyboardKey.digit2: '2',
      LogicalKeyboardKey.digit3: '3',
      LogicalKeyboardKey.digit4: '4',
      LogicalKeyboardKey.digit5: '5',
      LogicalKeyboardKey.digit6: '6',
      LogicalKeyboardKey.digit7: '7',
      LogicalKeyboardKey.digit8: '8',
      LogicalKeyboardKey.digit9: '9',
      LogicalKeyboardKey.numpad0: '0',
      LogicalKeyboardKey.numpad1: '1',
      LogicalKeyboardKey.numpad2: '2',
      LogicalKeyboardKey.numpad3: '3',
      LogicalKeyboardKey.numpad4: '4',
      LogicalKeyboardKey.numpad5: '5',
      LogicalKeyboardKey.numpad6: '6',
      LogicalKeyboardKey.numpad7: '7',
      LogicalKeyboardKey.numpad8: '8',
      LogicalKeyboardKey.numpad9: '9',
    };
    return digits[key];
  }

  @override
  void dispose() {
    _osdTimer?.cancel();
    _bannerTimer?.cancel();
    _messageTimer?.cancel();
    _sleepTimer?.cancel();
    _numberTimer?.cancel();
    _volumeSaveTimer?.cancel();
    _trackMemoryTimer?.cancel();
    _errorSubscription?.cancel();
    _playingSubscription?.cancel();
    _bufferingSubscription?.cancel();
    _volumeSubscription?.cancel();
    _positionSubscription?.cancel();
    _videoParamsSubscription?.cancel();
    _logSubscription?.cancel();
    _tracksSubscription?.cancel();
    _trackSubscription?.cancel();
    _bufferingWatchdog?.cancel();
    _startupTimer?.cancel();
    _focusNode.dispose();
    if (_brightnessSupported) {
      unawaited(
        ScreenBrightness()
            .resetApplicationScreenBrightness()
            .catchError((Object error) {
          debugPrint('Could not reset application brightness: $error');
        }),
      );
    }
    unawaited(
      WakelockPlus.disable().catchError((Object error) {
        debugPrint('Could not disable the wakelock: $error');
      }),
    );
    unawaited(_player.dispose());
    unawaited(_setSystemUi(immersive: false));
    unawaited(_setOrientation(landscape: false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = context.strings;
    final colors = context.mojacColors;
    final allowInsecure = state.activeSource?.allowInsecureCerts ?? false;
    final now = state.now;
    final current = state.epg.nowFor(_channel, now);
    final next = state.epg.nextFor(_channel, now);
    final groups = channelGroups(state.channels);
    final group = groups.contains(state.settings.groupFilter)
        ? state.settings.groupFilter
        : null;

    final video = _VideoPane(
      player: _player,
      controller: _controller,
      channel: _channel,
      error: _error,
      buffering: _buffering,
      starting: !_started && _error == null,
      strings: strings,
      onRetry: _open,
      fullscreen: _fullscreen,
      onToggleFullscreen: _toggleFullscreen,
      onDragStart: _startGesture,
      onDragUpdate: _updateGesture,
      onTap: _toggleOverlay,
      onSwipe: _nextChannel,
      dimOpacity: _brightnessSupported ? 0.0 : (1 - _brightness) * 0.6,
      aspect: _aspect,
      showChrome: _showChrome,
      onPlayPause: () => unawaited(_player.playOrPause()),
      onToggleMute: _toggleMute,
      onTracks: () => unawaited(_showTracks()),
      onPicture: _showPicture,
      onSleep: _showSleepTimer,
      onStats: () => setState(() => _showStats = !_showStats),
      onDiagnostics: _showDiagnostics,
      onBrowse: _openBrowser,
      stats: _showStats
          ? PlayerStatsOverlay(player: _player, strings: strings)
          : null,
      levelOsd: _osdKind == null
          ? null
          : StbLevelOsd(
              label: _osdKind == _OsdKind.brightness
                  ? strings.brightness
                  : strings.volume,
              icon: _osdKind == _OsdKind.brightness
                  ? Icons.brightness_6_rounded
                  : (_volume <= 0.01
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded),
              value: _osdValue,
              muted: _osdKind == _OsdKind.volume && _volume <= 0.01,
            ),
      messageOsd: _message == null
          ? null
          : StbMessageOsd(
              icon: _message!.icon,
              title: _message!.title,
              subtitle: _message!.subtitle,
              accent: _message!.accent,
            ),
      banner: _bannerVisible
          ? StbBanner(
              channel: _channel,
              allowInsecure: allowInsecure,
              nowPlaying: current,
              next: next,
              now: now,
              use24HourTime: state.settings.use24HourTime,
              favorite: state.isFavorite(_channel.id),
              pinned: _bannerPinned,
              compact: MediaQuery.sizeOf(context).width < 620,
              sleepLabel: _sleepLabel(),
              onToggleFavorite: () {
                unawaited(state.toggleFavorite(_channel.id));
              },
              onTogglePin: _togglePin,
              onOpenProgramme: () => _openProgrammeSheet(current),
            )
          : null,
    );

    final info = PlayerChannelInfo(
      channel: _channel,
      allowInsecure: allowInsecure,
      onRetry: _open,
      onBrowse: _openBrowser,
    );

    final body = LayoutBuilder(
      builder: (context, constraints) {
        final landscape = constraints.maxWidth > constraints.maxHeight;
        final wideDesktop = constraints.maxWidth >= 980;
        final sideBySide = landscape || wideDesktop;

        if (_fullscreen) {
          return video;
        }

        if (sideBySide) {
          // Landscape phones get the same side panel as wide desktops, so
          // the video stays fully visible instead of pushing the channel
          // information below the fold.
          final panelWidth = wideDesktop
              ? 380.0
              : (constraints.maxWidth * 0.4).clamp(260.0, 380.0).toDouble();
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: video),
              Container(
                width: panelWidth,
                decoration: BoxDecoration(
                  color: colors.mantle,
                  border: BorderDirectional(
                    start: BorderSide(color: colors.surface1),
                  ),
                ),
                child: info,
              ),
            ],
          );
        }

        return Column(
          children: <Widget>[
            AspectRatio(aspectRatio: 16 / 9, child: video),
            Expanded(
              child: Container(
                width: double.infinity,
                color: colors.mantle,
                child: info,
              ),
            ),
          ],
        );
      },
    );

    return PopScope<void>(
      canPop: !_fullscreen && !_browserOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        if (_browserOpen) {
          _closeBrowser();
        } else if (_fullscreen) {
          unawaited(_toggleFullscreen());
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _fullscreen
            ? null
            : AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                titleSpacing: 0,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    BidiText(
                      _channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '${strings.channel} ${_channel.displayNumber}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                actions: <Widget>[
                  IconButton(
                    tooltip: strings.browseChannels,
                    onPressed: _openBrowser,
                    icon: const Icon(Icons.live_tv_rounded),
                  ),
                  IconButton(
                    tooltip: strings.fullScreen,
                    onPressed: _toggleFullscreen,
                    icon: const Icon(Icons.fullscreen_rounded),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
        body: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _onKey,
          child: SafeArea(
            top: _fullscreen,
            bottom: !_fullscreen,
            child: Stack(
              children: <Widget>[
                Positioned.fill(child: body),
                if (_browserOpen)
                  Positioned.fill(
                    child: StbChannelBrowser(
                      channels: state.channels,
                      current: _channel,
                      groups: groups,
                      group: group,
                      now: now,
                      allowInsecure: allowInsecure,
                      nowFor: (channel) => state.epg.nowFor(channel, now),
                      isFavorite: (channel) => state.isFavorite(channel.id),
                      onTune: _tune,
                      onGroupChanged: (value) {
                        unawaited(state.setGroupFilter(value));
                      },
                      onClose: _closeBrowser,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _aspectLabel(AppStrings strings, String aspect) {
  switch (aspect) {
    case 'auto':
      return strings.aspectAuto;
    case 'fill':
      return strings.aspectFill;
    case 'stretch':
      return strings.aspectStretch;
    default:
      return aspect;
  }
}

String _formatDelay(double seconds) {
  final millis = (seconds * 1000).round();
  final sign = millis > 0 ? '+' : '';
  return '$sign$millis ms';
}

double _aspectValue(String aspect) {
  switch (aspect) {
    case '4:3':
      return 4 / 3;
    case '21:9':
      return 21 / 9;
    default:
      return 16 / 9;
  }
}

class _MessageData {
  const _MessageData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color accent;
}

class _VideoPane extends StatelessWidget {
  const _VideoPane({
    required this.player,
    required this.controller,
    required this.channel,
    required this.error,
    required this.buffering,
    required this.starting,
    required this.strings,
    required this.onRetry,
    required this.fullscreen,
    required this.onToggleFullscreen,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onTap,
    required this.onSwipe,
    required this.dimOpacity,
    required this.aspect,
    required this.showChrome,
    required this.onPlayPause,
    required this.onToggleMute,
    required this.onTracks,
    required this.onPicture,
    required this.onSleep,
    required this.onStats,
    required this.onDiagnostics,
    required this.onBrowse,
    required this.stats,
    required this.levelOsd,
    required this.messageOsd,
    required this.banner,
  });

  final Player player;
  final VideoController controller;
  final Channel channel;
  final String? error;
  final bool buffering;
  final bool starting;
  final AppStrings strings;
  final VoidCallback onRetry;
  final bool fullscreen;
  final VoidCallback onToggleFullscreen;
  final void Function(Offset position, double width) onDragStart;
  final void Function(DragUpdateDetails details, double height) onDragUpdate;
  final VoidCallback onTap;
  final void Function(int delta) onSwipe;
  final double dimOpacity;
  final String aspect;
  final bool showChrome;
  final VoidCallback onPlayPause;
  final VoidCallback onToggleMute;
  final VoidCallback onTracks;
  final VoidCallback onPicture;
  final VoidCallback onSleep;
  final VoidCallback onStats;
  final VoidCallback onDiagnostics;
  final VoidCallback onBrowse;
  final Widget? stats;
  final Widget? levelOsd;
  final Widget? messageOsd;
  final Widget? banner;

  @override
  Widget build(BuildContext context) {
    // `auto` shows the stream's own texture, letterboxed. `fill` keeps that
    // ratio and crops, and `stretch` distorts it to the window. The ratio
    // presets get a stage of that shape; mpv has already overridden the
    // texture to match (see _applyPicture).
    final video = switch (aspect) {
      'fill' => SizedBox.expand(
          child: Video(
            controller: controller,
            controls: NoVideoControls,
            fit: BoxFit.cover,
          ),
        ),
      'stretch' => SizedBox.expand(
          child: Video(
            controller: controller,
            controls: NoVideoControls,
            fit: BoxFit.fill,
          ),
        ),
      'auto' => SizedBox.expand(
          child: Video(
            controller: controller,
            controls: NoVideoControls,
            fit: BoxFit.contain,
          ),
        ),
      _ => Center(
          child: AspectRatio(
            aspectRatio: _aspectValue(aspect),
            child: Video(
              controller: controller,
              controls: NoVideoControls,
              // Fill the chosen stage even if the texture's own ratio did
              // not follow mpv's override, so the preset always looks the
              // same on every platform.
              fit: BoxFit.fill,
            ),
          ),
        ),
    };

    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560 ||
              constraints.maxHeight < 320;
          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  onDoubleTap: onToggleFullscreen,
                  onVerticalDragStart: (details) =>
                      onDragStart(details.localPosition, constraints.maxWidth),
                  onVerticalDragUpdate: (details) =>
                      onDragUpdate(details, constraints.maxHeight),
                  onHorizontalDragEnd: (details) {
                    final velocity = details.primaryVelocity ?? 0;
                    if (velocity.abs() < 240) {
                      return;
                    }
                    onSwipe(velocity < 0 ? 1 : -1);
                  },
                  child: video,
                ),
              ),
              if (dimOpacity > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: dimOpacity),
                    ),
                  ),
                ),
              if (buffering && !starting)
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (starting)
                // A quiet placeholder while mpv negotiates the HLS playlist.
                // The error overlay only appears after the quiet retries run
                // out, so a slow cold start never flashes a failure screen.
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            strings.startingStream,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (error != null)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.82),
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Icon(
                                Icons.error_outline_rounded,
                                color: Colors.white70,
                                size: 44,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                strings.playbackError,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                strings.playbackErrorBody,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  height: 1.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 10),
                              BidiText(
                                error!,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 18),
                              FilledButton.icon(
                                onPressed: onRetry,
                                icon: const Icon(Icons.refresh_rounded),
                                label: Text(strings.playbackRetry),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (banner != null)
                PositionedDirectional(
                  start: 12,
                  end: 12,
                  bottom: showChrome ? 62 : 12,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: compact ? 520 : 680,
                      ),
                      child: banner!,
                    ),
                  ),
                ),
              if (showChrome)
                PositionedDirectional(
                  start: 8,
                  end: 8,
                  bottom: 8,
                  child: Row(
                    children: <Widget>[
                      _OverlayButton(
                        tooltip: strings.play,
                        icon: Icons.play_arrow_rounded,
                        onPressed: onPlayPause,
                      ),
                      const SizedBox(width: 6),
                      _OverlayButton(
                        tooltip: strings.mute,
                        icon: Icons.volume_up_rounded,
                        onPressed: onToggleMute,
                      ),
                      const SizedBox(width: 6),
                      _OverlayButton(
                        tooltip: strings.tracks,
                        icon: Icons.tune_rounded,
                        onPressed: onTracks,
                      ),
                      if (!compact) ...<Widget>[
                        const SizedBox(width: 6),
                        _OverlayButton(
                          tooltip: strings.picture,
                          icon: Icons.aspect_ratio_rounded,
                          onPressed: onPicture,
                        ),
                        const SizedBox(width: 6),
                        _OverlayButton(
                          tooltip: strings.sleepTimer,
                          icon: Icons.bedtime_outlined,
                          onPressed: onSleep,
                        ),
                        const SizedBox(width: 6),
                        _OverlayButton(
                          tooltip: strings.statistics,
                          icon: Icons.monitor_heart_outlined,
                          onPressed: onStats,
                          onLongPress: onDiagnostics,
                        ),
                      ],
                      const SizedBox(width: 6),
                      _OverlayButton(
                        tooltip: strings.browseChannels,
                        icon: Icons.view_list_rounded,
                        onPressed: onBrowse,
                      ),
                      const Spacer(),
                      _OverlayButton(
                        tooltip: fullscreen
                            ? strings.exitFullScreen
                            : strings.fullScreen,
                        icon: fullscreen
                            ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded,
                        onPressed: onToggleFullscreen,
                      ),
                    ],
                  ),
                ),
              if (banner == null && !showChrome && !fullscreen)
                PositionedDirectional(
                  bottom: 8,
                  end: 8,
                  child: _OverlayButton(
                    tooltip: strings.fullScreen,
                    icon: Icons.fullscreen_rounded,
                    onPressed: onToggleFullscreen,
                  ),
                ),
              if (stats != null)
                PositionedDirectional(
                  top: 12,
                  start: 12,
                  child: IgnorePointer(child: stats!),
                ),
              if (messageOsd != null)
                PositionedDirectional(
                  top: 12,
                  start: 64,
                  end: 64,
                  child: Center(child: messageOsd!),
                ),
              if (levelOsd != null) Positioned.fill(child: levelOsd!),
            ],
          );
        },
      ),
    );
  }
}

enum _OsdKind { brightness, volume }

class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.onLongPress,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.5),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        onLongPress: onLongPress,
        color: Colors.white,
        icon: Icon(icon),
      ),
    );
  }
}

class PlayerChannelInfo extends StatelessWidget {
  const PlayerChannelInfo({
    super.key,
    required this.channel,
    required this.allowInsecure,
    required this.onRetry,
    required this.onBrowse,
  });

  final Channel channel;
  final bool allowInsecure;
  final VoidCallback onRetry;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = context.strings;
    final colors = context.mojacColors;
    final theme = Theme.of(context);
    final now = state.now;
    final current = state.epg.nowFor(channel, now);
    final next = state.epg.nextFor(channel, now);
    final use24 = state.settings.use24HourTime;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              ChannelLogo(
                channel: channel,
                allowInsecure: allowInsecure,
                size: 54,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    BidiText(
                      channel.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: colors.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          strings.live,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.accent,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                        if (channel.group != null) ...<Widget>[
                          const SizedBox(width: 8),
                          Flexible(
                            child: BidiText(
                              channel.group!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.overlay0,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (current != null) ...<Widget>[
            Text(
              strings.onNow,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            BidiText(
              current.title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            if (current.subTitle != null) ...<Widget>[
              const SizedBox(height: 4),
              BidiText(
                current.subTitle!,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.subtext0,
                ),
              ),
            ],
            const SizedBox(height: 8),
            BidiText(
              strings.formatRange(
                current.start,
                current.stop,
                use24HourTime: use24,
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.overlay0,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: current.progressAt(now),
                minHeight: 4,
                backgroundColor: colors.surface1,
              ),
            ),
            if (current.description != null) ...<Widget>[
              const SizedBox(height: 14),
              BidiText(
                current.description!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.subtext1,
                  height: 1.55,
                ),
              ),
            ],
            if (current.categories.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final category in current.categories)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surface0,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: BidiText(
                        category,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.subtext0,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ] else ...<Widget>[
            Text(
              strings.noProgrammeInfo,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.overlay0,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (next != null) ...<Widget>[
            const SizedBox(height: 22),
            Text(
              strings.upNext,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.overlay0,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: BidiText(
                    strings.formatTime(next.start, use24HourTime: use24),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      BidiText(
                        next.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.subtext1,
                        ),
                      ),
                      if (next.subTitle != null) ...<Widget>[
                        const SizedBox(height: 2),
                        BidiText(
                          next.subTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.overlay0,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(strings.playbackRetry),
              ),
              const SizedBox(width: 10),
              TextButton.icon(
                onPressed: onBrowse,
                icon: const Icon(Icons.live_tv_rounded),
                label: Text(strings.browseChannels),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
