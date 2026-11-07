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
    final view = state.settings.channelsView;

    Widget tile(Channel channel) {
      if (view == 'grid') {
        return ChannelGridTile(
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
      }
      return ChannelTile(
        channel: channel,
        epg: state.epg,
        now: state.now,
        use24HourTime: state.settings.use24HourTime,
        allowInsecure: allowInsecure,
        favorite: state.isFavorite(channel.id),
        compact: view == 'compact',
        onPlay: () => _openPlayer(channel),
        onGuide: () => _openGuide(channel),
        onToggleFavorite: () => unawaited(state.toggleFavorite(channel.id)),
      );
    }

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
              const SizedBox(width: 8),
              _ChannelViewSwitcher(
                value: view,
                onChanged: (value) =>
                    unawaited(state.setChannelsView(value)),
              ),
              const SizedBox(width: 8),
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
                  child: view == 'grid'
                      ? GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            // Cards carry a 112 px poster header plus a two
                            // line now/next body, so they need more height
                            // than the old logo tiles. A slightly wider cell
                            // lets the artwork read as a picture instead of a
                            // strip.
                            maxCrossAxisExtent: 240,
                            mainAxisExtent: 208,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: channels.length,
                          itemBuilder: (context, index) =>
                              tile(channels[index]),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: channels.length,
                          itemBuilder: (context, index) =>
                              tile(channels[index]),
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

/// Three compact buttons that switch the channel list between the roomy list,
/// the artwork grid and the dense one-line list.
class _ChannelViewSwitcher extends StatelessWidget {
  const _ChannelViewSwitcher({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static IconData _icon(String view) => switch (view) {
        'grid' => Icons.grid_view_rounded,
        'compact' => Icons.view_stream_rounded,
        _ => Icons.view_list_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    final strings = context.strings;
    String label(String view) => switch (view) {
          'grid' => strings.viewGrid,
          'compact' => strings.viewCompact,
          _ => strings.viewList,
        };
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final view in kChannelViews)
            Tooltip(
              message: label(view),
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: value == view ? null : () => onChanged(view),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: value == view ? colors.surface2 : null,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    _icon(view),
                    size: 17,
                    color: value == view ? colors.accent : colors.overlay0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
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
