#!/bin/sh
set -eu
source_png=$1
output=$2
iconset=build/FauxRK.iconset
mkdir -p "$iconset" "$(dirname "$output")"
for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" "$source_png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -s format png -z "$retina" "$retina" "$source_png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns -o "$output" "$iconset"
