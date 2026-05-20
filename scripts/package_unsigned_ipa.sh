#!/usr/bin/env bash
set -euo pipefail

app_path="${APP_PATH:-build/ios/iphoneos/Runner.app}"
output_path="${1:-build/ios/Prism-ios-unsigned.ipa}"

if [ ! -d "$app_path" ]; then
  echo "Runner.app not found at $app_path" >&2
  echo "Run: flutter build ios --release --no-codesign" >&2
  exit 1
fi

output_dir="$(dirname "$output_path")"
output_file="$(basename "$output_path")"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd -P)"

staging_dir="build/ios/unsigned_ipa"
rm -rf "$staging_dir"
mkdir -p "$staging_dir/Payload"
cp -R "$app_path" "$staging_dir/Payload/Runner.app"

# These should be absent after --no-codesign, but remove stale signing material
# defensively if a local incremental build left it behind.
find "$staging_dir/Payload/Runner.app" -name _CodeSignature -type d -prune -exec rm -rf {} +
rm -f "$staging_dir/Payload/Runner.app/embedded.mobileprovision"

(
  cd "$staging_dir"
  zip -qry "$output_dir/$output_file" Payload
)

echo "$output_dir/$output_file"
