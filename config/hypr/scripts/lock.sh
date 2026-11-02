#!/usr/bin/env bash
# lock.sh — start hyprlock. The lock key and hypridle's lock_cmd both come here.
#
# Under VMware Hyprland refuses clients' GPU buffers (see the VMware paragraph in
# lucent's CLAUDE.md), and hyprlock uses them twice: to read the screen and to
# draw itself. Either one kills it, and a hyprlock that dies after taking the lock
# leaves the screen on Hyprland's "lockscreen died" page, and one that dies before
# leaves the desktop unlocked. So here it reads the screen through the CPU
# (screencopy_mode) and draws in software (LIBGL_ALWAYS_SOFTWARE).
#
# LIBGL_ALWAYS_SOFTWARE is set here rather than in gpu.lua because hl.env reaches
# Hyprland's own renderer too. screencopy_mode goes in a copy of hyprlock.conf,
# made on each lock, because that file is shared with every other machine and
# theme.sh and wallpaper.sh patch it in place.
set -u

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprlock.conf"

if [[ "$(systemd-detect-virt 2>/dev/null)" == vmware ]]; then
    copy="${XDG_RUNTIME_DIR:-/tmp}/hyprlock-vmware.conf"
    if sed 's/^general {$/general {\n    screencopy_mode = 1/' "$CONF" > "$copy"; then
        LIBGL_ALWAYS_SOFTWARE=1 exec hyprlock -c "$copy" "$@"
    fi
    LIBGL_ALWAYS_SOFTWARE=1 exec hyprlock "$@"
fi

exec hyprlock "$@"
