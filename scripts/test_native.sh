#!/usr/bin/env bash
# Required native lane for the resolved prism-sync revision and app codec.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$root"
for tool in flutter cargo git jq; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing native-lane prerequisite: $tool" >&2
    exit 2
  }
done

[[ -f .dart_tool/package_config.json ]] || {
  echo 'Run flutter pub get before the native lane.' >&2
  exit 2
}

package_checkout() {
  local package_name=$1 root_uri package_path
  root_uri=$(jq -er --arg name "$package_name" \
    '.packages[] | select(.name == $name) | .rootUri' \
    .dart_tool/package_config.json) || {
      echo "Package not resolved: $package_name" >&2
      exit 2
    }
  [[ $root_uri != *%* ]] || {
    echo "Encoded package paths are unsupported: $root_uri" >&2
    exit 2
  }
  if [[ $root_uri == file://* ]]; then
    package_path=${root_uri#file://}
  else
    package_path="$root/.dart_tool/$root_uri"
  fi
  package_path=$(cd "$package_path" && pwd -P) || exit 2
  git -C "$package_path" rev-parse --show-toplevel 2>/dev/null || {
    echo "$package_name did not resolve inside a prism-sync Git checkout." >&2
    exit 2
  }
}

resolved_sync_dir=$(package_checkout prism_sync)
for package_name in prism_sync_drift prism_sync_flutter; do
  candidate=$(package_checkout "$package_name")
  [[ $candidate == "$resolved_sync_dir" ]] || {
    echo "Prism Sync packages resolve to different checkouts: $resolved_sync_dir and $candidate" >&2
    exit 2
  }
done
sync_dir=${PRISM_SYNC_DIR:-$resolved_sync_dir}
sync_dir=$(cd "$sync_dir" && pwd -P)
[[ $sync_dir == "$resolved_sync_dir" ]] || {
  echo "PRISM_SYNC_DIR does not match the checkout selected by flutter pub get: $resolved_sync_dir" >&2
  exit 2
}
results_dir=${PRISM_TEST_RESULTS_DIR:-test-results}
target_dir=${PRISM_NATIVE_TARGET_DIR:-$root/build/test-native-sync-target}
mkdir -p "$results_dir" "$target_dir"
mode=${PRISM_NATIVE_MODE:-broad}
case "$mode" in
  broad|required) ;;
  *) echo "Unsupported PRISM_NATIVE_MODE: $mode" >&2; exit 2 ;;
esac
if [[ $mode == required && -n ${PRISM_NATIVE_TEST_ARGS:-} ]]; then
  echo 'PRISM_NATIVE_TEST_ARGS is not supported in required mode.' >&2
  exit 2
fi
started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
started_epoch=$(date +%s)
finish() {
  status=$?
  finished_epoch=$(date +%s)
  printf 'lane=native\nstarted_at=%s\nfinished_at=%s\nduration_seconds=%s\nexit_status=%s\n' \
    "$started_at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$((finished_epoch - started_epoch))" "$status" \
    > "$results_dir/native-status.txt"
}
trap finish EXIT

lockfile_source=$(awk '
  /^  prism_sync:$/ { in_package=1; next }
  in_package && /^  [^ ]/ { exit }
  in_package && /source:/ { value=$0; sub(/.*source:[[:space:]]*/, "", value); gsub(/["[:space:]]/, "", value); print value; exit }
' pubspec.lock)
lockfile_sync_rev=$(awk '
  /^  prism_sync:$/ { in_package=1; next }
  in_package && /^  [^ ]/ { exit }
  in_package && /resolved-ref:/ { value=$0; sub(/.*resolved-ref:[[:space:]]*/, "", value); gsub(/["[:space:]]/, "", value); print value; exit }
' pubspec.lock)
case "$lockfile_source" in
  git)
    [[ -n $lockfile_sync_rev ]] || { echo 'Git prism_sync lock entry has no resolved revision.' >&2; exit 2; }
    if [[ -n ${PRISM_EXPECTED_SYNC_REV:-} && $PRISM_EXPECTED_SYNC_REV != "$lockfile_sync_rev" ]]; then
      echo "PRISM_EXPECTED_SYNC_REV conflicts with git lockfile revision: $lockfile_sync_rev" >&2
      exit 2
    fi
    expected_sync_rev=$lockfile_sync_rev
    ;;
  path)
    expected_sync_rev=${PRISM_EXPECTED_SYNC_REV:-}
    [[ -n $expected_sync_rev ]] || { echo 'Set PRISM_EXPECTED_SYNC_REV for a prism_sync path override.' >&2; exit 2; }
    ;;
  *)
    echo "Unsupported prism_sync lockfile source: ${lockfile_source:-missing}" >&2
    exit 2
    ;;
esac
actual_sync_rev=$(git -C "$sync_dir" rev-parse HEAD)
if [[ $actual_sync_rev != "$expected_sync_rev" ]]; then
  echo "prism-sync revision mismatch: lockfile=$expected_sync_rev checkout=$actual_sync_rev" >&2
  exit 2
fi
if [[ -n $(git -C "$sync_dir" status --porcelain --untracked-files=all) ]]; then
  echo "prism-sync checkout is dirty: $sync_dir" >&2
  exit 2
fi
ignored_non_target=$(git -C "$sync_dir" status --ignored --porcelain | sed '/^!! target\/$/d')
if [[ -n $ignored_non_target ]]; then
  echo "prism-sync checkout has ignored non-target files that can affect the build: $ignored_non_target" >&2
  exit 2
fi

export CARGO_TARGET_DIR="$target_dir"
(cd "$sync_dir" && cargo build --locked --release -p prism_sync_ffi)
(cd "$sync_dir" && cargo build --locked --release -p prism-sync-relay --example test_relay)
if [[ $mode == broad ]]; then
  (cd packages/prism_media_codec/rust && cargo test --locked)
fi

case "$(uname -s)" in
  Darwin) ffi_name=libprism_sync_ffi.dylib ;;
  Linux) ffi_name=libprism_sync_ffi.so ;;
  *) echo "The native lane is qualified only on macOS and Linux; host $(uname -s) is unqualified." >&2; exit 2 ;;
esac
ffi_lib="$target_dir/release/$ffi_name"
relay_bin="$target_dir/release/examples/test_relay"
[[ -f $ffi_lib && -x $relay_bin ]] || { echo 'Required native artifacts were not produced.' >&2; exit 2; }
ffi_lib=$(cd "$(dirname "$ffi_lib")" && pwd -P)/$(basename "$ffi_lib")
relay_bin=$(cd "$(dirname "$relay_bin")" && pwd -P)/$(basename "$relay_bin")
sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}
provenance="$results_dir/native-provenance.json"
dart tool/write_native_provenance.dart "$provenance" \
  "app_revision=$(git rev-parse HEAD)" \
  "app_dirty=$(if [[ -n $(git status --porcelain) ]]; then echo true; else echo false; fi)" \
  "lockfile_source=$lockfile_source" \
  "lockfile_sync_revision=$lockfile_sync_rev" \
  "sync_revision=$actual_sync_rev" \
  "sync_source=$sync_dir" \
  "rustc=$(rustc --version)" \
  "rust_target=$(rustc -vV | awk '/^host:/{print $2}')" \
  "ffi_library=$ffi_lib" \
  "ffi_sha256=$(sha256 "$ffi_lib")" \
  "relay_binary=$relay_bin" \
  "relay_sha256=$(sha256 "$relay_bin")"

native_test_args=(--exclude-tags=benchmark)
if [[ -n ${PRISM_NATIVE_TEST_ARGS:-} ]]; then
  case "$PRISM_NATIVE_TEST_ARGS" in
    --tags=benchmark)
      native_test_args=(--tags=benchmark)
      expected_suites=(
        test/e2e/add_member_perf_bench_test.dart
        test/e2e/sp_avatar_zip_sync_volume_e2e_test.dart
      )
      ;;
    *) echo "Unsupported PRISM_NATIVE_TEST_ARGS: $PRISM_NATIVE_TEST_ARGS" >&2; exit 2 ;;
  esac
