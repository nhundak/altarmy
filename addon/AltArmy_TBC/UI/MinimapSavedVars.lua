-- LibDBIcon saved-var shape and migration from legacy minimapAngle / showMinimapButton.

AltArmy = AltArmy or {}

local DEFAULT_MINIMAP_POS = 90

---@param opts table|nil
---@return table minimap LibDBIcon db (hide, minimapPos, optional lock)
function AltArmy.MigrateMinimapSavedVars(opts)
    if not opts then return { hide = false, minimapPos = DEFAULT_MINIMAP_POS } end
    opts.minimap = opts.minimap or {}
    local m = opts.minimap
    if m.minimapPos == nil and opts.minimapAngle ~= nil then
        m.minimapPos = opts.minimapAngle
    end
    if m.minimapPos == nil then
        m.minimapPos = DEFAULT_MINIMAP_POS
    end
    if m.hide == nil then
        m.hide = (opts.showMinimapButton == false)
    end
    return m
end
