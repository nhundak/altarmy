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
local ItemStats = AltArmy.ItemStats
local TruncateFontString = AltArmy.Text and AltArmy.Text.TruncateFontString
local PAD = 4
local SECTION_INSET = Theme.TAB_SECTION_INSET
local SECTION_GAP = Theme.SECTION_GAP
local GRID_SPLIT_FRACTION = 0.6 -- grid/compare stats get 60%; settings columns get 40%
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
local selectedCompareSlot = nil
local hoveredCompareKey = nil
local compareHoverRefs = {}
local sessionCompareTechnique = nil

local COMPARE_ROW_HEIGHT = 14
local COMPARE_SECTION_GAP = 6
local COMPARE_STAT_ROW_INDENT = 8
local COMPARE_WARNING_COLOR_BLOCKING = { 1, 0.4, 0.3 }
local COMPARE_WARNING_COLOR_CAUTION = { 1, 0.82, 0 }
local COMPARE_DROPDOWN_ROW = 24
local COMPARE_PANEL_PAD = 8
local COMPARE_PANEL_MIN_HEIGHT = 100
local COMPARE_ALGO_DROPDOWN_WIDTH = 220
local COMPARE_FOCUS_DROP_SIZE = 44
local COMPARE_FOCUS_TITLE_GAP = 6
local COMPARE_FOCUS_HEADER_HEIGHT = COMPARE_FOCUS_DROP_SIZE + 8
local COMPARE_ITEMS_ROW_HEIGHT = COMPARE_FOCUS_HEADER_HEIGHT
local COMPARE_OPTIONS_SECTION_HEIGHT = 72
local COMPARE_HOVER_COLOR = { 0.82, 0.68, 0.22, 0.32 }
local CLEAR_UPGRADE_RATIO = 0.5
local UPGRADE_BADGE_COLORS = {
    upgrade = { 0.2, 1, 0.2 },
    sidegrade = { 0.9, 0.78, 0.12 },
    upgradeFuture = { 1, 1, 1 },
    sidegradeFuture = { 1, 1, 1 },
    unusable = { 1, 0.45, 0.2 },
}
local UPGRADE_BADGE_TEXT = {
    upgrade = "+",
    sidegrade = "~",
    upgradeFuture = "+",
    sidegradeFuture = "~",
    unusable = "x",
}
local UPGRADE_BADGE_FONT_OBJECT = "GameFontNormalSmall"
local UPGRADE_BADGE_FONT_SCALE = 2

local function applyUpgradeBadgeFont(fontString)
    if not fontString then return end
    fontString:SetFontObject(UPGRADE_BADGE_FONT_OBJECT)
    local font, size, flags = fontString:GetFont()
    if font and size then
        fontString:SetFont(font, size * UPGRADE_BADGE_FONT_SCALE, flags)
    end
end
local SELECTED_NEUTRAL_HIGHLIGHT = { 0.82, 0.68, 0.22, 0.42 }
local FOCUS_FADE_ALPHA = 0.45
local FOCUS_GRID_HEIGHT_SLACK = 2

-- Gear settings persistence (AltArmyTBC_GearSettings)
local DEFAULT_SCORE_PROVIDER = "level"
local SLOT_LABEL_WIDTH = 120
local SCORE_SORT_BTN_GAP = 2
local SCORE_ROW_LAYOUT_TRIM = 4
local SCORE_ROW_HEADER_BOTTOM_INSET = 6
local UPGRADE_HIGHLIGHT_COLUMN_INSET = 2
local ITEM_CHECK_BTN_TOP_OFFSET = 0
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
-- CENTER→TOPRIGHT: negative x = left, negative y = down
local UPGRADE_BADGE_OFFSET_X = -(ITEM_ICON_INSET + 4)
local UPGRADE_BADGE_OFFSET_Y = -(ITEM_ICON_INSET + 4)
local UPGRADE_BADGE_SIDEGRADE_Y_EXTRA = -10

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

function GearTab.GetFocusedInventorySlots()
    if not droppedItemLink or not IU or not IU.GetInventorySlotsForItem then return {} end
    return IU.GetInventorySlotsForItem(droppedItemLink) or {}
end

function GearTab.IsMultiSlotFocus()
    return #GearTab.GetFocusedInventorySlots() > 1
end

function GearTab.MakeCompareCellKey(charKey, invSlot)
    if not charKey or not invSlot then return nil end
    return charKey .. "#" .. tostring(invSlot)
end

function GearTab.IsCompareCellSelected(charKey, invSlot)
    if not selectedCompareKey or charKey ~= selectedCompareKey then return false end
    if not selectedCompareSlot or not invSlot then return false end
    return selectedCompareSlot == invSlot
end

function GearTab.HasCompareSelection()
    return selectedCompareKey ~= nil and selectedCompareSlot ~= nil
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
    local h = visibleCount * rh + PAD
    if droppedItemLink then
        h = h + FOCUS_GRID_HEIGHT_SLACK
    end
    return h
end

function GearTab.GetSessionCompareTechnique()
    if sessionCompareTechnique then return sessionCompareTechnique end
    if GU and GU.GetOptions then return GU.GetOptions().technique or "custom" end
    return "custom"
end

function GearTab.ClearCompareSelection()
    selectedCompareKey = nil
    selectedCompareSlot = nil
    hoveredCompareKey = nil
    wipe(compareHoverRefs)
    sessionCompareTechnique = nil
end

--- Best (character, inventory slot) for auto-select after focus; nil when no in-range upgrade.
function GearTab.PickBestCompareSelection(list)
    if not list or #list == 0 or not droppedItemLink then return nil, nil end
    local slots = GearTab.GetFocusedInventorySlots()
    if #slots == 0 then return nil, nil end
    local focusOpts = GU and GU.GetOptions and GU.GetOptions() or {}
    local upgradeMaxDelta = GearTab.ComputeFocusUpgradeMaxDelta(list, slots, focusOpts)
    local bestKey, bestSlot, bestDelta = nil, nil, 0
    local inRangeUpgrade = GU and GU.FOCUS_CATEGORY
    for i = 1, #list do
        local e = list[i]
        local charData = DS and DS.GetCharacter and DS:GetCharacter(e.name, e.realm)
        for s = 1, #slots do
            local invSlot = slots[s]
            local info = GU and GU.ClassifyFocusSlot
                and GU.ClassifyFocusSlot(e, charData, droppedItemLink, invSlot, focusOpts, upgradeMaxDelta)
            if info and inRangeUpgrade
                and (info.category == inRangeUpgrade.UPGRADE_IN_RANGE
                    or info.category == inRangeUpgrade.SIDEGRADE_IN_RANGE)
                and info.delta > bestDelta then
                bestDelta = info.delta
                bestKey = CharKey(e.name, e.realm)
                bestSlot = invSlot
            end
        end
    end
    if bestKey and bestSlot then
        return bestKey, bestSlot
    end
    return nil, nil
end

function GearTab.ComputeFocusUpgradeMaxDelta(list, slots, focusOpts)
    if not list or not slots or not droppedItemLink or not GU or not GU.GetSlotCompareDelta then
        return nil
    end
    local upgradeMaxDelta
    for i = 1, #list do
        local e = list[i]
        local charData = DS and DS.GetCharacter and DS:GetCharacter(e.name, e.realm)
        for s = 1, #slots do
            local delta = GU.GetSlotCompareDelta(
                charData, droppedItemLink, slots[s], focusOpts, e) or 0
            if delta > 0 and (not upgradeMaxDelta or delta > upgradeMaxDelta) then
                upgradeMaxDelta = delta
            end
        end
    end
    return upgradeMaxDelta
end

function GearTab.FormatCompareFocusTitle()
    return "Upgrade check for"
end

function GearTab.FormatCompareFocusVsLabel()
    return "vs"
end

function GearTab.FormatCompareEmptyHintText()
    return "This isn't a clear upgrade for any of your characters."
        .. "\nClick an item above to compare anyway"
end

function GearTab.FormatCompareEmptyStateText(_itemLink)
    return GearTab.FormatCompareFocusTitle()
        .. "\n" .. GearTab.FormatCompareEmptyHintText()
end

--- First visible column after focus sort (upgrade tier, then biggest delta).
function GearTab.PickBestCompareKey(list)
    return (GearTab.PickBestCompareSelection(list))
end

function GearTab.IsFocusedItemSoulbound()
    return droppedItemLink
        and IU
        and IU.IsBindOnPickup
        and IU.IsBindOnPickup(droppedItemLink)
end

function GearTab.ApplyFocusedItem(itemLink, opts)
    opts = opts or {}
    droppedItemLink = itemLink
    hoveredCompareKey = nil
    sessionCompareTechnique = nil
    local soulbound = GearTab.IsFocusedItemSoulbound()
    if soulbound and not opts.manual then
        selectedCompareKey = nil
        selectedCompareSlot = nil
    else
        selectedCompareKey, selectedCompareSlot = GearTab.PickBestCompareSelection(GearTab.GetDisplayList())
    end
    if GC and GC.LogItemComparisonDebug then
        GC.LogItemComparisonDebug(itemLink)
    end
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

