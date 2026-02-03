-- AltArmy TBC — Gear tab: "Who can use this?" drop box + equipment grid (slot rows x character columns)

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Gear
if not frame then return end

local DS = AltArmy.DataStore
local PAD = 4
local LEFT_PANEL_WIDTH = 120
local COLUMN_HEADER_HEIGHT = 20
local MESSAGE_ROW_HEIGHT = 20
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
    [18] = "Ranged",
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

--- Build display list: default = by level (highest first); when item dropped = by "who can use" then level delta.
local function GetDisplayList()
    if not AltArmy.Characters or not AltArmy.Characters.GetList then return {} end
    local list = AltArmy.Characters:GetList()
    if #list == 0 then return list end

    if not droppedItemLink then
        return list
    end

    local reqLevel, armorSubclass, weaponSubclass = GetItemUseInfo(droppedItemLink)
    if reqLevel == nil and armorSubclass == nil and weaponSubclass == nil then
        -- GetItemInfo failed (e.g. not cached); keep default order
        return list
    end
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

-- ---- Right panel: slot row headers + scrollable character columns ----
local HEADER_ROW_HEIGHT = COLUMN_HEADER_HEIGHT
local COLUMN_HEADER_HEIGHT_GEAR = 36
local SLOT_LABEL_WIDTH = 80
local COLUMN_WIDTH = 61
local ROW_HEIGHT = 42
local SCROLL_BAR_WIDTH = 20
local GRID_CONTENT_HEIGHT = COLUMN_HEADER_HEIGHT_GEAR + MESSAGE_ROW_HEIGHT + NUM_EQUIPMENT_SLOTS * ROW_HEIGHT + PAD

local rightPanel = CreateFrame("Frame", nil, frame)
rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", PAD, 0)
rightPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)

local SCROLL_BAR_TOP_INSET = 16
local SCROLL_BAR_BOTTOM_INSET = 16
local SCROLL_BAR_RIGHT_OFFSET = 4
local HORIZONTAL_SCROLL_BAR_HEIGHT = 20

-- Content area: leave room for vertical bar on right and horizontal bar at bottom
local contentArea = CreateFrame("Frame", nil, rightPanel)
contentArea:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 0, -(PAD + SCROLL_BAR_TOP_INSET))
contentArea:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -SCROLL_BAR_WIDTH, SCROLL_BAR_BOTTOM_INSET + HORIZONTAL_SCROLL_BAR_HEIGHT)

-- Vertical scroll (plain ScrollFrame, no template) so slot labels + grid stay inside the UI
local verticalScroll = CreateFrame("ScrollFrame", "AltArmyTBC_GearVerticalScroll", contentArea)
verticalScroll:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 0, 0)
verticalScroll:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", 0, 0)
verticalScroll:EnableMouse(true)

-- Scroll child: viewport width only; slot labels + horizontal scroll viewport live here (no horizontal scroll on this frame)
local MIN_SCROLL_CHILD_WIDTH = 400
local verticalScrollChild = CreateFrame("Frame", nil, verticalScroll)
verticalScrollChild:SetPoint("TOPLEFT", verticalScroll, "TOPLEFT", 0, 0)
verticalScrollChild:SetHeight(GRID_CONTENT_HEIGHT)
verticalScrollChild:SetWidth(MIN_SCROLL_CHILD_WIDTH)
verticalScrollChild:EnableMouse(true)
verticalScroll:SetScrollChild(verticalScrollChild)

-- Vertical scroll bar: custom (no template) so it doesn't conflict with horizontal; both bars under our control
local verticalScrollBar = CreateFrame("Slider", "AltArmyTBC_GearVerticalScrollBar", rightPanel)
verticalScrollBar:SetPoint("TOPRIGHT", rightPanel, "TOPRIGHT", SCROLL_BAR_RIGHT_OFFSET, -(PAD + SCROLL_BAR_TOP_INSET))
verticalScrollBar:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", SCROLL_BAR_RIGHT_OFFSET, SCROLL_BAR_BOTTOM_INSET)
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

-- Row headers (slot names) — fixed on the left; create before horizontal scroll so viewport can anchor to them
local slotHeaderContainer = CreateFrame("Frame", nil, verticalScrollChild)
slotHeaderContainer:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", 0, 0)
slotHeaderContainer:SetPoint("BOTTOMLEFT", verticalScrollChild, "BOTTOMLEFT", 0, 0)
slotHeaderContainer:SetWidth(SLOT_LABEL_WIDTH)

