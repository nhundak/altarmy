-- AltArmy TBC — Gear tab: "Who can use this?" drop box + equipment grid (slot rows x character columns)

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Gear
if not frame then return end

local GearTab = {}

local DS = AltArmy.DataStore
local Theme = AltArmy.Theme
local CC = AltArmy.ClassColor
local GearScoreMod = AltArmy.GearScore
local SD = AltArmy.SummaryData
local SSR = AltArmy.ScoreSortRow
local IU = AltArmy.ItemUsability
local GU = AltArmy.GearUpgrade
local GC = AltArmy.GearCompare
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
local selectedCompareKey = nil
local hoveredCompareKey = nil
local sessionCompareTechnique = nil
local comparePanelHeight = 0

local COMPARE_ROW_HEIGHT = 14
local COMPARE_SECTION_GAP = 6
local COMPARE_TITLE_HEIGHT = 18
local COMPARE_DROPDOWN_ROW = 24
local COMPARE_PANEL_PAD = 8
local COMPARE_PANEL_MIN_HEIGHT = 100
local COMPARE_ALGO_DROPDOWN_WIDTH = 220
local SELECTION_OUTLINE_WIDTH = 2
local COMPARE_HOVER_COLOR = { 0.82, 0.68, 0.22, 0.32 }

-- Gear settings persistence (AltArmyTBC_GearSettings)
local DEFAULT_SCORE_PROVIDER = "level"
local SLOT_LABEL_WIDTH = 98
local SCORE_SORT_BTN_GAP = 2
local SCORE_ROW_LAYOUT_TRIM = 4
local SCORE_ROW_HEADER_BOTTOM_INSET = 6
local UPGRADE_HIGHLIGHT_COLUMN_INSET = 2
local ITEM_CHECK_BTN_TOP_OFFSET = 4
local ITEM_CHECK_BTN_BOTTOM_GAP = 0

function GearTab.GetAvailableScoreProviders()
    return SSR.GetAvailableProviders()
end

function GearTab.ValidateScoreProvider(id)
    return SSR.ValidateProvider(id)
end

function GearTab.GetGearSettings()
    AltArmyTBC_GearSettings = AltArmyTBC_GearSettings or {}
    local s = AltArmyTBC_GearSettings
    if s.showSelfFirst == nil then s.showSelfFirst = true end
    if s.scoreSortDescending == nil then s.scoreSortDescending = true end
    s.scoreProvider = GearTab.ValidateScoreProvider(s.scoreProvider or DEFAULT_SCORE_PROVIDER)
    s.characters = s.characters or {}
    return s
end

function GearTab.GetSelectedScoreProvider()
    local s = GearTab.GetGearSettings()
    return GearTab.ValidateScoreProvider(s.scoreProvider or DEFAULT_SCORE_PROVIDER)
end

function GearTab.GetScoreProviderLabel(providerId)
    return SSR.GetProviderLabel(providerId)
end

--- Fixed layout: Normal spacing (12px row/column gaps) and medium icons (32px).
function GearTab.GetSpacingGaps()
    return 12, 12
end

function GearTab.GetIconSizePx()
    return 32
end

local ITEM_GLOW_ALPHA = 0.4
local ITEM_ICON_INSET = 2

--- Cell frame size: icon plus inset on each side for rarity glow ring.
function GearTab.GetCellSizePx()
    return GearTab.GetIconSizePx() + 2 * ITEM_ICON_INSET
end

--- Returns rowHeight, columnWidth for current spacing and cell size.
function GearTab.GetSpacingDimensions()
    local rowGap, colGap = GearTab.GetSpacingGaps()
    local cell = GearTab.GetCellSizePx()
    return cell + rowGap, cell + colGap
end

local dims = {}
local CharKey = AltArmy.CharKey

function GearTab.GetScoreRowContentHeight()
    local rh = dims.rowHeight or select(1, GearTab.GetSpacingDimensions())
    return math.floor(rh / 2)
end

function GearTab.GetScoreRowHeight()
    return GearTab.GetScoreRowContentHeight() - SCORE_ROW_LAYOUT_TRIM
end

function GearTab.GetScoreSortBtnSize()
    return GearTab.GetScoreRowContentHeight()
end

function GearTab.GetFocusedSlotSet()
    if not droppedItemLink or not IU or not IU.GetInventorySlotsForItem then return nil end
    local slots = IU.GetInventorySlotsForItem(droppedItemLink)
    if not slots or #slots == 0 then return nil end
    local set = {}
    for i = 1, #slots do
        set[slots[i]] = true
    end
    return set
end

function GearTab.IsDisplaySlotVisible(displayIdx)
    local focused = GearTab.GetFocusedSlotSet()
    if not focused then return true end
    local invSlot = SLOT_ORDER[displayIdx]
    return focused[invSlot] == true
end

