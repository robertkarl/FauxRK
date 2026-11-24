#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
xcrun clang -fobjc-arc -framework Foundation -ISources Sources/RKPaneOrder.m Tests/order.m -o build/order-test
build/order-test
