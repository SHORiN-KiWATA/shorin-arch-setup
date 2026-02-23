#!/usr/bin/env bash
set -Eeuo pipefail

# ================== Runtime state & Persistent Config ==================
APP="wf-recorder"

# --- 运行时状态 (应在每次会话结束时消失, 遵循 XDG_RUNTIME_DIR) ---
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"
STATE_DIR="$RUNTIME_DIR/wfrec"

PIDFILE="$STATE_DIR/pid"
STARTFILE="$STATE_DIR/start"
SAVEPATH_FILE="$STATE_DIR/save_path"
MODEFILE="$STATE_DIR/mode"             # full/region -> tooltip
GIF_MARKER="$STATE_DIR/is_gif"         # [NEW] 标记当前录制是否为 GIF 模式
TICKPIDFILE="$STATE_DIR/tickpid"
WAYBAR_PIDS_CACHE="$STATE_DIR/waybar.pids"


# --- 持久性配置 (缓存/设置, 存放在 .cache/ 下, 遵循 XDG_CACHE_HOME) ---
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
CONFIG_DIR="$XDG_CACHE_HOME/wf-recorder-sh" # 目标目录 .cache/wf-recorder-sh

CFG_CODEC="$CONFIG_DIR/codec"
CFG_FPS="$CONFIG_DIR/framerate"
CFG_AUDIO="$CONFIG_DIR/audio"
CFG_DRM="$CONFIG_DIR/drm_device"
CFG_EXT="$CONFIG_DIR/container_ext"      # persisted file format (auto/mp4/mkv/webm)

# 创建所需的目录
mkdir -p "$STATE_DIR"
mkdir -p "$CONFIG_DIR"

# Hold chosen mode
MODE_DECIDED=""
IS_GIF_MODE="false" # [NEW] 临时变量

# ================== Tunables (ENV overridable) ==================
# defaults — 默认使用 CPU 编码 (libx264)
_DEFAULT_CODEC="libx264"
_DEFAULT_FRAMERATE=""
_DEFAULT_AUDIO="on"
_DEFAULT_SAVE_EXT="auto"             # auto/mp4/mkv/webm

# --- [NEW] GIF 配置区域 ---
GIF_WIDTH=720
GIF_FPS=30
GIF_DITHER_MODE="bayer:bayer_scale=5"
GIF_STATS_MODE="diff"
# -------------------------

# load persisted settings if exist
codec_from_file=$(cat "$CFG_CODEC" 2>/dev/null || true)
fps_from_file=$(cat "$CFG_FPS" 2>/dev/null || true)
audio_from_file=$(cat "$CFG_AUDIO" 2>/dev/null || true)
drm_from_file=$(cat "$CFG_DRM" 2>/dev/null || true)
ext_from_file=$(cat "$CFG_EXT" 2>/dev/null || true)

# priority: ENV > persisted > default
CODEC="${CODEC:-${codec_from_file:-$_DEFAULT_CODEC}}"
FRAMERATE="${FRAMERATE:-${fps_from_file:-$_DEFAULT_FRAMERATE}}"
AUDIO="${AUDIO:-${audio_from_file:-$_DEFAULT_AUDIO}}"
DRM_DEVICE="${DRM_DEVICE:-${drm_from_file:-}}"
SAVE_EXT="${SAVE_EXT:-${ext_from_file:-$_DEFAULT_SAVE_EXT}}"

TITLE="${TITLE:-}"
SAVE_DIR_ENV="${SAVE_DIR:-}"
SAVE_SUBDIR_FS="${SAVE_SUBDIR_FS:-fullscreen}"

OUTPUT="${OUTPUT:-}"                     # e.g. eDP-1 / DP-2
OUTPUT_SELECT="${OUTPUT_SELECT:-auto}"   # off|auto|menu
MENU_TITLE_OUTPUT="${MENU_TITLE_OUTPUT:-}"
MENU_BACKEND="${MENU_BACKEND:-auto}"     # auto|fuzzel|wofi|rofi|bemenu|fzf|term

RECORD_MODE="${RECORD_MODE:-ask}"        # ask|full|region
MODE_MENU_TITLE="${MODE_MENU_TITLE:-Select recording mode}"
REC_AREA="${REC_AREA:-}"                 # "x,y WIDTHxHEIGHT" (optional)
GEOM_IN_NAME="${GEOM_IN_NAME:-off}"

WAYBAR_POKE="${WAYBAR_POKE:-on}"
WAYBAR_SIG="${WAYBAR_SIG:-9}"
ICON_REC="${ICON_REC:-⏺}"
ICON_IDLE="${ICON_IDLE:-}"

PKILL_AFTER_STOP="${PKILL_AFTER_STOP:-on}"

# DEBUG: 若设为 on，则在前台运行 wf-recorder，并把输出直接显示到终端（仅终端，不写文件）
DEBUG="${DEBUG:-off}"

# ================== Utils ==================
has() { command -v "$1" >/dev/null 2>&1; }

lang_code() {
  local l="${LC_MESSAGES:-${LANG:-en}}"
  l="${l,,}"; l="${l%%.*}"; l="${l%%-*}"; l="${l%%_*}"
  case "$l" in zh|zh-cn|zh-tw|zh-hk) echo zh ;; ja|jp) echo ja ;; *) echo en ;; esac
}

