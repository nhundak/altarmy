-- AltArmy TBC — Options panel (Interface > AddOns > AltArmy).
-- Two-column layout: character list + other settings (left), character settings (right).
-- SavedVariables: AltArmyTBC_Options (showMinimapButton, minimapAngle).

-- ---------------------------------------------------------------------------
-- Defaults / minimap helpers
-- ---------------------------------------------------------------------------

local function ensureDefaults()
    if not AltArmyTBC_Options then
        AltArmyTBC_Options = {}
        AltArmy.firstRun = true
    end
    if AltArmyTBC_Options.showMinimapButton == nil then
        AltArmyTBC_Options.showMinimapButton = true
    end
    if AltArmyTBC_Options.minimapAngle == nil then
        AltArmyTBC_Options.minimapAngle = 90
    end
    if AltArmy and AltArmy.GlobalRealmFilter and AltArmy.GlobalRealmFilter.Ensure then
        AltArmy.GlobalRealmFilter.Ensure()
    end
    if AltArmy and AltArmy.CooldownData and AltArmy.CooldownData.EnsureCooldownOptions then
        AltArmy.CooldownData.EnsureCooldownOptions()
    end
end

local function applyMinimapOption()
    ensureDefaults()
    if AltArmy.SetMinimapButtonShown then
        AltArmy.SetMinimapButtonShown(AltArmyTBC_Options.showMinimapButton)
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

-- Class color lookup (classFile -> r, g, b) — defined first so SetCharIcon can use it.
local CLASS_COLORS = {
    WARRIOR  = { 0.78, 0.61, 0.43 },
    PALADIN  = { 0.96, 0.55, 0.73 },
    HUNTER   = { 0.67, 0.83, 0.45 },
    ROGUE    = { 1.00, 0.96, 0.41 },
    PRIEST   = { 1.00, 1.00, 1.00 },
    SHAMAN   = { 0.00, 0.44, 0.87 },
    MAGE     = { 0.41, 0.80, 0.94 },
    WARLOCK  = { 0.58, 0.51, 0.79 },
    DRUID    = { 1.00, 0.49, 0.04 },
}

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
        local c = CLASS_COLORS[classFile]
        if c then
            iconFallback:SetColorTexture(c[1], c[2], c[3], 0.9)
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
    local curName = (UnitName and UnitName("player")) or (GetUnitName and GetUnitName("player")) or ""
    local curRealm = (GetRealmName and GetRealmName()) or ""
    return name == curName and realm == curRealm
end

local function GetSortedCharacters()
    local DS = AltArmy.DataStore
    if not DS or not DS.GetRealms then return {} end
    local list = {}
    for realm in pairs(DS:GetRealms()) do
        for charName, charData in pairs(DS:GetCharacters(realm)) do
            list[#list + 1] = {
                name      = charData.name or charName,
                realm     = realm,
                classFile = charData.classFile or "",
            }
        end
    end
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
end
panel.refresh = function()
    ensureDefaults()
    if panel.minimapCheckbox then
        panel.minimapCheckbox:SetChecked(AltArmyTBC_Options.showMinimapButton)
    end
    if panel.RefreshRealmFilterDropdown then
        panel.RefreshRealmFilterDropdown()
    end
    if panel.RefreshCooldownOptionsFromVars then
        panel.RefreshCooldownOptionsFromVars()
    end
end

-- ---------------------------------------------------------------------------
-- Header
-- ---------------------------------------------------------------------------

local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
header:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -12)
header:SetText("Alt Army")

local LEFT_INSET = 16
local COL_GAP    = 20

-- ---------------------------------------------------------------------------
-- Tab strip (General / Characters / Cooldowns)
-- ---------------------------------------------------------------------------

local TAB_BAR_Y = -42
local TAB_CONTENT_TOP = -72
local TAB_BTN_W = 120
local TAB_BTN_H = 22

local tabGeneral = CreateFrame("Frame", nil, panel)
local tabCharacters = CreateFrame("Frame", nil, panel)
local tabCooldowns = CreateFrame("Frame", nil, panel)
tabGeneral:SetPoint("TOPLEFT", panel, "TOPLEFT", LEFT_INSET, TAB_CONTENT_TOP)
tabGeneral:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 12)
tabCharacters:SetAllPoints(tabGeneral)
tabCooldowns:SetAllPoints(tabGeneral)

local tabButtons = {}
local function SetActiveOptionsTab(which)
    tabGeneral:SetShown(which == "general")
    tabCharacters:SetShown(which == "characters")
    tabCooldowns:SetShown(which == "cooldowns")
    for id, btn in pairs(tabButtons) do
        if btn and btn.SetAlpha then
            btn:SetAlpha(id == which and 1 or 0.55)
        end
    end
end

