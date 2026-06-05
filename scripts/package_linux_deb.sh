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

# Derive deps from the shipped ELFs instead of hardcoding them. The old list
# hardcoded libjsoncpp25, which nothing links (flutter_secure_storage_linux has
# been header-only JSON since 1.2.0) and which is absent on distros newer than
# the build runner (Ubuntu 25.x / Debian trixie ship libjsoncpp26), so apt
# refused the package there.
shlibdeps_dir=$(mktemp -d)
mkdir -p "$shlibdeps_dir/debian"
# dpkg-shlibdeps insists on a debian/control even with -O; give it a stub.
cat > "$shlibdeps_dir/debian/control" <<'CTRL'
Source: prism
Package: prism
Architecture: amd64
CTRL

# Scan the plugins too, not just the runner — they're what link
# libsecret/libsqlite3/libasound2.
mapfile -t shipped_elfs < <(
  find "$pkgroot/usr/lib/prism" -type f \
    \( -name '*.so' -o -name '*.so.*' -o -name 'prism_plurality' \) | sort
)
if [[ ${#shipped_elfs[@]} -eq 0 ]]; then
  echo "No ELF binaries found under $pkgroot/usr/lib/prism" >&2
  exit 1
fi

# -l resolves our bundled libs against each other; --ignore-missing-info skips
# them (no packaged shlibs) so only system libs land in Depends.
( cd "$shlibdeps_dir" \
  && dpkg-shlibdeps -l"$pkgroot/usr/lib/prism/lib" --ignore-missing-info -O \
       "${shipped_elfs[@]}" ) > "$shlibdeps_dir/out.txt"

depends=$(sed -n 's/^shlibs:Depends=//p' "$shlibdeps_dir/out.txt")
rm -rf "$shlibdeps_dir"
if [[ -z "$depends" ]]; then
  echo "dpkg-shlibdeps produced an empty Depends — refusing to build" >&2
  exit 1
fi
echo "Derived Depends: $depends"

cat > "$pkgroot/DEBIAN/control" <<CONTROL
Package: prism
Version: $version
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Prism Contributors <maintainers@prismplural.com>
Homepage: https://prismplural.com
Installed-Size: $installed_size
Depends: $depends
Description: Plural system management with end-to-end encrypted sync
 Prism helps plural systems track fronting, chat internally, build habits,
 run polls, keep shared notes and member profiles, and sync across devices
 with end-to-end encryption.
CONTROL

mkdir -p "$dist"
deb="$dist/Prism-${version}-linux-amd64.deb"
dpkg-deb --build --root-owner-group "$pkgroot" "$deb"

# Fail closed: jsoncpp must never come back, and a dep we know is linked (GTK)
# must be present — its absence means the derivation broke.
packaged_depends=$(dpkg-deb --field "$deb" Depends)
echo "Packaged Depends: $packaged_depends"
case "$packaged_depends" in
  *jsoncpp*)
    echo "ERROR: jsoncpp is back in Depends, but nothing in the bundle links it." >&2
    exit 1 ;;
esac
case "$packaged_depends" in
  *libgtk-3-0*) : ;;
  *)
    echo "ERROR: Depends is missing libgtk-3-0 — shlibdeps derivation looks broken." >&2
    exit 1 ;;
esac

(cd "$dist" && sha256sum "$(basename "$deb")" > "$(basename "$deb").sha256")
dpkg-deb --info "$deb"
dpkg-deb --contents "$deb" | sed -n '1,80p'
