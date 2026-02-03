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

-- Equipment slot ID -> display name (TBC slots 1-19)
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
local SLOT_LABEL_WIDTH = 80
local COLUMN_WIDTH = CELL_SIZE + 4
local NUM_VISIBLE_COLUMNS = 12
local SCROLL_BAR_WIDTH = 20

local rightPanel = CreateFrame("Frame", nil, frame)
rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", PAD, 0)
rightPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)

-- Row headers (slot names), fixed on the left
local slotHeaderContainer = CreateFrame("Frame", nil, rightPanel)
slotHeaderContainer:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 0, 0)
slotHeaderContainer:SetPoint("BOTTOMLEFT", rightPanel, "BOTTOMLEFT", 0, 0)
slotHeaderContainer:SetWidth(SLOT_LABEL_WIDTH)

-- Corner cell (above slot labels)
local cornerCell = slotHeaderContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
cornerCell:SetPoint("TOPLEFT", slotHeaderContainer, "TOPLEFT", 0, 0)
cornerCell:SetWidth(SLOT_LABEL_WIDTH - 4)
cornerCell:SetHeight(HEADER_ROW_HEIGHT)
cornerCell:SetJustifyH("LEFT")
cornerCell:SetText("")

local slotLabels = {}
for slot = 1, NUM_EQUIPMENT_SLOTS do
    local label = slotHeaderContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", slotHeaderContainer, "LEFT", 0, 0)
    label:SetWidth(SLOT_LABEL_WIDTH - 4)
    label:SetHeight(CELL_SIZE)
    label:SetJustifyH("LEFT")
    label:SetText(SLOT_NAMES[slot] or ("Slot " .. slot))
    if slot == 1 then
        label:SetPoint("TOP", cornerCell, "BOTTOM", 0, -(MESSAGE_ROW_HEIGHT + 2))
    else
        label:SetPoint("TOP", slotLabels[slot - 1], "BOTTOM", 0, 0)
    end
    slotLabels[slot] = label
end

-- Grid area: fixed column pool (no ScrollFrame; we scroll by offset)
local gridContainer = CreateFrame("Frame", nil, rightPanel)
gridContainer:SetPoint("TOPLEFT", slotHeaderContainer, "TOPRIGHT", 0, 0)
gridContainer:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -SCROLL_BAR_WIDTH, 0)

-- Pool of character column frames (reused)
local columnPool = {}
local gridScrollBar
local scrollOffset = 0

local function GetColumnFrame(index)
    if not columnPool[index] then
        local col = CreateFrame("Frame", nil, gridContainer)
        col:SetHeight(HEADER_ROW_HEIGHT + MESSAGE_ROW_HEIGHT + NUM_EQUIPMENT_SLOTS * CELL_SIZE + PAD)
        col.header = col:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        col.header:SetPoint("TOP", col, "TOP", 0, 0)
        col.header:SetWidth(COLUMN_WIDTH - 4)
        col.header:SetHeight(HEADER_ROW_HEIGHT)
        col.header:SetJustifyH("CENTER")
        col.message = col:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        col.message:SetPoint("TOP", col.header, "BOTTOM", 0, 0)
        col.message:SetWidth(COLUMN_WIDTH - 4)
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
                cell:SetPoint("TOP", col.cells[slot - 1], "BOTTOM", 0, 0)
            end
            col.cells[slot] = cell
        end
        columnPool[index] = col
    end
    return columnPool[index]
end

-- Slider for character column offset (scroll through many characters)
gridScrollBar = CreateFrame("Slider", "AltArmyTBC_GearScrollBar", rightPanel, "UIPanelScrollBarTemplate")
gridScrollBar:SetPoint("TOPLEFT", gridContainer, "TOPRIGHT", 0, 0)
gridScrollBar:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", 0, 0)
gridScrollBar:SetWidth(SCROLL_BAR_WIDTH)
gridScrollBar:SetMinMaxValues(0, 0)
gridScrollBar:SetValueStep(1)
gridScrollBar:SetValue(0)

local function UpdateGridWithOffset(offset)
    scrollOffset = offset
    if not AltArmy.Characters then return end
    local list = GetDisplayList()
    local numCols = #list
    local visibleCols = math.min(NUM_VISIBLE_COLUMNS, numCols)

    for i = 1, NUM_VISIBLE_COLUMNS do
        local col = GetColumnFrame(i)
        col:Hide()
    end

    for c = 1, visibleCols do
        local idx = offset + c
        if idx > numCols then break end
        local entry = list[idx]
        local col = GetColumnFrame(c)
        col:ClearAllPoints()
        col:SetPoint("TOPLEFT", gridContainer, "TOPLEFT", (c - 1) * COLUMN_WIDTH + PAD, 0)
        col:Show()

        local charData = DS and DS.GetCharacter and DS:GetCharacter(entry.name, entry.realm)
        local levelStr = entry.level and string.format("%.0f", math.floor(tonumber(entry.level) * 10) / 10) or "?"
        col.header:SetText((entry.name or "?") .. "\n" .. levelStr)

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
            local item = charData and DS.GetInventoryItem and DS:GetInventoryItem(charData, slot)
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
    local maxOffset = math.max(0, numCols - NUM_VISIBLE_COLUMNS)
    scrollOffset = math.min(scrollOffset, maxOffset)

    if gridScrollBar then
        gridScrollBar:SetMinMaxValues(0, maxOffset)
        gridScrollBar:SetValueStep(1)
        gridScrollBar:SetValue(scrollOffset)
        gridScrollBar:SetStepsPerPage(NUM_VISIBLE_COLUMNS - 1)
        gridScrollBar:SetScript("OnValueChanged", function(_, value)
            UpdateGridWithOffset(math.floor(value + 0.5))
        end)
    end

    UpdateGridWithOffset(scrollOffset)
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
