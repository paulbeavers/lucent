"""Windows — tiled, or every window floating.

The mode is floatall.lua's, which SUPER+SHIFT+V toggles. It is recorded in a
marker file, ~/.config/lucent/float-all, which this page reads back; Apply asks
the running compositor to switch, so open windows float or tile at once and the
key and the page never disagree.
"""

from .. import hypr, paths, readback
from ..widgets import Page, Row, switch


def _floating():
    return paths.FLOAT_ALL.exists()


def build(window):
    page = Page("Windows", "How windows are arranged on the screen.")
    key = readback.modifier()

    card = page.section("Arrangement")

    # Compared with the file as it is now: the key may have changed it since
    # the page was drawn, and after an Apply the page stays open.
    def on_float(value):
        if bool(value) == _floating():
            window.unstage("windows:float")
        else:
            window.stage("windows:float", lambda: _set_floating(value, key),
                         "windows " + ("float" if value else "tile"))

    card.add(Row(
        "Float every window",
        switch(_floating(), on_change=on_float),
        "On, every open window floats and so does every new one, like a "
        "stacking desktop. Off, they tile again. Dialogs and other windows a "
        f"rule floats stay floating either way. {key}+SHIFT+V switches it at "
        "any time, and this follows the key.",
    ))

    card.add(Row(
        "Moving a floating window",
        None,
        f"There are no title bars to drag: {key}+drag moves a window, "
        f"{key}+right-drag or its border resizes it.",
    ))

    page.note(
        "Applying takes effect at once, on every workspace, and is remembered "
        "across logins in ~/.config/lucent/float-all."
    )
    return page


def _set_floating(on, key):
    # Through the compositor rather than by writing the file, because the file
    # only decides new windows: floating or tiling the open ones is floatall.lua's
    # job, and it writes the file itself.
    if not hypr.available():
        raise RuntimeError("Hyprland is not running")
    lua = "true" if on else "false"
    mod = "ALT" if key == "ALT" else "SUPER"
    out = hypr.eval_lua(
        f'require("floatall").set({lua}, "{mod}") return "ok"'
    )
    if "ok" not in out or _floating() != on:
        raise RuntimeError(out or "Hyprland did not answer")
