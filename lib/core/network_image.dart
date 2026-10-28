import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

const String kMojacUserAgent =
    'Mojac/0.1.0 (+https://github.com/mmbesar/Mojac)';

/// An [ImageProvider] for channel logos that understands Mojac's per-source
/// "allow self-signed certificates" setting. Plain [NetworkImage] uses the
/// platform HTTP stack, which cannot be told to trust a specific source.
@immutable
class MojacNetworkImage extends ImageProvider<MojacNetworkImage> {
  const MojacNetworkImage(this.url, {required this.allowInsecure});

  final String url;
  final bool allowInsecure;

  @override
  Future<MojacNetworkImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<MojacNetworkImage>(this);
  }

  // Identity matters: Flutter's ImageCache deduplicates and reuses entries via
  // the key's ==/hashCode. Without these, every logo tile owns a private cache
  // entry, so one big playlist can evict the logos of the source shown before.
  @override
  bool operator ==(Object other) =>
      other is MojacNetworkImage &&
      other.url == url &&
      other.allowInsecure == allowInsecure;

  @override
  int get hashCode => Object.hash(url, allowInsecure);

  @override
  String toString() => 'MojacNetworkImage("$url")';

  @override
  ImageStreamCompleter loadImage(
    MojacNetworkImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      debugLabel: key.url,
    );
  }

  Future<ui.Codec> _loadAsync(
    MojacNetworkImage key,
    ImageDecoderCallback decode,
  ) async {
    final uri = Uri.tryParse(key.url);
    if (uri == null || !uri.hasScheme) {
      throw ArgumentError.value(key.url, 'url', 'Not a valid image URL');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw ArgumentError.value(key.url, 'url', 'Unsupported image scheme');
    }

    // Large playlists can produce a burst of logo requests. Retry once on
    // transient failures (timeouts, connection resets, 429/5xx) so a busy
    // source does not leave permanent fallback tiles in the channel list.
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 12)
        ..userAgent = kMojacUserAgent;
      if (key.allowInsecure) {
        client.badCertificateCallback = (_, _, _) => true;
      }

      try {
        final request = await client.getUrl(uri);
        request.headers.set(HttpHeaders.acceptHeader, 'image/*,*/*;q=0.8');
        final response = await request.close();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          await response.drain<void>();
          final error = NetworkImageLoadException(
            statusCode: response.statusCode,
            uri: uri,
          );
          if (response.statusCode != 429 && response.statusCode < 500) {
            throw error;
          }
          lastError = error;
          continue;
        }
        final Uint8List bytes =
            await consolidateHttpClientResponseBytes(response)
                .timeout(const Duration(seconds: 20));
        if (bytes.isEmpty) {
          throw StateError('Empty image response');
        }
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        return await decode(buffer);
      } on SocketException catch (error) {
        lastError = error;
      } on HttpException catch (error) {
        lastError = error;
      } on TimeoutException catch (error) {
        lastError = error;
      } finally {
        client.close(force: true);
      }
    }
    if (lastError != null) {
      throw lastError;
    }
    throw StateError('Image request failed');
  }

  @override
  bool operator ==(Object other) {
    return other is MojacNetworkImage &&
        other.url == url &&
        other.allowInsecure == allowInsecure;
  }

  @override
  int get hashCode => Object.hash(url, allowInsecure);

  @override
  String toString() => 'MojacNetworkImage("$url", insecure: $allowInsecure)';
}
