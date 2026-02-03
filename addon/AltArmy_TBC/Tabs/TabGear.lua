-- AltArmy TBC — Gear tab: "Who can use this?" drop box + equipment grid (slot rows x character columns)

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Gear
if not frame then return end

local DS = AltArmy.DataStore
local PAD = 4
local LEFT_PANEL_WIDTH = 120
local LEFT_PANEL_VISIBLE = false  -- set true to show "Who can use this?" drop zone
local COLUMN_HEADER_HEIGHT = 20
local MESSAGE_ROW_HEIGHT = 12
local CELL_SIZE = 28
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

--- True if this class can ever use this weapon subclass (TBC rules). subclass = GetItemInfo subclass e.g. "One-Handed Swords".
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

--- Build display list: filter hidden; order = self (if show self first) + pinned (sorted) + non-pinned (sorted). Optionally re-sort by "who can use" when item dropped.
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

    -- Split: self, pinned, non-pinned
    local selfEntry = nil
    local pinned = {}
    local nonPinned = {}
    for i = 1, #visible do
        local e = visible[i]
        local isSelf = (e.name == currentName and e.realm == currentRealm)
        if isSelf then
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
    if not showSelfFirst and selfEntry then list[#list + 1] = selfEntry end

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

--- Brief fit message for column: nil or "", or "Can not wear plate" / "10 levels ahead" etc. Returns message, color ("red" | "orange" | nil).
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

local dropBox = CreateFrame("Frame", "AltArmyTBC_GearDropBox", leftPanel)
dropBox:SetSize(40, 40)
dropBox:SetPoint("TOPLEFT", labelWho, "BOTTOMLEFT", 0, -4)
dropBox:EnableMouse(true)
if dropBox.SetBackdrop then
    dropBox:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
else
    local bg = dropBox:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(dropBox)
    bg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
end

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
local HEADER_ROW_HEIGHT = COLUMN_HEADER_HEIGHT
local COLUMN_HEADER_HEIGHT_GEAR = 18
local SLOT_LABEL_WIDTH = 80
local COLUMN_WIDTH = 61
local ROW_HEIGHT = 42
local SCROLL_BAR_WIDTH = 20
local FIXED_HEADER_ROW_HEIGHT = COLUMN_HEADER_HEIGHT_GEAR + MESSAGE_ROW_HEIGHT
local SCROLLABLE_GRID_HEIGHT = NUM_EQUIPMENT_SLOTS * ROW_HEIGHT + PAD
local GRID_CONTENT_HEIGHT = COLUMN_HEADER_HEIGHT_GEAR + MESSAGE_ROW_HEIGHT + NUM_EQUIPMENT_SLOTS * ROW_HEIGHT + PAD

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
contentArea:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -SCROLL_BAR_WIDTH, SCROLL_BAR_BOTTOM_INSET + HORIZONTAL_SCROLL_BAR_HEIGHT)

-- Vertical scroll: full content area; scroll child has spacer at top so header can overlay
local verticalScroll = CreateFrame("ScrollFrame", "AltArmyTBC_GearVerticalScroll", contentArea)
verticalScroll:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 0, 0)
verticalScroll:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", 0, 0)
verticalScroll:EnableMouse(true)

