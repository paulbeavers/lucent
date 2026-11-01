#!/usr/bin/env bash
# bar.sh — the bar, and which program draws it and the dock.
#
#     bar.sh                  start the bar (login: autostart.lua)
#     bar.sh --restart        stop it and start it again (dock.sh, after the
#                             dock's style or position changes)
#     bar.sh --reload         SUPER+SHIFT+R: waybar rereads its config; the
#                             Quickshell shell restarts
#     bar.sh --theme          theme.sh, after a switch (see below)
#     bar.sh --engine         print the engine in effect: waybar or quickshell
#     bar.sh --engine waybar|quickshell
#                             switch, at once, and remember it in
#                             ~/.config/lucent/shell-engine
#
# Two engines draw the same desktop from the same files (dock-mode,
# dock-position, dock-pinned, dock-hidden, waybar/colors.css):
#
#   waybar     waybar (waybar.sh) and the GTK dock (lucent-dock/dock.py),
#              two programs composed. The default.
#   quickshell ~/.config/lucent-shell, one Quickshell program drawing the bar
#              and the dock together. Used only where `qs` is installed (Arch,
#              Fedora 44; not Fedora 43 or Ubuntu 26.04); waybar otherwise.
#
# ~/.config/lucent/dock-engine was the dock-only switch this replaced, on the
# same day; "quickshell" there still counts.
set -euo pipefail

CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
SCRIPTS="$CFG/hypr/scripts"
ENGINE_FILE="$CFG/lucent/shell-engine"
OLD_ENGINE_FILE="$CFG/lucent/dock-engine"
SHELL_DIR="$CFG/lucent-shell"
OLD_QS_DOCK="$CFG/lucent-dock/quickshell"
HIDDEN="$CFG/lucent/dock-hidden"
ICONS_STAMP="${XDG_RUNTIME_DIR:-/tmp}/lucent-shell-icons"

engine() {
    local want
    want=$(cat "$ENGINE_FILE" 2>/dev/null || cat "$OLD_ENGINE_FILE" 2>/dev/null || echo waybar)
    if [[ $want == quickshell ]] && command -v qs >/dev/null && [[ -f $SHELL_DIR/shell.qml ]]; then
        echo quickshell
    else
        echo waybar
    fi
}

# Quickshell's process is qs whatever it runs, so pgrep cannot tell the shell
# from any other qs. Its bar's layer surface can: namespace lucent-bar, which
# only the shell uses.
shell_running() {
    hyprctl -j layers 2>/dev/null \
        | jq -e '[.. | objects | select(.namespace? == "lucent-bar")] | length > 0' \
        >/dev/null 2>&1
}

icon_theme() {
    local icons
    icons=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
    echo "${icons:-Papirus-Dark}"
}

start_shell() {
    shell_running && return 0
    # Qt does not read GTK's icon theme: env.lua names qt5ct as the platform
    # theme, which a Qt 6 program cannot load, so without this quickshell
    # finds no icon theme and draws every icon blank.
    local icons hidden=0
    icons=$(icon_theme)
    [[ -e $HIDDEN ]] && hidden=1
    printf '%s\n' "$icons" > "$ICONS_STAMP"
    # setsid, so it outlives this script and the keybind's shell; -n makes a
    # second qs for the same config exit.
    QS_ICON_THEME="$icons" LUCENT_DOCK_HIDDEN="$hidden" \
        setsid -f qs -n -p "$SHELL_DIR" >/dev/null 2>&1
}

stop_shell() {
    command -v qs >/dev/null || return 0
    qs kill -p "$SHELL_DIR" >/dev/null 2>&1 || true
    for _ in $(seq 20); do shell_running || break; sleep 0.1; done
}

start_waybar() {
    pgrep -x waybar >/dev/null && return 0
    setsid -f "$SCRIPTS/waybar.sh" >/dev/null 2>&1
}

stop_waybar() {
    pkill -x waybar 2>/dev/null || true
    for _ in $(seq 10); do pgrep -x waybar >/dev/null || break; sleep 0.1; done
}

start() {
    if [[ $(engine) == quickshell ]]; then start_shell; else start_waybar; fi
}

restart() {
    if [[ $(engine) == quickshell ]]; then
        stop_shell; start_shell
    else
        stop_waybar; start_waybar
    fi
}

# Everything either engine might have up, so a switch starts clean: waybar,
# the GTK dock, the shell, and the dock-only Quickshell config it replaced.
stop_all() {
    stop_waybar
    pkill -x lucent-dock 2>/dev/null || true
    stop_shell
    if command -v qs >/dev/null && [[ -d $OLD_QS_DOCK ]]; then
        qs kill -p "$OLD_QS_DOCK" >/dev/null 2>&1 || true
    fi
}

set_engine() {
    case "$1" in waybar|quickshell) ;;
        *) echo "bar.sh: engine is waybar or quickshell" >&2; exit 2 ;; esac
    if [[ $1 == quickshell ]] && ! command -v qs >/dev/null; then
        echo "bar.sh: quickshell is not installed" >&2; exit 1
    fi
    mkdir -p "${ENGINE_FILE%/*}"
    printf '%s\n' "$1" > "$ENGINE_FILE"
    rm -f "$OLD_ENGINE_FILE"
    stop_all
    start
    # The GTK dock, unless it is hidden; with Quickshell this does nothing,
    # the shell having drawn the dock already.
    "$SCRIPTS/dock.sh" --start
}

case "${1-}" in
    "")
        start ;;
    --restart)
        restart ;;
    --reload)
        if [[ $(engine) == quickshell ]]; then restart
        else pkill -SIGUSR2 -x waybar 2>/dev/null || true; fi ;;
    --theme)
        # Colours and font reach the shell by itself: it watches colors.css and
        # font.css. The icon theme does not — it is handed over at start — so
        # the shell restarts only when a theme brought icons of its own.
        if [[ $(engine) == quickshell ]]; then
            if shell_running && [[ "$(cat "$ICONS_STAMP" 2>/dev/null)" != "$(icon_theme)" ]]; then
                restart
            fi
        else
            pkill -SIGUSR2 -x waybar 2>/dev/null || true
        fi ;;
    --engine)
        if [[ -n ${2-} ]]; then set_engine "$2"; else engine; fi ;;
    *)
        echo "usage: bar.sh [--restart | --reload | --theme | --engine [waybar|quickshell]]" >&2
        exit 2 ;;
esac