msg() {
  local id="$1"; shift
  case "$(lang_code)" in
    zh)
      case "$id" in
        err_wf_not_found) printf "未找到 wf-recorder" ;;
        err_need_slurp)   printf "需要 slurp 以进行区域选择" ;;
        err_need_ffmpeg)  printf "GIF 转换需要 ffmpeg，但未找到。" ;;
        warn_drm_ignored) printf "警告：DRM_DEVICE=%s 不存在或不可读，将忽略。" "$@" ;;
        warn_invalid_fps) printf "警告：FRAMERATE=\"%s\" 非法，已忽略。" "$@" ;;
        warn_render_unreadable) printf "警告：无效的 render 节点：%s" "$@" ;;
        cancel_no_mode)   printf "已取消：未选择录制模式。" ;;
        cancel_no_output) printf "已取消：未选择输出。" ;;
        cancel_no_region) printf "已取消：未选择区域。" ;;
        warn_multi_outputs_cancel) printf "检测到多个输出但未选择，已取消。" ;;
        notif_started_full)   printf "开始录制（全屏：%s）→ %s" "$@" ;;
        notif_started_region) printf "开始录制（区域）→ %s" "$@" ;;
        notif_device_suffix)  printf "（设备 %s）" "$@" ;;
        notif_saved)    printf "已保存：%s" "$@" ;;
        notif_stopped)  printf "已停止录制。" ;;
        notif_processing_gif) printf "正在转换为 GIF，请稍候..." ;;
        notif_gif_failed)     printf "GIF 转换失败，保留原视频。" ;;
        notif_copied)         printf "文件已复制" ;;
        already_running) printf "already running" ;;
        not_running)      printf "not running" ;;
        title_mode)       printf "选择录制模式" ;;
        title_output)     printf "选择输出" ;;
        menu_fullscreen) printf "全屏" ;;
        menu_region)     printf "选择区域" ;;
        menu_gif_region) printf "录制 GIF (区域)" ;;
        # settings labels -> "标签：值"
        title_settings)  printf "设置..." ;;
        menu_settings)   printf "设置..." ;;
        menu_set_codec)  printf "编码格式：%s" "$@" ;;
        menu_set_fps)    printf "帧率：%s" "$@" ;;
        menu_set_filefmt) printf "文件格式：%s" "$@" ;;
        menu_toggle_audio) printf "音频：%s" "$@" ;;
        menu_set_render) printf "渲染设备：%s" "$@" ;;
        menu_back)        printf "返回" ;;
        fps_unlimited)    printf "不限制" ;;
        render_auto)      printf "自动" ;;
        ext_auto)         printf "自动" ;;
        title_select_codec) printf "选择编码格式" ;;
        title_select_fps)     printf "选择帧率" ;;
        title_select_filefmt) printf "选择文件格式" ;;
        title_select_render) printf "选择渲染设备（/dev/dri/renderD*）" ;;
        mode_full)        printf "全屏" ;;
        mode_region)      printf "区域" ;;
        prompt_enter_number) printf "输入编号：" ;;
        menu_exit)        printf "退出" ;;
        *) printf "%s" "$id" ;;
      esac
      ;;
    ja)
      case "$id" in
        err_wf_not_found) printf "wf-recorder が見つかりません" ;;
        err_need_slurp)   printf "領域選択には slurp が必要です" ;;
        err_need_ffmpeg)  printf "GIF変換には ffmpeg が必要ですが、見つかりません。" ;;
        warn_drm_ignored) printf "警告：DRM_DEVICE=%s は無視されます。" "$@" ;;
        warn_invalid_fps) printf "警告：FRAMERATE=\"%s\" は不正です。" "$@" ;;
        warn_render_unreadable) printf "警告：無効なレンダー ノード：%s" "$@" ;;
        cancel_no_mode)   printf "キャンセル：録画モード未選択。" ;;
        cancel_no_output) printf "キャンセル：出力未選択。" ;;
        cancel_no_region) printf "キャンセル：領域未選択。" ;;
        warn_multi_outputs_cancel) printf "出力が複数ですが未選択のため中止。" ;;
        notif_started_full)   printf "録画開始（全画面：%s）→ %s" "$@" ;;
        notif_started_region) printf "録画開始（領域）→ %s" "$@" ;;
        notif_device_suffix)  printf "（デバイス %s）" "$@" ;;
        notif_saved)    printf "保存しました：%s" "$@" ;;
        notif_stopped)  printf "録画を停止しました。" ;;
        notif_processing_gif) printf "GIF に変換中、お待ちください..." ;;
        notif_gif_failed)     printf "GIF 変換に失敗しました。元の動画を保持します。" ;;
        notif_copied)         printf "ファイルをコピーしました" ;;
        already_running) printf "already running" ;;
        not_running)      printf "not running" ;;
        title_mode)       printf "録画モードを選択" ;;
        title_output)     printf "出力を選択" ;;
        menu_fullscreen) printf "全画面" ;;
        menu_region)     printf "領域選択" ;;
        menu_gif_region) printf "GIF録画 (領域)" ;;
        # settings labels -> "ラベル：値"（全角コロン）
        title_settings)  printf "設定..." ;;
        menu_settings)   printf "設定..." ;;
        menu_set_codec)  printf "コーデック：%s" "$@" ;;
        menu_set_fps)    printf "フレームレート：%s" "$@" ;;
        menu_set_filefmt) printf "ファイル形式：%s" "$@" ;;
        menu_toggle_audio) printf "音声：%s" "$@" ;;
        menu_set_render) printf "レンダーデバイス：%s" "$@" ;;
        menu_back)        printf "戻る" ;;
        fps_unlimited)    printf "無制限" ;;
        render_auto)      printf "自動" ;;
        ext_auto)         printf "自動" ;;
        title_select_codec) printf "コーデックを選択" ;;
        title_select_fps)     printf "フレームレートを選択" ;;
        title_select_filefmt) printf "ファイル形式を選択" ;;
        title_select_render) printf "レンダーデバイスを選択（/dev/dri/renderD*）" ;;
        mode_full)        printf "全画面" ;;
        mode_region)      printf "領域" ;;
        prompt_enter_number) printf "番号を入力：" ;;
        menu_exit)        printf "終了" ;;
        *) printf "%s" "$id" ;;
      esac
      ;;
    *)
      case "$id" in
        err_wf_not_found) printf "wf-recorder not found" ;;
        err_need_slurp)   printf "slurp required for region selection" ;;
        err_need_ffmpeg)  printf "ffmpeg is required for GIF conversion but not found." ;;
        warn_drm_ignored) printf "Warning: DRM_DEVICE=%s ignored." "$@" ;;
        warn_invalid_fps) printf "Warning: invalid FRAMERATE=\"%s\"." "$@" ;;
        warn_render_unreadable) printf "Warning: invalid render node: %s" "$@" ;;
        cancel_no_mode)   printf "Canceled: no recording mode selected." ;;
        cancel_no_output) printf "Canceled: no output selected." ;;
        cancel_no_region) printf "Canceled: no region selected." ;;
        warn_multi_outputs_cancel) printf "Multiple outputs but none selected; canceled." ;;
        notif_started_full)   printf "Recording started (fullscreen: %s) → %s" "$@" ;;
        notif_started_region) printf "Recording started (region) → %s" "$@" ;;
        notif_device_suffix)  printf " (device %s)" "$@" ;;
        notif_saved)    printf "Saved: %s" "$@" ;;
        notif_stopped)  printf "Recording stopped." ;;
        notif_processing_gif) printf "Converting to GIF, please wait..." ;;
        notif_gif_failed)     printf "GIF conversion failed. Original video kept." ;;
        notif_copied)         printf "File copied" ;;
        already_running) printf "already running" ;;
        not_running)      printf "not running" ;;
        title_mode)       printf "Select recording mode" ;;
        title_output)     printf "Select output" ;;
        menu_fullscreen) printf "Fullscreen" ;;
        menu_region)     printf "Region" ;;
        menu_gif_region) printf "Record GIF (Region)" ;;
        # settings labels -> "Label: Value"
        title_settings)  printf "Settings..." ;;
        menu_settings)   printf "Settings..." ;;
        menu_set_codec)  printf "Codec: %s" "$@" ;;
        menu_set_fps)    printf "Framerate: %s" "$@" ;;
        menu_set_filefmt) printf "File Format: %s" "$@" ;;
        menu_toggle_audio) printf "Audio: %s" "$@" ;;
        menu_set_render) printf "Render Device: %s" "$@" ;;
        menu_back)        printf "Back" ;;
        fps_unlimited)    printf "unlimited" ;;
        render_auto)      printf "Auto" ;;
        ext_auto)         printf "Auto" ;;
        title_select_codec) printf "Select Codec" ;;
        title_select_fps)     printf "Select Framerate" ;;
        title_select_filefmt) printf "Select File Format" ;;
        title_select_render) printf "Select Render Device (/dev/dri/renderD*)" ;;
        mode_full)        printf "Fullscreen" ;;
        mode_region)      printf "Region" ;;
        prompt_enter_number) printf "Enter number: " ;;
        menu_exit)        printf "Exit" ;;
        *) printf "%s" "$id" ;;
      esac
      ;;
  esac
}