function GearTab.GetVisibleDisplaySlots()
    local out = {}
    for slot = 1, NUM_EQUIPMENT_SLOTS do
        if GearTab.IsDisplaySlotVisible(slot) then
            out[#out + 1] = slot
        end
    end
    return out
end

function GearTab.GetScrollableGridHeight()
    local rh = dims.rowHeight or select(1, GearTab.GetSpacingDimensions())
    local visibleCount = #GearTab.GetVisibleDisplaySlots()
    if visibleCount <= 0 then
        visibleCount = NUM_EQUIPMENT_SLOTS
    end
    return visibleCount * rh + PAD
end

function GearTab.GetSessionCompareTechnique()
    if sessionCompareTechnique then return sessionCompareTechnique end
    if GU and GU.GetOptions then return GU.GetOptions().technique or "custom" end
    return "custom"
end

function GearTab.ClearCompareSelection()
    selectedCompareKey = nil
    hoveredCompareKey = nil
    sessionCompareTechnique = nil
    comparePanelHeight = 0
end

function GearTab.GetSelectedCompareEntry(list)
    if not selectedCompareKey or not list then return nil end
    for i = 1, #list do
        local e = list[i]
        if CharKey(e.name, e.realm) == selectedCompareKey then
            return e
        end
    end
    return nil
end

function GearTab.EstimateComparePanelHeight(comparison, showDropdown)
    if not comparison then return 0 end
    local h = COMPARE_PANEL_PAD * 2 + COMPARE_TITLE_HEIGHT + 14
    if showDropdown then
        h = h + COMPARE_DROPDOWN_ROW
    end
    local sections = comparison.sections or {}
    for s = 1, #sections do
        local section = sections[s]
        h = h + COMPARE_SECTION_GAP + COMPARE_ROW_HEIGHT
        h = h + #(section.rows or {}) * COMPARE_ROW_HEIGHT
    end
    return math.max(COMPARE_PANEL_MIN_HEIGHT, h)
end

function GearTab.GetCharSetting(name, realm, key)
    local s = GearTab.GetGearSettings()
    local c = s.characters[CharKey(name, realm)]
    if not c then return false end
    return c[key] == true
end

function GearTab.SetCharSetting(name, realm, pin, hide)
    local s = GearTab.GetGearSettings()
    local key = CharKey(name, realm)
    s.characters[key] = { pin = pin == true, hide = hide == true }
end

function GearTab.CanClassEverUseArmor(classFile, subclass)
    return IU and IU.CanClassEverUseArmor(classFile, subclass) or true
end

function GearTab.CanClassEverUseWeapon(classFile, weaponSubclass)
    return IU and IU.CanClassEverUseWeapon(classFile, weaponSubclass) or true
end

function GearTab.GetItemUseInfo(link)
    if IU and IU.GetItemUseInfo then
        return IU.GetItemUseInfo(link)
    end
    return nil, nil, nil
end

function GearTab.CompareBySelectedScore(entryA, entryB, providerId, descending)
    return SSR.Compare(entryA, entryB, providerId, descending)
end

function GearTab.DecorateDisplayEntry(entry)
    SSR.DecorateEntry(entry)
end

--- Build display list: filter hidden; order = pinned (incl. current when pin-current) + non-pinned.
--- Optionally re-sort by "who can use" when item dropped.
function GearTab.GetDisplayList()
    if not AltArmy.Characters or not AltArmy.Characters.GetList then return {} end
    local rawList = AltArmy.Characters:GetList()
    if #rawList == 0 then return rawList end

    local settings = GearTab.GetGearSettings()
    local currentRealm = DS and DS.GetCurrentPlayerRealm and DS:GetCurrentPlayerRealm() or ""
    local showSelfFirst = settings.showSelfFirst ~= false

    -- Filter out hidden (pin-current-character overrides hide for the signed-in character)
    local visible = {}
    for i = 1, #rawList do
        local e = rawList[i]
        local isSelf = DS and DS.IsCurrentCharacter and DS:IsCurrentCharacter(e.name, e.realm)
        local isHidden = GearTab.GetCharSetting(e.name, e.realm, "hide")
        if not isHidden or (showSelfFirst and isSelf) then
            visible[#visible + 1] = e
            GearTab.DecorateDisplayEntry(e)
        end
    end

    local providerId = GearTab.GetSelectedScoreProvider()
    local descending = settings.scoreSortDescending ~= false

    -- Split: pinned (manual pin or pin-current-character), non-pinned
    local pinned = {}
    local nonPinned = {}
    for i = 1, #visible do
        local e = visible[i]
        local isSelf = DS and DS.IsCurrentCharacter and DS:IsCurrentCharacter(e.name, e.realm)
        local isPinned = GearTab.GetCharSetting(e.name, e.realm, "pin")
        if isPinned or (showSelfFirst and isSelf) then
            pinned[#pinned + 1] = e
        else
            nonPinned[#nonPinned + 1] = e
        end
    end

    table.sort(pinned, function(a, b)
        return GearTab.CompareBySelectedScore(a, b, providerId, descending)
    end)
    table.sort(nonPinned, function(a, b)
        return GearTab.CompareBySelectedScore(a, b, providerId, descending)
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

    -- When item focused, sort: upgrades first, then usable, then cannot use.
    if not droppedItemLink then return list end
    local upgradeOpts = GU and GU.GetOptions and GU.GetOptions() or {}
    local copy = {}
    for i = 1, #list do copy[i] = list[i] end
    table.sort(copy, function(a, b)
        local charA = DS and DS.GetCharacter and DS:GetCharacter(a.name, a.realm)
        local charB = DS and DS.GetCharacter and DS:GetCharacter(b.name, b.realm)
        local ta = GU and GU.GetFocusTier and GU.GetFocusTier(a, charA, droppedItemLink, upgradeOpts) or 3
        local tb = GU and GU.GetFocusTier and GU.GetFocusTier(b, charB, droppedItemLink, upgradeOpts) or 3
        if ta ~= tb then return ta < tb end
        if ta == 1 and GU and GU.GetFocusUpgradeDelta then
            local da = GU.GetFocusUpgradeDelta(a, charA, droppedItemLink, upgradeOpts) or 0
            local db = GU.GetFocusUpgradeDelta(b, charB, droppedItemLink, upgradeOpts) or 0
            if da ~= db then return da > db end
        end
        return (a.name or "") < (b.name or "")
    end)
    return copy
end

function GearTab.GetFocusTierForEntry(entry)
    if not droppedItemLink or not GU or not GU.GetFocusTier then return nil end
    local charData = DS and DS.GetCharacter and DS:GetCharacter(entry.name, entry.realm)
    local opts = GU.GetOptions and GU.GetOptions() or {}
    return GU.GetFocusTier(entry, charData, droppedItemLink, opts)
end

function GearTab.getUpgradeHighlightHorizontalInset()
    return UPGRADE_HIGHLIGHT_COLUMN_INSET
end

function GearTab.getUpgradeHighlightBelowHeaderExtent()
    local rh = dims.rowHeight or select(1, GearTab.GetSpacingDimensions())
    local cell = dims.cellSize or GearTab.GetCellSizePx()
    return (rh - cell) / 2 + cell
end

function GearTab.getUpgradeHighlightColor(delta, minDelta, maxDelta)
    if not delta or delta <= 0 then
        return 0.45, 0.85, 0.45, 0.22
    end
    local t = 1
    if minDelta and maxDelta and maxDelta > minDelta then
        t = (delta - minDelta) / (maxDelta - minDelta)
    end
    local r = 0.55 - t * 0.35
    local g = 0.82 + t * 0.08
    local b = 0.55 - t * 0.35
    local a = 0.18 + t * 0.25
    return r, g, b, a
end

function GearTab.layoutUpgradeHighlight(headerCol, show, delta, minDelta, maxDelta)
    if not headerCol or not headerCol.upgradeHighlight then return end
    local tex = headerCol.upgradeHighlight
    if not show then
        tex:Hide()
        return
    end
    local hInset = GearTab.getUpgradeHighlightHorizontalInset()
    local extendBelow = GearTab.getUpgradeHighlightBelowHeaderExtent()
    local r, g, b, a = GearTab.getUpgradeHighlightColor(delta, minDelta, maxDelta)
    tex:SetColorTexture(r, g, b, a)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", headerCol.header, "TOPLEFT", hInset, 1)
    tex:SetPoint("BOTTOMRIGHT", headerCol, "BOTTOMRIGHT", -hInset, -extendBelow)
    tex:Show()
end

function GearTab.layoutSelectionOutline(headerCol, show)
    local o = headerCol and headerCol.selectionOutline
    if not o then return end
    if not show then
        for _, tex in pairs(o) do tex:Hide() end
        return
    end
    local hInset = GearTab.getUpgradeHighlightHorizontalInset()
    local extendBelow = GearTab.getUpgradeHighlightBelowHeaderExtent()
    local outInset = math.max(0, hInset - SELECTION_OUTLINE_WIDTH)
    local outExtend = extendBelow + SELECTION_OUTLINE_WIDTH
    local w = SELECTION_OUTLINE_WIDTH

    o.top:ClearAllPoints()
    o.top:SetPoint("TOPLEFT", headerCol.header, "TOPLEFT", outInset, 1 + SELECTION_OUTLINE_WIDTH)
    o.top:SetPoint("TOPRIGHT", headerCol, "TOPRIGHT", -outInset, 1 + SELECTION_OUTLINE_WIDTH)
    o.top:SetHeight(w)
    o.top:Show()

    o.bottom:ClearAllPoints()
    o.bottom:SetPoint("BOTTOMLEFT", headerCol, "BOTTOMLEFT", outInset, -outExtend)
    o.bottom:SetPoint("BOTTOMRIGHT", headerCol, "BOTTOMRIGHT", -outInset, -outExtend)
    o.bottom:SetHeight(w)
    o.bottom:Show()

    o.left:ClearAllPoints()
    o.left:SetPoint("TOPLEFT", headerCol.header, "TOPLEFT", outInset, 1)
    o.left:SetPoint("BOTTOMLEFT", headerCol, "BOTTOMLEFT", outInset, -outExtend)
    o.left:SetWidth(w)
    o.left:Show()

    o.right:ClearAllPoints()
    o.right:SetPoint("TOPRIGHT", headerCol, "TOPRIGHT", -outInset, 1)
    o.right:SetPoint("BOTTOMRIGHT", headerCol, "BOTTOMRIGHT", -outInset, -outExtend)
    o.right:SetWidth(w)
    o.right:Show()
end

function GearTab.layoutCompareHover(headerCol, show)
    if not headerCol or not headerCol.compareHover then return end
    local tex = headerCol.compareHover
    if not show or not droppedItemLink then
        tex:Hide()
        return
    end
    local hInset = GearTab.getUpgradeHighlightHorizontalInset()
    local extendBelow = GearTab.getUpgradeHighlightBelowHeaderExtent()
    tex:SetColorTexture(
        COMPARE_HOVER_COLOR[1],
        COMPARE_HOVER_COLOR[2],
        COMPARE_HOVER_COLOR[3],
        COMPARE_HOVER_COLOR[4])
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", headerCol.header, "TOPLEFT", hInset, 1)
    tex:SetPoint("BOTTOMRIGHT", headerCol, "BOTTOMRIGHT", -hInset, -extendBelow)
    tex:Show()
end

--- True if this entry can never equip the current dropped item (for graying).
function GearTab.CanNeverUseCurrentItem(entry)
    if not droppedItemLink then return false end
    if IU and IU.CanNeverUseItem then
        return IU.CanNeverUseItem(entry.classFile, droppedItemLink)
    end
    return false
end

--- Brief fit message for column: nil or "", or "Can not wear plate" / "10 levels ahead" etc.
--- Returns message, color ("red" | "orange" | nil).
function GearTab.GetFitMessage(entry)
    if not droppedItemLink then return nil, nil end
    local reqLevel, armorSubclass, weaponSubclass = GearTab.GetItemUseInfo(droppedItemLink)
    if reqLevel == nil and armorSubclass == nil and weaponSubclass == nil then
        return nil, nil
    end
    reqLevel = reqLevel or 0
    local classFile = (entry.classFile or ""):upper()
    local charLevel = math.floor(tonumber(entry.level) or 0)

    if armorSubclass and armorSubclass ~= "" then
        if not GearTab.CanClassEverUseArmor(classFile, armorSubclass) then
            return "Can not wear " .. armorSubclass:lower(), "red"
        end
    end
    if weaponSubclass and weaponSubclass ~= "" then
        if not GearTab.CanClassEverUseWeapon(classFile, weaponSubclass) then
            return "Can not use " .. weaponSubclass:lower(), "red"
        end
    end

    local delta = charLevel - reqLevel
    if droppedItemLink and GearTab.GetFocusTierForEntry(entry) == 1 then
        return "Upgrade!", "green"
    end
    if delta > 0 then
        return delta == 1 and "1 level ahead" or (delta .. " levels ahead"), "orange"
    elseif delta < 0 then
        local absDelta = math.abs(delta)
        return absDelta == 1 and "1 level behind" or (absDelta .. " levels behind"), "orange"
    end
    return nil, nil
end

--- Resolve item to texture path for display (itemID or link).
function GearTab.GetItemTexture(itemIDOrLink)
    if not itemIDOrLink then return nil end
    if not GetItemInfo then return nil end
    local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemIDOrLink)
    return texture
end

--- Item quality from GetItemInfo (0=poor, 1=common, 2=uncommon, 3=rare, 4=epic, 5=legendary).
function GearTab.GetItemQuality(itemIDOrLink)
    if not itemIDOrLink or not GetItemInfo then return nil end
    local _, _, quality = GetItemInfo(itemIDOrLink)
    return quality
end

--- Glow color for uncommon–legendary; nil for poor/common or unknown quality.
function GearTab.GetQualityGlowColor(quality)
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

function GearTab.ApplyItemCellVisual(cell, item, gray)
    local texPath = GearTab.GetItemTexture(item)
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

    local gr, gg, gb = GearTab.GetQualityGlowColor(GearTab.GetItemQuality(item))
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
function GearTab.HandleItemCellClick(itemLinkOrID, button)
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

function GearTab.tryAcceptCursorItem()
    if not GetCursorInfo then return end
    local infoType, _, itemLink = GetCursorInfo()
    if infoType == "item" and itemLink then
        droppedItemLink = itemLink
        if ClearCursor then ClearCursor() end
        local tex = GearTab.GetItemTexture(itemLink)
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
    GearTab.tryAcceptCursorItem()
end)
dropBox:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then
        droppedItemLink = nil
        dropBoxIcon:Hide()
        if frame.RefreshGrid then frame:RefreshGrid() end
        return
    end
    GearTab.tryAcceptCursorItem()
end)
if not LEFT_PANEL_VISIBLE then
    leftPanel:Hide()
end

-- ---- Right panel: slot row headers + scrollable character columns ----
local COLUMN_HEADER_HEIGHT_GEAR = 18
local SCORE_PROVIDER_DROPDOWN_WIDTH = 200
local SCROLL_GUTTER = Theme.VerticalScrollBarGutter()
local FIXED_HEADER_ROW_HEIGHT = COLUMN_HEADER_HEIGHT_GEAR + MESSAGE_ROW_HEIGHT

function GearTab.GetPinnedHeaderHeight()
    return FIXED_HEADER_ROW_HEIGHT + GearTab.GetScoreRowHeight()
end
-- Layout dimensions from spacing + icon size
do
    dims.cellSize = GearTab.GetCellSizePx()
    local rh, cw = GearTab.GetSpacingDimensions()
    dims.rowHeight, dims.columnWidth = rh, cw
    dims.scrollableGridHeight = GearTab.GetScrollableGridHeight()
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
verticalScrollChild:SetHeight(GearTab.GetPinnedHeaderHeight() + dims.scrollableGridHeight)
verticalScrollChild:SetWidth(MIN_SCROLL_CHILD_WIDTH)
verticalScrollChild:EnableMouse(true)
verticalScroll:SetScrollChild(verticalScrollChild)

-- Spacer at top of scroll child so first row of content sits below where header will overlay
local scrollTopSpacer = CreateFrame("Frame", nil, verticalScrollChild)
scrollTopSpacer:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", 0, 0)
scrollTopSpacer:SetPoint("TOPRIGHT", verticalScrollChild, "TOPRIGHT", 0, 0)
scrollTopSpacer:SetHeight(GearTab.GetPinnedHeaderHeight())

-- Fixed header row: character names + score row pinned; scrolls horizontally with grid
local fixedHeaderRow = CreateFrame("Frame", nil, contentArea)
fixedHeaderRow:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 0, 0)
fixedHeaderRow:SetPoint("TOPRIGHT", contentArea, "TOPRIGHT", 0, 0)
fixedHeaderRow:SetHeight(GearTab.GetPinnedHeaderHeight())
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
Theme.ApplyGridLabelColumnBackground(headerCornerColumn)
local headerCornerCell = headerCornerColumn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
headerCornerCell:SetPoint("TOPLEFT", headerCornerColumn, "TOPLEFT", 0, 0)
headerCornerCell:SetWidth(SLOT_LABEL_WIDTH - 4)
headerCornerCell:SetHeight(FIXED_HEADER_ROW_HEIGHT)
headerCornerCell:SetJustifyH("LEFT")
headerCornerCell:SetText("")

local itemCheckBtn = CreateFrame("Button", nil, headerCornerColumn)
Theme.SkinButton(itemCheckBtn)
local itemCheckBtnText = itemCheckBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
itemCheckBtnText:SetPoint("LEFT", itemCheckBtn, "LEFT", 4, 0)
itemCheckBtnText:SetPoint("RIGHT", itemCheckBtn, "RIGHT", -4, 0)
itemCheckBtnText:SetJustifyH("CENTER")
itemCheckBtnText:SetWordWrap(false)
itemCheckBtnText:SetTextColor(1, 1, 1, 1)
itemCheckBtnText:SetText("Item Check")

local itemCheckModeActive = false
local itemCheckPanel

function GearTab.updateItemCheckButtonLabel()
    if droppedItemLink then
        itemCheckBtnText:SetText("Clear selection")
    elseif itemCheckModeActive then
        itemCheckBtnText:SetText("Cancel")
    else
        itemCheckBtnText:SetText("Item Check")
    end
end

local headerHorizontalScroll = CreateFrame("ScrollFrame", "AltArmyTBC_GearHeaderHorizontalScroll", fixedHeaderRow)
headerHorizontalScroll:SetPoint("TOPLEFT", headerCornerColumn, "TOPRIGHT", 0, 0)
headerHorizontalScroll:SetPoint("BOTTOMRIGHT", fixedHeaderRow, "BOTTOMRIGHT", 0, 0)
headerHorizontalScroll:EnableMouse(true)
local headerGridContainer = CreateFrame("Frame", nil, headerHorizontalScroll)
headerGridContainer:SetPoint("TOPLEFT", headerHorizontalScroll, "TOPLEFT", 0, 0)
headerGridContainer:SetHeight(GearTab.GetPinnedHeaderHeight())
headerHorizontalScroll:SetScrollChild(headerGridContainer)

-- Vertical scroll bar: custom (no template) so it doesn't conflict with horizontal; both bars under our control
local verticalScrollBar = CreateFrame("Slider", "AltArmyTBC_GearVerticalScrollBar", rightPanel)
verticalScrollBar:SetMinMaxValues(0, 0)
verticalScrollBar:SetValueStep(dims.rowHeight)
verticalScrollBar:SetValue(0)
verticalScrollBar:EnableMouse(true)
Theme.AnchorVerticalScrollBar(verticalScrollBar, tabContentPanel, contentArea)
local scrollTopFade
verticalScrollBar:SetScript("OnValueChanged", function(_, value)
    verticalScroll:SetVerticalScroll(value)
    if scrollTopFade then scrollTopFade:Update() end
end)

scrollTopFade = Theme.CreatePinnedHeaderScrollFade({
    headerFrame = fixedHeaderRow,
    scrollFrame = verticalScroll,
    scrollBar = verticalScrollBar,
})

-- Mouse wheel: scroll the gear list when hovering over the scroll area (frame or scroll child)
function GearTab.OnGearScrollWheel(_, delta)
    if not verticalScrollBar then return end
    local minVal, maxVal = verticalScrollBar:GetMinMaxValues()
    local current = verticalScrollBar:GetValue()
    -- delta: 1 = scroll up (see higher content), -1 = scroll down (see lower content)
    local newVal = current - delta * dims.rowHeight * 2
    newVal = math.max(minVal, math.min(maxVal, newVal))
    verticalScrollBar:SetValue(newVal)
    verticalScroll:SetVerticalScroll(newVal)
    if scrollTopFade then scrollTopFade:Update() end
end
verticalScroll:SetScript("OnMouseWheel", GearTab.OnGearScrollWheel)
verticalScrollChild:SetScript("OnMouseWheel", GearTab.OnGearScrollWheel)

-- Row headers (slot names) — below pinned header; scroll with equipment rows
local slotHeaderContainer = CreateFrame("Frame", nil, verticalScrollChild)
slotHeaderContainer:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", 0, -GearTab.GetPinnedHeaderHeight())
slotHeaderContainer:SetHeight(dims.scrollableGridHeight)
slotHeaderContainer:SetWidth(SLOT_LABEL_WIDTH)
Theme.ApplyGridLabelColumnBackground(slotHeaderContainer)

-- Score row: pinned in header corner (provider selector + sort-direction button)
local scoreSortBtn = CreateFrame("Button", nil, headerCornerColumn)
scoreSortBtn:SetPoint("BOTTOMRIGHT", headerCornerColumn, "BOTTOMRIGHT", 0, SCORE_ROW_HEADER_BOTTOM_INSET)
scoreSortBtn:SetSize(GearTab.GetScoreSortBtnSize(), GearTab.GetScoreSortBtnSize())
Theme.SkinButton(scoreSortBtn)
local scoreSortBtnText = scoreSortBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
scoreSortBtnText:SetPoint("CENTER", scoreSortBtn, "CENTER", 0, 0)
scoreSortBtnText:SetJustifyH("CENTER")
scoreSortBtnText:SetTextColor(1, 0.82, 0, 1)

function GearTab.UpdateScoreSortButton()
    local descending = GearTab.GetGearSettings().scoreSortDescending ~= false
    scoreSortBtnText:SetText(descending and ">" or "<")
end

scoreSortBtn:SetScript("OnClick", function()
    local s = GearTab.GetGearSettings()
    s.scoreSortDescending = not s.scoreSortDescending
    GearTab.UpdateScoreSortButton()
    if frame.RefreshGrid then frame:RefreshGrid() end
end)
GearTab.UpdateScoreSortButton()

function GearTab.LayoutItemCheckButton()
    if not itemCheckBtn or not scoreSortBtn or not headerCornerColumn then return end
    itemCheckBtn:ClearAllPoints()
    itemCheckBtn:SetPoint("TOPLEFT", headerCornerColumn, "TOPLEFT", 0, ITEM_CHECK_BTN_TOP_OFFSET)
    itemCheckBtn:SetPoint("TOPRIGHT", headerCornerColumn, "TOPRIGHT", 0, ITEM_CHECK_BTN_TOP_OFFSET)
    itemCheckBtn:SetPoint("BOTTOM", scoreSortBtn, "TOP", 0, -ITEM_CHECK_BTN_BOTTOM_GAP)
end
GearTab.LayoutItemCheckButton()

local scoreProviderStaticLabel = headerCornerColumn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
scoreProviderStaticLabel:SetPoint("BOTTOMLEFT", headerCornerColumn, "BOTTOMLEFT", 4, SCORE_ROW_HEADER_BOTTOM_INSET)
scoreProviderStaticLabel:SetPoint("BOTTOMRIGHT", scoreSortBtn, "BOTTOMLEFT", -SCORE_SORT_BTN_GAP, 0)
scoreProviderStaticLabel:SetHeight(GearTab.GetScoreRowContentHeight())
scoreProviderStaticLabel:SetJustifyH("LEFT")
scoreProviderStaticLabel:SetJustifyV("MIDDLE")
scoreProviderStaticLabel:SetText("Level")

local scoreProviderBtn = CreateFrame("Button", nil, headerCornerColumn)
scoreProviderBtn:SetPoint("BOTTOMLEFT", headerCornerColumn, "BOTTOMLEFT", 0, SCORE_ROW_HEADER_BOTTOM_INSET)
scoreProviderBtn:SetPoint("BOTTOMRIGHT", scoreSortBtn, "BOTTOMLEFT", -SCORE_SORT_BTN_GAP, 0)
scoreProviderBtn:SetHeight(GearTab.GetScoreRowContentHeight())
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

function GearTab.UpdateScoreProviderControl()
    local providers = GearTab.GetAvailableScoreProviders()
    local selectedId = GearTab.GetSelectedScoreProvider()
    local label = GearTab.GetScoreProviderLabel(selectedId)
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

function GearTab.UpdateScoreProviderDropdownSelection()
    local selectedId = GearTab.GetSelectedScoreProvider()
    for i = 1, #scoreProviderDropdownButtons do
        local b = scoreProviderDropdownButtons[i]
        if b.SetDropdownSelected then
            b:SetDropdownSelected(b.providerId == selectedId)
        end
    end
end

function GearTab.RebuildScoreProviderDropdown()
    for i = 1, #scoreProviderDropdownButtons do
        scoreProviderDropdownButtons[i]:Hide()
        scoreProviderDropdownButtons[i]:SetParent(nil)
    end
    wipe(scoreProviderDropdownButtons)
    local providers = GearTab.GetAvailableScoreProviders()
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
            selected = provider.id == GearTab.GetSelectedScoreProvider(),
            onClick = function(self)
                GearTab.GetGearSettings().scoreProvider = self.providerId
                GearTab.UpdateScoreProviderDropdownSelection()
                scoreProviderDropdown:Hide()
                GearTab.UpdateScoreProviderControl()
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
        GearTab.UpdateScoreProviderDropdownSelection()
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
horizontalScroll:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", SLOT_LABEL_WIDTH, -GearTab.GetPinnedHeaderHeight())
horizontalScroll:SetPoint("TOPRIGHT", verticalScrollChild, "TOPRIGHT", 0, -GearTab.GetPinnedHeaderHeight())
horizontalScroll:SetHeight(dims.scrollableGridHeight)
horizontalScroll:EnableMouse(true)

-- Grid area: scroll child of horizontalScroll; engine scrolls via SetHorizontalScroll (like vertical)
local gridContainer = CreateFrame("Frame", nil, horizontalScroll)
gridContainer:SetPoint("TOPLEFT", horizontalScroll, "TOPLEFT", 0, 0)
gridContainer:SetHeight(dims.scrollableGridHeight)
horizontalScroll:SetScrollChild(gridContainer)

-- Header column pool: name + message per character, in fixed header row (scrolls horizontally)
local headerColumnPool = {}
function GearTab.GetHeaderColumnFrame(index)
    if not headerColumnPool[index] then
        local col = CreateFrame("Frame", nil, headerGridContainer)
        col:SetSize(dims.columnWidth, GearTab.GetPinnedHeaderHeight())
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
        col.scoreText:SetHeight(GearTab.GetScoreRowContentHeight())
        col.scoreText:SetJustifyH("CENTER")
        col.scoreText:SetJustifyV("MIDDLE")
        col.scoreHover = CreateFrame("Frame", nil, col)
        col.scoreHover:SetPoint("BOTTOMLEFT", col, "BOTTOMLEFT", 0, SCORE_ROW_HEADER_BOTTOM_INSET)
        col.scoreHover:SetPoint("BOTTOMRIGHT", col, "BOTTOMRIGHT", 0, SCORE_ROW_HEADER_BOTTOM_INSET)
        col.scoreHover:SetHeight(GearTab.GetScoreRowContentHeight())
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
        local upgradeHighlight = col:CreateTexture(nil, "BACKGROUND")
        upgradeHighlight:SetColorTexture(0.2, 0.9, 0.2, 0.35)
        upgradeHighlight:Hide()
        col.upgradeHighlight = upgradeHighlight
        local compareHover = col:CreateTexture(nil, "BACKGROUND", nil, 1)
        compareHover:SetColorTexture(
            COMPARE_HOVER_COLOR[1],
            COMPARE_HOVER_COLOR[2],
            COMPARE_HOVER_COLOR[3],
            COMPARE_HOVER_COLOR[4])
        compareHover:Hide()
        col.compareHover = compareHover
        col.selectionOutline = {}
        local function makeOutlineEdge(key)
            local tex = col:CreateTexture(nil, "OVERLAY", nil, 7)
            tex:SetColorTexture(1, 1, 1, 0.95)
            tex:Hide()
            col.selectionOutline[key] = tex
        end
        makeOutlineEdge("top")
        makeOutlineEdge("bottom")
        makeOutlineEdge("left")
        makeOutlineEdge("right")
        col:SetScript("OnEnter", function(self)
            if droppedItemLink then
                hoveredCompareKey = self.compareKey
                GearTab.layoutCompareHover(self, true)
            end
            if self.tooltipText and self.tooltipText ~= "" and GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(self.tooltipText, 1, 1, 1)
                if droppedItemLink then
                    GameTooltip:AddLine("Click to compare", 0.7, 0.7, 0.7)
                end
                GameTooltip:Show()
            elseif droppedItemLink and GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                GameTooltip:ClearLines()
                GameTooltip:AddLine("Click to compare", 1, 0.82, 0)
                GameTooltip:Show()
            end
        end)
        col:SetScript("OnLeave", function(self)
            if hoveredCompareKey == self.compareKey then
                hoveredCompareKey = nil
            end
            GearTab.layoutCompareHover(self, false)
            if GameTooltip then GameTooltip:Hide() end
        end)
        col:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" or not droppedItemLink then return end
            local key = self.compareKey
            if not key then return end
            if selectedCompareKey == key then
                GearTab.ClearCompareSelection()
            else
                selectedCompareKey = key
            end
            if frame.RefreshGrid then frame:RefreshGrid() end
        end)
        headerColumnPool[index] = col
    end
    return headerColumnPool[index]
