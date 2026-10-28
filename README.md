# Mojac

Mojac is a small, focused IPTV client for **Android (ARM64)** and **Linux
(x86_64 / aarch64)**. It reads M3U/M3U8 playlists and XMLTV guides, and is built
around a 12-hour programme timeline with first-class Arabic/English
bidirectional text.

Mojac was written for a self-hosted [Tunarr](https://tunarr.com/) setup, but it
works with any source that serves a standard M3U playlist and an XMLTV file.

![GPL-3.0-or-later](https://img.shields.io/badge/license-GPL--3.0--or--later-blue)

## Features

- **M3U + XMLTV** — channel names, numbers, logos, groups, `tvg-id`,
  `group-title`, `#EXTGRP`, `url-tvg`/`x-tvg-url`, `sub-title`, descriptions,
  categories, icons and `episode-num`.
- **12-hour guide** — a scrollable timeline that starts half an hour before the
  current time. The current programme is highlighted and a live line marks
  "now". The guide shows 12-hour clock times by default; 24-hour time is one
  switch away.
- **Bidirectional UI** — English and Arabic interfaces, with per-string
  directionality for mixed Arabic/Latin text, numbers and channel names. The
  guide, player and programme sheet all use the same bidi-aware text widget.
- **Multiple sources** — store as many M3U/XMLTV pairs as you like, each with
  its own URL or local file and its own TLS policy. Only the active source is
  loaded, so channel ids and programme data never mix.
- **Self-signed HTTPS** — an opt-in per-source switch accepts self-signed
  certificates for the playlist, the guide, channel logos and playback.
- **Offline fallback** — the last successful snapshot of each source is cached
  for up to 30 days. A failed refresh keeps showing the cached guide instead of
  an empty screen.
- **Themes** — all four Catppuccin flavours (Latte, Frappé, Macchiato, Mocha),
  all fourteen Catppuccin accents, a pure-black AMOLED mode with Catppuccin
  accents, and a system mode that follows Android dynamic colour / the desktop
  light-dark preference.
- **Playback** — libmpv through `media_kit`, with HLS support, hardware
  decoding, a fullscreen mode and a wakelock while a channel is open.

## Supported platforms

| Platform | Architecture | Package |
| --- | --- | --- |
| Android 7.0+ | `arm64-v8a` | APK |
| Linux | `x86_64` | DEB, RPM, AppImage |
| Linux | `aarch64` | DEB, RPM, AppImage |

Linux packages are built and tested on Ubuntu 24.04. Other distributions work
as long as GTK 3 and libmpv are available. The AppImage bundles the Flutter
application but **not** libmpv; install `libmpv2`/`libmpv1` (or your
distribution's `mpv-libs`) first.

## Install

Download the file for your platform from the
[Releases](https://github.com/mmbesar/Mojac/releases) page. Every release
includes a `SHA256SUMS` file:

```bash
sha256sum -c SHA256SUMS
```

### Android

Sideload `Mojac-<version>-arm64-v8a.apk`. The release APK is signed with
Flutter's debug key so it can be installed directly; it is not suitable for
Play Store distribution. Allow installation from unknown sources for your file
manager or browser when prompted.

### Debian / Ubuntu

```bash
sudo apt install ./mojac_<version>_amd64.deb
# or: sudo apt install ./mojac_<version>_arm64.deb
```

### Fedora / RHEL-family

```bash
sudo dnf install ./mojac-<version>-1.x86_64.rpm
# or the aarch64 RPM
```

### AppImage

```bash
chmod +x Mojac-<version>-x86_64.AppImage
./Mojac-<version>-x86_64.AppImage
```

## Add a source

1. Open **Sources → Add source**.
2. Give the source a name.
3. Enter the playlist location:
   - Tunarr: `https://tunarr.hs.lan/api/channels.m3u`
   - or choose a local `.m3u`/`.m3u8` file.
4. Enter the XMLTV location:
   - Tunarr: `https://tunarr.hs.lan/api/xmltv.xml`
   - or leave it empty if the playlist advertises `url-tvg`/`x-tvg-url`.
5. If the server uses a self-signed certificate (common for `.lan` hosts), turn
   on **Allow self-signed HTTPS certificates**. Plain HTTP is always accepted.
6. Use **Test connection** to verify the playlist and guide before saving, then
   **Save**.

The active source is loaded immediately. Use **Refresh** to reload it, or pick
a different source from the Sources page.

## Build from source

Flutter's generated `android/` and `linux/` shells are intentionally not
committed. `tool/bootstrap.sh` creates them from the pinned SDK and applies the
Mojac-specific manifest, Gradle, icon and Linux runner changes.

```bash
git clone https://github.com/mmbesar/Mojac.git
cd Mojac
tool/bootstrap.sh          # creates platform shells and runs flutter pub get
flutter build apk --release --target-platform android-arm64
flutter build linux --release
tool/package_linux.sh --bundle build/linux/x64/release/bundle --arch amd64
```

See [docs/BUILDING.md](docs/BUILDING.md) for prerequisites, the CI matrix, and
release steps. Source/format details are in [docs/SOURCES.md](docs/SOURCES.md).

## Project layout

```
lib/
  core/      bidi text, Catppuccin palettes, theming, TLS-aware images
  data/      models, storage, M3U/XMLTV parsers, loader, app state
  l10n/      English/Arabic strings and date/time formatting
  ui/        app shell, channels, guide, player, sources, settings
assets/
  branding/  SVG source and generated launcher icons
  fonts/     Noto Sans Arabic (variable)
tool/        platform bootstrap, icon generation, Linux packaging
.github/     CI for analysis, tests, APKs and Linux packages
```

## Known limitations

- Only Android ARM64 and Linux x86_64/aarch64 are supported. There are no iOS,
  macOS, Windows or web targets.
- The Android APK is debug-signed. Configure a release keystore before
  publishing it anywhere.
- Linux playback requires a system libmpv. The AppImage does not bundle it.
- The GitHub-hosted `ubuntu-24.04-arm` runner used for ARM64 Linux builds is
  free for public repositories only. Private forks skip that job automatically;
  build the ARM64 packages on your own runner instead.
- Mojac does not include EPG data, channel streams or any credentials. It only
  reads the sources you configure.

## Contributing

Bug reports and pull requests are welcome. Read
[CONTRIBUTING.md](CONTRIBUTING.md) first. For security issues, follow
[SECURITY.md](SECURITY.md) instead of opening a public issue.

## License

Mojac is licensed under the GNU General Public License, version 3 or later.
See [LICENSE](LICENSE). The bundled Noto Sans Arabic font is licensed under the
SIL Open Font License; its license text is in `assets/fonts/OFL.txt`.
