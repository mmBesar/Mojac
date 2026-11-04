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
      showChannelBanner: false,
      defaultAudioLanguage: 'ar',
      defaultSubtitleLanguage: 'off',
      playerVolume: 42,
      playerAspect: '4:3',
      playerDeinterlace: 'on',
      channelTracks: <String, String>{'home_1': '2|no'},
    );
    await storage.saveSettings(settings);

    final loaded = storage.loadSettings();
    expect(loaded.themeFamily, ThemeFamily.amoled);
    expect(loaded.accent, ThemeAccent.peach);
    expect(loaded.language, AppLanguage.arabic);
    expect(loaded.use24HourTime, isTrue);
    expect(loaded.activeSourceId, 'home');
    expect(loaded.showChannelBanner, isFalse);
    expect(loaded.defaultAudioLanguage, 'ar');
    expect(loaded.defaultSubtitleLanguage, 'off');
    expect(loaded.playerVolume, 42);
    expect(loaded.playerAspect, '4:3');
    expect(loaded.playerDeinterlace, 'on');
    expect(loaded.channelTracks, <String, String>{'home_1': '2|no'});

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

  test('player settings are clamped and validated', () {
    final decoded = AppSettings.fromJson(<String, dynamic>{
      'playerVolume': 900,
      'playerAspect': '11:9',
      'playerDeinterlace': 'sometimes',
      'channelTracks': <String, dynamic>{
        'ok': '0|no',
        'empty': '',
        'wrong-type': 42,
      },
    });
    expect(decoded.playerVolume, 100);
    expect(decoded.playerAspect, 'auto');
    expect(decoded.playerDeinterlace, 'auto');
    expect(decoded.channelTracks, <String, String>{'ok': '0|no'});
  });
}
