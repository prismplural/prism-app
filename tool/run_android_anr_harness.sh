#!/usr/bin/env bash
set -euo pipefail

# Host-side runner for the Android ANR harness.
#
# This is a local-development harness: it intentionally does NOT require a clean
# committed worktree, because its purpose is to validate the changes that are
# currently checked out. Instead of a clean-tree gate it records the git SHA, a
# hash of the tracked diff, and a hash of the full `git status --porcelain`
# output (which also covers untracked files), so a result can always be traced
# back to its inputs.
#
# It never stops an Android device it did not launch. `--device SERIAL` attaches
# to an already-running emulator or physical device and leaves it alone; only
# `--launch-avd NAME` makes the runner the owner of the emulator, and only then
# does cleanup issue `adb emu kill`.
#
# See docs/testing/android-anr-harness.md for interpretation and the
# emulator-versus-physical-device release gate.

package_id="com.prismplural.prism"
target="integration_test/android_anr_harness_test.dart"
driver="test_driver/integration_test.dart"
output_root="build/android-anr-harness/$(date -u +%Y%m%dT%H%M%SZ)"

device=""
avd_name=""
pulse_threshold_ms=500
sample_interval_seconds=1
boot_timeout_seconds=300
skip_pub_get=false
export_records=""
export_media_mib=""
export_image_members=""
export_image_kib=""
hash_mib=""
extra_defines=()

launched_emulator=false
emulator_pid=""
emulator_log=""
logcat_pid=""
sampler_pid=""
serial=""
logcat_file=""
stop_file=""

usage() {
  cat <<'EOF'
Android ANR harness runner (local validation, not a release gate by itself).

Runs integration_test/android_anr_harness_test.dart in profile mode with
`flutter drive` against exactly one Android target, and records a full evidence
bundle: Flutter log, full logcat, a filtered ANR/OOM log, periodic
`dumpsys meminfo` samples, device properties, harness events, and provenance.

Device selection (exactly one is required):
  --device SERIAL     Attach to an already-running device (emulator or hardware).
                      The runner never stops this device.
  --launch-avd NAME   Launch `emulator -avd NAME`, wait for boot, and treat the
                      emulator as runner-owned: cleanup kills it on exit. The
                      serial is discovered from `adb devices`. Fails fast if an
                      emulator for NAME is already running; use --device instead.

Scenario sizes (each maps to a dart-define; omit to use the test's default):
  --export-records N      PRISM_ANR_EXPORT_RECORDS     (default 20000)
  --export-media-mib N    PRISM_ANR_EXPORT_MEDIA_MIB   (default 16)
  --export-image-members N
                          PRISM_ANR_EXPORT_IMAGE_MEMBERS (default 48)
  --export-image-kib N    PRISM_ANR_EXPORT_IMAGE_KIB    (default 512)
  --hash-mib N            PRISM_ANR_HASH_MIB           (default 32)
  --pulse-threshold-ms N  PRISM_ANR_MAX_PULSE_GAP_MICROS
                          Main-isolate pulse gap budget. Default 500 ms
                          (500000 us), which is the harness default.

Other options:
  --sample-interval-seconds N
                          `dumpsys meminfo` sampling period. Default 1.
  --dart-define KEY=VALUE Repeatable. Extra dart-defines passed through verbatim.
  --out DIR               Output directory. Default
                          build/android-anr-harness/<UTC timestamp>.
  --boot-timeout-seconds N
                          Emulator boot budget for --launch-avd. Default 300.
  --skip-pub-get          Do not run `flutter pub get` first. `flutter drive`
                          is always invoked with --no-pub either way.
  --help, -h              Show this help.

Outcome: exits non-zero when Flutter fails (1) or when logcat contains an app
ANR/OOM for com.prismplural.prism (65). Usage errors exit 64, missing
prerequisites 69, missing target/driver 66.

Emulator results are supporting evidence only. The release gate for ANR/OOM
behavior must be run on a physical device; see docs/testing/android-anr-harness.md.
EOF
}

while (($#)); do
  case "$1" in
    --device) device="$2"; shift 2 ;;
    --launch-avd) avd_name="$2"; shift 2 ;;
    --export-records) export_records="$2"; shift 2 ;;
    --export-media-mib) export_media_mib="$2"; shift 2 ;;
    --export-image-members) export_image_members="$2"; shift 2 ;;
    --export-image-kib) export_image_kib="$2"; shift 2 ;;
    --hash-mib) hash_mib="$2"; shift 2 ;;
    --pulse-threshold-ms) pulse_threshold_ms="$2"; shift 2 ;;
    --sample-interval-seconds) sample_interval_seconds="$2"; shift 2 ;;
    --dart-define) extra_defines+=("$2"); shift 2 ;;
    --out) output_root="$2"; shift 2 ;;
    --boot-timeout-seconds) boot_timeout_seconds="$2"; shift 2 ;;
    --skip-pub-get) skip_pub_get=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 64 ;;
  esac
