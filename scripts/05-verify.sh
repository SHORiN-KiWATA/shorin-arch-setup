#!/bin/bash

# ==============================================================================
# Script: 05-verify-desktop.sh
# Description: 
#   統一驗證前面步驟中預定安裝的軟體是否全數就位。
#   讀取 /tmp/shorin_install_verify.list 並使用 pacman -T 進行極速審計。
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"
VERIFY_LIST="/tmp/shorin_install_verify.list"

# 如果沒有生成清單（例如選擇了 none 桌面），則直接跳過
if [ ! -f "$VERIFY_LIST" ]; then
    log "No verification list found. Skipping software audit."
    exit 0
fi

section "Verification" "Auditing Installed Software"

# 讀取、替換空格為換行、去空行、去重，生成最終的檢查陣列
mapfile -t CHECK_PKGS < <(cat "$VERIFY_LIST" | tr ' ' '\n' | sed '/^[[:space:]]*$/d' | sort -u)

if [ ${#CHECK_PKGS[@]} -eq 0 ]; then
    log "Verification list is empty. Skipping."
    exit 0
fi

log "Verifying ${#CHECK_PKGS[@]} packages..."

# 核心：pacman -T 如果發現缺失，會輸出缺失包名並返回非 0
# 我們捕獲它的輸出
MISSING_PKGS=$(pacman -T "${CHECK_PKGS[@]}" 2>/dev/null)

if [ -n "$MISSING_PKGS" ]; then
    echo ""
    error "SOFTWARE INSTALLATION INCOMPLETE!"
    echo -e "   ${DIM}The following packages failed to install:${NC}"
    
    # 優雅地打印出所有沒有安裝上的軟體
    echo "$MISSING_PKGS" | awk '{print "   \033[1;31m->\033[0m \033[1;33m" $0 "\033[0m"}'
    
    echo ""
    write_log "FATAL" "Missing packages: $(echo "$MISSING_PKGS" | tr '\n' ' ')"
    error "Cannot proceed with a broken desktop environment."
    echo -e "   ${H_YELLOW}>>> Exiting installer. Please check your network or AUR helpers. ${NC}"
    
    # 這裡的 exit 1 是關鍵！它會把 1 傳給主腳本 install.sh
    # 主腳本收到 1 後，就會立刻停止，絕對不會去執行 07 和 99 模塊
    exit 1
else
    success "All ${#CHECK_PKGS[@]} packages successfully verified."
    # 驗證通過，清理臨時文件
    rm -f "$VERIFY_LIST"
    exit 0
fi