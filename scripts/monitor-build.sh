#!/bin/bash

# DataSipper Build Monitor
# Tracks ninja build progress and estimates completion time

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

WORKSPACE_DIR="/workspace"
SRC_DIR="${WORKSPACE_DIR}/src"
LOG_DIR="${WORKSPACE_DIR}/build-logs"
STATUS_FILE="${LOG_DIR}/build-status.log"

mkdir -p "${LOG_DIR}"

# Function to get current timestamp
timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Function to get build progress
get_build_progress() {
    cd "${SRC_DIR}"
    
    # Check if ninja is running
    NINJA_PID=$(pgrep -f "ninja.*chrome" || echo "")
    
    if [ -z "$NINJA_PID" ]; then
        echo "NO_BUILD_RUNNING"
        return
    fi
    
    # Get ninja progress
    NINJA_PROGRESS=$(ninja -C out/Lightning -t query chrome 2>/dev/null | grep "outputs built" || echo "")
    
    # Get system stats
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    MEMORY_USAGE=$(free -m | awk 'NR==2{printf "%.1f%%", $3*100/$2}')
    DISK_USAGE=$(df -h out/Lightning 2>/dev/null | awk 'NR==2{print $3}')
    
    # Get number of ninja jobs running
    NINJA_JOBS=$(pgrep -f "ninja" | wc -l)
    
    echo "RUNNING|${NINJA_PID}|${NINJA_PROGRESS}|CPU:${CPU_USAGE}%|MEM:${MEMORY_USAGE}|DISK:${DISK_USAGE}|JOBS:${NINJA_JOBS}"
}

# Function to estimate completion time
estimate_completion() {
    local progress_line="$1"
    
    if [[ "$progress_line" =~ ([0-9]+)/([0-9]+) ]]; then
        local completed="${BASH_REMATCH[1]}"
        local total="${BASH_REMATCH[2]}"
        local percentage=$((completed * 100 / total))
        
        # Get build start time from process
        local start_time=$(ps -o lstart= -p "$NINJA_PID" 2>/dev/null || echo "")
        if [ -n "$start_time" ]; then
            local start_epoch=$(date -d "$start_time" +%s 2>/dev/null || echo "")
            local current_epoch=$(date +%s)
            local elapsed=$((current_epoch - start_epoch))
            
            if [ $percentage -gt 0 ] && [ $elapsed -gt 0 ]; then
                local estimated_total=$((elapsed * 100 / percentage))
                local remaining=$((estimated_total - elapsed))
                local eta=$(date -d "@$((current_epoch + remaining))" '+%H:%M:%S' 2>/dev/null || echo "Unknown")
                echo "${percentage}%|ETA:${eta}|Elapsed:$((elapsed/60))min"
            else
                echo "${percentage}%|Calculating..."
            fi
        else
            echo "${percentage}%|Unknown timing"
        fi
    else
        echo "Progress parsing failed"
    fi
}

# Function to check for build artifacts
check_build_artifacts() {
    cd "${SRC_DIR}"
    
    # Check for Chrome binary
    if [ -f "out/Lightning/chrome" ]; then
        CHROME_SIZE=$(du -h out/Lightning/chrome | cut -f1)
        echo "CHROME_BINARY:${CHROME_SIZE}"
    else
        echo "CHROME_BINARY:Not_Found"
    fi
    
    # Check build directory size
    BUILD_DIR_SIZE=$(du -sh out/Lightning 2>/dev/null | cut -f1 || echo "Unknown")
    echo "BUILD_DIR:${BUILD_DIR_SIZE}"
    
    # Count object files
    OBJ_COUNT=$(find out/Lightning -name "*.o" | wc -l 2>/dev/null || echo "0")
    echo "OBJECT_FILES:${OBJ_COUNT}"
}

