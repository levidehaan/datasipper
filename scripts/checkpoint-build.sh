#!/bin/bash

# DataSipper Build Checkpoint System
# Saves and restores build state for long-running Chromium builds

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Directories
WORKSPACE_DIR="/workspace"
SRC_DIR="${WORKSPACE_DIR}/src"
CHECKPOINT_DIR="${WORKSPACE_DIR}/.checkpoints"
LOG_DIR="${WORKSPACE_DIR}/build-logs"

# Create directories
mkdir -p "${CHECKPOINT_DIR}" "${LOG_DIR}"

# Function to get current timestamp
timestamp() {
    date '+%Y%m%d_%H%M%S'
}

# Function to get human readable timestamp
human_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Function to create checkpoint
create_checkpoint() {
    local checkpoint_name="${1:-auto_$(timestamp)}"
    local checkpoint_path="${CHECKPOINT_DIR}/${checkpoint_name}"
    
    echo -e "${BLUE}Creating checkpoint: ${checkpoint_name}${NC}"
    
    # Create checkpoint directory
    mkdir -p "${checkpoint_path}"
    
    # Save build state information
    echo "$(human_timestamp)" > "${checkpoint_path}/timestamp"
    
    # Check if ninja is running and get PID
    NINJA_PID=$(pgrep -f "ninja.*chrome" || echo "")
    echo "${NINJA_PID}" > "${checkpoint_path}/ninja_pid"
    
    # Save system information
    free -m > "${checkpoint_path}/memory_usage"
    df -h "${SRC_DIR}/out/Lightning" > "${checkpoint_path}/disk_usage" 2>/dev/null || echo "Build dir not found" > "${checkpoint_path}/disk_usage"
    
    # Count compiled objects
    find "${SRC_DIR}/out/Lightning" -name "*.o" 2>/dev/null | wc -l > "${checkpoint_path}/object_count" || echo "0" > "${checkpoint_path}/object_count"
    
    # Check build directory size
    du -sh "${SRC_DIR}/out/Lightning" 2>/dev/null | cut -f1 > "${checkpoint_path}/build_size" || echo "0B" > "${checkpoint_path}/build_size"
    
    # Save ninja progress if available
    cd "${SRC_DIR}" 2>/dev/null && ninja -C out/Lightning -t query chrome 2>/dev/null > "${checkpoint_path}/ninja_progress" || echo "Progress unavailable" > "${checkpoint_path}/ninja_progress"
    
    # Save git state
    cd "${SRC_DIR}" 2>/dev/null && git status --porcelain > "${checkpoint_path}/git_status" || echo "Git status unavailable" > "${checkpoint_path}/git_status"
    
    # Save applied patches info
    ls -la "${WORKSPACE_DIR}/patches/" > "${checkpoint_path}/patches_available" 2>/dev/null || echo "No patches dir" > "${checkpoint_path}/patches_available"
    
    # Save current environment info
    env | grep -E "(CHROMIUM|GN|DEPOT|ninja)" > "${checkpoint_path}/environment" || echo "No relevant env vars" > "${checkpoint_path}/environment"
    
    # Check if Chrome binary exists
    if [ -f "${SRC_DIR}/out/Lightning/chrome" ]; then
        ls -lh "${SRC_DIR}/out/Lightning/chrome" > "${checkpoint_path}/chrome_binary"
        echo "SUCCESS" > "${checkpoint_path}/build_status"
    else
        echo "Chrome binary not found" > "${checkpoint_path}/chrome_binary"
        if [ -n "$NINJA_PID" ]; then
            echo "IN_PROGRESS" > "${checkpoint_path}/build_status"
        else
            echo "STOPPED" > "${checkpoint_path}/build_status"
        fi
    fi
    
    # Create summary
    echo -e "${GREEN}Checkpoint '${checkpoint_name}' created successfully!${NC}"
    echo -e "${CYAN}Summary:${NC}"
    echo "  Timestamp: $(cat "${checkpoint_path}/timestamp")"
    echo "  Build Status: $(cat "${checkpoint_path}/build_status")"
    echo "  Build Size: $(cat "${checkpoint_path}/build_size")"
    echo "  Object Files: $(cat "${checkpoint_path}/object_count")"
    echo "  Ninja PID: $(cat "${checkpoint_path}/ninja_pid")"
    
    # Log checkpoint creation
    echo "$(human_timestamp)|CREATE|${checkpoint_name}|$(cat "${checkpoint_path}/build_status")|$(cat "${checkpoint_path}/build_size")" >> "${LOG_DIR}/checkpoint.log"
}

