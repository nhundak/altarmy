-- AltArmy TBC — Gear tab: "Who can use this?" drop box + equipment grid (slot rows x character columns)

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Gear
if not frame then return end

local DS = AltArmy.DataStore
local Theme = AltArmy.Theme
local CC = AltArmy.ClassColor
local GearScoreMod = AltArmy.GearScore
local SD = AltArmy.SummaryData
local SSR = AltArmy.ScoreSortRow
local TruncateFontString = AltArmy.Text and AltArmy.Text.TruncateFontString
local PAD = 4
local SECTION_INSET = Theme.TAB_SECTION_INSET
local SECTION_GAP = Theme.SECTION_GAP
local LEFT_PANEL_WIDTH = 120
local LEFT_PANEL_VISIBLE = false  -- set true to show "Who can use this?" drop zone
local MESSAGE_ROW_HEIGHT = 12
local SETTINGS_ROW_HEIGHT = 22
-- Base cell size was 28; icon size (medium 32px) + glow inset in dims.cellSize
local NUM_EQUIPMENT_SLOTS = 19

-- Equipment slot ID -> display name (TBC slots 1-19; ranged slot holds ranged weapons/relics; ammo omitted)
local SLOT_NAMES = {
    [1] = "Head",
    [2] = "Neck",
    [3] = "Shoulder",
    [4] = "Shirt",
    [5] = "Chest",
    [6] = "Waist",
    [7] = "Legs",
    [8] = "Feet",
    [9] = "Wrist",
    [10] = "Hands",
    [11] = "Finger 1",
    [12] = "Finger 2",
    [13] = "Trinket 1",
    [14] = "Trinket 2",
    [15] = "Back",
    [16] = "Main Hand",
    [17] = "Off Hand",
    [18] = "Ranged/Relic",
    [19] = "Tabard",
}

-- Display order of rows: Main Hand, Off Hand, Ranged at top; Shirt, Tabard at bottom.
-- Each entry is WoW inventory slot ID (1–19).
local SLOT_ORDER = {
    16, 17, 18,   -- Main Hand, Off Hand, Ranged
    1, 2, 3, 5,   -- Head, Neck, Shoulder, Chest
    15,           -- Back
    9, 10,        -- Wrist, Hands
    6, 7, 8,      -- Waist, Legs, Feet
    11, 12, 13, 14,   -- Finger 1, Finger 2, Trinket 1, Trinket 2
    4, 19,        -- Shirt, Tabard
}

-- State: dropped item link (nil = use default sort by level)
local droppedItemLink = nil

-- Gear settings persistence (AltArmyTBC_GearSettings)
local DEFAULT_SCORE_PROVIDER = "level"
local SLOT_LABEL_WIDTH = 98
local SCORE_SORT_BTN_GAP = 2
local SCORE_ROW_LAYOUT_TRIM = 4
local SCORE_ROW_HEADER_BOTTOM_INSET = 6

local function GetAvailableScoreProviders()
    return SSR.GetAvailableProviders()
end

local function ValidateScoreProvider(id)
    return SSR.ValidateProvider(id)
end

local function GetGearSettings()
    AltArmyTBC_GearSettings = AltArmyTBC_GearSettings or {}
    local s = AltArmyTBC_GearSettings
    if s.showSelfFirst == nil then s.showSelfFirst = true end
    if s.scoreSortDescending == nil then s.scoreSortDescending = true end
    s.scoreProvider = ValidateScoreProvider(s.scoreProvider or DEFAULT_SCORE_PROVIDER)
    s.characters = s.characters or {}
    return s
end

local function GetSelectedScoreProvider()
    local s = GetGearSettings()
    return ValidateScoreProvider(s.scoreProvider or DEFAULT_SCORE_PROVIDER)
end

local function GetScoreProviderLabel(providerId)
    return SSR.GetProviderLabel(providerId)
end

--- Fixed layout: Normal spacing (12px row/column gaps) and medium icons (32px).
local function GetSpacingGaps()
    return 12, 12
end

local function GetIconSizePx()
    return 32
end

local ITEM_GLOW_ALPHA = 0.4
local ITEM_ICON_INSET = 2

--- Cell frame size: icon plus inset on each side for rarity glow ring.
local function GetCellSizePx()
    return GetIconSizePx() + 2 * ITEM_ICON_INSET
end

--- Returns rowHeight, columnWidth for current spacing and cell size.
local function GetSpacingDimensions()
    local rowGap, colGap = GetSpacingGaps()
    local cell = GetCellSizePx()
    return cell + rowGap, cell + colGap
end

local dims = {}

local function GetScoreRowContentHeight()
    local rh = dims.rowHeight or select(1, GetSpacingDimensions())
    return math.floor(rh / 2)
end

local function GetScoreRowHeight()
    return GetScoreRowContentHeight() - SCORE_ROW_LAYOUT_TRIM
end

local function GetScoreSortBtnSize()
    return GetScoreRowContentHeight()
end

local function GetScrollableGridHeight()
    local rh = dims.rowHeight or select(1, GetSpacingDimensions())
    return NUM_EQUIPMENT_SLOTS * rh + PAD
end

local CharKey = AltArmy.CharKey

local function GetCharSetting(name, realm, key)
    local s = GetGearSettings()
    local c = s.characters[CharKey(name, realm)]
    if not c then return false end
    return c[key] == true
end

local function SetCharSetting(name, realm, pin, hide)
    local s = GetGearSettings()
    local key = CharKey(name, realm)
    s.characters[key] = { pin = pin == true, hide = hide == true }
end

--- True if this class can ever wear this armor subclass (TBC rules). subclass = "Cloth"|"Leather"|"Mail"|"Plate".
local function CanClassEverUseArmor(classFile, subclass)
    if not subclass or subclass == "" then return true end
    classFile = (classFile or ""):upper()
    subclass = subclass:lower()
    if subclass == "cloth" then return true end
    if subclass == "leather" then
        return classFile ~= "MAGE" and classFile ~= "PRIEST" and classFile ~= "WARLOCK"
    end
    if subclass == "mail" then
        return classFile == "HUNTER" or classFile == "SHAMAN" or classFile == "WARRIOR" or classFile == "PALADIN"
    end
    if subclass == "plate" then
        return classFile == "WARRIOR" or classFile == "PALADIN"
    end
    return true
end

-- TBC class weapon proficiencies (GetItemInfo weapon subclass: "One-Handed Axes", "Daggers", "Staves", etc.)
-- Subclass strings normalized to lowercase for comparison.
local WEAPON_PROFICIENCIES = {
    WARRIOR = {
        ["one-handed axes"] = true, ["two-handed axes"] = true,
        ["one-handed maces"] = true, ["two-handed maces"] = true,
        ["one-handed swords"] = true, ["two-handed swords"] = true,
        ["daggers"] = true, ["fist weapons"] = true, ["polearms"] = true, ["staves"] = true,
        ["bows"] = true, ["crossbows"] = true, ["guns"] = true, ["thrown"] = true,
        -- no wands
    },
    PALADIN = {
        ["one-handed axes"] = true, ["two-handed axes"] = true,
        ["one-handed maces"] = true, ["two-handed maces"] = true,
        ["one-handed swords"] = true, ["two-handed swords"] = true,
    },
    HUNTER = {
        ["one-handed axes"] = true, ["two-handed axes"] = true,
        ["one-handed swords"] = true, ["two-handed swords"] = true,
        ["polearms"] = true, ["staves"] = true, ["daggers"] = true,
        ["bows"] = true, ["crossbows"] = true, ["guns"] = true,
    },
    ROGUE = {
        ["daggers"] = true, ["fist weapons"] = true,
        ["one-handed swords"] = true, ["one-handed maces"] = true,
        ["bows"] = true, ["crossbows"] = true, ["guns"] = true, ["thrown"] = true,
    },
    DRUID = {
        ["daggers"] = true, ["fist weapons"] = true, ["staves"] = true, ["one-handed maces"] = true,
    },
    SHAMAN = {
        ["one-handed axes"] = true, ["two-handed axes"] = true,
        ["one-handed maces"] = true, ["two-handed maces"] = true,
        ["daggers"] = true, ["fist weapons"] = true, ["staves"] = true,
    },
    MAGE = {
        ["daggers"] = true, ["one-handed swords"] = true, ["staves"] = true, ["wands"] = true,
    },
    PRIEST = {
        ["daggers"] = true, ["one-handed maces"] = true, ["staves"] = true, ["wands"] = true,
    },
    WARLOCK = {
        ["daggers"] = true, ["one-handed swords"] = true, ["staves"] = true, ["wands"] = true,
    },
}

