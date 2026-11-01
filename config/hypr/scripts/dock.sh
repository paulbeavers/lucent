#!/usr/bin/env bash
# The dock. SUPER + D.
#
#     dock.sh             toggle: hide it if it is showing, show it if not
#     dock.sh --start     start it, unless it has been hidden (login)
#     dock.sh --mode dock|panel
#                         the floating dock, or the panel: one strip across
#                         the bottom holding the dock, the workspaces, the
#                         clock and everything else the top bar has, which
#                         goes away. Applied at once and remembered in
#                         ~/.config/lucent/dock-mode; lucent-config's Dock
#                         page calls this.
#     dock.sh --position bottom|top
#                         which screen edge, for the dock and the panel alike.
#                         Applied at once and remembered in
#                         ~/.config/lucent/dock-position.
#
# The Quickshell shell draws it, with the bar, wherever quickshell is
# installed; the GTK dock, lucent-dock/dock.py, beside waybar, where it is not.
# `bar.sh --engine` says which. This script works with either.
#
# On by default. Hiding it is remembered: ~/.config/lucent/dock-hidden exists
# while it is hidden, so the next login starts without it, and removing that
# file is the same as pressing the key.
#
# Hidden gives back the dock's exclusive zone, so windows tile into its space
# at once: the GTK dock stops; the shell unmaps it, told over IPC.
set -euo pipefail

CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
SCRIPTS="$CFG/hypr/scripts"
HIDDEN="$CFG/lucent/dock-hidden"
DOCK="$CFG/lucent-dock/dock.py"
MODE="$CFG/lucent/dock-mode"
POSITION="$CFG/lucent/dock-position"
SHELL_DIR="$CFG/lucent-shell"

note() { command -v notify-send >/dev/null && notify-send -a Dock -t 1500 "$@" || true; }

engine() { "$SCRIPTS/bar.sh" --engine; }

# The GTK dock names its own process lucent-dock, so -x finds it exactly.
# Matching the command line instead also matches any shell that mentions the
# path — it killed a test shell once.
gtk_running() { pgrep -x lucent-dock >/dev/null; }

gtk_start() {
    gtk_running && return 0
    [[ -f $DOCK ]] || return 0
    # At login the bar and the dock are started together. In panel mode the
    # dock must map after the panel to sit on top of it, so wait for waybar.
    # Panel is the default: anything but an explicit "dock".
    if [[ "$(cat "$MODE" 2>/dev/null)" != dock ]]; then
        for _ in $(seq 30); do pgrep -x waybar >/dev/null && break; sleep 0.1; done
        sleep 0.5
    fi
    # setsid, so it outlives this script and the keybind's shell.
    setsid -f python3 "$DOCK" >/dev/null 2>&1
}

gtk_stop() {
    pkill -x lucent-dock 2>/dev/null || true
}

# Tell the shell; if it is not running, start it, and it reads dock-hidden.
shell_dock() {
    qs -p "$SHELL_DIR" ipc call dock "$1" >/dev/null 2>&1 || "$SCRIPTS/bar.sh"
}

# The bar first, then the dock: with waybar the dock reads the mode when it
# starts and, in panel mode, has to be the later surface to land on top of the
# panel. The shell is one program, and bar.sh --restart covers both.
restart_all() {
    "$SCRIPTS/bar.sh" --restart
    if [[ $(engine) == waybar ]] && gtk_running; then
        gtk_stop
        for _ in $(seq 10); do gtk_running || break; sleep 0.1; done
        sleep 0.5    # let the bar map first
        gtk_start
    fi
}

set_mode() {
    case "$1" in dock|panel) ;; *) echo "dock.sh: mode is dock or panel" >&2; exit 2 ;; esac
    mkdir -p "${MODE%/*}"
    printf '%s\n' "$1" > "$MODE"
    restart_all
}

set_position() {
    case "$1" in bottom|top) ;;
        *) echo "dock.sh: position is bottom or top" >&2; exit 2 ;; esac
    mkdir -p "${POSITION%/*}"
    printf '%s\n' "$1" > "$POSITION"
    restart_all
}

toggle() {
    if [[ -e $HIDDEN ]] || { [[ $(engine) == waybar ]] && ! gtk_running; }; then
        rm -f "$HIDDEN"
        if [[ $(engine) == quickshell ]]; then shell_dock show; else gtk_start; fi
    else
        mkdir -p "${HIDDEN%/*}" && : > "$HIDDEN"
        if [[ $(engine) == quickshell ]]; then shell_dock hide; else gtk_stop; fi
        note "Dock hidden" "SUPER + D brings it back."
    fi
}

case "${1-}" in
    --mode)
        set_mode "${2-}" ;;
    --position)
        set_position "${2-}" ;;
    --start)
        # The shell draws its own dock when bar.sh starts it.
        [[ -e $HIDDEN || $(engine) == quickshell ]] || gtk_start ;;
    "")
        toggle ;;
    *)
        echo "usage: dock.sh [--start | --mode dock|panel | --position bottom|top]" >&2
        exit 2 ;;
esac
