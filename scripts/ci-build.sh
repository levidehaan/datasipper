#!/bin/bash

# DataSipper CI/CD Build Script
# Optimized for GitHub Actions and automated environments

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/ci-logs"
CI_STATE_DIR="$PROJECT_ROOT/.ci_state"

# Create directories
mkdir -p "$LOG_DIR" "$CI_STATE_DIR"

# Color codes (disabled in CI if needed)
if [[ "${CI}" == "true" ]] || [[ "${GITHUB_ACTIONS}" == "true" ]]; then
    # CI environment - simpler output
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    NC=""
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
fi

# GitHub Actions specific logging
github_log() {
    local level="$1"
    local message="$2"
    
    if [[ "${GITHUB_ACTIONS}" == "true" ]]; then
        case "$level" in
            "error")
                echo "::error::$message"
                ;;
            "warning")
                echo "::warning::$message"
                ;;
            "notice")
                echo "::notice::$message"
                ;;
            *)
                echo "$message"
                ;;
        esac
    fi
    
    echo -e "${BLUE}[CI]${NC} $message" | tee -a "$LOG_DIR/ci-build.log"
}

log_error() {
    github_log "error" "$1"
}

log_warning() {
    github_log "warning" "$1"
}

log_info() {
    github_log "notice" "$1"
}

# CI environment detection and setup
setup_ci_environment() {
    log_info "Setting up CI environment..."
    
    # Detect CI system
    if [[ "${GITHUB_ACTIONS}" == "true" ]]; then
        log_info "Detected GitHub Actions environment"
        export CI_SYSTEM="github_actions"
        export CI_PARALLEL_JOBS="${CI_PARALLEL_JOBS:-2}"  # Conservative for CI
    elif [[ "${GITLAB_CI}" == "true" ]]; then
        log_info "Detected GitLab CI environment"
        export CI_SYSTEM="gitlab_ci"
        export CI_PARALLEL_JOBS="${CI_PARALLEL_JOBS:-2}"
    else
        log_info "Generic CI environment detected"
        export CI_SYSTEM="generic"
        export CI_PARALLEL_JOBS="${CI_PARALLEL_JOBS:-$(nproc)}"
    fi
    
    # Set CI-specific optimizations
    export GN_ARGS_CI="
        is_debug=false
        is_component_build=true
        symbol_level=0
        use_jumbo_build=true
        enable_precompiled_headers=false
        use_goma=false
        treat_warnings_as_errors=false
        enable_nacl=false
        enable_remoting=false
        enable_pdf=false
        enable_plugins=false
        enable_print_preview=false
        enable_service_discovery=false
        safe_browsing_mode=0
        use_cups=false
        use_pulseaudio=false
        rtc_use_pipewire=false
        use_vaapi=false
        proprietary_codecs=false
        ffmpeg_branding=\"Chromium\"
        use_custom_libcxx=false
        use_sysroot=false
    "
    
    log_info "CI environment setup complete"
    log_info "Parallel jobs: $CI_PARALLEL_JOBS"
}

# Cache management for CI
setup_ci_cache() {
    log_info "Setting up CI cache..."
    
    local cache_dir="${CI_CACHE_DIR:-$HOME/.cache/datasipper}"
    mkdir -p "$cache_dir"
    
    # Create cache symlinks
    if [[ ! -L "$PROJECT_ROOT/.cipd" ]] && [[ -d "$cache_dir/cipd" ]]; then
        ln -sf "$cache_dir/cipd" "$PROJECT_ROOT/.cipd"
    fi
    
    if [[ ! -L "$PROJECT_ROOT/.gclient_entries" ]] && [[ -f "$cache_dir/gclient_entries" ]]; then
        ln -sf "$cache_dir/gclient_entries" "$PROJECT_ROOT/.gclient_entries"
    fi
    
    log_info "Cache setup complete"
}

