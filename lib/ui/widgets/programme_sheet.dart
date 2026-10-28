import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import 'channel_logo.dart';

Future<void> showProgrammeSheet(
  BuildContext context, {
  required Channel channel,
  required Programme programme,
  required bool allowInsecure,
  required VoidCallback onWatch,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: context.mojacColors.mantle,
    builder: (sheetContext) {
      return _ProgrammeSheet(
        channel: channel,
        programme: programme,
        allowInsecure: allowInsecure,
        onWatch: () {
          Navigator.of(sheetContext).pop();
          onWatch();
        },
      );
    },
  );
}

class _ProgrammeSheet extends StatelessWidget {
  const _ProgrammeSheet({
    required this.channel,
    required this.programme,
    required this.allowInsecure,
    required this.onWatch,
  });

  final Channel channel;
  final Programme programme;
  final bool allowInsecure;
  final VoidCallback onWatch;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.mojacColors;
    final theme = Theme.of(context);
    final use24HourTime = context.select<AppState, bool>(
      (state) => state.settings.use24HourTime,
    );
    final isLive = programme.isLiveAt(DateTime.now());
    final duration = programme.stop.difference(programme.start).inMinutes;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ChannelLogo(
                  channel: channel,
                  allowInsecure: allowInsecure,
                  size: 56,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      BidiText(
                        channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.subtext0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      BidiText(
                        programme.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isLive) ...<Widget>[
                  const SizedBox(width: 8),
                  _Badge(
                    label: strings.live,
                    color: colors.accent,
                    softColor: colors.accentSoft,
                  ),
                ],
              ],
            ),
            if (programme.subTitle != null) ...<Widget>[
              const SizedBox(height: 10),
              BidiText(
                programme.subTitle!,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.subtext0,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                _Meta(
                  icon: Icons.schedule_rounded,
                  label: strings.formatRange(
                    programme.start,
                    programme.stop,
                    use24HourTime: use24HourTime,
                  ),
                ),
                _Meta(
                  icon: Icons.timelapse_rounded,
                  label: strings.isArabic ? '$duration دقيقة' : '$duration min',
                ),
                if (programme.episode != null)
                  _Meta(
                    icon: Icons.numbers_rounded,
                    label: programme.episode!,
                  ),
              ],
            ),
            if (programme.categories.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final category in programme.categories)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surface1,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: BidiText(
                        category,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.subtext1,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            BidiText(
              programme.description ?? strings.noDescription,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.subtext1,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onWatch,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(strings.watchChannel),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(strings.close),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.color,
    required this.softColor,
  });

  final String label;
  final Color color;
  final Color softColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: softColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 16, color: colors.overlay0),
        const SizedBox(width: 5),
        BidiText(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.subtext0,
              ),
        ),
      ],
    );
  }
}
