#!/usr/bin/env bash
# The dock — lucent-dock, ~/.config/lucent-dock/dock.py. SUPER + SHIFT + D.
#
#     dock.sh             toggle: hide it if it is showing, show it if not
#     dock.sh --start     start it, unless it has been hidden (login)
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

note() { command -v notify-send >/dev/null && notify-send -a Dock -t 1500 "$@" || true; }

# The dock names its own process lucent-dock, so -x finds it exactly. Matching
# the command line instead also matches any shell that mentions the path.
running() { pgrep -x lucent-dock >/dev/null; }

start() {
    running && return 0
    [[ -f $DOCK ]] || return 0
    # setsid, so it outlives this script and the keybind's shell.
    setsid -f python3 "$DOCK" >/dev/null 2>&1
}

stop() {
    pkill -x lucent-dock 2>/dev/null || true
}

case "${1-}" in
    --start)
        [[ -e $HIDDEN ]] || start ;;
    "")
        if running; then
            stop
            mkdir -p "${HIDDEN%/*}" && : > "$HIDDEN"
            note "Dock hidden" "SUPER + SHIFT + D brings it back."
        else
            rm -f "$HIDDEN"
            start
        fi ;;
    *)
        echo "usage: dock.sh [--start]" >&2; exit 2 ;;
esac
