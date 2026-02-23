#!/bin/bash
# 04c-quickshell-setup.sh

# 1. 引用工具库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
if [[ -f "$SCRIPT_DIR/00-utils.sh" ]]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found in $SCRIPT_DIR."
    exit 1
fi

# ==============================================================================
#  核心辅助函数定义
# ==============================================================================

# --- 函数：强制安全拷贝（解决覆盖冲突） ---
force_copy() {
    local src="$1"
    local target_dir="$2"
    
    if [[ -z "$src" || -z "$target_dir" ]]; then
        warn "force_copy: Missing arguments"
        return 1
    fi

    local item_name
    item_name=$(basename "$src")
    
    # 只有当拷贝的不是 "目录下的所有内容" (即路径不以 /. 结尾) 时，才执行精确删除
    if [[ "$src" != */. ]]; then
        # 清理 target_dir 结尾多余的斜杠或 /. 
        local clean_target="${target_dir%/}"
        clean_target="${clean_target%/.}"
        
        # 先安全删除目标路径的同名内容，防止目录覆盖文件的冲突
        as_user rm -rf "${clean_target}/${item_name}"
    fi
    
    # 执行安全拷贝
    exe as_user cp -rf "$src" "$target_dir"
}

# --- 函数：静默删除 niri 绑定 ---
niri_remove_bind() {
    local target_key="$1"
    local config_file="$HOME_DIR/.config/niri/dms/binds.kdl"

    if [[ ! -f "$config_file" ]]; then
        return 1
    fi

    # 使用 Python 处理，无日志，无备份
    python3 -c "
import sys, re

file_path = '$config_file'
target_key = sys.argv[1]

try:
    with open(file_path, 'r') as f:
        content = f.read()

    pattern = re.compile(r'(?m)^\s*(?!//).*?' + re.escape(target_key) + r'(?=\s|\{)')

    while True:
        match = pattern.search(content)
        if not match:
            break

        start_idx = match.start()
        open_brace_idx = content.find('{', start_idx)
        if open_brace_idx == -1:
            break 
        
        balance = 0
        end_idx = -1
        for i in range(open_brace_idx, len(content)):
            char = content[i]
            if char == '{':
                balance += 1
            elif char == '}':
                balance -= 1
                if balance == 0:
                    end_idx = i + 1
                    break
        
        if end_idx != -1:
            if end_idx < len(content) and content[end_idx] == '\n':
                end_idx += 1
            content = content[:start_idx] + content[end_idx:]
        else:
            break

    with open(file_path, 'w') as f:
        f.write(content)

except Exception:
    pass
" "$target_key"
}


log "Installing DMS..."
# ==============================================================================
#  Identify User & DM Check
# ==============================================================================
log "Identifying user..."
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
TARGET_USER="${DETECTED_USER:-$(read -p "Target user: " u && echo "$u")}"
HOME_DIR="/home/$TARGET_USER"

if [[ -z "$TARGET_USER" || ! -d "$HOME_DIR" ]]; then
    error "Target user invalid or home directory does not exist."
    exit 1
fi

info_kv "Target" "$TARGET_USER"

# DM Check
KNOWN_DMS=("gdm" "sddm" "lightdm" "lxdm" "slim" "xorg-xdm" "ly" "greetd" "plasma-login-manager")
SKIP_AUTOLOGIN="false"
DM_FOUND=""

for dm in "${KNOWN_DMS[@]}"; do
    if pacman -Q "$dm" &>/dev/null; then
        DM_FOUND="$dm"
        break
    fi
done

if [[ -n "$DM_FOUND" ]]; then
    info_kv "Conflict" "${H_RED}$DM_FOUND${NC}"
    SKIP_AUTOLOGIN="true"
else
    read -t 20 -p "$(echo -e "   ${H_CYAN}Enable TTY auto-login? [Y/n] (Default Y): ${NC}")" choice || true
    if [[ "${choice:-Y}" =~ ^[Yy]$ ]]; then
        SKIP_AUTOLOGIN="false"
    else
        SKIP_AUTOLOGIN="true"
    fi
