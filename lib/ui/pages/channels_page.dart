import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../player_launcher.dart';
import '../widgets/channel_logo.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_banner.dart';
import '../widgets/programme_summary.dart';
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
  String? _group;

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

    final channels = _filtered(state.channels);
    final groups = _groups(state.channels);
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
        if (groups.length > 1)
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: <Widget>[
                _GroupChip(
                  label: strings.allGroups,
                  selected: _group == null,
                  onSelected: () => setState(() => _group = null),
                ),
                for (final group in groups)
                  _GroupChip(
                    label: group,
                    selected: _group == group,
                    onSelected: () => setState(() => _group = group),
                  ),
              ],
            ),
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
                  icon: Icons.search_off_rounded,
                  title: strings.noSearchResults,
                  body: strings.noChannelsBody,
                  actionLabel: strings.clearSearch,
                  onAction: () {
                    _search.clear();
                    setState(() => _group = null);
                  },
                )
              : RefreshIndicator(
                  onRefresh: state.refresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: channels.length,
                    itemBuilder: (context, index) {
                      final channel = channels[index];
                      return _ChannelTile(
                        channel: channel,
                        epg: state.epg,
                        now: state.now,
                        use24HourTime: state.settings.use24HourTime,
                        allowInsecure: allowInsecure,
                        onPlay: () => _openPlayer(channel),
                        onGuide: () => _openGuide(channel),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  List<Channel> _filtered(List<Channel> channels) {
    final query = _search.text.trim().toLowerCase();
    return channels.where((channel) {
      if (_group != null && channel.group != _group) {
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

  List<String> _groups(List<Channel> channels) {
    final values = <String>{
      for (final channel in channels)
        if (channel.group != null && channel.group!.trim().isNotEmpty)
          channel.group!.trim(),
    }.toList()
      ..sort();
    return values;
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

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.channel,
    required this.epg,
    required this.now,
    required this.use24HourTime,
    required this.allowInsecure,
    required this.onPlay,
    required this.onGuide,
  });

  final Channel channel;
  final EpgData epg;
  final DateTime now;
  final bool use24HourTime;
  final bool allowInsecure;
  final VoidCallback onPlay;
  final VoidCallback onGuide;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    final theme = Theme.of(context);
    final strings = context.strings;
    final rtl = Directionality.of(context) == TextDirection.rtl;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.surface0,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
          child: Row(
            children: <Widget>[
              // Tapping the logo starts playback; the schedule below opens the
              // channel's own guide. Keeping the actions on their own targets
              // avoids the old trailing play button taking up list space.
              Tooltip(
                message: strings.watchLive,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onPlay,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: ChannelLogo(
                      channel: channel,
                      allowInsecure: allowInsecure,
                      size: 52,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 32,
                child: Text(
                  channel.displayNumber,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.overlay0,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 6),
                      child: BidiText(
                        channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.text,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: onGuide,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: ProgrammeSummary(
                                channel: channel,
                                epg: epg,
                                now: now,
                                use24HourTime: use24HourTime,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              rtl
                                  ? Icons.chevron_left_rounded
                                  : Icons.chevron_right_rounded,
                              size: 18,
                              color: colors.overlay0,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
