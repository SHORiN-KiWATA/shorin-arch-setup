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
# === 隐藏多余的 Desktop 图标 ===
section "Config" "Hiding useless .desktop files"
log "Hiding useless .desktop files"
run_hide_desktop_file

# ==============================================================================
#  autologin
# ==============================================================================
section "Config" "Display Manager"

if [ "$SKIP_DM" = true ]; then
    log "Display Manager setup skipped (Conflict found or user opted out)."
    warn "You will need to start your session manually from the TTY."
else
    
    setup_ly
fi

log "Module 04e (End4) completed."
