#!/bin/bash

# ==============================================================================
# 03c-snapshot-before-desktop.sh
# Creates a system snapshot before installing major Desktop Environments.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. 引用工具库
if [ -f "$SCRIPT_DIR/00-utils.sh" ]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found."
    exit 1
fi

# 2. 权限检查
check_root

section "Phase 3c" "System Snapshot"

# ==============================================================================

create_checkpoint() {
    local MARKER="Before Desktop Environments"
    
    # 0. 检查 snapper 是否安装
    if ! command -v snapper &>/dev/null; then
        warn "Snapper tool not found. Skipping snapshot creation."
        return
    fi

    # 1. Root 分区快照
    # 检查 root 配置是否存在
    if snapper -c root get-config &>/dev/null; then
        # 检查是否已存在同名快照 (避免重复创建)
        if snapper -c root list --columns description | grep -Fqx "$MARKER"; then
            log "Snapshot '$MARKER' already exists on [root]."
        else
            log "Creating safety checkpoint on [root]..."
            # 使用 --type single 表示这是一个独立的存档点
            snapper -c root create --description "$MARKER"
            success "Root snapshot created."
        fi
    else
        warn "Snapper 'root' config not configured. Skipping root snapshot."
    fi

    # 2. Home 分区快照 (如果存在 home 配置)
    if snapper -c home get-config &>/dev/null; then
        if snapper -c home list --columns description | grep -Fqx "$MARKER"; then
            log "Snapshot '$MARKER' already exists on [home]."
        else
            log "Creating safety checkpoint on [home]..."
            snapper -c home create --description "$MARKER"
            success "Home snapshot created."
        fi
    fi
}




# ==============================================================================
# 执行
# ==============================================================================

log "Preparing to create restore point..."
create_checkpoint
rm -fv $HOME_DIR/.config/systemd/user/default.target.wants/hyprland-autostart.service
rm -fv $HOME_DIR/.config/systemd/user/default.target.wants/niri-autostart.service


log "Module 03c completed."