end

-- Pool of character column frames (cells only; reused)
local columnPool = {}

-- Horizontal scroll bar: create after horizontalScroll/gridContainer exist so OnValueChanged sees them
local scrollGridLeftFade
local scrollHeaderLeftFade
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
        if scrollGridLeftFade then scrollGridLeftFade:Update() end
        if scrollHeaderLeftFade then scrollHeaderLeftFade:Update() end
    end,
    isShown = function()
        return frame:IsShown()
    end,
})
local horizontalScrollBar = horizontalScrollApi.bar
horizontalScrollBar:SetPoint("BOTTOMLEFT", tabContentInner, "BOTTOMLEFT", PAD, -4)
horizontalScrollBar:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", 0, -4)

scrollGridLeftFade = Theme.CreatePinnedHorizontalScrollFade({
    anchorScrollFrame = horizontalScroll,
    scrollFrame = horizontalScroll,
    scrollBar = horizontalScrollBar,
})
scrollHeaderLeftFade = Theme.CreatePinnedHorizontalScrollFade({
    anchorScrollFrame = headerHorizontalScroll,
    scrollFrame = horizontalScroll,
    scrollBar = horizontalScrollBar,
})

-- Item Check inline mode: replaces grid body with drop UI while keeping the pinned header.
itemCheckPanel = CreateFrame("Frame", nil, contentArea)
itemCheckPanel:SetPoint("TOPLEFT", fixedHeaderRow, "BOTTOMLEFT", 0, 0)
itemCheckPanel:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", 0, 0)
itemCheckPanel:SetFrameLevel(contentArea:GetFrameLevel() + 10)
itemCheckPanel:EnableMouse(true)
itemCheckPanel:Hide()

