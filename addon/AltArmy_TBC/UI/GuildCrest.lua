-- AltArmy TBC — Player guild crest (tabard background + emblem + border) drawn into three
-- textures. Used by the Guild tab header, the Guild side tab and the window portrait.

AltArmy = AltArmy or {}
AltArmy.GuildCrest = AltArmy.GuildCrest or {}

local GC = AltArmy.GuildCrest

function GC.IsInGuild()
    return _G.IsInGuild ~= nil and _G.IsInGuild() and true or false
end

--- Draw the player's guild tabard into the given textures.
--- Returns true when a crest was drawn; false (textures untouched) when there is no guild or
--- no tabard API, so callers can show their fallback icon instead.
function GC.Apply(background, emblem, border)
    if not GC.IsInGuild() then
        return false
    end
    if _G.SetLargeGuildTabardTextures then
        _G.SetLargeGuildTabardTextures("player", emblem, background, border)
        return true
    end
    -- Modern C_GuildInfo emblem info (background color + emblem; no border art).
    local info = _G.C_GuildInfo and _G.C_GuildInfo.GetGuildTabardInfo
        and _G.C_GuildInfo.GetGuildTabardInfo("player")
    if info and info.backgroundColor then
        local c = info.backgroundColor
        background:SetColorTexture(c.r or 0, c.g or 0, c.b or 0, 1)
        emblem:SetTexture(info.emblemFileID)
        if border then border:SetTexture(nil) end
        return true
    end
    return false
end

--- Three stacked crest textures on `parent`, covering `anchor` (a frame or texture).
--- opts.mask: MaskTexture to clip the crest (e.g. side-tab corners, portrait circle).
--- opts.layer / opts.subLevel: draw layer (default ARTWORK, sublevels +0..+2).
--- Returns { background, emblem, border, SetShown(on) }.
function GC.CreateLayers(parent, anchor, opts)
    opts = opts or {}
    local layer = opts.layer or "ARTWORK"
    local base = opts.subLevel or 0
    local layers = {}
    local list = {}
    for i, key in ipairs({ "background", "emblem", "border" }) do
        local t = parent:CreateTexture(nil, layer, nil, base + i - 1)
        t:SetAllPoints(anchor)
        if opts.mask and t.AddMaskTexture then
            t:AddMaskTexture(opts.mask)
        end
        t:Hide()
        layers[key] = t
        list[i] = t
    end
    function layers.SetShown(_, on)
        for _, t in ipairs(list) do
            t:SetShown(on and true or false)
        end
    end
    --- Apply the crest; shows the layers and returns true when drawn.
    function layers.Refresh(self)
        local drawn = GC.Apply(self.background, self.emblem, self.border)
        self:SetShown(drawn)
        return drawn
    end
    return layers
end
