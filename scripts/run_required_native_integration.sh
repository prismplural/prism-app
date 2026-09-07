#!/usr/bin/env bash
set -euo pipefail

readonly REQUIRED_TESTS=(
  test/core/sync/front_delivery_boundary_review_test.dart
  test/e2e/front_sync_combined_e2e_test.dart
  test/e2e/pk_service_peer_e2e_test.dart
  test/e2e/pk_upgrade_replay_e2e_test.dart
)

fail() {
  printf 'required native integration gate: %s\n' "$*" >&2
  exit 1
}

for tool in flutter cargo git jq; do
  command -v "$tool" >/dev/null 2>&1 || fail "missing prerequisite: $tool"
done

app_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$app_root"

for test_file in "${REQUIRED_TESTS[@]}"; do
  [[ -f "$test_file" ]] || fail "required test is missing: $test_file"
done

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
[[ -z "$(git -C "$sync_checkout" status --porcelain --untracked-files=all)" ]] || \
  fail "resolved prism-sync checkout has source changes; commit or remove them so provenance is exact: $sync_checkout"
ignored_non_target=$(git -C "$sync_checkout" status --ignored --porcelain | sed '/^!! target\/$/d')
[[ -z "$ignored_non_target" ]] || \
  fail "resolved prism-sync checkout has ignored non-target files that can affect the build: $ignored_non_target"
printf 'PRISM_SYNC_GATE_SOURCE=%s\nPRISM_SYNC_GATE_REF=%s\n' "$sync_checkout" "$sync_ref"

gate_target=$(mktemp -d "${TMPDIR:-/tmp}/prism-native-target.XXXXXX")
trap 'rm -rf "$gate_target"' EXIT
printf 'PRISM_SYNC_GATE_TARGET=%s\n' "$gate_target"
cargo build --locked --release --target-dir "$gate_target" \
  --manifest-path "$sync_checkout/Cargo.toml" -p prism_sync_ffi
cargo build --locked --release --target-dir "$gate_target" \
  --manifest-path "$sync_checkout/Cargo.toml" \
  -p prism-sync-relay --example test_relay

case "$(uname -s)" in
  Darwin) ffi_name=libprism_sync_ffi.dylib ;;
  Linux) ffi_name=libprism_sync_ffi.so ;;
  MINGW*|MSYS*|CYGWIN*) ffi_name=prism_sync_ffi.dll ;;
  *) fail "unsupported host: $(uname -s)" ;;
esac
relay_name=test_relay
[[ "$ffi_name" == *.dll ]] && relay_name=test_relay.exe
export PRISM_SYNC_FFI_LIB="$gate_target/release/$ffi_name"
export PRISM_SYNC_TEST_RELAY="$gate_target/release/examples/$relay_name"
export PRISM_REQUIRED_NATIVE_INTEGRATION=1
[[ -f "$PRISM_SYNC_FFI_LIB" ]] || fail "FFI build did not produce $PRISM_SYNC_FFI_LIB"
[[ -x "$PRISM_SYNC_TEST_RELAY" ]] || fail "relay build did not produce executable $PRISM_SYNC_TEST_RELAY"

report=${PRISM_NATIVE_GATE_REPORT:-build/reports/required-native-integration.jsonl}
mkdir -p "$(dirname "$report")"
: > "$report"
printf 'PRISM_NATIVE_GATE_REPORT=%s\n' "$report"
set +e
flutter test --no-pub --reporter=json "${REQUIRED_TESTS[@]}" | tee "$report"
test_status=${PIPESTATUS[0]}
set -e
(( test_status == 0 )) || fail "required Flutter tests failed with exit $test_status"

completed=$(scripts/audit_required_native_report.sh "$report" "$app_root" "${REQUIRED_TESTS[@]}") || \
  fail "required test protocol audit failed; inspect $report"
printf 'Required native integration gate passed at prism-sync %s (%s successful test cases).\n' \
  "$sync_ref" "$completed"
