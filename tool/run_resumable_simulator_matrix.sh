#!/usr/bin/env bash
set -euo pipefail

# Device simulator/emulator matrix for the SPLIT resumable pairing surface.
#
# This is a THIN orchestration layer. It does not reimplement the pairing
# ceremony: the ceremony, its assertions, and its metrics reading all live in
# `integration_test/resumable_split_pairing_device_test.dart`, which drives the
# real generated FFI against the real Rust core.
#
# What this runner owns:
#
#   1. Building the relay image from the *feature* prism-sync worktree, using the
#      test-only `Containerfile.test-relay` (bookworm-pinned on both stages).
#   2. Starting a disposable, file-backed relay per scenario family and waiting
#      for `/health`.
#   3. Making that relay reachable from the device: the iOS simulator shares the
#      host loopback, and Android gets `adb reverse tcp:<port> tcp:<port>`.
#   4. Running `flutter drive --profile` once per (platform, scenario) pair.
#   5. Capturing logs, metrics, device facts, provenance, and screenshots.
#   6. Writing a hard pass/fail summary artifact and exiting non-zero on failure.
#
# Scenario matrix (per platform): happy-resumable x1, dark-fallback x1,
# cancel-mid-upload x3. Cancellation is repeated because a mid-flight abort is
# inherently timing-sensitive; three runs make a one-off pass visibly weaker than
# a stable one in the summary artifact.
#
# Only synthetic data is used. No secret (metrics token, registration token) is
# written to any evidence artifact.
#
# See docs/testing/resumable-simulator-matrix.md for interpretation.

app_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$app_root"

repo_root=$(git rev-parse --show-toplevel)
if [[ "$repo_root" != "$app_root" ]]; then
  printf '%s\n' 'Run this script from the prism-app repository root.' >&2
  exit 64
fi

container_image="prism-sync-relay:test-resumable"
containerfile="Containerfile.test-relay"
target="integration_test/resumable_split_pairing_device_test.dart"
driver="test_driver/integration_test.dart"
relay_container_port=8080
# Chosen to stay clear of the relay's own 8080 default, adb's 5037, and the
# emulator console ports (5554/5555).
host_port=18080
boot_timeout_seconds=420
cancel_repeats=3

ios_device=""
ios_simulator_name=""
android_serial=""
android_avd=""
sync_dir=""
output_root=""
skip_pub_get=false
skip_image_build=false
keep_relay=false
relay_only=false
extra_defines=()
scenarios=()

relay_name=""
relay_started=false
relay_pid=""
# "container" is the specified, primary backend. "process" runs a pre-built
# production relay binary directly and exists only as a documented fallback for
# hosts where the Apple container runtime is unavailable.
relay_backend="container"
relay_binary=""
launched_emulator=false
emulator_pid=""
emulator_log=""
booted_simulator_udid=""
platforms_csv=""

usage() {
  cat <<'EOF'
Resumable pairing simulator/emulator matrix runner.

Builds the relay from the feature prism-sync worktree in a bookworm-pinned test
image, starts a disposable file-backed relay, makes it reachable from the device,
and runs the device integration test for each scenario.

Requirements:
  - Apple `container` CLI (verified before anything else)
  - flutter, dart, adb, xcrun, python3, git, curl, jq
  - A prism-app checkout whose prism_sync packages resolve inside a prism-sync
    Git worktree (--sync-dir overrides the resolved one)

Platform selection (at least one; both may be given for the full matrix):
  --ios-device UDID       Boot/attach this iOS simulator (e.g. from
                          `xcrun simctl list devices available`). An already
                          booted simulator is reused and NOT shut down by this
                          runner; one this runner boots is shut down on exit.
  --ios-simulator NAME    Shorthand: pick the first available simulator whose
                          name equals NAME (exact match).
                          NOTE: the iOS Simulator shares the host loopback, so
                          the relay is reached at http://localhost:<port> with
                          no extra forwarding.
  --android-serial SERIAL Attach to an already-running Android emulator or
                          physical device. Never stopped by this runner.
  --android-avd NAME      Launch `emulator -avd NAME`, wait for boot, and stop
                          it on exit (runner-owned). Fails if already running.
                          Reached through `adb reverse tcp:<port> tcp:<port>`.

Relay and scenarios:
  --sync-dir DIR          prism-sync worktree to build the relay from. Defaults
                          to the checkout resolved from package_config.json.
  --host-port N           Host loopback port for the relay. Default 18080.
                          Only `http://localhost:<port>` is ever used.
  --cancel-repeats N      cancel-mid-upload repetitions per platform. Default 3.
  --scenario NAME         Run only this scenario. Repeatable. Default: all of
                          happy-resumable, dark-fallback, cancel-mid-upload.

Other options:
  --relay-only            Preflight only: verify the container CLI, build the
                          image, and prove both the resumable and dark relays
                          start, advertise the expected capability, and serve
                          /metrics. No device is touched. Useful before a long
                          matrix run, and the only mode that needs no device.
  --relay-binary PATH     FALLBACK backend. Run this pre-built prism-sync-relay
                          binary directly instead of the Apple container runtime.
                          The relay image build is skipped. The container backend
                          is the primary, specified path; this exists for hosts
                          where the container runtime is unavailable. PATH must
                          be a production `prism-sync-relay` built from the
                          feature worktree (`cargo build -p prism-sync-relay`).
  --out DIR               Output root. Default build/resumable-simulator-matrix/
                          <UTC timestamp>.
  --dart-define KEY=VALUE Repeatable. Extra dart-defines passed through verbatim.
  --boot-timeout-seconds N
                          Emulator/simulator boot budget. Default 420.
  --skip-pub-get          Skip `flutter pub get`.
  --skip-image-build      Reuse the existing container image.
  --keep-relay            Do not delete relay state on exit (debugging).
  --help, -h              Show this help.

Exit status: 0 only when every scenario in the matrix passed and the evidence
bundle is complete. Usage errors 64, missing prerequisites 69, missing
target/driver 66, scenario failure 65.
EOF
}