-- Scroll child: spacer at top (header overlays it) + slot labels + cell grid
local MIN_SCROLL_CHILD_WIDTH = 400
local verticalScrollChild = CreateFrame("Frame", nil, verticalScroll)
verticalScrollChild:SetPoint("TOPLEFT", verticalScroll, "TOPLEFT", 0, 0)
verticalScrollChild:SetHeight(FIXED_HEADER_ROW_HEIGHT + SCROLLABLE_GRID_HEIGHT)
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
headerBg:SetColorTexture(0.12, 0.12, 0.15, 1)
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
verticalScrollBar:SetPoint("TOPRIGHT", rightPanel, "TOPRIGHT", SCROLL_BAR_RIGHT_OFFSET + 4, -(PAD + SCROLL_BAR_TOP_INSET))
verticalScrollBar:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", SCROLL_BAR_RIGHT_OFFSET + 4, SCROLL_BAR_BOTTOM_INSET)
verticalScrollBar:SetWidth(SCROLL_BAR_WIDTH)
verticalScrollBar:SetMinMaxValues(0, 0)
verticalScrollBar:SetValueStep(ROW_HEIGHT)
verticalScrollBar:SetValue(0)
verticalScrollBar:SetOrientation("VERTICAL")
verticalScrollBar:EnableMouse(true)
local vertThumb = verticalScrollBar:CreateTexture(nil, "ARTWORK")
vertThumb:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
vertThumb:SetVertexColor(0.5, 0.5, 0.6, 1)
vertThumb:SetSize(SCROLL_BAR_WIDTH - 4, 24)
verticalScrollBar:SetThumbTexture(vertThumb)
verticalScrollBar:SetScript("OnValueChanged", function(_, value)
    verticalScroll:SetVerticalScroll(value)
end)

-- Mouse wheel: scroll the gear list when hovering over the scroll area (frame or scroll child)
local WHEEL_STEP = ROW_HEIGHT * 2
local function OnGearScrollWheel(_, delta)
    if not verticalScrollBar then return end
    local minVal, maxVal = verticalScrollBar:GetMinMaxValues()
    local current = verticalScrollBar:GetValue()
    -- delta: 1 = scroll up (see higher content), -1 = scroll down (see lower content)
    local newVal = current - delta * WHEEL_STEP
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

-- Slot labels: height CELL_SIZE and vertically centered in each row (row height is ROW_HEIGHT)
local SLOT_LABEL_ROW_OFFSET = (ROW_HEIGHT - CELL_SIZE) / 2
local slotLabels = {}
for slot = 1, NUM_EQUIPMENT_SLOTS do
    local label = slotHeaderContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", slotHeaderContainer, "LEFT", 0, 0)
    label:SetWidth(SLOT_LABEL_WIDTH - 4)
    label:SetHeight(CELL_SIZE)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("MIDDLE")
    label:SetText(SLOT_NAMES[SLOT_ORDER[slot]] or ("Slot " .. slot))
    if slot == 1 then
        label:SetPoint("TOP", slotHeaderContainer, "TOP", 0, -SLOT_LABEL_ROW_OFFSET + 2)
    else
        label:SetPoint("TOP", slotLabels[slot - 1], "TOP", 0, -ROW_HEIGHT)
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
gridContainer:SetHeight(SCROLLABLE_GRID_HEIGHT)
horizontalScroll:SetScrollChild(gridContainer)

