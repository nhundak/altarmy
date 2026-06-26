-- AltArmy TBC — Options panel (Interface > AddOns > AltArmy).

local Theme = AltArmy.Theme
-- Two-column layout: character list + other settings (left), character settings (right).
-- SavedVariables: AltArmyTBC_Options (showMinimapButton legacy; minimap.hide / minimap.minimapPos for LibDBIcon).

-- ---------------------------------------------------------------------------
-- Defaults / minimap helpers
-- ---------------------------------------------------------------------------

local function ensureDefaults()
    if not AltArmyTBC_Options then
        AltArmyTBC_Options = {}
        AltArmy.firstRun = true
    end
    if AltArmy.MigrateMinimapSavedVars then
        AltArmy.MigrateMinimapSavedVars(AltArmyTBC_Options)
    else
        if AltArmyTBC_Options.showMinimapButton == nil then
            AltArmyTBC_Options.showMinimapButton = true
        end
    end
    if AltArmy and AltArmy.GlobalRealmFilter and AltArmy.GlobalRealmFilter.Ensure then
        AltArmy.GlobalRealmFilter.Ensure()
    end
    if AltArmy and AltArmy.CooldownData and AltArmy.CooldownData.EnsureCooldownOptions then
        AltArmy.CooldownData.EnsureCooldownOptions()
    end
    if AltArmy and AltArmy.GearUpgrade and AltArmy.GearUpgrade.EnsureGearUpgradeOptions then
        AltArmy.GearUpgrade.EnsureGearUpgradeOptions()
    end
    if AltArmy and AltArmy.Debug and AltArmy.Debug.Ensure then
        AltArmy.Debug.Ensure()
    end
end

local function minimapShown()
    local m = AltArmyTBC_Options.minimap
    if m and m.hide ~= nil then
        return not m.hide
    end
    return AltArmyTBC_Options.showMinimapButton ~= false
end

local function applyMinimapOption()
    ensureDefaults()
    if AltArmy.SetMinimapButtonShown then
        AltArmy.SetMinimapButtonShown(minimapShown())
    end
end

ensureDefaults()
applyMinimapOption()

--- InterfaceOptions checkboxes do not include the caption in their hit rect; forward label clicks.
function AltArmy.WireCheckboxLabelClick(checkButton, fontString)
    if not checkButton or not fontString then return end
    local hit = CreateFrame("Button", nil, checkButton)
    hit:SetFrameStrata(checkButton:GetFrameStrata() or "MEDIUM")
    hit:SetFrameLevel((checkButton:GetFrameLevel() or 0) + 5)
    hit:EnableMouse(true)
    hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    hit:SetScript("OnClick", function()
        if not checkButton:IsEnabled() then return end
        checkButton:Click()
    end)
    local function layout()
        hit:ClearAllPoints()
        hit:SetPoint("TOPLEFT", fontString, "TOPLEFT", -6, 6)
        hit:SetPoint("BOTTOMRIGHT", fontString, "BOTTOMRIGHT", 6, -6)
    end
    layout()
end

-- ---------------------------------------------------------------------------
-- Class icon helpers
-- Uses Interface\WorldStateFrame\Icons-Classes with CLASS_ICON_TCOORDS,
-- both guaranteed to exist in TBC Classic. Falls back to a class-colored
-- square when tcoords are unavailable (e.g. unknown class).
-- ---------------------------------------------------------------------------

-- Class color lookup via AltArmy.ClassColor (classFile -> r, g, b).
local CC = AltArmy.ClassColor

local CLASS_ICON_SHEET = "Interface\\WorldStateFrame\\Icons-Classes"

local function SetCharIcon(icon, iconFallback, classFile)
    local tcoords = CLASS_ICON_TCOORDS and classFile and CLASS_ICON_TCOORDS[classFile]
    if tcoords then
        icon:SetTexture(CLASS_ICON_SHEET)
        icon:SetTexCoord(tcoords[1], tcoords[2], tcoords[3], tcoords[4])
        icon:Show()
        iconFallback:Hide()
    else
        icon:SetTexture(nil)
        icon:Hide()
        if CC and CC.getRGBOr then
            local r, g, b = CC.getRGBOr(classFile, 0.5, 0.5, 0.5)
            iconFallback:SetColorTexture(r, g, b, 0.9)
        else
            iconFallback:SetColorTexture(0.5, 0.5, 0.5, 0.9)
        end
        iconFallback:Show()
    end
end

-- ---------------------------------------------------------------------------
-- Character list helpers
-- ---------------------------------------------------------------------------

local function IsCurrentCharacter(name, realm)
    local DS = AltArmy.DataStore
    return DS and DS.IsCurrentCharacter and DS:IsCurrentCharacter(name, realm)
end

