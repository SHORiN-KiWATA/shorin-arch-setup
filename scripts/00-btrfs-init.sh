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
# 0. Early Exit Check
# ------------------------------------------------------------------------------
log "Checking Root filesystem..."
ROOT_FSTYPE=$(findmnt -n -o FSTYPE /)

if [ "$ROOT_FSTYPE" != "btrfs" ]; then
    warn "Root filesystem is not Btrfs ($ROOT_FSTYPE detected)."
    log "Skipping Btrfs snapshot initialization entirely."
    exit 0
fi

log "Root is Btrfs. Proceeding with pristine Snapshot Safety Net setup..."

# ------------------------------------------------------------------------------
# 1. Configure Root (/) & Home (/home)
# ------------------------------------------------------------------------------
# 【极致纯净】这里只装 snapper！不装任何多余工具
log "Installing Snapper..."
exe pacman -Syu --noconfirm --needed snapper

log "Configuring Snapper for Root..."
if ! snapper list-configs | grep -q "^root "; then
    if [ -d "/.snapshots" ]; then
        exe_silent umount /.snapshots
        exe_silent rm -rf /.snapshots
    fi
    if exe snapper -c root create-config /; then
        success "Config 'root' created."
        exe snapper -c root set-config ALLOW_GROUPS="wheel" TIMELINE_CREATE="yes" TIMELINE_CLEANUP="yes" NUMBER_LIMIT="10" NUMBER_MIN_AGE="0" NUMBER_LIMIT_IMPORTANT="5" TIMELINE_LIMIT_HOURLY="3" TIMELINE_LIMIT_DAILY="0" TIMELINE_LIMIT_WEEKLY="0" TIMELINE_LIMIT_MONTHLY="0" TIMELINE_LIMIT_YEARLY="0"
        exe systemctl enable snapper-cleanup.timer
        exe systemctl enable snapper-timeline.timer
    fi
fi

if findmnt -n -o FSTYPE /home | grep -q "btrfs"; then
    log "Configuring Snapper for Home..."
    if ! snapper list-configs | grep -q "^home "; then
        if [ -d "/home/.snapshots" ]; then
            exe_silent umount /home/.snapshots
            exe_silent rm -rf /home/.snapshots
        fi
        if exe snapper -c home create-config /home; then
            success "Config 'home' created."
            exe snapper -c home set-config ALLOW_GROUPS="wheel" TIMELINE_CREATE="yes" TIMELINE_CLEANUP="yes" NUMBER_MIN_AGE="0" NUMBER_LIMIT="10" NUMBER_LIMIT_IMPORTANT="5" TIMELINE_LIMIT_HOURLY="3" TIMELINE_LIMIT_DAILY="0" TIMELINE_LIMIT_WEEKLY="0" TIMELINE_LIMIT_MONTHLY="0" TIMELINE_LIMIT_YEARLY="0"
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 2. Advanced Btrfs-GRUB Decoupling (Pure Base)
# ------------------------------------------------------------------------------
section "Safety Net" "GRUB-Btrfs Decoupling"

if [ -f "/etc/default/grub" ] && command -v grub-mkconfig >/dev/null 2>&1; then
    FOUND_ESP_GRUB=""
    VFAT_MOUNTS=$(findmnt -n -l -o TARGET -t vfat | grep -v "^/boot$")

    if [ -n "$VFAT_MOUNTS" ]; then
        while read -r mountpoint; do
            if [ -d "$mountpoint/grub" ]; then
                FOUND_ESP_GRUB="$mountpoint/grub"
                break 
            fi
        done <<< "$VFAT_MOUNTS"
    fi

    if [ -n "$FOUND_ESP_GRUB" ]; then
        log "Applying GRUB Decoupling Stub..."

        if [ -L "/boot/grub" ]; then exe rm -f /boot/grub; fi
        if [ ! -d "/boot/grub" ]; then exe mkdir -p /boot/grub; fi

        BTRFS_UUID=$(findmnt -n -o UUID /)
        SUBVOL_NAME=$(findmnt -n -o OPTIONS / | tr ',' '\n' | grep '^subvol=' | cut -d= -f2)
        
        if [ "$SUBVOL_NAME" == "/" ] || [ -z "$SUBVOL_NAME" ]; then
            BTRFS_BOOT_PATH="/boot/grub"
        else
            [[ "$SUBVOL_NAME" != /* ]] && SUBVOL_NAME="/${SUBVOL_NAME}"
            BTRFS_BOOT_PATH="${SUBVOL_NAME}/boot/grub"
        fi

        cat <<EOF | sudo tee "${FOUND_ESP_GRUB}/grub.cfg" > /dev/null
search --no-floppy --fs-uuid --set=root $BTRFS_UUID
configfile ${BTRFS_BOOT_PATH}/grub.cfg
EOF
        
        sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
        if grep -q "^#*GRUB_SAVEDEFAULT=" /etc/default/grub; then
            sed -i 's/^#*GRUB_SAVEDEFAULT=.*/GRUB_SAVEDEFAULT=true/' /etc/default/grub
        else
            echo "GRUB_SAVEDEFAULT=true" >> /etc/default/grub
        fi
    fi

    # 【关键】这里生成的是最干净的、没有快照菜单的 grub.cfg
    log "Regenerating Pristine GRUB Config..."
    exe grub-mkconfig -o /boot/grub/grub.cfg
fi

# ------------------------------------------------------------------------------
# 3. Create Initial Pristine Snapshot
# ------------------------------------------------------------------------------
section "Safety Net" "Creating Pristine Initial Snapshots"

if snapper list-configs | grep -q "root "; then
    if ! snapper -c root list --columns description | grep -q "Before Shorin Setup"; then
        if exe snapper -c root create --description "Before Shorin Setup"; then
            success "Pristine Root snapshot created."
        else
            error "Failed to create Root snapshot."; exit 1
        fi
    fi
fi

if snapper list-configs | grep -q "home "; then
    if ! snapper -c home list --columns description | grep -q "Before Shorin Setup"; then
        if exe snapper -c home create --description "Before Shorin Setup"; then
            success "Pristine Home snapshot created."
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 4. Deploy Rollback Scripts
# ------------------------------------------------------------------------------
BIN_DIR="/usr/local/bin"
UNDO_SRC="$PARENT_DIR/undochange.sh"
DE_UNDO_SRC="$SCRIPT_DIR/de-undochange.sh"

exe mkdir -p "$BIN_DIR"
if [ -f "$UNDO_SRC" ]; then exe force_copy "$UNDO_SRC" "$BIN_DIR/shorin-undochange" && exe chmod +x "$BIN_DIR/shorin-undochange"; fi
if [ -f "$DE_UNDO_SRC" ]; then exe force_copy "$DE_UNDO_SRC" "$BIN_DIR/shorin-de-undochange" && exe chmod +x "$BIN_DIR/shorin-de-undochange"; fi

log "Module 00 completed. Pure base system secured."