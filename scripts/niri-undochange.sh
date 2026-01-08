#!/bin/bash
# ==============================================================================
# Script: niri-undochange.sh
# Purpose: Emergency rollback to 'Before Niri Setup' checkpoint
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

check_root

echo ""
echo -e "${H_RED}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${H_RED}║              INSTALLATION FAILURE DETECTED           ║${NC}"
echo -e "${H_RED}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
warn "Critical error encountered during Niri setup."
log "Initiating system rollback to checkpoint: 'Before Desktop Environments'..."

# ------------------------------------------------------------------------------
# Function: Perform Rollback
# ------------------------------------------------------------------------------
perform_rollback() {
    local config="$1"
    local marker="Before Desktop Environments"
    
    # 1. 查找標記快照的 ID
    local snap_id
    snap_id=$(snapper -c "$config" list --columns number,description | grep "$marker" | awk '{print $1}' | tail -n 1)
    
    if [ -n "$snap_id" ]; then
        log "Reverting changes in '$config' (Target Snapshot ID: $snap_id)..."
        
        # 2. 執行撤銷 (undochange ID..0)
        # 這會將文件系統當前狀態(0) 恢復到 ID 的狀態
        if snapper -c "$config" undochange "$snap_id"..0; then
            success "Successfully reverted $config."
        else
            error "Failed to revert $config. Manual intervention required."
            # 如果回滾失敗，不要重啟，讓用戶看日誌
            exit 1 
        fi
    else
        warn "Checkpoint '$marker' not found in $config. Skipping."
    fi
}

# ------------------------------------------------------------------------------
# Execution
# ------------------------------------------------------------------------------

# 1. 回滾 Root 和 Home
perform_rollback "root"
perform_rollback "home"

# 2. [新增] 清理緩存 (Clean Caches)
# 這是為了確保下次重試時不會因為緩存損壞而再次失敗
log "Cleaning package manager caches..."

# 清理 Pacman 緩存 (刪除未安裝的包和緩存數據)
pacman -Sc --noconfirm

# 清理 Yay 緩存 (針對 UID 1000 用戶)
# 雖然回滾 /home 可能已經清除了一部分，但強制刪除是最保險的
MAIN_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
if [ -n "$MAIN_USER" ]; then
    YAY_CACHE="/home/$MAIN_USER/.cache/yay"
    if [ -d "$YAY_CACHE" ]; then
        log "Removing yay cache directory for $MAIN_USER..."
        rm -rf "$YAY_CACHE"
    fi
    
    # 順便清理 paru，如果存在的話
    PARU_CACHE="/home/$MAIN_USER/.cache/paru"
    if [ -d "$PARU_CACHE" ]; then
        rm -rf "$PARU_CACHE"
    fi
fi
success "Caches cleaned."

# 3. 狀態文件保護
# 我們保留 .install_progress 文件，這樣重啟後前面 00-03 的步驟會被自動跳過
# 但為了安全，我們確保 04-niri-setup.sh 不在裡面
if [ -f "$PARENT_DIR/.install_progress" ]; then
    sed -i "/04-niri-setup.sh/d" "$PARENT_DIR/.install_progress"
fi

# 4. 強制重啟與用戶提示
echo ""
echo -e "${H_YELLOW}╔═════════════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${H_YELLOW}║                                                                                     ║${NC}"
echo -e "${H_YELLOW}║   AFTER REBOOT: LOGIN AS YOUR ORIGINAL USER -> RUN install.sh AGAIN TO RETRY        ║${NC}"
echo -e "${H_YELLOW}║   AFTER REBOOT: LOGIN AS YOUR ORIGINAL USER -> RUN install.sh AGAIN TO RETRY        ║${NC}"
echo -e "${H_YELLOW}║   AFTER REBOOT: LOGIN AS YOUR ORIGINAL USER -> RUN install.sh AGAIN TO RETRY        ║${NC}"
echo -e "${H_YELLOW}║                                                                                     ║${NC}"
echo -e "${H_YELLOW}╚═════════════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

for i in {10..1}; do
    echo -ne "\r   ${H_RED}Rebooting in ${i}s...${NC}"
    sleep 1
done

echo ""
systemctl reboot