#!/usr/bin/env bash

# ==============================================================================
# 脚本功能说明 (Bootstrap Script for Shorin Arch Setup - Ninja PV Edition)
# 1. 环境防御：严格检测操作系统(仅限Linux)与系统架构(仅限x86_64)。
# 2. 权限自适应：智能识别 root/普通用户，防止 Live CD 环境下缺少 sudo 导致崩溃。
# 3. 依赖隐身：静默准备 curl/tar/git/pv。其中 pv 仅作临时数据流监控。
# 4. 流式处理：通过 curl 拉取源码，pv 提供带有预估总量的真实进度条与网速监控。
# 5. 用完即焚：解压完成后，静默卸载临时依赖 pv (若它是被本脚本安装的)，保持系统洁净。
# 6. 一键引导：无缝切换目录并接管标准输入，提权执行核心安装脚本。
# ==============================================================================

# 启用严格模式：遇到错误、未定义变量或管道错误时立即退出
set -euo pipefail

# --- [颜色配置] ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- [环境检测与准备] ---

# 1. 检查是否为 Linux 内核
if [ "$(uname -s)" != "Linux" ]; then
    printf "%bError: This installer only supports Linux systems.%b\n" "$RED" "$NC"
    exit 1
fi

# 2. 检查架构是否匹配 (仅允许 x86_64)
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    printf "%bError: Unsupported architecture: %s%b\n" "$RED" "$ARCH" "$NC"
    printf "This installer is strictly designed for x86_64 (amd64) systems only.\n"
    exit 1
fi
ARCH_NAME="amd64"

# 3. 极简提权封装 (KISS 原则：是 root 直接跑，不是 root 才加 sudo)
run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        if ! command -v sudo >/dev/null 2>&1; then
            printf "%bError: 'sudo' command not found. Please run this script as root.%b\n" "$RED" "$NC"
            exit 1
        fi
        sudo "$@"
    fi
}

# --- [配置区域] ---
TARGET_BRANCH="${BRANCH:-main}"
TARBALL_URL="https://github.com/SHORiN-KiWATA/shorin-arch-setup/archive/refs/heads/${TARGET_BRANCH}.tar.gz"
TARGET_DIR="/tmp/shorin-arch-setup"

# 【极客魔法】预估源码压缩包体积。实际测得约为 60MB，这里预留一点余量设定为 65M，确保进度条平滑且不卡顿。
EXPECTED_SIZE="75M"

printf "%b>>> Preparing to install from branch: %s on %s%b\n" "$BLUE" "$TARGET_BRANCH" "$ARCH_NAME" "$NC"

# --- [执行流程] ---

# 1. 依赖检查与静默安装
MISSING_PKGS=()
INSTALLED_PV_FLAG=0

for cmd in curl tar git pv; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING_PKGS+=("$cmd")
        if [ "$cmd" = "pv" ]; then
            INSTALLED_PV_FLAG=1
        fi
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    run_as_root pacman -Sy --noconfirm --needed "${MISSING_PKGS[@]}" >/dev/null 2>&1
fi

# 2. 清理旧目录并重新创建
if [ -d "$TARGET_DIR" ]; then
    run_as_root rm -rf "$TARGET_DIR"
fi
mkdir -p "$TARGET_DIR"

# 3. 流式下载与解压 (引入基于预估体积的真实进度条)
printf "Downloading and extracting repository to %s...\n" "$TARGET_DIR"

for attempt in 1 2 3; do
    # 核心变动：加入了 -s "$EXPECTED_SIZE" 让 pv 以为自己知道了终点。
    # -ptrb: p=真实的进度条, t=时间, r=网速, b=字节
    if curl -sSLf "$TARBALL_URL" | pv -ptrb -s "$EXPECTED_SIZE" | tar -xz -C "$TARGET_DIR" --strip-components=1; then
        run_as_root chmod 755 "$TARGET_DIR"
        printf "%b\nDownload and extraction successful.%b\n" "$GREEN" "$NC"
        break
    fi
    
    if [ "$attempt" -eq 3 ]; then
        printf "%bError: Failed to download branch '%s' after 3 attempts. Network issue suspected.%b\n" "$RED" "$TARGET_BRANCH" "$NC"
        exit 1
    fi
    
    printf "%bWarning: Download failed (attempt %d/3). Retrying in 3 seconds...%b\n" "$RED" "$attempt" "$NC"
    sleep 3
    run_as_root rm -rf "$TARGET_DIR"
    mkdir -p "$TARGET_DIR"
done

# 4. 毁尸灭迹：如果 pv 是我们刚装的，悄悄卸载掉
if [ "$INSTALLED_PV_FLAG" -eq 1 ]; then
    run_as_root pacman -Rns --noconfirm pv >/dev/null 2>&1
fi

# 5. 运行安装
cd "$TARGET_DIR"
printf "Starting installer...\n"
run_as_root bash install.sh < /dev/tty