-- Header column pool: name + message per character, in fixed header row (scrolls horizontally)
local headerColumnPool = {}
local function GetHeaderColumnFrame(index)
    if not headerColumnPool[index] then
        local col = CreateFrame("Frame", nil, headerGridContainer)
        col:SetSize(COLUMN_WIDTH, FIXED_HEADER_ROW_HEIGHT)
        col.header = col:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        col.header:SetPoint("TOPLEFT", col, "TOPLEFT", 0, 0)
        col.header:SetPoint("TOPRIGHT", col, "TOPRIGHT", 0, 0)
        col.header:SetHeight(COLUMN_HEADER_HEIGHT_GEAR)
        col.header:SetJustifyH("CENTER")
        col.header:SetWordWrap(true)
        col.header:SetNonSpaceWrap(true)
        col.message = col:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        col.message:SetPoint("TOP", col.header, "BOTTOM", 0, 0)
        col.message:SetPoint("LEFT", col, "LEFT", 0, 0)
        col.message:SetPoint("RIGHT", col, "RIGHT", 0, 0)
        col.message:SetHeight(MESSAGE_ROW_HEIGHT)
        col.message:SetJustifyH("CENTER")
        col.message:SetWordWrap(true)
        col.message:SetNonSpaceWrap(true)
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
horizontalScrollBar:SetScript("OnValueChanged", function(_, value)
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
                local scale = (horizontalScrollBar.GetEffectiveScale and horizontalScrollBar:GetEffectiveScale()) or (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
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
if horizontalScrollBar.SetBackdrop then
    horizontalScrollBar:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = nil,
        tile = true, tileSize = 0, edgeSize = 0,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    horizontalScrollBar:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
end
-- Thumb: visible draggable nub (TBC-friendly texture)
local thumbTex = horizontalScrollBar:CreateTexture(nil, "ARTWORK")
thumbTex:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
thumbTex:SetVertexColor(0.5, 0.5, 0.6, 1)
thumbTex:SetSize(24, HORIZONTAL_SCROLL_BAR_HEIGHT - PAD * 2)
horizontalScrollBar:SetThumbTexture(thumbTex)

local function GetColumnFrame(index)
    if not columnPool[index] then
        local col = CreateFrame("Frame", nil, gridContainer)
        col:SetSize(COLUMN_WIDTH, SCROLLABLE_GRID_HEIGHT)
        col.cells = {}
        for slot = 1, NUM_EQUIPMENT_SLOTS do
            local cell = CreateFrame("Frame", nil, col)
            cell:SetSize(CELL_SIZE, CELL_SIZE)
            cell:EnableMouse(true)
            local tex = cell:CreateTexture(nil, "OVERLAY")
            tex:SetAllPoints(cell)
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
            local cellXOffset = (COLUMN_WIDTH - CELL_SIZE) / 2
            if slot == 1 then
                cell:SetPoint("TOPLEFT", col, "TOPLEFT", cellXOffset, -2)
            else
                cell:SetPoint("TOPLEFT", col.cells[slot - 1], "BOTTOMLEFT", 0, -(ROW_HEIGHT - CELL_SIZE))
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
        headerCol:SetPoint("TOPLEFT", headerGridContainer, "TOPLEFT", (c - 1) * COLUMN_WIDTH + PAD, 0)
        headerCol:Show()

        local charData = DS and DS.GetCharacter and DS:GetCharacter(entry.name, entry.realm)
        headerCol.header:SetText(entry.name or "?")

        local gray = CanNeverUseCurrentItem(entry)
        if gray then
            headerCol.header:SetTextColor(0.5, 0.5, 0.5, 1)
        else
            if entry.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.classFile] then
                local rc = RAID_CLASS_COLORS[entry.classFile]
                headerCol.header:SetTextColor(rc.r, rc.g, rc.b, 1)
            else
                headerCol.header:SetTextColor(1, 0.82, 0, 1)
            end
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
        col:SetPoint("TOPLEFT", gridContainer, "TOPLEFT", (c - 1) * COLUMN_WIDTH + PAD - 4, 0)
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
        end
    end
end

function frame:RefreshGrid()
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
    local gridContentWidth = numCols * COLUMN_WIDTH + PAD
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
            local totalChildHeight = FIXED_HEADER_ROW_HEIGHT + SCROLLABLE_GRID_HEIGHT
            local maxVertScroll = math.max(0, totalChildHeight - viewHeight)
            verticalScrollBar:SetMinMaxValues(0, maxVertScroll)
            verticalScrollBar:SetValueStep(ROW_HEIGHT)
            verticalScrollBar:SetStepsPerPage(10)
        end
        if horizontalScrollBar and horizontalScroll and gridContainer then
            local maxHorzScroll = math.max(0, gridContentWidth - gridViewWidth)
            horizontalScrollBar:SetMinMaxValues(0, maxHorzScroll)
            horizontalScrollBar:SetValueStep(1)
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

frame:SetScript("OnShow", function()
    frame:RefreshGrid()
end)

frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if AltArmy.Characters and AltArmy.Characters.InvalidateView then
            AltArmy.Characters:InvalidateView()
        end
        if frame:IsShown() then
            frame:RefreshGrid()
        end
    end
end)

