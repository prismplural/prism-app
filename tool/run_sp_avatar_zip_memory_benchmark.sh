#!/usr/bin/env bash
set -euo pipefail

package_id="com.prismplural.prism"
device=""
expected_avd_hash=""
snapshot_id=""
output_root="build/sp-avatar-zip-memory/$(date -u +%Y%m%dT%H%M%SZ)"
confirmed=false
allow_supplementary_2gb_profile=false
seed=20260714

usage() {
  cat <<'EOF'
Strict-memory Android gate for Simply Plural avatar ZIP imports.

This script never launches, wipes, snapshots, or stops an emulator. It does
install a profile integration-test build on the explicitly selected dedicated
AVD, so confirmation is mandatory. Run `flutter pub get` first, then confirm
the worktree is clean; the profile driver intentionally uses `--no-pub` so it
cannot rewrite the lockfile after the evidence preflight.

Usage:
  tool/run_sp_avatar_zip_memory_benchmark.sh \
    --device emulator-PORT \
    --avd-config-sha256 SHA256 \
    --snapshot-id CLEAN_SNAPSHOT_ID \
    --confirm-dedicated-clean-avd [--out DIR] \
    [--allow-supplementary-2gb-profile]

Required pinned profile:
  name prism-lowmem-api35; API 35 Google APIs arm64-v8a;
  RAM 1536 MiB; VM heap 256 MiB; animation scales 1.0.

--allow-supplementary-2gb-profile accepts the known emulator-enforced runtime
of approximately 2 GiB RAM and 512 MiB VM heap. Its output is explicitly
supplementary evidence and never satisfies the strict 1.5 GiB / 256 MiB gate.
EOF
}

while (($#)); do
  case "$1" in
    --device) device="$2"; shift 2 ;;
    --avd-config-sha256) expected_avd_hash="$2"; shift 2 ;;
    --snapshot-id) snapshot_id="$2"; shift 2 ;;
    --out) output_root="$2"; shift 2 ;;
    --confirm-dedicated-clean-avd) confirmed=true; shift ;;
    --allow-supplementary-2gb-profile) allow_supplementary_2gb_profile=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 64 ;;
  esac
done

if [[ -z "$device" || -z "$expected_avd_hash" || -z "$snapshot_id" ]]; then
  printf '%s\n' '--device, --avd-config-sha256, and --snapshot-id are required.' >&2
  exit 64
fi
if [[ "$confirmed" != true ]]; then
  printf '%s\n' \
    'Refusing to install on a device without --confirm-dedicated-clean-avd.' >&2
  exit 64
fi
if ! [[ "$expected_avd_hash" =~ ^[0-9a-fA-F]{64}$ ]]; then
  printf '%s\n' '--avd-config-sha256 must be 64 hexadecimal characters.' >&2
  exit 64
fi
expected_avd_hash="$(tr '[:upper:]' '[:lower:]' <<<"$expected_avd_hash" | tr -d '\n')"

for command in adb flutter dart python3 git shasum awk sed grep; do
  command -v "$command" >/dev/null || {
    printf 'Missing prerequisite: %s\n' "$command" >&2
    exit 69
  }
done

if [[ "$(git rev-parse --show-toplevel)" != "$(pwd)" ]]; then
  printf '%s\n' 'Run this script from the prism-app repository root.' >&2
  exit 64
fi
if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  printf '%s\n' 'Strict-memory evidence requires a clean committed worktree.' >&2
  exit 65
fi
if ! adb -s "$device" get-state 2>/dev/null | grep -qx device; then
  printf 'Android device is not ready: %s\n' "$device" >&2
  exit 69
fi

qemu="$(adb -s "$device" shell getprop ro.kernel.qemu | tr -d '\r')"
avd_name="$(adb -s "$device" shell getprop ro.boot.qemu.avd_name | tr -d '\r')"
sdk="$(adb -s "$device" shell getprop ro.build.version.sdk | tr -d '\r')"
abi="$(adb -s "$device" shell getprop ro.product.cpu.abi | tr -d '\r')"
heap_size="$(adb -s "$device" shell getprop dalvik.vm.heapsize | tr -d '\r')"
fingerprint="$(adb -s "$device" shell getprop ro.build.fingerprint | tr -d '\r')"
mem_total_kb="$(adb -s "$device" shell cat /proc/meminfo | awk '/^MemTotal:/ {print $2; exit}' | tr -d '\r')"
if [[ "$qemu" != 1 || "$avd_name" != prism-lowmem-api35 ]]; then
  printf 'Expected the dedicated prism-lowmem-api35 emulator, got %s.\n' "$avd_name" >&2
  exit 65
