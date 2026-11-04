import 'package:flutter_test/flutter_test.dart';
import 'package:mojac/data/models.dart';

void main() {
  group('provider server URLs', () {
    test('a bare host becomes https and both endpoints', () {
      expect(normalizeServerBase('tunarr.hs.lan'), 'https://tunarr.hs.lan');
      expect(
        providerPlaylistUrl(SourceProvider.tunarr, 'tunarr.hs.lan'),
        'https://tunarr.hs.lan/api/channels.m3u',
      );
      expect(
        providerGuideUrl(SourceProvider.tunarr, 'tunarr.hs.lan'),
        'https://tunarr.hs.lan/api/xmltv.xml',
      );
      expect(
        providerPlaylistUrl(SourceProvider.ersatzTv, 'etv.hs.lan'),
        'https://etv.hs.lan/iptv/channels.m3u',
      );
      expect(
        providerGuideUrl(SourceProvider.ersatzTv, 'etv.hs.lan'),
        'https://etv.hs.lan/iptv/xmltv.xml',
      );
    });

    test('pasted endpoints and trailing slashes reduce to the base', () {
      expect(
        normalizeServerBase('https://etv.hs.lan/'),
        'https://etv.hs.lan',
      );
      expect(
        normalizeServerBase('https://etv.hs.lan/iptv/channels.m3u'),
        'https://etv.hs.lan',
      );
      expect(
        normalizeServerBase('https://tunarr.hs.lan:8000/api/xmltv.xml'),
        'https://tunarr.hs.lan:8000',
      );
    });

    test('a sub-path is preserved', () {
      expect(
        normalizeServerBase('https://example.com/mojac/'),
        'https://example.com/mojac',
      );
      expect(
        providerGuideUrl(
          SourceProvider.tunarr,
          'https://example.com/mojac',
        ),
        'https://example.com/mojac/api/xmltv.xml',
      );
    });

    test('empty input produces no endpoints', () {
      expect(normalizeServerBase('   '), '');
      expect(providerPlaylistUrl(SourceProvider.ersatzTv, ''), '');
      expect(providerGuideUrl(SourceProvider.tunarr, '  '), '');
    });
  });

  group('persisted provider sources', () {
    test('provider and server survive a JSON round trip', () {
      final source = SourceConfig(
        id: 'home',
        name: 'Home',
        m3u: SourceEndpoint(
          value: providerPlaylistUrl(
            SourceProvider.tunarr,
            'tunarr.hs.lan',
          ),
        ),
        epg: SourceEndpoint(
          value: providerGuideUrl(SourceProvider.tunarr, 'tunarr.hs.lan'),
        ),
        provider: SourceProvider.tunarr,
        serverUrl: 'tunarr.hs.lan',
      );

      final decoded = SourceConfig.fromJson(source.toJson());
      expect(decoded.provider, SourceProvider.tunarr);
      expect(decoded.serverUrl, 'tunarr.hs.lan');
      expect(decoded.m3u.value, 'https://tunarr.hs.lan/api/channels.m3u');
      expect(decoded.epg.value, 'https://tunarr.hs.lan/api/xmltv.xml');
    });

    test('an unknown provider falls back to plain IPTV', () {
      final decoded = SourceConfig.fromJson(<String, dynamic>{
        'id': 'old',
        'name': 'Old',
        'm3u': 'https://example.com/list.m3u',
        'epg': 'https://example.com/guide.xml',
        'provider': 'somethingElse',
      });
      expect(decoded.provider, SourceProvider.iptv);
      expect(decoded.serverUrl, '');
      expect(decoded.m3u.value, 'https://example.com/list.m3u');
    });
  });

  group('guide settings', () {
    test('round trip keeps window, refresh, group and favorites', () {
      final settings = AppSettings.defaults().copyWith(
        guideHours: 48,
        refreshMinutes: 60,
        groupFilter: 'News',
        favoriteChannelIds: const <String>['source_1', 'source_4'],
      );

      final decoded = AppSettings.fromJson(settings.toJson());
      expect(decoded.guideHours, 48);
      expect(decoded.refreshMinutes, 60);
      expect(decoded.groupFilter, 'News');
      expect(decoded.favoriteChannelIds, <String>['source_1', 'source_4']);
    });

    test('out-of-range values are clamped and an empty group means all', () {
      final decoded = AppSettings.fromJson(<String, dynamic>{
        'guideHours': 400,
        'refreshMinutes': -20,
        'groupFilter': '   ',
      });
      expect(decoded.guideHours, 168);
      expect(decoded.refreshMinutes, 0);
      expect(decoded.groupFilter, isNull);
      expect(decoded.favoriteChannelIds, isEmpty);
    });

    test('older settings files default to the twelve-hour guide', () {
      final decoded = AppSettings.fromJson(<String, dynamic>{
        'themeFamily': 'mocha',
        'accent': 'mauve',
        'language': 'system',
      });
      expect(decoded.guideHours, 12);
      expect(decoded.refreshMinutes, 0);
      expect(decoded.groupFilter, isNull);
    });
  });
}
