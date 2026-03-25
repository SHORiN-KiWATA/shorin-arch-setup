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
# 0. Early Exit Check (Guard Clause)
# ------------------------------------------------------------------------------
log "Checking Root filesystem..."
ROOT_FSTYPE=$(findmnt -n -o FSTYPE /)

if [ "$ROOT_FSTYPE" != "btrfs" ]; then
    warn "Root filesystem is not Btrfs ($ROOT_FSTYPE detected)."
    log "Skipping Btrfs snapshot initialization entirely."
    # 退出当前脚本，返回状态码 0 保证主程序继续往下走
    exit 0 
fi

log "Root is Btrfs. Proceeding with Snapshot Safety Net setup..."

# ------------------------------------------------------------------------------
# 1. Configure Root (/)
# ------------------------------------------------------------------------------
# 从这里开始，我们 100% 确定环境是 Btrfs
log "Installing Snapper and dependencies..."
exe pacman -Syu --noconfirm --needed snapper rsync less

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

# ------------------------------------------------------------------------------
# 2. Configure Home (/home)
# ------------------------------------------------------------------------------
log "Checking Home filesystem..."

if findmnt -n -o FSTYPE /home | grep -q "btrfs"; then
    log "Home is Btrfs. Configuring Snapper for Home..."
    
    if ! snapper list-configs | grep -q "^home "; then
        if [ -d "/home/.snapshots" ]; then
            exe_silent umount /home/.snapshots
            exe_silent rm -rf /home/.snapshots
        fi
        
        if exe snapper -c home create-config /home; then
            success "Config 'home' created."
            
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
# 2.5 Backup ESP (FAT32)
# ------------------------------------------------------------------------------
section "Safety Net" "Backing up ESP (FAT32)"

VFAT_MOUNTS=$(findmnt -n -l -o TARGET -t vfat)

if [ -n "$VFAT_MOUNTS" ]; then
    log "Found FAT32 partitions. Creating backups in /var/backups/before-shorin-setup-esp..."
    BACKUP_BASE="/var/backups/before-shorin-setup-esp"
    exe mkdir -p "$BACKUP_BASE"
    
    while read -r mountpoint; do
        safe_name=$(echo "$mountpoint" | tr '/' '_')
        log "Backing up $mountpoint to $BACKUP_BASE/esp${safe_name}/ ..."
        
        exe mkdir -p "$BACKUP_BASE/esp${safe_name}/"
        exe rsync -a --delete "$mountpoint/" "$BACKUP_BASE/esp${safe_name}/"
    done <<< "$VFAT_MOUNTS"
    
    success "ESP partitions backed up safely."
else
    warn "No FAT32 partitions found. Skipping ESP backup."
fi

# ------------------------------------------------------------------------------
# 3. Create Initial Safety Snapshots
# ------------------------------------------------------------------------------
section "Safety Net" "Creating Initial Snapshots"

if snapper list-configs | grep -q "root "; then
    if snapper -c root list --columns description | grep -q "Before Shorin Setup"; then
        log "Root snapshot already created."
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

if snapper list-configs | grep -q "home "; then
    if snapper -c home list --columns description | grep -q "Before Shorin Setup"; then
        log "Home snapshot already created."
    else
        log "Creating Home snapshot..."
        if exe snapper -c home create --description "Before Shorin Setup"; then
            success "Home snapshot created."
        else
            error "Failed to create Home snapshot."
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
exe mkdir -p "$BIN_DIR"

if [ -f "$UNDO_SRC" ]; then
    exe cp "$UNDO_SRC" "$BIN_DIR/shorin-undochange"
    exe chmod +x "$BIN_DIR/shorin-undochange"
    success "Installed 'shorin-undochange' command."
else
    warn "Could not find $UNDO_SRC. Skipping."
fi

if [ -f "$DE_UNDO_SRC" ]; then
    exe cp "$DE_UNDO_SRC" "$BIN_DIR/shorin-de-undochange"
    exe chmod +x "$BIN_DIR/shorin-de-undochange"
    success "Installed 'de-undochange' command."
else
    warn "Could not find $DE_UNDO_SRC. Skipping."
fi

log "Module 00 completed. Safe to proceed."