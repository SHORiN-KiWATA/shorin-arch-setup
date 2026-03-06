#!/usr/bin/env bash

# =======================================================================
# Initialization & Utilities
# =======================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

if [[ -f "$SCRIPT_DIR/00-utils.sh" ]]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found in $SCRIPT_DIR."
    exit 1
fi

check_root

# 初始化安装验证文件
VERIFY_LIST="/tmp/shorin_install_verify.list"
rm -f "$VERIFY_LIST"

# =======================================================================
# Identify User & DM Check
# =======================================================================

log "Identifying target user..."
detect_target_user

if [[ -z "$TARGET_USER" || ! -d "$HOME_DIR" ]]; then
    error "Target user invalid or home directory does not exist."
    exit 1
fi

info_kv "Target User" "$TARGET_USER"
check_dm_conflict

# =======================================================================
# Temporary Sudo Privileges
# =======================================================================

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

# =======================================================================
# Execution Phase
# =======================================================================

AUR_HELPER="paru"

# --- 1. Dotfiles ---
section "Minimal Niri" "Dotfiles"
force_copy "$PARENT_DIR/minimal-niri-dotfiles/." "$HOME_DIR"

# --- 2. Bookmarks ---
BOOKMARKS_FILE="$HOME_DIR/.config/gtk-3.0/bookmarks"
if [[ -f "$BOOKMARKS_FILE" ]]; then
    as_user sed -i "s/shorin/$TARGET_USER/g" "$BOOKMARKS_FILE"
fi

# --- 3. Niri output.kdl ---
OUTPUT_KDL="$HOME_DIR/.config/niri/output.kdl"
# 注意: DOTFILES_REPO 需确保在 00-utils.sh 或外部已定义
if [[ "$TARGET_USER" != "shorin" ]]; then
    as_user touch "$OUTPUT_KDL"
else
    as_user cp "$PARENT_DIR/minimal-niri-dotfiles/.config/niri/output-example.kdl" "$OUTPUT_KDL"
fi

# --- 4. Core Components ---
section "Minimal Niri" "Core Components"
NIRI_PKGS=(niri xwayland-satellite xdg-desktop-portal-gnome fuzzel waybar polkit-gnome mako)
echo "${NIRI_PKGS[*]}" >> "$VERIFY_LIST"
exe as_user "$AUR_HELPER" -S --noconfirm --needed "${NIRI_PKGS[@]}"

# --- 5. Terminal ---
section "Minimal Niri" "Terminal"
TERMINAL_PKGS=(zsh foot ttf-jetbrains-maple-mono-nf-xx-xx starship eza zoxide zsh-syntax-highlighting zsh-autosuggestions zsh-completions imagemagick jq)
echo "${TERMINAL_PKGS[*]}" >> "$VERIFY_LIST"
exe as_user "$AUR_HELPER" -S --noconfirm --needed "${TERMINAL_PKGS[@]}"

# --- 6. File Manager ---
section "Minimal Niri" "File Manager"
FM_PKGS1=(ffmpegthumbnailer gvfs-smb nautilus-open-any-terminal file-roller gnome-keyring gst-plugins-base gst-plugins-good gst-libav nautilus)
FM_PKGS2=(xdg-desktop-portal-gtk thunar tumbler poppler-glib thunar-archive-plugin thunar-volman gvfs-mtp gvfs-gphoto2 webp-pixbuf-loader libgsf)
echo "${FM_PKGS1[*]}" >> "$VERIFY_LIST"
echo "${FM_PKGS2[*]}" >> "$VERIFY_LIST"

exe pacman -S --noconfirm --needed "${FM_PKGS1[@]}"
exe pacman -S --noconfirm --needed "${FM_PKGS2[@]}"

echo "xdg-terminal-exec" >> "$VERIFY_LIST"
exe as_user "$AUR_HELPER" -S --noconfirm --needed xdg-terminal-exec

# 修复：如果不包含 foot，则追加
XDG_TERMS_LIST="$HOME_DIR/.config/xdg-terminals.list"
if ! grep -qs "foot" "$XDG_TERMS_LIST"; then
    # 确保目录存在
    mkdir -p "$(dirname "$XDG_TERMS_LIST")"
    echo 'foot.desktop' >> "$XDG_TERMS_LIST"
    chown "$TARGET_USER:" "$XDG_TERMS_LIST" 2>/dev/null || true
fi

sudo -u "$TARGET_USER" dbus-run-session gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal foot
# 注意: 确保 configure_nautilus_user 在 00-utils.sh 中已定义
configure_nautilus_user

# --- 7. Tools ---
section "Minimal Niri" "Tools"
TOOLS_PKGS=(imv cliphist wl-clipboard shorinclip-git shorin-contrib-git hyprlock breeze-cursors nwg-look adw-gtk-theme pavucontrol)
echo "${TOOLS_PKGS[*]}" >> "$VERIFY_LIST"
exe as_user "$AUR_HELPER" -S --noconfirm --needed "${TOOLS_PKGS[@]}"

as_user shorin link

# --- 8. Flatpak Overrides ---
if command -v flatpak &>/dev/null; then
    section "Minimal Niri" "Flatpak Config"
    as_user flatpak override --user --filesystem=xdg-data/themes
    as_user flatpak override --user --filesystem="$HOME_DIR/.themes"
    as_user flatpak override --user --filesystem=xdg-config/gtk-4.0
    as_user flatpak override --user --filesystem=xdg-config/gtk-3.0
    as_user flatpak override --user --env=GTK_THEME=adw-gtk3-dark
    as_user flatpak override --user --filesystem=xdg-config/fontconfig
fi
run_hide_desktop_file
section "Final" "Cleanup & Boot Configuration"

log "Cleaning up legacy TTY autologin configs..."
rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf 2>/dev/null

if [ "$SKIP_DM" = true ]; then
    log "Display Manager setup skipped (Conflict found or user opted out)."
    warn "You will need to start your session manually from the TTY."
else
    setup_greetd_tuigreet
fi
