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
local SP = AltArmy.StockpilePlan
if not CD or not DS then return end
if not SP or not SP.BuildItemPlan then return end

CD.EnsureCooldownOptions()

local function ChatInfo(msg)
    local chat = _G.DEFAULT_CHAT_FRAME
    if chat and chat.AddMessage and msg and msg ~= "" then
        chat:AddMessage(string.format("|cfffecc00AltArmy|r %s", msg))
    end
end

local function GetCurrentIdentity()
    local name = (UnitName and UnitName("player")) or (GetUnitName and GetUnitName("player")) or ""
    local realm = (GetRealmName and GetRealmName()) or ""
    return name, realm
end

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
local ComputeMaxCraftsWithAttachmentCap -- forward-declared; used by row click
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

-- ---------------------------------------------------------------------------
-- Send Stockpile popover (row click)
-- ---------------------------------------------------------------------------

local stockpilePopover = CreateFrame("Frame", nil, frame)
stockpilePopover:Hide()
stockpilePopover:SetFrameStrata("DIALOG")
stockpilePopover:SetFrameLevel((frame:GetFrameLevel() or 0) + 200)
stockpilePopover:SetSize(320, 110)
stockpilePopover:EnableMouse(true)
stockpilePopover:SetClampedToScreen(true)

-- Always-opaque background (some clients/skins disable backdrops)
local stockpilePopoverBg = stockpilePopover:CreateTexture(nil, "BACKGROUND")
stockpilePopoverBg:SetAllPoints(stockpilePopover)
stockpilePopoverBg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
stockpilePopoverBg:SetVertexColor(0.06, 0.06, 0.08, 1)

if stockpilePopover.SetBackdrop then
    stockpilePopover:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    stockpilePopover:SetBackdropColor(0.06, 0.06, 0.08, 1)
    if stockpilePopover.SetBackdropBorderColor then
        stockpilePopover:SetBackdropBorderColor(0.85, 0.82, 0.55, 1)
    end
end

-- Click-catcher overlay: click outside popover to close it.
local stockpilePopoverOverlay = CreateFrame("Frame", nil, UIParent)
stockpilePopoverOverlay:Hide()
stockpilePopoverOverlay:SetAllPoints(UIParent)
stockpilePopoverOverlay:SetFrameStrata("DIALOG")
stockpilePopoverOverlay:SetFrameLevel(stockpilePopover:GetFrameLevel() - 1)
stockpilePopoverOverlay:EnableMouse(true)

local popTitle = stockpilePopover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
popTitle:SetPoint("TOPLEFT", stockpilePopover, "TOPLEFT", 12, -10)
popTitle:SetText("Send Stockpile")

local popValueLabel = stockpilePopover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
popValueLabel:SetPoint("TOPRIGHT", stockpilePopover, "TOPRIGHT", -12, -12)
popValueLabel:SetText("")

local popSlider = CreateFrame("Slider", nil, stockpilePopover)
popSlider:SetPoint("TOPLEFT", popTitle, "BOTTOMLEFT", 6, -16)
popSlider:SetPoint("TOPRIGHT", stockpilePopover, "TOPRIGHT", -18, -32)
popSlider:SetHeight(16)
popSlider:SetOrientation("HORIZONTAL")
popSlider:SetMinMaxValues(0, 1)
popSlider:SetValueStep(1)
popSlider:SetObeyStepOnDrag(true)
popSlider:EnableMouse(true)
local popThumb = popSlider:CreateTexture(nil, "ARTWORK")
popThumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
popThumb:SetSize(16, 16)
popSlider:SetThumbTexture(popThumb)
local popBar = popSlider:CreateTexture(nil, "BACKGROUND")
popBar:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
popBar:SetVertexColor(0.35, 0.35, 0.45, 1)
popBar:SetHeight(8)
popBar:SetPoint("LEFT", popSlider, "LEFT", 0, 0)
popBar:SetPoint("RIGHT", popSlider, "RIGHT", 0, 0)

local popMinLabel = stockpilePopover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
popMinLabel:SetPoint("TOPLEFT", popSlider, "BOTTOMLEFT", -6, -6)
popMinLabel:SetText("")

local popMaxLabel = stockpilePopover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
popMaxLabel:SetPoint("TOPRIGHT", popSlider, "BOTTOMRIGHT", 6, -6)
popMaxLabel:SetText("")

