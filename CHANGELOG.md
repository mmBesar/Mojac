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
- Guide timeline zoom (4-12 px/minute) and lazy row/programme rendering so
  large playlists stay responsive; compact blocks keep programme sub-titles.
- Multiple stored sources with independent playlist and guide locations, local
  files, per-source self-signed TLS policy and an active-source selector.
- Per-source offline cache with 30-day expiry and playlist/guide fallback.
- English and Arabic interfaces with bidirectional text handling throughout.
- Catppuccin Latte, Frappé, Macchiato and Mocha themes, all fourteen accents,
  AMOLED black mode, and system/dynamic colour support.
- Android ARM64 and Linux x86_64/aarch64 builds; DEB, RPM and AppImage
  packaging scripts; GitHub Actions CI with tag releases and `SHA256SUMS`.
- Self-contained AppImage runtime library bundle (media, ICU, TLS and
  bzip2), while host GTK/system libraries are never shadowed.
- Bundled Noto Sans Arabic font and GPL-3.0-or-later licensing.

[0.1.0]: https://github.com/mmbesar/Mojac/releases/tag/v0.1.0
