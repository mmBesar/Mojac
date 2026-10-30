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

### Fixed

- Linux playback now uses media_kit's software video output. The isolated
  EGLImage texture path could freeze on its first frame on Wayland/Mesa and
  take the UI with it; set `MOJAC_MPV_LOG=1` to get libmpv diagnostics.
- The Linux software output now starts with a 1280x720 texture and follows the
  stream's aspect ratio. Without a known size media_kit never rendered a first
  frame, so playback stalled behind a black texture with no audio.
- Guide programme blocks show posters from 92 px wide (54x74 posters above
  196 px) instead of only on very wide blocks, so EPG artwork appears again.
- Very short guide programmes no longer draw ellipsis tiles that looked like
  missing guide data; they show just a clipped poster thumbnail instead.
- The XMLTV file field suggests a `.xml` example instead of the playlist's
  `.m3u` one.

[0.1.0]: https://github.com/mmbesar/Mojac/releases/tag/v0.1.0