is_running() {
  [[ -r "$PIDFILE" ]] || return 1
  local pid; read -r pid <"$PIDFILE" 2>/dev/null || return 1
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}
notify() { has notify-send && notify-send "wf-recorder" "$1" || true; }

signal_waybar() {
  local pids
  if [[ -r "$WAYBAR_PIDS_CACHE" ]]; then
    pids="$(tr '\n' ' ' <"$WAYBAR_PIDS_CACHE")"
    if [[ -n "$pids" ]]; then kill -RTMIN+"$WAYBAR_SIG" $pids 2>/dev/null && return 0; fi
  fi
  pids="$(pgrep -x -u "$UID" waybar 2>/dev/null | tr '\n' ' ')"
  [[ -n "$pids" ]] && printf '%s\n' $pids >"$WAYBAR_PIDS_CACHE"
  [[ -n "$pids" ]] && kill -RTMIN+"$WAYBAR_SIG" $pids 2>/dev/null || true
}
emit_waybar_signal() { [[ "${WAYBAR_POKE,,}" == "off" ]] && return 0; signal_waybar; }

start_tick() {
  if [[ -f "$TICKPIDFILE" ]]; then
    local tpid; read -r tpid <"$TICKPIDFILE" 2>/dev/null || true
    [[ -n "$tpid" ]] && kill -TERM "$tpid" 2>/dev/null || true
    rm -f "$TICKPIDFILE"
  fi
  (
    while :; do
      [[ -r "$PIDFILE" ]] || break
      local p; read -r p <"$PIDFILE" 2>/dev/null || p=""
      [[ -n "$p" ]] && kill -0 "$p" 2>/dev/null || break
      signal_waybar
      sleep 1
    done
  ) & echo $! >"$TICKPIDFILE"
}
stop_tick() {
  if [[ -f "$TICKPIDFILE" ]]; then
    local tpid; read -r tpid <"$TICKPIDFILE" 2>/dev/null || true
    [[ -n "$tpid" ]] && kill -TERM "$tpid" 2>/dev/null || true
    rm -f "$TICKPIDFILE"
  fi
}

