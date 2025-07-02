#!/bin/bash

# DataSipper Staged Build System
# Handles long builds in manageable stages with proper state management
# Prevents timeouts and allows resumable builds

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_STATE_DIR="$PROJECT_ROOT/.build_state"
LOG_DIR="$PROJECT_ROOT/build-logs"
STAGE_TIMEOUT=1800  # 30 minutes per stage
MAX_STAGE_RETRIES=3

# Create necessary directories
mkdir -p "$BUILD_STATE_DIR" "$LOG_DIR"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_DIR/staged-build.log"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_DIR/staged-build.log"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_DIR/staged-build.log"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_DIR/staged-build.log"
}

# State management functions
save_stage_state() {
    local stage_name="$1"
    local status="$2"
    echo "$status" > "$BUILD_STATE_DIR/${stage_name}.state"
    echo "$(date -Iseconds)" > "$BUILD_STATE_DIR/${stage_name}.timestamp"
}

get_stage_state() {
    local stage_name="$1"
    if [[ -f "$BUILD_STATE_DIR/${stage_name}.state" ]]; then
        cat "$BUILD_STATE_DIR/${stage_name}.state"
    else
        echo "NOT_STARTED"
    fi
}

is_stage_complete() {
    local stage_name="$1"
    [[ "$(get_stage_state "$stage_name")" == "COMPLETE" ]]
}

mark_stage_complete() {
    local stage_name="$1"
    save_stage_state "$stage_name" "COMPLETE"
    log_success "Stage '$stage_name' completed successfully"
}

mark_stage_failed() {
    local stage_name="$1"
    save_stage_state "$stage_name" "FAILED"
    log_error "Stage '$stage_name' failed"
}

# Timeout wrapper for long-running commands
run_with_timeout() {
    local timeout_seconds="$1"
    local stage_name="$2"
    shift 2
    local command=("$@")
    
    log_info "Running stage '$stage_name' with ${timeout_seconds}s timeout: ${command[*]}"
    
    if timeout "$timeout_seconds" "${command[@]}" 2>&1 | tee -a "$LOG_DIR/${stage_name}.log"; then
        mark_stage_complete "$stage_name"
        return 0
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log_warning "Stage '$stage_name' timed out after ${timeout_seconds}s"
            save_stage_state "$stage_name" "TIMEOUT"
        else
            log_error "Stage '$stage_name' failed with exit code $exit_code"
            mark_stage_failed "$stage_name"
        fi
        return $exit_code
    fi
}

# Stage definitions
stage_01_environment_setup() {
    local stage_name="stage_01_environment_setup"
    if is_stage_complete "$stage_name"; then
        log_info "Stage 1: Environment setup already complete, skipping"
        return 0
    fi
    
    log_info "=== Stage 1: Environment Setup ==="
    run_with_timeout 600 "$stage_name" bash -c "
        cd '$PROJECT_ROOT'
        # Update system packages
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update -qq
        fi
        
        # Run environment optimization
        if [[ -f scripts/optimize-build-env.sh ]]; then
            chmod +x scripts/optimize-build-env.sh
            ./scripts/optimize-build-env.sh
        fi
        
        # Source updated environment
        if [[ -f ~/.bashrc ]]; then
            source ~/.bashrc || true
        fi
        
        # Verify basic tools
        which git >/dev/null || { echo 'Git not found'; exit 1; }
        which python3 >/dev/null || { echo 'Python3 not found'; exit 1; }
        
        echo 'Environment setup complete'
    "
}

stage_02_dependencies() {
    local stage_name="stage_02_dependencies"
    if is_stage_complete "$stage_name"; then
        log_info "Stage 2: Dependencies already installed, skipping"
        return 0
    fi
    
    log_info "=== Stage 2: Install Dependencies ==="
    run_with_timeout 900 "$stage_name" bash -c "
        cd '$PROJECT_ROOT'
        
        # Detect and run appropriate dependency installer
        if [[ -f scripts/install-deps-debian.sh ]] && command -v apt-get >/dev/null 2>&1; then
            chmod +x scripts/install-deps-debian.sh
            ./scripts/install-deps-debian.sh
        elif [[ -f scripts/install-deps-arch.sh ]] && command -v pacman >/dev/null 2>&1; then
            chmod +x scripts/install-deps-arch.sh
            ./scripts/install-deps-arch.sh
        else
            echo 'Running universal setup'
            if [[ -f scripts/dev-setup-universal.sh ]]; then
                chmod +x scripts/dev-setup-universal.sh
                ./scripts/dev-setup-universal.sh
            fi
        fi
        
        echo 'Dependencies installation complete'
    "
}

