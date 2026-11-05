import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../player_launcher.dart';
import '../widgets/channel_logo.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_banner.dart';
import '../widgets/group_filter_bar.dart';
import '../widgets/programme_poster.dart';
import '../widgets/programme_sheet.dart';
import '../widgets/warnings_panel.dart';
import 'channel_guide_page.dart';

const double _channelWidth = 84;
const double _rowHeight = 110;
const double _headerHeight = 50;

/// The old guide was locked to 4-12 px/minute, which made ErsatzTV's five to
/// eight minute programmes unreadable. Two px/minute fits a whole week on a
/// desktop, while 180 px/minute turns a six-minute show into 1,080 px of
/// readable block. The guide opens 35% denser than the historical 4 px so
/// short programmes get a visible title without the user touching the slider.
const double _minPixelsPerMinute = 2;
const double _defaultPixelsPerMinute = 5.4;
const double _maxPixelsPerMinute = 180;

/// Minimum pixel gaps for timeline ticks. Labels need more room than grid
/// lines, so they choose their interval independently.
const double _labelSpacing = 64;
const double _gridSpacing = 56;

/// Labels are only built around the visible slice of the header. A 168-hour
/// window at deep zoom is millions of pixels wide, and building a Text for
/// every five-minute mark would create thousands of widgets nothing can see.
const double _labelOverscan = 700;

/// Chooses the finest tick interval (from [candidates]) that keeps at least
/// [spacing] pixels between marks.
int _tickMinutes(double pixelsPerMinute, double spacing) {
  const candidates = <int>[5, 10, 15, 30, 60, 120, 360];
  for (final minutes in candidates) {
    if (minutes * pixelsPerMinute >= spacing) {
      return minutes;
    }
  }
  return candidates.last;
}

/// Each row carries the channel name in a thin strip above its programmes.
/// The strip is pinned to the left of the visible timeline (it does not scroll
/// with the schedule), so the name has room to breathe while the logo cell
/// stays narrow.
const double _rowLabelHeight = 18;

/// Programme blocks keep their previous 82px height: the extra row height is
/// spent on the name strip instead of shrinking the programme text.
const double _programmeTop = _rowLabelHeight + 5;
const double _programmeHeight = _rowHeight - _programmeTop - 5;

/// Rows are built lazily around the vertical viewport. Keeping a few rows of
/// overscan above and below avoids blank strips during a fast fling without
/// laying out a whole 5,000-channel playlist on every frame.
const int _rowOverscan = 8;

class GuidePage extends StatefulWidget {
  const GuidePage({super.key, required this.onAddSource});

