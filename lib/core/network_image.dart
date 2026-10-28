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

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
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
        throw NetworkImageLoadException(
          statusCode: response.statusCode,
          uri: uri,
        );
      }
      final Uint8List bytes = await consolidateHttpClientResponseBytes(response)
          .timeout(const Duration(seconds: 30));
      if (bytes.isEmpty) {
        throw StateError('Empty image response');
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return await decode(buffer);
    } finally {
      client.close(force: true);
    }
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
