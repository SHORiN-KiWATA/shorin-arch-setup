#!/bin/bash

# ==============================================================================
# GNOME Setup Script (04d-gnome.sh)
# ==============================================================================

# 引用工具库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# 检查 utils 脚本
if [ -f "$SCRIPT_DIR/00-utils.sh" ]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found."
    exit 1
fi

log "Initializing installation..."

check_root

# ==============================================================================
#  Identify User 
# ==============================================================================
log "Identifying user..."
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
TARGET_USER="${DETECTED_USER:-$(read -p "Target user: " u && echo $u)}"
TARGET_UID=$(id -u "$TARGET_USER") # 提前获取 UID，后续 DBUS 配置需要
HOME_DIR="/home/$TARGET_USER"

info_kv "Target User" "$TARGET_USER"
info_kv "Home Dir"    "$HOME_DIR"

# ==================================
# temp sudo without passwd
# ==================================
SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" >"$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"
log "Temp sudo file created..."

cleanup_sudo() {
    if [ -f "$SUDO_TEMP_FILE" ]; then
        rm -f "$SUDO_TEMP_FILE"
        log "Security: Temporary sudo privileges revoked."
    fi
}

trap cleanup_sudo EXIT INT TERM

#=================================================
# Step 1: Install base pkgs
#=================================================
section "Step 1" "Install base pkgs"
log "Installing GNOME and base tools..."
if exe as_user yay -S --noconfirm --needed --answerdiff=None --answerclean=None \
    gnome-desktop gnome-backgrounds gnome-tweaks gdm ghostty \
    gnome-control-center gnome-software flatpak file-roller \
    nautilus-python firefox nm-connection-editor pacman-contrib \
    dnsmasq ttf-jetbrains-maple-mono-nf-xx-xx; then
        log "Packages installed successfully."
else
        log "Installation failed."
        return 1
fi

# start gdm 
log "Enable gdm..."
exe systemctl enable gdm

#=================================================
# Step 2: Set default terminal
#=================================================
section "Step 2" "Set default terminal"
log "Setting GNOME default terminal to Ghostty..."
# 注意：这里如果普通 as_user 失败，通常是因为 dbus 连接问题，但此处保留原样
exe as_user gsettings set org.gnome.desktop.default-applications.terminal exec 'ghostty'
exe as_user gsettings set org.gnome.desktop.default-applications.terminal exec-arg '-e'

#=================================================
# Step 3: Set locale
#=================================================
section "Step 3" "Set locale"
log "Configuring GNOME locale for user $TARGET_USER..."
ACCOUNT_FILE="/var/lib/AccountsService/users/$TARGET_USER"
ACCOUNT_DIR=$(dirname "$ACCOUNT_FILE")
# 确保目录存在
mkdir -p "$ACCOUNT_DIR"
# 设置语言为中文
cat > "$ACCOUNT_FILE" <<EOF
[User]
Languages=zh_CN.UTF-8
EOF

#=================================================
# Step 4: Configure Shortcuts
#=================================================
section "Step 4" "Configure Shortcuts"
log "Configuring shortcuts..."

