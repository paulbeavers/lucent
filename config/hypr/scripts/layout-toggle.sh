#!/usr/bin/env bash
# Layout toggle — MOD + T. Flips general:layout between dwindle and scrolling.
#
# The switch is a runtime `hyprctl eval`, so it re-tiles the open windows
# immediately but does not touch theme.lua: a fresh session puts you back on
# whatever theme.lua sets as the default.
#
# `hyprctl keyword` is not usable here — the Lua config manager rejects it with
# "keyword can't work with non-legacy parsers. Use eval." `getoption` is still
# fine, so reading the current layout is unchanged.
set -euo pipefail

note() { command -v notify-send >/dev/null && notify-send -a Layout -t 1500 "$@" || true; }

# The hint names the modifier the binds actually use. keys.lua is written by
# lucent-config and is absent until the modifier has been changed, which means
# SUPER; keybinds.sh reads it the same way.
MOD=SUPER
if grep -qE 'mod[[:space:]]*=[[:space:]]*"ALT"' \
        "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/keys.lua" 2>/dev/null; then
    MOD=ALT
fi

current() { hyprctl getoption general:layout -j | jq -r '.str'; }

if [[ "$(current)" == scrolling ]]; then next=dwindle; else next=scrolling; fi

hyprctl eval "hl.config({ general = { layout = \"$next\" } })" >/dev/null

case "$next" in
    scrolling) note "Scrolling" "Windows on an endless tape. $MOD + - / = resizes a column." ;;
    dwindle)   note "Dwindle"   "Back to binary-split tiling." ;;
esac
