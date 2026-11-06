#!/usr/bin/env bash
# Power menu — SUPER+SHIFT+E. Uses wofi so it matches the launcher.
set -euo pipefail

# Nerd Font glyphs (nf-md), as escapes: literals in this file were once lost
# and left plain spaces. Each is in JetBrainsMono Nerd Font; check a new one
# with fc-list ":charset=XXXXX".
lock=$'\U000F033E  Lock'          # md-lock
logout=$'\U000F0343  Log out'     # md-logout
suspend=$'\U000F04B2  Suspend'    # md-sleep
reboot=$'\U000F0709  Reboot'      # md-restart
shutdown=$'\U000F0425  Shut down' # md-power

choice=$(printf '%s\n' "$lock" "$logout" "$suspend" "$reboot" "$shutdown" \
    | wofi --dmenu --prompt "Power" --width 260 --height 260 --cache-file /dev/null)

case "$choice" in
    "$lock")     loginctl lock-session ;;
    "$logout")   hyprctl dispatch 'hl.dsp.exit()' ;;
    "$suspend")  systemctl suspend ;;
    "$reboot")   systemctl reboot ;;
    "$shutdown") systemctl poweroff ;;
esac
