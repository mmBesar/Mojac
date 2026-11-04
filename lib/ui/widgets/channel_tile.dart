import 'package:flutter/material.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import 'channel_logo.dart';
import 'programme_summary.dart';

/// One channel in the list and favourites pages.
///
/// Tapping the logo starts playback; the programme summary opens the channel's
/// own schedule. The star sits on the trailing edge so it is reachable without
/// taking space away from the guide preview.
class ChannelTile extends StatelessWidget {
  const ChannelTile({
    super.key,
    required this.channel,
    required this.epg,
    required this.now,
    required this.use24HourTime,
    required this.allowInsecure,
    required this.favorite,
    required this.onPlay,
    required this.onGuide,
    required this.onToggleFavorite,
  });

  final Channel channel;
  final EpgData epg;
  final DateTime now;
  final bool use24HourTime;
  final bool allowInsecure;
  final bool favorite;
  final VoidCallback onPlay;
  final VoidCallback onGuide;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    final theme = Theme.of(context);
    final strings = context.strings;
    final rtl = Directionality.of(context) == TextDirection.rtl;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.surface0,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 6, 8),
          child: Row(
            children: <Widget>[
              Tooltip(
                message: strings.watchLive,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onPlay,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
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
                              child: ChannelNumberBadge(
                                number: channel.displayNumber,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 6),
                      child: BidiText(
                        channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.text,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: onGuide,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: ProgrammeSummary(
                                channel: channel,
                                epg: epg,
                                now: now,
                                use24HourTime: use24HourTime,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              rtl
                                  ? Icons.chevron_left_rounded
                                  : Icons.chevron_right_rounded,
                              size: 18,
                              color: colors.overlay0,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 2),
              IconButton(
                tooltip:
                    favorite ? strings.removeFavorite : strings.addFavorite,
                onPressed: onToggleFavorite,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 34,
                  minHeight: 34,
                ),
                iconSize: 21,
                icon: Icon(
                  favorite ? Icons.star_rounded : Icons.star_border_rounded,
                  color: favorite ? colors.accent : colors.overlay0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