local function GetSortedCharacters()
    local DS = AltArmy.DataStore
    if not DS or not DS.ForEachCharacter then return {} end
    local list = {}
    DS:ForEachCharacter(function(realm, charName, charData)
        list[#list + 1] = {
            name      = charData.name or charName,
            realm     = realm,
            classFile = charData.classFile or "",
        }
    end)
    table.sort(list, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.realm < b.realm
    end)
    return list
end

-- ---------------------------------------------------------------------------
-- Options panel
-- ---------------------------------------------------------------------------

local panel = CreateFrame("Frame")
AltArmy.OptionsPanel = panel
panel.name = "AltArmy"

panel.okay = function()
    ensureDefaults()
    applyMinimapOption()
end
panel.cancel = function()
    ensureDefaults()
    applyMinimapOption()
end
panel.default = function()
    AltArmyTBC_Options.showMinimapButton = true
    if AltArmyTBC_Options.minimap then
        AltArmyTBC_Options.minimap.hide = false
    end
    applyMinimapOption()
    if panel.minimapCheckbox then
        panel.minimapCheckbox:SetChecked(true)
    end
    if AltArmy.GlobalRealmFilter and AltArmy.GlobalRealmFilter.Set then
        AltArmy.GlobalRealmFilter.Set("currentRealm")
    end
    if panel.RefreshRealmFilterDropdown then
        panel.RefreshRealmFilterDropdown()
    end
    if AltArmy.CooldownData and AltArmy.CooldownData.ResetCooldownOptionsToDefaults then
        AltArmy.CooldownData.ResetCooldownOptionsToDefaults()
    end
    if panel.RefreshCooldownOptionsFromVars then
        panel.RefreshCooldownOptionsFromVars()
    end
    if panel.RefreshGearUpgradeOptionsFromVars then
        panel.RefreshGearUpgradeOptionsFromVars()
    end
end
panel.refresh = function()
    ensureDefaults()
    if panel.minimapCheckbox then
        panel.minimapCheckbox:SetChecked(minimapShown())
    end
    if panel.RefreshRealmFilterDropdown then
        panel.RefreshRealmFilterDropdown()
    end
    if panel.RefreshCooldownOptionsFromVars then
        panel.RefreshCooldownOptionsFromVars()
    end
    if panel.RefreshGearUpgradeOptionsFromVars then
        panel.RefreshGearUpgradeOptionsFromVars()
    end
end

-- ---------------------------------------------------------------------------
-- Header
-- ---------------------------------------------------------------------------

local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
header:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -12)
header:SetText("Alt Army")
Theme.SetTitleColor(header)

local LEFT_INSET = 16
local COL_GAP    = 20

-- ---------------------------------------------------------------------------
-- Tab strip (General / Characters / Gear / Cooldowns / Debug)
-- ---------------------------------------------------------------------------

local TAB_BAR_Y = -42
local TAB_CONTENT_TOP = -72
local TAB_BTN_W = 96
local TAB_BTN_H = 22

local tabGeneral = CreateFrame("Frame", nil, panel)
local tabCharacters = CreateFrame("Frame", nil, panel)
local tabCooldowns = CreateFrame("Frame", nil, panel)
local tabGearUpgrades = CreateFrame("Frame", nil, panel)
local tabDebug = CreateFrame("Frame", nil, panel)
tabGeneral:SetPoint("TOPLEFT", panel, "TOPLEFT", LEFT_INSET, TAB_CONTENT_TOP)
tabGeneral:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 12)
tabCharacters:SetAllPoints(tabGeneral)
tabCooldowns:SetAllPoints(tabGeneral)
tabGearUpgrades:SetAllPoints(tabGeneral)
tabDebug:SetAllPoints(tabGeneral)

local tabButtons = {}
local activeOptionsTab = "general"

local RefreshDebugCheckboxes
local RefreshDebugTabVisibility

local function SetActiveOptionsTab(which)
    activeOptionsTab = which
    tabGeneral:SetShown(which == "general")
    tabCharacters:SetShown(which == "characters")
    tabCooldowns:SetShown(which == "cooldowns")
    tabGearUpgrades:SetShown(which == "gearUpgrades")
    tabDebug:SetShown(which == "debug")
    for id, btn in pairs(tabButtons) do
        if btn and btn.SetSelected then
            btn:SetSelected(id == which)
        elseif btn and btn.SetAlpha then
            btn:SetAlpha(id == which and 1 or 0.55)
        end
    end
    if which == "gearUpgrades" then
        if AltArmy.BuildGearUpgradeOptionsUI then
            AltArmy.BuildGearUpgradeOptionsUI(panel)
        end
        if panel.UpdateGearUpgradeScrollRange then
            panel.UpdateGearUpgradeScrollRange()
        end
        if panel.RefreshGearUpgradeOptionsFromVars then
            panel.RefreshGearUpgradeOptionsFromVars()
        end
    end
    if which == "debug" and RefreshDebugCheckboxes then
        RefreshDebugCheckboxes()
    end
end

