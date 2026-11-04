import 'package:xml/xml.dart';

import 'models.dart';

/// Parsed XMLTV output. [unmatchedChannels] counts XMLTV channels that could
/// not be tied to a playlist entry, which is useful for diagnostics.
class XmltvParseResult {
  const XmltvParseResult({
    required this.epg,
    required this.matchedChannels,
    required this.unmatchedChannels,
    required this.channelNames,
  });

  final EpgData epg;
  final int matchedChannels;
  final int unmatchedChannels;
  final Map<String, String> channelNames;
}

/// Parses XMLTV into [EpgData] keyed by Mojac's internal channel ids.
///
/// Only programmes that overlap the visible window are kept. A typical
/// XMLTV file contains several days of data for dozens of channels, and
/// keeping all of it needlessly inflates memory on phones.
class XmltvParser {
  const XmltvParser({
    this.pastWindow = const Duration(hours: 12),
    this.futureWindow = const Duration(hours: 72),
  });

  /// How much history to retain. The guide can scroll back a little.
  final Duration pastWindow;

  /// How much upcoming programming to retain.
  final Duration futureWindow;

  XmltvParseResult parse(
    String content,
    List<Channel> channels, {
    DateTime? now,
  }) {
    final reference = (now ?? DateTime.now()).toLocal();
    final document = XmlDocument.parse(content);
    final catalogue = _ChannelCatalogue(channels);

    final tv = document.findAllElements('tv').firstOrNull;
    if (tv == null) {
      return XmltvParseResult(
        epg: EpgData.empty(),
        matchedChannels: 0,
        unmatchedChannels: 0,
        channelNames: const <String, String>{},
      );
    }

    for (final element in tv.childElements) {
      if (element.name.local != 'channel') {
        continue;
      }
      final id = element.getAttribute('id')?.trim() ?? '';
      if (id.isEmpty) {
        continue;
      }
      final names = element
          .findAllElements('display-name')
          .map((node) => node.innerText.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      catalogue.register(id, names);
    }

    final windowStart = reference.subtract(pastWindow);
    final windowEnd = reference.add(futureWindow);
    final byChannel = <String, List<Programme>>{};

    for (final element in tv.childElements) {
      if (element.name.local != 'programme') {
        continue;
      }
      final xmltvChannel = element.getAttribute('channel')?.trim() ?? '';
      final internalId = catalogue.resolve(xmltvChannel);
      if (internalId == null) {
        continue;
      }

      final start = parseXmltvTime(element.getAttribute('start'));
      final stop = parseXmltvTime(element.getAttribute('stop'));
      if (start == null || stop == null || !stop.isAfter(start)) {
        continue;
      }
      if (!stop.isAfter(windowStart) || !start.isBefore(windowEnd)) {
        continue;
      }

      final title = _firstText(element, 'title');
      if (title.isEmpty) {
        continue;
      }

      final categories = _texts(element, 'category');
      // Tunarr and ErsatzTV both publish several <icon> tags per programme
      // (poster and still). Keeping every URL lets the detail sheet try the
      // next image when one fails, without widening the guide's artwork gate.
      final images = <String>[];
      for (final node in element.findAllElements('icon')) {
        final src = node.getAttribute('src')?.trim();
        if (src != null && src.isNotEmpty && !images.contains(src)) {
          images.add(src);
        }
      }
      // Some XMLTV feeds use <image> instead of the older <icon> spelling.
      for (final node in element.findAllElements('image')) {
        final src = node.innerText.trim();
        if (src.isNotEmpty && !images.contains(src)) {
          images.add(src);
        }
      }
      final numbering = _episodeNumbering(element);
      final rating = _firstElement(element, 'rating');
      final ratingValue = rating == null
          ? null
          : _optionalChildText(rating, 'value') ?? _optionalOwnText(rating);

      byChannel.putIfAbsent(internalId, () => <Programme>[]).add(
            Programme(
              channelId: internalId,
              start: start,
              stop: stop,
              title: title,
              subTitle: _optionalText(element, 'sub-title'),
              description: _optionalText(element, 'desc'),
              categories: categories,
              images: List<String>.unmodifiable(images),
              episode: numbering.label,
              season: numbering.season,
              episodeNumber: numbering.episode,
              credits: _credits(element),
              rating: ratingValue,
              ratingSystem: rating?.getAttribute('system')?.trim(),
              keywords: _texts(element, 'keyword'),
              year: _year(element),
              previouslyShown:
                  element.findElements('previously-shown').isNotEmpty,
              newEpisode: element.findElements('new').isNotEmpty,
            ),
          );
    }

    for (final programmes in byChannel.values) {
      programmes.sort((a, b) => a.start.compareTo(b.start));
    }

    return XmltvParseResult(
      epg: EpgData.fromMap(byChannel),
      matchedChannels: byChannel.length,
      unmatchedChannels: catalogue.unmatched,
      channelNames: catalogue.names,
    );
  }

  static String _firstText(XmlElement element, String name) {
    return _optionalText(element, name) ?? '';
  }

  static String? _optionalText(XmlElement element, String name) {
    for (final node in element.findElements(name)) {
      final value = node.innerText.trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static List<String> _texts(XmlElement element, String name) {
    return element
        .findAllElements(name)
        .map((node) => node.innerText.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  static XmlElement? _firstElement(XmlElement element, String name) {
    for (final node in element.findElements(name)) {
      return node;
    }
    return null;
  }

  static String? _optionalChildText(XmlElement element, String name) {
    for (final node in element.findElements(name)) {
      final value = node.innerText.trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  /// Text directly inside [element], ignoring nested elements such as
  /// `<rating><value>...</value></rating>`.
  static String? _optionalOwnText(XmlElement element) {
    for (final node in element.children) {
      if (node is XmlText) {
        final value = node.value.trim();
        if (value.isNotEmpty) {
          return value;
        }
      }
    }
    return null;
  }

  static ProgrammeCredits _credits(XmlElement programme) {
    final credits = _firstElement(programme, 'credits');
    if (credits == null) {
      return const ProgrammeCredits();
    }
    return ProgrammeCredits(
      directors: _texts(credits, 'director'),
      writers: _texts(credits, 'writer'),
      producers: _texts(credits, 'producer'),
      composers: _texts(credits, 'composer'),
      presenters: _texts(credits, 'presenter'),
      actors: _texts(credits, 'actor'),
      guests: _texts(credits, 'guest'),
    );
  }

  /// XMLTV's `<date>` is usually just a year, but some feeds put a full date.
  static int? _year(XmlElement element) {
    final raw = _optionalText(element, 'date');
    if (raw == null) {
      return null;
    }
    final match = RegExp(r'\b(\d{4})\b').firstMatch(raw);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static _EpisodeNumbering _episodeNumbering(XmlElement element) {
    String? onscreen;
    int? xmltvSeason;
    int? xmltvEpisode;
    for (final node in element.findElements('episode-num')) {
      final system = node.getAttribute('system')?.toLowerCase() ?? '';
      final value = node.innerText.trim();
      if (value.isEmpty) {
        continue;
      }
      if (system == 'onscreen') {
        onscreen ??= value;
        continue;
      }
      if (system == 'xmltv_ns' || system.isEmpty) {
        final parts = value.split('/').first.split('.');
        xmltvSeason ??= _parseIndex(parts, 0);
        xmltvEpisode ??= _parseIndex(parts, 1);
      }
    }

    if (onscreen != null) {
      // Pull the numbers out of "S01E05" style labels too, so details can
      // show a season/episode line even when only the on-screen label exists.
      final match = RegExp(r'S(\d+)\s*E(\d+)', caseSensitive: false)
          .firstMatch(onscreen);
      final season = xmltvSeason ??
          (match == null ? null : int.tryParse(match.group(1)!));
      final episode = xmltvEpisode ??
          (match == null ? null : int.tryParse(match.group(2)!));
      return _EpisodeNumbering(
        label: onscreen,
        season: season,
        episode: episode,
      );
    }

    if (xmltvSeason == null && xmltvEpisode == null) {
      return const _EpisodeNumbering();
    }
    final buffer = StringBuffer();
    if (xmltvSeason != null) {
      buffer.write('S${xmltvSeason.toString().padLeft(2, '0')}');
    }
    if (xmltvEpisode != null) {
      buffer.write('E${xmltvEpisode.toString().padLeft(2, '0')}');
    }
    return _EpisodeNumbering(
      label: buffer.toString(),
      season: xmltvSeason,
      episode: xmltvEpisode,
    );
  }

  static int? _parseIndex(List<String> parts, int index) {
    if (index >= parts.length) {
      return null;
    }
    final value = parts[index].trim();
    if (value.isEmpty) {
      return null;
    }
    final parsed = int.tryParse(value);
    return parsed == null ? null : parsed + 1;
  }
}

class _EpisodeNumbering {
  const _EpisodeNumbering({this.label, this.season, this.episode});

  final String? label;
  final int? season;
  final int? episode;
}

/// XMLTV timestamps look like `20261028142553 +0000`. Seconds and the zone
/// are optional in the wild, so accept both and treat a missing zone as local
/// time.
DateTime? parseXmltvTime(String? raw) {
  if (raw == null) {
    return null;
  }
  final value = raw.trim();
  if (value.isEmpty) {
    return null;
  }
  final match = RegExp(
    r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?\s*([+-]\d{2}:?\d{2})?$',
  ).firstMatch(value);
  if (match == null) {
    return null;
  }

  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.tryParse(match.group(6) ?? '') ?? 0;
  if (month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }
  if (hour > 23 || minute > 59 || second > 59) {
    return null;
  }

  final local = DateTime(year, month, day, hour, minute, second);
  final zone = match.group(7);
  if (zone == null || zone.isEmpty) {
    return local;
  }
  final sign = zone.startsWith('-') ? -1 : 1;
  final digits = zone.substring(1).replaceAll(':', '');
  final offsetHours = int.parse(digits.substring(0, 2));
  final offsetMinutes = int.parse(digits.substring(2, 4));
  final offset = Duration(hours: offsetHours, minutes: offsetMinutes);
  return DateTime.utc(year, month, day, hour, minute, second)
      .subtract(offset * sign)
      .toLocal();
}

/// Maps XMLTV channel ids and display names onto Mojac channels.
class _ChannelCatalogue {
  _ChannelCatalogue(this._channels);

  final List<Channel> _channels;
  final Map<String, String> _byNormalizedName = <String, String>{};
  final Map<String, String> _resolved = <String, String>{};
  final Map<String, String> names = <String, String>{};
  final Set<String> _unmatchedIds = <String>{};

  int get unmatched => _unmatchedIds.length;

  void register(String xmltvId, List<String> displayNames) {
    final internal = _match(xmltvId, displayNames);
    if (internal == null) {
      _unmatchedIds.add(xmltvId);
    }
    _resolved[xmltvId] = internal ?? '';
    if (internal != null) {
      names[xmltvId] = displayNames.firstOrNull ?? internal;
      for (final name in displayNames) {
        _byNormalizedName.putIfAbsent(_normalize(name), () => internal);
      }
    }
  }

  String? resolve(String xmltvId) {
    final resolved = _resolved[xmltvId];
    if (resolved != null) {
      return resolved.isEmpty ? null : resolved;
    }
    final internal = _match(xmltvId, const <String>[]);
    _resolved[xmltvId] = internal ?? '';
    if (internal == null) {
      _unmatchedIds.add(xmltvId);
    }
    return internal;
  }

  String? _match(String xmltvId, List<String> displayNames) {
    // Programmes without a channel attribute must never match channels that
    // happen to have an empty tvg-id/channel-id.
    if (xmltvId.isEmpty) {
      return null;
    }
    for (final channel in _channels) {
      if (channel.tvgId.isNotEmpty && channel.tvgId == xmltvId) {
        return channel.id;
      }
      if (channel.channelId.isNotEmpty && channel.channelId == xmltvId) {
        return channel.id;
      }
    }

    final normalizedId = _normalize(xmltvId);
    for (final channel in _channels) {
      if (_normalize(channel.tvgId) == normalizedId ||
          _normalize(channel.channelId) == normalizedId) {
        return channel.id;
      }
    }

    for (final name in displayNames) {
      final normalized = _normalize(name);
      if (normalized.isEmpty) {
        continue;
      }
      final known = _byNormalizedName[normalized];
      if (known != null) {
        return known;
      }
      for (final channel in _channels) {
        if (_normalize(channel.name) == normalized) {
          return channel.id;
        }
      }
    }

    if (displayNames.isEmpty) {
      for (final channel in _channels) {
        if (_normalize(channel.name) == normalizedId) {
          return channel.id;
        }
      }
    }
    return null;
  }
}

final RegExp _separatorPattern = RegExp(r'[^0-9A-Za-z\u0600-\u06FF]+');
final RegExp _spacePattern = RegExp(r'\s+');

String _normalize(String value) {
  return value
      .toLowerCase()
      .replaceAll(_separatorPattern, '')
      .replaceAll(_spacePattern, '');
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
