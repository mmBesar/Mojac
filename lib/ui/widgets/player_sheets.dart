import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../../core/bidi.dart';
import '../../core/redact.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../../player/playback_stats.dart';

/// Sheets shared by the built-in player: tracks, picture, sleep timer,
/// keyboard help and playback diagnostics.
///
/// They all follow the same visual language as the programme sheet (a
/// Catppuccin surface, drag handle and safe-area padding), so the player does
/// not feel like a separate application.

// Catppuccin Mocha accents. The sheets are the one place where colour carries
// meaning instead of decoration: every section has a fixed hue, so a glance at
// the tracks panel separates audio from subtitles, and the sleep panel reads
// as "off / timed / programme end" before reading a single label.
const Color _accentMauve = Color(0xFFCBA6F7);
const Color _accentBlue = Color(0xFF89B4FA);
const Color _accentGreen = Color(0xFFA6E3A1);
const Color _accentPeach = Color(0xFFFAB387);
const Color _accentYellow = Color(0xFFF9E2AF);
const Color _accentTeal = Color(0xFF94E2D5);
const Color _accentPink = Color(0xFFF5C2E7);
const Color _accentRed = Color(0xFFF38BA8);
const Color _accentSky = Color(0xFF89DCEB);
const Color _accentLavender = Color(0xFFB4BEFE);

/// A tinted icon chip and title at the top of a player sheet. The chip keeps
/// the icon legible on any surface while the colour gives the panel an
/// identity at a glance.
class _SheetTitle extends StatelessWidget {
  const _SheetTitle({
    required this.icon,
    required this.color,
    required this.title,
  });

  final IconData icon;
  final Color color;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Icon(icon, size: 19, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A small section label with a matching icon, used inside the tracks panel.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 20, 4),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showTrackSheet(
  BuildContext context, {
  required Player player,
  required AppStrings strings,
  required VoidCallback onRestoreDefaults,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: context.mojacColors.mantle,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final colors = sheetContext.mojacColors;

      return StreamBuilder<Tracks>(
        stream: player.stream.tracks,
        initialData: player.state.tracks,
        builder: (context, tracksSnapshot) {
          return StreamBuilder<Track>(
            stream: player.stream.track,
            initialData: player.state.track,
            builder: (context, trackSnapshot) {
              final tracks = tracksSnapshot.data ?? player.state.tracks;
              final selected = trackSnapshot.data ?? player.state.track;
              final rows = <Widget>[];

              rows.add(
                _SectionHeader(
                  icon: Icons.graphic_eq_rounded,
                  color: _accentTeal,
                  label: strings.audioTracks,
                ),
              );
              for (var index = 0; index < tracks.audio.length; index++) {
                final track = tracks.audio[index];
                final label = switch (track.id) {
                  'auto' => strings.autoTrack,
                  'no' => strings.noTrack,
                  _ => _describeTrack(track.title, track.language, track.codec),
                };
                rows.add(
                  ListTile(
                    leading: Icon(
                      selected.audio.id == track.id
                          ? Icons.check_circle_rounded
                          : Icons.graphic_eq_rounded,
                      color: selected.audio.id == track.id
                          ? _accentGreen
                          : _accentTeal,
                    ),
                    title: BidiText(
                      label.isEmpty ? strings.trackNumber(index + 1) : label,
                    ),
                    onTap: () => player.setAudioTrack(track),
                  ),
                );
              }

              rows.add(
                _SectionHeader(
                  icon: Icons.subtitles_rounded,
                  color: _accentPink,
                  label: strings.subtitleTracks,
                ),
              );
              for (var index = 0; index < tracks.subtitle.length; index++) {
                final track = tracks.subtitle[index];
                final label = switch (track.id) {
                  'auto' => strings.autoTrack,
                  'no' => strings.subtitlesOff,
                  _ => _describeTrack(track.title, track.language, track.codec),
                };
                rows.add(
                  ListTile(
                    leading: Icon(
                      selected.subtitle.id == track.id
                          ? Icons.check_circle_rounded
                          : Icons.subtitles_rounded,
                      color: selected.subtitle.id == track.id
                          ? _accentGreen
                          : _accentPink,
                    ),
                    title: BidiText(
                      label.isEmpty ? strings.trackNumber(index + 1) : label,
                    ),
                    onTap: () => player.setSubtitleTrack(track),
                  ),
                );
              }

              rows.add(
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                  child: Text(
                    strings.trackMemoryHelp,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.overlay0,
                      height: 1.4,
                    ),
                  ),
                ),
              );
              rows.add(
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      onRestoreDefaults();
                    },
                    icon: const Icon(
                      Icons.restart_alt_rounded,
                      color: _accentYellow,
                    ),
                    label: Text(strings.restoreTrackDefaults),
                  ),
                ),
              );
              rows.add(const SizedBox(height: 20));

              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: rows,
                ),
              );
            },
          );
        },
      );
    },
  );
}