local tabBar = CreateFrame("Frame", nil, panel)
tabBar:SetPoint("TOPLEFT", panel, "TOPLEFT", LEFT_INSET, TAB_BAR_Y)
tabBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, TAB_BAR_Y)
tabBar:SetHeight(TAB_BTN_H)
local tabIds = { "general", "characters", "gearUpgrades", "cooldowns" }
local tabLabels = {
    general = "General",
    characters = "Characters",
    gearUpgrades = "Gear",
    cooldowns = "Cooldowns",
    debug = "Debug",
}
for i, id in ipairs(tabIds) do
    local b = CreateFrame("Button", nil, tabBar, "UIPanelButtonTemplate")
    b:SetSize(TAB_BTN_W, TAB_BTN_H)
    b:SetPoint("TOPLEFT", tabBar, "TOPLEFT", (i - 1) * (TAB_BTN_W + 4), 0)
    b:SetText(tabLabels[id] or id)
    Theme.SkinButton(b, true)
    b:SetScript("OnClick", function()
        SetActiveOptionsTab(id)
    end)
    tabButtons[id] = b
end

do
    local b = CreateFrame("Button", nil, tabBar, "UIPanelButtonTemplate")
    b:SetSize(TAB_BTN_W, TAB_BTN_H)
    b:SetPoint("TOPLEFT", tabBar, "TOPLEFT", 4 * (TAB_BTN_W + 4), 0)
    b:SetText("Debug")
    Theme.SkinButton(b, true)
    b:SetScript("OnClick", function()
        SetActiveOptionsTab("debug")
    end)
    b:Hide()
    tabButtons["debug"] = b
end

-- ---------------------------------------------------------------------------
-- Debug tab
-- ---------------------------------------------------------------------------

local debugSearchRow = Theme.CreateLabeledCheckbox(tabDebug, {
    point = "TOPLEFT",
    relativeTo = tabDebug,
    relativePoint = "TOPLEFT",
    x = 0,
    y = 0,
    text = "Search query timing",
    fullWidthHover = true,
    onClick = function(checked)
        if AltArmy.Debug and AltArmy.Debug.SetSearchEnabled then
            AltArmy.Debug.SetSearchEnabled(checked)
        end
    end,
})
panel.debugSearchCheckbox = debugSearchRow.check

local debugSearchHint = tabDebug:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
debugSearchHint:SetPoint("TOPLEFT", debugSearchRow, "BOTTOMLEFT", 0, -8)
debugSearchHint:SetWidth(520)
debugSearchHint:SetJustifyH("LEFT")
debugSearchHint:SetText("Logs search pipeline timing in chat when using the Search tab.")

local debugCooldownsRow = Theme.CreateLabeledCheckbox(tabDebug, {
    point = "TOPLEFT",
    relativeTo = debugSearchHint,
    relativePoint = "BOTTOMLEFT",
    x = 0,
    y = -16,
    text = "Profession cooldown scans",
    fullWidthHover = true,
    onClick = function(checked)
        if AltArmy.Debug and AltArmy.Debug.SetCooldownsEnabled then
            AltArmy.Debug.SetCooldownsEnabled(checked)
        end
    end,
})
panel.debugCooldownsCheckbox = debugCooldownsRow.check

local debugCooldownsHint = tabDebug:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
debugCooldownsHint:SetPoint("TOPLEFT", debugCooldownsRow, "BOTTOMLEFT", 0, -8)
debugCooldownsHint:SetWidth(520)
debugCooldownsHint:SetJustifyH("LEFT")
debugCooldownsHint:SetText("Logs cooldown persistence when opening profession windows (e.g. Tailoring).")

local debugLevelHistoryRow = Theme.CreateLabeledCheckbox(tabDebug, {
    point = "TOPLEFT",
    relativeTo = debugCooldownsHint,
    relativePoint = "BOTTOMLEFT",
    x = 0,
    y = -16,
    text = "Level history tracking",
    fullWidthHover = true,
    onClick = function(checked)
        if AltArmy.Debug and AltArmy.Debug.SetLevelHistoryEnabled then
            AltArmy.Debug.SetLevelHistoryEnabled(checked)
        end
    end,
})
panel.debugLevelHistoryCheckbox = debugLevelHistoryRow.check

local deleteAllHistoryConfirmPending = false

local debugDeleteAllHistoryBtn = CreateFrame("Button", nil, tabDebug, "UIPanelButtonTemplate")
debugDeleteAllHistoryBtn:SetSize(160, 22)
debugDeleteAllHistoryBtn:SetPoint("TOPLEFT", debugLevelHistoryRow, "BOTTOMLEFT", 0, -12)
debugDeleteAllHistoryBtn:SetText("Delete all history")
Theme.SkinDangerButton(debugDeleteAllHistoryBtn)
panel.debugDeleteAllHistoryBtn = debugDeleteAllHistoryBtn

