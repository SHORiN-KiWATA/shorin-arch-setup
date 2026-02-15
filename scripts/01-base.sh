#!/bin/bash

# ==============================================================================
# 01-base.sh - Base System Configuration
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

check_root

log "Starting Phase 1: Base System Configuration..."

# ------------------------------------------------------------------------------
# 1. Set Global Default Editor
# ------------------------------------------------------------------------------
section "Step 1/6" "Global Default Editor"

TARGET_EDITOR="vim"

if command -v nvim &> /dev/null; then
    TARGET_EDITOR="nvim"
    log "Neovim detected."
elif command -v nano &> /dev/null; then
    TARGET_EDITOR="nano"
    log "Nano detected."
else
    log "Neovim or Nano not found. Installing Vim..."
    if ! command -v vim &> /dev/null; then
        exe pacman -Syu --noconfirm gvim
    fi
fi

log "Setting EDITOR=$TARGET_EDITOR in /etc/environment..."

if grep -q "^EDITOR=" /etc/environment; then
    exe sed -i "s/^EDITOR=.*/EDITOR=${TARGET_EDITOR}/" /etc/environment
else
    # exe handles simple commands, for redirection we wrap in bash -c or just run it
    # For simplicity in logging, we just run it and log success
    echo "EDITOR=${TARGET_EDITOR}" >> /etc/environment
fi
success "Global EDITOR set to: ${TARGET_EDITOR}"

# ------------------------------------------------------------------------------
# 2. Enable 32-bit (multilib) Repository
# ------------------------------------------------------------------------------
section "Step 2/6" "Multilib Repository"

if grep -q "^\[multilib\]" /etc/pacman.conf; then
    success "[multilib] is already enabled."
else
    log "Uncommenting [multilib]..."
    # Uncomment [multilib] and the following Include line
    exe sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
    
    log "Refreshing database..."
    exe pacman -Syu
    success "[multilib] enabled."
fi

# ------------------------------------------------------------------------------
# 3. Install Base Fonts
# ------------------------------------------------------------------------------
section "Step 3/6" "Base Fonts"

log "Installing adobe-source-han-serif-cn-fonts adobe-source-han-sans-cn-fonts , ttf-liberation, emoji..."
exe pacman -S --noconfirm --needed adobe-source-han-serif-cn-fonts adobe-source-han-sans-cn-fonts ttf-liberation noto-fonts-emoji ttf-jetbrains-mono-nerd
log "Base fonts installed."

log "Installing terminus-font..."
# 安装 terminus-font 包
exe pacman -S --noconfirm --needed terminus-font

log "Setting font for current session..."
exe setfont ter-v20n

log "Configuring permanent vconsole font..."
if [ -f /etc/vconsole.conf ] && grep -q "^FONT=" /etc/vconsole.conf; then
    exe sed -i 's/^FONT=.*/FONT=ter-v20n/' /etc/vconsole.conf
else
    echo "FONT=ter-v20n" >> /etc/vconsole.conf
fi

log "Restarting systemd-vconsole-setup..."
exe systemctl restart systemd-vconsole-setup

success "TTY font configured (ter-v20n)."
# ------------------------------------------------------------------------------
# 4. Configure archlinuxcn Repository
# ------------------------------------------------------------------------------
section "Step 4/6" "ArchLinuxCN Repository"

if grep -q "\[archlinuxcn\]" /etc/pacman.conf; then
    success "archlinuxcn repository already exists."
else
    log "Adding archlinuxcn mirrors to pacman.conf..."
    cat <<EOT >> /etc/pacman.conf

[archlinuxcn]
Server = https://mirrors.ustc.edu.cn/archlinuxcn/\$arch
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/\$arch
Server = https://mirrors.hit.edu.cn/archlinuxcn/\$arch
Server = https://repo.huaweicloud.com/archlinuxcn/\$arch
EOT
    success "Mirrors added."
fi

log "Installing archlinuxcn-keyring..."
# Keyring installation often needs -Sy specifically, but -Syu is safe too
exe pacman -Syu --noconfirm archlinuxcn-keyring
success "ArchLinuxCN configured."

# ------------------------------------------------------------------------------
# 5. Install AUR Helpers
# ------------------------------------------------------------------------------
section "Step 5/6" "AUR Helpers"

log "Installing yay and paru..."
exe pacman -S --noconfirm --needed base-devel yay paru
success "Helpers installed."

# ------------------------------------------------------------------------------
# 6. Configure NetworkManager Backend (iwd)
# ------------------------------------------------------------------------------
section "Step 6/6" "Network Backend (iwd)"

# Check if NetworkManager is installed before attempting configuration
if pacman -Qi networkmanager &> /dev/null; then
    log "NetworkManager detected. Proceeding with iwd backend configuration..."

    log "Installing iwd..."
    exe pacman -S --noconfirm --needed iwd impala

    log "Configuring NetworkManager to use iwd backend..."

    # Ensure directory exists
    if [ ! -d /etc/NetworkManager/conf.d ]; then
        mkdir -p /etc/NetworkManager/conf.d
    fi

    echo -e "[device]\nwifi.backend=iwd" >> /etc/NetworkManager/conf.d/iwd.conf
    echo "wifi.iwd.autoconnect=false" >> /etc/NetworkManager/conf.d/iwd.conf

    log "Notice: NetworkManager restart deferred. Changes will apply after reboot."
    success "Network backend configured (iwd)."
else
    log "NetworkManager not found. Skipping iwd configuration."
fi

# ------------------------------------------------------------------------------

log "Module 01 completed."