get_save_dir() {
  local videos
  if has xdg-user-dir; then videos="$(xdg-user-dir VIDEOS 2>/dev/null || true)"; fi
  videos="${videos:-"$HOME/Videos"}"
  echo "${SAVE_DIR_ENV:-"$videos/wf-recorder"}"
}

# --- render device helpers ---
list_render_nodes() {
  local d
  for d in /dev/dri/renderD*; do
    [[ -r "$d" ]] && printf '%s\n' "$d"
  done 2>/dev/null || true
}
render_display() {
  local cur="${1:-}"
  if [[ -z "$cur" ]]; then
    msg render_auto
  else
    printf "%s" "$cur"
  fi
}
pick_render_device() {
  local dev="${DRM_DEVICE:-}"
  if [[ -n "$dev" && ! -r "$dev" ]]; then
    printf '%s\n' "$(msg warn_render_unreadable "$dev")" >&2
    dev=""
  fi
  echo -n "$dev"
}

# --- file format helpers ---
ext_for_codec(){ case "${1,,}" in
  *h264*|*hevc*) echo mp4 ;;
  *vp9*)         echo webm ;;
  *av1*)         echo mkv ;;
  *)             echo mp4 ;;
esac; }
choose_ext(){
  local e="${SAVE_EXT,,}"
  if [[ -z "$e" || "$e" == "auto" ]]; then
    ext_for_codec "$CODEC"
  else
    case "$e" in mp4|mkv|webm) echo "$e" ;; *) echo mp4 ;; esac
  fi
}

# ================== Menus ==================
__norm() { printf '%s' "$1" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }

_pick_menu_backend() {
  local pref="${MENU_BACKEND,,}"
  case "$pref" in fuzzel|wofi|rofi|bemenu|fzf|term) : ;; auto|"") pref="auto" ;; *) pref="auto" ;; esac
  if [[ "$pref" != "auto" ]]; then
    if has "$pref"; then echo "$pref"; else [[ -t 0 ]] && echo "term" || echo "none"; fi
    return
  fi
  for b in fuzzel wofi rofi bemenu fzf; do has "$b" && { echo "$b"; return; }; done
  [[ -t 0 ]] && echo "term" || echo "none"
}