local function ResetDeleteAllHistoryButton()
    deleteAllHistoryConfirmPending = false
    if panel.debugDeleteAllHistoryBtn then
        panel.debugDeleteAllHistoryBtn:SetText("Delete all history")
        panel.debugDeleteAllHistoryBtn:Enable()
    end
end

debugDeleteAllHistoryBtn:SetScript("OnClick", function(self)
    if deleteAllHistoryConfirmPending then
        deleteAllHistoryConfirmPending = false
        local DS = AltArmy and AltArmy.DataStore
        if DS and DS.DeleteAllLevelHistory then
            DS:DeleteAllLevelHistory()
        end
        self:SetText("Delete all history")
    else
        deleteAllHistoryConfirmPending = true
        self:SetText("Really Delete?")
    end
end)

local debugLevelHistoryHint = tabDebug:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
debugLevelHistoryHint:SetPoint("TOPLEFT", debugDeleteAllHistoryBtn, "BOTTOMLEFT", 0, -12)
debugLevelHistoryHint:SetWidth(520)
debugLevelHistoryHint:SetJustifyH("LEFT")
debugLevelHistoryHint:SetText("Logs level history import checks, decisions, and stored milestone summaries.")

local debugItemComparisonRow = Theme.CreateLabeledCheckbox(tabDebug, {
    point = "TOPLEFT",
    relativeTo = debugLevelHistoryHint,
    relativePoint = "BOTTOMLEFT",
    x = 0,
    y = -16,
    text = "Item comparison details",
    fullWidthHover = true,
    onClick = function(checked)
        if AltArmy.Debug and AltArmy.Debug.SetItemComparisonEnabled then
            AltArmy.Debug.SetItemComparisonEnabled(checked)
        end
    end,
})
panel.debugItemComparisonCheckbox = debugItemComparisonRow.check

local debugItemComparisonHint = tabDebug:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
debugItemComparisonHint:SetPoint("TOPLEFT", debugItemComparisonRow, "BOTTOMLEFT", 0, -8)
debugItemComparisonHint:SetWidth(520)
debugItemComparisonHint:SetJustifyH("LEFT")
debugItemComparisonHint:SetText(
    "Logs every comparison algorithm for each equippable alt when you loot an item or run /altarmy debug item.")

local debugItemStatsRow = Theme.CreateLabeledCheckbox(tabDebug, {
    point = "TOPLEFT",
    relativeTo = debugItemComparisonHint,
    relativePoint = "BOTTOMLEFT",
    x = 0,
    y = -16,
    text = "Item stat parsing details",
    fullWidthHover = true,
    onClick = function(checked)
        if AltArmy.Debug and AltArmy.Debug.SetItemStatsEnabled then
            AltArmy.Debug.SetItemStatsEnabled(checked)
        end
    end,
})
panel.debugItemStatsCheckbox = debugItemStatsRow.check

local debugItemStatsHint = tabDebug:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
debugItemStatsHint:SetPoint("TOPLEFT", debugItemStatsRow, "BOTTOMLEFT", 0, -8)
debugItemStatsHint:SetWidth(520)
debugItemStatsHint:SetJustifyH("LEFT")
debugItemStatsHint:SetText(
    "Logs API vs tooltip stat parsing when comparing items. Use /altarmy debug stats with an item on the cursor.")

function RefreshDebugCheckboxes()
    local D = AltArmy and AltArmy.Debug
    if not D or not D.Ensure then return end
    D.Ensure()
    local d = AltArmyTBC_Options.debug
    if panel.debugSearchCheckbox then
        panel.debugSearchCheckbox:SetChecked(d.search == true)
    end
    if panel.debugCooldownsCheckbox then
        panel.debugCooldownsCheckbox:SetChecked(d.cooldowns == true)
    end
    if panel.debugLevelHistoryCheckbox then
        panel.debugLevelHistoryCheckbox:SetChecked(d.levelHistory == true)
    end
    if panel.debugItemComparisonCheckbox then
        panel.debugItemComparisonCheckbox:SetChecked(d.itemComparison == true)
    end
    if panel.debugItemStatsCheckbox then
        panel.debugItemStatsCheckbox:SetChecked(d.itemStats == true)
    end
    ResetDeleteAllHistoryButton()
end
panel.RefreshDebugCheckboxes = RefreshDebugCheckboxes

function RefreshDebugTabVisibility()
    local D = AltArmy and AltArmy.Debug
    local btn = tabButtons["debug"]
    if not D or not D.IsEnabled or not btn then return end
    if D.IsEnabled() then
        btn:Show()
    else
        btn:Hide()
        if activeOptionsTab == "debug" then
            SetActiveOptionsTab("general")
        end
    end
end
panel.RefreshDebugTabVisibility = RefreshDebugTabVisibility

RefreshDebugTabVisibility()

-- ---------------------------------------------------------------------------
-- General tab
-- ---------------------------------------------------------------------------

