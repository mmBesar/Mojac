import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';

/// Horizontal group chips shared by Channels and Guide. Both pages read and
/// write [AppSettings.groupFilter], so choosing a group on one page filters the
/// other page as well.
class GroupFilterBar extends StatefulWidget {
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
  State<GroupFilterBar> createState() => _GroupFilterBarState();
}

class _GroupFilterBarState extends State<GroupFilterBar> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// A mouse wheel over a horizontal strip scrolls it sideways. Without this
  /// the only way to reach a group past the edge is to drag with the mouse,
  /// which a desktop user never thinks to do.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scroll.hasClients) {
      return;
    }
    final delta = event.scrollDelta.dy != 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (delta == 0) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver
        .register(event, (PointerSignalEvent _) {});
    final position = _scroll.position;
    _scroll.jumpTo(
      (position.pixels + delta).clamp(0.0, position.maxScrollExtent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.groups;
    if (groups.length <= 1) {
      return const SizedBox.shrink();
    }
    final strings = context.strings;
    final selected = widget.selected;
    final effective = groups.contains(selected) ? selected : null;
    return SizedBox(
      height: 42,
      child: Listener(
        onPointerSignal: _onPointerSignal,
        child: ListView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: <Widget>[
            _GroupChip(
              label: strings.allGroups,
              selected: effective == null,
              onSelected: () => widget.onChanged(null),
            ),
            for (final group in groups)
              _GroupChip(
                label: group,
                selected: effective == group,
                onSelected: () => widget.onChanged(group),
              ),
          ],
        ),
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
