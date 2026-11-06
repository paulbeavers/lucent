"""Talking to the running compositor.

Everything goes through hyprctl rather than the socket directly: it is one
subprocess for a settings app that changes something twice a minute, and it
keeps us out of the business of locating instance signatures.

Note the dispatch form. With a Lua config Hyprland evaluates whatever follows
`dispatch` as Lua, so the old `hyprctl dispatch dpms off` is a syntax error that
fails silently. Anything this app sends is Lua.
"""

import json
import subprocess


class NotRunning(Exception):
    """No compositor answered. The app still works; live preview does not."""


def _run(args, *, check=True):
    try:
        out = subprocess.run(
            ["hyprctl", *args], capture_output=True, text=True, timeout=5
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise NotRunning(str(exc)) from exc
    if check and out.returncode != 0:
        raise NotRunning(out.stderr.strip() or "hyprctl failed")
    return out.stdout


def available() -> bool:
    try:
        _run(["version"])
        return True
    except NotRunning:
        return False


def query(*what):
    """A -j query, parsed. `what` is e.g. ("monitors",) or ("monitors", "all")."""
    return json.loads(_run([*what, "-j"]))


def monitors():
    """Connected outputs, each with the modes it advertises."""
    # "all" includes outputs that are connected but currently disabled, which
    # is the difference between a laptop with the lid shut showing one screen
    # and showing none.
    for args in (("monitors", "all"), ("monitors",)):
        try:
            return query(*args)
        except (NotRunning, json.JSONDecodeError):
            continue
    return []


def eval_lua(expr: str) -> str:
    """Evaluate Lua in the compositor. Used to preview a change instantly."""
    return _run(["repl", expr], check=False).strip()


def _ok(args, what: str) -> str:
    """Run a hyprctl command that answers "ok", and raise if it did not.

    hyprctl can exit 0 with an error as its whole reply — a Lua dispatch that
    fails to evaluate is the usual case — so the exit status alone would let
    Apply say "Applied." over a change that never happened. An empty reply is
    let through: it says nothing either way, and calling it a failure would
    only be a guess. A non-zero exit is still NotRunning, which callers that
    can do without a compositor catch; an error reply is a RuntimeError, as
    every other failed apply step is, and the footer names it.
    """
    reply = _run(args).strip()
    if reply and reply != "ok":
        raise RuntimeError(f"{what}: {reply}")
    return reply


def reload() -> str:
    return _ok(["reload"], "hyprctl reload")


def center_window(pid: int) -> str:
    """Centre the floating window belonging to `pid` on its monitor.

    keybinds.lua's Centre window bind calls hl.dsp.window.center() with no
    argument, which acts on the active window. The `window` selector here is
    the one hl.dsp.focus and hl.dsp.window.close take in lucent-shell's
    Hypr.qml, with a pid: rather than an address: target. rules.lua floats
    this app, which is what centring is for; whatever Hyprland answers other
    than "ok" is reported by Apply rather than dropped.
    """
    return _ok(
        ["dispatch", f'hl.dsp.window.center({{ window = "pid:{pid}" }})'],
        "centring the window",
    )


def get_option(name: str):
    """Read one config value from the running compositor.

    hyprctl reports the type alongside the value, which is how we know whether
    "false" means the boolean or the string. Returns None if the compositor is
    not there or does not know the option.
    """
    try:
        data = json.loads(_run(["getoption", name, "-j"], check=False))
    except (NotRunning, json.JSONDecodeError):
        return None
    for key in ("int", "bool", "float", "str"):
        if key in data:
            return data[key]
    return None


def has_touchpad() -> bool:
    try:
        devices = query("devices")
    except (NotRunning, json.JSONDecodeError):
        return False
    return any(
        "touchpad" in (m.get("name") or "").lower()
        for m in devices.get("mice", [])
    )
