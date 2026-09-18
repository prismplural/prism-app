#!/usr/bin/env bash
#
# Local-only runner for the sync half-open recovery qualification.
#
# The qualification itself is
# integration_test/sync_resilience_qualification_test.dart: a real macOS sender
# and a real Android receiver pair through a localhost relay while a host-side
# fault proxy blackholes relay->receiver bytes on the receiver's already
# upgraded WebSocket, leaving the socket open. The receiver must retire the
# silent socket, open a replacement, and catch up on its own inside the gate,
# with no manual sync, no rebind, and no restart.
#
# This script wires up and tears down everything the two roles need:
#
#   1. a localhost relay (`prism-sync-relay --example test_relay`)
#   2. the localhost rendezvous controller, which also owns the fault proxy
#   3. a dedicated, wiped emulator for the Android receiver
#   4. adb reverse mappings for the relay, proxy, and controller ports
#   5. both `flutter test` processes, Android first, with identical defines
#   6. validation of the non-secret evidence both roles publish to the
#      controller (autonomous recovery, manual-sync-clean, sender convergence)
#
# Everything the script starts is stopped again from a single EXIT trap, so an
# interrupted or failing run does not leave a relay, proxy, emulator, or
# half-finished test behind. It only ever touches what it started: it removes
# exactly the three reverse mappings it installed and never kills unrelated
# devices or processes.
#
# The run uses `flutter test --no-pub`, so it never rewrites pubspec.lock or
# pubspec_overrides.yaml. Tracked files that change during the run are reported,
# never restored automatically.
#
# See --help for the configured values and the environment knobs.

set -euo pipefail

