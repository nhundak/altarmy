-- AltArmy TBC — Inventory tab, Bags and Bank views: fills frame.BagsView and frame.BankView with one
-- character's containers drawn like the stock windows. Two layouts (Data/Inventory/InventoryOptions.lua):
-- "blocks", one block per bag with its icon and name (the bank: its main grid, then each bank bag), or
-- "combined", a bag bar over one grid (retail's combined bags). Slots: UI/ItemSlotButton.lua; what to
-- draw: Data/Inventory/InventoryLayout.lua.
-- luacheck: globals GameTooltip GetContainerNumSlots NUM_BANKGENERIC_SLOTS

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Inventory
if not frame or not frame.BagsView or not frame.BankView then return end

local DS = AltArmy.DataStore
local Theme = AltArmy.Theme
local IO = AltArmy.InventoryOptions
local IL = AltArmy.InventoryLayout
local ISB = AltArmy.ItemSlotButton
local SD = AltArmy.SummaryData
if not (DS and Theme and IO and IL and ISB and SD) then return end

local UI = {
    SLOT = ISB.SIZE,
    GAP = ISB.SPACING,
    HEADER_HEIGHT = 20,
    HEADER_ICON = 16,
    HEADER_GAP = 2, -- header to its grid
    BLOCK_GAP_Y = 12, -- between rows of blocks
    BLOCK_GAP_X = 16, -- between blocks in a row
    MIN_BLOCK_WIDTH = 150, -- room for a bag's name in the header
    BAR_SLOT = 26, -- the combined layout's bag bar
    BAR_GAP = 4,
    BAR_HEIGHT = 34,
    STATUS_HEIGHT = 20,
    FALLBACK_WIDTH = 600, -- before the viewport has a size
    EMPTY_NOTE_HEIGHT = 16,
    BACKPACK_ICON = "Interface\\Buttons\\Button-Backpack-Up",
    BANK_ICON = "Interface\\Icons\\INV_Crate_01", -- a crate (also the Economy tab's Waylaid Crates icon)
    KEYRING_ICON = "Interface\\Icons\\INV_Misc_Key_03",
    REAGENT_ICON = "Interface\\Icons\\INV_Misc_Bag_10",
    STATUS_ICON = 14,
    ESTIMATE_NOTE = "Slot count estimated from the items seen; exact after the next scan on this character.",
    -- Blizzard's placeholder items ("Character Bank Tab Bag (DNT)" sits in Forever's first bank tab slot;
    -- DNT = do not translate) are never shown by name.
    INTERNAL_ITEM_MARK = "(DNT)",
}

local views = {} -- kind -> view

-- Item ids whose icons were not cached when drawn; the views redraw when they arrive.
local pendingIcons = {}
local iconEvents
local function TrackPendingIcon(itemID)
    if not itemID then return end
    pendingIcons[itemID] = true
    if not iconEvents and CreateFrame then
        iconEvents = CreateFrame("Frame")
        iconEvents:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        iconEvents:SetScript("OnEvent", function(_, _, itemId)
            itemId = tonumber(itemId)
            if not itemId or not pendingIcons[itemId] then return end
            pendingIcons[itemId] = nil
            for _, view in pairs(views) do
                if view.panel:IsShown() then view.Refresh() end
            end
        end)
    end
end

local function BagItemInfo(itemIDOrLink)
    if not itemIDOrLink or not DS.CompatGetItemInfo then return nil, nil end
    local name, _, _, _, _, _, _, _, _, texture = DS.CompatGetItemInfo(itemIDOrLink)
    return name, texture
end

--- Name and icon for a block: the bag item's, or the stock art for the backpack, bank and keyring. A
--- placeholder bag item keeps its icon but not its name or tooltip (the block falls back to "Bank Tab N").
local function ResolveBag(block)
    if block.kind == "backpack" then return nil, UI.BACKPACK_ICON end
    if block.kind == "bank" then return nil, UI.BANK_ICON end
    if block.kind == "keyring" then return nil, UI.KEYRING_ICON end
    local name, texture = BagItemInfo(block.bagLink or block.bagItemID)
    if block.bagItemID and not texture then
        texture = GetItemIcon and GetItemIcon(block.bagItemID) or nil
        if not texture then TrackPendingIcon(block.bagItemID) end
    end
    if name and name:find(UI.INTERNAL_ITEM_MARK, 1, true) then
        block.bagLink, block.bagItemID = nil, nil
        name = nil
    end
    if not texture and block.kind == "reagentbag" then texture = UI.REAGENT_ICON end
    return name, texture
end

local function IconMarkup(path)
    if not path then return "" end
    return "|T" .. path .. ":" .. UI.STATUS_ICON .. ":" .. UI.STATUS_ICON .. "|t "
end

local function SlotCountText(icon, used, total, estimate)
    return string.format("%s%d/%s%d", IconMarkup(icon), used, estimate and "~" or "", total)
end

--- The Bags footer: used / total slots per group (bags, reagent bag, keyring), each with its icon.
local function SlotGroupsText(blocks, estimate)
    local parts = {}
    for _, g in ipairs(IL.SlotGroups(blocks)) do
        local icon = g.icon
        if g.key == "bags" then icon = UI.BACKPACK_ICON end
        if g.key == "keyring" then icon = UI.KEYRING_ICON end
        if g.key == "reagent" and not icon then icon = UI.REAGENT_ICON end
        parts[#parts + 1] = SlotCountText(icon, g.used, g.total, estimate)
    end
    return table.concat(parts, "   ")
end

--- The Bank footer: used / total slots over the whole bank, with the bank icon.
local function SlotTotalText(blocks)
    local used, total, estimate = 0, 0, false
    for _, block in ipairs(blocks) do
        used = used + block.used
        total = total + block.numSlots
        estimate = estimate or block.sizeIsEstimate
    end
    return SlotCountText(UI.BANK_ICON, used, total, estimate)
end

--- The client's live sizes, for data saved before slot counts were (containers v2).
local function LiveDefaults()
    local roles = DS:GetBagRoles()
    local backpack
    if C_Container and C_Container.GetContainerNumSlots then
        backpack = C_Container.GetContainerNumSlots(roles.backpack)
    elseif GetContainerNumSlots then
        backpack = GetContainerNumSlots(roles.backpack)
    end
    if not backpack or backpack <= 0 then backpack = IL.CONST.DEFAULT_BACKPACK_SLOTS end
    return { backpack = backpack, bank = NUM_BANKGENERIC_SLOTS or IL.CONST.DEFAULT_BANK_SLOTS }
end

local function ShowHeaderTooltip(header)
    local block = header.block
    if not block or not GameTooltip then return end
    GameTooltip:SetOwner(header, "ANCHOR_RIGHT")
    if block.bagLink and block.bagLink ~= "" then
        GameTooltip:SetHyperlink(block.bagLink)
    elseif block.bagItemID and GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(block.bagItemID)
    else
        GameTooltip:SetText(block.name or "")
    end
    GameTooltip:AddLine(string.format("%d of %d slots used", block.used, block.numSlots), 0.75, 0.75, 0.75)
    if block.sizeIsEstimate then
        GameTooltip:AddLine(UI.ESTIMATE_NOTE, 0.75, 0.75, 0.75, true)
    end
    GameTooltip:Show()
end

local function CreateHeader(parent)
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(UI.HEADER_HEIGHT)
    h:EnableMouse(true)
    h.icon = h:CreateTexture(nil, "ARTWORK")
    h.icon:SetSize(UI.HEADER_ICON, UI.HEADER_ICON)
    h.icon:SetPoint("LEFT", h, "LEFT", 0, 0)
    h.count = h:CreateFontString(nil, "OVERLAY", Theme.FONTS.muted)
    h.count:SetPoint("RIGHT", h, "RIGHT", 0, 0)
    h.count:SetJustifyH("RIGHT")
    h.name = h:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
    h.name:SetPoint("LEFT", h.icon, "RIGHT", 4, 0)
    h.name:SetPoint("RIGHT", h.count, "LEFT", -4, 0)
    h.name:SetJustifyH("LEFT")
    h.name:SetWordWrap(false)
    h.note = parent:CreateFontString(nil, "OVERLAY", Theme.FONTS.muted)
    h.note:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -UI.HEADER_GAP)
    h.note:SetJustifyH("LEFT")
    h.note:Hide()
    h:SetScript("OnEnter", ShowHeaderTooltip)
    h:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return h
end

--- A pool of header frames on `parent` (same Acquire / ReleaseAll shape as the slot pool).
local function CreateHeaderPool(parent)
    local pool = { free = {}, active = {} }
    function pool.Acquire()
        local h = table.remove(pool.free) or CreateHeader(parent)
        h:Show()
        pool.active[#pool.active + 1] = h
        return h
    end
    function pool.ReleaseAll()
        for i = #pool.active, 1, -1 do
            local h = pool.active[i]
            pool.active[i] = nil
            h.block = nil
            h.note:Hide()
            h:Hide()
            h:ClearAllPoints()
            pool.free[#pool.free + 1] = h
        end
    end
    return pool
end

local function SlotWhere(block, slot)
    return string.format("%s, slot %d", block.name or "", slot)
end

local function SlotTooltipExtra(_, tooltip, entry)
    if entry.where then
        tooltip:AddLine(entry.where, 0.6, 0.6, 0.6)
    end
end

--- Draw a block's slots as a grid at (x, y) on the scroll child; returns the grid's height.
local function DrawGrid(view, block, x, y, columns)
    local m = IL.GridMetrics(block.numSlots, UI.SLOT, UI.GAP, columns)
    for slot = 1, block.numSlots do
        local btn = view.slots.Acquire()
        btn:SetPoint("TOPLEFT", view.child, "TOPLEFT", x + m.x(slot), -(y + m.y(slot)))
        local entry = block.slots[slot]
        if entry then
            entry.where = SlotWhere(block, slot)
            btn.tooltipExtra = SlotTooltipExtra
            TrackPendingIcon(ISB.SetItem(btn, entry))
        else
            ISB.SetEmpty(btn)
        end
    end
    return m.height, m.width
end

local function FillHeader(h, block, x, y, width, parent)
    h.block = block
    h:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    h:SetWidth(width)
    if block.icon then
        h.icon:SetTexture(block.icon)
        h.icon:Show()
    else
        h.icon:Hide()
    end
    h.name:SetText(block.name or "")
    h.count:SetText(string.format("%s%d / %d", block.sizeIsEstimate and "~" or "", block.used, block.numSlots))
end

--- "blocks": each bag as its own block, flowing left to right then down.
local function LayoutBlocks(view, blocks, width)
    local x, y, rowHeight = 0, 0, 0
    for _, block in ipairs(blocks) do
        local columns = IL.BlockColumns(block)
        local m = IL.GridMetrics(block.numSlots, UI.SLOT, UI.GAP, columns)
        local blockWidth = math.max(m.width, UI.MIN_BLOCK_WIDTH)
        if x > 0 and x + blockWidth > width then
            x = 0
            y = y + rowHeight + UI.BLOCK_GAP_Y
            rowHeight = 0
        end
        local h = view.headers.Acquire()
        FillHeader(h, block, x, y, blockWidth, view.child)
        local gridTop = y + UI.HEADER_HEIGHT + UI.HEADER_GAP
        local height
        if block.numSlots > 0 then
            height = DrawGrid(view, block, x, gridTop, columns)
        else
            h.note:SetText("Size unknown until the next scan.")
            h.note:Show()
            height = UI.EMPTY_NOTE_HEIGHT
        end
        local total = UI.HEADER_HEIGHT + UI.HEADER_GAP + height
        if total > rowHeight then rowHeight = total end
        x = x + blockWidth + UI.BLOCK_GAP_X
    end
    return y + rowHeight
end

--- "combined": the bag bar, then every slot in one grid.
local function LayoutCombined(view, blocks, width)
    local combined = IL.Combined(blocks)
    local x = 0
    for _, bag in ipairs(combined.bagBar) do
        local btn = view.bar.Acquire()
        btn:SetPoint("TOPLEFT", view.child, "TOPLEFT", x, 0)
        local entry = { itemID = bag.itemID, link = bag.link, icon = bag.icon, name = bag.name, count = 1 }
        entry.where = string.format("%d / %d slots used", bag.used, bag.numSlots)
        btn.tooltipExtra = SlotTooltipExtra
        TrackPendingIcon(ISB.SetItem(btn, entry))
        x = x + UI.BAR_SLOT + UI.BAR_GAP
    end
    local columns = IL.ColumnsForWidth(width, UI.SLOT, UI.GAP, IL.CONST.COMBINED_MAX_COLUMNS)
    local m = IL.GridMetrics(#combined.slots, UI.SLOT, UI.GAP, columns)
    local top = UI.BAR_HEIGHT
    local byBag = {}
    for _, block in ipairs(blocks) do byBag[block.bagID] = block end
    for i, entry in ipairs(combined.slots) do
        local btn = view.slots.Acquire()
        btn:SetPoint("TOPLEFT", view.child, "TOPLEFT", m.x(i), -(top + m.y(i)))
        if entry.itemID then
            entry.where = SlotWhere(byBag[entry.bagID] or {}, entry.slot)
            btn.tooltipExtra = SlotTooltipExtra
            TrackPendingIcon(ISB.SetItem(btn, entry))
        else
            ISB.SetEmpty(btn)
        end
    end
    return top + m.height
end

local function ShowEmptyState(view, text)
    view.empty:SetText(text)
    view.empty:Show()
    view.status:SetText("")
    view.child:SetHeight(1)
    view.viewport.UpdateRange()
end

local function CreateContainerView(panel, kind)
    local view = { panel = panel, kind = kind }
    local inner = Theme.CreatePanelInnerContent(panel)

    view.status = inner:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    view.status:SetPoint("BOTTOMLEFT", inner, "BOTTOMLEFT", 0, 0)
    view.status:SetHeight(UI.STATUS_HEIGHT)
    view.status:SetJustifyH("LEFT")
    -- The character's gold, bottom right (as the stock bag and bank windows show it).
    view.money = inner:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    view.money:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", 0, 0)
    view.money:SetHeight(UI.STATUS_HEIGHT)
    view.money:SetJustifyH("RIGHT")
    view.status:SetPoint("RIGHT", view.money, "LEFT", -Theme.SECTION_GAP, 0)

    local listViewport = CreateFrame("Frame", nil, inner)
    listViewport:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, 0)
    listViewport:SetPoint("BOTTOM", view.status, "TOP", 0, Theme.SECTION_GAP)
    listViewport:SetPoint("RIGHT", panel, "RIGHT", -Theme.VerticalScrollBarGutter(), 0)
    view.listViewport = listViewport

    view.viewport = Theme.CreateVerticalScrollViewport({
        parent = listViewport,
        gutterEdge = panel,
        anchorTop = { "TOPLEFT", listViewport, "TOPLEFT", 0, 0 },
        anchorBottom = { "BOTTOMRIGHT", listViewport, "BOTTOMRIGHT", 0, 0 },
        valueStep = UI.SLOT + UI.GAP,
        wheelStep = (UI.SLOT + UI.GAP) * 2,
        enableMouseWheel = true,
        childWidth = UI.FALLBACK_WIDTH,
    })
    view.child = view.viewport.child
    view.slots = ISB.CreatePool(view.child)
    view.bar = ISB.CreatePool(view.child, { size = UI.BAR_SLOT })
    view.headers = CreateHeaderPool(view.child)

    view.empty = listViewport:CreateFontString(nil, "OVERLAY", Theme.FONTS.emptyState)
    view.empty:SetPoint("CENTER", listViewport, "CENTER", 0, 20)
    view.empty:SetWidth(440)
    view.empty:SetJustifyH("CENTER")
    view.empty:SetWordWrap(true)
    view.empty:Hide()

    function view.Refresh()
        view.slots.ReleaseAll()
        view.bar.ReleaseAll()
        view.headers.ReleaseAll()
        view.empty:Hide()
        local char, pick = frame.GetSelectedCharacter()
        view.money:SetText(char and SD.GetMoneyString(DS:GetMoney(char) or 0) or "")
        if not char then
            ShowEmptyState(view, "No characters recorded yet.")
            return
        end
        local opts = {
            ids = DS:GetBagRoles(), defaults = LiveDefaults(), resolveBag = ResolveBag, includeKeyring = true,
        }
        local blocks = kind == "bags" and IL.BagsBlocks(char, opts) or IL.BankBlocks(char, opts)
        if not blocks then
            ShowEmptyState(view, string.format("Bank not recorded yet.\n\nVisit the bank on %s once.",
                pick and pick.name or "this character"))
            return
        end
        local width = view.viewport.scroll:GetWidth()
        if not width or width <= 0 then width = UI.FALLBACK_WIDTH end
        local height
        if IO.GetLayout(IO.EnsureOptions(), kind) == "combined" then
            height = LayoutCombined(view, blocks, width)
        else
            height = LayoutBlocks(view, blocks, width)
        end
        view.child:SetHeight(math.max(height, 1))
        view.viewport.UpdateRange()

        if kind == "bags" then
            local estimate = false
            for _, block in ipairs(blocks) do
                estimate = estimate or block.sizeIsEstimate
            end
            view.status:SetText(SlotGroupsText(blocks, estimate))
        else
            view.status:SetText(SlotTotalText(blocks))
        end
    end

    views[kind] = view
    return view
end

local bags = CreateContainerView(frame.BagsView, "bags")
local bank = CreateContainerView(frame.BankView, "bank")
frame.RefreshBags = bags.Refresh
frame.RefreshBank = bank.Refresh

-- The grid reflows when the window's size settles (the viewport has no width before the first show).
for _, view in pairs(views) do
    view.viewport.scroll:HookScript("OnSizeChanged", function()
        if view.panel:IsShown() and frame:IsShown() then view.Refresh() end
    end)
end
