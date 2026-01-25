#!/bin/bash

# ==============================================================================
# 02-musthave.sh - Essential Software, Drivers & Locale
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

check_root

log ">>> Starting Phase 2: Essential (Must-have) Software & Drivers"
# ------------------------------------------------------------------------------
# 1. Btrfs Extras & GRUB (Config was done in 00-btrfs-init)
# ------------------------------------------------------------------------------
section "Step 1/8" "Btrfs Extras & GRUB"

ROOT_FSTYPE=$(findmnt -n -o FSTYPE /)

if [ "$ROOT_FSTYPE" == "btrfs" ]; then
    log "Btrfs filesystem detected."
    exe pacman -S --noconfirm --needed snapper snap-pac btrfs-assistant
    success "Snapper tools installed."

    log "Initializing Snapper 'root' configuration..."
    if ! snapper list-configs | grep -q "^root "; then
        if [ -d "/.snapshots" ]; then
            warn "Removing existing /.snapshots..."
            exe_silent umount /.snapshots
            exe_silent rm -rf /.snapshots
        fi
        if exe snapper -c root create-config /; then
            success "Snapper config created."
            log "Applying retention policy..."
            exe snapper -c root set-config ALLOW_GROUPS="wheel" TIMELINE_CREATE="no" TIMELINE_CLEANUP="yes" NUMBER_LIMIT="10" NUMBER_LIMIT_IMPORTANT="5" TIMELINE_LIMIT_HOURLY="5" TIMELINE_LIMIT_DAILY="7" TIMELINE_LIMIT_WEEKLY="0" TIMELINE_LIMIT_MONTHLY="0" TIMELINE_LIMIT_YEARLY="0"
            success "Policy applied."
        fi
    else
        log "Config exists."
    fi
    
    exe systemctl enable --now snapper-timeline.timer snapper-cleanup.timer

    # GRUB Integration
if [ -f "/etc/default/grub" ] && command -v grub-mkconfig >/dev/null 2>&1; then
        log "Checking GRUB..."
        
         FOUND_EFI_GRUB=""
        
        # 1. 使用 findmnt 查找所有 vfat 类型的挂载点 (通常 ESP 是 vfat)
        # -n: 不输出标题头
        # -l: 列表格式输出
        # -o TARGET: 只输出挂载点路径
        # -t vfat: 限制文件系统类型
        # sort -r: 反向排序，这样 /boot/efi 会排在 /boot 之前（如果同时存在），优先匹配深层路径
        VFAT_MOUNTS=$(findmnt -n -l -o TARGET -t vfat)

        if [ -n "$VFAT_MOUNTS" ]; then
            # 2. 遍历这些 vfat 分区，寻找 grub 目录
            # 使用 while read 循环处理多行输出
            while read -r mountpoint; do
                # 检查这个挂载点下是否有 grub 目录
                if [ -d "$mountpoint/grub" ]; then
                    FOUND_EFI_GRUB="$mountpoint/grub"
                    log "Found GRUB directory in ESP mountpoint: $mountpoint"
                    break 
                fi
            done <<< "$VFAT_MOUNTS"
        fi

        # 3. 如果找到了位于 ESP 中的 GRUB 真实路径
        if [ -n "$FOUND_EFI_GRUB" ]; then
            
            # -e 判断存在, -L 判断是软链接 
            if [ -e "/boot/grub" ] || [ -L "/boot/grub" ]; then
                warn "Skip" "/boot/grub already exists. No symlink created."
            else
                # 5. 仅当完全不存在时，创建软链接
                warn "/boot/grub is missing. Linking to $FOUND_EFI_GRUB..."
                exe ln -sf "$FOUND_EFI_GRUB" /boot/grub
                success "Symlink created: /boot/grub -> $FOUND_EFI_GRUB"
            fi
        else
            log "No 'grub' directory found in any active vfat mounts. Skipping symlink check."
        fi
        # --- 核心修改结束 ---

        exe pacman -Syu --noconfirm --needed grub-btrfs inotify-tools
        exe systemctl enable --now grub-btrfsd

        if ! grep -q "grub-btrfs-overlayfs" /etc/mkinitcpio.conf; then
            log "Adding overlayfs hook to mkinitcpio..."
            sed -i 's/^HOOKS=(\(.*\))/HOOKS=(\1 grub-btrfs-overlayfs)/' /etc/mkinitcpio.conf
            exe mkinitcpio -P
        fi

        log "Regenerating GRUB..."
        exe grub-mkconfig -o /boot/grub/grub.cfg
    fi
else
    log "Root is not Btrfs. Skipping Snapper setup."
fi

# ------------------------------------------------------------------------------
# 2. Audio & Video
# ------------------------------------------------------------------------------
section "Step 2/8" "Audio & Video"

log "Installing firmware..."
exe pacman -S --noconfirm --needed sof-firmware alsa-ucm-conf alsa-firmware

log "Installing Pipewire stack..."
exe pacman -S --noconfirm --needed pipewire lib32-pipewire wireplumber pipewire-pulse pipewire-alsa pipewire-jack pavucontrol

exe systemctl --global enable pipewire pipewire-pulse wireplumber
success "Audio setup complete."

# ------------------------------------------------------------------------------
# 3. Locale
# ------------------------------------------------------------------------------
section "Step 3/8" "Locale Configuration"

if locale -a | grep -iq "zh_CN.utf8"; then
    success "Chinese locale (zh_CN.UTF-8) is active."
else
    log "Generating zh_CN.UTF-8..."
    sed -i 's/^#\s*zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
    if exe locale-gen; then
        success "Locale generated."
    else
        error "Locale generation failed."
    fi
fi

# ------------------------------------------------------------------------------
# 4. Input Method
# ------------------------------------------------------------------------------
section "Step 4/8" "Input Method (Fcitx5)"

# chinese-addons备用，ice为主
exe pacman -S --noconfirm --needed fcitx5-im fcitx5-chinese-addons fcitx5-rime rime-ice-git

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
    exe pacman -S --noconfirm --needed bluez

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

exe pacman -S --noconfirm --needed fastfetch
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