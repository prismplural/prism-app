#!/usr/bin/env bash
# Native FFI benchmark workloads require the same checked provenance as E2E.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
PRISM_NATIVE_TEST_ARGS='--tags=benchmark' scripts/test_native.sh
