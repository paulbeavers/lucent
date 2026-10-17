#!/usr/bin/env bash
# Keybind cheatsheet — MOD + /
#
# Reads the binds out of the running compositor rather than parsing
# keybinds.lua, so it can never drift out of sync with what is actually bound.
# That includes the modifier: the names below are decoded from each bind's
# modmask, so they follow starch-config's Primary modifier setting by
# themselves.
#
# Dump to stdout instead of opening wofi:
#     ~/.config/hypr/scripts/keybinds.sh --print
set -euo pipefail

# The one label that cannot come from a modmask, because it describes a bind
# by name rather than listing it. keys.lua is written by starch-config and is
# absent until the modifier has been changed, which means SUPER.
MOD=SUPER
if [[ -f ${XDG_CONFIG_HOME:-$HOME/.config}/hypr/keys.lua ]] &&
   grep -qE 'mod[[:space:]]*=[[:space:]]*"ALT"' \
        "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/keys.lua" 2>/dev/null; then
    MOD=ALT
fi

format_binds() {
    # Tab-separated: bind arguments routinely contain '|' (shell pipes inside
    # exec commands), which would corrupt any other delimiter.
    hyprctl -j binds | jq -r '
        .[]
        | [ (.modmask // 0 | tostring),
            (.key // ""),
            (.dispatcher // ""),
            (.arg // ""),
            (.submap // ""),
            (.description // "") ]
        | @tsv
    ' | awk -F'\t' '
        # Hyprland modmask bits: SHIFT 1, CAPS 2, CTRL 4, ALT 8, SUPER 64.
        {
            mask = $1 + 0
            keys = ""
            if (and(mask, 64)) keys = keys "SUPER + "
            if (and(mask,  8)) keys = keys "ALT + "
            if (and(mask,  4)) keys = keys "CTRL + "
            if (and(mask,  1)) keys = keys "SHIFT + "
            keys = keys $2

            # Prefer a human description when the config supplies one.
            if ($6 != "")      action = $6
            else if ($4 != "") action = $3 " " $4
            else               action = $3

            # A full exec line can run to hundreds of characters.
            if (length(action) > 66) action = substr(action, 1, 63) "..."

            # Submap binds only work inside that mode, so label them.
            printf "%s\t%s\t%s\n", $5, keys, action
        }' \
    | LC_ALL=C sort -t "$(printf '\t')" -k1,1 -k2,2 \
    | uniq \
    | awk -F'\t' -v mod="$MOD" '
        {
            if (!seen || $1 != last) {
                if (seen) print ""
                if ($1 == "")
                    print "── GLOBAL ───────────────────────────────────────────"
                else
                    print "── SUBMAP: " $1 "  (" mod "+R enters, Esc leaves) ─────"
                last = $1; seen = 1
            }
            printf "  %-28s  %s\n", $2, $3
        }'
}

if [[ ${1:-} == --print ]]; then
    format_binds
    exit 0
fi

format_binds | wofi --dmenu --prompt "Keybinds" --width 860 --height 660 \
                    --cache-file /dev/null --insensitive >/dev/null || true
