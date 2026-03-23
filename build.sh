#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────
# Prism Build Script
# ─────────────────────────────────────────────────────────────────────

MACOS_DEVICE="macos"
ANDROID_DEVICE="adb-19101FDEE007T3-b9mL3t._adb-tls-connect._tcp"
IPHONE_DEVICE="00008120-0014759E3A33401E"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

usage() {
    echo ""
    echo -e "${BOLD}Prism Build Script${RESET}"
    echo ""
    echo -e "  ${CYAN}build.sh${RESET} ${DIM}<command>${RESET} ${DIM}[options]${RESET}"
    echo ""
    echo -e "${BOLD}Commands:${RESET}"
    echo -e "  ${GREEN}run${RESET}       Build and run on a device"
    echo -e "  ${GREEN}build${RESET}     Build without running"
    echo -e "  ${GREEN}test${RESET}      Run all tests"
    echo -e "  ${GREEN}check${RESET}     Codegen + analyze + test (full pre-flight)"
    echo -e "  ${GREEN}codegen${RESET}   Run build_runner codegen"
    echo -e "  ${GREEN}devices${RESET}   List connected devices"
    echo -e "  ${GREEN}clean${RESET}     Clean build artifacts"
    echo ""
    echo -e "${BOLD}Targets (for run/build):${RESET}"
    echo -e "  ${GREEN}--mac${RESET}       macOS desktop"
    echo -e "  ${GREEN}--android${RESET}   Pixel 6 Pro"
    echo -e "  ${GREEN}--iphone${RESET}   Skylar's iPhone"
    echo -e "  ${GREEN}--all${RESET}       All three targets (parallel)"
    echo ""
    echo -e "${BOLD}Options:${RESET}"
    echo -e "  ${GREEN}--release${RESET}   Release mode (default: debug)"
    echo -e "  ${GREEN}--profile${RESET}   Profile mode"
    echo ""
    echo -e "${BOLD}Examples:${RESET}"
    echo -e "  ${DIM}./build.sh run --mac${RESET}"
    echo -e "  ${DIM}./build.sh run --android --release${RESET}"
    echo -e "  ${DIM}./build.sh run --all${RESET}"
    echo -e "  ${DIM}./build.sh check${RESET}"
    echo ""
}

step() {
    echo -e "\n${BLUE}▸${RESET} ${BOLD}$1${RESET}"
}

success() {
    echo -e "${GREEN}✓${RESET} $1"
}

fail() {
    echo -e "${RED}✗${RESET} $1"
    exit 1
}

timer_start() {
    _TIMER_START=$(date +%s)
}

timer_end() {
    local elapsed=$(( $(date +%s) - _TIMER_START ))
    local min=$(( elapsed / 60 ))
    local sec=$(( elapsed % 60 ))
    if [ $min -gt 0 ]; then
        echo -e "${DIM}(${min}m ${sec}s)${RESET}"
    else
        echo -e "${DIM}(${sec}s)${RESET}"
    fi
}

# ─────────────────────────────────────────────────────────────────────
# Commands
# ─────────────────────────────────────────────────────────────────────

cmd_codegen() {
    step "Running codegen"
    timer_start
    dart run build_runner build --delete-conflicting-outputs 2>&1 | tail -1
    timer_end
    success "Codegen complete"
}

cmd_test() {
    step "Running tests"
    timer_start
    local output
    output=$(flutter test 2>&1)
    local result=$?
    local last_line=$(echo "$output" | tail -1)
    timer_end
    if [ $result -eq 0 ]; then
        success "$last_line"
    else
        echo "$output" | tail -20
        fail "Tests failed"
    fi
}

cmd_analyze() {
    step "Running analyzer"
    timer_start
    local output
    output=$(flutter analyze --no-fatal-infos 2>&1)
    local result=$?
    local errors=$(echo "$output" | grep -c "error" || true)
    timer_end
    if [ "$errors" -eq 0 ]; then
        local issues=$(echo "$output" | tail -1)
        success "No errors — $issues"
    else
        echo "$output" | grep "error"
        fail "$errors errors found"
    fi
}

