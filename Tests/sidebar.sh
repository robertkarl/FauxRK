#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/tmp
work=$(mktemp -d "$PWD/build/tmp/sidebar.XXXXXX")
export TMPDIR="$work"
trap 'rm -rf "$work"' EXIT
xcrun clang -fobjc-arc -fmodules -Wall -I Sources -framework Cocoa -framework QuartzCore \
  Tests/sidebar.m Sources/RKSidebar.m Sources/RK*View*.m -o "$work/sidebar-tests"
"$work/sidebar-tests"