fi
if [[ "$sdk" != 35 || "$abi" != arm64-v8a ]]; then
  printf 'Pinned device mismatch: sdk=%s abi=%s\n' "$sdk" "$abi" >&2
  exit 65
fi

execution_classification="strict-1.5gb-256m"
release_gate_eligible=true
if [[ "$heap_size" != 256m ]]; then
  if [[ "$allow_supplementary_2gb_profile" != true || "$heap_size" != 512m ||
        ! "$mem_total_kb" =~ ^[0-9]+$ || "$mem_total_kb" -lt 1900000 ||
        "$mem_total_kb" -gt 2200000 ]]; then
    printf 'Pinned device mismatch: heap=%s observedMemTotalKiB=%s\n' \
      "$heap_size" "$mem_total_kb" >&2
    exit 65
  fi
  execution_classification="supplementary-2gb-512m"
  release_gate_eligible=false
  printf '%s\n' \
    'Running supplementary 2 GiB / 512 MiB evidence; strict 1.5 GiB / 256 MiB remains unpassed.' >&2
fi

avd_config="${ANDROID_AVD_HOME:-$HOME/.android/avd}/prism-lowmem-api35.avd/config.ini"
if [[ ! -f "$avd_config" ]]; then
  printf 'Pinned AVD config is unavailable: %s\n' "$avd_config" >&2
  exit 69
fi
actual_avd_hash="$(shasum -a 256 "$avd_config" | awk '{print $1}')"
if [[ "$actual_avd_hash" != "$expected_avd_hash" ]]; then
  printf 'AVD config digest mismatch: expected %s, got %s\n' \
    "$expected_avd_hash" "$actual_avd_hash" >&2
  exit 65
fi