-- ---- Gear settings panel (replaces grid when settings icon clicked) ----
local settingsPanel = CreateFrame("Frame", nil, frame)
local frameWidth = frame:GetWidth()
if frameWidth <= 0 then frameWidth = 400 end
settingsPanel:SetPoint("TOP", frame, "TOP", 0, -PAD)
settingsPanel:SetPoint("BOTTOM", frame, "BOTTOM", 0, PAD)
settingsPanel:SetPoint("CENTER", frame, "CENTER", 0, 0)
settingsPanel:SetWidth(frameWidth * 0.5)
settingsPanel:Hide()

local SETTINGS_ROW_HEIGHT = 22

-- Show self first checkbox (at top)
local showSelfFirstCheck = CreateFrame("CheckButton", nil, settingsPanel)
showSelfFirstCheck:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 0, 0)
showSelfFirstCheck:SetSize(24, 24)
local showSelfFirstBg = showSelfFirstCheck:CreateTexture(nil, "BACKGROUND")
showSelfFirstBg:SetAllPoints(showSelfFirstCheck)
showSelfFirstBg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
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
local btnPrimary = CreateFrame("Button", nil, settingsPanel)
btnPrimary:SetPoint("TOPLEFT", showSelfFirstCheck, "BOTTOMLEFT", 0, -6)
btnPrimary:SetPoint("TOPRIGHT", settingsPanel, "TOPRIGHT", 0, 0)
btnPrimary:SetHeight(SETTINGS_ROW_HEIGHT)
local btnPrimaryBg = btnPrimary:CreateTexture(nil, "BACKGROUND")
btnPrimaryBg:SetAllPoints(btnPrimary)
btnPrimaryBg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
local btnPrimaryText = btnPrimary:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
btnPrimaryText:SetPoint("LEFT", btnPrimary, "LEFT", 4, 0)
btnPrimaryText:SetPoint("RIGHT", btnPrimary, "RIGHT", -4, 0)
btnPrimaryText:SetJustifyH("LEFT")
local primaryDropdown = CreateFrame("Frame", nil, settingsPanel)
primaryDropdown:SetPoint("TOPLEFT", btnPrimary, "BOTTOMLEFT", 0, -2)
primaryDropdown:SetPoint("TOPRIGHT", btnPrimary, "BOTTOMRIGHT", 0, 0)
primaryDropdown:SetHeight(#SORT_OPTIONS * SETTINGS_ROW_HEIGHT + 4)
primaryDropdown:SetFrameLevel(settingsPanel:GetFrameLevel() + 100)
primaryDropdown:Hide()
local primaryDropdownBg = primaryDropdown:CreateTexture(nil, "BACKGROUND")
primaryDropdownBg:SetAllPoints(primaryDropdown)
primaryDropdownBg:SetColorTexture(0.15, 0.15, 0.18, 0.98)
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
        if settingsPanel.RefreshCharacterList then settingsPanel:RefreshCharacterList() end
    end)
end
btnPrimary:SetScript("OnClick", function()
    primaryDropdown:SetShown(not primaryDropdown:IsShown())
    secondaryDropdown:Hide()
end)

-- Secondary sort: full-width dropdown, collapsed shows "Secondary Sort: Name"
local btnSecondary = CreateFrame("Button", nil, settingsPanel)
btnSecondary:SetPoint("TOPLEFT", btnPrimary, "BOTTOMLEFT", 0, -6)
btnSecondary:SetPoint("TOPRIGHT", settingsPanel, "TOPRIGHT", 0, 0)
btnSecondary:SetHeight(SETTINGS_ROW_HEIGHT)
local btnSecondaryBg = btnSecondary:CreateTexture(nil, "BACKGROUND")
btnSecondaryBg:SetAllPoints(btnSecondary)
btnSecondaryBg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
local btnSecondaryText = btnSecondary:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
btnSecondaryText:SetPoint("LEFT", btnSecondary, "LEFT", 4, 0)
btnSecondaryText:SetPoint("RIGHT", btnSecondary, "RIGHT", -4, 0)
btnSecondaryText:SetJustifyH("LEFT")
local secondaryDropdown = CreateFrame("Frame", nil, settingsPanel)
secondaryDropdown:SetPoint("TOPLEFT", btnSecondary, "BOTTOMLEFT", 0, -2)
secondaryDropdown:SetPoint("TOPRIGHT", btnSecondary, "BOTTOMRIGHT", 0, 0)
secondaryDropdown:SetHeight(#SORT_OPTIONS * SETTINGS_ROW_HEIGHT + 4)
secondaryDropdown:SetFrameLevel(settingsPanel:GetFrameLevel() + 100)
secondaryDropdown:Hide()
local secondaryDropdownBg = secondaryDropdown:CreateTexture(nil, "BACKGROUND")
secondaryDropdownBg:SetAllPoints(secondaryDropdown)
secondaryDropdownBg:SetColorTexture(0.15, 0.15, 0.18, 0.98)
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
        if settingsPanel.RefreshCharacterList then settingsPanel:RefreshCharacterList() end
    end)
