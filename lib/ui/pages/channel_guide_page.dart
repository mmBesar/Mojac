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
import '../widgets/programme_poster.dart';
import '../widgets/programme_sheet.dart';

/// The full schedule for a single channel. It deliberately starts at the
/// current programme so opening it from the channel list lands on "now"
/// instead of twelve hours of history.
class ChannelGuidePage extends StatefulWidget {
  const ChannelGuidePage({super.key, required this.channel});

  final Channel channel;

  @override
  State<ChannelGuidePage> createState() => _ChannelGuidePageState();
}

class _ChannelGuidePageState extends State<ChannelGuidePage> {
  void _openPlayer() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PlayerPage(channel: widget.channel),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = context.strings;
    final colors = context.mojacColors;
    final allowInsecure = state.activeSource?.allowInsecureCerts ?? false;
    final now = state.now;
    final upcoming = state.epg
        .programmesFor(widget.channel)
        .where((programme) => programme.stop.isAfter(now))
        .toList(growable: false);

    final entries = <_GuideEntry>[];
    DateTime? day;
    for (final programme in upcoming) {
      final startDay = DateTime(
        programme.start.year,
        programme.start.month,
        programme.start.day,
      );
      if (day == null || startDay != day) {
        day = startDay;
        entries.add(_DayEntry(startDay));
      }
      entries.add(_ProgrammeEntry(programme));
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: <Widget>[
            ChannelLogo(
              channel: widget.channel,
              allowInsecure: allowInsecure,
              size: 34,
              radius: 9,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  BidiText(
                    widget.channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  Text(
                    strings.channelGuide,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.subtext0,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: strings.watchLive,
            onPressed: _openPlayer,
            icon: const Icon(Icons.play_circle_fill_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: entries.isEmpty
          ? EmptyState(
              icon: Icons.event_busy_rounded,
              title: strings.guideEmptyTitle,
              body: strings.guideEmptyBody,
              actionLabel: strings.refresh,
              onAction: state.refresh,
            )
          : RefreshIndicator(
              onRefresh: state.refresh,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  if (entry is _DayEntry) {
                    return _DayHeader(date: entry.date);
                  }
                  final programme = (entry as _ProgrammeEntry).programme;
                  return _ProgrammeCard(
                    programme: programme,
                    now: now,
                    allowInsecure: allowInsecure,
                    use24HourTime: state.settings.use24HourTime,
                    onTap: () => showProgrammeSheet(
                      context,
                      channel: widget.channel,
                      programme: programme,
                      allowInsecure: allowInsecure,
                      onWatch: _openPlayer,
                    ),
                  );
                },
              ),
            ),
    );
  }
}

sealed class _GuideEntry {
  const _GuideEntry();
}

class _DayEntry extends _GuideEntry {
  const _DayEntry(this.date);

  final DateTime date;
}

class _ProgrammeEntry extends _GuideEntry {
  const _ProgrammeEntry(this.programme);

  final Programme programme;
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    final strings = context.strings;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
      child: Row(
        children: <Widget>[
          Text(
            strings.formatDate(date),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.subtext0,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(color: colors.surface1, height: 1),
          ),
        ],
      ),
    );
  }
}

class _ProgrammeCard extends StatelessWidget {
  const _ProgrammeCard({
    required this.programme,
    required this.now,
    required this.allowInsecure,
    required this.use24HourTime,
    required this.onTap,
  });

  final Programme programme;
  final DateTime now;
  final bool allowInsecure;
  final bool use24HourTime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.mojacColors;
    final theme = Theme.of(context);
    final live = programme.isLiveAt(now);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: live ? colors.accentSoft : colors.surface0,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: live
                    ? colors.accent.withValues(alpha: 0.55)
                    : colors.surface1,
              ),
            ),
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ProgrammePoster(
                  programme: programme,
                  allowInsecure: allowInsecure,
                  width: 86,
                  height: 64,
                  radius: 10,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          BidiText(
                            strings.formatRange(
                              programme.start,
                              programme.stop,
                              use24HourTime: use24HourTime,
                            ),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: live ? colors.accent : colors.overlay0,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (live) ...<Widget>[
                            const SizedBox(width: 8),
                            _LiveBadge(label: strings.live),
                          ],
                          if (programme.episode != null) ...<Widget>[
                            const SizedBox(width: 8),
                            Flexible(
                              child: BidiText(
                                programme.episode!,
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
                      const SizedBox(height: 3),
                      BidiText(
                        programme.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      if (programme.subTitle != null) ...<Widget>[
                        const SizedBox(height: 2),
                        BidiText(
                          programme.subTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.subtext0,
                          ),
                        ),
                      ],
                      if (programme.description != null) ...<Widget>[
                        const SizedBox(height: 4),
                        BidiText(
                          programme.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.subtext1,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
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

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.base,
              fontWeight: FontWeight.w800,
              fontSize: 9,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}
