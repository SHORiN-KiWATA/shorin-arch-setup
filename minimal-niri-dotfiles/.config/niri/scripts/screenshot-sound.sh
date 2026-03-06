#!/bin/bash

# =================配置区域=================
SOUND="/usr/share/sounds/freedesktop/stereo/camera-shutter.oga"
# 这是一个“扳机”文件，存于内存中 (/dev/shm)，读写极快
TRIGGER_FILE="/dev/shm/niri_screenshot_armed"
# 有效期：按下截图键后，多少秒内产生了图片才响？(防止你取消截图后，下次复制图片误响)
TIMEOUT_SEC=15
# =========================================

# 环境检查
if ! command -v pw-play >/dev/null; then
    notify-send "错误: 未找到 pw-play"
    exit 1
fi

# =========================================
# 1. 定义信号处理 (收到信号 = 上膛)
# =========================================
arm_trigger() {
    # 更新文件的修改时间，或者创建它
    touch "$TRIGGER_FILE"
}

# 注册信号：收到 USR1 就执行 arm_trigger
trap arm_trigger SIGUSR1

# =========================================
# 2. 启动剪贴板监听 (后台运行)
# =========================================
# 只有当剪贴板真正发生变化时，这个子进程才会醒来
wl-paste --watch bash -c "
    # A. 检查是不是图片
    if wl-paste --list-types 2>/dev/null | grep -q 'image/'; then
        
        # B. 检查有没有“上膛” (文件是否存在)
        if [ -f \"$TRIGGER_FILE\" ]; then
            
            # C. 检查“上膛”是否过期 (利用文件修改时间)
            # $(date +%s) - stat获取的时间
            NOW=\$(date +%s)
            FILE_TIME=\$(stat -c %Y \"$TRIGGER_FILE\")
            DIFF=\$((NOW - FILE_TIME))

            if [ \$DIFF -lt $TIMEOUT_SEC ]; then
                #  조건을 满足：是图片 + 已上膛 + 没过期
                pw-play \"$SOUND\" &
                
                # D. 销毁扳机 (防止连响)
                rm -f \"$TRIGGER_FILE\"
            fi
        fi
    fi
" &
# 获取 wl-paste 的 PID，以便脚本退出时杀掉它
WATCHER_PID=$!

# =========================================
# 3. 守护进程主循环 (0 CPU 占用)
# =========================================
# 这里的 trap 负责在脚本退出时清理子进程
trap "kill $WATCHER_PID; exit" INT TERM EXIT

# 写入当前 PID 方便调试 (可选)
# echo $$ > /tmp/niri-sound.pid

echo "截图音效服务已启动，等待 SIGUSR1 信号..."

# 无限睡眠，只响应信号
while true; do
    sleep infinity & wait $!
done
