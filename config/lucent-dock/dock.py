#!/usr/bin/env python3
"""lucent-dock — the dock along the bottom of the screen.

One icon per app, not per window: the pinned apps first, then anything else
that is open. Dots under an icon count its windows; the focused app is lit.

    left click     open the app, or focus its window; again cycles its windows
    middle click   a new window
    right click    its windows, New window, Pin / Unpin, Close

Started by hypr/scripts/dock.sh, which SUPER+D runs to hide and show it.

Why lucent has its own: the docks in Arch's repositories (nwg-dock-hyprland,
cairo-dock) load icons as bitmaps at the logical size, so on a fractionally
scaled panel every icon is stretched and soft. GTK 4 draws at the output's
real scale, so these are sharp — judged on a 1.33 panel, which is the case a
VM never shows.

Hyprland is read and driven through its IPC sockets: j/clients for the
windows, the event socket for when to look again, and Lua dispatches, because
lucent's Hyprland is configured in Lua and evaluates everything after
`dispatch` as Lua.

The pinned apps are ~/.config/lucent/dock-pinned, one desktop file ID per
line, in order. The colours are waybar's colors.css, which theme.sh rewrites
on every theme switch; the dock watches it and restyles.
"""

import os
import sys


# gtk4-layer-shell has to be loaded before libwayland-client, which for a
# Python program means LD_PRELOAD, so the dock re-executes itself with it set.
def _preload_layer_shell():
    if "libgtk4-layer-shell" in os.environ.get("LD_PRELOAD", ""):
        return
    for lib in ("/usr/lib/libgtk4-layer-shell.so.0",
                "/usr/lib64/libgtk4-layer-shell.so.0",
                "/usr/lib/x86_64-linux-gnu/libgtk4-layer-shell.so.0",
                "/usr/lib/aarch64-linux-gnu/libgtk4-layer-shell.so.0"):
        if os.path.exists(lib):
            env = dict(os.environ, LD_PRELOAD=lib)
            os.execve(sys.executable, [sys.executable] + sys.argv, env)
    sys.exit("lucent-dock: gtk4-layer-shell is not installed")


_preload_layer_shell()
# And take it straight back out, or every app the dock launches inherits it.
os.environ.pop("LD_PRELOAD", None)

import ctypes  # noqa: E402
import json  # noqa: E402
import socket  # noqa: E402
import subprocess  # noqa: E402
import threading  # noqa: E402
from pathlib import Path  # noqa: E402

import gi  # noqa: E402

gi.require_version("Gdk", "4.0")
gi.require_version("Gtk", "4.0")
gi.require_version("Gtk4LayerShell", "1.0")
from gi.repository import Gdk, Gio, GLib, Gtk  # noqa: E402
from gi.repository import Gtk4LayerShell as LayerShell  # noqa: E402

# GLib 2.86 moved DesktopAppInfo to GioUnix and deprecated the Gio name.
try:
    gi.require_version("GioUnix", "2.0")
    from gi.repository import GioUnix  # noqa: E402
    DesktopAppInfo = GioUnix.DesktopAppInfo
except (ValueError, ImportError):
    DesktopAppInfo = Gio.DesktopAppInfo

ICON_SIZE = 40
MAX_DOTS = 3
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
PINNED = CONFIG / "lucent" / "dock-pinned"
MODE = CONFIG / "lucent" / "dock-mode"      # "dock" (the default) or "panel"
PANEL_HEIGHT = 58                           # waybar/panel.jsonc's height
DEFAULT_PINNED = ["firefox.desktop", "thunar.desktop", "foot.desktop"]
STYLE = Path(__file__).resolve().parent / "style.css"
COLORS = CONFIG / "waybar" / "colors.css"
LAUNCHER = ["wofi", "--show", "drun"]

# Events after which the windows are worth reading again.
EVENTS = {"openwindow", "closewindow", "activewindowv2", "movewindowv2",
          "windowtitlev2", "urgent"}


# ── Hyprland ──────────────────────────────────────────────────────────────────

def _socket_path(name):
    return os.path.join(os.environ["XDG_RUNTIME_DIR"], "hypr",
                        os.environ["HYPRLAND_INSTANCE_SIGNATURE"], name)


def hypr(request):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(_socket_path(".socket.sock"))
        s.sendall(request.encode())
        chunks = []
        while chunk := s.recv(65536):
            chunks.append(chunk)
    return b"".join(chunks).decode(errors="replace")


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def dispatch(lua):
    try:
        hypr("dispatch " + lua)
    except OSError:
        pass


def focus(address):
    dispatch(f"hl.dsp.focus({{ window = {lua_string('address:' + address)} }})")