menu_pick() { # $1:title; items...
  local title="${1:-Select}"; shift
  local items=("$@")
  ((${#items[@]})) || return 130

  local backend; backend="$(_pick_menu_backend)"
  local sel rc=130
  case "$backend" in
    fuzzel) set +e; sel="$(printf '%s\n' "${items[@]}" | fuzzel --dmenu -p "$title")"; rc=$?; set -e ;;
    wofi)   set +e; sel="$(printf '%s\n' "${items[@]}" | wofi --dmenu --prompt "$title")"; rc=$?; set -e ;;
    rofi)   set +e; sel="$(printf '%s\n' "${items[@]}" | rofi -dmenu -p "$title")"; rc=$?; set -e ;;
    bemenu) set +e; sel="$(printf '%s\n' "${items[@]}" | bemenu -p "$title")"; rc=$?; set -e ;;
    fzf)    set +e; sel="$(printf '%s\n' "${items[@]}" | fzf --prompt "$title> ")"; rc=$?; set -e ;;
    term)
      echo "$title"
      local i=1; for it in "${items[@]}"; do printf '  %d) %s\n' "$i" "$it"; ((i++)); done
      printf "%s" "$(msg prompt_enter_number)"
      local idx; set +e; read -r idx; rc=$?; set -e
      if [[ $rc -eq 0 && -n "$idx" && "$idx" =~ ^[0-9]+$ ]]; then
        if (( idx>=1 && idx<=${#items[@]} )); then sel="${items[$((idx-1))]}"; rc=0; fi
      fi
      ;;
    none) return 130 ;;
  esac
  [[ $rc -ne 0 || -z "${sel:-}" ]] && return 130
  printf '%s' "$(__norm "$sel")"
}

# ---------- Outputs ----------
list_outputs() {
  local raw
  if raw="$(wf-recorder -L 2>/dev/null)"; then :; elif has wlr-randr; then raw="$(wlr-randr 2>/dev/null | awk '/^[^ ]/{print $1}')"; else raw=""; fi
  awk 'BEGIN{RS="[ \t\r\n,]+"} /^[A-Za-z0-9_.:-]+$/ { if ($0 ~ /^(e?DP|HDMI|DVI|VGA|LVDS|Virtual|XWAYLAND)/) seen[$0]=1 } END{for(k in seen) print k}' <<<"$raw" | sort -u
}
decide_output() {
  if [[ -n "$OUTPUT" ]]; then printf '%s' "$OUTPUT"; return 0; fi
  local -a outs; mapfile -t outs < <(list_outputs || true)
  local out_title; out_title="${MENU_TITLE_OUTPUT:-$(msg title_output)}"
  if [[ "${OUTPUT_SELECT}" == "menu" ]] || { [[ "${OUTPUT_SELECT}" == "auto" ]] && ((${#outs[@]} > 1)); }; then
    local pick; pick="$(menu_pick "$out_title" "${outs[@]}")" || return 130
    printf '%s' "$pick"; return 0
  fi
  if ((${#outs[@]} == 1)); then printf '%s' "${outs[0]}"; else printf '%s\n' "$(msg warn_multi_outputs_cancel)" >&2; return 130; fi
}

# ---------- Settings ----------
choose_render_menu() {
  local -a nodes
  mapfile -t nodes < <(list_render_nodes | sort -V || true)
  local auto_item; auto_item="$(msg render_auto)"
  local pick
  if ! pick="$(menu_pick "$(msg title_select_render)" "$auto_item" "${nodes[@]}")"; then
    return 0
  fi
  if [[ "$pick" == "$auto_item" ]]; then
    DRM_DEVICE=""
    rm -f "$CFG_DRM"
    return 0
  fi
  local sel="$pick"
  if [[ -n "$sel" && -r "$sel" ]]; then
    DRM_DEVICE="$sel"
    printf '%s' "$DRM_DEVICE" >"$CFG_DRM"
  else
    printf '%s\n' "$(msg warn_render_unreadable "$sel")" >&2
  fi
}

choose_filefmt_menu() {
  local auto_item; auto_item="$(msg ext_auto)"
  local pick
  if ! pick="$(menu_pick "$(msg title_select_filefmt)" "$auto_item" "mp4" "mkv" "webm")"; then
    return 0
  fi
  if [[ "$pick" == "$auto_item" ]]; then
    SAVE_EXT="auto"
    rm -f "$CFG_EXT"
  else
    case "$pick" in
      mp4|mkv|webm) SAVE_EXT="$pick"; printf '%s' "$SAVE_EXT" >"$CFG_EXT" ;;
      *) : ;;
    esac
  fi
}

show_settings_menu() {
  while :; do
    local fps_display="${FRAMERATE:-$(msg fps_unlimited)}"
    local audio_display="${AUDIO}"
    local render_display_now; render_display_now="$(render_display "$DRM_DEVICE")"
    local ff_display; if [[ -z "$SAVE_EXT" || "${SAVE_EXT,,}" == "auto" ]]; then ff_display="$(msg ext_auto)"; else ff_display="$SAVE_EXT"; fi

    # ORDER: Framerate → Audio → Codec → File Format → Render → Back
    local pick; pick="$(menu_pick "$(msg title_settings)" \
                      "$(msg menu_set_fps "$fps_display")" \
                      "$(msg menu_toggle_audio "$audio_display")" \
                      "$(msg menu_set_codec "$CODEC")" \
                      "$(msg menu_set_filefmt "$ff_display")" \
                      "$(msg menu_set_render "$render_display_now")" \
                      "$(msg menu_back)")" || return 0

    if [[ "$pick" == "$(msg menu_set_fps "$fps_display")" ]]; then
      local newf; newf="$(menu_pick "$(msg title_select_fps)" "60" "30" "120" "144" "165" "240" "$(msg fps_unlimited)")" || continue
      if [[ "$newf" == "$(msg fps_unlimited)" ]]; then
        FRAMERATE=""; rm -f "$CFG_FPS"
      else
        if [[ "$newf" =~ ^[0-9]+$ && "$newf" -gt 0 ]]; then FRAMERATE="$newf"; printf '%s' "$FRAMERATE" >"$CFG_FPS"; fi
      fi

    elif [[ "$pick" == "$(msg menu_toggle_audio "$audio_display")" ]]; then
      if [[ "$AUDIO" == "on" ]]; then AUDIO="off"; else AUDIO="on"; fi
      printf '%s' "$AUDIO" >"$CFG_AUDIO"

    elif [[ "$pick" == "$(msg menu_set_codec "$CODEC")" ]]; then
      # 仅保留 CPU (libx264) 与所有常见 VAAPI 编码选项，CPU 放在首位
      local newc; newc="$(menu_pick "$(msg title_select_codec)" \
                        "libx264" "h264_vaapi" "hevc_vaapi" "av1_vaapi" "vp9_vaapi")" || continue
      CODEC="$newc"; printf '%s' "$CODEC" >"$CFG_CODEC"

    elif [[ "$pick" == "$(msg menu_set_filefmt "$ff_display")" ]]; then
      choose_filefmt_menu

    elif [[ "$pick" == "$(msg menu_set_render "$render_display_now")" ]]; then
      choose_render_menu

    elif [[ "$pick" == "$(msg menu_back)" ]]; then
      return 0
    fi
    # loop to refresh values instantly
  done
}

# ---------- Mode selection ----------
decide_mode() {
  case "${RECORD_MODE,,}" in
    full|fullscreen) MODE_DECIDED="full";    return 0 ;;
    region|area)     MODE_DECIDED="region"; return 0 ;;
    *) ;;
  esac
  local L_FULL L_REGION L_GIF L_SETTINGS L_EXIT
  case "$(lang_code)" in
    zh) L_FULL="$(msg menu_fullscreen)"; L_REGION="$(msg menu_region)"; L_GIF="$(msg menu_gif_region)"; L_SETTINGS="$(msg menu_settings)"; L_EXIT="$(msg menu_exit)";;
    ja) L_FULL="$(msg menu_fullscreen)"; L_REGION="$(msg menu_region)"; L_GIF="$(msg menu_gif_region)"; L_SETTINGS="$(msg menu_settings)"; L_EXIT="$(msg menu_exit)";;
    *)  L_FULL="Fullscreen"; L_REGION="Region"; L_GIF="$(msg menu_gif_region)"; L_SETTINGS="$(msg menu_settings)"; L_EXIT="$(msg menu_exit)";;
  esac
  local title; title="$(msg title_mode)"
  while :; do
    # ORDER: Fullscreen -> Region -> GIF -> Settings -> Exit
    # [FIXED] 调整菜单顺序以匹配图片要求：全屏在最前，GIF在区域之后
    local pick; pick="$(menu_pick "$title" "$L_FULL" "$L_REGION" "$L_GIF" "$L_SETTINGS" "$L_EXIT")" || return 130
    if    [[ "$pick" == "$L_FULL"   ]]; then MODE_DECIDED="full";    return 0
    elif [[ "$pick" == "$L_REGION"  ]]; then MODE_DECIDED="region"; return 0
    elif [[ "$pick" == "$L_GIF"     ]]; then MODE_DECIDED="region"; IS_GIF_MODE="true"; return 0
    elif [[ "$pick" == "$L_SETTINGS" ]]; then show_settings_menu; continue
    elif [[ "$pick" == "$L_EXIT"    ]]; then return 130
    else return 130; fi
  done
}

