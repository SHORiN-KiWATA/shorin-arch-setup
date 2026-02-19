#!/bin/bash
# 04c-quickshell-setup.sh

# 1. 引用工具库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
if [ -f "$SCRIPT_DIR/00-utils.sh" ]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found."
    exit 1
fi

# --- 函数定义：静默删除 niri 绑定 ---
niri_remove_bind() {
    local target_key="$1"
    # 确保使用脚本中定义的 HOME_DIR 变量
    local config_file="$HOME_DIR/.config/niri/dms/binds.kdl"

    if [ ! -f "$config_file" ]; then
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

    # 正则逻辑：
    # (?m)^\\s* -> 多行模式，匹配行首空白
    # (?!//)     -> 排除以 // 开头的注释行
    # .*?        -> 懒惰匹配
    # (?=\\s|\{) -> 确保 key 后面是空格或左大括号（防止 Mod+T 误删 Mod+Tab）
    pattern = re.compile(r'(?m)^\s*(?!//).*?' + re.escape(target_key) + r'(?=\s|\{)')

    while True:
        match = pattern.search(content)
        if not match:
            break

        start_idx = match.start()
        
        # 找左大括号 {
        open_brace_idx = content.find('{', start_idx)
        if open_brace_idx == -1:
            break 
        
        # 找匹配的右大括号 } (处理嵌套)
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
            # 如果块后面紧跟换行符，连换行符一起删，保持整洁
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


log "installing dms..."
# ==============================================================================
#  Identify User & DM Check
# ==============================================================================
log "Identifying user..."
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
TARGET_USER="${DETECTED_USER:-$(read -p "Target user: " u && echo $u)}"
HOME_DIR="/home/$TARGET_USER"
info_kv "Target" "$TARGET_USER"

# DM Check
KNOWN_DMS=("gdm" "sddm" "lightdm" "lxdm" "slim" "xorg-xdm" "ly" "greetd" "plasma-login-manager")
SKIP_AUTOLOGIN=false
DM_FOUND=""
for dm in "${KNOWN_DMS[@]}"; do
  if pacman -Q "$dm" &>/dev/null; then
    DM_FOUND="$dm"
    break
  fi
done

if [ -n "$DM_FOUND" ]; then
  info_kv "Conflict" "${H_RED}$DM_FOUND${NC}"
  SKIP_AUTOLOGIN=true
else
  read -t 20 -p "$(echo -e "   ${H_CYAN}Enable TTY auto-login? [Y/n] (Default Y): ${NC}")" choice || true
  [[ "${choice:-Y}" =~ ^[Yy]$ ]] && SKIP_AUTOLOGIN=false || SKIP_AUTOLOGIN=true
fi

log "Target user for DMS installation: $TARGET_USER"

# 下载并执行安装脚本
INSTALLER_SCRIPT="/tmp/dms_install.sh"
DMS_URL="https://install.danklinux.com"

log "Downloading DMS installer wrapper..."
if curl -fsSL "$DMS_URL" -o "$INSTALLER_SCRIPT"; then
    
    # 赋予执行权限
    chmod +x "$INSTALLER_SCRIPT"
    
    # 将文件所有权给用户，否则 runuser 可能会因为权限问题读不到 /tmp 下的文件
    chown "$TARGET_USER" "$INSTALLER_SCRIPT"

    log "Executing DMS installer as user ($TARGET_USER)..."
    log "NOTE: If the installer asks for input, this script might hang."
    
    # --- 关键步骤：切换用户执行 ---
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

# dms.service 路径
DMS_AUTOSTART_LINK="$HOME_DIR/.config/systemd/user/graphical-session.target.wants/dms.service"
DMS_NIRI_CONFIG_FILE="$HOME_DIR/.config/niri/config.kdl"
DMS_HYPR_CONFIG_FILE="$HOME_DIR/.config/hypr/hyprland.conf"
# 删除dms自己的服务链接（如果有的话）
if [ -L "$DMS_AUTOSTART_LINK" ]; then
    log "detect dms systemd service enabled, disabling ...." 
    rm -f "$DMS_AUTOSTART_LINK"
fi

# 状态变量
DMS_NIRI_INSTALLED=false
DMS_HYPR_INSTALLED=false

# 检查安装的是niri还是hyprland
if command -v niri &>/dev/null; then 
    DMS_NIRI_INSTALLED=true
elif command -v hyprland &>/dev/null; then
    DMS_HYPR_INSTALLED=true
fi

# 修改niri配置文件设置dms自动启动
if [ $DMS_NIRI_INSTALLED = true ]; then

    if ! grep -E -q "^[[:space:]]*spawn-at-startup.*dms.*run" "$DMS_NIRI_CONFIG_FILE"; then
        log "enabling dms autostart in niri config.kdl..." 
        echo 'spawn-at-startup "dms" "run"' >> "$DMS_NIRI_CONFIG_FILE"
    else
        log "dms autostart already exists in niri config.kdl, skipping."
    fi

# 修改hyprland的配置文件设置dms自动启动
elif [ "$DMS_HYPR_INSTALLED" = true ]; then

    log "Configuring Hyprland autostart..."

    # 1. 配置 dms run
    # 检查文件中是否已经有 dms run 相关的 exec-once
    if ! grep -q "exec-once.*dms run" "$DMS_HYPR_CONFIG_FILE"; then
        log "Adding dms autostart to hyprland.conf"
        echo 'exec-once = dms run' >> "$DMS_HYPR_CONFIG_FILE"
    else
        log "dms autostart already exists in Hyprland config, skipping."
    fi
fi

# ==============================================================================
#  fcitx5 configuration and locale
# ==============================================================================
section "Config" "input method"

# niri的输入法配置
if [ "$DMS_NIRI_INSTALLED" = true ]; then

    # fcitx5 自动启动
    if ! grep -q "fcitx5" "$DMS_NIRI_CONFIG_FILE"; then
        log "enabling fcitx5 autostart in niri config.kdl..."
        echo 'spawn-at-startup "fcitx5" "-d"' >> "$DMS_NIRI_CONFIG_FILE"
    else
        log "fcitx5 autostart already exists, skipping."
    fi

    # 处理环境变量
    # 这里的 grep 检查是否存在 environment 块的开头
    if grep -q "^[[:space:]]*environment[[:space:]]*{" "$DMS_NIRI_CONFIG_FILE"; then
        log "Existing environment block found. Injecting fcitx variables..."
        
        # 检查是否已经写过 XMODIFIERS，防止重复插入
        if ! grep -q 'XMODIFIERS "@im=fcitx"' "$DMS_NIRI_CONFIG_FILE"; then
            # 使用 sed 在 'environment {' 这一行后面 (a)ppend 插入两行配置
            # \t 代表缩进，\n 代表换行
            sed -i '/^[[:space:]]*environment[[:space:]]*{/a \    LC_CTYPE "en_US.UTF-8"\n    XMODIFIERS "@im=fcitx"\n    LANG "zh_CN.UTF-8"' "$DMS_NIRI_CONFIG_FILE"
        else
            log "Environment variables for fcitx already exist, skipping."
        fi
        
    else
        log "No environment block found. Appending new block..."
        # 如果没有 environment 块，直接追加到底部
        cat << EOT >> "$DMS_NIRI_CONFIG_FILE"

environment {
    LC_CTYPE "en_US.UTF-8"
    XMODIFIERS "@im=fcitx"
    LANG "zh_CN.UTF-8"
}
EOT
    fi

    # 3. 复制其他配置
    chown -R "$TARGET_USER:" "$PARENT_DIR/quickshell-dotfiles"
    as_user cp -rf "$PARENT_DIR/quickshell-dotfiles/." "$HOME_DIR/"

# hyprland 的输入法配置
elif [ "$DMS_HYPR_INSTALLED" = true ]; then
    
    if ! grep -q "fcitx5" "$DMS_HYPR_CONFIG_FILE"; then
        log "Adding fcitx5 autostart to hyprland.conf"
        echo 'exec-once = fcitx5 -d' >> "$DMS_HYPR_CONFIG_FILE"
        
        # 【可选但推荐】同时写入 fcitx5 需要的环境变量
        # Hyprland 的环境变量写法是 env = KEY,VALUE
        cat << EOT >> "$DMS_HYPR_CONFIG_FILE"

# --- Added by Shorin-Setup Script ---
# Fcitx5 Input Method Variables
env = XMODIFIERS,@im=fcitx
env = LC_CTYPE,en_US.UTF-8
# Locale Settings
env = LANG,zh_CN.UTF-8
# ----------------------------------
EOT

    cp -rf "$PARENT_DIR/quickshell-dotfiles/"* "$HOME_DIR/.config/"
    chown -R "$TARGET_USER" "$HOME_DIR/.config"
    else
        log "fcitx5 configuration already exists in Hyprland config, skipping."
    fi
fi
# ==============================================================================
# filemanager
# ==============================================================================
section "Config" "file manager"

if [ "$DMS_NIRI_INSTALLED" = true ]; then
    log "dms niri detected, configuring nautilus"
    exe pacman -S --noconfirm --needed ffmpegthumbnailer gvfs-smb nautilus-open-any-terminal file-roller gnome-keyring gst-plugins-base gst-plugins-good gst-libav nautilus
    if pacman -Q | grep -q "kitty" && [ ! -f /usr/bin/gnome-terminal ] || [ -L /usr/bin/gnome-terminal ]; then
        ln -sf /usr/bin/kitty /usr/bin/gnome-terminal
    fi
    as_user mkdir -p "$HOME_DIR/Templates"
    as_user touch "$HOME_DIR/Templates/new"
    as_user touch "$HOME_DIR/Templates/new.sh"
    as_user echo "#!/bin/bash" >> "$HOME_DIR/Templates/new.sh"
    chown -R "$TARGET_USER" "$HOME_DIR/Templates"
# Nautilus Nvidia/Input Fix
    configure_nautilus_user


elif [ "$DMS_HYPR_INSTALLED" = true ]; then
    log "dms hyprland detected, skipping file manager "
fi

# ==============================================================================
#  screenshare
# ==============================================================================
section "Config" "screenshare"

if [ "$DMS_NIRI_INSTALLED" = true ]; then
    log "dms niri detected, configuring xdg-desktop-portal"
    exe pacman -S --noconfirm --needed xdg-desktop-portal-gnome
    
    if ! grep -q '/usr/lib/xdg-desktop-portal-gnome' $DMS_NIRI_CONFIG_FILE; then
    log "configuring environment in niri config.kdl"
    echo 'spawn-sh-at-startup "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=niri & /usr/lib/xdg-desktop-portal-gnome"' >> $DMS_NIRI_CONFIG_FILE
    fi

elif [ "$DMS_HYPR_INSTALLED" = true ]; then
    log "dms hyprland detected, configuring xdg-desktop-portal"
    exe pacman -S --noconfirm --needed xdg-desktop-portal-hyprland
    if ! grep -q '/usr/lib/xdg-desktop-portal-hyprland' $DMS_NIRI_CONFIG_FILE; then
        log "configuring environment in hyprland.conf"
        echo 'exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=hyprland & /usr/lib/xdg-desktop-portal-hyprland' >> $DMS_NIRI_CONFIG_FILE
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

if [ ${#MISSING_COMPONENTS[@]} -gt 0 ]; then
    warn "Validation failed! Missing components: ${MISSING_COMPONENTS[*]}"
    warn "Setting SKIP_AUTOLOGIN=true to prevent booting into a broken environment."
    SKIP_AUTOLOGIN=true
else
    success "All core components validated successfully."
fi
# ==============================================================================
#  tty autologin
# ==============================================================================
section "Config" "tty autostart"

SVC_DIR="$HOME_DIR/.config/systemd/user"

# 确保目录存在
as_user mkdir -p "$SVC_DIR/default.target.wants"
# tty自动登录
if [ "$SKIP_AUTOLOGIN" = false ]; then
    log "Configuring Niri Auto-start (TTY)..."
    mkdir -p "/etc/systemd/system/getty@tty1.service.d"
    echo -e "[Service]\nExecStart=\nExecStart=-/sbin/agetty --noreset --noclear --autologin $TARGET_USER - \${TERM}" >"/etc/systemd/system/getty@tty1.service.d/autologin.conf"

fi
# ===================================================
#  window manager autostart (if don't have any of dm)
# ===================================================
section "Config" "WM autostart"
# 如果安装了niri
if [ "$SKIP_AUTOLOGIN" = false ] && [ $DMS_NIRI_INSTALLED = true ] &>/dev/null; then
    SVC_FILE="$SVC_DIR/niri-autostart.service"
    LINK="$SVC_DIR/default.target.wants/niri-autostart.service"
    # 创建niri自动登录服务
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
    # 启用服务
    as_user ln -sf "$SVC_FILE" "$LINK"
    # 确保权限
    chown -R "$TARGET_USER" "$SVC_DIR"
    success "Niri/DMS auto-start enabled with DMS dependency."

# 如果安装了hyprland
elif [ "$SKIP_AUTOLOGIN" = false ] && [ $DMS_HYPR_INSTALLED = true ] &>/dev/null; then
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
    # 启用服务
    as_user ln -sf "$SVC_FILE" "$LINK"
    # 确保权限
    chown -R "$TARGET_USER" "$SVC_DIR"
    success "Hyprland DMS auto-start enabled with DMS dependency."

fi


# ============================================================================
#   Shorin DMS 杂交/自定义
#
# 
# ============================================================================
log "Checking if Niri is installed ..."
if ! command -v niri &>/dev/null; then
    SHORIN_DMS=0
fi 

if [ "$SHORIN_DMS" != "1" ]; then
    log "Shorin DMS not selected, skipping custom configurations."
    exit 0
fi

#--------------sudo temp file 临时sudo--------------------#
SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" >"$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"
log "Temp sudo file created..."

# 定义清理函数：无论脚本是成功结束还是意外中断(Ctrl+C)，都确保删除免密文件
cleanup_sudo() {
    if [ -f "$SUDO_TEMP_FILE" ]; then
        rm -f "$SUDO_TEMP_FILE"
        log "Security: Temporary sudo privileges revoked."
    fi
}
# 注册陷阱：在脚本退出(EXIT)或被中断(INT/TERM)时触发清理
trap cleanup_sudo EXIT INT TERM

# 定义 DMS 配置文件目录
DMS_DOTFILES_DIR="$PARENT_DIR/dms-dotfiles"

# === 文档管理器配置 ===
# 修复输入法导致nautilus无法重命名的问题
configure_nautilus_user
# 安装thuanar
if command -v niri &>/dev/null; then
    log "Niri detected, installing Thunar and related plugins..."
    exe as_user yay -S --noconfirm --needed xdg-desktop-portal-gtk thunar tumbler ffmpegthumbnailer poppler-glib gvfs-smb file-roller thunar-archive-plugin gnome-keyring thunar-volman gvfs-mtp gvfs-gphoto2 webp-pixbuf-loader libgsf
fi
exe as_user cp -rf "$DMS_DOTFILES_DIR/.config/Thunar" "$HOME_DIR/.config/"
exe as_user cp -rf "$DMS_DOTFILES_DIR/.config/xfce4" "$HOME_DIR/.config/"
# bookmarks侧边栏书签
exe as_user cp -rf "$DMS_DOTFILES_DIR/.config/gtk-3.0" "$HOME_DIR/.config/"
as_user sed -i "s/shorin/$TARGET_USER/g" "$HOME_DIR/.config/gtk-3.0/bookmarks"

# === shorin niri自定义配置 ===
# 修复壁纸图层问题
# ^quickshell$ place-within-backdrop true改成false
sed -i '/match namespace="\^quickshell\$"/,/}/ s/place-within-backdrop[[:space:]]\+true/place-within-backdrop false/' "$DMS_NIRI_CONFIG_FILE"
# 开启niri的时候不要自动开启数字锁定
sed -i -E '/^\s*\/\//b; s/^(\s*)numlock/\1\/\/numlock/' "$DMS_NIRI_CONFIG_FILE"
# 导入shorin的按键配置
# 按键依赖的软件和配置
exe as_user yay -S --noconfirm --needed satty mpv kitty
exe as_user cp -rf "$DMS_DOTFILES_DIR/.config/mpv" "$HOME_DIR/.config/"
exe as_user cp -rf "$DMS_DOTFILES_DIR/.config/satty" "$HOME_DIR/.config/"
exe as_user cp -rf "$DMS_DOTFILES_DIR/.config/fuzzel" "$HOME_DIR/.config/"

# 截图音效
if ! grep -q "screenshot-sound.sh" "$DMS_NIRI_CONFIG_FILE"; then
    echo 'spawn-at-startup "~/.config/niri/shorin-niri/scripts/screenshot-sound.sh"' >> "$DMS_NIRI_CONFIG_FILE"
fi
# 用我的快捷键覆盖dms的
if ! grep -q 'include "shorin-niri/binds.kdl"' "$DMS_NIRI_CONFIG_FILE"; then
    log "Importing Shorin's custom keybindings into niri config..."
    echo 'include "shorin-niri/rule.kdl"' >> "$DMS_NIRI_CONFIG_FILE"
    echo 'include "shorin-niri/supertab.kdl"' >> "$DMS_NIRI_CONFIG_FILE"
    # 移除按键冲突
    sed -i '/Mod+Tab repeat=false { toggle-overview; }/d' "$HOME_DIR/.config/niri/dms/binds.kdl"
fi

# === 光标配置 ===
section "Shorin DMS" "cursor"
as_user mkdir -p "$HOME_DIR/.local/share/icons"
exe as_user cp -rf "$DMS_DOTFILES_DIR/.local/share/icons/breeze_cursors" "$HOME_DIR/.local/share/icons/"
# Check if the cursor block already exists
if ! grep -q "^[[:space:]]*cursor[[:space:]]*{" "$DMS_NIRI_CONFIG_FILE"; then
    log "Cursor configuration missing. Appending default cursor block..."
    
    
    cat <<EOT >> "$DMS_NIRI_CONFIG_FILE"

// 光标配置
cursor {
    // 主题，存放路径在~/.local/share/icons
    xcursor-theme "breeze_cursors"
    // 大小
    xcursor-size 30
    // 闲置多少毫秒自动隐藏光标
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
    # 安装依赖
    exe pacman -S --noconfirm --needed eza zoxide starship jq fish libnotify timg imv cava imagemagick wl-clipboard cliphist
    # 复制终端配置
    log "Copying Terminal configuration..."
    chown -R "$TARGET_USER:" "$DMS_DOTFILES_DIR"
    as_user mkdir -p "$HOME_DIR/.config"
    exe as_user cp -rf "$DMS_DOTFILES_DIR/.config/fish" "$HOME_DIR/.config/"
    exe as_user cp -rf "$DMS_DOTFILES_DIR/.config/kitty" "$HOME_DIR/.config/"
    exe as_user cp -rf "$DMS_DOTFILES_DIR/.config/starship.toml" "$HOME_DIR/.config/"
    # 复制自定义脚本
    as_user mkdir -p "$HOME_DIR/.local/bin"
    exe as_user cp -rf "$DMS_DOTFILES_DIR/.local/bin/." "$HOME_DIR/.local/bin/"

else
    log "Kitty not found, skipping Kitty configuration."
fi

# === mimeapps配置 ===
section "Shorin DMS" "mimeapps"
exe as_user cp -rf "$DMS_DOTFILES_DIR/.config/mimeapps.list" "$HOME_DIR/.config/"

# === vim 配置 ===
section "Shorin DMS" "vim"
log "Configuring Vim for Shorin DMS..."
exe as_user cp -rf "$DMS_DOTFILES_DIR/.vimrc" "$HOME_DIR/"

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
ln -sf /usr/share/themes "$HOME_DIR/.local/share/themes"
fi

# === matugen 配置  ===
section "Shorin DMS" "matugen"
log "Configuring Matugen for Shorin DMS..."
# 安装依赖
exe as_user yay -S --noconfirm --needed matugen python-pywalfox firefox adw-gtk-theme 
# 复制配置文件
# matugen
exe as_user cp -rf "$DMS_DOTFILES_DIR/.config/matugen" "$HOME_DIR/.config/"
# btop
exe as_user cp -rf "$DMS_DOTFILES_DIR/.config/btop" "$HOME_DIR/.config/"
# cava 
exe as_user cp -rf "$DMS_DOTFILES_DIR/.config/cava" "$HOME_DIR/.config/"
# yazi
exe as_user cp -rf "$DMS_DOTFILES_DIR/.config/yazi" "$HOME_DIR/.config/"
# fcitx5
rm -rf "$HOME_DIR/.config/fcitx5"
exe as_user cp -rf "$DMS_DOTFILES_DIR/.config/fcitx5" "$HOME_DIR/.config/"
# fcitx5 快捷键冲突配置
sed -i '/Mod+Space hotkey-overlay-title="Application Launcher" {/,/}/d' "$HOME_DIR/.config/niri/dms/binds.kdl"

# firefox插件
log "Configuring Firefox Policies..."
POL_DIR="/etc/firefox/policies"
exe mkdir -p "$POL_DIR"
echo '{ "policies": { "Extensions": { "Install": ["https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi"] } } }' >"$POL_DIR/policies.json"
exe chmod 755 "$POL_DIR" && exe chmod 644 "$POL_DIR/policies.json"

# === 壁纸 ===
section "Shorin DMS" "wallpaper"
WALLPAPER_SOURCE_DIR="$PARENT_DIR/resources/Wallpapers"
WALLPAPER_DIR="$HOME_DIR/Pictures/Wallpapers"

chown -R "$TARGET_USER:" "$WALLPAPER_SOURCE_DIR"
as_user mkdir -p "$WALLPAPER_DIR"
exe as_user cp -rf "$WALLPAPER_SOURCE_DIR/." "$WALLPAPER_DIR/"

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

# === font configuration字体配置  ===
section "Shorin DMS" "fonts"
log "Configuring fonts for Shorin DMS..."
# 依赖
exe as_user yay -S --noconfirm --needed ttf-jetbrains-maple-mono-nf-xx-xx
# 复制fontconfig
exe as_user cp -rf "$DMS_DOTFILES_DIR/.config/fontconfig" "$HOME_DIR/.config/"



# 处理dms和shorind的快捷键冲突
section "Shorin DMS" "keybindings"
rm -rf "$HOME_DIR/.config/niri/dms/binds.kdl"
exe as_user cp -rf "$DMS_DOTFILES_DIR/.config/dms-niri/binds.kdl" "$HOME_DIR/.config/niri/dms/."

# niri_remove_bind "Mod+V"
# niri_remove_bind "Super+X"
# niri_remove_bind "Mod+Comma"
# niri_remove_bind "Mod+Y"
# niri_remove_bind "Mod+N"
# niri_remove_bind "Mod+T"
# niri_remove_bind "Mod+WheelScrollDown"
# niri_remove_bind "Mod+WheelScrollUp"
# niri_remove_bind "Mod+Ctrl+WheelScrollDown"
# niri_remove_bind "Mod+Ctrl+WheelScrollUp"
# niri_remove_bind "Mod+Shift+1"
# niri_remove_bind "Mod+Shift+2"
# niri_remove_bind "Mod+Shift+3"
# niri_remove_bind "Mod+Shift+4"
# niri_remove_bind "Mod+Shift+5"
# niri_remove_bind "Mod+Shift+6"
# niri_remove_bind "Mod+Shift+7"
# niri_remove_bind "Mod+Shift+8"
# niri_remove_bind "Mod+Shift+9"
# niri_remove_bind "Mod+Alt+N"
# niri_remove_bind "Mod+Shift+F"
# niri_remove_bind "Mod+Shift+T"
# niri_remove_bind "Mod+W"
# niri_remove_bind "Mod+Shift+WheelScrollDown"
# niri_remove_bind "Mod+Shift+WheelScrollUp"
# niri_remove_bind "Mod+Shift+Left"
# niri_remove_bind "Mod+Shift+Right"
# niri_remove_bind "Mod+Shift+H"
# niri_remove_bind "Mod+Ctrl+Shift+WheelScrollDown"
# niri_remove_bind "Mod+Ctrl+Shift+WheelScrollUp"
# niri_remove_bind ""

# === 教程文件 ===
section "Shorin DMS" "tutorial"
log "Copying tutorial files for Shorin DMS..."
exe as_user cp -rf "$PARENT_DIR/resources/必看-Shorin-DMS-Niri使用方法.txt" "$HOME_DIR"

log "Module 05 completed."