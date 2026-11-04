import 'package:flutter/material.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';

/// Horizontal group chips shared by Channels and Guide. Both pages read and
/// write [AppSettings.groupFilter], so choosing a group on one page filters the
/// other page as well.
class GroupFilterBar extends StatelessWidget {
  const GroupFilterBar({
    super.key,
    required this.groups,
    required this.selected,
    required this.onChanged,
  });

  final List<String> groups;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (groups.length <= 1) {
      return const SizedBox.shrink();
    }
    final strings = context.strings;
    final effective = groups.contains(selected) ? selected : null;
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: <Widget>[
          _GroupChip(
            label: strings.allGroups,
            selected: effective == null,
            onSelected: () => onChanged(null),
          ),
          for (final group in groups)
            _GroupChip(
              label: group,
              selected: effective == group,
              onSelected: () => onChanged(group),
            ),
        ],
      ),
    );
  }
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Material(
        color: selected ? colors.accentSoft : colors.surface0,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onSelected,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: BidiText(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: selected ? colors.accent : colors.subtext0,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sorted, de-duplicated group names for a channel list.
List<String> channelGroups(List<Channel> channels) {
  final values = <String>{
    for (final channel in channels)
      if (channel.group != null && channel.group!.trim().isNotEmpty)
        channel.group!.trim(),
  }.toList()
    ..sort();
  return values;
}
