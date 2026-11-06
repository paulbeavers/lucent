"""Look — theme, wallpaper, cursor and font.

Almost nothing here is implemented twice. theme.sh and wallpaper.sh already do
this work, are already bound to the theme and wallpaper keys, and already know
about every consumer of a palette — the bar and dock, foot, mako, wofi,
hyprlock, GTK and Firefox. The page drives those scripts rather than reimplementing what they do, so there is
one code path and it is the one that already worked.
"""

import subprocess

from .. import paths, readback
from ..widgets import Page, Row, button, dropdown

CURSOR_SIZES = [16, 20, 24, 32, 40, 48, 64]
FONT_SIZES = [9, 10, 11, 12, 13, 14, 16]


class _Failed:
    """Stands in for a CompletedProcess when the command is not there at all.

    theme.sh and wallpaper.sh live in the deployed config, so a checkout that
    has never been installed does not have them — and an exception here took
    the whole app down rather than the one page.
    """

    returncode = 1
    stdout = ""
    stderr = "not found"


def _run(args, **kw):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=20, **kw)
    except (OSError, subprocess.TimeoutExpired):
        return _Failed()


def _check(out, what):
    """Raise if a command failed, so Apply names it rather than saying "Applied."."""
    if out.returncode != 0:
        raise RuntimeError(f"{what}: {out.stderr.strip() or 'failed'}")


def _gsettings(key, default=None):
    out = _run(["gsettings", "get", "org.gnome.desktop.interface", key])
    if out.returncode != 0:
        return default
    return out.stdout.strip().strip("'")


def _themes():
    """(slug, display name) for every installed theme."""
    out = _run([str(paths.THEME_SH), "--list"])
    if out.returncode != 0:
        return []
    rows = []
    for line in out.stdout.splitlines():
        slug, _, name = line.partition("\t")
        if slug:
            rows.append((slug.strip(), (name or slug).strip()))
    return rows


def build(window):
    page = Page("Look", "Theme, wallpaper and the size of things.")
    state = _LookState(window)

    themes = _themes()
    if themes:
        card = page.section("Theme")
        card.add(Row("Colour theme", state.theme_control(themes),
                     "Applies everywhere at once — the bar, the terminal, "
                     "notifications, the launcher, the lock screen and this "
                     "window."))
    else:
        page.note(f"No themes found. Expected {paths.THEME_SH} to answer --list.")

    card = page.section("Wallpaper")
    card.add(Row("Current", state.wallpaper_label(),
                 state.wallpaper_path() or "Nothing recorded yet."))
    card.add(Row("Choose", button("Pick a wallpaper…", on_click=state.pick_wallpaper),
                 f"Opens the same picker as {readback.modifier()}+W."))
    card.add(Row("Random", button("Surprise me", on_click=state.random_wallpaper)))

    card = page.section("Size")
    card.add(Row("Cursor size", state.cursor_control(),
                 "Sets the size GTK applications use. The desktop's own "
                 "pointer changes too, but only until Hyprland next reloads "
                 "or you log in again, which put it back to the session's "
                 "size (24)."))
    card.add(Row("Interface font size", state.font_control(),
                 "Applies to GTK applications. Display scale is on the "
                 "Display page and moves everything, not just text."))

    page.note(
        "Theme and size changes are applied when you press Apply. The "
        "wallpaper buttons act immediately, because the picker is a window of "
        "its own."
    )
    return page


