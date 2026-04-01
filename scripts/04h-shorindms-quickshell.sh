#!/usr/bin/env bash

# --- Import Utilities ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

if [[ -f "$SCRIPT_DIR/00-utils.sh" ]]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found in $SCRIPT_DIR."
    exit 1
fi

check_root
VERIFY_LIST="/tmp/shorin_install_verify.list"
rm -f "$VERIFY_LIST"

# --- Identify User & DM Check ---
log "Identifying target user..."
detect_target_user

if [[ -z "$TARGET_USER" || ! -d "$HOME_DIR" ]]; then
    error "Target user invalid or home directory does not exist."
    exit 1
fi

info_kv "Target User" "$TARGET_USER"
check_dm_conflict

# --- Temporary Sudo Privileges ---
log "Granting temporary sudo privileges..."
SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"

cleanup_sudo() {
    if [[ -f "$SUDO_TEMP_FILE" ]]; then
        rm -f "$SUDO_TEMP_FILE"
        log "Security: Temporary sudo privileges revoked."
    fi
}
trap cleanup_sudo EXIT INT TERM

# ==============================================================================
# 核心安装逻辑：将依赖管理全部交给 AUR 包！
# ==============================================================================
AUR_HELPER="paru"
section "Shorin DMS" "Installing Meta Environment"

# 1. 只需要安装这一个包！PKGBUILD 会自动拉取那几百个依赖软件和配置文件模板
log "Installing quickshell and core dependencies via AUR..."
BASE_PACKAGES=(
    "vulkan-headers"
    "quickshell-git"
    "xdg-desktop-portal-gnome"
)
echo "${BASE_PACKAGES[@]}" >> "$VERIFY_LIST"
exe as_user "$AUR_HELPER" -S --noconfirm --needed "${BASE_PACKAGES[@]}"
log "Installing shorin-dms-niri environment..."
echo "shorin-dms-niri-git" >> "$VERIFY_LIST"
exe as_user "$AUR_HELPER" -S --noconfirm --needed shorin-dms-niri-git

# 2. 调用 AUR 包自带的 CLI 工具进行全自动用户环境初始化 (包含了配置下发、GTK设置、图标隐藏等)
log "Initializing User Dotfiles and Environment..."
exe as_user shorindms init
# ==============================================================================

# --- Wallpapers & Static Resources (不属于包管理的静态大文件) ---
section "Shorin DMS" "Wallpapers & Tutorials"

log "Deploying wallpapers..."
WALLPAPER_SOURCE_DIR="$PARENT_DIR/resources/Wallpapers"
WALLPAPER_DIR="$HOME_DIR/Pictures/Wallpapers"
as_user mkdir -p "$WALLPAPER_DIR"
force_copy "$WALLPAPER_SOURCE_DIR/." "$WALLPAPER_DIR/"
chown -R "$TARGET_USER:" "$WALLPAPER_DIR"

log "Copying tutorial files..."
force_copy "$PARENT_DIR/resources/必看-Shorin-DMS-Niri使用方法.txt" "$HOME_DIR"
chown "$TARGET_USER:" "$HOME_DIR/必看-Shorin-DMS-Niri使用方法.txt"

# niri blur toggle 脚本
curl -L shorin.xyz/niri-blur-toggle | as_user bash

# --- Finalization & Auto-Login ---
section "Final" "Auto-Login & Cleanup"
rm -f "$SUDO_TEMP_FILE"

log "Cleaning up legacy TTY autologin configs..."
rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf 2>/dev/null

if [ "$SKIP_DM" = true ]; then
    log "Display Manager setup skipped (Conflict found or user opted out)."
    warn "You will need to start your session manually from the TTY."
else
    setup_ly
fi

success "Shorin DMS Niri Installation Complete!"