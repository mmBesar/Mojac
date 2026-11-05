import 'dart:math';

import '../core/catppuccin.dart';

/// A user-configured playlist/EPG pair. Every source keeps its own M3U and
/// XMLTV location, and its own TLS policy.
enum EndpointKind { url, file }

class SourceEndpoint {
  const SourceEndpoint({required this.value, this.kind = EndpointKind.url});

  final String value;
  final EndpointKind kind;

  bool get isFile => kind == EndpointKind.file;
  bool get isEmpty => value.trim().isEmpty;

  SourceEndpoint copyWith({String? value, EndpointKind? kind}) {
    return SourceEndpoint(
      value: value ?? this.value,
      kind: kind ?? this.kind,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'value': value,
        'kind': kind.name,
      };

  factory SourceEndpoint.fromJson(dynamic json) {
    if (json is String) {
      return SourceEndpoint(value: json);
    }
    if (json is Map) {
      final map = json.cast<String, dynamic>();
      final kindName = map['kind'] as String? ?? 'url';
      return SourceEndpoint(
        value: map['value'] as String? ?? '',
        kind: EndpointKind.values.firstWhere(
          (value) => value.name == kindName,
          orElse: () => EndpointKind.url,
        ),
      );
    }
    return const SourceEndpoint(value: '');
  }
}

/// Where a source comes from. Plain IPTV sources keep the two endpoints the
/// user typed; Tunarr and ErsatzTV only need the server address because their
/// playlist and guide live at fixed paths.
enum SourceProvider { iptv, tunarr, ersatzTv }

extension SourceProviderX on SourceProvider {
  bool get isServer => this != SourceProvider.iptv;

  String get playlistPath => switch (this) {
        SourceProvider.iptv => '',
        SourceProvider.tunarr => '/api/channels.m3u',
        SourceProvider.ersatzTv => '/iptv/channels.m3u',
      };

  String get guidePath => switch (this) {
        SourceProvider.iptv => '',
        SourceProvider.tunarr => '/api/xmltv.xml',
        SourceProvider.ersatzTv => '/iptv/xmltv.xml',
      };

  String get label => switch (this) {
        SourceProvider.iptv => 'IPTV',
        SourceProvider.tunarr => 'Tunarr',
        SourceProvider.ersatzTv => 'ErsatzTV',
      };
}

const List<String> _serverEndpointSuffixes = <String>[
  '/api/channels.m3u',
  '/api/xmltv.xml',
  '/iptv/channels.m3u',
  '/iptv/xmltv.xml',
];

/// Turns whatever the user pasted into a bare server base URL.
///
/// Accepts a bare host (`tunarr.lan:8000`), a full endpoint URL from either
/// provider, or a server URL with a trailing slash.
String normalizeServerBase(String raw) {
  var value = raw.trim();
  if (value.isEmpty) {
    return '';
  }
  final lower = value.toLowerCase();
  for (final suffix in _serverEndpointSuffixes) {
    if (lower.endsWith(suffix)) {
      value = value.substring(0, value.length - suffix.length);
      break;
    }
  }
  if (!value.contains('://')) {
    value = 'https://$value';
  }
  return value.replaceAll(RegExp(r'/+$'), '');
}

String providerPlaylistUrl(SourceProvider provider, String server) {
  final base = normalizeServerBase(server);
  return base.isEmpty ? '' : '$base${provider.playlistPath}';
}

String providerGuideUrl(SourceProvider provider, String server) {
  final base = normalizeServerBase(server);
  return base.isEmpty ? '' : '$base${provider.guidePath}';
}

class SourceConfig {
  const SourceConfig({
    required this.id,
    required this.name,
    required this.m3u,
    required this.epg,
    this.allowInsecureCerts = false,
    this.provider = SourceProvider.iptv,
    this.serverUrl = '',
  });

  final String id;
  final String name;
  final SourceEndpoint m3u;
  final SourceEndpoint epg;
  final bool allowInsecureCerts;
  final SourceProvider provider;

