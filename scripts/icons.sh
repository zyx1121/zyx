#!/bin/sh
# Renders Resources/Logo.svg into AppIcon.icns. MenuIcon.pdf comes from zyx1121/cappuccino.
set -eu
cd "$(dirname "$0")/../Resources"
set=$(mktemp -d)/AppIcon.iconset
mkdir -p "$set"
for s in 16 32 128 256 512; do
  for k in 1 2; do
    px=$((s * k)); name=icon_${s}x${s}; [ $k = 2 ] && name=${name}@2x
    # The logo, centered on a white rounded square at 80 percent.
    inner=$((px * 64 / 100))
    rsvg-convert -w $inner -h $inner --keep-aspect-ratio Logo.svg -o "$set/logo.png"
    magick -size ${px}x${px} xc:none -fill white \
      -draw "roundrectangle $((px/10)),$((px/10)) $((px*9/10-1)),$((px*9/10-1)) $((px*18/100)),$((px*18/100))" \
      "$set/logo.png" -gravity center -composite "$set/$name.png"
  done
done
rm "$set/logo.png"
iconutil -c icns "$set" -o AppIcon.icns