end
btnSecondary:SetScript("OnClick", function()
    secondaryDropdown:SetShown(not secondaryDropdown:IsShown())
    primaryDropdown:Hide()
end)

-- Character list (scrollable): name | Pin | Hide
local CHAR_LIST_ROW = 20
local charListScroll = CreateFrame("ScrollFrame", nil, settingsPanel)
charListScroll:SetPoint("TOPLEFT", btnSecondary, "BOTTOMLEFT", 0, -8)
charListScroll:SetPoint("BOTTOMRIGHT", settingsPanel, "BOTTOMRIGHT", 0, 0)
charListScroll:EnableMouse(true)
local charListChild = CreateFrame("Frame", nil, charListScroll)
charListChild:SetPoint("TOPLEFT", charListScroll, "TOPLEFT", 0, 0)
charListChild:SetWidth(1)
charListScroll:SetScrollChild(charListChild)
charListScroll:SetScript("OnMouseWheel", function(_, delta)
    local scroll = charListScroll:GetVerticalScroll()
    local newScroll = scroll - delta * CHAR_LIST_ROW * 2
    newScroll = math.max(0, math.min(charListChild:GetHeight() - charListScroll:GetHeight(), newScroll))
    charListScroll:SetVerticalScroll(newScroll)
end)
local charListRowPool = {}
local function GetCharListRow(i)
    if not charListRowPool[i] then
        local row = CreateFrame("Frame", nil, charListChild)
        row:SetPoint("TOPLEFT", charListChild, "TOPLEFT", 0, -(i - 1) * CHAR_LIST_ROW)
        row:SetHeight(CHAR_LIST_ROW)
        row:SetPoint("RIGHT", charListChild, "RIGHT", 0, 0)
        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.nameText:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.nameText:SetPoint("RIGHT", row, "RIGHT", -120, 0)
        row.nameText:SetJustifyH("LEFT")
        row.pinBtn = CreateFrame("CheckButton", nil, row)
        row.pinBtn:SetPoint("RIGHT", row, "RIGHT", -60, 0)
        row.pinBtn:SetSize(18, 18)
        local pinBg = row.pinBtn:CreateTexture(nil, "BACKGROUND")
        pinBg:SetAllPoints(row.pinBtn)
        pinBg:SetColorTexture(0.25, 0.25, 0.25, 0.9)
        row.pinBtn.tex = row.pinBtn:CreateTexture(nil, "OVERLAY")
        row.pinBtn.tex:SetAllPoints(row.pinBtn)
        row.pinBtn.tex:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        row.pinBtn:SetCheckedTexture(row.pinBtn.tex)
        local pinLabel = row.pinBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pinLabel:SetPoint("RIGHT", row.pinBtn, "LEFT", -2, 0)
        pinLabel:SetText("Pin")
        row.hideBtn = CreateFrame("CheckButton", nil, row)
        row.hideBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.hideBtn:SetSize(18, 18)
        local hideBg = row.hideBtn:CreateTexture(nil, "BACKGROUND")
        hideBg:SetAllPoints(row.hideBtn)
        hideBg:SetColorTexture(0.25, 0.25, 0.25, 0.9)
        row.hideBtn.tex = row.hideBtn:CreateTexture(nil, "OVERLAY")
        row.hideBtn.tex:SetAllPoints(row.hideBtn)
        row.hideBtn.tex:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        row.hideBtn:SetCheckedTexture(row.hideBtn.tex)
        local hideLabel = row.hideBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hideLabel:SetPoint("RIGHT", row.hideBtn, "LEFT", -2, 0)
        hideLabel:SetText("Hide")
        charListRowPool[i] = row
    end
    return charListRowPool[i]
