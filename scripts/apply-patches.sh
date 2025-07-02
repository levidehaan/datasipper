#!/bin/bash

# DataSipper Patch Application System
# Applies patches intelligently with error handling and recovery

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
PATCH_DIR="${WORKSPACE_DIR}/patches"
LOG_DIR="${WORKSPACE_DIR}/build-logs"
STATE_DIR="${WORKSPACE_DIR}/.patch_state"

# Create directories
mkdir -p "${LOG_DIR}" "${STATE_DIR}"

# Banner
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════════════════════╗"
echo "║                         DataSipper Patch Application System                   ║"
echo "║                            Intelligent Patch Manager                         ║"
echo "╚═══════════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Logging
LOG_FILE="${LOG_DIR}/patch-application-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "${LOG_FILE}")
exec 2>&1

echo -e "${CYAN}[INFO]${NC} Starting patch application at $(date)"
echo -e "${CYAN}[INFO]${NC} Log file: ${LOG_FILE}"

# Function to print section headers
print_section() {
    echo -e "\n${PURPLE}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}║ $1${NC}"
    echo -e "${PURPLE}════════════════════════════════════════════════════════════════════════════════${NC}\n"
}

# Function to check prerequisites
check_prerequisites() {
    print_section "CHECKING PREREQUISITES"
    
    # Check if we're in the right directory
    if [[ ! -d "${SRC_DIR}" ]]; then
        echo -e "${RED}[ERROR]${NC} Chromium source directory not found: ${SRC_DIR}"
        exit 1
    fi
    
    # Check if patch directory exists
    if [[ ! -d "${PATCH_DIR}" ]]; then
        echo -e "${RED}[ERROR]${NC} Patch directory not found: ${PATCH_DIR}"
        exit 1
    fi
    
    # Check if series file exists
    if [[ ! -f "${PATCH_DIR}/series" ]]; then
        echo -e "${RED}[ERROR]${NC} Patch series file not found: ${PATCH_DIR}/series"
        exit 1
    fi
    
    # Check git status
    cd "${SRC_DIR}"
    if ! git status >/dev/null 2>&1; then
        echo -e "${RED}[ERROR]${NC} Not in a git repository"
        exit 1
    fi
    
    echo -e "${GREEN}[SUCCESS]${NC} All prerequisites met"
}

# Function to backup current state
backup_state() {
    print_section "BACKING UP CURRENT STATE"
    
    cd "${SRC_DIR}"
    
    # Create backup branch
    BACKUP_BRANCH="datasipper-backup-$(date +%Y%m%d-%H%M%S)"
    git checkout -b "${BACKUP_BRANCH}"
    echo -e "${GREEN}[SUCCESS]${NC} Created backup branch: ${BACKUP_BRANCH}"
    
    # Return to original branch
    git checkout main
    
    # Save backup info
    echo "${BACKUP_BRANCH}" > "${STATE_DIR}/backup_branch"
    echo -e "${GREEN}[SUCCESS]${NC} State backed up successfully"
}

# Function to apply a single patch
apply_patch() {
    local patch_file="$1"
    local patch_name=$(basename "${patch_file}" .patch)
    
    echo -e "\n${BLUE}[APPLYING]${NC} ${patch_name}"
    
    cd "${SRC_DIR}"
    
    # Check if patch was already applied
    if [[ -f "${STATE_DIR}/applied_${patch_name}" ]]; then
        echo -e "${YELLOW}[SKIP]${NC} Patch already applied: ${patch_name}"
        return 0
    fi
    
    # Try to apply patch
    if patch -p1 --forward --dry-run < "${patch_file}" >/dev/null 2>&1; then
        # Dry run successful, apply for real
        if patch -p1 --forward < "${patch_file}"; then
            echo -e "${GREEN}[SUCCESS]${NC} Applied: ${patch_name}"
            touch "${STATE_DIR}/applied_${patch_name}"
            return 0
        else
            echo -e "${RED}[ERROR]${NC} Failed to apply: ${patch_name}"
            return 1
        fi
    else
        echo -e "${YELLOW}[WARNING]${NC} Patch ${patch_name} cannot be applied cleanly"
        echo -e "${YELLOW}[INFO]${NC} Attempting with fuzz factor..."
        
        # Try with fuzz factor
        if patch -p1 --forward --fuzz=3 < "${patch_file}"; then
            echo -e "${GREEN}[SUCCESS]${NC} Applied with fuzz: ${patch_name}"
            touch "${STATE_DIR}/applied_${patch_name}"
            return 0
        else
            echo -e "${RED}[ERROR]${NC} Failed to apply even with fuzz: ${patch_name}"
            return 1
        fi
    fi
}

