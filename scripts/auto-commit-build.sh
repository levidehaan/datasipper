#!/bin/bash

# Auto-Commit Build Results
# Automatically commits logs and results when build completes

set -e

WORKSPACE_DIR="/workspace"
LOG_DIR="${WORKSPACE_DIR}/build-logs"

# Function to commit build results
commit_build_results() {
    local status="$1"
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    
    cd "$WORKSPACE_DIR"
    
    echo "$(date): Preparing to commit build results..."
    
    # Add all logs to git (these are safe to commit)
    git add build-logs/ || true
    git add .checkpoints/ || true
    git add docs/ || true
    
    # Check if Chrome binary exists and handle it carefully
    if [ -f "src/out/Lightning/chrome" ]; then
        echo "$(date): Chrome binary found!"
        
        # Get binary size
        CHROME_SIZE=$(du -h "src/out/Lightning/chrome" | cut -f1)
        echo "Chrome binary size: $CHROME_SIZE" > "${LOG_DIR}/chrome-binary-info.txt"
        
        # Create a marker file instead of committing the large binary
        echo "Chrome binary successfully built at $(date)" > "CHROME_BUILD_SUCCESS.md"
        echo "Binary location: src/out/Lightning/chrome" >> "CHROME_BUILD_SUCCESS.md"
        echo "Binary size: $CHROME_SIZE" >> "CHROME_BUILD_SUCCESS.md"
        
        git add "CHROME_BUILD_SUCCESS.md"
        
        # DON'T commit the actual Chrome binary (too large for git)
        echo "src/out/Lightning/chrome" >> .gitignore
        
        COMMIT_MSG="🎉 SUCCESS: Chrome binary built successfully ($CHROME_SIZE) - $timestamp"
        
    else
        echo "$(date): Build completed but no Chrome binary found"
        
        # Commit failure logs for analysis
        echo "Build completed but Chrome binary not found at $(date)" > "BUILD_INCOMPLETE.md"
        git add "BUILD_INCOMPLETE.md"
        
        COMMIT_MSG="🔧 Build completed without Chrome binary - $timestamp"
    fi
    
    # Add build status to commit
    git add "${LOG_DIR}/" || true
    
    # Commit the results
    if git diff --staged --quiet; then
        echo "$(date): No changes to commit"
    else
        git commit -m "$COMMIT_MSG" || true
        echo "$(date): Build results committed"
        
        # Try to push (may fail if no remote configured)
        git push origin main 2>/dev/null || git push 2>/dev/null || echo "$(date): Could not push (no remote configured)"
    fi
}

# Function to monitor and auto-commit
monitor_and_commit() {
    echo "$(date): Starting auto-commit monitor..."
    
    while true; do
        # Check if ninja is still running
        if ! pgrep -f "ninja.*chrome" > /dev/null; then
            echo "$(date): Ninja process finished!"
            
            # Wait a moment for files to finish writing
            sleep 10
            
            # Check build results and commit
            if [ -f "/workspace/src/out/Lightning/chrome" ]; then
                commit_build_results "SUCCESS"
            else
                commit_build_results "INCOMPLETE"
            fi
            
            break
        else
            echo "$(date): Ninja still running, checking again in 10 minutes..."
            sleep 600  # Check every 10 minutes
        fi
    done
}

# Main execution
case "${1:-monitor}" in
    "commit")
        commit_build_results "${2:-MANUAL}"
        ;;
    "monitor")
        monitor_and_commit
        ;;
    *)
        echo "Usage: $0 {commit|monitor}"
        echo "  commit [status] - Commit build results now"
        echo "  monitor         - Monitor ninja and auto-commit when done"
        exit 1
        ;;
esac