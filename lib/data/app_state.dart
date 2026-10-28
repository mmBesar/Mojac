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
    });
    notifyListeners();

    if (activeSource != null && !_initialLoadStarted) {
      _initialLoadStarted = true;
      unawaited(load());
    }
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
      final content = await _loader.load(source);
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
    _settings = _settings.copyWith(activeSourceId: sourceId);
    _content = null;
    _warnings = <LoadWarning>{};
    _error = null;
    await _storage.saveSettings(_settings);
    notifyListeners();
    unawaited(load());
  }

  Future<void> addSource(SourceConfig source) async {
    _sources = <SourceConfig>[..._sources, source];
    _settings = _settings.copyWith(activeSourceId: source.id);
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

  Future<SourceContent> probe(SourceConfig source) => _loader.probe(source);

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