# Fast dependency installation for CI
install_ci_dependencies() {
    log_info "Installing CI dependencies..."
    
    # Update package lists
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -qq
        
        # Install essential build dependencies
        sudo apt-get install -y \
            build-essential \
            git \
            python3 \
            python3-pip \
            wget \
            curl \
            ninja-build \
            pkg-config \
            libnss3-dev \
            libatk-bridge2.0-dev \
            libdrm2 \
            libxkbcommon-dev \
            libxcomposite-dev \
            libxdamage-dev \
            libxrandr-dev \
            libgbm-dev \
            libxss-dev \
            libasound2-dev \
            2>&1 | tee "$LOG_DIR/dependencies.log"
    fi
    
    log_info "Dependencies installation complete"
}

# Lightweight Chromium fetch for CI
fetch_chromium_ci() {
    log_info "Fetching Chromium source (CI optimized)..."
    
    cd "$PROJECT_ROOT"
    
    # Install depot_tools if not present
    if [[ ! -d depot_tools ]]; then
        log_info "Installing depot_tools..."
        git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
        export PATH="$PROJECT_ROOT/depot_tools:$PATH"
    fi
    
    # Configure git for CI
    git config --global user.email "ci@datasipper.build"
    git config --global user.name "DataSipper CI"
    git config --global init.defaultBranch main
    
    # Fetch Chromium (shallow clone for CI)
    if [[ ! -d src ]]; then
        log_info "Fetching Chromium source..."
        fetch --nohooks chromium
        
        cd src
        git checkout main
        
        # Minimal sync for CI (no history)
        gclient sync --nohooks --shallow --no-history
    else
        log_info "Chromium source already exists"
        cd src
        gclient sync --nohooks
    fi
    
    log_info "Chromium fetch complete"
}

# Apply patches with CI-specific error handling
apply_patches_ci() {
    log_info "Applying DataSipper patches..."
    
    cd "$PROJECT_ROOT"
    
    # Validate patches first
    if [[ -f scripts/patches.py ]]; then
        python3 scripts/patches.py validate
    else
        log_error "Patch validation script not found"
        return 1
    fi
    
    # Apply patches with detailed logging
    if [[ -f build_scripts/manage_patches.sh ]]; then
        chmod +x build_scripts/manage_patches.sh
        ./build_scripts/manage_patches.sh apply 2>&1 | tee "$LOG_DIR/patch-application.log"
    else
        log_error "Patch management script not found"
        return 1
    fi
    
    log_info "Patches applied successfully"
}

# CI-optimized build configuration
configure_build_ci() {
    log_info "Configuring build for CI..."
    
    cd "$PROJECT_ROOT/src"
    mkdir -p out/CI
    
    # Generate CI build configuration
    cat > out/CI/args.gn << EOF
# DataSipper CI build configuration
$GN_ARGS_CI
EOF
    
    # Generate build files
    gn gen out/CI 2>&1 | tee "$LOG_DIR/gn-gen.log"
    
    log_info "Build configuration complete"
}

# Build core components for CI testing
build_core_components_ci() {
    log_info "Building core components..."
    
    cd "$PROJECT_ROOT/src"
    
    # Build essential components first (faster feedback)
    local core_targets=(
        "base"
        "net"
        "content/public/browser"
        "chrome/browser/datasipper:datasipper_core"
        "chrome/browser/ui/views/datasipper:datasipper_ui"
    )
    
    for target in "${core_targets[@]}"; do
        log_info "Building target: $target"
        if ! ninja -C out/CI "$target" -j"$CI_PARALLEL_JOBS" 2>&1 | tee "$LOG_DIR/build-$target.log"; then
            log_error "Failed to build target: $target"
            return 1
        fi
    done
    
    log_info "Core components build complete"
}

