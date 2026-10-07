-- AltArmy TBC — Inventory tab: one character's bags, bank and mail, drawn like the stock windows.
-- This shell owns the toolbar controls (the character picker and the layout dropdown), the Bags / Bank /
-- Mail sub-view tabs with their panels, and the refresh wiring. Tabs/TabInventoryBags.lua fills
-- frame.BagsView and frame.BankView; Tabs/TabInventoryMail.lua fills frame.MailView. Saved state:
-- Data/Inventory/InventoryOptions.lua; layout model: Data/Inventory/InventoryLayout.lua.
-- luacheck: globals GetRealmName

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Inventory
if not frame then return end

local DS = AltArmy.DataStore
local Theme = AltArmy.Theme
local IO = AltArmy.InventoryOptions
local SD = AltArmy.SummaryData
local RF = AltArmy.RealmFilter
local GRF = AltArmy.GlobalRealmFilter
local CharKey = AltArmy.CharKey
if not (DS and Theme and IO and SD and RF and GRF and CharKey) then return end

IO.EnsureOptions()

-- The chosen character and sub-view, kept while the window stays open (switching tabs keeps them); the
-- next time the window opens the tab starts on the character playing and the Bags view.
local state = { selectedChar = nil, activeView = IO.DEFAULT_VIEW }

local UI = {
    PICKER_WIDTH = 190,
    LAYOUT_WIDTH = 150,
    TOOLBAR_GAP = 6,
    TOOLBAR_EDGE = -4, -- off the window's edge, as the Economy views' Filter button
}

local VIEW = {
    tabs = nil,
    defs = {
        { name = "bags", label = "Bags", icon = "Interface\\Icons\\INV_Misc_Bag_08" },
        { name = "bank", label = "Bank", icon = "Interface\\Icons\\INV_Misc_OrnateBox" },
        { name = "mail", label = "Mail", icon = "Interface\\Icons\\INV_Letter_15" },
    },
}

-- Panels: one per sub-view, same anchors; only the active one is shown.
local function CreateViewPanel()
    local p = Theme.CreateMainContentPanel(frame)
    p:SetPoint("TOPLEFT", frame, "TOPLEFT", Theme.TAB_SECTION_INSET, -Theme.TAB_SECTION_INSET)
    p:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -Theme.TAB_SECTION_INSET, Theme.TAB_SECTION_INSET)
    p:Hide()
    return p
end
local panels = { bags = CreateViewPanel(), bank = CreateViewPanel(), mail = CreateViewPanel() }
frame.BagsView = panels.bags
frame.BankView = panels.bank
frame.MailView = panels.mail

--- The characters the picker offers, under the global realm filter, as dropdown entries that also
--- carry name and realm: { id = CharKey, label, name, realm }.
local function CharacterEntries()
    local list = SD.GetCharacterList()
    local currentRealm = GetRealmName and GetRealmName() or ""
    list = RF.filterListByRealm(list, GRF.Get(), currentRealm)
    table.sort(list, function(a, b)
        if (a.realm or "") ~= (b.realm or "") then return (a.realm or "") < (b.realm or "") end
        return (a.name or "") < (b.name or "")
    end)
    local showRealm = GRF.Get() == "all" and RF.hasMultipleRealms(list)
    local out = {}
    for _, e in ipairs(list) do
        out[#out + 1] = {
            id = CharKey(e.name, e.realm),
            label = RF.formatColoredCharacterNameRealm(e.name, e.realm, showRealm, e.classFile),
            name = e.name,
            coloredName = RF.formatColoredCharacterNameRealm(e.name, e.realm, false, e.classFile, false),
            realm = e.realm,
        }
    end
    return out
end

--- The chosen character's entry: this opening's pick when it still names a listed character, else the
--- character playing (or the first listed), which then becomes the pick.
local function ResolveSelection()
    local entries = CharacterEntries()
    local pick
    for _, e in ipairs(entries) do
        if e.id == state.selectedChar then pick = e end
    end
    if not pick then
        local name, realm = DS:GetCurrentPlayerIdentity()
        local mine = name and realm and CharKey(name, realm)
        for _, e in ipairs(entries) do
            if e.id == mine then pick = e end
        end
        pick = pick or entries[1]
        state.selectedChar = pick and pick.id or nil
    end
    return pick
end

--- `name` in its class colour when it is one of our characters (on `realm`, or the realm after a "-"),
--- else as given: mail comes from other players and NPCs too, whose class we don't know.
function frame.ColorCharacterName(name, realm)
    if type(name) ~= "string" or name == "" then return name end
    local base, otherRealm = name:match("^(.-)%-(.+)$")
    local char = DS._FindCharacterByName and DS._FindCharacterByName(otherRealm or realm, base or name)
    local classFile = char and char.classFile
    local CC = AltArmy.ClassColor
    if classFile and classFile ~= "" and CC and CC.formatName then
        return CC.formatName(name, classFile)
    end
    return name
