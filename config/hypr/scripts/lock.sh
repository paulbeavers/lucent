#!/usr/bin/env bash
# lock.sh — start hyprlock, and start it again if it dies while the session is
# still locked. The lock key and hypridle's lock_cmd both come here.
#
# hyprlock aborts when it loses its Wayland connection, and waking with the only
# monitor gone (a KVM switched to another computer) does that: Hyprland drops the
# client as it swaps in its FALLBACK output. The session stays locked with nothing
# to unlock it, which used to mean rebooting over ssh. So this stays running and
# asks Hyprland, rather than reading hyprlock's exit status, because a hyprlock
# that left without unlocking is the same problem however it left. It needs
# misc.allow_session_lock_restore, set in hyprland.lua.
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

note() { logger -t lucent-lock "$*" 2>/dev/null || true; }

# One of these per session. A second one, from hypridle during a restart's pause,
# leaves it to the first. Only "busy" counts: if flock itself is missing, locking
# matters more than being the only one.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/lucent-lock.flock"
flock -n 9
[[ $? -eq 1 ]] && exit 0

cmd=(hyprlock)
if [[ "$(systemd-detect-virt 2>/dev/null)" == vmware ]]; then
    export LIBGL_ALWAYS_SOFTWARE=1
    copy="${XDG_RUNTIME_DIR:-/tmp}/hyprlock-vmware.conf"
    if sed 's/^general {$/general {\n    screencopy_mode = 1/' "$CONF" > "$copy"; then
        cmd+=(-c "$copy")
    fi
fi

# 9>&- or hyprlock inherits the flock and outlives this script holding it.
"${cmd[@]}" "$@" 9>&-
status=$?

# Slow enough not to spin while there is nothing to draw on, and it starts over
# after a hyprlock that lasted. It never gives up: giving up is the stuck screen.
delay=1
while :; do
    # An unlock has been sent by the time hyprlock exits, but not necessarily
    # handled. Asking too soon would lock the screen again straight after a
    # correct password.
    sleep 0.5
    # Anything but true or false: Hyprland is gone (logging out, which also ends
    # hyprlock) or is too old to have this request. Nothing to do in either case.
    [[ "$(hyprctl locked 2>/dev/null)" == true ]] || exit "$status"

    note "hyprlock exited with $status while locked; restarting in ${delay}s"
    sleep "$delay"
    started=$SECONDS
    # Without "$@": a --grace given to the first would let a restart unlock on a
    # mouse movement.
    "${cmd[@]}" 9>&-
    status=$?

    if (( SECONDS - started >= 60 )); then
        delay=1
    elif (( delay < 30 )); then
        delay=$(( delay * 2 ))
    fi
done
