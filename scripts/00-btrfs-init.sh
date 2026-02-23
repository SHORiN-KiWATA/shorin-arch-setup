#!/bin/bash

# ==============================================================================
# 00-btrfs-init.sh - Pre-install Snapshot Safety Net (Root & Home)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

check_root

section "Phase 0" "System Snapshot Initialization"

# ------------------------------------------------------------------------------
# 1. Configure Root (/)
# ------------------------------------------------------------------------------
log "Checking Root filesystem..."
ROOT_FSTYPE=$(findmnt -n -o FSTYPE /)

if [ "$ROOT_FSTYPE" == "btrfs" ]; then
    log "Root is Btrfs. Installing Snapper..."
    # Minimal install for snapshot capability
    exe pacman -Syu --noconfirm --needed snapper less
    
    log "Configuring Snapper for Root..."
    if ! snapper list-configs | grep -q "^root "; then
        # Cleanup existing dir to allow subvolume creation
        if [ -d "/.snapshots" ]; then
            exe_silent umount /.snapshots
            exe_silent rm -rf /.snapshots
        fi
        
        if exe snapper -c root create-config /; then
            success "Config 'root' created."
            
            # Apply Retention Policy
            exe snapper -c root set-config \
                ALLOW_GROUPS="wheel" \
                TIMELINE_CREATE="yes" \
                TIMELINE_CLEANUP="yes" \
                NUMBER_LIMIT="10" \
                NUMBER_MIN_AGE="0" \
                NUMBER_LIMIT_IMPORTANT="5" \
                TIMELINE_LIMIT_HOURLY="3" \
                TIMELINE_LIMIT_DAILY="0" \
                TIMELINE_LIMIT_WEEKLY="0" \
                TIMELINE_LIMIT_MONTHLY="0" \
                TIMELINE_LIMIT_YEARLY="0"

            exe systemctl enable snapper-cleanup.timer
            exe systemctl enable snapper-timeline.timer
        fi
    else
        log "Config 'root' already exists."
    fi
else
    warn "Root is not Btrfs. Skipping Root snapshot."
fi

# ------------------------------------------------------------------------------
# 2. Configure Home (/home)
# ------------------------------------------------------------------------------
log "Checking Home filesystem..."

# Check if /home is a mountpoint and is btrfs
if findmnt -n -o FSTYPE /home | grep -q "btrfs"; then
    log "Home is Btrfs. Configuring Snapper for Home..."
    
    if ! snapper list-configs | grep -q "^home "; then
        # Cleanup .snapshots in home if exists
        if [ -d "/home/.snapshots" ]; then
            exe_silent umount /home/.snapshots
            exe_silent rm -rf /home/.snapshots
        fi
        
        if exe snapper -c home create-config /home; then
            success "Config 'home' created."
            
            # Apply same policy to home
            exe snapper -c home set-config \
                ALLOW_GROUPS="wheel" \
                TIMELINE_CREATE="yes" \
                TIMELINE_CLEANUP="yes" \
                NUMBER_MIN_AGE="0" \
                NUMBER_LIMIT="10" \
                NUMBER_LIMIT_IMPORTANT="5" \
                TIMELINE_LIMIT_HOURLY="3" \
                TIMELINE_LIMIT_DAILY="0" \
                TIMELINE_LIMIT_WEEKLY="0" \
                TIMELINE_LIMIT_MONTHLY="0" \
                TIMELINE_LIMIT_YEARLY="0"
        fi
    else
        log "Config 'home' already exists."
    fi
else
    log "/home is not a separate Btrfs volume. Skipping."
fi

# ------------------------------------------------------------------------------
# 3. Create Initial Safety Snapshots
# ------------------------------------------------------------------------------
section "Safety Net" "Creating Initial Snapshots"

# Snapshot Root
if snapper list-configs | grep -q "root "; then
    if snapper -c root list --columns description | grep -q "Before Shorin Setup"; then
        log "Snapshot already created."
    else
        log "Creating Root snapshot..."
        if exe snapper -c root create --description "Before Shorin Setup"; then
            success "Root snapshot created."
        else
            error "Failed to create Root snapshot."
            warn "Cannot proceed without a safety snapshot. Aborting."
            exit 1
        fi
    fi
fi

# Snapshot Home
if snapper list-configs | grep -q "home "; then
    if snapper -c home list --columns description | grep -q "Before Shorin Setup"; then
        log "Snapshot already created."
    else
        log "Creating Home snapshot..."
        if exe snapper -c home create --description "Before Shorin Setup"; then
            success "Home snapshot created."
        else
            error "Failed to create Home snapshot."
            # This is less critical than root, but should still be a failure.
            exit 1
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 4. Deploy Rollback Scripts
# ------------------------------------------------------------------------------
section "Safety Net" "Deploying Rollback Scripts"

BIN_DIR="/usr/local/bin"
UNDO_SRC="$PARENT_DIR/undochange.sh"
DE_UNDO_SRC="$SCRIPT_DIR/de-undochange.sh"

log "Installing undo utilities to $BIN_DIR..."

if [ ! -d "$BIN_DIR" ]; then
    exe mkdir -p "$BIN_DIR"
fi

# 部署主撤销脚本
if [ -f "$UNDO_SRC" ]; then
    exe cp "$UNDO_SRC" "$BIN_DIR/shorin-undochange"
    exe chmod +x "$BIN_DIR/shorin-undochange"
    success "Installed 'shorin-undochange' command."
else
    warn "Could not find $UNDO_SRC. Skipping."
fi

# 部署桌面环境撤销脚本
if [ -f "$DE_UNDO_SRC" ]; then
    exe cp "$DE_UNDO_SRC" "$BIN_DIR/shorin-de-undochange"
    exe chmod +x "$BIN_DIR/shorin-de-undochange"
    success "Installed 'de-undochange' command."
else
    warn "Could not find $DE_UNDO_SRC. Skipping."
fi

log "Module 00 completed. Safe to proceed."