String _describeTrack(String? title, String? language, String? codec) {
  final parts = <String>[
    if (title != null && title.trim().isNotEmpty) title.trim(),
    if (language != null && language.trim().isNotEmpty) language.trim(),
    if (codec != null && codec.trim().isNotEmpty) codec.trim(),
  ];
  return parts.join(' · ');
}

String _aspectLabel(AppStrings strings, String aspect) {
  switch (aspect) {
    case 'auto':
      return strings.aspectAuto;
    case 'fill':
      return strings.aspectFill;
    case 'stretch':
      return strings.aspectStretch;
    default:
      return aspect;
  }
}

String _deinterlaceLabel(AppStrings strings, String mode) {
  switch (mode) {
    case 'on':
      return strings.deinterlaceOn;
    case 'off':
      return strings.deinterlaceOff;
    default:
      return strings.deinterlaceAuto;
  }
}

String _formatDelay(double seconds) {
  final millis = (seconds * 1000).round();
  final sign = millis > 0 ? '+' : '';
  return '$sign$millis ms';
}

/// Picture controls: the aspect override, deinterlacing and the audio and
/// subtitle delays. "Auto (native)" is deliberately listed first and is a real
/// choice, not a hidden reset: it clears mpv's aspect override so the stream's
/// own ratio comes back after any experiment.
Future<void> showPictureSheet(
  BuildContext context, {
  required String aspect,
  required String deinterlace,
  required double audioDelay,
  required double subtitleDelay,
  required ValueChanged<String> onAspect,
  required ValueChanged<String> onDeinterlace,
  required ValueChanged<double> onAudioDelay,
  required ValueChanged<double> onSubtitleDelay,
  required VoidCallback onReset,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: context.mojacColors.mantle,
    builder: (sheetContext) {
      final strings = sheetContext.strings;
      final colors = sheetContext.mojacColors;
      final theme = Theme.of(sheetContext);
      // The callbacks below update the sheet's own copy so the chips react
      // immediately, while the player persists the change through the
      // `on*` callbacks. Parameters stay untouched.
      var currentAspect = aspect;
      var currentDeinterlace = deinterlace;
      var currentAudioDelay = audioDelay;
      var currentSubtitleDelay = subtitleDelay;
      return StatefulBuilder(
        builder: (context, setSheetState) {
          void applyAspect(String value) {
            setSheetState(() => currentAspect = value);
            onAspect(value);
          }

          void applyDeinterlace(String value) {
            setSheetState(() => currentDeinterlace = value);
            onDeinterlace(value);
          }

          void nudge(bool audio, double delta) {
            final current = audio ? currentAudioDelay : currentSubtitleDelay;
            final next = (current + delta).clamp(-10.0, 10.0).toDouble();
            setSheetState(() {
              if (audio) {
                currentAudioDelay = next;
              } else {
                currentSubtitleDelay = next;
              }
            });
            if (audio) {
              onAudioDelay(next);
            } else {
              onSubtitleDelay(next);
            }
          }

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: <Widget>[
                _SheetTitle(
                  icon: Icons.aspect_ratio_rounded,
                  color: _accentBlue,
                  title: strings.picture,
                ),
                const SizedBox(height: 16),
                Text(
                  strings.aspectRatio,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.subtext0,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final option in kPlayerAspects)
                      ChoiceChip(
                        label: Text(_aspectLabel(strings, option)),
                        selected: currentAspect == option,
                        onSelected: (_) => applyAspect(option),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  strings.aspectHelp,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.overlay0,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  strings.deinterlace,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.subtext0,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: <ButtonSegment<String>>[
                    for (final mode in kPlayerDeinterlaceModes)
                      ButtonSegment<String>(
                        value: mode,
                        label: Text(_deinterlaceLabel(strings, mode)),
                      ),
                  ],
                  selected: <String>{currentDeinterlace},
                  onSelectionChanged: (selection) =>
                      applyDeinterlace(selection.first),
                ),
                const SizedBox(height: 22),
                _DelayRow(
                  label: strings.audioDelay,
                  value: _formatDelay(currentAudioDelay),
                  resetTooltip: strings.resetPicture,
                  onDecrease: () => nudge(true, -0.05),
                  onIncrease: () => nudge(true, 0.05),
                  onReset: () => nudge(true, -currentAudioDelay),
                ),
                const SizedBox(height: 10),
                _DelayRow(
                  label: strings.subtitleDelay,
                  value: _formatDelay(currentSubtitleDelay),
                  resetTooltip: strings.resetPicture,
                  onDecrease: () => nudge(false, -0.05),
                  onIncrease: () => nudge(false, 0.05),
                  onReset: () => nudge(false, -currentSubtitleDelay),
                ),
                const SizedBox(height: 22),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    onReset();
                  },
                  icon: const Icon(
                    Icons.restart_alt_rounded,
                    color: _accentYellow,
                  ),
                  label: Text(strings.resetPicture),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class _DelayRow extends StatelessWidget {
  const _DelayRow({
    required this.label,
    required this.value,
    required this.resetTooltip,
    required this.onDecrease,
    required this.onIncrease,
    required this.onReset,
  });

  final String label;
  final String value;
  final String resetTooltip;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.mojacColors;
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: theme.textTheme.bodyMedium),
              Text(
                value,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.overlay0,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: resetTooltip,
          onPressed: onReset,
          icon: const Icon(Icons.restart_alt_rounded, color: _accentYellow),
        ),
        IconButton(
          tooltip: label,
          onPressed: onDecrease,
          icon: const Icon(Icons.remove_rounded, color: _accentPeach),
        ),
        IconButton(
          tooltip: label,
          onPressed: onIncrease,
          icon: const Icon(Icons.add_rounded, color: _accentGreen),
        ),
      ],
    );
  }
}

/// Sleep timer choices. `minutes` is null when the timer is off, and
/// [endOfProgramme] selects the end of what is on air right now.
Future<void> showSleepTimerSheet(
  BuildContext context, {
  required int? minutes,
  required bool endOfProgramme,
  required ValueChanged<int?> onMinutes,
  required VoidCallback onEndOfProgramme,
}) {
  const presets = <int>[15, 30, 45, 60, 90, 120];
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: context.mojacColors.mantle,
    builder: (sheetContext) {
      final strings = sheetContext.strings;
      Widget row({
        required String label,
        required bool selected,
        required VoidCallback onTap,
        IconData icon = Icons.bedtime_outlined,
        Color color = _accentYellow,
      }) {
        return ListTile(
          leading: Icon(icon, color: selected ? color : color.withValues(alpha: 0.7)),
          title: Text(label),
          trailing: selected
              ? const Icon(Icons.check_rounded, color: _accentGreen)
              : null,
          onTap: onTap,
        );
      }

      return SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: _SheetTitle(
                icon: Icons.bedtime_rounded,
                color: _accentMauve,
                title: strings.sleepTimer,
              ),
            ),
            row(
              label: strings.sleepOff,
              icon: Icons.do_not_disturb_on_outlined,
              color: _accentRed,
              selected: minutes == null && !endOfProgramme,
              onTap: () {
                Navigator.of(sheetContext).pop();
                onMinutes(null);
              },
            ),
            for (final preset in presets)
              row(
                label: strings.sleepIn(preset),
                selected: minutes == preset && !endOfProgramme,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onMinutes(preset);
                },
              ),
            row(
              label: strings.sleepEndOfProgramme,
              icon: Icons.event_available_outlined,
              color: _accentTeal,
              selected: endOfProgramme,
              onTap: () {
                Navigator.of(sheetContext).pop();
                onEndOfProgramme();
              },
            ),
          ],
        ),
      );
    },
  );
}

