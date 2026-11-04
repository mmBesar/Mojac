import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../l10n/strings.dart';
import '../../player/playback_stats.dart';
import 'stb_osd.dart';

/// A compact "stats for nerds" panel: resolution, frame rate, buffer and
/// dropped frames, refreshed once a second while visible.
class PlayerStatsOverlay extends StatefulWidget {
  const PlayerStatsOverlay({
    super.key,
    required this.player,
    required this.strings,
  });

  final Player player;
  final AppStrings strings;

  @override
  State<PlayerStatsOverlay> createState() => _PlayerStatsOverlayState();
}

class _PlayerStatsOverlayState extends State<PlayerStatsOverlay> {
  Map<String, String> _stats = <String, String>{};
  Timer? _timer;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    if (_reading) {
      return;
    }
    _reading = true;
    try {
      final stats = await readPlaybackStats(widget.player);
      if (!mounted) {
        return;
      }
      setState(() => _stats = stats);
    } finally {
      _reading = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final rows = <(String, String)>[];
    final resolution = _resolution();
    if (resolution != null) {
      rows.add((strings.resolution, resolution));
    }
    final fps = _fps();
    if (fps != null) {
      rows.add((strings.frameRate, fps));
    }
    final buffer = _buffer();
    if (buffer != null) {
      rows.add((strings.bufferLevel, buffer));
    }
    final codec = _shortCodec(_stats['video-codec']);
    if (codec != null) {
      rows.add((strings.videoCodec, codec));
    }
    final audio = _shortCodec(_stats['audio-codec-name']);
    if (audio != null) {
      rows.add((strings.audioCodec, audio));
    }
    final drops = _drops();
    if (drops != null) {
      rows.add((strings.droppedFrames, drops));
    }
    final decoder = _stats['hwdec-current'];
    if (decoder != null && decoder != 'no') {
      rows.add((strings.hardwareDecoder, decoder));
    }

    return Container(
      width: 240,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: stbPanelDecoration(radius: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.monitor_heart_outlined,
                size: 15,
                color: Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                strings.statistics,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          if (rows.isEmpty)
            Text(
              strings.startingStream,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 10.5,
              ),
            ),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 78,
                    child: Text(
                      row.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.48),
                        fontSize: 10,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        fontFeatures: <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String? _resolution() {
    final width = _stats['video-params/w'];
    final height = _stats['video-params/h'];
    if (width == null || height == null) {
      return null;
    }
    return '$width × $height';
  }

  String? _fps() {
    final raw = _stats['estimated-vf-fps'] ?? _stats['container-fps'];
    final fps = double.tryParse(raw ?? '');
    if (fps == null || fps <= 0) {
      return null;
    }
    return '${fps.toStringAsFixed(1)} fps';
  }

  String? _buffer() {
    final parts = <String>[];
    final percent = double.tryParse(_stats['cache-buffering-state'] ?? '');
    if (percent != null) {
      parts.add('${percent.round()}%');
    }
    final seconds = double.tryParse(_stats['demuxer-cache-time'] ?? '');
    if (seconds != null && seconds > 0) {
      parts.add('${seconds.toStringAsFixed(1)} s');
    }
    if (parts.isEmpty) {
      return null;
    }
    if (_stats['paused-for-cache'] == 'yes') {
      parts.add(widget.strings.waitingForData);
    }
    return parts.join(' · ');
  }

  String? _drops() {
    final output = int.tryParse(_stats['frame-drop-count'] ?? '');
    final decoder = int.tryParse(_stats['decoder-frame-drop-count'] ?? '');
    if (output == null && decoder == null) {
      return null;
    }
    return '${output ?? 0} / ${decoder ?? 0}';
  }

  String? _shortCodec(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    final bracket = trimmed.indexOf(' (');
    return bracket > 0 ? trimmed.substring(0, bracket) : trimmed;
  }
}
