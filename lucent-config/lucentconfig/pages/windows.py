"""Windows — which workspaces tile and which float.

The setting is floatall.lua's floating workspaces; SUPER+SHIFT+V toggles the
workspace in front of you. It is recorded in ~/.config/lucent/float-workspaces,
one workspace name per line, which this page reads back; Apply asks the running
compositor to switch, so open windows float or tile at once and the key and the
page never disagree.
"""

from .. import hypr, paths, readback
from ..widgets import Page, Row, switch

# The workspaces the keys reach. Others in the file (a named workspace someone
# floated with the key) are kept as they are: the page only shows these.
WORKSPACES = [str(i) for i in range(1, 11)]


def _floating():
    """The names of the workspaces that float, as floatall.lua reads them."""
    try:
        text = paths.FLOAT_WORKSPACES.read_text()
    except FileNotFoundError:
        # The older all-or-nothing marker floated every workspace, and
        # floatall.lua reads it as 1-10 until the first change replaces it.
        return set(WORKSPACES) if paths.FLOAT_ALL.exists() else set()
    except OSError:
        return set()
    return {line.strip() for line in text.splitlines() if line.strip()}


def build(window):
    page = Page("Windows", "How windows are arranged on the screen.")
    key = readback.modifier()

    # Only what was touched on this page, laid over the file as it is when
    # compared or applied: the key may change other workspaces meanwhile, and
    # after an Apply the page stays open.
    touched = {}

    def on_switch(name, value):
        touched[name] = bool(value)
        current = _floating()
        if all((n in current) == on for n, on in touched.items()):
            window.unstage("windows:float")
            return
        want = _wanted(touched)
        window.stage("windows:float", lambda: _apply(dict(touched), key),
                     "windows: " + (_describe(want) if want else "every workspace tiles"))

    card = page.section("Floating workspaces")
    card.add(Row(
        "How it works",
        None,
        "On a floating workspace every window floats, and so does every one "
        "that opens there or is moved there, like a stacking desktop. The rest "
        "tile. Dialogs and other windows a rule floats stay floating either "
        f"way. {key}+SHIFT+V switches the workspace in front of you, and this "
        "follows the key.",
    ))
    floating = _floating()
    for name in WORKSPACES:
        card.add(Row(
            f"Workspace {name}",
            switch(name in floating, on_change=lambda v, n=name: on_switch(n, v)),
        ))

    card = page.section("Moving a floating window")
    card.add(Row(
        "No title bars",
        None,
        f"There are no title bars to drag: {key}+drag moves a window, "
        f"{key}+right-drag or its border resizes it.",
    ))

    page.note(
        "Applying takes effect at once, and is remembered across logins in "
        "~/.config/lucent/float-workspaces."
    )
    return page


def _wanted(touched):
    want = _floating()
    for name, on in touched.items():
        if on:
            want.add(name)
        else:
            want.discard(name)
    return want


def _sort_key(name):
    return (0, int(name), "") if name.isdigit() else (1, 0, name)


def _describe(names):
    return "float " + ", ".join(sorted(names, key=_sort_key))


def _lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def _apply(touched, key):
    # Through the compositor rather than by writing the file, because the file
    # only decides new windows: floating or tiling the open ones is floatall.lua's
    # job, and it writes the file itself.
    if not hypr.available():
        raise RuntimeError("Hyprland is not running")
    want = _wanted(touched)
    names = ", ".join(_lua_string(n) for n in sorted(want, key=_sort_key))
    mod = "ALT" if key == "ALT" else "SUPER"
    out = hypr.eval_lua(
        f'require("floatall").set_workspaces({{ {names} }}, "{mod}") return "ok"'
    )
    if "ok" not in out or _floating() != want:
        raise RuntimeError(out or "Hyprland did not answer")
