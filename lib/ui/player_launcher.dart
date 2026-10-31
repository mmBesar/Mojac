import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../player/mpv_client.dart';
import 'pages/desktop_player_page.dart';
import 'player_page.dart';

/// Opens [channel] in the best available player.
///
/// On desktop the system mpv is preferred: media_kit's Linux video output is a
/// software texture, which tears and drops frames on high-bitrate streams,
/// while a real mpv decodes with the GPU and can go properly fullscreen. The
/// embedded player stays as the fallback on Android, when mpv is not
/// installed, and when the setting is turned off.
void openChannelPlayer(BuildContext context, Channel channel) {
  final settings = context.read<AppState>().settings;
  final native =
      Platform.isLinux &&
      settings.nativePlayer &&
      MpvClient.resolveBinary() != null;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => native
          ? DesktopPlayerPage(channel: channel)
          : PlayerPage(channel: channel),
    ),
  );
}