/// A drawn key cap, so the shortcut list reads like a remote-control card
/// rather than a paragraph of text.
class _KeyCap extends StatelessWidget {
  const _KeyCap({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface0,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.surface2),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.text,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

Future<void> showShortcutsSheet(BuildContext context) {
  final strings = context.strings;
  final rows = <(List<String>, String)>[
    (<String>['Space', 'K'], strings.shortcutPlayPause),
    (<String>['F', 'F11'], strings.shortcutFullscreen),
    (<String>['M'], strings.shortcutMute),
    (<String>['↑', '↓'], strings.shortcutVolume),
    (<String>['←', '→'], strings.shortcutChannels),
    (<String>['C', 'B'], strings.shortcutBrowser),
    (<String>['S'], strings.shortcutTracks),
    (<String>['A'], strings.shortcutAudio),
    (<String>['J'], strings.shortcutSubtitles),
    (<String>['P'], strings.shortcutPicture),
    (<String>['Z'], strings.shortcutAspect),
    (<String>['T'], strings.shortcutDeinterlace),
    (<String>['I'], strings.shortcutBanner),
    (<String>['N'], strings.shortcutSleep),
    (<String>['D'], strings.shortcutStatistics),
    (<String>['Shift', 'D'], strings.shortcutInfo),
    (<String>['0–9'], strings.shortcutNumbers),
    (<String>['Esc'], strings.shortcutEscape),
    (<String>['H', 'F1'], strings.shortcutHelp),
  ];

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: context.mojacColors.mantle,
    builder: (sheetContext) {
      final colors = sheetContext.mojacColors;
      final theme = Theme.of(sheetContext);
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: <Widget>[
            _SheetTitle(
              icon: Icons.keyboard_rounded,
              color: _accentLavender,
              title: strings.keyboardShortcuts,
            ),
            const SizedBox(height: 6),
            Text(
              strings.shortcutsIntro,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.overlay0,
              ),
            ),
            const SizedBox(height: 14),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 108,
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: <Widget>[
                          for (final key in row.$1) _KeyCap(label: key),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: BidiText(
                        row.$2,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.subtext1,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// Diagnostics: the redacted stream URL, codecs, buffer state and frame drops.
/// The panel refreshes once a second and the copy button produces text that is
/// safe to paste into a bug report.
Future<void> showDiagnosticsSheet(
  BuildContext context, {
  required Player player,
  required Channel channel,
  String? lastError,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: context.mojacColors.mantle,
    builder: (sheetContext) {
      return _DiagnosticsSheet(
        player: player,
        channel: channel,
        lastError: lastError,
      );
    },
  );
}

class _DiagnosticsSheet extends StatefulWidget {
  const _DiagnosticsSheet({
    required this.player,
    required this.channel,
    required this.lastError,
  });

  final Player player;
  final Channel channel;
  final String? lastError;

  @override
  State<_DiagnosticsSheet> createState() => _DiagnosticsSheetState();
}

class _DiagnosticsSheetState extends State<_DiagnosticsSheet> {
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

  String? _codec(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    final bracket = trimmed.indexOf(' (');
    return bracket > 0 ? trimmed.substring(0, bracket) : trimmed;
  }

  List<(String, String)> _rows(AppStrings strings) {
    final rows = <(String, String)>[];
    final width = _stats['video-params/w'];
    final height = _stats['video-params/h'];
    if (width != null && height != null) {
      rows.add((strings.resolution, '$width × $height'));
    }
    final video = _codec(_stats['video-codec']);
    if (video != null) {
      rows.add((strings.videoCodec, video));
    }
    final audio = _codec(_stats['audio-codec-name']);
    if (audio != null) {
      rows.add((strings.audioCodec, audio));
    }
    final fps = double.tryParse(
      _stats['estimated-vf-fps'] ?? _stats['container-fps'] ?? '',
    );
    if (fps != null && fps > 0) {
      rows.add((strings.frameRate, '${fps.toStringAsFixed(2)} fps'));
    }
    final videoBitrate = formatBitrate(_stats['video-bitrate']);
    if (videoBitrate != null) {
      rows.add((strings.bitrate, videoBitrate));
    }
    final cache = _stats['cache-buffering-state'];
    if (cache != null) {
      rows.add((strings.bufferLevel, '$cache%'));
    }
    final demuxer = double.tryParse(_stats['demuxer-cache-time'] ?? '');
    if (demuxer != null && demuxer > 0) {
      rows.add(('demuxer-cache-time', '${demuxer.toStringAsFixed(1)} s'));
    }
    final drops = _stats['frame-drop-count'];
    if (drops != null) {
      rows.add((strings.droppedFrames, drops));
    }
    final decoder = _stats['hwdec-current'];
    if (decoder != null) {
      rows.add((strings.hardwareDecoder, decoder));
    }
    if (_stats['paused-for-cache'] == 'yes') {
      rows.add((strings.bufferLevel, strings.waitingForData));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.mojacColors;
    final theme = Theme.of(context);
    final url = redactUrl(widget.channel.url);
    final rows = _rows(strings);

    String details() {
      final buffer = StringBuffer()
        ..writeln('Mojac ${widget.channel.name} '
            '(${widget.channel.displayNumber})')
        ..writeln('${strings.engine}: ${strings.builtInEngine}')
        ..writeln('${strings.streamUrl}: $url');
      for (final row in rows) {
        buffer.writeln('${row.$1}: ${row.$2}');
      }
      final error = widget.lastError;
      if (error != null && error.trim().isNotEmpty) {
        buffer.writeln('error: ${error.trim()}');
      }
      return buffer.toString();
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _SheetTitle(
                  icon: Icons.monitor_heart_rounded,
                  color: _accentSky,
                  title: strings.playbackInfo,
                ),
              ),
              IconButton(
                tooltip: strings.copyDetails,
                onPressed: () {
                  unawaited(
                    Clipboard.setData(ClipboardData(text: details())),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(strings.detailsCopied)),
                  );
                },
                icon: const Icon(Icons.copy_all_rounded, color: _accentSky),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _InfoLine(label: strings.engine, value: strings.builtInEngine),
          _InfoLine(label: strings.streamUrl, value: url),
          Text(
            strings.redactedUrlNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.overlay0,
            ),
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                strings.waitingForData,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.overlay0,
                ),
              ),
            )
          else
            for (final row in rows)
              _InfoLine(label: row.$1, value: row.$2),
          if (widget.lastError != null &&
              widget.lastError!.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            Text(
              widget.lastError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.overlay0,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.mojacColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.overlay0,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textDirection: TextDirection.ltr,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.text,
                fontWeight: FontWeight.w600,
                fontFeatures: const <FontFeature>[
                  FontFeature.tabularFigures(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
