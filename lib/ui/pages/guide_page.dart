import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../player_page.dart';
import '../widgets/channel_logo.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_banner.dart';
import '../widgets/programme_poster.dart';
import '../widgets/programme_sheet.dart';
import '../widgets/warnings_panel.dart';
import 'channel_guide_page.dart';

const double _channelWidth = 126;
const double _rowHeight = 92;
const double _headerHeight = 50;
const double _minPixelsPerMinute = 4;
const double _maxPixelsPerMinute = 12;
const int _windowMinutes = 12 * 60;

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

  late DateTime _windowStart;

  /// Timeline density. The guide opens at the historical 4 px/minute and can
  /// zoom in to 12 px/minute for reading long programme titles.
  double _pixelsPerMinute = _minPixelsPerMinute;

  double get _timelineWidth => _windowMinutes * _pixelsPerMinute;

  /// Horizontal viewport in timeline pixels. Programme posters are only
  /// requested for blocks near the visible window, so a 12-hour grid does not
  /// fire hundreds of image downloads for rows the user cannot see.
  double _visibleStart = 0;
  double _visibleEnd = 900;

  /// Vertical viewport in row pixels; posters are limited to visible rows too.
  double _rowStart = 0;
  double _rowEnd = 900;

  /// Guards the one-frame window rollover when the app resumes after enough
  /// time has passed for "now" to fall outside the displayed twelve hours.
  bool _windowSyncScheduled = false;

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
    super.dispose();
  }

  DateTime get _windowEnd => _windowStart.add(const Duration(hours: 12));

  void _syncHeader() {
    if (!_headerHorizontal.hasClients || !_bodyHorizontal.hasClients) {
      return;
    }
    final target = _bodyHorizontal.offset.clamp(
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

  /// If the app stayed open long enough for the guide window to scroll past
  /// "now", move it back so the page does not present an empty schedule.
  void _ensureWindowContainsNow(DateTime now) {
    if (_windowSyncScheduled) {
      return;
    }
    if (!now.isBefore(_windowStart) && now.isBefore(_windowEnd)) {
      return;
    }
    _windowSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _windowSyncScheduled = false;
      if (!mounted) {
        return;
      }
      final current = context.read<AppState>().now;
      if (current.isBefore(_windowStart) || !current.isBefore(_windowEnd)) {
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PlayerPage(channel: channel),
      ),
    );
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

    final channels = state.channels;
    final allowInsecure = state.activeSource?.allowInsecureCerts ?? false;
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

    return Column(
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
                      )} · ${strings.twelveHourWindow}',
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
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.tv_rounded,
                            size: 16,
                            color: context.mojacColors.overlay0,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            strings.channel,
                            style:
                                Theme.of(context).textTheme.labelMedium?.copyWith(
                                      color: context.mojacColors.subtext0,
                                      fontWeight: FontWeight.w700,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: SingleChildScrollView(
                          controller: _headerHorizontal,
                          scrollDirection: Axis.horizontal,
                          physics: const NeverScrollableScrollPhysics(),
                          child: SizedBox(
                            width: _timelineWidth,
                            height: _headerHeight,
                            child: _TimeHeader(
                              start: _windowStart,
                              pixelsPerMinute: _pixelsPerMinute,
                              use24HourTime: state.settings.use24HourTime,
                              nowOffset: showNow ? nowOffset : null,
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
                            child: SizedBox(
                              width: _timelineWidth,
                              height: channels.length * _rowHeight,
                              child: Stack(
                                children: <Widget>[
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: _GridPainter(
                                        start: _windowStart,
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
                                          visibleStart: _visibleStart - 600,
                                          visibleEnd: _visibleEnd + 600,
                                          onWatch: () => _openPlayer(
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
                    ],
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

DateTime _floorToHalfHour(DateTime value) {
  final minute = value.minute < 30 ? 0 : 30;
  return DateTime(value.year, value.month, value.day, value.hour, minute);
}

/// Compact density control for the timeline. The guide spans twelve hours, so
/// the slider trades how much of the schedule is visible against how much room
/// each programme gets for its title.
class _TimelineZoom extends StatelessWidget {
  const _TimelineZoom({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    final strings = context.strings;
    return Semantics(
      label: strings.timelineZoom,
      child: Tooltip(
        message: strings.timelineZoom,
        child: SizedBox(
          width: 104,
          height: 32,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              activeTrackColor: colors.accent,
              inactiveTrackColor: colors.surface1,
              thumbColor: colors.accent,
              overlayColor: colors.accent.withValues(alpha: 0.16),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: 16,
              semanticFormatterCallback: (zoom) =>
                  '${zoom.toStringAsFixed(0)} px/min',
              onChanged: onChanged,
            ),
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
      alignment: AlignmentDirectional.centerStart,
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
    required this.pixelsPerMinute,
    required this.use24HourTime,
    this.nowOffset,
  });

  final DateTime start;
  final double pixelsPerMinute;
  final bool use24HourTime;
  final double? nowOffset;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    final strings = context.strings;
    final labels = <Widget>[];
    for (var minute = 0; minute <= _windowMinutes; minute += 30) {
      final time = start.add(Duration(minutes: minute));
      if (time.minute != 0) {
        continue;
      }
      labels.add(
        Positioned(
          left: minute * pixelsPerMinute + 6,
          top: 0,
          bottom: 0,
          child: Center(
            child: Text(
              strings.formatHour(time, use24HourTime: use24HourTime),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.subtext0,
                    fontWeight: FontWeight.w600,
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
    required this.pixelsPerMinute,
    required this.gridColor,
    required this.hourColor,
  });

  final DateTime start;
  final double pixelsPerMinute;
  final Color gridColor;
  final Color hourColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeWidth = 1;
    for (var minute = 0; minute <= _windowMinutes; minute += 30) {
      final x = minute * pixelsPerMinute;
      final isHour = start.add(Duration(minutes: minute)).minute == 0;
      paint.color = isHour ? hourColor : gridColor;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) {
    return oldDelegate.start != start ||
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
    final strings = context.strings;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Container(
      height: _rowHeight,
      decoration: BoxDecoration(
        color: colors.base,
        border: BorderDirectional(
          bottom: BorderSide(color: colors.surface1),
          end: BorderSide(color: colors.surface1),
        ),
      ),
      child: Row(
        children: <Widget>[
          Tooltip(
            message: strings.watchLive,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onPlay,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: ChannelLogo(
                  channel: channel,
                  allowInsecure: allowInsecure,
                  size: 40,
                  radius: 9,
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onGuide,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(2, 6, 6, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          channel.displayNumber,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: colors.overlay0,
                                  ),
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          rtl
                              ? Icons.chevron_left_rounded
                              : Icons.chevron_right_rounded,
                          size: 14,
                          color: colors.overlay0,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    BidiText(
                      channel.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.text,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
    required this.visibleStart,
    required this.visibleEnd,
    required this.onWatch,
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
  final double visibleStart;
  final double visibleEnd;
  final VoidCallback onWatch;

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
              top: 0,
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
        ],
      ),
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
    final live = programme.isLiveAt(now);
    final nearViewport = left + width >= visibleStart && left <= visibleEnd;
    return Positioned(
      left: left,
      top: 5,
      width: width,
      height: _rowHeight - 10,
      child: _ProgrammeBlock(
        programme: programme,
        live: live,
        allowInsecure: allowInsecure,
        showPoster: nearViewport,
        use24HourTime: use24HourTime,
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

class _ProgrammeBlock extends StatelessWidget {
  const _ProgrammeBlock({
    required this.programme,
    required this.live,
    required this.allowInsecure,
    required this.showPoster,
    required this.use24HourTime,
    required this.onTap,
  });

  final Programme programme;
  final bool live;
  final bool allowInsecure;
  final bool showPoster;
  final bool use24HourTime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    final strings = context.strings;
    final background = live ? colors.accentSoft : colors.surface0;
    final border =
        live ? colors.accent.withValues(alpha: 0.65) : colors.surface1;

    return Material(
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
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textScale =
                  MediaQuery.textScalerOf(context).scale(12) / 12;
              // Large accessibility font sizes would otherwise push the live
              // badge, title, subtitle and time past the fixed row height.
              final detailed =
                  constraints.maxWidth > 110 && textScale <= 1.2;
              // Very short programmes leave only a few pixels inside the
              // block, where an ellipsis reads as missing guide data.
              final hasText = constraints.maxWidth >= 44;
              // Only large blocks carry artwork. XMLTV posters are full-size
              // bitmaps (Tunarr serves ~570 KB each), and a twelve-hour guide
              // on a phone holds thousands of programmes, so widening this
              // rule turns the guide into a multi-hundred-megabyte download
              // that starves playback and playlist refreshes from the same
              // host.
              final withPoster = showPoster &&
                  detailed &&
                  constraints.maxWidth > 190 &&
                  textScale <= 1.15;

              final title = BidiText(
                programme.title,
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

              if (!hasText) {
                // A sliver cannot fit a label, and an ellipsis tile reads as
                // missing guide data. Leave it empty: a thumbnail here would
                // add one image request per short programme.
                return const SizedBox.shrink();
              }

              if (!detailed) {
                // Even the narrowest readable block carries the sub-title, so
                // short programmes still show e.g. the episode name.
                final compactSubtitle = textScale <= 1.8 ? subtitle : null;
                return Directionality(
                  textDirection: bidiDirectionOf(programme.title),
                  child: Stack(
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
                  ),
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
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
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
    );
  }
}
