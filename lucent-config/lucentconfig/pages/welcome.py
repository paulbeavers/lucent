"""Welcome — the page the desktop opens on first login.

It exists to do two things and then get out of the way: say what this app is,
and offer to stop appearing. A first-run screen that cannot be dismissed
permanently is a nuisance rather than a welcome.
"""

from gi.repository import Gtk

from .. import hypr, readback, state
from ..widgets import Page, Row, switch

INTRO = (
    "Everything here writes a plain file you can read, edit or delete. "
    "Nothing runs in the background to keep it that way."
)

TOUR = [
    ("\U000f0369", "Display",
     "Resolution, refresh rate, and a scale menu that only offers the values "
     "your screen can actually use."),
    ("\U000f04b2", "Idle",
     "When the screen dims, blanks and locks, when the machine suspends, and "
     "what closing the lid does."),
    ("\U000f030c", "Input",
     "Keyboard layout, what Caps Lock does, key repeat, and the touchpad."),
    ("\U000f03d8", "Look",
     "Theme, wallpaper, cursor and font size. The theme applies everywhere at "
     "once, including this window."),
    ("\U000f10a9", "Dock",
     "Whether the dock shows at login, and whether it floats or is a panel "
     "across the bottom that takes the top bar's place."),
]


def build(window):
    page = Page("Welcome", INTRO)

    card = page.section("What is here")
    for icon, name, what in TOUR:
        row = Row(name, subtitle=what)
        glyph = Gtk.Label(label=icon)
        glyph.add_css_class("sc-nav-icon")
        glyph.set_valign(Gtk.Align.CENTER)
        row.prepend(glyph)
        card.add(row)

    card = page.section("At login")
    card.add(Row(
        "Show this at login",
        switch(state.get("show_at_login"), on_change=_set_show_at_login),
        "Turn this off and lucent-config stays out of the way until you open "
        f"it yourself, with {readback.modifier()}+I.",
    ))

    if not hypr.available():
        page.note("No compositor answered, so the other pages have nothing to "
                  "read. Start Hyprland and reopen lucent-config.")
    return page


def _set_show_at_login(value):
    # Written immediately rather than staged with the rest. The footer's Apply
    # is about changing the machine; this is about whether a window opens, and
    # making someone press Apply to dismiss a greeter is the opposite of the
    # point.
    state.set("show_at_login", bool(value))

