#!/usr/bin/env bash
# The terminal every keybind and bar button opens.
#
#     terminal.sh [--class NAME] [-e] [COMMAND [ARGS...]]
#
# foot. --class sets the window class the rules match on; foot calls it
# --app-id. -e is accepted for callers that pass it, and dropped: foot takes the
# command as its remaining arguments.
set -u

args=()
if [[ ${1:-} == --class ]]; then
    args+=(--app-id="${2:-}")
    shift 2
fi
[[ ${1:-} == -e ]] && shift

exec foot "${args[@]}" "$@"
