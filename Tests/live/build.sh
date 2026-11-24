#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
mkdir -p build
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Wno-unused-parameter -ISources \
  Sources/RKCore.m Sources/RKMonitor.m Sources/RKPaneScreen.m Sources/RKHelper.m Tests/live/harness.m \
  -framework AppKit -framework ApplicationServices -o build/live-qa
