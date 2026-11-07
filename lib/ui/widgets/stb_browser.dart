import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import 'channel_logo.dart';
import 'group_filter_bar.dart';
import 'stb_osd.dart';

/// The channel list that slides over the picture: groups across the top and
/// channels with what is on now below. Tapping a row tunes to it; a hardware
/// keyboard (or TV remote) can type a name or number, move with the arrow keys
/// and press Enter.
class StbChannelBrowser extends StatefulWidget {
  const StbChannelBrowser({
    super.key,
    required this.channels,
    required this.current,
    required this.groups,
    required this.group,
    required this.now,
    required this.allowInsecure,
    required this.nowFor,
    required this.isFavorite,
    required this.onTune,
    required this.onGroupChanged,
    required this.onClose,
  });

  final List<Channel> channels;
  final Channel current;
  final List<String> groups;
  final String? group;
  final DateTime now;
  final bool allowInsecure;
  final Programme? Function(Channel channel) nowFor;
  final bool Function(Channel channel) isFavorite;
  final ValueChanged<Channel> onTune;
  final ValueChanged<String?> onGroupChanged;
  final VoidCallback onClose;

  @override
  State<StbChannelBrowser> createState() => _StbChannelBrowserState();
}

class _StbChannelBrowserState extends State<StbChannelBrowser> {
  static const double _rowExtent = 62;

