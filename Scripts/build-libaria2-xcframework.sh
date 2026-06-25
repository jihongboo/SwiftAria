#!/bin/sh
set -eu

ARIA2_VERSION="${ARIA2_VERSION:-1.37.0}"
PROTOCOL_PROFILE="${PROTOCOL_PROFILE:-minimal}"
PACKAGE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="${WORK_DIR:-/tmp/swiftaria-aria2-build}"
INSTALL_DIR="${INSTALL_DIR:-/tmp/swiftaria-aria2-install}"
DAEMON_OUTPUT="${DAEMON_OUTPUT:-$PACKAGE_ROOT/Sources/SwiftAria/Resources/aria2c}"
SOURCE_URL="https://github.com/aria2/aria2/releases/download/release-$ARIA2_VERSION/aria2-$ARIA2_VERSION.tar.xz"

export CFLAGS="${CFLAGS:--Os -DNDEBUG}"
export CXXFLAGS="${CXXFLAGS:--Os -DNDEBUG}"

append_pkg_config_path() {
  if command -v brew >/dev/null 2>&1 && brew --prefix "$1" >/dev/null 2>&1; then
    prefix="$(brew --prefix "$1")"
    if [ -d "$prefix/lib/pkgconfig" ]; then
      PKG_CONFIG_PATH="${PKG_CONFIG_PATH:+$PKG_CONFIG_PATH:}$prefix/lib/pkgconfig"
      export PKG_CONFIG_PATH
    fi
    CPPFLAGS="${CPPFLAGS:-} -I$prefix/include"
    LDFLAGS="${LDFLAGS:-} -L$prefix/lib"
    export CPPFLAGS LDFLAGS
  fi
}

CONFIGURE_PROTOCOL_OPTIONS=""
case "$PROTOCOL_PROFILE" in
  minimal)
    CONFIGURE_PROTOCOL_OPTIONS="--disable-bittorrent --disable-metalink --disable-websocket --without-gnutls --without-openssl --without-sqlite3 --without-libxml2 --without-libcares --without-libssh2"
    ;;
  magnet)
    CONFIGURE_PROTOCOL_OPTIONS="--disable-metalink --disable-websocket --without-gnutls --without-openssl --without-sqlite3 --without-libxml2 --without-libcares --without-libssh2"
    ;;
  full)
    append_pkg_config_path c-ares
    append_pkg_config_path libssh2
    append_pkg_config_path openssl@3
    append_pkg_config_path sqlite
    append_pkg_config_path libxml2
    CONFIGURE_PROTOCOL_OPTIONS="--without-gnutls"
    ;;
  *)
    echo "Unsupported PROTOCOL_PROFILE: $PROTOCOL_PROFILE" >&2
    echo "Use one of: minimal, magnet, full" >&2
    exit 2
    ;;
esac

rm -rf "$WORK_DIR" "$INSTALL_DIR"
mkdir -p "$WORK_DIR" "$(dirname "$DAEMON_OUTPUT")"

cd "$WORK_DIR"
curl -L -o "aria2-$ARIA2_VERSION.tar.xz" "$SOURCE_URL"
tar -xf "aria2-$ARIA2_VERSION.tar.xz"

cd "aria2-$ARIA2_VERSION"
# shellcheck disable=SC2086
./configure \
  --prefix="$INSTALL_DIR" \
  --host=arm-apple-darwin \
  --disable-shared \
  $CONFIGURE_PROTOCOL_OPTIONS

make -j"$(sysctl -n hw.ncpu)"
make install

strip -S "$INSTALL_DIR/bin/aria2c"
cp "$INSTALL_DIR/bin/aria2c" "$DAEMON_OUTPUT"
chmod 755 "$DAEMON_OUTPUT"

du -sh "$DAEMON_OUTPUT"
echo "Wrote $DAEMON_OUTPUT"
echo "Protocol profile: $PROTOCOL_PROFILE"