def close(address):
    dispatch(f"hl.dsp.window.close({{ window = {lua_string('address:' + address)} }})")


def windows():
    """Mapped windows outside the scratchpad, oldest first."""
    try:
        clients = json.loads(hypr("j/clients"))
    except (OSError, ValueError):
        return []
    return [c for c in clients
            if c.get("mapped", True)
            and not str(c.get("workspace", {}).get("name", "")).startswith("special")
            and (c.get("class") or c.get("initialClass"))]


def active_address():
    try:
        return json.loads(hypr("j/activewindow")).get("address")
    except (OSError, ValueError):
        return None


def watch_events(on_event):
    """Read the event socket on a thread; call on_event on the main loop."""
    def run():
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
                s.connect(_socket_path(".socket2.sock"))
                for line in s.makefile("r", errors="replace"):
                    if line.split(">>", 1)[0] in EVENTS:
                        GLib.idle_add(on_event)
        except OSError:
            pass
        # The compositor has gone; so should the dock.
        GLib.idle_add(Gio.Application.get_default().quit)
    threading.Thread(target=run, daemon=True).start()


# ── apps ──────────────────────────────────────────────────────────────────────

_app_cache = {}


def app_for_class(cls):
    """The desktop entry a window class belongs to, or None."""
    key = cls.lower()
    if key in _app_cache:
        return _app_cache[key]
    found = None
    for candidate in (cls, key, key.rsplit(".", 1)[-1]):
        try:
            found = DesktopAppInfo.new(candidate + ".desktop")
        except TypeError:
            found = None
        if found:
            break
    if not found:
        for info in Gio.AppInfo.get_all():
            wm = info.get_startup_wm_class() if hasattr(info, "get_startup_wm_class") else None
            if wm and wm.lower() == key:
                found = info
                break
    _app_cache[key] = found
    return found


def app_by_id(desktop_id):
    try:
        return DesktopAppInfo.new(desktop_id)
    except TypeError:
        return None


def panel_mode():
    try:
        return MODE.read_text().strip() == "panel"
    except OSError:
        return False


def load_pinned():
    try:
        lines = PINNED.read_text().split()
    except OSError:
        return list(DEFAULT_PINNED)
    return [line for line in lines if line]


def save_pinned(ids):
    PINNED.parent.mkdir(parents=True, exist_ok=True)
    tmp = PINNED.with_suffix(".tmp")
    tmp.write_text("".join(i + "\n" for i in ids))
    tmp.replace(PINNED)


class App:
    """One icon: an app, pinned or not, with whatever windows it has open."""

    def __init__(self, key, info, cls=None):
        self.key = key            # desktop ID, or "class:<wm class>" without one
        self.info = info
        self.cls = cls
        self.windows = []

    @property
    def name(self):
        if self.info:
            return self.info.get_display_name()
        return self.cls or self.key

    @property
    def icon(self):
        if self.info and self.info.get_icon():
            return self.info.get_icon()
        names = [self.cls.lower()] if self.cls else []
        return Gio.ThemedIcon.new_from_names(names + ["application-x-executable"])


# ── the dock ──────────────────────────────────────────────────────────────────

