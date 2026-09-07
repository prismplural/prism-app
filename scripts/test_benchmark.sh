#!/usr/bin/env bash
# Deliberate local measurement lane; it is not an ordinary PR timing gate.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
results_dir=${PRISM_TEST_RESULTS_DIR:-test-results}
mkdir -p "$results_dir"
started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
started_epoch=$(date +%s)
finish() {
  status=$?
  finished_epoch=$(date +%s)
  printf 'lane=benchmark\nstarted_at=%s\nfinished_at=%s\nduration_seconds=%s\nexit_status=%s\n' \
    "$started_at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$((finished_epoch - started_epoch))" "$status" \
    > "$results_dir/benchmark-status.txt"
}
trap finish EXIT
printf 'lane=benchmark\nstarted_at=%s\napp_revision=%s\n' \
  "$started_at" "$(git rev-parse HEAD)" > "$results_dir/benchmark-environment.txt"
tests=()
while IFS= read -r test_file; do
  tests+=("$test_file")
done < <(rg -l "@Tags\\(\\['benchmark'\\]\\)|tags: \['benchmark'\]" test -g '*_test.dart' | rg -v '^test/e2e/' | sort)
if ((${#tests[@]} == 0)); then
  echo 'No non-native benchmark test files were found.' >&2
  exit 1
fi
env -u PK_TOKEN -u PK_TEST_TOKEN -u PLURALKIT_TOKEN -u PRISM_LIVE_TEST_TOKEN -u PRISM_ALLOW_LIVE_TESTS \
  flutter test "${tests[@]}" --tags=benchmark \
    --file-reporter "json:$results_dir/benchmark-tests.json" \
    | tee "$results_dir/benchmark-tests.log"
