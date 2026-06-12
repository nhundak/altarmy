-- AltArmy TBC — Gear tab: "Who can use this?" drop box + equipment grid (slot rows x character columns)

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Gear
if not frame then return end

local DS = AltArmy.DataStore
local Theme = AltArmy.Theme
local PAD = 4
local LEFT_PANEL_WIDTH = 120
local LEFT_PANEL_VISIBLE = false  -- set true to show "Who can use this?" drop zone
local MESSAGE_ROW_HEIGHT = 12
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
local SORT_OPTIONS = { "Name", "Level", "Avg Item Level", "Time Played" }
local function SortOptionValid(val)
    for _, o in ipairs(SORT_OPTIONS) do if o == val then return true end end
    return false
end
local function GetGearSettings()
    AltArmyTBC_GearSettings = AltArmyTBC_GearSettings or {}
    local s = AltArmyTBC_GearSettings
    if not s.primarySort or not SortOptionValid(s.primarySort) then s.primarySort = "Time Played" end
    if not s.secondarySort or not SortOptionValid(s.secondarySort) then s.secondarySort = "Name" end
    if s.showSelfFirst == nil then s.showSelfFirst = true end
    s.characters = s.characters or {}
    return s
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

local function CharKey(name, realm)
    return (realm or "") .. "\\" .. (name or "")
end

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

--- Sort value for an entry by key (Name, Level, Avg Item Level, Time Played). Numeric = high first, Name = A–Z.
local function GetSortValue(entry, sortKey)
    if sortKey == "Name" then return entry.name or "" end
    if sortKey == "Level" then return tonumber(entry.level) or 0 end
    if sortKey == "Avg Item Level" then return tonumber(entry.avgItemLevel) or 0 end
    if sortKey == "Time Played" then return tonumber(entry.played) or 0 end
    return 0
end

--- Compare two entries by primary then secondary sort (numeric high-first, string A–Z).
local function CompareBySort(entryA, entryB, primary, secondary)
    local va = GetSortValue(entryA, primary)
    local vb = GetSortValue(entryB, primary)
    if primary == "Name" then
        if va ~= vb then return va < vb end
    else
        if va ~= vb then return va > vb end
    end
    va = GetSortValue(entryA, secondary)
    vb = GetSortValue(entryB, secondary)
    if secondary == "Name" then
        return va < vb
    else
        return va > vb
    end
end