cmd_check() {
    step "Pre-flight check"
    echo ""
    cmd_codegen
    cmd_analyze
    cmd_test
    echo ""
    success "All checks passed"
}

cmd_clean() {
    step "Cleaning"
    flutter clean
    success "Clean complete"
}

cmd_devices() {
    flutter devices
}

cmd_run() {
    local targets=()
    local mode="debug"

    for arg in "$@"; do
        case "$arg" in
            --mac)      targets+=("$MACOS_DEVICE") ;;
            --android)  targets+=("$ANDROID_DEVICE") ;;
            --iphone)   targets+=("$IPHONE_DEVICE") ;;
            --all)      targets+=("$MACOS_DEVICE" "$ANDROID_DEVICE" "$IPHONE_DEVICE") ;;
            --release)  mode="release" ;;
            --profile)  mode="profile" ;;
            *)          echo "Unknown option: $arg"; usage; exit 1 ;;
        esac
    done

    if [ ${#targets[@]} -eq 0 ]; then
        echo -e "${RED}No target specified.${RESET} Use --mac, --android, --iphone, or --all"
        exit 1
    fi

    local mode_flag=""
    [ "$mode" = "release" ] && mode_flag="--release"
    [ "$mode" = "profile" ] && mode_flag="--profile"

    # Single target: run in foreground so hot reload (r/R) works
    if [ ${#targets[@]} -eq 1 ]; then
        local name=""
        case "${targets[0]}" in
            "$MACOS_DEVICE")    name="macOS" ;;
            "$ANDROID_DEVICE")  name="Pixel 6 Pro" ;;
            "$IPHONE_DEVICE")   name="iPhone" ;;
        esac
        step "Running on $name ($mode)"
        exec flutter run -d "${targets[0]}" $mode_flag
    fi

    # Multiple targets: background all, but warn about hot reload
    echo -e "${DIM}Note: hot reload (r/R) is not available when running multiple targets${RESET}"
    for device in "${targets[@]}"; do
        local name=""
        case "$device" in
            "$MACOS_DEVICE")    name="macOS" ;;
            "$ANDROID_DEVICE")  name="Pixel 6 Pro" ;;
            "$IPHONE_DEVICE")   name="iPhone" ;;
        esac
        step "Running on $name ($mode)"
        flutter run -d "$device" $mode_flag &
    done

    wait
}

cmd_build() {
    local targets=()
    local mode="debug"

    for arg in "$@"; do
        case "$arg" in
            --mac)      targets+=("macos") ;;
            --android)  targets+=("apk") ;;
            --iphone)   targets+=("ios") ;;
            --all)      targets+=("macos" "apk" "ios") ;;
            --release)  mode="release" ;;
            --profile)  mode="profile" ;;
            *)          echo "Unknown option: $arg"; usage; exit 1 ;;
        esac
    done

    if [ ${#targets[@]} -eq 0 ]; then
        echo -e "${RED}No target specified.${RESET} Use --mac, --android, --iphone, or --all"
        exit 1
    fi

    local mode_flag=""
    [ "$mode" = "release" ] && mode_flag="--release"
    [ "$mode" = "profile" ] && mode_flag="--profile"

    for platform in "${targets[@]}"; do
        step "Building $platform ($mode)"
        timer_start
        flutter build "$platform" $mode_flag
        timer_end
        success "$platform build complete"
    done
}

# ─────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────

if [ $# -eq 0 ]; then
    usage
    exit 0
fi

command="$1"
shift

case "$command" in
    run)      cmd_run "$@" ;;
    build)    cmd_build "$@" ;;
    test)     cmd_test ;;
    check)    cmd_check ;;
    codegen)  cmd_codegen ;;
    devices)  cmd_devices ;;
    clean)    cmd_clean ;;
    help|-h)  usage ;;
    *)        echo "Unknown command: $command"; usage; exit 1 ;;
esac
