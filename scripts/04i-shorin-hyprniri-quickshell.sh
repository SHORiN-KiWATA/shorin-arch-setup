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

# ========================================================================
#   初始化验证清单
# ========================================================================
VERIFY_LIST="/tmp/shorin_install_verify.list"
rm -f "$VERIFY_LIST"

force_copy() {
    local src="$1"
    local target_dir="$2"
    
    if [[ -z "$src" || -z "$target_dir" ]]; then
        warn "force_copy: Missing arguments"
        return 1
    fi

    if [[ -d "${src%/}" ]]; then
        (cd "$src" && find . -type d) | while read -r d; do
            as_user rm -f "$target_dir/$d" 2>/dev/null
        done
    fi

    exe as_user cp -rf "$src" "$target_dir"
}

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

# ========================================================================
#   exec 
# ========================================================================

AUR_HELPER="paru"

# --- Installation: Core Components ---
section "Shorin Hyprniri" "Core Components & Utilities"

# 清理可能冲突的依赖
declare -a target_pkgs=(
    "hyprcursor-git"
    "hyprgraphics-git"
    "hyprland-git"
    "hyprland-guiutils-git"
    "hyprlang-git"
    "hyprlock-git"
    "hyprpicker-git"
    "hyprtoolkit-git"
    "hyprutils-git"
    "xdg-desktop-portal-hyprland-git"
)
# 2. 过滤出系统中实际已安装的包
declare -a installed_pkgs=()
for pkg in "${target_pkgs[@]}"; do
    # 使用 pacman -Qq 检查是否安装，抑制输出以保持终端干净
    if pacman -Qq "$pkg" >/dev/null 2>&1; then
        installed_pkgs+=("$pkg")
    fi
