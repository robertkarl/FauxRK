#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/tmp
work=$(mktemp -d "$PWD/build/tmp/routing.XXXXXX")
trap 'rm -rf "$work"' EXIT
set --
for source in Sources/*.m; do
    [ "$source" = Sources/main.m ] || set -- "$@" "$source"
done
xcrun clang -fobjc-arc -fmodules -Wall -ISources Tests/routing.m "$@" -framework Cocoa \
    -framework AVFoundation -framework AudioToolbox -framework ApplicationServices -framework UserNotifications -o "$work/routing"
"$work/routing"
