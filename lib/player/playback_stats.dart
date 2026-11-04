import 'package:media_kit/media_kit.dart';

/// libmpv properties worth showing while diagnosing a stream. They cover the
/// first things to check when video stalls: what was opened, which decoder is
/// active, whether frames are arriving, and how much is buffered.
const List<String> kPlaybackStatProperties = <String>[
  'video-params/w',
  'video-params/h',
  'video-codec',
  'audio-codec-name',
  'container-fps',
  'estimated-vf-fps',
  'cache-buffering-state',
  'demuxer-cache-time',
  'frame-drop-count',
  'decoder-frame-drop-count',
  'hwdec-current',
  'video-bitrate',
  'audio-bitrate',
  'paused-for-cache',
  'core-idle',
];

/// Reads the properties above from the native player, skipping any the local
/// libmpv build does not expose. Non-native players simply return nothing.
Future<Map<String, String>> readPlaybackStats(Player player) async {
  final platform = player.platform;
  if (platform is! NativePlayer) {
    return <String, String>{};
  }
  final entries = await Future.wait<MapEntry<String, String>?>(
    kPlaybackStatProperties.map((property) async {
      try {
        final value = (await platform.getProperty(property)).trim();
        if (value.isEmpty) {
          return null;
        }
        return MapEntry<String, String>(property, value);
      } catch (_) {
        return null;
      }
    }),
  );
  return <String, String>{
    for (final entry in entries)
      if (entry != null) entry.key: entry.value,
  };
}

/// Formats mpv's bits-per-second properties for display.
String? formatBitrate(String? value) {
  final bits = double.tryParse(value ?? '');
  if (bits == null || bits <= 0) {
    return null;
  }
  if (bits >= 1000000) {
    return '${(bits / 1000000).toStringAsFixed(1)} Mbps';
  }
  return '${(bits / 1000).round()} kbps';
}