end

--- The selected character's DataStore record and its picker entry (nil when no character is stored).
function frame.GetSelectedCharacter()
    local pick = ResolveSelection()
    if not pick then return nil, nil end
    return DS:GetCharacter(pick.name, pick.realm), pick
end

local function RefreshActive()
    local which = state.activeView
    if which == "bags" and frame.RefreshBags then
        frame.RefreshBags()
    elseif which == "bank" and frame.RefreshBank then
        frame.RefreshBank()
    elseif which == "mail" and frame.RefreshMail then
        frame.RefreshMail()
    end
end
frame.RefreshActive = RefreshActive
frame.GetActiveView = function() return state.activeView end

-- Scans arrive in bursts (one BAG_UPDATE per bag when looting): redraw once, next frame.
local refreshScheduled = false
local function ScheduleRefresh()
    if refreshScheduled then return end
    if C_Timer and C_Timer.After then
        refreshScheduled = true
        C_Timer.After(0, function()
            refreshScheduled = false
            if frame:IsVisible() then RefreshActive() end
        end)
    elseif frame:IsVisible() then
        RefreshActive()
    end
end
frame.ScheduleRefresh = ScheduleRefresh

-- Toolbar: the character picker at the right end of the search slot, the layout dropdown left of it.
local picker = Theme.CreateSingleSelectDropdown({
    parent = frame,
    dropdownParent = frame,
    width = UI.PICKER_WIDTH,
    popupAlign = "right",
    getEntries = CharacterEntries,
    getSelectedId = function()
        local pick = ResolveSelection()
        return pick and pick.id or nil
    end,
    onSelect = function(id)
        state.selectedChar = id
        RefreshActive()
    end,
})
if picker and AltArmy.PlaceInToolbarRight then
    AltArmy.PlaceInToolbarRight(picker.button, frame, UI.TOOLBAR_EDGE)
end

local layoutDropdown = Theme.CreateSingleSelectDropdown({
    parent = frame,
    dropdownParent = frame,
    width = UI.LAYOUT_WIDTH,
    popupAlign = "right",
    getEntries = function() return IO.LayoutEntries(state.activeView) end,
    getSelectedId = function() return IO.GetLayout(IO.EnsureOptions(), state.activeView) end,
    onSelect = function(id)
        if IO.SetLayout(IO.EnsureOptions(), state.activeView, id) then
            RefreshActive()
        end
    end,
})
if layoutDropdown and picker then
    layoutDropdown.button:SetParent(frame)
    layoutDropdown.button:SetFrameLevel(frame:GetFrameLevel() + 50)
    layoutDropdown.button:ClearAllPoints()
    layoutDropdown.button:SetPoint("RIGHT", picker.button, "LEFT", -UI.TOOLBAR_GAP, 0)
end
frame:HookScript("OnHide", function()
    if picker then picker:Close() end
    if layoutDropdown then layoutDropdown:Close() end
end)

local function SetActiveInventoryView(which)
    if not IO.VIEWS[which] then
        which = IO.DEFAULT_VIEW
    end
    state.activeView = which
    for name, panel in pairs(panels) do
        panel:SetShown(name == which)
    end
    if VIEW.tabs then
        VIEW.tabs:SetSelected(which)
    end
    if layoutDropdown then layoutDropdown:Update() end
    RefreshActive()
end
frame.SetInventoryView = SetActiveInventoryView

-- Sub-view tabs hang from the panel top into the main window's toolbar row (as on Economy and Gear).
VIEW.tabs = AltArmy.TopTabs.Create(frame, VIEW.defs, {
    onSelect = function(id)
        if state.activeView ~= id then
            SetActiveInventoryView(id)
        end
    end,
})
VIEW.tabs.frame:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", AltArmy.MainToolbarInsetX or 54, 0)

frame:SetScript("OnShow", function()
    if picker then picker:Update() end
    SetActiveInventoryView(state.activeView)
end)

-- Closing the main window forgets the pick and the view: the next opening starts on the character
-- playing and Bags.
if AltArmy.MainFrame and AltArmy.MainFrame.HookScript then
    AltArmy.MainFrame:HookScript("OnHide", function()
        state.selectedChar = nil
        state.activeView = IO.DEFAULT_VIEW
    end)
end

-- A bag, bank, equipment or mailbox scan (or a cached send) redraws the open view. IsVisible, not
-- IsShown: the tab frame stays "shown" while the main window is closed.
if DS.OnContainerDataChanged then
    DS:OnContainerDataChanged(function()
        if frame:IsVisible() then
            ScheduleRefresh()
        end
    end)
end