while (($#)); do
  case "$1" in
    --ios-device) ios_device="$2"; shift 2 ;;
    --ios-simulator) ios_simulator_name="$2"; shift 2 ;;
    --android-serial) android_serial="$2"; shift 2 ;;
    --android-avd) android_avd="$2"; shift 2 ;;
    --sync-dir) sync_dir="$2"; shift 2 ;;
    --host-port) host_port="$2"; shift 2 ;;
    --cancel-repeats) cancel_repeats="$2"; shift 2 ;;
    --scenario) scenarios+=("$2"); shift 2 ;;
    --out) output_root="$2"; shift 2 ;;
    --dart-define) extra_defines+=("$2"); shift 2 ;;
    --boot-timeout-seconds) boot_timeout_seconds="$2"; shift 2 ;;
    --skip-pub-get) skip_pub_get=true; shift ;;
    --skip-image-build) skip_image_build=true; shift ;;
    --keep-relay) keep_relay=true; shift ;;
    --relay-only) relay_only=true; shift ;;
    --relay-binary) relay_binary="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 64 ;;
  esac
done

fail_usage() {
  printf '%s\n' "$1" >&2
  exit 64
}

if [[ "$relay_only" != true ]] &&
  [[ -z "$ios_device" && -z "$android_serial" && -z "$android_avd" && -z "$ios_simulator_name" ]]; then
  fail_usage 'Select at least one target (--ios-device/--ios-simulator, --android-serial/--android-avd), or pass --relay-only.'
fi
if [[ -n "$ios_device" && -n "$ios_simulator_name" ]]; then
  fail_usage '--ios-device and --ios-simulator are mutually exclusive.'
fi
if [[ -n "$android_serial" && -n "$android_avd" ]]; then
  fail_usage '--android-serial and --android-avd are mutually exclusive.'
fi
if ! [[ "$host_port" =~ ^[1-9][0-9]{2,4}$ ]] || ((host_port > 65535)); then
  fail_usage '--host-port must be a valid TCP port.'
fi
if ! [[ "$cancel_repeats" =~ ^[1-9][0-9]*$ ]]; then
  fail_usage '--cancel-repeats must be a positive integer.'
