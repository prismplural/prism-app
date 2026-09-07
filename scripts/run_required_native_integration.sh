#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'required native integration gate: %s\n' "$*" >&2
  exit 1
}

for tool in flutter cargo git jq; do
  command -v "$tool" >/dev/null 2>&1 || fail "missing prerequisite: $tool"
done

app_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$app_root"

flutter pub get
[[ -f .dart_tool/package_config.json ]] || fail 'flutter pub get did not create package_config.json'

package_checkout() {
  local package_name=$1 root_uri package_path
  root_uri=$(jq -er --arg name "$package_name" \
    '.packages[] | select(.name == $name) | .rootUri' \
    .dart_tool/package_config.json) || fail "package not resolved: $package_name"
  [[ "$root_uri" != *%* ]] || fail "unsupported encoded package path for $package_name: $root_uri"
  if [[ "$root_uri" == file://* ]]; then
    package_path=${root_uri#file://}
  else
    package_path="$app_root/.dart_tool/$root_uri"
  fi
  package_path=$(cd "$package_path" && pwd -P) || fail "package root does not exist: $package_path"
  git -C "$package_path" rev-parse --show-toplevel 2>/dev/null || \
    fail "$package_name did not resolve inside a prism-sync Git checkout"
}

sync_checkout=$(package_checkout prism_sync)
for package_name in prism_sync_drift prism_sync_flutter; do
  candidate=$(package_checkout "$package_name")
  [[ "$candidate" == "$sync_checkout" ]] || \
    fail "prism_sync packages resolve to different checkouts: $sync_checkout and $candidate"
done

sync_ref=$(git -C "$sync_checkout" rev-parse HEAD)
gate_target=$(mktemp -d "${TMPDIR:-/tmp}/prism-native-target.XXXXXX")
trap 'rm -rf "$gate_target"' EXIT
report=${PRISM_NATIVE_GATE_REPORT:-build/reports/required-native-integration.jsonl}
PRISM_SYNC_DIR="$sync_checkout" \
PRISM_EXPECTED_SYNC_REV="$sync_ref" \
PRISM_NATIVE_MODE=required \
PRISM_NATIVE_TARGET_DIR="$gate_target" \
PRISM_NATIVE_TEST_REPORT="$report" \
PRISM_TEST_RESULTS_DIR="$(dirname "$report")" \
  scripts/test_native.sh
