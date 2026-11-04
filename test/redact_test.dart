import 'package:flutter_test/flutter_test.dart';
import 'package:mojac/core/redact.dart';

void main() {
  test('drops credentials and query strings from URLs', () {
    final redacted = redactUrl(
      'https://user:secret@example.com:8443/live/channel-41/index.m3u8'
      '?token=abc123&expires=999',
    );
    expect(redacted, 'https://example.com:8443/…/index.m3u8');
    expect(redacted.contains('secret'), isFalse);
    expect(redacted.contains('token'), isFalse);
    expect(redacted.contains('abc123'), isFalse);
  });

  test('keeps the host when there is no path', () {
    expect(
      redactUrl('http://tunarr.hs.lan:8000?apiKey=nope'),
      'http://tunarr.hs.lan:8000',
    );
  });

  test('reduces local paths to their file name', () {
    expect(
      redactUrl('/home/user/recordings/eastenders.ts'),
      'eastenders.ts',
    );
  });

  test('passes plain values through', () {
    expect(redactUrl(''), '');
    expect(redactUrl('not a url'), 'not a url');
  });

  test('shortens very long final segments', () {
    final redacted = redactUrl(
      'https://example.com/${'a' * 80}/stream-abcdefghijklmnop.m3u8',
    );
    expect(redacted.length, lessThan(60));
    expect(redacted.contains('…'), isTrue);
  });
}
