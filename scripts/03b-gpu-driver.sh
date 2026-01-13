#!/bin/bash

# ==============================================================================
# 03b-gpu-driver.sh GPU Driver Installer 参考了cachyos的chwd脚本
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 引用工具库
if [ -f "$SCRIPT_DIR/00-utils.sh" ]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found."
    exit 1
fi

check_root

section "Phase 2b" "GPU Driver Setup"

# ==============================================================================
# 1. 变量声明与基础信息获取
# ==============================================================================
log "Detecting GPU Hardware..."

# 核心变量：存放 lspci 信息
GPU_INFO=$(lspci -mm | grep -E -i "VGA|3D|Display")
log "GPU Info Detected:\n$GPU_INFO"

# 状态变量初始化
HAS_AMD=false
HAS_INTEL=false
HAS_NVIDIA=false
GPU_NUMBER=0
# 待安装包数组
PKGS=("libva-utils")
# ==============================================================================
# 2. 状态变更 & 基础包追加 (Base Packages)
# ==============================================================================

# --- AMD 检测 --- -q 静默，-i忽略大小写
if echo "$GPU_INFO" | grep -q -i "AMD\|ATI"; then
    HAS_AMD=true
    info_kv "Vendor" "AMD Detected"
    # 追加 AMD 基础包
    PKGS+=("mesa" "lib32-mesa" "xf86-video-amdgpu" "vulkan-radeon" "lib32-vulkan-radeon" "linux-firmware-amdgpu" "gst-plugin-va" "opencl-mesa" "lib32-opencl-mesa" "opencl-icd-loader" "lib32-opencl-icd-loader" )
fi

# --- Intel 检测 ---
if echo "$GPU_INFO" | grep -q -i "Intel"; then
    HAS_INTEL=true
    info_kv "Vendor" "Intel Detected"
    # 追加 Intel 基础包 (保证能亮机，能跑基础桌面)
    PKGS+=("mesa" "vulkan-intel" "lib32-mesa" "lib32-vulkan-intel" "gst-plugin-va" "linux-firmware-intel" "opencl-mesa" "lib32-opencl-mesa" "opencl-icd-loader" "lib32-opencl-icd-loader" )
fi

# --- NVIDIA 检测 ---
if echo "$GPU_INFO" | grep -q -i "NVIDIA"; then
    HAS_NVIDIA=true
    info_kv "Vendor" "NVIDIA Detected"
    # 追加 NVIDIA 基础工具包
fi

# --- 多显卡检测 ---
GPU_COUNT=$(echo "$GPU_INFO" | grep -c .)

if [ "$GPU_COUNT" -ge 2 ]; then
    info_kv "GPU Layout" "Dual/Multi-GPU Detected (Count: $GPU_COUNT)"
    # 安装 vulkan-mesa-layers 以支持 vk-device-select
    PKGS+=("vulkan-mesa-layers" "lib32-vulkan-mesa-layers")

    if [[ $HAS_NVIDIA == true ]]; then 
    PKGS+=("nvidia-prime" "switcheroo-control")
    fi
fi
# ==============================================================================
# 3. Conditional 包判断 
# ==============================================================================

# ------------------------------------------------------------------------------
# 3.1 Intel 硬件编解码判断
# ------------------------------------------------------------------------------
if [ "$HAS_INTEL" = true ]; then
    if echo "$GPU_INFO" | grep -q -E -i "Arc|Xe|UHD|Iris|Raptor|Alder|Tiger|Rocket|Ice|Comet|Coffee|Kaby|Skylake|Broadwell|Gemini|Jasper|Elkhart|HD Graphics 6|HD Graphics 5[0-9][0-9]\b"; then
        log "   -> Intel: Modern architecture matched (iHD path)..."
        PKGS+=("intel-media-driver")
    else
        warn "   -> Intel: Legacy or Unknown model. Skipping intel-media-driver."
    fi
fi