function GearTab.GetCompareWarningColor(warning)
    local caution = COMPARE_WARNING_COLOR_CAUTION
    local blocking = COMPARE_WARNING_COLOR_BLOCKING
    local kind = IU and IU.GetEquipWarningKind and IU.GetEquipWarningKind(warning)
    if kind == IU.EQUIP_WARNING_KIND.LEVEL or kind == IU.EQUIP_WARNING_KIND.TRAINING then
        return caution[1], caution[2], caution[3]
    end
    if kind == IU.EQUIP_WARNING_KIND.NEVER then
        return blocking[1], blocking[2], blocking[3]
    end
    local text = IU and IU.GetEquipWarningText and IU.GetEquipWarningText(warning) or warning
    if type(text) == "string" then
        if text:find("must gain ", 1, true) or text:find("must train ", 1, true) then
            return caution[1], caution[2], caution[3]
        end
        if text:find("can never equip this", 1, true) then
            return blocking[1], blocking[2], blocking[3]
        end
    end
    return blocking[1], blocking[2], blocking[3]
end

function GearTab.GetCompareWarnings(entry, itemLink, charData)
    if not entry or not itemLink or not IU or not IU.GetEquipWarnings then return {} end
    return IU.GetEquipWarnings(entry.classFile, entry.level, entry.name, itemLink, charData)
end

function GearTab.EstimateComparePanelHeight(comparison, warningCount, hasVerdict)
    if not comparison then return 0 end
    local leftH = COMPARE_ITEMS_ROW_HEIGHT + 8
    warningCount = tonumber(warningCount) or 0
    if warningCount > 0 then
        leftH = leftH + warningCount * COMPARE_ROW_HEIGHT + (warningCount - 1) * 2 + 4
    end
    if hasVerdict then
        leftH = leftH + COMPARE_ROW_HEIGHT + 4
    end
    local sections = comparison.sections or {}
    for s = 1, #sections do
        local section = sections[s]
        leftH = leftH + COMPARE_SECTION_GAP + COMPARE_ROW_HEIGHT
        leftH = leftH + #(section.rows or {}) * COMPARE_ROW_HEIGHT
    end
    local contentH = math.max(leftH, COMPARE_OPTIONS_SECTION_HEIGHT)
    return math.max(COMPARE_PANEL_MIN_HEIGHT, COMPARE_PANEL_PAD * 2 + contentH)
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

    -- When item focused, sort by focus category then upgrade magnitude.
    if not droppedItemLink then return list end
    local upgradeOpts = GU and GU.GetOptions and GU.GetOptions() or {}
    local focusSlots = GearTab.GetFocusedInventorySlots()
    local upgradeMaxDelta = GearTab.ComputeFocusUpgradeMaxDelta(list, focusSlots, upgradeOpts)
    local copy = {}
    for i = 1, #list do copy[i] = list[i] end
    table.sort(copy, function(a, b)
        local charA = DS and DS.GetCharacter and DS:GetCharacter(a.name, a.realm)
        local charB = DS and DS.GetCharacter and DS:GetCharacter(b.name, b.realm)
        local ta = GU and GU.GetFocusTier
            and GU.GetFocusTier(a, charA, droppedItemLink, upgradeOpts, upgradeMaxDelta) or 5
        local tb = GU and GU.GetFocusTier
            and GU.GetFocusTier(b, charB, droppedItemLink, upgradeOpts, upgradeMaxDelta) or 5
        if ta ~= tb then return ta < tb end
        if GU and GU.GetFocusUpgradeDelta then
            local da = GU.GetFocusUpgradeDelta(a, charA, droppedItemLink, upgradeOpts, upgradeMaxDelta) or 0
            local db = GU.GetFocusUpgradeDelta(b, charB, droppedItemLink, upgradeOpts, upgradeMaxDelta) or 0
            if da ~= db then return da > db end
        end
        return (a.name or "") < (b.name or "")
    end)
    return copy
end

function GearTab.GetFocusSummaryForEntry(entry, upgradeMaxDelta)
    if not droppedItemLink or not GU or not GU.SummarizeFocusEntry then return nil end
    local charData = DS and DS.GetCharacter and DS:GetCharacter(entry.name, entry.realm)
    local opts = GU.GetOptions and GU.GetOptions() or {}
    return GU.SummarizeFocusEntry(entry, charData, droppedItemLink, opts, upgradeMaxDelta)
end

function GearTab.GetFocusColumnDimmed(entry, upgradeMaxDelta)
    if not droppedItemLink or not GU or not GU.GetFocusColumnDimmed then return false end
    local charData = DS and DS.GetCharacter and DS:GetCharacter(entry.name, entry.realm)
    local opts = GU.GetOptions and GU.GetOptions() or {}
    return GU.GetFocusColumnDimmed(entry, charData, droppedItemLink, opts, upgradeMaxDelta)
end

function GearTab.getUpgradeHighlightHorizontalInset()
    return UPGRADE_HIGHLIGHT_COLUMN_INSET
end

function GearTab.getUpgradeHighlightBelowHeaderExtent()
    local rh = dims.rowHeight or select(1, GearTab.GetSpacingDimensions())
    local cell = dims.cellSize or GearTab.GetCellSizePx()
    return (rh - cell) / 2 + cell
end

function GearTab.getUpgradeHighlightKind(delta, maxDelta)
    if GU and GU.GetUpgradeHighlightKind then
        return GU.GetUpgradeHighlightKind(delta, maxDelta)
    end
    if not delta or delta <= 0 then return nil end
    if not maxDelta or maxDelta <= 0 then return "clear" end
    if delta >= maxDelta * CLEAR_UPGRADE_RATIO then return "clear" end
    return "minor"
end

function GearTab.getFocusColumnAlpha(shouldDim, isSelected)
    if isSelected then return 1 end
    if not droppedItemLink then return 1 end
    if shouldDim then return FOCUS_FADE_ALPHA end
    return 1
end

function GearTab.GetFirstFocusedColumnSlot()
    local visible = GearTab.GetVisibleDisplaySlots()
    if #visible > 0 then
        return SLOT_ORDER[visible[1]]
    end
    local slots = GearTab.GetFocusedInventorySlots()
    return slots[1]
end

function GearTab.SelectCompareCell(charKey, invSlot)
    if not charKey or not invSlot then return end
    if GearTab.IsCompareCellSelected(charKey, invSlot) then
        GearTab.ClearCompareSelection()
    else
        selectedCompareKey = charKey
        selectedCompareSlot = invSlot
    end
    if frame.RefreshGrid then frame:RefreshGrid() end
end

function GearTab.SelectCompareCharacter(key)
    if not key then return end
    local invSlot = GearTab.GetFirstFocusedColumnSlot()
    if invSlot then
        GearTab.SelectCompareCell(key, invSlot)
    end
end

local function resolveColumnHighlightColor(_kind, selected)
    if not selected then return nil end
    return SELECTED_NEUTRAL_HIGHLIGHT
end

local function layoutCellFillTexture(tex, cell, hInset, r, g, b, a)
    if not tex or not cell then
        if tex then tex:Hide() end
        return
    end
    tex:SetColorTexture(r, g, b, a)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", cell, "TOPLEFT", -hInset, hInset)
    tex:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", hInset, -hInset)
    tex:Show()
end

function GearTab.layoutCellUpgradeBadge(cell, kind)
    if not cell or not cell.upgradeBadge then return end
    local badge = cell.upgradeBadge
    if not kind then
        badge:Hide()
        return
    end
    local colors = UPGRADE_BADGE_COLORS[kind]
    local text = UPGRADE_BADGE_TEXT[kind]
    if not colors or not text then
        badge:Hide()
        return
    end
    local offsetY = UPGRADE_BADGE_OFFSET_Y
    if kind == "sidegrade" or kind == "sidegradeFuture" then
        offsetY = offsetY + UPGRADE_BADGE_SIDEGRADE_Y_EXTRA
    end
    badge:ClearAllPoints()
    badge:SetPoint("CENTER", cell, "TOPRIGHT", UPGRADE_BADGE_OFFSET_X, offsetY)
    badge:SetText(text)
    badge:SetTextColor(colors[1], colors[2], colors[3], 1)
    badge:Show()
end

function GearTab.layoutCellFocusHighlight(cell, _kind, selected)
    if not cell or not cell.focusHighlight then return end
    local colors = resolveColumnHighlightColor(nil, selected)
    if not colors then
        cell.focusHighlight:Hide()
        return
    end
    local hInset = GearTab.getUpgradeHighlightHorizontalInset()
    layoutCellFillTexture(
        cell.focusHighlight, cell, hInset,
        colors[1], colors[2], colors[3], colors[4])
end

function GearTab.layoutCellCompareHover(cell, show)
    if not cell or not cell.compareHover then return end
    if not show then
        cell.compareHover:Hide()
        return
    end
    local hInset = GearTab.getUpgradeHighlightHorizontalInset()
    local r, g, b, a = COMPARE_HOVER_COLOR[1], COMPARE_HOVER_COLOR[2], COMPARE_HOVER_COLOR[3], COMPARE_HOVER_COLOR[4]
    layoutCellFillTexture(cell.compareHover, cell, hInset, r, g, b, a)
end

