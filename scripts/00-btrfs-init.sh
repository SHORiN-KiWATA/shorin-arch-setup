#!/bin/bash

# ==============================================================================
# 00-btrfs-init.sh - Pre-install Snapshot Safety Net (Root & Home)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

check_root

# GRUB 可能装在 ESP 里（archinstall --boot-directory=/efi），此时 /boot/grub 不存在，
# 所有硬编码该路径的操作都会落空。这是安装流程的第一个模块，在这里统一处理一次。
# 【位置要紧】必须在下面的 Btrfs 提前退出之前——非 Btrfs 的系统同样需要这个软链接。
ensure_grub_dir_link

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
# 2. GRUB Boot Memory & Btrfs Environment Block
# ------------------------------------------------------------------------------
section "Safety Net" "GRUB Btrfs Environment Block"

if [ -f "/etc/default/grub" ] && command -v grub-mkconfig >/dev/null 2>&1; then
    UKI_ENABLED=false
    if grep -qsE '^[[:space:]]*[[:alnum:]_]+_uki[[:space:]]*=' /etc/mkinitcpio.d/*.preset 2>/dev/null ||
    grep -qsE '^[[:space:]]*layout[[:space:]]*=[[:space:]]*uki([[:space:]]|$)' /etc/kernel/install.conf 2>/dev/null; then
        UKI_ENABLED=true
    fi
    
    if [ "$UKI_ENABLED" = true ]; then
        log "UKI configuration detected. Skipping GRUB savedefault configuration."
    else
        log "Enabling GRUB boot entry memory (savedefault)..."
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
    
    # Btrfs 不像 FAT 那样能被 GRUB 就地写入，必须先用 grub-editenv 写一次，
    # 让 grubenv 里预留出环境块（env_block），savedefault 才能真正落盘。
    # 若 /boot/grub 不在 Btrfs 上（例如 ESP 挂在 /boot），GRUB 本就能直接写，无需处理。
    GRUB_DIR_FSTYPE=$(findmnt -n -o FSTYPE -T /boot/grub 2>/dev/null)

    if [ "$GRUB_DIR_FSTYPE" == "btrfs" ] && command -v grub-editenv >/dev/null 2>&1; then
        log "Initializing Btrfs GRUB environment block..."
        exe grub-editenv - set ok=1
        
        if grub-editenv - list 2>/dev/null | grep -q "^env_block="; then
            success "Environment block reserved. GRUB savedefault is functional."
        else
            warn "No env_block reserved in /boot/grub/grubenv."
        fi
    fi
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
if [ -f "$UNDO_SRC" ]; then exe cp -f "$UNDO_SRC" "$BIN_DIR/shorin-undochange" && exe chmod +x "$BIN_DIR/shorin-undochange"; fi
if [ -f "$DE_UNDO_SRC" ]; then exe cp -f "$DE_UNDO_SRC" "$BIN_DIR/shorin-de-undochange" && exe chmod +x "$BIN_DIR/shorin-de-undochange"; fi

log "Module 00 completed. Pure base system secured."
