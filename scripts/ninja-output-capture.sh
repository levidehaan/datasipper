#!/bin/bash

# Ninja Output Capture - Safely monitor ninja without interruption
# This script monitors ninja process and captures its output streams

set -e

WORKSPACE_DIR="/workspace"
LOG_DIR="${WORKSPACE_DIR}/build-logs"
PID_FILE="${LOG_DIR}/ninja.pid"

mkdir -p "${LOG_DIR}"

# Function to safely capture ninja output
capture_ninja_output() {
    local ninja_pid=$(pgrep -f "ninja.*chrome" || echo "")
    
    if [ -z "$ninja_pid" ]; then
        echo "$(date): No ninja process found"
        return 1
    fi
    
    echo "$(date): Found ninja process PID: $ninja_pid"
    echo "$ninja_pid" > "$PID_FILE"
    
    # Use strace to capture file descriptors (non-invasive)
    # This won't interrupt the process but lets us see what it's writing
    timeout 60 strace -p "$ninja_pid" -e trace=write -o "${LOG_DIR}/ninja-strace.log" 2>/dev/null || true
    
    # Alternative: Monitor the directory for new log files ninja might create
    find /workspace/src/out/Lightning -name "*.log" -newer "${LOG_DIR}/last-check" 2>/dev/null | head -10 > "${LOG_DIR}/new-ninja-logs.txt" || true
    
    # Update timestamp
    touch "${LOG_DIR}/last-check"
    
    # Check if any ninja output files exist
    if [ -f "/workspace/src/out/Lightning/.ninja_log" ]; then
        tail -20 "/workspace/src/out/Lightning/.ninja_log" > "${LOG_DIR}/ninja-progress.log"
    fi
    
    echo "$(date): Ninja output capture complete"
}

# Function to monitor ninja completion
check_ninja_completion() {
    local ninja_pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
    
    if [ -n "$ninja_pid" ] && ! kill -0 "$ninja_pid" 2>/dev/null; then
        echo "$(date): Ninja process $ninja_pid has completed!"
        
        # Check for Chrome binary
        if [ -f "/workspace/src/out/Lightning/chrome" ]; then
            echo "$(date): SUCCESS! Chrome binary created"
            ls -lh "/workspace/src/out/Lightning/chrome" > "${LOG_DIR}/chrome-binary-success.log"
            return 0
        else
            echo "$(date): Build completed but no Chrome binary found"
            # Capture any error logs
            find /workspace/src/out/Lightning -name "*.log" -exec tail -50 {} \; > "${LOG_DIR}/build-failure-logs.txt" 2>/dev/null || true
            return 1
        fi
    elif [ -n "$ninja_pid" ]; then
        echo "$(date): Ninja process $ninja_pid still running"
        return 2
    else
        echo "$(date): No ninja PID file found"
        return 3
    fi
}

# Main execution
case "${1:-capture}" in
    "capture")
        capture_ninja_output
        ;;
    "check")
        check_ninja_completion
        ;;
    "monitor")
        # Run continuous monitoring
        while true; do
            result=$(check_ninja_completion)
            echo "$result"
            
            if [[ "$result" == *"SUCCESS!"* ]] || [[ "$result" == *"no Chrome binary"* ]]; then
                echo "Build completed - stopping monitor"
                break
            fi
            
            sleep 300  # Check every 5 minutes
        done
        ;;
    *)
        echo "Usage: $0 {capture|check|monitor}"
        exit 1
        ;;
esac