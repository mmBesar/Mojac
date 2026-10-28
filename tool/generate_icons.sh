#!/usr/bin/env bash
# Regenerates launcher icons from assets/branding/mojac.svg.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG="$ROOT/assets/branding/mojac.svg"
BRANDING="$ROOT/assets/branding"

if [[ ! -f "$SVG" ]]; then
  echo "Missing $SVG" >&2
  exit 1
fi

render() {
  local size="$1"
  local output="$2"
  if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w "$size" -h "$size" "$SVG" -o "$output"
  elif command -v magick >/dev/null 2>&1; then
    magick -background none "$SVG" -resize "${size}x${size}" "$output"
  elif command -v convert >/dev/null 2>&1; then
    convert -background none "$SVG" -resize "${size}x${size}" "$output"
  elif command -v inkscape >/dev/null 2>&1; then
    inkscape "$SVG" -w "$size" -h "$size" -o "$output"
  else
    echo "Install rsvg-convert, ImageMagick or Inkscape to render icons." >&2
    exit 1
  fi
}

mkdir -p "$BRANDING/linux"
render 512 "$BRANDING/mojac_icon.png"
render 512 "$BRANDING/linux/mojac.png"

for pair in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  density="${pair%%:*}"
  size="${pair##*:}"
  mkdir -p "$BRANDING/android/mipmap-$density"
  render "$size" "$BRANDING/android/mipmap-$density/ic_launcher.png"
done

echo "Icons regenerated under assets/branding/."
