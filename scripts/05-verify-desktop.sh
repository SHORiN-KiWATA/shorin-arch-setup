#!/bin/bash

# ==============================================================================
# Script: 05-verify-desktop.sh
# Description:
#   2. 显式包发货单对账 (pacman -T)。
#   3. 用户配置文件/软链接部署完整性验证。
#   一旦任何一环发现缺失，立即中断并退出 (exit 1)。
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

VERIFY_LIST="/tmp/shorin_install_verify.list"

section "Verification" "Auditing System State"


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
detect_target_user

if [ -z "${TARGET_USER:-}" ]; then
    warn "Could not reliably detect user 1000. Skipping dotfiles audit."
else
    HOME_DIR="/home/$TARGET_USER"
    CONFIG_ERRORS=0
    
    # KISS 的常规检查小函数
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

    # 针对 shorinniri 的进阶检查：严格验证实体/软链接状态
    check_shorinniri_path() {
        local path="$1"
        local expect_link="$2" # true 或 false

        # 无论期待何种状态，目标必须有效存在。这能一刀切掉“缺失”和“死链接(Broken Symlink)”
        if [ ! -e "$path" ]; then
            echo -e "   \033[1;31m->\033[0m \033[1;33m$path\033[0m is MISSING or BROKEN!"
            CONFIG_ERRORS=$((CONFIG_ERRORS + 1))
            return
        fi

        # 状态机分化验证
        if [ "$expect_link" = "true" ]; then
            if [ ! -L "$path" ]; then
                echo -e "   \033[1;31m->\033[0m \033[1;33m$path\033[0m should be a SYMLINK, but it is a standalone entity!"
                CONFIG_ERRORS=$((CONFIG_ERRORS + 1))
            else
                log "  [OK] $path (symlink)"
            fi
        else
            if [ -L "$path" ]; then
                echo -e "   \033[1;31m->\033[0m \033[1;33m$path\033[0m should be an ENTITY, but it is a symlink!"
                CONFIG_ERRORS=$((CONFIG_ERRORS + 1))
            else
                log "  [OK] $path (entity)"
            fi
        fi
    }
    
    log "Auditing dotfiles for ${DESKTOP_ENV^^}..."
    
    case "$DESKTOP_ENV" in
        shorindms|shorindmsgit)
            check_config_exists "$HOME_DIR/.config/niri/dms"
        ;;
        hyprniri)
            check_config_exists "$HOME_DIR/.config/hypr"
        ;;
        shorinniri)
            local repo_path="$HOME_DIR/.local/share/shorin-niri"
            local expect_link="false"
            
            if [ -d "$repo_path" ]; then
                log "Detected shorin-niri repository. Enforcing strict SYMLINK checks..."
                expect_link="true"
            else
                log "Repository shorin-niri NOT found. Enforcing STANDALONE entity checks..."
            fi
            
            # 集中定义需要验证的目标路径数组
            local shorin_targets=(
                "$HOME_DIR/.config/matugen"
                "$HOME_DIR/.config/waybar"
                "$HOME_DIR/.config/kitty"
                "$HOME_DIR/.config/fish"
                "$HOME_DIR/.config/niri"
                "$HOME_DIR/.config/waypaper"
                "$HOME_DIR/Pictures/Wallpapers"
            )
            
            for target in "${shorin_targets[@]}"; do
                check_shorinniri_path "$target" "$expect_link"
            done
        ;;
        *)
            log "No specific config checks mapped for $DESKTOP_ENV. Skipping."
        ;;
    esac
    
    if [ "$CONFIG_ERRORS" -gt 0 ]; then
        echo ""
        error "DOTFILES DEPLOYMENT FAILED!"
        if declare -f write_log >/dev/null; then
            write_log "FATAL" "Dotfiles audit failed. $CONFIG_ERRORS paths missing or improperly configured."
        fi
        echo -e "   ${H_YELLOW}>>> Exiting installer. The repository clone or symlink step might have failed. ${NC}"
        exit 1
    else
        success "Configuration files and symlinks deployed correctly."
    fi
fi

# 全部通关！
exit 0