--------------------------------------------------------------------------------
--  Minimize — SUPER + M, and SUPER + CTRL + M to bring the last one back
--
--  Hyprland has no minimized state, so a minimized window is one parked on a
--  special workspace, `special:minimized`, that nothing ever shows. The dock
--  (config/lucent-shell) lists the windows there after its separator, and a
--  click brings one back to the workspace you are on, which is where you
--  were looking when you went for it.
--
--  Apps' own minimize buttons do nothing on Hyprland 0.57: xdg-shell's
--  set_minimized only feeds the fullscreen request path, and only the
--  foreign-toplevel protocol (a taskbar asking) reaches the Lua config, as
--  window.minimize. That one is honoured below.
--
--  Bringing a window back is a silent move and then a focus. A plain move out
--  of a special workspace also closes whatever special workspace that monitor
--  is showing, which would take the scratchpad with it.
--
--  The state is where the window is, so it survives a reload: no list here.
--  floatall.lua ignores moves onto special workspaces, so a window floated by
--  a floating workspace is still floating when it comes back.
--------------------------------------------------------------------------------

local M = {}

M.WORKSPACE = "special:minimized"

local function selector(w)
    return w and ("address:" .. w.address) or nil
end

-- The active window when `w` is nil.
function M.minimize(w)
    local args = { workspace = M.WORKSPACE, follow = false }
    args.window = selector(w)
    hl.dispatch(hl.dsp.window.move(args))
end

local function here()
    local ws = hl.get_active_workspace()
    if not ws then return nil end
    -- A named workspace is reached by name; a numbered one by its number.
    return tonumber(ws.name) or ("name:" .. ws.name)
end

function M.restore(w)
    local target = here()
    if not w or not target then return end
    local win = selector(w)
    hl.dispatch(hl.dsp.window.move({ workspace = target, follow = false, window = win }))
    hl.dispatch(hl.dsp.focus({ window = win }))
end

-- The window minimized last: of those parked, the one focused most recently,
-- which is the one that had focus when SUPER + M sent it away.
function M.restore_last()
    local last
    for _, w in ipairs(hl.get_windows()) do
        local ws = w.workspace
        if ws and ws.name == M.WORKSPACE
            and (not last or (w.focus_history_id or 1e9) < (last.focus_history_id or 1e9)) then
            last = w
        end
    end
    M.restore(last)
end

hl.on("window.minimize", function(w, minimized)
    local ws = w.workspace
    local parked = ws and ws.name == M.WORKSPACE
    if minimized and not parked then
        M.minimize(w)
    elseif not minimized and parked then
        M.restore(w)
    end
end)

return M
