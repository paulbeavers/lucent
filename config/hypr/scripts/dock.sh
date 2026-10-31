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

note() { command -v notify-send >/dev/null && notify-send -a Dock -t 1500 "$@" || true; }

# The dock names its own process lucent-dock, so -x finds it exactly. Matching
# the command line instead also matches any shell that mentions the path.
running() { pgrep -x lucent-dock >/dev/null; }

start() {
    running && return 0
    [[ -f $DOCK ]] || return 0
    # At login the bar and the dock are started together. In panel mode the
    # dock must map after the panel to sit on top of it, so wait for waybar.
    if [[ "$(cat "$MODE" 2>/dev/null)" == panel ]]; then
        for _ in $(seq 30); do pgrep -x waybar >/dev/null && break; sleep 0.1; done
        sleep 0.5
    fi
    # setsid, so it outlives this script and the keybind's shell.
    setsid -f python3 "$DOCK" >/dev/null 2>&1
}

stop() {
    pkill -x lucent-dock 2>/dev/null || true
}

# The bar and the dock are restarted in that order, bar first: the dock reads
# the mode when it starts, and in panel mode it draws inside waybar's strip,
# so it has to be the later of the two surfaces to land on top of it.
set_mode() {
    case "$1" in dock|panel) ;; *) echo "dock.sh: mode is dock or panel" >&2; exit 2 ;; esac
    mkdir -p "${MODE%/*}"
    printf '%s\n' "$1" > "$MODE"
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
        echo "usage: dock.sh [--start | --mode dock|panel]" >&2; exit 2 ;;
esac