-- Corner cell (above slot labels); height matches column header so slot labels align with equipment rows
local cornerCell = slotHeaderContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
cornerCell:SetPoint("TOPLEFT", slotHeaderContainer, "TOPLEFT", 0, 0)
cornerCell:SetWidth(SLOT_LABEL_WIDTH - 4)
cornerCell:SetHeight(COLUMN_HEADER_HEIGHT_GEAR)
cornerCell:SetJustifyH("LEFT")
cornerCell:SetText("")

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
        label:SetPoint("TOP", cornerCell, "BOTTOM", 0, -(MESSAGE_ROW_HEIGHT + 2 + SLOT_LABEL_ROW_OFFSET))
    else
        label:SetPoint("TOP", slotLabels[slot - 1], "TOP", 0, -ROW_HEIGHT)
    end
    slotLabels[slot] = label
end

-- Horizontal viewport: create before scroll bar scripts so callbacks see non-nil horizontalScroll
local horizontalScroll = CreateFrame("ScrollFrame", "AltArmyTBC_GearHorizontalScroll", verticalScrollChild)
horizontalScroll:SetPoint("TOPLEFT", slotHeaderContainer, "TOPRIGHT", 0, 0)
horizontalScroll:SetPoint("BOTTOMRIGHT", verticalScrollChild, "BOTTOMRIGHT", 0, 0)
horizontalScroll:EnableMouse(true)

-- Grid area: scroll child of horizontalScroll; engine scrolls via SetHorizontalScroll (like vertical)
local gridContainer = CreateFrame("Frame", nil, horizontalScroll)
gridContainer:SetPoint("TOPLEFT", horizontalScroll, "TOPLEFT", 0, 0)
gridContainer:SetHeight(GRID_CONTENT_HEIGHT)
horizontalScroll:SetScrollChild(gridContainer)

-- Pool of character column frames (reused)
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
        col:SetSize(COLUMN_WIDTH, COLUMN_HEADER_HEIGHT_GEAR + MESSAGE_ROW_HEIGHT + NUM_EQUIPMENT_SLOTS * ROW_HEIGHT + PAD)
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
        col.cells = {}
        for slot = 1, NUM_EQUIPMENT_SLOTS do
            local cell = CreateFrame("Frame", nil, col)
            cell:SetSize(CELL_SIZE, CELL_SIZE)
            local tex = cell:CreateTexture(nil, "OVERLAY")
            tex:SetAllPoints(cell)
            cell.texture = tex
            if slot == 1 then
                cell:SetPoint("TOP", col.message, "BOTTOM", 0, -2)
            else
                cell:SetPoint("TOP", col.cells[slot - 1], "BOTTOM", 0, -(ROW_HEIGHT - CELL_SIZE))
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

    for c = 1, numCols do
        local entry = list[c]
        local col = GetColumnFrame(c)
        col:ClearAllPoints()
        col:SetPoint("TOPLEFT", gridContainer, "TOPLEFT", (c - 1) * COLUMN_WIDTH + PAD, 0)
        col:Show()

        local charData = DS and DS.GetCharacter and DS:GetCharacter(entry.name, entry.realm)
        col.header:SetText(entry.name or "?")

        local gray = CanNeverUseCurrentItem(entry)
        if gray then
            col.header:SetTextColor(0.5, 0.5, 0.5, 1)
        else
            if entry.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.classFile] then
                local rc = RAID_CLASS_COLORS[entry.classFile]
                col.header:SetTextColor(rc.r, rc.g, rc.b, 1)
            else
                col.header:SetTextColor(1, 0.82, 0, 1)
            end
        end

        local fitMsg, fitColor = GetFitMessage(entry)
        if fitMsg and fitMsg ~= "" then
            col.message:SetText(fitMsg)
            if fitColor == "red" then
                col.message:SetTextColor(1, 0.3, 0.3, 1)
            elseif fitColor == "orange" then
                col.message:SetTextColor(1, 0.6, 0.2, 1)
            else
                col.message:SetTextColor(0.9, 0.9, 0.9, 1)
            end
            col.message:Show()
        else
            col.message:SetText("")
            col.message:Show()
        end

        for slot = 1, NUM_EQUIPMENT_SLOTS do
            local cell = col.cells[slot]
            local item = charData and DS.GetInventoryItem and DS:GetInventoryItem(charData, SLOT_ORDER[slot])
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

    -- Vertical scroll child: viewport width only so slot labels stay on screen; horizontal scroll is inner (grid only)
    if verticalScrollChild and verticalScroll then
        verticalScrollChild:SetWidth(math.max(MIN_SCROLL_CHILD_WIDTH, viewWidth))
        if gridContainer then
            gridContainer:SetWidth(math.max(0, gridContentWidth))
        end
        if verticalScrollBar then
            local maxVertScroll = math.max(0, GRID_CONTENT_HEIGHT - viewHeight)
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