local ITEM_CHECK_STACK_WIDTH = 420
local ITEM_CHECK_STACK_HEIGHT = 180

local itemCheckStack = CreateFrame("Frame", nil, itemCheckPanel)
itemCheckStack:SetSize(ITEM_CHECK_STACK_WIDTH, ITEM_CHECK_STACK_HEIGHT)
itemCheckStack:SetPoint("CENTER", itemCheckPanel, "CENTER", 0, 0)

local itemCheckMessage = itemCheckStack:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
itemCheckMessage:SetPoint("TOP", itemCheckStack, "TOP", 0, 0)
itemCheckMessage:SetWidth(ITEM_CHECK_STACK_WIDTH)
itemCheckMessage:SetJustifyH("CENTER")
itemCheckMessage:SetWordWrap(true)
itemCheckMessage:SetText(
    "Drop an item to see which characters can equip it\nand who it would be an upgrade for.")
if Theme.SetLabelColor then
    Theme.SetLabelColor(itemCheckMessage)
end

local itemCheckDrop = CreateFrame("Frame", nil, itemCheckStack, "BackdropTemplate")
itemCheckDrop:SetSize(44, 44)
itemCheckDrop:SetPoint("TOP", itemCheckMessage, "BOTTOM", 0, -14)
itemCheckDrop:SetPoint("LEFT", itemCheckStack, "LEFT", (ITEM_CHECK_STACK_WIDTH - 44) / 2, 0)
itemCheckDrop:EnableMouse(true)

