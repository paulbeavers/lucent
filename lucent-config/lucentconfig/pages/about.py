"""About — versions, and where everything this app writes actually lives.

The second half matters more than the first. Every other page ends by saying
"applying rewrites such-and-such a file"; this is the one place that lists them
together, so it is possible to see at a glance what lucent-config owns and what
it will never touch.
"""

import platform
import subprocess

from .. import __version__, hypr, paths, readback
from ..widgets import Page, Row
from gi.repository import Gtk


def _version(command, args=("--version",)):
    try:
        out = subprocess.run(
            [command, *args], capture_output=True, text=True, timeout=5
        )
    except (OSError, subprocess.TimeoutExpired):
        return "not installed"
    text = (out.stdout or out.stderr).strip().splitlines()
    return text[0] if text else "unknown"


def _value(text, dim=False):
    label = Gtk.Label(label=text, xalign=1.0)
    label.add_css_class("sc-dim" if dim else "sc-row-title")
    label.set_selectable(True)
    return label


def build(window):
    page = Page("About", "What this is, and what it writes.")

    card = page.section("Versions")
    card.add(Row("lucent-config", _value(__version__)))
    card.add(Row("Hyprland", _value(_hyprland_version())))
    # The bar and the dock are Quickshell, which install.sh requires.
    card.add(Row("Quickshell", _value(_version("qs"))))
    card.add(Row("GTK", _value("%d.%d.%d" % (
        Gtk.get_major_version(), Gtk.get_minor_version(), Gtk.get_micro_version()))))
    card.add(Row("Kernel", _value(platform.release())))

    card = page.section("Files it writes")
    card.add(Row("Display", _value(_short(paths.MONITORS_LUA), dim=True),
                 "Rewritten whole. Previous version kept as .bak."))
    card.add(Row("Idle", _value(_short(paths.HYPRIDLE_CONF), dim=True),
                 "Rewritten whole. Previous version kept as .bak."))
    card.add(Row("Input", _value(_short(paths.SETTINGS_LUA), dim=True),
                 "Loaded after the rest of the config, so it wins. Delete it "
                 "to go back to the defaults."))
    card.add(Row("Modifier key", _value(_short(paths.KEYS_LUA), dim=True),
                 "Read by keybinds.lua before it binds anything. Delete it to "
                 "go back to Super."))
    card.add(Row("Lid", _value(str(readback.LID_CONF), dim=True),
                 "The only file outside your home directory. Needs a password."))
    card.add(Row("Show at login", _value(_short(paths.STATE), dim=True),
                 "This app's own record, of the one choice nothing else "
                 "holds. Absent until that switch is first touched."))
    card.add(Row("Dock", _value(_short(paths.DOCK_HIDDEN.parent) + "/dock-*",
                                dim=True),
                 "dock-hidden, which the page writes as the key does; "
                 "dock-mode and dock-position, through dock.sh."))
    card.add(Row("Windows", _value(_short(paths.FLOAT_ALL), dim=True),
                 "Written by floatall.lua, which the page asks to switch."))
    card.add(Row("Cursor and font size", _value("gsettings", dim=True),
                 "org.gnome.desktop.interface cursor-size and font-name; the "
                 "font's family is left to the theme."))

    card = page.section("Files it never touches")
    for name in ("hyprland.lua", "input.lua", "theme.lua", "keybinds.lua",
                 "rules.lua", "autostart.lua", "env.lua", "floatall.lua",
                 "programs.lua"):
        card.add(Row(name, _value("hand-written", dim=True)))
    for name in ("keyboard.lua", "gpu.lua"):
        card.add(Row(name, _value("written by install.sh", dim=True)))

    page.note(
        "Theme and wallpaper are not in either list: those are applied by "
        "hypr/scripts/theme.sh and wallpaper.sh, which this app calls rather "
        "than duplicates."
    )
    return page


def _short(path):
    try:
        return "~/" + str(path.relative_to(paths.HOME))
    except ValueError:
        return str(path)


def _hyprland_version():
    if not hypr.available():
        return "not running"
    try:
        first = hypr._run(["version"]).strip().splitlines()[0]
    except Exception:
        return "unknown"
    return first.replace("Hyprland ", "").split(" built")[0]
