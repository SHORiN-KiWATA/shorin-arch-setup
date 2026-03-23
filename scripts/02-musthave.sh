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

# 检测根文件系统类型
ROOT_FSTYPE=$(findmnt -n -o FSTYPE /)

# 如果是 Btrfs
if [ "$ROOT_FSTYPE" == "btrfs" ]; then
    log "Btrfs filesystem detected."
    exe pacman -S --noconfirm --needed snapper btrfs-assistant xorg-xhost
    success "Snapper tools installed."

    
    # 如果用的是grub
    if [ -f "/etc/default/grub" ] && command -v grub-mkconfig >/dev/null 2>&1; then
        log "Checking GRUB..."
        
        # ----------------------------------------------------------------------
        # 核心逻辑：动态寻找 ESP 分区中的 GRUB，并自动应用“存根 (Stub)”分离架构
        # ----------------------------------------------------------------------
        FOUND_ESP_GRUB=""
        
        # 1. 查找所有 vfat 类型的挂载点 (排除 /boot 本身就是 vfat 的情况，因为那样无法做 Btrfs 快照)
        VFAT_MOUNTS=$(findmnt -n -l -o TARGET -t vfat | grep -v "^/boot$")

        # 查找esp里的grub，获取grub的安装目录。
        if [ -n "$VFAT_MOUNTS" ]; then
            while read -r mountpoint; do
                if [ -d "$mountpoint/grub" ]; then
                    FOUND_ESP_GRUB="$mountpoint/grub"
                    log "Found GRUB core directory in ESP: $FOUND_ESP_GRUB"
                    break 
                fi
            done <<< "$VFAT_MOUNTS"
        fi

        # 快照启动项
        exe pacman -Syu --noconfirm --needed grub-btrfs inotify-tools

        if [ -n "$FOUND_ESP_GRUB" ]; then
            log "Applying Advanced Btrfs-GRUB Decoupling Architecture (Stub Method)..."

            # 2. 清理历史遗留：斩断可能存在的软链接
            if [ -L "/boot/grub" ]; then
                warn "Found /boot/grub symlink. Removing to decouple Btrfs and FAT32..."
                exe rm -f /boot/grub
            fi
            # 确保 Btrfs 上有真正的 /boot/grub 目录用于存放快照和主菜单
            if [ ! -d "/boot/grub" ]; then
                exe mkdir -p /boot/grub
            fi

            # 3. 动态计算 Btrfs 根分区 UUID 和子卷路径
            BTRFS_UUID=$(findmnt -n -o UUID /)
            SUBVOL_NAME=$(findmnt -n -o OPTIONS / | tr ',' '\n' | grep '^subvol=' | cut -d= -f2)
            
            if [ "$SUBVOL_NAME" == "/" ] || [ -z "$SUBVOL_NAME" ]; then
                BTRFS_BOOT_PATH="/boot/grub"
            else
                # 处理subvol=@的情况
                [[ "$SUBVOL_NAME" != /* ]] && SUBVOL_NAME="/${SUBVOL_NAME}"
                BTRFS_BOOT_PATH="${SUBVOL_NAME}/boot/grub"
            fi
            log "Resolved Btrfs absolute path for main config: ${BTRFS_BOOT_PATH}"

            # 4. 生成统一存根 (Stub) 覆盖 ESP 中的配置
            log "Writing GRUB Stub to ${FOUND_ESP_GRUB}/grub.cfg..."
            cat <<EOF | sudo tee "${FOUND_ESP_GRUB}/grub.cfg" > /dev/null
# 由安装脚本自动生成的存根
# 将启动逻辑 (Btrfs) 与环境状态 (FAT32) 解耦
search --no-floppy --fs-uuid --set=root $BTRFS_UUID
configfile ${BTRFS_BOOT_PATH}/grub.cfg
EOF
            success "GRUB Stub generated at ${FOUND_ESP_GRUB}."

            # 5. 修改 grub-btrfs 的跨区搜索路径
            if [ -f "/etc/default/grub-btrfs/config" ]; then
                log "Patching grub-btrfs config for Btrfs search path..."
                sed -i "s|^#*GRUB_BTRFS_GBTRFS_SEARCH_DIRNAME=.*|GRUB_BTRFS_GBTRFS_SEARCH_DIRNAME=\"${BTRFS_BOOT_PATH}\"|" /etc/default/grub-btrfs/config
            fi


            # ==================================================================
            # 开启 GRUB 启动项记忆功能
            # ==================================================================
            log "Enabling GRUB 'save default' feature (Supported by FAT32 grubenv)..."
            
            # 将 GRUB_DEFAULT 改为 saved
            sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
            
            # 确保 GRUB_SAVEDEFAULT=true 被正确设置
            if grep -q "^#*GRUB_SAVEDEFAULT=" /etc/default/grub; then
                # 如果该行存在（无论是否被注释），直接替换
                sed -i 's/^#*GRUB_SAVEDEFAULT=.*/GRUB_SAVEDEFAULT=true/' /etc/default/grub
            else
                # 如果该行完全不存在，则追加到文件末尾
                echo "GRUB_SAVEDEFAULT=true" >> /etc/default/grub
            fi
            success "GRUB boot entry memory enabled."

        else
            log "No separate ESP GRUB directory found. Proceeding with standard configuration..."
            # 如果 GRUB 完全安装在 Btrfs 上（没有分离），脚本会聪明地跳过开启记忆功能，避免报错
        fi

        # 6. 生成真正的主菜单到 Btrfs 分区 (此时会读取刚刚修改的 /etc/default/grub)
        log "Regenerating Main GRUB Config..."
        exe grub-mkconfig -o /boot/grub/grub.cfg

        # 7. 重启快照监听服务
        exe systemctl enable --now grub-btrfsd
        exe systemctl restart grub-btrfsd
        success "GRUB and grub-btrfs integration completed."    
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