# ------------------------------------------------------------------------------
# 3.2 NVIDIA 驱动版本与内核 Headers 判断
# ------------------------------------------------------------------------------
if [ "$HAS_NVIDIA" = true ]; then
    NV_MODEL=$(echo "$GPU_INFO" | grep -i "NVIDIA" | head -n 1)
    
    # 初始化一个标志位，只有匹配到支持的显卡才设为 true
    DRIVER_SELECTED=false

    # ==========================================================================
    #  nvidia-open 
    # ==========================================================================
    if echo "$NV_MODEL" | grep -q -E -i "RTX|GTX 16"; then
        log "   -> NVIDIA: Modern GPU detected (Turing+). Using Open Kernel Modules."
        
        # 核心驱动包
        PKGS+=("nvidia-open-dkms" "nvidia-utils" "lib32-nvidia-utils" "opencl-nvidia" "lib32-opencl-nvidia" "libva-nvidia-driver" "vulkan-icd-loader" "lib32-vulkan-icd-loader" "opencl-icd-loader" "lib32-opencl-icd-loader")
        DRIVER_SELECTED=true

    # ==========================================================================
    # nvidia-580xx-dkms
    # ==========================================================================
    elif echo "$NV_MODEL" | grep -q -E -i "GTX 10|GTX 950|GTX 960|GTX 970|GTX 980|GTX 745|GTX 750|GTX 750 Ti|GTX 840M|GTX 845M|GTX 850M|GTX 860M|GTX 950M|GTX 960M|GeForce 830M|GeForce 840M|GeForce 930M|GeForce 940M|GeForce GTX Titan X|Tegra X1|NVIDIA Titan X|NVIDIA Titan Xp|NVIDIA Titan V|NVIDIA Quadro GV100"; then
        log "   -> NVIDIA: Pascal/Maxwell GPU detected. Using Proprietary DKMS."
        PKGS+=("nvidia-580xx-dkms" "nvidia-580xx-utils" "opencl-nvidia-580xx" "lib32-opencl-nvidia-580xx" "lib32-nvidia-580xx-utils" "libva-nvidia-driver" "vulkan-icd-loader" "lib32-vulkan-icd-loader" "opencl-icd-loader" "lib32-opencl-icd-loader" )
        DRIVER_SELECTED=true

    # ==========================================================================
    # nvidia-470xx-dkms
    # ==========================================================================
    elif echo "$NV_MODEL" | grep -q -E -i "GTX 6[0-9][0-9]|GTX 760|GTX 765|GTX 770|GTX 775|GTX 780|GTX 860M|GT 6[0-9][0-9]|GT 710M|GT 720|GT 730M|GT 735M|GT 740|GT 745M|GT 750M|GT 755M|GT 920M|Quadro 410|Quadro K500|Quadro K510|Quadro K600|Quadro K610|Quadro K1000|Quadro K1100|Quadro K2000|Quadro K2100|Quadro K3000|Quadro K3100|Quadro K4000|Quadro K4100|Quadro K5000|Quadro K5100|Quadro K6000|Tesla K10|Tesla K20|Tesla K40|Tesla K80|NVS 510|NVS 1000|Tegra K1|Titan|Titan Z"; then

        log "   -> NVIDIA:  Kepler GPU detected. Using nvidia-470xx-dkms."
        PKGS+=("nvidia-470xx-dkms" "nvidia-470xx-utils" "opencl-nvidia-470xx" "vulkan-icd-loader" "lib32-nvidia-470xx-utils" "lib32-opencl-nvidia-470xx" "lib32-vulkan-icd-loader" "libva-nvidia-driver" "opencl-icd-loader" "lib32-opencl-icd-loader")
        DRIVER_SELECTED=true

    # ==========================================================================
    # others
    # ========================================================================== 
    else
        warn "   -> NVIDIA: Legacy GPU detected ($NV_MODEL)."
        warn "   -> Please manually install GPU driver."
    fi

    # ==========================================================================
    # headers
    # ==========================================================================
    if [ "$DRIVER_SELECTED" = true ]; then
        log "   -> NVIDIA: Scanning installed kernels for headers..."
        
        # 1. 获取所有以 linux 开头的候选包
        CANDIDATES=$(pacman -Qq | grep "^linux" | grep -vE "headers|firmware|api|docs|tools|utils|qq")

        for kernel in $CANDIDATES; do
            # 2. 验证：只有在 /boot 下存在对应 vmlinuz 文件的才算是真内核
            if [ -f "/boot/vmlinuz-${kernel}" ]; then
                HEADER_PKG="${kernel}-headers"
                log "      + Kernel found: $kernel -> Adding $HEADER_PKG"
                PKGS+=("$HEADER_PKG")
            fi
        done
    fi
fi

# ==============================================================================
# 4. 执行
# ==============================================================================



DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
TARGET_USER="${DETECTED_USER:-$(read -p "Target user: " u && echo $u)}"

#--------------sudo temp file--------------------#
SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" >"$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"
log "Temp sudo file created..."

# 定义清理函数：无论脚本是成功结束还是意外中断(Ctrl+C)，都确保删除免密文件
cleanup_sudo() {
    if [ -f "$SUDO_TEMP_FILE" ]; then
        rm -f "$SUDO_TEMP_FILE"
        log "Security: Temporary sudo privileges revoked."
    fi
}
# 注册陷阱：在脚本退出(EXIT)或被中断(INT/TERM)时触发清理
trap cleanup_sudo EXIT INT TERM

if [ ${#PKGS[@]} -gt 0 ]; then
    # 数组去重
    UNIQUE_PKGS=($(printf "%s\n" "${PKGS[@]}" | sort -u))
    
    section "Installation" "Installing Packages"
    log "Target Packages: ${UNIQUE_PKGS[*]}"
    
    # 执行安装
    exe runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed --answerdiff=None --answerclean=None "${UNIQUE_PKGS[@]}"
    
    log "Enabling services (if supported)..."
    systemctl enable --now nvidia-powerd &>/dev/null || true
    systemctl enable switcheroo-control.service &>/dev/null || true
    success "GPU Drivers processed successfully."
else
    warn "No GPU drivers matched or needed."
fi

log "Module 02b completed."