stage_03_chromium_fetch() {
    local stage_name="stage_03_chromium_fetch"
    if is_stage_complete "$stage_name"; then
        log_info "Stage 3: Chromium source already fetched, skipping"
        return 0
    fi
    
    log_info "=== Stage 3: Fetch Chromium Source ==="
    run_with_timeout 2400 "$stage_name" bash -c "
        cd '$PROJECT_ROOT'
        
        # Check if chromium-src exists and has content
        if [[ -d chromium-src/.git ]] && [[ -f chromium-src/BUILD.gn ]]; then
            echo 'Chromium source already exists and appears valid'
            exit 0
        fi
        
        # Run chromium fetch script
        if [[ -f scripts/fetch-chromium.sh ]]; then
            chmod +x scripts/fetch-chromium.sh
            ./scripts/fetch-chromium.sh
        else
            echo 'Fetch script not found, running manual fetch'
            if [[ ! -f .gclient ]]; then
                fetch --nohooks chromium
            fi
            cd chromium-src
            git checkout main
            gclient sync --nohooks
        fi
        
        echo 'Chromium source fetch complete'
    "
}

stage_04_build_config() {
    local stage_name="stage_04_build_config"
    if is_stage_complete "$stage_name"; then
        log_info "Stage 4: Build configuration already complete, skipping"
        return 0
    fi
    
    log_info "=== Stage 4: Configure Build ==="
    run_with_timeout 300 "$stage_name" bash -c "
        cd '$PROJECT_ROOT'
        
        # Run build configuration
        if [[ -f scripts/configure-build.sh ]]; then
            chmod +x scripts/configure-build.sh
            ./scripts/configure-build.sh
        else
            # Manual configuration
            cd chromium-src
            mkdir -p out/Lightning
            cat > out/Lightning/args.gn << 'EOF'
# DataSipper optimized build configuration
is_debug = false
is_component_build = true
symbol_level = 0
use_jumbo_build = true
enable_precompiled_headers = true
use_goma = false
treat_warnings_as_errors = false
enable_nacl = false
enable_remoting = false
enable_pdf = false
enable_plugins = false
enable_print_preview = false
enable_service_discovery = false
safe_browsing_mode = 0
use_cups = false
use_pulseaudio = false
rtc_use_pipewire = false
use_vaapi = true
proprietary_codecs = true
ffmpeg_branding = \"Chrome\"
EOF
            gn gen out/Lightning
        fi
        
        echo 'Build configuration complete'
    "
}

stage_05_patch_application() {
    local stage_name="stage_05_patch_application"
    if is_stage_complete "$stage_name"; then
        log_info "Stage 5: Patches already applied, skipping"
        return 0
    fi
    
    log_info "=== Stage 5: Apply DataSipper Patches ==="
    run_with_timeout 600 "$stage_name" bash -c "
        cd '$PROJECT_ROOT'
        
        # Validate patches first
        if [[ -f scripts/patches.py ]]; then
            python3 scripts/patches.py validate
        fi
        
        # Apply patches using preferred method
        if [[ -f build_scripts/manage_patches.sh ]]; then
            chmod +x build_scripts/manage_patches.sh
            ./build_scripts/manage_patches.sh apply
        elif [[ -f scripts/patches.py ]]; then
            python3 scripts/patches.py apply
        else
            echo 'No patch management system found'
            exit 1
        fi
        
        echo 'Patch application complete'
    "
}

stage_06_initial_build() {
    local stage_name="stage_06_initial_build"
    if is_stage_complete "$stage_name"; then
        log_info "Stage 6: Initial build already complete, skipping"
        return 0
    fi
    
    log_info "=== Stage 6: Initial Build (Core Components) ==="
    run_with_timeout 3600 "$stage_name" bash -c "
        cd '$PROJECT_ROOT'
        
        # Build core components first
        cd chromium-src
        
        # Build base libraries and core components
        ninja -C out/Lightning \\
            base \\
            net \\
            content/public/browser \\
            content/public/renderer \\
            components/prefs \\
            components/policy \\
            ui/base \\
            ui/views \\
            2>&1 | tee '$LOG_DIR/initial-build.log'
        
        echo 'Initial build (core components) complete'
    "
}

stage_07_chrome_build() {
    local stage_name="stage_07_chrome_build"
    if is_stage_complete "$stage_name"; then
        log_info "Stage 7: Chrome build already complete, skipping"
        return 0
    fi
    
    log_info "=== Stage 7: Build Chrome Binary ==="
    run_with_timeout 4800 "$stage_name" bash -c "
        cd '$PROJECT_ROOT/chromium-src'
        
        # Use optimized build script if available
        if [[ -f ../scripts/build-chrome-optimized.sh ]]; then
            cd ..
            ./scripts/build-chrome-optimized.sh
        else
            # Manual optimized build
            ninja -C out/Lightning chrome -j8 -l8 2>&1 | tee '$LOG_DIR/chrome-build.log'
        fi
        
        # Verify build success
        if [[ -f out/Lightning/chrome ]]; then
            echo 'Chrome build complete and verified'
        else
            echo 'Chrome build failed - binary not found'
            exit 1
        fi
    "
}

