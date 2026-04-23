-- AltArmy TBC — Cooldowns tab: profession cooldown overview.

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Cooldowns
if not frame then return end

local PAD = 4
-- Match TabSearch.lua result rows (items / recipes): row height, fonts, flush columns, icon scale.
local ROW_HEIGHT = 18
local HEADER_HEIGHT = 18
local HEADER_ROW_GAP = 6 -- TabSearch.lua section headers use this gap above first row
local MAT_ICON_SIZE = 14 -- TabSearch OVERLAY_ICON_SIZE (inline "|Tpath:0|t" uses ~14px height)
local REFRESH_INTERVAL = 1

local CD = AltArmy.CooldownData
local DS = AltArmy.DataStore
local RF = AltArmy.RealmFilter
if not CD or not DS then return end

CD.EnsureCooldownOptions()

local function RecipeIconTexture(spellId, charTable)
    local fallback = "Interface\\Icons\\INV_Misc_QuestionMark"
    local resultItemID
    if charTable and charTable.Professions and spellId then
        for _, pdata in pairs(charTable.Professions) do
            local rec = pdata and pdata.Recipes and pdata.Recipes[spellId]
            if rec and rec.resultItemID then
                resultItemID = rec.resultItemID
                break
            end
        end
    end
    if resultItemID and GetItemInfo then
        local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(resultItemID)
        if tex then return tex end
    end
    if spellId and GetSpellInfo then
        local _, _, tex = GetSpellInfo(spellId)
        if tex and tex ~= "" then return tex end
    end
    if spellId and GetItemInfo then
        local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(spellId)
        if tex then return tex end
    end
    return fallback
end

local function FormatRecipeColumnText(spellId, title, charTable)
    local icon = RecipeIconTexture(spellId, charTable)
    -- Match TabSearch "|Ttexture:0|t " …
    return ("|T%s:0|t %s"):format(icon, title or "")
end

--- GameTooltip:AddLine accepts inline |T…|t textures in the text.
local function TooltipReagentLine(itemID, label, have, need)
    local tex = "Interface\\Icons\\INV_Misc_QuestionMark"
    if itemID and GetItemInfo then
        local t = select(10, GetItemInfo(itemID))
        if t and t ~= "" then
            tex = t
        end
    end
    local prefix = ("|T%s:%d:%d|t "):format(tex, MAT_ICON_SIZE, MAT_ICON_SIZE)
    return prefix .. string.format("%s: %d / %d", label, have, need)
end

local function AccountHasMultipleRealms()
    local n = 0
    for _ in pairs(DS:GetRealms()) do
        n = n + 1
        if n > 1 then return true end
    end
    return false
end

local colWidths = {
    Category = 175,
    Character = 190,
    Mats = 44,
    Time = 128,
}

local SORT_KEYS_ORDER = { "recipe", "character", "mats", "time" }
local SORT_HEADER_LABEL = {
    recipe = "Recipe",
    character = "Character",
    mats = "Mats",
    time = "Time Remaining",
}
local SORT_COL_WIDTH = {
    recipe = colWidths.Category,
    character = colWidths.Character,
    mats = colWidths.Mats,
    time = colWidths.Time,
}
local SORT_HEADER_JUSTIFY = {
    recipe = "LEFT",
    character = "LEFT",
    mats = "CENTER",
    time = "RIGHT",
}

local currentSortKey = "recipe"
local sortAscending = true

local function GetCooldownListSort()
    CD.EnsureCooldownOptions()
    return AltArmyTBC_Options.cooldowns
end

local function SyncSortFromSaved()
    GetCooldownListSort()
    local cd = AltArmyTBC_Options.cooldowns
    currentSortKey = cd.listSortKey
    sortAscending = cd.listSortAscending
end

local RefreshList -- forward-declared; header buttons call this after sort changes
local headerButtons = {}

local function UpdateHeaderSortIndicators()
    for _, sk in ipairs(SORT_KEYS_ORDER) do
        local btn = headerButtons and headerButtons[sk]
        if btn and btn.label then
            local base = SORT_HEADER_LABEL[sk]
            local label = base
            if sk == currentSortKey then
                label = base .. (sortAscending and " ^" or " v")
            end
            btn.label:SetText(label)
        end
    end
end

local totalColWidth = colWidths.Category + colWidths.Character + colWidths.Mats + colWidths.Time

local headerRow = CreateFrame("Frame", nil, frame)
headerRow:SetHeight(HEADER_HEIGHT)
headerRow:SetWidth(totalColWidth)
headerRow:SetFrameLevel((frame:GetFrameLevel() or 0) + 10)
headerRow:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD)

