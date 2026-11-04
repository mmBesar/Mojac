import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';

/// App-bar title that always shows the active source and opens a quick source
/// picker. Managing sources lives one tap deeper, in Settings.
class SourceSwitcherButton extends StatelessWidget {
  const SourceSwitcherButton({super.key, required this.onManageSources});

  final VoidCallback onManageSources;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = context.strings;
    final colors = context.mojacColors;
    final active = state.activeSource;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (state.sources.isEmpty) {
          onManageSources();
        } else {
          _showSourceSheet(context, state);
        }
      },
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(2, 4, 2, 4),
        child: Row(
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.asset(
                'assets/branding/mojac_icon.png',
                width: 34,
                height: 34,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text(
                    'Mojac',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      letterSpacing: 0.2,
                    ),
                  ),
                  if (active != null)
                    BidiText(
                      active.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.subtext0,
                          ),
                    )
                  else
                    Text(
                      strings.appTagline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.subtext0,
                          ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              state.sources.length > 1
                  ? Icons.expand_more_rounded
                  : Icons.tune_rounded,
              size: 19,
              color: colors.overlay0,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSourceSheet(BuildContext context, AppState state) async {
    final strings = context.strings;
    final colors = context.mojacColors;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: colors.mantle,
      builder: (sheetContext) {
        final activeId = state.activeSource?.id;
        return SafeArea(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Text(
                    strings.chooseSource,
                    style: Theme.of(sheetContext).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: state.sources.length,
                    itemBuilder: (context, index) {
                      final source = state.sources[index];
                      final active = source.id == activeId;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: active
                                  ? colors.accent
                                  : colors.surface1,
                            ),
                          ),
                          tileColor:
                              active ? colors.accentSoft : colors.surface0,
                          leading: Icon(
                            _providerIcon(source.provider),
                            color: active ? colors.accent : colors.subtext0,
                          ),
                          title: BidiText(
                            source.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            source.provider.label,
                            style: Theme.of(sheetContext)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: colors.subtext0),
                          ),
                          trailing: active
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  color: colors.accent,
                                  size: 20,
                                )
                              : null,
                          onTap: () =>
                              Navigator.of(sheetContext).pop(source.id),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 6),
                Divider(height: 1, color: colors.surface1),
                ListTile(
                  leading: const Icon(Icons.tune_rounded),
                  title: Text(strings.manageSources),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onManageSources();
                  },
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        );
      },
    );

    if (selected != null) {
      await state.selectSource(selected);
    }
  }

  IconData _providerIcon(SourceProvider provider) {
    return switch (provider) {
      SourceProvider.iptv => Icons.playlist_play_rounded,
      SourceProvider.tunarr => Icons.view_stream_rounded,
      SourceProvider.ersatzTv => Icons.live_tv_rounded,
    };
  }
}
