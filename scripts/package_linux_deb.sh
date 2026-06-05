#!/usr/bin/env bash
set -euo pipefail

version=$(grep '^version:' pubspec.yaml | awk '{print $2}')
bundle=${1:-build/linux/x64/release/bundle}
dist=${2:-dist}
pkgroot=$(mktemp -d)
chmod 0755 "$pkgroot"

cleanup() {
  rm -rf "$pkgroot"
}
trap cleanup EXIT

if [[ ! -d "$bundle" ]]; then
  echo "Linux release bundle not found: $bundle" >&2
  exit 1
fi

mkdir -p \
  "$pkgroot/DEBIAN" \
  "$pkgroot/usr/bin" \
  "$pkgroot/usr/lib/prism" \
  "$pkgroot/usr/share/applications" \
  "$pkgroot/usr/share/metainfo" \
  "$pkgroot/usr/share/icons"

# Copy the Flutter bundle without the portable tarball wrapper/metadata.
tar -C "$bundle" \
  --exclude='./prism' \
  --exclude='./share' \
  -cf - . | tar -C "$pkgroot/usr/lib/prism" -xf -

cat > "$pkgroot/usr/bin/prism" <<'WRAPPER'
#!/bin/sh
export GDK_BACKEND=x11
# soloud's FFI plugin is dlopened and finds its bundled audio codecs only here.
export LD_LIBRARY_PATH="/usr/lib/prism/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec /usr/lib/prism/prism_plurality "$@"
WRAPPER
chmod 0755 "$pkgroot/usr/bin/prism"

cp packaging/linux/com.prismplural.prism.desktop "$pkgroot/usr/share/applications/"
cp packaging/linux/com.prismplural.prism.metainfo.xml "$pkgroot/usr/share/metainfo/"
cp -R packaging/linux/icons/hicolor "$pkgroot/usr/share/icons/"

find "$pkgroot/usr/share" -type d -exec chmod 0755 {} +
find "$pkgroot/usr/share" -type f -exec chmod 0644 {} +
find "$pkgroot/usr/lib/prism" -type d -exec chmod 0755 {} +
find "$pkgroot/usr/lib/prism" -type f -exec chmod 0644 {} +
chmod 0755 "$pkgroot/usr/lib/prism/prism_plurality"
find "$pkgroot/usr/lib/prism/lib" -type f -name '*.so*' -exec chmod 0755 {} + 2>/dev/null || true

installed_size=$(du -sk "$pkgroot/usr" | awk '{print $1}')

# No libjsoncpp here: flutter_secure_storage_linux (its only past user) went
# header-only nlohmann/json in 1.2.0, so nothing in the bundle links it. A
# versioned libjsoncppNN dep only breaks apt on distros whose jsoncpp soname
# differs from the build runner's (e.g. Ubuntu 25.x / Debian trixie ship 26).
cat > "$pkgroot/DEBIAN/control" <<CONTROL
Package: prism
Version: $version
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Prism Contributors <maintainers@prismplural.com>
Homepage: https://prismplural.com
Installed-Size: $installed_size
Depends: libc6, libstdc++6, libgtk-3-0, libglib2.0-0, libsecret-1-0, libsqlite3-0, libasound2
Description: Plural system management with end-to-end encrypted sync
 Prism helps plural systems track fronting, chat internally, build habits,
 run polls, keep shared notes and member profiles, and sync across devices
 with end-to-end encryption.
CONTROL

mkdir -p "$dist"
deb="$dist/Prism-${version}-linux-amd64.deb"
dpkg-deb --build --root-owner-group "$pkgroot" "$deb"
(cd "$dist" && sha256sum "$(basename "$deb")" > "$(basename "$deb").sha256")
dpkg-deb --info "$deb"
dpkg-deb --contents "$deb" | sed -n '1,80p'
