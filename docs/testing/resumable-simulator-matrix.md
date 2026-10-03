# Resumable pairing simulator/emulator matrix

`tool/run_resumable_simulator_matrix.sh` runs the device-lane harness for the
**split resumable pairing** surface on an iOS simulator and/or an Android
emulator, against a disposable relay started by the runner.

The test itself is `integration_test/resumable_split_pairing_device_test.dart`.
It drives the real generated FFI against the real Rust core; the runner only
supplies the relay, the device, and the environment.

## What the matrix proves

| Scenario             | Relay mode | Asserted outcome                                                              |
| -------------------- | ---------- | ----------------------------------------------------------------------------- |
| `happy-resumable`    | resumable  | resumable transport, lease v1 active, >1 accepted chunk, exact snapshot hash   |
| `dark-fallback`      | dark       | single-`PUT` downgrade, no lease, still completes, exact snapshot hash         |
| `cancel-mid-upload`  | resumable  | one accepted chunk then abort, no completion, no credential release, upload fails |

Per platform the matrix runs `happy-resumable` once, `dark-fallback` once, and
`cancel-mid-upload` three times. Cancellation is repeated on purpose: a mid-flight
abort is timing-sensitive, so three runs make a one-off pass visibly weaker than
a stable one in `scenario-results.tsv`.

Each scenario has its own relay, so counters start clean. The test additionally
compares every metric against a baseline it captures before the scenario, so a
reused relay cannot make a stale counter look like success.

## Requirements

- Apple `container` CLI (checked first; see *Relay backend* below for the
  documented fallback).
- `flutter`, `dart`, `adb`, `xcrun`, `python3`, `git`, `curl`, `jq`.
- A prism-app checkout whose `prism_sync`, `prism_sync_drift`, and
  `prism_sync_flutter` packages all resolve inside the **same** prism-sync Git
  worktree. `flutter pub get` must have run against that worktree.

### Apple `container` CLI syntax this runner relies on

Verified against `container` 1.0.0:

```bash
container build -f <Containerfile> -t <tag> --progress plain <context-dir>
container run -d --name <name> \
  --mount type=bind,source=<host>,target=<container> \
  --publish 127.0.0.1:<host-port>:<container-port> \
  -e KEY=VALUE <image>
```

`--mount type=bind,...` is preferred over `-v` because it states the mount type
explicitly. The runner refuses to continue if the installed CLI does not
document these flags.

## Relay backend

### Container (primary)

The relay image is built **from the feature prism-sync worktree**, never from
the base checkout, using `prism-sync/Containerfile.test-relay`.

That Containerfile exists as a test-only sibling of the production `Dockerfile`
because the production file builds in `rust:1.93-slim` (a trixie-based image)
and runs in `debian:bookworm-slim`. A binary linked against trixie's glibc can
fail to load against bookworm's older glibc — a silent, environment-shaped
failure for a harness whose entire purpose is to be trustworthy. Both stages in
the test Containerfile are pinned to **bookworm**. The production `Dockerfile`
is deliberately left untouched.

### Process fallback (documented)

If the container runtime is unavailable, `--relay-binary PATH` runs a pre-built
production relay binary directly and skips the image build:

```bash
(cd <prism-sync worktree> && cargo build -p prism-sync-relay)
tool/run_resumable_simulator_matrix.sh \
  --relay-binary <prism-sync worktree>/target/debug/prism-sync-relay \
  --ios-device <UDID>
```

Both backends receive the **same explicit flag set**, and both write relay logs
into the evidence bundle. Do not substitute the `test_relay` example binary: it
is a separate build target and a stale copy silently produces a dark relay.

### Relay flags the runner sets explicitly

Resumable relay:

```text
SNAPSHOT_FILE_BACKING_ENABLED=true      # refuse startup rather than silently downgrade
SNAPSHOT_UPLOAD_ENABLED=true            # the capability itself
PAIRING_LEASE_ENABLED=true              # lease v1
SNAPSHOT_UPLOAD_GLOBAL_RESERVED_BYTES / _GROUP_ / _FREE_SPACE_RESERVE_BYTES
SNAPSHOT_UPLOAD_CREATE_RATE_LIMIT=10000
PAIRING_SESSION_TTL_SECS=1800, PAIRING_SESSION_RATE_LIMIT=1000,
NONCE_RATE_LIMIT=1000, WS_UPGRADE_RATE_LIMIT=1000
```

Dark relay: `SNAPSHOT_UPLOAD_ENABLED=false`, `PAIRING_LEASE_ENABLED=false` —
the shipped defaults, i.e. what an old or not-yet-enabled deployment looks like.

Both relays also get a random `METRICS_TOKEN` and `REGISTRATION_TOKEN=OPEN`. The
registration token matters: the production relay auto-generates one and rejects
client registration unless it is explicitly open.

## Device reachability

Only `http://localhost:<port>` is ever used.

- **iOS simulator** shares the host loopback, so the relay is reachable with no
  forwarding.
- **Android** gets `adb reverse tcp:<port> tcp:<port>`, which keeps the relay
  bound to host loopback rather than exposing it on the LAN.

Cleartext loopback is already permitted: Android's
`network_security_config.xml` allows `127.0.0.1` and `localhost`, and iOS's
`Info.plist` carries matching ATS exception domains. A missing `adb reverse` is
caught immediately by the test's own preflight `/health` check instead of
surfacing later as an opaque pairing timeout.

## Compilation mode

| Platform         | Mode      | Why                                                                        |
| ---------------- | --------- | -------------------------------------------------------------------------- |
| iOS simulator    | `debug`   | `--profile` needs AOT, and Flutter refuses AOT for an iOS *simulator*.      |
| Android emulator | `--profile` | Supported, and closer to a release-like runtime.                          |

