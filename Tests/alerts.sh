#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
work=$(mktemp -d build/alerts-test.XXXXXX)
trap 'rm -rf "$work"' EXIT
xcrun clang -fobjc-arc -fmodules -Wall -I Sources -framework Cocoa -framework UserNotifications \
  Tests/alerts.m Sources/RKAlerts.m -o "$work/alerts-tests"
"$work/alerts-tests"