# Function to apply all patches
apply_all_patches() {
    print_section "APPLYING DATASIPPER PATCHES"
    
    local failed_patches=()
    local applied_count=0
    local total_count=0
    
    # Read patch series
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        
        total_count=$((total_count + 1))
        
        local patch_file="${PATCH_DIR}/${line}"
        
        if [[ ! -f "$patch_file" ]]; then
            echo -e "${RED}[ERROR]${NC} Patch file not found: $patch_file"
            failed_patches+=("$line")
            continue
        fi
        
        if apply_patch "$patch_file"; then
            applied_count=$((applied_count + 1))
        else
            failed_patches+=("$line")
        fi
        
    done < "${PATCH_DIR}/series"
    
    # Summary
    echo -e "\n${PURPLE}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}║ PATCH APPLICATION SUMMARY${NC}"
    echo -e "${PURPLE}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Applied successfully: ${applied_count}/${total_count}${NC}"
    
    if [[ ${#failed_patches[@]} -gt 0 ]]; then
        echo -e "${RED}Failed patches:${NC}"
        for patch in "${failed_patches[@]}"; do
            echo -e "  ${RED}- ${patch}${NC}"
        done
    fi
    
    # Save summary
    echo "Applied: ${applied_count}/${total_count}" > "${STATE_DIR}/summary"
    printf '%s\n' "${failed_patches[@]}" > "${STATE_DIR}/failed_patches"
    
    return ${#failed_patches[@]}
}

# Function to verify patches
verify_patches() {
    print_section "VERIFYING APPLIED PATCHES"
    
    cd "${SRC_DIR}"
    
    # Check for DataSipper files
    local datasipper_files=$(find . -name "*datasipper*" -type f | wc -l)
    echo -e "${CYAN}[INFO]${NC} DataSipper files found: ${datasipper_files}"
    
    # Check git status
    local modified_files=$(git status --porcelain | wc -l)
    echo -e "${CYAN}[INFO]${NC} Modified files: ${modified_files}"
    
    # List some key files
    echo -e "\n${CYAN}[INFO]${NC} Key DataSipper components:"
    find . -path "*/datasipper/*" -type f | head -10 | while read -r file; do
        echo -e "  ${GREEN}+ ${file}${NC}"
    done
    
    if [[ $datasipper_files -gt 0 ]]; then
        echo -e "${GREEN}[SUCCESS]${NC} DataSipper components detected in source tree"
        return 0
    else
        echo -e "${YELLOW}[WARNING]${NC} No DataSipper components found"
        return 1
    fi
}

# Function to update build files
update_build_files() {
    print_section "UPDATING BUILD CONFIGURATION"
    
    cd "${SRC_DIR}"
    
    # Check if we need to regenerate build files
    echo -e "${CYAN}[INFO]${NC} Checking if build files need regeneration..."
    
    if [[ -f "out/Lightning/build.ninja" ]]; then
        echo -e "${YELLOW}[INFO]${NC} Regenerating build files to include DataSipper components..."
        gn gen out/Lightning --args="$(cat out/Lightning/args.gn)"
        echo -e "${GREEN}[SUCCESS]${NC} Build files regenerated"
    else
        echo -e "${YELLOW}[WARNING]${NC} No existing build configuration found"
    fi
}

# Function to test compilation
test_compilation() {
    print_section "TESTING DATASIPPER COMPILATION"
    
    cd "${SRC_DIR}"
    
    echo -e "${CYAN}[INFO]${NC} Testing DataSipper component compilation..."
    
    # Try to build just the base target to see if our patches work
    if ninja -C out/Lightning base 2>&1 | tee "${LOG_DIR}/datasipper-compile-test.log"; then
        echo -e "${GREEN}[SUCCESS]${NC} Basic compilation test passed"
        return 0
    else
        echo -e "${RED}[ERROR]${NC} Compilation test failed - check ${LOG_DIR}/datasipper-compile-test.log"
        return 1
    fi
}

# Main execution
main() {
    echo -e "${CYAN}[INFO]${NC} Starting DataSipper patch application..."
    
    check_prerequisites
    backup_state
    
    if apply_all_patches; then
        echo -e "\n${GREEN}[SUCCESS]${NC} All patches applied successfully!"
        
        verify_patches
        update_build_files
        test_compilation
        
        echo -e "\n${GREEN}████████████████████████████████████████████████████████████████████████████████${NC}"
        echo -e "${GREEN}║                    DATASIPPER PATCHES SUCCESSFULLY APPLIED!                   ║${NC}"
        echo -e "${GREEN}████████████████████████████████████████████████████████████████████████████████${NC}"
        echo -e "${GREEN}[NEXT STEP]${NC} Run: ${YELLOW}cd src && ninja -C out/Lightning chrome${NC}"
        
    else
        echo -e "\n${YELLOW}[WARNING]${NC} Some patches failed to apply"
        echo -e "${YELLOW}[INFO]${NC} Check failed patches in: ${STATE_DIR}/failed_patches"
        echo -e "${YELLOW}[INFO]${NC} You may need to resolve conflicts manually"
        
        verify_patches
    fi
    
    echo -e "\n${CYAN}[INFO]${NC} Patch application completed at $(date)"
    echo -e "${CYAN}[INFO]${NC} Full log available at: ${LOG_FILE}"
}

# Handle command line arguments
case "${1:-}" in
    "help"|"-h"|"--help")
        echo "Usage: $0 [command]"
        echo "Commands:"
        echo "  apply    - Apply all DataSipper patches (default)"
        echo "  verify   - Verify applied patches"
        echo "  status   - Show patch application status"
        echo "  reset    - Reset to backup state"
        echo "  help     - Show this help"
        exit 0
        ;;
    "verify")
        check_prerequisites
        verify_patches
        exit $?
        ;;
    "status")
        if [[ -f "${STATE_DIR}/summary" ]]; then
            echo -e "${CYAN}[INFO]${NC} Patch application status:"
            cat "${STATE_DIR}/summary"
            if [[ -f "${STATE_DIR}/failed_patches" ]] && [[ -s "${STATE_DIR}/failed_patches" ]]; then
                echo -e "${RED}Failed patches:${NC}"
                cat "${STATE_DIR}/failed_patches"
            fi
        else
            echo -e "${YELLOW}[INFO]${NC} No patch application history found"
        fi
        exit 0
        ;;
    "reset")
        if [[ -f "${STATE_DIR}/backup_branch" ]]; then
            cd "${SRC_DIR}"
            backup_branch=$(cat "${STATE_DIR}/backup_branch")
            echo -e "${YELLOW}[INFO]${NC} Resetting to backup branch: ${backup_branch}"
            git checkout "${backup_branch}"
            git checkout -b main-restored
            echo -e "${GREEN}[SUCCESS]${NC} Reset to backup state"
        else
            echo -e "${RED}[ERROR]${NC} No backup branch found"
            exit 1
        fi
        exit 0
        ;;
    "apply"|"")
        main
        ;;
    *)
        echo -e "${RED}[ERROR]${NC} Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac