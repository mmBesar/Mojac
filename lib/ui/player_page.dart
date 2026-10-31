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
import '../data/app_state.dart';
import '../data/models.dart';
import '../l10n/strings.dart';
import 'widgets/channel_logo.dart';

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

  late final Player _player;
  late final VideoController _controller;
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<VideoParams>? _videoParamsSubscription;
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription<double>? _volumeSubscription;
  StreamSubscription<PlayerLog>? _logSubscription;
  (int, int)? _softwareVideoSize;
  Timer? _bufferingWatchdog;

  String? _error;
  bool _buffering = false;
  bool _fullscreen = false;

  /// Playback gestures: the left half of the video controls brightness and the
  /// right half controls volume. Brightness uses the Android application
  /// brightness API; on Linux an overlay dims the video instead.
  bool _brightnessSupported = false;
  double _brightness = 1;
  double _volume = 100;
  bool _adjustingBrightness = true;
  _OsdKind? _osdKind;
  double _osdValue = 0;
  Timer? _osdTimer;

  @override
  void initState() {
    super.initState();
    _player = Player(
      configuration: PlayerConfiguration(
        title: 'Mojac — ${widget.channel.name}',
        logLevel: _mpvLogLevel,
      ),
    );
    _controller = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        // media_kit 2.0.1 renders Linux video through an isolated EGL context
        // and an EGLImage texture. On Wayland/Mesa that texture can stall on
        // its first frame and take the whole UI down with it. The bundled
        // libmpv exposes MPV_RENDER_API_TYPE_SW, so use the CPU upload path
        // on Linux instead and keep the faster H/W path elsewhere.
        enableHardwareAcceleration: !Platform.isLinux,
        width: Platform.isLinux ? _softwareVideoWidth : null,
        height: Platform.isLinux ? _softwareVideoHeight : null,
      ),
    );
    _volume = _player.state.volume;
    if (Platform.isLinux) {
      _videoParamsSubscription = _player.stream.videoParams.listen(
        _resizeSoftwareVideo,
      );
    }

    _errorSubscription = _player.stream.error.listen((message) {
      if (!mounted || message.trim().isEmpty) {
        return;
      }
      setState(() => _error = message.trim());
    });
    _playingSubscription = _player.stream.playing.listen((playing) {
      if (playing && mounted && _error != null) {
        setState(() => _error = null);
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

  /// Keeps the Linux software texture at the stream's aspect ratio without
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
    final state = context.read<AppState>();
    final allowInsecure = state.activeSource?.allowInsecureCerts ?? false;
    setState(() {
      _error = null;
      _buffering = true;
    });
    try {
      // The Linux software video path avoids the EGLImage texture entirely,
      // so keep decoding on the CPU too and let libmpv convert directly.
      await _setMpvProperty('hwdec', Platform.isLinux ? 'no' : 'auto-safe');
      await _setMpvProperty('keep-open', 'yes');
      await _setMpvProperty('network-timeout', '60');
      await _setMpvProperty('tls-verify', allowInsecure ? 'no' : 'yes');
      await _setMpvProperty('demuxer-lavf-o', kMpvDemuxerLavfOptions);
      await _player.open(
        Media(
          widget.channel.url,
          httpHeaders: const <String, String>{
            'User-Agent': kMojacUserAgent,
          },
        ),
        play: true,
      );
      if (mounted) {
        setState(() => _buffering = false);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _buffering = false;
          _error = error.toString();
        });
      }
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

  @override
  void dispose() {
    _osdTimer?.cancel();
    _errorSubscription?.cancel();
    _playingSubscription?.cancel();
    _bufferingSubscription?.cancel();
    _volumeSubscription?.cancel();
    _videoParamsSubscription?.cancel();
    _logSubscription?.cancel();
    _bufferingWatchdog?.cancel();
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

    return Scaffold(
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
                    widget.channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    '${strings.channel} ${widget.channel.displayNumber}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                IconButton(
                  tooltip: strings.fullScreen,
                  onPressed: _toggleFullscreen,
                  icon: const Icon(Icons.fullscreen_rounded),
                ),
                const SizedBox(width: 4),
              ],
            ),
      body: SafeArea(
        top: _fullscreen,
        bottom: !_fullscreen,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final landscape = constraints.maxWidth > constraints.maxHeight;
            final wideDesktop = constraints.maxWidth >= 980;
            final sideBySide = landscape || wideDesktop;

            final video = _VideoPane(
              player: _player,
              controller: _controller,
              channel: widget.channel,
              error: _error,
              buffering: _buffering,
              strings: strings,
              onRetry: _open,
              fullscreen: _fullscreen,
              onToggleFullscreen: _toggleFullscreen,
              onDragStart: _startGesture,
              onDragUpdate: _updateGesture,
              dimOpacity: _brightnessSupported ? 0.0 : (1 - _brightness) * 0.6,
              osd: _osdKind == null
                  ? null
                  : _GestureOsd(
                      kind: _osdKind!,
                      value: _osdValue,
                      strings: strings,
                    ),
            );
            final info = PlayerChannelInfo(
              channel: widget.channel,
              allowInsecure: allowInsecure,
              onRetry: _open,
            );

            if (_fullscreen) {
              return Stack(
                children: <Widget>[
                  Positioned.fill(child: video),
                  PositionedDirectional(
                    top: 12,
                    end: 12,
                    child: _OverlayButton(
                      tooltip: strings.exitFullScreen,
                      icon: Icons.fullscreen_exit_rounded,
                      onPressed: _toggleFullscreen,
                    ),
                  ),
                ],
              );
            }

            if (sideBySide) {
              // Landscape phones get the same side panel as wide desktops, so
              // the video stays fully visible instead of pushing the channel
              // information below the fold.
              final panelWidth = wideDesktop
                  ? 380.0
                  : (constraints.maxWidth * 0.4)
                      .clamp(260.0, 380.0)
                      .toDouble();
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
        ),
      ),
    );
  }
}