local itemCheckDropGlow = itemCheckDrop:CreateTexture(nil, "BACKGROUND")
itemCheckDropGlow:SetPoint("TOPLEFT", itemCheckDrop, "TOPLEFT", -5, 5)
itemCheckDropGlow:SetPoint("BOTTOMRIGHT", itemCheckDrop, "BOTTOMRIGHT", 5, -5)
if Theme.ApplySettingsGlow then
    Theme.ApplySettingsGlow(itemCheckDropGlow)
end
itemCheckDropGlow:Hide()

Theme.ApplyBackdrop(itemCheckDrop, "section")

local itemCheckDropHover = itemCheckDrop:CreateTexture(nil, "BACKGROUND")
itemCheckDropHover:SetAllPoints(true)
itemCheckDropHover:SetTexture(Theme.HOVER_TINT_BG or "Interface\\Tooltips\\UI-Tooltip-Background")
itemCheckDropHover:SetVertexColor(0.82, 0.68, 0.22, 0)

function GearTab.setItemCheckDropHighlighted(on)
    if on then
        itemCheckDropGlow:Show()
        itemCheckDropHover:SetVertexColor(0.82, 0.68, 0.22, 0.45)
        local colors = Theme.COLORS
        if colors and itemCheckDrop.SetBackdropColor then
            local bg = colors.btnHoverBg
            local border = colors.btnActiveBorder
            itemCheckDrop:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
            itemCheckDrop:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
        end
    else
        itemCheckDropGlow:Hide()
        itemCheckDropHover:SetVertexColor(0.82, 0.68, 0.22, 0)
        Theme.ApplyBackdrop(itemCheckDrop, "section")
    end
end

itemCheckDrop:SetScript("OnEnter", function()
    GearTab.setItemCheckDropHighlighted(true)
end)
itemCheckDrop:SetScript("OnLeave", function()
    GearTab.setItemCheckDropHighlighted(false)
end)

local itemCheckDropIcon = itemCheckDrop:CreateTexture(nil, "OVERLAY")
itemCheckDropIcon:SetSize(32, 32)
itemCheckDropIcon:SetPoint("CENTER", itemCheckDrop, "CENTER", 0, 0)
itemCheckDropIcon:Hide()

local itemCheckCancel = CreateFrame("Button", nil, itemCheckStack)
itemCheckCancel:SetSize(72, SETTINGS_ROW_HEIGHT)
itemCheckCancel:SetPoint("TOP", itemCheckDrop, "BOTTOM", 0, -14)
itemCheckCancel:SetPoint("LEFT", itemCheckStack, "LEFT", (ITEM_CHECK_STACK_WIDTH - 72) / 2, 0)
Theme.SkinButton(itemCheckCancel)

local itemCheckCancelText = itemCheckCancel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
itemCheckCancelText:SetPoint("CENTER", itemCheckCancel, "CENTER", 0, 0)
itemCheckCancelText:SetTextColor(1, 1, 1, 1)
itemCheckCancelText:SetText("Cancel")

local itemCheckError = itemCheckStack:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
itemCheckError:SetPoint("TOP", itemCheckCancel, "BOTTOM", 0, -10)
itemCheckError:SetWidth(ITEM_CHECK_STACK_WIDTH)
itemCheckError:SetJustifyH("CENTER")
itemCheckError:SetWordWrap(true)
itemCheckError:SetTextColor(1, 0.4, 0.3, 1)
itemCheckError:Hide()

function GearTab.clearItemCheckError()
    itemCheckError:SetText("")
    itemCheckError:Hide()
end

function GearTab.showItemCheckError(msg)
    itemCheckError:SetText(msg or "")
    itemCheckError:Show()
end

function GearTab.resetItemCheckDrop()
    itemCheckDropIcon:Hide()
    GearTab.clearItemCheckError()
end

function GearTab.getCursorItemLink()
    if not GetCursorInfo then return nil end
    local infoType, _, itemLink = GetCursorInfo()
    if infoType == "item" and itemLink then return itemLink end
    return nil
end

function GearTab.applyItemCheckDrop(itemLink)
    GearTab.ClearCompareSelection()
    droppedItemLink = itemLink
    GearTab.exitItemCheckMode()
    GearTab.updateItemCheckButtonLabel()
    if frame.RefreshGrid then frame:RefreshGrid() end
end

function GearTab.tryAcceptItemCheckDrop()
    local itemLink = GearTab.getCursorItemLink()
    if not itemLink then return false end

    local ok, errMsg = true, nil
    if IU and IU.ValidateItemCheckDrop then
        ok, errMsg = IU.ValidateItemCheckDrop(itemLink)
    end
    if not ok then
        itemCheckDropIcon:Hide()
        GearTab.showItemCheckError(errMsg)
        return false
    end

    if ClearCursor then ClearCursor() end
    GearTab.applyItemCheckDrop(itemLink)
    return true
end

itemCheckDrop:SetScript("OnReceiveDrag", GearTab.tryAcceptItemCheckDrop)
itemCheckDrop:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then
        GearTab.resetItemCheckDrop()
        return
    end
    GearTab.tryAcceptItemCheckDrop()
end)

itemCheckCancel:SetScript("OnClick", function()
    GearTab.exitItemCheckMode()
end)

-- Character comparison panel (split view below focused slot grid)
local comparePanel = CreateFrame("Frame", nil, verticalScrollChild)
comparePanel:Hide()
Theme.ApplyGridLabelColumnBackground(comparePanel)

local compareTitle = comparePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
compareTitle:SetPoint("TOPLEFT", comparePanel, "TOPLEFT", COMPARE_PANEL_PAD, -COMPARE_PANEL_PAD)
compareTitle:SetPoint("TOPRIGHT", comparePanel, "TOPRIGHT", -COMPARE_PANEL_PAD, -COMPARE_PANEL_PAD)
compareTitle:SetHeight(COMPARE_TITLE_HEIGHT)
compareTitle:SetJustifyH("LEFT")
compareTitle:SetWordWrap(true)

local compareSummary = comparePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
compareSummary:SetPoint("TOPLEFT", compareTitle, "BOTTOMLEFT", 0, -4)
compareSummary:SetPoint("TOPRIGHT", compareTitle, "BOTTOMRIGHT", 0, -4)
compareSummary:SetHeight(COMPARE_ROW_HEIGHT)
compareSummary:SetJustifyH("LEFT")