--- Build display list: filter hidden; order = self (if show self first) + pinned + non-pinned.
--- Optionally re-sort by "who can use" when item dropped.
local function GetDisplayList()
    if not AltArmy.Characters or not AltArmy.Characters.GetList then return {} end
    local rawList = AltArmy.Characters:GetList()
    if #rawList == 0 then return rawList end

    local settings = GetGearSettings()
    local currentName = (UnitName and UnitName("player")) or (GetUnitName and GetUnitName("player")) or ""
    local currentRealm = (GetRealmName and GetRealmName()) or ""

    -- Filter out hidden
    local visible = {}
    for i = 1, #rawList do
        local e = rawList[i]
        if not GetCharSetting(e.name, e.realm, "hide") then
            visible[#visible + 1] = e
        end
    end

    local primary = settings.primarySort or "Time Played"
    local secondary = settings.secondarySort or "Name"
    local showSelfFirst = settings.showSelfFirst ~= false

    -- Split: self (when show self first), pinned, non-pinned
    local selfEntry = nil
    local pinned = {}
    local nonPinned = {}
    for i = 1, #visible do
        local e = visible[i]
        local isSelf = (e.name == currentName and e.realm == currentRealm)
        if isSelf and showSelfFirst then
            selfEntry = e
        elseif GetCharSetting(e.name, e.realm, "pin") then
            pinned[#pinned + 1] = e
        else
            nonPinned[#nonPinned + 1] = e
        end
    end

    table.sort(pinned, function(a, b) return CompareBySort(a, b, primary, secondary) end)
    table.sort(nonPinned, function(a, b) return CompareBySort(a, b, primary, secondary) end)

    local list = {}
    if showSelfFirst and selfEntry then list[#list + 1] = selfEntry end
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

--- Insert item link into chat (same as shift-clicking item in bags).
--- Prefers a fresh link from GetItemInfo(itemID) so stored/saved links don't insert as "()".
local function InsertItemLinkIntoChat(itemLinkOrID)
    if not ChatEdit_InsertLink then return end
    local link = nil
    local itemID = nil
    if type(itemLinkOrID) == "number" then
        itemID = itemLinkOrID
    elseif type(itemLinkOrID) == "string" and itemLinkOrID ~= "" then
        itemID = tonumber(itemLinkOrID:match("item:(%d+)"))
    end
    if itemID and GetItemInfo then
        local _, freshLink = GetItemInfo(itemID)
        if freshLink and freshLink ~= "" then
            link = freshLink
        end
    end
    if not link and type(itemLinkOrID) == "string" and itemLinkOrID ~= "" then
        link = itemLinkOrID
    end
    -- Only insert if link looks like a valid item link (avoids blank "()" from bad/stale links)
    if link and link:find("item:") and link:find("%[") then
        ChatEdit_InsertLink(link)
    end
end

-- ---- Left panel ----
local leftPanel = CreateFrame("Frame", nil, frame)
leftPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD)
leftPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, PAD)
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
local SLOT_LABEL_WIDTH = 80
local SCROLL_BAR_WIDTH = 20
local FIXED_HEADER_ROW_HEIGHT = COLUMN_HEADER_HEIGHT_GEAR + MESSAGE_ROW_HEIGHT
-- Layout dimensions from spacing + icon size
local dims = {}
do
    dims.cellSize = GetCellSizePx()
    local rh, cw = GetSpacingDimensions()
    dims.rowHeight, dims.columnWidth = rh, cw
    dims.scrollableGridHeight = NUM_EQUIPMENT_SLOTS * dims.rowHeight + PAD
end

local rightPanel = CreateFrame("Frame", nil, frame)
if LEFT_PANEL_VISIBLE then
    rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", PAD, 0)
else
    rightPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD)
end
rightPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)

local SCROLL_BAR_TOP_INSET = 16
local SCROLL_BAR_BOTTOM_INSET = 16
local SCROLL_BAR_RIGHT_OFFSET = 4
local HORIZONTAL_SCROLL_BAR_HEIGHT = 20

-- Content area: full height except scroll bars; fixed header will sit at top of this
local contentArea = CreateFrame("Frame", nil, rightPanel)
contentArea:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 0, -PAD)
contentArea:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -SCROLL_BAR_WIDTH,
    SCROLL_BAR_BOTTOM_INSET + HORIZONTAL_SCROLL_BAR_HEIGHT)

-- Vertical scroll: full content area; scroll child has spacer at top so header can overlay
local verticalScroll = CreateFrame("ScrollFrame", "AltArmyTBC_GearVerticalScroll", contentArea)
verticalScroll:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 0, 0)
verticalScroll:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", 0, 0)
verticalScroll:EnableMouse(true)

-- Scroll child: spacer at top (header overlays it) + slot labels + cell grid
local MIN_SCROLL_CHILD_WIDTH = 400
local verticalScrollChild = CreateFrame("Frame", nil, verticalScroll)
verticalScrollChild:SetPoint("TOPLEFT", verticalScroll, "TOPLEFT", 0, 0)
verticalScrollChild:SetHeight(FIXED_HEADER_ROW_HEIGHT + dims.scrollableGridHeight)
verticalScrollChild:SetWidth(MIN_SCROLL_CHILD_WIDTH)
verticalScrollChild:EnableMouse(true)
verticalScroll:SetScrollChild(verticalScrollChild)

