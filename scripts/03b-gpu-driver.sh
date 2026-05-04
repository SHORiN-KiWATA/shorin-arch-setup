#!/bin/bash

# ==============================================================================
# 03b-gpu-driver.sh GPU Driver Installer (Powered by chwd)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/00-utils.sh" ]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found."
    exit 1
fi

check_root

section "Phase 2b" "GPU Driver Setup"

DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
TARGET_USER="${DETECTED_USER:-$(read -p "Target user: " u && echo $u)}"

#--------------sudo temp file--------------------#
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

# ==============================================================================
# 1. 安装你的专属硬件检测工具
# ==============================================================================
log "Installing chwd-arch-git from AUR..."
exe runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed --answerdiff=None --answerclean=None chwd-arch-git

# ==============================================================================
# 2. 自动检测并安装驱动
# ==============================================================================
log "Running Automated Hardware Detection and Driver Installation..."
# -a 自动配置所有匹配的 PCI 设备
chwd -a

# 检查上一条命令是否成功
if [ $? -eq 0 ]; then
    success "Hardware drivers installed via chwd."
else
    warn "chwd encountered an error. Please check pacman logs."
fi

# ==============================================================================
# 4. 启用服务
# ==============================================================================
log "Enabling services (if supported)..."
# 注意：有些服务可能因为硬件不支持而没安装，这里用 || true 防止脚本中断
systemctl enable switcheroo-control.service &>/dev/null || true

# Nvidia 特有服务 (如果系统里存在 nvidia 相关文件才执行)
if lsmod | grep -q nvidia || lspci | grep -i nvidia -q; then
    systemctl enable --now nvidia-powerd &>/dev/null || true
    systemctl enable nvidia-suspend.service &>/dev/null || true
    systemctl enable nvidia-hibernate.service &>/dev/null || true
    systemctl enable nvidia-resume.service &>/dev/null || true
fi

log "Module 03b completed."