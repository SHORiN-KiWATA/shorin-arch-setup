#!/bin/bash

# ==============================================================================
# Script: 05-verify-desktop.sh
# Description: 
#   1. 针对黑盒环境 (DMS) 采取启发式核心验证 (检查 dms 和 quickshell)。
#   2. 統一驗證前面步驟中預定安裝的軟體是否全數就位 (讀取發貨單)。
#   一旦发现缺失，立即中断并退出 (exit 1)。
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

VERIFY_LIST="/tmp/shorin_install_verify.list"

section "Verification" "Auditing Installed Software"

# ==============================================================================
# 1. 特殊环境启发式验证 (仅针对 Shorin DMS 系列)
# ==============================================================================
if [[ "$DESKTOP_ENV" == "shorindms" || "$DESKTOP_ENV" == "shorindmsgit" ]]; then
    log "Performing specialized heuristic checks for DMS blackbox..."
    DMS_ERRORS=0

    # 验证 quickshell (支持 quickshell, quickshell-git 等变体或直接存在的命令)
    if ! command -v quickshell &>/dev/null && ! pacman -Qq | grep -q "quickshell"; then
        echo -e "   \033[1;31m->\033[0m \033[1;33mquickshell (or related package)\033[0m is MISSING!"
        DMS_ERRORS=1
    fi

    # 验证 dms-shell (支持 dms-shell-bin, dms-shell-git 等变体或 dms 命令)
    if ! command -v dms &>/dev/null && ! pacman -Qq | grep -q "dms-shell"; then
        echo -e "   \033[1;31m->\033[0m \033[1;33mdms-shell (or related package)\033[0m is MISSING!"
        DMS_ERRORS=1
    fi

    # 如果核心黑盒组件缺失，立刻斩断流程
    if [ "$DMS_ERRORS" -ne 0 ]; then
        echo ""
        error "DMS CORE VALIDATION FAILED!"
        write_log "FATAL" "DMS heuristic validation failed. quickshell or dms-shell is missing."
        echo -e "   ${H_YELLOW}>>> Exiting installer. The official DMS script might have failed. ${NC}"
        exit 1
    else
        success "DMS core components (quickshell & dms-shell) verified."
    fi
fi

# ==============================================================================
# 2. 清单统实验证 (发货单对账)
# ==============================================================================
if [ ! -f "$VERIFY_LIST" ]; then
    log "No verification list found. Skipping standard software audit."
    exit 0
fi

# 讀取、替換空格為換行、去空行、去重，生成最終的檢查陣列
mapfile -t CHECK_PKGS < <(cat "$VERIFY_LIST" | tr ' ' '\n' | sed '/^[[:space:]]*$/d' | sort -u)

if [ ${#CHECK_PKGS[@]} -eq 0 ]; then
    log "Verification list is empty. Skipping standard audit."
    exit 0
fi

log "Verifying ${#CHECK_PKGS[@]} explicit packages from previous steps..."

# 核心：pacman -T 如果發現缺失，會輸出缺失包名並返回非 0
MISSING_PKGS=$(pacman -T "${CHECK_PKGS[@]}" 2>/dev/null)

if [ -n "$MISSING_PKGS" ]; then
    echo ""
    error "SOFTWARE INSTALLATION INCOMPLETE!"
    echo -e "   ${DIM}The following packages failed to install:${NC}"
    
    # 優雅地打印出所有沒有安裝上的軟體
    echo "$MISSING_PKGS" | awk '{print "   \033[1;31m->\033[0m \033[1;33m" $0 "\033[0m"}'
    
    echo ""
    if declare -f write_log >/dev/null; then
        write_log "FATAL" "Missing packages: $(echo "$MISSING_PKGS" | tr '\n' ' ')"
    fi
    error "Cannot proceed with a broken desktop environment."
    echo -e "   ${H_YELLOW}>>> Exiting installer. Please check your network or AUR helpers. ${NC}"
    
    exit 1
else
    success "All ${#CHECK_PKGS[@]} explicit packages successfully verified."
    # 驗證通過，清理臨時文件
    rm -f "$VERIFY_LIST"
    exit 0
fi