end

function settingsPanel:RefreshCharacterList()
    local rawList = (AltArmy.Characters and AltArmy.Characters.GetList and AltArmy.Characters:GetList()) or {}
    local list = {}
    for i = 1, #rawList do list[i] = rawList[i] end
    table.sort(list, function(a, b)
        local na, nb = (a.name or ""):lower(), (b.name or ""):lower()
        if na ~= nb then return na < nb end
        return (a.realm or ""):lower() < (b.realm or ""):lower()
    end)
    for idx, row in pairs(charListRowPool) do
        row:Hide()
    end
    local n = #list
    charListChild:SetWidth(charListScroll:GetWidth() or 350)
    charListChild:SetHeight(math.max(1, n * CHAR_LIST_ROW))
    for i = 1, n do
        local entry = list[i]
        local row = GetCharListRow(i)
        row:Show()
        row.nameText:SetText(entry.name or "?")
        if entry.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.classFile] then
            local rc = RAID_CLASS_COLORS[entry.classFile]
            row.nameText:SetTextColor(rc.r, rc.g, rc.b, 1)
        else
            row.nameText:SetTextColor(1, 0.82, 0, 1)
        end
        row.entry = entry
        local pin = GetCharSetting(entry.name, entry.realm, "pin")
        local hide = GetCharSetting(entry.name, entry.realm, "hide")
        row.pinBtn:SetChecked(pin)
        row.hideBtn:SetChecked(hide)
        row.pinBtn:SetScript("OnClick", function()
            local newPin = not GetCharSetting(entry.name, entry.realm, "pin")
            SetCharSetting(entry.name, entry.realm, newPin, false)
            row.pinBtn:SetChecked(newPin)
            row.hideBtn:SetChecked(false)
            if frame.RefreshGrid then frame:RefreshGrid() end
        end)
        row.hideBtn:SetScript("OnClick", function()
            local newHide = not GetCharSetting(entry.name, entry.realm, "hide")
            SetCharSetting(entry.name, entry.realm, false, newHide)
            row.hideBtn:SetChecked(newHide)
            row.pinBtn:SetChecked(false)
            if frame.RefreshGrid then frame:RefreshGrid() end
        end)
    end
end

-- Close dropdowns when clicking outside
settingsPanel:SetScript("OnHide", function()
    primaryDropdown:Hide()
    secondaryDropdown:Hide()
end)

function frame:IsGearSettingsShown()
    return settingsPanel and settingsPanel:IsShown()
end

function frame:ToggleGearSettings()
    local showSettings = not settingsPanel:IsShown()
    settingsPanel:SetShown(showSettings)
    rightPanel:SetShown(not showSettings)
    if LEFT_PANEL_VISIBLE then
        leftPanel:SetShown(not showSettings)
    end
    if showSettings then
        local w = frame:GetWidth()
        if w > 0 then settingsPanel:SetWidth(w * 0.5) end
        local s = GetGearSettings()
        btnPrimaryText:SetText("Primary Sort: " .. s.primarySort)
        btnSecondaryText:SetText("Secondary Sort: " .. s.secondarySort)
        showSelfFirstCheck:SetChecked(s.showSelfFirst)
        if AltArmy.Characters and AltArmy.Characters.InvalidateView then
            AltArmy.Characters:InvalidateView()
        end
        settingsPanel:RefreshCharacterList()
    end
end
