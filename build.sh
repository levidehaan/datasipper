#!/bin/bash

# DataSipper Master Build Controller
# Single entry point for all build operations

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    DataSipper Build System                   ║"
    echo "║            Network Monitoring Browser Project                ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log() {
    echo -e "${BLUE}[BUILD-MASTER]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    local missing_deps=()
    
    # Check essential tools
    if ! command -v git >/dev/null 2>&1; then
        missing_deps+=("git")
    fi
    
    if ! command -v python3 >/dev/null 2>&1; then
        missing_deps+=("python3")
    fi
    
    if ! command -v ninja >/dev/null 2>&1 && ! command -v ninja-build >/dev/null 2>&1; then
        missing_deps+=("ninja")
    fi
    
    # Check if we're in the right directory
    if [[ ! -f "README.md" ]] || [[ ! -d "patches" ]]; then
        error "This doesn't appear to be the DataSipper project root"
        error "Please run this script from the project root directory"
        exit 1
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error "Missing dependencies: ${missing_deps[*]}"
        error "Please install them first or run: ./build.sh setup"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# System setup
setup_system() {
    log "Setting up system dependencies..."
    chmod +x scripts/*.sh
    chmod +x build_scripts/*.sh
    
    # Run appropriate setup script
    if [[ -f scripts/dev-setup-universal.sh ]]; then
        ./scripts/dev-setup-universal.sh
    else
        error "Setup script not found"
        exit 1
    fi
    
    success "System setup completed"
}

# Full staged build
full_build() {
    log "Starting full staged build..."
    check_prerequisites
    
    if [[ ! -f scripts/staged-build-system.sh ]]; then
        error "Staged build system not found"
        exit 1
    fi
    
    chmod +x scripts/staged-build-system.sh
    ./scripts/staged-build-system.sh build
}

# Quick incremental build
quick_build() {
    log "Starting quick incremental build..."
    check_prerequisites
    
    if [[ ! -f scripts/quick-build.sh ]]; then
        error "Quick build system not found"
        exit 1
    fi
    
    chmod +x scripts/quick-build.sh
    ./scripts/quick-build.sh chrome
}

# Resume interrupted build
resume_build() {
    log "Resuming interrupted build..."
    check_prerequisites
    
    if [[ ! -f scripts/staged-build-system.sh ]]; then
        error "Staged build system not found"
        exit 1
    fi
    
    chmod +x scripts/staged-build-system.sh
    ./scripts/staged-build-system.sh resume
}

# Check build status
check_status() {
    log "Checking build status..."
    
    # Check if staged build system exists
    if [[ -f scripts/staged-build-system.sh ]]; then
        chmod +x scripts/staged-build-system.sh
        ./scripts/staged-build-system.sh status
    else
        warning "Staged build system not available"
    fi
    
    # Check if Chrome binary exists
    if [[ -f chromium-src/out/Lightning/chrome ]]; then
        success "Chrome binary found:"
        ls -lh chromium-src/out/Lightning/chrome
    else
        warning "Chrome binary not found"
    fi
    
    # Check patches status
    if [[ -f scripts/patches.py ]]; then
        log "Patch status:"
        python3 scripts/patches.py status
    fi
}

# Test the build
test_build() {
    log "Testing build..."
    check_prerequisites
    
    if [[ ! -f scripts/quick-build.sh ]]; then
        error "Quick build system not found"
        exit 1
    fi
    
    chmod +x scripts/quick-build.sh
    ./scripts/quick-build.sh run-test
}

# Clean build artifacts
clean_build() {
    log "Cleaning build artifacts..."
    
    # Clean staged build state
    if [[ -f scripts/staged-build-system.sh ]]; then
        chmod +x scripts/staged-build-system.sh
        ./scripts/staged-build-system.sh clean
    fi
    
    # Clean quick build artifacts
    if [[ -f scripts/quick-build.sh ]]; then
        chmod +x scripts/quick-build.sh
        ./scripts/quick-build.sh clean
    fi
    
    # Clean Chromium build directory
    if [[ -d chromium-src/out ]]; then
        log "Removing Chromium build directory..."
        rm -rf chromium-src/out
    fi
    
    success "Build artifacts cleaned"
}

# Development mode (patch and quick build)
dev_mode() {
    log "Starting development mode..."
    check_prerequisites
    
    if [[ ! -f scripts/quick-build.sh ]]; then
        error "Quick build system not found"
        exit 1
    fi
    
    chmod +x scripts/quick-build.sh
    ./scripts/quick-build.sh patch-build
}

# Show build logs
show_logs() {
    log "Showing recent build logs..."
    
    if [[ -d build-logs ]]; then
        echo "=== Recent log files ==="
        ls -la build-logs/*.log 2>/dev/null | tail -10 || echo "No logs found"
        
        echo -e "\n=== Latest staged build log (last 20 lines) ==="
        if [[ -f build-logs/staged-build.log ]]; then
            tail -20 build-logs/staged-build.log
        else
            echo "No staged build log found"
        fi
    else
        warning "Build logs directory not found"
    fi
}

# Show system info
show_system_info() {
    log "System Information:"
    echo "  OS: $(uname -s) $(uname -r)"
    echo "  CPU: $(nproc) cores"
    echo "  Memory: $(free -h | grep '^Mem:' | awk '{print $2}') total"
    echo "  Disk free: $(df -h . | tail -1 | awk '{print $4}')"
    echo "  Python: $(python3 --version 2>/dev/null || echo 'Not found')"
    echo "  Git: $(git --version 2>/dev/null || echo 'Not found')"
    echo "  Ninja: $(ninja --version 2>/dev/null || ninja-build --version 2>/dev/null || echo 'Not found')"
    
    if [[ -f CHROMIUM_VERSION.txt ]]; then
        echo "  Target Chromium: $(cat CHROMIUM_VERSION.txt)"
    fi
}

# Usage information
usage() {
    print_banner
    cat << EOF
${PURPLE}DataSipper Build System - Master Controller${NC}

${YELLOW}Basic Commands:${NC}
  ${GREEN}setup${NC}           Setup system dependencies and environment
  ${GREEN}build${NC}           Full staged build (1-2 hours first time)
  ${GREEN}quick${NC}           Quick incremental build (5-15 minutes)
  ${GREEN}resume${NC}          Resume interrupted staged build
  ${GREEN}test${NC}            Test if build works correctly
  ${GREEN}dev${NC}             Development mode (apply patches + quick build)

${YELLOW}Information Commands:${NC}
  ${GREEN}status${NC}          Check current build status and progress
  ${GREEN}logs${NC}            Show recent build logs
  ${GREEN}info${NC}            Show system information
  ${GREEN}help${NC}            Show this help message

${YELLOW}Maintenance Commands:${NC}
  ${GREEN}clean${NC}           Clean all build artifacts and state
  ${GREEN}reset${NC}           Reset specific build stage (use with stage name)

${YELLOW}Examples:${NC}
  ${CYAN}./build.sh setup${NC}              # First time setup
  ${CYAN}./build.sh build${NC}              # Full build from scratch
  ${CYAN}./build.sh quick${NC}              # Fast rebuild after changes
  ${CYAN}./build.sh dev${NC}                # Apply patches and rebuild
  ${CYAN}./build.sh status${NC}             # Check what's been built
  ${CYAN}./build.sh test${NC}               # Verify build works

${YELLOW}Build Process Overview:${NC}
  1. ${GREEN}setup${NC}     - Install dependencies (once)
  2. ${GREEN}build${NC}     - Full staged build (1-2 hours)
  3. ${GREEN}quick${NC}     - Fast incremental builds (5-15 min)
  4. ${GREEN}test${NC}      - Verify functionality
  5. ${GREEN}dev${NC}       - Development workflow

${YELLOW}Build Stages (staged build):${NC}
  Stage 1: Environment Setup (10 min)
  Stage 2: Dependencies (15 min)  
  Stage 3: Chromium Fetch (40 min)
  Stage 4: Build Config (5 min)
  Stage 5: Patch Application (10 min)
  Stage 6: Initial Build (60 min)
  Stage 7: Chrome Build (80 min)
  Stage 8: Test Build (10 min)

${YELLOW}Advanced Usage:${NC}
  ${CYAN}./scripts/staged-build-system.sh${NC} - Direct staged build access
  ${CYAN}./scripts/quick-build.sh${NC}         - Direct quick build access
  ${CYAN}./build_scripts/manage_patches.sh${NC} - Direct patch management

${RED}Important Notes:${NC}
  - First build takes 1-2 hours with good internet
  - Requires ~50GB disk space for full build
  - Builds are resumable if interrupted
  - Use 'quick' for daily development
  - Use 'build' only for major changes

EOF
}

# Main execution
main() {
    local command="${1:-help}"
    
    case "$command" in
        "setup")
            print_banner
            setup_system
            ;;
        "build"|"full")
            print_banner
            full_build
            ;;
        "quick"|"incremental")
            quick_build
            ;;
        "resume")
            resume_build
            ;;
        "status"|"progress")
            check_status
            ;;
        "test"|"verify")
            test_build
            ;;
        "clean")
            clean_build
            ;;
        "dev"|"development")
            dev_mode
            ;;
        "logs")
            show_logs
            ;;
        "info"|"system")
            show_system_info
            ;;
        "reset")
            if [[ -n "$2" ]]; then
                if [[ -f scripts/staged-build-system.sh ]]; then
                    chmod +x scripts/staged-build-system.sh
                    ./scripts/staged-build-system.sh reset "$2"
                else
                    error "Staged build system not found"
                fi
            else
                error "Please specify stage to reset"
                echo "Example: ./build.sh reset chromium_fetch"
            fi
            ;;
        "help"|"--help"|"-h"|"")
            usage
            ;;
        *)
            error "Unknown command: $command"
            echo "Run './build.sh help' for usage information"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"