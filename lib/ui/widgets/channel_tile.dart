import 'package:flutter/material.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import 'channel_logo.dart';
import 'programme_poster.dart';
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
    this.compact = false,
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

  /// A denser row used by the channels page's compact layout.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    final theme = Theme.of(context);
    final strings = context.strings;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final logoSize = compact ? 40.0 : 64.0;
    final logoRadius = compact ? 10.0 : 14.0;

    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 4 : 8),
      child: Material(
        color: colors.surface0,
        borderRadius: BorderRadius.circular(compact ? 10 : 14),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            compact ? 6 : 8,
            compact ? 6 : 8,
            compact ? 4 : 6,
            compact ? 6 : 8,
          ),
          child: Row(
            children: <Widget>[
              Tooltip(
                message: strings.watchLive,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onPlay,
                  child: Padding(
                    padding: EdgeInsets.all(compact ? 2 : 4),
                    child: SizedBox(
                      width: logoSize,
                      height: logoSize,
                      child: Stack(
                        children: <Widget>[
                          ChannelLogo(
                            channel: channel,
                            allowInsecure: allowInsecure,
                            size: logoSize,
                            radius: logoRadius,
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
              SizedBox(width: compact ? 8 : 10),
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
                        padding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: compact ? 2 : 4,
                        ),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: ProgrammeSummary(
                                channel: channel,
                                epg: epg,
                                now: now,
                                use24HourTime: use24HourTime,
                                dense: compact,
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
                constraints: BoxConstraints(
                  minWidth: compact ? 28 : 34,
                  minHeight: compact ? 28 : 34,
                ),
                iconSize: compact ? 18 : 21,
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

/// A poster card for the channels page's grid layout.
///
/// The current programme's artwork is the card's background, with the channel
/// logo, number and name over a scrim at the bottom. That makes the grid read
/// like a wall of what is on now instead of a list of logos, which is the
/// whole point of a grid view. The body keeps the now/next summary and opens
/// the channel's schedule; tapping the artwork tunes the channel.
class ChannelGridTile extends StatelessWidget {
  const ChannelGridTile({
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
    final programme = epg.nowFor(channel, now) ?? epg.nextFor(channel, now);
    // Only keep a programme that actually has artwork: the fallback below is
    // nicer than a generic film icon stretched across the card.
    final current =
        programme != null && programme.images.isNotEmpty ? programme : null;

    return MediaQuery.withClampedTextScaling(
      // Grid cards have a fixed aspect ratio; very large accessibility text
      // must not push the programme line out of the card.
      maxScaleFactor: 1.2,
      child: Material(
        color: colors.surface0,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPlay,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                height: 112,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (current != null)
                      FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: ProgrammePoster(
                          programme: current,
                          allowInsecure: allowInsecure,
                          width: 240,
                          height: 135,
                          radius: 0,
                        ),
                      )
                    else
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topStart,
                            end: Alignment.bottomEnd,
                            colors: <Color>[
                              colors.surface1,
                              colors.accentSoft,
                            ],
                          ),
                        ),
                      ),
                    // Scrim: the name and logo must stay readable on bright
                    // artwork, and the star needs its own contrast at the top.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Color(0x66000000),
                            Color(0x00000000),
                            Color(0xCC000000),
                          ],
                          stops: <double>[0, 0.45, 1],
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      top: 2,
                      end: 2,
                      child: IconButton(
                        tooltip: favorite
                            ? strings.removeFavorite
                            : strings.addFavorite,
                        onPressed: onToggleFavorite,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 30,
                          minHeight: 30,
                        ),
                        iconSize: 19,
                        icon: Icon(
                          favorite
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: favorite ? colors.accent : Colors.white70,
                          shadows: const <Shadow>[
                            Shadow(color: Colors.black54, blurRadius: 6),
                          ],
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      start: 8,
                      end: 8,
                      bottom: 7,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          SizedBox(
                            width: 38,
                            height: 38,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: <Widget>[
                                ChannelLogo(
                                  channel: channel,
                                  allowInsecure: allowInsecure,
                                  size: 38,
                                  radius: 9,
                                ),
                                if (channel.number.isNotEmpty)
                                  PositionedDirectional(
                                    start: -3,
                                    bottom: -3,
                                    child: ChannelNumberBadge(
                                      number: channel.displayNumber,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: BidiText(
                              channel.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                height: 1.15,
                                shadows: const <Shadow>[
                                  Shadow(
                                    color: Colors.black87,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: onGuide,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 4, 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: ProgrammeSummary(
                            channel: channel,
                            epg: epg,
                            now: now,
                            use24HourTime: use24HourTime,
                            dense: true,
                          ),
                        ),
                        const SizedBox(width: 2),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
