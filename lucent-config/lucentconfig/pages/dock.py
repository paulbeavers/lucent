"""Dock — whether it shows at login, dock or panel, and bottom or top.

All three settings already have a home outside this app: dock.sh hides and
shows the dock (SUPER+D) and switches its style and edge, and records each in
a marker file that the shell reads at start. The page reads those files back
and drives that script, so the key and the page can never disagree about what
the dock will do.
"""

import subprocess

from .. import paths, readback
from ..widgets import Page, Row, dropdown, switch

MODES = [
    ("dock", "Dock"),
    ("panel", "Panel"),
]


POSITIONS = [
    ("bottom", "Bottom"),
    ("top", "Top"),
]


def _position():
    try:
        value = paths.DOCK_POSITION.read_text().strip()
    except OSError:
        return "bottom"
    return value if value in dict(POSITIONS) else "bottom"


def _mode():
    try:
        value = paths.DOCK_MODE.read_text().strip()
    except OSError:
        return "panel"   # the default, as the shell reads it: anything but "dock"
    return "dock" if value == "dock" else "panel"


def _shown_at_login():
    return not paths.DOCK_HIDDEN.exists()


def build(window):
    page = Page("Dock", "The row of apps along the edge of the screen.")
    key = readback.modifier()

    card = page.section("At login")
    login_now = _shown_at_login()

    # Compared with the file as it is now, not as it was when the page was
    # built: after an Apply the page stays open, and comparing with the old
    # value made changing it back look like no change at all.
    def on_login(value):
        if bool(value) == _shown_at_login():
            window.unstage("dock:login")
        else:
            window.stage("dock:login", lambda: _set_login(value),
                         "dock " + ("shown" if value else "hidden") + " at login")

    card.add(Row(
        "Show the dock at login",
        switch(login_now, on_change=on_login),
        f"{key}+D hides and shows it at any time, and that choice is remembered "
        "too, so this switch follows the key.",
    ))

    card = page.section("Style")
    mode_now = _mode()
    slugs = [slug for slug, _ in MODES]

    def on_mode(index):
        if not 0 <= index < len(MODES):
            return
        chosen = slugs[index]
        if chosen == _mode():
            window.unstage("dock:mode")
        else:
            window.stage("dock:mode", lambda: _set_mode(chosen),
                         f"dock style → {dict(MODES)[chosen].lower()}")

    card.add(Row(
        "Style",
        dropdown([name for _, name in MODES], slugs.index(mode_now), on_change=on_mode),
        "Panel, the default, is one strip along the edge chosen below, with "
        "the dock, the workspaces, the date and time and the rest of the top "
        "bar's items, and the top bar goes away. Dock keeps the bar at the "
        "top and floats the dock, centred, at that edge.",
    ))

    edges = [slug for slug, _ in POSITIONS]

    def on_position(index):
        if not 0 <= index < len(POSITIONS):
            return
        chosen = edges[index]
        if chosen == _position():
            window.unstage("dock:position")
        else:
            window.stage("dock:position", lambda: _set_position(chosen),
                         f"dock position → {dict(POSITIONS)[chosen].lower()}")

    card.add(Row(
        "Position",
        dropdown([name for _, name in POSITIONS], edges.index(_position()),
                 on_change=on_position),
        "The bottom or the top of the screen, for the dock and the panel "
        "alike.",
    ))

    page.note(
        "Style and position take effect at once when applied: the bar and "
        "the dock restart. Showing at login takes effect at the next login. "
        "The settings are files in ~/.config/lucent — dock-hidden, dock-mode "
        "and dock-position."
    )
    return page


def _set_login(show):
    # The same file SUPER+D writes. Only the record changes: a dock that is
    # running stays up, and one that is hidden stays hidden, until the key or
    # the next login.
    if show:
        paths.DOCK_HIDDEN.unlink(missing_ok=True)
    else:
        paths.DOCK_HIDDEN.parent.mkdir(parents=True, exist_ok=True)
        paths.DOCK_HIDDEN.touch()


def _set_mode(mode):
    _dock_sh("--mode", mode)


def _set_position(edge):
    _dock_sh("--position", edge)


def _dock_sh(*args):
    try:
        result = subprocess.run([str(paths.DOCK_SH), *args],
                                capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise RuntimeError(f"dock.sh did not run: {exc}") from exc
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "dock.sh failed")
