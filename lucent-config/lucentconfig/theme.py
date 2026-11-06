"""Load the stylesheet, with the live palette in front of it.

theme.sh already renders the active theme to ~/.config/lucent/colors.css as a
list of @define-color declarations, for the bar and the dock. Rather than teach
it about another consumer, we read that file and paste it on top of our own
stylesheet — so the app is themed by whatever the desktop is themed by, and
SUPER+SHIFT+T changes both.
"""

import re
from pathlib import Path

from gi.repository import Gdk, Gio, Gtk

from . import paths

# Used when colors.css is missing, which is the case on live media and on any
# machine where theme.sh has not run yet. Plain Catppuccin Mocha: install.sh's
# default theme, catppuccin-mocha-blue-contrast, is a variant of it, so the app
# looks close to right rather than unstyled.
FALLBACK = """
@define-color crust     #11111b;
@define-color mantle    #181825;
@define-color base      #1e1e2e;
@define-color surface0  #313244;
@define-color surface1  #45475a;
@define-color overlay   #6c7086;
@define-color subtext   #a6adc8;
@define-color text      #cdd6f4;
@define-color rosewater #f5e0dc;
@define-color red       #f38ba8;
@define-color peach     #fab387;
@define-color yellow    #f9e2af;
@define-color green     #a6e3a1;
@define-color teal      #94e2d5;
@define-color sapphire  #74c7ec;
@define-color blue      #89b4fa;
@define-color lavender  #b4befe;
@define-color mauve     #cba6f7;
@define-color pink      #f5c2e7;
"""


def palette_css() -> str:
    try:
        text = paths.COLORS_CSS.read_text()
    except OSError:
        return FALLBACK
    # A colors.css that somehow defines nothing would leave every colour
    # undefined and GTK would drop the rules that use them, so check.
    return text if "@define-color" in text else FALLBACK


def font_css() -> str:
    """The theme's font family: ~/.config/lucent/font.css, which theme.sh renders.

    It goes after style.css, so its `* { font-family }` wins over the one
    there, which stays as what this app uses when the file is missing. A
    theme that names no font gets JetBrainsMono Nerd Font in it, the same
    as style.css, so only a theme such as Adwaita Light changes anything.
    """
    try:
        text = paths.FONT_CSS.read_text()
    except OSError:
        return ""
    return text if "font-family" in text else ""


def _css() -> str:
    return (palette_css() + "\n" + (Path(__file__).parent / "style.css").read_text()
            + "\n" + font_css())


def is_light(palette: str) -> bool:
    """Does this palette put dark text on a light background?

    It matters because translucency is not symmetric. A dark @base at 60% over
    a wallpaper still reads as dark, and light text stays legible. A light
    @base at 60% over the same wallpaper turns grey, and the dark text on it
    disappears — which is exactly how Catppuccin Latte broke twice. So the
    stylesheet carries both sets of alphas and app.py gives the window an
    `sc-light` class to pick between them.

    Decided from @base rather than a `mode` key because colors.css is the only
    file we read, and every palette has to define @base.
    """
    match = re.search(r"@define-color\s+base\s+#([0-9a-fA-F]{6})", palette)
    if not match:
        return False
    r, g, b = (int(match.group(1)[i : i + 2], 16) for i in (0, 2, 4))
    # Rec. 601 luma. Precision is not the point; which side of the middle is.
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.5


class Theme:
    """The stylesheet, kept in step with the desktop's theme.

    SUPER+SHIFT+T rewrites colors.css and tells the bar and mako to
    pick it up. An app that only read the palette at startup would sit there in
    the old colours until it was restarted, which is exactly the kind of small
    wrongness that makes something feel bolted on. So we watch the file.

    The watch is on the *directory*, not the file: theme.sh renders to a
    temporary file and moves it into place, and a monitor attached to the old
    inode stops hearing about anything after the first switch.
    """

    def __init__(self, display: Gdk.Display):
        self.on_change = None
        self.light = is_light(palette_css())
        self.provider = Gtk.CssProvider()
        self.provider.load_from_string(_css())
        Gtk.StyleContext.add_provider_for_display(
            display, self.provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )
        self._monitor = self._watch()

    def _watch(self):
        try:
            directory = Gio.File.new_for_path(str(paths.COLORS_CSS.parent))
            monitor = directory.monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, None)
        except Exception:
            return None  # no inotify is a reason to not follow along, not to fail
        monitor.connect("changed", self._on_change)
        return monitor

    def _on_change(self, _monitor, file, other, event):
        names = {f.get_basename() for f in (file, other) if f is not None}
        # theme.sh writes the palette and then the font; either one changing
        # is a reason to read both again.
        if not names & {paths.COLORS_CSS.name, paths.FONT_CSS.name}:
            return
        if event in (
            Gio.FileMonitorEvent.CHANGES_DONE_HINT,
            Gio.FileMonitorEvent.CREATED,
            Gio.FileMonitorEvent.MOVED_IN,
            Gio.FileMonitorEvent.RENAMED,
        ):
            self.reload()

    def reload(self):
        try:
            self.light = is_light(palette_css())
            self.provider.load_from_string(_css())
        except Exception:
            return  # a half-written palette is transient; the next event wins
        if self.on_change:
            self.on_change()


def load(display: Gdk.Display) -> Theme:
    """Apply the stylesheet to `display` and keep it following the theme."""
    return Theme(display)
