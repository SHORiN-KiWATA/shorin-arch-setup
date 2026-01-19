#!/bin/bash

# ==============================================================================
# Bootstrap Script for Shorin Arch Setup
# ==============================================================================

# --- [配置区域] ---
# 优先使用环境变量传入的分支名，如果没传，则默认使用 'main'
TARGET_BRANCH="${BRANCH:-main}"
REPO_URL="https://github.com/SHORiN-KiWATA/shorin-arch-setup.git"
DIR_NAME="shorin-arch-setup"

echo -e "\033[0;34m>>> Preparing to install from branch: $TARGET_BRANCH\033[0m"

# 1. 检查并安装 git
if ! command -v git &> /dev/null; then
    echo "Git not found. Installing..."
    sudo pacman -Syu --noconfirm git
fi

# 2. 清理旧目录
if [ -d "$DIR_NAME" ]; then
    echo "Removing existing directory..."
    rm -rf "$DIR_NAME"
fi

# 3. 克隆指定分支 (-b 参数)
echo "Cloning repository..."
if git clone --depth 1 -b "$TARGET_BRANCH" "$REPO_URL"; then
    echo "Clone successful."
else
    echo -e "\033[0;31mError: Failed to clone branch '$TARGET_BRANCH'. Check if it exists.\033[0m"
    exit 1
fi

# 4. 运行安装
if [ -d "$DIR_NAME" ]; then
    cd "$DIR_NAME"
    echo "Starting installer..."
    sudo bash install.sh
else
    echo "Error: Directory not found."
    exit 1
fi
