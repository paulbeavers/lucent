#!/usr/bin/env bash
# bar.sh — the bar and the dock: ~/.config/lucent-shell, one Quickshell program
# drawing both. install.sh makes Quickshell a requirement on every distro.
#
#     bar.sh              start it (login: autostart.lua)
#     bar.sh --restart    stop it and start it again (SUPER+SHIFT+R, and dock.sh
#                         after the dock's style or position changes)
#     bar.sh --theme      theme.sh, after a switch (see below)
#
# It reads dock-mode, dock-position, dock-pinned and dock-hidden in
# ~/.config/lucent, and the palette theme.sh renders beside them.
set -euo pipefail

CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
SHELL_DIR="$CFG/lucent-shell"
HIDDEN="$CFG/lucent/dock-hidden"
ICONS_STAMP="${XDG_RUNTIME_DIR:-/tmp}/lucent-shell-icons"

# Quickshell's process is qs whatever it runs, so pgrep cannot tell the shell
# from any other qs. Its bar's layer surface can: namespace lucent-bar, which
# only the shell uses.
running() {
    hyprctl -j layers 2>/dev/null \
        | jq -e '[.. | objects | select(.namespace? == "lucent-bar")] | length > 0' \
        >/dev/null 2>&1
}

icon_theme() {
    local icons
    icons=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
    echo "${icons:-Papirus-Dark}"
}

start() {
    running && return 0
    # Qt does not read GTK's icon theme, so without this quickshell finds no
    # icon theme and draws every icon blank.
    local icons hidden=0
    icons=$(icon_theme)
    [[ -e $HIDDEN ]] && hidden=1
    printf '%s\n' "$icons" > "$ICONS_STAMP"
    # setsid, so it outlives this script and the keybind's shell; -n makes a
    # second qs for the same config exit.
    QS_ICON_THEME="$icons" LUCENT_DOCK_HIDDEN="$hidden" \
        setsid -f qs -n -p "$SHELL_DIR" >/dev/null 2>&1
}

stop() {
    qs kill -p "$SHELL_DIR" >/dev/null 2>&1 || true
    for _ in $(seq 20); do running || break; sleep 0.1; done
}

if ! command -v qs >/dev/null; then
    echo "bar.sh: quickshell (qs) is not installed; run install.sh" >&2
    exit 1
fi

case "${1-}" in
    "")
        start ;;
    --restart)
        stop; start ;;
    --theme)
        # Colours and font reach the shell by itself: it watches the palette.
        # The icon theme does not — it is handed over at start — so the shell
        # restarts only when a theme brought icons of its own.
        if running && [[ "$(cat "$ICONS_STAMP" 2>/dev/null)" != "$(icon_theme)" ]]; then
            stop; start
        fi ;;
    *)
        echo "usage: bar.sh [--restart | --theme]" >&2
        exit 2 ;;
esac