fi

log "Target user for DMS installation: $TARGET_USER"

# 下载并执行安装脚本
INSTALLER_SCRIPT="/tmp/dms_install.sh"
DMS_URL="https://install.danklinux.com"

log "Downloading DMS installer wrapper..."
if curl -fsSL "$DMS_URL" -o "$INSTALLER_SCRIPT"; then
    chmod +x "$INSTALLER_SCRIPT"
    chown "$TARGET_USER" "$INSTALLER_SCRIPT"

    log "Executing DMS installer as user ($TARGET_USER)..."
    log "NOTE: If the installer asks for input, this script might hang."
    
    if runuser -u "$TARGET_USER" -- bash -c "cd ~ && $INSTALLER_SCRIPT"; then
        success "DankMaterialShell installed successfully."
    else
        warn "DMS installer returned an error code. You may need to install it manually."
        exit 1 
    fi
    rm -f "$INSTALLER_SCRIPT"
else
    warn "Failed to download DMS installer script from $DMS_URL."
fi

# ==============================================================================
#  dms 随图形化环境自动启动
# ==============================================================================
section "Config" "dms autostart"

DMS_AUTOSTART_LINK="$HOME_DIR/.config/systemd/user/graphical-session.target.wants/dms.service"
DMS_NIRI_CONFIG_FILE="$HOME_DIR/.config/niri/config.kdl"
DMS_HYPR_CONFIG_FILE="$HOME_DIR/.config/hypr/hyprland.conf"

if [[ -L "$DMS_AUTOSTART_LINK" ]]; then
    log "Detect DMS systemd service enabled, disabling ...." 
    rm -f "$DMS_AUTOSTART_LINK"
fi

DMS_NIRI_INSTALLED="false"
DMS_HYPR_INSTALLED="false"

if command -v niri &>/dev/null; then 
    DMS_NIRI_INSTALLED="true"
elif command -v hyprland &>/dev/null; then
    DMS_HYPR_INSTALLED="true"
fi

if [[ "$DMS_NIRI_INSTALLED" == "true" ]]; then
    if ! grep -E -q "^[[:space:]]*spawn-at-startup.*dms.*run" "$DMS_NIRI_CONFIG_FILE"; then
        log "Enabling DMS autostart in niri config.kdl..." 
        echo 'spawn-at-startup "dms" "run"' >> "$DMS_NIRI_CONFIG_FILE"
    else
        log "DMS autostart already exists in niri config.kdl, skipping."
    fi

elif [[ "$DMS_HYPR_INSTALLED" == "true" ]]; then
    log "Configuring Hyprland autostart..."
    if ! grep -q "exec-once.*dms run" "$DMS_HYPR_CONFIG_FILE"; then
        log "Adding DMS autostart to hyprland.conf"
        echo 'exec-once = dms run' >> "$DMS_HYPR_CONFIG_FILE"
    else
        log "DMS autostart already exists in Hyprland config, skipping."
    fi
fi

# ==============================================================================
#  fcitx5 configuration and locale
# ==============================================================================
section "Config" "input method"

if [[ "$DMS_NIRI_INSTALLED" == "true" ]]; then
    if ! grep -q "fcitx5" "$DMS_NIRI_CONFIG_FILE"; then
        log "Enabling fcitx5 autostart in niri config.kdl..."
        echo 'spawn-at-startup "fcitx5" "-d"' >> "$DMS_NIRI_CONFIG_FILE"
    else
        log "Fcitx5 autostart already exists, skipping."
    fi

    if grep -q "^[[:space:]]*environment[[:space:]]*{" "$DMS_NIRI_CONFIG_FILE"; then
        log "Existing environment block found. Injecting fcitx variables..."
        if ! grep -q 'XMODIFIERS "@im=fcitx"' "$DMS_NIRI_CONFIG_FILE"; then
            sed -i '/^[[:space:]]*environment[[:space:]]*{/a \    LC_CTYPE "en_US.UTF-8"\n    XMODIFIERS "@im=fcitx"\n    LANG "zh_CN.UTF-8"' "$DMS_NIRI_CONFIG_FILE"
        else
            log "Environment variables for fcitx already exist, skipping."
        fi
    else
        log "No environment block found. Appending new block..."
        cat << EOT >> "$DMS_NIRI_CONFIG_FILE"

