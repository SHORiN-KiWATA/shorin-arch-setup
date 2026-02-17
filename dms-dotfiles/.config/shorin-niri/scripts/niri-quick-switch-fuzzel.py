#!/usr/bin/env python3

import subprocess
import json
import sys
import shutil
import time  # <--- 新增：用于等待窗口关闭生效

# ================= Configuration =================
EXCLUDE_APPS = ["fuzzel", "quick-switch", "niri-quick-switch"]
FUZZEL_ARGS = [
    "--dmenu",
    "--index",              
    "--width", "60",        
    "--lines", "15",        
    "--prompt", "Switch: ", 
    # 修改了这里：提示 Ctrl+L 跳转，Ctrl+H 关闭
    "--placeholder", "Search... [Ctrl+J/K: Select | Ctrl+L: Switch | Ctrl+H: Close]"
]
# =================================================

def run_cmd(cmd):
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if result.returncode != 0: return None
        if "-j" in cmd:
            return json.loads(result.stdout)
        return result.stdout
    except Exception: return None

def get_active_workspace_id():
    workspaces = run_cmd("niri msg -j workspaces")
    if not workspaces: return None
    for ws in workspaces:
        if ws.get("is_focused"): return ws.get("id")
    return None

def get_window_sort_key(w):
    if w.get("is_floating"):
        return (99999, 0, w.get("id"))
    try:
        layout = w.get("layout", {})
        if not layout: return (9999, 0, w.get("id"))
        pos = layout.get("pos_in_scrolling_layout")
        if pos and isinstance(pos, list) and len(pos) >= 2:
            return (pos[0], pos[1], w.get("id"))
    except Exception:
        pass
    return (9999, 0, w.get("id"))

def main():
    if not shutil.which("fuzzel"):
        print("Error: Fuzzel not found")
        sys.exit(1)

    # === 核心改动：开启死循环 ===
    while True:
        # 1. 每次循环都重新获取最新的 Workspace ID (防止工作区变动)
        ws_id = get_active_workspace_id()
        if ws_id is None: break

        # 2. 每次循环都重新获取最新的窗口列表 (因为刚才可能关掉了一个)
        windows = run_cmd("niri msg -j windows")
        if not windows: break

        current_windows = []
        for w in windows:
            if w.get("workspace_id") != ws_id: continue
            app_id = w.get("app_id") or ""
            if app_id in EXCLUDE_APPS: continue
            current_windows.append(w)

        # 如果没有窗口了，直接退出
        if not current_windows: break

        current_windows.sort(key=get_window_sort_key)

        input_str = ""
        for w in current_windows:
            app_id = w.get("app_id") or "Wayland"
            title = w.get("title", "No Title").replace("\n", " ")
            display_str = f"[{app_id}] {title}"
            line = f"{display_str}\0icon\x1f{app_id}"
            input_str += f"{line}\n"

        try:
            # 3. 启动 Fuzzel
            proc = subprocess.Popen(
                ["fuzzel"] + FUZZEL_ARGS,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                text=True
            )
            stdout, _ = proc.communicate(input=input_str)
            
            return_code = proc.returncode
            raw_output = stdout.strip()

            # 情况 A: 用户按 ESC 取消 -> 退出循环
            if return_code not in [0, 10] or not raw_output:
                break

            try:
                selected_idx = int(raw_output)
            except ValueError:
                break

            if 0 <= selected_idx < len(current_windows):
                target_window = current_windows[selected_idx]
                target_id = target_window.get("id")
                
                if return_code == 0:
                    # 动作: 切换窗口 -> 任务完成，退出循环
                    subprocess.run(["niri", "msg", "action", "focus-window", "--id", str(target_id)])
                    break 
                
                elif return_code == 10:
                    # 动作: 关闭窗口 -> 执行关闭，然后 CONTINUE (继续循环)
                    subprocess.run(["niri", "msg", "action", "close-window", "--id", str(target_id)])
                    
                    # 关键：稍微等一下，让 niri 有时间处理关闭动作，
                    # 否则立刻刷新列表可能还会看到那个已经被杀死的窗口
                    time.sleep(0.1)
                    continue 

        except Exception as e:
            print(f"Error: {e}")
            break

if __name__ == "__main__":
    main()
