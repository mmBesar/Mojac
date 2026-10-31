# Changelog

All notable changes to Mojac are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions use
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - Unreleased

### Added

- M3U/M3U8 playlist parsing with `tvg-id`, `tvg-name`, `tvg-chno`, `tvg-logo`,
  `group-title`, `#EXTGRP`, relative locations and advertised `url-tvg`.
- XMLTV parsing with timezone offsets, `<sub-title>`, descriptions, categories,
  icons and `episode-num`, limited to a rolling 12-hour-past / 72-hour-future
  window.
- 12-hour guide timeline with channel column, live programme highlight, "now"
  line, programme sheet and 12/24-hour display option.
- Guide timeline zoom (4-12 px/minute) and lazy row rendering so large
  playlists stay responsive; compact blocks keep programme sub-titles and the
  window rolls back to "now" when it has been open past the displayed span.
- Channels list shows the next programme's sub-title alongside the current
  one.
- Multiple stored sources with independent playlist and guide locations, local
  files, per-source self-signed TLS policy and an active-source selector.
- Per-source offline cache with 30-day expiry and playlist/guide fallback.
- English and Arabic interfaces with bidirectional text handling throughout.
- Catppuccin Latte, Frappé, Macchiato and Mocha themes, all fourteen accents,
  AMOLED black mode, and system/dynamic colour support.
- Android ARM64 and Linux x86_64/aarch64 builds; DEB, RPM and AppImage
  packaging scripts; GitHub Actions CI with tag releases and `SHA256SUMS`.
- Self-contained AppImage runtime library bundle (media, ICU, TLS and
  bzip2), while host GTK/system libraries (including librsvg) are never
  shadowed.
- Bundled Noto Sans Arabic font and GPL-3.0-or-later licensing.
- Native mpv playback on Linux desktops. Channels open in the system mpv's
  own window, so video is decoded on the GPU, fullscreen is real instead of
  filling the app window, and mpv's usual controls work (scroll-wheel volume,
  keyboard shortcuts, on-screen controller). The Mojac page stays open as a
  remote control with pause, mute, volume and fullscreen, plus the channel's
  now/next information. A setting switches back to the built-in player, which
  also remains the fallback when no `mpv` binary is installed.

### Fixed

- HLS streams whose master playlist advertises a subtitle rendition play again.
  media_kit hands ffmpeg `strict=experimental`, which enables its unfinished
  `EXT-X-MEDIA` support; ErsatzTV publishes a `DEFAULT=YES` WebVTT rendition,
  so ffmpeg switched to the subtitle playlist and read `.vtt` segments only,
  leaving video and audio silent behind the spinner while the server kept
  transcoding. The player now passes the same demuxer options without that
  flag, so the rendition is ignored and the video playlist stays active.
- Linux playback now uses media_kit's software video output. The isolated
  EGLImage texture path could freeze on its first frame on Wayland/Mesa and
  take the UI with it; set `MOJAC_MPV_LOG=1` to get libmpv diagnostics.
- The Linux software output now starts with a 1280x720 texture and follows the
  stream's aspect ratio. Without a known size media_kit never rendered a first
  frame, so playback stalled behind a black texture with no audio.
- Live streams get 60 seconds to produce their first segment instead of 30.
  Android playback also reports libmpv's messages and dumps player state after
  10, 20 and 30 seconds of buffering to `adb logcat`, above the endless
  spinner in the UI.
- Guide blocks only request artwork above 190 px wide again. Widening that rule
  to 92 px made a phone guide download thousands of full-size XMLTV posters
  (Tunarr serves ~570 KB each), which starved playback and source refreshes
  from the same host. Very short programmes still avoid the misleading
  ellipsis tile.
- Artwork downloads are queued behind six concurrent fetches, so a screen
  full of posters can no longer exhaust sockets or starve playback and EPG
  refreshes, and the disk cache prunes far less often.
- The XMLTV file field suggests a `.xml` example instead of the playlist's
  `.m3u` one.
- Very short guide programmes no longer look like missing guide data.
  ErsatzTV's movie channels air five to eight minute programmes, which are
  20-32 px wide at the default zoom (below the label threshold) and were drawn
  as nothing at all. They now render as tinted blocks, including the live
  accent, without text or artwork, so the whole row visibly has coverage while
  still avoiding one artwork request per sliver.

[0.1.0]: https://github.com/mmbesar/Mojac/releases/tag/v0.1.0