-- Spacer at top of scroll child so first row of content sits below where header will overlay
local scrollTopSpacer = CreateFrame("Frame", nil, verticalScrollChild)
scrollTopSpacer:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", 0, 0)
scrollTopSpacer:SetPoint("TOPRIGHT", verticalScrollChild, "TOPRIGHT", 0, 0)
scrollTopSpacer:SetHeight(FIXED_HEADER_ROW_HEIGHT)

-- Fixed header row: overlays top of content area so names stay pinned; scrolls horizontally with grid
local fixedHeaderRow = CreateFrame("Frame", nil, contentArea)
fixedHeaderRow:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 0, 0)
fixedHeaderRow:SetPoint("TOPRIGHT", contentArea, "TOPRIGHT", 0, 0)
fixedHeaderRow:SetHeight(FIXED_HEADER_ROW_HEIGHT)
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
local headerCornerCell = fixedHeaderRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
headerCornerCell:SetPoint("TOPLEFT", fixedHeaderRow, "TOPLEFT", 0, 0)
headerCornerCell:SetWidth(SLOT_LABEL_WIDTH - 4)
headerCornerCell:SetHeight(FIXED_HEADER_ROW_HEIGHT)
headerCornerCell:SetJustifyH("LEFT")
headerCornerCell:SetText("")
local headerHorizontalScroll = CreateFrame("ScrollFrame", "AltArmyTBC_GearHeaderHorizontalScroll", fixedHeaderRow)
headerHorizontalScroll:SetPoint("TOPLEFT", headerCornerCell, "TOPRIGHT", 0, 0)
headerHorizontalScroll:SetPoint("BOTTOMRIGHT", fixedHeaderRow, "BOTTOMRIGHT", 0, 0)
headerHorizontalScroll:EnableMouse(true)
local headerGridContainer = CreateFrame("Frame", nil, headerHorizontalScroll)
headerGridContainer:SetPoint("TOPLEFT", headerHorizontalScroll, "TOPLEFT", 0, 0)
headerGridContainer:SetHeight(FIXED_HEADER_ROW_HEIGHT)
headerHorizontalScroll:SetScrollChild(headerGridContainer)

-- Vertical scroll bar: custom (no template) so it doesn't conflict with horizontal; both bars under our control
local verticalScrollBar = CreateFrame("Slider", "AltArmyTBC_GearVerticalScrollBar", rightPanel)
verticalScrollBar:SetPoint("TOPRIGHT", rightPanel, "TOPRIGHT", SCROLL_BAR_RIGHT_OFFSET + 4,
    -(PAD + SCROLL_BAR_TOP_INSET))
verticalScrollBar:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", SCROLL_BAR_RIGHT_OFFSET + 4,
    SCROLL_BAR_BOTTOM_INSET)
verticalScrollBar:SetWidth(SCROLL_BAR_WIDTH)
verticalScrollBar:SetMinMaxValues(0, 0)
verticalScrollBar:SetValueStep(dims.rowHeight)
verticalScrollBar:SetValue(0)
verticalScrollBar:SetOrientation("VERTICAL")
verticalScrollBar:EnableMouse(true)
Theme.SetupScrollBar(verticalScrollBar, { thickness = SCROLL_BAR_WIDTH })
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

-- Row headers (slot names) — below spacer so they scroll with rows; fixed header overlays spacer only
local slotHeaderContainer = CreateFrame("Frame", nil, verticalScrollChild)
slotHeaderContainer:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", 0, -FIXED_HEADER_ROW_HEIGHT)
slotHeaderContainer:SetPoint("BOTTOMLEFT", verticalScrollChild, "BOTTOMLEFT", 0, 0)
slotHeaderContainer:SetWidth(SLOT_LABEL_WIDTH)

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
        label:SetPoint("TOP", slotHeaderContainer, "TOP", 0, -SLOT_LABEL_ROW_OFFSET + 2)
    else
        label:SetPoint("TOP", slotLabels[slot - 1], "TOP", 0, -dims.rowHeight)
    end
    slotLabels[slot] = label
end

-- Horizontal viewport: below spacer, same vertical start as slot labels
local horizontalScroll = CreateFrame("ScrollFrame", "AltArmyTBC_GearHorizontalScroll", verticalScrollChild)
horizontalScroll:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", SLOT_LABEL_WIDTH, -FIXED_HEADER_ROW_HEIGHT)
horizontalScroll:SetPoint("BOTTOMRIGHT", verticalScrollChild, "BOTTOMRIGHT", 0, 0)
horizontalScroll:EnableMouse(true)

-- Grid area: scroll child of horizontalScroll; engine scrolls via SetHorizontalScroll (like vertical)
local gridContainer = CreateFrame("Frame", nil, horizontalScroll)
gridContainer:SetPoint("TOPLEFT", horizontalScroll, "TOPLEFT", 0, 0)
gridContainer:SetHeight(dims.scrollableGridHeight)
horizontalScroll:SetScrollChild(gridContainer)

-- Truncate name with "..." if it exceeds maxWidth; sets fontString text and returns displayed string.
local function TruncateName(fontString, fullName, maxWidth)
    if not fullName or fullName == "" then
        fontString:SetText("?")
        return "?"
    end
    fontString:SetText(fullName)
    if fontString:GetStringWidth() <= maxWidth then
        return fullName
    end
    for len = #fullName - 1, 1, -1 do
        local truncated = fullName:sub(1, len) .. "..."
        fontString:SetText(truncated)
        if fontString:GetStringWidth() <= maxWidth then
            return truncated
        end
    end
    fontString:SetText("...")
    return "..."
end

-- Header column pool: name + message per character, in fixed header row (scrolls horizontally)
local headerColumnPool = {}
local function GetHeaderColumnFrame(index)
    if not headerColumnPool[index] then
        local col = CreateFrame("Frame", nil, headerGridContainer)
        col:SetSize(dims.columnWidth, FIXED_HEADER_ROW_HEIGHT)
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
local horizontalScrollBar = CreateFrame("Slider", "AltArmyTBC_GearHorizontalScrollBar", rightPanel)
horizontalScrollBar:SetPoint("BOTTOMLEFT", rightPanel, "BOTTOMLEFT", PAD, PAD)
horizontalScrollBar:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -SCROLL_BAR_WIDTH - PAD, PAD)
horizontalScrollBar:SetHeight(HORIZONTAL_SCROLL_BAR_HEIGHT - PAD * 2)
horizontalScrollBar:SetOrientation("HORIZONTAL")
horizontalScrollBar:SetMinMaxValues(0, 0)
horizontalScrollBar:SetValueStep(1)
horizontalScrollBar:SetValue(0)
horizontalScrollBar:EnableMouse(true)
local lastHorizontalScrollValue = nil
local horizontalBarDragging = false
local horizontalDragStartX = 0
local horizontalDragStartValue = 0
local function ApplyHorizontalScrollValue(value)
    if not horizontalScroll then return end
    lastHorizontalScrollValue = value
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
end
local function SyncHorizontalScrollPosition()
    if not (horizontalScroll and horizontalScrollBar) then return end
    local value = horizontalScrollBar:GetValue()
    if lastHorizontalScrollValue == value then return end
    ApplyHorizontalScrollValue(value)
end
horizontalScrollBar:SetScript("OnValueChanged", function(_, _value)
    SyncHorizontalScrollPosition()
end)
-- Manual drag: Slider often doesn't update value when thumb is dragged; track mouse and set value ourselves
horizontalScrollBar:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" then return end
    horizontalBarDragging = true
    horizontalDragStartX = select(1, GetCursorPosition())
    horizontalDragStartValue = horizontalScrollBar:GetValue()
end)
horizontalScrollBar:SetScript("OnUpdate", function()
    if not frame:IsShown() then return end
    if horizontalBarDragging then
        if not IsMouseButtonDown(1) then
            horizontalBarDragging = false
        else
            local minVal, maxVal = horizontalScrollBar:GetMinMaxValues()
            local barWidth = horizontalScrollBar:GetWidth()
            if barWidth and barWidth > 0 and maxVal > minVal then
                local scale = (horizontalScrollBar.GetEffectiveScale and horizontalScrollBar:GetEffectiveScale())
                    or (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
                if scale <= 0 then scale = 1 end
                local cursorX = select(1, GetCursorPosition()) / scale
                local startX = horizontalDragStartX / scale
                local deltaX = cursorX - startX
                local value = horizontalDragStartValue + deltaX * (maxVal - minVal) / barWidth
                value = math.max(minVal, math.min(maxVal, value))
                horizontalScrollBar:SetValue(value)
                ApplyHorizontalScrollValue(value)
            end
        end
    end
end)
-- Visible track and thumb (TBC may lack SetBackdrop; thumb uses solid texture so it always shows)
Theme.SetupScrollBar(horizontalScrollBar, {
    horizontal = true,
    thickness = HORIZONTAL_SCROLL_BAR_HEIGHT - PAD * 2,
})

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
                if button ~= "LeftButton" or not IsShiftKeyDown() then return end
                InsertItemLinkIntoChat(self.itemLink or self.itemID)
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
            if slot == 1 then
                cell:SetPoint("TOPLEFT", col, "TOPLEFT", cellXOffset, -2)
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
            if entry.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.classFile] then
                local rc = RAID_CLASS_COLORS[entry.classFile]
                classR, classG, classB = rc.r, rc.g, rc.b
            end
        end
        headerCol.classR, headerCol.classG, headerCol.classB = classR, classG, classB
        local displayName = entry.name or "?"
        headerCol.header:SetTextColor(classR, classG, classB, 1)
        TruncateName(headerCol.header, displayName, dims.columnWidth - 4)
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
            local totalChildHeight = FIXED_HEADER_ROW_HEIGHT + dims.scrollableGridHeight
            local maxVertScroll = math.max(0, totalChildHeight - viewHeight)
            verticalScrollBar:SetMinMaxValues(0, maxVertScroll)
            verticalScrollBar:SetValueStep(dims.rowHeight)
            verticalScrollBar:SetStepsPerPage(10)
        end
        if horizontalScrollBar and horizontalScroll and gridContainer then
            local maxHorzScroll = math.max(0, gridContentWidth - gridViewWidth)
            horizontalScrollBar:SetMinMaxValues(0, maxHorzScroll)
            horizontalScrollBar:SetValueStep(1)
            horizontalScrollBar:SetShown(maxHorzScroll > 0)
            horizontalScrollBar:SetValue(0)
            lastHorizontalScrollValue = 0
            horizontalScroll:SetHorizontalScroll(0)
            if headerHorizontalScroll then
                headerHorizontalScroll:SetHorizontalScroll(0)
            end
        end
    end

    UpdateGridWithOffset()
end

--- Reapply fixed layout dimensions (medium icons, normal spacing).
local function ApplySpacing()
    dims.cellSize = GetCellSizePx()
    local rh, cw = GetSpacingDimensions()
    dims.rowHeight, dims.columnWidth = rh, cw
    dims.scrollableGridHeight = NUM_EQUIPMENT_SLOTS * dims.rowHeight + PAD

    if verticalScrollChild then
        verticalScrollChild:SetHeight(FIXED_HEADER_ROW_HEIGHT + dims.scrollableGridHeight)
    end
    if gridContainer then
        gridContainer:SetHeight(dims.scrollableGridHeight)
    end
    if verticalScrollBar then
        verticalScrollBar:SetValueStep(dims.rowHeight)
    end

    if slotLabels and slotLabels[1] then
        local slotLabelRowOffset = (dims.rowHeight - dims.cellSize) / 2
        for slot = 1, NUM_EQUIPMENT_SLOTS do
            slotLabels[slot]:SetHeight(dims.cellSize)
            slotLabels[slot]:ClearAllPoints()
            slotLabels[slot]:SetPoint("LEFT", slotHeaderContainer, "LEFT", 0, 0)
            if slot == 1 then
                slotLabels[slot]:SetPoint("TOP", slotHeaderContainer, "TOP", 0, -slotLabelRowOffset + 2)
            else
                slotLabels[slot]:SetPoint("TOP", slotLabels[slot - 1], "TOP", 0, -dims.rowHeight)
            end
        end
    end

    for _, col in pairs(headerColumnPool) do
        col:SetSize(dims.columnWidth, FIXED_HEADER_ROW_HEIGHT)
    end
    for _, col in pairs(columnPool) do
        col:SetSize(dims.columnWidth, dims.scrollableGridHeight)
        local cellXOffset = (dims.columnWidth - dims.cellSize) / 2
        for slot = 1, NUM_EQUIPMENT_SLOTS do
            local cell = col.cells[slot]
            cell:SetSize(dims.cellSize, dims.cellSize)
            cell:ClearAllPoints()
            if slot == 1 then
                cell:SetPoint("TOPLEFT", col, "TOPLEFT", cellXOffset, -2)
            else
                cell:SetPoint("TOPLEFT", col.cells[slot - 1], "BOTTOMLEFT", 0, -(dims.rowHeight - dims.cellSize))
            end
        end
    end
end

-- Apply layout when tab is shown (dims initialized at file load)
frame:SetScript("OnShow", function()
    ApplySpacing()
    frame:RefreshGrid()
end)

frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if AltArmy.Characters and AltArmy.Characters.InvalidateView then
            AltArmy.Characters:InvalidateView()
        end
        ApplySpacing()
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
    settingsPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", w * GRID_SPLIT_FRACTION + PAD, -PAD)
    settingsPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", w * GRID_SPLIT_FRACTION + PAD, PAD)
    settingsPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -PAD)
    settingsPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)
end
ApplySettingsPanelLayout()
settingsPanel:Hide()

local SETTINGS_ROW_HEIGHT = 22
local SETTINGS_TITLE_HEIGHT = 26
local settingsContent = Theme.CreateSettingsPanelContent(settingsPanel)
local gearSettingsTitle = settingsContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
gearSettingsTitle:SetPoint("TOPLEFT", settingsContent, "TOPLEFT", 0, 0)
gearSettingsTitle:SetPoint("TOPRIGHT", settingsContent, "TOPRIGHT", 0, 0)
gearSettingsTitle:SetJustifyH("LEFT")
gearSettingsTitle:SetText("Gear Settings")
Theme.SetTitleColor(gearSettingsTitle)
local primaryDropdown, secondaryDropdown  -- forward ref for dropdowns created below
local gearCharListRefresh = function() end

local sortingContent = CreateFrame("Frame", nil, settingsContent)
sortingContent:SetPoint("TOPLEFT", settingsContent, "TOPLEFT", 0, -SETTINGS_TITLE_HEIGHT - 8)
sortingContent:SetPoint("BOTTOMRIGHT", settingsContent, "BOTTOMRIGHT", 0, 0)
sortingContent:Show()

-- ---- Sort/Filter: Show self first, Primary/Secondary sort, Character list ----
local showSelfFirstCheck = CreateFrame("CheckButton", nil, sortingContent)
showSelfFirstCheck:SetPoint("TOPLEFT", sortingContent, "TOPLEFT", 0, 0)
showSelfFirstCheck:SetSize(24, 24)
local showSelfFirstBg = showSelfFirstCheck:CreateTexture(nil, "BACKGROUND")
showSelfFirstBg:SetAllPoints(showSelfFirstCheck)
Theme.ApplyCheckboxBackground(showSelfFirstBg)
local showSelfFirstCheckTex = showSelfFirstCheck:CreateTexture(nil, "OVERLAY")
showSelfFirstCheckTex:SetPoint("CENTER", showSelfFirstCheck, "CENTER", 0, 0)
showSelfFirstCheckTex:SetSize(16, 16)
showSelfFirstCheckTex:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
showSelfFirstCheck:SetCheckedTexture(showSelfFirstCheckTex)
local showSelfFirstLabel = showSelfFirstCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
showSelfFirstLabel:SetPoint("LEFT", showSelfFirstCheck, "RIGHT", 4, 0)
showSelfFirstLabel:SetText("Show self first")
showSelfFirstCheck:SetScript("OnClick", function()
    GetGearSettings().showSelfFirst = showSelfFirstCheck:GetChecked()
    if frame.RefreshGrid then frame:RefreshGrid() end
end)

-- Primary sort: full-width dropdown, collapsed shows "Primary Sort: Name"
local btnPrimary = CreateFrame("Button", nil, sortingContent)
btnPrimary:SetPoint("TOPLEFT", showSelfFirstCheck, "BOTTOMLEFT", 0, -6)
btnPrimary:SetPoint("TOPRIGHT", sortingContent, "TOPRIGHT", 0, 0)
btnPrimary:SetHeight(SETTINGS_ROW_HEIGHT)
local btnPrimaryText = btnPrimary:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
btnPrimaryText:SetPoint("LEFT", btnPrimary, "LEFT", 4, 0)
btnPrimaryText:SetPoint("RIGHT", btnPrimary, "RIGHT", -4, 0)
btnPrimaryText:SetJustifyH("LEFT")
Theme.SkinButton(btnPrimary)
primaryDropdown = CreateFrame("Frame", nil, sortingContent, "BackdropTemplate")
primaryDropdown:SetPoint("TOPLEFT", btnPrimary, "BOTTOMLEFT", 0, -2)
primaryDropdown:SetPoint("TOPRIGHT", btnPrimary, "BOTTOMRIGHT", 0, 0)
primaryDropdown:SetHeight(#SORT_OPTIONS * SETTINGS_ROW_HEIGHT + 4)
primaryDropdown:SetFrameLevel(sortingContent:GetFrameLevel() + 100)
primaryDropdown:Hide()
Theme.ApplyBackdrop(primaryDropdown, "section")
for idx, opt in ipairs(SORT_OPTIONS) do
    local b = CreateFrame("Button", nil, primaryDropdown)
    b:SetPoint("TOPLEFT", primaryDropdown, "TOPLEFT", 2, -2 - (idx - 1) * SETTINGS_ROW_HEIGHT)
    b:SetPoint("LEFT", primaryDropdown, "LEFT", 2, 0)
    b:SetPoint("RIGHT", primaryDropdown, "RIGHT", -2, 0)
    b:SetHeight(SETTINGS_ROW_HEIGHT - 2)
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT", b, "LEFT", 4, 0)
    t:SetText(opt)
    b.option = opt
    b:SetScript("OnClick", function()
        GetGearSettings().primarySort = opt
        primaryDropdown:Hide()
        btnPrimaryText:SetText("Primary Sort: " .. opt)
        if frame.RefreshGrid then frame:RefreshGrid() end
        if gearCharListRefresh then gearCharListRefresh() end
    end)
end
btnPrimary:SetScript("OnClick", function()
    primaryDropdown:SetShown(not primaryDropdown:IsShown())
    secondaryDropdown:Hide()
end)

-- Secondary sort: full-width dropdown, collapsed shows "Secondary Sort: Name"
local btnSecondary = CreateFrame("Button", nil, sortingContent)
btnSecondary:SetPoint("TOPLEFT", btnPrimary, "BOTTOMLEFT", 0, -6)
btnSecondary:SetPoint("TOPRIGHT", sortingContent, "TOPRIGHT", 0, 0)
btnSecondary:SetHeight(SETTINGS_ROW_HEIGHT)
local btnSecondaryText = btnSecondary:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
btnSecondaryText:SetPoint("LEFT", btnSecondary, "LEFT", 4, 0)
btnSecondaryText:SetPoint("RIGHT", btnSecondary, "RIGHT", -4, 0)
btnSecondaryText:SetJustifyH("LEFT")
Theme.SkinButton(btnSecondary)
secondaryDropdown = CreateFrame("Frame", nil, sortingContent, "BackdropTemplate")
secondaryDropdown:SetPoint("TOPLEFT", btnSecondary, "BOTTOMLEFT", 0, -2)
secondaryDropdown:SetPoint("TOPRIGHT", btnSecondary, "BOTTOMRIGHT", 0, 0)
secondaryDropdown:SetHeight(#SORT_OPTIONS * SETTINGS_ROW_HEIGHT + 4)
secondaryDropdown:SetFrameLevel(sortingContent:GetFrameLevel() + 100)
secondaryDropdown:Hide()
Theme.ApplyBackdrop(secondaryDropdown, "section")
for idx, opt in ipairs(SORT_OPTIONS) do
    local b = CreateFrame("Button", nil, secondaryDropdown)
    b:SetPoint("TOPLEFT", secondaryDropdown, "TOPLEFT", 2, -2 - (idx - 1) * SETTINGS_ROW_HEIGHT)
    b:SetPoint("LEFT", secondaryDropdown, "LEFT", 2, 0)
    b:SetPoint("RIGHT", secondaryDropdown, "RIGHT", -2, 0)
    b:SetHeight(SETTINGS_ROW_HEIGHT - 2)
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT", b, "LEFT", 4, 0)
    t:SetText(opt)
    b.option = opt
    b:SetScript("OnClick", function()
        GetGearSettings().secondarySort = opt
        secondaryDropdown:Hide()
        btnSecondaryText:SetText("Secondary Sort: " .. opt)
        if frame.RefreshGrid then frame:RefreshGrid() end
        if gearCharListRefresh then gearCharListRefresh() end
    end)
end
btnSecondary:SetScript("OnClick", function()
    secondaryDropdown:SetShown(not secondaryDropdown:IsShown())
    primaryDropdown:Hide()
end)

-- Character list: Pin/Hide (reusable component from UI/CharacterPinHideList.lua)
if AltArmy.CreateCharacterPinHideList then
    -- luacheck: push ignore 211
    local _scroll, refresh = AltArmy.CreateCharacterPinHideList(sortingContent, btnSecondary, {
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
    primaryDropdown:Hide()
    secondaryDropdown:Hide()
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

    -- Resize grid (rightPanel): full width when settings closed, left 60% when settings open
    rightPanel:ClearAllPoints()
    if LEFT_PANEL_VISIBLE then
        rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", PAD, 0)
    else
        rightPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD)
    end
    if showSettings then
        -- Extra gap so vertical scroll bar (anchored with RIGHT_OFFSET+4 past right edge) doesn't overlap settings
        rightPanel:SetPoint("BOTTOMRIGHT", settingsPanel, "BOTTOMLEFT", -(PAD + SCROLL_BAR_RIGHT_OFFSET + 4), 0)
    else
        rightPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)
    end

    if showSettings then
        local s = GetGearSettings()
        btnPrimaryText:SetText("Primary Sort: " .. s.primarySort)
        btnSecondaryText:SetText("Secondary Sort: " .. s.secondarySort)
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
        rightPanel:ClearAllPoints()
        if LEFT_PANEL_VISIBLE then
            rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", PAD, 0)
        else
            rightPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD)
        end
        rightPanel:SetPoint("BOTTOMRIGHT", settingsPanel, "BOTTOMLEFT", -(PAD + SCROLL_BAR_RIGHT_OFFSET + 4), 0)
        if frame.RefreshGrid then frame:RefreshGrid() end
    end
end)
