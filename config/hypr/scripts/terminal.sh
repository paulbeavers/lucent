#!/usr/bin/env bash
# The terminal every keybind and bar button opens.
#
#     terminal.sh [--class NAME] [-e] [COMMAND [ARGS...]]
#
# kitty, unless it cannot run, and then foot. kitty draws with OpenGL 3.3 and
# exits if it cannot get a context; under VMware Fusion it showed a grey window
# and was gone, with 3D acceleration on. foot draws on the CPU, so a broken
# graphics stack cannot keep it from opening — and without a terminal there is
# no way left to fix anything from inside the session.
#
# foot is used outright on VMware, where kitty is known not to start, and as a
# fallback anywhere kitty fails within a few seconds of launch. A fallback
# leaves a line and kitty's error in /tmp/terminal.log, because a grey flash
# leaves no other trace.
#
# --class is kitty's spelling; foot calls it --app-id. foot takes no -e.
set -u

class=""
if [[ ${1:-} == --class ]]; then
    class="${2:-}"
    shift 2
fi
[[ ${1:-} == -e ]] && shift

LOG=/tmp/terminal.log

run_foot() {
    local args=()
    [[ -n $class ]] && args+=(--app-id="$class")
    exec foot "${args[@]}" "$@"
}

command -v kitty >/dev/null || run_foot "$@"
if command -v foot >/dev/null &&
   [[ "$(systemd-detect-virt 2>/dev/null || true)" == vmware ]]; then
    run_foot "$@"
fi

args=()
[[ -n $class ]] && args+=(--class "$class")
[[ $# -gt 0 ]] && args+=(-e "$@")

err="$(mktemp)"
start=$SECONDS
kitty "${args[@]}" 2>"$err"
rc=$?
if [[ $rc -ne 0 ]] && (( SECONDS - start < 3 )) && command -v foot >/dev/null; then
    {
        echo "$(date '+%F %T') kitty exited $rc at launch, opening foot"
        tail -n 20 "$err"
    } >> "$LOG"
    rm -f "$err"
    run_foot "$@"
fi
rm -f "$err"
exit $rc