done
# 3. 只有当存在已安装的包时，才执行卸载命令
if [[ ${#installed_pkgs[@]} -gt 0 ]]; then
    exe as_user "$AUR_HELPER" -Rns --noconfirm "${installed_pkgs[@]}"
fi

log "Installing Hyprland core components..."
CORE_PKGS="vulkan-headers hyprland quickshell-git dms-shell-bin matugen cava cups-pk-helper kimageformats kitty adw-gtk-theme nwg-look breeze-cursors wl-clipboard cliphist"
echo "$CORE_PKGS" >> "$VERIFY_LIST"
exe as_user "$AUR_HELPER" -S --noconfirm --needed $CORE_PKGS

log "Installing terminal utilities..."
TERM_PKGS="fish jq zoxide socat imagemagick imv starship eza ttf-jetbrains-maple-mono-nf-xx-xx fuzzel shorin-contrib-git timg"
echo "$TERM_PKGS" >> "$VERIFY_LIST"
exe as_user "$AUR_HELPER" -S --noconfirm --needed $TERM_PKGS

log "Installing file manager and dependencies..."
FM_PKGS="xdg-desktop-portal-gtk thunar tumbler ffmpegthumbnailer poppler-glib gvfs-smb file-roller thunar-archive-plugin gnome-keyring thunar-volman gvfs-mtp gvfs-gphoto2 webp-pixbuf-loader"
echo "$FM_PKGS" >> "$VERIFY_LIST"
exe as_user "$AUR_HELPER" -S --noconfirm --needed $FM_PKGS

log "Installing screenshot and screencast tools..."
SCREEN_PKGS="satty grim slurp xdg-desktop-portal-hyprland"
echo "$SCREEN_PKGS" >> "$VERIFY_LIST"
exe as_user "$AUR_HELPER" -S --noconfirm --needed $SCREEN_PKGS

# --- Environment Configurations ---
section "Shorin Hyprniri" "Environment Configuration"

log "Configuring default terminal and templates..."
exe ln -sf /usr/bin/kitty /usr/bin/gnome-terminal

as_user mkdir -p "$HOME_DIR/Templates"
as_user touch "$HOME_DIR/Templates/new" "$HOME_DIR/Templates/new.sh"
if [[ -f "$HOME_DIR/Templates/new.sh" ]] && grep -q "#!" "$HOME_DIR/Templates/new.sh"; then
    log "Template new.sh already initialized."
else
    as_user bash -c "echo '#!/usr/bin/env bash' >> '$HOME_DIR/Templates/new.sh'"
fi
chown -R "$TARGET_USER:" "$HOME_DIR/Templates"

log "Applying file manager bookmarks..."
as_user sed -i "s/shorin/$TARGET_USER/g" "$HOME_DIR/.config/gtk-3.0/bookmarks"

# --- Dotfiles & Wallpapers ---
section "Shorin Hyprniri" "Dotfiles & Wallpapers"

log "Deploying user dotfiles from repository..."
DOTFILES_REPO_LINK="https://github.com/SHORiN-KiWATA/shorin-dms-hyprniri.git"
exe git clone --depth 1 "$DOTFILES_REPO_LINK" "$PARENT_DIR/shorin-dms-hyprniri-dotfiles"
chown -R "$TARGET_USER:" "$PARENT_DIR/shorin-dms-hyprniri-dotfiles"
force_copy "$PARENT_DIR/shorin-dms-hyprniri-dotfiles/dotfiles/." "$HOME_DIR"
as_user shorin link

log "Deploying wallpapers..."
WALLPAPER_SOURCE_DIR="$PARENT_DIR/resources/Wallpapers"
WALLPAPER_DIR="$HOME_DIR/Pictures/Wallpapers"
chown -R "$TARGET_USER:" "$WALLPAPER_SOURCE_DIR"
as_user mkdir -p "$WALLPAPER_DIR"
force_copy "$WALLPAPER_SOURCE_DIR/." "$WALLPAPER_DIR/"

# --- Browser Setup ---
section "Shorin Hyprniri" "Browser Setup"

log "Installing Firefox and Pywalfox..."
BROWSER_PKGS="firefox python-pywalfox"
echo "$BROWSER_PKGS" >> "$VERIFY_LIST"
exe as_user "$AUR_HELPER" -S --noconfirm --needed $BROWSER_PKGS

log "Configuring Firefox Pywalfox extension policy..."
POL_DIR="/etc/firefox/policies"
exe mkdir -p "$POL_DIR"
echo '{ "policies": { "Extensions": { "Install": ["https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi"] } } }' >"$POL_DIR/policies.json"
exe chmod 755 "$POL_DIR"
exe chmod 644 "$POL_DIR/policies.json"

# --- Flatpak & Theme Integration ---
section "Shorin Hyprniri" "Flatpak & Theme Integration"

if command -v flatpak &>/dev/null; then
    log "Configuring Flatpak overrides and theme integrations..."
    echo "bazaar" >> "$VERIFY_LIST"
    exe as_user "$AUR_HELPER" -S --noconfirm --needed bazaar
    as_user flatpak override --user --filesystem=xdg-data/themes
    as_user flatpak override --user --filesystem="$HOME_DIR/.themes"
    as_user flatpak override --user --filesystem=xdg-config/gtk-4.0
    as_user flatpak override --user --filesystem=xdg-config/gtk-3.0
    as_user flatpak override --user --env=GTK_THEME=adw-gtk3-dark
    as_user flatpak override --user --filesystem=xdg-config/fontconfig
    as_user ln -sf /usr/share/themes "$HOME_DIR/.local/share/themes"
else
    warn "Flatpak is not installed. Skipping overrides."
fi


# === update module ===
if command -v kitty &>/dev/null; then 
exe ln -sf /usr/bin/kitty /usr/local/bin/xterm
fi

# --- Desktop Cleanup & Tutorials ---
section "Config" "Desktop Cleanup"
log "Hiding unnecessary .desktop icons..."
run_hide_desktop_file
chown -R "$TARGET_USER:" "$HOME_DIR/.local/share"

log "Copying tutorial files..."
force_copy "$PARENT_DIR/resources/必看-shoirn-hyprniri使用方法.txt" "$HOME_DIR"

# ========================================================================
#   exec-end 
# ========================================================================

# --- Finalization & Auto-Login ---
section "Final" "Auto-Login & Cleanup"
rm -f "$SUDO_TEMP_FILE"

# 1. 清理旧的 TTY 自动登录残留（无论是否启用 greetd，旧版残留都应清除）
log "Cleaning up legacy TTY autologin configs..."
rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf 2>/dev/null

if [ "$SKIP_DM" = true ]; then
  log "Display Manager setup skipped (Conflict found or user opted out)."
  warn "You will need to start your session manually from the TTY."
else

  setup_greetd_tuigreet
fi