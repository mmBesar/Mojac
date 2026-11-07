# Building Mojac

Mojac targets Flutter **3.47.8** (Dart **3.13.x**). The generated `android/`
and `linux/` directories are not checked in; they are recreated from the pinned
SDK so that Flutter template changes never conflict with Mojac's small set of
platform patches.

## Prerequisites

### All platforms

- Git and Python 3 (used by `tool/configure_platforms.py`).
- Network access for the Flutter SDK, pub packages and platform artifacts.
- `bash` for the scripts in `tool/` (Linux and macOS; on Windows use WSL).

### Android

- JDK 17.
- Android SDK with build tools and platform 35 (or whatever the pinned Flutter
  version requests). Android Studio's SDK Manager or the command-line tools
  are both fine.
- Accept the SDK licenses (`flutter doctor --android-licenses`).

### Linux

Ubuntu 24.04 package names:

```bash
sudo apt-get update
sudo apt-get install --yes --no-install-recommends \
  clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libmpv-dev \
  libxi-dev libx11-dev \
  dpkg-dev rpm
```

`libxi-dev` and `libx11-dev` are needed by the window-management plugin that
gives the built-in player real desktop fullscreen. `cnativeapi` (its
transitive native-assets dependency) runs `pkg-config gtk+-3.0 x11 xi` at
build time, so `flutter test` needs those headers too, not just
`flutter build linux`.

`libmpv-dev` is only needed to compile/link against libmpv; the resulting
application loads libmpv at runtime, so end users need `libmpv2`/`libmpv1`
(or `mpv-libs` on RPM distributions).

## Get the Flutter SDK

### x86_64 Linux

Install the 3.47.8 stable SDK however you prefer, for example:

```bash
git clone --depth 1 --branch 3.47.8 \
  https://github.com/flutter/flutter.git "$HOME/flutter"
export PATH="$HOME/flutter/bin:$PATH"
```

`tool/bootstrap.sh` does this automatically into `./.flutter` if `flutter` is
not already on `PATH`:

```bash
FLUTTER_VERSION=3.47.8 tool/bootstrap.sh
```

### aarch64 Linux

The GitHub-hosted ARM64 runner is `ubuntu-24.04-arm`. Flutter's prebuilt Linux
SDK archive is not available for every ARM64 release, so CI clones the SDK
source and lets it download the ARM64 Dart SDK and engine artifacts:

```bash
git clone --depth 1 --branch 3.47.8 \
  https://github.com/flutter/flutter.git "$RUNNER_TEMP/flutter"
export PATH="$RUNNER_TEMP/flutter/bin:$PATH"
tool/bootstrap.sh
```

This is exactly what the `linux-arm64` CI job does. It needs network access and
a few minutes on the first run.

## Bootstrap

From the repository root:

```bash
tool/bootstrap.sh
```

The script:

1. Locates Flutter (or clones it into `./.flutter`).
2. Disables analytics and enables Linux desktop.
3. Runs `flutter create --platforms=android,linux --org com.mmbesar
   --project-name mojac` in a temporary directory, and copies only platform
   folders that do not already exist.
4. Calls `tool/configure_platforms.py` to set the application id
   `com.mmbesar.mojac`, the Android label, `minSdk` 24, network/wakelock
   permissions, cleartext support, launcher icons and the Linux window title.
5. Runs `flutter pub get`.

Bootstrap is idempotent. Run it again after changing the pinned Flutter version;
existing shell folders are left alone, so delete `android/` or `linux/` if you
need a clean template.

## Build

```bash
# Android, ARM64 only (produces app-release.apk; CI renames it to
# Mojac-<version>-arm64-v8a.apk for the release)
flutter build apk --release --target-platform android-arm64

# Linux, native host architecture
flutter build linux --release
```

Linux bundle locations:

- `build/linux/x64/release/bundle` (x86_64)
- `build/linux/arm64/release/bundle` (aarch64)

The bundle contains the `mojac` executable, `lib/` and `data/`. It is not
relocatable on its own unless you preserve that layout, which is why the Linux
packages put it under `/opt/mojac`.

## Package Linux releases

`tool/package_linux.sh` stages the bundle and produces DEB, RPM and AppImage
artifacts under `dist/`:

```bash
tool/package_linux.sh \
  --bundle build/linux/x64/release/bundle \
  --arch amd64 \
  --formats deb,rpm,appimage
```

| Option | Meaning |
| --- | --- |
| `--bundle DIR` | Flutter release bundle directory |
| `--arch amd64\|arm64` | Target architecture (aliases `x86_64`/`aarch64`) |
| `--version X.Y.Z` | Package version; defaults to `pubspec.yaml` |
| `--out DIR` | Output directory; defaults to `dist` |
| `--formats LIST` | Any subset of `deb,rpm,appimage` |

Details:

- **DEB** — installs into `/opt/mojac`, adds `/usr/bin/mojac`, the
  `com.mmbesar.mojac.desktop` launcher, a 512×512 icon and matching AppStream
  metainfo under `/usr/share/metainfo`. Depends on
  `libgtk-3-0t64 | libgtk-3-0` (Ubuntu 24.04 renamed the package),
  `libmpv2 | libmpv1` and the usual C++ runtime libraries.
