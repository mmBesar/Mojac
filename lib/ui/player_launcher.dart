import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/network_image.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../l10n/strings.dart';
import '../player/desktop_playback.dart';
import '../player/mpv_client.dart';
import 'player_page.dart';

/// Opens [channel] in the best available player.
///
/// On desktop the system mpv is preferred: it decodes with the GPU, goes
/// properly fullscreen on Wayland and X11, and uses the user's own mpv
/// configuration and controls. Mojac stays on the channel list and does not
/// hold a stream connection, so closing the mpv window ends the stream on the
/// server too. The embedded player remains for Android, when mpv is not
/// installed, and when the setting is turned off.
void openChannelPlayer(BuildContext context, Channel channel) {
  final state = context.read<AppState>();
  final native =
      Platform.isLinux &&
      state.settings.nativePlayer &&
      MpvClient.resolveBinary() != null;
  if (!native) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PlayerPage(channel: channel),
      ),
    );
    return;
  }
  unawaited(_playOnDesktop(context, state, channel));
}

Future<void> _playOnDesktop(
  BuildContext context,
  AppState state,
  Channel channel,
) async {
  final strings = context.strings;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final allowInsecure = state.activeSource?.allowInsecureCerts ?? false;
  final playback = DesktopPlayback.instance;
  playback.onError = (detail) {
    final current = messenger?.mounted == true ? messenger : null;
    current?.showSnackBar(
      SnackBar(
        content: Text('${strings.nativePlaybackFailed} ($detail)'),
        duration: const Duration(seconds: 6),
      ),
    );
  };

  try {
    await playback.play(
      uri: Uri.parse(channel.url),
      title: 'Mojac — ${channel.name}',
      userAgent: kMojacUserAgent,
      allowInsecure: allowInsecure,
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    final current = messenger?.mounted == true ? messenger : null;
    current?.showSnackBar(
      SnackBar(
        content: Text('${strings.nativePlaybackFailed} $error'),
        duration: const Duration(seconds: 8),
      ),
    );
    // mpv could not start at all. Do not leave the user without video when
    // the embedded player can still try the same stream.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PlayerPage(channel: channel),
      ),
    );
  }
}