  /// Only used by [SourceProvider.tunarr] and [SourceProvider.ersatzTv], so the
  /// editor can show and edit the single address the user entered.
  final String serverUrl;

  SourceConfig copyWith({
    String? name,
    SourceEndpoint? m3u,
    SourceEndpoint? epg,
    bool? allowInsecureCerts,
    SourceProvider? provider,
    String? serverUrl,
  }) {
    return SourceConfig(
      id: id,
      name: name ?? this.name,
      m3u: m3u ?? this.m3u,
      epg: epg ?? this.epg,
      allowInsecureCerts: allowInsecureCerts ?? this.allowInsecureCerts,
      provider: provider ?? this.provider,
      serverUrl: serverUrl ?? this.serverUrl,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'm3u': m3u.toJson(),
        'epg': epg.toJson(),
        'allowInsecureCerts': allowInsecureCerts,
        'provider': provider.name,
        'serverUrl': serverUrl,
      };

  factory SourceConfig.fromJson(Map<String, dynamic> json) {
    final rawId = (json['id'] as String?)?.trim() ?? '';
    final rawName = (json['name'] as String?)?.trim() ?? '';
    final providerName = json['provider'] as String?;
    return SourceConfig(
      id: rawId.isEmpty ? generateSourceId() : rawId,
      name: rawName.isEmpty ? 'Source' : rawName,
      m3u: SourceEndpoint.fromJson(json['m3u']),
      epg: SourceEndpoint.fromJson(json['epg']),
      allowInsecureCerts: json['allowInsecureCerts'] as bool? ?? false,
      provider: _enumByName(
        SourceProvider.values,
        providerName,
        SourceProvider.iptv,
      ),
      serverUrl: (json['serverUrl'] as String?)?.trim() ?? '',
    );
  }
}

class Channel {
  const Channel({
    required this.id,
    required this.sourceId,
    required this.name,
    required this.number,
    required this.url,
    this.tvgId = '',
    this.channelId = '',
    this.logoUrl,
    this.group,
  });

  /// Stable internal identity, unique per source.
  final String id;
  final String sourceId;
  final String name;
  final String number;
  final String url;
  final String tvgId;
  final String channelId;
  final String? logoUrl;
  final String? group;

  String get displayNumber => number.isEmpty ? '—' : number;
}

/// People credited for a programme. XMLTV separates the roles, so Mojac keeps
/// them apart instead of flattening everything into one "cast" line.
class ProgrammeCredits {
  const ProgrammeCredits({
    this.directors = const <String>[],
    this.writers = const <String>[],
    this.producers = const <String>[],
    this.composers = const <String>[],
    this.presenters = const <String>[],
    this.actors = const <String>[],
    this.guests = const <String>[],
  });

  final List<String> directors;
  final List<String> writers;
  final List<String> producers;
  final List<String> composers;
  final List<String> presenters;
  final List<String> actors;
  final List<String> guests;

  bool get isEmpty =>
      directors.isEmpty &&
      writers.isEmpty &&
      producers.isEmpty &&
      composers.isEmpty &&
      presenters.isEmpty &&
      actors.isEmpty &&
      guests.isEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (directors.isNotEmpty) 'directors': directors,
        if (writers.isNotEmpty) 'writers': writers,
        if (producers.isNotEmpty) 'producers': producers,
        if (composers.isNotEmpty) 'composers': composers,
        if (presenters.isNotEmpty) 'presenters': presenters,
        if (actors.isNotEmpty) 'actors': actors,
        if (guests.isNotEmpty) 'guests': guests,
      };