The scenario and its assertions are identical either way; only the compilation
mode differs. A physical iOS device would allow `--profile`, but that is out of
scope for a simulator matrix.

## Scenario control and cancellation

Scenario selection and fixture sizing travel to the app as **dart-defines**,
because a mobile app process does not inherit the shell environment:

| dart-define                       | Meaning                                              | Default            |
| --------------------------------- | ---------------------------------------------------- | ------------------ |
| `PRISM_TEST_RELAY_URL`            | device-facing relay base URL                         | required           |
| `PRISM_RESUMABLE_SCENARIO`        | scenario id                                          | `happy-resumable`  |
| `PRISM_RESUMABLE_SNAPSHOT_MIB`    | raw MiB of the injected incompressible blob          | per scenario       |
| `PRISM_TEST_RELAY_METRICS_TOKEN`  | bearer token for `/metrics`                          | empty              |
| `PRISM_RESUMABLE_SCREENSHOTS`     | ask `integration_test` for screenshots               | `false`            |

**Cancellation is coordinated by relay metrics, not by a side channel.** The test
starts the upload detached, then polls the relay's own production
`/metrics` over loopback until `prism_snapshot_upload_chunks_total{result="accepted"}`
has grown by at least one. Only then does it call `cancelPairingCeremony`. This
is why no host-side coordination signal is needed: the relay is the ground truth
for "a real session exists and is still transferring", and the device can read it
directly. The runner additionally captures `METRICS_TOKEN`-authenticated
`/metrics` before and after each attempt as external evidence.

The poll interval is deliberately tight (25 ms) for the first 20 s so a fast
loopback upload cannot finish before the cancellation lands, then relaxes so a
stuck run does not hammer the endpoint.

## Evidence bundle

Written to `--out` (default `build/resumable-simulator-matrix/<UTC timestamp>/`):

```text
summary.json            hard pass/fail artifact (see below)
scenario-results.tsv    platform, scenario, attempt, status, log file
logs/<label>.log        full flutter drive output, including harness events
logs/relay-<mode>.log   relay startup log for each relay mode
metrics/<label>.txt     post-attempt /metrics snapshot
metrics/<mode>-before.txt  baseline /metrics snapshot
screenshots/<label>.png device screenshot per attempt
provenance/run.txt      app + sync SHAs, container version, ports, scenarios
provenance/<label>-defines.txt  dart-defines with the metrics token REDACTED
provenance/ios-device.txt | android-device.txt  device facts
```

The test also emits structured, secret-free events into the Flutter log:

```text
PRISM_RESUMABLE_HARNESS {"event":"scenario_start", ...}
PRISM_RESUMABLE_HARNESS {"event":"metrics", ...}
PRISM_RESUMABLE_HARNESS {"event":"scenario_end","ok":true|false, ...}
```

`flutter drive` can exit 0 even when an integration test reports a failure, so
the runner requires **both** a zero exit status and an `"ok":true` end event.

### `summary.json`

`matrixPassed` is the machine-readable verdict. It is true only when every
recorded attempt passed and the runner reached completion. The metrics token
value is never included; only `metricsTokenConfigured: true`.

### Secrets

Relay state and the metrics token live in a `mktemp` directory **outside** the
output tree, and the runner deletes that directory on exit (unless
`--keep-relay`). The token is passed to the app as a dart-define, so it does
appear in the Flutter process invocation; the persisted define file is redacted
with `sed`. All fixture data is synthetic.

## Exit status

| Status | Meaning                                    |
| ------ | ------------------------------------------ |
| 0      | every scenario passed                       |
| 64     | usage error                                 |
| 69     | missing prerequisite / relay failed to start |
| 65     | one or more scenarios failed                |
| 66     | integration test target or driver missing   |

## Examples

```bash
# Preflight only: verify the container CLI, build the image, prove both relay
# shapes start and serve /metrics. Needs no device. Run this first.
tool/run_resumable_simulator_matrix.sh --relay-only

# Full matrix on a named simulator and a named AVD (the common case).
tool/run_resumable_simulator_matrix.sh \
  --ios-simulator "iPhone 17 Pro" \
  --android-avd prism_codec_api35

# Attach to already-running devices. Neither is stopped by the runner.
tool/run_resumable_simulator_matrix.sh \
  --ios-device <UDID> --android-serial <SERIAL>

# One scenario, three cancellation repeats, on Android only.
tool/run_resumable_simulator_matrix.sh \
  --android-avd prism_codec_api35 --scenario cancel-mid-upload

# Process fallback when the container runtime is unavailable.
tool/run_resumable_simulator_matrix.sh \
  --relay-binary <prism-sync worktree>/target/debug/prism-sync-relay \
  --ios-simulator "iPhone 17 Pro"
```

## Cleanup safety

- A relay is disposable state; it is stopped and deleted on exit.
- An emulator or simulator the runner **launched** is stopped on exit. A device
  passed with `--android-serial` or an already-booted simulator passed with
  `--ios-device` is reused and never stopped, so interrupting the runner cannot
  kill someone else's device.
- `--keep-relay` retains the relay state directory for debugging; that directory
  contains a live metrics token, so treat it as sensitive and remove it after use.

## Memory observations

Harness events include `rssBytes` and `maxRssBytes` from the device process.
These are synthetic-test measurements: sender and joiner share one process,
iOS Simulator runs in debug mode, and Android Emulator runs in profile mode.
They do not establish a production physical-device memory budget or justify
increasing snapshot size limits. Keep storage export/import costs separate
from transport retry and byte-equality results.
