"""Reading the current settings out of the files that hold them.

A settings app that opens showing defaults instead of what the machine is
actually doing is worse than useless, so every page reads the real state. Where
the running compositor knows (input, displays) we ask it; where only a file
knows (idle timeouts, the lid) we parse the file, including the hand-written
one that shipped, because the first run happens before we have written
anything of our own.
"""

import re
from pathlib import Path

from . import paths

LID_CONF = Path("/etc/systemd/logind.conf.d/10-lucent-lid.conf")
# The name it had until 2026-10-17. Read when the new one is absent, and
# removed whenever the new one is written, so the two can never disagree.
OLD_LID_CONF = Path("/etc/systemd/logind.conf.d/10-starch-lid.conf")


def hypridle_timeouts():
    """{"dim": secs|None, "blank": ..., "lock": ..., "suspend": ...}

    Listeners are identified by what they run, not by their position, so this
    survives the file being reordered or a listener being removed.
    """
    found = {"dim": None, "blank": None, "lock": None, "suspend": None}
    try:
        text = paths.HYPRIDLE_CONF.read_text()
    except OSError:
        return found

    # A block ends at a line that is only "}", not at the first brace: the
    # blank listener's on-timeout is `hl.dsp.dpms({ action = "off" })`, and
    # stopping at the brace inside that cut the block before its on-resume.
    for block in re.findall(r"^\s*listener\s*\{(.*?)^\s*\}\s*$", text, re.S | re.M):
        timeout = re.search(r"timeout\s*=\s*(\d+)", block)
        action = re.search(r"on-timeout\s*=\s*(.+)", block)
        if not (timeout and action):
            continue
        seconds, command = int(timeout.group(1)), action.group(1).strip()
        for key, needle in (
            ("dim", "brightnessctl"),
            ("blank", "dpms"),
            ("lock", "lock-session"),
            ("suspend", "suspend"),
        ):
            if needle in command and found[key] is None:
                found[key] = seconds
                break
    return found


# keys.lua is a two-token module, so a regex beats carrying a Lua parser.
# Case-sensitive, like keybinds.lua's own test (`keys.mod == "ALT"`): a file
# saying "alt" binds with SUPER, so it must read back as SUPER too.
_MODIFIER_RE = re.compile(r"""\bmod\s*=\s*["'](SUPER|ALT)["']""")


def modifier() -> str:
    """"SUPER" or "ALT" — the key every keybind starts with.

    keys.lua is generated and does not exist until the setting has been
    changed, so a missing file is the ordinary case and means the default.
    """
    try:
        text = paths.KEYS_LUA.read_text()
    except OSError:
        return "SUPER"
    match = _MODIFIER_RE.search(text)
    return match.group(1) if match else "SUPER"


def lid_action() -> str:
    """"suspend", "lock", "ignore" — what closing the lid does.

    systemd's own default is suspend, so that is what an absent drop-in means.
    """
    try:
        text = (LID_CONF if LID_CONF.exists() else OLD_LID_CONF).read_text()
    except OSError:
        return "suspend"
    match = re.search(r"^\s*HandleLidSwitch\s*=\s*(\S+)", text, re.M)
    if not match:
        return "suspend"
    value = match.group(1).lower()
    return value if value in ("suspend", "lock", "ignore") else "suspend"


def has_battery() -> bool:
    """Whether this machine has a lid worth asking about."""
    power = Path("/sys/class/power_supply")
    if not power.is_dir():
        return False
    for entry in power.iterdir():
        try:
            if (entry / "type").read_text().strip() != "Battery":
                continue
        except OSError:
            continue
        # A wireless mouse or headset reports a battery too, with scope
        # "Device"; only the machine's own (scope "System", or no scope file
        # at all on older drivers) says there is a lid.
        try:
            if (entry / "scope").read_text().strip() == "Device":
                continue
        except OSError:
            pass
        return True
    return False
