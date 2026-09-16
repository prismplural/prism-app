# Android ANR profile harness

`tool/run_android_anr_harness.sh` runs the ANR-sensitive workload suite on an
Android emulator or device in Flutter profile mode. It is development/profile
evidence only; it does not add production telemetry.

The harness currently exercises:

- encrypted export serialization, scrypt/AES-GCM, and streamed media output;
- profile-header decode, crop, resize, PNG ladder, and native WebP encoding;
- large media SHA-256 hashing;
- a deliberate main-isolate stall that calibrates the pulse detector.

A helper isolate emits pulses every 16 ms. The main isolate receives and
timestamps them, so delayed delivery measures event-loop starvation. Each real
scenario fails when its maximum pulse gap exceeds 500 ms by default. The
calibration scenario intentionally blocks for about 650 ms and must be detected.

## Run on an existing emulator or device

```bash
tool/run_android_anr_harness.sh --device emulator-5554
```

List available devices with `adb devices -l`.

## Launch an AVD for the run

```bash
tool/run_android_anr_harness.sh --launch-avd prism_codec_api35
```

The runner stops only an emulator that it launched. It never stops a device
provided through `--device`.

## Adjust workload sizes

```bash
tool/run_android_anr_harness.sh \
  --device emulator-5554 \
  --export-records 40000 \
  --export-media-mib 32 \
  --export-image-members 48 \
  --export-image-kib 512 \
  --hash-mib 64 \
  --pulse-threshold-ms 500
```

Defaults are 20,000 export records, 16 MiB streamed export media, 48 members
with three 512 KiB inline image payloads each, 32 MiB hashed media, and a 500 ms
pulse-gap threshold. Use the image flags to scale the isolate-handoff graph
toward the export writer's JSON limit.

## Artifacts

Each run writes under `build/android-anr-harness/<UTC timestamp>/` unless
`--out` is supplied:

- `result.json` — overall Flutter/ANR/OOM verdict;
- `harness-events.json` — parsed phase and pulse summaries;
- `flutter-drive.log` — profile integration-test output;
- `logcat.txt` and `logcat-anr-oom.txt` — complete and filtered Android logs;
- `meminfo-samples.csv` and `meminfo-raw/` — periodic PSS/RSS evidence;
- `device-props.txt` — Android version, ABI, model, heap, and RAM;
- `provenance.json` — Git SHA, dirty-tree fingerprints, tool versions, device,
  thresholds, and Dart defines.

A passing run requires the integration target to pass and no app ANR or OOM to
appear in logcat. Inspect per-scenario `maximumGapMicros` values and memory
samples as well as the top-level verdict.

## Release interpretation

An emulator run is useful for reproducibility and regression detection, but it
is not the final release gate: emulator CPU scheduling and memory behavior differ
from physical Android hardware. Before release, repeat the profile harness on a
representative low/mid-range physical device using `--device`, retain the full
artifact directory, and verify:

- every real scenario remains at or below the 500 ms pulse-gap gate;
- no ANR, OOM, process kill, or native crash appears in logcat;
- peak and post-scenario memory are acceptable and do not grow across repeated
  runs;
- the tested Git SHA/diff fingerprint and Android device metadata match the
  release evidence record.
