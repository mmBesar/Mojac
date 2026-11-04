import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/app_state.dart';
import '../l10n/strings.dart';
import 'pages/channels_page.dart';
import 'pages/favorites_page.dart';
import 'pages/guide_page.dart';
import 'pages/search_page.dart';
import 'pages/settings_page.dart';
import 'pages/sources_page.dart';
import 'widgets/source_switcher.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const int _tabCount = 4;
  static const double _swipeVelocity = 260;

  int _index = 0;

  void _selectTab(int index) {
    if (index == _index || index < 0 || index >= _tabCount) {
      return;
    }
    setState(() => _index = index);
  }

  void _openSources() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const SourcesScreen(),
      ),
    );
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const SearchPage(),
      ),
    );
  }

  /// Swipe left/right between tabs on Android. Direction is reversed for RTL
  /// interfaces so "forward" always follows the reading direction.
  void _handleSwipe(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    if (velocity.abs() < _swipeVelocity) {
      return;
    }
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final forward = rtl ? velocity > 0 : velocity < 0;
    _selectTab(_index + (forward ? 1 : -1));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = context.strings;
    final colors = context.mojacColors;

    final pages = <Widget>[
      ChannelsPage(onAddSource: _openSources),
      GuidePage(onAddSource: _openSources),
      FavoritesPage(
        onAddSource: _openSources,
        onBrowseChannels: () => _selectTab(0),
      ),
      SettingsPage(onOpenSources: _openSources),
    ];
    final labels = <String>[
      strings.channels,
      strings.guide,
      strings.favorites,
      strings.settings,
    ];
    final icons = <IconData>[
      Icons.live_tv_rounded,
      Icons.calendar_month_rounded,
      Icons.star_rounded,
      Icons.settings_rounded,
    ];

    final appBar = AppBar(
      titleSpacing: 12,
      title: SourceSwitcherButton(onManageSources: _openSources),
      actions: <Widget>[
        IconButton(
          tooltip: strings.search,
          onPressed: _openSearch,
          icon: const Icon(Icons.search_rounded),
        ),
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
        final swipeable = defaultTargetPlatform == TargetPlatform.android;

        if (wide) {
          final extended = constraints.maxWidth >= 1280;
          return Scaffold(
            appBar: appBar,
            body: Row(
              children: <Widget>[
                NavigationRail(
                  extended: extended,
                  selectedIndex: _index,
                  onDestinationSelected: _selectTab,
                  labelType: extended
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.all,
                  leading: const SizedBox(height: 8),
                  destinations: <NavigationRailDestination>[
                    for (var index = 0; index < labels.length; index++)
                      NavigationRailDestination(
                        icon: Icon(icons[index]),
                        selectedIcon: Icon(icons[index], color: colors.accent),
                        label: Text(labels[index]),
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
          body: swipeable
              ? GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragEnd: _handleSwipe,
                  child: body,
                )
              : body,
          bottomNavigationBar: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.mantle,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: colors.surface1),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.24),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: _selectTab,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  height: 66,
                  labelBehavior:
                      NavigationDestinationLabelBehavior.alwaysShow,
                  destinations: <NavigationDestination>[
                    for (var index = 0; index < labels.length; index++)
                      NavigationDestination(
                        icon: Icon(icons[index]),
                        selectedIcon:
                            Icon(icons[index], color: colors.accent),
                        label: labels[index],
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
