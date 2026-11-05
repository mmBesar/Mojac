# Changelog

All notable changes to Mojac are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions use
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - Unreleased

### Added

- M3U/M3U8 playlist parsing with `tvg-id`, `tvg-name`, `tvg-chno`, `tvg-logo`,
  `group-title`, `#EXTGRP`, relative locations and advertised `url-tvg`.
- XMLTV parsing with timezone offsets, `<sub-title>`, descriptions, categories,
  icons and `episode-num`, keeping 12 hours of the past plus the selected guide
  window (12-168 hours) and a margin.
- Guide timeline with channel column, live programme highlight, "now" line,
  programme sheet, 12/24-hour display option and a configurable 12-168 hour
  span.
- Guide timeline zoom (2-180 px/minute) and lazy row rendering so large
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
- Tunarr and ErsatzTV source presets. Both only need the server address;
  Mojac derives `/api/channels.m3u` + `/api/xmltv.xml` or
  `/iptv/channels.m3u` + `/iptv/xmltv.xml`. IPTV sources still accept explicit
  playlist and guide locations.
- Favourites tab with per-channel stars, plus a floating rounded bottom bar on
  phones. Sources moved into Settings and a quick source switcher stays in the
  app bar.
- One search surface for channels, groups and programmes. Programme results
  carry artwork, sub-title, episode number, channel and air time, and the
  results are ranked so exact title matches come first.
- Shared group filter on Channels and Guide, half-hour timeline labels, and a
  configurable guide window from 12 to 168 hours. Automatic background refresh
  can run every 15 minutes to 12 hours.
- Rich XMLTV metadata: every poster/still URL, credits, rating, keywords,
  year, new/previously-shown flags, and season/episode numbers even when the
  sub-title omits them. The programme sheet shows the full detail.
- Audio and subtitle track picker in the built-in player, driven by media_kit's
  live track streams.
- Set-top-box style player overlays on the built-in player. A lower-third
  banner shows the logo, number, clock, what is on now with a live progress
  line and what is next, fading after eight seconds (or pinned), with group,
  sleep and track chips. Volume and brightness use a 30-segment level bar, and
  track, mute, aspect and sleep changes appear as a short message overlay.
- In-player channel browser: group tabs, what is on now on every row, type-to-
  search by channel name, group or programme, and tuning without leaving the
  video. Swiping the picture or pressing the arrow/Page keys surfs channels,
  and the number keys tune by channel number.
- Per-channel audio and subtitle memory, with default audio and subtitle
  languages in Settings (including "subtitles off"). `A` and `J` cycle tracks
  and the track sheet can restore the defaults.
- Keyboard controls for the built-in player: space to pause, F/F11 fullscreen,
  M mute, arrows for volume and channels, C/B browser, S tracks, P picture,
  Z aspect, T deinterlace, I banner, N sleep timer, D statistics, H/F1 the
  shortcut card, and `[`/`]` and `,`/`.` for audio and subtitle delays.
- Picture controls in the player: aspect override, deinterlacing and audio and
  subtitle delays. "Auto (native)" is a first-class choice that clears mpv's
  aspect override, so the stream's own ratio comes back after any change;
  "Fill screen" crops to fill without distorting and "Stretch" fills even when
  that changes the ratio. "Reset picture" restores every picture control at
  once.
- Playback statistics and a diagnostics sheet with the redacted stream URL,
  codecs, resolution, buffer, dropped frames and a copy-to-clipboard action.
  Open it with Shift+D or by holding the statistics button. Failed starts now
  retry quietly twice before any error is shown.
- Sleep timer with 15, 30, 45, 60, 90 and 120 minute options, or the end of the
  current programme; playback pauses when it expires.
- CI now signs the Android APK with a repository-backed upload key, verifies it
  with `apksigner`, and falls back to debug signing when the secrets are not
  configured.
- Native mpv playback on Linux desktops. Channels open in the system mpv's
  own window, so video is decoded on the GPU, fullscreen is real instead of
  filling the app window, and mpv's usual controls and the user's own mpv
  configuration apply. Mojac shows no remote control: it stays on the channel
  list, never holds the stream itself, closes any previous player when another
  channel starts, and quits mpv when the app exits. Closing the mpv window
  therefore ends the stream (and its server-side transcode) immediately. A
  setting switches back to the built-in player, which also remains the
  fallback when no `mpv` binary is installed.
- Three channel layouts on the Channels page: the original roomy list, an
  artwork grid that reflows from two cards on a phone to five or more on a
  desktop, and a dense single-line list for long playlists. The choice is
  saved with the other settings and can be switched from the toolbar.
- AppStream metainfo (`com.mmbesar.mojac.appdata.xml`) and a reverse-DNS
  desktop entry, installed by the DEB, RPM and AppImage so software centres
  can identify Mojac and `appimagetool` can validate the AppDir cleanly.

### Changed

- The guide opens at 5.4 px/minute (35% denser than the old default) and zooms
  from 2 to 180 px/minute. The zoom slider is logarithmic so the useful short-
  programme range gets most of the travel, and `Ctrl`/`⌘` + scroll zooms around
  the centre of the viewport.
- Programme text sticks to the visible edge of its block while the timeline
  scrolls: left in LTR and right in Arabic. Every programme in a built row is
  laid out again; only artwork is limited to the visible viewport. Horizontal
  block culling could leave whole rows blank when the viewport state was stale,
  for example when the guide was first shown after being built offstage.
- The guide window rolls forward before its future edge runs out: when 90
  minutes remain, it jumps to a fresh window around "now" so the right side of
  the grid always shows upcoming programmes.
- Channel artwork is larger in both the channel list and the guide. The
  channel number now rides on the logo corner as a small badge instead of
  taking a text column, and the guide's channel column is logo-only.
- Guide rows carry the channel name in a thin strip pinned to the left of the
  visible timeline. The name no longer competes with the logo for space, stays
  readable while the timeline scrolls, and does not cover or shift programme
  text: programme blocks keep their previous size and time alignment.
- The guide header no longer appends the redundant "12-hour window" label,
  which was the first thing truncated on narrow screens.
- The app tagline is now "Stream, Your Wave".

### Fixed

- HLS streams whose master playlist advertises a subtitle rendition play again.
  media_kit hands ffmpeg `strict=experimental`, which enables its unfinished
  `EXT-X-MEDIA` support; ErsatzTV publishes a `DEFAULT=YES` WebVTT rendition,
  so ffmpeg switched to the subtitle playlist and read `.vtt` segments only,
  leaving video and audio silent behind the spinner while the server kept
  transcoding. The player now passes the same demuxer options without that
  flag, so the rendition is ignored and the video playlist stays active.
- The built-in player uses GPU video output by default again on Linux, so
  desktop playback is smooth instead of CPU-converted. A new Settings →
  Playback renderer choice keeps the old software path as an escape hatch for
  Wayland/Mesa systems where the EGLImage texture freezes, and
  `MOJAC_PLAYER_RENDERER=software` overrides it without changing settings. Set
  `MOJAC_MPV_LOG=1` to get libmpv diagnostics.
- The software path starts with a 1280x720 texture and follows the stream's
  aspect ratio. Without a known size media_kit never rendered a first frame,
  so playback stalled behind a black texture with no audio.
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