done

fail_usage() {
  printf '%s\n' "$1" >&2
  exit 64
}

if [[ -n "$device" && -n "$avd_name" ]]; then
  fail_usage '--device and --launch-avd are mutually exclusive.'
fi
if [[ -z "$device" && -z "$avd_name" ]]; then
  fail_usage 'Exactly one of --device SERIAL or --launch-avd NAME is required.'
fi
if ! [[ "$pulse_threshold_ms" =~ ^[1-9][0-9]*$ ]]; then
  fail_usage '--pulse-threshold-ms must be a positive integer.'
fi
if ! [[ "$sample_interval_seconds" =~ ^[1-9][0-9]*$ ]]; then
  fail_usage '--sample-interval-seconds must be a positive integer.'
fi
if ! [[ "$boot_timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
  fail_usage '--boot-timeout-seconds must be a positive integer.'
fi
for size_pair in "export-records:$export_records" \
                 "export-media-mib:$export_media_mib" \
                 "export-image-members:$export_image_members" \
                 "export-image-kib:$export_image_kib" \
                 "hash-mib:$hash_mib"; do
  size_flag="${size_pair%%:*}"
  size_value="${size_pair#*:}"
  if [[ -n "$size_value" ]] && ! [[ "$size_value" =~ ^[1-9][0-9]*$ ]]; then
    fail_usage "--$size_flag must be a positive integer."
  fi
done
# macOS still ships bash 3.2, where `"${array[@]}"` on an empty array is an
# unbound-variable error under `set -u`. The `${array[@]+"${array[@]}"}` idiom
# expands to nothing when the array is unset or empty, and to the quoted
# elements otherwise.
for definition in ${extra_defines[@]+"${extra_defines[@]}"}; do
  if [[ "$definition" != *=* || "$definition" == =* ]]; then
    fail_usage "--dart-define expects KEY=VALUE, got: $definition"
  fi
done

for command in adb flutter dart python3 git awk sed grep tr; do
  command -v "$command" >/dev/null || {
    printf 'Missing prerequisite: %s\n' "$command" >&2
    exit 69
  }
done
if ! command -v shasum >/dev/null && ! command -v sha256sum >/dev/null; then
  printf '%s\n' 'Missing prerequisite: shasum or sha256sum' >&2
  exit 69
fi

hash_stream() {
  if command -v shasum >/dev/null; then
    shasum -a 256 | awk '{print $1}'
  else
    sha256sum | awk '{print $1}'
  fi
}

repo_root="$(git rev-parse --show-toplevel)"
if [[ "$repo_root" != "$(pwd)" ]]; then
  printf '%s\n' 'Run this script from the prism-app repository root.' >&2
  exit 64
fi
if [[ ! -f "$target" ]]; then
  printf 'Harness target not found: %s\n' "$target" >&2
  exit 66
fi
if [[ ! -f "$driver" ]]; then
  printf 'Driver not found: %s\n' "$driver" >&2
  exit 66
fi

# ---------------------------------------------------------------------------
# Device acquisition
# ---------------------------------------------------------------------------

find_emulator_binary() {
  if command -v emulator >/dev/null; then
    command -v emulator
    return 0
  fi
  local candidate
  for candidate in \
    "${ANDROID_SDK_ROOT:-}/emulator/emulator" \
    "${ANDROID_HOME:-}/emulator/emulator" \
    "$HOME/Library/Android/sdk/emulator/emulator" \
    "$HOME/Android/Sdk/emulator/emulator"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

if [[ -n "$avd_name" ]]; then
  emulator_bin="$(find_emulator_binary)" || {
    printf '%s\n' \
      'Could not find the `emulator` binary. Set ANDROID_SDK_ROOT or ANDROID_HOME.' >&2
    exit 69
  }
  # Launching an AVD that is already running would fail (and risk two
  # emulators fighting over the same AVD); point the caller at --device instead.
  while read -r running_serial; do
    [[ -z "$running_serial" ]] && continue
    running_avd="$(adb -s "$running_serial" shell getprop ro.boot.qemu.avd_name \
      2>/dev/null | tr -d '\r')"
    if [[ "$running_avd" == "$avd_name" ]]; then
      printf 'AVD %s is already running as %s; use --device %s instead.\n' \
        "$avd_name" "$running_serial" "$running_serial" >&2
      exit 69
    fi
  done < <(adb devices | awk 'NR > 1 && $2 == "device" {print $1}')
else
  # Validate an attached device before creating any artifact directory, so a
  # typo in the serial cannot leave a half-written run behind.
  if ! adb -s "$device" get-state 2>/dev/null | grep -qx device; then
    printf 'Android device is not ready: %s\n' "$device" >&2
    exit 69
  fi
fi

mkdir -p "$output_root"
logcat_file="$output_root/logcat.txt"
stop_file="$output_root/stop-sampler"

cleanup() {
  local status=$?
  set +e
  trap - EXIT INT TERM
  if [[ -n "$stop_file" ]]; then
    touch "$stop_file" 2>/dev/null
  fi
  if [[ -n "$sampler_pid" ]]; then
    wait "$sampler_pid" 2>/dev/null
  fi
  if [[ -n "$logcat_pid" ]]; then
    kill "$logcat_pid" 2>/dev/null
    wait "$logcat_pid" 2>/dev/null
  fi
  # Only an emulator this runner launched is stopped. An attached device is
  # never touched, so interrupting the script cannot kill someone else's
  # emulator or a physical test device.
  if [[ "$launched_emulator" == true && -n "$serial" ]]; then
    printf 'Stopping emulator launched by this runner: %s\n' "$serial" >&2
    adb -s "$serial" emu kill >/dev/null 2>&1
    if [[ -n "$emulator_pid" ]]; then
      wait "$emulator_pid" 2>/dev/null
    fi
  elif [[ "$launched_emulator" == true && -n "$emulator_pid" ]]; then
    # Registration can time out (or the runner can be interrupted) before adb
    # assigns a serial. The PID is still runner-owned, so terminate it directly
    # rather than leaking an unidentified AVD that wedges the next run.
    printf 'Stopping emulator process launched by this runner: pid %s\n' \
      "$emulator_pid" >&2
    kill "$emulator_pid" 2>/dev/null
    wait "$emulator_pid" 2>/dev/null
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

wait_for_boot() {
  local deadline=$((SECONDS + boot_timeout_seconds)) state
  adb -s "$serial" wait-for-device
  while ((SECONDS < deadline)); do
    state="$(adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
    if [[ "$state" == 1 ]]; then
      return 0
    fi
    if [[ -n "$emulator_pid" ]] && ! kill -0 "$emulator_pid" 2>/dev/null; then
      printf 'Emulator process exited before booting; see %s\n' "$emulator_log" >&2
      return 1
    fi
    sleep 2
  done
  printf 'Timed out after %ss waiting for %s to boot.\n' \
    "$boot_timeout_seconds" "$serial" >&2
  return 1
}

if [[ -n "$avd_name" ]]; then
  emulator_log="$output_root/emulator.log"
  existing_serials="$(adb devices | awk 'NR > 1 && $2 == "device" {print $1}')"
  printf 'Launching AVD %s (log: %s)\n' "$avd_name" "$emulator_log" >&2
  "$emulator_bin" -avd "$avd_name" -no-snapshot-save -no-boot-anim \
    > "$emulator_log" 2>&1 &
  emulator_pid=$!
  launched_emulator=true

  deadline=$((SECONDS + boot_timeout_seconds))
  while [[ -z "$serial" ]] && ((SECONDS < deadline)); do
    while read -r candidate; do
      [[ -z "$candidate" ]] && continue
      if ! grep -qx "$candidate" <<<"$existing_serials"; then
        serial="$candidate"
        break
      fi
    done < <(adb devices | awk 'NR > 1 && $2 == "device" {print $1}')
    [[ -n "$serial" ]] && break
    if ! kill -0 "$emulator_pid" 2>/dev/null; then
      printf 'Emulator process exited before registering; see %s\n' "$emulator_log" >&2
      exit 69
    fi
    sleep 2
  done
  if [[ -z "$serial" ]]; then
    printf 'Timed out after %ss waiting for the AVD to register with adb.\n' \
      "$boot_timeout_seconds" >&2
    exit 69
  fi
  if ! wait_for_boot; then
    exit 69
  fi
else
  serial="$device"
fi

printf 'Using device: %s\n' "$serial" >&2

# ---------------------------------------------------------------------------
# Preflight: pub get, provenance, device facts
# ---------------------------------------------------------------------------

if [[ "$skip_pub_get" != true ]]; then
  printf '%s\n' 'Running flutter pub get ...' >&2
  flutter pub get
fi

generated_at_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
git_sha="$(git rev-parse HEAD)"
git_diff_sha="$(git diff --binary | hash_stream)"
git_status_sha="$(git status --porcelain=v1 --untracked-files=all | hash_stream)"
flutter_version="$(flutter --version --machine)"
dart_version="$(dart --version 2>&1)"
adb_version="$(adb version)"

qemu="$(adb -s "$serial" shell getprop ro.kernel.qemu | tr -d '\r')"
avd_name_on_device="$(adb -s "$serial" shell getprop ro.boot.qemu.avd_name | tr -d '\r')"
sdk="$(adb -s "$serial" shell getprop ro.build.version.sdk | tr -d '\r')"
abi="$(adb -s "$serial" shell getprop ro.product.cpu.abi | tr -d '\r')"
model="$(adb -s "$serial" shell getprop ro.product.model | tr -d '\r')"
fingerprint="$(adb -s "$serial" shell getprop ro.build.fingerprint | tr -d '\r')"
heap_size="$(adb -s "$serial" shell getprop dalvik.vm.heapsize | tr -d '\r')"
mem_total_kb="$(adb -s "$serial" shell cat /proc/meminfo \
  | awk '/^MemTotal:/ {print $2; exit}' | tr -d '\r')"

device_props="$output_root/device-props.txt"
{
  printf 'serial=%s\n' "$serial"
  printf 'requestedAvd=%s\n' "${avd_name:-<attached-device>}"
  printf 'runningAvd=%s\n' "${avd_name_on_device:-<none>}"
  printf 'ro.kernel.qemu=%s\n' "$qemu"
  printf 'ro.build.version.sdk=%s\n' "$sdk"
  printf 'ro.product.cpu.abi=%s\n' "$abi"
  printf 'ro.product.model=%s\n' "$model"
  printf 'ro.build.fingerprint=%s\n' "$fingerprint"
  printf 'dalvik.vm.heapsize=%s\n' "$heap_size"
  printf 'memTotalKiB=%s\n' "$mem_total_kb"
  printf 'runnerLaunchedDevice=%s\n' "$launched_emulator"
} > "$device_props"

dart_define_args=()
dart_define_file="$output_root/dart-defines.txt"
: > "$dart_define_file"
add_define() {
  dart_define_args+=("--dart-define=$1")
  printf '%s\n' "$1" >> "$dart_define_file"
}

add_define "PRISM_ANR_MAX_PULSE_GAP_MICROS=$((pulse_threshold_ms * 1000))"
if [[ -n "$export_records" ]]; then
  add_define "PRISM_ANR_EXPORT_RECORDS=$export_records"
fi
if [[ -n "$export_media_mib" ]]; then
  add_define "PRISM_ANR_EXPORT_MEDIA_MIB=$export_media_mib"
fi
if [[ -n "$export_image_members" ]]; then
  add_define "PRISM_ANR_EXPORT_IMAGE_MEMBERS=$export_image_members"
fi
if [[ -n "$export_image_kib" ]]; then
  add_define "PRISM_ANR_EXPORT_IMAGE_KIB=$export_image_kib"
fi
if [[ -n "$hash_mib" ]]; then
  add_define "PRISM_ANR_HASH_MIB=$hash_mib"
fi
for definition in ${extra_defines[@]+"${extra_defines[@]}"}; do
  add_define "$definition"
done

PP_TIMESTAMP="$generated_at_utc" \
PP_GIT_SHA="$git_sha" \
PP_DIFF_SHA="$git_diff_sha" \
PP_STATUS_SHA="$git_status_sha" \
PP_SERIAL="$serial" \
PP_AVD_NAME="${avd_name:-}" \
PP_AVD_ON_DEVICE="$avd_name_on_device" \
PP_LAUNCHED="$launched_emulator" \
PP_QEMU="$qemu" \
PP_SDK="$sdk" \
PP_ABI="$abi" \
PP_MODEL="$model" \
PP_FINGERPRINT="$fingerprint" \
PP_HEAP="$heap_size" \
PP_MEM_TOTAL_KB="$mem_total_kb" \
PP_FLUTTER="$flutter_version" \
PP_DART="$dart_version" \
PP_ADB="$adb_version" \
PP_PULSE="$pulse_threshold_ms" \
PP_SAMPLE_INTERVAL="$sample_interval_seconds" \
PP_PACKAGE="$package_id" \
PP_TARGET="$target" \
PP_DRIVER="$driver" \
PP_DEFINES_FILE="$dart_define_file" \
PP_OUT="$output_root" \
python3 - "$output_root/provenance.json" <<'PY'
import json
import os
import sys

output = sys.argv[1]
defines = {}
with open(os.environ["PP_DEFINES_FILE"], encoding="utf-8") as handle:
    for line in handle:
        line = line.rstrip("\n")
        if not line or "=" not in line:
            continue
        key, value = line.split("=", 1)
        defines[key] = value

value = {
    "schemaVersion": 1,
    "generatedAtUtc": os.environ.get("PP_TIMESTAMP", ""),
    "package": os.environ["PP_PACKAGE"],
    "target": os.environ["PP_TARGET"],
    "driver": os.environ["PP_DRIVER"],
    "gitSha": os.environ["PP_GIT_SHA"],
    "workingTreeDiffSha256": os.environ["PP_DIFF_SHA"],
    "workingTreeStatusSha256": os.environ["PP_STATUS_SHA"],
    "cleanTreeRequired": False,
    "dartDefines": defines,
    "device": {
        "serial": os.environ["PP_SERIAL"],
        "requestedAvd": os.environ["PP_AVD_NAME"],
        "runningAvd": os.environ["PP_AVD_ON_DEVICE"],
        "isEmulator": os.environ["PP_QEMU"] == "1",
        "sdk": os.environ["PP_SDK"],
        "abi": os.environ["PP_ABI"],
        "model": os.environ["PP_MODEL"],
        "fingerprint": os.environ["PP_FINGERPRINT"],
        "vmHeap": os.environ["PP_HEAP"],
        "memTotalKiB": os.environ["PP_MEM_TOTAL_KB"],
    },
    "tools": {
        "flutter": json.loads(os.environ["PP_FLUTTER"]),
        "dart": os.environ["PP_DART"],
        "adb": os.environ["PP_ADB"],
    },
    "thresholds": {
        "pulseThresholdMs": int(os.environ["PP_PULSE"]),
        "sampleIntervalSeconds": int(os.environ["PP_SAMPLE_INTERVAL"]),
    },
    "safety": {
        "runnerLaunchedDevice": os.environ["PP_LAUNCHED"] == "true",
        "runnerStopsDeviceOnlyIfLaunched": True,
    },
}
with open(output, "x", encoding="utf-8") as handle:
    json.dump(value, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

# ---------------------------------------------------------------------------
# Sampler
# ---------------------------------------------------------------------------

sample_meminfo() {
  local samples="$output_root/meminfo-samples.csv"
  local raw_root="$output_root/meminfo-raw"
  local start_ms now_ms elapsed_ms pid dumpsys pss rss sequence=0
  mkdir -p "$raw_root"
  printf '%s\n' 'elapsed_ms,pid,total_pss_kb,rss_kb' > "$samples"
  start_ms="$(python3 -c 'import time; print(time.monotonic_ns() // 1000000)')"
  while [[ ! -e "$stop_file" ]]; do
    # The sampler starts before Flutter installs and launches the profile app.
    # `pidof` therefore legitimately exits non-zero for its first few polls;
    # absorb that expected state so `set -e -o pipefail` cannot kill sampling.
    pid="$({ adb -s "$serial" shell pidof "$package_id" 2>/dev/null || true; } \
      | tr -d '\r' | awk '{print $1}')"
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
      sequence=$((sequence + 1))
      dumpsys="$raw_root/$(printf '%06d' "$sequence").txt"
      adb -s "$serial" shell dumpsys meminfo "$package_id" > "$dumpsys" 2>/dev/null || true
      pss="$(awk '
        /TOTAL PSS:/ {print $3; found=1; exit}
        $1 == "TOTAL" && $2 ~ /^[0-9]+$/ {candidate=$2}
        END {if (!found && candidate != "") print candidate}
      ' "$dumpsys")"
      rss="$({ adb -s "$serial" shell cat "/proc/$pid/status" 2>/dev/null || true; } \
        | awk '/^VmRSS:/ {print $2; exit}' | tr -d '\r')"
      if [[ "$pss" =~ ^[1-9][0-9]*$ && "$rss" =~ ^[1-9][0-9]*$ ]]; then
        now_ms="$(python3 -c 'import time; print(time.monotonic_ns() // 1000000)')"
        elapsed_ms=$((now_ms - start_ms))
        printf '%s,%s,%s,%s\n' "$elapsed_ms" "$pid" "$pss" "$rss" >> "$samples"
      fi
    fi
    sleep "$sample_interval_seconds"
  done
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

adb -s "$serial" logcat -c
adb -s "$serial" logcat -v threadtime > "$logcat_file" 2>&1 &
logcat_pid=$!
sample_meminfo &
sampler_pid=$!

flutter_log="$output_root/flutter-drive.log"
: > "$flutter_log"

set +e
flutter drive --profile --no-pub \
  --driver="$driver" \
  --target="$target" \
  -d "$serial" \
  ${dart_define_args[@]+"${dart_define_args[@]}"} \
  2>&1 | tee "$flutter_log"
flutter_status=${PIPESTATUS[0]}
set -e

touch "$stop_file"
wait "$sampler_pid" 2>/dev/null || true
sampler_pid=""
kill "$logcat_pid" 2>/dev/null || true
wait "$logcat_pid" 2>/dev/null || true
logcat_pid=""

# Filtered log uses the same fatal-signal vocabulary as the memory report tool
# (tool/sp_avatar_zip_memory_report.dart) so both harnesses read alike.
filter_regex='ANR in com\.prismplural\.prism|OutOfMemoryError|lowmemorykiller|am_anr|am_kill|Killing .*com\.prismplural\.prism|FATAL EXCEPTION|com\.prismplural\.prism|PRISM_ANR_HARNESS'
filtered_log="$output_root/logcat-anr-oom.txt"
grep -nE "$filter_regex" "$logcat_file" > "$filtered_log" 2>/dev/null || true

anr_detected=false
oom_detected=false
if grep -qiE 'ANR in com\.prismplural\.prism' "$logcat_file"; then
  anr_detected=true
fi
# The emulator may reclaim unrelated background apps while Gradle installs and
# launches Prism. That is useful context in the filtered log, but only a Prism
# OOM/LMK is a harness failure.
if grep -qiE \
  "OutOfMemoryError.*com\\.prismplural\\.prism|com\\.prismplural\\.prism.*OutOfMemoryError|(lowmemorykiller|lmkd).*Kill '?com\\.prismplural\\.prism|am_kill.*com\\.prismplural\\.prism" \
  "$logcat_file"; then
  oom_detected=true
fi

PP_FLUTTER_LOG="$flutter_log" \
python3 - "$output_root/harness-events.json" <<'PY'
import json
import os
import sys

output = sys.argv[1]
events = []
with open(os.environ["PP_FLUTTER_LOG"], encoding="utf-8", errors="replace") as handle:
    for raw in handle:
        marker = raw.find("PRISM_ANR_HARNESS ")
        if marker < 0:
            continue
        payload = raw[marker + len("PRISM_ANR_HARNESS "):].strip()
        try:
            parsed = json.loads(payload)
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, dict):
            events.append(parsed)

scenarios = []
max_gap_micros = None
for event in events:
    if event.get("event") == "scenario_end":
        scenarios.append(event.get("scenario"))
    # `scenario_end` nests the pulse summary under "heartbeat"; the
    # `monitor_calibration` event emits the summary fields inline.
    heartbeat = event.get("heartbeat")
    if not isinstance(heartbeat, dict):
        heartbeat = event
    gap = heartbeat.get("maximumGapMicros")
    if isinstance(gap, int):
        max_gap_micros = gap if max_gap_micros is None else max(max_gap_micros, gap)

value = {
    "schemaVersion": 1,
    "eventCount": len(events),
    "events": events,
    "scenarios": scenarios,
    "maxObservedGapMicros": max_gap_micros,
    "harnessTeardownMarkerPresent": any(
        event.get("event") == "harness_teardown_reached" for event in events
    ),
}
with open(output, "x", encoding="utf-8") as handle:
    json.dump(value, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

PP_OUT="$output_root" \
PP_FLUTTER_STATUS="$flutter_status" \
PP_ANR="$anr_detected" \
PP_OOM="$oom_detected" \
PP_LAUNCHED="$launched_emulator" \
PP_PULSE="$pulse_threshold_ms" \
PP_EVENTS="$output_root/harness-events.json" \
python3 - "$output_root/result.json" <<'PY'
import json
import os
import sys

output = sys.argv[1]
flutter_status = int(os.environ["PP_FLUTTER_STATUS"])
anr = os.environ["PP_ANR"] == "true"
oom = os.environ["PP_OOM"] == "true"
with open(os.environ["PP_EVENTS"], encoding="utf-8") as handle:
    event_report = json.load(handle)
expected_scenarios = {"encrypted_export", "profile_header", "media_hash"}
scenario_events = [
    event for event in event_report["events"]
    if event.get("event") == "scenario_end"
]
observed_scenarios = {event.get("scenario") for event in scenario_events}
heartbeats_passed = bool(scenario_events) and all(
    isinstance(event.get("heartbeat"), dict)
    and event["heartbeat"].get("passed") is True
    for event in scenario_events
)
calibration_passed = any(
    event.get("event") == "monitor_calibration"
    and event.get("passed") is False
    and isinstance(event.get("maximumGapMicros"), int)
    for event in event_report["events"]
)
harness_evidence_valid = (
    event_report["harnessTeardownMarkerPresent"] is True
    and observed_scenarios == expected_scenarios
    and heartbeats_passed
    and calibration_passed
)
passed = (
    flutter_status == 0
    and not anr
    and not oom
    and harness_evidence_valid
)
value = {
    "schemaVersion": 1,
    "flutterExitStatus": flutter_status,
    "appAnrDetected": anr,
    "appOomDetected": oom,
    "harnessEvidenceValid": harness_evidence_valid,
    "harnessTeardownMarkerPresent": event_report[
        "harnessTeardownMarkerPresent"
    ],
    "observedScenarios": sorted(observed_scenarios),
    "heartbeatsPassed": heartbeats_passed,
    "calibrationDetectedStall": calibration_passed,
    "passed": passed,
    "pulseThresholdMs": int(os.environ["PP_PULSE"]),
    "runnerLaunchedDevice": os.environ["PP_LAUNCHED"] == "true",
    "runnerStoppedEmulator": os.environ["PP_LAUNCHED"] == "true",
    "artifacts": {
        "flutterLog": "flutter-drive.log",
        "logcat": "logcat.txt",
        "filteredAnrOomLog": "logcat-anr-oom.txt",
        "harnessEvents": "harness-events.json",
        "meminfoSamples": "meminfo-samples.csv",
        "meminfoRawDir": "meminfo-raw",
        "deviceProps": "device-props.txt",
        "provenance": "provenance.json",
        "dartDefines": "dart-defines.txt",
        "emulatorLog": "emulator.log" if os.environ["PP_LAUNCHED"] == "true" else None,
    },
}
with open(output, "x", encoding="utf-8") as handle:
    json.dump(value, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

# The verdict is decided in bash so that an artifact-write problem cannot be
# mistaken for a harness failure (or vice versa).
if ((flutter_status != 0)); then
  printf 'Flutter integration test failed with status %s (see %s).\n' \
    "$flutter_status" "$flutter_log" >&2
  exit 1
fi
if [[ "$anr_detected" == true || "$oom_detected" == true ]]; then
  printf 'App ANR/OOM detected in logcat (anr=%s oom=%s); see %s.\n' \
    "$anr_detected" "$oom_detected" "$filtered_log" >&2
  exit 65
fi
if ! python3 - "$output_root/result.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    raise SystemExit(0 if json.load(handle).get("passed") is True else 1)
PY
then
  printf 'Harness evidence is incomplete or invalid; see %s.\n' \
    "$output_root/result.json" >&2
  exit 65
fi

printf 'Android ANR harness passed. Artifacts: %s\n' "$output_root"