environment {
    LC_CTYPE "en_US.UTF-8"
    XMODIFIERS "@im=fcitx"
    LANG "zh_CN.UTF-8"
}
EOT
    fi

    chown -R "$TARGET_USER:" "$PARENT_DIR/quickshell-dotfiles"
    
    # === [ 核心修复点 ] ===
    # 精准清除目标路径中会导致冲突的非目录文件(软链接)
    as_user rm -rf "$HOME_DIR/.local/share/fcitx5"
    as_user rm -rf "$HOME_DIR/.config/fcitx5"
    # =======================
    
    force_copy "$PARENT_DIR/quickshell-dotfiles/." "$HOME_DIR/"

elif [[ "$DMS_HYPR_INSTALLED" == "true" ]]; then
    if ! grep -q "fcitx5" "$DMS_HYPR_CONFIG_FILE"; then
        log "Adding fcitx5 autostart to hyprland.conf"
        echo 'exec-once = fcitx5 -d' >> "$DMS_HYPR_CONFIG_FILE"
        
        cat << EOT >> "$DMS_HYPR_CONFIG_FILE"

# --- Added by Shorin-Setup Script ---
# Fcitx5 Input Method Variables
env = XMODIFIERS,@im=fcitx
env = LC_CTYPE,en_US.UTF-8
# Locale Settings
env = LANG,zh_CN.UTF-8
# ----------------------------------
EOT
    else
        log "Fcitx5 configuration already exists in Hyprland config, skipping."
    fi
    
    chown -R "$TARGET_USER:" "$PARENT_DIR/quickshell-dotfiles"
    
    # === [ 核心修复点 ] ===
    as_user rm -rf "$HOME_DIR/.local/share/fcitx5"
    as_user rm -rf "$HOME_DIR/.config/fcitx5"
    # 这里我顺手修正了原本脚本的一个小 Bug: 
    # 如果 quickshell-dotfiles 包含 .config 和 .local，应复制到 ~ 下，而不是 ~/.config/ 下，否则会变成 ~/.config/.config
    force_copy "$PARENT_DIR/quickshell-dotfiles/." "$HOME_DIR/"
fi
# ==============================================================================
# filemanager
# ==============================================================================
section "Config" "file manager"

if [[ "$DMS_NIRI_INSTALLED" == "true" ]]; then
    log "DMS niri detected, configuring nautilus"
    exe pacman -S --noconfirm --needed ffmpegthumbnailer gvfs-smb nautilus-open-any-terminal file-roller gnome-keyring gst-plugins-base gst-plugins-good gst-libav nautilus
    if pacman -Q | grep -q "kitty" && [[ ! -f /usr/bin/gnome-terminal || -L /usr/bin/gnome-terminal ]]; then
        ln -sf /usr/bin/kitty /usr/bin/gnome-terminal
    fi
    as_user mkdir -p "$HOME_DIR/Templates"
    as_user touch "$HOME_DIR/Templates/new"
    as_user touch "$HOME_DIR/Templates/new.sh"
    as_user bash -c "echo '#!/bin/bash' >> '$HOME_DIR/Templates/new.sh'"
    chown -R "$TARGET_USER:" "$HOME_DIR/Templates"
    
    configure_nautilus_user

elif [[ "$DMS_HYPR_INSTALLED" == "true" ]]; then
    log "DMS hyprland detected, skipping file manager."
fi

# ==============================================================================
#  screenshare
# ==============================================================================
section "Config" "screenshare"

