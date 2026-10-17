"""Where everything lives.

Resolved once, here, so no other module has to know whether XDG_CONFIG_HOME is
set — and so the whole app can be pointed at a scratch directory in a test by
setting XDG_CONFIG_HOME before importing it.
"""

import os
from pathlib import Path

HOME = Path.home()
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config")

HYPR = CONFIG / "hypr"
WAYBAR = CONFIG / "waybar"

# The palette theme.sh renders for waybar. We import the same file rather than
# rendering a third copy, so SUPER+SHIFT+T restyles this app too.
COLORS_CSS = WAYBAR / "colors.css"

# Hand-written, and left alone.
INPUT_LUA = HYPR / "input.lua"

# Generated. starch-config owns these outright and rewrites them whole; each
# one carries a header saying so.
MONITORS_LUA = HYPR / "monitors.lua"
HYPRIDLE_CONF = HYPR / "hypridle.conf"
SETTINGS_LUA = HYPR / "settings.lua"

# Which key the keybinds start with. Its own file rather than another entry in
# settings.lua, because it is not a Hyprland setting: keybinds.lua reads it and
# binds with it, and hyprland.lua requires keybinds.lua *before* settings.lua —
# so a value arriving in settings.lua would arrive after everything is bound.
KEYS_LUA = HYPR / "keys.lua"

# Our own record of what the user chose, which is the thing the generated files
# are rendered from. Kept separate because a generated file cannot always be
# read back: "suspend after 10 minutes" survives a round trip, but "scale 1.6 on
# a display that cannot do 1.6" does not.
STATE = CONFIG / "starch" / "settings.json"

SCRIPTS = HYPR / "scripts"
THEME_SH = SCRIPTS / "theme.sh"
WALLPAPER_SH = SCRIPTS / "wallpaper.sh"