local minimapRow = Theme.CreateLabeledCheckbox(tabGeneral, {
    point = "TOPLEFT",
    relativeTo = tabGeneral,
    relativePoint = "TOPLEFT",
    x = 0,
    y = 0,
    text = "Show Minimap Button",
    fullWidthHover = true,
    onClick = function(checked)
        AltArmyTBC_Options.showMinimapButton = checked
        if AltArmyTBC_Options.minimap then
            AltArmyTBC_Options.minimap.hide = not checked
        end
        applyMinimapOption()
    end,
})
panel.minimapCheckbox = minimapRow.check

local REALM_FILTER_MENU = {
    { value = "currentRealm", label = "Show characters from current realm" },
    { value = "all",          label = "Show characters from all realms" },
}

local function realmFilterEntries()
    local out = {}
    for i = 1, #REALM_FILTER_MENU do
        local entry = REALM_FILTER_MENU[i]
        out[i] = { id = entry.value, label = entry.label }
    end
    return out
end

local realmFilterDropdown = Theme.CreateSingleSelectDropdown({
    parent = tabGeneral,
    point = "TOPLEFT",
    relativeTo = minimapRow,
    relativePoint = "BOTTOMLEFT",
    x = 0,
    y = -14,
    width = 340,
    dropdownParent = tabGeneral,
    getEntries = realmFilterEntries,
    getSelectedId = function()
        local G = AltArmy.GlobalRealmFilter
        if G and G.Get then
            G.Ensure()
            return G.Get()
        end
        return "all"
    end,
    onSelect = function(id)
        local G = AltArmy.GlobalRealmFilter
        if G and G.Set then
            G.Set(id)
        end
    end,
})

local function RefreshRealmFilterDropdown()
    if realmFilterDropdown and realmFilterDropdown.Update then
        realmFilterDropdown:Update()
    end
end

RefreshRealmFilterDropdown()
panel.realmFilterDropdown = realmFilterDropdown
panel.RefreshRealmFilterDropdown = RefreshRealmFilterDropdown

local generalHint = tabGeneral:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
generalHint:SetPoint("TOPLEFT", realmFilterDropdown.button, "BOTTOMLEFT", 0, -10)
generalHint:SetWidth(520)
generalHint:SetJustifyH("LEFT")
generalHint:SetText(
    "Realm filter applies to Summary, Gear, Reputation, Search, Cooldowns, and Graphs tabs."
)

-- Host frame for UI/CooldownOptions.lua (loaded after this file)
panel.tabCooldownsHost = tabCooldowns
panel.tabGearUpgradesHost = tabGearUpgrades

-- ---------------------------------------------------------------------------
-- Selection state
-- ---------------------------------------------------------------------------

local selectedEntry        = nil   -- { name, realm } or nil
local deleteConfirmPending = false

-- Forward declarations
local RefreshCharacterList
local UpdateCharSettings

-- ---------------------------------------------------------------------------
-- Character scroll list (left column)
-- ---------------------------------------------------------------------------

local ROW_HEIGHT  = 20
local ROW_SPACING = 2
local ROW_STRIDE  = ROW_HEIGHT + ROW_SPACING
local ICON_SIZE   = 16
local LIST_HEIGHT = 220
local SCROLL_GUTTER = Theme.VerticalScrollBarGutter()

local charListFrame = CreateFrame("Frame", nil, tabCharacters, "BackdropTemplate")
Theme.ApplyBackdrop(charListFrame, "section")
charListFrame:SetPoint("TOPLEFT", tabCharacters, "TOPLEFT", 0, 0)
charListFrame:SetPoint("RIGHT",   tabCharacters, "CENTER", -COL_GAP / 2, 0)
charListFrame:SetHeight(LIST_HEIGHT)

-- ScrollFrame clips the visible area; scrollChild holds all rows.
local charListViewport = Theme.CreateVerticalScrollViewport({
    parent = charListFrame,
    gutterEdge = charListFrame,
    anchorTop = { "TOPLEFT", charListFrame, "TOPLEFT", 4, -4 },
    anchorBottom = { "BOTTOMRIGHT", charListFrame, "BOTTOMRIGHT", -SCROLL_GUTTER, 4 },
    wheelStep = ROW_STRIDE * 3,
    valueStep = ROW_STRIDE,
    enableMouseWheel = true,
    wheelOnChild = false,
    wheelSource = "slider",
    fallbackViewHeight = LIST_HEIGHT - 8,
})
local scrollChild = charListViewport.child

-- Row pool — rows are Buttons parked under charListFrame when pooled.
local rowPool    = {}
local activeRows = {}