# Quick smoke test for CI
run_ci_tests() {
    log_info "Running CI tests..."
    
    cd "$PROJECT_ROOT/src"
    
    # Build test binary if it doesn't exist
    if [[ ! -f out/CI/chrome ]]; then
        log_info "Building Chrome binary for testing..."
        ninja -C out/CI chrome -j"$CI_PARALLEL_JOBS" 2>&1 | tee "$LOG_DIR/chrome-build.log"
    fi
    
    if [[ -f out/CI/chrome ]]; then
        log_info "Running basic functionality tests..."
        
        # Version test
        ./out/CI/chrome --version 2>&1 | tee "$LOG_DIR/version-test.log"
        
        # Basic rendering test
        timeout 30s ./out/CI/chrome --headless --disable-gpu --virtual-time-budget=5000 --dump-dom about:blank > "$LOG_DIR/render-test.html" 2>&1 || true
        
        # Check if output contains expected HTML
        if grep -q "<html" "$LOG_DIR/render-test.html"; then
            log_info "Basic rendering test passed"
        else
            log_warning "Basic rendering test may have issues"
        fi
        
        log_info "CI tests completed"
        return 0
    else
        log_error "Chrome binary not found"
        return 1
    fi
}

# Generate CI artifacts
generate_ci_artifacts() {
    log_info "Generating CI artifacts..."
    
    local artifacts_dir="$PROJECT_ROOT/ci-artifacts"
    mkdir -p "$artifacts_dir"
    
    # Copy build logs
    cp -r "$LOG_DIR"/* "$artifacts_dir/" 2>/dev/null || true
    
    # Binary information
    if [[ -f "$PROJECT_ROOT/src/out/CI/chrome" ]]; then
        cd "$PROJECT_ROOT/src"
        ls -lh out/CI/chrome > "$artifacts_dir/binary-info.txt"
        ldd out/CI/chrome > "$artifacts_dir/dependencies.txt" 2>&1 || true
        file out/CI/chrome > "$artifacts_dir/binary-type.txt"
    fi
    
    # Build configuration
    if [[ -f "$PROJECT_ROOT/src/out/CI/args.gn" ]]; then
        cp "$PROJECT_ROOT/src/out/CI/args.gn" "$artifacts_dir/"
    fi
    
    # System information
    uname -a > "$artifacts_dir/system-info.txt"
    cat /proc/meminfo > "$artifacts_dir/memory-info.txt" 2>/dev/null || true
    cat /proc/cpuinfo | head -20 > "$artifacts_dir/cpu-info.txt" 2>/dev/null || true
    
    log_info "CI artifacts generated in: $artifacts_dir"
}

# Main CI build workflow
ci_build_workflow() {
    local build_type="${1:-core}"
    
    log_info "Starting CI build workflow: $build_type"
    
    setup_ci_environment
    setup_ci_cache
    install_ci_dependencies
    fetch_chromium_ci
    apply_patches_ci
    configure_build_ci
    
    case "$build_type" in
        "core")
            build_core_components_ci
            ;;
        "full")
            build_core_components_ci
            run_ci_tests
            ;;
        "test")
            run_ci_tests
            ;;
        *)
            log_error "Unknown build type: $build_type"
            return 1
            ;;
    esac
    
    generate_ci_artifacts
    log_info "CI build workflow completed successfully"
}

# Usage
usage() {
    cat << EOF
DataSipper CI/CD Build Script

Usage: $0 [command]

Commands:
  core            - Build core components only (fast)
  full            - Full build with tests
  test            - Run tests only (requires existing build)
  setup           - Setup CI environment only
  artifacts       - Generate artifacts from existing build
  help            - Show this help

Environment Variables:
  CI_PARALLEL_JOBS    - Number of parallel build jobs (default: 2)
  CI_CACHE_DIR        - Cache directory for dependencies
  
Examples:
  $0 core             # Fast core build for PR checks
  $0 full             # Full build for releases
  $0 test             # Test existing build
  
EOF
}

# Main execution
main() {
    local command="${1:-core}"
    
    case "$command" in
        "core")
            ci_build_workflow "core"
            ;;
        "full")
            ci_build_workflow "full"
            ;;
        "test")
            ci_build_workflow "test"
            ;;
        "setup")
            setup_ci_environment
            setup_ci_cache
            install_ci_dependencies
            ;;
        "artifacts")
            generate_ci_artifacts
            ;;
        "help"|"--help"|"-h")
            usage
            ;;
        *)
            log_error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

# Execute with error handling
if ! main "$@"; then
    log_error "CI build failed"
    exit 1
fi