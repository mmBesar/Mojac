import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../player_launcher.dart';
import '../widgets/channel_tile.dart';
import '../widgets/empty_state.dart';
import 'channel_guide_page.dart';

/// Starred channels from the active source. Favourites follow the playlist
/// snapshot, so a source that renumbers its channels keeps the ones it can and
/// simply drops the rest instead of pointing at a different stream.
class FavoritesPage extends StatelessWidget {
  const FavoritesPage({
    super.key,
    required this.onAddSource,
    required this.onBrowseChannels,
  });

  final VoidCallback onAddSource;
  final VoidCallback onBrowseChannels;

  void _openPlayer(BuildContext context, Channel channel) {
    openChannelPlayer(context, channel);
  }

  void _openGuide(BuildContext context, Channel channel) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ChannelGuidePage(channel: channel),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = context.strings;
    final colors = context.mojacColors;

    if (state.sources.isEmpty) {
      return EmptyState(
        icon: Icons.star_border_rounded,
        title: strings.favoritesEmptyTitle,
        body: strings.favoritesEmptyBody,
        actionLabel: strings.addSource,
        onAction: onAddSource,
      );
    }

    if (!state.hasContent && state.isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 16),
            Text(
              strings.refreshing,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.subtext0,
                  ),
            ),
          ],
        ),
      );
    }

    if (!state.hasContent && state.error != null) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: strings.errorTitle,
        body: state.error!,
        actionLabel: strings.retry,
        onAction: () => state.refresh(),
        secondaryLabel: strings.sources,
        onSecondary: onAddSource,
      );
    }

    final favorites = state.favoriteChannels;
    if (favorites.isEmpty) {
      return EmptyState(
        icon: Icons.star_border_rounded,
        title: strings.favoritesEmptyTitle,
        body: strings.favoritesEmptyBody,
        actionLabel: strings.channels,
        onAction: onBrowseChannels,
      );
    }

    final allowInsecure = state.activeSource?.allowInsecureCerts ?? false;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Row(
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colors.accentSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.star_rounded,
                  size: 19,
                  color: colors.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      strings.favorites,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    Text(
                      strings.favoriteCount(favorites.length),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.subtext0,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: state.refresh,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: favorites.length,
              itemBuilder: (context, index) {
                final channel = favorites[index];
                return ChannelTile(
                  channel: channel,
                  epg: state.epg,
                  now: state.now,
                  use24HourTime: state.settings.use24HourTime,
                  allowInsecure: allowInsecure,
                  favorite: true,
                  onPlay: () => _openPlayer(context, channel),
                  onGuide: () => _openGuide(context, channel),
                  onToggleFavorite: () =>
                      unawaited(state.toggleFavorite(channel.id)),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