  factory ProgrammeCredits.fromJson(Map<String, dynamic> json) {
    List<String> read(String key) =>
        (json[key] as List?)?.whereType<String>().toList(growable: false) ??
        const <String>[];
    return ProgrammeCredits(
      directors: read('directors'),
      writers: read('writers'),
      producers: read('producers'),
      composers: read('composers'),
      presenters: read('presenters'),
      actors: read('actors'),
      guests: read('guests'),
    );
  }
}

class Programme {
  const Programme({
    required this.channelId,
    required this.start,
    required this.stop,
    required this.title,
    this.subTitle,
    this.description,
    this.categories = const <String>[],
    this.images = const <String>[],
    this.episode,
    this.season,
    this.episodeNumber,
    this.credits = const ProgrammeCredits(),
    this.rating,
    this.ratingSystem,
    this.keywords = const <String>[],
    this.year,
    this.previouslyShown = false,
    this.newEpisode = false,
  });

  final String channelId;
  final DateTime start;
  final DateTime stop;
  final String title;
  final String? subTitle;
  final String? description;
  final List<String> categories;

  /// Every artwork URL advertised by the guide, in document order. Tunarr and
  /// ErsatzTV both publish multiple `<icon>` tags (a poster and a still), and
  /// Mojac keeps them all so the detail sheet can fall back gracefully.
  final List<String> images;
  final String? episode;

  /// Structured numbering, when XMLTV exposes it separately from [episode].
  final int? season;
  final int? episodeNumber;
  final ProgrammeCredits credits;
  final String? rating;
  final String? ratingSystem;
  final List<String> keywords;

  /// Year from XMLTV's `<date>` element.
  final int? year;
  final bool previouslyShown;
  final bool newEpisode;

  /// First artwork URL. Kept as a getter so the many call sites that only need
  /// one image stay simple.
  String? get iconUrl => images.isEmpty ? null : images.first;

  /// A title that includes the episode number when the guide does not already
  /// put it in the sub-title.
  String get displayTitle {
    final number = episode;
    if (number == null || number.isEmpty) {
      return title;
    }
    final haystack = '${subTitle ?? ''} $title'.toUpperCase();
    if (haystack.contains(number.toUpperCase())) {
      return title;
    }
    return '$title · $number';
  }

  bool isLiveAt(DateTime now) => !now.isBefore(start) && now.isBefore(stop);

  bool overlaps(DateTime windowStart, DateTime windowEnd) =>
      stop.isAfter(windowStart) && start.isBefore(windowEnd);

  double progressAt(DateTime now) {
    final total = stop.difference(start).inMilliseconds;
    if (total <= 0) {
      return 0;
    }
    return (now.difference(start).inMilliseconds / total).clamp(0.0, 1.0);
  }
}

class Playlist {
  const Playlist({required this.channels, this.xmltvUrl});

  final List<Channel> channels;

  /// The `url-tvg` / `x-tvg-url` advertised by the M3U header, if any.
  final String? xmltvUrl;
}

class EpgData {
  EpgData._(this._byChannel, this.programmeCount);

  factory EpgData.empty() => EpgData._(const <String, List<Programme>>{}, 0);

  factory EpgData.fromMap(Map<String, List<Programme>> byChannel) {
    final frozen = <String, List<Programme>>{};
    var count = 0;
    for (final entry in byChannel.entries) {
      if (entry.value.isEmpty) {
        continue;
      }
      final programmes = List<Programme>.unmodifiable(entry.value);
      frozen[entry.key] = programmes;
      count += programmes.length;
    }
    return EpgData._(Map<String, List<Programme>>.unmodifiable(frozen), count);
  }

  final Map<String, List<Programme>> _byChannel;
  final int programmeCount;

  int get matchedChannels => _byChannel.length;
  bool get isEmpty => programmeCount == 0;

  List<Programme> programmesFor(Channel channel) =>
      _byChannel[channel.id] ?? const <Programme>[];

  Programme? nowFor(Channel channel, DateTime now) {
    final programmes = programmesFor(channel);
    // Programmes are sorted by start. Only the last programme that has begun
    // can still be on air, so binary-search its position instead of walking
    // the whole day for every visible channel on every tick.
    final index = _firstStartAfter(programmes, now);
    if (index == 0) {
      return null;
    }
    final candidate = programmes[index - 1];
    return candidate.isLiveAt(now) ? candidate : null;
  }