local compareAlgoBtn = CreateFrame("Button", nil, comparePanel)
compareAlgoBtn:SetPoint("TOPLEFT", compareSummary, "BOTTOMLEFT", 0, -6)
compareAlgoBtn:SetSize(COMPARE_ALGO_DROPDOWN_WIDTH, COMPARE_DROPDOWN_ROW - 4)
compareAlgoBtn:Hide()
Theme.SkinButton(compareAlgoBtn)
local compareAlgoBtnText = compareAlgoBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
compareAlgoBtnText:SetPoint("LEFT", compareAlgoBtn, "LEFT", 6, 0)
compareAlgoBtnText:SetPoint("RIGHT", compareAlgoBtn, "RIGHT", -2, 0)
compareAlgoBtnText:SetJustifyH("LEFT")

local compareAlgoDropdown = CreateFrame("Frame", nil, comparePanel, "BackdropTemplate")
compareAlgoDropdown:SetPoint("TOPLEFT", compareAlgoBtn, "BOTTOMLEFT", 0, -2)
compareAlgoDropdown:SetWidth(COMPARE_ALGO_DROPDOWN_WIDTH)
compareAlgoDropdown:SetFrameLevel(comparePanel:GetFrameLevel() + 100)
compareAlgoDropdown:Hide()
Theme.ApplyBackdrop(compareAlgoDropdown, "section")
local compareAlgoDropdownButtons = {}

local compareStatContainer = CreateFrame("Frame", nil, comparePanel)
compareStatContainer:SetPoint("TOPLEFT", compareAlgoBtn, "BOTTOMLEFT", 0, -4)
compareStatContainer:SetPoint("BOTTOMRIGHT", comparePanel, "BOTTOMRIGHT", -COMPARE_PANEL_PAD, COMPARE_PANEL_PAD)
local compareStatRows = {}

function GearTab.HideCompareStatRows()
    for i = 1, #compareStatRows do
        compareStatRows[i]:Hide()
    end
end

function GearTab.GetCompareStatRow(index)
    if not compareStatRows[index] then
        local row = compareStatContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row:SetPoint("LEFT", compareStatContainer, "LEFT", 0, 0)
        row:SetPoint("RIGHT", compareStatContainer, "RIGHT", 0, 0)
        row:SetHeight(COMPARE_ROW_HEIGHT)
        row:SetJustifyH("LEFT")
        compareStatRows[index] = row
    end
    return compareStatRows[index]
end

function GearTab.FormatCompareNumber(n)
    n = tonumber(n) or 0
    if math.floor(n) == n then return tostring(n) end
    return string.format("%.1f", n)
end

function GearTab.FormatCompareDelta(n)
    local s = GearTab.FormatCompareNumber(n)
    if n > 0 then return "+" .. s end
    return s
end

function GearTab.UpdateCompareTechniqueDropdownSelection()
    local selectedId = GearTab.GetSessionCompareTechnique()
    for i = 1, #compareAlgoDropdownButtons do
        local b = compareAlgoDropdownButtons[i]
        if b and b.techniqueId then
            b:SetDropdownSelected(b.techniqueId == selectedId)
        end
    end
end

function GearTab.RebuildCompareTechniqueDropdown()
    for i = 1, #compareAlgoDropdownButtons do
        compareAlgoDropdownButtons[i]:Hide()
        compareAlgoDropdownButtons[i]:SetParent(nil)
    end
    wipe(compareAlgoDropdownButtons)
    if not GC or not GC.GetAvailableComparisonTechniques then return end
    local techniques = GC.GetAvailableComparisonTechniques()
    if #techniques <= 1 then
        compareAlgoDropdown:Hide()
        return
    end
    compareAlgoDropdown:SetHeight(#techniques * SETTINGS_ROW_HEIGHT + 4)
    for idx, provider in ipairs(techniques) do
        local b = Theme.CreateDropdownMenuItem(compareAlgoDropdown, {
            index = idx,
            text = GU.GetProviderDisplayLabel(provider),
            selected = provider.id == GearTab.GetSessionCompareTechnique(),
            onClick = function(self)
                sessionCompareTechnique = self.techniqueId
                compareAlgoDropdown:Hide()
                if frame.RefreshGrid then frame:RefreshGrid() end
            end,
        })
        b.techniqueId = provider.id
        compareAlgoDropdownButtons[idx] = b
    end
end

compareAlgoBtn:SetScript("OnClick", function()
    local show = not compareAlgoDropdown:IsShown()
    if show then
        GearTab.UpdateCompareTechniqueDropdownSelection()
    end
    compareAlgoDropdown:SetShown(show)
end)

function GearTab.LayoutScrollArea()
    local gridH = dims.scrollableGridHeight or GearTab.GetScrollableGridHeight()
    if horizontalScroll then
        horizontalScroll:SetHeight(gridH)
    end
    if slotHeaderContainer then
        slotHeaderContainer:ClearAllPoints()
        slotHeaderContainer:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", 0, -GearTab.GetPinnedHeaderHeight())
        slotHeaderContainer:SetHeight(gridH)
        slotHeaderContainer:SetWidth(SLOT_LABEL_WIDTH)
    end
    local compareH = comparePanelHeight or 0
    if comparePanel then
        if compareH > 0 and selectedCompareKey and droppedItemLink then
            comparePanel:SetHeight(compareH)
            comparePanel:ClearAllPoints()
            comparePanel:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", 0,
                -(GearTab.GetPinnedHeaderHeight() + gridH))
            comparePanel:SetPoint("TOPRIGHT", verticalScrollChild, "TOPRIGHT", 0,
                -(GearTab.GetPinnedHeaderHeight() + gridH))
            comparePanel:Show()
            if compareStatContainer then
                compareStatContainer:ClearAllPoints()
                if compareAlgoBtn:IsShown() then
                    compareStatContainer:SetPoint("TOPLEFT", compareAlgoBtn, "BOTTOMLEFT", 0, -4)
                else
                    compareStatContainer:SetPoint("TOPLEFT", compareSummary, "BOTTOMLEFT", 0, -8)
                end
                compareStatContainer:SetPoint("BOTTOMRIGHT", comparePanel, "BOTTOMRIGHT",
                    -COMPARE_PANEL_PAD, COMPARE_PANEL_PAD)
            end
        else
            comparePanel:Hide()
        end
    end
    if verticalScrollChild then
        verticalScrollChild:SetHeight(GearTab.GetPinnedHeaderHeight() + gridH + compareH)
    end
end