if [[ "$DMS_NIRI_INSTALLED" == "true" ]]; then
    log "DMS niri detected, configuring xdg-desktop-portal"
    exe pacman -S --noconfirm --needed xdg-desktop-portal-gnome
    if ! grep -q '/usr/lib/xdg-desktop-portal-gnome' "$DMS_NIRI_CONFIG_FILE"; then
        log "Configuring environment in niri config.kdl"
        echo 'spawn-sh-at-startup "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=niri & /usr/lib/xdg-desktop-portal-gnome"' >> "$DMS_NIRI_CONFIG_FILE"
    fi

elif [[ "$DMS_HYPR_INSTALLED" == "true" ]]; then
    log "DMS hyprland detected, configuring xdg-desktop-portal"
    exe pacman -S --noconfirm --needed xdg-desktop-portal-hyprland
    if ! grep -q '/usr/lib/xdg-desktop-portal-hyprland' "$DMS_HYPR_CONFIG_FILE"; then
        log "Configuring environment in hyprland.conf"
        echo 'exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=hyprland & /usr/lib/xdg-desktop-portal-hyprland' >> "$DMS_HYPR_CONFIG_FILE"
    fi
fi

# ==============================================================================
#  Validation Check: DMS & Core Components
# ==============================================================================
section "Config" "components validation"
log "Verifying DMS and core components installation for autologin..."

MISSING_COMPONENTS=()

if ! command -v dms &>/dev/null ; then
    MISSING_COMPONENTS+=("dms")
fi
if ! command -v quickshell &>/dev/null; then
    MISSING_COMPONENTS+=("quickshell")
fi

