#!/usr/bin/env bash
# The dock — lucent-dock, ~/.config/lucent-dock/dock.py. SUPER + D.
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
#     dock.sh --engine gtk|quickshell
#                         which program draws it: lucent-dock/dock.py (GTK 4,
#                         the default) or lucent-dock/quickshell/shell.qml
#                         (experimental). Remembered in
#                         ~/.config/lucent/dock-engine. Quickshell is used only
#                         where `qs` is installed (Arch, Fedora 44; not Fedora
#                         43 or Ubuntu 26.04), and the GTK dock otherwise.
#
# On by default. Hiding it is remembered: ~/.config/lucent/dock-hidden exists
# while it is hidden, so the next login starts without it, and removing that
# file is the same as pressing the key.
#
# Hidden means stopped. The dock holds an exclusive zone, so windows tile
# above it rather than under it; stopping it gives that space back at once.
set -euo pipefail

CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
HIDDEN="$CFG/lucent/dock-hidden"
DOCK="$CFG/lucent-dock/dock.py"
MODE="$CFG/lucent/dock-mode"
POSITION="$CFG/lucent/dock-position"
ENGINE="$CFG/lucent/dock-engine"
QS_DOCK="$CFG/lucent-dock/quickshell"

note() { command -v notify-send >/dev/null && notify-send -a Dock -t 1500 "$@" || true; }

engine() {
    if [[ "$(cat "$ENGINE" 2>/dev/null)" == quickshell ]] \
        && command -v qs >/dev/null && [[ -f $QS_DOCK/shell.qml ]]; then
        echo quickshell
    else
        echo gtk
    fi
}

# The GTK dock names its own process lucent-dock, so -x finds it exactly.
# Matching the command line instead also matches any shell that mentions the
# path. Quickshell's process is qs whatever it runs, so that one is found by
# its layer surface, whose namespace both docks set to lucent-dock.
running() {
    pgrep -x lucent-dock >/dev/null && return 0
    command -v qs >/dev/null || return 1
    hyprctl -j layers 2>/dev/null \
        | jq -e '[.. | objects | select(.namespace? == "lucent-dock")] | length > 0' \
        >/dev/null 2>&1
}

start() {
    running && return 0
    local which; which=$(engine)
    [[ $which == quickshell || -f $DOCK ]] || return 0
    # At login the bar and the dock are started together. In panel mode the
    # dock must map after the panel to sit on top of it, so wait for waybar.
    # Panel is the default: anything but an explicit "dock".
    if [[ "$(cat "$MODE" 2>/dev/null)" != dock ]]; then
        for _ in $(seq 30); do pgrep -x waybar >/dev/null && break; sleep 0.1; done
        sleep 0.5
    fi
    # setsid, so it outlives this script and the keybind's shell. -n makes a
    # second qs for the same config exit, as the GTK dock's application ID does.
    if [[ $which == quickshell ]]; then
        # Qt does not read GTK's icon theme: env.lua names qt5ct as the
        # platform theme, which a Qt 6 program cannot load, so quickshell
        # would find no icon theme and draw every icon blank. Hand it the
        # one theme.sh set. A theme switch reaches it on the next start.
        local icons
        icons=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
        QS_ICON_THEME="${icons:-Papirus-Dark}" setsid -f qs -n -p "$QS_DOCK" >/dev/null 2>&1
    else
        setsid -f python3 "$DOCK" >/dev/null 2>&1
    fi
}

# Both, whichever engine is chosen: after a switch the other one may be up.
stop() {
    pkill -x lucent-dock 2>/dev/null || true
    if command -v qs >/dev/null; then
        qs kill -p "$QS_DOCK" >/dev/null 2>&1 || true
    fi
}

set_engine() {
    case "$1" in gtk|quickshell) ;;
        *) echo "dock.sh: engine is gtk or quickshell" >&2; exit 2 ;; esac
    if [[ $1 == quickshell ]] && ! command -v qs >/dev/null; then
        echo "dock.sh: quickshell is not installed" >&2; exit 1
    fi
    mkdir -p "${ENGINE%/*}"
    printf '%s\n' "$1" > "$ENGINE"
    if running; then
        stop
        for _ in 1 2 3 4 5 6 7 8 9 10; do running || break; sleep 0.1; done
        start
    fi
}

# The bar and the dock are restarted in that order, bar first: the dock reads
# the mode when it starts, and in panel mode it draws inside waybar's strip,
# so it has to be the later of the two surfaces to land on top of it.
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

restart_all() {
    pkill -x waybar 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x waybar >/dev/null || break; sleep 0.1; done
    setsid -f "$CFG/hypr/scripts/waybar.sh" >/dev/null 2>&1
    if running; then
        stop
        for _ in 1 2 3 4 5 6 7 8 9 10; do running || break; sleep 0.1; done
        sleep 0.5    # let the bar map first
        start
    fi
}

case "${1-}" in
    --mode)
        set_mode "${2-}" ;;
    --position)
        set_position "${2-}" ;;
    --engine)
        set_engine "${2-}" ;;
    --start)
        [[ -e $HIDDEN ]] || start ;;
    "")
        if running; then
            stop
            mkdir -p "${HIDDEN%/*}" && : > "$HIDDEN"
            note "Dock hidden" "SUPER + D brings it back."
        else
            rm -f "$HIDDEN"
            start
        fi ;;
    *)
        echo "usage: dock.sh [--start | --mode dock|panel | --position bottom|top | --engine gtk|quickshell]" >&2
        exit 2 ;;
esac