function GearTab.layoutSelectionOutline(_headerCol, gridCol, _focusCells, _show)
    local function hideOutline(o)
        if not o then return end
        for _, tex in pairs(o) do tex:Hide() end
    end
    hideOutline(gridCol and gridCol.selectionOutline)
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

    local effective = IU and IU.EffectiveRequiredLevel
        and IU.EffectiveRequiredLevel(classFile, droppedItemLink) or reqLevel
    if effective >= 999 then
        effective = reqLevel
    end
    local delta = charLevel - effective
    local summary = GearTab.GetFocusSummaryForEntry(entry)
    if summary and summary.category and GU and GU.FOCUS_CATEGORY then
        local cat = summary.category
        if cat == GU.FOCUS_CATEGORY.UPGRADE_IN_RANGE
            or cat == GU.FOCUS_CATEGORY.SIDEGRADE_IN_RANGE then
            return "Upgrade!", "green"
        end
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

function GearTab.SetCompareItemIcon(iconFrame, itemLink)
    if not iconFrame then return end
    iconFrame.itemLink = itemLink
    local texPath = itemLink and GearTab.GetItemTexture(itemLink)
    if texPath and iconFrame.texture then
        iconFrame.texture:SetTexture(texPath)
        iconFrame.texture:SetVertexColor(1, 1, 1, 1)
        iconFrame.texture:Show()
    elseif iconFrame.texture then
        iconFrame.texture:Hide()
    end
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

function GearTab.ApplyItemCellVisual(cell, item, gray, alpha)
    local fade = alpha or 1
    local texPath = GearTab.GetItemTexture(item)
    if texPath then
        cell.texture:SetTexture(texPath)
        cell.texture:Show()
        if gray then
            cell.texture:SetVertexColor(0.5, 0.5, 0.5, fade)
        else
            cell.texture:SetVertexColor(fade, fade, fade, fade)
        end
    else
        cell.texture:SetTexture(nil)
        cell.texture:Hide()
    end

    local gr, gg, gb = GearTab.GetQualityGlowColor(GearTab.GetItemQuality(item))
    if gr and texPath and cell.glow then
        cell.glow:SetColorTexture(gr, gg, gb, ITEM_GLOW_ALPHA * fade)
        if gray then
            cell.glow:SetVertexColor(0.5, 0.5, 0.5, fade)
        else
            cell.glow:SetVertexColor(fade, fade, fade, fade)
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

-- ---- Gear layout host (transparent; section panels sit inside with gaps like Graphs tab) ----
local gearLayoutHost = CreateFrame("Frame", nil, frame)
gearLayoutHost:SetPoint("TOPLEFT", frame, "TOPLEFT", SECTION_INSET, -SECTION_INSET)
gearLayoutHost:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SECTION_INSET, SECTION_INSET)

local gearMainSection
local itemCheckSection
local compareStatsSection
local compareSettingsSection
local gridHost
local settingsPanel

-- ---- Left panel ----
local leftPanel = CreateFrame("Frame", nil, gearLayoutHost)
leftPanel:SetPoint("TOPLEFT", gearLayoutHost, "TOPLEFT", 0, 0)
leftPanel:SetPoint("BOTTOMLEFT", gearLayoutHost, "BOTTOMLEFT", 0, 0)
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
        GearTab.ApplyFocusedItem(itemLink, { manual = true })
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

local rightPanel = CreateFrame("Frame", nil, gearLayoutHost)
if LEFT_PANEL_VISIBLE then
    rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", PAD, 0)
else
    rightPanel:SetPoint("TOPLEFT", gearLayoutHost, "TOPLEFT", 0, 0)
end
rightPanel:SetPoint("BOTTOMRIGHT", gearLayoutHost, "BOTTOMRIGHT", 0, 0)

local HORIZONTAL_SCROLL_BAR_HEIGHT = 20

gearMainSection = Theme.CreateTabContentPanel(rightPanel)
local gearMainInner = Theme.CreatePanelInnerContent(gearMainSection)
gearMainInner:SetClipsChildren(true)

function GearTab.GetHorizontalScrollChromeHeight()
    return HORIZONTAL_SCROLL_BAR_HEIGHT
end

-- Fixed header row: character names + score row; scrolls horizontally with grid
local fixedHeaderRow = CreateFrame("Frame", nil, gearMainInner)
fixedHeaderRow:SetPoint("TOPLEFT", gearMainInner, "TOPLEFT", 0, 0)
fixedHeaderRow:SetPoint("TOPRIGHT", gearMainInner, "TOPRIGHT", 0, 0)
fixedHeaderRow:SetHeight(GearTab.GetPinnedHeaderHeight())
local headerBg = fixedHeaderRow:CreateTexture(nil, "BACKGROUND")
headerBg:SetAllPoints(true)
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
itemCheckBtnText:SetText("Upgrade check")

local itemCheckModeActive = false

function GearTab.updateItemCheckButtonLabel()
    if droppedItemLink or itemCheckModeActive then
        itemCheckBtnText:SetText("Go back")
    else
        itemCheckBtnText:SetText("Upgrade check")
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

gridHost = CreateFrame("Frame", nil, gearMainInner)
gridHost:SetClipsChildren(true)
local horizontalScrollBar

function GearTab.LayoutGridHost()
    local chromeH = GearTab.GetHorizontalScrollChromeHeight()
    gridHost:ClearAllPoints()
    gridHost:SetPoint("TOPLEFT", fixedHeaderRow, "BOTTOMLEFT", 0, 0)
    gridHost:SetPoint("TOPRIGHT", gearMainInner, "TOPRIGHT", 0, 0)
    gridHost:SetPoint("BOTTOMLEFT", gearMainInner, "BOTTOMLEFT", 0, 0)
    gridHost:SetPoint("BOTTOMRIGHT", gearMainInner, "BOTTOMRIGHT", 0, chromeH)
    if horizontalScrollBar then
        horizontalScrollBar:ClearAllPoints()
        horizontalScrollBar:SetPoint("BOTTOMLEFT", gearMainInner, "BOTTOMLEFT", 0, 0)
        horizontalScrollBar:SetPoint("BOTTOMRIGHT", gearMainInner, "BOTTOMRIGHT", -SCROLL_GUTTER, 0)
        horizontalScrollBar:SetFrameLevel(gearMainInner:GetFrameLevel() + 30)
        horizontalScrollBar:EnableMouse(true)
    end
end

GearTab.LayoutGridHost()

-- Vertical scroll: grid area below pinned header
local verticalScroll = CreateFrame("ScrollFrame", "AltArmyTBC_GearVerticalScroll", gridHost)
verticalScroll:SetPoint("TOPLEFT", gridHost, "TOPLEFT", 0, 0)
verticalScroll:SetPoint("BOTTOMRIGHT", gridHost, "BOTTOMRIGHT", -SCROLL_GUTTER, 0)
verticalScroll:EnableMouse(true)

local MIN_SCROLL_CHILD_WIDTH = 400
local verticalScrollChild = CreateFrame("Frame", nil, verticalScroll)
verticalScrollChild:SetPoint("TOPLEFT", verticalScroll, "TOPLEFT", 0, 0)
verticalScrollChild:SetHeight(dims.scrollableGridHeight)
verticalScrollChild:SetWidth(MIN_SCROLL_CHILD_WIDTH)
verticalScrollChild:EnableMouse(true)
verticalScroll:SetScrollChild(verticalScrollChild)

-- Vertical scroll bar: custom (no template) so it doesn't conflict with horizontal; both bars under our control
local verticalScrollBar = CreateFrame("Slider", "AltArmyTBC_GearVerticalScrollBar", gridHost)
verticalScrollBar:SetMinMaxValues(0, 0)
verticalScrollBar:SetValueStep(dims.rowHeight)
verticalScrollBar:SetValue(0)
verticalScrollBar:EnableMouse(true)
Theme.AnchorVerticalScrollBar(verticalScrollBar, gearMainSection, verticalScroll)

verticalScrollBar:SetScript("OnValueChanged", function(_, value)
    verticalScroll:SetVerticalScroll(value)
end)

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
end
verticalScroll:SetScript("OnMouseWheel", GearTab.OnGearScrollWheel)
verticalScrollChild:SetScript("OnMouseWheel", GearTab.OnGearScrollWheel)

-- Row headers (slot names); scroll with equipment rows
local slotHeaderContainer = CreateFrame("Frame", nil, verticalScrollChild)
slotHeaderContainer:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", 0, 0)
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
    if GearTab.ApplyScoreSortLayout then
        GearTab.ApplyScoreSortLayout()
    end
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

function GearTab.ApplyScoreSortLayout()
    -- Hide direction toggle while focus/comparison mode overrides score sorting (like faction sort on Rep tab).
    local showDirection = not droppedItemLink
    if scoreSortBtn then
        scoreSortBtn:SetShown(showDirection)
    end
    local bottomInset = SCORE_ROW_HEADER_BOTTOM_INSET
    if showDirection then
        scoreProviderStaticLabel:SetPoint("BOTTOMRIGHT", scoreSortBtn, "BOTTOMLEFT", -SCORE_SORT_BTN_GAP, 0)
        scoreProviderBtn:SetPoint("BOTTOMRIGHT", scoreSortBtn, "BOTTOMLEFT", -SCORE_SORT_BTN_GAP, 0)
    else
        scoreProviderStaticLabel:SetPoint("BOTTOMRIGHT", headerCornerColumn, "BOTTOMRIGHT", -2, bottomInset)
        scoreProviderBtn:SetPoint("BOTTOMRIGHT", headerCornerColumn, "BOTTOMRIGHT", 0, bottomInset)
    end
end

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

