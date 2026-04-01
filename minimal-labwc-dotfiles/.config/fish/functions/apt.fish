# ==============================================================================
# Function: apt (Smart Arch Package Manager Wrapper for Fish)
# Description: Maps common Debian 'apt' commands to an intelligent Arch backend.
# Features:
#   - Fallback routing: paru > yay > pacman.
#   - Automatic Sudo Handling: Prevents AUR helpers from running as root.
#   - Anti-Partial-Upgrade: Merges update/upgrade into a safe -Syu operation.
#   - Deep Clean Default: Merges remove/purge into -Rns for a pristine system.
#   - UI Integration: Progressive enhancement with 'shorin' for interactive modes.
#   - Safe orphan detection and i18n support.
#   - Highly readable, colorized, and column-aligned help output.
# Usage: apt {update|upgrade|install [ui]|remove [ui]|search|show|autoremove|clean|help|-h} [pkg...]
# ==============================================================================

function apt -d "Smart wrapper routing apt commands to paru/yay/pacman"
    # 1. 极简的 Locale 探测
    set -l is_zh 0
    if string match -q -r "^zh_" "$LC_ALL" "$LC_MESSAGES" "$LANG"
        set is_zh 1
    end

    # 2. 探测 shorin UI 工具是否存在
    set -l has_shorin 0
    if command -q shorin
        set has_shorin 1
    end

    set -l action "help"
    set -l exit_code 0

    if test (count $argv) -eq 0
        set exit_code 1
    else
        set action $argv[1]
        set -e argv[1]
    end

    # 3. 帮助信息拦截与本地化 (重构的高颜值排版)
    switch $action
        case help -h --help
            set -l c_cmd (set_color cyan)
            set -l c_hl  (set_color yellow)
            set -l c_rst (set_color normal)

            if test $is_zh -eq 1
                echo "Arch 包管理器包装器 (优先级: "$c_hl"paru > yay > pacman"$c_rst")"
                echo "用法: "$c_hl"apt"$c_rst" <命令> [软件包...]"
                echo ""
                echo "命令:"
                echo "  "$c_cmd"update(upgrade)"$c_rst"  同步数据库并更新系统 (-Syu)"
                echo "  "$c_cmd"install        "$c_rst"  安装软件包 (-S)"
                if test $has_shorin -eq 1
                    echo "  "$c_cmd"install ui     "$c_rst"  打开交互式界面安装 (依赖: shorin-contrib-git)"
                end
                echo "  "$c_cmd"remove         "$c_rst"  彻底卸载软件包、依赖及配置文件 (-Rns)"
                if test $has_shorin -eq 1
                    echo "  "$c_cmd"remove ui      "$c_rst"  打开交互式界面卸载 (依赖: shorin-contrib-git)"
                end
                echo "  "$c_cmd"search         "$c_rst"  搜索软件包 (-Ss)"
                echo "  "$c_cmd"show           "$c_rst"  显示软件包详细信息 (-Si)"
                echo "  "$c_cmd"autoremove     "$c_rst"  安全地清理系统中的孤立软件包"
                echo "  "$c_cmd"clean          "$c_rst"  清理下载缓存 (-Sc)"
                echo "  "$c_cmd"help, -h       "$c_rst"  显示此帮助信息"
            else
                echo "Smart Arch Package Wrapper (Routing: "$c_hl"paru > yay > pacman"$c_rst")"
                echo "Usage: "$c_hl"apt"$c_rst" <command> [package...]"
                echo ""
                echo "Commands:"
                echo "  "$c_cmd"update(upgrade)"$c_rst"  Sync databases and update system (Safe -Syu)"
                echo "  "$c_cmd"install        "$c_rst"  Install packages (-S)"
                if test $has_shorin -eq 1
                    echo "  "$c_cmd"install ui     "$c_rst"  Open interactive installation UI (shorin pac)"
                end
                echo "  "$c_cmd"remove         "$c_rst"  Remove packages, unneeded dependencies, and configs (-Rns)"
                if test $has_shorin -eq 1
                    echo "  "$c_cmd"remove ui      "$c_rst"  Open interactive removal UI (shorin pacr)"
                end
                echo "  "$c_cmd"search         "$c_rst"  Search for packages (-Ss)"
                echo "  "$c_cmd"show           "$c_rst"  Show package details (-Si)"
                echo "  "$c_cmd"autoremove     "$c_rst"  Remove orphaned packages safely"
                echo "  "$c_cmd"clean          "$c_rst"  Clean package cache (-Sc)"
                echo "  "$c_cmd"help, -h       "$c_rst"  Show this help message"
            end
            return $exit_code
    end

    # 4. 核心路由与提权逻辑
    set -l pkg_mgr
    set -l needs_sudo "no"

    if command -q paru
        set pkg_mgr "paru"
    else if command -q yay
        set pkg_mgr "yay"
    else
        set pkg_mgr "pacman"
        set needs_sudo "yes"
    end

    set -l cmd
    if test "$needs_sudo" = "yes"
        set cmd sudo $pkg_mgr
    else
        set cmd $pkg_mgr
    end

    # 5. 预定义基础错误信息 (本地化)
    set -l msg_err_pkg "Error: Specify packages."
    set -l msg_err_search "Error: Specify search term."
    set -l msg_err_show "Error: Specify package to show."
    if test $is_zh -eq 1
        set msg_err_pkg "错误：请指定要操作的软件包。"
        set msg_err_search "错误：请指定搜索词。"
        set msg_err_show "错误：请指定要查看的软件包。"
    end

    # 6. 动作映射 (Action Mapping)
    switch $action
        case update upgrade
            $cmd -Syu
        case install
            if test (count $argv) -eq 0; echo $msg_err_pkg; return 1; end
            # 拦截 'install ui'，条件：且只输入了 ui 一个参数，且系统存在 shorin
            if test "$argv[1]" = "ui" -a (count $argv) -eq 1 -a $has_shorin -eq 1
                shorin pac
                return 0
            end
            $cmd -S $argv
        case remove
            if test (count $argv) -eq 0; echo $msg_err_pkg; return 1; end
            # 拦截 'remove ui'
            if test "$argv[1]" = "ui" -a (count $argv) -eq 1 -a $has_shorin -eq 1
                shorin pacr
                return 0
            end
            $cmd -Rns $argv
        case search
            if test (count $argv) -eq 0; echo $msg_err_search; return 1; end
            $pkg_mgr -Ss $argv
        case show
            if test (count $argv) -eq 0; echo $msg_err_show; return 1; end
            $pkg_mgr -Si $argv
        case autoremove
            set -l orphans (pacman -Qtdq)
            if test (count $orphans) -gt 0
                if test $is_zh -eq 1
                    echo "找到 "(count $orphans)" 个孤立的软件包。正在通过 $pkg_mgr 卸载..."
                else
                    echo "Found "(count $orphans)" orphaned package(s). Removing via $pkg_mgr..."
                end
                $cmd -Rns $orphans
            else
                if test $is_zh -eq 1
                    echo "系统很干净，没有需要清理的孤立软件包。"
                else
                    echo "System is clean. No orphaned packages to remove."
                end
            end
        case clean
            $cmd -Sc
        case '*'
            if test $is_zh -eq 1
                echo "错误：不支持的 apt 命令映射: $action"
                echo "运行 'apt -h' 查看可用命令。"
            else
                echo "Error: Unsupported apt command mapped: $action"
                echo "Run 'apt -h' for valid commands."
            end
            return 1
    end
end