config_value() {
  local key="$1"
  awk -F= -v key="$key" '
    {
      name=$1
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
    }
    name == key {
      value=$2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "$avd_config"
}

ram_mb="$(config_value hw.ramSize)"
config_heap_mb="$(config_value vm.heapSize)"
image_path="$(config_value image.sysdir.1)"
if [[ ( "$ram_mb" != 1536 && "$ram_mb" != 1536M ) ||
      ( "$config_heap_mb" != 256 && "$config_heap_mb" != 256M ) ]]; then
  printf 'Pinned AVD config mismatch: RAM=%s heap=%s\n' "$ram_mb" "$config_heap_mb" >&2
  exit 65
fi
if [[ "$image_path" != *android-35* || "$image_path" != *google_apis* || "$image_path" != *arm64-v8a* ]]; then
  printf 'Pinned AVD system image mismatch: %s\n' "$image_path" >&2
  exit 65
fi
for animation_key in window_animation_scale transition_animation_scale animator_duration_scale; do
  animation_value="$(adb -s "$device" shell settings get global "$animation_key" | tr -d '\r')"
  # Android reports an unset global as `null`; that means the platform's
  # default 1.0 scale is in effect, which is the required non-disabled state.
  if [[ "$animation_value" != 1 &&
        "$animation_value" != 1.0 &&
        "$animation_value" != null ]]; then
    printf 'Animation scale %s must remain at 1.0; got %s\n' \
      "$animation_key" "$animation_value" >&2
    exit 65
  fi
done

mkdir -p "$output_root"
git_sha="$(git rev-parse HEAD)"
git_diff_sha="$(git diff --binary | shasum -a 256 | awk '{print $1}')"
flutter_version="$(flutter --version --machine)"
dart_version="$(dart --version 2>&1)"
adb_version="$(adb version)"

python3 - "$output_root/provenance.json" "$git_sha" "$git_diff_sha" \
  "$device" "$avd_name" "$actual_avd_hash" "$snapshot_id" "$sdk" "$abi" \
  "$heap_size" "$ram_mb" "$mem_total_kb" "$fingerprint" "$seed" \
  "$flutter_version" "$dart_version" "$adb_version" \
  "$execution_classification" "$release_gate_eligible" <<'PY'
import json
import sys

(
    output, git_sha, git_diff_sha, device, avd_name, avd_hash, snapshot_id,
    sdk, abi, heap_size, ram_mb, mem_total_kb, fingerprint, seed,
    flutter_version, dart_version, adb_version, execution_classification,
    release_gate_eligible,
) = sys.argv[1:]
value = {
    "schemaVersion": 1,
    "gitSha": git_sha,
    "workingTreeDiffSha256": git_diff_sha,
    "fixtureSeed": int(seed),
    "device": {
        "serial": device,
        "avdName": avd_name,
        "avdConfigSha256": avd_hash,
        "cleanSnapshotAttestation": snapshot_id,
        "sdk": int(sdk),
        "abi": abi,
        "vmHeap": heap_size,
        "configuredRamMiB": int(ram_mb.removesuffix("M")),
        "observedMemTotalKiB": int(mem_total_kb),
        "fingerprint": fingerprint,
        "animations": "default-1.0",
    },
    "tools": {
        "flutter": json.loads(flutter_version),
        "dart": dart_version,
        "adb": adb_version,
    },
    "safety": {
        "runnerLaunchedDevice": False,
        "runnerWipedDevice": False,
        "dedicatedCleanAvdConfirmed": True,
    },
    "execution": {
        "classification": execution_classification,
        "releaseGateEligible": release_gate_eligible == "true",
    },
}
with open(output, "x", encoding="utf-8") as handle:
    json.dump(value, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

current_phase() {
  local log="$1" marker
  marker="$(grep -o '"memoryPhase":"[^"]*"' "$log" 2>/dev/null | tail -1 || true)"
  if [[ -z "$marker" ]]; then
    printf '%s\n' bootstrap
  else
    sed -E 's/.*"memoryPhase":"([^"]*)".*/\1/' <<<"$marker"
  fi
}

sample_case() {
  local run_root="$1" flutter_log="$2" stop_file="$3"
  local samples="$run_root/memory-samples.csv" raw_root="$run_root/meminfo-raw"
  local start_ms now_ms elapsed_ms phase pid dumpsys pss rss sequence=0
  mkdir -p "$raw_root"
  printf '%s\n' 'elapsed_ms,phase,total_pss_kb,rss_kb' > "$samples"
  start_ms="$(python3 -c 'import time; print(time.monotonic_ns() // 1000000)')"
  while [[ ! -e "$stop_file" ]]; do
    # The sampler starts before Flutter installs and launches the profile app.
    # `pidof` therefore legitimately exits non-zero for its first few polls;
    # absorb that expected state so `set -e -o pipefail` cannot kill sampling.
    pid="$({ adb -s "$device" shell pidof "$package_id" 2>/dev/null || true; } | tr -d '\r' | awk '{print $1}')"
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
      sequence=$((sequence + 1))
      dumpsys="$raw_root/$(printf '%06d' "$sequence").txt"
      adb -s "$device" shell dumpsys meminfo "$package_id" > "$dumpsys" 2>/dev/null || true
      pss="$(awk '
        /TOTAL PSS:/ {print $3; found=1; exit}
        $1 == "TOTAL" && $2 ~ /^[0-9]+$/ {candidate=$2}
        END {if (!found && candidate != "") print candidate}
      ' "$dumpsys")"
      rss="$({ adb -s "$device" shell cat "/proc/$pid/status" 2>/dev/null || true; } | awk '/^VmRSS:/ {print $2; exit}' | tr -d '\r')"
      if [[ "$pss" =~ ^[1-9][0-9]*$ && "$rss" =~ ^[1-9][0-9]*$ ]]; then
        now_ms="$(python3 -c 'import time; print(time.monotonic_ns() // 1000000)')"
        elapsed_ms=$((now_ms - start_ms))
        phase="$(current_phase "$flutter_log")"
        printf '%s,%s,%s,%s\n' "$elapsed_ms" "$phase" "$pss" "$rss" >> "$samples"
      fi
    fi
    sleep 1
  done
}

run_case() {
  local case_name="$1" profile="$2" count="$3" repetitions="$4" baseline="${5:-}" assess="${6:-true}"
  local run_root="$output_root/$case_name"
  local flutter_log="$run_root/flutter-test.log" logcat="$run_root/logcat.txt"
  local combined_log="$run_root/combined.log" stop_file="$run_root/stop-sampler"
  local sampler_pid logcat_pid flutter_status report_status
  mkdir -p "$run_root"
  rm -f "$stop_file"

  adb -s "$device" logcat -c
  adb -s "$device" logcat -v threadtime > "$logcat" 2>&1 &
  logcat_pid=$!
  : > "$flutter_log"
  sample_case "$run_root" "$flutter_log" "$stop_file" &
  sampler_pid=$!

  set +e
  flutter drive --profile --no-pub \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/sp_avatar_zip_memory_benchmark_test.dart \
    -d "$device" \
    --dart-define="SP_AVATAR_ZIP_BENCHMARK_CASE=$case_name" \
    --dart-define="SP_AVATAR_ZIP_BENCHMARK_PROFILE=$profile" \
    --dart-define="SP_AVATAR_ZIP_BENCHMARK_COUNT=$count" \
    --dart-define="SP_AVATAR_ZIP_BENCHMARK_REPETITIONS=$repetitions" \
    --dart-define="SP_AVATAR_ZIP_BENCHMARK_SEED=$seed" \
    --dart-define="SP_AVATAR_ZIP_APP_COMMIT=$git_sha" \
    --dart-define=SP_AVATAR_ZIP_BEFORE_IDLE_SECONDS=10 \
    --dart-define=SP_AVATAR_ZIP_AFTER_IDLE_SECONDS=30 \
    --dart-define=SP_AVATAR_ZIP_CLEANUP_IDLE_SECONDS=10 \
    2>&1 | tee "$flutter_log"
  flutter_status=${PIPESTATUS[0]}
  set -e

  touch "$stop_file"
  wait "$sampler_pid" || true
  kill "$logcat_pid" 2>/dev/null || true
  wait "$logcat_pid" 2>/dev/null || true
  cp "$flutter_log" "$combined_log"
  printf '\n--- Android logcat ---\n' >> "$combined_log"
  sed -n '/com\.prismplural\.prism\|OutOfMemoryError\|lowmemorykiller\|ANR in/p' \
    "$logcat" >> "$combined_log"

  if ((flutter_status != 0)); then
    printf 'Flutter integration test failed for %s with status %s.\n' \
      "$case_name" "$flutter_status" >&2
    return "$flutter_status"
  fi
  if [[ "$assess" != true ]]; then
    return 0
  fi

  report_args=(
    --samples "$run_root/memory-samples.csv"
    --log "$combined_log"
    --out "$run_root/summary.json"
  )
  if [[ -n "$baseline" ]]; then
    report_args+=(--scale-baseline "$baseline")
  fi
  set +e
  dart run tool/sp_avatar_zip_memory_report.dart "${report_args[@]}"
  report_status=$?
  set -e
  if ((report_status != 0)); then
    printf 'Strict-memory acceptance failed for %s.\n' "$case_name" >&2
    return "$report_status"
  fi
}

run_scale_fixture() {
  local count="$1" run baseline=""
  # Warm-ups prime profile compilation and image codecs but are intentionally
  # excluded from the evidence set; only the three measured repetitions gate.
  run_case "scale-$count-warmup" scale-small "$count" 1 "" false
  for run in 1 2 3; do
    if [[ "$count" != 500 ]]; then
      baseline="$output_root/scale-500-run-$run/summary.json"
    fi
    run_case "scale-$count-run-$run" scale-small "$count" 1 "$baseline"
  done
}

run_scale_fixture 500
run_scale_fixture 2000
run_scale_fixture 5000
run_case near-pixel-limit near-pixel-limit 1 1
run_case repeat-5000 scale-small 5000 3

python3 - "$output_root/gate-summary.json" "$output_root" <<'PY'
import json
import os
import sys

output, root = sys.argv[1:]
cases = {}
measured_scales = [
    f"scale-{count}-run-{run}"
    for count in (500, 2000, 5000)
    for run in (1, 2, 3)
]
for name in (*measured_scales, "near-pixel-limit", "repeat-5000"):
    path = os.path.join(root, name, "summary.json")
    with open(path, encoding="utf-8") as handle:
        cases[name] = json.load(handle)
value = {
    "schemaVersion": 1,
    "valid": all(case.get("valid") is True for case in cases.values()),
    "cases": cases,
    "provenance": os.path.realpath(os.path.join(root, "provenance.json")),
}
with open(output, "x", encoding="utf-8") as handle:
    json.dump(value, handle, indent=2, sort_keys=True)
    handle.write("\n")
if not value["valid"]:
    raise SystemExit(1)
PY

if [[ "$release_gate_eligible" == true ]]; then
  printf 'SP avatar ZIP strict-memory gate passed: %s\n' "$output_root/gate-summary.json"
else
  printf 'SP avatar ZIP supplementary 2 GiB / 512 MiB evidence passed (not release-gate eligible): %s\n' \
    "$output_root/gate-summary.json"
fi
