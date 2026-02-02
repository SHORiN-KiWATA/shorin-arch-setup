#!/bin/bash

# ==============================================================================
# undochange.sh - Emergency System Rollback Tool (Btrfs Assistant Edition)
# ==============================================================================
# Usage: sudo ./undochange.sh
# Description: Reverts system to "Before Shorin Setup" using btrfs-assistant
#              This performs a Subvolume Rollback, not just a file diff undo.
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TARGET_DESC="Before Shorin Setup"

# 1. Check Root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Please run as root (sudo ./undochange.sh)${NC}"
    exit 1
fi

# 2. Check Dependencies
if ! command -v snapper &> /dev/null; then
    echo -e "${RED}Error: Snapper is not installed.${NC}"
    exit 1
fi

if ! command -v btrfs-assistant &> /dev/null; then
    echo -e "${RED}Error: btrfs-assistant is not installed.${NC}"
    echo "Cannot perform subvolume rollback."
    exit 1
fi

echo -e "${YELLOW}>>> Initializing Emergency Rollback (Target: '$TARGET_DESC')...${NC}"

# --- Helper Function: Rollback Logic from quickload ---
# Args: $1 = Subvolume Name (e.g., @ or @home), $2 = Snapper Config (e.g., root or home)
perform_rollback() {
    local subvol="$1"
    local snap_conf="$2"
    
    echo -e "Checking config: ${YELLOW}$snap_conf${NC} for subvolume: ${YELLOW}$subvol${NC}..."

    # 1. Get Snapper ID
    # logic: list snapshots -> filter by description -> take the last one -> get ID
    local snap_id=$(snapper -c "$snap_conf" list --columns number,description | grep "$TARGET_DESC" | tail -n 1 | awk '{print $1}')

    if [ -z "$snap_id" ]; then
        echo -e "${RED}  [SKIP] Snapshot '$TARGET_DESC' not found in config '$snap_conf'.${NC}"
        return 1
    fi

    echo -e "  Found Snapshot ID: ${GREEN}$snap_id${NC}"

    # 2. Map to Btrfs-Assistant Index
    # Logic from quickload: Match Subvolume Name ($2) and Snapper ID ($3) to get Index ($1)
    local ba_index=$(btrfs-assistant -l | awk -v v="$subvol" -v s="$snap_id" '$2==v && $3==s {print $1}')

    if [ -z "$ba_index" ]; then
        echo -e "${RED}  [FAIL] Could not map Snapper ID $snap_id to Btrfs-Assistant index.${NC}"
        return 1
    fi

    # 3. Execute Restore
    echo -e "  Executing rollback (Index: $ba_index)..."
    if btrfs-assistant -r "$ba_index"; then
        echo -e "  ${GREEN}Success.${NC}"
        return 0
    else
        echo -e "  ${RED}Restore command failed.${NC}"
        return 1
    fi
}

# --- Main Execution ---

# 3. Rollback Root (Critical)
# Arch layout usually maps config 'root' to subvolume '@'
echo -e "${YELLOW}>>> Restoring Root Filesystem...${NC}"
if ! perform_rollback "@" "root"; then
    echo -e "${RED}CRITICAL FAILURE: Failed to restore root partition.${NC}"
    echo "Aborting operation to prevent partial system state."
    exit 1
fi

# 4. Rollback Home (Optional)
# Only attempt if 'home' config exists
if snapper list-configs | grep -q "^home "; then
    echo -e "${YELLOW}>>> Restoring Home Filesystem...${NC}"
    # Arch layout usually maps config 'home' to subvolume '@home'
    perform_rollback "@home" "home"
else
    echo -e "No 'home' snapper config found, skipping home restore."
fi

# 5. Reboot
echo -e "${GREEN}System rollback successful.${NC}"
echo -e "${YELLOW}Rebooting in 3 seconds...${NC}"
sleep 3
reboot