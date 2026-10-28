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
import '../widgets/programme_sheet.dart';
import '../widgets/warnings_panel.dart';

const double _channelWidth = 164;
const double _rowHeight = 82;
const double _headerHeight = 54;
const double _pixelsPerMinute = 4;
const int _windowMinutes = 12 * 60;
const double _timelineWidth = _windowMinutes * _pixelsPerMinute;

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

  @override
  void initState() {
    super.initState();
    _windowStart = _floorToHalfHour(DateTime.now())
        .subtract(const Duration(minutes: 30));
    _bodyHorizontal.addListener(_syncHeader);
  }

  @override
  void dispose() {
    _bodyHorizontal
      ..removeListener(_syncHeader)
      ..dispose();
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

  void _openPlayer(Channel channel) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PlayerPage(channel: channel),
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
    final nowOffset = now.difference(_windowStart).inSeconds / 60 *
        _pixelsPerMinute;
    final showNow = nowOffset >= 0 && nowOffset <= _timelineWidth;

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
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.mojacColors.subtext0,
                          ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _jumpToNow,
                icon: const Icon(Icons.my_location_rounded, size: 18),
                label: Text(strings.guideNow),
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
                            for (final channel in channels)
                              _ChannelCell(
                                channel: channel,
                                allowInsecure: allowInsecure,
                                onTap: () => _openPlayer(channel),
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
                                      for (var index = 0;
                                          index < channels.length;
                                          index++)
                                        _GuideRow(
                                          channel: channels[index],
                                          epg: state.epg,
                                          windowStart: _windowStart,
                                          windowEnd: _windowEnd,
                                          now: now,
                                          use24HourTime:
                                              state.settings.use24HourTime,
                                          allowInsecure: allowInsecure,
                                          even: index.isEven,
                                          onWatch: () => _openPlayer(
                                            channels[index],
                                          ),
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
    required this.use24HourTime,
    this.nowOffset,
  });

  final DateTime start;
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
          left: minute * _pixelsPerMinute + 6,
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
    required this.gridColor,
    required this.hourColor,
  });

  final DateTime start;
  final Color gridColor;
  final Color hourColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeWidth = 1;
    for (var minute = 0; minute <= _windowMinutes; minute += 30) {
      final x = minute * _pixelsPerMinute;
      final isHour = start.add(Duration(minutes: minute)).minute == 0;
      paint.color = isHour ? hourColor : gridColor;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) {
    return oldDelegate.start != start ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.hourColor != hourColor;
  }
}

class _ChannelCell extends StatelessWidget {
  const _ChannelCell({
    required this.channel,
    required this.allowInsecure,
    required this.onTap,
  });

  final Channel channel;
  final bool allowInsecure;
  final VoidCallback onTap;

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
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: <Widget>[
              ChannelLogo(
                channel: channel,
                allowInsecure: allowInsecure,
                size: 38,
                radius: 9,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      channel.displayNumber,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.overlay0,
                          ),
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
            ],
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
    required this.use24HourTime,
    required this.allowInsecure,
    required this.even,
    required this.onWatch,
  });

  final Channel channel;
  final EpgData epg;
  final DateTime windowStart;
  final DateTime windowEnd;
  final DateTime now;
  final bool use24HourTime;
  final bool allowInsecure;
  final bool even;
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
            _pixelsPerMinute;
    final width = math.max(
      0.0,
      stop.difference(start).inSeconds / 60 * _pixelsPerMinute - 2,
    );
    if (width < 1) {
      return const SizedBox.shrink();
    }
    final live = programme.isLiveAt(now);
    return Positioned(
      left: left,
      top: 5,
      width: width,
      height: _rowHeight - 10,
      child: _ProgrammeBlock(
        programme: programme,
        live: live,
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
    required this.use24HourTime,
    required this.onTap,
  });

  final Programme programme;
  final bool live;
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
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 110;
              final textScale =
                  MediaQuery.textScalerOf(context).scale(12) / 12;
              // Large accessibility font sizes would otherwise push the live
              // badge, title, subtitle and time past the fixed row height.
              final detailed = wide && textScale <= 1.2;

              final title = BidiText(
                programme.title,
                maxLines: wide ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.text,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
              );

              if (!detailed) {
                return Directionality(
                  textDirection: bidiDirectionOf(programme.title),
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: title,
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

              return ClipRect(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    if (live) ...<Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: colors.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              strings.live,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: colors.accent,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 9,
                                    letterSpacing: 0.5,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                    ],
                    Flexible(flex: 3, child: title),
                    if (programme.subTitle != null) ...<Widget>[
                      const SizedBox(height: 1),
                      Flexible(
                        flex: 2,
                        child: BidiText(
                          programme.subTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: colors.subtext0,
                                    height: 1.2,
                                  ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      strings.formatRange(
                        programme.start,
                        programme.stop,
                        use24HourTime: use24HourTime,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.overlay0,
                            fontSize: 9,
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                    ),
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