fi

required_tests=(
  test/core/sync/front_delivery_boundary_review_test.dart
  test/e2e/front_sync_combined_e2e_test.dart
  test/e2e/pk_service_peer_e2e_test.dart
  test/e2e/pk_upgrade_replay_e2e_test.dart
)
if [[ -z ${PRISM_NATIVE_TEST_ARGS:-} ]]; then
  expected_suites=("${required_tests[@]}")
fi
for test_file in "${expected_suites[@]}"; do
  [[ -f $test_file ]] || {
    echo "Required native test is missing: $test_file" >&2
    exit 2
  }
done
if [[ $mode == required ]]; then
  test_paths=("${required_tests[@]}")
else
  test_paths=(test/e2e test/core/sync/front_delivery_boundary_review_test.dart)
fi
native_report=${PRISM_NATIVE_TEST_REPORT:-$results_dir/native-tests.json}
mkdir -p "$(dirname "$native_report")"

env -u PK_TOKEN -u PK_TEST_TOKEN -u PLURALKIT_TOKEN -u PRISM_LIVE_TEST_TOKEN -u PRISM_ALLOW_LIVE_TESTS \
PRISM_REQUIRE_NATIVE_ASSETS=1 PRISM_ENABLE_NATIVE_E2E=1 \
PRISM_EXPECTED_SYNC_REV="$expected_sync_rev" PRISM_NATIVE_PROVENANCE="$provenance" \
PRISM_SYNC_FFI_LIB="$ffi_lib" PRISM_SYNC_RELAY_BIN="$relay_bin" \
  flutter test "${test_paths[@]}" "${native_test_args[@]}" \
    --file-reporter "json:$native_report" \
    | tee "$results_dir/native-tests.log"
completed=$(scripts/audit_required_native_report.sh \
  "$native_report" "$root" "${expected_suites[@]}")
printf 'Native %s suites passed at prism-sync %s (%s successful test cases).\n' \
  "$mode" "$actual_sync_rev" "$completed"

if [[ $mode == broad && -z ${PRISM_NATIVE_TEST_ARGS:-} ]]; then
  # The full 5,000-avatar workload belongs to native-benchmark.
  env -u PK_TOKEN -u PK_TEST_TOKEN -u PLURALKIT_TOKEN -u PRISM_LIVE_TEST_TOKEN -u PRISM_ALLOW_LIVE_TESTS \
  SP_AVATAR_SYNC_E2E_COUNT=3 PRISM_REQUIRE_NATIVE_ASSETS=1 PRISM_ENABLE_NATIVE_E2E=1 \
  PRISM_EXPECTED_SYNC_REV="$expected_sync_rev" PRISM_NATIVE_PROVENANCE="$provenance" \
  PRISM_SYNC_FFI_LIB="$ffi_lib" PRISM_SYNC_RELAY_BIN="$relay_bin" \
    flutter test test/e2e/sp_avatar_zip_sync_volume_e2e_test.dart --tags=benchmark \
      --file-reporter "json:$results_dir/native-sp-avatar-smoke.json" \
      | tee "$results_dir/native-sp-avatar-smoke.log"
fi
