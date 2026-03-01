#!/bin/bash

# ==============================================================================
# Script: 05-verify-desktop.sh
# Description: 
#   1. 黑盒环境启发式验证 (dms / quickshell)。
#   2. 显式包发货单对账 (pacman -T)。
#   3. 用户配置文件/软链接部署完整性验证。
#   一旦任何一环发现缺失，立即中断并退出 (exit 1)。
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

VERIFY_LIST="/tmp/shorin_install_verify.list"

section "Verification" "Auditing System State"

# ==============================================================================
# 1. 特殊环境启发式验证 (仅针对 Shorin DMS 系列)
# ==============================================================================
if [[ "$DESKTOP_ENV" == "shorindms" || "$DESKTOP_ENV" == "shorindmsgit" ]]; then
    log "Performing specialized heuristic checks for DMS blackbox..."
    DMS_ERRORS=0

    if ! command -v quickshell &>/dev/null && ! pacman -Qq | grep -q "quickshell"; then
        echo -e "   \033[1;31m->\033[0m \033[1;33mquickshell (or related package)\033[0m is MISSING!"
        DMS_ERRORS=1
    fi

    if ! command -v dms &>/dev/null && ! pacman -Qq | grep -q "dms-shell"; then
        echo -e "   \033[1;31m->\033[0m \033[1;33mdms-shell (or related package)\033[0m is MISSING!"
        DMS_ERRORS=1
    fi

    if [ "$DMS_ERRORS" -ne 0 ]; then
        echo ""
        error "DMS CORE VALIDATION FAILED!"
        write_log "FATAL" "DMS heuristic validation failed. quickshell or dms-shell is missing."
        echo -e "   ${H_YELLOW}>>> Exiting installer. The official DMS script might have failed. ${NC}"
        exit 1
    else
        success "DMS core components verified."
    fi
fi

# ==============================================================================
# 2. 清单统实验证 (发货单对账)
# ==============================================================================
if [ -f "$VERIFY_LIST" ]; then
    mapfile -t CHECK_PKGS < <(cat "$VERIFY_LIST" | tr ' ' '\n' | sed '/^[[:space:]]*$/d' | sort -u)

    if [ ${#CHECK_PKGS[@]} -gt 0 ]; then
        log "Verifying ${#CHECK_PKGS[@]} explicit packages..."
        MISSING_PKGS=$(pacman -T "${CHECK_PKGS[@]}" 2>/dev/null)

        if [ -n "$MISSING_PKGS" ]; then
            echo ""
            error "SOFTWARE INSTALLATION INCOMPLETE!"
            echo -e "   ${DIM}The following packages failed to install:${NC}"
            echo "$MISSING_PKGS" | awk '{print "   \033[1;31m->\033[0m \033[1;33m" $0 "\033[0m"}'
            echo ""
            if declare -f write_log >/dev/null; then
                write_log "FATAL" "Missing packages: $(echo "$MISSING_PKGS" | tr '\n' ' ')"
            fi
            error "Cannot proceed with a broken desktop environment."
            echo -e "   ${H_YELLOW}>>> Exiting installer. Please check your network or AUR helpers. ${NC}"
            exit 1
        else
            success "All explicit packages successfully verified."
            rm -f "$VERIFY_LIST"
        fi
    fi
fi

# ==============================================================================
# 3. 配置文件部署验证 (Dotfiles Audit)
# ==============================================================================
log "Identifying target user for config audit..."
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
TARGET_USER="${DETECTED_USER}"

if [ -z "$TARGET_USER" ]; then
    warn "Could not reliably detect user 1000. Skipping dotfiles audit."
else
    HOME_DIR="/home/$TARGET_USER"
    CONFIG_ERRORS=0

    # KISS 的检查小函数
    check_config_exists() {
        local path="$1"
        # -e 可以完美识别常规目录、文件，以及目标有效的软链接
        if [ ! -e "$path" ]; then
            echo -e "   \033[1;31m->\033[0m \033[1;33m$path\033[0m is MISSING or BROKEN!"
            CONFIG_ERRORS=$((CONFIG_ERRORS + 1))
        else
            log "  [OK] $path"
        fi
    }

    log "Auditing dotfiles for ${DESKTOP_ENV^^}..."

    case "$DESKTOP_ENV" in
        niri)
            check_config_exists "$HOME_DIR/.config/niri"
            check_config_exists "$HOME_DIR/.config/waybar"
            ;;
        shorindms|shorindmsgit)
            check_config_exists "$HOME_DIR/.config/niri/dms"
            ;;
        hyprniri)
            check_config_exists "$HOME_DIR/.config/hypr"
            ;;
        *)
            log "No specific config checks mapped for $DESKTOP_ENV. Skipping."
            ;;
    esac

    if [ "$CONFIG_ERRORS" -gt 0 ]; then
        echo ""
        error "DOTFILES DEPLOYMENT FAILED!"
        if declare -f write_log >/dev/null; then
            write_log "FATAL" "Dotfiles audit failed. $CONFIG_ERRORS paths missing or broken."
        fi
        echo -e "   ${H_YELLOW}>>> Exiting installer. The repository clone or symlink step might have failed. ${NC}"
        exit 1
    else
        success "Configuration files and symlinks deployed correctly."
    fi
fi

# 全部通关！
exit 0