  Programme? nextFor(Channel channel, DateTime now) {
    final programmes = programmesFor(channel);
    final index = _firstStartAfter(programmes, now);
    return index < programmes.length ? programmes[index] : null;
  }

  List<Programme> forWindow(
    Channel channel,
    DateTime windowStart,
    DateTime windowEnd,
  ) {
    final programmes = programmesFor(channel);
    if (programmes.isEmpty || !programmes.first.start.isBefore(windowEnd)) {
      return const <Programme>[];
    }
    // Programmes are sorted by start, so jump close to the window instead of
    // walking the whole day. One step back keeps a programme that started
    // before the window but is still running.
    final first = _firstStartAtOrAfter(programmes, windowStart);
    final from = first > 0 ? first - 1 : 0;
    final result = <Programme>[];
    for (var index = from; index < programmes.length; index++) {
      final programme = programmes[index];
      if (!programme.start.isBefore(windowEnd)) {
        break;
      }
      if (programme.overlaps(windowStart, windowEnd)) {
        result.add(programme);
      }
    }
    return result;
  }

  /// Index of the first programme starting at or after [time].
  static int _firstStartAtOrAfter(List<Programme> programmes, DateTime time) {
    var low = 0;
    var high = programmes.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (programmes[middle].start.isBefore(time)) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  /// Index of the first programme starting strictly after [time].
  static int _firstStartAfter(List<Programme> programmes, DateTime time) {
    var low = 0;
    var high = programmes.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (programmes[middle].start.isAfter(time)) {
        high = middle;
      } else {
        low = middle + 1;
      }
    }
    return low;
  }
}

enum LoadWarning {
  noEpgEndpoint,
  playlistFromCache,
  epgFromCache,
  epgUnavailable,
  epgEmpty,
}

enum AppLanguage { system, english, arabic }

extension AppLanguageX on AppLanguage {
  String? get localeCode => switch (this) {
        AppLanguage.system => null,
        AppLanguage.english => 'en',
        AppLanguage.arabic => 'ar',
      };
}

/// Aspects the built-in player can force. `auto` is the stream's own ratio and
/// is the only value that also clears mpv's `video-aspect-override`.
const List<String> kPlayerAspects = <String>[
  'auto',
  'fill',
  'stretch',
  '16:9',
  '4:3',
  '21:9',
];

const List<String> kPlayerDeinterlaceModes = <String>['auto', 'on', 'off'];

/// Video output used by the built-in player. `auto` follows the platform
/// (GPU where available) and `software` is the fallback for machines whose
/// EGL/Mesa stack cannot present the hardware texture.
const List<String> kPlayerRenderers = <String>['auto', 'gpu', 'software'];

/// Layouts offered by the channels page.
const List<String> kChannelViews = <String>['list', 'grid', 'compact'];

class AppSettings {
  const AppSettings({
    required this.themeFamily,
    required this.accent,
    required this.language,
    required this.use24HourTime,
    this.nativePlayer = true,
    this.activeSourceId,
    this.guideHours = 12,
    this.refreshMinutes = 0,
    this.groupFilter,
    this.favoriteChannelIds = const <String>[],
    this.showChannelBanner = true,
    this.defaultAudioLanguage,
    this.defaultSubtitleLanguage,
    this.playerVolume = 100,
    this.playerAspect = 'auto',
    this.playerDeinterlace = 'auto',
    this.playerRenderer = 'auto',
    this.channelsView = 'list',
    this.channelTracks = const <String, String>{},
  });

  factory AppSettings.defaults() => const AppSettings(
        themeFamily: ThemeFamily.system,
        accent: ThemeAccent.mauve,
        language: AppLanguage.system,
        use24HourTime: false,
      );

  final ThemeFamily themeFamily;
  final ThemeAccent accent;
  final AppLanguage language;
  final bool use24HourTime;

