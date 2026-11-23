"""Dock — whether it shows at login, dock or panel, bottom or top, which apps
it lists, and whether it hides itself.

Every setting already has a home outside this app: dock.sh hides and shows
the dock (SUPER+D) and switches its style, edge, scope and auto-hide, and
records each in a marker file that the shell reads at start. The page reads those files back
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


SCOPES = [
    ("all", "All workspaces"),
    ("workspace", "This workspace only"),
]


def _scope():
    try:
        value = paths.DOCK_SCOPE.read_text().strip()
    except OSError:
        return "all"
    return "workspace" if value == "workspace" else "all"


def _autohide():
    try:
        return paths.DOCK_AUTOHIDE.read_text().strip() == "on"
    except OSError:
        return False


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

    card = page.section("Behaviour")
    scopes = [slug for slug, _ in SCOPES]

    def on_scope(index):
        if not 0 <= index < len(SCOPES):
            return
        chosen = scopes[index]
        if chosen == _scope():
            window.unstage("dock:scope")
        else:
            window.stage("dock:scope", lambda: _dock_sh("--scope", chosen),
                         f"dock shows → {dict(SCOPES)[chosen].lower()}")

    card.add(Row(
        "Apps shown",
        dropdown([name for _, name in SCOPES], scopes.index(_scope()),
                 on_change=on_scope),
        "This workspace only lists the apps with a window on the workspace in "
        "front of you, and a click on one with none there opens a new window "
        "here. Pinned apps and minimized windows show either way.",
    ))

    def on_autohide(value):
        if bool(value) == _autohide():
            window.unstage("dock:autohide")
        else:
            window.stage("dock:autohide",
                         lambda: _dock_sh("--autohide", "on" if value else "off"),
                         "dock auto-hide " + ("on" if value else "off"))

    card.add(Row(
        "Hide automatically",
        switch(_autohide(), on_change=on_autohide),
        "Slides off the edge and gives windows its space, and comes back when "
        "the pointer reaches that edge. In panel style the whole panel hides, "
        "since the dock is part of it.",
    ))

    card = page.section("Using it")
    card.add(Row(
        "Scroll",
        None,
        "Over an app, its next or previous window. Anywhere else on the "
        "dock, the next or previous workspace.",
    ))
    card.add(Row(
        "Drag",
        None,
        "Drag a pinned app to reorder, or off the dock to unpin it. Drag a "
        "running app in among the pinned ones to pin it there.",
    ))
    card.add(Row(
        "Minimize",
        None,
        f"{key}+M minimizes the window in front of you; it waits after the "
        f"separator until a click brings it back here. {key}+CTRL+M brings "
        "back the last one.",
    ))

    page.note(
        "Style, position, apps shown and hiding take effect at once when "
        "applied: the bar and the dock restart. Showing at login takes effect "
        "at the next login. The settings are files in ~/.config/lucent — "
        "dock-hidden, dock-mode, dock-position, dock-scope and dock-autohide."
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
