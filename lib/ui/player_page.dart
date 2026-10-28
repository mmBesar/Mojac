import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/bidi.dart';
import '../core/network_image.dart';
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
  late final Player _player;
  late final VideoController _controller;
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _bufferingSubscription;

  String? _error;
  bool _buffering = false;
  bool _fullscreen = false;

  @override
  void initState() {
    super.initState();
    _player = Player(
      configuration: PlayerConfiguration(title: 'Mojac — ${widget.channel.name}'),
    );
    _controller = VideoController(_player);

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
    });

    unawaited(
      WakelockPlus.enable().catchError((Object error) {
        debugPrint('Could not enable the wakelock: $error');
      }),
    );
    unawaited(_open());
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
      await _setMpvProperty('hwdec', 'auto-safe');
      await _setMpvProperty('keep-open', 'yes');
      await _setMpvProperty('network-timeout', '30');
      await _setMpvProperty('tls-verify', allowInsecure ? 'no' : 'yes');
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

  @override
  void dispose() {
    _errorSubscription?.cancel();
    _playingSubscription?.cancel();
    _bufferingSubscription?.cancel();
    unawaited(
      WakelockPlus.disable().catchError((Object error) {
        debugPrint('Could not disable the wakelock: $error');
      }),
    );
    unawaited(_player.dispose());
    unawaited(_setSystemUi(immersive: false));
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
            final wide = constraints.maxWidth >= 980;
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
            );
            final info = _ChannelInfo(
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

            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(child: video),
                  Container(
                    width: 380,
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

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
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
        ],
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

class _ChannelInfo extends StatelessWidget {
  const _ChannelInfo({
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
              children: <Widget>[
                BidiText(
                  strings.formatTime(next.start, use24HourTime: use24),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: BidiText(
                    next.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.subtext1,
                    ),
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