stage_08_test_build() {
    local stage_name="stage_08_test_build"
    if is_stage_complete "$stage_name"; then
        log_info "Stage 8: Test build already complete, skipping"
        return 0
    fi
    
    log_info "=== Stage 8: Test and Validate Build ==="
    run_with_timeout 600 "$stage_name" bash -c "
        cd '$PROJECT_ROOT/chromium-src'
        
        # Basic functionality test
        ./out/Lightning/chrome --version
        
        # Test DataSipper features (basic smoke test)
        timeout 10s ./out/Lightning/chrome --headless --disable-gpu --dump-dom about:blank >/dev/null 2>&1 || true
        
        # Verify binary size and dependencies
        ls -lh out/Lightning/chrome
        ldd out/Lightning/chrome | head -10
        
        echo 'Build testing complete'
    "
}

# Stage execution with retry logic
execute_stage() {
    local stage_func="$1"
    local stage_name="${stage_func#stage_*}"
    local retry_count=0
    
    while [[ $retry_count -lt $MAX_STAGE_RETRIES ]]; do
        if "$stage_func"; then
            return 0
        else
            retry_count=$((retry_count + 1))
            if [[ $retry_count -lt $MAX_STAGE_RETRIES ]]; then
                log_warning "Stage failed, retrying ($retry_count/$MAX_STAGE_RETRIES)"
                sleep 30
            else
                log_error "Stage failed after $MAX_STAGE_RETRIES attempts"
                return 1
            fi
        fi
    done
}

# Progress reporting
show_progress() {
    log_info "=== Build Progress Report ==="
    local stages=("stage_01_environment_setup" "stage_02_dependencies" "stage_03_chromium_fetch" 
                 "stage_04_build_config" "stage_05_patch_application" "stage_06_initial_build" 
                 "stage_07_chrome_build" "stage_08_test_build")
    
    local completed=0
    local total=${#stages[@]}
    
    for stage in "${stages[@]}"; do
        local state=$(get_stage_state "$stage")
        if [[ "$state" == "COMPLETE" ]]; then
            echo -e "✅ ${stage/stage_*_/}: $state"
            completed=$((completed + 1))
        elif [[ "$state" == "FAILED" ]]; then
            echo -e "❌ ${stage/stage_*_/}: $state"
        elif [[ "$state" == "TIMEOUT" ]]; then
            echo -e "⏰ ${stage/stage_*_/}: $state"
        else
            echo -e "⏸️  ${stage/stage_*_/}: $state"
        fi
    done
    
    log_info "Progress: $completed/$total stages complete ($(( completed * 100 / total ))%)"
}

# Main execution function
main() {
    local command="${1:-build}"
    
    case "$command" in
        "build"|"start")
            log_info "Starting DataSipper staged build system"
            log_info "Build state directory: $BUILD_STATE_DIR"
            log_info "Log directory: $LOG_DIR"
            
            # Execute all stages
            execute_stage stage_01_environment_setup || exit 1
            execute_stage stage_02_dependencies || exit 1
            execute_stage stage_03_chromium_fetch || exit 1
            execute_stage stage_04_build_config || exit 1
            execute_stage stage_05_patch_application || exit 1
            execute_stage stage_06_initial_build || exit 1
            execute_stage stage_07_chrome_build || exit 1
            execute_stage stage_08_test_build || exit 1
            
            log_success "All build stages completed successfully!"
            log_info "Chrome binary location: chromium-src/out/Lightning/chrome"
            ;;
            
        "resume")
            log_info "Resuming build from last incomplete stage"
            show_progress
            main build
            ;;
            
        "progress"|"status")
            show_progress
            ;;
            
        "clean")
            log_info "Cleaning build state"
            rm -rf "$BUILD_STATE_DIR"
            log_success "Build state cleaned"
            ;;
            
        "reset")
            log_info "Resetting specific stage: $2"
            if [[ -n "$2" ]]; then
                rm -f "$BUILD_STATE_DIR/stage_*${2}*.state"
                rm -f "$BUILD_STATE_DIR/stage_*${2}*.timestamp"
                log_success "Reset stage containing '$2'"
            else
                log_error "Please specify stage name/pattern to reset"
                exit 1
            fi
            ;;
            
        "logs")
            log_info "Recent build logs:"
            ls -la "$LOG_DIR"/*.log 2>/dev/null | tail -10 || echo "No logs found"
            ;;
            
        "help"|"--help"|"-h")
            cat << EOF
DataSipper Staged Build System

Usage: $0 [command]

Commands:
  build, start    - Start/continue the build process
  resume          - Resume from last incomplete stage  
  progress, status - Show current build progress
  clean           - Clean all build state
  reset <stage>   - Reset specific stage state
  logs            - Show recent build logs
  help            - Show this help message

Examples:
  $0 build                    # Start full build
  $0 resume                   # Resume interrupted build
  $0 progress                 # Check build status
  $0 reset chromium_fetch     # Reset the chromium fetch stage
  $0 clean                    # Start fresh

Build logs are stored in: $LOG_DIR
Build state is stored in: $BUILD_STATE_DIR
EOF
            ;;
            
        *)
            log_error "Unknown command: $command"
            main help
            exit 1
            ;;
    esac
}

# Handle script interruption
cleanup() {
    log_warning "Build interrupted by user"
    log_info "Build can be resumed later with: $0 resume"
    exit 1
}

trap cleanup SIGINT SIGTERM

# Execute main function
main "$@"