# ---------- Helpers ----------
geom_token() {
  local g="$1"
  awk 'NF==2{split($1,a,","); split($2,b,"x");
             if(a[1]!=""){printf "%sx%s@%s,%s",b[1],b[2],a[1],a[2]}}' <<<"$g"
}
pretty_dur() {
  local dur="${1:-0}"
  [[ "$dur" =~ ^[0-9]+$ ]] || dur=0
  if ((dur>=3600)); then printf "%d:%02d:%02d" $((dur/3600)) $(((dur%3600)/60)) $((dur%60))
  else printf "%02d:%02d" $((dur/60)) $((dur%60)); fi
}
json_escape() { sed ':a;N;$!ba;s/\\/\\\\/g;s/"/\\"/g;s/\n/\\n/g'; }

# ================== Start / Stop ==================
start_rec() {
  if is_running; then echo "$(msg already_running)"; exit 0; fi
  has wf-recorder || { echo "$(msg err_wf_not_found)"; exit 1; }

  MODE_DECIDED=""
  IS_GIF_MODE="false"
  if ! decide_mode; then
    echo "$(msg cancel_no_mode)"; emit_waybar_signal; exit 130
  fi
  local mode="$MODE_DECIDED"

  # [NEW] GIF 模式检查
  if [[ "$IS_GIF_MODE" == "true" ]]; then
      if ! has ffmpeg; then echo "$(msg err_need_ffmpeg)"; emit_waybar_signal; exit 1; fi
      # GIF 模式强制使用 mp4 作为中间格式，因为 mp4 兼容性好且编码速度快
      SAVE_EXT="mp4"
      touch "$GIF_MARKER"
  else
      rm -f "$GIF_MARKER"
  fi

  local marker="" output="" GEOM="" gtok=""
  local -a args
  args=( -c "$CODEC" )

  local ROOT_DIR TARGET_DIR
  ROOT_DIR="$(get_save_dir)"
  if [[ "$mode" == "full" ]]; then TARGET_DIR="$ROOT_DIR/${SAVE_SUBDIR_FS}"; else TARGET_DIR="$ROOT_DIR"; fi
  mkdir -p "$TARGET_DIR"

  if [[ "$mode" == "full" ]]; then
    output="$(decide_output)" || { echo "$(msg cancel_no_output)"; emit_waybar_signal; exit 130; }
    [[ -n "$output" ]] && args+=( -o "$output" )
    marker="FS${output:+-$output}"
  else
    if [[ -n "$REC_AREA" ]]; then
      GEOM="$REC_AREA"
    else
      has slurp || { echo "$(msg err_need_slurp)"; emit_waybar_signal; exit 1; }
      set +e; GEOM="$(slurp)"; local rc=$?; set -e
      if [[ $rc -ne 0 || -z "${GEOM// /}" ]]; then echo "$(msg cancel_no_region)"; emit_waybar_signal; exit 130; fi
    fi
    GEOM="$(echo -n "$GEOM" | tr -s '[:space:]' ' ')"
    args+=( -g "$GEOM" )
    if [[ "${GEOM_IN_NAME,,}" == "on" ]]; then gtok="$(geom_token "$GEOM")"; marker="REGION${gtok:+-$gtok}"; else marker="REGION"; fi
  fi

  local ts safe_title base SAVE_PATH ext
  ts="$(date +'%Y-%m-%d-%H%M%S')"; safe_title="${TITLE// /_}"
  base="$ts${safe_title:+-$safe_title}-${marker}"
  ext="$(choose_ext)"
  SAVE_PATH="$TARGET_DIR/$base.$ext"

  args=( --file "$SAVE_PATH" "${args[@]}" )

  # Render device
  local dev; dev="$(pick_render_device)"; [[ -n "$dev" ]] && args+=( -d "$dev" )

  # Audio
  case "$AUDIO" in off|OFF|0|false) ;; on|ON|1|true|"") args+=( --audio ) ;; *) args+=( --audio="$AUDIO" ) ;; esac

  # Framerate
  if [[ -n "$FRAMERATE" ]]; then
    if [[ "$FRAMERATE" =~ ^[0-9]+$ && "$FRAMERATE" -gt 0 ]]; then args+=( --framerate "$FRAMERATE" )
    else printf '%s\n' "$(msg warn_invalid_fps "$FRAMERATE")" >&2; fi
  fi

  # Pixel format
  if [[ "$CODEC" == *"_vaapi" ]]; then args+=( -F "scale_vaapi=format=nv12:out_range=full:out_color_primaries=bt709" )
  else args+=( -F "format=yuv420p" ); fi

  # === 不保存日志：仅在 DEBUG=on 时将 wf-recorder 输出到终端 ===
  if [[ "${DEBUG,,}" == "on" ]]; then
    echo "DEBUG=on: running wf-recorder in foreground"
    echo "Command: wf-recorder ${args[*]}"
    wf-recorder "${args[@]}" 2>&1 &
    local pid=$!
    echo "$pid" >"$PIDFILE"
    date +%s >"$STARTFILE"
    echo "$SAVE_PATH" >"$SAVEPATH_FILE"
    echo "$mode" >"$MODEFILE"
    local note; if [[ "$mode" == "full" ]]; then note="$(msg notif_started_full "$output" "$SAVE_PATH")"; else note="$(msg notif_started_region "$SAVE_PATH")"; fi
    [[ -n "$dev" ]] && note+="$(msg notif_device_suffix "$dev")"
    echo "$note";
    emit_waybar_signal
    start_tick
    return 0
  fi

  # 非 DEBUG：后台运行，且不保存任何日志（与原脚本行为相近）
  setsid nohup wf-recorder "${args[@]}" >/dev/null 2>&1 &
  local pid=$!
  echo "$pid" >"$PIDFILE"
  date +%s >"$STARTFILE"
  echo "$SAVE_PATH" >"$SAVEPATH_FILE"
  echo "$mode" >"$MODEFILE"

  local note; if [[ "$mode" == "full" ]]; then note="$(msg notif_started_full "$output" "$SAVE_PATH")"; else note="$(msg notif_started_region "$SAVE_PATH")"; fi
  [[ -n "$dev" ]] && note+="$(msg notif_device_suffix "$dev")"
  echo "$note";
  emit_waybar_signal
  start_tick
}