-- Horizontal viewport: same vertical start as slot labels
local horizontalScroll = CreateFrame("ScrollFrame", "AltArmyTBC_GearHorizontalScroll", verticalScrollChild)
horizontalScroll:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", SLOT_LABEL_WIDTH, 0)
horizontalScroll:SetPoint("TOPRIGHT", verticalScrollChild, "TOPRIGHT", 0, 0)
horizontalScroll:SetHeight(dims.scrollableGridHeight)
horizontalScroll:EnableMouse(true)

-- Grid area: scroll child of horizontalScroll; engine scrolls via SetHorizontalScroll (like vertical)
local gridContainer = CreateFrame("Frame", nil, horizontalScroll)
gridContainer:SetPoint("TOPLEFT", horizontalScroll, "TOPLEFT", 0, 0)
gridContainer:SetHeight(dims.scrollableGridHeight)
horizontalScroll:SetScrollChild(gridContainer)

-- Header column pool: name + message per character, in fixed header row (scrolls horizontally)
local headerColumnPool = {}
-- Pool of character column frames (cells only; reused)
local columnPool = {}

function GearTab.RefreshCompareHover()
    for _, col in pairs(columnPool) do
        if col:IsShown() and col.compareKey then
            for slot = 1, NUM_EQUIPMENT_SLOTS do
                local cell = col.cells[slot]
                if cell and cell:IsShown() and cell.isFocusCompareCell and cell.inventorySlot then
                    local cellKey = GearTab.MakeCompareCellKey(col.compareKey, cell.inventorySlot)
                    local show = droppedItemLink
                        and hoveredCompareKey == cellKey
                        and not GearTab.IsCompareCellSelected(col.compareKey, cell.inventorySlot)
                    GearTab.layoutCellCompareHover(cell, show)
                end
            end
        end
    end
end

function GearTab.AddCompareHover(key)
    if not key then return end
    compareHoverRefs[key] = (compareHoverRefs[key] or 0) + 1
    if hoveredCompareKey ~= key then
        hoveredCompareKey = key
        GearTab.RefreshCompareHover()
    end
end

function GearTab.RemoveCompareHover(key)
    if not key then return end
    local n = (compareHoverRefs[key] or 0) - 1
    if n <= 0 then
        compareHoverRefs[key] = nil
    else
        compareHoverRefs[key] = n
    end
    local function apply()
        local active = nil
        for k, count in pairs(compareHoverRefs) do
            if count > 0 then
                active = k
                break
            end
        end
        if active ~= hoveredCompareKey then
            hoveredCompareKey = active
            GearTab.RefreshCompareHover()
        end
    end
    local ctimer = _G.C_Timer
    if ctimer and ctimer.After then
        ctimer.After(0, apply)
    else
        apply()
    end
end

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
            if not GameTooltip then return end
            local show = false
            if self.tooltipText and self.tooltipText ~= "" then
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(self.tooltipText, 1, 1, 1)
                show = true
            end
            if droppedItemLink and self.compareKey then
                if not show then
                    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                    GameTooltip:ClearLines()
                end
                GameTooltip:AddLine("Click to compare", 0.7, 0.7, 0.7)
                show = true
            end
            if show then GameTooltip:Show() end
        end)
        col:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        col:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" or not droppedItemLink or not self.compareKey then return end
            local shift = IsShiftKeyDown and IsShiftKeyDown()
            local ctrl = IsControlKeyDown and IsControlKeyDown()
            if shift or ctrl then return end
            GearTab.SelectCompareCharacter(self.compareKey)
        end)
        headerColumnPool[index] = col
    end
    return headerColumnPool[index]
end

-- Horizontal scroll bar: create after horizontalScroll/gridContainer exist so OnValueChanged sees them
local scrollGridLeftFade
local scrollHeaderLeftFade
local horizontalScrollApi = Theme.CreateHorizontalScrollBar(gearMainInner, {
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
horizontalScrollBar = horizontalScrollApi.bar
GearTab.LayoutGridHost()

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

-- Item Check mode: header panel + instructions panel below.
itemCheckSection = Theme.CreateTabContentPanel(rightPanel)
itemCheckSection:Hide()
local itemCheckInner = Theme.CreatePanelInnerContent(itemCheckSection)
itemCheckInner:EnableMouse(true)

local ITEM_CHECK_STACK_WIDTH = 420
local ITEM_CHECK_STACK_HEIGHT = 180

local itemCheckStack = CreateFrame("Frame", nil, itemCheckInner)
itemCheckStack:SetSize(ITEM_CHECK_STACK_WIDTH, ITEM_CHECK_STACK_HEIGHT)
itemCheckStack:SetPoint("CENTER", itemCheckInner, "CENTER", 0, 0)

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
itemCheckCancelText:SetText("Go back")

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
    GearTab.ApplyFocusedItem(itemLink, { manual = true })
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

-- Character comparison panels (split view below focused slot grid)
compareStatsSection = Theme.CreateTabContentPanel(rightPanel)
compareStatsSection:Hide()
local compareStatsInner = Theme.CreatePanelInnerContent(compareStatsSection)

compareSettingsSection = Theme.CreateTabContentPanel(rightPanel)
compareSettingsSection:Hide()
local compareSettingsInner = Theme.CreatePanelInnerContent(compareSettingsSection)

local compareItemsRow = CreateFrame("Frame", nil, compareStatsInner)
compareItemsRow:SetPoint("TOPLEFT", compareStatsInner, "TOPLEFT", 0, 0)
compareItemsRow:SetPoint("TOPRIGHT", compareStatsInner, "TOPRIGHT", 0, 0)
compareItemsRow:SetHeight(COMPARE_FOCUS_HEADER_HEIGHT)

local compareFocusRow = CreateFrame("Frame", nil, compareItemsRow)
compareFocusRow:SetHeight(COMPARE_FOCUS_HEADER_HEIGHT)
compareFocusRow:SetPoint("CENTER", compareItemsRow, "CENTER", 0, 0)

local compareFocusTitle = compareFocusRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
compareFocusTitle:SetJustifyH("RIGHT")
compareFocusTitle:SetText(GearTab.FormatCompareFocusTitle())
if Theme.SetLabelColor then
    Theme.SetLabelColor(compareFocusTitle)
end

local compareFocusDrop = CreateFrame("Frame", nil, compareFocusRow, "BackdropTemplate")
compareFocusDrop:SetSize(COMPARE_FOCUS_DROP_SIZE, COMPARE_FOCUS_DROP_SIZE)
compareFocusDrop:EnableMouse(true)
Theme.ApplyBackdrop(compareFocusDrop, "section")

local compareFocusDropGlow = compareFocusDrop:CreateTexture(nil, "BACKGROUND")
compareFocusDropGlow:SetPoint("TOPLEFT", compareFocusDrop, "TOPLEFT", -5, 5)
compareFocusDropGlow:SetPoint("BOTTOMRIGHT", compareFocusDrop, "BOTTOMRIGHT", 5, -5)
if Theme.ApplySettingsGlow then
    Theme.ApplySettingsGlow(compareFocusDropGlow)
end
compareFocusDropGlow:Hide()

local compareFocusDropHover = compareFocusDrop:CreateTexture(nil, "BACKGROUND")
compareFocusDropHover:SetAllPoints(true)
compareFocusDropHover:SetTexture(Theme.HOVER_TINT_BG or "Interface\\Tooltips\\UI-Tooltip-Background")
compareFocusDropHover:SetVertexColor(0.82, 0.68, 0.22, 0)

function GearTab.setCompareFocusDropHighlighted(on)
    if on then
        compareFocusDropGlow:Show()
        compareFocusDropHover:SetVertexColor(0.82, 0.68, 0.22, 0.45)
        local colors = Theme.COLORS
        if colors and compareFocusDrop.SetBackdropColor then
            local bg = colors.btnHoverBg
            local border = colors.btnActiveBorder
            compareFocusDrop:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
            compareFocusDrop:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
        end
    else
        compareFocusDropGlow:Hide()
        compareFocusDropHover:SetVertexColor(0.82, 0.68, 0.22, 0)
        Theme.ApplyBackdrop(compareFocusDrop, "section")
    end
end

compareFocusDrop:SetScript("OnEnter", function(self)
    GearTab.setCompareFocusDropHighlighted(true)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if droppedItemLink and droppedItemLink ~= "" then
        GameTooltip:SetHyperlink(droppedItemLink)
    else
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Drop an item to check upgrades", 1, 1, 1)
    end
    GameTooltip:Show()
end)
compareFocusDrop:SetScript("OnLeave", function()
    GearTab.setCompareFocusDropHighlighted(false)
    if GameTooltip then GameTooltip:Hide() end
end)

local compareFocusDropIcon = compareFocusDrop:CreateTexture(nil, "OVERLAY")
compareFocusDropIcon:SetSize(32, 32)
compareFocusDropIcon:SetPoint("CENTER", compareFocusDrop, "CENTER", 0, 0)
compareFocusDropIcon:Hide()

local compareFocusVs = compareFocusRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
compareFocusVs:SetText(GearTab.FormatCompareFocusVsLabel())
if Theme.SetLabelColor then
    Theme.SetLabelColor(compareFocusVs)
end
compareFocusVs:Hide()

local compareFocusEquipped = CreateFrame("Frame", nil, compareFocusRow, "BackdropTemplate")
compareFocusEquipped:SetSize(COMPARE_FOCUS_DROP_SIZE, COMPARE_FOCUS_DROP_SIZE)
compareFocusEquipped:EnableMouse(true)
Theme.ApplyBackdrop(compareFocusEquipped, "section")
compareFocusEquipped:Hide()

local compareFocusEquippedIcon = compareFocusEquipped:CreateTexture(nil, "ARTWORK")
compareFocusEquippedIcon:SetPoint("TOPLEFT", compareFocusEquipped, "TOPLEFT", ITEM_ICON_INSET, -ITEM_ICON_INSET)
compareFocusEquippedIcon:SetPoint("BOTTOMRIGHT", compareFocusEquipped, "BOTTOMRIGHT", -ITEM_ICON_INSET, ITEM_ICON_INSET)
compareFocusEquipped.texture = compareFocusEquippedIcon

compareFocusEquipped:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.itemLink and self.itemLink ~= "" then
        GameTooltip:SetHyperlink(self.itemLink)
    else
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Empty slot", 1, 1, 1)
    end
    GameTooltip:Show()
end)
compareFocusEquipped:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
end)