--- True if this class can ever use this weapon subclass (TBC rules).
--- subclass = GetItemInfo subclass e.g. "One-Handed Swords".
local function CanClassEverUseWeapon(classFile, weaponSubclass)
    if not weaponSubclass or weaponSubclass == "" then return true end
    local key = weaponSubclass:lower()
    if key == "fishing pole" then return true end
    classFile = (classFile or ""):upper()
    local prof = WEAPON_PROFICIENCIES[classFile]
    if not prof then return true end
    return prof[key] == true
end

--- Get item info for "who can use" sort. Returns reqLevel, armorSubclass (or nil), weaponSubclass (or nil).
local function GetItemUseInfo(link)
    if not link or not GetItemInfo then return nil, nil, nil end
    local name, _, _, _, reqLevel, itemClass, subclass = GetItemInfo(link)
    if not name then return nil, nil, nil end
    reqLevel = tonumber(reqLevel) or 0
    local ic = itemClass and itemClass:lower() or ""
    -- Armor: subclass = "Cloth", "Leather", "Mail", "Plate"
    if ic == "armor" or ic == "armour" then
        return reqLevel, subclass, nil
    end
    -- Weapon: subclass = "One-Handed Axes", "Daggers", "Staves", etc.
    if ic == "weapon" then
        return reqLevel, nil, subclass
    end
    return reqLevel, subclass, nil
end

local function CompareBySelectedScore(entryA, entryB, providerId, descending)
    return SSR.Compare(entryA, entryB, providerId, descending)
end

local function DecorateDisplayEntry(entry)
    SSR.DecorateEntry(entry)
end

--- Build display list: filter hidden; order = pinned (incl. current when pin-current) + non-pinned.
--- Optionally re-sort by "who can use" when item dropped.
local function GetDisplayList()
    if not AltArmy.Characters or not AltArmy.Characters.GetList then return {} end
    local rawList = AltArmy.Characters:GetList()
    if #rawList == 0 then return rawList end

    local settings = GetGearSettings()
    local currentRealm = DS and DS.GetCurrentPlayerRealm and DS:GetCurrentPlayerRealm() or ""
    local showSelfFirst = settings.showSelfFirst ~= false

    -- Filter out hidden (pin-current-character overrides hide for the signed-in character)
    local visible = {}
    for i = 1, #rawList do
        local e = rawList[i]
        local isSelf = DS and DS.IsCurrentCharacter and DS:IsCurrentCharacter(e.name, e.realm)
        local isHidden = GetCharSetting(e.name, e.realm, "hide")
        if not isHidden or (showSelfFirst and isSelf) then
            visible[#visible + 1] = e
            DecorateDisplayEntry(e)
        end
    end

    local providerId = GetSelectedScoreProvider()
    local descending = settings.scoreSortDescending ~= false

    -- Split: pinned (manual pin or pin-current-character), non-pinned
    local pinned = {}
    local nonPinned = {}
    for i = 1, #visible do
        local e = visible[i]
        local isSelf = DS and DS.IsCurrentCharacter and DS:IsCurrentCharacter(e.name, e.realm)
        local isPinned = GetCharSetting(e.name, e.realm, "pin")
        if isPinned or (showSelfFirst and isSelf) then
            pinned[#pinned + 1] = e
        else
            nonPinned[#nonPinned + 1] = e
        end
    end

    table.sort(pinned, function(a, b)
        return CompareBySelectedScore(a, b, providerId, descending)
    end)
    table.sort(nonPinned, function(a, b)
        return CompareBySelectedScore(a, b, providerId, descending)
    end)

    local list = {}
    for i = 1, #pinned do list[#list + 1] = pinned[i] end
    for i = 1, #nonPinned do list[#list + 1] = nonPinned[i] end

    local RF = AltArmy.RealmFilter
    local realmFilter = "all"
    local GRF = AltArmy.GlobalRealmFilter
    if GRF and GRF.Get then
        realmFilter = GRF.Get()
    end
    if RF and RF.filterListByRealm then
        list = RF.filterListByRealm(list, realmFilter, currentRealm)
    end

    -- When item dropped, re-sort by "who can use" then level/name (overrides column order for fit)
    if not droppedItemLink then return list end
    local reqLevel, armorSubclass, weaponSubclass = GetItemUseInfo(droppedItemLink)
    if reqLevel == nil and armorSubclass == nil and weaponSubclass == nil then return list end
    reqLevel = reqLevel or 0

    local function score(entry)
        local classFile = (entry.classFile or ""):upper()
        local charLevel = math.floor(tonumber(entry.level) or 0)
        local canUseArmor = CanClassEverUseArmor(classFile, armorSubclass)
        local canUseWeapon = CanClassEverUseWeapon(classFile, weaponSubclass)
        if not canUseArmor or not canUseWeapon then
            return 999999, charLevel, entry.name or ""
        end
        local levelDelta = math.abs(charLevel - reqLevel)
        return levelDelta, -charLevel, entry.name or ""
    end

    local copy = {}
    for i = 1, #list do copy[i] = list[i] end
    table.sort(copy, function(a, b)
        local sa, lva, na = score(a)
        local sb, lvb, nb = score(b)
        if sa ~= sb then return sa < sb end
        if lva ~= lvb then return lva > lvb end
        return na < nb
    end)
    return copy
end

--- True if this entry can never equip the current dropped item (for graying).
local function CanNeverUseCurrentItem(entry)
    if not droppedItemLink then return false end
    local _, armorSubclass, weaponSubclass = GetItemUseInfo(droppedItemLink)
    if armorSubclass and armorSubclass ~= "" then
        if not CanClassEverUseArmor(entry.classFile, armorSubclass) then return true end
    end
    if weaponSubclass and weaponSubclass ~= "" then
        if not CanClassEverUseWeapon(entry.classFile, weaponSubclass) then return true end
    end
    return false
end

--- Brief fit message for column: nil or "", or "Can not wear plate" / "10 levels ahead" etc.
--- Returns message, color ("red" | "orange" | nil).
local function GetFitMessage(entry)
    if not droppedItemLink then return nil, nil end
    local reqLevel, armorSubclass, weaponSubclass = GetItemUseInfo(droppedItemLink)
    if reqLevel == nil and armorSubclass == nil and weaponSubclass == nil then
        return nil, nil
    end
    reqLevel = reqLevel or 0
    local classFile = (entry.classFile or ""):upper()
    local charLevel = math.floor(tonumber(entry.level) or 0)

    if armorSubclass and armorSubclass ~= "" then
        if not CanClassEverUseArmor(classFile, armorSubclass) then
            return "Can not wear " .. armorSubclass:lower(), "red"
        end
    end
    if weaponSubclass and weaponSubclass ~= "" then
        if not CanClassEverUseWeapon(classFile, weaponSubclass) then
            return "Can not use " .. weaponSubclass:lower(), "red"
        end
    end

    local delta = charLevel - reqLevel
    if delta > 0 then
        return delta == 1 and "1 level ahead" or (delta .. " levels ahead"), "orange"
    elseif delta < 0 then
        local absDelta = math.abs(delta)
        return absDelta == 1 and "1 level behind" or (absDelta .. " levels behind"), "orange"
    end
    return nil, nil
end

--- Resolve item to texture path for display (itemID or link).
local function GetItemTexture(itemIDOrLink)
    if not itemIDOrLink then return nil end
    if not GetItemInfo then return nil end
    local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemIDOrLink)
    return texture
end

--- Item quality from GetItemInfo (0=poor, 1=common, 2=uncommon, 3=rare, 4=epic, 5=legendary).
local function GetItemQuality(itemIDOrLink)
    if not itemIDOrLink or not GetItemInfo then return nil end
    local _, _, quality = GetItemInfo(itemIDOrLink)
    return quality
end

--- Glow color for uncommon–legendary; nil for poor/common or unknown quality.
local function GetQualityGlowColor(quality)
    if quality == nil or quality < 2 or quality > 5 then return nil end
    if ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
        local c = ITEM_QUALITY_COLORS[quality]
        return c.r, c.g, c.b
    end
    if quality == 2 then return 0, 1, 0 end
    if quality == 3 then return 0, 0.44, 0.87 end
    if quality == 4 then return 0.64, 0.21, 0.93 end
    return 1, 0.5, 0
end

local function ApplyItemCellVisual(cell, item, gray)
    local texPath = GetItemTexture(item)
    if texPath then
        cell.texture:SetTexture(texPath)
        cell.texture:Show()
        if gray then
            cell.texture:SetVertexColor(0.5, 0.5, 0.5, 1)
        else
            cell.texture:SetVertexColor(1, 1, 1, 1)
        end
    else
        cell.texture:SetTexture(nil)
        cell.texture:Hide()
    end

    local gr, gg, gb = GetQualityGlowColor(GetItemQuality(item))
    if gr and texPath and cell.glow then
        cell.glow:SetColorTexture(gr, gg, gb, ITEM_GLOW_ALPHA)
        if gray then
            cell.glow:SetVertexColor(0.5, 0.5, 0.5, 1)
        else
            cell.glow:SetVertexColor(1, 1, 1, 1)
        end
        cell.glow:Show()
    elseif cell.glow then
        cell.glow:Hide()
    end
end

local ItemActions = AltArmy.ItemActions

--- Route a left-click on an item cell: Ctrl previews in the Dressing Room, Shift links to chat.
local function HandleItemCellClick(itemLinkOrID, button)
    if not ItemActions then return end
    local action = ItemActions.GetClickAction(
        button,
        IsShiftKeyDown and IsShiftKeyDown() or false,
        IsControlKeyDown and IsControlKeyDown() or false)
    if action == "preview" then
        ItemActions.PreviewInDressingRoom(itemLinkOrID)
    elseif action == "chatlink" then
        ItemActions.InsertLinkIntoChat(itemLinkOrID)
    end
end

-- ---- Tab content panel (bordered; same styling as settings panel) ----
local tabContentPanel = Theme.CreateTabContentPanel(frame)
tabContentPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", SECTION_INSET, -SECTION_INSET)
tabContentPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SECTION_INSET, SECTION_INSET)
local tabContentInner = Theme.CreatePanelInnerContent(tabContentPanel)

-- ---- Left panel ----
local leftPanel = CreateFrame("Frame", nil, tabContentInner)
leftPanel:SetPoint("TOPLEFT", tabContentInner, "TOPLEFT", 0, 0)
leftPanel:SetPoint("BOTTOMLEFT", tabContentInner, "BOTTOMLEFT", 0, 0)
leftPanel:SetWidth(LEFT_PANEL_WIDTH)

local labelWho = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
labelWho:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 0, 0)
labelWho:SetText("Who can use this?")

local dropBox = CreateFrame("Frame", "AltArmyTBC_GearDropBox", leftPanel, "BackdropTemplate")
dropBox:SetSize(40, 40)
dropBox:SetPoint("TOPLEFT", labelWho, "BOTTOMLEFT", 0, -4)
dropBox:EnableMouse(true)
Theme.ApplyBackdrop(dropBox, "section")

local dropBoxIcon = dropBox:CreateTexture(nil, "OVERLAY")
dropBoxIcon:SetPoint("CENTER", dropBox, "CENTER", 0, 0)
dropBoxIcon:SetSize(32, 32)
dropBoxIcon:Hide()

local function tryAcceptCursorItem()
    if not GetCursorInfo then return end
    local infoType, _, itemLink = GetCursorInfo()
    if infoType == "item" and itemLink then
        droppedItemLink = itemLink
        if ClearCursor then ClearCursor() end
        local tex = GetItemTexture(itemLink)
        if tex then
            dropBoxIcon:SetTexture(tex)
            dropBoxIcon:Show()
        else
            dropBoxIcon:Hide()
        end
        if frame.RefreshGrid then frame:RefreshGrid() end
        return true
    end
    return false
end

dropBox:SetScript("OnReceiveDrag", function()
    tryAcceptCursorItem()
end)
dropBox:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then
        droppedItemLink = nil
        dropBoxIcon:Hide()
        if frame.RefreshGrid then frame:RefreshGrid() end
        return
    end
    tryAcceptCursorItem()
end)
if not LEFT_PANEL_VISIBLE then
    leftPanel:Hide()
end

-- ---- Right panel: slot row headers + scrollable character columns ----
local COLUMN_HEADER_HEIGHT_GEAR = 18
local SCORE_PROVIDER_DROPDOWN_WIDTH = 200
local SCROLL_GUTTER = Theme.VerticalScrollBarGutter()
local FIXED_HEADER_ROW_HEIGHT = COLUMN_HEADER_HEIGHT_GEAR + MESSAGE_ROW_HEIGHT

local function GetPinnedHeaderHeight()
    return FIXED_HEADER_ROW_HEIGHT + GetScoreRowHeight()
end
-- Layout dimensions from spacing + icon size
do
    dims.cellSize = GetCellSizePx()
    local rh, cw = GetSpacingDimensions()
    dims.rowHeight, dims.columnWidth = rh, cw
    dims.scrollableGridHeight = GetScrollableGridHeight()
end

local rightPanel = CreateFrame("Frame", nil, tabContentInner)
if LEFT_PANEL_VISIBLE then
    rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", PAD, 0)
else
    rightPanel:SetPoint("TOPLEFT", tabContentInner, "TOPLEFT", 0, 0)
end
rightPanel:SetPoint("BOTTOMRIGHT", tabContentInner, "BOTTOMRIGHT", 0, 0)

local HORIZONTAL_SCROLL_BAR_HEIGHT = 20

-- Content area: full height except scroll bars; fixed header will sit at top of this
local contentArea = CreateFrame("Frame", nil, rightPanel)
contentArea:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 0, -PAD)
contentArea:SetPoint("BOTTOMRIGHT", tabContentPanel, "BOTTOMRIGHT", -SCROLL_GUTTER,
    HORIZONTAL_SCROLL_BAR_HEIGHT)

-- Vertical scroll: full content area; scroll child has spacer at top so header can overlay
local verticalScroll = CreateFrame("ScrollFrame", "AltArmyTBC_GearVerticalScroll", contentArea)
verticalScroll:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 0, 0)
verticalScroll:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", 0, 0)
verticalScroll:EnableMouse(true)

-- Scroll child: spacer at top (header overlays it) + slot labels + cell grid
local MIN_SCROLL_CHILD_WIDTH = 400
local verticalScrollChild = CreateFrame("Frame", nil, verticalScroll)
verticalScrollChild:SetPoint("TOPLEFT", verticalScroll, "TOPLEFT", 0, 0)
verticalScrollChild:SetHeight(GetPinnedHeaderHeight() + dims.scrollableGridHeight)
verticalScrollChild:SetWidth(MIN_SCROLL_CHILD_WIDTH)
verticalScrollChild:EnableMouse(true)
verticalScroll:SetScrollChild(verticalScrollChild)

-- Spacer at top of scroll child so first row of content sits below where header will overlay
local scrollTopSpacer = CreateFrame("Frame", nil, verticalScrollChild)
scrollTopSpacer:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", 0, 0)
scrollTopSpacer:SetPoint("TOPRIGHT", verticalScrollChild, "TOPRIGHT", 0, 0)
scrollTopSpacer:SetHeight(GetPinnedHeaderHeight())

-- Fixed header row: character names + score row pinned; scrolls horizontally with grid
local fixedHeaderRow = CreateFrame("Frame", nil, contentArea)
fixedHeaderRow:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 0, 0)
fixedHeaderRow:SetPoint("TOPRIGHT", contentArea, "TOPRIGHT", 0, 0)
fixedHeaderRow:SetHeight(GetPinnedHeaderHeight())
fixedHeaderRow:SetFrameLevel(contentArea:GetFrameLevel() + 20)
-- Opaque background so scrolling content doesn't show through; extend slightly above, stop short at bottom
local HEADER_BG_OVERHANG = 6
local HEADER_BG_BOTTOM_INSET = 6
local headerBg = fixedHeaderRow:CreateTexture(nil, "BACKGROUND")
headerBg:SetPoint("BOTTOMLEFT", fixedHeaderRow, "BOTTOMLEFT", 0, HEADER_BG_BOTTOM_INSET)
headerBg:SetPoint("BOTTOMRIGHT", fixedHeaderRow, "BOTTOMRIGHT", 0, HEADER_BG_BOTTOM_INSET)
headerBg:SetPoint("TOPLEFT", fixedHeaderRow, "TOPLEFT", 0, HEADER_BG_OVERHANG)
headerBg:SetPoint("TOPRIGHT", fixedHeaderRow, "TOPRIGHT", 0, HEADER_BG_OVERHANG)
Theme.StyleGridHeader(headerBg)
fixedHeaderRow:EnableMouse(true)
local headerCornerColumn = CreateFrame("Frame", nil, fixedHeaderRow)
headerCornerColumn:SetPoint("TOPLEFT", fixedHeaderRow, "TOPLEFT", 0, 0)
headerCornerColumn:SetPoint("BOTTOMLEFT", fixedHeaderRow, "BOTTOMLEFT", 0, 0)
headerCornerColumn:SetWidth(SLOT_LABEL_WIDTH)
local headerCornerCell = headerCornerColumn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
headerCornerCell:SetPoint("TOPLEFT", headerCornerColumn, "TOPLEFT", 0, 0)
headerCornerCell:SetWidth(SLOT_LABEL_WIDTH - 4)
headerCornerCell:SetHeight(FIXED_HEADER_ROW_HEIGHT)
headerCornerCell:SetJustifyH("LEFT")
headerCornerCell:SetText("")
local headerHorizontalScroll = CreateFrame("ScrollFrame", "AltArmyTBC_GearHeaderHorizontalScroll", fixedHeaderRow)
headerHorizontalScroll:SetPoint("TOPLEFT", headerCornerColumn, "TOPRIGHT", 0, 0)
headerHorizontalScroll:SetPoint("BOTTOMRIGHT", fixedHeaderRow, "BOTTOMRIGHT", 0, 0)
headerHorizontalScroll:EnableMouse(true)
local headerGridContainer = CreateFrame("Frame", nil, headerHorizontalScroll)
headerGridContainer:SetPoint("TOPLEFT", headerHorizontalScroll, "TOPLEFT", 0, 0)
headerGridContainer:SetHeight(GetPinnedHeaderHeight())
headerHorizontalScroll:SetScrollChild(headerGridContainer)

-- Vertical scroll bar: custom (no template) so it doesn't conflict with horizontal; both bars under our control
local verticalScrollBar = CreateFrame("Slider", "AltArmyTBC_GearVerticalScrollBar", rightPanel)
verticalScrollBar:SetMinMaxValues(0, 0)
verticalScrollBar:SetValueStep(dims.rowHeight)
verticalScrollBar:SetValue(0)
verticalScrollBar:EnableMouse(true)
Theme.AnchorVerticalScrollBar(verticalScrollBar, tabContentPanel, contentArea)
verticalScrollBar:SetScript("OnValueChanged", function(_, value)
    verticalScroll:SetVerticalScroll(value)
end)

-- Mouse wheel: scroll the gear list when hovering over the scroll area (frame or scroll child)
local function OnGearScrollWheel(_, delta)
    if not verticalScrollBar then return end
    local minVal, maxVal = verticalScrollBar:GetMinMaxValues()
    local current = verticalScrollBar:GetValue()
    -- delta: 1 = scroll up (see higher content), -1 = scroll down (see lower content)
    local newVal = current - delta * dims.rowHeight * 2
    newVal = math.max(minVal, math.min(maxVal, newVal))
    verticalScrollBar:SetValue(newVal)
    verticalScroll:SetVerticalScroll(newVal)
end
verticalScroll:SetScript("OnMouseWheel", OnGearScrollWheel)
verticalScrollChild:SetScript("OnMouseWheel", OnGearScrollWheel)

-- Row headers (slot names) — below pinned header; scroll with equipment rows
local slotHeaderContainer = CreateFrame("Frame", nil, verticalScrollChild)
slotHeaderContainer:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", 0, -GetPinnedHeaderHeight())
slotHeaderContainer:SetPoint("BOTTOMLEFT", verticalScrollChild, "BOTTOMLEFT", 0, 0)
slotHeaderContainer:SetWidth(SLOT_LABEL_WIDTH)

-- Score row: pinned in header corner (provider selector + sort-direction button)
local scoreSortBtn = CreateFrame("Button", nil, headerCornerColumn)
scoreSortBtn:SetPoint("BOTTOMRIGHT", headerCornerColumn, "BOTTOMRIGHT", 0, SCORE_ROW_HEADER_BOTTOM_INSET)
scoreSortBtn:SetSize(GetScoreSortBtnSize(), GetScoreSortBtnSize())
Theme.SkinButton(scoreSortBtn)
local scoreSortBtnText = scoreSortBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
scoreSortBtnText:SetPoint("CENTER", scoreSortBtn, "CENTER", 0, 0)
scoreSortBtnText:SetJustifyH("CENTER")
scoreSortBtnText:SetTextColor(1, 0.82, 0, 1)

local function UpdateScoreSortButton()
    local descending = GetGearSettings().scoreSortDescending ~= false
    scoreSortBtnText:SetText(descending and ">" or "<")
end

scoreSortBtn:SetScript("OnClick", function()
    local s = GetGearSettings()
    s.scoreSortDescending = not s.scoreSortDescending
    UpdateScoreSortButton()
    if frame.RefreshGrid then frame:RefreshGrid() end
end)
UpdateScoreSortButton()

local scoreProviderStaticLabel = headerCornerColumn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
scoreProviderStaticLabel:SetPoint("BOTTOMLEFT", headerCornerColumn, "BOTTOMLEFT", 4, SCORE_ROW_HEADER_BOTTOM_INSET)
scoreProviderStaticLabel:SetPoint("BOTTOMRIGHT", scoreSortBtn, "BOTTOMLEFT", -SCORE_SORT_BTN_GAP, 0)
scoreProviderStaticLabel:SetHeight(GetScoreRowContentHeight())
scoreProviderStaticLabel:SetJustifyH("LEFT")
scoreProviderStaticLabel:SetJustifyV("MIDDLE")
scoreProviderStaticLabel:SetText("Level")

local scoreProviderBtn = CreateFrame("Button", nil, headerCornerColumn)
scoreProviderBtn:SetPoint("BOTTOMLEFT", headerCornerColumn, "BOTTOMLEFT", 0, SCORE_ROW_HEADER_BOTTOM_INSET)
scoreProviderBtn:SetPoint("BOTTOMRIGHT", scoreSortBtn, "BOTTOMLEFT", -SCORE_SORT_BTN_GAP, 0)
scoreProviderBtn:SetHeight(GetScoreRowContentHeight())
scoreProviderBtn:Hide()
Theme.SkinButton(scoreProviderBtn)
local scoreProviderBtnText = scoreProviderBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
scoreProviderBtnText:SetPoint("LEFT", scoreProviderBtn, "LEFT", 6, 0)
scoreProviderBtnText:SetPoint("RIGHT", scoreProviderBtn, "RIGHT", -2, 0)
scoreProviderBtnText:SetJustifyH("LEFT")

local scoreProviderDropdown = CreateFrame("Frame", nil, fixedHeaderRow, "BackdropTemplate")
scoreProviderDropdown:SetPoint("TOPLEFT", scoreProviderBtn, "BOTTOMLEFT", 0, -2)
scoreProviderDropdown:SetWidth(SCORE_PROVIDER_DROPDOWN_WIDTH)
scoreProviderDropdown:SetFrameLevel(fixedHeaderRow:GetFrameLevel() + 100)
scoreProviderDropdown:Hide()
Theme.ApplyBackdrop(scoreProviderDropdown, "section")
local scoreProviderDropdownButtons = {}

local function UpdateScoreProviderControl()
    local providers = GetAvailableScoreProviders()
    local selectedId = GetSelectedScoreProvider()
    local label = GetScoreProviderLabel(selectedId)
    if #providers <= 1 then
        scoreProviderStaticLabel:SetText(label)
        scoreProviderStaticLabel:Show()
        scoreProviderBtn:Hide()
        scoreProviderDropdown:Hide()
        return
    end
    scoreProviderStaticLabel:Hide()
    scoreProviderBtn:Show()
    scoreProviderBtnText:SetText(label)
end

local function UpdateScoreProviderDropdownSelection()
    local selectedId = GetSelectedScoreProvider()
    for i = 1, #scoreProviderDropdownButtons do
        local b = scoreProviderDropdownButtons[i]
        if b.SetDropdownSelected then
            b:SetDropdownSelected(b.providerId == selectedId)
        end
    end
end

local function RebuildScoreProviderDropdown()
    for i = 1, #scoreProviderDropdownButtons do
        scoreProviderDropdownButtons[i]:Hide()
        scoreProviderDropdownButtons[i]:SetParent(nil)
    end
    wipe(scoreProviderDropdownButtons)
    local providers = GetAvailableScoreProviders()
    if #providers <= 1 then
        scoreProviderDropdown:Hide()
        return
    end
    scoreProviderDropdown:SetHeight(#providers * SETTINGS_ROW_HEIGHT + 4)
    scoreProviderDropdown:SetWidth(SCORE_PROVIDER_DROPDOWN_WIDTH)
    for idx, provider in ipairs(providers) do
        local b = Theme.CreateDropdownMenuItem(scoreProviderDropdown, {
            index = idx,
            rowHeight = SETTINGS_ROW_HEIGHT,
            text = provider.label,
            selected = provider.id == GetSelectedScoreProvider(),
            onClick = function(self)
                GetGearSettings().scoreProvider = self.providerId
                UpdateScoreProviderDropdownSelection()
                scoreProviderDropdown:Hide()
                UpdateScoreProviderControl()
                if frame.RefreshGrid then frame:RefreshGrid() end
            end,
        })
        b.providerId = provider.id
        scoreProviderDropdownButtons[idx] = b
    end
end

scoreProviderBtn:SetScript("OnClick", function()
    local show = not scoreProviderDropdown:IsShown()
    if show then
        UpdateScoreProviderDropdownSelection()
    end
    scoreProviderDropdown:SetShown(show)
end)

-- Slot labels: height dims.cellSize and vertically centered in each row (row height is dims.rowHeight)
local SLOT_LABEL_ROW_OFFSET = (dims.rowHeight - dims.cellSize) / 2
local slotLabels = {}
for slot = 1, NUM_EQUIPMENT_SLOTS do
    local label = slotHeaderContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", slotHeaderContainer, "LEFT", 0, 0)
    label:SetWidth(SLOT_LABEL_WIDTH - 4)
    label:SetHeight(dims.cellSize)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("MIDDLE")
    label:SetText(SLOT_NAMES[SLOT_ORDER[slot]] or ("Slot " .. slot))
    if slot == 1 then
        label:SetPoint("TOP", slotHeaderContainer, "TOP", 0, -SLOT_LABEL_ROW_OFFSET)
    else
        label:SetPoint("TOP", slotLabels[slot - 1], "TOP", 0, -dims.rowHeight)
    end
    slotLabels[slot] = label
end

-- Horizontal viewport: below spacer, same vertical start as slot labels
local horizontalScroll = CreateFrame("ScrollFrame", "AltArmyTBC_GearHorizontalScroll", verticalScrollChild)
horizontalScroll:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", SLOT_LABEL_WIDTH, -GetPinnedHeaderHeight())
horizontalScroll:SetPoint("BOTTOMRIGHT", verticalScrollChild, "BOTTOMRIGHT", 0, 0)
horizontalScroll:EnableMouse(true)

-- Grid area: scroll child of horizontalScroll; engine scrolls via SetHorizontalScroll (like vertical)
local gridContainer = CreateFrame("Frame", nil, horizontalScroll)
gridContainer:SetPoint("TOPLEFT", horizontalScroll, "TOPLEFT", 0, 0)
gridContainer:SetHeight(dims.scrollableGridHeight)
horizontalScroll:SetScrollChild(gridContainer)

-- Header column pool: name + message per character, in fixed header row (scrolls horizontally)
local headerColumnPool = {}
local function GetHeaderColumnFrame(index)
    if not headerColumnPool[index] then
        local col = CreateFrame("Frame", nil, headerGridContainer)
        col:SetSize(dims.columnWidth, GetPinnedHeaderHeight())
        col:EnableMouse(true)
        col.header = col:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        col.header:SetPoint("TOPLEFT", col, "TOPLEFT", 0, 0)
        col.header:SetPoint("TOPRIGHT", col, "TOPRIGHT", 0, 0)
        col.header:SetHeight(COLUMN_HEADER_HEIGHT_GEAR)
        col.header:SetJustifyH("CENTER")
        col.header:SetWordWrap(false)
        col.message = col:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        col.message:SetPoint("TOP", col.header, "BOTTOM", 0, 0)
        col.message:SetPoint("LEFT", col, "LEFT", 0, 0)
        col.message:SetPoint("RIGHT", col, "RIGHT", 0, 0)
        col.message:SetHeight(MESSAGE_ROW_HEIGHT)
        col.message:SetJustifyH("CENTER")
        col.message:SetWordWrap(true)
        col.message:SetNonSpaceWrap(true)
        col.scoreText = col:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        col.scoreText:SetPoint("BOTTOMLEFT", col, "BOTTOMLEFT", 0, SCORE_ROW_HEADER_BOTTOM_INSET)
        col.scoreText:SetPoint("BOTTOMRIGHT", col, "BOTTOMRIGHT", 0, SCORE_ROW_HEADER_BOTTOM_INSET)
        col.scoreText:SetHeight(GetScoreRowContentHeight())
        col.scoreText:SetJustifyH("CENTER")
        col.scoreText:SetJustifyV("MIDDLE")
        col.scoreHover = CreateFrame("Frame", nil, col)
        col.scoreHover:SetPoint("BOTTOMLEFT", col, "BOTTOMLEFT", 0, SCORE_ROW_HEADER_BOTTOM_INSET)
        col.scoreHover:SetPoint("BOTTOMRIGHT", col, "BOTTOMRIGHT", 0, SCORE_ROW_HEADER_BOTTOM_INSET)
        col.scoreHover:SetHeight(GetScoreRowContentHeight())
        col.scoreHover:EnableMouse(true)
        col.scoreHover:SetScript("OnEnter", function(self)
            local colFrame = self:GetParent()
            local e = colFrame and colFrame.scoreMissingEntry
            if e and SD and SD.PresentMissingDataTooltip then
                SD.PresentMissingDataTooltip(self, "ANCHOR_BOTTOMLEFT", e.name, e.realm, e.classFile)
            end
        end)
        col.scoreHover:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        col:SetScript("OnEnter", function(self)
            if self.tooltipText and self.tooltipText ~= "" and GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(self.tooltipText, 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        col:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        headerColumnPool[index] = col
    end
    return headerColumnPool[index]
end

-- Pool of character column frames (cells only; reused)
local columnPool = {}

-- Horizontal scroll bar: create after horizontalScroll/gridContainer exist so OnValueChanged sees them
local horizontalScrollApi = Theme.CreateHorizontalScrollBar(tabContentInner, {
    name = "AltArmyTBC_GearHorizontalScrollBar",
    thickness = HORIZONTAL_SCROLL_BAR_HEIGHT - PAD * 2,
    onScroll = function(value)
        if not horizontalScroll then return end
        if horizontalScroll.UpdateScrollChildRect then
            horizontalScroll:UpdateScrollChildRect()
        end
        horizontalScroll:SetHorizontalScroll(value)
        if headerHorizontalScroll then
            if headerHorizontalScroll.UpdateScrollChildRect then
                headerHorizontalScroll:UpdateScrollChildRect()
            end
            headerHorizontalScroll:SetHorizontalScroll(value)
        end
    end,
    isShown = function()
        return frame:IsShown()
    end,
})
local horizontalScrollBar = horizontalScrollApi.bar
horizontalScrollBar:SetPoint("BOTTOMLEFT", tabContentInner, "BOTTOMLEFT", PAD, -4)
horizontalScrollBar:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", 0, -4)

local function GetColumnFrame(index)
    if not columnPool[index] then
        local col = CreateFrame("Frame", nil, gridContainer)
        col:SetSize(dims.columnWidth, dims.scrollableGridHeight)
        col.cells = {}
        for slot = 1, NUM_EQUIPMENT_SLOTS do
            local cell = CreateFrame("Frame", nil, col)
            cell:SetSize(dims.cellSize, dims.cellSize)
            cell:EnableMouse(true)
            local glow = cell:CreateTexture(nil, "BACKGROUND")
            glow:SetAllPoints(cell)
            glow:Hide()
            cell.glow = glow
            local tex = cell:CreateTexture(nil, "ARTWORK")
            tex:SetPoint("TOPLEFT", cell, "TOPLEFT", ITEM_ICON_INSET, -ITEM_ICON_INSET)
            tex:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -ITEM_ICON_INSET, ITEM_ICON_INSET)
            cell.texture = tex
            cell:SetScript("OnMouseUp", function(self, button)
                local target = self.itemLink or self.itemID
                if not target then return end
                HandleItemCellClick(target, button)
            end)
            cell:SetScript("OnEnter", function(self)
                if GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                    if self.itemLink and self.itemLink ~= "" then
                        GameTooltip:SetHyperlink(self.itemLink)
                    elseif self.itemID then
                        GameTooltip:SetItemByID(self.itemID)
                    else
                        GameTooltip:Hide()
                        return
                    end
                    GameTooltip:Show()
                end
            end)
            cell:SetScript("OnLeave", function()
                if GameTooltip then GameTooltip:Hide() end
            end)
            local cellXOffset = (dims.columnWidth - dims.cellSize) / 2
            local slotLabelRowOffset = (dims.rowHeight - dims.cellSize) / 2
            if slot == 1 then
                cell:SetPoint("TOPLEFT", col, "TOPLEFT", cellXOffset, -slotLabelRowOffset)
            else
                cell:SetPoint("TOPLEFT", col.cells[slot - 1], "BOTTOMLEFT", 0, -(dims.rowHeight - dims.cellSize))
            end
            col.cells[slot] = cell
        end
        columnPool[index] = col
    end
    return columnPool[index]
end

local function UpdateGridWithOffset()
    if not AltArmy.Characters then return end
    local list = GetDisplayList()
    local numCols = #list

    for idx, col in pairs(columnPool) do
        if idx > numCols then col:Hide() end
    end
    for idx, col in pairs(headerColumnPool) do
        if idx > numCols then col:Hide() end
    end

    for c = 1, numCols do
        local entry = list[c]
        local headerCol = GetHeaderColumnFrame(c)
        headerCol:ClearAllPoints()
        headerCol:SetPoint("TOPLEFT", headerGridContainer, "TOPLEFT", (c - 1) * dims.columnWidth + PAD, 0)
        headerCol:Show()

        local charData = DS and DS.GetCharacter and DS:GetCharacter(entry.name, entry.realm)
        local RF = AltArmy.RealmFilter
        local classR, classG, classB = 1, 0.82, 0
        local gray = CanNeverUseCurrentItem(entry)
        if gray then
            classR, classG, classB = 0.5, 0.5, 0.5
        else
            if CC and CC.getRGBOr then
                classR, classG, classB = CC.getRGBOr(entry.classFile, classR, classG, classB)
            end
        end
        headerCol.classR, headerCol.classG, headerCol.classB = classR, classG, classB
        local displayName = entry.name or "?"
        headerCol.header:SetTextColor(classR, classG, classB, 1)
        if TruncateFontString then
            TruncateFontString(headerCol.header, displayName, dims.columnWidth - 4)
        end
        headerCol.truncated = (headerCol.header:GetText() ~= displayName)
        local realmFilter = "all"
        local GRF = AltArmy.GlobalRealmFilter
        if GRF and GRF.Get then
            realmFilter = GRF.Get()
        end
        local showRealmSuffix = (realmFilter == "all")
            and RF and RF.hasMultipleRealms and RF.hasMultipleRealms(list)
        local hasRealm = entry.realm and entry.realm ~= ""
        if headerCol.truncated or (showRealmSuffix and hasRealm) then
            headerCol.tooltipText = RF and RF.formatColoredCharacterNameRealm
                and RF.formatColoredCharacterNameRealm(
                    entry.name or "?",
                    entry.realm,
                    showRealmSuffix,
                    entry.classFile
                )
                or displayName
        else
            headerCol.tooltipText = nil
        end

        local fitMsg, fitColor = GetFitMessage(entry)
        if fitMsg and fitMsg ~= "" then
            headerCol.message:SetText(fitMsg)
            if fitColor == "red" then
                headerCol.message:SetTextColor(1, 0.3, 0.3, 1)
            elseif fitColor == "orange" then
                headerCol.message:SetTextColor(1, 0.6, 0.2, 1)
            else
                headerCol.message:SetTextColor(0.9, 0.9, 0.9, 1)
            end
            headerCol.message:Show()
        else
            headerCol.message:SetText("")
            headerCol.message:Show()
        end

        local providerId = GetSelectedScoreProvider()
        local scoreMissing = GearScoreMod and GearScoreMod.IsScoreMissing
            and GearScoreMod.IsScoreMissing(charData, providerId)
        if headerCol.scoreText then
            if scoreMissing then
                headerCol.scoreText:SetText("!")
                headerCol.scoreText:SetTextColor(1, 0.82, 0, 1)
                headerCol.scoreMissingEntry = {
                    name = entry.name or "",
                    realm = entry.realm or "",
                    classFile = entry.classFile,
                }
                if headerCol.scoreHover then
                    headerCol.scoreHover:Show()
                    headerCol.scoreHover:EnableMouse(true)
                end
            else
                local scoreValue = GearScoreMod and GearScoreMod.GetDisplayScore
                    and GearScoreMod.GetDisplayScore(entry, providerId) or 0
                local scoreDisplay = GearScoreMod and GearScoreMod.FormatDisplayScore
                    and GearScoreMod.FormatDisplayScore(providerId, scoreValue) or "0"
                headerCol.scoreText:SetText(scoreDisplay)
                headerCol.scoreMissingEntry = nil
                if headerCol.scoreHover then
                    headerCol.scoreHover:Hide()
                    headerCol.scoreHover:EnableMouse(false)
                end
                if gray then
                    headerCol.scoreText:SetTextColor(0.5, 0.5, 0.5, 1)
                else
                    local sr, sg, sb
                    if GearScoreMod and GearScoreMod.GetDisplayScoreColor then
                        sr, sg, sb = GearScoreMod.GetDisplayScoreColor(providerId, scoreValue)
                    end
                    if sr and sg and sb then
                        headerCol.scoreText:SetTextColor(sr, sg, sb, 1)
                    else
                        headerCol.scoreText:SetTextColor(0.9, 0.9, 0.9, 1)
                    end
                end
            end
            headerCol.scoreText:Show()
        end

        local col = GetColumnFrame(c)
        col:ClearAllPoints()
        col:SetPoint("TOPLEFT", gridContainer, "TOPLEFT", (c - 1) * dims.columnWidth + PAD - 4, 0)
        col:Show()

        for slot = 1, NUM_EQUIPMENT_SLOTS do
            local cell = col.cells[slot]
            local item = charData and DS.GetInventoryItem and DS:GetInventoryItem(charData, SLOT_ORDER[slot])
            if type(item) == "string" then
                cell.itemLink = item
                cell.itemID = nil
            elseif type(item) == "number" then
                cell.itemLink = nil
                cell.itemID = item
            else
                cell.itemLink = nil
                cell.itemID = nil
            end
            ApplyItemCellVisual(cell, item, gray)
        end
    end
end

function frame:RefreshGrid(_self)
    if not AltArmy.Characters then return end
    if AltArmy.Characters.InvalidateView then
        AltArmy.Characters:InvalidateView()
    end
    if AltArmy.Characters.Sort then
        AltArmy.Characters:Sort(false, "level")
    end

    local list = GetDisplayList()
    local numCols = #list
    local viewWidth = verticalScroll and verticalScroll:GetWidth() or 0
    local viewHeight = verticalScroll and verticalScroll:GetHeight() or 0
    local gridContentWidth = numCols * dims.columnWidth + PAD
    local gridViewWidth = math.max(0, viewWidth - SLOT_LABEL_WIDTH)

    -- Vertical scroll child: viewport width only; horizontal scroll is inner (grid only)
    if verticalScrollChild and verticalScroll then
        verticalScrollChild:SetWidth(math.max(MIN_SCROLL_CHILD_WIDTH, viewWidth))
        if gridContainer then
            gridContainer:SetWidth(math.max(0, gridContentWidth))
        end
        if headerGridContainer then
            headerGridContainer:SetWidth(math.max(0, gridContentWidth))
        end
        if verticalScrollBar then
            local totalChildHeight = GetPinnedHeaderHeight() + dims.scrollableGridHeight
            local maxVertScroll = math.max(0, totalChildHeight - viewHeight)
            verticalScrollBar:SetMinMaxValues(0, maxVertScroll)
            verticalScrollBar:SetValueStep(dims.rowHeight)
            verticalScrollBar:SetStepsPerPage(10)
        end
        if horizontalScrollBar and horizontalScroll and gridContainer then
            local maxHorzScroll = math.max(0, gridContentWidth - gridViewWidth)
            horizontalScrollApi:SetRange(0, maxHorzScroll)
            horizontalScrollBar:SetShown(maxHorzScroll > 0)
            horizontalScrollApi:Reset()
        end
    end

    UpdateGridWithOffset()
end

--- Reapply fixed layout dimensions (medium icons, normal spacing).
local function ApplySpacing()
    dims.cellSize = GetCellSizePx()
    local rh, cw = GetSpacingDimensions()
    dims.rowHeight, dims.columnWidth = rh, cw
    dims.scrollableGridHeight = GetScrollableGridHeight()

    if verticalScrollChild then
        verticalScrollChild:SetHeight(GetPinnedHeaderHeight() + dims.scrollableGridHeight)
    end
    if gridContainer then
        gridContainer:SetHeight(dims.scrollableGridHeight)
    end
    if fixedHeaderRow then
        fixedHeaderRow:SetHeight(GetPinnedHeaderHeight())
    end
    if scrollTopSpacer then
        scrollTopSpacer:SetHeight(GetPinnedHeaderHeight())
    end
    if headerGridContainer then
        headerGridContainer:SetHeight(GetPinnedHeaderHeight())
    end
    if slotHeaderContainer then
        slotHeaderContainer:ClearAllPoints()
        slotHeaderContainer:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", 0, -GetPinnedHeaderHeight())
        slotHeaderContainer:SetPoint("BOTTOMLEFT", verticalScrollChild, "BOTTOMLEFT", 0, 0)
        slotHeaderContainer:SetWidth(SLOT_LABEL_WIDTH)
    end
    if headerCornerColumn then
        headerCornerColumn:SetWidth(SLOT_LABEL_WIDTH)
    end
    if headerCornerCell then
        headerCornerCell:SetWidth(SLOT_LABEL_WIDTH - 4)
    end
    if horizontalScroll then
        horizontalScroll:ClearAllPoints()
        horizontalScroll:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", SLOT_LABEL_WIDTH, -GetPinnedHeaderHeight())
        horizontalScroll:SetPoint("BOTTOMRIGHT", verticalScrollChild, "BOTTOMRIGHT", 0, 0)
    end
    if verticalScrollBar then
        verticalScrollBar:SetValueStep(dims.rowHeight)
    end

    if scoreProviderStaticLabel then
        scoreProviderStaticLabel:SetHeight(GetScoreRowContentHeight())
    end
    if scoreProviderBtn then
        scoreProviderBtn:SetHeight(GetScoreRowContentHeight())
    end
    if scoreSortBtn then
        local btnSize = GetScoreSortBtnSize()
        scoreSortBtn:SetSize(btnSize, btnSize)
    end

    if slotLabels and slotLabels[1] then
        local slotLabelRowOffset = (dims.rowHeight - dims.cellSize) / 2
        for slot = 1, NUM_EQUIPMENT_SLOTS do
            slotLabels[slot]:SetHeight(dims.cellSize)
            slotLabels[slot]:ClearAllPoints()
            slotLabels[slot]:SetPoint("LEFT", slotHeaderContainer, "LEFT", 0, 0)
            if slot == 1 then
                slotLabels[slot]:SetPoint("TOP", slotHeaderContainer, "TOP", 0, -slotLabelRowOffset)
            else
                slotLabels[slot]:SetPoint("TOP", slotLabels[slot - 1], "TOP", 0, -dims.rowHeight)
            end
        end
    end

    for _, col in pairs(headerColumnPool) do
        col:SetSize(dims.columnWidth, GetPinnedHeaderHeight())
        if col.scoreText then
            col.scoreText:SetHeight(GetScoreRowContentHeight())
        end
        if col.scoreHover then
            col.scoreHover:SetHeight(GetScoreRowContentHeight())
        end
    end
    for _, col in pairs(columnPool) do
        col:SetSize(dims.columnWidth, dims.scrollableGridHeight)
        local cellXOffset = (dims.columnWidth - dims.cellSize) / 2
        local slotLabelRowOffset = (dims.rowHeight - dims.cellSize) / 2
        for slot = 1, NUM_EQUIPMENT_SLOTS do
            local cell = col.cells[slot]
            cell:SetSize(dims.cellSize, dims.cellSize)
            cell:ClearAllPoints()
            if slot == 1 then
                cell:SetPoint("TOPLEFT", col, "TOPLEFT", cellXOffset, -slotLabelRowOffset)
            else
                cell:SetPoint("TOPLEFT", col.cells[slot - 1], "BOTTOMLEFT", 0, -(dims.rowHeight - dims.cellSize))
            end
        end
    end
end

local function RefreshGearTabControls()
    RebuildScoreProviderDropdown()
    UpdateScoreProviderControl()
    UpdateScoreSortButton()
end

-- Apply layout when tab is shown (dims initialized at file load)
frame:SetScript("OnShow", function()
    ApplySpacing()
    RefreshGearTabControls()
    if GearScoreMod and GearScoreMod.CaptureCurrentCharacterScore then
        GearScoreMod.CaptureCurrentCharacterScore()
    end
    frame:RefreshGrid()
end)

local function IsGearScoreAddonEvent(addonName)
    if not addonName or addonName == "" then return false end
    if addonName == "TacoTip" then return true end
    if GearScoreMod and GearScoreMod.IsSupportedGearScoreAddon then
        return GearScoreMod.IsSupportedGearScoreAddon(addonName)
    end
    return false
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, addonName)
    if event == "PLAYER_LOGIN" then
        if GearScoreMod and GearScoreMod.RefreshProviders then
            GearScoreMod.RefreshProviders("login")
        end
        if AltArmy.Characters and AltArmy.Characters.InvalidateView then
            AltArmy.Characters:InvalidateView()
        end
        ApplySpacing()
        RefreshGearTabControls()
        if frame:IsShown() then
            frame:RefreshGrid()
        end
    elseif event == "ADDON_LOADED" and IsGearScoreAddonEvent(addonName) then
        if GearScoreMod and GearScoreMod.RefreshProviders then
            GearScoreMod.RefreshProviders("addon-loaded:" .. tostring(addonName))
        end
        RefreshGearTabControls()
        if frame:IsShown() then
            frame:RefreshGrid()
        end
    end
end)

-- ---- Gear settings panel: right 40% of frame when visible (grid 60%, both full height) ----
local GRID_SPLIT_FRACTION = 0.6  -- grid gets 60%, settings gets 40%
local settingsPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
Theme.ApplyBackdrop(settingsPanel, "section")
local function ApplySettingsPanelLayout()
    local w = frame:GetWidth()
    if w <= 0 then return end
    settingsPanel:ClearAllPoints()
    settingsPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", w * GRID_SPLIT_FRACTION + SECTION_GAP, -SECTION_INSET)
    settingsPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", w * GRID_SPLIT_FRACTION + SECTION_GAP, SECTION_INSET)
    settingsPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SECTION_INSET, -SECTION_INSET)
    settingsPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SECTION_INSET, SECTION_INSET)
end
ApplySettingsPanelLayout()
settingsPanel:Hide()

local settingsContent = Theme.CreateSettingsPanelContent(settingsPanel)
local gearSettingsTitle = settingsContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
gearSettingsTitle:SetPoint("TOPLEFT", settingsContent, "TOPLEFT", 0, 0)
gearSettingsTitle:SetPoint("TOPRIGHT", settingsContent, "TOPRIGHT", 0, 0)
gearSettingsTitle:SetJustifyH("LEFT")
gearSettingsTitle:SetText("Gear Settings")
Theme.SetTitleColor(gearSettingsTitle)
local gearCharListRefresh = function() end

local sortingContent = CreateFrame("Frame", nil, settingsContent)
sortingContent:SetPoint("TOPLEFT", gearSettingsTitle, "BOTTOMLEFT", 0, -8)
sortingContent:SetPoint("BOTTOMRIGHT", settingsContent, "BOTTOMRIGHT", 0, 0)
sortingContent:Show()

-- ---- Pin current character, Character list ----
local showSelfFirstRow = Theme.CreateLabeledCheckbox(sortingContent, {
    point = "TOPLEFT",
    x = 0,
    y = 0,
    text = "Pin current character",
    fullWidthHover = true,
    onClick = function(checked)
        GetGearSettings().showSelfFirst = checked
        if frame.RefreshGrid then frame:RefreshGrid() end
    end,
})
Theme.AttachSettingsHelpIcon(showSelfFirstRow, {
    title = "Pin current character",
    lines = {
        "When enabled, your currently signed-in character is automatically pinned, "
            .. "causing it to show ahead of all non-pinned characters.",
        'This will override the "Hide" setting.',
    },
})
local showSelfFirstCheck = showSelfFirstRow.check
showSelfFirstCheck:SetChecked(GetGearSettings().showSelfFirst)

-- Character list: Pin/Hide (reusable component from UI/CharacterPinHideList.lua)
if AltArmy.CreateCharacterPinHideList then
    -- luacheck: push ignore 211
    local _scroll, refresh = AltArmy.CreateCharacterPinHideList(sortingContent, showSelfFirstRow, {
        gutterEdge = settingsPanel,
        getSettings = GetGearSettings,
        getCharSetting = GetCharSetting,
        setCharSetting = SetCharSetting,
        onChange = function()
            if frame.RefreshGrid then frame:RefreshGrid() end
        end,
    })
    if refresh then gearCharListRefresh = refresh end
    -- luacheck: pop
end

-- Close dropdowns when clicking outside
settingsPanel:SetScript("OnHide", function()
    scoreProviderDropdown:Hide()
end)

function frame:IsGearSettingsShown()
    return settingsPanel and settingsPanel:IsShown()
end

function frame:ToggleGearSettings(_self)
    local showSettings = not settingsPanel:IsShown()
    settingsPanel:SetShown(showSettings)

    if showSettings then
        ApplySettingsPanelLayout()
    end

    -- Resize tab content: full width when settings closed, left 60% when settings open
    tabContentPanel:ClearAllPoints()
    tabContentPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", SECTION_INSET, -SECTION_INSET)
    if showSettings then
        tabContentPanel:SetPoint("BOTTOMRIGHT", settingsPanel, "BOTTOMLEFT", -SECTION_GAP, 0)
    else
        tabContentPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SECTION_INSET, SECTION_INSET)
    end
    rightPanel:ClearAllPoints()
    if LEFT_PANEL_VISIBLE then
        rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", PAD, 0)
    else
        rightPanel:SetPoint("TOPLEFT", tabContentInner, "TOPLEFT", 0, 0)
    end
    rightPanel:SetPoint("BOTTOMRIGHT", tabContentInner, "BOTTOMRIGHT", 0, 0)

    if showSettings then
        local s = GetGearSettings()
        showSelfFirstCheck:SetChecked(s.showSelfFirst)
        if AltArmy.Characters and AltArmy.Characters.InvalidateView then
            AltArmy.Characters:InvalidateView()
        end
        if gearCharListRefresh then gearCharListRefresh() end
    end

    if frame.RefreshGrid then frame:RefreshGrid() end
end

-- Keep 60/40 split when frame is resized and settings are open
frame:SetScript("OnSizeChanged", function()
    if settingsPanel and settingsPanel:IsShown() then
        ApplySettingsPanelLayout()
        tabContentPanel:ClearAllPoints()
        tabContentPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", SECTION_INSET, -SECTION_INSET)
        tabContentPanel:SetPoint("BOTTOMRIGHT", settingsPanel, "BOTTOMLEFT", -SECTION_GAP, 0)
        rightPanel:ClearAllPoints()
        if LEFT_PANEL_VISIBLE then
            rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", PAD, 0)
        else
            rightPanel:SetPoint("TOPLEFT", tabContentInner, "TOPLEFT", 0, 0)
        end
        rightPanel:SetPoint("BOTTOMRIGHT", tabContentInner, "BOTTOMRIGHT", 0, 0)
        if frame.RefreshGrid then frame:RefreshGrid() end
    end
end)
