import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/bidi.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../l10n/strings.dart';
import 'pages/channels_page.dart';
import 'pages/guide_page.dart';
import 'pages/settings_page.dart';
import 'pages/sources_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void _openSources() {
    setState(() => _index = 2);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = context.strings;
    final colors = context.mojacColors;

    final pages = <Widget>[
      ChannelsPage(onAddSource: _openSources),
      GuidePage(onAddSource: _openSources),
      const SourcesPage(),
      SettingsPage(onOpenSources: _openSources),
    ];
    final labels = <String>[
      strings.channels,
      strings.guide,
      strings.sources,
      strings.settings,
    ];
    final icons = <IconData>[
      Icons.live_tv_rounded,
      Icons.calendar_month_rounded,
      Icons.dns_rounded,
      Icons.settings_rounded,
    ];

    final appBar = AppBar(
      titleSpacing: 16,
      title: Row(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: colors.accentSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.live_tv_rounded,
              size: 20,
              color: colors.accent,
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
                if (state.activeSource != null)
                  BidiText(
                    state.activeSource!.name,
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
        ],
      ),
      actions: <Widget>[
        IconButton(
          tooltip: strings.refresh,
          onPressed: state.isLoading ? null : () => state.refresh(),
          icon: state.isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
        ),
        const SizedBox(width: 4),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final body = IndexedStack(index: _index, children: pages);

        if (wide) {
          final extended = constraints.maxWidth >= 1280;
          return Scaffold(
            appBar: appBar,
            body: Row(
              children: <Widget>[
                NavigationRail(
                  extended: extended,
                  selectedIndex: _index,
                  onDestinationSelected: (index) =>
                      setState(() => _index = index),
                  labelType: extended
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.all,
                  leading: const SizedBox(height: 8),
                  destinations: <NavigationRailDestination>[
                    for (var index = 0; index < labels.length; index++)
                      NavigationRailDestination(
                        icon: Icon(icons[index]),
                        selectedIcon: Icon(icons[index], color: colors.accent),
                        label: BidiText(labels[index]),
                      ),
                  ],
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: colors.surface1,
                ),
                Expanded(child: body),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: appBar,
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (index) => setState(() => _index = index),
            destinations: <NavigationDestination>[
              for (var index = 0; index < labels.length; index++)
                NavigationDestination(
                  icon: Icon(icons[index]),
                  selectedIcon: Icon(icons[index], color: colors.accent),
                  label: labels[index],
                ),
            ],
          ),
        );
      },
    );
  }
}