local compareFocusError = compareItemsRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
compareFocusError:SetPoint("TOP", compareItemsRow, "BOTTOM", 0, -2)
compareFocusError:SetPoint("LEFT", compareItemsRow, "LEFT", 8, 0)
compareFocusError:SetPoint("RIGHT", compareItemsRow, "RIGHT", -8, 0)
compareFocusError:SetJustifyH("CENTER")
compareFocusError:SetWordWrap(true)
compareFocusError:SetTextColor(1, 0.4, 0.3, 1)
compareFocusError:Hide()

function GearTab.clearCompareFocusError()
    if compareFocusError then
        compareFocusError:SetText("")
        compareFocusError:Hide()
    end
end

function GearTab.showCompareFocusError(msg)
    if compareFocusError then
        compareFocusError:SetText(msg or "")
        compareFocusError:Show()
    end
end

function GearTab.updateCompareFocusDrop(itemLink)
    if not compareFocusDropIcon then return end
    if itemLink then
        local tex = GearTab.GetItemTexture(itemLink)
        if tex then
            compareFocusDropIcon:SetTexture(tex)
            compareFocusDropIcon:Show()
        else
            compareFocusDropIcon:Hide()
        end
    else
        compareFocusDropIcon:Hide()
    end
    GearTab.clearCompareFocusError()
end

function GearTab.tryAcceptCompareFocusDrop()
    local itemLink = GearTab.getCursorItemLink()
    if not itemLink then return false end

    local ok, errMsg = true, nil
    if IU and IU.ValidateItemCheckDrop then
        ok, errMsg = IU.ValidateItemCheckDrop(itemLink)
    end
    if not ok then
        GearTab.updateCompareFocusDrop(droppedItemLink)
        GearTab.showCompareFocusError(errMsg)
        return false
    end

    if ClearCursor then ClearCursor() end
    GearTab.ApplyFocusedItem(itemLink, { manual = true })
    GearTab.updateCompareFocusDrop(itemLink)
    GearTab.updateItemCheckButtonLabel()
    if frame.RefreshGrid then frame:RefreshGrid() end
    return true
end

compareFocusDrop:SetScript("OnReceiveDrag", GearTab.tryAcceptCompareFocusDrop)
compareFocusDrop:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then
        droppedItemLink = nil
        GearTab.ClearCompareSelection()
        GearTab.updateCompareFocusDrop(nil)
        GearTab.updateItemCheckButtonLabel()
        if frame.RefreshGrid then frame:RefreshGrid() end
        return
    end
    GearTab.tryAcceptCompareFocusDrop()
end)

local compareEmptyHintArea = CreateFrame("Frame", nil, compareStatsInner)
compareEmptyHintArea:SetPoint("TOPLEFT", compareItemsRow, "BOTTOMLEFT", 0, 0)
compareEmptyHintArea:SetPoint("BOTTOMRIGHT", compareStatsInner, "BOTTOMRIGHT", 0, 0)
compareEmptyHintArea:Hide()

local compareEmptyHint = compareEmptyHintArea:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
compareEmptyHint:SetPoint("LEFT", compareEmptyHintArea, "LEFT", 12, 0)
compareEmptyHint:SetPoint("RIGHT", compareEmptyHintArea, "RIGHT", -12, 0)
compareEmptyHint:SetPoint("CENTER", compareEmptyHintArea, "CENTER", 0, 0)
compareEmptyHint:SetJustifyH("CENTER")
compareEmptyHint:SetJustifyV("MIDDLE")
compareEmptyHint:SetWordWrap(true)
compareEmptyHint:Hide()

local compareWarningContainer = CreateFrame("Frame", nil, compareStatsInner)
local compareWarningRows = {}

local compareVerdictRow = CreateFrame("Frame", nil, compareStatsInner)
compareVerdictRow:SetHeight(COMPARE_ROW_HEIGHT)
compareVerdictRow:Hide()
local compareVerdictPrefix = compareVerdictRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
compareVerdictPrefix:SetPoint("LEFT", compareVerdictRow, "LEFT", 0, 0)
compareVerdictPrefix:SetJustifyH("LEFT")
compareVerdictPrefix:SetText("Verdict: ")
local compareVerdictLabel = compareVerdictRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
compareVerdictLabel:SetPoint("LEFT", compareVerdictPrefix, "RIGHT", 0, 0)
compareVerdictLabel:SetPoint("RIGHT", compareVerdictRow, "RIGHT", 0, 0)
compareVerdictLabel:SetJustifyH("LEFT")

local compareOptionsSection = CreateFrame("Frame", nil, compareSettingsInner)
compareOptionsSection:SetPoint("TOPLEFT", compareSettingsInner, "TOPLEFT", 0, 0)
compareOptionsSection:SetPoint("TOPRIGHT", compareSettingsInner, "TOPRIGHT", 0, 0)
compareOptionsSection:SetPoint("BOTTOMRIGHT", compareSettingsInner, "BOTTOMRIGHT", 0, 0)

local compareAlgoLabel = compareOptionsSection:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
compareAlgoLabel:SetPoint("TOPLEFT", compareOptionsSection, "TOPLEFT", 0, 0)
compareAlgoLabel:SetText("Comparison technique")

local compareAlgoBtn = CreateFrame("Button", nil, compareOptionsSection)
compareAlgoBtn:SetPoint("TOP", compareAlgoLabel, "BOTTOM", 0, -4)
compareAlgoBtn:SetPoint("LEFT", compareOptionsSection, "LEFT", 0, 0)
compareAlgoBtn:SetPoint("RIGHT", compareOptionsSection, "RIGHT", 0, 0)
compareAlgoBtn:SetHeight(COMPARE_DROPDOWN_ROW - 4)
Theme.SkinButton(compareAlgoBtn)
local compareAlgoBtnText = compareAlgoBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
compareAlgoBtnText:SetPoint("LEFT", compareAlgoBtn, "LEFT", 6, 0)
compareAlgoBtnText:SetPoint("RIGHT", compareAlgoBtn, "RIGHT", -2, 0)
compareAlgoBtnText:SetJustifyH("LEFT")

local compareLevelsLabel = compareOptionsSection:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
compareLevelsLabel:SetPoint("TOPLEFT", compareAlgoBtn, "BOTTOMLEFT", 0, -8)
compareLevelsLabel:SetText("Level look-ahead")

local compareLevelsEdit = CreateFrame("EditBox", nil, compareOptionsSection)
compareLevelsEdit:SetPoint("TOPLEFT", compareLevelsLabel, "BOTTOMLEFT", 0, -4)
compareLevelsEdit:SetSize(44, 20)
compareLevelsEdit:SetFontObject("GameFontHighlightSmall")
compareLevelsEdit:SetAutoFocus(false)
compareLevelsEdit:SetNumeric(true)
compareLevelsEdit:SetJustifyH("CENTER")
Theme.ApplyInputTextures(compareLevelsEdit)

local function syncCompareLevelsEditFromOptions()
    if not compareLevelsEdit or not GU or not GU.GetOptions then return end
    if compareLevelsEdit.HasFocus and compareLevelsEdit:HasFocus() then return end
    local levelsAhead = GU.GetOptions().levelsAhead
    compareLevelsEdit:SetText(tostring(levelsAhead ~= nil and levelsAhead or 5))
end

local function saveCompareLevelsAhead()
    if not GU or not GU.EnsureGearUpgradeOptions then return end
    local n = tonumber(compareLevelsEdit:GetText()) or 0
    local newVal = math.max(0, math.floor(n))
    local opts = GU.EnsureGearUpgradeOptions()
    if opts.levelsAhead == newVal then return end
    opts.levelsAhead = newVal
    if frame.RefreshGrid then frame:RefreshGrid() end
end

compareLevelsEdit:SetScript("OnTextChanged", function()
    saveCompareLevelsAhead()
end)
compareLevelsEdit:SetScript("OnEnterPressed", function(box)
    box:ClearFocus()
    saveCompareLevelsAhead()
end)
compareLevelsEdit:SetScript("OnEditFocusLost", saveCompareLevelsAhead)

