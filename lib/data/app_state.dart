// The storage parameter cannot use an initializing formal because named
// parameters cannot be private.
// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/catppuccin.dart';

import 'models.dart';
import 'playlist_loader.dart';
import 'storage.dart';

/// Central application state: persisted sources and settings, the currently
/// loaded channel/EPG snapshot, and a lightweight ticker so "now playing"
/// information stays current without reopening the guide.
class AppState extends ChangeNotifier {
  AppState({
    required StorageService storage,
    PlaylistLoader? loader,
  })  : _storage = storage,
        _loader = loader ?? PlaylistLoader();

  static Future<AppState> create({PlaylistLoader? loader}) async {
    final storage = await StorageService.create();
    final state = AppState(storage: storage, loader: loader);
    state._restore();
    return state;
  }

  final StorageService _storage;
  final PlaylistLoader _loader;
  Timer? _ticker;
  int _loadGeneration = 0;
  DateTime? _lastAutoRefresh;

  late AppSettings _settings;
  List<SourceConfig> _sources = <SourceConfig>[];
  SourceContent? _content;
  String? _error;
  Set<LoadWarning> _warnings = <LoadWarning>{};
  DateTime _now = DateTime.now();
  bool _loading = false;
  bool _restored = false;
  bool _initialLoadStarted = false;

  AppSettings get settings => _settings;
  List<SourceConfig> get sources => List<SourceConfig>.unmodifiable(_sources);
  List<Channel> get channels =>
      _content?.playlist.channels ?? const <Channel>[];
  EpgData get epg => _content?.epg ?? EpgData.empty();
  SourceContent? get content => _content;
  DateTime get now => _now;
  bool get isLoading => _loading;
  bool get restored => _restored;
  bool get hasContent => _content != null;
  String? get error => _error;
  Set<LoadWarning> get warnings => Set<LoadWarning>.unmodifiable(_warnings);
  String? get xmltvLocation => _content?.xmltvLocation;
  DateTime? get lastLoaded => _content?.loadedAt;

  SourceConfig? get activeSource {
    final id = _settings.activeSourceId;
    if (id == null) {
      return _sources.isEmpty ? null : _sources.first;
    }
    for (final source in _sources) {
      if (source.id == id) {
        return source;
      }
    }
    return _sources.isEmpty ? null : _sources.first;
  }

