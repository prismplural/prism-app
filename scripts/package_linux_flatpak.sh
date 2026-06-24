#!/usr/bin/env bash
set -euo pipefail

app_id=com.prismplural.prism
branch=${FLATPAK_BRANCH:-stable}
arch=${FLATPAK_ARCH:-x86_64}
case "$arch" in
  x86_64) artifact_arch=linux-x64 ;;
  aarch64) artifact_arch=linux-arm64 ;;
  *) artifact_arch="linux-$arch" ;;
esac
runtime=${FLATPAK_RUNTIME:-org.freedesktop.Platform}
sdk=${FLATPAK_SDK:-org.freedesktop.Sdk}
runtime_version=${FLATPAK_RUNTIME_VERSION:-25.08}
collection_id=${FLATPAK_COLLECTION_ID:-com.prismplural.PrismRepo}
repo_url=${FLATPAK_REPO_URL:-https://prismplural.com/flatpak/repo/}
appstream_media_baseurl=${FLATPAK_APPSTREAM_MEDIA_BASEURL:-https://prismplural.com/flatpak/media/}
runtime_repo_url=${FLATPAK_RUNTIME_REPO_URL:-https://dl.flathub.org/repo/flathub.flatpakrepo}
gpg_key=${FLATPAK_GPG_KEY_ID:-${FLATPAK_GPG_KEY:-}}
gpg_homedir=${FLATPAK_GPG_HOMEDIR:-}
gpg_key_file=${FLATPAK_GPG_KEY_FILE:-}
require_gpg=${FLATPAK_REQUIRE_GPG:-false}

version=$(grep '^version:' pubspec.yaml | awk '{print $2}')
bundle=${1:-build/linux/x64/release/bundle}
dist=${2:-dist}
workdir=$(mktemp -d)
builddir="$workdir/build"
repo="$workdir/repo"

cleanup() {
  rm -rf "$workdir"
}
trap cleanup EXIT

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

sha256_artifact() {
  local file=$1
  (cd "$(dirname "$file")" && sha256sum "$(basename "$file")" > "$(basename "$file").sha256")
}

require_command flatpak
require_command appstreamcli
require_command base64
require_command tar
require_command sha256sum

if [[ ! -d "$bundle" ]]; then
  echo "Linux release bundle not found: $bundle" >&2
  exit 1
fi

mkdir -p "$dist"
dist=$(cd "$dist" && pwd)

if [[ -n "$gpg_key" && -z "$gpg_key_file" ]]; then
  require_command gpg
  gpg_key_file="$workdir/prism-flatpak.gpg"
  gpg_args=(--batch)
  if [[ -n "$gpg_homedir" ]]; then
    gpg_args+=(--homedir "$gpg_homedir")
  fi
  gpg "${gpg_args[@]}" --export "$gpg_key" > "$gpg_key_file"
fi

if [[ -n "$gpg_key_file" && ! -f "$gpg_key_file" ]]; then
  echo "Flatpak GPG public key file not found: $gpg_key_file" >&2
  exit 1
fi
signed_repo=false
if [[ -n "$gpg_key" && -n "$gpg_key_file" ]]; then
  signed_repo=true
fi
if [[ "$signed_repo" != true &&
  ( "$require_gpg" == "1" || "$require_gpg" == "true" || "$require_gpg" == "yes" ) ]]; then
  echo "Flatpak signing is required for this build; configure FLATPAK_GPG_KEY_ID and FLATPAK_GPG_KEY_FILE." >&2
  exit 1
fi

flatpak build-init "$builddir" "$app_id" "$sdk" "$runtime" "$runtime_version"

mkdir -p \
  "$builddir/files/bin" \
  "$builddir/files/lib/prism" \
  "$builddir/files/share/applications" \
  "$builddir/files/share/metainfo" \
  "$builddir/files/share/icons"

# Copy the Flutter bundle without the portable tarball wrapper/metadata.
tar -C "$bundle" \
  --exclude='./prism' \
  --exclude='./share' \
  -cf - . | tar -C "$builddir/files/lib/prism" -xf -

cat > "$builddir/files/bin/prism" <<'WRAPPER'
#!/bin/sh
export GDK_BACKEND=x11
export LD_LIBRARY_PATH="/app/lib/prism/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
if [ -n "${XDG_DATA_DIRS:-}" ]; then
  export XDG_DATA_DIRS="/app/share:$XDG_DATA_DIRS"
else
  export XDG_DATA_DIRS="/app/share:/usr/share"
fi
exec /app/lib/prism/prism_plurality "$@"
WRAPPER
chmod 0755 "$builddir/files/bin/prism"

cp packaging/linux/com.prismplural.prism.desktop "$builddir/files/share/applications/"
cp packaging/linux/com.prismplural.prism.metainfo.xml "$builddir/files/share/metainfo/"
cp -R packaging/linux/icons/hicolor "$builddir/files/share/icons/"
# flatpak build-finish rejects exported icons above 512x512.
rm -rf "$builddir/files/share/icons/hicolor/1024x1024"

find "$builddir/files/share" -type d -exec chmod 0755 {} +
find "$builddir/files/share" -type f -exec chmod 0644 {} +
find "$builddir/files/lib/prism" -type d -exec chmod 0755 {} +
find "$builddir/files/lib/prism" -type f -exec chmod 0644 {} +
chmod 0755 "$builddir/files/lib/prism/prism_plurality"
find "$builddir/files/lib/prism/lib" -type f -name '*.so*' -exec chmod 0755 {} + 2>/dev/null || true

appstreamcli compose \
  --no-net \
  --prefix=/ \
  --origin="$app_id" \
  --media-baseurl="$appstream_media_baseurl" \
  --media-dir="$builddir/files/share/app-info/media" \
  --result-root="$builddir/files" \
  --data-dir="$builddir/files/share/app-info/xmls" \
  --icons-dir="$builddir/files/share/app-info/icons/flatpak" \
  --components="$app_id" \
  "$builddir/files"

flatpak build-finish "$builddir" \
  --command=prism \
  --share=ipc \
  --share=network \
  --socket=x11 \
  --socket=pulseaudio \
  --device=all \
  --talk-name=org.freedesktop.secrets \
  --talk-name=org.freedesktop.Notifications \
  --env=GDK_BACKEND=x11 \
  --env=LD_LIBRARY_PATH=/app/lib/prism/lib

export_args=(
  --arch="$arch"
  --collection-id="$collection_id"
  --subject="Prism $version"
  --update-appstream
)
update_args=(
  --generate-static-deltas
  --collection-id="$collection_id"
  --deploy-collection-id
  --title=Prism
  --comment="Prism desktop releases"
  --description="Prism Flatpak repository"
  --homepage=https://prismplural.com
)
if [[ "$signed_repo" == true ]]; then
  export_args+=(--gpg-sign="$gpg_key")
  update_args+=(--gpg-sign="$gpg_key" --gpg-import="$gpg_key_file")
  if [[ -n "$gpg_homedir" ]]; then
    export_args+=(--gpg-homedir="$gpg_homedir")
    update_args+=(--gpg-homedir="$gpg_homedir")
  fi
else
  echo "Flatpak GPG key not configured; producing unsigned repo artifacts for local testing." >&2
fi

flatpak build-export "${export_args[@]}" "$repo" "$builddir" "$branch"
flatpak build-update-repo "${update_args[@]}" "$repo"

flatpak_file="$dist/Prism-${version}-${artifact_arch}.flatpak"
flatpakrepo_file="$dist/prism.flatpakrepo"
flatpakref_file="$dist/com.prismplural.prism.flatpakref"
repo_archive="$dist/Prism-${version}-${artifact_arch}-flatpak-repo.tar.gz"

bundle_args=(
  --arch="$arch"
  --runtime-repo="$runtime_repo_url"
  --repo-url="$repo_url"
)
if [[ "$signed_repo" == true ]]; then
  bundle_args+=(--gpg-keys="$gpg_key_file")
fi

flatpak build-bundle "${bundle_args[@]}" "$repo" "$flatpak_file" "$app_id" "$branch"

gpg_key_b64=
if [[ "$signed_repo" == true ]]; then
  gpg_key_b64=$(base64 < "$gpg_key_file" | tr -d '\n')
fi

cat > "$flatpakrepo_file" <<REPO
[Flatpak Repo]
Title=Prism
Url=$repo_url
Homepage=https://prismplural.com
Comment=Prism desktop releases
Description=Prism Flatpak repository
DefaultBranch=$branch
REPO
if [[ -n "$gpg_key_b64" ]]; then
  printf 'GPGKey=%s\n' "$gpg_key_b64" >> "$flatpakrepo_file"
fi

cat > "$flatpakref_file" <<REF
[Flatpak Ref]
Name=$app_id
Branch=$branch
Title=Prism
Url=$repo_url
RuntimeRepo=$runtime_repo_url
IsRuntime=false
SuggestRemoteName=prism
REF
if [[ -n "$gpg_key_b64" ]]; then
  printf 'GPGKey=%s\n' "$gpg_key_b64" >> "$flatpakref_file"
fi

repo_staging="$workdir/repo-staging"
mkdir -p "$repo_staging"
cp -a "$repo" "$repo_staging/repo"
cp "$flatpakrepo_file" "$repo_staging/"
cp "$flatpakref_file" "$repo_staging/"
if [[ "$signed_repo" == true ]]; then
  cp "$gpg_key_file" "$repo_staging/prism-flatpak.gpg"
fi
tar -C "$repo_staging" -czf "$repo_archive" .

sha256_artifact "$flatpak_file"
sha256_artifact "$flatpakrepo_file"
sha256_artifact "$flatpakref_file"
sha256_artifact "$repo_archive"

find "$dist" -maxdepth 1 -mindepth 1 | sort | sed -n '1,120p'