local compareAlgoDropdown = CreateFrame("Frame", nil, compareSettingsSection, "BackdropTemplate")
compareAlgoDropdown:SetPoint("TOPLEFT", compareAlgoBtn, "BOTTOMLEFT", 0, -2)
compareAlgoDropdown:SetWidth(COMPARE_ALGO_DROPDOWN_WIDTH)
compareAlgoDropdown:SetFrameLevel(compareSettingsSection:GetFrameLevel() + 100)
compareAlgoDropdown:Hide()
Theme.ApplyBackdrop(compareAlgoDropdown, "section")
local compareAlgoDropdownButtons = {}

local compareStatContainer = CreateFrame("Frame", nil, compareStatsInner)
local compareStatRows = {}

function GearTab.updateCompareFocusEquipped(itemLink)
    if not compareFocusEquipped then return end
    GearTab.SetCompareItemIcon(compareFocusEquipped, itemLink)
end

function GearTab.GetSelectedEquippedCompareLink(list, technique)
    if not GearTab.HasCompareSelection() or not GC or not GC.GetEquippedCompareItem then return nil end
    local entry = GearTab.GetSelectedCompareEntry(list)
    if not entry or not droppedItemLink then return nil end
    local charData = DS and DS.GetCharacter and DS:GetCharacter(entry.name, entry.realm)
    if not charData then return nil end
    return GC.GetEquippedCompareItem(charData, droppedItemLink, {
        technique = technique or GearTab.GetSessionCompareTechnique(),
        slot = selectedCompareSlot,
        entry = entry,
    })
end

function GearTab.LayoutCompareFocusInline(showCompareTarget)
    if not compareFocusTitle or not compareFocusDrop or not compareFocusRow then return end
    local gap = COMPARE_FOCUS_TITLE_GAP
    compareFocusTitle:ClearAllPoints()
    compareFocusDrop:ClearAllPoints()
    compareFocusTitle:SetPoint("LEFT", compareFocusRow, "LEFT", 0, 0)
    compareFocusTitle:SetPoint("CENTER", compareFocusRow, "CENTER", 0, 0)
    compareFocusDrop:SetPoint("LEFT", compareFocusTitle, "RIGHT", gap, 0)
    compareFocusDrop:SetPoint("CENTER", compareFocusTitle, "CENTER", 0, 0)

    local rowW = (compareFocusTitle:GetStringWidth() or 0) + gap + COMPARE_FOCUS_DROP_SIZE
    if showCompareTarget and compareFocusVs and compareFocusEquipped then
        compareFocusVs:Show()
        compareFocusEquipped:Show()
        compareFocusVs:ClearAllPoints()
        compareFocusEquipped:ClearAllPoints()
        compareFocusVs:SetPoint("LEFT", compareFocusDrop, "RIGHT", gap, 0)
        compareFocusVs:SetPoint("CENTER", compareFocusDrop, "CENTER", 0, 0)
        compareFocusEquipped:SetPoint("LEFT", compareFocusVs, "RIGHT", gap, 0)
        compareFocusEquipped:SetPoint("CENTER", compareFocusDrop, "CENTER", 0, 0)
        rowW = rowW + gap + (compareFocusVs:GetStringWidth() or 0)
            + gap + COMPARE_FOCUS_DROP_SIZE
    elseif compareFocusVs and compareFocusEquipped then
        compareFocusVs:Hide()
        compareFocusEquipped:Hide()
    end
    compareFocusRow:SetWidth(rowW)
    compareFocusRow:SetPoint("CENTER", compareItemsRow, "CENTER", 0, 0)
end

function GearTab.UpdateCompareFocusHeader(itemLink, equippedLink)
    if compareFocusTitle then
        compareFocusTitle:SetText(GearTab.FormatCompareFocusTitle())
    end
    if compareFocusVs then
        compareFocusVs:SetText(GearTab.FormatCompareFocusVsLabel())
    end
    local showCompareTarget = GearTab.HasCompareSelection()
    GearTab.updateCompareFocusDrop(itemLink)
    if showCompareTarget then
        GearTab.updateCompareFocusEquipped(equippedLink)
    else
        GearTab.updateCompareFocusEquipped(nil)
    end
    GearTab.LayoutCompareFocusInline(showCompareTarget)
    if compareItemsRow then compareItemsRow:Show() end
end

GearTab.LayoutCompareFocusInline(false)

function GearTab.ShowCompareEmptyHint()
    if compareEmptyHint then
        compareEmptyHint:SetText(GearTab.FormatCompareEmptyHintText())
        compareEmptyHint:Show()
    end
    if compareEmptyHintArea then compareEmptyHintArea:Show() end
    if compareWarningContainer then compareWarningContainer:Hide() end
    if compareVerdictRow then compareVerdictRow:Hide() end
    if compareStatContainer then compareStatContainer:Hide() end
    GearTab.HideCompareWarningRows()
    GearTab.HideCompareStatRows()
end

function GearTab.HideCompareEmptyHint()
    if compareEmptyHint then compareEmptyHint:Hide() end
    if compareEmptyHintArea then compareEmptyHintArea:Hide() end
    if compareStatContainer then compareStatContainer:Show() end
end

function GearTab.ShowCompareEmptyState(itemLink, equippedLink)
    GearTab.UpdateCompareFocusHeader(itemLink, equippedLink)
    GearTab.ShowCompareEmptyHint()
end

function GearTab.HideCompareEmptyState()
    GearTab.HideCompareEmptyHint()
end

function GearTab.HideCompareWarningRows()
    for i = 1, #compareWarningRows do
        compareWarningRows[i]:Hide()
    end
end

function GearTab.GetCompareWarningRow(index)
    if not compareWarningRows[index] then
        local row = compareWarningContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row:SetPoint("LEFT", compareWarningContainer, "LEFT", 0, 0)
        row:SetPoint("RIGHT", compareWarningContainer, "RIGHT", 0, 0)
        row:SetHeight(COMPARE_ROW_HEIGHT)
        row:SetJustifyH("LEFT")
        compareWarningRows[index] = row
    end
    return compareWarningRows[index]
end

function GearTab.LayoutComparePanelSections(warnings, verdict)
    local anchor = compareItemsRow
    GearTab.HideCompareWarningRows()

    if compareVerdictRow then
        compareVerdictRow:ClearAllPoints()
        if verdict and verdict.label then
            compareVerdictPrefix:SetText("Verdict: ")
            compareVerdictLabel:SetText(verdict.label)
            compareVerdictLabel:SetTextColor(verdict.r or 1, verdict.g or 1, verdict.b or 1, 1)
            compareVerdictRow:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
            compareVerdictRow:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
            compareVerdictRow:Show()
            anchor = compareVerdictRow
        else
            compareVerdictRow:Hide()
        end
    end

    local warningCount = warnings and #warnings or 0
    compareWarningContainer:ClearAllPoints()
    if warningCount > 0 then
        compareWarningContainer:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
        compareWarningContainer:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
        for i = 1, warningCount do
            local warning = warnings[i]
            local row = GearTab.GetCompareWarningRow(i)
            local text = IU and IU.GetEquipWarningText and IU.GetEquipWarningText(warning) or warning
            row:SetText(text)
            local wr, wg, wb = GearTab.GetCompareWarningColor(warning)
            row:SetTextColor(wr, wg, wb, 1)
            row:ClearAllPoints()
            if i == 1 then
                row:SetPoint("TOPLEFT", compareWarningContainer, "TOPLEFT", 0, 0)
                row:SetPoint("TOPRIGHT", compareWarningContainer, "TOPRIGHT", 0, 0)
            else
                local prev = compareWarningRows[i - 1]
                row:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -2)
                row:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -2)
            end
            row:Show()
        end
        compareWarningContainer:SetHeight(
            warningCount * COMPARE_ROW_HEIGHT + math.max(0, warningCount - 1) * 2)
        compareWarningContainer:Show()
        anchor = compareWarningContainer
    else
        compareWarningContainer:SetHeight(0)
        compareWarningContainer:Hide()
    end

    compareStatContainer:ClearAllPoints()
    compareStatContainer:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
    compareStatContainer:SetPoint("BOTTOMRIGHT", compareStatsInner, "BOTTOMRIGHT", 0, 0)
end

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
    local dropdownWidth = compareAlgoBtn:GetWidth()
    if dropdownWidth and dropdownWidth > 0 then
        compareAlgoDropdown:SetWidth(dropdownWidth)
    else
        compareAlgoDropdown:SetWidth(COMPARE_ALGO_DROPDOWN_WIDTH)
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

function GearTab.ShouldHideCompareSettingsSection()
    return GearTab.GetGearLayoutMode() == "focus_compare"
        and settingsPanel
        and settingsPanel:IsShown()
end

function GearTab.GetSettingsColumnLeftX()
    local w = frame:GetWidth()
    if w <= 0 then return 0 end
    return w * GRID_SPLIT_FRACTION + SECTION_GAP
end

