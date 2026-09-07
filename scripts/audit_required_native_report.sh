#!/usr/bin/env bash
set -euo pipefail

report=${1:?usage: audit_required_native_report.sh REPORT APP_ROOT TEST...}
app_root=${2:?usage: audit_required_native_report.sh REPORT APP_ROOT TEST...}
shift 2
(( $# > 0 )) || { printf 'no required suites supplied\n' >&2; exit 1; }

terminal_ok=$(jq -s '[.[] | select(.type == "done")] | length == 1 and .[0].success == true' "$report")
[[ "$terminal_ok" == true ]] || {
  printf 'test protocol did not end with one successful terminal event\n' >&2
  exit 1
}
bad_results=$(jq -s '[.[] | select(.type == "testDone" and (.skipped == true or .result != "success"))] | length' "$report")
(( bad_results == 0 )) || {
  printf '%s required test results skipped or failed\n' "$bad_results" >&2
  exit 1
}

completed=0
for test_file in "$@"; do
  suite_path="$app_root/$test_file"
  suite_id=$(jq -er -s --arg path "$suite_path" \
    '[.[] | select(.type == "suite" and .suite.path == $path) | .suite.id] | unique | if length == 1 then .[0] else error("suite missing or duplicated") end' \
    "$report") || {
      printf 'required suite did not register exactly once: %s\n' "$test_file" >&2
      exit 1
    }
  suite_successes=$(jq -s --argjson suite_id "$suite_id" '
    . as $events
    | [$events[] | select(.type == "testStart" and .test.suiteID == $suite_id) | .test.id] as $ids
    | [$events[] | select(
        .type == "testDone"
        and (.testID as $id | $ids | index($id))
        and .hidden != true
        and .skipped != true
        and .result == "success"
      )] | length
  ' "$report")
  (( suite_successes > 0 )) || {
    printf 'required suite had no real successful test: %s\n' "$test_file" >&2
    exit 1
  }
  completed=$((completed + suite_successes))
done
printf '%s\n' "$completed"