  /// Desktop only: play with the system mpv instead of media_kit's embedded
  /// engine. It is the default because the embedded Linux video output only
  /// has a software texture, while a real mpv decodes with the GPU and goes
  /// properly fullscreen.
  final bool nativePlayer;
  final String? activeSourceId;

  /// How many hours the guide timeline spans. Twelve was the old fixed value;
  /// longer windows make overnight planning possible.
  final int guideHours;

  /// Automatic background refresh interval in minutes. Zero disables it.
  final int refreshMinutes;

  /// The group chip selected on Channels and Guide, shared by both pages.
  final String? groupFilter;

  /// Channel ids starred by the user in the current playlist snapshot.
  final List<String> favoriteChannelIds;

  /// Show the set-top-box style channel banner for a few seconds whenever a
  /// channel opens. It never depends on the guide having data.
  final bool showChannelBanner;

  /// Language code (`en`, `ar`, …) preferred for audio. Null means automatic.
  final String? defaultAudioLanguage;

  /// Language code preferred for subtitles, `off` to start with subtitles
  /// disabled, or null for automatic.
  final String? defaultSubtitleLanguage;

  /// Last volume set by the user, restored on the next channel.
  final double playerVolume;

  /// One of [kPlayerAspects].
  final String playerAspect;

  /// One of [kPlayerDeinterlaceModes].
  final String playerDeinterlace;

  /// One of [kPlayerRenderers]. The built-in player uses it on desktop, where
  /// the GPU texture can be replaced by the slower but reliable software path.
  final String playerRenderer;

  /// How the channels page lays out its list: `list`, `grid` or `compact`.
  final String channelsView;

  /// Per-channel audio/subtitle choice, encoded as `audioId|subtitleId`.
  final Map<String, String> channelTracks;

