#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────
# Prism Build Script
# ─────────────────────────────────────────────────────────────────────

MACOS_DEVICE="macos"
ANDROID_DEVICE="Pixel 6 Pro"
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
    echo -e "  ${GREEN}clean${RESET}     Clean build artifacts (--mac/--android/--iphone/--all; default: all)"
    echo ""
    echo -e "${BOLD}Targets (for run/build):${RESET}"
    echo -e "  ${GREEN}--mac${RESET}       macOS desktop"
    echo -e "  ${GREEN}--android${RESET}   Pixel 6 Pro (debug: arm64 only; use --release for multi-arch APK)"
    echo -e "  ${GREEN}--iphone${RESET}   Skylar's iPhone"
    echo -e "  ${GREEN}--all${RESET}       All three targets (parallel)"
    echo ""
    echo -e "${BOLD}Options:${RESET}"
    echo -e "  ${GREEN}--live${RESET}      Live debug mode (hot reload: r, hot restart: R, quit: q)"
    echo -e "  ${GREEN}--release${RESET}   Release mode (default: debug)"
    echo -e "  ${GREEN}--profile${RESET}   Profile mode"
    echo ""
    echo -e "${BOLD}Examples:${RESET}"
    echo -e "  ${DIM}./build.sh run --mac --live${RESET}"
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
# Build info injection
# ─────────────────────────────────────────────────────────────────────
#
# Populate BUILD_INFO_DEFINES with --dart-define flags so BuildInfo
# (lib/core/services/build_info.dart) can surface the git revision,
# branch, pubspec version, and timestamp in the debug screen.
#
# Echoed as a single word-splittable string: callers pass it unquoted
# ($BUILD_INFO_DEFINES) so bash splits each flag into its own argv slot.
# None of the values we inject contain whitespace, so this is safe.
compute_build_info() {
    local git_rev git_describe git_branch built_at app_version
    git_rev=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    git_describe=$(git describe --always --dirty 2>/dev/null || echo "unknown")
    git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    app_version=$(grep '^version:' pubspec.yaml 2>/dev/null \
        | awk '{print $2}' \
        | tr -d '"' \
        | head -1)
    [ -z "$app_version" ] && app_version="unknown"

    BUILD_INFO_DEFINES="--dart-define=APP_VERSION=${app_version}"
    BUILD_INFO_DEFINES="${BUILD_INFO_DEFINES} --dart-define=GIT_REV=${git_rev}"
    BUILD_INFO_DEFINES="${BUILD_INFO_DEFINES} --dart-define=GIT_DESCRIBE=${git_describe}"
    BUILD_INFO_DEFINES="${BUILD_INFO_DEFINES} --dart-define=GIT_BRANCH=${git_branch}"
    BUILD_INFO_DEFINES="${BUILD_INFO_DEFINES} --dart-define=BUILT_AT=${built_at}"

    # Optional: bake a beta relay registration token into the binary so
    # TestFlight / beta testers don't have to type it by hand. The token
    # itself is NEVER committed to this repo; it's passed in via the
    # PRISM_BETA_REGISTRATION_TOKEN env var from a wrapper script that
    # sources a gitignored env file outside the app/ tree. If unset, the
    # token field stays blank and the app builds cleanly for self-hosters.
    if [ -n "${PRISM_BETA_REGISTRATION_TOKEN:-}" ]; then
        BUILD_INFO_DEFINES="${BUILD_INFO_DEFINES} --dart-define=PRISM_BETA_REGISTRATION_TOKEN=${PRISM_BETA_REGISTRATION_TOKEN}"
    fi

    export BUILD_INFO_DEFINES
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
    local do_ios=false do_mac=false do_android=false

    if [ $# -eq 0 ]; then
        do_ios=true; do_mac=true; do_android=true
    else
        for arg in "$@"; do
            case "$arg" in
                --iphone)   do_ios=true ;;
                --mac)      do_mac=true ;;
                --android)  do_android=true ;;
                --all)      do_ios=true; do_mac=true; do_android=true ;;
                *)          echo "Unknown option: $arg"; usage; exit 1 ;;
            esac
        done
    fi

    step "Cleaning Flutter"
    flutter clean

    if $do_ios || $do_mac; then
        step "Cleaning Pods"
        $do_ios && rm -rf ios/Pods
        $do_mac && rm -rf macos/Pods
    fi

    if $do_android; then
        step "Cleaning Gradle"
        (cd android && ./gradlew --stop 2>/dev/null || true)
        rm -rf android/.gradle
    fi

    success "Clean complete"
}