local function AcquireRow()
    local row = table.remove(rowPool)
    if not row then
        row = CreateFrame("Button", nil, scrollChild)
        row:SetHeight(ROW_HEIGHT)

        Theme.InstallRowHoverHighlight(row)

        local selBg = row:CreateTexture(nil, "BACKGROUND")
        selBg:SetAllPoints(row)
        selBg:SetVertexColor(0, 0, 0, 0)
        selBg:Hide()
        row.selBg = selBg
        row.altArmyRowBg = selBg
        Theme.InstallRowAccentBar(row)

        -- Race/class icon
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.icon = icon

        -- Fallback colored square when no race texture is available
        local iconFallback = row:CreateTexture(nil, "ARTWORK")
        iconFallback:SetSize(ICON_SIZE, ICON_SIZE)
        iconFallback:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.iconFallback = iconFallback

        -- Name – Realm label (stretches full width; no delete button in the row)
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT",  icon, "RIGHT", 4, 0)
        label:SetPoint("RIGHT", row,  "RIGHT", -4, 0)
        label:SetJustifyH("LEFT")
        row.label = label
    end
    row:SetParent(scrollChild)
    row:Show()
    activeRows[#activeRows + 1] = row
    return row
end

local function ReleaseAllRows()
    for _, row in ipairs(activeRows) do
        row:Hide()
        row:SetParent(charListFrame)
        rowPool[#rowPool + 1] = row
    end
    activeRows = {}
end

local function RefreshCharacterList_impl()
    ReleaseAllRows()
    local chars = GetSortedCharacters()

    local totalH = math.max(1, #chars * ROW_STRIDE)
    scrollChild:SetHeight(totalH)
    charListViewport:UpdateRange()

    for i, entry in ipairs(chars) do
        local row = AcquireRow()
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  scrollChild, "TOPLEFT",  0, -(i - 1) * ROW_STRIDE)
        row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -(i - 1) * ROW_STRIDE)
        row:SetHeight(ROW_HEIGHT)

        -- Class icon
        SetCharIcon(row.icon, row.iconFallback, entry.classFile)

        local RF = AltArmy.RealmFilter
        if RF and RF.formatColoredCharacterNameRealm then
            row.label:SetTextColor(1, 1, 1, 1)
            row.label:SetText(RF.formatColoredCharacterNameRealm(
                entry.name or "",
                entry.realm,
                true,
                entry.classFile
            ))
        else
            local r, g, b = 1, 1, 1
            if CC and CC.getRGBOr then
                r, g, b = CC.getRGBOr(entry.classFile, r, g, b)
            end
            row.label:SetTextColor(r, g, b, 1)
            row.label:SetText((entry.name or "") .. " - " .. (entry.realm or ""))
        end

        -- Selection highlight
        local isSelected = selectedEntry
            and selectedEntry.name  == entry.name
            and selectedEntry.realm == entry.realm
        row.selBg:SetShown(isSelected == true)
        Theme.SetRowSelected(row, isSelected == true)

        -- Click: select this character and update the right pane
        local capName  = entry.name
        local capRealm = entry.realm
        row:SetScript("OnClick", function()
            selectedEntry = { name = capName, realm = capRealm }
            UpdateCharSettings()
            RefreshCharacterList()
        end)
    end
end

RefreshCharacterList = RefreshCharacterList_impl

-- ---------------------------------------------------------------------------
-- Right column: Character Settings pane
-- ---------------------------------------------------------------------------

-- "Choose a character to begin" shown when nothing is selected
local charSettingPrompt = tabCharacters:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
charSettingPrompt:SetPoint("TOPLEFT", tabCharacters, "TOP", COL_GAP / 2, 0)
charSettingPrompt:SetText("Choose a character to begin")
charSettingPrompt:Show()

-- Delete button shown whenever any character is selected;
-- disabled with "Can't delete self" when the current character is selected.
local charSettingDeleteBtn = CreateFrame("Button", nil, tabCharacters, "UIPanelButtonTemplate")
charSettingDeleteBtn:SetSize(160, 22)
charSettingDeleteBtn:SetPoint("TOPLEFT", tabCharacters, "TOP", COL_GAP / 2, 0)
charSettingDeleteBtn:SetText("Delete Data")
charSettingDeleteBtn:Hide()
Theme.SkinDangerButton(charSettingDeleteBtn)

charSettingDeleteBtn:SetScript("OnClick", function(self)
    if deleteConfirmPending then
        -- Second click: commit delete
        deleteConfirmPending = false
        if AltArmy.DataStore and AltArmy.DataStore.DeleteCharacter and selectedEntry then
            AltArmy.DataStore:DeleteCharacter(selectedEntry.name, selectedEntry.realm)
        end
        selectedEntry = nil
        RefreshCharacterList()
        UpdateCharSettings()
    else
        -- First click: enter confirm mode
        deleteConfirmPending = true
        self:SetText("Really Delete?")
    end
end)

UpdateCharSettings = function()
    local hasSelection = selectedEntry ~= nil
    local isSelf = hasSelection
        and IsCurrentCharacter(selectedEntry.name, selectedEntry.realm)
    charSettingPrompt:SetShown(not hasSelection)
    charSettingDeleteBtn:SetShown(hasSelection)
    -- Reset confirm state whenever the selection changes
    deleteConfirmPending = false
    if isSelf then
        charSettingDeleteBtn:SetText("Can't delete self")
        charSettingDeleteBtn:Disable()
    else
        charSettingDeleteBtn:SetText("Delete Data")
        charSettingDeleteBtn:Enable()
    end
end

SetActiveOptionsTab("general")

-- ---------------------------------------------------------------------------
-- Panel show/hide hooks
-- ---------------------------------------------------------------------------

-- Apply General / Characters / Cooldowns after Interface Options has actually shown our panel
-- (OpenToCategory often does not re-fire OnShow; IsShown() may be false until a later frame).
local tabApplyFrame = CreateFrame("Frame", nil, panel)
tabApplyFrame:Hide()

local function optionsHostIsOpen()
    local iof = _G.InterfaceOptionsFrame
    if not iof or not iof.IsShown then
        return true
    end
    return iof:IsShown()
end

local function scheduleApplyOptionsTab(tabId)
    if tabId ~= "characters" and tabId ~= "cooldowns" and tabId ~= "gearUpgrades" and tabId ~= "debug" then
        return
    end
    if tabId == "debug" and AltArmy.Debug and not AltArmy.Debug.IsEnabled() then
        return
    end
    tabApplyFrame:SetScript("OnUpdate", nil)
    tabApplyFrame:Hide()
    tabApplyFrame.tabId = tabId
    tabApplyFrame.attempts = 0
    tabApplyFrame:Show()
    tabApplyFrame:SetScript("OnUpdate", function(self)
        self.attempts = self.attempts + 1
        if panel:IsShown() and optionsHostIsOpen() then
            SetActiveOptionsTab(self.tabId)
            if self.tabId == "cooldowns" and panel.RefreshCooldownOptionsFromVars then
                panel.RefreshCooldownOptionsFromVars()
            end
            if self.tabId == "gearUpgrades" then
                if AltArmy.BuildGearUpgradeOptionsUI then
                    AltArmy.BuildGearUpgradeOptionsUI(panel)
                end
                if panel.RefreshGearUpgradeOptionsFromVars then
                    panel.RefreshGearUpgradeOptionsFromVars()
                end
            end
            if self.tabId == "debug" and panel.RefreshDebugCheckboxes then
                panel.RefreshDebugCheckboxes()
            end
            self:SetScript("OnUpdate", nil)
            self:Hide()
            return
        end
        if self.attempts > 300 then
            self:SetScript("OnUpdate", nil)
            self:Hide()
        end
    end)
end

panel:SetScript("OnHide", function()
    selectedEntry        = nil
    deleteConfirmPending = false
    tabApplyFrame:SetScript("OnUpdate", nil)
    tabApplyFrame:Hide()
    UpdateCharSettings()
end)

panel:HookScript("OnShow", function()
    RefreshCharacterList()
    UpdateCharSettings()
    if panel.minimapCheckbox then
        panel.minimapCheckbox:SetChecked(minimapShown())
    end
    if panel.RefreshRealmFilterDropdown then
        panel.RefreshRealmFilterDropdown()
    end
end)

-- ---------------------------------------------------------------------------
-- Register with WoW's options system on login
-- ---------------------------------------------------------------------------

local function registerOptionsPanel()
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "AltArmy")
        Settings.RegisterAddOnCategory(category)
        panel.altArmySettingsCategory = category
    end
    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        if InterfaceAddOnsList_Update then
            InterfaceAddOnsList_Update()
        end
    end
