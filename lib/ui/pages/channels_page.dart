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
import '../widgets/error_banner.dart';
import '../widgets/group_filter_bar.dart';
import '../widgets/warnings_panel.dart';
import 'channel_guide_page.dart';

class ChannelsPage extends StatefulWidget {
  const ChannelsPage({super.key, required this.onAddSource});

  final VoidCallback onAddSource;

  @override
  State<ChannelsPage> createState() => _ChannelsPageState();
}

class _ChannelsPageState extends State<ChannelsPage> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openPlayer(Channel channel) {
    openChannelPlayer(context, channel);
  }

  void _openGuide(Channel channel) {
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

    if (state.sources.isEmpty) {
      return EmptyState(
        icon: Icons.playlist_add_rounded,
        title: strings.noChannels,
        body: strings.noChannelsBody,
        actionLabel: strings.addSource,
        onAction: widget.onAddSource,
      );
    }

    if (!state.hasContent && state.isLoading) {
      return _Loading(message: strings.refreshing);
    }

    if (!state.hasContent && state.error != null) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: strings.errorTitle,
        body: state.error!,
        actionLabel: strings.retry,
        onAction: () => state.refresh(),
        secondaryLabel: strings.sources,
        onSecondary: widget.onAddSource,
      );
    }

    final allChannels = state.channels;
    if (allChannels.isEmpty) {
      return EmptyState(
        icon: Icons.live_tv_rounded,
        title: strings.noChannels,
        body: strings.noChannelsBody,
        actionLabel: strings.refresh,
        onAction: () => state.refresh(),
        secondaryLabel: strings.sources,
        onSecondary: widget.onAddSource,
      );
    }

    final groups = channelGroups(allChannels);
    final group = groups.contains(state.settings.groupFilter)
        ? state.settings.groupFilter
        : null;
    final channels = _filtered(allChannels, group);
    final allowInsecure = state.activeSource?.allowInsecureCerts ?? false;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: strings.searchChannels,
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: strings.clearSearch,
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _search.clear();
                              setState(() {});
                            },
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: context.mojacColors.surface1,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  strings.channelCount(channels.length),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: context.mojacColors.subtext0,
                      ),
                ),
              ),
            ],
          ),
        ),
        GroupFilterBar(
          groups: groups,
          selected: group,
          onChanged: (value) => unawaited(state.setGroupFilter(value)),
        ),
        if (state.warnings.isNotEmpty)
          WarningsPanel(warnings: state.warnings),
        if (state.error != null && state.hasContent)
          ErrorBanner(
            message: state.error!,
            retryLabel: strings.retry,
            onRetry: () => state.refresh(),
          ),
        Expanded(
          child: channels.isEmpty
              ? EmptyState(
                  icon: group == null
                      ? Icons.search_off_rounded
                      : Icons.filter_alt_off_rounded,
                  title: group == null
                      ? strings.noSearchResults
                      : strings.noGroupChannels,
                  body: strings.noChannelsBody,
                  actionLabel:
                      group == null ? strings.clearSearch : strings.allGroups,
                  onAction: () {
                    _search.clear();
                    setState(() {});
                    unawaited(state.setGroupFilter(null));
                  },
                )
              : RefreshIndicator(
                  onRefresh: state.refresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: channels.length,
                    itemBuilder: (context, index) {
                      final channel = channels[index];
                      return ChannelTile(
                        channel: channel,
                        epg: state.epg,
                        now: state.now,
                        use24HourTime: state.settings.use24HourTime,
                        allowInsecure: allowInsecure,
                        favorite: state.isFavorite(channel.id),
                        onPlay: () => _openPlayer(channel),
                        onGuide: () => _openGuide(channel),
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

  List<Channel> _filtered(List<Channel> channels, String? group) {
    final query = _search.text.trim().toLowerCase();
    return channels.where((channel) {
      if (group != null && channel.group != group) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      return channel.name.toLowerCase().contains(query) ||
          channel.number.toLowerCase().contains(query) ||
          (channel.group?.toLowerCase().contains(query) ?? false);
    }).toList(growable: false);
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
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
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.mojacColors.subtext0,
                ),
          ),
        ],
      ),
    );
  }
}