# Function to list checkpoints
list_checkpoints() {
    echo -e "${BLUE}Available checkpoints:${NC}"
    echo
    
    if [ ! -d "${CHECKPOINT_DIR}" ] || [ -z "$(ls -A "${CHECKPOINT_DIR}" 2>/dev/null)" ]; then
        echo -e "${YELLOW}No checkpoints found${NC}"
        return
    fi
    
    printf "%-25s %-20s %-12s %-12s %-10s\n" "CHECKPOINT" "TIMESTAMP" "STATUS" "SIZE" "OBJECTS"
    printf "%-25s %-20s %-12s %-12s %-10s\n" "----------" "---------" "------" "----" "-------"
    
    for checkpoint in "${CHECKPOINT_DIR}"/*; do
        if [ -d "$checkpoint" ]; then
            local name=$(basename "$checkpoint")
            local timestamp=$(cat "$checkpoint/timestamp" 2>/dev/null || echo "Unknown")
            local status=$(cat "$checkpoint/build_status" 2>/dev/null || echo "Unknown")
            local size=$(cat "$checkpoint/build_size" 2>/dev/null || echo "Unknown")
            local objects=$(cat "$checkpoint/object_count" 2>/dev/null || echo "Unknown")
            
            # Truncate timestamp for display
            timestamp_short=$(echo "$timestamp" | cut -d' ' -f2)
            
            printf "%-25s %-20s %-12s %-12s %-10s\n" "$name" "$timestamp_short" "$status" "$size" "$objects"
        fi
    done
}

# Function to show checkpoint details
show_checkpoint() {
    local checkpoint_name="$1"
    local checkpoint_path="${CHECKPOINT_DIR}/${checkpoint_name}"
    
    if [ ! -d "$checkpoint_path" ]; then
        echo -e "${RED}Checkpoint '${checkpoint_name}' not found${NC}"
        return 1
    fi
    
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}                     ${PURPLE}Checkpoint Details: ${checkpoint_name}${NC}                      ${BLUE}║${NC}"
    echo -e "${BLUE}╠═══════════════════════════════════════════════════════════════════════════════╣${NC}"
    
    # Basic info
    echo -e "${BLUE}║${NC} ${CYAN}Timestamp:${NC} $(cat "$checkpoint_path/timestamp" 2>/dev/null || echo "Unknown")                                    ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} ${CYAN}Status:${NC} $(cat "$checkpoint_path/build_status" 2>/dev/null || echo "Unknown")                                       ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} ${CYAN}Build Size:${NC} $(cat "$checkpoint_path/build_size" 2>/dev/null || echo "Unknown")                                   ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} ${CYAN}Object Files:${NC} $(cat "$checkpoint_path/object_count" 2>/dev/null || echo "Unknown")                               ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} ${CYAN}Ninja PID:${NC} $(cat "$checkpoint_path/ninja_pid" 2>/dev/null || echo "Unknown")                                   ${BLUE}║${NC}"
    
    # Memory and disk
    echo -e "${BLUE}║${NC}                                                                               ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} ${CYAN}System Resources:${NC}                                                         ${BLUE}║${NC}"
    if [ -f "$checkpoint_path/memory_usage" ]; then
        local mem_line=$(grep "^Mem:" "$checkpoint_path/memory_usage" | awk '{printf "Used: %s/%s MB", $3, $2}')
        echo -e "${BLUE}║${NC}   Memory: ${mem_line}                                          ${BLUE}║${NC}"
    fi
    if [ -f "$checkpoint_path/disk_usage" ]; then
        local disk_line=$(tail -1 "$checkpoint_path/disk_usage" | awk '{print $3 " used"}')
        echo -e "${BLUE}║${NC}   Disk: ${disk_line}                                               ${BLUE}║${NC}"
    fi
    
    # Build progress
    echo -e "${BLUE}║${NC}                                                                               ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} ${CYAN}Build Progress:${NC}                                                           ${BLUE}║${NC}"
    if [ -f "$checkpoint_path/ninja_progress" ]; then
        local progress=$(head -1 "$checkpoint_path/ninja_progress")
        echo -e "${BLUE}║${NC}   ${progress}                                                    ${BLUE}║${NC}"
    fi
    
    # Chrome binary status
    if [ -f "$checkpoint_path/chrome_binary" ]; then
        echo -e "${BLUE}║${NC}                                                                               ${BLUE}║${NC}"
        echo -e "${BLUE}║${NC} ${CYAN}Chrome Binary:${NC}                                                          ${BLUE}║${NC}"
        local binary_info=$(cat "$checkpoint_path/chrome_binary")
        echo -e "${BLUE}║${NC}   ${binary_info}                                              ${BLUE}║${NC}"
    fi
    
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
}

# Function to delete checkpoint
delete_checkpoint() {
    local checkpoint_name="$1"
    local checkpoint_path="${CHECKPOINT_DIR}/${checkpoint_name}"
    
    if [ ! -d "$checkpoint_path" ]; then
        echo -e "${RED}Checkpoint '${checkpoint_name}' not found${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}Are you sure you want to delete checkpoint '${checkpoint_name}'? (y/N)${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        rm -rf "$checkpoint_path"
        echo -e "${GREEN}Checkpoint '${checkpoint_name}' deleted${NC}"
        # Log deletion
        echo "$(human_timestamp)|DELETE|${checkpoint_name}|||" >> "${LOG_DIR}/checkpoint.log"
    else
        echo -e "${CYAN}Deletion cancelled${NC}"
    fi
}

# Function to clean old checkpoints
clean_checkpoints() {
    local days="${1:-7}"
    echo -e "${YELLOW}Cleaning checkpoints older than ${days} days...${NC}"
    
    find "${CHECKPOINT_DIR}" -type d -name "*_*" -mtime +${days} -print0 | while IFS= read -r -d '' checkpoint; do
        local name=$(basename "$checkpoint")
        echo -e "${CYAN}Removing old checkpoint: ${name}${NC}"
        rm -rf "$checkpoint"
        echo "$(human_timestamp)|CLEAN|${name}|||" >> "${LOG_DIR}/checkpoint.log"
    done
    
    echo -e "${GREEN}Cleanup complete${NC}"
}

# Function to create automatic checkpoint if build is running
auto_checkpoint() {
    local ninja_pid=$(pgrep -f "ninja.*chrome" || echo "")
    
    if [ -n "$ninja_pid" ]; then
        echo -e "${CYAN}Build detected (PID: ${ninja_pid}), creating automatic checkpoint...${NC}"
        create_checkpoint "auto_$(timestamp)"
    else
        echo -e "${YELLOW}No active build detected${NC}"
        
        # Check if Chrome binary was successfully created
        if [ -f "${SRC_DIR}/out/Lightning/chrome" ]; then
            echo -e "${GREEN}Chrome binary found! Creating success checkpoint...${NC}"
            create_checkpoint "success_$(timestamp)"
        fi
    fi
}

# Function to monitor and create periodic checkpoints
monitor_checkpoints() {
    local interval="${1:-3600}"  # Default 1 hour
    local max_checks="${2:-24}"  # Default 24 hours
    local check_count=0
    
    echo -e "${GREEN}Starting automatic checkpoint monitoring (every $((interval/60)) minutes)${NC}"
    
    while [ $check_count -lt $max_checks ]; do
        auto_checkpoint
        
        check_count=$((check_count + 1))
        if [ $check_count -lt $max_checks ]; then
            echo -e "${CYAN}Next checkpoint in $((interval/60)) minutes... (${check_count}/${max_checks})${NC}"
            sleep "$interval"
        fi
    done
    
    echo -e "${GREEN}Checkpoint monitoring complete${NC}"
}

# Command line interface
case "${1:-help}" in
    "create"|"checkpoint")
        create_checkpoint "$2"
        ;;
    "list"|"ls")
        list_checkpoints
        ;;
    "show"|"info")
        if [ -z "$2" ]; then
            echo -e "${RED}Please specify checkpoint name${NC}"
            exit 1
        fi
        show_checkpoint "$2"
        ;;
    "delete"|"rm")
        if [ -z "$2" ]; then
            echo -e "${RED}Please specify checkpoint name${NC}"
            exit 1
        fi
        delete_checkpoint "$2"
        ;;
    "auto")
        auto_checkpoint
        ;;
    "monitor")
        monitor_checkpoints "${2:-3600}" "${3:-24}"
        ;;
    "clean")
        clean_checkpoints "${2:-7}"
        ;;
    "log")
        echo -e "${CYAN}Checkpoint log:${NC}"
        tail -20 "${LOG_DIR}/checkpoint.log" 2>/dev/null || echo "No checkpoint log found"
        ;;
    "help")
        echo -e "${GREEN}DataSipper Build Checkpoint System${NC}"
        echo
        echo "Usage: $0 <command> [options]"
        echo
        echo "Commands:"
        echo "  create [name]     - Create a checkpoint (auto-named if no name given)"
        echo "  list              - List all checkpoints"
        echo "  show <name>       - Show checkpoint details"
        echo "  delete <name>     - Delete a checkpoint"
        echo "  auto              - Create automatic checkpoint if build is running"
        echo "  monitor [sec] [n] - Monitor and create periodic checkpoints"
        echo "  clean [days]      - Clean checkpoints older than N days (default: 7)"
        echo "  log               - Show checkpoint activity log"
        echo "  help              - Show this help"
        echo
        echo "Examples:"
        echo "  $0 create milestone1    # Create named checkpoint"
        echo "  $0 auto                 # Auto checkpoint if building"
        echo "  $0 monitor 3600 12      # Monitor for 12 hours, checkpoint every hour"
        echo "  $0 show auto_20240702   # Show checkpoint details"
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac