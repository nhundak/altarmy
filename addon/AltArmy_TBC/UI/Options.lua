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
end

local function applyMinimapOption()
    ensureDefaults()
    if AltArmy.SetMinimapButtonShown then
        AltArmy.SetMinimapButtonShown(AltArmyTBC_Options.showMinimapButton)
    end
end

ensureDefaults()
applyMinimapOption()

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
end
panel.refresh = function()
    ensureDefaults()
    if panel.minimapCheckbox then
        panel.minimapCheckbox:SetChecked(AltArmyTBC_Options.showMinimapButton)
    end
end

-- ---------------------------------------------------------------------------
-- Header
-- ---------------------------------------------------------------------------

local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
header:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -12)
header:SetText("Alt Army")

-- ---------------------------------------------------------------------------
-- Column layout constants
-- ---------------------------------------------------------------------------

local COL_GAP    = 20
local LEFT_INSET = 16
local TOP_INSET  = 50

-- ---------------------------------------------------------------------------
-- Left column header: Characters
-- ---------------------------------------------------------------------------

local charHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
charHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", LEFT_INSET, -TOP_INSET)
charHeader:SetText("Characters")

-- ---------------------------------------------------------------------------
-- Right column header: Character Settings
-- ---------------------------------------------------------------------------

local rightHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
rightHeader:SetPoint("TOPLEFT", panel, "TOP", COL_GAP / 2, -TOP_INSET)
rightHeader:SetText("Character Settings")

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

local charListFrame = CreateFrame("Frame", nil, panel, "InsetFrameTemplate")
charListFrame:SetPoint("TOPLEFT", charHeader, "BOTTOMLEFT", 0, -6)
charListFrame:SetPoint("RIGHT",   panel, "CENTER", -COL_GAP / 2, 0)
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

        local rc = RAID_CLASS_COLORS and entry.classFile and RAID_CLASS_COLORS[entry.classFile]
        if rc then
            row.label:SetTextColor(rc.r, rc.g, rc.b, 1)
        else
            row.label:SetTextColor(1, 1, 1, 1)
        end
        row.label:SetText(entry.name .. " - " .. entry.realm)

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
local charSettingPrompt = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
charSettingPrompt:SetPoint("TOPLEFT", rightHeader, "BOTTOMLEFT", 0, -12)
charSettingPrompt:SetText("Choose a character to begin")
charSettingPrompt:Show()

-- Delete button shown whenever any character is selected;
-- disabled with "Can't delete self" when the current character is selected.
local charSettingDeleteBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
charSettingDeleteBtn:SetSize(160, 22)
charSettingDeleteBtn:SetPoint("TOPLEFT", rightHeader, "BOTTOMLEFT", 0, -12)
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

-- ---------------------------------------------------------------------------
-- Left column: Other Settings (below character list)
-- ---------------------------------------------------------------------------

local otherHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
otherHeader:SetPoint("TOPLEFT", charListFrame, "BOTTOMLEFT", 0, -12)
otherHeader:SetText("Other Settings")

local minimapCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
minimapCheckbox:SetPoint("TOPLEFT", otherHeader, "BOTTOMLEFT", 0, -6)
minimapCheckbox:SetScript("OnClick", function(self)
    AltArmyTBC_Options.showMinimapButton = self:GetChecked()
    applyMinimapOption()
end)
panel.minimapCheckbox = minimapCheckbox

local minimapLabel = minimapCheckbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
minimapLabel:SetPoint("LEFT", minimapCheckbox, "RIGHT", 4, 0)
minimapLabel:SetText("Show Minimap Button")

-- ---------------------------------------------------------------------------
-- Panel show/hide hooks
-- ---------------------------------------------------------------------------

panel:SetScript("OnHide", function()
    selectedEntry        = nil
    deleteConfirmPending = false
    UpdateCharSettings()
end)

panel:HookScript("OnShow", function()
    RefreshCharacterList()
    UpdateCharSettings()
    if panel.minimapCheckbox then
        panel.minimapCheckbox:SetChecked(AltArmyTBC_Options.showMinimapButton)
    end
end)

-- ---------------------------------------------------------------------------
-- Register with WoW's options system on login
-- ---------------------------------------------------------------------------

local function registerOptionsPanel()
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "AltArmy")
        Settings.RegisterAddOnCategory(category)
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