  void _restore() {
    _settings = _storage.loadSettings();
    _sources = _storage.loadSources();

    if (_sources.isEmpty) {
      _settings = _settings.copyWith(activeSourceId: null);
    } else if (activeSource == null) {
      _settings = _settings.copyWith(activeSourceId: _sources.first.id);
    } else if (_settings.activeSourceId != activeSource!.id) {
      _settings = _settings.copyWith(activeSourceId: activeSource!.id);
    }

    _restored = true;
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      _now = DateTime.now();
      notifyListeners();
      unawaited(_autoRefreshIfDue());
    });
    notifyListeners();

    if (activeSource != null && !_initialLoadStarted) {
      _initialLoadStarted = true;
      unawaited(load());
    }
  }

  /// Refreshes quietly when the interval chosen in Settings has elapsed. The
  /// ticker calls this, so changing the interval needs no timer restart.
  Future<void> _autoRefreshIfDue() async {
    final minutes = _settings.refreshMinutes;
    if (minutes <= 0 || _loading || activeSource == null) {
      return;
    }
    // Track attempts separately from the content's timestamp: a network
    // failure returns the old cache, whose loadedAt would otherwise make the
    // next thirty-second tick retry immediately and hammer a downed host.
    final last = _lastAutoRefresh ?? _content?.loadedAt;
    if (last == null) {
      return;
    }
    if (DateTime.now().difference(last) < Duration(minutes: minutes)) {
      return;
    }
    _lastAutoRefresh = DateTime.now();
    await load();
  }

  Future<void> load() async {
    final source = activeSource;
    if (source == null) {
      _content = null;
      _warnings = <LoadWarning>{};
      _error = null;
      _loading = false;
      notifyListeners();
      return;
    }

    final generation = ++_loadGeneration;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final content = await _loader.load(
        source,
        guideHours: _settings.guideHours,
      );
      if (generation != _loadGeneration) {
        return;
      }
      _content = content;
      _warnings = content.warnings;
      _lastErrorMessage = null;
      _error = null;
      _now = DateTime.now();
    } catch (error) {
      if (generation != _loadGeneration) {
        return;
      }
      _lastErrorMessage = _messageFor(error);
      _error = _lastErrorMessage;
      if (_content == null || _content!.playlist.channels.isEmpty) {
        _warnings = <LoadWarning>{};
      }
    } finally {
      if (generation == _loadGeneration) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  String? _lastErrorMessage;

  /// Returns the last error; kept separately from [error] so the UI can show
  /// it in a retry banner while continuing to display cached channels.
  String? get lastErrorMessage => _lastErrorMessage;

  Future<void> refresh() => load();

  Future<void> selectSource(String sourceId) async {
    final exists = _sources.any((source) => source.id == sourceId);
    if (!exists) {
      return;
    }
    _settings = _settings.copyWith(
      activeSourceId: sourceId,
      // Groups are playlist-specific; keeping the old one would hide every
      // channel on the new source.
      groupFilter: null,
    );
    _content = null;
    _warnings = <LoadWarning>{};
    _error = null;
    await _storage.saveSettings(_settings);
    notifyListeners();
    unawaited(load());
  }

  Future<void> addSource(SourceConfig source) async {
    _sources = <SourceConfig>[..._sources, source];
    _settings = _settings.copyWith(
      activeSourceId: source.id,
      groupFilter: null,
    );
    await _storage.saveSources(_sources);
    await _storage.saveSettings(_settings);
    _content = null;
    notifyListeners();
    unawaited(load());
  }

  Future<void> updateSource(SourceConfig source) async {
    final index = _sources.indexWhere((item) => item.id == source.id);
    if (index < 0) {
      return;
    }
    final updated = <SourceConfig>[..._sources];
    updated[index] = source;
    _sources = updated;
    await _storage.saveSources(_sources);
    notifyListeners();
    if (activeSource?.id == source.id) {
      unawaited(load());
    }
  }

  Future<void> deleteSource(String sourceId) async {
    // Work this out before replacing the list: after that, [activeSource] would
    // already have fallen back to a different source.
    final wasActive = activeSource?.id == sourceId;
    final remaining =
        _sources.where((source) => source.id != sourceId).toList(growable: false);
    _sources = remaining;
    if (wasActive) {
      _settings = _settings.copyWith(
        activeSourceId: remaining.isEmpty ? null : remaining.first.id,
      );
      _content = null;
      _warnings = <LoadWarning>{};
      _error = null;
    }
    await _storage.saveSources(_sources);
    await _storage.saveSettings(_settings);
    notifyListeners();
    if (wasActive && remaining.isNotEmpty) {
      unawaited(load());
    }
  }

  Future<void> updateSettings(AppSettings settings) async {
    _settings = settings;
    await _storage.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> setThemeFamily(ThemeFamily family) {
    return updateSettings(_settings.copyWith(themeFamily: family));
  }

  Future<void> setAccent(ThemeAccent accent) {
    return updateSettings(_settings.copyWith(accent: accent));
  }

  Future<void> setLanguage(AppLanguage language) {
    return updateSettings(_settings.copyWith(language: language));
  }

  Future<void> setUse24HourTime(bool value) {
    return updateSettings(_settings.copyWith(use24HourTime: value));
  }

  Future<void> setNativePlayer(bool value) {
    return updateSettings(_settings.copyWith(nativePlayer: value));
  }

  Future<void> setGuideHours(int hours) async {
    final clamped = hours.clamp(12, 168).toInt();
    if (_settings.guideHours == clamped) {
      return;
    }
    await updateSettings(_settings.copyWith(guideHours: clamped));
    unawaited(load());
  }

  Future<void> setRefreshMinutes(int minutes) {
    return updateSettings(
      _settings.copyWith(refreshMinutes: minutes.clamp(0, 24 * 60).toInt()),
    );
  }

  Future<void> setShowChannelBanner(bool value) {
    return updateSettings(_settings.copyWith(showChannelBanner: value));
  }

  Future<void> setDefaultAudioLanguage(String? language) {
    return updateSettings(
      _settings.copyWith(defaultAudioLanguage: _language(language)),
    );
  }

  Future<void> setDefaultSubtitleLanguage(String? language) {
    return updateSettings(
      _settings.copyWith(defaultSubtitleLanguage: _language(language)),
    );
  }

  String? _language(String? value) {
    final trimmed = value?.trim().toLowerCase();
    if (trimmed == null || trimmed.isEmpty || trimmed == 'auto') {
      return null;
    }
    return trimmed;
  }

  Future<void> setPlayerVolume(double volume) {
    final clamped = volume.clamp(0, 100).toDouble();
    if ((_settings.playerVolume - clamped).abs() < 0.01) {
      return Future<void>.value();
    }
    return updateSettings(_settings.copyWith(playerVolume: clamped));
  }

  Future<void> setPlayerAspect(String aspect) {
    if (!kPlayerAspects.contains(aspect)) {
      return Future<void>.value();
    }
    return updateSettings(_settings.copyWith(playerAspect: aspect));
  }

  Future<void> setPlayerDeinterlace(String mode) {
    if (!kPlayerDeinterlaceModes.contains(mode)) {
      return Future<void>.value();
    }
    return updateSettings(_settings.copyWith(playerDeinterlace: mode));
  }

  /// Remembers the audio and subtitle track picked for one channel. The map is
  /// capped so a long-lived install cannot grow the settings blob forever;
  /// Dart maps keep insertion order, so the oldest channel is dropped first.
  Future<void> rememberChannelTracks(
    String channelId, {
    required String audioId,
    required String subtitleId,
  }) {
    final value = '$audioId|$subtitleId';
    if (_settings.channelTracks[channelId] == value) {
      return Future<void>.value();
    }
    final tracks = Map<String, String>.from(_settings.channelTracks);
    tracks.remove(channelId);
    tracks[channelId] = value;
    if (tracks.length > 400) {
      tracks.remove(tracks.keys.first);
    }
    return updateSettings(_settings.copyWith(channelTracks: tracks));
  }

  Future<void> forgetChannelTracks(String channelId) {
    if (!_settings.channelTracks.containsKey(channelId)) {
      return Future<void>.value();
    }
    final tracks = Map<String, String>.from(_settings.channelTracks)
      ..remove(channelId);
    return updateSettings(_settings.copyWith(channelTracks: tracks));
  }

  /// Group chips on Channels and Guide share this value, so picking a group on
  /// one page filters the other too.
  Future<void> setGroupFilter(String? group) {
    final normalized = group == null || group.trim().isEmpty
        ? null
        : group.trim();
    if (_settings.groupFilter == normalized) {
      return Future<void>.value();
    }
    return updateSettings(_settings.copyWith(groupFilter: normalized));
  }

  bool isFavorite(String channelId) =>
      _settings.favoriteChannelIds.contains(channelId);

  List<Channel> get favoriteChannels => channels
      .where((channel) => isFavorite(channel.id))
      .toList(growable: false);

  Future<void> toggleFavorite(String channelId) async {
    final favorites = _settings.favoriteChannelIds.toList(growable: true);
    if (!favorites.remove(channelId)) {
      favorites.insert(0, channelId);
    }
    await updateSettings(
      _settings.copyWith(favoriteChannelIds: favorites),
    );
  }

  Future<SourceContent> probe(SourceConfig source) =>
      _loader.probe(source, guideHours: _settings.guideHours);

  String _messageFor(Object error) {
    if (error is SourceLoadException) {
      return error.message;
    }
    return error.toString();
  }

  @override
  void dispose() {
    _loadGeneration++;
    _ticker?.cancel();
    super.dispose();
  }
}