  final VoidCallback onAddSource;

  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage> {
  final ScrollController _bodyHorizontal = ScrollController();
  final ScrollController _headerHorizontal = ScrollController();
  final ScrollController _vertical = ScrollController();

  /// Current horizontal offset, exposed to the pinned row labels so they stay
  /// at the left edge of the visible timeline while it scrolls.
  final ValueNotifier<double> _horizontalOffset = ValueNotifier<double>(0);

  late DateTime _windowStart;

  /// Timeline density. The guide opens at 5.4 px/minute (the historical 4 px
  /// plus 35%) and can zoom from a whole week down to very short programmes.
  double _pixelsPerMinute = _defaultPixelsPerMinute;

  int get _windowMinutes => context.read<AppState>().settings.guideHours * 60;

  double get _timelineWidth => _windowMinutes * _pixelsPerMinute;

  /// Horizontal viewport in timeline pixels. Programme posters are only
  /// requested for blocks near the visible window, so a long grid does not
  /// fire hundreds of image downloads for rows the user cannot see.
  double _visibleStart = 0;
  double _visibleEnd = 900;

  /// Vertical viewport in row pixels; posters are limited to visible rows too.
  double _rowStart = 0;
  double _rowEnd = 900;

  /// Guards the one-frame window rollover when the app resumes after enough
  /// time has passed for "now" to fall outside the displayed schedule.
  bool _windowSyncScheduled = false;

  /// Start rolling the window forward while this much of the schedule is still
  /// ahead, so the guide never runs out of future programmes at its right
  /// edge. A twelve-hour window therefore rolls every ten and a half hours.
  static const Duration _rollAhead = Duration(minutes: 90);

  @override
  void initState() {
    super.initState();
    _windowStart = _floorToHalfHour(DateTime.now())
        .subtract(const Duration(minutes: 30));
    _bodyHorizontal
      ..addListener(_syncHeader)
      ..addListener(_syncViewport);
    _vertical.addListener(_syncViewport);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncViewport(force: true);
    });
  }

  @override
  void dispose() {
    _bodyHorizontal
      ..removeListener(_syncHeader)
      ..removeListener(_syncViewport)
      ..dispose();
    _vertical.removeListener(_syncViewport);
    _headerHorizontal.dispose();
    _vertical.dispose();
    _horizontalOffset.dispose();
    super.dispose();
  }

  DateTime get _windowEnd =>
      _windowStart.add(Duration(minutes: _windowMinutes));

  void _syncHeader() {
    if (!_headerHorizontal.hasClients || !_bodyHorizontal.hasClients) {
      return;
    }
    final offset = _bodyHorizontal.offset;
    if (_horizontalOffset.value != offset) {
      _horizontalOffset.value = offset;
    }
    final target = offset.clamp(
      0.0,
      _headerHorizontal.position.maxScrollExtent,
    );
    if ((_headerHorizontal.offset - target).abs() > 0.5) {
      _headerHorizontal.jumpTo(target);
    }
  }

  void _syncViewport({bool force = false}) {
    final horizontal = _bodyHorizontal.hasClients;
    final vertical = _vertical.hasClients;
    if (!horizontal && !vertical) {
      return;
    }

    var hStart = _visibleStart;
    var hEnd = _visibleEnd;
    var vStart = _rowStart;
    var vEnd = _rowEnd;
    if (horizontal) {
      final position = _bodyHorizontal.position;
      hStart = position.pixels;
      hEnd = hStart + position.viewportDimension;
    }
    if (vertical) {
      final position = _vertical.position;
      vStart = position.pixels;
      vEnd = vStart + position.viewportDimension;
    }

    if (!force &&
        (hStart - _visibleStart).abs() < 600 &&
        (hEnd - _visibleEnd).abs() < 600 &&
        (vStart - _rowStart).abs() < 600 &&
        (vEnd - _rowEnd).abs() < 600) {
      return;
    }
    setState(() {
      _visibleStart = hStart;
      _visibleEnd = hEnd;
      _rowStart = vStart;
      _rowEnd = vEnd;
    });
  }

  /// Keeps the guide supplied with future programmes. The window rolls forward
  /// once "now" reaches the last [_rollAhead] of the schedule, and it also
  /// recovers when the app resumes outside the displayed window, so the grid
  /// never presents empty rows at its leading edge.
  void _ensureWindowContainsNow(DateTime now) {
    if (_windowSyncScheduled) {
      return;
    }
    final rollAt = _windowEnd.subtract(_rollAhead);
    if (!now.isBefore(_windowStart) && now.isBefore(rollAt)) {
      return;
    }
    _windowSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _windowSyncScheduled = false;
      if (!mounted) {
        return;
      }
      final current = context.read<AppState>().now;
      final nextRollAt = _windowEnd.subtract(_rollAhead);
      if (current.isBefore(_windowStart) || !current.isBefore(nextRollAt)) {
        _jumpToNow();
      }
    });
  }

  void _jumpToNow() {
    final now = context.read<AppState>().now;
    final start = _floorToHalfHour(now).subtract(const Duration(minutes: 30));
    setState(() => _windowStart = start);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_bodyHorizontal.hasClients) {
        return;
      }
      final offset =
          now.difference(start).inSeconds / 60 * _pixelsPerMinute;
      final target = (offset - _bodyHorizontal.position.viewportDimension / 2)
          .clamp(0.0, _bodyHorizontal.position.maxScrollExtent);
      _bodyHorizontal.animateTo(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// Ctrl/⌘ + scroll changes the timeline scale. The event is claimed in the
  /// pointer-signal resolver so the grid does not also scroll sideways.
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed && !keyboard.isMetaPressed) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver
        .register(event, (PointerSignalEvent _) {});
    final delta = event.scrollDelta.dy;
    if (delta == 0) {
      return;
    }
    _setZoom(_pixelsPerMinute * (delta > 0 ? 0.88 : 1.14));
  }

  /// Changes the timeline scale without losing the time the user is looking
  /// at: the minute under the middle of the viewport stays under the middle.
  void _setZoom(double value) {
    final zoom = value.clamp(_minPixelsPerMinute, _maxPixelsPerMinute);
    if ((zoom - _pixelsPerMinute).abs() < 0.01) {
      return;
    }
    var centreMinute = (DateTime.now().difference(_windowStart).inSeconds / 60)
        .clamp(0.0, _windowMinutes.toDouble());
    if (_bodyHorizontal.hasClients) {
      final position = _bodyHorizontal.position;
      centreMinute =
          (position.pixels + position.viewportDimension / 2) /
              _pixelsPerMinute;
    }
    setState(() => _pixelsPerMinute = zoom);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_bodyHorizontal.hasClients) {
        return;
      }
      final position = _bodyHorizontal.position;
      final target = centreMinute * zoom - position.viewportDimension / 2;
      _bodyHorizontal.jumpTo(
        target.clamp(0.0, position.maxScrollExtent),
      );
      _syncViewport(force: true);
    });
  }

  void _openPlayer(Channel channel) {
    openChannelPlayer(context, channel);
  }

  void _openGuide(Channel channel) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ChannelGuidePage(channel: channel),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = context.strings;

    if (state.sources.isEmpty) {
      return EmptyState(
        icon: Icons.calendar_month_rounded,
        title: strings.guideNoChannels,
        body: strings.noSourcesBody,
        actionLabel: strings.addSource,
        onAction: widget.onAddSource,
      );
    }

    if (!state.hasContent && state.isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 16),
            Text(
              strings.refreshing,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.mojacColors.subtext0,
                  ),
            ),
          ],
        ),
      );
    }

    if (!state.hasContent && state.error != null) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: strings.errorTitle,
        body: state.error!,
        actionLabel: strings.retry,
        onAction: state.refresh,
        secondaryLabel: strings.sources,
        onSecondary: widget.onAddSource,
      );
    }

    if (state.channels.isEmpty || state.epg.isEmpty) {
      return EmptyState(
        icon: Icons.event_busy_rounded,
        title: strings.guideEmptyTitle,
        body: strings.guideEmptyBody,
        actionLabel: strings.refresh,
        onAction: state.refresh,
        secondaryLabel: strings.sources,
        onSecondary: widget.onAddSource,
      );
    }

    final groups = channelGroups(state.channels);
    final group = groups.contains(state.settings.groupFilter)
        ? state.settings.groupFilter
        : null;
    final channels = group == null
        ? state.channels
        : state.channels
            .where((channel) => channel.group == group)
            .toList(growable: false);
    if (channels.isEmpty) {
      return Column(
        children: <Widget>[
          GroupFilterBar(
            groups: groups,
            selected: group,
            onChanged: (value) => unawaited(state.setGroupFilter(value)),
          ),
          Expanded(
            child: EmptyState(
              icon: Icons.filter_alt_off_rounded,
              title: strings.noGroupChannels,
              body: strings.guideEmptyBody,
              actionLabel: strings.allGroups,
              onAction: () => unawaited(state.setGroupFilter(null)),
            ),
          ),
        ],
      );
    }
    final allowInsecure = state.activeSource?.allowInsecureCerts ?? false;
    final uiDirection = Directionality.of(context);
    final viewportWidth = math.max(1.0, _visibleEnd - _visibleStart);
    final now = state.now;
    _ensureWindowContainsNow(now);
    final nowOffset = now.difference(_windowStart).inSeconds / 60 *
        _pixelsPerMinute;
    final showNow = nowOffset >= 0 && nowOffset <= _timelineWidth;
    final lastRow = math.min(
      channels.length - 1,
      (_rowEnd / _rowHeight).ceil() + _rowOverscan,
    );
    // Clamp against lastRow as well: a refresh can replace a long playlist
    // with a shorter one while the user is scrolled far down, and an
    // unclamped firstRow would create spacers larger than the content.
    final firstRow = math.max(
      0,
      math.min(
        lastRow,
        (_rowStart / _rowHeight).floor() - _rowOverscan,
      ),
    );

    final grid = Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    BidiText(
                      strings.formatDate(_windowStart),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    BidiText(
                      '${strings.formatTime(
                        _windowStart,
                        use24HourTime: state.settings.use24HourTime,
                      )} – ${strings.formatTime(
                        _windowEnd,
                        use24HourTime: state.settings.use24HourTime,
                      )}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.mojacColors.subtext0,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _TimelineZoom(
                value: _pixelsPerMinute,
                min: _minPixelsPerMinute,
                max: _maxPixelsPerMinute,
                onChanged: _setZoom,
                onStep: (direction) => _setZoom(
                  direction > 0
                      ? _pixelsPerMinute * 1.35
                      : _pixelsPerMinute / 1.35,
                ),
              ),
              const SizedBox(width: 2),
              IconButton(
                tooltip: strings.guideNow,
                onPressed: _jumpToNow,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.my_location_rounded, size: 20),
              ),
            ],
          ),
        ),
        GroupFilterBar(
          groups: groups,
          selected: group,
          onChanged: (value) => unawaited(state.setGroupFilter(value)),
        ),
        if (state.isLoading) const LinearProgressIndicator(minHeight: 2),
        if (state.warnings.isNotEmpty)
          WarningsPanel(warnings: state.warnings),
        if (state.error != null && state.hasContent)
          ErrorBanner(
            message: state.error!,
            retryLabel: strings.retry,
            onRetry: state.refresh,
          ),
        Expanded(
          child: Column(
            children: <Widget>[
              SizedBox(
                height: _headerHeight,
                child: Row(
                  children: <Widget>[
                    _CornerCell(
                      child: Icon(
                        Icons.tv_rounded,
                        size: 18,
                        color: context.mojacColors.overlay0,
                      ),
                    ),
                    Expanded(
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: SingleChildScrollView(
                          controller: _headerHorizontal,
                          scrollDirection: Axis.horizontal,
                          physics: const NeverScrollableScrollPhysics(),
                          child: Listener(
                            onPointerSignal: _handlePointerSignal,
                            child: SizedBox(
                              width: _timelineWidth,
                              height: _headerHeight,
                              child: _TimeHeader(
                                start: _windowStart,
                                windowMinutes: _windowMinutes,
                                pixelsPerMinute: _pixelsPerMinute,
                                use24HourTime: state.settings.use24HourTime,
                                nowOffset: showNow ? nowOffset : null,
                                visibleStart: _visibleStart - _labelOverscan,
                                visibleEnd: _visibleEnd + _labelOverscan,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _vertical,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: _channelWidth,
                        child: Column(
                          children: <Widget>[
                            SizedBox(height: firstRow * _rowHeight),
                            for (var index = firstRow;
                                index <= lastRow;
                                index++)
                              _ChannelCell(
                                channel: channels[index],
                                allowInsecure: allowInsecure,
                                onPlay: () => _openPlayer(channels[index]),
                                onGuide: () => _openGuide(channels[index]),
                              ),
                            SizedBox(
                              height:
                                  (channels.length - 1 - lastRow) * _rowHeight,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: SingleChildScrollView(
                            controller: _bodyHorizontal,
                            scrollDirection: Axis.horizontal,
                            child: Listener(
                              onPointerSignal: _handlePointerSignal,
                              child: SizedBox(
                                width: _timelineWidth,
                                height: channels.length * _rowHeight,
                                child: Stack(
                                  children: <Widget>[
                                    Positioned.fill(
                                      child: CustomPaint(
                                        painter: _GridPainter(
                                          start: _windowStart,
                                          windowMinutes: _windowMinutes,
                                          pixelsPerMinute: _pixelsPerMinute,
                                          gridColor:
                                              context.mojacColors.surface1,
                                          hourColor:
                                              context.mojacColors.overlay0
                                                  .withValues(alpha: 0.5),
                                        ),
                                      ),
                                    ),
                                    Column(
                                      children: <Widget>[
                                        SizedBox(height: firstRow * _rowHeight),
                                        for (var index = firstRow;
                                            index <= lastRow;
                                            index++)
                                          _GuideRow(
                                            channel: channels[index],
                                            epg: state.epg,
                                            windowStart: _windowStart,
                                            windowEnd: _windowEnd,
                                            now: now,
                                            pixelsPerMinute: _pixelsPerMinute,
                                            use24HourTime:
                                                state.settings.use24HourTime,
                                            allowInsecure: allowInsecure,
                                            even: index.isEven,
                                            horizontalOffset: _horizontalOffset,
                                            viewportWidth: viewportWidth,
                                            uiDirection: uiDirection,
                                            onWatch: () => _openPlayer(
                                              channels[index],
                                            ),
                                            onGuide: () => _openGuide(
                                              channels[index],
                                            ),
                                          ),
                                        SizedBox(
                                          height: (channels.length -
                                                  1 -
                                                  lastRow) *
                                              _rowHeight,
                                        ),
                                      ],
                                    ),
                                    if (showNow)
                                      Positioned(
                                        left: nowOffset,
                                        top: 0,
                                        bottom: 0,
                                        width: 2,
                                        child: IgnorePointer(
                                          child: Container(
                                            color: context.mojacColors.accent,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return grid;
  }
}

DateTime _floorToHalfHour(DateTime value) {
  final minute = value.minute < 30 ? 0 : 30;
  return DateTime(value.year, value.month, value.day, value.hour, minute);
}

/// Compact density control for the timeline. The slider trades how much of the
/// schedule is visible against how much room each programme gets for its
/// title; the two buttons give touch users a precise step without dragging a
/// tiny slider thumb.
class _TimelineZoom extends StatelessWidget {
  const _TimelineZoom({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onStep,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  /// Positive zooms in, negative zooms out.
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    final strings = context.strings;
    // Zoom is logarithmic so the slider gives the 2-20 px/minute range (where
    // most short-programme work happens) as much travel as the deep end.
    final span = math.log(max / min);
    final fraction =
        span == 0 ? 0.0 : (math.log(value / min) / span).clamp(0.0, 1.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _ZoomButton(
          icon: Icons.remove_rounded,
          tooltip: strings.zoomOut,
          enabled: value > min + 0.01,
          onTap: () => onStep(-1),
        ),
        Semantics(
          label: strings.timelineZoom,
          child: Tooltip(
            message: strings.timelineZoom,
            child: SizedBox(
              width: 86,
              height: 32,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 12),
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  activeTrackColor: colors.accent,
                  inactiveTrackColor: colors.surface1,
                  thumbColor: colors.accent,
                  overlayColor: colors.accent.withValues(alpha: 0.16),
                ),
                child: Slider(
                  value: fraction,
                  min: 0,
                  max: 1,
                  divisions: 100,
                  semanticFormatterCallback: (_) =>
                      '${value.toStringAsFixed(1)} px/min',
                  onChanged: (position) =>
                      onChanged(min * math.pow(max / min, position).toDouble()),
                ),
              ),
            ),
          ),
        ),
        _ZoomButton(
          icon: Icons.add_rounded,
          tooltip: strings.zoomIn,
          enabled: value < max - 0.01,
          onTap: () => onStep(1),
        ),
      ],
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(
            icon,
            size: 17,
            color: enabled ? colors.subtext1 : colors.surface2,
          ),
        ),
      ),
    );
  }
}

class _CornerCell extends StatelessWidget {
  const _CornerCell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _channelWidth,
      height: _headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: AlignmentDirectional.center,
      decoration: BoxDecoration(
        color: context.mojacColors.mantle,
        border: BorderDirectional(
          bottom: BorderSide(color: context.mojacColors.surface1),
          end: BorderSide(color: context.mojacColors.surface1),
        ),
      ),
      child: child,
    );
  }
}

class _TimeHeader extends StatelessWidget {
  const _TimeHeader({
    required this.start,
    required this.windowMinutes,
    required this.pixelsPerMinute,
    required this.use24HourTime,
    required this.visibleStart,
    required this.visibleEnd,
    this.nowOffset,
  });

  final DateTime start;
  final int windowMinutes;
  final double pixelsPerMinute;
  final bool use24HourTime;

  /// Timeline slice to build labels for, in timeline pixels.
  final double visibleStart;
  final double visibleEnd;
  final double? nowOffset;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    final strings = context.strings;
    final labels = <Widget>[];
    // Pick the finest interval whose labels still have room. Deep zoom gets
    // five-minute labels for short episodes, while a two px/minute week view
    // keeps hourly labels.
    final step = _tickMinutes(pixelsPerMinute, _labelSpacing);
    for (var minute = 0; minute <= windowMinutes; minute += step) {
      final x = minute * pixelsPerMinute + 6;
      if (x < visibleStart || x > visibleEnd) {
        continue;
      }
      final time = start.add(Duration(minutes: minute));
      final onHour = time.minute == 0;
      labels.add(
        Positioned(
          left: x,
          top: 0,
          bottom: 0,
          child: Center(
            child: Text(
              onHour
                  ? strings.formatHour(time, use24HourTime: use24HourTime)
                  : strings.formatTime(time, use24HourTime: use24HourTime),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: onHour ? colors.subtext0 : colors.overlay0,
                    fontWeight: onHour ? FontWeight.w600 : FontWeight.w500,
                    fontSize: onHour ? null : 9,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.mantle,
        border: Border(
          bottom: BorderSide(color: colors.surface1),
        ),
      ),
      child: Stack(
        children: <Widget>[
          ...labels,
          if (nowOffset != null)
            Positioned(
              left: nowOffset! - 4,
              top: 8,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colors.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter({
    required this.start,
    required this.windowMinutes,
    required this.pixelsPerMinute,
    required this.gridColor,
    required this.hourColor,
  });

  final DateTime start;
  final int windowMinutes;
  final double pixelsPerMinute;
  final Color gridColor;
  final Color hourColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeWidth = 1;
    // Pick the finest grid whose lines do not visually merge. Deep zoom adds
    // five-minute lines, which makes a six-minute ErsatzTV episode readable;
    // a week view falls back to half-hour lines.
    final step = _tickMinutes(pixelsPerMinute, _gridSpacing);
    for (var minute = 0; minute <= windowMinutes; minute += step) {
      final x = minute * pixelsPerMinute;
      final onHour = start.add(Duration(minutes: minute)).minute == 0;
      if (onHour) {
        paint.color = hourColor;
      } else if (minute % 60 == 0) {
        paint.color = hourColor.withValues(alpha: 0.35);
      } else if (minute % 30 == 0) {
        paint.color = gridColor;
      } else {
        paint.color = gridColor.withValues(alpha: 0.45);
      }
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) {
    return oldDelegate.start != start ||
        oldDelegate.windowMinutes != windowMinutes ||
        oldDelegate.pixelsPerMinute != pixelsPerMinute ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.hourColor != hourColor;
  }
}

class _ChannelCell extends StatelessWidget {
  const _ChannelCell({
    required this.channel,
    required this.allowInsecure,
    required this.onPlay,
    required this.onGuide,
  });

  final Channel channel;
  final bool allowInsecure;
  final VoidCallback onPlay;
  final VoidCallback onGuide;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    return Container(
      height: _rowHeight,
      decoration: BoxDecoration(
        color: colors.base,
        border: BorderDirectional(
          bottom: BorderSide(color: colors.surface1),
          end: BorderSide(color: colors.surface1),
        ),
      ),
      alignment: Alignment.center,
      // The cell is logo-only now: the channel name lives in the timeline
      // strip, so the artwork gets the whole column. Tap starts playback and
      // long-press opens the channel's own schedule.
      child: Tooltip(
        message: channel.name,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPlay,
          onLongPress: onGuide,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                children: <Widget>[
                  ChannelLogo(
                    channel: channel,
                    allowInsecure: allowInsecure,
                    size: 64,
                    radius: 14,
                  ),
                  if (channel.number.isNotEmpty)
                    PositionedDirectional(
                      start: 2,
                      bottom: 2,
                      child: ChannelNumberBadge(number: channel.displayNumber),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GuideRow extends StatelessWidget {
  const _GuideRow({
    required this.channel,
    required this.epg,
    required this.windowStart,
    required this.windowEnd,
    required this.now,
    required this.pixelsPerMinute,
    required this.use24HourTime,
    required this.allowInsecure,
    required this.even,
    required this.horizontalOffset,
    required this.viewportWidth,
    required this.uiDirection,
    required this.onWatch,
    required this.onGuide,
  });

  final Channel channel;
  final EpgData epg;
  final DateTime windowStart;
  final DateTime windowEnd;
  final DateTime now;
  final double pixelsPerMinute;
  final bool use24HourTime;
  final bool allowInsecure;
  final bool even;
  final ValueListenable<double> horizontalOffset;
  final double viewportWidth;
  final TextDirection uiDirection;
  final VoidCallback onWatch;
  final VoidCallback onGuide;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    final strings = context.strings;
    final programmes = epg.forWindow(channel, windowStart, windowEnd);

    return Container(
      height: _rowHeight,
      decoration: BoxDecoration(
        color: even ? colors.base : colors.mantle.withValues(alpha: 0.35),
        border: Border(bottom: BorderSide(color: colors.surface1)),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: <Widget>[
          if (programmes.isEmpty)
            PositionedDirectional(
              start: 10,
              top: _programmeTop,
              bottom: 0,
              child: Center(
                child: Text(
                  strings.noProgrammeInfo,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.overlay0,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ),
            ),
          for (final programme in programmes)
            _positionedBlock(context, programme),
          _pinnedLabel(context),
        ],
      ),
    );
  }

  /// The channel name, pinned to the left of the visible timeline so it stays
  /// readable while the schedule scrolls horizontally. It lives in the strip
  /// above the programme blocks, so it never covers programme text or shifts
  /// the timeline alignment.
  Widget _pinnedLabel(BuildContext context) {
    final colors = context.mojacColors;
    final theme = Theme.of(context);
    return ValueListenableBuilder<double>(
      valueListenable: horizontalOffset,
      builder: (context, offset, _) {
        return Positioned(
          left: offset + 4,
          top: 1,
          height: _rowLabelHeight - 2,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: MediaQuery.withClampedTextScaling(
              // The name strip has a fixed height so the programme grid keeps
              // its rhythm; very large accessibility text scales must not
              // overflow it.
              maxScaleFactor: 1.1,
              child: Material(
                color: colors.mantle,
                borderRadius: BorderRadius.circular(5),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onGuide,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.surface1),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (channel.number.isNotEmpty) ...<Widget>[
                          Text(
                            channel.displayNumber,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.overlay0,
                              fontSize: 9,
                              height: 1.1,
                              fontFeatures: const <FontFeature>[
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: BidiText(
                            channel.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.subtext1,
                              fontSize: 10,
                              height: 1.1,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _positionedBlock(BuildContext context, Programme programme) {
    final start = programme.start.isBefore(windowStart)
        ? windowStart
        : programme.start;
    final stop =
        programme.stop.isAfter(windowEnd) ? windowEnd : programme.stop;
    final left =
        math.max(0.0, start.difference(windowStart).inSeconds / 60) *
            pixelsPerMinute;
    final width = math.max(
      0.0,
      stop.difference(start).inSeconds / 60 * pixelsPerMinute - 2,
    );
    if (width < 1) {
      return const SizedBox.shrink();
    }
    // Every programme in a built row is laid out. Horizontal culling used to
    // drop blocks outside the last known viewport, which left whole rows
    // blank when that viewport was stale (for example when the guide was
    // first shown after being built offstage). Only artwork is viewport-gated.
    final live = programme.isLiveAt(now);
    return Positioned(
      left: left,
      top: _programmeTop,
      width: width,
      height: _programmeHeight,
      child: _ProgrammeBlock(
        programme: programme,
        live: live,
        allowInsecure: allowInsecure,
        use24HourTime: use24HourTime,
        left: left,
        width: width,
        horizontalOffset: horizontalOffset,
        viewportWidth: viewportWidth,
        uiDirection: uiDirection,
        onTap: () => showProgrammeSheet(
          context,
          channel: channel,
          programme: programme,
          allowInsecure: allowInsecure,
          onWatch: onWatch,
        ),
      ),
    );
  }
}

/// Slides a block's content to the visible side of the viewport as the block
/// scrolls under the fixed edge. Only edge blocks rebuild while scrolling;
/// fully visible blocks keep their inset at zero and do no work.
class _StickyInset extends StatefulWidget {
  const _StickyInset({
    required this.offset,
    required this.left,
    required this.width,
    required this.viewportWidth,
    required this.direction,
    required this.child,
  });

  final ValueListenable<double> offset;
  final double left;
  final double width;
  final double viewportWidth;
  final TextDirection direction;
  final Widget child;

  @override
  State<_StickyInset> createState() => _StickyInsetState();
}

class _StickyInsetState extends State<_StickyInset> {
  late double _inset = _compute();

  double _compute() {
    final start = widget.offset.value;
    final end = start + widget.viewportWidth;
    final overflow = widget.direction == TextDirection.rtl
        // Arabic UI: the leading edge of a block is its right side, so keep
        // the title at the right edge of the visible timeline.
        ? widget.left + widget.width - end
        : start - widget.left;
    return overflow.clamp(0.0, widget.width);
  }

  @override
  void initState() {
    super.initState();
    widget.offset.addListener(_sync);
  }

  @override
  void didUpdateWidget(_StickyInset oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.offset != widget.offset) {
      oldWidget.offset.removeListener(_sync);
      widget.offset.addListener(_sync);
    }
    // The framework builds again right after this callback, so updating the
    // inset directly avoids a redundant setState during the update phase.
    _inset = _compute();
  }

  @override
  void dispose() {
    widget.offset.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    final next = _compute();
    if ((next - _inset).abs() < 0.5) {
      return;
    }
    setState(() => _inset = next);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(start: _inset),
      child: widget.child,
    );
  }
}

class _ProgrammeBlock extends StatelessWidget {
  const _ProgrammeBlock({
    required this.programme,
    required this.live,
    required this.allowInsecure,
    required this.use24HourTime,
    required this.left,
    required this.width,
    required this.horizontalOffset,
    required this.viewportWidth,
    required this.uiDirection,
    required this.onTap,
  });

  final Programme programme;
  final bool live;
  final bool allowInsecure;
  final bool use24HourTime;
  final double left;
  final double width;
  final ValueListenable<double> horizontalOffset;
  final double viewportWidth;
  final TextDirection uiDirection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    final strings = context.strings;
    final background = live ? colors.accentSoft : colors.surface0;
    final border =
        live ? colors.accent.withValues(alpha: 0.65) : colors.surface1;

    return Directionality(
      textDirection: uiDirection,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(9),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: border),
            ),
            child: _StickyInset(
              offset: horizontalOffset,
              left: left,
              width: width,
              viewportWidth: viewportWidth,
              direction: uiDirection,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final textScale =
                      MediaQuery.textScalerOf(context).scale(12) / 12;
                  // The constraints describe the *visible* slice of the
                  // block, so a wide programme scrolled mostly off screen
                  // switches to the compact layout instead of hiding its
                  // title past the edge.
                  final detailed =
                      constraints.maxWidth > 110 && textScale <= 1.2;
                  // Very short programmes leave only a few pixels inside the
                  // block, where an ellipsis reads as missing guide data.
                  final hasText = constraints.maxWidth >= 44;
                  // Only large visible slices carry artwork. XMLTV posters
                  // are full-size bitmaps (Tunarr serves ~570 KB each), and a
                  // long guide on a phone holds thousands of programmes, so
                  // widening this rule turns the guide into a multi-hundred-
                  // megabyte download that starves playback and refreshes
                  // from the same host.
                  final withPoster = detailed &&
                      constraints.maxWidth > 190 &&
                      textScale <= 1.15;

                  if (!hasText) {
                    // A sliver cannot fit a label, but it still marks where
                    // the programme sits. Leaving it blank reads as missing
                    // guide data (ErsatzTV airs five-minute programmes, so an
                    // entire channel looked empty at the default zoom). The
                    // surrounding Material already paints the tinted block
                    // and the live accent; return no text and no artwork.
                    return live
                        ? Align(
                            alignment: Alignment.center,
                            child: Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: colors.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          )
                        : const SizedBox.expand();
                  }

                  final title = BidiText(
                    programme.displayTitle,
                    maxLines: detailed ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.text,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                  );
                  final subtitle = programme.subTitle == null
                      ? null
                      : BidiText(
                          programme.subTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: colors.subtext0,
                                    height: 1.2,
                                  ),
                        );

                  if (!detailed) {
                    // Even the narrowest readable block carries the
                    // sub-title, so short programmes still show e.g. the
                    // episode name.
                    final compactSubtitle = textScale <= 1.8 ? subtitle : null;
                    return Stack(
                      children: <Widget>[
                        Positioned.fill(
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: ClipRect(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  title,
                                  if (compactSubtitle != null) ...<Widget>[
                                    const SizedBox(height: 1),
                                    compactSubtitle,
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (live)
                          PositionedDirectional(
                            top: 0,
                            end: 0,
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: colors.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    );
                  }

                  final text = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          if (live) ...<Widget>[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: colors.accent,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                strings.live,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: colors.base,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 8.5,
                                      height: 1.1,
                                      letterSpacing: 0.4,
                                    ),
                              ),
                            ),
                            const SizedBox(width: 5),
                          ],
                          Expanded(
                            child: Text(
                              strings.formatRange(
                                programme.start,
                                programme.stop,
                                use24HourTime: use24HourTime,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: uiDirection == TextDirection.rtl
                                  ? TextAlign.right
                                  : TextAlign.left,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: colors.overlay0,
                                    fontSize: 9,
                                    fontFeatures: const <FontFeature>[
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      title,
                      if (subtitle != null) ...<Widget>[
                        const SizedBox(height: 1),
                        subtitle,
                      ],
                    ],
                  );

                  if (!withPoster) {
                    return ClipRect(child: text);
                  }

                  return ClipRect(
                    child: Row(
                      children: <Widget>[
                        ProgrammePoster(
                          programme: programme,
                          allowInsecure: allowInsecure,
                          width: 54,
                          height: 74,
                          radius: 7,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: text),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
