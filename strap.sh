#!/usr/bin/env bash

# ==============================================================================
# Bootstrap Script for Shorin Arch Setup
# ==============================================================================

# 启用严格模式：遇到错误、未定义变量或管道错误时立即退出
set -euo pipefail

# --- [颜色配置] ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- [环境检测] ---

# 2. 检查是否为 Linux 内核
if [ "$(uname -s)" != "Linux" ]; then
    printf "%bError: This installer only supports Linux systems.%b\n" "$RED" "$NC"
    exit 1
fi

# 3. 检查架构是否匹配
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)
        ARCH_NAME="amd64"
        ;;
    *)
        printf "%bError: Unsupported architecture: %s%b\n" "$RED" "$ARCH" "$NC"
        printf "This installer only supports x86_64 (amd64) and aarch64 (arm64).\n"
        exit 1
        ;;
esac

# --- [配置区域] ---
# 优先使用环境变量传入的分支名，如果没传，则默认使用 'main'
TARGET_BRANCH="${BRANCH:-main}"
REPO_URL="https://github.com/SHORiN-KiWATA/shorin-arch-setup.git"
DIR_NAME="shorin-arch-setup"

printf "%b>>> Preparing to install from branch: %s on %s%b\n" "$BLUE" "$TARGET_BRANCH" "$ARCH_NAME" "$NC"

# --- [执行流程] ---

# 1. 检查并安装 git (修改了检测逻辑以适配 set -e)
if ! command -v git >/dev/null 2>&1; then
    printf "Git not found. Installing...\n"
    sudo pacman -Syu --noconfirm git
fi

# 2. 清理旧目录
if [ -d "$DIR_NAME" ]; then
    printf "Removing existing directory '%s'...\n" "$DIR_NAME"
    rm -rf "$DIR_NAME"
fi

# 3. 克隆指定分支 (-b 参数)
printf "Cloning repository...\n"
if git clone --depth 1 -b "$TARGET_BRANCH" "$REPO_URL"; then
    printf "%bClone successful.%b\n" "$GREEN" "$NC"
else
    printf "%bError: Failed to clone branch '%s'. Check if it exists.%b\n" "$RED" "$TARGET_BRANCH" "$NC"
    exit 1
fi

# 4. 运行安装
if [ -d "$DIR_NAME" ]; then
    chmod -R 777 "$DIR_NAME"
    cd "$DIR_NAME"
    printf "Starting installer...\n"
    sudo bash install.sh
else
    printf "%bError: Directory '%s' not found after cloning.%b\n" "$RED" "$DIR_NAME" "$NC"
    exit 1
fi