local popCancel = CreateFrame("Button", nil, stockpilePopover, "UIPanelButtonTemplate")
popCancel:SetSize(90, 20)
popCancel:SetPoint("BOTTOMRIGHT", stockpilePopover, "BOTTOMRIGHT", -12, 12)
popCancel:SetText("Cancel")

local popOk = CreateFrame("Button", nil, stockpilePopover, "UIPanelButtonTemplate")
popOk:SetSize(90, 20)
popOk:SetPoint("RIGHT", popCancel, "LEFT", -8, 0)
popOk:SetText("Okay")
popOk:Disable()

local popCtx = nil
local function HideStockpilePopover()
    stockpilePopover:Hide()
    stockpilePopoverOverlay:Hide()
    popCtx = nil
end
popCancel:SetScript("OnClick", HideStockpilePopover)

local function IsMailboxActuallyOpen()
    local mf = _G.MailFrame
    if mf and mf.IsShown and mf:IsShown() then
        return true
    end
    local inbox = _G.InboxFrame
    if inbox and inbox.IsShown and inbox:IsShown() then
        return true
    end
    return false
end

local function SyncPopoverOkState()
    if not popCtx then
        popOk:Disable()
        return
    end
    local v = tonumber(popSlider:GetValue()) or popCtx.minCrafts or 0
    if v > (popCtx.minCrafts or 0) then
        popOk:Enable()
    else
        popOk:Disable()
    end
end
popSlider:SetScript("OnValueChanged", function(_, value)
    if not popCtx then return end
    local v = math.floor((tonumber(value) or 0) + 0.5)
    popValueLabel:SetText("Will have: " .. tostring(v) .. "x")
    SyncPopoverOkState()
end)

local function RunSendStockpile(_ctx)
    -- Implemented in a later step (mail compose + attachment engine).
end
popOk:SetScript("OnClick", function()
    if not popCtx then return end
    local v = tonumber(popSlider:GetValue()) or popCtx.minCrafts or 0
    if v <= (popCtx.minCrafts or 0) then return end
    popCtx.requestedCrafts = math.floor(v + 0.5)
    local ctx = popCtx
    HideStockpilePopover()
    RunSendStockpile(ctx)
end)

local function ShowStockpilePopover(anchorRow, ctx)
    popCtx = ctx
    stockpilePopover:ClearAllPoints()
    -- Anchor using UIParent-relative screen coords so it survives list refresh/row pooling.
    local left = anchorRow and anchorRow.GetLeft and anchorRow:GetLeft() or nil
    local bottom = anchorRow and anchorRow.GetBottom and anchorRow:GetBottom() or nil
    local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    if scale <= 0 then scale = 1 end
    if left and bottom then
        stockpilePopover:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale + 6, bottom / scale - 2)
    else
        local cx, cy = GetCursorPosition()
        stockpilePopover:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / scale + 6, cy / scale - 2)
    end
    local minV = tonumber(ctx.minCrafts) or 0
    local maxV = tonumber(ctx.maxCrafts) or minV
    if maxV < minV then maxV = minV end
    popSlider:SetMinMaxValues(minV, maxV)

    local function ColorNameByClass(name, classFile)
        local base = name or "?"
        local rc = RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]
        if rc and rc.r and rc.g and rc.b then
            local r = math.floor(rc.r * 255 + 0.5)
            local g = math.floor(rc.g * 255 + 0.5)
            local b = math.floor(rc.b * 255 + 0.5)
            return string.format("|cff%02x%02x%02x%s|r", r, g, b, base)
        end
        return base
    end

    local titleName = ctx.targetDisplayName or ctx.targetName or "?"
    local classFile = ctx.targetClassFile
    popTitle:SetText("Send Stockpile to " .. ColorNameByClass(titleName, classFile))

    local defaultV = minV
    if maxV > minV then
        defaultV = math.min(maxV, minV + 1)
    end
    popSlider:SetValue(defaultV)
    popMinLabel:SetText("Min: " .. tostring(minV))
    popMaxLabel:SetText("Max: " .. tostring(maxV))
    popValueLabel:SetText("Will have: " .. tostring(defaultV) .. "x")
    SyncPopoverOkState()
    stockpilePopoverOverlay:Show()
    stockpilePopover:Show()