if [[ ${#MISSING_COMPONENTS[@]} -gt 0 ]]; then
    warn "Validation failed! Missing components: ${MISSING_COMPONENTS[*]}"
    warn "Setting SKIP_AUTOLOGIN=true to prevent booting into a broken environment."
    SKIP_AUTOLOGIN="true"
else
    success "All core components validated successfully."
fi

# ==============================================================================
#  tty autologin
# ==============================================================================
section "Config" "tty autostart"

SVC_DIR="$HOME_DIR/.config/systemd/user"
as_user mkdir -p "$SVC_DIR/default.target.wants"

if [[ "$SKIP_AUTOLOGIN" == "false" ]]; then
    log "Configuring Niri Auto-start (TTY)..."
    mkdir -p "/etc/systemd/system/getty@tty1.service.d"
    echo -e "[Service]\nExecStart=\nExecStart=-/sbin/agetty --noreset --noclear --autologin $TARGET_USER - \${TERM}" >"/etc/systemd/system/getty@tty1.service.d/autologin.conf"
fi

# ===================================================
#  window manager autostart (if don't have any of dm)
# ===================================================
section "Config" "WM autostart"

if [[ "$SKIP_AUTOLOGIN" == "false" && "$DMS_NIRI_INSTALLED" == "true" ]]; then
    SVC_FILE="$SVC_DIR/niri-autostart.service"
    LINK="$SVC_DIR/default.target.wants/niri-autostart.service"
    
    cat <<EOT >"$SVC_FILE"
[Unit]
Description=Niri Session Autostart
After=graphical-session-pre.target
StartLimitIntervalSec=60
StartLimitBurst=3
[Service]
ExecStart=/usr/bin/niri-session
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
EOT

    as_user ln -sf "$SVC_FILE" "$LINK"
    chown -R "$TARGET_USER:" "$SVC_DIR"
    success "Niri/DMS auto-start enabled with DMS dependency."

elif [[ "$SKIP_AUTOLOGIN" == "false" && "$DMS_HYPR_INSTALLED" == "true" ]]; then
    SVC_FILE="$SVC_DIR/hyprland-autostart.service"
    LINK="$SVC_DIR/default.target.wants/hyprland-autostart.service"
    
    cat <<EOT >"$SVC_FILE"
[Unit]
Description=Hyprland Session Autostart
After=graphical-session-pre.target
StartLimitIntervalSec=60
StartLimitBurst=3
[Service]
ExecStart=/usr/bin/start-hyprland
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
EOT

    as_user ln -sf "$SVC_FILE" "$LINK"
    chown -R "$TARGET_USER:" "$SVC_DIR"
    success "Hyprland DMS auto-start enabled with DMS dependency."
fi


# ============================================================================
#   Shorin DMS 自定义增强模块
# ============================================================================
log "Checking if Niri is installed for Shorin Customizations..."
if ! command -v niri &>/dev/null; then
    SHORIN_DMS=0
fi 

if [[ "${SHORIN_DMS:-0}" != "1" ]]; then
    log "Shorin DMS not selected or Niri missing, skipping custom configurations."
    exit 0
fi

# ==================== [ 一键备份原有配置 ] ====================
section "Shorin DMS" "backup config"

BACKUP_FILE="$HOME_DIR/shorin_config_backup.tar.gz"
log "Backing up old configs to archive (Overwrite previous)..."

BACKUP_LIST=(
    "Thunar" "xfce4" "gtk-3.0" "mpv" "satty" "fuzzel" 
    "niri/shorin-niri" "fish" "kitty" "starship.toml" 
    "mimeapps.list" "matugen" "btop" "cava" "yazi" 
    "fcitx5" "fontconfig"
)

TAR_LIST="/tmp/shorin_tar_list.txt"
> "$TAR_LIST"

for item in "${BACKUP_LIST[@]}"; do
    if [[ -e "$HOME_DIR/.config/$item" ]]; then
        echo "$item" >> "$TAR_LIST"
    fi
done

if [[ -s "$TAR_LIST" ]]; then
    as_user rm -f "$BACKUP_FILE"
    # 使用安全的 tar 压缩
    exe as_user tar -czf "$BACKUP_FILE" -C "$HOME_DIR/.config" -T "$TAR_LIST"
    success "Backup completed: ~/shorin_config_backup.tar.gz"
else
    log "No existing configurations found to backup."
fi

rm -f "$TAR_LIST"
# ==============================================================

#--------------sudo temp file 临时sudo--------------------#
SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" >"$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"
log "Temp sudo file created..."

# 清理函数及陷阱
cleanup_sudo() {
    if [[ -f "$SUDO_TEMP_FILE" ]]; then
        rm -f "$SUDO_TEMP_FILE"
        log "Security: Temporary sudo privileges revoked."
    fi
}
trap cleanup_sudo EXIT INT TERM

DMS_DOTFILES_DIR="$PARENT_DIR/dms-dotfiles"

# === 文档管理器配置 ===
configure_nautilus_user

if command -v niri &>/dev/null; then
    log "Niri detected, installing Thunar and related plugins..."
    exe as_user yay -S --noconfirm --needed xdg-desktop-portal-gtk thunar tumbler ffmpegthumbnailer poppler-glib gvfs-smb file-roller thunar-archive-plugin gnome-keyring thunar-volman gvfs-mtp gvfs-gphoto2 webp-pixbuf-loader libgsf
fi

force_copy "$DMS_DOTFILES_DIR/.config/Thunar" "$HOME_DIR/.config/"
force_copy "$DMS_DOTFILES_DIR/.config/xfce4" "$HOME_DIR/.config/"
force_copy "$DMS_DOTFILES_DIR/.config/gtk-3.0" "$HOME_DIR/.config/"
as_user sed -i "s/shorin/$TARGET_USER/g" "$HOME_DIR/.config/gtk-3.0/bookmarks"

# === shorin niri自定义配置 ===
sed -i '/match namespace="\^quickshell\$"/,/}/ s/place-within-backdrop[[:space:]]\+true/place-within-backdrop false/' "$DMS_NIRI_CONFIG_FILE"
sed -i -E '/^\s*\/\//b; s/^(\s*)numlock/\1\/\/numlock/' "$DMS_NIRI_CONFIG_FILE"

exe as_user yay -S --noconfirm --needed satty mpv kitty
force_copy "$DMS_DOTFILES_DIR/.config/mpv" "$HOME_DIR/.config/"
force_copy "$DMS_DOTFILES_DIR/.config/satty" "$HOME_DIR/.config/"
force_copy "$DMS_DOTFILES_DIR/.config/fuzzel" "$HOME_DIR/.config/"
force_copy "$DMS_DOTFILES_DIR/.config/shorin-niri" "$HOME_DIR/.config/niri/"

if ! grep -q "screenshot-sound.sh" "$DMS_NIRI_CONFIG_FILE"; then
    echo 'spawn-at-startup "~/.config/niri/shorin-niri/scripts/screenshot-sound.sh"' >> "$DMS_NIRI_CONFIG_FILE"
fi

if ! grep -q 'include "shorin-niri/rule.kdl"' "$DMS_NIRI_CONFIG_FILE"; then
    log "Importing Shorin's custom keybindings into niri config..."
    echo 'include "shorin-niri/rule.kdl"' >> "$DMS_NIRI_CONFIG_FILE"
    echo 'include "shorin-niri/supertab.kdl"' >> "$DMS_NIRI_CONFIG_FILE"
    sed -i '/Mod+Tab repeat=false { toggle-overview; }/d' "$HOME_DIR/.config/niri/dms/binds.kdl"
fi

# === 光标配置 ===
section "Shorin DMS" "cursor"
as_user mkdir -p "$HOME_DIR/.local/share/icons"
force_copy "$DMS_DOTFILES_DIR/.local/share/icons/breeze_cursors" "$HOME_DIR/.local/share/icons/"

if ! grep -q "^[[:space:]]*cursor[[:space:]]*{" "$DMS_NIRI_CONFIG_FILE"; then
    log "Cursor configuration missing. Appending default cursor block..."
    cat <<EOT >> "$DMS_NIRI_CONFIG_FILE"

// 光标配置
cursor {
    xcursor-theme "breeze_cursors"
    xcursor-size 30
    hide-after-inactive-ms 15000
}
EOT
else
    log "Cursor configuration block already exists, skipping."
fi

# === 自定义fish和kitty配置 === 
if command -v kitty &>/dev/null; then
    section "Shorin DMS" "terminal and shell"
    log "Applying Shorin DMS custom configurations for Terminal..."
    
    exe pacman -S --noconfirm --needed fuzzel wf-recorder slurp eza zoxide starship jq fish libnotify timg imv cava imagemagick wl-clipboard cliphist 
    
    chown -R "$TARGET_USER:" "$DMS_DOTFILES_DIR"
    as_user mkdir -p "$HOME_DIR/.config"
    force_copy "$DMS_DOTFILES_DIR/.config/fish" "$HOME_DIR/.config/"
    force_copy "$DMS_DOTFILES_DIR/.config/kitty" "$HOME_DIR/.config/"
    force_copy "$DMS_DOTFILES_DIR/.config/starship.toml" "$HOME_DIR/.config/"
    
    as_user mkdir -p "$HOME_DIR/.local/bin"
    force_copy "$DMS_DOTFILES_DIR/.local/bin/." "$HOME_DIR/.local/bin/"
else
    log "Kitty not found, skipping Kitty configuration."
fi

# === mimeapps配置 ===
section "Shorin DMS" "mimeapps"
force_copy "$DMS_DOTFILES_DIR/.config/mimeapps.list" "$HOME_DIR/.config/"

# === vim 配置 ===
section "Shorin DMS" "vim"
log "Configuring Vim for Shorin DMS..."
force_copy "$DMS_DOTFILES_DIR/.vimrc" "$HOME_DIR/"

# === flatpak 配置 ===
section "Shorin DMS" "flatpak"
log "Configuring Flatpak for Shorin DMS..."

if command -v flatpak &>/dev/null; then
    exe as_user yay -S --noconfirm --needed bazaar
    as_user flatpak override --user --filesystem=xdg-data/themes
    as_user flatpak override --user --filesystem="$HOME_DIR/.themes"
    as_user flatpak override --user --filesystem=xdg-config/gtk-4.0
    as_user flatpak override --user --filesystem=xdg-config/gtk-3.0
    as_user flatpak override --user --env=GTK_THEME=adw-gtk3-dark
    as_user flatpak override --user --filesystem=xdg-config/fontconfig
    as_user ln -sf /usr/share/themes "$HOME_DIR/.local/share/themes"
fi

# === matugen 配置 ===
section "Shorin DMS" "matugen"
log "Configuring Matugen for Shorin DMS..."
exe as_user yay -S --noconfirm --needed matugen python-pywalfox firefox adw-gtk-theme 

force_copy "$DMS_DOTFILES_DIR/.config/matugen" "$HOME_DIR/.config/"
force_copy "$DMS_DOTFILES_DIR/.config/btop" "$HOME_DIR/.config/"
force_copy "$DMS_DOTFILES_DIR/.config/cava" "$HOME_DIR/.config/"
force_copy "$DMS_DOTFILES_DIR/.config/yazi" "$HOME_DIR/.config/"
force_copy "$DMS_DOTFILES_DIR/.config/fcitx5" "$HOME_DIR/.config/"

sed -i '/Mod+Space hotkey-overlay-title="Application Launcher" {/,/}/d' "$HOME_DIR/.config/niri/dms/binds.kdl"

log "Configuring Firefox Policies..."
POL_DIR="/etc/firefox/policies"
exe mkdir -p "$POL_DIR"
echo '{ "policies": { "Extensions": { "Install": ["https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi"] } } }' >"$POL_DIR/policies.json"
exe chmod 755 "$POL_DIR"
exe chmod 644 "$POL_DIR/policies.json"

# === 壁纸 ===
section "Shorin DMS" "wallpaper"
WALLPAPER_SOURCE_DIR="$PARENT_DIR/resources/Wallpapers"
WALLPAPER_DIR="$HOME_DIR/Pictures/Wallpapers"

chown -R "$TARGET_USER:" "$WALLPAPER_SOURCE_DIR"
as_user mkdir -p "$WALLPAPER_DIR"
force_copy "$WALLPAPER_SOURCE_DIR/." "$WALLPAPER_DIR/"

# === 主题 ===
section "Shorin DMS" "theme"
log "Configuring themes for Shorin DMS..."

if ! grep -q 'QS_ICON_THEME "Adwaita"' "$DMS_NIRI_CONFIG_FILE"; then
    log "QT/Icon variables missing. Injecting into environment block..."
    sed -i '/^[[:space:]]*environment[[:space:]]*{/a \
// qt theme\
QT_QPA_PLATFORMTHEME "gtk3"\
QT_QPA_PLATFORMTHEME_QT6 "gtk3"\
// fix quickshell icon theme missing\
QS_ICON_THEME "Adwaita"' "$DMS_NIRI_CONFIG_FILE"
else
    log "QT/Icon variables already exist in environment block."
fi

# === font configuration字体配置 ===
section "Shorin DMS" "fonts"
log "Configuring fonts for Shorin DMS..."
exe as_user yay -S --noconfirm --needed ttf-jetbrains-maple-mono-nf-xx-xx
force_copy "$DMS_DOTFILES_DIR/.config/fontconfig" "$HOME_DIR/.config/"

# === 处理dms和shorin的快捷键冲突 ===
section "Shorin DMS" "keybindings"
force_copy "$DMS_DOTFILES_DIR/.config/dms-niri/binds.kdl" "$HOME_DIR/.config/niri/dms/."

# === 隐藏多余的 Desktop 图标 ===
section "Config" "Hiding useless .desktop files"
log "Hiding useless .desktop files"
run_hide_desktop_file

# === 教程文件 ===
section "Shorin DMS" "tutorial"
log "Copying tutorial files for Shorin DMS..."
force_copy "$PARENT_DIR/resources/必看-Shorin-DMS-Niri使用方法.txt" "$HOME_DIR"

log "Module 04c completed."