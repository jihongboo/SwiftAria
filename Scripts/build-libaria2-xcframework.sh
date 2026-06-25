#!/bin/sh
set -eu

ARIA2_VERSION="${ARIA2_VERSION:-1.37.0}"
PACKAGE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="${WORK_DIR:-/tmp/swiftaria-aria2-build}"
INSTALL_DIR="${INSTALL_DIR:-/tmp/swiftaria-aria2-install}"
OUTPUT_DIR="${OUTPUT_DIR:-$PACKAGE_ROOT/Vendor/Aria2.xcframework}"
SOURCE_URL="https://github.com/aria2/aria2/releases/download/release-$ARIA2_VERSION/aria2-$ARIA2_VERSION.tar.xz"

export CFLAGS="${CFLAGS:--Os -DNDEBUG}"
export CXXFLAGS="${CXXFLAGS:--Os -DNDEBUG}"

rm -rf "$WORK_DIR" "$INSTALL_DIR" "$OUTPUT_DIR"
mkdir -p "$WORK_DIR" "$(dirname "$OUTPUT_DIR")"

cd "$WORK_DIR"
curl -L -o "aria2-$ARIA2_VERSION.tar.xz" "$SOURCE_URL"
tar -xf "aria2-$ARIA2_VERSION.tar.xz"

cd "aria2-$ARIA2_VERSION"
./configure \
  --prefix="$INSTALL_DIR" \
  --host=arm-apple-darwin \
  --enable-libaria2 \
  --enable-static \
  --disable-shared \
  --disable-bittorrent \
  --disable-metalink \
  --disable-websocket \
  --without-gnutls \
  --without-openssl \
  --without-sqlite3 \
  --without-libxml2 \
  --without-libcares \
  --without-libssh2

make -j"$(sysctl -n hw.ncpu)"
make install

strip -S "$INSTALL_DIR/lib/libaria2.a"

xcodebuild -create-xcframework \
  -library "$INSTALL_DIR/lib/libaria2.a" \
  -headers "$INSTALL_DIR/include" \
  -output "$OUTPUT_DIR"

du -sh "$OUTPUT_DIR"
echo "Wrote $OUTPUT_DIR"