function GearTab.LayoutCompareBottomPanels(mainSection, areaLeft, areaRight)
    local hideCompareSettings = GearTab.ShouldHideCompareSettingsSection()
    compareStatsSection:Show()
    compareStatsSection:ClearAllPoints()
    compareStatsSection:SetPoint("TOPLEFT", mainSection, "BOTTOMLEFT", 0, -SECTION_GAP)
    compareStatsSection:SetPoint("BOTTOMLEFT", areaLeft, "BOTTOMLEFT", 0, 0)
    if hideCompareSettings then
        compareStatsSection:SetPoint("BOTTOMRIGHT", areaRight, "BOTTOMRIGHT", 0, 0)
        if compareAlgoDropdown then compareAlgoDropdown:Hide() end
        return
    end

    compareSettingsSection:Show()
    compareSettingsSection:ClearAllPoints()
    compareSettingsSection:SetPoint("TOPRIGHT", mainSection, "BOTTOMRIGHT", 0, -SECTION_GAP)
    compareSettingsSection:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SECTION_INSET, SECTION_INSET)
    compareSettingsSection:SetPoint("LEFT", frame, "LEFT", GearTab.GetSettingsColumnLeftX(), 0)

    compareStatsSection:SetPoint("RIGHT", compareSettingsSection, "LEFT", -SECTION_GAP, 0)
end

function GearTab.ApplyGearLayoutHostBounds()
    gearLayoutHost:ClearAllPoints()
    gearLayoutHost:SetPoint("TOPLEFT", frame, "TOPLEFT", SECTION_INSET, -SECTION_INSET)
    if settingsPanel and settingsPanel:IsShown() then
        gearLayoutHost:SetPoint("BOTTOMRIGHT", settingsPanel, "BOTTOMLEFT", -SECTION_GAP, 0)
    else
        gearLayoutHost:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SECTION_INSET, SECTION_INSET)
    end
end

function GearTab.GetGearLayoutMode()
    if itemCheckModeActive then return "item_check" end
    if droppedItemLink then return "focus_compare" end
    return "normal"
end

function GearTab.GetGearMainSectionHeight()
    local innerPad = Theme.TAB_CONTENT_PADDING or 8
    local gridH = dims.scrollableGridHeight or GearTab.GetScrollableGridHeight()
    if itemCheckModeActive then
        return GearTab.GetPinnedHeaderHeight() + innerPad * 2
    end
    local chromeH = GearTab.GetHorizontalScrollChromeHeight()
    return GearTab.GetPinnedHeaderHeight() + gridH + chromeH + innerPad * 2
end

function GearTab.LayoutGearPanels()
    GearTab.ApplyGearLayoutHostBounds()
    local mode = GearTab.GetGearLayoutMode()
    local areaLeft = rightPanel
    local areaRight = rightPanel

    gearMainSection:Hide()
    itemCheckSection:Hide()
    compareStatsSection:Hide()
    compareSettingsSection:Hide()

    if mode == "item_check" then
        gearMainSection:Show()
        gearMainSection:ClearAllPoints()
        gearMainSection:SetPoint("TOPLEFT", areaLeft, "TOPLEFT", 0, 0)
        gearMainSection:SetPoint("TOPRIGHT", areaRight, "TOPRIGHT", 0, 0)
        gearMainSection:SetHeight(GearTab.GetGearMainSectionHeight())
        if gridHost then gridHost:Hide() end

        itemCheckSection:Show()
        itemCheckSection:ClearAllPoints()
        itemCheckSection:SetPoint("TOPLEFT", gearMainSection, "BOTTOMLEFT", 0, -SECTION_GAP)
        itemCheckSection:SetPoint("BOTTOMRIGHT", areaRight, "BOTTOMRIGHT", 0, 0)
    elseif mode == "focus_compare" then
        gearMainSection:Show()
        gearMainSection:ClearAllPoints()
        gearMainSection:SetPoint("TOPLEFT", areaLeft, "TOPLEFT", 0, 0)
        gearMainSection:SetPoint("TOPRIGHT", areaRight, "TOPRIGHT", 0, 0)
        gearMainSection:SetHeight(GearTab.GetGearMainSectionHeight())
        if gridHost then gridHost:Show() end

        GearTab.LayoutCompareBottomPanels(gearMainSection, areaLeft, areaRight)
    else
        gearMainSection:Show()
        gearMainSection:ClearAllPoints()
        gearMainSection:SetPoint("TOPLEFT", areaLeft, "TOPLEFT", 0, 0)
        gearMainSection:SetPoint("BOTTOMRIGHT", areaRight, "BOTTOMRIGHT", 0, 0)
        if gridHost then gridHost:Show() end
    end
end

GearTab.LayoutGearPanels()

function GearTab.LayoutScrollArea()
    local gridH = dims.scrollableGridHeight or GearTab.GetScrollableGridHeight()
    GearTab.LayoutGridHost()
    if horizontalScroll then
        horizontalScroll:SetHeight(gridH)
    end
    if slotHeaderContainer then
        slotHeaderContainer:ClearAllPoints()
        slotHeaderContainer:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", 0, 0)
        slotHeaderContainer:SetHeight(gridH)
        slotHeaderContainer:SetWidth(SLOT_LABEL_WIDTH)
    end
    if verticalScrollChild then
        verticalScrollChild:SetHeight(gridH)
    end
    GearTab.LayoutGearPanels()
end

function GearTab.UpdateComparePanel(list)
    GearTab.HideCompareStatRows()
    if not droppedItemLink then
        if compareAlgoDropdown then compareAlgoDropdown:Hide() end
        if compareItemsRow then compareItemsRow:Hide() end
        GearTab.HideCompareEmptyHint()
        return
    end

    syncCompareLevelsEditFromOptions()
    GearTab.RebuildCompareTechniqueDropdown()
    local technique = GearTab.GetSessionCompareTechnique()
    local provider = GU.GetProvider(GU.GetEffectiveTechnique(technique))
    compareAlgoBtnText:SetText(provider and GU.GetProviderDisplayLabel(provider) or technique)

    local equippedLink = GearTab.GetSelectedEquippedCompareLink(list, technique)
    GearTab.UpdateCompareFocusHeader(droppedItemLink, equippedLink)

    if not GearTab.HasCompareSelection() or not GC then
        if compareAlgoDropdown then compareAlgoDropdown:Hide() end
        GearTab.ShowCompareEmptyHint()
        return
    end

    GearTab.HideCompareEmptyState()
    local entry = GearTab.GetSelectedCompareEntry(list)
    if not entry then
        GearTab.ClearCompareSelection()
        GearTab.ShowCompareEmptyHint()
        return
    end
    local charData = DS and DS.GetCharacter and DS:GetCharacter(entry.name, entry.realm)
    if not charData then return end

    equippedLink = equippedLink or GC.GetEquippedCompareItem(charData, droppedItemLink, {
        technique = technique,
        slot = selectedCompareSlot,
        entry = entry,
    })
    local comparison = GC.BuildComparison(droppedItemLink, equippedLink, technique, charData, entry)
    if not comparison then return end

    local compareWarnings = GearTab.GetCompareWarnings(entry, droppedItemLink, charData)
    local focusOpts = GU and GU.GetOptions and GU.GetOptions() or {}
    local upgradeMaxDelta = GearTab.ComputeFocusUpgradeMaxDelta(
        list, GearTab.GetFocusedInventorySlots(), focusOpts)
    local verdict = GU and GU.GetFocusVerdictForSlot
        and GU.GetFocusVerdictForSlot(
            entry, charData, droppedItemLink, selectedCompareSlot, focusOpts, upgradeMaxDelta)
    if GU and GU.LogFocusSlotDebug then
        GU.LogFocusSlotDebug(
            entry,
            charData,
            droppedItemLink,
            selectedCompareSlot,
            focusOpts,
            upgradeMaxDelta,
            {
                sessionTechnique = technique,
                equippedCompareLink = equippedLink,
            })
    end
    GearTab.LayoutComparePanelSections(compareWarnings, verdict)

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
            line:SetPoint("TOPLEFT", compareStatRows[rowIndex - 1], "BOTTOMLEFT", 0, -2)
            line:SetPoint("LEFT", compareStatContainer, "LEFT", COMPARE_STAT_ROW_INDENT, 0)
            line:SetPoint("RIGHT", compareStatContainer, "RIGHT", 0, 0)
            line:Show()
        end
    end

    for i = rowIndex + 1, #compareStatRows do
        compareStatRows[i]:Hide()
    end
end

function GearTab.enterItemCheckMode()
    itemCheckModeActive = true
    GearTab.resetItemCheckDrop()
    if compareAlgoDropdown then compareAlgoDropdown:Hide() end
    if slotHeaderContainer then slotHeaderContainer:Hide() end
    if horizontalScroll then horizontalScroll:Hide() end
    if verticalScrollBar then verticalScrollBar:Hide() end
    if horizontalScrollBar then horizontalScrollBar:Hide() end
    if verticalScroll then verticalScroll:EnableMouse(false) end
    GearTab.updateItemCheckButtonLabel()
    GearTab.LayoutGearPanels()
end