local tabBar = CreateFrame("Frame", nil, panel)
tabBar:SetPoint("TOPLEFT", panel, "TOPLEFT", LEFT_INSET, TAB_BAR_Y)
tabBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, TAB_BAR_Y)
tabBar:SetHeight(TAB_BTN_H)
local tabIds = { "general", "characters", "cooldowns" }
local tabLabels = { general = "General", characters = "Characters", cooldowns = "Cooldowns" }
for i, id in ipairs(tabIds) do
    local b = CreateFrame("Button", nil, tabBar, "UIPanelButtonTemplate")
    b:SetSize(TAB_BTN_W, TAB_BTN_H)
    b:SetPoint("TOPLEFT", tabBar, "TOPLEFT", (i - 1) * (TAB_BTN_W + 4), 0)
    b:SetText(tabLabels[id] or id)
    b:SetScript("OnClick", function()
        SetActiveOptionsTab(id)
    end)
    tabButtons[id] = b
end

-- ---------------------------------------------------------------------------
-- General tab
-- ---------------------------------------------------------------------------

local minimapCheckbox = CreateFrame("CheckButton", nil, tabGeneral, "InterfaceOptionsCheckButtonTemplate")
minimapCheckbox:SetPoint("TOPLEFT", tabGeneral, "TOPLEFT", 0, 0)
minimapCheckbox:SetScript("OnClick", function(self)
    AltArmyTBC_Options.showMinimapButton = self:GetChecked()
    applyMinimapOption()
end)
panel.minimapCheckbox = minimapCheckbox

local minimapLabel = minimapCheckbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
minimapLabel:SetPoint("LEFT", minimapCheckbox, "RIGHT", 4, 0)
minimapLabel:SetText("Show Minimap Button")
AltArmy.WireCheckboxLabelClick(minimapCheckbox, minimapLabel)

local REALM_FILTER_MENU = {
    { value = "currentRealm", label = "Show characters from current realm" },
    { value = "all",          label = "Show characters from all realms" },
}

local realmFilterDD = CreateFrame("Frame", "AltArmyTBC_RealmFilterDD", tabGeneral, "UIDropDownMenuTemplate")
realmFilterDD:SetPoint("TOPLEFT", minimapCheckbox, "BOTTOMLEFT", -16, -14)

local function RefreshRealmFilterDropdown()
    if not realmFilterDD or not UIDropDownMenu_SetText then return end
    local G = AltArmy.GlobalRealmFilter
    if not G or not G.Get then return end
    G.Ensure()
    local v = G.Get()
    local text = REALM_FILTER_MENU[1].label
    for i = 1, #REALM_FILTER_MENU do
        if REALM_FILTER_MENU[i].value == v then
            text = REALM_FILTER_MENU[i].label
            break
        end
    end
    UIDropDownMenu_SetText(realmFilterDD, text)
end