stop_rec() {
  if ! is_running; then echo "$(msg not_running)"; emit_waybar_signal; exit 0; fi
  local pid; read -r pid <"$PIDFILE"

  kill -INT "$pid" 2>/dev/null || true
  for _ in {1..40}; do sleep 0.1; is_running || break; done
  is_running && kill -TERM "$pid" 2>/dev/null || true
  sleep 0.2
  is_running && kill -KILL "$pid" 2>/dev/null || true

  # 停止后清理运行时状态文件
  rm -f "$PIDFILE" "$MODEFILE"
  stop_tick

  local save_path=""; [[ -r "$SAVEPATH_FILE" ]] && read -r save_path <"$SAVEPATH_FILE"
  
  # --- [NEW] GIF Conversion Logic ---
  if [[ -f "$GIF_MARKER" ]]; then
    rm -f "$GIF_MARKER"
    if [[ -n "$save_path" && -f "$save_path" ]]; then
        notify "$(msg notif_processing_gif)"
        
        # [FIXED] 确保 GIF 目录存在: .../wf-recorder/gif/
        local gif_dir="$(get_save_dir)/gif"
        mkdir -p "$gif_dir"
        
        local filename=$(basename "$save_path")
        local gif_out="$gif_dir/${filename%.*}.gif"
        
        # 使用您提供的滤镜字符串
        local filters="fps=$GIF_FPS,scale=$GIF_WIDTH:-1:flags=lanczos,split[s0][s1];[s0]palettegen=stats_mode=$GIF_STATS_MODE[p];[s1][p]paletteuse=dither=$GIF_DITHER_MODE"
        
        # 运行转换，如果成功则删除原文件
        if ffmpeg -y -v error -i "$save_path" -vf "$filters" "$gif_out"; then
             rm "$save_path"
             save_path="$gif_out"
             # 更新保存路径以便后续通知使用
             echo "$save_path" > "$SAVEPATH_FILE"
        else
             notify "$(msg notif_gif_failed)"
        fi
    fi
  fi
  # -----------------------------------

  if [[ -n "$save_path" && -f "$save_path" ]]; then
    # 生成不带后缀的 latest（例如：.../latest）
    ln -sf "$(basename "$save_path")" "$(dirname "$save_path")/latest" || true

    # --- [NEW] Auto Copy to Clipboard (as File Object) ---
    local cp_note=""
    if command -v wl-copy >/dev/null; then
        # [CRITICAL FIX] 使用 text/uri-list MIME 类型，并添加 file:// 前缀
        # 这会让剪贴板将其视为一个“文件”，允许在文件管理器或聊天软件中直接粘贴
        echo "file://${save_path}" | wl-copy --type text/uri-list
        cp_note=" $(msg notif_copied)"
    fi
    # ------------------------------------

    local s; s="$(msg notif_saved "$save_path")${cp_note}"; echo "$s"; notify "$s"
  else
    local s; s="$(msg notif_stopped)"; echo "$s"; notify "$s"
  fi

  if [[ "${PKILL_AFTER_STOP,,}" != "off" ]]; then
    for sig in INT TERM KILL; do
      pgrep -x -u "$UID" "$APP" >/dev/null || break
      pkill -"$sig" -x -u "$UID" "$APP" 2>/dev/null || true
      sleep 0.1
    done
  fi
  emit_waybar_signal
}

