--------------------------------------------------------------------------------
--  Float everything — SUPER + SHIFT + V
--
--  A mode rather than a one-off: turning it on floats every open window, on
--  every workspace, and every window that opens afterwards, so the desktop
--  behaves like a stacking one. Turning it off tiles them again.
--
--  Only the windows this mode floated go back. A file dialog, pavucontrol or
--  picture-in-picture float because rules.lua says so, and they stay floating
--  when the mode ends. Those windows are recognised by a tag, `floatall`,
--  rather than a list kept here: a reload builds a fresh Lua state, and a
--  list would be forgotten, leaving windows floated before the reload
--  floating for good. The tag lives on the window. `hyprctl clients` shows
--  it.
--
--  Hyprland draws no title bars, so a floating window moves with the modifier
--  and a left-drag (right-drag resizes), or by its border. The notification
--  says so.
--
--  New windows are caught on window.open, after the rules have run, so the
--  window's own floating flag says whether a rule floated it. A window_rule
--  could not tell: it would float and tag every window, dialogs included,
--  and turning the mode off would then tile the dialogs too.
--
--  The mode is remembered: ~/.config/lucent/float-all exists while it is on,
--  so it survives a reload and the next login.
--------------------------------------------------------------------------------

local M = {}

local TAG = "floatall"

local config = os.getenv("XDG_CONFIG_HOME") or ((os.getenv("HOME") or "") .. "/.config")
local marker = config .. "/lucent/float-all"

local function is_on()
    local f = io.open(marker, "r")
    if f then f:close() end
    return f ~= nil
end

local function remember(on)
    if on then
        os.execute("mkdir -p '" .. config .. "/lucent'")
        local f = io.open(marker, "w")
        if f then f:close() end
    else
        os.remove(marker)
    end
end

local function has_tag(w)
    for _, t in ipairs(w.tags or {}) do
        if t == TAG then return true end
    end
    return false
end

local function float(w)
    if w.floating then return end
    local win = "address:" .. w.address
    hl.dispatch(hl.dsp.window.float({ action = "enable", window = win }))
    hl.dispatch(hl.dsp.window.tag({ tag = "+" .. TAG, window = win }))
end

local function tile(w)
    if not has_tag(w) then return end
    local win = "address:" .. w.address
    hl.dispatch(hl.dsp.window.tag({ tag = "-" .. TAG, window = win }))
    hl.dispatch(hl.dsp.window.float({ action = "disable", window = win }))
end

-- `mod` is the primary modifier keybinds.lua settled on, for the hint: there
-- are no title bars to drag, so moving a floating window takes the modifier.
function M.toggle(mod)
    mod = mod or "SUPER"
    local on = not is_on()
    remember(on)
    for _, w in ipairs(hl.get_windows()) do
        if on then float(w) else tile(w) end
    end
    if on then
        hl.exec_cmd("notify-send -a Windows -t 3000 'Floating' 'Every window floats, new ones too. "
            .. mod .. " + drag moves one, " .. mod .. " + right-drag resizes.'")
    else
        hl.exec_cmd("notify-send -a Windows -t 1500 'Tiling' 'Windows tile again.'")
    end
end

hl.on("window.open", function(w)
    if is_on() then float(w) end
end)

return M