# 使用 sudo -u 切换用户并注入 DBUS 变量以修改 dconf
sudo -u "$TARGET_USER" bash <<EOF
    # 关键：手动指定 DBUS 地址
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${TARGET_UID}/bus"

    echo "   ➜ Applying shortcuts for user: $(whoami)..."

    # ---------------------------------------------------------
    # 1. org.gnome.desktop.wm.keybindings (窗口管理)
    # ---------------------------------------------------------
    SCHEMA="org.gnome.desktop.wm.keybindings"
    
    # 基础窗口控制
    gsettings set \$SCHEMA close "['<Super>q']"
    gsettings set \$SCHEMA show-desktop "['<Super>h']"
    gsettings set \$SCHEMA toggle-fullscreen "['<Alt><Super>f']"
    gsettings set \$SCHEMA toggle-maximized "['<Super>f']"
    
    # 清理未使用的窗口控制键 
    gsettings set \$SCHEMA maximize "[]"
    gsettings set \$SCHEMA minimize "[]"
    gsettings set \$SCHEMA unmaximize "[]"

    # 切换与移动工作区 
    gsettings set \$SCHEMA switch-to-workspace-left "['<Shift><Super>q']"
    gsettings set \$SCHEMA switch-to-workspace-right "['<Shift><Super>e']"
    gsettings set \$SCHEMA move-to-workspace-left "['<Control><Super>q']"
    gsettings set \$SCHEMA move-to-workspace-right "['<Control><Super>e']"
    
    # 切换应用/窗口 
    gsettings set \$SCHEMA switch-applications "['<Alt>Tab']"
    gsettings set \$SCHEMA switch-applications-backward "['<Shift><Alt>Tab']"
    gsettings set \$SCHEMA switch-group "['<Alt>grave']"
    gsettings set \$SCHEMA switch-group-backward "['<Shift><Alt>grave']"
    
    # 清理输入法切换快捷键
    gsettings set \$SCHEMA switch-input-source "[]"
    gsettings set \$SCHEMA switch-input-source-backward "[]"

    # ---------------------------------------------------------
    # 2. org.gnome.shell.keybindings (Shell 全局)
    # ---------------------------------------------------------
    SCHEMA="org.gnome.shell.keybindings"
    
    # 截图相关
    gsettings set \$SCHEMA screenshot "['<Shift><Control><Super>a']"
    gsettings set \$SCHEMA screenshot-window "['<Control><Super>a']"
    gsettings set \$SCHEMA show-screenshot-ui "['<Alt><Super>a']"
    
    # 界面视图
    gsettings set \$SCHEMA toggle-application-view "['<Super>g']"
    gsettings set \$SCHEMA toggle-quick-settings "['<Control><Super>s']"
    gsettings set \$SCHEMA toggle-message-tray "[]"

    # ---------------------------------------------------------
    # 3. org.gnome.settings-daemon.plugins.media-keys (媒体与自定义)
    # ---------------------------------------------------------
    SCHEMA="org.gnome.settings-daemon.plugins.media-keys"

    # 辅助功能
    gsettings set \$SCHEMA magnifier "['<Alt><Super>0']"
    gsettings set \$SCHEMA screenreader "[]"

    # --- 自定义快捷键逻辑 ---
    # 定义添加函数
    add_custom() {
        local index="\$1"
        local name="\$2"
        local cmd="\$3"
        local bind="\$4"
        
        local path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom\$index/"
        local key_schema="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:\$path"
        
        gsettings set "\$key_schema" name "\$name"
        gsettings set "\$key_schema" command "\$cmd"
        gsettings set "\$key_schema" binding "\$bind"
        
        echo "\$path"
    }

    # 构建自定义快捷键列表
    
    P0=\$(add_custom 0 "openbrowser" "firefox" "<Super>b")
    P1=\$(add_custom 1 "openterminal" "ghostty" "<Super>t")
    P2=\$(add_custom 2 "missioncenter" "missioncenter" "<Super>grave")
    P3=\$(add_custom 3 "opennautilus" "nautilus" "<Super>e")
    P4=\$(add_custom 4 "editscreenshot" "gradia --screenshot" "<Shift><Super>s")
    P5=\$(add_custom 5 "gnome-control-center" "gnome-control-center" "<Control><Alt>s")

    # 应用列表 (已移除重复的 P6)
    CUSTOM_LIST="['\$P0', '\$P1', '\$P2', '\$P3', '\$P4', '\$P5']"
    gsettings set \$SCHEMA custom-keybindings "\$CUSTOM_LIST"
    
    echo "   ➜ Shortcuts synced with config files successfully."
EOF

#=================================================
# Step 5: Extensions
#=================================================
section "Step 5" "Install Extensions"
log "Installing Extensions CLI..."

sudo -u $TARGET_USER yay -S --noconfirm --needed --answerdiff=None --answerclean=None gnome-extensions-cli

EXTENSION_LIST=(
    "arch-update@RaphaelRochet"
    "aztaskbar@aztaskbar.gitlab.com"
    "blur-my-shell@aunetx"
    "caffeine@patapon.info"
    "clipboard-indicator@tudmotu.com"
    "color-picker@tuberry"
    "desktop-cube@schneegans.github.com"
    "ding@rastersoft.com"
    "fuzzy-application-search@mkhl.codeberg.page"
    "lockkeys@vaina.lt"
    "middleclickclose@paolo.tranquilli.gmail.com"
    "steal-my-focus-window@steal-my-focus-window"
    "tilingshell@ferrarodomenico.com"
    "user-theme@gnome-shell-extensions.gcampax.github.com"
    "kimpanel@kde.org"
    "rounded-window-corners@fxgn"
)
log "Downloading extensions..."
sudo -u $TARGET_USER gnome-extensions-cli install ${EXTENSION_LIST[@]} 2>/dev/null

section "Step 5.2" "Enable GNOME Extensions"
sudo -u "$TARGET_USER" bash <<EOF
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${TARGET_UID}/bus"

    # 定义一个函数来安全地启用扩展 (追加模式)
    enable_extension() {
        local uuid="\$1"
        local current_list=\$(gsettings get org.gnome.shell enabled-extensions)
        
        # 检查是否已经在列表中
        if [[ "\$current_list" == *"\$uuid"* ]]; then
            echo "   -> Extension \$uuid already enabled."
        else
            echo "   -> Enabling extension: \$uuid"
            # 如果列表为空 (@as [])，直接设置；否则追加
            if [ "\$current_list" = "@as []" ]; then
                gsettings set org.gnome.shell enabled-extensions "['\$uuid']"
            else
                new_list="\${current_list%]}, '\$uuid']"
                gsettings set org.gnome.shell enabled-extensions "\$new_list"
            fi
        fi
    }

    echo "   ➜ Activating extensions via gsettings..."

    enable_extension "user-theme@gnome-shell-extensions.gcampax.github.com"
    enable_extension "arch-update@RaphaelRochet"
    enable_extension "aztaskbar@aztaskbar.gitlab.com"
    enable_extension "blur-my-shell@aunetx"
    enable_extension "caffeine@patapon.info"
    enable_extension "clipboard-indicator@tudmotu.com"
    enable_extension "color-picker@tuberry"
    enable_extension "desktop-cube@schneegans.github.com"
    enable_extension "ding@rastersoft.com"
    enable_extension "fuzzy-application-search@mkhl.codeberg.page"
    enable_extension "lockkeys@vaina.lt"
    enable_extension "middleclickclose@paolo.tranquilli.gmail.com"
    enable_extension "steal-my-focus-window@steal-my-focus-window"
    enable_extension "tilingshell@ferrarodomenico.com"
    enable_extension "kimpanel@kde.org"
    enable_extension "rounded-window-corners@fxgn"

    echo "   ➜ Extensions activation request sent."
