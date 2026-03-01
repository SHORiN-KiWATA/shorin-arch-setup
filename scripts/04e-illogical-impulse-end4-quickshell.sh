#!/bin/bash
# 04e-illogical-impulse-end4-quickshell.sh

# 1. 引用工具库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
if [ -f "$SCRIPT_DIR/00-utils.sh" ]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found."
    exit 1
fi
log "installing Illogical Impulse End4 (Quickshell)..."

# ==============================================================================
#  Identify User & DM Check
# ==============================================================================
log "Identifying user..."
detect_target_user
info_kv "Target" "$TARGET_USER"

# DM Check
check_dm_conflict

log "Target user for End4 installation: $TARGET_USER"
# ==============================================================================
#  install
# ==============================================================================
section "Desktop" "illogical-impulse"
# 下载并执行安装脚本
INSTALLER_SCRIPT="/tmp/end4_install.sh"
II_URL="https://ii.clsty.link/get"

log "Downloading Illogical Impulse installer wrapper..."
if curl -fsSL "$II_URL" -o "$INSTALLER_SCRIPT"; then
    
    chmod +x "$INSTALLER_SCRIPT"
    chown "$TARGET_USER" "$INSTALLER_SCRIPT"

    log "Executing End4 installer as user ($TARGET_USER)..."
    log "NOTE: If the installer asks for input, this script might hang."
    
    if runuser -u "$TARGET_USER" -- bash -c "cd ~ && $INSTALLER_SCRIPT"; then
        success "Illogical Impulse End4 installed successfully."
    else
        # 安装失败不应该导致整个系统安装退出，所以只警告
        warn "End4 installer returned an error code. You may need to install it manually."
    fi
    rm -f "$INSTALLER_SCRIPT"
else
    warn "Failed to download installer script from $II_URL."
fi
# ==============================================================================
#  Input Method & Environment (End4 Config)
# ==============================================================================
section "end4" "Input Method and Environment Configuration"

# 1. 定义变量与路径
END4_HYPR_DOT_DIR="$HOME_DIR/.config/hypr"
CUSTOM_DIR="$END4_HYPR_DOT_DIR/custom"
END4_HYPR_CUS_ENV="$CUSTOM_DIR/env.conf"
END4_HYPR_CUS_EXEC="$CUSTOM_DIR/execs.conf"
SOURCE_DOTFILES="$PARENT_DIR/quickshell-dotfiles"

# 2. 部署配置文件
if [ -d "$SOURCE_DOTFILES" ]; then
    log "Deploying Quickshell dotfiles to $HOME_DIR/.config/..."
    chown -R "$TARGET_USER:" "$SOURCE_DOTFILES"
    as_user cp -rf "$SOURCE_DOTFILES/." "$HOME_DIR/"
else
    warn "Source directory not found: $SOURCE_DOTFILES"
    warn "Skipping dotfiles copy."
fi

# 确保 custom 目录存在 (防止因拷贝未发生而导致后续报错)
if [ ! -d "$CUSTOM_DIR" ]; then
    mkdir -p "$CUSTOM_DIR"
    log "Created missing directory: $CUSTOM_DIR"
fi

# 3. 配置环境变量 (env.conf)
# 使用 grep 检查是否已经存在 fcitx 配置，防止重复追加
if ! grep -q "XMODIFIERS,@im=fcitx" "$END4_HYPR_CUS_ENV" 2>/dev/null; then
    log "Injecting Fcitx5 environment variables into env.conf..."
    
    # 补充了 QT, GTK, SDL 的输入法变量，确保在各种应用中都能唤起输入法
    cat << EOT >> "$END4_HYPR_CUS_ENV"

# --- Added by Shorin-Setup Script ---
# Fcitx5 Input Method Variables
env = XMODIFIERS,@im=fcitx
env = LC_CTYPE,en_US.UTF-8
# Locale Settings
env = LANG,zh_CN.UTF-8
# ----------------------------------
EOT
else
    log "Fcitx5 environment variables already exist in env.conf, skipping."
fi

# 4. 配置自动启动 (execs.conf)
# 同样检查防止重复添加
if ! grep -q "^[[:space:]]*exec-once = fcitx5 -d" "$END4_HYPR_CUS_EXEC" 2>/dev/null; then
    log "Adding Fcitx5 autostart command to execs.conf..."

    echo "exec-once = fcitx5 -d" >> "$END4_HYPR_CUS_EXEC"

else
    log "Fcitx5 autostart already exists in execs.conf, skipping."
fi

# 5. 统一修复权限 (Critical Step)
# 必须在所有写入操作完成后执行，确保新追加的内容也属于目标用户
log "Applying permission fixes for user: $TARGET_USER..."
chown -R "$TARGET_USER" "$HOME_DIR/.config"

success "End4 input method and environment configured."
# ==============================================================================
#  screenshare
# ==============================================================================
section "end4" "Screenshare"
pacman -S --noconfirm --needed xdg-desktop-portal-hyprland



# === 隐藏多余的 Desktop 图标 ===
section "Config" "Hiding useless .desktop files"
log "Hiding useless .desktop files"
run_hide_desktop_file

# ==============================================================================
#  autologin
# ==============================================================================
section "Config" "Display Manager"

# 1. 清理旧的 TTY 自动登录残留（无论是否启用 greetd，旧版残留都应清除）
log "Cleaning up legacy TTY autologin configs..."
rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf 2>/dev/null

if [ "$SKIP_DM" = true ]; then
  log "Display Manager setup skipped (Conflict found or user opted out)."
  warn "You will need to start your session manually from the TTY."
else

  setup_greetd_tuigreet
fi

log "Module 04e (End4) completed."