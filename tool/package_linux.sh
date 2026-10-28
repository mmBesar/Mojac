#!/usr/bin/env bash
# Packages a Flutter Linux release bundle as DEB, RPM and AppImage.
#
# Usage:
#   tool/package_linux.sh --bundle build/linux/x64/release/bundle \
#     --arch amd64 --version 0.1.0
#
# AppImage output requires appimagetool. Set APPIMAGETOOL to an existing
# binary, otherwise the script downloads one for the target architecture.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE=""
ARCH=""
VERSION=""
OUT="$ROOT/dist"
FORMATS="deb,rpm,appimage"

usage() {
  cat <<'EOF'
Usage: tool/package_linux.sh --bundle DIR --arch amd64|arm64 [options]

Options:
  --bundle DIR        Flutter Linux release bundle directory
  --arch ARCH         amd64 (x86_64) or arm64 (aarch64)
  --version VERSION   Package version (defaults to pubspec.yaml)
  --out DIR           Output directory (default: dist)
  --formats LIST      Comma-separated subset of deb,rpm,appimage
  -h, --help          Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle) BUNDLE="${2:-}"; shift 2 ;;
    --arch) ARCH="${2:-}"; shift 2 ;;
    --version) VERSION="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --formats) FORMATS="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$BUNDLE" || -z "$ARCH" ]]; then
  usage >&2
  exit 2
fi

case "$ARCH" in
  amd64|x86_64)
    DEB_ARCH="amd64"
    RPM_ARCH="x86_64"
    APPIMAGE_ARCH="x86_64"
    ;;
  arm64|aarch64)
    DEB_ARCH="arm64"
    RPM_ARCH="aarch64"
    APPIMAGE_ARCH="aarch64"
    ;;
  *)
    echo "Unsupported architecture: $ARCH (expected amd64 or arm64)" >&2
    exit 2
    ;;
esac

BUNDLE="$(cd "$BUNDLE" && pwd)"
if [[ ! -x "$BUNDLE/mojac" ]]; then
  echo "No executable 'mojac' found in $BUNDLE" >&2
  exit 1
fi

if [[ -z "$VERSION" ]]; then
  VERSION="$(sed -n 's/^version: *\([0-9][0-9.]*\).*/\1/p' "$ROOT/pubspec.yaml" | head -n1)"
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid version: $VERSION" >&2
  exit 2
fi

ICON="$ROOT/assets/branding/linux/mojac.png"
DESKTOP="$ROOT/assets/branding/mojac.desktop"
if [[ ! -f "$ICON" ]]; then
  echo "Missing $ICON; run tool/generate_icons.sh" >&2
  exit 1
fi
if [[ ! -f "$DESKTOP" ]]; then
  echo "Missing $DESKTOP" >&2
  exit 1
fi

WORK="$ROOT/build/package/$DEB_ARCH"
ROOTFS="$WORK/rootfs"
rm -rf "$WORK"
mkdir -p "$OUT" "$ROOTFS/opt/mojac" \
  "$ROOTFS/usr/bin" \
  "$ROOTFS/usr/share/applications" \
  "$ROOTFS/usr/share/icons/hicolor/512x512/apps"

cp -a "$BUNDLE/." "$ROOTFS/opt/mojac/"
chmod +x "$ROOTFS/opt/mojac/mojac"
ln -sfn /opt/mojac/mojac "$ROOTFS/usr/bin/mojac"
install -m644 "$ICON" "$ROOTFS/usr/share/icons/hicolor/512x512/apps/mojac.png"
install -m644 "$DESKTOP" "$ROOTFS/usr/share/applications/mojac.desktop"

echo "Staged $(du -sh "$ROOTFS/opt/mojac" | cut -f1) application bundle for $DEB_ARCH."

has_format() {
  [[ ",$FORMATS," == *",$1,"* ]]
}