local hx = 0
for _, sk in ipairs(SORT_KEYS_ORDER) do
    local btn = CreateFrame("Button", nil, headerRow)
    btn:SetPoint("TOPLEFT", headerRow, "TOPLEFT", hx, 0)
    btn:SetSize(SORT_COL_WIDTH[sk], HEADER_HEIGHT)
    btn:EnableMouse(true)
    btn:RegisterForClicks("LeftButtonUp")
    local sortKeyForClick = sk
    btn:SetScript("OnClick", function()
        if currentSortKey == sortKeyForClick then
            sortAscending = not sortAscending
        else
            currentSortKey = sortKeyForClick
            sortAscending = true
        end
        local cd = GetCooldownListSort()
        cd.listSortKey = currentSortKey
        cd.listSortAscending = sortAscending
        UpdateHeaderSortIndicators()
        if RefreshList then
            RefreshList()
        end
    end)
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", btn, "LEFT", 0, 0)
    label:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
    label:SetHeight(HEADER_HEIGHT)
    label:SetJustifyH(SORT_HEADER_JUSTIFY[sk] or "LEFT")
    label:SetText(SORT_HEADER_LABEL[sk])
    btn.label = label
    headerButtons[sk] = btn
    hx = hx + SORT_COL_WIDTH[sk]
end

local rowParent = CreateFrame("Frame", nil, frame)
rowParent:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD - HEADER_HEIGHT - HEADER_ROW_GAP)
rowParent:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - 16, PAD)

local scroll = CreateFrame("ScrollFrame", nil, rowParent)
scroll:SetPoint("TOPLEFT", rowParent, "TOPLEFT", 0, 0)
scroll:SetPoint("BOTTOMRIGHT", rowParent, "BOTTOMRIGHT", -14, 0)

local scrollBar = CreateFrame("Slider", nil, rowParent)
scrollBar:SetOrientation("VERTICAL")
scrollBar:SetPoint("TOPRIGHT", rowParent, "TOPRIGHT", 0, 0)
scrollBar:SetPoint("BOTTOMRIGHT", rowParent, "BOTTOMRIGHT", 0, 0)
scrollBar:SetWidth(14)
scrollBar:SetMinMaxValues(0, 0)
scrollBar:SetValue(0)
scrollBar:SetValueStep(ROW_HEIGHT)

local sbThumb = scrollBar:CreateTexture(nil, "OVERLAY")
sbThumb:SetTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
sbThumb:SetSize(18, 24)
scrollBar:SetThumbTexture(sbThumb)

local scrollChild = CreateFrame("Frame", nil, scroll)
scroll:SetScrollChild(scrollChild)

scrollBar:SetScript("OnValueChanged", function(_, v)
    scroll:SetVerticalScroll(v)
end)

scroll:SetScript("OnMouseWheel", function(_, delta)
    local cur = scrollBar:GetValue()
    local lo, hi = scrollBar:GetMinMaxValues()
    scrollBar:SetValue(math.max(lo, math.min(hi, cur - delta * ROW_HEIGHT * 3)))
end)

scroll:SetScript("OnSizeChanged", function(s, w)
    scrollChild:SetWidth(math.max(1, (w or s:GetWidth()) - 18))
end)

local rowPool = {}
local activeRows = {}

