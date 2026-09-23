-- AltArmy TBC — Right-edge icon flyout tabs for the main window (CharacterFrame style).
-- Forever: LargeSideTabButtonTemplate (common-sidetab atlases, truncated corners, built-in tooltip).
-- TBC Anniversary lacks that template; falls back to classic spellbook skill-line tabs.

AltArmy = AltArmy or {}
AltArmy.SideTabs = AltArmy.SideTabs or {}

local SideTabs = AltArmy.SideTabs

-- CharacterFrame ModeTabs: TOPLEFT -> frame TOPRIGHT, y -30; tab height already trims art padding.
SideTabs.NATIVE = { anchorX = 0, anchorY = -30, gap = 0, fallbackHeight = 55 }
-- SpellBookSkillLineTabTemplate: 32x32, 64x64 art at (-3, 11), tabs 17px apart, first at y -36.
SideTabs.CLASSIC = {
    anchorX = 0, anchorY = -36, size = 32, gap = 17,
    art = "Interface\\SpellBook\\SpellBook-SkillLineTab", artSize = 64, artX = -3, artY = 11,
    highlight = "Interface\\Buttons\\ButtonHilight-Square",
    checked = "Interface\\Buttons\\CheckButtonHilight",
}

--- Y offset (<= 0) from the container top for each visible tab, in `names` order.
function SideTabs.ComputeOffsets(names, hidden, stride)
    local offsets = {}
    local index = 0
    for _, name in ipairs(names) do
        if not (hidden and hidden[name]) then
            offsets[name] = -index * stride
            index = index + 1
        end
    end
    return offsets
end

local function createNativeTab(container, def, onSelect)
    local tab = CreateFrame("Frame", nil, container, "LargeSideTabButtonTemplate")
    tab.tabName = def.name
    tab.tooltipText = def.label
    if tab.Icon then
        tab.Icon:SetTexture(def.icon)
    end
    if tab.SetFillToInterior then
        tab:SetFillToInterior(true)
    end
    if tab.SetCustomOnMouseUpHandler then
        tab:SetCustomOnMouseUpHandler(function(_, button, upInside)
            if button == "LeftButton" and upInside then
                onSelect(def.name)
            end
        end)
    end
    return tab
end

local function createClassicTab(container, def, onSelect, isSelected)
    local C = SideTabs.CLASSIC
    local tab = CreateFrame("CheckButton", nil, container)
    tab.tabName = def.name
    tab.tooltipText = def.label
    tab:SetSize(C.size, C.size)

    local art = tab:CreateTexture(nil, "BACKGROUND")
    art:SetTexture(C.art)
    art:SetSize(C.artSize, C.artSize)
    art:SetPoint("TOPLEFT", tab, "TOPLEFT", C.artX, C.artY)

    tab:SetNormalTexture(def.icon)
    local highlight = tab:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture(C.highlight)
    highlight:SetBlendMode("ADD")
    highlight:SetAllPoints(tab)
    tab:SetHighlightTexture(highlight)
    local checked = tab:CreateTexture(nil, "OVERLAY")
    checked:SetTexture(C.checked)
    checked:SetBlendMode("ADD")
    checked:SetAllPoints(tab)
    tab:SetCheckedTexture(checked)

    tab:SetScript("OnClick", function(self)
        -- CheckButton toggles itself on click; selection state is owned by SetSelected.
        self:SetChecked(isSelected(def.name))
        onSelect(def.name)
    end)
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltipText)
    end)
    tab:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return tab
end

--- Build the tab stack on the right edge of `parent`.
--- defs: array of { name, label, icon }. opts.onSelect(name); opts.native (default: NativeUI caps).
function SideTabs.Create(parent, defs, opts)
    opts = opts or {}
    local native = opts.native
    if native == nil then
        local NativeUI = AltArmy.NativeUI
        native = NativeUI and NativeUI.GetCaps().sideTabs or false
    end
    local layout = native and SideTabs.NATIVE or SideTabs.CLASSIC
    local onSelect = opts.onSelect or function() end

    local obj = { tabs = {}, names = {}, hidden = {}, selected = nil, native = native }

    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", parent, "TOPRIGHT", layout.anchorX, layout.anchorY)
    container:SetSize(1, 1)
    obj.container = container

    local function isSelected(name)
        return obj.selected == name
    end

    for i, def in ipairs(defs) do
        obj.names[i] = def.name
        if native then
            obj.tabs[def.name] = createNativeTab(container, def, onSelect)
        else
            obj.tabs[def.name] = createClassicTab(container, def, onSelect, isSelected)
        end
    end

    local function stride()
        if not native then
            return layout.size + layout.gap
        end
        local first = obj.tabs[obj.names[1]]
        local h = first and first.GetHeight and first:GetHeight() or 0
        if h <= 0 then h = layout.fallbackHeight end
        return h + layout.gap
    end

    function obj:Relayout()
        local offsets = SideTabs.ComputeOffsets(self.names, self.hidden, stride())
        for _, name in ipairs(self.names) do
            local tab = self.tabs[name]
            tab:ClearAllPoints()
            if offsets[name] then
                tab:SetPoint("TOPLEFT", container, "TOPLEFT", 0, offsets[name])
                tab:Show()
            else
                tab:Hide()
            end
        end
    end

    function obj:SetSelected(name)
        self.selected = name
        for tabName, tab in pairs(self.tabs) do
            tab:SetChecked(tabName == name)
        end
    end

    --- Show the player's guild crest in place of the tab icon (falls back to the icon when
    --- there is no guild). Native tabs clip the crest with the tab's truncated-corner mask.
    function obj:RefreshCrest(name)
        local tab = self.tabs[name]
        local GuildCrest = AltArmy.GuildCrest
        if not tab or not GuildCrest then return end
        if not tab.altArmyCrest then
            if native then
                tab.altArmyCrest = GuildCrest.CreateLayers(tab, tab.Icon, { mask = tab.Mask, subLevel = 1 })
            else
                tab.altArmyCrest = GuildCrest.CreateLayers(tab, tab, { layer = "ARTWORK", subLevel = 1 })
            end
        end
        local drawn = tab.altArmyCrest:Refresh()
        if native then
            if tab.Icon and tab.Icon.SetShown then tab.Icon:SetShown(not drawn) end
        else
            local normal = tab.GetNormalTexture and tab:GetNormalTexture()
            if normal and normal.SetAlpha then normal:SetAlpha(drawn and 0 or 1) end
        end
    end

    function obj:SetTabShown(name, shown)
        if not self.tabs[name] then return end
        self.hidden[name] = not shown or nil
        self:Relayout()
    end

    obj:Relayout()
    return obj
end
