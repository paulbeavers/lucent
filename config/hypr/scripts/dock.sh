#!/usr/bin/env bash
# The dock. SUPER + D.
#
#     dock.sh             toggle: hide it if it is showing, show it if not
#     dock.sh --mode dock|panel
#                         the floating dock, or the panel: one strip along the
#                         screen edge holding the dock, the workspaces, the
#                         clock and the status items, in place of the top bar.
#                         Remembered in ~/.config/lucent/dock-mode.
#     dock.sh --position bottom|top
#                         which screen edge, for the dock and the panel alike.
#                         Remembered in ~/.config/lucent/dock-position.
#     dock.sh --scope all|workspace
#                         every running app, or only those with a window on
#                         the workspace in front of you (pinned apps and
#                         minimized windows show either way).
#                         Remembered in ~/.config/lucent/dock-scope.
#     dock.sh --autohide on|off
#                         slide the dock (the whole panel, in panel style) off
#                         the edge until the pointer reaches it, giving windows
#                         its space. Remembered in ~/.config/lucent/dock-autohide.
#
# lucent-config's Dock page calls the last four. The dock is drawn by the
# Quickshell shell with the bar (bar.sh), which reads these at start, so
# changing any of them restarts it.
#
# On by default. Hiding it is remembered: ~/.config/lucent/dock-hidden exists
# while it is hidden, so the next login starts without it, and removing that
# file is the same as pressing the key. The running shell is told over IPC and
# unmaps the dock, which gives its space back at once.
set -euo pipefail

CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
SCRIPTS="$CFG/hypr/scripts"
HIDDEN="$CFG/lucent/dock-hidden"
MODE="$CFG/lucent/dock-mode"
POSITION="$CFG/lucent/dock-position"
SCOPE="$CFG/lucent/dock-scope"
AUTOHIDE="$CFG/lucent/dock-autohide"
SHELL_DIR="$CFG/lucent-shell"

note() { command -v notify-send >/dev/null && notify-send -a Dock -t 1500 "$@" || true; }

# The key every bind starts with, for the hint: keys.lua is written by
# lucent-config and absent until the modifier has been changed, which means SUPER.
modifier() {
    if grep -qsE 'mod[[:space:]]*=[[:space:]]*"ALT"' "$CFG/hypr/keys.lua"; then
        echo ALT
    else
        echo SUPER
    fi
}

# Tell the shell; if it is not running, start it, and it reads dock-hidden.
shell_dock() {
    qs -p "$SHELL_DIR" ipc call dock "$1" >/dev/null 2>&1 || "$SCRIPTS/bar.sh"
}

set_mode() {
    case "$1" in dock|panel) ;; *) echo "dock.sh: mode is dock or panel" >&2; exit 2 ;; esac
    mkdir -p "${MODE%/*}"
    printf '%s\n' "$1" > "$MODE"
    "$SCRIPTS/bar.sh" --restart
}

set_position() {
    case "$1" in bottom|top) ;;
        *) echo "dock.sh: position is bottom or top" >&2; exit 2 ;; esac
    mkdir -p "${POSITION%/*}"
    printf '%s\n' "$1" > "$POSITION"
    "$SCRIPTS/bar.sh" --restart
}

# A setting the shell reads at start: write it, then restart the shell.
set_file() {
    mkdir -p "${1%/*}"
    printf '%s\n' "$2" > "$1"
    "$SCRIPTS/bar.sh" --restart
}

set_scope() {
    case "$1" in all|workspace) ;;
        *) echo "dock.sh: scope is all or workspace" >&2; exit 2 ;; esac
    set_file "$SCOPE" "$1"
}

set_autohide() {
    case "$1" in on|off) ;;
        *) echo "dock.sh: autohide is on or off" >&2; exit 2 ;; esac
    set_file "$AUTOHIDE" "$1"
}

toggle() {
    if [[ -e $HIDDEN ]]; then
        rm -f "$HIDDEN"
        shell_dock show
    else
        mkdir -p "${HIDDEN%/*}" && : > "$HIDDEN"
        shell_dock hide
        note "Dock hidden" "$(modifier) + D brings it back."
    fi
}

case "${1-}" in
    --mode)
        set_mode "${2-}" ;;
    --position)
        set_position "${2-}" ;;
    --scope)
        set_scope "${2-}" ;;
    --autohide)
        set_autohide "${2-}" ;;
    "")
        toggle ;;
    *)
        echo "usage: dock.sh [--mode dock|panel | --position bottom|top | --scope all|workspace | --autohide on|off]" >&2
        exit 2 ;;
esac
