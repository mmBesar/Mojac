import 'package:flutter/material.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import 'channel_logo.dart';
import 'live_progress_bar.dart';

/// Set-top-box style controls for the built-in player.
///
/// The panels are always dark, irrespective of the app theme: they sit on top
/// of video, where contrast matters more than palette consistency. Nothing here
/// animates while video plays except a single opacity fade, so the overlay
/// costs practically nothing per frame.

const Color _panelTop = Color(0xF2121C2E);
const Color _panelBottom = Color(0xF20A111E);

BoxDecoration stbPanelDecoration({
  double radius = 20,
  Color accent = const Color(0xFFCBA6F7),
}) {
  return BoxDecoration(
    gradient: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[_panelTop, _panelBottom],
    ),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: accent.withValues(alpha: 0.30)),
    boxShadow: const <BoxShadow>[
      BoxShadow(
        color: Color(0x66000000),
        blurRadius: 24,
        offset: Offset(0, 8),
      ),
    ],
  );
}

/// The lower-third channel banner: logo, number, clock, what is on now with
/// live progress, and what is next.
class StbBanner extends StatelessWidget {
  const StbBanner({
    super.key,
    required this.channel,
    required this.allowInsecure,
    required this.nowPlaying,
    required this.next,
    required this.now,
    required this.use24HourTime,
    required this.favorite,
    required this.pinned,
    required this.compact,
    required this.onToggleFavorite,
    required this.onTogglePin,
    required this.onOpenProgramme,
    this.sleepLabel,
    this.audioLabel,
    this.subtitleLabel,
  });

  final Channel channel;
  final bool allowInsecure;
  final Programme? nowPlaying;
  final Programme? next;
  final DateTime now;
  final bool use24HourTime;
  final bool favorite;
  final bool pinned;
  final bool compact;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTogglePin;
  final VoidCallback onOpenProgramme;
  final String? sleepLabel;
  final String? audioLabel;
  final String? subtitleLabel;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.mojacColors;
    final accent = colors.accent;
    final logoSize = compact ? 44.0 : 54.0;
    final titleSize = compact ? 15.0 : 18.0;

    // Each chip keeps the colour its sheet section uses, so the banner is a
    // compact reminder of where the same setting lives.
    final chips = <Widget>[
      if (channel.group != null && channel.group!.trim().isNotEmpty)
        _StbChip(
          icon: Icons.folder_outlined,
          color: const Color(0xFFF9E2AF),
          label: channel.group!.trim(),
        ),
      if (sleepLabel != null)
        _StbChip(
          icon: Icons.bedtime_rounded,
          color: const Color(0xFFCBA6F7),
          label: sleepLabel!,
        ),
      if (audioLabel != null)
        _StbChip(
          icon: Icons.graphic_eq_rounded,
          color: const Color(0xFF94E2D5),
          label: audioLabel!,
        ),
      if (subtitleLabel != null)
        _StbChip(
          icon: Icons.subtitles_rounded,
          color: const Color(0xFFF5C2E7),
          label: subtitleLabel!,
        ),
    ];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Container(
        decoration: stbPanelDecoration(accent: accent),
        padding: EdgeInsets.fromLTRB(
          compact ? 12 : 16,
          compact ? 10 : 14,
          compact ? 10 : 14,
          compact ? 10 : 14,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    ChannelLogo(
                      channel: channel,
                      allowInsecure: allowInsecure,
                      size: logoSize,
                      radius: 12,
                    ),
                    if (channel.number.trim().isNotEmpty)
                      PositionedDirectional(
                        start: -4,
                        bottom: -4,
                        child: ChannelNumberBadge(number: channel.number),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: BidiText(
                              channel.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: compact ? 16 : 19,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            strings.formatTime(now, use24HourTime: use24HourTime),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: compact ? 12 : 13,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const <FontFeature>[
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: <Widget>[
                          const _LiveDot(),
                          const SizedBox(width: 6),
                          Text(
                            strings.live,
                            style: TextStyle(
                              color: accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                          if (channel.number.trim().isNotEmpty) ...<Widget>[
                            const SizedBox(width: 10),
                            Text(
                              '${strings.channel} ${channel.number}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                _StbIconButton(
                  tooltip: favorite
                      ? strings.removeFavorite
                      : strings.addFavorite,
                  icon: favorite
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  color: favorite ? accent : Colors.white70,
                  onPressed: onToggleFavorite,
                ),
                _StbIconButton(
                  tooltip: pinned ? strings.unpinBanner : strings.pinBanner,
                  icon: pinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  color: pinned ? accent : Colors.white70,
                  onPressed: onTogglePin,
                ),
              ],
            ),
            const SizedBox(height: 10),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: nowPlaying == null ? null : onOpenProgramme,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (nowPlaying != null) ...<Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              BidiText(
                                nowPlaying!.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: titleSize,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ),
                              ),
                              if (!compact && nowPlaying!.subTitle != null) ...<Widget>[
                                const SizedBox(height: 2),
                                BidiText(
                                  nowPlaying!.subTitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.62),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        BidiText(
                          strings.formatRange(
                            nowPlaying!.start,
                            nowPlaying!.stop,
                            use24HourTime: use24HourTime,
                          ),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.62),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    LiveProgressBar(
                      programme: nowPlaying!,
                      height: 4,
                      showRemaining: false,
                    ),
                  ] else
                    Text(
                      strings.noProgrammeInfo,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
            if (!compact && next != null) ...<Widget>[
              const SizedBox(height: 9),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    strings.next,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    strings.formatTime(
                      next!.start,
                      use24HourTime: use24HourTime,
                    ),
                    style: TextStyle(
                      color: accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: BidiText(
                      next!.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (!compact && chips.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: chips),
            ],
          ],
        ),
      ),
    );
  }
}

/// A segmented level bar for volume and brightness, in the style of a set-top
/// box. Thirty blocks read at a glance from across a room; the exact
/// percentage sits beside them for fine adjustments.
class StbLevelOsd extends StatelessWidget {
  const StbLevelOsd({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    this.segments = 30,
    this.muted = false,
  });

  final String label;
  final IconData icon;
  final double value;
  final int segments;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    final percent = (value.clamp(0.0, 1.0) * 100).round();
    final filled = (value.clamp(0.0, 1.0) * segments).round();
    final accent = muted ? const Color(0xFFF38BA8) : colors.accent;
    return IgnorePointer(
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 340),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
        decoration: stbPanelDecoration(accent: accent),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '$percent%',
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    fontFeatures: <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                for (var index = 0; index < segments; index++) ...<Widget>[
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 90),
                      height: 16,
                      decoration: BoxDecoration(
                        color: index < filled
                            ? accent
                            : Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  if (index != segments - 1) const SizedBox(width: 2),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A short notice above the picture, used for track changes, mute and sleep
/// timer feedback.
class StbMessageOsd extends StatelessWidget {
  const StbMessageOsd({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.accent = const Color(0xFFCBA6F7),
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: stbPanelDecoration(radius: 14, accent: accent),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: accent, size: 20),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  BidiText(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle != null && subtitle!.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 1),
                    BidiText(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.62),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: const BoxDecoration(
        color: Color(0xFFF38BA8),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _StbChip extends StatelessWidget {
  const _StbChip({
    required this.icon,
    required this.label,
    this.color = Colors.white70,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: BidiText(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StbIconButton extends StatelessWidget {
  const _StbIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color = Colors.white,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      color: color,
      iconSize: 20,
      visualDensity: VisualDensity.compact,
      splashRadius: 18,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }
}