function GearTab.UpdateComparePanel(list)
    GearTab.HideCompareStatRows()
    comparePanelHeight = 0
    if not droppedItemLink or not selectedCompareKey or not GC then
        if compareAlgoBtn then compareAlgoBtn:Hide() end
        return
    end
    local entry = GearTab.GetSelectedCompareEntry(list)
    if not entry then
        GearTab.ClearCompareSelection()
        return
    end
    local charData = DS and DS.GetCharacter and DS:GetCharacter(entry.name, entry.realm)
    if not charData then return end

    local technique = GearTab.GetSessionCompareTechnique()
    local equippedLink = GC.GetEquippedCompareItem(charData, droppedItemLink, { technique = technique })
    local comparison = GC.BuildComparison(droppedItemLink, equippedLink, technique, charData)
    if not comparison then return end

    compareTitle:SetText(string.format(
        "Comparing %s with %s",
        comparison.focusedName or "?",
        comparison.equippedName or "(empty)"))

    local summary = comparison.summary or {}
    compareSummary:SetText(string.format(
        "Total: %s vs %s (%s)",
        GearTab.FormatCompareNumber(summary.newTotal),
        GearTab.FormatCompareNumber(summary.oldTotal),
        GearTab.FormatCompareDelta(summary.delta or 0)))
    local sr, sg, sb = 0.9, 0.9, 0.9
    if (summary.delta or 0) > 0 then
        sr, sg, sb = 0.2, 1, 0.2
    elseif (summary.delta or 0) < 0 then
        sr, sg, sb = 1, 0.4, 0.3
    end
    compareSummary:SetTextColor(sr, sg, sb, 1)

    local techniques = GC.GetAvailableComparisonTechniques()
    if #techniques > 1 then
        GearTab.RebuildCompareTechniqueDropdown()
        compareAlgoBtn:Show()
        local provider = GU.GetProvider(GU.GetEffectiveTechnique(technique))
        compareAlgoBtnText:SetText(provider and GU.GetProviderDisplayLabel(provider) or technique)
    else
        compareAlgoBtn:Hide()
        compareAlgoDropdown:Hide()
    end

    local rowIndex = 0
    local sections = comparison.sections or {}
    for s = 1, #sections do
        local section = sections[s]
        rowIndex = rowIndex + 1
        local sectionRow = GearTab.GetCompareStatRow(rowIndex)
        sectionRow:SetText(section.title or "")
        sectionRow:SetTextColor(1, 0.82, 0, 1)
        sectionRow:ClearAllPoints()
        if rowIndex == 1 then
            sectionRow:SetPoint("TOPLEFT", compareStatContainer, "TOPLEFT", 0, 0)
            sectionRow:SetPoint("TOPRIGHT", compareStatContainer, "TOPRIGHT", 0, 0)
        else
            local prev = compareStatRows[rowIndex - 1]
            sectionRow:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -COMPARE_SECTION_GAP)
            sectionRow:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -COMPARE_SECTION_GAP)
        end
        sectionRow:Show()

        local rows = section.rows or {}
        for r = 1, #rows do
            rowIndex = rowIndex + 1
            local data = rows[r]
            local line = GearTab.GetCompareStatRow(rowIndex)
            local delta = data.delta or 0
            local deltaText = GearTab.FormatCompareDelta(delta)
            line:SetText(string.format(
                "%s:  %s / %s  (%s)",
                data.label or "?",
                GearTab.FormatCompareNumber(data.newValue),
                GearTab.FormatCompareNumber(data.oldValue),
                deltaText))
            local dr, dg, db = 0.85, 0.85, 0.85
            if delta > 0 then
                dr, dg, db = 0.2, 1, 0.2
            elseif delta < 0 then
                dr, dg, db = 1, 0.4, 0.3
            end
            line:SetTextColor(dr, dg, db, 1)
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", compareStatRows[rowIndex - 1], "BOTTOMLEFT", 8, -2)
            line:SetPoint("TOPRIGHT", compareStatRows[rowIndex - 1], "BOTTOMRIGHT", 0, -2)
            line:Show()
        end
    end

    comparePanelHeight = GearTab.EstimateComparePanelHeight(comparison, #techniques > 1)
    for i = rowIndex + 1, #compareStatRows do
        compareStatRows[i]:Hide()
    end
end

function GearTab.enterItemCheckMode()
    itemCheckModeActive = true
    GearTab.resetItemCheckDrop()
    if itemCheckPanel then itemCheckPanel:Show() end
    if comparePanel then comparePanel:Hide() end
    if compareAlgoDropdown then compareAlgoDropdown:Hide() end
    if slotHeaderContainer then slotHeaderContainer:Hide() end
    if horizontalScroll then horizontalScroll:Hide() end
    if verticalScrollBar then verticalScrollBar:Hide() end
    if horizontalScrollBar then horizontalScrollBar:Hide() end
    if verticalScroll then verticalScroll:EnableMouse(false) end
    GearTab.updateItemCheckButtonLabel()
end

function GearTab.exitItemCheckMode()
    itemCheckModeActive = false
    GearTab.resetItemCheckDrop()
    if itemCheckPanel then itemCheckPanel:Hide() end
    if slotHeaderContainer then slotHeaderContainer:Show() end
    if horizontalScroll then horizontalScroll:Show() end
    if verticalScrollBar then verticalScrollBar:Show() end
    if horizontalScrollBar then horizontalScrollBar:Show() end
    if verticalScroll then verticalScroll:EnableMouse(true) end
    GearTab.updateItemCheckButtonLabel()
end

itemCheckBtn:SetScript("OnClick", function()
    if droppedItemLink then
        droppedItemLink = nil
        GearTab.ClearCompareSelection()
        GearTab.updateItemCheckButtonLabel()
        if frame.RefreshGrid then frame:RefreshGrid() end
        return
    end
    if itemCheckModeActive then
        GearTab.exitItemCheckMode()
        return
    end
    local cursorLink = GearTab.getCursorItemLink()
    if cursorLink then
        local ok, errMsg = true, nil
        if IU and IU.ValidateItemCheckDrop then
            ok, errMsg = IU.ValidateItemCheckDrop(cursorLink)
        end
        if ok then
            if ClearCursor then ClearCursor() end
            GearTab.applyItemCheckDrop(cursorLink)
            return
        end
        GearTab.enterItemCheckMode()
        GearTab.showItemCheckError(errMsg)
        return
    end
    GearTab.enterItemCheckMode()
end)

function frame:FocusItem(link)
    if not link or link == "" then return end
    if itemCheckModeActive then GearTab.exitItemCheckMode() end
    GearTab.ClearCompareSelection()
    droppedItemLink = link
    GearTab.updateItemCheckButtonLabel()
    if self.RefreshGrid then self:RefreshGrid() end
end

function frame:ClearFocus()
    droppedItemLink = nil
    GearTab.ClearCompareSelection()
    GearTab.updateItemCheckButtonLabel()
    if self.RefreshGrid then self:RefreshGrid() end
end

function GearTab.GetColumnFrame(index)
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
                GearTab.HandleItemCellClick(target, button)
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

function GearTab.LayoutVisibleGridRows()
    if not slotLabels or not slotLabels[1] then return end
    local visible = GearTab.GetVisibleDisplaySlots()
    local slotLabelRowOffset = (dims.rowHeight - dims.cellSize) / 2
    local cellXOffset = (dims.columnWidth - dims.cellSize) / 2

    for slot = 1, NUM_EQUIPMENT_SLOTS do
        if slotLabels[slot] then
            slotLabels[slot]:SetShown(false)
        end
    end

    for row = 1, #visible do
        local slot = visible[row]
        local label = slotLabels[slot]
        label:SetShown(true)
        label:SetHeight(dims.cellSize)
        label:ClearAllPoints()
        label:SetPoint("LEFT", slotHeaderContainer, "LEFT", 0, 0)
        if row == 1 then
            label:SetPoint("TOP", slotHeaderContainer, "TOP", 0, -slotLabelRowOffset)
        else
            label:SetPoint("TOP", slotLabels[visible[row - 1]], "TOP", 0, -dims.rowHeight)
        end
    end

    for _, col in pairs(columnPool) do
        for row = 1, #visible do
            local slot = visible[row]
            local cell = col.cells[slot]
            cell:SetSize(dims.cellSize, dims.cellSize)
            cell:ClearAllPoints()
            if row == 1 then
                cell:SetPoint("TOPLEFT", col, "TOPLEFT", cellXOffset, -slotLabelRowOffset)
            else
                cell:SetPoint(
                    "TOPLEFT",
                    col.cells[visible[row - 1]],
                    "BOTTOMLEFT",
                    0,
                    -(dims.rowHeight - dims.cellSize))
            end
        end
    end
end

function GearTab.UpdateGridWithOffset()
    if not AltArmy.Characters then return end
    local list = GearTab.GetDisplayList()
    local numCols = #list

    for idx, col in pairs(columnPool) do
        if idx > numCols then col:Hide() end
    end
    for idx, col in pairs(headerColumnPool) do
        if idx > numCols then col:Hide() end
    end

    local upgradeMinDelta, upgradeMaxDelta
    local upgradeDeltaByKey = {}
    if droppedItemLink and GU and GU.GetFocusUpgradeDelta then
        local focusOpts = GU.GetOptions and GU.GetOptions() or {}
        for i = 1, numCols do
            local e = list[i]
            local charData = DS and DS.GetCharacter and DS:GetCharacter(e.name, e.realm)
            local delta = GU.GetFocusUpgradeDelta(e, charData, droppedItemLink, focusOpts) or 0
            if delta > 0 then
                local key = CharKey(e.name, e.realm)
                upgradeDeltaByKey[key] = delta
                if not upgradeMinDelta or delta < upgradeMinDelta then upgradeMinDelta = delta end
                if not upgradeMaxDelta or delta > upgradeMaxDelta then upgradeMaxDelta = delta end
            end
        end
    end

    for c = 1, numCols do
        local entry = list[c]
        local headerCol = GearTab.GetHeaderColumnFrame(c)
        headerCol:ClearAllPoints()
        headerCol:SetPoint("TOPLEFT", headerGridContainer, "TOPLEFT", (c - 1) * dims.columnWidth + PAD - 4, 0)
        headerCol:Show()

        local focusTier = GearTab.GetFocusTierForEntry(entry)
        local upgradeDelta = upgradeDeltaByKey[CharKey(entry.name, entry.realm)] or 0
        GearTab.layoutUpgradeHighlight(headerCol, focusTier == 1, upgradeDelta, upgradeMinDelta, upgradeMaxDelta)
        headerCol.compareKey = CharKey(entry.name, entry.realm)
        GearTab.layoutSelectionOutline(headerCol, selectedCompareKey == headerCol.compareKey)
        GearTab.layoutCompareHover(headerCol, droppedItemLink and hoveredCompareKey == headerCol.compareKey)

        local charData = DS and DS.GetCharacter and DS:GetCharacter(entry.name, entry.realm)
        local RF = AltArmy.RealmFilter
        local classR, classG, classB = 1, 0.82, 0
        local gray = GearTab.CanNeverUseCurrentItem(entry)
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

        local fitMsg, fitColor = GearTab.GetFitMessage(entry)
        if droppedItemLink then
            headerCol.message:SetText("")
            headerCol.message:Hide()
        elseif fitMsg and fitMsg ~= "" then
            headerCol.message:SetText(fitMsg)
            if fitColor == "red" then
                headerCol.message:SetTextColor(1, 0.3, 0.3, 1)
            elseif fitColor == "orange" then
                headerCol.message:SetTextColor(1, 0.6, 0.2, 1)
            elseif fitColor == "green" then
                headerCol.message:SetTextColor(0.2, 1, 0.2, 1)
            else
                headerCol.message:SetTextColor(0.9, 0.9, 0.9, 1)
            end
            headerCol.message:Show()
        else
            headerCol.message:SetText("")
            headerCol.message:Show()
        end

        local providerId = GearTab.GetSelectedScoreProvider()
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

        local col = GearTab.GetColumnFrame(c)
        col:ClearAllPoints()
        col:SetPoint("TOPLEFT", gridContainer, "TOPLEFT", (c - 1) * dims.columnWidth + PAD - 4, 0)
        col:Show()

        for slot = 1, NUM_EQUIPMENT_SLOTS do
            local cell = col.cells[slot]
            if not GearTab.IsDisplaySlotVisible(slot) then
                cell:Hide()
            else
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
            GearTab.ApplyItemCellVisual(cell, item, gray)
            cell:Show()
            end
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

    local list = GearTab.GetDisplayList()
    local numCols = #list
    dims.scrollableGridHeight = GearTab.GetScrollableGridHeight()
    GearTab.UpdateComparePanel(list)
    GearTab.LayoutScrollArea()
    if gridContainer then
        gridContainer:SetHeight(dims.scrollableGridHeight)
    end
    for _, col in pairs(columnPool) do
        col:SetHeight(dims.scrollableGridHeight)
    end
    GearTab.LayoutVisibleGridRows()

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
            local totalChildHeight = GearTab.GetPinnedHeaderHeight()
                + dims.scrollableGridHeight + (comparePanelHeight or 0)
            local maxVertScroll = math.max(0, totalChildHeight - viewHeight)
            local savedVert = verticalScrollBar:GetValue() or 0
            verticalScrollBar:SetMinMaxValues(0, maxVertScroll)
            verticalScrollBar:SetValueStep(dims.rowHeight)
            verticalScrollBar:SetStepsPerPage(10)
            local vertScroll = Theme.ClampScroll(savedVert, maxVertScroll)
            verticalScrollBar:SetValue(vertScroll)
            verticalScroll:SetVerticalScroll(vertScroll)
        end
        if horizontalScrollBar and horizontalScroll and gridContainer then
            local maxHorzScroll = math.max(0, gridContentWidth - gridViewWidth)
            horizontalScrollApi:SetRange(0, maxHorzScroll)
            horizontalScrollBar:SetShown(maxHorzScroll > 0)
            horizontalScrollApi:Restore(maxHorzScroll)
        end
    end

    GearTab.UpdateGridWithOffset()
    if scrollTopFade then
        scrollTopFade:Update()
    end
    if scrollGridLeftFade then
        scrollGridLeftFade:Update()
    end
    if scrollHeaderLeftFade then
        scrollHeaderLeftFade:Update()
    end
end

--- Reapply fixed layout dimensions (medium icons, normal spacing).
function GearTab.ApplySpacing()
    dims.cellSize = GearTab.GetCellSizePx()
    local rh, cw = GearTab.GetSpacingDimensions()
    dims.rowHeight, dims.columnWidth = rh, cw
    dims.scrollableGridHeight = GearTab.GetScrollableGridHeight()

    if verticalScrollChild then
        GearTab.LayoutScrollArea()
    end
    if gridContainer then
        gridContainer:SetHeight(dims.scrollableGridHeight)
    end
    if fixedHeaderRow then
        fixedHeaderRow:SetHeight(GearTab.GetPinnedHeaderHeight())
    end
    if scrollTopSpacer then
        scrollTopSpacer:SetHeight(GearTab.GetPinnedHeaderHeight())
    end
    if headerGridContainer then
        headerGridContainer:SetHeight(GearTab.GetPinnedHeaderHeight())
    end
    if slotHeaderContainer then
        slotHeaderContainer:ClearAllPoints()
        slotHeaderContainer:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", 0, -GearTab.GetPinnedHeaderHeight())
        slotHeaderContainer:SetHeight(dims.scrollableGridHeight)
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
        horizontalScroll:SetPoint(
            "TOPLEFT", verticalScrollChild, "TOPLEFT", SLOT_LABEL_WIDTH, -GearTab.GetPinnedHeaderHeight())
        horizontalScroll:SetPoint("TOPRIGHT", verticalScrollChild, "TOPRIGHT", 0, -GearTab.GetPinnedHeaderHeight())
        horizontalScroll:SetHeight(dims.scrollableGridHeight)
    end
    if verticalScrollBar then
        verticalScrollBar:SetValueStep(dims.rowHeight)
    end

    if scoreProviderStaticLabel then
        scoreProviderStaticLabel:SetHeight(GearTab.GetScoreRowContentHeight())
    end
    if scoreProviderBtn then
        scoreProviderBtn:SetHeight(GearTab.GetScoreRowContentHeight())
    end
    if scoreSortBtn then
        local btnSize = GearTab.GetScoreSortBtnSize()
        scoreSortBtn:SetSize(btnSize, btnSize)
    end
    GearTab.LayoutItemCheckButton()

    for _, col in pairs(headerColumnPool) do
        col:SetSize(dims.columnWidth, GearTab.GetPinnedHeaderHeight())
        if col.scoreText then
            col.scoreText:SetHeight(GearTab.GetScoreRowContentHeight())
        end
        if col.scoreHover then
            col.scoreHover:SetHeight(GearTab.GetScoreRowContentHeight())
        end
    end
    for _, col in pairs(columnPool) do
        col:SetSize(dims.columnWidth, dims.scrollableGridHeight)
    end

    GearTab.LayoutVisibleGridRows()
end

function GearTab.RefreshGearTabControls()
    GearTab.RebuildScoreProviderDropdown()
    GearTab.UpdateScoreProviderControl()
    GearTab.UpdateScoreSortButton()
end

-- Apply layout when tab is shown (dims initialized at file load)
frame:HookScript("OnHide", function()
    if itemCheckModeActive then
        GearTab.exitItemCheckMode()
    end
    if compareAlgoDropdown then compareAlgoDropdown:Hide() end
end)
frame:SetScript("OnShow", function()
    GearTab.ApplySpacing()
    GearTab.RefreshGearTabControls()
    if GearScoreMod and GearScoreMod.CaptureCurrentCharacterScore then
        GearScoreMod.CaptureCurrentCharacterScore()
    end
    frame:RefreshGrid()
end)

function GearTab.IsGearScoreAddonEvent(addonName)
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
        GearTab.ApplySpacing()
        GearTab.RefreshGearTabControls()
        if frame:IsShown() then
            frame:RefreshGrid()
        end
    elseif event == "ADDON_LOADED" and GearTab.IsGearScoreAddonEvent(addonName) then
        if GearScoreMod and GearScoreMod.RefreshProviders then
            GearScoreMod.RefreshProviders("addon-loaded:" .. tostring(addonName))
        end
        GearTab.RefreshGearTabControls()
        if frame:IsShown() then
            frame:RefreshGrid()
        end
    end
end)

