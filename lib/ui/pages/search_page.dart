import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../player_launcher.dart';
import '../widgets/channel_logo.dart';
import '../widgets/group_filter_bar.dart';
import '../widgets/programme_poster.dart';
import '../widgets/programme_sheet.dart';
import 'channel_guide_page.dart';

/// One search surface for the whole app: channels, programmes and groups.
///
/// A guide can hold a week of programmes for dozens of channels, so matches
/// are ranked and capped. Programme rows carry the poster/still and the
/// sub-title, which is what makes "smart" search useful when the channel name
/// alone is not enough.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;
  String _term = '';
  _Results _results = const _Results();

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _term = value.trim();
        _results = _search(context.read<AppState>(), _term);
      });
    });
  }

  _Results _search(AppState state, String rawTerm) {
    if (rawTerm.isEmpty) {
      return const _Results();
    }
    final term = rawTerm.toLowerCase();
    final now = state.now;
    final windowEnd = now.add(Duration(hours: state.settings.guideHours));

    final groups = channelGroups(state.channels)
        .where((group) => group.toLowerCase().contains(term))
        .toList(growable: false);

    final channels = state.channels.where((channel) {
      return channel.name.toLowerCase().contains(term) ||
          channel.number.toLowerCase().contains(term) ||
          channel.displayNumber.toLowerCase().contains(term) ||
          (channel.group?.toLowerCase().contains(term) ?? false);
    }).toList(growable: false);

    final programmes = <_ProgrammeHit>[];
    for (final channel in state.channels) {
      for (final programme in state.epg.forWindow(
        channel,
        now.subtract(const Duration(hours: 2)),
        windowEnd,
      )) {
        final score = _score(programme, term, channel);
        if (score == null) {
          continue;
        }
        programmes.add(_ProgrammeHit(channel, programme, score));
      }
    }
    // Best textual matches first, then whatever is on soonest.
    programmes.sort((a, b) {
      final byScore = a.score.compareTo(b.score);
      if (byScore != 0) {
        return byScore;
      }
      return a.programme.start.compareTo(b.programme.start);
    });

    return _Results(
      groups: groups,
      channels: channels.take(24).toList(growable: false),
      programmes: programmes.take(60).toList(growable: false),
    );
  }

  int? _score(Programme programme, String term, Channel channel) {
    final title = programme.title.toLowerCase();
    if (title.startsWith(term)) {
      return 0;
    }
    if (title.contains(term)) {
      return 1;
    }
    if (programme.subTitle?.toLowerCase().contains(term) ?? false) {
      return 2;
    }
    if (programme.episode?.toLowerCase().contains(term) ?? false) {
      return 2;
    }
    if (programme.categories
        .any((category) => category.toLowerCase().contains(term))) {
      return 3;
    }
    if (programme.keywords
        .any((keyword) => keyword.toLowerCase().contains(term))) {
      return 3;
    }
    if (programme.description?.toLowerCase().contains(term) ?? false) {
      return 4;
    }
    if (channel.name.toLowerCase().contains(term)) {
      return 5;
    }
    return null;
  }

  void _openChannel(Channel channel) {
    openChannelPlayer(context, channel);
  }

  void _openGuide(Channel channel) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ChannelGuidePage(channel: channel),
      ),
    );
  }

  void _openProgramme(Channel channel, Programme programme) {
    final allowInsecure =
        context.read<AppState>().activeSource?.allowInsecureCerts ?? false;
    showProgrammeSheet(
      context,
      channel: channel,
      programme: programme,
      allowInsecure: allowInsecure,
      onWatch: () => _openChannel(channel),
    );
  }

  Future<void> _selectGroup(String group) async {
    await context.read<AppState>().setGroupFilter(group);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = context.strings;
    final colors = context.mojacColors;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          style: Theme.of(context).textTheme.titleMedium,
          decoration: InputDecoration(
            hintText: strings.searchHint,
            border: InputBorder.none,
            hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.overlay0,
                ),
          ),
        ),
        actions: <Widget>[
          if (_query.text.isNotEmpty || _term.isNotEmpty)
            IconButton(
              tooltip: MaterialLocalizations.of(context).clearButtonTooltip,
              onPressed: () {
                _query.clear();
                _onChanged('');
                setState(() {
                  _term = '';
                  _results = const _Results();
                });
              },
              icon: const Icon(Icons.close_rounded),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _term.isEmpty
          ? _Prompt(prompt: strings.searchPrompt)
          : _results.isEmpty
              ? _Prompt(prompt: strings.searchNoResults)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: <Widget>[
                    if (_results.groups.isNotEmpty) ...<Widget>[
                      _SectionHeader(
                        icon: Icons.folder_copy_rounded,
                        label: strings.searchGroups,
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          for (final group in _results.groups)
                            ActionChip(
                              avatar: Icon(
                                Icons.filter_alt_rounded,
                                size: 16,
                                color: colors.accent,
                              ),
                              label: BidiText(group),
                              onPressed: () => unawaited(_selectGroup(group)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                    ],
                    if (_results.channels.isNotEmpty) ...<Widget>[
                      _SectionHeader(
                        icon: Icons.live_tv_rounded,
                        label: strings.resultChannels,
                      ),
                      for (final channel in _results.channels)
                        _ChannelResult(
                          channel: channel,
                          program: state.epg.nowFor(channel, state.now),
                          allowInsecure:
                              state.activeSource?.allowInsecureCerts ?? false,
                          use24HourTime: state.settings.use24HourTime,
                          onPlay: () => _openChannel(channel),
                          onGuide: () => _openGuide(channel),
                        ),
                      const SizedBox(height: 18),
                    ],
                    if (_results.programmes.isNotEmpty) ...<Widget>[
                      _SectionHeader(
                        icon: Icons.movie_filter_rounded,
                        label: strings.resultProgrammes,
                      ),
                      for (final hit in _results.programmes)
                        _ProgrammeResult(
                          hit: hit,
                          allowInsecure:
                              state.activeSource?.allowInsecureCerts ?? false,
                          use24HourTime: state.settings.use24HourTime,
                          onTap: () => _openProgramme(
                            hit.channel,
                            hit.programme,
                          ),
                        ),
                    ],
                  ],
                ),
    );
  }
}

class _Results {
  const _Results({
    this.groups = const <String>[],
    this.channels = const <Channel>[],
    this.programmes = const <_ProgrammeHit>[],
  });

  final List<String> groups;
  final List<Channel> channels;
  final List<_ProgrammeHit> programmes;

  bool get isEmpty =>
      groups.isEmpty && channels.isEmpty && programmes.isEmpty;
}

class _ProgrammeHit {
  const _ProgrammeHit(this.channel, this.programme, this.score);

  final Channel channel;
  final Programme programme;
  final int score;
}

class _Prompt extends StatelessWidget {
  const _Prompt({required this.prompt});

  final String prompt;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.manage_search_rounded, size: 44, color: colors.overlay0),
            const SizedBox(height: 12),
            BidiText(
              prompt,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.subtext0,
                    height: 1.5,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: colors.overlay0),
          const SizedBox(width: 7),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.subtext0,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _ChannelResult extends StatelessWidget {
  const _ChannelResult({
    required this.channel,
    required this.program,
    required this.allowInsecure,
    required this.use24HourTime,
    required this.onPlay,
    required this.onGuide,
  });

  final Channel channel;
  final Programme? program;
  final bool allowInsecure;
  final bool use24HourTime;
  final VoidCallback onPlay;
  final VoidCallback onGuide;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    final strings = context.strings;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  children: <Widget>[
                    ChannelLogo(
                      channel: channel,
                      allowInsecure: allowInsecure,
                      size: 48,
                      radius: 10,
                    ),
                    if (channel.number.isNotEmpty)
                      PositionedDirectional(
                        start: 2,
                        bottom: 2,
                        child: ChannelNumberBadge(
                          number: channel.displayNumber,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    BidiText(
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      program == null
                          ? (channel.group ?? strings.noProgrammeInfo)
                          : '${program.title} · ${strings.formatRange(
                              program!.start,
                              program!.stop,
                              use24HourTime: use24HourTime,
                            )}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.subtext0,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: strings.guide,
                onPressed: onGuide,
                icon: Icon(Icons.calendar_month_rounded, color: colors.overlay0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgrammeResult extends StatelessWidget {
  const _ProgrammeResult({
    required this.hit,
    required this.allowInsecure,
    required this.use24HourTime,
    required this.onTap,
  });

  final _ProgrammeHit hit;
  final bool allowInsecure;
  final bool use24HourTime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    final strings = context.strings;
    final programme = hit.programme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ProgrammePoster(
                programme: programme,
                allowInsecure: allowInsecure,
                width: 50,
                height: 68,
                radius: 8,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    BidiText(
                      programme.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                    ),
                    if (programme.subTitle != null) ...<Widget>[
                      const SizedBox(height: 2),
                      BidiText(
                        programme.subTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: colors.subtext1,
                                ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      '${hit.channel.name} · ${strings.formatRange(
                        programme.start,
                        programme.stop,
                        use24HourTime: use24HourTime,
                      )}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.overlay0,
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
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