  AppSettings copyWith({
    ThemeFamily? themeFamily,
    ThemeAccent? accent,
    AppLanguage? language,
    bool? use24HourTime,
    bool? nativePlayer,
    Object? activeSourceId = _unset,
    int? guideHours,
    int? refreshMinutes,
    Object? groupFilter = _unset,
    List<String>? favoriteChannelIds,
    bool? showChannelBanner,
    Object? defaultAudioLanguage = _unset,
    Object? defaultSubtitleLanguage = _unset,
    double? playerVolume,
    String? playerAspect,
    String? playerDeinterlace,
    String? playerRenderer,
    String? channelsView,
    Map<String, String>? channelTracks,
  }) {
    return AppSettings(
      themeFamily: themeFamily ?? this.themeFamily,
      accent: accent ?? this.accent,
      language: language ?? this.language,
      use24HourTime: use24HourTime ?? this.use24HourTime,
      nativePlayer: nativePlayer ?? this.nativePlayer,
      activeSourceId: identical(activeSourceId, _unset)
          ? this.activeSourceId
          : activeSourceId as String?,
      guideHours: guideHours ?? this.guideHours,
      refreshMinutes: refreshMinutes ?? this.refreshMinutes,
      groupFilter: identical(groupFilter, _unset)
          ? this.groupFilter
          : groupFilter as String?,
      favoriteChannelIds: favoriteChannelIds ?? this.favoriteChannelIds,
      showChannelBanner: showChannelBanner ?? this.showChannelBanner,
      defaultAudioLanguage: identical(defaultAudioLanguage, _unset)
          ? this.defaultAudioLanguage
          : defaultAudioLanguage as String?,
      defaultSubtitleLanguage: identical(defaultSubtitleLanguage, _unset)
          ? this.defaultSubtitleLanguage
          : defaultSubtitleLanguage as String?,
      playerVolume: (playerVolume ?? this.playerVolume).clamp(0, 100).toDouble(),
      playerAspect: playerAspect ?? this.playerAspect,
      playerDeinterlace: playerDeinterlace ?? this.playerDeinterlace,
      playerRenderer: playerRenderer ?? this.playerRenderer,
      channelsView: channelsView ?? this.channelsView,
      channelTracks: channelTracks ?? this.channelTracks,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'themeFamily': themeFamily.name,
        'accent': accent.name,
        'language': language.name,
        'use24HourTime': use24HourTime,
        'nativePlayer': nativePlayer,
        'activeSourceId': activeSourceId,
        'guideHours': guideHours,
        'refreshMinutes': refreshMinutes,
        'groupFilter': groupFilter,
        'favorites': favoriteChannelIds,
        'showChannelBanner': showChannelBanner,
        'defaultAudioLanguage': defaultAudioLanguage,
        'defaultSubtitleLanguage': defaultSubtitleLanguage,
        'playerVolume': playerVolume,
        'playerAspect': playerAspect,
        'playerDeinterlace': playerDeinterlace,
        'playerRenderer': playerRenderer,
        'channelsView': channelsView,
        'channelTracks': channelTracks,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final rawGroup = (json['groupFilter'] as String?)?.trim();
    final rawTracks = json['channelTracks'];
    final channelTracks = <String, String>{};
    if (rawTracks is Map) {
      for (final entry in rawTracks.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is String && value is String && value.contains('|')) {
          channelTracks[key] = value;
        }
      }
    }
    return AppSettings(
      themeFamily: _enumByName(
        ThemeFamily.values,
        json['themeFamily'] as String?,
        ThemeFamily.system,
      ),
      accent: _enumByName(
        ThemeAccent.values,
        json['accent'] as String?,
        ThemeAccent.mauve,
      ),
      language: _enumByName(
        AppLanguage.values,
        json['language'] as String?,
        AppLanguage.system,
      ),
      use24HourTime: json['use24HourTime'] as bool? ?? false,
      nativePlayer: json['nativePlayer'] as bool? ?? true,
      activeSourceId: json['activeSourceId'] as String?,
      guideHours:
          ((json['guideHours'] as num?)?.toInt() ?? 12).clamp(12, 168).toInt(),
      refreshMinutes: ((json['refreshMinutes'] as num?)?.toInt() ?? 0)
          .clamp(0, 24 * 60)
          .toInt(),
      groupFilter: rawGroup == null || rawGroup.isEmpty ? null : rawGroup,
      favoriteChannelIds:
          (json['favorites'] as List?)?.whereType<String>().toList(
                growable: false,
              ) ??
              const <String>[],
      showChannelBanner: json['showChannelBanner'] as bool? ?? true,
      defaultAudioLanguage: _cleanLanguage(json['defaultAudioLanguage']),
      defaultSubtitleLanguage: _cleanLanguage(json['defaultSubtitleLanguage']),
      playerVolume:
          ((json['playerVolume'] as num?)?.toDouble() ?? 100).clamp(0, 100).toDouble(),
      playerAspect: _oneOf(json['playerAspect'], kPlayerAspects, 'auto'),
      playerDeinterlace: _oneOf(
        json['playerDeinterlace'],
        kPlayerDeinterlaceModes,
        'auto',
      ),
      playerRenderer: _oneOf(
        json['playerRenderer'],
        kPlayerRenderers,
        'auto',
      ),
      channelsView: _oneOf(
        json['channelsView'],
        kChannelViews,
        'list',
      ),
      channelTracks: Map<String, String>.unmodifiable(channelTracks),
    );
  }
}

String? _cleanLanguage(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim().toLowerCase();
  return trimmed.isEmpty || trimmed == 'auto' ? null : trimmed;
}

String _oneOf(Object? value, List<String> options, String fallback) {
  return value is String && options.contains(value) ? value : fallback;
}

const Object _unset = Object();

T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
  if (name == null) {
    return fallback;
  }
  for (final value in values) {
    if (value.name == name) {
      return value;
    }
  }
  return fallback;
}

String generateSourceId() {
  final random = Random.secure();
  final bytes = List<int>.generate(8, (_) => random.nextInt(256));
  final suffix = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}$suffix';
}
