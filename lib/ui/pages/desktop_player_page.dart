import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/bidi.dart';
import '../../core/network_image.dart';
import '../../core/playback.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../../player/mpv_client.dart';
import '../player_page.dart';
import '../widgets/channel_logo.dart';

/// Desktop playback surface.
///
/// The channel plays in the system mpv's own window, so the video decodes with
/// the GPU, can go properly fullscreen on Wayland and X11, and keeps mpv's
/// native controls (scroll wheel volume, keyboard shortcuts, OSC). This page
/// is the remote control and the programme information; it never draws a
/// second, software-rendered copy of the video.
class DesktopPlayerPage extends StatefulWidget {
  const DesktopPlayerPage({super.key, required this.channel});

  final Channel channel;

  @override
  State<DesktopPlayerPage> createState() => _DesktopPlayerPageState();
}

class _DesktopPlayerPageState extends State<DesktopPlayerPage> {
  static final bool _verbose = _resolveVerbose();

  static bool _resolveVerbose() {
    try {
      return (Platform.environment['MOJAC_MPV_LOG'] ?? '').trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  MpvClient? _player;
  StreamSubscription<MpvEvent>? _eventSubscription;
  StreamSubscription<String>? _logSubscription;

  /// Bumped on every start, so a retry that overlaps a slow launch cannot
  /// leave a second mpv window behind.
  int _generation = 0;

  bool _starting = true;
  bool _closed = false;
  bool _ended = false;
  bool _paused = false;
  bool _muted = false;
  bool _fullscreen = false;
  bool _buffering = false;
  double _volume = 100;
  String? _error;
  List<String> _logTail = const <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final generation = ++_generation;
    final allowInsecure =
        context.read<AppState>().activeSource?.allowInsecureCerts ?? false;
    await _stopPlayer();
    if (!mounted || generation != _generation) {
      return;
    }
    setState(() {
      _starting = true;
      _closed = false;
      _ended = false;
      _paused = false;
      _buffering = false;
      _error = null;
      _logTail = const <String>[];
    });

    final MpvClient player;
    try {
      player = await MpvClient.launch(
        uri: Uri.parse(widget.channel.url),
        title: 'Mojac — ${widget.channel.name}',
        userAgent: kMojacUserAgent,
        allowInsecure: allowInsecure,
        demuxerOptions: kMpvDemuxerLavfOptions,
        verbose: _verbose,
      );
    } catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _starting = false;
        _error = error.toString();
      });
      return;
    }

    if (!mounted || generation != _generation) {
      unawaited(player.quit());
      return;
    }

    _player = player;
    _eventSubscription = player.events.listen(_onEvent);
    if (_verbose) {
      _logSubscription = player.logs.listen(debugPrint);
    }
    unawaited(player.done.then((code) => _onExit(player, code)));
    for (final property in const <String>[
      'pause',
      'volume',
      'mute',
      'fullscreen',
      'paused-for-cache',
      'core-idle',
      'eof-reached',
    ]) {
      unawaited(player.observe(property));
    }
    setState(() => _starting = false);
  }

  Future<void> _stopPlayer() async {
    final player = _player;
    _player = null;
    final eventSubscription = _eventSubscription;
    final logSubscription = _logSubscription;
    _eventSubscription = null;
    _logSubscription = null;
    await eventSubscription?.cancel();
    await logSubscription?.cancel();
    if (player != null) {
      await player.quit();
    }
  }

  void _onEvent(MpvEvent event) {
    if (!mounted) {
      return;
    }
    final value = event.value;
    switch (event.name) {
      case 'property-change':
        switch (event.property) {
          case 'pause':
            setState(() => _paused = value == true);
          case 'volume':
            if (value is num) {
              setState(() => _volume = value.toDouble());
            }
          case 'mute':
            setState(() => _muted = value == true);
          case 'fullscreen':
            setState(() => _fullscreen = value == true);
          case 'paused-for-cache':
            setState(() => _buffering = value == true);
          case 'core-idle':
            setState(() {
              if (value == false) {
                _buffering = false;
              } else if (!_paused && !_ended) {
                _buffering = true;
              }
            });
          case 'eof-reached':
            setState(() {
              _ended = value == true;
              if (_ended) {
                _buffering = false;
              }
            });
        }
      case 'start-file':
        setState(() {
          _ended = false;
          _buffering = true;
          _error = null;
        });
      case 'file-loaded':
        setState(() {
          _ended = false;
          _buffering = false;
          _error = null;
        });
      case 'end-file':
        final reason = event.data['reason'];
        if (reason == 'eof') {
          setState(() => _ended = true);
        } else if (reason is String &&
            reason != 'quit' &&
            reason != 'stop' &&
            reason != 'redirect') {
          final detail = event.data['file_error'];
          unawaited(
            _failWith(
              'mpv ended the file: $reason'
              '${detail is String && detail.isNotEmpty ? ': $detail' : ''}',
            ),
          );
        }
    }
  }

  /// Shows [message] and closes the player window, so a failed stream does not
  /// leave an empty mpv window on screen. The log tail is copied first because
  /// quitting releases the client.
  Future<void> _failWith(String message) async {
    final tail = _player?.logTail ?? const <String>[];
    if (!mounted) {
      return;
    }
    setState(() {
      _buffering = false;
      _error = message;
      _logTail = tail;
    });
    await _stopPlayer();
  }

  void _onExit(MpvClient player, int code) {
    if (!mounted || !identical(_player, player)) {
      return;
    }
    setState(() {
      _closed = true;
      _buffering = false;
      if (code != 0 && _error == null) {
        _error = 'mpv exited with status $code';
      }
    });
  }

  Future<void> _setProperty(String name, Object value) async {
    final player = _player;
    if (player == null) {
      return;
    }
    try {
      await player.setProperty(name, value);
    } catch (error) {
      debugPrint('mpv could not set $name: $error');
    }
  }

  Future<void> _togglePause() => _setProperty('pause', !_paused);

  Future<void> _toggleMute() => _setProperty('mute', !_muted);

  Future<void> _toggleFullscreen() => _setProperty('fullscreen', !_fullscreen);

  Future<void> _setVolume(double value) async {
    final next = value.clamp(0.0, 100.0).toDouble();
    if (next != _volume) {
      setState(() => _volume = next);
    }
    await _setProperty('volume', next);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      unawaited(_togglePause());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      unawaited(_setVolume(_volume + 2));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      unawaited(_setVolume(_volume - 2));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      unawaited(_toggleFullscreen());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM) {
      unawaited(_toggleMute());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyQ || key == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _useBuiltInPlayer() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (context) => PlayerPage(channel: widget.channel),
      ),
    );
  }

  @override
  void dispose() {
    final player = _player;
    _player = null;
    _eventSubscription?.cancel();
    _logSubscription?.cancel();
    if (player != null) {
      unawaited(player.quit());
    }
    super.dispose();
  }

  String _statusText(AppStrings strings) {
    if (_error != null) {
      return strings.nativePlaybackFailed;
    }
    if (_starting) {
      return strings.nativePlaybackStarting;
    }
    if (_closed) {
      return strings.nativePlaybackClosed;
    }
    if (_ended) {
      return strings.nativePlaybackEnded;
    }
    if (_buffering) {
      return strings.nativePlaybackBuffering;
    }
    return _paused ? strings.pause : strings.live;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = context.strings;
    final colors = context.mojacColors;
    final allowInsecure = state.activeSource?.allowInsecureCerts ?? false;

    final remote = _buildRemote(context, strings, colors);
    final info = PlayerChannelInfo(
      channel: widget.channel,
      allowInsecure: allowInsecure,
      onRetry: () => unawaited(_start()),
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: <Widget>[
            ChannelLogo(
              channel: widget.channel,
              allowInsecure: allowInsecure,
              size: 30,
              radius: 8,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  BidiText(
                    widget.channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    '${strings.channel} ${widget.channel.displayNumber} · mpv',
                    style: TextStyle(color: colors.subtext0, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: strings.closePlayer,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Focus(
        autofocus: true,
        onKeyEvent: _handleKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 900) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(28),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: remote,
                        ),
                      ),
                    ),
                  ),
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
                Flexible(
                  flex: 4,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: remote,
                  ),
                ),
                Expanded(
                  flex: 5,
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

  Widget _buildRemote(
    BuildContext context,
    AppStrings strings,
    MojacColors colors,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.base,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.surface1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: colors.accentSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.play_circle_outline_rounded,
                  color: colors.accent,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      strings.nativePlaybackTitle,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _statusText(strings),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.subtext0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_error != null)
            _buildError(context, strings, colors)
          else if (_starting)
            _buildStarting(theme, strings, colors)
          else if (_closed || _ended)
            _buildStopped(context, strings, colors)
          else
            _buildControls(strings, colors, theme),
        ],
      ),
    );
  }

  Widget _buildStarting(
    ThemeData theme,
    AppStrings strings,
    MojacColors colors,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: const LinearProgressIndicator(minHeight: 4),
        ),
        const SizedBox(height: 16),
        Text(
          strings.nativePlaybackBody,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.subtext1,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildError(
    BuildContext context,
    AppStrings strings,
    MojacColors colors,
  ) {
    final theme = Theme.of(context);
    final logs = _logTail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          strings.nativePlaybackFailed,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        SelectableText(
          _error!,
          style: theme.textTheme.bodySmall?.copyWith(color: colors.subtext0),
        ),
        if (logs.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(maxHeight: 140),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.surface0,
              borderRadius: BorderRadius.circular(10),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                logs.join('\n'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.overlay0,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            FilledButton.icon(
              onPressed: () => unawaited(_start()),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(strings.playbackRetry),
            ),
            OutlinedButton.icon(
              onPressed: _useBuiltInPlayer,
              icon: const Icon(Icons.movie_rounded),
              label: Text(strings.useBuiltInPlayer),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStopped(
    BuildContext context,
    AppStrings strings,
    MojacColors colors,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          _closed ? strings.nativePlaybackClosed : strings.nativePlaybackEnded,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          strings.nativePlaybackBody,
          style: theme.textTheme.bodySmall?.copyWith(color: colors.subtext0),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            FilledButton.icon(
              onPressed: () => unawaited(_start()),
              icon: const Icon(Icons.replay_rounded),
              label: Text(strings.playAgain),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
              label: Text(strings.back),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildControls(
    AppStrings strings,
    MojacColors colors,
    ThemeData theme,
  ) {
    final muted = _muted || _volume <= 0.01;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          strings.nativePlaybackBody,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.subtext1,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _ControlButton(
              tooltip: _paused ? strings.play : strings.pause,
              icon: _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              primary: true,
              onPressed: () => unawaited(_togglePause()),
            ),
            const SizedBox(width: 14),
            _ControlButton(
              tooltip: _fullscreen
                  ? strings.exitFullScreen
                  : strings.fullScreen,
              icon: _fullscreen
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              onPressed: () => unawaited(_toggleFullscreen()),
            ),
            const SizedBox(width: 14),
            _ControlButton(
              tooltip: strings.playAgain,
              icon: Icons.replay_rounded,
              onPressed: () => unawaited(_start()),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            IconButton(
              tooltip: muted ? strings.unmute : strings.mute,
              onPressed: () => unawaited(_toggleMute()),
              icon: Icon(
                muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                color: colors.text,
              ),
            ),
            Expanded(
              child: Slider(
                value: _volume.clamp(0.0, 100.0).toDouble(),
                max: 100,
                onChanged: (value) => unawaited(_setVolume(value)),
              ),
            ),
            SizedBox(
              width: 46,
              child: Text(
                '${_volume.round()}%',
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.subtext0,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colors.surface0,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.keyboard_rounded, size: 18, color: colors.overlay0),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  strings.nativePlaybackShortcuts,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.subtext0,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    return Material(
      color: primary ? colors.accent : colors.surface1,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        iconSize: primary ? 30 : 22,
        padding: EdgeInsets.all(primary ? 14 : 11),
        color: primary ? colors.crust : colors.text,
        icon: Icon(icon),
      ),
    );
  }
}
