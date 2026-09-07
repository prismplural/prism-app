#!/usr/bin/env bash
# Live service tests are deliberately opt-in and never inherit PK_TOKEN.
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
  printf 'lane=live\nstarted_at=%s\nfinished_at=%s\nduration_seconds=%s\nexit_status=%s\n' \
    "$started_at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$((finished_epoch - started_epoch))" "$status" \
    > "$results_dir/live-status.txt"
}
trap finish EXIT
if [[ ${PRISM_ALLOW_LIVE_TESTS:-} != 1 ]]; then
  echo 'Refusing live tests: set PRISM_ALLOW_LIVE_TESTS=1 explicitly.' >&2
  exit 2
fi
if [[ -z ${PRISM_LIVE_TEST_TOKEN:-} ]]; then
  echo 'Refusing live tests: PRISM_LIVE_TEST_TOKEN is required.' >&2
  exit 2
fi
printf 'lane=live\nstarted_at=%s\napp_revision=%s\n' \
  "$started_at" "$(git rev-parse HEAD)" > "$results_dir/live-environment.txt"

# Replace both token spellings with the named, deliberate test-account token.
env -u PLURALKIT_TOKEN PK_TEST_TOKEN="$PRISM_LIVE_TEST_TOKEN" \
  PK_TOKEN="$PRISM_LIVE_TEST_TOKEN" \
  flutter test test/features/pluralkit/services \
    --tags=integration \
    --file-reporter "json:$results_dir/live-tests.json" \
    | tee "$results_dir/live-tests.log"