cmd_devices() {
    flutter devices
}

ensure_pods() {
    local platform="$1"  # ios or macos
    local pods_dir="${platform}/Pods"
    if [ ! -d "$pods_dir" ]; then
        step "Installing $platform Pods"
        flutter pub get
        (cd "$platform" && pod install --silent)
    fi
}

cmd_run() {
    local targets=()
    local mode="debug"
    local live=false

    for arg in "$@"; do
        case "$arg" in
            --mac)      targets+=("$MACOS_DEVICE") ;;
            --android)  targets+=("$ANDROID_DEVICE") ;;
            --iphone)   targets+=("$IPHONE_DEVICE") ;;
            --all)      targets+=("$MACOS_DEVICE" "$ANDROID_DEVICE" "$IPHONE_DEVICE") ;;
            --live)     live=true; mode="debug" ;;
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

    compute_build_info

    # Single target: run in foreground so hot reload (r/R) works
    if [ ${#targets[@]} -eq 1 ]; then
        local name=""
        case "${targets[0]}" in
            "$MACOS_DEVICE")    name="macOS";  ensure_pods "macos" ;;
            "$ANDROID_DEVICE")  name="Pixel 6 Pro" ;;
            "$IPHONE_DEVICE")   name="iPhone"; ensure_pods "ios" ;;
        esac
        step "Running on $name ($mode)"
        if $live; then
            echo -e "  ${DIM}r${RESET} hot reload  ${DIM}R${RESET} hot restart  ${DIM}q${RESET} quit"
            echo ""
        fi
        exec flutter run -d "${targets[0]}" $mode_flag $BUILD_INFO_DEFINES
    fi

    # Multiple targets: background all, but warn about hot reload
    echo -e "${DIM}Note: hot reload (r/R) is not available when running multiple targets${RESET}"
    for device in "${targets[@]}"; do
        local name=""
        case "$device" in
            "$MACOS_DEVICE")    name="macOS";  ensure_pods "macos" ;;
            "$ANDROID_DEVICE")  name="Pixel 6 Pro" ;;
            "$IPHONE_DEVICE")   name="iPhone"; ensure_pods "ios" ;;
        esac
        step "Running on $name ($mode)"
        flutter run -d "$device" $mode_flag $BUILD_INFO_DEFINES &
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
    [ "$mode" = "debug" ]   && mode_flag="--debug"
    [ "$mode" = "release" ] && mode_flag="--release"
    [ "$mode" = "profile" ] && mode_flag="--profile"

    compute_build_info

    for platform in "${targets[@]}"; do
        [[ "$platform" == "ios" || "$platform" == "macos" ]] && ensure_pods "$platform"
        step "Building $platform ($mode)"
        timer_start
        # Debug Android APK: compile only for arm64 to skip the armeabi-v7a pass.
        # Release keeps all ABIs for Play Store distribution.
        # flutter uses its own platform names (android-arm64), not NDK ABI names.
        local arch_flag=""
        [ "$mode" = "debug" ] && [ "$platform" = "apk" ] && arch_flag="--target-platform android-arm64"
        flutter build "$platform" $mode_flag $arch_flag $BUILD_INFO_DEFINES
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
    clean)    cmd_clean "$@" ;;
    help|-h)  usage ;;
    *)        echo "Unknown command: $command"; usage; exit 1 ;;
esac