-- ---- Gear settings panel: right 40% of frame when visible (grid 60%, both full height) ----
local GRID_SPLIT_FRACTION = 0.6  -- grid gets 60%, settings gets 40%
local settingsPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
Theme.ApplyBackdrop(settingsPanel, "section")
function GearTab.ApplySettingsPanelLayout()
    local w = frame:GetWidth()
    if w <= 0 then return end
    settingsPanel:ClearAllPoints()
    settingsPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", w * GRID_SPLIT_FRACTION + SECTION_GAP, -SECTION_INSET)
    settingsPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", w * GRID_SPLIT_FRACTION + SECTION_GAP, SECTION_INSET)
    settingsPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SECTION_INSET, -SECTION_INSET)
    settingsPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SECTION_INSET, SECTION_INSET)
end
GearTab.ApplySettingsPanelLayout()
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
        GearTab.GetGearSettings().showSelfFirst = checked
        if frame.RefreshGrid then frame:RefreshGrid() end
    end,
})
Theme.AttachSettingsHelpIcon(showSelfFirstRow, {
    title = "Pin current character",
    lines = {
        "When enabled, your current character is automatically pinned, "
            .. "causing it to show ahead of non-pinned characters.",
        'This will override the "Hide" setting.',
    },
})
local showSelfFirstCheck = showSelfFirstRow.check
showSelfFirstCheck:SetChecked(GearTab.GetGearSettings().showSelfFirst)

-- Character list: Pin/Hide (reusable component from UI/CharacterPinHideList.lua)
if AltArmy.CreateCharacterPinHideList then
    -- luacheck: push ignore 211
    local _scroll, refresh = AltArmy.CreateCharacterPinHideList(sortingContent, showSelfFirstRow, {
        gutterEdge = settingsPanel,
        getSettings = GearTab.GetGearSettings,
        getCharSetting = GearTab.GetCharSetting,
        setCharSetting = GearTab.SetCharSetting,
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
        GearTab.ApplySettingsPanelLayout()
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
        local s = GearTab.GetGearSettings()
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
        GearTab.ApplySettingsPanelLayout()
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
