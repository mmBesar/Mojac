import 'package:flutter_test/flutter_test.dart';
import 'package:mojac/core/catppuccin.dart';
import 'package:mojac/data/models.dart';
import 'package:mojac/data/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('settings and sources survive a JSON round trip', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final storage = await StorageService.create();

    final settings = AppSettings.defaults().copyWith(
      themeFamily: ThemeFamily.amoled,
      accent: ThemeAccent.peach,
      language: AppLanguage.arabic,
      use24HourTime: true,
      activeSourceId: 'home',
    );
    await storage.saveSettings(settings);

    final loaded = storage.loadSettings();
    expect(loaded.themeFamily, ThemeFamily.amoled);
    expect(loaded.accent, ThemeAccent.peach);
    expect(loaded.language, AppLanguage.arabic);
    expect(loaded.use24HourTime, isTrue);
    expect(loaded.activeSourceId, 'home');

    final source = SourceConfig(
      id: 'home',
      name: 'تونار المنزل',
      m3u: const SourceEndpoint(value: 'https://tunarr.hs.lan/api/channels.m3u'),
      epg: const SourceEndpoint(
        value: '/home/user/guide.xml',
        kind: EndpointKind.file,
      ),
      allowInsecureCerts: true,
    );
    await storage.saveSources(<SourceConfig>[source]);

    final sources = storage.loadSources();
    expect(sources, hasLength(1));
    expect(sources.single.name, 'تونار المنزل');
    expect(sources.single.m3u.kind, EndpointKind.url);
    expect(sources.single.epg.kind, EndpointKind.file);
    expect(sources.single.allowInsecureCerts, isTrue);
  });

  test('invalid preference JSON falls back to defaults', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mojac.settings.v1': 'not json',
      'mojac.sources.v1': '{"unexpected": true}',
    });
    final storage = await StorageService.create();

    expect(storage.loadSettings().themeFamily, ThemeFamily.system);
    expect(storage.loadSources(), isEmpty);
  });
}
