"""Dock — whether it shows at login, and whether it is a dock or a panel.

Both settings already have a home outside this app: dock.sh hides and shows
the dock (SUPER+D) and switches its mode, and records each in a marker file
that the login reads. The page reads those files back and drives that script,
so the key and the page can never disagree about what the dock will do.
"""

import subprocess

from .. import paths, readback
from ..widgets import Page, Row, dropdown, switch

MODES = [
    ("dock", "Dock"),
    ("panel", "Panel"),
]


def _mode():
    try:
        value = paths.DOCK_MODE.read_text().strip()
    except OSError:
        return "dock"
    return value if value in dict(MODES) else "dock"


def _shown_at_login():
    return not paths.DOCK_HIDDEN.exists()


def build(window):
    page = Page("Dock", "The apps along the bottom of the screen.")
    key = readback.modifier()

    card = page.section("At login")
    login_now = _shown_at_login()

    def on_login(value):
        if bool(value) == login_now:
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
        if chosen == mode_now:
            window.unstage("dock:mode")
        else:
            window.stage("dock:mode", lambda: _set_mode(chosen),
                         f"dock style → {dict(MODES)[chosen].lower()}")

    card.add(Row(
        "Style",
        dropdown([name for _, name in MODES], slugs.index(mode_now), on_change=on_mode),
        "Dock floats at the bottom, centred, under the bar at the top. Panel is "
        "one strip across the bottom with the dock, the workspaces, the date and "
        "time and the rest of the top bar's items, and the top bar goes away.",
    ))

    page.note(
        "Applying takes effect at once: the bar and the dock restart. Both "
        "settings are files in ~/.config/lucent — dock-hidden and dock-mode."
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
    try:
        result = subprocess.run([str(paths.DOCK_SH), "--mode", mode],
                                capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise RuntimeError(f"dock.sh did not run: {exc}") from exc
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "dock.sh failed")