end

stockpilePopoverOverlay:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" then return end
    if stockpilePopover and stockpilePopover.IsShown and stockpilePopover:IsShown() then
        HideStockpilePopover()
    end
end)

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
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
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
                    if DS.GetTotalItemCount then
                        return DS:GetTotalItemCount(ch, itemId)
                    end
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
                local showRealm = (AltArmy.GlobalRealmFilter and AltArmy.GlobalRealmFilter.Get() == "all")
                    and AccountHasMultipleRealms()
                    and charTable.realm
                    and charTable.realm ~= ""
                local _, classFile = DS:GetCharacterClass(charTable)
                local displayName = charTable.name or "?"
                local displayRealm = charTable.realm or ""
                local nameStr = RF and RF.formatColoredCharacterNameRealm
                    and RF.formatColoredCharacterNameRealm(displayName, displayRealm, showRealm, classFile)
                    or displayName
                GameTooltip:AddLine(nameStr .. " has:", 1, 1, 1, true)
                local rrows = CD.GetReagentHaveCounts(charTable, self.spellId, function(ch, itemId)
                    if DS.GetTotalItemCount then
                        return DS:GetTotalItemCount(ch, itemId)
                    end
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

        row:RegisterForClicks("LeftButtonUp")
        row:SetScript("OnClick", function(self)
            if stockpilePopover and stockpilePopover:IsShown() then
                HideStockpilePopover()
            end
            if not self or not self.rowData or not self.spellId then return end
            local rd = self.rowData

            local curName, curRealm = GetCurrentIdentity()
            if not curName or curName == "" then return end
            if (rd.charKeyName == curName) and (rd.realm == curRealm) then
                return
            end

            if DS.IsMailOpen and not DS:IsMailOpen() then
                ChatInfo("Visit a mailbox and click again to send stockpile")
                return
            end
            if not IsMailboxActuallyOpen() then
                ChatInfo("Visit a mailbox and click again to send stockpile")
                return
            end

            local currentChar = DS.GetCurrentCharacter and DS:GetCurrentCharacter() or nil
            local targetChar = self.charTableRef
            if not currentChar or not targetChar then return end

            local getTargetCount = function(ch, itemId)
                return DS.GetTotalItemCount and DS:GetTotalItemCount(ch, itemId) or DS:GetContainerItemCount(ch, itemId)
            end
            local getSourceCount = function(ch, itemId)
                if DS.GetBagItemCount then
                    return DS:GetBagItemCount(ch, itemId)
                end
                return DS:GetContainerItemCount(ch, itemId)
            end

            local minCrafts = CD.GetMaxCraftableQuantity
                and CD.GetMaxCraftableQuantity(targetChar, self.spellId, getTargetCount)
            if minCrafts == nil then
                ChatInfo("Open this profession's tradeskill window once to load material counts.")
                return
            end
            local maxCrafts = CD.GetMaxCraftableQuantityAfterTransfer
                and CD.GetMaxCraftableQuantityAfterTransfer(
                    targetChar,
                    currentChar,
                    self.spellId,
                    getTargetCount,
                    getSourceCount
                )
            if maxCrafts == nil then
                ChatInfo("Open this profession's tradeskill window once to load material counts.")
                return
            end
            local cappedMax = ComputeMaxCraftsWithAttachmentCap(
                targetChar,
                currentChar,
                self.spellId,
                minCrafts,
                maxCrafts
            )
            if cappedMax <= minCrafts then
                ChatInfo(string.format("Not enough items to increase %s's stockpile", rd.name or "?"))
                return
            end

            if rd.realm ~= curRealm then
                ChatInfo("Can't send stockpile across realms")
                return
            end

            ShowStockpilePopover(self, {
                spellId = self.spellId,
                targetName = rd.charKeyName,
                targetDisplayName = rd.name,
                targetRealm = rd.realm,
                targetClassFile = select(2, DS:GetCharacterClass(targetChar)),
                minCrafts = minCrafts,
                maxCrafts = cappedMax,
            })
        end)
    end
    row:Show()
    return row
end

-- ---------------------------------------------------------------------------
-- Mail compose + attachments
-- ---------------------------------------------------------------------------

local ATTACHMENTS_MAX_SEND = 12

local function IterateLiveBagSlots(callback)
    local maxBagId = DS.NUM_BAG_SLOTS or 4
    local getSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local getInfo = (C_Container and C_Container.GetContainerItemInfo) or GetContainerItemInfo
    local getLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
    if not getSlots or not getInfo then return end
    for bagID = 0, maxBagId do
        local numSlots = getSlots(bagID) or 0
        for slot = 1, numSlots do
            local itemID, count
            if C_Container and C_Container.GetContainerItemInfo then
                local info = getInfo(bagID, slot)
                itemID = info and info.itemID or nil
                -- Some clients expose quantity instead of stackCount
                count = info and (info.stackCount or info.quantity) or nil
            else
                local link = getLink and getLink(bagID, slot)
                itemID = link and tonumber(link:match("item:(%d+)")) or nil
                local _, c = getInfo(bagID, slot)
                count = c
            end
            if itemID and itemID > 0 then
                local link = getLink and getLink(bagID, slot) or nil
                if callback(bagID, slot, itemID, (count and count > 0) and count or 1, link) then
                    return
                end
            end
        end
    end
end

local function GetLiveBagSlotCount(bagID, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        local c = info and (info.stackCount or info.quantity)
        if type(c) == "number" and c > 0 then
            return c
        end
        return 0
    end
    if GetContainerItemInfo then
        local _, count = GetContainerItemInfo(bagID, slot)
        if type(count) == "number" and count > 0 then
            return count
        end
        return 0
    end
    return 0
end

local function FindFirstEmptyBagSlot()
    local maxBagId = DS.NUM_BAG_SLOTS or 4
    if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo then
        for bagID = 0, maxBagId do
            local n = C_Container.GetContainerNumSlots(bagID) or 0
            for slot = 1, n do
                local info = C_Container.GetContainerItemInfo(bagID, slot)
                if not info or not info.itemID then
                    return bagID, slot
                end
            end
        end
        return nil, nil
    end
    if GetContainerNumSlots and GetContainerItemLink then
        for bagID = 0, maxBagId do
            local n = GetContainerNumSlots(bagID) or 0
            for slot = 1, n do
                local link = GetContainerItemLink(bagID, slot)
                if not link then
                    return bagID, slot
                end
            end
        end
    end
    return nil, nil
end

local function CountEmptyBagSlotsLive()
    local maxBagId = DS.NUM_BAG_SLOTS or 4
    local total = 0
    if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo then
        for bagID = 0, maxBagId do
            local n = C_Container.GetContainerNumSlots(bagID) or 0
            for slot = 1, n do
                local info = C_Container.GetContainerItemInfo(bagID, slot)
                if not info or not info.itemID then
                    total = total + 1
                end
            end
        end
        return total
    end
    if GetContainerNumSlots and GetContainerItemLink then
        for bagID = 0, maxBagId do
            local n = GetContainerNumSlots(bagID) or 0
            for slot = 1, n do
                if not GetContainerItemLink(bagID, slot) then
                    total = total + 1
                end
            end
        end
        return total
    end
    return 0
end

local function GetItemStackLimit(itemID)
    if type(itemID) ~= "number" then
        return 20
    end
    local cItem = _G.C_Item
    if cItem and cItem.GetItemMaxStackSizeByID then
        local n = cItem.GetItemMaxStackSizeByID(itemID)
        if type(n) == "number" and n > 0 then
            return n
        end
    end
    if GetItemInfo then
        local maxStack = select(8, GetItemInfo(itemID))
        if type(maxStack) == "number" and maxStack > 0 then
            return maxStack
        end
    end
    return 20
end

local function CollectLiveStacksByItemID()
    local out = {}
    IterateLiveBagSlots(function(bagID, slot, itemID, count)
        out[itemID] = out[itemID] or {}
        -- count can differ by client API; always re-check live count at attach time
        out[itemID][#out[itemID] + 1] = { bagID = bagID, slot = slot, count = count }
        return false
    end)
    return out
end

ComputeMaxCraftsWithAttachmentCap = function(targetChar, sourceChar, spellId, minCrafts, maxCrafts)
    local minV = tonumber(minCrafts) or 0
    local maxV = tonumber(maxCrafts) or minV
    if maxV < minV then maxV = minV end
    if maxV == minV then return minV end

    local getTargetCount = function(ch, itemId)
        return DS.GetTotalItemCount and DS:GetTotalItemCount(ch, itemId) or DS:GetContainerItemCount(ch, itemId)
    end
    local getSourceCount = function(ch, itemId)
        return DS.GetBagItemCount and DS:GetBagItemCount(ch, itemId) or DS:GetContainerItemCount(ch, itemId)
    end

    local stacksById = CollectLiveStacksByItemID()
    local emptySlotsAvailable0 = CountEmptyBagSlotsLive()

    local function fits(crafts)
        local sendPlan = CD.GetReagentSendPlan and CD.GetReagentSendPlan(
            targetChar,
            sourceChar,
            spellId,
            crafts,
            getTargetCount,
            getSourceCount
        )
        if not sendPlan then
            return false
        end
        local totalAttachments = 0
        local emptySlotsAvailable = emptySlotsAvailable0
        for _, rr in ipairs(sendPlan) do
            local needToSend = rr.requiredToSend or 0
            if needToSend > 0 then
                local plan = SP.BuildItemPlan(needToSend, stacksById[rr.itemID] or {}, {
                    allowMerge = true,
                    preferExact = true,
                    stackLimit = GetItemStackLimit(rr.itemID),
                    maxAttachments = ATTACHMENTS_MAX_SEND,
                    emptySlotsAvailable = emptySlotsAvailable,
                })
                if not plan or not plan.ok then
                    return false
                end
                totalAttachments = totalAttachments + (plan.attachments or 0)
                if totalAttachments > ATTACHMENTS_MAX_SEND then
                    return false
                end
                for _, op in ipairs(plan.ops or {}) do
                    if op.op == "split_attach" then
                        emptySlotsAvailable = emptySlotsAvailable - 1
                        if emptySlotsAvailable < 0 then
                            return false
                        end
                    end
                end
            end
        end
        return true
    end

    local lo, hi = minV, maxV
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if fits(mid) then
            lo = mid
        else
            hi = mid - 1
        end
    end
    return lo
end

local function EnsureSendMailTab()
    local tab2 = _G.MailFrameTab2
    if tab2 and tab2.Click then
        tab2:Click()
        return true
    end
    local smf = _G.SendMailFrame
    if smf and smf.Show then
        smf:Show()
        return true
    end
    return false
end

local function SetSendMailRecipient(name)
    if not name or name == "" then return false end
    local eb = _G.SendMailNameEditBox
    if eb and eb.SetText then
        eb:SetText(name)
        if eb.HighlightText then
            eb:HighlightText()
        end
        return true
    end
    return false
end

local function FormatMailRecipient(name, realm)
    if not name or name == "" then return "" end
    if realm and realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

local function FirstFreeAttachmentIndex()
    local getSendMailItem = _G.GetSendMailItem
    if not getSendMailItem then
        return 1
    end
    for i = 1, ATTACHMENTS_MAX_SEND do
        local name = getSendMailItem(i)
        if not name then
            return i
        end
    end
    return nil
end

-- Sequential attach state machine (split -> place -> wait unlock -> attach).
local stockpileAttachSeq = {
    active = false,
    queue = nil,
    queueIndex = 1,
    phase = nil, -- "waitingPlacedUnlock"
    bagID = nil, -- placed split slot bag
    slot = nil, -- placed split slot slot
    expectedCount = nil, -- optional: when waiting on a merged stack to reach a count
    startedAt = 0,
    lastLogAt = 0,
}

local function DebugIsSlotLocked(bagID, slot)
    local cItem = _G.C_Item
    local itemLoc = _G.ItemLocation
    if not (cItem and itemLoc and cItem.IsLocked and cItem.DoesItemExist) then
        return false
    end
    local loc = itemLoc:CreateFromBagAndSlot(bagID, slot)
    if not cItem.DoesItemExist(loc) then
        return false
    end
    return cItem.IsLocked(loc) == true
end

local function AbortAttachSeq(msg)
    stockpileAttachSeq.active = false
    stockpileAttachSeq.queue = nil
    stockpileAttachSeq.queueIndex = 1
    stockpileAttachSeq.phase = nil
    stockpileAttachSeq.bagID = nil
    stockpileAttachSeq.slot = nil
    stockpileAttachSeq.expectedCount = nil
    stockpileAttachSeq.startedAt = 0
    stockpileAttachSeq.lastLogAt = 0
    ClearCursor()
    if msg then
        ChatInfo(msg)
    end
end

-- Hide popover / abort attachment when mailbox closes.
local mailCloseWatcher = CreateFrame("Frame", nil, frame)
mailCloseWatcher:RegisterEvent("MAIL_CLOSED")
mailCloseWatcher:SetScript("OnEvent", function()
    if stockpilePopover and stockpilePopover.IsShown and stockpilePopover:IsShown() then
        HideStockpilePopover()
    end
    if stockpileAttachSeq.active then
        AbortAttachSeq()
    end
end)

local function StartAttachSeq(steps)
    if not steps or #steps == 0 then
        return
    end
    stockpileAttachSeq.active = true
    stockpileAttachSeq.queue = steps
    stockpileAttachSeq.queueIndex = 1
    stockpileAttachSeq.phase = nil
    stockpileAttachSeq.bagID = nil
    stockpileAttachSeq.slot = nil
    stockpileAttachSeq.expectedCount = nil
    stockpileAttachSeq.startedAt = (time and time()) or 0
    stockpileAttachSeq.lastLogAt = 0
end

local function TryAdvanceAttachSeq()
    if not stockpileAttachSeq.active then return end
    local now = (time and time()) or 0
    local useItem = (C_Container and C_Container.UseContainerItem) or _G.UseContainerItem
    if not useItem then
        AbortAttachSeq("Missing UseContainerItem/C_Container.UseContainerItem")
        return
    end

    local step = stockpileAttachSeq.queue and stockpileAttachSeq.queue[stockpileAttachSeq.queueIndex] or nil
    if not step then
        AbortAttachSeq()
        return
    end

    if now - (stockpileAttachSeq.startedAt or now) > 10 then
        AbortAttachSeq("Timed out attaching items")
        return
    end

    local attachIndex = FirstFreeAttachmentIndex()
    if not attachIndex then
        AbortAttachSeq("Not enough attachment slots to send stockpile")
        return
    end

    -- If we're waiting on a placed split slot, attach from it once unlocked.
    if stockpileAttachSeq.phase == "waitingPlacedUnlock" then
        local bagID, slot = stockpileAttachSeq.bagID, stockpileAttachSeq.slot
        local count = (bagID and slot) and GetLiveBagSlotCount(bagID, slot) or 0
        local locked = (bagID and slot) and DebugIsSlotLocked(bagID, slot) or false
        local exp = stockpileAttachSeq.expectedCount
        if count <= 0 or locked or (type(exp) == "number" and exp > 0 and count < exp) then
            return
        end
        useItem(bagID, slot)
        stockpileAttachSeq.phase = nil
        stockpileAttachSeq.bagID = nil
        stockpileAttachSeq.slot = nil
        stockpileAttachSeq.expectedCount = nil
        stockpileAttachSeq.queueIndex = stockpileAttachSeq.queueIndex + 1
        stockpileAttachSeq.startedAt = now
        stockpileAttachSeq.lastLogAt = 0
        TryAdvanceAttachSeq()
        return
    end

    -- Otherwise, start the next step.
    if step.op == "split_merge_attach" then
        local splitFn = (C_Container and C_Container.SplitContainerItem) or _G.SplitContainerItem
        local pickup = (C_Container and C_Container.PickupContainerItem) or _G.PickupContainerItem
        if not splitFn or not pickup then
            AbortAttachSeq("Missing stack split APIs")
            return
        end
        if DebugIsSlotLocked(step.srcBagID, step.srcSlot) or DebugIsSlotLocked(step.dstBagID, step.dstSlot) then
            return
        end
        ClearCursor()
        splitFn(step.srcBagID, step.srcSlot, step.count)
        pickup(step.dstBagID, step.dstSlot) -- merge cursor split into destination stack
        ClearCursor()
        stockpileAttachSeq.phase = "waitingPlacedUnlock"
        stockpileAttachSeq.bagID = step.dstBagID
        stockpileAttachSeq.slot = step.dstSlot
        stockpileAttachSeq.expectedCount = step.finalCount
        stockpileAttachSeq.startedAt = now
        stockpileAttachSeq.lastLogAt = 0
        return
    end

    if step.op == "merge" then
        local pickup = (C_Container and C_Container.PickupContainerItem) or _G.PickupContainerItem
        if not pickup then
            AbortAttachSeq("Missing pickup API for merges")
            return
        end
        if DebugIsSlotLocked(step.srcBagID, step.srcSlot) or DebugIsSlotLocked(step.dstBagID, step.dstSlot) then
            return
        end
        ClearCursor()
        pickup(step.srcBagID, step.srcSlot)
        pickup(step.dstBagID, step.dstSlot)
        ClearCursor()
        stockpileAttachSeq.queueIndex = stockpileAttachSeq.queueIndex + 1
        stockpileAttachSeq.startedAt = now
        stockpileAttachSeq.lastLogAt = 0
        TryAdvanceAttachSeq()
        return
    end

    if step.op == "attach" then
        if DebugIsSlotLocked(step.bagID, step.slot) then
            return
        end
        useItem(step.bagID, step.slot)
        stockpileAttachSeq.queueIndex = stockpileAttachSeq.queueIndex + 1
        stockpileAttachSeq.startedAt = now
        stockpileAttachSeq.lastLogAt = 0
        TryAdvanceAttachSeq()
        return
    end

    -- step.op == "split_attach": split then place into empty slot, then wait unlock+attach.
    local splitFn = (C_Container and C_Container.SplitContainerItem) or _G.SplitContainerItem
    local pickup = (C_Container and C_Container.PickupContainerItem) or _G.PickupContainerItem
    if not splitFn or not pickup then
        AbortAttachSeq("Missing stack split APIs")
        return
    end
    local emptyBag, emptySlot = FindFirstEmptyBagSlot()
    if not emptyBag or not emptySlot then
        AbortAttachSeq("No free bag slots to split stacks")
        return
    end
    stockpileAttachSeq.phase = "waitingPlacedUnlock"
    stockpileAttachSeq.bagID = emptyBag
    stockpileAttachSeq.slot = emptySlot
    stockpileAttachSeq.startedAt = now
    stockpileAttachSeq.lastLogAt = 0
    ClearCursor()
    splitFn(step.bagID, step.slot, step.count)
    pickup(emptyBag, emptySlot)
    ClearCursor()
end

-- Event-driven wakeups for split debug
local stockpileSplitEventFrame = CreateFrame("Frame", nil, UIParent)
stockpileSplitEventFrame:RegisterEvent("BAG_UPDATE")
stockpileSplitEventFrame:RegisterEvent("ITEM_LOCK_CHANGED")
stockpileSplitEventFrame:SetScript("OnEvent", function()
    TryAdvanceAttachSeq()
end)
stockpileSplitEventFrame:SetScript("OnUpdate", function()
    if not stockpileAttachSeq.active then return end
    -- Poll fallback (some clients are noisy on events)
    TryAdvanceAttachSeq()
end)

RunSendStockpile = function(ctx)
    if not ctx or not ctx.spellId or not ctx.targetName or not ctx.requestedCrafts then return end
    if DS.IsMailOpen and not DS:IsMailOpen() then
        ChatInfo("Visit a mailbox and click again to send stockpile")
        return
    end
    local _, curRealm = GetCurrentIdentity()
    if ctx.targetRealm ~= curRealm then
        ChatInfo("Can't send stockpile across realms")
        return
    end

    local currentChar = DS.GetCurrentCharacter and DS:GetCurrentCharacter() or nil
    local targetChar = DS.GetCharacter and DS:GetCharacter(ctx.targetName, ctx.targetRealm) or nil
    if not currentChar or not targetChar then return end

    local getTargetCount = function(ch, itemId)
        return DS.GetTotalItemCount and DS:GetTotalItemCount(ch, itemId) or DS:GetContainerItemCount(ch, itemId)
    end
    local getSourceCount = function(ch, itemId)
        return DS.GetBagItemCount and DS:GetBagItemCount(ch, itemId) or DS:GetContainerItemCount(ch, itemId)
    end

    local minCrafts = CD.GetMaxCraftableQuantity
        and CD.GetMaxCraftableQuantity(targetChar, ctx.spellId, getTargetCount)
    local maxCrafts = CD.GetMaxCraftableQuantityAfterTransfer
        and CD.GetMaxCraftableQuantityAfterTransfer(
            targetChar,
            currentChar,
            ctx.spellId,
            getTargetCount,
            getSourceCount
        )
    if minCrafts == nil or maxCrafts == nil then return end
    if ctx.requestedCrafts <= minCrafts then return end
    if ctx.requestedCrafts > maxCrafts then
        ChatInfo(string.format("Not enough items to increase %s's stockpile", ctx.targetDisplayName or ctx.targetName))
        return
    end

    if not EnsureSendMailTab() then
        return
    end

    local clearSendMail = _G.ClearSendMail
    if clearSendMail then
        clearSendMail()
    end

    local recipient = FormatMailRecipient(ctx.targetName, ctx.targetRealm)
    if not SetSendMailRecipient(recipient) then
        return
    end

    local sendPlan = CD.GetReagentSendPlan and CD.GetReagentSendPlan(
        targetChar,
        currentChar,
        ctx.spellId,
        ctx.requestedCrafts,
        getTargetCount,
        getSourceCount
    )
    if not sendPlan then
        return
    end

    if stockpileAttachSeq.active then
        AbortAttachSeq()
    end

    local stacksById = CollectLiveStacksByItemID()
    for _, rr in ipairs(sendPlan) do
        local needToSend = rr.requiredToSend or 0
        if needToSend > 0 then
            local stacks = stacksById[rr.itemID] or {}
            local have = 0
            for _, st in ipairs(stacks) do
                have = have + (st.count or 1)
            end
            if have < needToSend then
                ChatInfo(string.format(
                    "Not enough items to increase %s's stockpile",
                    ctx.targetDisplayName or ctx.targetName
                ))
                return
            end
        end
    end

    local emptySlotsAvailable = CountEmptyBagSlotsLive()
    local steps = {}
    local totalAttachments = 0
    for _, rr in ipairs(sendPlan) do
        local needToSend = rr.requiredToSend or 0
        if needToSend > 0 then
            local itemStacks = stacksById[rr.itemID] or {}
            local stackLimit = GetItemStackLimit(rr.itemID)
            local plan = SP.BuildItemPlan(needToSend, itemStacks, {
                allowMerge = true,
                preferExact = true,
                stackLimit = stackLimit,
                maxAttachments = ATTACHMENTS_MAX_SEND,
                emptySlotsAvailable = emptySlotsAvailable,
            })
            if not plan or not plan.ok then
                local reason = plan and plan.reason or "unknown"
                if reason == "too_many_attachments" then
                    ChatInfo("Too many attachments needed (limit 12)")
                elseif reason == "no_empty_slot_for_split" then
                    ChatInfo("No free bag slots to split stacks")
                else
                    ChatInfo("Not enough items to increase stockpile")
                end
                return
            end
            for _, op in ipairs(plan.ops or {}) do
                steps[#steps + 1] = op
            end
            totalAttachments = totalAttachments + (plan.attachments or 0)
            for _, op in ipairs(plan.ops or {}) do
                if op.op == "split_attach" then
                    emptySlotsAvailable = math.max(0, emptySlotsAvailable - 1)
                end
            end
        end
    end

    if #steps == 0 then
        return
    end

    ChatInfo("Attaching items...")
    StartAttachSeq(steps)
    TryAdvanceAttachSeq()
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
    do
        local GRF = AltArmy.GlobalRealmFilter
        local rf = GRF and GRF.Get and GRF.Get() or "all"
        if rf == "currentRealm" then
            local _, curRealm = GetCurrentIdentity()
            local filtered = {}
            for _, rd in ipairs(rows) do
                if rd.realm == curRealm then
                    filtered[#filtered + 1] = rd
                end
            end
            rows = filtered
        end
    end

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
        local showRealm = (AltArmy.GlobalRealmFilter and AltArmy.GlobalRealmFilter.Get() == "all")
            and AccountHasMultipleRealms()
            and rd.realm
            and rd.realm ~= ""
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
        row.rowData = rd

        local craftQty = nil
        if row.charTableRef and rd.spellId then
            craftQty = CD.GetMaxCraftableQuantity(row.charTableRef, rd.spellId, function(ch, itemId)
                return DS.GetTotalItemCount and DS:GetTotalItemCount(ch, itemId) or DS:GetContainerItemCount(ch, itemId)
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
