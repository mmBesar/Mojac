import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class StorageService {
  StorageService(this._prefs);

  static const String _settingsKey = 'mojac.settings.v1';
  static const String _sourcesKey = 'mojac.sources.v1';

  final SharedPreferences _prefs;

  static Future<StorageService> create() async {
    return StorageService(await SharedPreferences.getInstance());
  }

  AppSettings loadSettings() {
    final raw = _prefs.getString(_settingsKey);
    if (raw == null || raw.isEmpty) {
      return AppSettings.defaults();
    }
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) {
        return AppSettings.fromJson(json);
      }
      if (json is Map) {
        return AppSettings.fromJson(json.cast<String, dynamic>());
      }
    } catch (_) {
      // Corrupt or outdated prefs should never prevent the app from starting.
    }
    return AppSettings.defaults();
  }

  Future<void> saveSettings(AppSettings settings) {
    return _prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  List<SourceConfig> loadSources() {
    final raw = _prefs.getString(_sourcesKey);
    if (raw == null || raw.isEmpty) {
      return <SourceConfig>[];
    }
    try {
      final json = jsonDecode(raw);
      if (json is! List) {
        return <SourceConfig>[];
      }
      final sources = <SourceConfig>[];
      for (final item in json) {
        try {
          if (item is Map<String, dynamic>) {
            sources.add(SourceConfig.fromJson(item));
          } else if (item is Map) {
            sources.add(SourceConfig.fromJson(item.cast<String, dynamic>()));
          }
        } catch (_) {
          // Skip one malformed source instead of discarding all of them.
        }
      }
      return sources;
    } catch (_) {
      return <SourceConfig>[];
    }
  }

  Future<void> saveSources(List<SourceConfig> sources) {
    final encoded = jsonEncode(
      sources.map((source) => source.toJson()).toList(growable: false),
    );
    return _prefs.setString(_sourcesKey, encoded);
  }
}
