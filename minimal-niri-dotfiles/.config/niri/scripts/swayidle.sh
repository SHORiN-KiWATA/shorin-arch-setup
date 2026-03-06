#!/usr/bin/env bash

# 5分钟锁屏，10分钟熄屏，20分钟休眠
exec swayidle -w \
timeout 600  'hyprlock -c ~/.config/niri/hyprlock.conf &' \
timeout 900  'niri msg action power-off-monitors' \
resume       'niri msg action power-on-monitors' \
timeout 1800 'systemctl suspend'