end

local reg = CreateFrame("Frame")
reg:RegisterEvent("PLAYER_LOGIN")
reg:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        reg:UnregisterEvent("PLAYER_LOGIN")
        registerOptionsPanel()
        RefreshCharacterList()
        UpdateCharSettings()
        if panel.minimapCheckbox then
            panel.minimapCheckbox:SetChecked(minimapShown())
        end
        if panel.RefreshRealmFilterDropdown then
            panel.RefreshRealmFilterDropdown()
        end
        if panel.RefreshDebugTabVisibility then
            panel.RefreshDebugTabVisibility()
        end
        if panel.RefreshDebugCheckboxes then
            panel.RefreshDebugCheckboxes()
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Slash command: open the main AltArmy UI
-- ---------------------------------------------------------------------------

SLASH_ALTARMY1, SLASH_ALTARMY2 = "/altarmy", "/alta"
SlashCmdList.ALTARMY = function(msg)
    local trimmed = (msg or ""):match("^%s*(.-)%s*$") or ""
    local lower = trimmed:lower()
    if lower == "debug on" then
        if AltArmy.Debug and AltArmy.Debug.SetEnabled then
            AltArmy.Debug.SetEnabled(true)
            if AltArmy.Debug.NotifyChat then
                AltArmy.Debug.NotifyChat("Debug options enabled")
            end
        end
        if panel.RefreshDebugTabVisibility then
            panel.RefreshDebugTabVisibility()
        end
        local gearFrame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Gear
        if gearFrame and gearFrame.RefreshGrid then
            gearFrame:RefreshGrid()
        end
        return
    end
    if lower == "debug off" then
        if AltArmy.Debug and AltArmy.Debug.SetEnabled then
            AltArmy.Debug.SetEnabled(false)
            if AltArmy.Debug.NotifyChat then
                AltArmy.Debug.NotifyChat("Debug options disabled")
            end
        end
        if panel.RefreshDebugTabVisibility then
            panel.RefreshDebugTabVisibility()
        end
        local gearFrame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Gear
        if gearFrame and gearFrame.RefreshGrid then
            gearFrame:RefreshGrid()
        end
        return
    end
    if lower == "debug remigrate recipes" then
        local DS = AltArmy and AltArmy.DataStore
        if not DS or not DS.RemigrateRecipePrimaryIdsDebug then
            if AltArmy.Debug and AltArmy.Debug.NotifyChat then
                AltArmy.Debug.NotifyChat("Recipe migration is unavailable.")
            end
            return
        end
        local updated = DS:RemigrateRecipePrimaryIdsDebug()
        if AltArmy.Debug and AltArmy.Debug.NotifyChat then
            AltArmy.Debug.NotifyChat(string.format(
                "Recipe primaryRecipeID migration re-ran (%d profession recipe group(s) updated).",
                updated
            ))
        end
        return
    end
    local debugLevelUp = trimmed:match("^[Dd]ebug [Ll]evelup%s+(%d+)$")
    if debugLevelUp then
        local GA = AltArmy and AltArmy.GearUpgradeAlerts
        if GA and GA.SimulateLevelUp then
            GA.SimulateLevelUp(tonumber(debugLevelUp))
        elseif AltArmy.Debug and AltArmy.Debug.NotifyChat then
            AltArmy.Debug.NotifyChat("Gear upgrade alerts are unavailable.")
        end
        return
    end
    local debugItemLink = trimmed:match("^[Dd]ebug [Ii]tem%s+(.+)$")
    if debugItemLink then
        local GA = AltArmy and AltArmy.GearUpgradeAlerts
        if GA and GA.SimulateSelfLoot then
            GA.SimulateSelfLoot(debugItemLink)
        elseif AltArmy.Debug and AltArmy.Debug.NotifyChat then
            AltArmy.Debug.NotifyChat("Gear upgrade alerts are unavailable.")
        end
        return
    end
    if lower == "debug dump" or lower == "debug dumpcompare" then
        local gearFrame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Gear
        if gearFrame and gearFrame.DumpComparePanelDebug then
            gearFrame:DumpComparePanelDebug()
        elseif AltArmy.Debug and AltArmy.Debug.NotifyChat then
            AltArmy.Debug.NotifyChat("Open the Gear tab with a focused item and compare selection.")
        end
        return
    end
    local debugStatsLink = trimmed:match("^[Dd]ebug [Ss]tats%s+(.+)$")
    if not debugStatsLink and lower == "debug stats" then
        if GetCursorInfo then
            local infoType, _, itemLink = GetCursorInfo()
            if infoType == "item" and itemLink then
                debugStatsLink = itemLink
            end
        end
    end
    if debugStatsLink or lower == "debug stats" then
        local IS = AltArmy and AltArmy.ItemStats
        local D = AltArmy and AltArmy.Debug
        if not IS or not IS.LogStatParseDebug then
            if D and D.NotifyChat then
                D.NotifyChat("Item stat parsing is unavailable.")
            end
            return
        end
        if not D or not D.IsItemStatsEnabled or not D.IsItemStatsEnabled() then
            if D and D.NotifyChat then
                D.NotifyChat("Enable Debug > Item stat parsing first (/altarmy debug on).")
            end
            return
        end
        if not debugStatsLink then
            if D and D.NotifyChat then
                D.NotifyChat("Put an item on the cursor or pass an item link: /altarmy debug stats <link>")
            end
            return
        end
        IS.LogStatParseDebug(debugStatsLink, { forceRefresh = true })
        return
    end
    if AltArmy and AltArmy.MainFrame then
        AltArmy.MainFrame:Show()
    end
end

AltArmy.OptionsPanel = panel

--- @param initialTab string|nil "general" (default), "characters", "cooldowns", or "debug"
function AltArmy.OpenInterfaceOptions(initialTab)
    if Settings and Settings.OpenToCategory and panel.altArmySettingsCategory then
        Settings.OpenToCategory(panel.altArmySettingsCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
    if initialTab == "characters" or initialTab == "cooldowns" or initialTab == "gearUpgrades"
        or (initialTab == "debug" and AltArmy.Debug and AltArmy.Debug.IsEnabled()) then
        scheduleApplyOptionsTab(initialTab)
    elseif panel:IsShown() and optionsHostIsOpen() then
        SetActiveOptionsTab("general")
    end
end
