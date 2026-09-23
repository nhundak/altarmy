-- AltArmy TBC — Spellbook-style sub-view tabs that hang above a panel (Cooldowns: Crafting /
-- Dungeons). Uses Blizzard's TabSystemTemplate with TabSystemTopButtonTemplate:
--   Forever: square icon tabs (spellbook-Tab-Frame-C60 art), name in the tooltip.
--   TBC Anniversary: its client does not load TabSystem at all, so classic text top tabs
--   (PanelTopTabButtonTemplate + PanelTemplates_SelectTab / DeselectTab).
--   Neither: plain toggle buttons.
-- Callers anchor `obj.frame` by its BOTTOMLEFT so the tabs grow upward from the panel top.

AltArmy = AltArmy or {}
AltArmy.TopTabs = AltArmy.TopTabs or {}

local TopTabs = AltArmy.TopTabs

TopTabs.FALLBACK_BUTTON = { width = 90, height = 22, gap = 4 }

local function resolveCaps(opts)
    if opts.caps then return opts.caps end
    local NativeUI = AltArmy.NativeUI
    return NativeUI and NativeUI.GetCaps() or {}
end

local function createTabSystem(parent, defs, obj, onSelect, useIcons)
    local sys = CreateFrame("Frame", nil, parent, "TabSystemTemplate")
    -- TabSystemMixin:OnLoad pooled the default (bottom) template; rebuild for top tabs.
    sys.tabTemplate = "TabSystemTopButtonTemplate"
    sys.tabPool = _G.CreateFramePool("BUTTON", sys, "TabSystemTopButtonTemplate")
    sys:SetTabSelectedCallback(function(tabID, isUserAction)
        local name = obj.nameById[tabID]
        if isUserAction and name then
            onSelect(name)
        end
        return false
    end)
    for _, def in ipairs(defs) do
        local id
        if useIcons then
            id = sys:AddTab(nil, def.icon)
        else
            id = sys:AddTab(def.label)
        end
        local btn = sys:GetTabButton(id)
        if btn and btn.SetTooltipText then
            btn:SetTooltipText(def.label)
        end
        obj.idByName[def.name] = id
        obj.nameById[id] = def.name
        obj.buttons[def.name] = btn
    end
    obj.frame = sys
    function obj:SetSelected(name)
        local id = self.idByName[name]
        if id then
            sys:SetTabVisuallySelected(id)
        end
    end
end

-- Classic TabButtonTemplate top tabs (HelpFrameTab art) driven by PanelTemplates_*; these helpers
-- look up textures by global name, so tabs need unique names.
local classicTabCount = 0
TopTabs.CLASSIC_TAB = { padding = 20, gap = -8 }

local function createClassicTopTabs(parent, defs, obj, onSelect)
    local C = TopTabs.CLASSIC_TAB
    local container = CreateFrame("Frame", nil, parent)
    local prev
    for _, def in ipairs(defs) do
        classicTabCount = classicTabCount + 1
        local btn = CreateFrame("Button", "AltArmyTBC_TopTab" .. classicTabCount, container,
            "PanelTopTabButtonTemplate")
        btn:SetText(def.label)
        if _G.PanelTemplates_TabResize then
            _G.PanelTemplates_TabResize(btn, C.padding)
        end
        if prev then
            btn:SetPoint("BOTTOMLEFT", prev, "BOTTOMRIGHT", C.gap, 0)
        else
            btn:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
        end
        btn:SetScript("OnClick", function()
            onSelect(def.name)
        end)
        obj.buttons[def.name] = btn
        prev = btn
    end
    local first = obj.buttons[defs[1] and defs[1].name]
    container:SetSize(200, first and first.GetHeight and first:GetHeight() or 24)
    obj.frame = container
    function obj:SetSelected(name)
        for tabName, btn in pairs(self.buttons) do
            if tabName == name then
                _G.PanelTemplates_SelectTab(btn)
            else
                _G.PanelTemplates_DeselectTab(btn)
            end
        end
    end
end

local function createFallbackButtons(parent, defs, obj, onSelect)
    local B = TopTabs.FALLBACK_BUTTON
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(#defs * (B.width + B.gap), B.height)
    local Theme = AltArmy.Theme
    for i, def in ipairs(defs) do
        local btn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
        btn:SetSize(B.width, B.height)
        btn:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", (i - 1) * (B.width + B.gap), 0)
        btn:SetText(def.label)
        if Theme and Theme.SkinButton then
            Theme.SkinButton(btn, true)
        end
        btn:SetScript("OnClick", function()
            onSelect(def.name)
        end)
        obj.buttons[def.name] = btn
    end
    obj.frame = container
    function obj:SetSelected(name)
        for tabName, btn in pairs(self.buttons) do
            if btn.SetSelected then
                btn:SetSelected(tabName == name)
            end
        end
    end
end

--- defs: array of { name, label, icon }. opts.onSelect(name) fires on user clicks only.
--- opts.caps overrides NativeUI caps (tests).
function TopTabs.Create(parent, defs, opts)
    opts = opts or {}
    local caps = resolveCaps(opts)
    local onSelect = opts.onSelect or function() end
    local obj = { buttons = {}, idByName = {}, nameById = {} }
    if caps.topTabs then
        createTabSystem(parent, defs, obj, onSelect, caps.iconTabs)
    elseif caps.panelTopTabs then
        createClassicTopTabs(parent, defs, obj, onSelect)
    else
        createFallbackButtons(parent, defs, obj, onSelect)
    end
    return obj
end