local function InitRealmFilterDropdown(dropdown)
    if not UIDropDownMenu_Initialize then return end
    UIDropDownMenu_SetWidth(dropdown, 340)
    UIDropDownMenu_Initialize(dropdown, function()
        if UIDropDownMenu_ClearMenu then
            UIDropDownMenu_ClearMenu(dropdown)
        end
        local G = AltArmy.GlobalRealmFilter
        if not G or not G.Set then return end
        for i = 1, #REALM_FILTER_MENU do
            local entry = REALM_FILTER_MENU[i]
            local info = UIDropDownMenu_CreateInfo()
            info.text = entry.label
            info.func = function()
                G.Set(entry.value)
                UIDropDownMenu_SetText(dropdown, entry.label)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
end

InitRealmFilterDropdown(realmFilterDD)
RefreshRealmFilterDropdown()
panel.realmFilterDropdown = realmFilterDD
panel.RefreshRealmFilterDropdown = RefreshRealmFilterDropdown

local generalHint = tabGeneral:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
generalHint:SetPoint("TOPLEFT", realmFilterDD, "BOTTOMLEFT", 16, -10)
generalHint:SetWidth(520)
generalHint:SetJustifyH("LEFT")
generalHint:SetText(
    "Realm filter applies to Summary, Gear, Reputation, Search, and Cooldowns tabs."
)

-- Host frame for UI/CooldownOptions.lua (loaded after this file)
panel.tabCooldownsHost = tabCooldowns

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
local SCROLLBAR_W = 14

local charListFrame = CreateFrame("Frame", nil, tabCharacters, "InsetFrameTemplate")
charListFrame:SetPoint("TOPLEFT", tabCharacters, "TOPLEFT", 0, 0)
charListFrame:SetPoint("RIGHT",   tabCharacters, "CENTER", -COL_GAP / 2, 0)
charListFrame:SetHeight(LIST_HEIGHT)

-- ScrollFrame clips the visible area; scrollChild holds all rows.
local scrollFrame = CreateFrame("ScrollFrame", nil, charListFrame)
scrollFrame:SetPoint("TOPLEFT",     charListFrame, "TOPLEFT",     4,                 -4)
scrollFrame:SetPoint("BOTTOMRIGHT", charListFrame, "BOTTOMRIGHT", -(SCROLLBAR_W + 6), 4)
scrollFrame:EnableMouseWheel(true)

local scrollChild = CreateFrame("Frame")
scrollChild:SetWidth(1)
scrollChild:SetHeight(1)
scrollFrame:SetScrollChild(scrollChild)

scrollFrame:SetScript("OnSizeChanged", function(_, w)
    scrollChild:SetWidth(w)
end)

-- Scrollbar
local scrollBar = CreateFrame("Slider", nil, charListFrame)
scrollBar:SetOrientation("VERTICAL")
scrollBar:SetPoint("TOPRIGHT",    charListFrame, "TOPRIGHT",    -4, -4)
scrollBar:SetPoint("BOTTOMRIGHT", charListFrame, "BOTTOMRIGHT", -4,  4)
scrollBar:SetWidth(SCROLLBAR_W)
scrollBar:SetMinMaxValues(0, 0)
scrollBar:SetValueStep(ROW_STRIDE)
scrollBar:SetValue(0)

local sbBg = scrollBar:CreateTexture(nil, "BACKGROUND")
sbBg:SetAllPoints(scrollBar)
sbBg:SetColorTexture(0.08, 0.08, 0.08, 0.8)

local sbThumb = scrollBar:CreateTexture(nil, "OVERLAY")
sbThumb:SetTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
sbThumb:SetSize(SCROLLBAR_W + 4, 24)
scrollBar:SetThumbTexture(sbThumb)

scrollBar:SetScript("OnValueChanged", function(_, value)
    scrollFrame:SetVerticalScroll(value)
end)

scrollFrame:SetScript("OnMouseWheel", function(_, delta)
    local cur = scrollBar:GetValue()
    local lo, hi = scrollBar:GetMinMaxValues()
    scrollBar:SetValue(math.max(lo, math.min(hi, cur - delta * ROW_STRIDE * 3)))
end)

-- Row pool — rows are Buttons parked under charListFrame when pooled.
local rowPool    = {}
local activeRows = {}

local function AcquireRow()
    local row = table.remove(rowPool)
    if not row then
        row = CreateFrame("Button", nil, scrollChild)
        row:SetHeight(ROW_HEIGHT)

        -- Hover highlight (gold shimmer, same feel as Syndicator's search-highlight)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

        -- Selection highlight (persistent tinted background for the selected row)
        local selBg = row:CreateTexture(nil, "BACKGROUND")
        selBg:SetAllPoints(row)
        selBg:SetColorTexture(0.3, 0.6, 1, 0.25)
        selBg:Hide()
        row.selBg = selBg

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
    local viewH = scrollFrame:GetHeight()
    if viewH <= 0 then viewH = LIST_HEIGHT - 8 end
    local maxScroll = math.max(0, totalH - viewH)
    local prevScroll = scrollBar:GetValue()
    scrollBar:SetMinMaxValues(0, maxScroll)
    scrollBar:SetValue(math.min(prevScroll, maxScroll))
    scrollBar:SetShown(maxScroll > 0)

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
            local rc = RAID_CLASS_COLORS and entry.classFile and RAID_CLASS_COLORS[entry.classFile]
            if rc then
                row.label:SetTextColor(rc.r, rc.g, rc.b, 1)
            else
                row.label:SetTextColor(1, 1, 1, 1)
            end
            row.label:SetText((entry.name or "") .. " - " .. (entry.realm or ""))
        end

        -- Selection highlight
        local isSelected = selectedEntry
            and selectedEntry.name  == entry.name
            and selectedEntry.realm == entry.realm
        row.selBg:SetShown(isSelected == true)

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
    if tabId ~= "characters" and tabId ~= "cooldowns" then
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
        panel.minimapCheckbox:SetChecked(AltArmyTBC_Options.showMinimapButton)
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
            panel.minimapCheckbox:SetChecked(AltArmyTBC_Options.showMinimapButton)
        end
        if panel.RefreshRealmFilterDropdown then
            panel.RefreshRealmFilterDropdown()
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Slash command: open the main AltArmy UI
-- ---------------------------------------------------------------------------

SLASH_ALTARMY1 = "/altarmy"
SlashCmdList.ALTARMY = function(_msg)
    if AltArmy and AltArmy.MainFrame then
        AltArmy.MainFrame:Show()
    end
end

AltArmy.OptionsPanel = panel

--- @param initialTab string|nil "general" (default), "characters", or "cooldowns"
function AltArmy.OpenInterfaceOptions(initialTab)
    if Settings and Settings.OpenToCategory and panel.altArmySettingsCategory then
        Settings.OpenToCategory(panel.altArmySettingsCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
    if initialTab == "characters" or initialTab == "cooldowns" then
        scheduleApplyOptionsTab(initialTab)
    elseif panel:IsShown() and optionsHostIsOpen() then
        SetActiveOptionsTab("general")
    end
end