class Dock(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="dev.lucent.dock",
                         flags=Gio.ApplicationFlags.DEFAULT_FLAGS)
        self.pinned = load_pinned()
        self.order = []           # keys of unpinned running apps, first seen first
        self.apps = {}
        self.menu_open = False
        self.pending = False

    # set-up

    def do_activate(self):
        if getattr(self, "win", None):
            return
        self.win = Gtk.ApplicationWindow(application=self)
        self.win.add_css_class("dock")
        LayerShell.init_for_window(self.win)
        LayerShell.set_namespace(self.win, "lucent-dock")
        LayerShell.set_layer(self.win, LayerShell.Layer.TOP)
        LayerShell.set_anchor(self.win, LayerShell.Edge.BOTTOM, True)
        if panel_mode():
            # Inside the panel: waybar draws the strip and reserves the space,
            # so the dock takes none and ignores waybar's (-1), or the
            # compositor would stack it above the panel instead of in it. Its
            # own slab is dropped by the .panel class in style.css.
            self.win.add_css_class("panel")
            LayerShell.set_exclusive_zone(self.win, -1)
            LayerShell.set_margin(self.win, LayerShell.Edge.BOTTOM, 0)
            self.win.set_size_request(-1, PANEL_HEIGHT)
        else:
            LayerShell.set_margin(self.win, LayerShell.Edge.BOTTOM, 6)
            LayerShell.auto_exclusive_zone_enable(self.win)
        # The menus are popovers; on-demand lets them take the keyboard
        # while open without the dock ever holding it otherwise.
        LayerShell.set_keyboard_mode(self.win, LayerShell.KeyboardMode.ON_DEMAND)

        self.box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=2)
        self.box.add_css_class("dock-box")
        self.box.set_valign(Gtk.Align.CENTER)
        self.win.set_child(self.box)

        self._install_actions()
        self._load_style()
        self._watch_colors()
        watch_events(self.schedule_refresh)
        self.refresh()
        self.win.present()

    def _install_actions(self):
        group = Gio.SimpleActionGroup()
        for name, handler in (("focus", lambda a: focus(a)),
                              ("launch", self.launch),
                              ("pin", self.pin),
                              ("unpin", self.unpin),
                              ("close", self.close_all)):
            action = Gio.SimpleAction.new(name, GLib.VariantType.new("s"))
            action.connect("activate", lambda _a, v, h=handler: h(v.get_string()))
            group.add_action(action)
        self.win.insert_action_group("dock", group)

    def _load_style(self):
        if not hasattr(self, "css"):
            self.css = Gtk.CssProvider()
            Gtk.StyleContext.add_provider_for_display(
                Gdk.Display.get_default(), self.css,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        try:
            self.css.load_from_path(str(STYLE))
        except GLib.Error:
            pass

    def _watch_colors(self):
        # theme.sh replaces colors.css by rename, so watch the directory and
        # pick the file out, rather than the file, whose monitor would follow
        # the old inode.
        self.monitor = Gio.File.new_for_path(str(COLORS.parent)).monitor_directory(
            Gio.FileMonitorFlags.WATCH_MOVES, None)

        def changed(_m, file, other, _event):
            names = {f.get_basename() for f in (file, other) if f}
            if COLORS.name in names:
                GLib.timeout_add(100, lambda: self._load_style() or False)
        self.monitor.connect("changed", changed)

    # model

    def schedule_refresh(self):
        # Events arrive in bursts (a window opening is four or five); one
        # read of the windows covers the lot.
        if not self.pending:
            self.pending = True
            GLib.timeout_add(40, self._refresh_now)
        return False

    def _refresh_now(self):
        self.pending = False
        if not self.menu_open:    # rebuilding would close an open menu
            self.refresh()
        return False

    def refresh(self):
        apps = {}
        for desktop_id in self.pinned:
            info = app_by_id(desktop_id)
            if info:
                apps[desktop_id] = App(desktop_id, info)

        for w in windows():
            cls = w.get("class") or w.get("initialClass")
            info = app_for_class(cls)
            key = info.get_id() if info else "class:" + cls.lower()
            if key not in apps:
                apps[key] = App(key, info, cls)
                if key not in self.order and key not in self.pinned:
                    self.order.append(key)
            apps[key].cls = apps[key].cls or cls
            apps[key].windows.append(w)

        self.order = [k for k in self.order if k in apps and k not in self.pinned]
        self.apps = apps
        self.active = active_address()
        self._rebuild([k for k in self.pinned if k in apps] + self.order)

    # view

    def _rebuild(self, keys):
        while child := self.box.get_first_child():
            self.box.remove(child)

        for key in keys:
            self.box.append(self._button(self.apps[key]))

        sep = Gtk.Separator(orientation=Gtk.Orientation.VERTICAL)
        sep.add_css_class("dock-sep")
        self.box.append(sep)

        grid = Gtk.Button()
        grid.add_css_class("dock-app")
        grid.add_css_class("launcher")
        grid.set_tooltip_text("All apps")
        grid.set_child(self._icon_column(
            Gio.ThemedIcon.new_from_names(["view-app-grid-symbolic", "view-grid-symbolic"]), 0))
        grid.connect("clicked", lambda _b: subprocess.Popen(LAUNCHER, start_new_session=True))
        self.box.append(grid)

        # A GTK window grows to fit new children but keeps that size when they
        # go, so a closed app would leave an empty stretch of slab. Asking for
        # a 1x1 default makes it settle back to what its children need.
        self.win.set_default_size(1, 1)

    def _icon_column(self, gicon, count):
        column = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        image = Gtk.Image.new_from_gicon(gicon)
        image.set_pixel_size(ICON_SIZE)
        column.append(image)
        dots = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=3)
        dots.set_halign(Gtk.Align.CENTER)
        dots.add_css_class("dots")
        for _ in range(min(count, MAX_DOTS)):
            dot = Gtk.Box()
            dot.add_css_class("dot")
            dots.append(dot)
        column.append(dots)
        return column

    def _button(self, app):
        button = Gtk.Button()
        button.add_css_class("dock-app")
        button.set_tooltip_text(app.name)
        if app.windows:
            button.add_css_class("running")
        if any(w["address"] == self.active for w in app.windows):
            button.add_css_class("active")
        if any(w.get("urgent") for w in app.windows):
            button.add_css_class("urgent")
        button.set_child(self._icon_column(app.icon, len(app.windows)))
        button.connect("clicked", lambda _b: self.activate_app(app))

        clicks = Gtk.GestureClick(button=0)
        clicks.connect("pressed", self._on_press, app, button)
        button.add_controller(clicks)
        return button

    def _on_press(self, gesture, _n, _x, _y, app, button):
        which = gesture.get_current_button()
        if which == Gdk.BUTTON_MIDDLE:
            self.launch(app.key)
        elif which == Gdk.BUTTON_SECONDARY:
            self._menu(app, button)

    def _menu(self, app, button):
        menu = Gio.Menu()

        if app.windows:
            section = Gio.Menu()
            for w in app.windows:
                title = (w.get("title") or app.name).strip()
                if len(title) > 48:
                    title = title[:47] + "…"
                item = Gio.MenuItem.new(title, None)
                item.set_action_and_target_value("dock.focus", GLib.Variant("s", w["address"]))
                section.append_item(item)
            menu.append_section(None, section)

        section = Gio.Menu()
        if app.info:
            self._item(section, "New window", "dock.launch", app.key)
            if app.key in self.pinned:
                self._item(section, "Unpin from dock", "dock.unpin", app.key)
            else:
                self._item(section, "Pin to dock", "dock.pin", app.key)
        menu.append_section(None, section)

        if app.windows:
            section = Gio.Menu()
            label = "Close window" if len(app.windows) == 1 else f"Close all {len(app.windows)} windows"
            self._item(section, label, "dock.close", app.key)
            menu.append_section(None, section)

        popover = Gtk.PopoverMenu.new_from_model(menu)
        popover.set_parent(button)
        popover.set_has_arrow(False)
        popover.set_position(Gtk.PositionType.TOP)

        def closed(p):
            self.menu_open = False
            # Unparent after the action has run: actions fire after "closed".
            GLib.idle_add(lambda: p.unparent() or False)
            self.schedule_refresh()
        popover.connect("closed", closed)
        self.menu_open = True
        popover.popup()

    @staticmethod
    def _item(menu, label, action, target):
        item = Gio.MenuItem.new(label, None)
        item.set_action_and_target_value(action, GLib.Variant("s", target))
        menu.append_item(item)

    # actions

    def activate_app(self, app):
        if not app.windows:
            self.launch(app.key)
            return
        # Most recently focused first; Hyprland counts focusHistoryID from 0.
        recent = sorted(app.windows, key=lambda w: w.get("focusHistoryID", 1 << 30))
        addresses = [w["address"] for w in app.windows]   # stable: oldest first
        if self.active in addresses:
            if len(addresses) > 1:
                focus(addresses[(addresses.index(self.active) + 1) % len(addresses)])
        else:
            focus(recent[0]["address"])

    def launch(self, key):
        app = self.apps.get(key)
        info = app.info if app else app_by_id(key)
        if not info:
            return
        context = Gdk.Display.get_default().get_app_launch_context()
        context.unsetenv("LD_PRELOAD")
        try:
            info.launch([], context)
        except GLib.Error as e:
            print(f"lucent-dock: could not start {key}: {e.message}", file=sys.stderr)

    def pin(self, key):
        if key not in self.pinned:
            self.pinned.append(key)
            save_pinned(self.pinned)
        self.schedule_refresh()

    def unpin(self, key):
        if key in self.pinned:
            self.pinned.remove(key)
            save_pinned(self.pinned)
            # Still open, it stays in the dock, after the pinned ones.
            self.order.append(key)
        self.schedule_refresh()

    def close_all(self, key):
        app = self.apps.get(key)
        for w in (app.windows if app else []):
            close(w["address"])


def _name_process():
    # "lucent-dock" in ps and to pgrep -x, rather than python3. dock.sh finds
    # it that way; matching the command line also matches any shell that
    # merely mentions the path.
    try:
        libc = ctypes.CDLL(None)
        libc.prctl(15, b"lucent-dock", 0, 0, 0)   # PR_SET_NAME
    except (OSError, AttributeError):
        pass


if __name__ == "__main__":
    if "HYPRLAND_INSTANCE_SIGNATURE" not in os.environ:
        sys.exit("lucent-dock: Hyprland is not running")
    _name_process()
    sys.exit(Dock().run([sys.argv[0]]))