# Function to display status
display_status() {
    local status="$1"
    local timestamp="$2"
    
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}                         ${PURPLE}DataSipper Build Monitor${NC}                          ${BLUE}║${NC}"
    echo -e "${BLUE}╠═══════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC} ${CYAN}Timestamp:${NC} ${timestamp}                                           ${BLUE}║${NC}"
    
    if [[ "$status" == "NO_BUILD_RUNNING" ]]; then
        echo -e "${BLUE}║${NC} ${RED}Status: No build currently running${NC}                                     ${BLUE}║${NC}"
        
        # Check if build completed successfully
        if [ -f "${SRC_DIR}/out/Lightning/chrome" ]; then
            CHROME_SIZE=$(du -h "${SRC_DIR}/out/Lightning/chrome" | cut -f1)
            echo -e "${BLUE}║${NC} ${GREEN}✅ Build Completed! Chrome binary: ${CHROME_SIZE}${NC}                           ${BLUE}║${NC}"
        else
            echo -e "${BLUE}║${NC} ${YELLOW}⚠️  Build may have failed or interrupted${NC}                               ${BLUE}║${NC}"
        fi
    else
        IFS='|' read -ra PARTS <<< "$status"
        local ninja_pid="${PARTS[1]}"
        local progress="${PARTS[2]}"
        local cpu="${PARTS[3]}"
        local memory="${PARTS[4]}"
        local disk="${PARTS[5]}"
        local jobs="${PARTS[6]}"
        
        echo -e "${BLUE}║${NC} ${GREEN}Status: Build running (PID: ${ninja_pid})${NC}                               ${BLUE}║${NC}"
        echo -e "${BLUE}║${NC} ${CYAN}Progress:${NC} ${progress}                                                  ${BLUE}║${NC}"
        
        # Estimate completion
        local estimate=$(estimate_completion "$progress")
        echo -e "${BLUE}║${NC} ${YELLOW}Estimate:${NC} ${estimate}                                              ${BLUE}║${NC}"
        
        echo -e "${BLUE}║${NC} ${CYAN}System:${NC} ${cpu} | ${memory} | Disk: ${disk} | Jobs: ${jobs}              ${BLUE}║${NC}"
    fi
    
    # Show build artifacts
    local artifacts=$(check_build_artifacts)
    echo -e "${BLUE}║${NC} ${CYAN}Artifacts:${NC}                                                            ${BLUE}║${NC}"
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            echo -e "${BLUE}║${NC}   ${line}                                                           ${BLUE}║${NC}"
        fi
    done <<< "$artifacts"
    
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
}

# Main monitoring function
monitor_build() {
    local interval="${1:-300}"  # Default 5 minutes
    local max_checks="${2:-999}" # Default unlimited
    local check_count=0
    
    echo -e "${GREEN}Starting DataSipper build monitoring (checking every ${interval} seconds)${NC}\n"
    
    while [ $check_count -lt $max_checks ]; do
        local current_time=$(timestamp)
        local build_status=$(get_build_progress)
        
        # Display status
        display_status "$build_status" "$current_time"
        
        # Log to file
        echo "${current_time}|${build_status}" >> "${STATUS_FILE}"
        
        # Check if build completed
        if [[ "$build_status" == "NO_BUILD_RUNNING" ]]; then
            echo -e "\n${GREEN}Build monitoring complete!${NC}"
            break
        fi
        
        check_count=$((check_count + 1))
        echo -e "\n${CYAN}Next check in ${interval} seconds... (Check ${check_count}/${max_checks})${NC}\n"
        sleep "$interval"
    done
}

# Command line interface
case "${1:-monitor}" in
    "monitor")
        monitor_build "${2:-300}" "${3:-999}"
        ;;
    "status")
        current_time=$(timestamp)
        build_status=$(get_build_progress)
        display_status "$build_status" "$current_time"
        ;;
    "log")
        echo -e "${CYAN}Recent build status log:${NC}"
        tail -20 "${STATUS_FILE}" 2>/dev/null || echo "No log file found"
        ;;
    "artifacts")
        echo -e "${CYAN}Current build artifacts:${NC}"
        check_build_artifacts
        ;;
    "help")
        echo -e "${GREEN}DataSipper Build Monitor Commands:${NC}"
        echo "  monitor [interval] [max_checks] - Monitor build progress (default: 5min intervals)"
        echo "  status                          - Show current build status"
        echo "  log                            - Show recent status log"
        echo "  artifacts                      - Show current build artifacts"
        echo "  help                           - Show this help"
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo "Use './monitor-build.sh help' for usage information"
        exit 1
        ;;
esac