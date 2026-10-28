import 'dart:convert';

import 'models.dart';

class M3uParseResult {
  const M3uParseResult({required this.channels, this.xmltvUrl});

  final List<Channel> channels;
  final String? xmltvUrl;
}

class M3uParser {
  const M3uParser();

  M3uParseResult parse(
    String content, {
    required String sourceId,
    Uri? baseUri,
  }) {
    final lines = const LineSplitter().convert(content);
    final channels = <Channel>[];
    String? xmltvUrl;
    String? nextGroup;
    _PendingChannel? pending;

    for (var index = 0; index < lines.length; index++) {
      final rawLine = lines[index];
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }

      if (line.toUpperCase().startsWith('#EXTM3U')) {
        final attrs = _parseAttributes(line.substring(7));
        final advertised = attrs['url-tvg'] ??
            attrs['x-tvg-url'] ??
            attrs['tvg-url'] ??
            attrs['x-tvg'];
        if (advertised != null && advertised.trim().isNotEmpty) {
          xmltvUrl = _firstLocation(advertised, baseUri);
        }
        continue;
      }

      if (line.toUpperCase().startsWith('#EXTINF:')) {
        final info = line.substring(8);
        final comma = _lastUnquotedComma(info);
        final metadata = comma >= 0 ? info.substring(0, comma) : info;
        final displayName = comma >= 0
            ? info.substring(comma + 1).trim()
            : '';
        final attrs = _parseAttributes(metadata);
        final groupTitle = attrs['group-title']?.trim();
        pending = _PendingChannel(
          attrs: attrs,
          displayName: displayName,
          group: groupTitle == null || groupTitle.isEmpty
              ? nextGroup
              : groupTitle,
        );
        nextGroup = null;
        continue;
      }

      if (line.toUpperCase().startsWith('#EXTGRP:')) {
        final group = line.substring(8).trim();
        if (group.isNotEmpty) {
          // Some playlists emit #EXTGRP before #EXTINF, others between the
          // #EXTINF and its URL. Support both, but let group-title win.
          if (pending != null) {
            final groupTitle = pending.attrs['group-title']?.trim();
            if (groupTitle == null || groupTitle.isEmpty) {
              pending.group = group;
            }
            nextGroup = null;
          } else {
            nextGroup = group;
          }
        }
        continue;
      }

      if (line.startsWith('#')) {
        continue;
      }

      final current = pending;
      if (current == null) {
        continue;
      }
      pending = null;

      final streamUrl = _resolveLocation(line, baseUri);
      if (streamUrl.isEmpty || streamUrl == '#') {
        continue;
      }

      final indexNumber = channels.length + 1;
      final tvgId = (current.attrs['tvg-id'] ?? '').trim();
      final channelId = (current.attrs['channel-id'] ?? tvgId).trim();
      final name = _channelName(
        current.displayName,
        current.attrs['tvg-name'],
        indexNumber,
      );
      final number = (current.attrs['tvg-chno'] ?? '').trim();
      final logo = (current.attrs['tvg-logo'] ?? '').trim();

      channels.add(
        Channel(
          id: '${sourceId}_$indexNumber',
          sourceId: sourceId,
          name: name,
          number: number.isEmpty ? indexNumber.toString() : number,
          url: streamUrl,
          tvgId: tvgId,
          channelId: channelId,
          logoUrl: logo.isEmpty ? null : _resolveLocation(logo, baseUri),
          group: current.group?.isEmpty ?? true ? null : current.group,
        ),
      );
    }

    return M3uParseResult(channels: channels, xmltvUrl: xmltvUrl);
  }

  String _channelName(String displayName, String? tvgName, int index) {
    if (displayName.isNotEmpty) {
      return displayName;
    }
    final fallback = tvgName?.trim() ?? '';
    if (fallback.isNotEmpty) {
      return fallback;
    }
    return 'Channel $index';
  }

  Map<String, String> _parseAttributes(String input) {
    final attributes = <String, String>{};
    final pattern = RegExp(r'([A-Za-z0-9_.-]+)=("[^"]*"|[^,\s]+)');
    for (final match in pattern.allMatches(input)) {
      final key = match.group(1)!.toLowerCase();
      var value = match.group(2)!;
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      attributes[key] = value;
    }
    return attributes;
  }

  int _lastUnquotedComma(String input) {
    var inQuotes = false;
    var lastComma = -1;
    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        lastComma = i;
      }
    }
    return lastComma;
  }

  String? _firstLocation(String input, Uri? baseUri) {
    final first = input.split(',').first.trim();
    if (first.isEmpty) {
      return null;
    }
    return _resolveLocation(first, baseUri);
  }

  String _resolveLocation(String raw, Uri? baseUri) {
    var value = raw.trim();
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    if (value.isEmpty) {
      return '';
    }
    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme) {
      return value;
    }
    if (baseUri == null) {
      return value;
    }
    try {
      final resolved = baseUri.resolveUri(parsed ?? Uri());
      return baseUri.scheme == 'file' ? resolved.toFilePath() : resolved.toString();
    } on FormatException {
      return value;
    }
  }
}

class _PendingChannel {
  _PendingChannel({
    required this.attrs,
    required this.displayName,
    this.group,
  });

  final Map<String, String> attrs;
  final String displayName;
  String? group;
}
