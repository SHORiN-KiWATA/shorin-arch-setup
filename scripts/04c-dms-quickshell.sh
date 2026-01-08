#!/bin/bash
# 04c-quickshell-setup.sh

# 1. 引用工具库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/00-utils.sh" ]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found."
    exit 1
fi

section "Extras" "Quickshell (DMS) Setup"

# 2. 获取目标用户 (必须准确，因为脚本禁止 Root)

DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
TARGET_USER="${DETECTED_USER:-$(read -p "Target user: " u && echo $u)}"

if [ -z "$TARGET_USER" ]; then
    error "Could not detect target user. Skipping DMS installation."
    exit 1
fi

log "Target user for DMS installation: $TARGET_USER"

# 3. 安装脚本所需的依赖 (gzip 是关键，其他通常都有)
log "Ensuring dependencies (gzip, curl)..."
exe pacman -S --noconfirm --needed gzip curl

# 4. 下载并执行安装脚本
# 我们不直接 curl | sh，而是下载下来处理，更稳健
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
    # 我们进入用户的家目录执行，以防万一它在当前目录写文件
    if runuser -u "$TARGET_USER" -- bash -c "cd ~ && $INSTALLER_SCRIPT"; then
        success "DankMaterialShell installed successfully."
    else
        # DMS 安装失败不应该导致整个系统安装退出，所以只警告
        warn "DMS installer returned an error code. You may need to install it manually."
    fi
    
    # 清理
    rm -f "$INSTALLER_SCRIPT"
else
    warn "Failed to download DMS installer script from $DMS_URL."
fi

log "Module 05 completed."