class _VideoPane extends StatelessWidget {
  const _VideoPane({
    required this.player,
    required this.controller,
    required this.channel,
    required this.error,
    required this.buffering,
    required this.strings,
    required this.onRetry,
    required this.fullscreen,
    required this.onToggleFullscreen,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.dimOpacity,
    required this.osd,
  });

  final Player player;
  final VideoController controller;
  final Channel channel;
  final String? error;
  final bool buffering;
  final AppStrings strings;
  final VoidCallback onRetry;
  final bool fullscreen;
  final VoidCallback onToggleFullscreen;
  final void Function(Offset position, double width) onDragStart;
  final void Function(DragUpdateDetails details, double height) onDragUpdate;
  final double dimOpacity;
  final Widget? osd;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (details) =>
                      onDragStart(details.localPosition, constraints.maxWidth),
                  onVerticalDragUpdate: (details) =>
                      onDragUpdate(details, constraints.maxHeight),
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Video(
                        controller: controller,
                        controls: NoVideoControls,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                );
              },
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
          if (buffering)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: LinearProgressIndicator(minHeight: 2),
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
          PositionedDirectional(
            bottom: 8,
            start: 8,
            child: Row(
              children: <Widget>[
                StreamBuilder<bool>(
                  stream: player.stream.playing,
                  initialData: player.state.playing,
                  builder: (context, snapshot) {
                    final playing = snapshot.data ?? false;
                    return _OverlayButton(
                      tooltip: playing ? strings.pause : strings.play,
                      icon: playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      onPressed: player.playOrPause,
                    );
                  },
                ),
                const SizedBox(width: 6),
                StreamBuilder<double>(
                  stream: player.stream.volume,
                  initialData: player.state.volume,
                  builder: (context, snapshot) {
                    final volume = snapshot.data ?? player.state.volume;
                    final muted = volume <= 0.01;
                    return _OverlayButton(
                      tooltip: muted ? strings.unmute : strings.mute,
                      icon: muted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      onPressed: () {
                        player.setVolume(muted ? 100 : 0);
                      },
                    );
                  },
                ),
              ],
            ),
          ),
          if (!fullscreen)
            PositionedDirectional(
              bottom: 8,
              end: 8,
              child: _OverlayButton(
                tooltip: strings.fullScreen,
                icon: Icons.fullscreen_rounded,
                onPressed: onToggleFullscreen,
              ),
            ),
          if (osd != null) Positioned.fill(child: osd!),
        ],
      ),
    );
  }
}

enum _OsdKind { brightness, volume }

class _GestureOsd extends StatelessWidget {
  const _GestureOsd({
    required this.kind,
    required this.value,
    required this.strings,
  });

  final _OsdKind kind;
  final double value;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final brightness = kind == _OsdKind.brightness;
    final percent = (value * 100).round();
    return IgnorePointer(
      child: Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.68),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    brightness
                        ? Icons.brightness_6_rounded
                        : (percent == 0
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded),
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    brightness ? strings.brightness : strings.volume,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: 156,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 5,
                    backgroundColor: Colors.white.withValues(alpha: 0.22),
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$percent%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.5),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
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
  });

  final Channel channel;
  final bool allowInsecure;
  final VoidCallback onRetry;

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
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(strings.playbackRetry),
          ),
        ],
      ),
    );
  }
}