# ================== Waybar JSON/status ==================
tooltip_idle_text() {
  case "$(lang_code)" in
    zh) cat <<'EOF'
屏幕录制（wf-recorder）
左键：打开录制菜单
右键：强制关闭
EOF
      ;;
    ja) cat <<'EOF'
画面録画（wf-recorder）
左クリック：録画メニューを開く
右クリック：強制停止
EOF
      ;;
    *)  cat <<'EOF'
Screen recording (wf-recorder)
Left click: open recording menu
Right click: force stop
EOF
      ;;
  esac
}
tooltip_recording_text() { # $1 elapsed, $2 filepath, $3 mode: full|region
  local t="$1" p="${2:-}" m="${3:-}"
  local mode_label
  case "$m" in full|fullscreen) mode_label="$(msg mode_full)";; region|area) mode_label="$(msg mode_region)";; *) mode_label="";; esac
  case "$(lang_code)" in
    zh) [[ -n "$p" ]] && { [[ -n "$mode_label" ]] && printf "录制中（%s）\n已用时：%s\n文件：%s\n" "$mode_label" "$t" "$p" || printf "录制中\n已用时：%s\n文件：%s\n" "$t" "$p"; } || { [[ -n "$mode_label" ]] && printf "录制中（%s）\n已用时：%s\n" "$mode_label" "$t" || printf "录制中\n已用时：%s\n" "$t"; } ;;
    ja) [[ -n "$p" ]] && { [[ -n "$mode_label" ]] && printf "録画中（%s）\n経過時間：%s\nファイル：%s\n" "$mode_label" "$t" "$p" || printf "録画中\n経過時間：%s\nファイル：%s\n" "$t" "$p"; } || { [[ -n "$mode_label" ]] && printf "録画中（%s）\n経過時間：%s\n" "$mode_label" "$t" || printf "録画中\n経過時間：%s\n" "$t"; } ;;
    *)  [[ -n "$p" ]] && { [[ -n "$mode_label" ]] && printf "Recording (%s)\nElapsed: %s\nFile: %s\n" "$mode_label" "$t" "$p" || printf "Recording\nElapsed: %s\nFile: %s\n" "$t" "$p"; } || { [[ -n "$mode_label" ]] && printf "Recording (%s)\nElapsed: %s\n" "$mode_label" "$t" || printf "Recording\nElapsed: %s\n" "$t"; } ;;
  esac
}
pretty_status_json() {
  local text tooltip class alt
  if is_running; then
    local start=0; [[ -r "$STARTFILE" ]] && read -r start <"$STARTFILE" || true
    [[ "$start" =~ ^[0-9]+$ ]] || start=0
    local now dur; now="$(date +%s)"; dur=$((now - start)); (( dur < 0 )) && dur=0
    local t; t="$(pretty_dur "$dur")"
    local save_path=""; [[ -r "$SAVEPATH_FILE" ]] && read -r save_path <"$SAVEPATH_FILE" || true
    local mode=""; [[ -r "$MODEFILE" ]] && read -r mode <"$MODEFILE" || true
    text="$ICON_REC$t"
    tooltip="$(tooltip_recording_text "$t" "$save_path" "$mode")"
    class="recording"; alt="rec"
  else
    text="$ICON_IDLE"; tooltip="$(tooltip_idle_text)"; class="idle"; alt="idle"
  fi
  printf '{"text":"%s","tooltip":"%s","class":"%s","alt":"%s"}\n' \
     "$(printf '%s' "$text"    | json_escape)" \
     "$(printf '%s' "$tooltip" | json_escape)" \
    "$class" "$alt"
}
status_rec() {
  local json="${1:-}"
  if [[ "$json" == "--json" ]]; then
    pretty_status_json
  else
    if is_running; then
      local start=0; [[ -r "$STARTFILE" ]] && read -r start <"$STARTFILE" || true
      [[ "$start" =~ ^[0-9]+$ ]] || start=0
      local now dur; now="$(date +%s)"; dur=$((now - start)); (( dur < 0 )) && dur=0
      printf "%s%s\n" "$ICON_REC" "$(pretty_dur "$dur")"
    else
      echo "$ICON_IDLE"
    fi
  fi
}

# ================== Main ==================
case "${1:-toggle}" in
  start)          start_rec ;;
  stop)           stop_rec ;;
  status)         status_rec ;;
  status-json)    status_rec --json ;;
  waybar)         status_rec --json ;;
  is-active)      if is_running; then exit 0; else exit 1; fi ;;
  toggle)         is_running && stop_rec || start_rec ;;
  settings)       show_settings_menu ;;
  *)              echo "Usage: $0 {start|stop|toggle|status|status-json|waybar|is-active|settings}"; exit 2 ;;
esac
