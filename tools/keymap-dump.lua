-- Print every key combination keybinds.lua binds, and fail on a collision.
--
--     luajit tools/keymap-dump.lua config/hypr           -- as configured
--     luajit tools/keymap-dump.lua config/hypr SUPER     -- force the default
--     luajit tools/keymap-dump.lua config/hypr ALT       -- force the swap
--
-- Exits 1 if two binds resolve to the same combination, which is the whole
-- reason this exists. The modifier is a pair that swaps (see keybinds.lua), and
-- the wrong way to implement that collapses eleven binds onto combinations
-- already in use -- without Hyprland saying a word about any of them. Compare
-- the two modes after touching keybinds.lua:
--
--     diff <(luajit tools/keymap-dump.lua config/hypr SUPER) \
--          <(luajit tools/keymap-dump.lua config/hypr ALT)
--
-- Modifiers are normalised into a set before comparison, the way Hyprland
-- turns them into a modmask. That matters: "ALT + ALT + H" and "ALT + H" are
-- different strings and the same bind, so comparing the text misses exactly
-- the collisions this is looking for.
--
-- Loads keybinds.lua against a stub `hl` rather than starting a compositor, so
-- it runs anywhere luajit does -- including over a checkout, with no session.

local cfgdir = arg[1]
local force = arg[2]

if not cfgdir then
    io.stderr:write("usage: keymap-dump.lua <config/hypr dir> [SUPER|ALT]\n")
    os.exit(2)
end

package.path = cfgdir .. "/?.lua;" .. package.path

-- With a modifier forced, hand keybinds.lua a keys module instead of letting
-- it read one from disk -- so both modes can be checked without writing a
-- file into somebody's config.
if force then
    force = force:upper()
    if force ~= "SUPER" and force ~= "ALT" then
        io.stderr:write("modifier must be SUPER or ALT, got: " .. tostring(arg[2]) .. "\n")
        os.exit(2)
    end
    package.preload["keys"] = function() return { mod = force } end
end

local MODS = { SUPER = true, ALT = true, CTRL = true, SHIFT = true, CAPS = true }
local counts, order, submap = {}, {}, ""

-- "mod + SHIFT + K" -> "SHIFT+SUPER|K": modifiers sorted and deduplicated,
-- key last. Two binds with the same normal form are the same bind.
local function normalise(key)
    local mods, plain = {}, {}
    for part in tostring(key):gmatch("[^+]+") do
        part = part:gsub("^%s+", ""):gsub("%s+$", "")
        if MODS[part:upper()] then
            mods[part:upper()] = true
        elseif part ~= "" then
            plain[#plain + 1] = part
        end
    end
    local list = {}
    for m in pairs(mods) do list[#list + 1] = m end
    table.sort(list)
    return submap .. "\t" .. table.concat(list, "+") .. "|" .. table.concat(plain, " ")
end

local function record(key)
    local k = normalise(key)
    if counts[k] == nil then
        order[#order + 1] = k
        counts[k] = 0
    end
    counts[k] = counts[k] + 1
end

-- Every hl.dsp.* call returns something opaque and callable, so both
-- hl.dsp.window.close() and hl.dsp.focus({ ... }) go through unexamined.
local function opaque()
    return setmetatable({}, {
        __call = function() return "dispatch" end,
        __index = function() return opaque() end,
    })
end

hl = {
    bind = function(key) record(key) end,
    dispatch = function() end,
    env = function() end,
    config = function() end,
    monitor = function() end,
    on = function() end,           -- floatall.lua subscribes to window.open
    define_submap = function(name, fn)
        local previous = submap
        submap = name
        fn()
        submap = previous
    end,
    dsp = opaque(),
}

require("keybinds")

table.sort(order)
local collisions = 0
for _, k in ipairs(order) do
    if counts[k] > 1 then
        collisions = collisions + 1
        io.stderr:write("COLLISION x" .. counts[k] .. ": " .. (k:gsub("\t", "[")) .. "\n")
    end
    print(k)
end
io.stderr:write(("%d binds, %d collisions\n"):format(#order, collisions))
os.exit(collisions == 0 and 0 or 1)