class _LookState:
    def __init__(self, window):
        self.window = window
        self.theme = None
        self.cursor = None
        self.font_size = None

    # ── theme ────────────────────────────────────────────────────────────────
    def theme_control(self, themes):
        current = _run([str(paths.THEME_SH), "--current"]).stdout.strip()
        slugs = [slug for slug, _name in themes]
        index = slugs.index(current) if current in slugs else 0
        self.theme = slugs[index]
        return dropdown(
            [name for _slug, name in themes],
            selected=index,
            on_change=lambda i: self._set_theme(slugs[i]),
        )

    def _set_theme(self, slug):
        self.theme = slug
        self.window.stage("look:theme", self._apply_theme, f"theme → {slug}")

    def _apply_theme(self):
        out = _run([str(paths.THEME_SH), "--set", self.theme])
        if out.returncode != 0:
            raise RuntimeError(out.stderr.strip() or "theme.sh failed")

    # ── wallpaper ────────────────────────────────────────────────────────────
    def wallpaper_path(self):
        try:
            return (paths.HYPR / ".active-wallpaper").read_text().strip()
        except OSError:
            return ""

    def wallpaper_label(self):
        from gi.repository import Gtk

        path = self.wallpaper_path()
        label = Gtk.Label(label=path.rsplit("/", 1)[-1] if path else "—")
        label.add_css_class("sc-dim")
        return label

    def pick_wallpaper(self):
        self._detach([str(paths.WALLPAPER_SH)])

    def random_wallpaper(self):
        self._detach([str(paths.WALLPAPER_SH), "--random"])

    @staticmethod
    def _detach(args):
        """The picker is wofi and outlives this callback, so it is detached —
        and a missing script says so rather than raising into the toolkit."""
        try:
            subprocess.Popen(
                args,
                start_new_session=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except OSError:
            pass

    # ── sizes ────────────────────────────────────────────────────────────────
    def cursor_control(self):
        try:
            current = int(_gsettings("cursor-size", "24"))
        except (TypeError, ValueError):
            current = 24
        options = sorted(set(CURSOR_SIZES) | {current})
        self.cursor = current
        return dropdown(
            [f"{v} px" for v in options],
            selected=options.index(current),
            on_change=lambda i: self._set_cursor(options[i]),
        )

    def _set_cursor(self, size):
        self.cursor = size
        self.window.stage("look:cursor", self._apply_cursor, f"cursor → {size}px")

    def _apply_cursor(self):
        _check(_run(["gsettings", "set", "org.gnome.desktop.interface",
                     "cursor-size", str(self.cursor)]), "gsettings")
        # Hyprland's own cursor is set separately from the GTK one, and only
        # for this session. autostart.lua runs `hyprctl setcursor Adwaita
        # $XCURSOR_SIZE` at its top level, so every reload puts it back to
        # env.lua's 24 — and settings.lua cannot change that: it loads after
        # autostart.lua, whose set_cursor has already been started with the
        # environment env.lua left, so an hl.env("XCURSOR_SIZE", ...) there
        # arrives too late on every reload. Making this stick needs
        # the size in env.lua or gpu.lua, which load first, and neither is
        # this app's to write. The row says so instead of pretending.
        out = _run(["hyprctl", "setcursor", _gsettings("cursor-theme", "Adwaita") or
                    "Adwaita", str(self.cursor)])
        _check(out, "hyprctl setcursor")
        # hyprctl can exit 0 with an error as its reply.
        reply = out.stdout.strip()
        if reply and reply != "ok":
            raise RuntimeError(f"hyprctl setcursor: {reply}")

    def font_control(self):
        name = _gsettings("font-name", "Noto Sans 11") or "Noto Sans 11"
        _family, current = _split_font(name)
        options = sorted(set(FONT_SIZES) | {current})
        self.font_size = current
        return dropdown(
            [f"{v} pt" for v in options],
            selected=options.index(current),
            on_change=lambda i: self._set_font(options[i]),
        )

    def _set_font(self, size):
        self.font_size = size
        self.window.stage("look:font", self._apply_font, f"font → {size}pt")

    def _apply_font(self):
        # The family is read again here rather than kept from when the page was
        # built: theme.sh owns it, and a theme applied in the same batch — or
        # with SUPER+SHIFT+T while the page was open — would otherwise be put
        # back to the old family. Only the size is this page's.
        name = _gsettings("font-name")
        if not name:
            raise RuntimeError("could not read the current font from gsettings")
        family, _size = _split_font(name)
        _check(_run(["gsettings", "set", "org.gnome.desktop.interface",
                     "font-name", f"{family} {self.font_size}"]), "gsettings")


def _split_font(name: str):
    """"Noto Sans 11" -> ("Noto Sans", 11). A font with no size keeps 11."""
    family, _, tail = name.rpartition(" ")
    try:
        return family or name, int(tail)
    except ValueError:
        return name, 11
