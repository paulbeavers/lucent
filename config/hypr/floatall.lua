--------------------------------------------------------------------------------
--  Floating workspaces — SUPER + SHIFT + V
--
--  Each workspace is tiled or floating, and the key switches the one in
--  front of you. Floating means every window on it floats, and so does every
--  window that opens there or is moved there, so that workspace behaves like
--  a stacking desktop while the others tile. Switching it back tiles them.
--
--  Only the windows this module floated go back. A file dialog, pavucontrol
--  or picture-in-picture float because rules.lua says so, and they stay
--  floating on a tiled workspace. Those windows are recognised by a tag,
--  `floatall`, rather than a list kept here: a reload builds a fresh Lua
--  state, and a list would be forgotten, leaving windows floated before the
--  reload floating for good. The tag lives on the window. `hyprctl clients`
--  shows it.
--
--  A window follows the workspace it is on. Moved onto a floating one it
--  floats; moved onto a tiled one it tiles, if this module was what floated
--  it. Hyprland emits window.move_to_workspace from inside the layout's own
--  move, so the float or tile waits for a one-shot timer rather than
--  re-entering the layout from its callback.
--
--  Hyprland draws no title bars, so a floating window moves with the modifier
--  and a left-drag (right-drag resizes), or by its border. The notification
--  says so.
--
--  New windows are caught on window.open, after the rules have run, so the
--  window's own floating flag says whether a rule floated it. A window_rule
--  could not tell: it would float and tag every window, dialogs included,
--  and tiling the workspace would then tile the dialogs too.
--
--  Which workspaces float is a file, ~/.config/lucent/float-workspaces, one
--  workspace name per line, read on every window.open, so it survives a
--  reload and the next login. Before this was per workspace, one marker,
--  ~/.config/lucent/float-all, floated every workspace. While it is the only
--  record it reads as workspaces 1 to 10, the ones the keys reach; the first
--  change writes the new file and removes it. Nothing is migrated on load:
--  tools/keymap-dump.lua loads this module, and must not rewrite anyone's
--  settings.
--
--  lucent-config's Windows page sets it through `hyprctl repl`, calling
--  set_workspaces() on this same module: require() hands back the copy
--  keybinds.lua loaded.
--------------------------------------------------------------------------------

local M = {}

local TAG = "floatall"

local config = os.getenv("XDG_CONFIG_HOME") or ((os.getenv("HOME") or "") .. "/.config")
local dir = config .. "/lucent"
local list = dir .. "/float-workspaces"
local legacy = dir .. "/float-all"

local function exists(path)
    local f = io.open(path, "r")
    if f then f:close() end
    return f ~= nil
end

-- Numbered workspaces in numeric order, then named ones alphabetically.
local function sorted(set)
    local names = {}
    for n in pairs(set) do names[#names + 1] = n end
    table.sort(names, function(a, b)
        local x, y = tonumber(a), tonumber(b)
        if x and y then return x < y end
        if x or y then return x ~= nil end
        return a < b
    end)
    return names
end

-- The set of workspace names that float, as { ["3"] = true }.
local function read()
    local set = {}
    local f = io.open(list, "r")
    if f then
        for line in f:lines() do
            local name = line:match("^%s*(.-)%s*$")
            if name ~= "" then set[name] = true end
        end
        f:close()
    elseif exists(legacy) then
        for i = 1, 10 do set[tostring(i)] = true end
    end
    return set
end

-- Written whole, through a rename, so window.open never reads half a file.
-- An empty set is no file at all, as "nothing floats" was before.
local function write(set)
    local names = sorted(set)
    if #names == 0 then
        os.remove(list)
    else
        os.execute("mkdir -p '" .. dir .. "'")
        local tmp = list .. ".tmp"
        local f = io.open(tmp, "w")
        if not f then return false end
        f:write(table.concat(names, "\n"), "\n")
        f:close()
        os.rename(tmp, list)
    end
    os.remove(legacy)
    return true
end

local function floats(name)
    return name ~= nil and read()[name] == true
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

local function workspace_name(w)
    local ws = w.workspace
    return ws and ws.name
end

-- Float or tile every window on one workspace, to match what it now is.
local function arrange(name, on)
    for _, w in ipairs(hl.get_windows()) do
        if workspace_name(w) == name then
            if on then float(w) else tile(w) end
        end
    end
end

local function label(name)
    return tonumber(name) and ("Workspace " .. name) or name
end

local function notify(changed, want, mod)
    local hint = mod .. " + drag moves a window, " .. mod .. " + right-drag resizes."
    if #changed == 1 then
        local name = changed[1]
        if want[name] then
            hl.exec_cmd("notify-send -a Windows -t 3000 'Floating' '" .. label(name)
                .. " floats, new windows too. " .. hint .. "'")
        else
            hl.exec_cmd("notify-send -a Windows -t 1500 'Tiling' '" .. label(name)
                .. " tiles again.'")
        end
        return
    end
    local names = sorted(want)
    if #names == 0 then
        hl.exec_cmd("notify-send -a Windows -t 1500 'Tiling' 'Every workspace tiles.'")
    else
        hl.exec_cmd("notify-send -a Windows -t 3000 'Floating' 'Floating on "
            .. table.concat(names, ", ") .. ". " .. hint .. "'")
    end
end

-- The whole set at once: lucent-config's Apply, which may change several
-- workspaces and should say so in one notification, not ten. Workspaces that
-- were already right are left alone, and a set that matches what is on disk
-- does nothing at all, not even the notification.
--
-- `mod` is the primary modifier keybinds.lua settled on, for the hint: there
-- are no title bars to drag, so moving a floating window takes the modifier.
function M.set_workspaces(names, mod)
    mod = mod or "SUPER"
    local want = {}
    for _, n in ipairs(names or {}) do want[tostring(n)] = true end
    local have = read()
    local changed = {}
    for n in pairs(want) do if not have[n] then changed[#changed + 1] = n end end
    for n in pairs(have) do if not want[n] then changed[#changed + 1] = n end end
    if #changed == 0 then return end
    write(want)
    for _, n in ipairs(changed) do arrange(n, want[n] == true) end
    notify(changed, want, mod)
end

-- One workspace on or off, rather than a flip, for anything that knows which
-- it wants.
function M.set(name, on, mod)
    local set = read()
    set[tostring(name)] = on and true or nil
    M.set_workspaces(sorted(set), mod)
end

-- The key: the workspace in front of you.
function M.toggle(mod)
    local ws = hl.get_active_workspace()
    if not ws then return end
    M.set(ws.name, not floats(ws.name), mod)
end

hl.on("window.open", function(w)
    if floats(workspace_name(w)) then float(w) end
end)

hl.on("window.move_to_workspace", function(w, ws)
    local name = ws and ws.name
    if not name then return end
    hl.timer(function()
        -- The window may have closed, or moved on again, in the meantime;
        -- a field read on a destroyed window raises.
        pcall(function()
            if workspace_name(w) ~= name then return end
            if floats(name) then float(w) else tile(w) end
        end)
    end, { timeout = 1, type = "oneshot" })
end)

return M
