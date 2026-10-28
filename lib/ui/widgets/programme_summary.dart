import 'package:flutter/material.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';

class ProgrammeSummary extends StatelessWidget {
  const ProgrammeSummary({
    super.key,
    required this.channel,
    required this.epg,
    required this.now,
    required this.use24HourTime,
    this.dense = false,
  });

  final Channel channel;
  final EpgData epg;
  final DateTime now;
  final bool use24HourTime;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.mojacColors;
    final current = epg.nowFor(channel, now);
    final next = epg.nextFor(channel, now);

    if (current == null && next == null) {
      return Text(
        strings.noProgrammeInfo,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.overlay0,
              fontStyle: FontStyle.italic,
            ),
      );
    }

    final style = Theme.of(context).textTheme.bodySmall;
    final lineStyle = style?.copyWith(
      color: colors.subtext1,
      height: 1.35,
    );
    final labelStyle = style?.copyWith(
      color: colors.accent,
      fontWeight: FontWeight.w600,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (current != null) ...<Widget>[
          Row(
            children: <Widget>[
              Text(strings.now, style: labelStyle),
              const SizedBox(width: 6),
              Expanded(
                child: BidiText(
                  current.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: lineStyle,
                ),
              ),
              if (!dense) ...<Widget>[
                const SizedBox(width: 8),
                BidiText(
                  strings.formatTime(
                    current.start,
                    use24HourTime: use24HourTime,
                  ),
                  style: style?.copyWith(color: colors.overlay0),
                ),
              ],
            ],
          ),
          if (current.subTitle != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 1),
              child: BidiText(
                current.subTitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style?.copyWith(
                  color: colors.subtext0,
                  height: 1.3,
                ),
              ),
            ),
        ],
        if (!dense && next != null) ...<Widget>[
          const SizedBox(height: 2),
          Row(
            children: <Widget>[
              Text(
                strings.next,
                style: style?.copyWith(
                  color: colors.overlay0,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: BidiText(
                  next.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style?.copyWith(color: colors.overlay0),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
