/// Language matching for audio and subtitle tracks.
///
/// Servers are inconsistent: the same language arrives as `en`, `eng`,
/// `en-GB`, `English` or `الإنجليزية`, depending on the encoder and on whether
/// the name came from HLS `EXT-X-MEDIA` or from the container's metadata. The
/// helpers here reduce all of those to one code so a preferred language can be
/// applied without guessing at every call site.
library;

const Map<String, List<String>> _languageAliases = <String, List<String>>{
  'ar': <String>['ar', 'ara', 'arabic'],
  'bn': <String>['bn', 'ben', 'bengali'],
  'cs': <String>['cs', 'ces', 'cze', 'czech'],
  'da': <String>['da', 'dan', 'danish'],
  'de': <String>['de', 'deu', 'ger', 'german'],
  'el': <String>['el', 'ell', 'gre', 'greek'],
  'en': <String>['en', 'eng', 'english'],
  'es': <String>['es', 'spa', 'spanish'],
  'fa': <String>['fa', 'fas', 'per', 'persian', 'farsi'],
  'fi': <String>['fi', 'fin', 'finnish'],
  'fr': <String>['fr', 'fra', 'fre', 'french'],
  'he': <String>['he', 'heb', 'hebrew'],
  'hi': <String>['hi', 'hin', 'hindi'],
  'hu': <String>['hu', 'hun', 'hungarian'],
  'id': <String>['id', 'ind', 'indonesian'],
  'it': <String>['it', 'ita', 'italian'],
  'ja': <String>['ja', 'jpn', 'japanese'],
  'ko': <String>['ko', 'kor', 'korean'],
  'ms': <String>['ms', 'msa', 'may', 'malay'],
  'nl': <String>['nl', 'nld', 'dut', 'dutch'],
  'no': <String>['no', 'nor', 'norwegian'],
  'pl': <String>['pl', 'pol', 'polish'],
  'pt': <String>['pt', 'por', 'portuguese'],
  'ro': <String>['ro', 'ron', 'rum', 'romanian'],
  'ru': <String>['ru', 'rus', 'russian'],
  'sv': <String>['sv', 'swe', 'swedish'],
  'ta': <String>['ta', 'tam', 'tamil'],
  'th': <String>['th', 'tha', 'thai'],
  'tr': <String>['tr', 'tur', 'turkish'],
  'uk': <String>['uk', 'ukr', 'ukrainian'],
  'ur': <String>['ur', 'urd', 'urdu'],
  'vi': <String>['vi', 'vie', 'vietnamese'],
  'zh': <String>['zh', 'zho', 'chi', 'chinese', 'mandarin'],
};

/// Human names used to match track *titles* such as "English 5.1".
const Map<String, List<String>> _languageNames = <String, List<String>>{
  'ar': <String>['arabic', 'العربية'],
  'bn': <String>['bengali'],
  'cs': <String>['czech'],
  'da': <String>['danish'],
  'de': <String>['german', 'deutsch'],
  'el': <String>['greek'],
  'en': <String>['english'],
  'es': <String>['spanish', 'español'],
  'fa': <String>['persian', 'farsi'],
  'fi': <String>['finnish'],
  'fr': <String>['french', 'français'],
  'he': <String>['hebrew'],
  'hi': <String>['hindi'],
  'hu': <String>['hungarian'],
  'id': <String>['indonesian'],
  'it': <String>['italian', 'italiano'],
  'ja': <String>['japanese'],
  'ko': <String>['korean'],
  'ms': <String>['malay'],
  'nl': <String>['dutch'],
  'no': <String>['norwegian'],
  'pl': <String>['polish'],
  'pt': <String>['portuguese'],
  'ro': <String>['romanian'],
  'ru': <String>['russian'],
  'sv': <String>['swedish'],
  'ta': <String>['tamil'],
  'th': <String>['thai'],
  'tr': <String>['turkish'],
  'uk': <String>['ukrainian'],
  'ur': <String>['urdu'],
  'vi': <String>['vietnamese'],
  'zh': <String>['chinese', 'mandarin'],
};

/// Reduces a track language tag to a two-letter code when it is recognised,
/// otherwise to its bare primary subtag (`en-GB` becomes `en`). Returns null
/// for empty or meaningless values such as `und`.
String? normalizeLanguageCode(String? raw) {
  final value = raw?.trim().toLowerCase();
  if (value == null || value.isEmpty) {
    return null;
  }
  final base = value.split(RegExp('[-_]')).first;
  if (base.isEmpty || base == 'und' || base == 'unknown') {
    return null;
  }
  for (final entry in _languageAliases.entries) {
    if (entry.key == base) {
      return entry.key;
    }
    if (entry.value.contains(base)) {
      return entry.key;
    }
  }
  return base.length >= 2 && base.length <= 3 ? base : null;
}

/// Whether a track's language tag matches [preference] (`en`, `eng` and
/// `English` all match each other).
bool languageMatches(String? language, String preference) {
  final wanted = normalizeLanguageCode(preference);
  if (wanted == null) {
    return false;
  }
  return normalizeLanguageCode(language) == wanted;
}

/// Scores how well a track fits [preference]: 3 for a language-tag match, 2
/// when the preference's name appears in the title, and 0 otherwise. Higher is
/// better, so callers keep the highest-scoring track.
int languageScore({
  required String? language,
  required String? title,
  required String preference,
}) {
  final wanted = normalizeLanguageCode(preference);
  if (wanted == null) {
    return 0;
  }
  if (languageMatches(language, preference)) {
    return 3;
  }
  final haystack = '${title ?? ''} ${language ?? ''}'.toLowerCase();
  for (final name in _languageNames[wanted] ?? const <String>[]) {
    if (haystack.contains(name)) {
      return 2;
    }
  }
  return 0;
}