local function PoolRow()
    local row = table.remove(rowPool)
    if not row then
        row = CreateFrame("Button", nil, scrollChild)
        row:SetHeight(ROW_HEIGHT)

        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

        local cat = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        cat:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        cat:SetSize(colWidths.Category, ROW_HEIGHT)
        cat:SetJustifyH("LEFT")
        cat:SetJustifyV("MIDDLE")
        cat:SetNonSpaceWrap(false)
        row.catCell = cat

        local char = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        char:SetPoint("TOPLEFT", cat, "TOPRIGHT", 0, 0)
        char:SetSize(colWidths.Character, ROW_HEIGHT)
        char:SetJustifyH("LEFT")
        char:SetJustifyV("MIDDLE")
        char:SetNonSpaceWrap(false)
        char:SetWordWrap(false)
        row.charCell = char

        -- Fixed-height cell so the waiting icon stays vertically centered; centering on a hidden
        -- FontString used an unstable height and misaligned the ? on some rows.
        local matSlot = CreateFrame("Frame", nil, row)
        matSlot:SetSize(colWidths.Mats, ROW_HEIGHT)
        matSlot:SetPoint("TOPLEFT", char, "TOPRIGHT", 0, 0)

        local matIcon = matSlot:CreateTexture(nil, "ARTWORK")
        matIcon:SetSize(MAT_ICON_SIZE, MAT_ICON_SIZE)
        matIcon:SetPoint("CENTER", matSlot, "CENTER", 0, 0)
        row.matIcon = matIcon

        local matNum = matSlot:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        matNum:SetAllPoints(matSlot)
        matNum:SetJustifyH("CENTER")
        matNum:SetJustifyV("MIDDLE")
        matNum:SetNonSpaceWrap(false)
        row.matCountLabel = matNum

        local tm = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        tm:SetPoint("TOPLEFT", matSlot, "TOPRIGHT", 0, 0)
        tm:SetSize(colWidths.Time, ROW_HEIGHT)
        tm:SetJustifyH("RIGHT")
        tm:SetJustifyV("MIDDLE")
        tm:SetNonSpaceWrap(false)
        row.timeCell = tm

        row:SetScript("OnEnter", function(self)
            if not self.spellId then
                return
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local link = _G.GetSpellLink and _G.GetSpellLink(self.spellId)
            if link and link ~= "" then
                GameTooltip:SetHyperlink(link)
            else
                if GameTooltip_Clear then
                    GameTooltip_Clear(GameTooltip)
                elseif GameTooltip.ClearLines then
                    GameTooltip:ClearLines()
                end
                local title = _G.GetSpellInfo and _G.GetSpellInfo(self.spellId)
                GameTooltip:AddLine(title or ("Spell " .. tostring(self.spellId)), 1, 1, 1)
            end
            -- Small gap before custom material summary (between default spell tooltip and AltArmy lines).
            GameTooltip:AddLine(" ", 1, 1, 1)
            local charTable = self.charTableRef
            local qty = nil
            if charTable and CD.GetMaxCraftableQuantity then
                qty = CD.GetMaxCraftableQuantity(charTable, self.spellId, function(ch, itemId)
                    return DS:GetContainerItemCount(ch, itemId)
                end)
            end
            if qty == nil then
                GameTooltip:AddLine(
                    "Open this profession's tradeskill window once to load material counts.",
                    0.75,
                    0.75,
                    0.75,
                    true
                )
            end
            if charTable and CD.GetReagentHaveCounts then
                local rrows = CD.GetReagentHaveCounts(charTable, self.spellId, function(ch, itemId)
                    return DS:GetContainerItemCount(ch, itemId)
                end)
                for _, rr in ipairs(rrows) do
                    local have, need = rr.have or 0, rr.need or 0
                    local label
                    if GetItemInfo then
                        local itemName = GetItemInfo(rr.itemID)
                        label = itemName or ("Item " .. tostring(rr.itemID))
                    else
                        label = "Item " .. tostring(rr.itemID)
                    end
                    local color = have >= need and { 0, 1, 0 } or { 1, 0.3, 0.3 }
                    GameTooltip:AddLine(
                        TooltipReagentLine(rr.itemID, label, have, need),
                        color[1],
                        color[2],
                        color[3],
                        true
                    )
                end
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
    row:Show()
    return row
end

local function ReleaseRows()
    for _, r in ipairs(activeRows) do
        r:Hide()
        r:SetParent(scrollChild)
        rowPool[#rowPool + 1] = r
    end
    activeRows = {}
end

local function CompareCooldownRows(a, b)
    local asc = sortAscending

    local function lessStr(sa, sb)
        if sa == sb then return nil end
        if asc then
            return sa < sb
        end
        return sa > sb
    end

    local function lessNum(na, nb)
        if na == nb then return nil end
        if asc then
            return na < nb
        end
        return na > nb
    end

    if currentSortKey == "recipe" then
        local r = lessStr(a.categoryTitle or "", b.categoryTitle or "")
        if r ~= nil then return r end
    elseif currentSortKey == "character" then
        local r = lessStr(a.name or "", b.name or "")
        if r ~= nil then return r end
        r = lessStr(a.realm or "", b.realm or "")
        if r ~= nil then return r end
    elseif currentSortKey == "mats" then
        local qa, qb = a._sortCraftQty, b._sortCraftQty
        if qa ~= nil or qb ~= nil then
            if qa == nil then
                return false
            elseif qb == nil then
                return true
            else
                local r = lessNum(qa, qb)
                if r ~= nil then return r end
            end
        end
    elseif currentSortKey == "time" then
        local ea, eb = a.expiresUnix, b.expiresUnix
        if ea ~= nil or eb ~= nil then
            if ea == nil then
                return false
            elseif eb == nil then
                return true
            else
                local r = lessNum(ea, eb)
                if r ~= nil then return r end
            end
        end
    end

    local r = lessStr(a.categoryTitle or "", b.categoryTitle or "")
    if r ~= nil then return r end
    r = lessStr(a.name or "", b.name or "")
    if r ~= nil then return r end
    r = lessStr(a.realm or "", b.realm or "")
    if r ~= nil then return r end
    return false
end

RefreshList = function()
    ReleaseRows()
    CD.EnsureCooldownOptions()
    local opts = AltArmyTBC_Options and AltArmyTBC_Options.cooldowns
    if not opts then return end

    local now = time and time() or 0
    local rows = CD.BuildRows(DS, opts, now)

    for _, rd in ipairs(rows) do
        local ch = DS:GetCharacter(rd.charKeyName, rd.realm)
        rd._sortCraftQty = nil
        if ch and rd.spellId and CD.GetMaxCraftableQuantity then
            rd._sortCraftQty = CD.GetMaxCraftableQuantity(ch, rd.spellId, function(charTable, itemId)
                return DS:GetContainerItemCount(charTable, itemId)
            end)
        end
    end

    table.sort(rows, CompareCooldownRows)

    local totalH = math.max(1, #rows) * ROW_HEIGHT
    scrollChild:SetSize(totalColWidth, totalH)

    local y = 0
    for _, rd in ipairs(rows) do
        local row = PoolRow()
        activeRows[#activeRows + 1] = row
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, y)
        y = y - ROW_HEIGHT

        row.charTableRef = DS:GetCharacter(rd.charKeyName, rd.realm)
        row.catCell:SetText(FormatRecipeColumnText(rd.spellId, rd.categoryTitle or "", row.charTableRef))
        local _, classFile = DS:GetCharacterClass(row.charTableRef)
        row.charCell:SetTextColor(1, 1, 1, 1)
        local showRealm = AccountHasMultipleRealms() and rd.realm and rd.realm ~= ""
        local charText = RF and RF.formatColoredCharacterNameRealm
            and RF.formatColoredCharacterNameRealm(rd.name or "", rd.realm, showRealm, classFile)
            or ((rd.name or "") .. (showRealm and (" — " .. rd.realm) or ""))
        row.charCell:SetText(charText)
        row.timeCell:SetText(rd.timeText or "")
        local expUnix = rd.expiresUnix
        if expUnix == nil then
            row.timeCell:SetTextColor(1, 1, 0.4, 1)
        elseif expUnix <= now then
            row.timeCell:SetTextColor(0, 1, 0, 1)
        else
            row.timeCell:SetTextColor(1, 0.35, 0.35, 1)
        end
        row.spellId = rd.spellId

        local craftQty = nil
        if row.charTableRef and rd.spellId then
            craftQty = CD.GetMaxCraftableQuantity(row.charTableRef, rd.spellId, function(ch, itemId)
                return DS:GetContainerItemCount(ch, itemId)
            end)
        end
        if craftQty == nil then
            row.matCountLabel:Hide()
            row.matIcon:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Waiting")
            row.matIcon:Show()
        elseif craftQty >= 1 then
            row.matIcon:Hide()
            local label = craftQty >= 100 and "99+x" or (tostring(craftQty) .. "x")
            row.matCountLabel:SetText(label)
            row.matCountLabel:SetTextColor(0, 1, 0, 1)
            row.matCountLabel:Show()
        else
            row.matIcon:Hide()
            row.matCountLabel:SetText("0x")
            row.matCountLabel:SetTextColor(1, 0.25, 0.25, 1)
            row.matCountLabel:Show()
        end
    end

    local viewH = scroll:GetHeight()
    if viewH <= 0 then viewH = 1 end
    local maxScroll = math.max(0, totalH - viewH)
    scrollBar:SetMinMaxValues(0, maxScroll)
    scrollBar:SetShown(maxScroll > 1)
end

frame.RefreshCooldownList = RefreshList

frame:SetScript("OnShow", function()
    SyncSortFromSaved()
    UpdateHeaderSortIndicators()
    RefreshList()
end)

local upd = 0
frame:SetScript("OnUpdate", function(_, dt)
    if AltArmy.CurrentTab ~= "Cooldowns" then return end
    upd = upd + dt
    if upd >= REFRESH_INTERVAL then
        upd = 0
        RefreshList()
    end
end)
