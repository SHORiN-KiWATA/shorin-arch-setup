#!/bin/bash

# ==============================================================================
# 02b-musthave.sh - Essential Software & Drivers
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

check_root

log ">>> Starting Phase 2: Essential (Must-have) Software & Drivers"

detect_target_user

if [[ -z "$TARGET_USER" ]] || ! id "$TARGET_USER" &>/dev/null; then
    error "Target user is missing. Run 02a-user.sh before 02b-musthave.sh."
    exit 1
fi

SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" >"$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"

cleanup_sudo() { rm -f "$SUDO_TEMP_FILE"; }
trap cleanup_sudo EXIT INT TERM

# ------------------------------------------------------------------------------
# 1. Btrfs Assistants & GRUB Snapshot Integration
# ------------------------------------------------------------------------------
section "Step 1/8" "Btrfs Snapshot Integration"

ROOT_FSTYPE=$(findmnt -n -o FSTYPE /)
if [ "$ROOT_FSTYPE" == "btrfs" ]; then
    log "Btrfs detected. Installing advanced snapshot management tools..."
    
    exe pacman -S --noconfirm --needed btrfs-assistant xorg-xhost less
    success "Btrfs helper tools installed."
    
    if [ -f "/etc/default/grub" ] && command -v grub-mkconfig >/dev/null 2>&1; then
        log "Integrating snapshots into GRUB menu..."
        exe pacman -S --noconfirm --needed grub-btrfs inotify-tools 
        # 【新增条件判断】：检测 ESP 分区上是否存在独立的 grub 目录
        HAS_ESP_GRUB=false
        VFAT_MOUNTS=$(findmnt -n -l -o TARGET -t vfat | grep -v "^/boot$")
        if [ -n "$VFAT_MOUNTS" ]; then
            while read -r mountpoint; do
                if [ -d "$mountpoint/grub" ]; then
                    HAS_ESP_GRUB=true
                    break 
                fi
            done <<< "$VFAT_MOUNTS"
        fi
        
        # 只有在 Decoupled 模式（找到 ESP 上的 grub 目录）时，才修改路径配置
        if [ "$HAS_ESP_GRUB" = true ]; then
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
                log "Decoupled ESP/GRUB detected. Patching grub-btrfs config for Btrfs search path..."
                sed -i "s|^#*GRUB_BTRFS_GBTRFS_SEARCH_DIRNAME=.*|GRUB_BTRFS_GBTRFS_SEARCH_DIRNAME=\"${BTRFS_BOOT_PATH}\"|" /etc/default/grub-btrfs/config
            fi
        else
            log "Standard /boot/grub setup detected. Skipping grub-btrfs path patch."
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
# 3. Input Method
# ------------------------------------------------------------------------------
section "Step 3/8" "Input Method (Fcitx5)"
pacman -Rdd --noconfirm fcitx5 || true
exe as_user yay -S --noconfirm --needed fcitx5-shorin-patched-git
exe as_user yay -S --noconfirm --needed fcitx5-configtool fcitx5-gtk fcitx5-qt fcitx5-rime rime-ice-git

success "Fcitx5 installed."

# ------------------------------------------------------------------------------
# 4. Bluetooth (Smart Detection)
# ------------------------------------------------------------------------------
section "Step 4/8" "Bluetooth"

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
# 5. Power
# ------------------------------------------------------------------------------
section "Step 5/8" "Power Management"

exe pacman -S --noconfirm --needed power-profiles-daemon
exe systemctl enable --now power-profiles-daemon
success "Power profiles daemon enabled."

# ------------------------------------------------------------------------------
# 6. Fastfetch
# ------------------------------------------------------------------------------
section "Step 6/8" "Fastfetch"

exe pacman -S --noconfirm --needed fastfetch gdu btop cmatrix lolcat sl
success "Fastfetch installed."

# ------------------------------------------------------------------------------
# 7. Pacman UI
# ------------------------------------------------------------------------------
section "Step 7/8" "Pacman UI"

if grep -q "^ILoveCandy" /etc/pacman.conf; then
    success "Pacman candy progress bar is already enabled."
else
    log "Enabling pacman candy progress bar..."
    if grep -q "^#[[:space:]]*ILoveCandy" /etc/pacman.conf; then
        exe sed -i 's/^#[[:space:]]*ILoveCandy/ILoveCandy/' /etc/pacman.conf
    elif grep -q "^# Misc options" /etc/pacman.conf; then
        exe sed -i '/^# Misc options/a ILoveCandy' /etc/pacman.conf
    else
        echo "ILoveCandy" >> /etc/pacman.conf
    fi
    success "Pacman candy progress bar enabled."
fi

# ------------------------------------------------------------------------------
# 8. Flatpak
# ------------------------------------------------------------------------------
section "Step 8/8" "Flatpak"

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

log "Module 02b completed."