fi
if ! [[ "$boot_timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
  fail_usage '--boot-timeout-seconds must be a positive integer.'
fi
# macOS still ships bash 3.2, where `"${array[@]}"` on an empty array is an
# unbound-variable error under `set -u`; the `${array[@]+...}` idiom is safe.
if ((${#scenarios[@]} == 0)); then
  scenarios=(happy-resumable dark-fallback cancel-mid-upload)
fi
for scenario in ${scenarios[@]+"${scenarios[@]}"}; do
  case "$scenario" in
    happy-resumable|dark-fallback|cancel-mid-upload) ;;
    *) fail_usage "Unsupported --scenario: $scenario" ;;
  esac
done
for definition in ${extra_defines[@]+"${extra_defines[@]}"}; do
  if [[ "$definition" != *=* || "$definition" == =* ]]; then
    fail_usage "--dart-define expects KEY=VALUE, got: $definition"
  fi
done
if [[ -n "$relay_binary" ]]; then
  relay_backend="process"
  relay_binary=$(cd "$(dirname "$relay_binary")" && pwd -P)/$(basename "$relay_binary")
  [[ -x "$relay_binary" ]] || {
    printf 'Relay binary is not executable: %s\n' "$relay_binary" >&2
    exit 69
  }
fi

for command in flutter dart git python3 curl awk sed tr jq; do
  command -v "$command" >/dev/null || {
    printf 'Missing prerequisite: %s\n' "$command" >&2
    exit 69
  }
done

# ---------------------------------------------------------------------------
# Apple `container` CLI gate
# ---------------------------------------------------------------------------

# Verified first, before any other work, because everything downstream depends on
# it. The installed CLI must expose the subcommands and options this runner uses:
# `build -f/--file`, and `run` with `--mount type=bind,...` plus `--publish`.
# Skipped only when the documented --relay-binary fallback backend is selected.
if [[ "$relay_backend" == "container" ]]; then
  if ! command -v container >/dev/null; then
    printf '%s\n' \
      'Missing prerequisite: container (Apple container CLI). See docs/testing/resumable-simulator-matrix.md.' >&2
    exit 69
  fi

  container_help="$(container --help 2>&1 || true)"
  for subcommand in build run stop delete list; do
    if ! grep -qE "(^|[ ,])${subcommand}(,| |$)" <<<"$container_help"; then
      printf 'Installed container CLI does not expose the "%s" subcommand.\n' "$subcommand" >&2
      exit 69
    fi
  done

  build_help="$(container build --help 2>&1 || true)"
  for option in --file --tag; do
    if ! grep -q -- "$option" <<<"$build_help"; then
      printf 'Installed container build CLI does not support %s.\n' "$option" >&2
      exit 69
    fi
  done

  run_help="$(container run --help 2>&1 || true)"
  for option in --mount --publish --env --detach --name; do
    if ! grep -q -- "$option" <<<"$run_help"; then
      printf 'Installed container run CLI does not support %s.\n' "$option" >&2
      exit 69
    fi
  done
  # `--mount` must be the `type=<>,source=<>,target=<>` form, which is preferred
  # over `-v` because it is explicit about the mount type.
  if ! grep -q 'type=' <<<"$run_help"; then
    printf '%s\n' 'Installed container run --mount does not document type=<>,source=<>,target=<>.' >&2
    exit 69
  fi

  container --version 2>&1 | head -1 >&2
fi

# ---------------------------------------------------------------------------
# Resolve the feature prism-sync worktree
# ---------------------------------------------------------------------------

if [[ "$skip_pub_get" != true ]]; then
  printf '%s\n' 'Running flutter pub get ...' >&2
  flutter pub get
fi
[[ -f .dart_tool/package_config.json ]] || {
  printf '%s\n' 'flutter pub get did not produce .dart_tool/package_config.json.' >&2
  exit 69
}

package_checkout() {
  local package_name=$1 root_uri package_path
  root_uri=$(jq -er --arg name "$package_name" \
    '.packages[] | select(.name == $name) | .rootUri' \
    .dart_tool/package_config.json) || {
      printf 'Package not resolved: %s\n' "$package_name" >&2
      exit 69
    }
  [[ "$root_uri" != *%* ]] || {
    printf 'Encoded package paths are unsupported: %s\n' "$root_uri" >&2
    exit 69
  }
  if [[ "$root_uri" == file://* ]]; then
    package_path=${root_uri#file://}
  else
    package_path="$app_root/.dart_tool/$root_uri"
  fi
  package_path=$(cd "$package_path" && pwd -P) || exit 69
  git -C "$package_path" rev-parse --show-toplevel 2>/dev/null || {
    printf '%s did not resolve inside a prism-sync Git checkout.\n' "$package_name" >&2
    exit 69
  }
}

resolved_sync_dir="$(package_checkout prism_sync)"
for package_name in prism_sync_drift prism_sync_flutter; do
  candidate="$(package_checkout "$package_name")"
  [[ "$candidate" == "$resolved_sync_dir" ]] || {
    printf 'Prism Sync packages resolve to different checkouts: %s and %s\n' \
      "$resolved_sync_dir" "$candidate" >&2
    exit 69
  }
done
if [[ -n "$sync_dir" ]]; then
  sync_dir=$(cd "$sync_dir" && pwd -P)
  [[ "$sync_dir" == "$resolved_sync_dir" ]] || {
    printf '%s\n' \
      '--sync-dir does not match the checkout flutter pub get resolved. Run flutter pub get against that worktree, or omit --sync-dir.' >&2
    exit 69
  }
else
  sync_dir="$resolved_sync_dir"
fi
if [[ "$relay_backend" == "container" ]]; then
  [[ -f "$sync_dir/$containerfile" ]] || {
    printf 'Test-only Containerfile not found: %s/%s\n' "$sync_dir" "$containerfile" >&2
    exit 66
  }
fi
sync_rev="$(git -C "$sync_dir" rev-parse HEAD)"
printf 'Relay build source: %s @ %s\n' "$sync_dir" "$sync_rev" >&2

# ---------------------------------------------------------------------------
# Output tree
# ---------------------------------------------------------------------------

if [[ -z "$output_root" ]]; then
  output_root="build/resumable-simulator-matrix/$(date -u +%Y%m%dT%H%M%SZ)"
fi
mkdir -p "$output_root"
logs_dir="$output_root/logs"
metrics_dir="$output_root/metrics"
screenshots_dir="$output_root/screenshots"
provenance_dir="$output_root/provenance"
mkdir -p "$logs_dir" "$metrics_dir" "$screenshots_dir" "$provenance_dir"

# Relay state and every secret live OUTSIDE the output tree, so no evidence
# artifact can ever contain a token.
state_root="$(mktemp -d "${TMPDIR:-/tmp}/prism-resumable-matrix.XXXXXX")"
metrics_token="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
registration_token="OPEN"

summary_path="$output_root/summary.json"

write_summary() {
  local status=$1
  PP_OUTPUT="$output_root" \
  PP_STATUS="$status" \
  PP_PLATFORMS="$platforms_csv" \
  PP_SYNC_DIR="$sync_dir" \
  PP_SYNC_REV="$sync_rev" \
  PP_HOST_PORT="$host_port" \
  PP_IMAGE="$container_image" \
  PP_SCENARIOS="${scenarios[*]}" \
  PP_CANCEL_REPEATS="$cancel_repeats" \
  PP_RESULTS_FILE="$output_root/scenario-results.tsv" \
  PP_RELAY_ONLY="$relay_only" \
  PP_RELAY_BACKEND="$relay_backend" \
  python3 - "$summary_path" <<'PY'
import json
import os
import sys

results = []
results_file = os.environ["PP_RESULTS_FILE"]
if os.path.exists(results_file):
    with open(results_file, encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t")
            if len(parts) < 5:
                continue
            results.append(
                {
                    "platform": parts[0],
                    "scenario": parts[1],
                    "attempt": int(parts[2]),
                    "status": parts[3],
                    "logFile": parts[4],
                }
            )

relay_only = os.environ["PP_RELAY_ONLY"] == "true"
runner_status = os.environ["PP_STATUS"]
# In --relay-only there is no device matrix to pass; success is the preflight.
attempts_ok = bool(results) and all(item["status"] == "passed" for item in results)
matrix_passed = (
    runner_status == "complete" and (attempts_ok or relay_only)
)
value = {
    "schemaVersion": 1,
    "runnerStatus": runner_status,
    "mode": "relay-only" if relay_only else "device-matrix",
    "matrixPassed": matrix_passed,
    "platforms": [p for p in os.environ["PP_PLATFORMS"].split(",") if p],
    "scenarios": [s for s in os.environ["PP_SCENARIOS"].split() if s],
    "cancelRepeats": int(os.environ["PP_CANCEL_REPEATS"]),
    "relay": {
        "image": os.environ["PP_IMAGE"],
        "backend": os.environ["PP_RELAY_BACKEND"],
        "hostPort": int(os.environ["PP_HOST_PORT"]),
        "urlForm": "http://localhost:%s" % os.environ["PP_HOST_PORT"],
        # The token VALUE is deliberately absent: this file is evidence.
        "metricsTokenConfigured": True,
    },
    "sync": {
        "worktree": os.environ["PP_SYNC_DIR"],
        "revision": os.environ["PP_SYNC_REV"],
    },
    "attempts": results,
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(value, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
}

cleanup() {
  local status=$?
  set +e
  trap - EXIT INT TERM
  stop_relay
  # Only a device this runner launched is stopped.
  if [[ "$launched_emulator" == true ]]; then
    if [[ -n "$android_serial" ]]; then
      printf 'Stopping emulator launched by this runner: %s\n' "$android_serial" >&2
      adb -s "$android_serial" emu kill >/dev/null 2>&1
    fi
    if [[ -n "$emulator_pid" ]]; then
      kill "$emulator_pid" 2>/dev/null
      wait "$emulator_pid" 2>/dev/null
    fi
  fi
  if [[ -n "$booted_simulator_udid" ]]; then
    printf 'Shutting down simulator booted by this runner: %s\n' \
      "$booted_simulator_udid" >&2
    xcrun simctl shutdown "$booted_simulator_udid" >/dev/null 2>&1
  fi
  # The summary is always written, including on failure: it is the artifact a
  # reader uses to understand what ran, not just a success marker.
  write_summary "$([[ $status -eq 0 ]] && echo complete || echo failed)"
  if [[ "$keep_relay" != true ]]; then
    rm -rf "$state_root"
  else
    printf 'Keeping relay state: %s\n' "$state_root" >&2
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

: > "$output_root/scenario-results.tsv"
# Provenance for the run as a whole. Tokens are never included.
{
  printf 'app_git_sha=%s\n' "$(git rev-parse HEAD)"
  printf 'sync_git_sha=%s\n' "$sync_rev"
  printf 'sync_worktree=%s\n' "$sync_dir"
  printf 'container_version=%s\n' "$(container --version 2>&1 | head -1)"
  printf 'host_port=%s\n' "$host_port"
  printf 'relay_backend=%s\n' "$relay_backend"
  if [[ "$relay_backend" == "process" ]]; then
    printf 'relay_binary=%s\n' "$relay_binary"
  fi
  printf 'relay_scenarios=%s\n' "${scenarios[*]}"
  printf 'cancel_repeats=%s\n' "$cancel_repeats"
} > "$provenance_dir/run.txt"

# ---------------------------------------------------------------------------
# Relay lifecycle
# ---------------------------------------------------------------------------

stop_relay() {
  if [[ "$relay_started" != true ]]; then
    return 0
  fi
  relay_started=false
  if [[ "$relay_backend" == "process" ]]; then
    if [[ -n "$relay_pid" ]]; then
      kill "$relay_pid" >/dev/null 2>&1 || true
      wait "$relay_pid" 2>/dev/null || true
      relay_pid=""
    fi
    return 0
  fi
  if [[ -n "$relay_name" ]]; then
    container stop "$relay_name" >/dev/null 2>&1 || true
    container delete "$relay_name" >/dev/null 2>&1 || true
  fi
}

# Fetch a relay route from the host and print the body. Used for the readiness
# probe and for the evidence snapshot.
relay_curl() {
  curl -fsS -m 5 "http://localhost:$host_port$1" 2>/dev/null
}

capture_metrics() {
  curl -fsS -m 5 -H "Authorization: Bearer $metrics_token" \
    "http://localhost:$host_port/metrics" > "$metrics_dir/$1.txt" 2>/dev/null || true
}

# Print diagnostic output for a failed relay startup, per backend.
relay_diagnostics() {
  if [[ "$relay_backend" == "process" ]]; then
    printf 'Relay process %s is not serving; log:\n' "${relay_pid:-<none>}" >&2
    tail -40 "$logs_dir/relay-"*.log 2>/dev/null >&2 || true
    return 0
  fi
  printf 'Relay container %s is not running; logs:\n' "$relay_name" >&2
  container logs "$relay_name" 2>&1 | tail -40 >&2 || true
}

wait_for_health() {
  local deadline=$((SECONDS + 150))
  while ((SECONDS < deadline)); do
    if relay_curl /health | grep -q '"status"'; then
      return 0
    fi
    # A relay that died on startup is a configuration error, not a slow boot.
    if [[ "$relay_backend" == "process" ]]; then
      if [[ -z "$relay_pid" ]] || ! kill -0 "$relay_pid" 2>/dev/null; then
        relay_diagnostics
        return 1
      fi
    elif ! container list 2>/dev/null | grep -q "$relay_name"; then
      relay_diagnostics
      return 1
    fi
    sleep 1
  done
  printf 'Timed out waiting for relay health on port %s.\n' "$host_port" >&2
  relay_diagnostics
  return 1
}

# Start a disposable, file-backed relay.
#
# $1 = label (resumable|dark)
# $2 = "resumable" or "dark"
start_relay() {
  local label=$1 mode=$2 state_dir
  stop_relay
  state_dir="$state_root/$label"
  mkdir -p "$state_dir/media"

  # Shared, explicit feature flags. Computed once and consumed by BOTH backends
  # so the container path and the process fallback cannot drift apart.
  local file_backing="false" upload_enabled="false" lease_enabled="false"
  local global_reserved="4294967296" group_reserved="1073741824"
  local free_space_reserve="268435456" create_rate_limit="10000"
  if [[ "$mode" == "resumable" ]]; then
    # Explicit: file backing requested (startup refuses rather than silently
    # downgrading, which would withhold the capability), the upload capability
    # on, the lease on, and the resource envelope widened so a multi-chunk
    # upload exercises chunk semantics rather than quota enforcement.
    file_backing="true"
    upload_enabled="true"
    lease_enabled="true"
  fi

  local env_args=()
  env_args+=(-e "DB_PATH=/data/relay.db")
  env_args+=(-e "MEDIA_STORAGE_PATH=/data/media")
  env_args+=(-e "PORT=$relay_container_port")
  env_args+=(-e "METRICS_TOKEN=$metrics_token")
  # The relay auto-generates a registration token and rejects client
  # registration unless it is explicitly open. These are loopback-only,
  # disposable relays.
  env_args+=(-e "REGISTRATION_TOKEN=$registration_token")
  env_args+=(-e "RUST_LOG=info")
  env_args+=(-e "SNAPSHOT_FILE_BACKING_ENABLED=$file_backing")
  env_args+=(-e "SNAPSHOT_UPLOAD_ENABLED=$upload_enabled")
  env_args+=(-e "PAIRING_LEASE_ENABLED=$lease_enabled")
  env_args+=(-e "SNAPSHOT_UPLOAD_GLOBAL_RESERVED_BYTES=$global_reserved")
  env_args+=(-e "SNAPSHOT_UPLOAD_GROUP_RESERVED_BYTES=$group_reserved")
  env_args+=(-e "SNAPSHOT_UPLOAD_FREE_SPACE_RESERVE_BYTES=$free_space_reserve")
  env_args+=(-e "SNAPSHOT_UPLOAD_CREATE_RATE_LIMIT=$create_rate_limit")
  env_args+=(-e "PAIRING_SESSION_TTL_SECS=1800")
  env_args+=(-e "PAIRING_SESSION_RATE_LIMIT=1000")
  env_args+=(-e "NONCE_RATE_LIMIT=1000")
  env_args+=(-e "WS_UPGRADE_RATE_LIMIT=1000")

  if [[ "$relay_backend" == "process" ]]; then
    # Fallback backend: run the pre-built production relay binary directly, with
    # the same explicit file backing, lease, and upload flags the container path
    # uses. No image is built and the build context is irrelevant.
    #
    # There is no port remapping here (a container is published from its internal
    # port to the host port; a bare process is not), so the relay must bind the
    # host port directly.
    printf 'Starting %s relay process at http://localhost:%s (state: %s)\n' \
      "$mode" "$host_port" "$state_dir" >&2
    env DB_PATH="$state_dir/relay.db" \
      MEDIA_STORAGE_PATH="$state_dir/media" \
      PORT="$host_port" \
      METRICS_TOKEN="$metrics_token" \
      REGISTRATION_TOKEN="$registration_token" \
      RUST_LOG=info \
      SNAPSHOT_FILE_BACKING_ENABLED="$file_backing" \
      SNAPSHOT_UPLOAD_ENABLED="$upload_enabled" \
      PAIRING_LEASE_ENABLED="$lease_enabled" \
      SNAPSHOT_UPLOAD_GLOBAL_RESERVED_BYTES="$global_reserved" \
      SNAPSHOT_UPLOAD_GROUP_RESERVED_BYTES="$group_reserved" \
      SNAPSHOT_UPLOAD_FREE_SPACE_RESERVE_BYTES="$free_space_reserve" \
      SNAPSHOT_UPLOAD_CREATE_RATE_LIMIT="$create_rate_limit" \
      PAIRING_SESSION_TTL_SECS=1800 \
      PAIRING_SESSION_RATE_LIMIT=1000 \
      NONCE_RATE_LIMIT=1000 \
      WS_UPGRADE_RATE_LIMIT=1000 \
      "$relay_binary" > "$logs_dir/relay-$label.log" 2>&1 &
    relay_pid=$!
    relay_started=true
    sleep 1
    if ! kill -0 "$relay_pid" 2>/dev/null; then
      printf 'Relay process exited during startup; log:\n' >&2
      tail -40 "$logs_dir/relay-$label.log" >&2
      return 1
    fi
    wait_for_health || return 1
    printf 'Relay ready: %s\n' "$(relay_curl /health)" >&2
    capture_metrics "$label-before"
    return 0
  fi

  relay_name="prism-resumable-$label-$$"
  printf 'Starting %s relay at http://localhost:%s (state: %s)\n' \
    "$mode" "$host_port" "$state_dir" >&2
  container run -d \
    --name "$relay_name" \
    --mount "type=bind,source=$state_dir,target=/data" \
    --publish "127.0.0.1:$host_port:$relay_container_port" \
    ${env_args[@]+"${env_args[@]}"} \
    "$container_image" >/dev/null
  relay_started=true

  wait_for_health || return 1
  printf 'Relay ready: %s\n' "$(relay_curl /health)" >&2
  # Prove the capability shape from the host as the first evidence artifact.
  capture_metrics "$label-before"
  return 0
}

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

prepare_android() {
  command -v adb >/dev/null || {
    printf '%s\n' 'Missing prerequisite: adb (required for --android-*).' >&2
    exit 69
  }
  if [[ -n "$android_avd" ]]; then
    local emulator_bin
    emulator_bin="$(find_emulator_binary)" || {
      printf '%s\n' 'Could not find the emulator binary. Set ANDROID_SDK_ROOT or ANDROID_HOME.' >&2
      exit 69
    }
    local running
    while read -r running; do
      [[ -z "$running" ]] && continue
      if [[ "$(adb -s "$running" shell getprop ro.boot.qemu.avd_name 2>/dev/null | tr -d '\r')" == "$android_avd" ]]; then
        printf 'AVD %s is already running as %s; use --android-serial %s instead.\n' \
          "$android_avd" "$running" "$running" >&2
        exit 69
      fi
    done < <(adb devices | awk 'NR > 1 && $2 == "device" {print $1}')

    emulator_log="$logs_dir/emulator.log"
    printf 'Launching AVD %s\n' "$android_avd" >&2
    "$emulator_bin" -avd "$android_avd" -no-snapshot-save -no-boot-anim \
      > "$emulator_log" 2>&1 &
    emulator_pid=$!
    launched_emulator=true

    local deadline=$((SECONDS + boot_timeout_seconds))
    while [[ -z "$android_serial" ]] && ((SECONDS < deadline)); do
      while read -r candidate; do
        [[ -z "$candidate" ]] && continue
        android_serial="$candidate"
        break
      done < <(adb devices | awk 'NR > 1 && $2 == "device" {print $1}')
      [[ -n "$android_serial" ]] && break
      if ! kill -0 "$emulator_pid" 2>/dev/null; then
        printf 'Emulator exited before registering; see %s\n' "$emulator_log" >&2
        exit 69
      fi
      sleep 2
    done
    [[ -n "$android_serial" ]] || {
      printf 'Timed out waiting for the AVD to register with adb.\n' >&2
      exit 69
    }
  fi
  if ! adb -s "$android_serial" get-state 2>/dev/null | grep -qx device; then
    printf 'Android device is not ready: %s\n' "$android_serial" >&2
    exit 69
  fi
  local deadline=$((SECONDS + boot_timeout_seconds))
  while ((SECONDS < deadline)); do
    if [[ "$(adb -s "$android_serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; then
      break
    fi
    sleep 2
  done
  # Make the host loopback relay reachable from the device without exposing it
  # beyond loopback.
  adb -s "$android_serial" reverse "tcp:$host_port" "tcp:$host_port" >/dev/null
  printf 'adb reverse configured on %s for port %s\n' "$android_serial" "$host_port" >&2
  {
    printf 'serial=%s\n' "$android_serial"
    printf 'avd=%s\n' "${android_avd:-<attached-device>}"
    printf 'model=%s\n' "$(adb -s "$android_serial" shell getprop ro.product.model 2>/dev/null | tr -d '\r')"
    printf 'sdk=%s\n' "$(adb -s "$android_serial" shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')"
    printf 'abi=%s\n' "$(adb -s "$android_serial" shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r')"
    printf 'runnerLaunchedDevice=%s\n' "$launched_emulator"
  } > "$provenance_dir/android-device.txt"
}

prepare_ios() {
  command -v xcrun >/dev/null || {
    printf '%s\n' 'Missing prerequisite: xcrun (required for --ios-*).' >&2
    exit 69
  }
  if [[ -n "$ios_simulator_name" ]]; then
    ios_device="$(xcrun simctl list devices available --json 2>/dev/null \
      | python3 -c 'import json,sys
name = sys.argv[1]
devices = json.load(sys.stdin)["devices"]
print(next((d["udid"] for group in devices.values() for d in group if d["name"] == name), ""))' "$ios_simulator_name")"
    [[ -n "$ios_device" ]] || {
      printf 'No available simulator named %s.\n' "$ios_simulator_name" >&2
      exit 69
    }
  fi
  # Reuse an already booted simulator; only boot (and therefore only shut down)
  # one this runner started.
  local already_booted=false
  if xcrun simctl list devices booted 2>/dev/null | grep -q "$ios_device"; then
    already_booted=true
  fi
  if [[ "$already_booted" != true ]]; then
    printf 'Booting simulator %s\n' "$ios_device" >&2
    xcrun simctl boot "$ios_device" >/dev/null 2>&1 || true
    booted_simulator_udid="$ios_device"
  fi
  xcrun simctl bootstatus "$ios_device" -b >/dev/null 2>&1 || true
  printf 'Using iOS simulator: %s\n' "$ios_device" >&2
  xcrun simctl list devices | grep "$ios_device" \
    > "$provenance_dir/ios-device.txt" 2>/dev/null || true
  printf 'runnerBootedSimulator=%s\n' \
    "$([[ "$already_booted" == true ]] && echo false || echo true)" \
    >> "$provenance_dir/ios-device.txt"
}

# ---------------------------------------------------------------------------
# Scenario execution
# ---------------------------------------------------------------------------

# Run one scenario once and record the verdict.
#
# $1 = platform (ios|android), $2 = scenario, $3 = attempt number
run_scenario() {
  local plat=$1 scen=$2 attempt=$3 device
  case "$plat" in
    ios) device="$ios_device" ;;
    android) device="$android_serial" ;;
  esac
  local label="${plat}-${scen}-${attempt}"
  local log_file="$logs_dir/${label}.log"
  local define_file="$provenance_dir/${label}-defines.txt"

  local define_args=()
  define_args+=("--dart-define=PRISM_TEST_RELAY_URL=http://localhost:$host_port")
  define_args+=("--dart-define=PRISM_RESUMABLE_SCENARIO=$scen")
  define_args+=("--dart-define=PRISM_TEST_RELAY_METRICS_TOKEN=$metrics_token")
  define_args+=("--dart-define=PRISM_RESUMABLE_SCREENSHOTS=true")
  for definition in ${extra_defines[@]+"${extra_defines[@]}"}; do
    define_args+=("--dart-define=$definition")
  done
  # Record the defines with the secret REDACTED; this file is evidence.
  printf '%s\n' ${define_args[@]+"${define_args[@]}"} \
    | sed "s/$metrics_token/<redacted-metrics-token>/g" > "$define_file"

  printf '\n=== [%s] %s (attempt %s) on %s ===\n' "$plat" "$scen" "$attempt" "$device" >&2
  # `flutter drive --profile` performs an AOT build, and Flutter refuses AOT for
  # an iOS *simulator* ("release/profile builds are only supported for physical
  # devices"). So the iOS simulator lane runs in debug mode while Android, whose
  # emulator does support profile builds, keeps `--profile`. The scenario and its
  # assertions are identical either way; only the compilation mode differs.
  local -a mode_args=(--profile)
  if [[ "$plat" == ios ]]; then
    mode_args=()
  fi
  set +e
  flutter drive ${mode_args[@]+"${mode_args[@]}"} --no-pub \
    --driver="$driver" \
    --target="$target" \
    -d "$device" \
    ${define_args[@]+"${define_args[@]}"} \
    2>&1 | tee "$log_file"
  local flutter_status=${PIPESTATUS[0]}
  set -e

  # Capture relay metrics and a screenshot on both outcomes.
  capture_metrics "$label"
  if [[ "$plat" == android ]]; then
    adb -s "$device" exec-out screencap -p \
      > "$screenshots_dir/${label}.png" 2>/dev/null || true
  else
    xcrun simctl io "$device" screenshot \
      "$screenshots_dir/${label}.png" >/dev/null 2>&1 || true
  fi

  # The harness emits its own structured verdict; `flutter drive` can exit 0
  # even when an integration test reports a failure, so both are required.
  local harness_ok=false
  if grep -q 'PRISM_RESUMABLE_HARNESS .*"event":"scenario_end".*"ok":true' "$log_file"; then
    harness_ok=true
  fi

  local status=passed
  if ((flutter_status != 0)) || [[ "$harness_ok" != true ]]; then
    status=failed
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$plat" "$scen" "$attempt" "$status" "$(basename "$log_file")" \
    >> "$output_root/scenario-results.tsv"
  if [[ "$status" == passed ]]; then
    printf '%s\n' "PASS: $label" >&2
    return 0
  fi
  printf 'FAIL: %s (flutter exit %s, harness ok marker: %s)\n' \
    "$label" "$flutter_status" "$harness_ok" >&2
  return 1
}

# Which relay mode each scenario needs.
relay_mode_for() {
  case "$1" in
    dark-fallback) printf 'dark' ;;
    *) printf 'resumable' ;;
  esac
}

run_platform() {
  local plat=$1 scenario mode current_mode="" failed=0
  for scenario in ${scenarios[@]+"${scenarios[@]}"}; do
    mode="$(relay_mode_for "$scenario")"
    if [[ "$mode" != "$current_mode" ]]; then
      # Each scenario family gets a fresh relay, so counters start clean. The
      # test also compares against a baseline, so a reused relay stays safe.
      start_relay "$mode" "$mode" || exit 69
      current_mode="$mode"
    fi
    local repetitions=1
    if [[ "$scenario" == cancel-mid-upload ]]; then
      repetitions="$cancel_repeats"
    fi
    local attempt=1
    while ((attempt <= repetitions)); do
      if ! run_scenario "$plat" "$scenario" "$attempt"; then
        failed=1
      fi
      attempt=$((attempt + 1))
    done
  done
  return "$failed"
}

# ---------------------------------------------------------------------------
# Preflight: relay-only
# ---------------------------------------------------------------------------

# Prove both relay shapes come up and advertise what the device test expects.
run_relay_only() {
  local failed=0
  start_relay resumable resumable || exit 69
  printf 'resumable relay /health: %s\n' "$(relay_curl /health)" >&2
  if grep -q '^prism_snapshot_upload_completions_total' "$metrics_dir/resumable-before.txt" 2>/dev/null; then
    printf '%s\n' 'resumable relay exposes the snapshot-upload metrics series' >&2
  else
    printf '%s\n' 'resumable relay did NOT expose the snapshot-upload metrics series' >&2
    failed=1
  fi
  start_relay dark dark || exit 69
  printf 'dark relay /health: %s\n' "$(relay_curl /health)" >&2
  if grep -q '^prism_snapshot_upload_completions_total' "$metrics_dir/dark-before.txt" 2>/dev/null; then
    printf '%s\n' 'dark relay exposes the metrics series (it is the same binary)' >&2
  else
    printf '%s\n' 'dark relay did NOT expose the metrics series' >&2
    failed=1
  fi
  stop_relay
  return "$failed"
}

# ---------------------------------------------------------------------------
# Matrix
# ---------------------------------------------------------------------------

[[ -f "$target" ]] || {
  printf 'Integration test target not found: %s\n' "$target" >&2
  exit 66
}
[[ -f "$driver" ]] || {
  printf 'Driver not found: %s\n' "$driver" >&2
  exit 66
}

if [[ "$relay_backend" == "process" ]]; then
  printf 'Relay backend: process binary %s (image build skipped)\n' \
    "$relay_binary" >&2
elif [[ "$skip_image_build" != true ]]; then
  printf 'Building relay image from %s ...\n' "$sync_dir" >&2
  container build \
    -f "$sync_dir/$containerfile" \
    -t "$container_image" \
    --progress plain \
    "$sync_dir" || {
      printf '%s\n' 'Relay image build failed.' >&2
      exit 69
    }
else
  printf 'Reusing existing image %s\n' "$container_image" >&2
fi

if [[ "$relay_only" == true ]]; then
  if ! run_relay_only; then
    printf '\nRelay preflight FAILED. Summary: %s\n' "$summary_path" >&2
    exit 65
  fi
  printf '\nRelay preflight passed. Summary: %s\n' "$summary_path"
  exit 0
fi

matrix_failed=0
if [[ -n "$ios_device" || -n "$ios_simulator_name" ]]; then
  platforms_csv="${platforms_csv:+$platforms_csv,}ios"
  prepare_ios
  run_platform ios || matrix_failed=1
fi
if [[ -n "$android_serial" || -n "$android_avd" ]]; then
  platforms_csv="${platforms_csv:+$platforms_csv,}android"
  prepare_android
  run_platform android || matrix_failed=1
fi

if ((matrix_failed != 0)); then
  printf '\nMatrix FAILED. Summary: %s\n' "$summary_path" >&2
  exit 65
fi

printf '\nMatrix passed. Summary: %s\n' "$summary_path"
