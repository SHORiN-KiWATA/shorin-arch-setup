#!/bin/bash

# ==============================================================================
# 02-musthave.sh - Essential Software, Drivers & Locale
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

check_root

log ">>> Starting Phase 2: Essential (Must-have) Software & Drivers"

# ------------------------------------------------------------------------------
# 1. Btrfs Assistants & GRUB Snapshot Integration
# ------------------------------------------------------------------------------
section "Step 1/8" "Btrfs Snapshot Integration"

ROOT_FSTYPE=$(findmnt -n -o FSTYPE /)
if [ "$ROOT_FSTYPE" == "btrfs" ]; then
    log "Btrfs detected. Installing advanced snapshot management tools..."
    
    exe pacman -S --noconfirm --needed btrfs-assistant xorg-xhost grub-btrfs inotify-tools less
    success "Btrfs helper tools installed."
    
    if [ -f "/etc/default/grub" ] && command -v grub-mkconfig >/dev/null 2>&1; then
        log "Integrating snapshots into GRUB menu..."
        
        # 重新计算 Btrfs 内部的 boot 路径
        SUBVOL_NAME=$(findmnt -n -o OPTIONS / | tr ',' '\n' | grep '^subvol=' | cut -d= -f2)
        if [ "$SUBVOL_NAME" == "/" ] || [ -z "$SUBVOL_NAME" ]; then
            BTRFS_BOOT_PATH="/boot/grub"
        else
            [[ "$SUBVOL_NAME" != /* ]] && SUBVOL_NAME="/${SUBVOL_NAME}"
            BTRFS_BOOT_PATH="${SUBVOL_NAME}/boot/grub"
        fi
        
        # 修改 grub-btrfs 的跨区搜索路径
        if [ -f "/etc/default/grub-btrfs/config" ]; then
            log "Patching grub-btrfs config for Btrfs search path..."
            sed -i "s|^#*GRUB_BTRFS_GBTRFS_SEARCH_DIRNAME=.*|GRUB_BTRFS_GBTRFS_SEARCH_DIRNAME=\"${BTRFS_BOOT_PATH}\"|" /etc/default/grub-btrfs/config
        fi
        
        # 开启监听服务并重新生成菜单（这次菜单里就会多出 Snapshots 选项了！）
        exe systemctl enable --now grub-btrfsd
        log "Regenerating GRUB Config with Snapshot entries..."
        exe grub-mkconfig -o /boot/grub/grub.cfg
        success "GRUB snapshot menu integration completed."
    fi
else
    log "Root is not Btrfs. Skipping Btrfs tool installation."
fi

# ------------------------------------------------------------------------------
# 2. Audio & Video
# ------------------------------------------------------------------------------
section "Step 2/8" "Audio & Video"

log "Installing firmware..."
exe pacman -S --noconfirm --needed sof-firmware alsa-ucm-conf alsa-firmware

log "Installing Pipewire stack..."
exe pacman -S --noconfirm --needed pipewire lib32-pipewire wireplumber pipewire-pulse pipewire-alsa pipewire-jack

exe systemctl --global enable pipewire pipewire-pulse wireplumber
success "Audio setup complete."

# ------------------------------------------------------------------------------
# 3. Locale
# ------------------------------------------------------------------------------
section "Step 3/8" "Locale Configuration"

# 标记是否需要重新生成
NEED_GENERATE=false

# --- 1. 检测 en_US.UTF-8 ---
if locale -a | grep -iq "en_US.utf8"; then
    success "English locale (en_US.UTF-8) is active."
else
    log "Enabling en_US.UTF-8..."
    # 使用 sed 取消注释
    sed -i 's/^#\s*en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    NEED_GENERATE=true
fi

# --- 2. 检测 zh_CN.UTF-8 ---
if locale -a | grep -iq "zh_CN.utf8"; then
    success "Chinese locale (zh_CN.UTF-8) is active."
else
    log "Enabling zh_CN.UTF-8..."
    # 使用 sed 取消注释
    sed -i 's/^#\s*zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
    NEED_GENERATE=true
fi

# --- 3. 如果有修改，统一执行生成 ---
if [ "$NEED_GENERATE" = true ]; then
    log "Generating locales (this may take a moment)..."
    if exe locale-gen; then
        success "Locales generated successfully."
    else
        error "Locale generation failed."
    fi
else
    success "All locales are already up to date."
fi

# ------------------------------------------------------------------------------
# 4. Input Method
# ------------------------------------------------------------------------------
section "Step 4/8" "Input Method (Fcitx5)"

# chinese-addons备用，ice为主
exe pacman -S --noconfirm --needed fcitx5-im fcitx5-rime rime-ice-git

success "Fcitx5 installed."

# ------------------------------------------------------------------------------
# 5. Bluetooth (Smart Detection)
# ------------------------------------------------------------------------------
section "Step 5/8" "Bluetooth"

# Ensure detection tools are present
log "Detecting Bluetooth hardware..."
exe pacman -S --noconfirm --needed usbutils pciutils

BT_FOUND=false

# 1. Check USB
if lsusb | grep -qi "bluetooth"; then BT_FOUND=true; fi
# 2. Check PCI
if lspci | grep -qi "bluetooth"; then BT_FOUND=true; fi
# 3. Check RFKill
if rfkill list bluetooth >/dev/null 2>&1; then BT_FOUND=true; fi

if [ "$BT_FOUND" = true ]; then
    info_kv "Hardware" "Detected"
    
    log "Installing Bluez "
    exe pacman -S --noconfirm --needed bluez bluetui
    
    exe systemctl enable --now bluetooth
    success "Bluetooth service enabled."
else
    info_kv "Hardware" "Not Found"
    warn "No Bluetooth device detected. Skipping installation."
fi

# ------------------------------------------------------------------------------
# 6. Power
# ------------------------------------------------------------------------------
section "Step 6/8" "Power Management"

exe pacman -S --noconfirm --needed power-profiles-daemon
exe systemctl enable --now power-profiles-daemon
success "Power profiles daemon enabled."

# ------------------------------------------------------------------------------
# 7. Fastfetch
# ------------------------------------------------------------------------------
section "Step 7/8" "Fastfetch"

exe pacman -S --noconfirm --needed fastfetch gdu btop cmatrix lolcat sl
success "Fastfetch installed."

log "Module 02 completed."

# ------------------------------------------------------------------------------
# 9. flatpak
# ------------------------------------------------------------------------------

exe pacman -S --noconfirm --needed flatpak
exe flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

CURRENT_TZ=$(readlink -f /etc/localtime)
IS_CN_ENV=false
if [[ "$CURRENT_TZ" == *"Shanghai"* ]] || [ "$CN_MIRROR" == "1" ] || [ "$DEBUG" == "1" ]; then
    IS_CN_ENV=true
    info_kv "Region" "China Optimization Active"
fi

if [ "$IS_CN_ENV" = true ]; then
    select_flathub_mirror
else
    log "Using Global Sources."
fi
