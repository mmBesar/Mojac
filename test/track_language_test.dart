import 'package:flutter_test/flutter_test.dart';
import 'package:mojac/core/track_language.dart';

void main() {
  group('normalizeLanguageCode', () {
    test('reduces tags to two-letter codes', () {
      expect(normalizeLanguageCode('en'), 'en');
      expect(normalizeLanguageCode('ENG'), 'en');
      expect(normalizeLanguageCode('en-GB'), 'en');
      expect(normalizeLanguageCode('ar_EG'), 'ar');
    });

    test('recognises full names and synonyms', () {
      expect(normalizeLanguageCode('English'), 'en');
      expect(normalizeLanguageCode('Arabic'), 'ar');
      expect(normalizeLanguageCode('Farsi'), 'fa');
      expect(normalizeLanguageCode('Mandarin'), 'zh');
    });

    test('ignores unknown and empty values', () {
      expect(normalizeLanguageCode(null), isNull);
      expect(normalizeLanguageCode('  '), isNull);
      expect(normalizeLanguageCode('und'), isNull);
      expect(normalizeLanguageCode('unknown'), isNull);
    });

    test('keeps an unrecognised primary subtag', () {
      expect(normalizeLanguageCode('tlh'), 'tlh');
    });
  });

  group('languageMatches', () {
    test('matches equivalent tags', () {
      expect(languageMatches('eng', 'en'), isTrue);
      expect(languageMatches('en-US', 'English'), isTrue);
      expect(languageMatches(null, 'en'), isFalse);
      expect(languageMatches('fr', 'en'), isFalse);
    });
  });

  group('languageScore', () {
    test('prefers a language tag over a title match', () {
      final tagged = languageScore(
        language: 'en',
        title: 'Stereo',
        preference: 'ar',
      );
      final named = languageScore(
        language: null,
        title: 'Arabic 5.1',
        preference: 'ar',
      );
      expect(tagged, 0);
      expect(named, 2);
    });

    test('returns 3 only for a real language match', () {
      expect(
        languageScore(language: 'ara', title: null, preference: 'ar'),
        3,
      );
      expect(
        languageScore(language: 'eng', title: null, preference: 'ar'),
        0,
      );
    });

    test('unknown preferences match nothing', () {
      expect(
        languageScore(language: 'en', title: 'English', preference: 'und'),
        0,
      );
    });
  });
}
