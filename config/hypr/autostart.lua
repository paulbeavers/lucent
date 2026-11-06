--------------------------------------------------------------------------------
--  Autostart
--
--  The hyprlang `exec-once` became an event handler: everything here runs once,
--  when the compositor finishes starting. The `exec` (run on reload) equivalent
--  is a call at the top level of this file, which a reload runs again; only the
--  cursor needs that.
--
--  uwsm-managed sessions start the portals and polkit agent as systemd user
--  units, so this stays short on purpose.
--------------------------------------------------------------------------------

local function set_cursor()
    hl.exec_cmd('hyprctl setcursor Adwaita "${XCURSOR_SIZE:-24}"')
end

hl.on("hyprland.start", function()
    -- Tell systemd and D-Bus about the session so portals, screen sharing and
    -- xdg-open all find the right compositor.
    --
    -- Then, if nothing has started the systemd graphical session, start it.
    -- uwsm does that itself; a display manager's plain "Hyprland" entry does
    -- not, and without it the portals never start — which, among other things,
    -- leaves Firefox showing sites light on a dark desktop. In that order, and
    -- in one shell, so the portals see WAYLAND_DISPLAY when they start.
    --
    -- The polkit agent goes in the same shell, after them: without one anything
    -- asking for a password silently fails, and where install.sh limits it to
    -- Hyprland its unit reads XDG_CURRENT_DESKTOP from the environment set here.
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE"
        .. " && { systemctl --user -q is-active graphical-session.target"
        .. " || systemctl --user start hyprland-session.target; }"
        .. "; systemctl --user start hyprpolkitagent")
    hl.exec_cmd("/usr/bin/gnome-keyring-daemon --start --components=secrets")

    -- The bar and the dock: one Quickshell program, config/lucent-shell, which
    -- bar.sh starts. It leaves the dock out if SUPER + D hid it last time.
    hl.exec_cmd("~/.config/hypr/scripts/bar.sh")
    hl.exec_cmd("mako")

    -- The wallpaper. There is no daemon to start first: --restore reads the
    -- recorded choice and runs swaybg with it, and swaybg takes the image as
    -- an argument, so there is nothing to wait for and no ordering to get
    -- right. A no-op when nothing has been chosen.
    --
    -- This used to start hyprpaper here and then apply over IPC, because
    -- hyprpaper would not reliably show what its own config named. That call
    -- answers "ok" whether or not anything was painted, so a desktop that came
    -- up bare could not be told from one that worked, and on install media it
    -- never answered at all. Three rounds of timeout tuning did not fix it;
    -- removing the daemon did.
    hl.exec_cmd("~/.config/hypr/scripts/wallpaper.sh --restore")

    -- The theme into any Firefox profile made since the last theme switch.
    -- Firefox reads userChrome.css only at start; see theme.sh's render_firefox.
    hl.exec_cmd("~/.config/hypr/scripts/theme.sh --firefox")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("swayosd-server")

    -- Tray applets.
    hl.exec_cmd("nm-applet --indicator")
    hl.exec_cmd("blueman-applet")
    hl.exec_cmd("udiskie --tray")

    -- cliphist watches the clipboard; SUPER+X browses it.
    hl.exec_cmd("wl-paste --type text  --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")

    hl.exec_cmd("mkdir -p ~/Pictures/Screenshots")

    -- Again at login: the copy below runs while the config is still loading,
    -- possibly before hyprctl has a socket to talk to.
    set_cursor()

    -- The settings app, on its welcome page. --welcome is the difference
    -- between "the desktop started me" and "someone asked for me": with it,
    -- the app exits without drawing anything if its own "Show at login"
    -- switch has been turned off. So this line stays regardless of the
    -- choice, and the choice lives where it is made.
    hl.exec_cmd("lucent-config --welcome")
end)

-- Set the cursor explicitly so XWayland apps do not fall back to X11's. Outside
-- the start handler, because a reload builds a fresh Lua state and runs this
-- file again, and it also puts the cursor back to the size Hyprland read at
-- launch — so a size gpu.lua overrides would hold only until the first reload.
-- The size comes from the environment for the same reason.
set_cursor()

-- And stop it again, so a later login does not find a session still marked
-- active with portals attached to a compositor that has gone. A no-op under
-- uwsm, which never started this target.
hl.on("hyprland.shutdown", function()
    hl.exec_cmd("systemctl --user stop hyprland-session.target")
end)
