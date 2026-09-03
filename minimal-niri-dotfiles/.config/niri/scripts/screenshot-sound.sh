#!/bin/bash
#
# 截图音效守护进程
#
# 工作原理：
#   截图快捷键先让 niri 截图，随后发来 SIGUSR1 → 本脚本"上膛"（touch 扳机文件）；
#   wl-paste --watch 在剪贴板出现图片时检查扳机是否已上膛且未过期，是则播放快门声。
#   "上膛"机制的意义：区分「截图产生的图片」和「你手动复制的图片」。
#
# ── 2026-09-03 修复的两个进程泄漏 ────────────────────────────────────────────
# 1) 主循环原为 `while true; do sleep infinity & wait $!; done`。
#    SIGUSR1 会打断 wait，bash 跑完 trap 后 wait 返回，但那个 sleep 子进程
#    没有任何人回收 —— 每按一次截图键泄漏一个。实测曾累积 2179 个残留进程。
#    现改为 wait 在 watcher 上：同样是 0 CPU 阻塞，但不产生一次性子进程。
#
# 2) niri 的 spawn-at-startup 走 double-fork + 独立 systemd scope（落在 app.slice，
#    与 session.slice/niri.service 是兄弟），niri 退出不会带走本脚本。
#    而 wl-paste 会随 compositor 断连而死 —— 旧版察觉不到，于是退化成"哑巴实例"：
#    发不出声，却仍响应广播的 SIGUSR1 继续泄漏，且每次 niri 重启再叠加一个。
#    现在 watcher 一死本脚本立即退出；另加 flock 单例锁作双保险。
# ─────────────────────────────────────────────────────────────────────────────

# =================配置区域=================
SOUND="/usr/share/sounds/freedesktop/stereo/camera-shutter.oga"
# 这是一个"扳机"文件，存于内存中 (/dev/shm)，读写极快
TRIGGER_FILE="/dev/shm/niri_screenshot_armed"
# 有效期：按下截图键后，多少秒内产生了图片才响？（防止你取消截图后，下次复制图片误响）
TIMEOUT_SEC=15
# 单例锁：防止 niri 重启时叠加出多个实例
LOCK_FILE="/dev/shm/niri_screenshot_sound.lock"
# =========================================

# =========================================
# 0. 环境检查
# =========================================
for _cmd in pw-play wl-paste flock; do
    if ! command -v "$_cmd" >/dev/null; then
        notify-send "截图音效" "错误: 未找到 $_cmd"
        exit 1
    fi
done

# =========================================
# 1. 单例锁（fd 9 在进程退出时自动释放）
# =========================================
exec 9>"$LOCK_FILE" || exit 1
if ! flock -n 9; then
    echo "已有实例在运行，本次退出。"
    exit 0
fi

# 清掉上次可能残留的过期扳机
rm -f "$TRIGGER_FILE"

# =========================================
# 2. 定义信号处理 (收到信号 = 上膛)
# =========================================
arm_trigger() {
    # 更新文件的修改时间，或者创建它
    touch "$TRIGGER_FILE"
}

# 注册信号：收到 USR1 就执行 arm_trigger
trap arm_trigger SIGUSR1

# =========================================
# 3. 启动剪贴板监听 (后台运行)
# =========================================
# 只有当剪贴板真正发生变化时，这个子进程才会醒来。
# 注意：脚本体用【单引号】，参数经环境变量传入。旧版用双引号，导致内层注释里的
#       $(date +%s) 在守护进程启动那一刻就被外层 shell 展开成了一个固定时间戳。
# shellcheck disable=SC2016  # 内层 $ 必须留到 watcher 运行时才展开，这里就是要单引号
TRIGGER_FILE="$TRIGGER_FILE" TIMEOUT_SEC="$TIMEOUT_SEC" SOUND="$SOUND" \
wl-paste --watch bash -c '
    # A. 检查是不是图片
    wl-paste --list-types 2>/dev/null | grep -q "image/" || exit 0

    # B. 检查有没有"上膛"（文件是否存在）
    [ -f "$TRIGGER_FILE" ] || exit 0

    # C. 检查"上膛"是否过期（利用文件修改时间）
    file_time=$(stat -c %Y "$TRIGGER_FILE" 2>/dev/null) || exit 0
    [ $(( $(date +%s) - file_time )) -lt "$TIMEOUT_SEC" ] || exit 0

    # 条件满足：是图片 + 已上膛 + 没过期
    rm -f "$TRIGGER_FILE"      # D. 先销毁扳机，防止连响
    pw-play "$SOUND" &
' &
# 获取 wl-paste 的 PID，以便脚本退出时杀掉它
WATCHER_PID=$!

# =========================================
# 4. 退出清理
# =========================================
trap 'kill "$WATCHER_PID" 2>/dev/null; rm -f "$TRIGGER_FILE"; exit' INT TERM EXIT

echo "截图音效服务已启动 (PID $$, watcher $WATCHER_PID)，等待 SIGUSR1 信号..."

# =========================================
# 5. 守护进程主循环 (0 CPU 占用、0 进程泄漏)
# =========================================
# wait 会被 SIGUSR1 打断（bash 先跑 trap，再让 wait 返回），循环于是重新判断：
#   · watcher 还活着 → 继续 wait，不产生任何新进程
#   · watcher 已死（compositor 退出导致 wl-paste 断连）→ 跳出，由 EXIT trap 收尾
while kill -0 "$WATCHER_PID" 2>/dev/null; do
    wait "$WATCHER_PID"
done