build_deb() {
  command -v dpkg-deb >/dev/null 2>&1 || {
    echo "dpkg-deb is required for DEB output" >&2
    return 1
  }

  local deb_root="$WORK/deb"
  rm -rf "$deb_root"
  cp -a "$ROOTFS" "$deb_root"
  mkdir -p "$deb_root/DEBIAN"

  cat > "$deb_root/DEBIAN/control" <<EOF
Package: mojac
Version: $VERSION-1
Section: video
Priority: optional
Architecture: $DEB_ARCH
Installed-Size: $(du -sk "$deb_root/opt" | cut -f1)
Maintainer: mmbesar <mbesar@proton.me>
Homepage: https://github.com/mmbesar/Mojac
Depends: libgtk-3-0t64 | libgtk-3-0, libmpv2 | libmpv1, libstdc++6, libblkid1, liblzma5
Recommends: fonts-noto-core
Description: Bidirectional IPTV client for Android and Linux
 Mojac plays M3U playlists with an XMLTV guide, a 12-hour timeline and
 first-class Arabic/English bidirectional text. It supports Catppuccin,
 AMOLED and system themes, multiple sources and self-signed HTTPS.
EOF

  dpkg-deb --build --root-owner-group "$deb_root" \
    "$OUT/mojac_${VERSION}_${DEB_ARCH}.deb" >/dev/null
  echo "  built mojac_${VERSION}_${DEB_ARCH}.deb"
}

build_rpm() {
  command -v rpmbuild >/dev/null 2>&1 || {
    echo "rpmbuild is required for RPM output" >&2
    return 1
  }

  local rpmbuild_root="$WORK/rpmbuild"
  local spec="$WORK/mojac.spec"
  mkdir -p "$rpmbuild_root"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

  cat > "$spec" <<EOF
%global debug_package %{nil}
Name:           mojac
Version:        $VERSION
Release:        1
Summary:        Bidirectional IPTV client with a 12-hour guide
License:        GPL-3.0-or-later
URL:            https://github.com/mmbesar/Mojac
BuildArch:      $RPM_ARCH
Requires:       gtk3
Requires:       mpv-libs

%description
Mojac plays M3U playlists with an XMLTV guide, a 12-hour timeline and
first-class Arabic/English bidirectional text. It supports Catppuccin,
AMOLED and system themes, multiple sources and self-signed HTTPS.

%prep

%build

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
cp -a "$ROOTFS/." %{buildroot}/

%files
/opt/mojac
/usr/bin/mojac
/usr/share/applications/mojac.desktop
/usr/share/icons/hicolor/512x512/apps/mojac.png
EOF

  rpmbuild -bb \
    --define "_topdir $rpmbuild_root" \
    --target "$RPM_ARCH" \
    "$spec" >/dev/null

  local package
  package="$(find "$rpmbuild_root/RPMS" -type f -name '*.rpm' -print -quit)"
  if [[ -z "$package" ]]; then
    echo "rpmbuild did not produce a package" >&2
    return 1
  fi
  cp "$package" "$OUT/"
  echo "  built $(basename "$package")"
}

build_appimage() {
  local appdir="$WORK/Mojac.AppDir"
  rm -rf "$appdir"
  mkdir -p "$appdir/usr/bin" \
    "$appdir/usr/share/applications" \
    "$appdir/usr/share/icons/hicolor/512x512/apps"

  cp -a "$BUNDLE/." "$appdir/usr/bin/"
  install -m644 "$ICON" "$appdir/usr/share/icons/hicolor/512x512/apps/mojac.png"
  install -m644 "$DESKTOP" "$appdir/usr/share/applications/mojac.desktop"
  install -m644 "$ICON" "$appdir/mojac.png"
  install -m644 "$DESKTOP" "$appdir/mojac.desktop"
  ln -sfn mojac.png "$appdir/.DirIcon"

  cat > "$appdir/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/bin/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$HERE/usr/bin/mojac" "$@"
EOF
  chmod +x "$appdir/AppRun"

  local tool="${APPIMAGETOOL:-$WORK/appimagetool}"
  if [[ ! -x "$tool" ]]; then
    command -v curl >/dev/null 2>&1 || {
      echo "curl is required to download appimagetool" >&2
      return 1
    }
    echo "Downloading appimagetool for $APPIMAGE_ARCH"
    curl -fsSL \
      "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${APPIMAGE_ARCH}.AppImage" \
      -o "$tool"
    chmod +x "$tool"
  fi

  ARCH="$APPIMAGE_ARCH" APPIMAGE_EXTRACT_AND_RUN=1 "$tool" \
    "$appdir" "$OUT/Mojac-${VERSION}-${APPIMAGE_ARCH}.AppImage" >/dev/null
  chmod +x "$OUT/Mojac-${VERSION}-${APPIMAGE_ARCH}.AppImage"
  echo "  built Mojac-${VERSION}-${APPIMAGE_ARCH}.AppImage"
}

STATUS=0
if has_format deb; then build_deb || STATUS=1; fi
if has_format rpm; then build_rpm || STATUS=1; fi
if has_format appimage; then build_appimage || STATUS=1; fi

echo "Release files in $OUT:"
ls -lh "$OUT"
exit "$STATUS"