script_name=${0##*/}
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
app_root=$(cd "$script_dir/.." && pwd -P)

usage() {
  cat <<'USAGE'
Usage: scripts/run_sync_resilience_qualification.sh [--check] [--help]

Runs the local sync half-open recovery qualification in this checkout, starting
and stopping the relay, the controller/fault proxy, a dedicated emulator, and
both Flutter test processes. Local-only: it targets the host, one emulator, and
the macOS desktop device.

Options:
  --check   preflight only: resolve configuration, verify tools, ports, AVD,
            and checkout, print the resolved run parameters, then exit
  --help    print this help and exit

Exit status:
  0    qualification passed and every evidence check was clean
  1    the run finished but a test failed, timed out, or evidence was invalid
  2    configuration or prerequisite problem (tooling, ports, AVD, checkout)
  130  interrupted (SIGINT); 143 interrupted (SIGTERM). Cleanup still runs.

Environment (defaults in parentheses):
  PRISM_SYNC_DIR=DIR              prism-sync checkout owning the relay
                                  (resolved from PRISM_SYNC_DIR, else the
                                  checkout selected by flutter pub get, else a
                                  ../prism-sync sibling; must contain
                                  crates/prism-sync-relay)
  PRISM_QUAL_AVD=NAME             AVD to boot (Prism_Sync_Compat)
  PRISM_QUAL_EMULATOR_PORT=N      emulator console port; serial becomes
                                  emulator-N (5562)
  PRISM_QUAL_ANDROID_SERIAL=S     attach to an already-running emulator instead
                                  of booting one; must be an emulator (unset)
  PRISM_QUAL_RELAY_PORT=N         direct relay port (50225)
  PRISM_QUAL_CONTROLLER_PORT=N    controller rendezvous port (50230)
  PRISM_QUAL_PROXY_PORT=N         fault proxy port (50226)
  PRISM_QUAL_OUT_ROOT=DIR         log and report root
                                  (build/sync-resilience-qualification)
  PRISM_QUAL_RUN_ID=ID            fresh run id, [A-Za-z0-9_.-]+ (generated)
  PRISM_QUAL_CARGO_TARGET_DIR=DIR cargo target dir for the relay build
                                  (<out root>/cargo-target)
  PRISM_QUAL_SKIP_WIPE=1          boot the AVD without -wipe-data
  PRISM_QUAL_EMULATOR_HEADLESS=1  add -no-window when booting the AVD
  PRISM_QUAL_KEEP_EMULATOR=1      leave a script-started emulator booted
  PRISM_QUAL_BOOT_TIMEOUT=N       seconds to wait for sys.boot_completed (300)
  PRISM_QUAL_STARTUP_TIMEOUT=N    seconds to wait for relay/controller/receiver
                                  startup (600)
  PRISM_QUAL_TEST_TIMEOUT=N       seconds to wait for both tests (1500)
  PRISM_QUAL_SKIP_PREFLIGHT_PORTS=1
                                  do not fail when a port is already in use

Use a fresh run id per attempt; the relay is started with an in-memory database,
so relay state is also fresh per run.
USAGE
}

log() { printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"; }
warn() { printf '[%s] warning: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >&2; }

# Exit 2: the operator must change something before this can run.
die() {
  printf '%s: error: %s\n' "$script_name" "$*" >&2
  exit 2
}

# Exit 1: the run itself did not qualify.
fail_run() {
  printf '%s: qualification failed: %s\n' "$script_name" "$*" >&2
  exit 1
}

check_only=0
while (($# > 0)); do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --check)
      check_only=1
      ;;
    *)
      printf '%s: unknown argument: %s\n' "$script_name" "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

# ── Configuration ──────────────────────────────────────────────────────────

require_port() {
  local name=$1 value=$2
  [[ $value =~ ^[0-9]+$ ]] || die "$name must be a TCP port number (got: $value)"
  if ((value < 1 || value > 65535)); then
    die "$name must be between 1 and 65535 (got: $value)"
  fi
}

require_positive_int() {
  local name=$1 value=$2
  [[ $value =~ ^[0-9]+$ ]] || die "$name must be a positive integer (got: $value)"
  if ((value < 1)); then
    die "$name must be a positive integer (got: $value)"
  fi
}

avd_name=${PRISM_QUAL_AVD:-Prism_Sync_Compat}
emulator_port=${PRISM_QUAL_EMULATOR_PORT:-5562}
relay_port=${PRISM_QUAL_RELAY_PORT:-50225}
controller_port=${PRISM_QUAL_CONTROLLER_PORT:-50230}
proxy_port=${PRISM_QUAL_PROXY_PORT:-50226}
boot_timeout=${PRISM_QUAL_BOOT_TIMEOUT:-300}
startup_timeout=${PRISM_QUAL_STARTUP_TIMEOUT:-600}
test_timeout=${PRISM_QUAL_TEST_TIMEOUT:-1500}
android_serial_override=${PRISM_QUAL_ANDROID_SERIAL:-}

require_port PRISM_QUAL_RELAY_PORT "$relay_port"
require_port PRISM_QUAL_CONTROLLER_PORT "$controller_port"
require_port PRISM_QUAL_PROXY_PORT "$proxy_port"
require_port PRISM_QUAL_EMULATOR_PORT "$emulator_port"
require_positive_int PRISM_QUAL_BOOT_TIMEOUT "$boot_timeout"
require_positive_int PRISM_QUAL_STARTUP_TIMEOUT "$startup_timeout"
require_positive_int PRISM_QUAL_TEST_TIMEOUT "$test_timeout"

if [[ $relay_port == "$controller_port" || $relay_port == "$proxy_port" || $controller_port == "$proxy_port" ]]; then
  die 'relay, controller, and fault-proxy ports must be distinct'
fi

run_id=${PRISM_QUAL_RUN_ID:-syncqual-$(date -u '+%Y%m%dT%H%M%SZ')-$$}
if [[ ! $run_id =~ ^[A-Za-z0-9_.-]+$ ]]; then
  die "PRISM_QUAL_RUN_ID must match [A-Za-z0-9_.-]+ (got: $run_id)"
fi

out_root=${PRISM_QUAL_OUT_ROOT:-$app_root/build/sync-resilience-qualification}
out_dir=$out_root/$run_id
evidence_dir=$out_dir/evidence
report_path=$out_dir/report.json
cargo_target=${PRISM_QUAL_CARGO_TARGET_DIR:-$out_root/cargo-target}
test_file=integration_test/sync_resilience_qualification_test.dart
controller_script=scripts/sync_resilience_qualification_controller.py

# ── Cleanup state ──────────────────────────────────────────────────────────

relay_pid=''
relay_bin=''
controller_pid=''
emulator_pid=''
emulator_owned=''
emulator_bin=''
android_serial=''
reverses_installed=''
android_test_pid=''
macos_test_pid=''
finalized=''

kill_tree() {
  local pid=$1 signal=${2:-TERM} child
  [[ -n $pid ]] || return 0
  if command -v pgrep >/dev/null 2>&1; then
    while read -r child; do
      if [[ -n $child ]]; then
        kill_tree "$child" "$signal"
      fi
    done < <(pgrep -P "$pid" 2>/dev/null || true)
  fi
  kill -s "$signal" "$pid" 2>/dev/null || true
}

stop_process() {
  local pid=$1 label=$2 waited=0
  [[ -n $pid ]] || return 0
  if ! kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  log "stopping $label (pid $pid)"
  kill_tree "$pid" TERM
  while kill -0 "$pid" 2>/dev/null && ((waited < 15)); do
    sleep 1
    waited=$((waited + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    warn "$label (pid $pid) ignored SIGTERM; sending SIGKILL"
    kill_tree "$pid" KILL
  fi
}

# shellcheck disable=SC2329  # invoked from the EXIT trap below
remove_reverses() {
  local port
  [[ -n $android_serial && -n $reverses_installed ]] || return 0
  for port in "$relay_port" "$proxy_port" "$controller_port"; do
    adb -s "$android_serial" reverse --remove "tcp:$port" >/dev/null 2>&1 || true
  done
}

# shellcheck disable=SC2329  # invoked from on_exit
stop_emulator() {
  local waited=0
  [[ -n $emulator_owned && -n $android_serial ]] || return 0
  if [[ ${PRISM_QUAL_KEEP_EMULATOR:-0} == 1 ]]; then
    log "leaving emulator $android_serial booted (PRISM_QUAL_KEEP_EMULATOR=1)"
    return 0
  fi
  log "shutting down emulator $android_serial"
  adb -s "$android_serial" emu kill >/dev/null 2>&1 || true
  while ((waited < 30)) && adb -s "$android_serial" get-state >/dev/null 2>&1; do
    sleep 1
    waited=$((waited + 1))
  done
  stop_process "$emulator_pid" 'owned emulator'
}

# shellcheck disable=SC2329  # registered as the EXIT/INT/TERM handler
on_exit() {
  local code=$?
  if [[ -n $finalized ]]; then
    return 0
  fi
  finalized=1
  trap - EXIT INT TERM HUP
  set +e
  stop_process "$macos_test_pid" 'macOS sender test'
  stop_process "$android_test_pid" 'Android receiver test'
  remove_reverses
  if [[ -n $controller_pid ]] && kill -0 "$controller_pid" 2>/dev/null; then
    # Best effort: never leave the blackhole armed if a test was killed.
    curl -sS -X POST --max-time 5 "http://localhost:$controller_port/fault/clear" >/dev/null 2>&1
  fi
  stop_process "$controller_pid" 'controller/fault proxy'
  stop_process "$relay_pid" 'test relay'
  stop_emulator
  exit "$code"
}

trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ── Helpers ────────────────────────────────────────────────────────────────

resolve_emulator() {
  local candidate
  if candidate=$(command -v emulator 2>/dev/null) && [[ -x $candidate ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  for candidate in "${ANDROID_HOME:-}/emulator/emulator" "${ANDROID_SDK_ROOT:-}/emulator/emulator"; do
    if [[ -x $candidate ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

# The prism-sync checkout selected by `flutter pub get`, if that choice is
# visible in the package config and resolves inside a Git checkout.
package_config_sync_dir() {
  python3 - "$app_root/.dart_tool/package_config.json" <<'PY'
import json
import os
import subprocess
import sys

path = sys.argv[1]
try:
    with open(path) as handle:
        config = json.load(handle)
except (OSError, ValueError):
    sys.exit(0)

root = None
for package in config.get("packages", []):
    if package.get("name") == "prism_sync":
        root = package.get("rootUri")
        break
if not root or "%" in root:
    sys.exit(0)
if root.startswith("file://"):
    root = root[len("file://") :]
else:
    root = os.path.join(os.path.dirname(path), root)
root = os.path.realpath(root)
try:
    toplevel = subprocess.run(
        ["git", "-C", root, "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
except (OSError, subprocess.CalledProcessError):
    sys.exit(0)
if toplevel:
    print(toplevel)
PY
}

resolve_sync_dir() {
  local candidate resolved=''
  if [[ -n ${PRISM_SYNC_DIR:-} ]]; then
    [[ -d $PRISM_SYNC_DIR ]] || die "PRISM_SYNC_DIR is not a directory: $PRISM_SYNC_DIR"
    resolved=$(cd "$PRISM_SYNC_DIR" && pwd -P)
  else
    candidate=$(package_config_sync_dir || true)
    if [[ -n $candidate && -d $candidate && -f $candidate/Cargo.toml ]]; then
      resolved=$candidate
    elif [[ -d $app_root/../prism-sync && -f $app_root/../prism-sync/Cargo.toml ]]; then
      resolved=$(cd "$app_root/../prism-sync" && pwd -P)
    fi
  fi
  if [[ -z $resolved ]]; then
    die 'could not locate a prism-sync checkout. Set PRISM_SYNC_DIR=/path/to/prism-sync, or keep a sibling checkout at ../prism-sync next to this repository.'
  fi
  if [[ ! -f $resolved/crates/prism-sync-relay/Cargo.toml ]]; then
    die "not a prism-sync checkout (missing crates/prism-sync-relay/Cargo.toml): $resolved"
  fi
  printf '%s\n' "$resolved"
}

check_ports_free() {
  [[ ${PRISM_QUAL_SKIP_PREFLIGHT_PORTS:-0} == 1 ]] && return 0
  python3 - "$relay_port" "$controller_port" "$proxy_port" <<'PY'
import socket
import sys

busy = []
for raw in sys.argv[1:]:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(("127.0.0.1", int(raw)))
    except OSError:
        busy.append(raw)
    finally:
        sock.close()
if busy:
    print("127.0.0.1 ports already in use: " + ", ".join(busy), file=sys.stderr)
    sys.exit(2)
PY
}

# Wait for a marker line in a log file, failing fast if the process died.
wait_for_marker() {
  local file=$1 pattern=$2 timeout=$3 label=$4 pid=${5:-}
  local deadline=$((SECONDS + timeout))
  while :; do
    if grep -q -- "$pattern" "$file" 2>/dev/null; then
      return 0
    fi
    if [[ -n $pid ]] && ! kill -0 "$pid" 2>/dev/null; then
      warn "$label exited before reporting $pattern"
      return 1
    fi
    if ((SECONDS >= deadline)); then
      return 1
    fi
    sleep 1
  done
}

kv_url() {
  printf 'http://localhost:%s/kv/%s/%s' "$controller_port" "$run_id" "$1"
}

# Print the stored JSON value for a controller key; non-zero when unset.
kv_get() {
  local key=$1 tmp status
  tmp=$(mktemp "${TMPDIR:-/tmp}/prism-qual-kv.XXXXXX")
  status=$(curl -sS --max-time 15 -o "$tmp" -w '%{http_code}' "$(kv_url "$key")" 2>/dev/null || printf '000')
  if [[ $status == 200 ]]; then
    cat "$tmp"
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# Poll a controller key, failing fast if the producing process died.
kv_wait() {
  local key=$1 timeout=$2 pid=${3:-}
  local label=${4:-$key}
  local deadline=$((SECONDS + timeout))
  while :; do
    if kv_get "$key" >/dev/null 2>&1; then
      return 0
    fi
    if [[ -n $pid ]] && ! kill -0 "$pid" 2>/dev/null; then
      warn "$label exited before publishing controller key $key"
      return 1
    fi
    if ((SECONDS >= deadline)); then
      warn "timed out after ${timeout}s waiting for controller key $key"
      return 1
    fi
    sleep 2
  done
}

tail_log() {
  local file=$1
  if [[ -s $file ]]; then
    printf '%s: last lines of %s\n' "$script_name" "$file" >&2
    tail -n 20 "$file" >&2 || true
  fi
}

snapshot_git_status() {
  local dest=$1
  if git -C "$app_root" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$app_root" status --porcelain >"$dest" 2>/dev/null || true
  fi
}

# ── Preflight ──────────────────────────────────────────────────────────────

[[ $(uname -s) == Darwin ]] || die 'the qualification needs a macOS sender device; run it on macOS'

for tool in flutter adb cargo python3 curl mktemp git; do
  command -v "$tool" >/dev/null 2>&1 || die "missing required command: $tool"
done

if [[ -z $android_serial_override ]]; then
  emulator_bin=$(resolve_emulator) || die "could not find the Android emulator binary. Put 'emulator' on PATH or set ANDROID_HOME/ANDROID_SDK_ROOT."
fi

[[ -f $app_root/$test_file ]] || die "missing qualification test: $test_file"
[[ -f $app_root/$controller_script ]] || die "missing qualification controller: $controller_script"

if [[ ! -f $app_root/.dart_tool/package_config.json ]]; then
  die "run 'flutter pub get' in this checkout first; the runner uses 'flutter test --no-pub' and never rewrites pubspec.lock itself"
fi

sync_dir=$(resolve_sync_dir)
resolved_pub_sync=$(package_config_sync_dir || true)

if [[ -n $android_serial_override ]]; then
  android_serial=$android_serial_override
else
  android_serial=emulator-$emulator_port
  if ! "$emulator_bin" -list-avds 2>/dev/null | grep -Fx -- "$avd_name" >/dev/null; then
    warn "AVD not found: $avd_name. Available AVDs:"
    "$emulator_bin" -list-avds >&2 || true
    die "create the AVD or set PRISM_QUAL_AVD to one of the names above"
  fi
fi

if ! check_ports_free; then
  die "ports ${relay_port}/${controller_port}/${proxy_port} are not all free. Stop the stale processes or choose other ports with PRISM_QUAL_RELAY_PORT / PRISM_QUAL_CONTROLLER_PORT / PRISM_QUAL_PROXY_PORT."
fi

printf '%s resolved configuration\n' "$script_name"
printf '  app checkout:      %s\n' "$app_root"
printf '  prism-sync:        %s\n' "$sync_dir"
printf '  run id:            %s\n' "$run_id"
printf '  relay port:        %s\n' "$relay_port"
printf '  controller port:   %s\n' "$controller_port"
printf '  fault proxy port:  %s\n' "$proxy_port"
if [[ -n $android_serial_override ]]; then
  printf '  android target:    %s (attached; the runner will not start or stop it)\n' "$android_serial"
else
  printf '  android target:    %s from AVD %s\n' "$android_serial" "$avd_name"
fi
printf '  output directory:  %s\n' "$out_dir"
if [[ -n $resolved_pub_sync && $resolved_pub_sync != "$sync_dir" ]]; then
  warn "the app currently links prism_sync from $resolved_pub_sync, but the relay will be built from $sync_dir. Point a gitignored pubspec_overrides.yaml at the same checkout and re-run \`flutter pub get\` if that mismatch is not intended."
fi

if [[ $check_only == 1 ]]; then
  printf '%s preflight OK\n' "$script_name"
  exit 0
fi

# ── Run ────────────────────────────────────────────────────────────────────

mkdir -p "$out_dir" "$evidence_dir" "$cargo_target"
: >"$out_dir/run.log"
snapshot_git_status "$out_dir/git-status-before.txt"
started_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

log 'building the local test relay'
if ! cargo build \
  --manifest-path "$sync_dir/Cargo.toml" \
  -p prism-sync-relay \
  --example test_relay \
  --target-dir "$cargo_target" >"$out_dir/relay-build.log" 2>&1; then
  tail_log "$out_dir/relay-build.log"
  fail_run "the test relay did not build; see $out_dir/relay-build.log"
fi
relay_bin=$cargo_target/debug/examples/test_relay
[[ -x $relay_bin ]] || fail_run "relay binary missing after build: $relay_bin"

log "starting the test relay on port $relay_port"
env -u TEST_RELAY_DB TEST_RELAY_PORT="$relay_port" "$relay_bin" >"$out_dir/relay.log" 2>&1 &
relay_pid=$!
if ! wait_for_marker "$out_dir/relay.log" '^RELAY_URL=' "$startup_timeout" 'test relay' "$relay_pid"; then
  tail_log "$out_dir/relay.log"
  die "the test relay did not start within ${startup_timeout}s; see $out_dir/relay.log"
fi

log "starting the controller and fault proxy on ports $controller_port/$proxy_port"
python3 "$app_root/$controller_script" \
  --relay "http://localhost:$relay_port" \
  --port "$controller_port" \
  --proxy-port "$proxy_port" \
  >"$out_dir/controller.log" 2>&1 &
controller_pid=$!
if ! wait_for_marker "$out_dir/controller.log" 'CONTROLLER_URL=' "$startup_timeout" 'controller' "$controller_pid"; then
  tail_log "$out_dir/controller.log"
  die "the controller did not start within ${startup_timeout}s; see $out_dir/controller.log"
fi
if ! curl -fsS --max-time 10 "http://localhost:$controller_port/health" >/dev/null; then
  tail_log "$out_dir/controller.log"
  die 'the controller health endpoint did not answer'
fi

if [[ -n $android_serial_override ]]; then
  log "attaching to the already-running Android target $android_serial"
else
  emulator_args=(-avd "$avd_name" -port "$emulator_port" -no-snapshot-save -no-boot-anim)
  if [[ ${PRISM_QUAL_SKIP_WIPE:-0} != 1 ]]; then
    emulator_args+=(-wipe-data)
  fi
  if [[ ${PRISM_QUAL_EMULATOR_HEADLESS:-0} == 1 ]]; then
    emulator_args+=(-no-window)
  fi
  log "starting emulator $avd_name on port $emulator_port"
  "$emulator_bin" "${emulator_args[@]}" >"$out_dir/emulator.log" 2>&1 &
  emulator_pid=$!
  emulator_owned=1
fi

adb start-server >/dev/null 2>&1 || true

log "waiting for $android_serial to finish booting"
boot_deadline=$((SECONDS + boot_timeout))
while :; do
  if [[ $(adb -s "$android_serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r') == 1 ]]; then
    break
  fi
  if ((SECONDS >= boot_deadline)); then
    tail_log "$out_dir/emulator.log"
    die "$android_serial did not report sys.boot_completed within ${boot_timeout}s"
  fi
  sleep 3
done

if [[ $android_serial != emulator-* ]]; then
  if [[ $(adb -s "$android_serial" shell getprop ro.kernel.qemu 2>/dev/null | tr -d '\r') != 1 ]]; then
    die "refusing to run against a non-emulator Android target: $android_serial"
  fi
fi

log "installing adb reverse for $relay_port (relay), $proxy_port (fault proxy), $controller_port (controller)"
for port in "$relay_port" "$proxy_port" "$controller_port"; do
  adb -s "$android_serial" reverse "tcp:$port" "tcp:$port" >/dev/null
done
reverses_installed=1

defines=(
  "--dart-define=PRISM_RESILIENCE_RUN_ID=$run_id"
  "--dart-define=PRISM_RESILIENCE_CONTROLLER=http://localhost:$controller_port"
  "--dart-define=PRISM_RESILIENCE_RELAY=http://localhost:$relay_port"
  "--dart-define=PRISM_RESILIENCE_PROXY=http://localhost:$proxy_port"
)

# The role is derived from the native platform inside the test, so both devices
# compile with identical defines and cannot overwrite a shared artifact with the
# peer's role.
log "launching the Android receiver test first on $android_serial"
(
  cd "$app_root" && exec flutter test "$test_file" -d "$android_serial" --no-pub "${defines[@]}"
) >"$out_dir/android-test.log" 2>&1 &
android_test_pid=$!

log 'waiting for the receiver to report runtime-started before launching the sender'
if ! kv_wait 'android_receiver/runtime-started' "$startup_timeout" "$android_test_pid" 'Android receiver test'; then
  tail_log "$out_dir/android-test.log"
  fail_run "the Android receiver never reached its runtime-started barrier; see $out_dir/android-test.log"
fi

log 'launching the macOS sender test'
(
  cd "$app_root" && exec flutter test "$test_file" -d macos --no-pub "${defines[@]}"
) >"$out_dir/macos-test.log" 2>&1 &
macos_test_pid=$!

log "waiting up to ${test_timeout}s for both tests"
timed_out=''
wait_deadline=$((SECONDS + test_timeout))
while :; do
  alive=0
  for pid in "$android_test_pid" "$macos_test_pid"; do
    if kill -0 "$pid" 2>/dev/null; then
      alive=1
    fi
  done
  if ((alive == 0)); then
    break
  fi
  if ((SECONDS >= wait_deadline)); then
    timed_out=1
    break
  fi
  sleep 5
done

if [[ -n $timed_out ]]; then
  warn "both tests did not finish within ${test_timeout}s; stopping them"
  stop_process "$macos_test_pid" 'macOS sender test'
  stop_process "$android_test_pid" 'Android receiver test'
fi

android_status=0
wait "$android_test_pid" || android_status=$?
macos_status=0
wait "$macos_test_pid" || macos_status=$?

log "android receiver test exit status: $android_status"
log "macOS sender test exit status: $macos_status"
if ((android_status != 0)); then
  tail_log "$out_dir/android-test.log"
fi
if ((macos_status != 0)); then
  tail_log "$out_dir/macos-test.log"
fi

# ── Evidence ───────────────────────────────────────────────────────────────

log 'collecting non-secret evidence from the controller'
evidence_keys=(
  'mac_sender/runtime-started'
  'android_receiver/runtime-started'
  'mac/fronts-established'
  'android/fronts-observed'
  'mac/profile-changed'
  'android/recovered'
  'android/manual-sync-clean'
  'evidence/mac_sender/complete'
  'evidence/android_receiver/complete'
  'evidence/android_receiver/pre-fault-fronts'
  'evidence/android_receiver/fault-active'
  'evidence/android_receiver/autonomous-recovery'
  'evidence/android_receiver/manual-sync-clean'
  'evidence/mac_sender/sender-converged'
)
for key in "${evidence_keys[@]}"; do
  evidence_file=$evidence_dir/${key//\//__}.json
  if ! kv_get "$key" >"$evidence_file" 2>/dev/null; then
    warn "controller key never published: $key"
  fi
done

context_json=$(python3 -c 'import json, sys; print(json.dumps(dict(zip(sys.argv[1::2], sys.argv[2::2]))))' \
  run_id "$run_id" \
  avd "$avd_name" \
  android_target "$android_serial" \
  relay_port "$relay_port" \
  controller_port "$controller_port" \
  proxy_port "$proxy_port" \
  sync_dir "$sync_dir" \
  out_dir "$out_dir" \
  test_file "$test_file" \
  android_exit "$android_status" \
  macos_exit "$macos_status" \
  timed_out "${timed_out:-0}")

finished_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

log 'validating evidence'
validation_failed=''
python3 - "$evidence_dir" "$report_path" "$run_id" "$started_at" "$finished_at" "$context_json" <<'PY' || validation_failed=1
import json
import os
import sys

evidence_dir, report_path, run_id, started_at, finished_at, context_raw = sys.argv[1:7]
context = json.loads(context_raw)

# Keys that must never reach an evidence record on disk or on the terminal.
FORBIDDEN_KEY_PARTS = ("token", "password", "mnemonic", "session", "secret", "dek")

RECOVERY_BUDGET_MS = 110_000


def load(key):
    path = os.path.join(evidence_dir, key.replace("/", "__") + ".json")
    if not os.path.exists(path):
        return None
    try:
        with open(path) as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def assertions(key):
    value = load(key)
    if not isinstance(value, dict):
        return {}
    inner = value.get("assertions")
    return inner if isinstance(inner, dict) else {}


def as_int(value):
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    try:
        return int(str(value))
    except (TypeError, ValueError):
        return 0


checks = []


def check(name, ok, detail):
    checks.append({"name": name, "ok": bool(ok), "detail": str(detail)})


# Both roles must have launched natively and reached the end of the protocol.
for role, platform in (("mac_sender", "macos"), ("android_receiver", "android")):
    launched = load(role + "/runtime-started")
    check(
        role + "-runtime-started",
        isinstance(launched, dict) and launched.get("platform") == platform,
        "platform=" + str(launched.get("platform") if isinstance(launched, dict) else None),
    )
    complete = assertions("evidence/" + role + "/complete")
    check(
        role + "-complete",
        complete.get("passed") is True,
        "passed=" + str(complete.get("passed")),
    )

pre_fault = assertions("evidence/android_receiver/pre-fault-fronts")
check(
    "pre-fault-three-fronts",
    pre_fault.get("exactly_three_fronts") is True
    and as_int(pre_fault.get("active_front_count")) == 3,
    "exactly_three_fronts=%s active_front_count=%s"
    % (pre_fault.get("exactly_three_fronts"), pre_fault.get("active_front_count")),
)

fault = assertions("evidence/android_receiver/fault-active")
check(
    "fault-armed",
    fault.get("proxy_armed") is True and as_int(fault.get("upgraded_total_at_arm")) > 0,
    "proxy_armed=%s upgraded_total_at_arm=%s"
    % (fault.get("proxy_armed"), fault.get("upgraded_total_at_arm")),
)

recovery = assertions("evidence/android_receiver/autonomous-recovery")
elapsed_ms = as_int(recovery.get("elapsed_ms"))
check(
    "recovery-within-gate",
    recovery.get("within_110s") is True and 0 < elapsed_ms <= RECOVERY_BUDGET_MS,
    "within_110s=%s elapsed_ms=%s" % (recovery.get("within_110s"), recovery.get("elapsed_ms")),
)
check(
    "recovery-opened-replacement-socket",
    recovery.get("replacement_socket_opened") is True
    and as_int(recovery.get("upgraded_total_after")) > as_int(recovery.get("upgraded_total_at_arm")),
    "replacement_socket_opened=%s upgraded_total %s -> %s"
    % (
        recovery.get("replacement_socket_opened"),
        recovery.get("upgraded_total_at_arm"),
        recovery.get("upgraded_total_after"),
    ),
)
check(
    "recovery-kept-same-three-fronts",
    recovery.get("same_three_fronts") is True and as_int(recovery.get("active_front_count")) == 3,
    "same_three_fronts=%s active_front_count=%s"
    % (recovery.get("same_three_fronts"), recovery.get("active_front_count")),
)
check(
    "recovery-observed-profile-change",
    recovery.get("profile_change_observed") is True,
    "profile_change_observed=" + str(recovery.get("profile_change_observed")),
)
check(
    "recovery-without-manual-sync",
    recovery.get("manual_sync_used_for_recovery") is False,
    "manual_sync_used_for_recovery=" + str(recovery.get("manual_sync_used_for_recovery")),
)
check(
    "fault-suppressed-and-then-forwarded-bytes",
    as_int(recovery.get("blackholed_bytes")) > 0
    and as_int(recovery.get("forwarded_bytes_after_arm")) > 0,
    "blackholed_bytes=%s forwarded_bytes_after_arm=%s"
    % (recovery.get("blackholed_bytes"), recovery.get("forwarded_bytes_after_arm")),
)

recovered = load("android/recovered")
recovered = recovered if isinstance(recovered, dict) else {}
check(
    "receiver-recovery-report",
    recovered.get("profile_observed") is True
    and as_int(recovered.get("active_front_count")) == 3
    and 0 < as_int(recovered.get("elapsed_ms")) <= RECOVERY_BUDGET_MS,
    "profile_observed=%s active_front_count=%s elapsed_ms=%s"
    % (
        recovered.get("profile_observed"),
        recovered.get("active_front_count"),
        recovered.get("elapsed_ms"),
    ),
)

manual = assertions("evidence/android_receiver/manual-sync-clean")
check(
    "manual-sync-clean",
    as_int(manual.get("merged")) == 0
    and as_int(manual.get("pulled")) == 0
    and as_int(manual.get("pushed")) == 0,
    "merged=%s pulled=%s pushed=%s"
    % (manual.get("merged"), manual.get("pulled"), manual.get("pushed")),
)
check(
    "fault-cleared-after-recovery",
    manual.get("proxy_cleared") is True,
    "proxy_cleared=" + str(manual.get("proxy_cleared")),
)

sender = assertions("evidence/mac_sender/sender-converged")
check(
    "sender-converged",
    sender.get("sender_engine_name_matches") is True
    and as_int(sender.get("sender_pending_ops")) == 0,
    "sender_engine_name_matches=%s sender_pending_ops=%s"
    % (sender.get("sender_engine_name_matches"), sender.get("sender_pending_ops")),
)


def secret_paths(value, path):
    if isinstance(value, dict):
        for key, item in value.items():
            child = path + "." + str(key)
            if any(part in str(key).lower() for part in FORBIDDEN_KEY_PARTS):
                yield child
            yield from secret_paths(item, child)
    elif isinstance(value, list):
        for index, item in enumerate(value):
            yield from secret_paths(item, path + "[%d]" % index)


evidence = {}
leaked = []
if os.path.isdir(evidence_dir):
    entries = sorted(os.listdir(evidence_dir))
else:
    entries = []
for entry in entries:
    if not entry.endswith(".json"):
        continue
    name = entry[: -len(".json")]
    try:
        with open(os.path.join(evidence_dir, entry)) as handle:
            value = json.load(handle)
    except (OSError, ValueError):
        continue
    evidence[name] = value
    leaked.extend(secret_paths(value, name))

check(
    "no-secret-shaped-evidence",
    not leaked,
    "offending keys=" + (", ".join(leaked) if leaked else "none"),
)

failed = [item for item in checks if not item["ok"]]
report = {
    "run_id": run_id,
    "status": "passed" if not failed else "failed",
    "exit_code": 0 if not failed else 1,
    "started_at": started_at,
    "finished_at": finished_at,
    "context": context,
    "checks": checks,
    "summary": "%d/%d checks passed" % (len(checks) - len(failed), len(checks)),
    "evidence": evidence,
}

with open(report_path, "w") as handle:
    json.dump(report, handle, indent=2, sort_keys=True)
    handle.write("\n")

for item in checks:
    print("%s %s: %s" % ("PASS" if item["ok"] else "FAIL", item["name"], item["detail"]))
print("evidence checks: %d/%d passed" % (len(checks) - len(failed), len(checks)))
sys.exit(0 if not failed else 1)
PY

snapshot_git_status "$out_dir/git-status-after.txt"
added=$(comm -13 <(sort "$out_dir/git-status-before.txt") <(sort "$out_dir/git-status-after.txt") 2>/dev/null || true)
if [[ -n $added ]]; then
  warn 'tracked files changed during the run (nothing was restored automatically):'
  printf '%s\n' "$added" >&2
fi

ln -sfn "$out_dir" "$out_root/latest" 2>/dev/null || true

printf '\n%s summary\n' "$script_name"
printf '  run id:            %s\n' "$run_id"
printf '  output directory:  %s\n' "$out_dir"
printf '  report:            %s\n' "$report_path"
printf '  android test exit: %s\n' "$android_status"
printf '  macOS test exit:   %s\n' "$macos_status"

if [[ -n $timed_out ]]; then
  printf '  result:            FAIL (tests timed out)\n'
  fail_run 'the tests did not finish inside the configured timeout'
fi
if ((android_status != 0)) || ((macos_status != 0)); then
  printf '  result:            FAIL\n'
  fail_run "a device test failed (see $out_dir/android-test.log and $out_dir/macos-test.log)"
fi
if [[ -n $validation_failed ]]; then
  printf '  result:            FAIL (evidence invalid)\n'
  fail_run "evidence validation failed; see $report_path"
fi

printf '  result:            PASS\n'
log 'qualification passed'
exit 0
