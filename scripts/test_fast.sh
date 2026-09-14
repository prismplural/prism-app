#!/usr/bin/env bash
# Deterministic PR lane. Fetch dependencies first with `flutter pub get`.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
results_dir=${PRISM_TEST_RESULTS_DIR:-test-results}
mkdir -p "$results_dir"
start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
started_epoch=$(date +%s)

finish() {
  status=$?
  finished_epoch=$(date +%s)
  printf 'lane=fast\nstarted_at=%s\nfinished_at=%s\nduration_seconds=%s\nexit_status=%s\n' \
    "$start" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$((finished_epoch - started_epoch))" "$status" \
    > "$results_dir/fast-status.txt"
}
trap finish EXIT

for tool in flutter dart git rg; do
  command -v "$tool" >/dev/null || {
    echo "Missing fast-lane prerequisite: $tool" >&2
    exit 2
  }
done

{
  printf 'lane=fast\nstarted_at=%s\napp_revision=%s\n' "$start" "$(git rev-parse HEAD)"
  flutter --version
  dart --version
} > "$results_dir/fast-environment.txt"

# Bash 3 compatibility for the macOS system shell.
tests=()
while IFS= read -r test_file; do
  tests+=("$test_file")
done < <(rg --files test -g '*_test.dart' | rg -v '^test/e2e/' | sort)
if ((${#tests[@]} == 0)); then
  echo 'No fast test files were found.' >&2
  exit 1
fi

# Retain existing diagnostics without making baseline warnings fatal.
env -u PK_TOKEN -u PK_TEST_TOKEN -u PLURALKIT_TOKEN -u PRISM_LIVE_TEST_TOKEN -u PRISM_ALLOW_LIVE_TESTS \
  flutter analyze --no-fatal-infos --no-fatal-warnings \
  | tee "$results_dir/fast-analyze.log"
env -u PK_TOKEN -u PK_TEST_TOKEN -u PLURALKIT_TOKEN -u PRISM_LIVE_TEST_TOKEN -u PRISM_ALLOW_LIVE_TESTS \
  flutter test "${tests[@]}" \
    --exclude-tags='integration || slow || fixture-gen || benchmark || golden' \
    --file-reporter "json:$results_dir/fast-tests.json" \
    | tee "$results_dir/fast-tests.log"