  final TextEditingController _search = TextEditingController();
  final FocusNode _listFocus = FocusNode(debugLabel: 'stb-channel-list');
  final FocusNode _searchFocus = FocusNode(debugLabel: 'stb-channel-search');
  final ScrollController _scroll = ScrollController();
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _listFocus.requestFocus();
      }
    });
  }

  @override
  void didUpdateWidget(covariant StbChannelBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group != widget.group) {
      _selected = 0;
      _scrollToSelected();
    }
    final count = _filtered().length;
    if (_selected >= count) {
      _selected = count == 0 ? 0 : count - 1;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _listFocus.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<Channel> _filtered() {
    final query = _search.text.trim().toLowerCase();
    final group = widget.group;
    return widget.channels.where((channel) {
      if (group != null && channel.group != group) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      if (channel.name.toLowerCase().contains(query) ||
          channel.number.toLowerCase().contains(query) ||
          (channel.group ?? '').toLowerCase().contains(query)) {
        return true;
      }
      final programme = widget.nowFor(channel);
      return programme != null &&
          programme.displayTitle.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  void _scrollToSelected() {
    if (!_scroll.hasClients) {
      return;
    }
    final target = (_selected * _rowExtent - _rowExtent * 2)
        .clamp(0.0, _scroll.position.maxScrollExtent)
        .toDouble();
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
    );
  }

  void _select(int index, int count) {
    if (count == 0) {
      return;
    }
    final next = index.clamp(0, count - 1);
    if (next == _selected) {
      return;
    }
    setState(() => _selected = next);
    _scrollToSelected();
  }

  void _tuneSelected() {
    final channels = _filtered();
    if (channels.isEmpty) {
      return;
    }
    widget.onTune(channels[_selected.clamp(0, channels.length - 1)]);
  }

  void _appendQuery(String character) {
    _search.text = '${_search.text}$character';
    _search.selection = TextSelection.collapsed(offset: _search.text.length);
    setState(() => _selected = 0);
    if (!_searchFocus.hasFocus) {
      _searchFocus.requestFocus();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (_searchFocus.hasFocus) {
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        _tuneSelected();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final count = _filtered().length;
    if (key == LogicalKeyboardKey.arrowDown) {
      _select(_selected + 1, count);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _select(_selected - 1, count);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      _select(_selected + 8, count);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      _select(_selected - 8, count);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _select(0, count);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _select(count - 1, count);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _tuneSelected();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      if (_search.text.isNotEmpty) {
        _search.text =
            _search.text.substring(0, _search.text.length - 1);
        setState(() => _selected = 0);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final character = event.character;
    if (character != null &&
        character.isNotEmpty &&
        !character.contains(RegExp('[\u0000-\u001f]'))) {
      _appendQuery(character);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.mojacColors;
    final channels = _filtered();
    if (_selected >= channels.length) {
      _selected = channels.isEmpty ? 0 : channels.length - 1;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = (constraints.maxHeight - 24).clamp(220.0, 600.0);
        // A desktop window has room beside the picture: dock the list to the
        // leading edge and let it use the full height instead of floating a
        // phone-sized dialog in the middle of a 27-inch screen.
        final side = constraints.maxWidth >= 900 &&
            constraints.maxHeight >= 420;
        final panel = Focus(
          focusNode: _listFocus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(
              maxWidth: side ? 460 : 680,
              maxHeight: side
                  ? constraints.maxHeight - 28
                  : maxHeight,
            ),
            decoration: stbPanelDecoration(
              radius: 18,
              accent: colors.accent,
            ),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.live_tv_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.browseChannels,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      strings.channelCount(channels.length),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: strings.close,
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close_rounded),
                      color: Colors.white70,
                      iconSize: 20,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _search,
                  focusNode: _searchFocus,
                  onChanged: (_) => setState(() => _selected = 0),
                  onSubmitted: (_) => _tuneSelected(),
                  textInputAction: TextInputAction.go,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                  ),
                  decoration: InputDecoration(
                    hintText: strings.channelBrowserHint,
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.38),
                      fontSize: 13,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 19,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: strings.clearSearch,
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 17,
                            ),
                            color: Colors.white54,
                            onPressed: () {
                              _search.clear();
                              setState(() => _selected = 0);
                              _listFocus.requestFocus();
                            },
                          ),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.07),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 11),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (widget.groups.length > 1) ...<Widget>[
                  const SizedBox(height: 2),
                  GroupFilterBar(
                    groups: widget.groups,
                    selected: widget.group,
                    onChanged: widget.onGroupChanged,
                  ),
                ],
                const SizedBox(height: 6),
                Divider(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                Flexible(
                  child: channels.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 28,
                          ),
                          child: Text(
                            strings.noChannelMatch,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(
                                alpha: 0.55,
                              ),
                              fontSize: 13,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(
                            vertical: 6,
                          ),
                          itemExtent: _rowExtent,
                          itemCount: channels.length,
                          itemBuilder: (context, index) {
                            final channel = channels[index];
                            return _BrowserRow(
                              channel: channel,
                              programme: widget.nowFor(channel),
                              favorite: widget.isFavorite(channel),
                              current: channel.id == widget.current.id,
                              selected: index == _selected,
                              allowInsecure: widget.allowInsecure,
                              onTap: () {
                                _select(index, channels.length);
                                widget.onTune(channel);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onClose,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: side ? 0.45 : 0.66),
                ),
              ),
            ),
            if (side)
              PositionedDirectional(
                start: 14,
                top: 14,
                bottom: 14,
                child: SizedBox(
                  width: math.min(460.0, constraints.maxWidth * 0.44),
                  child: panel,
                ),
              )
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: panel,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BrowserRow extends StatelessWidget {
  const _BrowserRow({
    required this.channel,
    required this.programme,
    required this.favorite,
    required this.current,
    required this.selected,
    required this.allowInsecure,
    required this.onTap,
  });

  final Channel channel;
  final Programme? programme;
  final bool favorite;
  final bool current;
  final bool selected;
  final bool allowInsecure;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    final strings = context.strings;
    return Material(
      color: selected
          ? colors.accent.withValues(alpha: 0.18)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: <Widget>[
              ChannelLogo(
                channel: channel,
                allowInsecure: allowInsecure,
                size: 42,
                radius: 9,
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 38,
                child: Text(
                  channel.displayNumber,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: current ? colors.accent : Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    BidiText(
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: current ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                    if (programme != null) ...<Widget>[
                      const SizedBox(height: 1),
                      BidiText(
                        programme!.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (favorite)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 6),
                  child: Icon(
                    Icons.star_rounded,
                    size: 15,
                    color: colors.accent,
                  ),
                ),
              if (current)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8),
                  child: Text(
                    strings.live,
                    style: TextStyle(
                      color: colors.accent,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}