- **RPM** — same layout, requires `gtk3` and `mpv-libs`; the metainfo is
  installed alongside the desktop file so package managers can show the
  application in their software centres.
- **AppImage** — bundles the Flutter app under `usr/bin`, sets
  `LD_LIBRARY_PATH` to `usr/bin/lib`, and downloads `appimagetool` for the
  target architecture unless `APPIMAGETOOL` points at an existing binary.
  libmpv is still required from the host.

The AppImage download URLs are:

- `https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage`
- `https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-aarch64.AppImage`

CI runs appimagetool with `APPIMAGE_EXTRACT_AND_RUN=1` because the runner has no
FUSE.

## Continuous integration

`.github/workflows/build.yml` runs on pushes to `main`, pull requests, tags
matching `v*`, and manual dispatches.

| Job | Runner | Output |
| --- | --- | --- |
| `quality` | `ubuntu-24.04` | `flutter analyze`, `flutter test` |
| `android` | `ubuntu-24.04` | ARM64 release APK artifact |
| `linux-amd64` | `ubuntu-24.04` | DEB, RPM, AppImage |
| `linux-arm64` | `ubuntu-24.04-arm` | DEB, RPM, AppImage |
| `release` | `ubuntu-24.04` | GitHub release + `SHA256SUMS` on tags |

The ARM64 runner is free only for **public** repositories. The workflow checks
`github.event.repository.private` and skips the ARM64 leg on private
repositories, so a private fork still builds the x86_64 packages. Tag releases
are published only for tags pushed to the canonical repository.

To cut a release:

1. Update the version in `pubspec.yaml` and `lib/core/app_info.dart`
   (`kAppVersion`); they must match.
2. Add a `CHANGELOG.md` entry.
3. Commit and tag: `git tag v0.1.1 && git push origin main v0.1.1`.
4. The `release` job publishes the platform artifacts and checksums.

### Signing the Android APK

`tool/configure_platforms.py` adds an optional release signing config to the
generated Gradle file. It reads `android/key.properties` when that file exists
and otherwise falls back to Flutter's debug signing, so local builds keep
working without secrets.

Create the upload key once:

```bash
keytool -genkeypair -v \
  -keystore mojac.jks \
  -alias mojac \
  -keyalg RSA -keysize 4096 -validity 10000
```

Back the `.jks` file up in at least two places and keep the passwords in a
password manager. A lost upload key can only be replaced through Play Console
support; a leaked one lets someone publish as you. Never commit the keystore,
`key.properties`, or the passwords.

Add these four repository secrets (Settings → Secrets and variables → Actions):

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_B64` | The `.jks` file, base64-encoded |
| `ANDROID_KEYSTORE_PASSWORD` | The keystore password |
| `ANDROID_KEY_ALIAS` | `mojac` (or the alias you chose) |
| `ANDROID_KEY_PASSWORD` | The key password |

Encode the keystore without line wrapping:

```bash
base64 --wrap=0 mojac.jks > mojac.jks.b64
# copy the file contents into the ANDROID_KEYSTORE_B64 secret
```

On each Android build CI decodes the keystore into `$RUNNER_TEMP/signing`,
writes `android/key.properties`, builds, verifies the APK with `apksigner
verify --print-certs`, and deletes the signing material. If
`ANDROID_KEYSTORE_B64` is absent the build still succeeds with a debug-signed
APK and a workflow warning.

`keytool` can create either the classic JKS format or PKCS12 (the default in
newer JDKs). Both work with Android Gradle Plugin; the extension does not have
to be `.jks` as long as `storeFile` points at the file. For Play Store
distribution, enrol in Play App Signing: Google keeps the app-signing key and
this upload key only signs the bundle you upload.

For a local signed build, run `tool/bootstrap.sh`, then create
`android/key.properties` with absolute paths:

```properties
storeFile=/home/you/keys/mojac.jks
storePassword=…
keyAlias=mojac
keyPassword=…
```

### Dependency lockfile

`pubspec.lock` is generated by `flutter pub get` and is not committed. Mojac is
built in CI from the version ranges in `pubspec.yaml`; there is no local Flutter
installation in the development environment. If you need reproducible builds,
commit the lockfile from a machine that has the pinned SDK.

## Troubleshooting

- **`flutter: command not found`** — run `tool/bootstrap.sh`, or add
  `./.flutter/bin` to `PATH`.
- **Linux build cannot find GTK** — install `libgtk-3-dev` and `pkg-config`.
- **`libmpv.so` missing at runtime** — install `libmpv2`/`libmpv1` (or
  `mpv-libs`). The AppImage does not include libmpv.
- **`flutter create` fails with an existing project name** — bootstrap creates
  the template in a temporary directory, so this usually means `--project-name`
  or the pinned SDK changed; remove the generated `android/`/`linux/` folders
  and rerun.
- **ARM64 job is skipped** — the repository is private; use a self-hosted ARM64
  runner or build the packages manually.
- **Android build fails on SDK licenses** — run
  `flutter doctor --android-licenses` locally, or add the license acceptance
  step to your own CI.
