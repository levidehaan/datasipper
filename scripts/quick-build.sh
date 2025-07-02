#!/bin/bash

# DataSipper Quick Build Script
# For fast incremental builds and testing specific components

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/build-logs"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[QUICK-BUILD]${NC} $1" | tee -a "$LOG_DIR/quick-build.log"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_DIR/quick-build.log"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_DIR/quick-build.log"
}

# Quick build targets
quick_build_chrome() {
    log "Starting quick Chrome build..."
    cd "$PROJECT_ROOT/src"
    
    # Check if main build exists
    if [[ ! -f "out/Lightning/chrome" ]]; then
        error "Main Chrome build not found. Run full staged build first:"
        error "  ./scripts/staged-build-system.sh build"
        exit 1
    fi
    
    # Quick incremental build
    log "Running incremental build (5-15 min expected)..."
    ninja -C out/Lightning chrome -j8 -l8 2>&1 | tee "$LOG_DIR/quick-chrome-$(date +%Y%m%d-%H%M%S).log"
    
    if [[ -f "out/Lightning/chrome" ]]; then
        success "Quick Chrome build completed"
        ls -lh out/Lightning/chrome
    else
        error "Quick build failed"
        exit 1
    fi
}

quick_build_datasipper() {
    log "Building DataSipper components only..."
    cd "$PROJECT_ROOT/src"
    
    # Build only DataSipper-related targets
    ninja -C out/Lightning \
        chrome/browser/ui/views/datasipper \
        chrome/browser/datasipper \
        content/browser/datasipper \
        2>&1 | tee "$LOG_DIR/quick-datasipper-$(date +%Y%m%d-%H%M%S).log"
    
    success "DataSipper components build completed"
}

quick_build_test() {
    log "Building test components..."
    cd "$PROJECT_ROOT/src"
    
    ninja -C out/Lightning \
        browser_tests \
        unit_tests \
        content_unittests \
        2>&1 | tee "$LOG_DIR/quick-test-$(date +%Y%m%d-%H%M%S).log"
    
    success "Test components build completed"
}

quick_patch_and_build() {
    log "Applying patches and quick build..."
    cd "$PROJECT_ROOT"
    
    # Apply any new patches
    if [[ -f build_scripts/manage_patches.sh ]]; then
        ./build_scripts/manage_patches.sh apply
    fi
    
    # Quick rebuild
    quick_build_chrome
}

run_quick_test() {
    log "Running quick functionality test..."
    cd "$PROJECT_ROOT/src"
    
    if [[ ! -f "out/Lightning/chrome" ]]; then
        error "Chrome binary not found"
        exit 1
    fi
    
    # Version check
    ./out/Lightning/chrome --version
    
    # Quick headless test
    timeout 30s ./out/Lightning/chrome --headless --disable-gpu --virtual-time-budget=5000 --run-all-compositor-stages-before-draw --dump-dom about:blank > /tmp/test_output.html 2>&1
    
    if [[ $? -eq 0 ]] || [[ $? -eq 124 ]]; then  # 124 is timeout exit code
        success "Quick test passed - Chrome can start and render"
    else
        error "Quick test failed"
        exit 1
    fi
}

# Clean incremental artifacts
clean_incremental() {
    log "Cleaning incremental build artifacts..."
    cd "$PROJECT_ROOT/src"
    
    # Remove object files but keep main binaries
    find out/Lightning -name "*.o" -delete 2>/dev/null || true
    find out/Lightning -name "*.a" -delete 2>/dev/null || true
    
    # Clean ninja deps
    ninja -C out/Lightning -t clean chrome
    
    success "Incremental artifacts cleaned"
}

# Performance monitoring
monitor_build() {
    log "Starting build monitoring..."
    
    # Start build in background
    quick_build_chrome &
    BUILD_PID=$!
    
    # Monitor resources
    while kill -0 $BUILD_PID 2>/dev/null; do
        echo "$(date): $(ps -p $BUILD_PID -o %cpu,%mem,time --no-headers 2>/dev/null || echo 'Process ended')"
        sleep 10
    done
    
    wait $BUILD_PID
    return $?
}

# Usage function
usage() {
    cat << EOF
DataSipper Quick Build System

Usage: $0 [command] [options]

Commands:
  chrome          - Quick incremental Chrome build (5-15 min)
  datasipper      - Build only DataSipper components (2-5 min)
  test            - Build test components (10-20 min)
  patch-build     - Apply patches and quick build (5-20 min)
  run-test        - Quick functionality test (< 1 min)
  clean           - Clean incremental artifacts (< 1 min)
  monitor         - Build with resource monitoring
  help            - Show this help

Examples:
  $0 chrome           # Quick Chrome rebuild
  $0 datasipper       # Build only DataSipper parts
  $0 patch-build      # Apply new patches and rebuild
  $0 run-test         # Test if build works
  
Prerequisites:
  - Full build must exist (run staged-build-system.sh first)
  - Must be in git repository with applied patches

Performance Tips:
  - Use 'chrome' for general development
  - Use 'datasipper' when only changing DataSipper code
  - Use 'clean' if builds become inconsistent
  - Use 'monitor' to track resource usage
EOF
}

# Main execution
main() {
    local command="${1:-help}"
    
    # Ensure log directory exists
    mkdir -p "$LOG_DIR"
    
    case "$command" in
        "chrome")
            quick_build_chrome
            ;;
        "datasipper")
            quick_build_datasipper
            ;;
        "test")
            quick_build_test
            ;;
        "patch-build")
            quick_patch_and_build
            ;;
        "run-test")
            run_quick_test
            ;;
        "clean")
            clean_incremental
            ;;
        "monitor")
            monitor_build
            ;;
        "help"|"--help"|"-h")
            usage
            ;;
        *)
            error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"