EOF

# 编译扩展 Schema (防止报错)
log "Compiling extension schemas..."
# 先确保所有权正确
chown -R $TARGET_USER:$TARGET_USER $HOME_DIR/.local/share/gnome-shell/extensions

sudo -u "$TARGET_USER" bash <<EOF
    EXT_DIR="$HOME_DIR/.local/share/gnome-shell/extensions"
    
    echo "   ➜ Compiling schemas in \$EXT_DIR..."
    for dir in "\$EXT_DIR"/*; do
        if [ -d "\$dir/schemas" ]; then
            glib-compile-schemas "\$dir/schemas"
        fi
    done
EOF

#=================================================
# Firefox Policies
#=================================================
section "Firefox" "Configuring Firefox GNOME Integration"
exe sudo -u $TARGET_USER yay -S --noconfirm --needed --answerdiff=None --answerclean=None gnome-browser-connector

# 配置 Firefox 策略自动安装扩展
POL_DIR="/etc/firefox/policies"
exe mkdir -p "$POL_DIR"

echo '{
  "policies": {
    "Extensions": {
      "Install": [
        "https://addons.mozilla.org/firefox/downloads/latest/gnome-shell-integration/latest.xpi"
      ]
    }
  }
}' > "$POL_DIR/policies.json"

exe chmod 755 "$POL_DIR" && exe chmod 644 "$POL_DIR/policies.json"
log "Firefox policies updated."
#=================================================
# nautilus fix
#=================================================
DESKTOP_FILE="/usr/share/applications/org.gnome.Nautilus.desktop"
if [ -f "$DESKTOP_FILE" ]; then
  GPU_COUNT=$(lspci | grep -E -i "vga|3d" | wc -l)
  HAS_NVIDIA=$(lspci | grep -E -i "nvidia" | wc -l)
  [ "$GPU_COUNT" -gt 1 ] && [ "$HAS_NVIDIA" -gt 0 ] && ENV_VARS="env GSK_RENDERER=gl GTK_IM_MODULE=fcitx"

  if ! grep -q "^Exec=$ENV_VARS" "$DESKTOP_FILE"; then
    exe sed -i "s|^Exec=|Exec=$ENV_VARS |" "$DESKTOP_FILE"
  fi

  if ! grep -q GSK_RENDERER=gl /etc/environment; then 
    exe echo "GSK_RENDERER=gl" >> /etc/environment
  fi
fi

#=================================================
# Step 6: Input Method
#=================================================
section "Step 6" "Input method"
log "Configure input method environment..."

if ! grep -q "fcitx" "/etc/environment" 2>/dev/null; then
    cat << EOT >> /etc/environment
XIM="fcitx"
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
XDG_CURRENT_DESKTOP=GNOME
EOT
    log "Fcitx environment variables added."
else
    log "Fcitx environment variables already exist."
fi

#=================================================
# Dotfiles
#=================================================
section "Dotfiles" "Deploying dotfiles"
GNOME_DOTFILES_DIR=$PARENT_DIR/gnome-dotfiles

# 1. 确保目标目录存在
log "Ensuring .config exists..."
sudo -u $TARGET_USER mkdir -p $HOME_DIR/.config

# 2. 复制文件 (包含隐藏文件)
# 使用 /. 语法将源文件夹的*内容*合并到目标文件夹
log "Copying dotfiles..."
cp -rf "$GNOME_DOTFILES_DIR/." "$HOME_DIR/"

# 3. 修复权限 (因为 cp 是 root 运行的)
# 明确修复 home 目录下的关键配置文件夹，避免权限问题
log "Fixing permissions..."
chown -R $TARGET_USER:$TARGET_USER $HOME_DIR/.config
chown -R $TARGET_USER:$TARGET_USER $HOME_DIR/.local

# 4. 安装 Shell 工具
log "Installing shell tools..."
pacman -S --noconfirm --needed thefuck starship eza fish zoxide jq

log "Installation Complete! Please reboot."
cleanup_sudo