function GearTab.exitItemCheckMode()
    itemCheckModeActive = false
    GearTab.resetItemCheckDrop()
    if slotHeaderContainer then slotHeaderContainer:Show() end
    if horizontalScroll then horizontalScroll:Show() end
    if verticalScrollBar then verticalScrollBar:Show() end
    if horizontalScrollBar then horizontalScrollBar:Show() end
    if verticalScroll then verticalScroll:EnableMouse(true) end
    GearTab.updateItemCheckButtonLabel()
    GearTab.LayoutGearPanels()
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
    GearTab.ApplyFocusedItem(link)
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
        local upgradeHighlight = col:CreateTexture(nil, "BACKGROUND", nil, -2)
        upgradeHighlight:Hide()
        col.upgradeHighlight = upgradeHighlight
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
            cell.focusHighlight = cell:CreateTexture(nil, "BACKGROUND", nil, -2)
            cell.focusHighlight:Hide()
            cell.compareHover = cell:CreateTexture(nil, "BACKGROUND", nil, -1)
            cell.compareHover:SetColorTexture(
                COMPARE_HOVER_COLOR[1],
                COMPARE_HOVER_COLOR[2],
                COMPARE_HOVER_COLOR[3],
                COMPARE_HOVER_COLOR[4])
            cell.compareHover:Hide()
            cell.upgradeBadge = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            applyUpgradeBadgeFont(cell.upgradeBadge)
            cell.upgradeBadge:SetPoint("CENTER", cell, "TOPRIGHT", UPGRADE_BADGE_OFFSET_X, UPGRADE_BADGE_OFFSET_Y)
            cell.upgradeBadge:SetJustifyH("CENTER")
            cell.upgradeBadge:Hide()
            cell:SetScript("OnMouseUp", function(self, button)
                local colFrame = self:GetParent()
                if droppedItemLink and button == "LeftButton" and colFrame and colFrame.compareKey
                    and self.isFocusCompareCell and self.inventorySlot then
                    local shift = IsShiftKeyDown and IsShiftKeyDown()
                    local ctrl = IsControlKeyDown and IsControlKeyDown()
                    if not shift and not ctrl then
                        GearTab.SelectCompareCell(colFrame.compareKey, self.inventorySlot)
                        return
                    end
                end
                local target = self.itemLink or self.itemID
                if not target then return end
                GearTab.HandleItemCellClick(target, button)
            end)
            cell:SetScript("OnEnter", function(self)
                local colFrame = self:GetParent()
                if droppedItemLink and colFrame and colFrame.compareKey
                    and self.isFocusCompareCell and self.inventorySlot then
                    GearTab.AddCompareHover(
                        GearTab.MakeCompareCellKey(colFrame.compareKey, self.inventorySlot))
                end
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
                    if droppedItemLink and self.isFocusCompareCell then
                        GameTooltip:AddLine("Click to compare", 0.7, 0.7, 0.7)
                    end
                    GameTooltip:Show()
                end
            end)
            cell:SetScript("OnLeave", function(self)
                local colFrame = self:GetParent()
                if droppedItemLink and colFrame and colFrame.compareKey
                    and self.isFocusCompareCell and self.inventorySlot then
                    GearTab.RemoveCompareHover(
                        GearTab.MakeCompareCellKey(colFrame.compareKey, self.inventorySlot))
                end
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

    local upgradeMaxDelta
    local focusOpts = GU and GU.GetOptions and GU.GetOptions() or {}
    if droppedItemLink and GU and GU.GetSlotCompareDelta then
        upgradeMaxDelta = GearTab.ComputeFocusUpgradeMaxDelta(
            list,
            GearTab.GetFocusedInventorySlots(),
            focusOpts)
    end

    for c = 1, numCols do
        local entry = list[c]
        local headerCol = GearTab.GetHeaderColumnFrame(c)
        headerCol:ClearAllPoints()
        headerCol:SetPoint("TOPLEFT", headerGridContainer, "TOPLEFT", (c - 1) * dims.columnWidth + PAD - 4, 0)
        headerCol:Show()

        local compareKey = CharKey(entry.name, entry.realm)
        local columnDimmed = GearTab.GetFocusColumnDimmed(entry, upgradeMaxDelta)
        local columnAlpha = GearTab.getFocusColumnAlpha(
            columnDimmed,
            selectedCompareKey == compareKey)
        headerCol.compareKey = compareKey

        local col = GearTab.GetColumnFrame(c)
        col.compareKey = compareKey
        col:ClearAllPoints()
        col:SetPoint("TOPLEFT", gridContainer, "TOPLEFT", (c - 1) * dims.columnWidth + PAD - 4, 0)
        col:Show()

        if col.upgradeHighlight then col.upgradeHighlight:Hide() end

        local charData = DS and DS.GetCharacter and DS:GetCharacter(entry.name, entry.realm)
        local gray = GearTab.CanNeverUseCurrentItem(entry)
        for slot = 1, NUM_EQUIPMENT_SLOTS do
            local cell = col.cells[slot]
            cell.isFocusCompareCell = false
            cell.inventorySlot = nil
            if not GearTab.IsDisplaySlotVisible(slot) then
                cell:Hide()
                GearTab.layoutCellUpgradeBadge(cell, nil)
                GearTab.layoutCellFocusHighlight(cell, nil, false)
                GearTab.layoutCellCompareHover(cell, false)
            else
                local invSlot = SLOT_ORDER[slot]
                cell.inventorySlot = invSlot
                if droppedItemLink then
                    cell.isFocusCompareCell = true
                end
                local item = charData and DS.GetInventoryItem and DS:GetInventoryItem(charData, invSlot)
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
                GearTab.ApplyItemCellVisual(cell, item, gray, columnAlpha)
                cell:Show()

                if droppedItemLink then
                    local cellKind = GU and GU.GetFocusCellBadgeKind
                        and GU.GetFocusCellBadgeKind(
                            entry, charData, droppedItemLink, invSlot, focusOpts, upgradeMaxDelta)
                        or nil
                    local selected = GearTab.IsCompareCellSelected(compareKey, invSlot)
                    GearTab.layoutCellUpgradeBadge(cell, cellKind)
                    GearTab.layoutCellFocusHighlight(cell, cellKind, selected)
                    local hoverKey = GearTab.MakeCompareCellKey(compareKey, invSlot)
                    GearTab.layoutCellCompareHover(
                        cell,
                        hoveredCompareKey == hoverKey and not selected)
                else
                    GearTab.layoutCellUpgradeBadge(cell, nil)
                    GearTab.layoutCellFocusHighlight(cell, nil, false)
                    GearTab.layoutCellCompareHover(cell, false)
                end
            end
        end

        GearTab.layoutSelectionOutline(headerCol, col, nil, false)

        local RF = AltArmy.RealmFilter
        local classR, classG, classB = 1, 0.82, 0
        if gray then
            classR, classG, classB = 0.5, 0.5, 0.5
        else
            if CC and CC.getRGBOr then
                classR, classG, classB = CC.getRGBOr(entry.classFile, classR, classG, classB)
            end
        end
        headerCol.classR, headerCol.classG, headerCol.classB = classR, classG, classB
        local displayName = entry.name or "?"
        headerCol.header:SetTextColor(classR, classG, classB, columnAlpha)
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
                headerCol.scoreText:SetTextColor(1, 0.82, 0, columnAlpha)
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
                    headerCol.scoreText:SetTextColor(0.5, 0.5, 0.5, columnAlpha)
                else
                    local sr, sg, sb
                    if GearScoreMod and GearScoreMod.GetDisplayScoreColor then
                        sr, sg, sb = GearScoreMod.GetDisplayScoreColor(providerId, scoreValue)
                    end
                    if sr and sg and sb then
                        headerCol.scoreText:SetTextColor(sr, sg, sb, columnAlpha)
                    else
                        headerCol.scoreText:SetTextColor(0.9, 0.9, 0.9, columnAlpha)
                    end
                end
            end
            headerCol.scoreText:Show()
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

    GearTab.UpdateScoreSortButton()

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
            local totalChildHeight = dims.scrollableGridHeight
            local maxVertScroll = math.max(0, totalChildHeight - viewHeight)
            local savedVert = verticalScrollBar:GetValue() or 0
            verticalScrollBar:SetMinMaxValues(0, maxVertScroll)
            verticalScrollBar:SetValueStep(dims.rowHeight)
            verticalScrollBar:SetStepsPerPage(10)
            local vertScroll = Theme.ClampScroll(savedVert, maxVertScroll)
            if droppedItemLink then
                vertScroll = 0
                verticalScrollBar:Hide()
            else
                verticalScrollBar:SetShown(maxVertScroll > 0)
            end
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
    GearTab.LayoutGridHost()
    if gridContainer then
        gridContainer:SetHeight(dims.scrollableGridHeight)
    end
    if fixedHeaderRow then
        fixedHeaderRow:SetHeight(GearTab.GetPinnedHeaderHeight())
    end
    if headerGridContainer then
        headerGridContainer:SetHeight(GearTab.GetPinnedHeaderHeight())
    end
    if slotHeaderContainer then
        slotHeaderContainer:ClearAllPoints()
        slotHeaderContainer:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", 0, 0)
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
        horizontalScroll:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", SLOT_LABEL_WIDTH, 0)
        horizontalScroll:SetPoint("TOPRIGHT", verticalScrollChild, "TOPRIGHT", 0, 0)
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

if ItemStats and ItemStats.SetOnUpdated then
    ItemStats.SetOnUpdated(function(itemId)
        if not droppedItemLink then return end
        local linkId = tonumber(tostring(droppedItemLink):match("item:(%d+)"))
        if linkId ~= itemId then return end
        if frame.RefreshGrid then
            frame:RefreshGrid()
        end
    end)
end

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
settingsPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
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

    GearTab.ApplyGearLayoutHostBounds()
    GearTab.LayoutGearPanels()

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
        GearTab.ApplyGearLayoutHostBounds()
        GearTab.LayoutGearPanels()
        if frame.RefreshGrid then frame:RefreshGrid() end
    elseif droppedItemLink then
        GearTab.LayoutGearPanels()
    end
end)
