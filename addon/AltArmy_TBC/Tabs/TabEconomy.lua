-- AltArmy TBC — Economy tab (WoW Forever only): the Currency grid (Tabs/TabEconomyCurrency.lua fills
-- frame.CurrencyView), Waylaid Crates fill costs from the Alt Army auction scan, and the Supply Chain page
-- about alt-army.com (Tabs/TabEconomySupplyChain.lua fills frame.SupplyChainView).
-- luacheck: globals GameTooltip GetItemIcon GetServerTime

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Economy
if not frame then return end

local DS = AltArmy.DataStore
if not (DS and DS.IsWowForever) then
    -- Waylaid Crates, the full auction scan and alt-army.com's prices exist only on WoW Forever.
    if AltArmy.MainSideTabs then
        AltArmy.MainSideTabs:SetTabShown("Economy", false)
    end
    frame.SupplyChainView = nil
    frame.CurrencyView = nil
    return
end

local Theme = AltArmy.Theme
local W = AltArmy.WaylaidCosts
local Crates = AltArmy.WaylaidCrates
local Book = AltArmy.AuctionBook
if not (Theme and W and Crates and Book) then return end

W.EnsureOptions()

local UI = {
    PAD = 4,
    ROW_HEIGHT = 20,
    HEADER_HEIGHT = 20,
    HEADER_ROW_GAP = 3,
    STATUS_HEIGHT = 22, -- fits the scan button
    ICON_SIZE = 14,
    -- Sums to 626: the list viewport's width (window 670, content insets, panel padding, scrollbar gutter).
    colWidths = { crate = 170, price = 96, bundle = 168, bundleCost = 96, total = 96 },
    sortKeys = { "crate", "price", "bundle", "bundleCost", "total" },
    sortLabels = {
        crate = "Crate",
        price = "Crate price",
        bundle = "Cheapest fill",
        bundleCost = "Fill cost",
        total = "Total",
    },
    sortJustify = { crate = "LEFT", price = "RIGHT", bundle = "LEFT", bundleCost = "RIGHT", total = "RIGHT" },
    headerButtons = {},
    rowPool = {},
    activeRows = {},
    cache = nil, -- { scan, book }: the decoded scan, kept until a newer one arrives
    CRAFTED_COLOR = "|cff1eff00",
    GATHERED_COLOR = "|cffffffff",
}

local VIEW = {
    active = "currency",
    tabs = nil,
    defs = {
        -- Forever's CharacterFrame Currency side-tab icon.
        { name = "currency", label = "Currency", icon = "Interface\\Icons\\INV_SideTab_Currency_c60" },
        { name = "waylaid", label = "Waylaid Crates", icon = "Interface\\Icons\\INV_Crate_01" },
    },
}
UI.supplyEnabled = AltArmy.FeatureFlags and AltArmy.FeatureFlags.economySupplyChain and true or false
if UI.supplyEnabled then
    VIEW.defs[#VIEW.defs + 1] = { name = "supply", label = "Supply Chain", icon = "Interface\\Icons\\INV_Misc_Map_01" }
end

local function TotalColWidth()
    local w = UI.colWidths
    return w.crate + w.price + w.bundle + w.bundleCost + w.total
end

local function Money(copper)
    if copper == nil then return "—" end
    return AltArmy.SummaryData.GetMoneyString(copper)
end

local function ItemIcon(itemID)
    local icon = GetItemIcon and GetItemIcon(itemID)
    if not icon and C_Item and C_Item.GetItemIconByID then
        icon = C_Item.GetItemIconByID(itemID)
    end
    return icon
end

local function CrateLabel(row)
    local color = row.kind == "Gathered" and UI.GATHERED_COLOR or UI.CRAFTED_COLOR
    local icon = ItemIcon(row.id)
    local prefix = icon and ("|T" .. icon .. ":" .. UI.ICON_SIZE .. ":" .. UI.ICON_SIZE .. "|t ") or ""
    return prefix .. color .. (row.short or row.name) .. "|r"
end

-- Panels: one per sub-view, same anchors; only the active one is shown.
local currencyPanel = Theme.CreateMainContentPanel(frame)
currencyPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", Theme.TAB_SECTION_INSET, -Theme.TAB_SECTION_INSET)
currencyPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -Theme.TAB_SECTION_INSET, Theme.TAB_SECTION_INSET)
local waylaidPanel = Theme.CreateMainContentPanel(frame)
waylaidPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", Theme.TAB_SECTION_INSET, -Theme.TAB_SECTION_INSET)
waylaidPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -Theme.TAB_SECTION_INSET, Theme.TAB_SECTION_INSET)
-- Behind a feature flag: without the panel, Tabs/TabEconomySupplyChain.lua builds nothing.
local supplyPanel
if UI.supplyEnabled then
    supplyPanel = Theme.CreateMainContentPanel(frame)
    supplyPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", Theme.TAB_SECTION_INSET, -Theme.TAB_SECTION_INSET)
    supplyPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -Theme.TAB_SECTION_INSET, Theme.TAB_SECTION_INSET)
    supplyPanel:Hide()
end
waylaidPanel:Hide()
frame.CurrencyView = currencyPanel
frame.WaylaidView = waylaidPanel
frame.SupplyChainView = supplyPanel

local inner = Theme.CreatePanelInnerContent(waylaidPanel)

-- Bottom row: scan age on the left (colored by how stale the prices are), the scan button centered while
-- the auction house is open, the automatic scan checkbox on the right.
local statusLabel = inner:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
statusLabel:SetPoint("BOTTOMLEFT", inner, "BOTTOMLEFT", 0, 0)
statusLabel:SetHeight(UI.STATUS_HEIGHT)
statusLabel:SetJustifyH("LEFT")

-- Same setting as Options → General → Auction House. CreateLabeledCheckbox stretches its row to its
-- parent's right edge: a holder sized to the checkbox and label keeps it right-aligned.
UI.autoScanHolder = CreateFrame("Frame", nil, inner)
UI.autoScanHolder:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", 0, 0)
UI.autoScanHolder:SetHeight(UI.STATUS_HEIGHT)
UI.autoScanCheck = Theme.CreateLabeledCheckbox(UI.autoScanHolder, {
    point = "LEFT",
    relativeTo = UI.autoScanHolder,
    relativePoint = "LEFT",
    text = "Auto scan when opening AH",
    onClick = function(checked)
        local S = AltArmy.AuctionScan
        if S and S.SetAutoScanEnabled then S.SetAutoScanEnabled(checked) end
    end,
})
UI.autoScanHolder:SetWidth(Theme.CHAR_LIST_CHECKBOX_SIZE + 2 + UI.autoScanCheck.label:GetStringWidth() + 4)

-- While the auction house is open: scan now, or the cooldown left (same text as the auction house button).
UI.scanBtn = CreateFrame("Button", nil, inner, "UIPanelButtonTemplate")
UI.scanBtn:SetSize(110, UI.STATUS_HEIGHT)
UI.scanBtn:SetPoint("BOTTOM", inner, "BOTTOM", 0, 0)
UI.scanBtn:SetMotionScriptsWhileDisabled(true)
Theme.SkinButton(UI.scanBtn)
UI.scanBtn:Hide()

local function UpdateScanButton()
    local S = AltArmy.AuctionScan
    local Btn = AltArmy.AuctionScanButton
    local show = S and S.HasApi() and S.IsOpen() and Btn and Btn.Label and statusLabel:IsShown()
    UI.scanBtn:SetShown(show and true or false)
    if not show then return end
    local text, enabled = Btn.Label(S.State(), S.Progress(), S.CooldownLeft())
    UI.scanBtn:SetText(enabled and "Scan now" or text)
    UI.scanBtn:SetEnabled(enabled)
end

UI.scanBtn:SetScript("OnClick", function()
    local S = AltArmy.AuctionScan
    if S then S.Start() end
    UpdateScanButton()
end)
do
    local elapsed = 0
    UI.scanBtn:SetScript("OnUpdate", function(_, dt) -- the cooldown's countdown
        elapsed = elapsed + dt
        if elapsed >= 1 then
            elapsed = 0
            UpdateScanButton()
        end
    end)
end

local headerRow = CreateFrame("Frame", nil, inner)
headerRow:SetHeight(UI.HEADER_HEIGHT)
headerRow:SetWidth(TotalColWidth())
headerRow:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, 0)

local function UpdateHeaderSortIndicators()
    local o = W.EnsureOptions()
    for _, sk in ipairs(UI.sortKeys) do
        local btn = UI.headerButtons[sk]
        btn.label:SetText(Theme.FormatSortHeaderLabel(UI.sortLabels[sk], sk == o.waylaidSortKey,
            o.waylaidSortAscending))
    end
end

do
    local hx = 0
    for _, sk in ipairs(UI.sortKeys) do
        local btn = CreateFrame("Button", nil, headerRow)
        btn:SetPoint("TOPLEFT", headerRow, "TOPLEFT", hx, 0)
        btn:SetSize(UI.colWidths[sk], UI.HEADER_HEIGHT)
        btn:RegisterForClicks("LeftButtonUp")
        local key = sk
        btn:SetScript("OnClick", function()
            local o = W.EnsureOptions()
            if o.waylaidSortKey == key then
                o.waylaidSortAscending = not o.waylaidSortAscending
            else
                o.waylaidSortKey = key
                -- Money columns start cheapest first; names A-Z.
                o.waylaidSortAscending = true
            end
            if frame.RefreshWaylaid then frame.RefreshWaylaid() end
        end)
        local label = btn:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
        label:SetPoint("LEFT", btn, "LEFT", 0, 0)
        label:SetPoint("RIGHT", btn, "RIGHT", UI.sortJustify[sk] == "RIGHT" and -4 or 0, 0)
        label:SetHeight(UI.HEADER_HEIGHT)
        label:SetJustifyH(UI.sortJustify[sk])
        btn.label = label
        Theme.BindInteractableHover(btn)
        UI.headerButtons[sk] = btn
        hx = hx + UI.colWidths[sk]
    end
end

local listViewport = CreateFrame("Frame", nil, inner)
listViewport:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, -(UI.HEADER_HEIGHT + UI.HEADER_ROW_GAP))
listViewport:SetPoint("BOTTOM", statusLabel, "TOP", 0, UI.PAD)
listViewport:SetPoint("RIGHT", waylaidPanel, "RIGHT", -Theme.VerticalScrollBarGutter(), 0)

local viewport = Theme.CreateVerticalScrollViewport({
    parent = listViewport,
    gutterEdge = waylaidPanel,
    anchorTop = { "TOPLEFT", listViewport, "TOPLEFT", 0, 0 },
    anchorBottom = { "BOTTOMRIGHT", listViewport, "BOTTOMRIGHT", 0, 0 },
    valueStep = UI.ROW_HEIGHT,
    wheelStep = UI.ROW_HEIGHT * 3,
    enableMouseWheel = true,
    childWidth = TotalColWidth(),
})
local scrollChild = viewport.child

headerRow:SetFrameLevel((inner:GetFrameLevel() or 0) + 10)
local headerFade = Theme.CreatePinnedHeaderScrollFade({
    headerFrame = headerRow,
    scrollFrame = viewport.scroll,
    scrollBar = viewport.scrollBar,
    headerBottomInset = 2,
})
viewport.OnScroll(function()
    if headerFade then headerFade:Update() end
end)

-- A scan with no Waylaid Crates listed: a message in the empty table.
UI.noCratesLabel = listViewport:CreateFontString(nil, "OVERLAY", Theme.FONTS.emptyState)
UI.noCratesLabel:SetPoint("CENTER", listViewport, "CENTER", 0, 20)
UI.noCratesLabel:SetText("No Waylaid Crates were listed on this scan.")
UI.noCratesLabel:Hide()

-- No scan of this auction house yet: a message and the automatic scan checkbox, in place of the table.
local empty = CreateFrame("Frame", nil, inner)
empty:SetSize(440, 120)
empty:SetPoint("CENTER", inner, "CENTER", 0, 20)
local emptyLabel = empty:CreateFontString(nil, "OVERLAY", Theme.FONTS.emptyState)
emptyLabel:SetPoint("TOPLEFT", empty, "TOPLEFT", 0, 0)
emptyLabel:SetPoint("TOPRIGHT", empty, "TOPRIGHT", 0, 0)
emptyLabel:SetJustifyH("CENTER")
emptyLabel:SetWordWrap(true)
-- CreateLabeledCheckbox stretches its row to its parent's right edge: give it a narrow holder to center.
local checkHolder = CreateFrame("Frame", nil, empty)
checkHolder:SetSize(340, Theme.CHAR_LIST_ROW_HEIGHT)
checkHolder:SetPoint("TOP", emptyLabel, "BOTTOM", 0, -18)
local autoScanRow = Theme.CreateLabeledCheckbox(checkHolder, {
    point = "TOPLEFT",
    relativeTo = checkHolder,
    relativePoint = "TOPLEFT",
    text = "Scan the auction house automatically when it opens",
    onClick = function(checked)
        local S = AltArmy.AuctionScan
        if S and S.SetAutoScanEnabled then S.SetAutoScanEnabled(checked) end
    end,
})
empty:Hide()

local function ReleaseRows()
    for i = #UI.activeRows, 1, -1 do
        local row = UI.activeRows[i]
        UI.activeRows[i] = nil
        row:Hide()
        UI.rowPool[#UI.rowPool + 1] = row
    end
end

local function ShowRowTooltip(row)
    local rd = row.rowData
    if not rd then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(rd.id)
    else
        GameTooltip:SetText(rd.name)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Cheapest crate on the auction house", Money(rd.price), 1, 0.82, 0, 1, 1, 1)
    if rd.random then
        GameTooltip:AddLine("Its shipment is random until you read the label, so there is no fill cost.",
            0.7, 0.7, 0.7, true)
    elseif #rd.options > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Fill it with any one of these bundles:", 1, 0.82, 0)
        for _, opt in ipairs(rd.options) do
            local left = opt.count .. " x " .. opt.name
            local right, r, g, b
            if opt.cost then
                right = Money(opt.cost) .. (opt.approx and "*" or "")
                r, g, b = 1, 1, 1
                if opt == rd.bundle then
                    left = left .. " (cheapest)"
                end
            elseif opt.listed > 0 then
                right, r, g, b = "only " .. opt.listed .. " listed", 0.7, 0.7, 0.7
            else
                right, r, g, b = "not listed", 0.7, 0.7, 0.7
            end
            GameTooltip:AddDoubleLine(left, right, 1, 1, 1, r, g, b)
        end
        if rd.bundle and rd.bundle.approx then
            GameTooltip:AddLine("* Estimate: some of it comes from the scan's dearest listings, which are "
                .. "saved together at their cheapest price.", 0.7, 0.7, 0.7, true)
        end
    end
    local AZ = AltArmy.AuctionatorSearch
    if AZ and AZ.IsAvailable() then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to search with Auctionator", 0.5, 0.5, 0.5)
    end
    GameTooltip:Show()
end

-- At the auction house with Auctionator: search the crate and its bundles as a temporary shopping list.
local function OnRowClick(row)
    local rd = row.rowData
    local AZ = AltArmy.AuctionatorSearch
    if rd and AZ and AZ.IsAvailable() then
        AZ.Search(W.SearchTerms(rd))
    end
end

local function PoolRow()
    local row = table.remove(UI.rowPool)
    if row then
        row:Show()
        return row
    end
    row = CreateFrame("Button", nil, scrollChild)
    row:SetHeight(UI.ROW_HEIGHT)
    Theme.InstallRowHoverHighlight(row)
    row:SetScript("OnEnter", ShowRowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", OnRowClick)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta) viewport.Wheel(delta) end)
    row.cells = {}
    local x = 0
    for _, sk in ipairs(UI.sortKeys) do
        local cell = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        cell:SetPoint("LEFT", row, "LEFT", x, 0)
        cell:SetWidth(UI.colWidths[sk] - 4)
        cell:SetJustifyH(UI.sortJustify[sk])
        cell:SetWordWrap(false)
        row.cells[sk] = cell
        x = x + UI.colWidths[sk]
    end
    return row
end

local function CurrentScan()
    local realm = GetRealmName and GetRealmName() or ""
    local faction = UnitFactionGroup and UnitFactionGroup("player") or ""
    return Book.Latest(realm, faction), realm, faction
end

local function ShowEmpty(realm, faction)
    local S = AltArmy.AuctionScan
    emptyLabel:SetText("No auction house scan yet for " .. realm .. " (" .. faction .. ").\n\n"
        .. "Visit an auction house and press the Alt Army scan button above it (or type /altarmy scan) "
        .. "to see what each Waylaid Crate costs to buy and fill.")
    autoScanRow.check:SetChecked(S and S.IsAutoScanEnabled and S.IsAutoScanEnabled() or false)
    empty:Show()
    statusLabel:Hide()
    UI.scanBtn:Hide()
    UI.autoScanHolder:Hide()
    headerRow:Hide()
    listViewport:Hide()
end

local function RefreshWaylaid()
    ReleaseRows()
    local scan, realm, faction = CurrentScan()
    if not scan then
        UI.cache = nil
        ShowEmpty(realm, faction)
        return
    end
    if not UI.cache or UI.cache.scan ~= scan then
        UI.cache = { scan = scan, book = Book.Decode(scan.items) }
    end
    empty:Hide()
    statusLabel:Show()
    UI.autoScanHolder:Show()
    headerRow:Show()
    listViewport:Show()

    local rows = W.BuildRows(UI.cache.book, Crates)
    local o = W.EnsureOptions()
    table.sort(rows, function(a, b) return W.Compare(a, b, o.waylaidSortKey, o.waylaidSortAscending) end)
    UpdateHeaderSortIndicators()

    local now = GetServerTime and GetServerTime() or time()
    statusLabel:SetText(W.AgeText(scan.t, now, AltArmy.SummaryData.GetTimeString))
    local level = W.AgeLevel(scan.t, now)
    local ageColor = level == "old" and Theme.COLORS.warningBlocking
        or level == "stale" and Theme.COLORS.warningCaution
        or { 1, 1, 1 }
    statusLabel:SetTextColor(ageColor[1], ageColor[2], ageColor[3], 1)
    UpdateScanButton()
    local S = AltArmy.AuctionScan
    UI.autoScanCheck.check:SetChecked(S and S.IsAutoScanEnabled and S.IsAutoScanEnabled() or false)

    local totalW = TotalColWidth()
    scrollChild:SetSize(totalW, math.max(1, #rows) * UI.ROW_HEIGHT)
    UI.noCratesLabel:SetShown(#rows == 0)
    local y = 0
    for _, rd in ipairs(rows) do
        local row = PoolRow()
        UI.activeRows[#UI.activeRows + 1] = row
        row.rowData = rd
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
        row:SetWidth(totalW)
        y = y - UI.ROW_HEIGHT
        local c = row.cells
        c.crate:SetText(CrateLabel(rd))
        c.price:SetText(Money(rd.price))
        c.bundle:SetText(rd.bundleText)
        if rd.bundle then
            c.bundle:SetTextColor(1, 1, 1, 1)
            c.bundleCost:SetText(Money(rd.bundle.cost) .. (rd.bundle.approx and "*" or ""))
        else
            c.bundle:SetTextColor(0.6, 0.6, 0.6, 1)
            c.bundleCost:SetText("—")
        end
        c.total:SetText(Money(rd.total))
    end
    viewport.UpdateRange()
    if headerFade then headerFade:Update() end
end
frame.RefreshWaylaid = RefreshWaylaid

local function SetActiveEconomyView(which)
    if not W.VIEWS[which] or (which == "supply" and not supplyPanel) then
        which = "currency"
    end
    VIEW.active = which
    W.EnsureOptions().activeView = which
    if which ~= "currency" and frame.HideEconomySettings then
        frame.HideEconomySettings()
    end
    currencyPanel:SetShown(which == "currency")
    waylaidPanel:SetShown(which == "waylaid")
    if supplyPanel then supplyPanel:SetShown(which == "supply") end
    if VIEW.tabs then
        VIEW.tabs:SetSelected(which)
    end
    if which == "currency" then
        if frame.RefreshCurrency then frame.RefreshCurrency() end
    elseif which == "waylaid" then
        RefreshWaylaid()
    elseif frame.LayoutSupplyChain then
        frame.LayoutSupplyChain()
    end
    -- The toolbar settings button belongs to the Currency view only.
    if AltArmy.UpdateSearchSettingsButtonGlow then AltArmy.UpdateSearchSettingsButtonGlow() end
end
frame.GetEconomyView = function() return VIEW.active end
frame.SetEconomyView = SetActiveEconomyView

-- Sub-view tabs hang from the panel top into the main window's toolbar row (as on Gear and Cooldowns).
VIEW.tabs = AltArmy.TopTabs.Create(frame, VIEW.defs, {
    onSelect = function(id)
        if VIEW.active ~= id then
            SetActiveEconomyView(id)
        end
    end,
})
VIEW.tabs.frame:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", AltArmy.MainToolbarInsetX or 54, 0)

frame:SetScript("OnShow", function()
    SetActiveEconomyView(W.EnsureOptions().activeView)
end)

-- A finished scan (ours or another addon's) fills the table while it is open.
do
    local S = AltArmy.AuctionScan
    if S and S.OnChange then
        S.OnChange(function(state)
            -- Idle also follows the auction house opening or closing (the scan button comes and goes).
            if not (frame:IsShown() and waylaidPanel:IsShown()) then return end
            if state == "idle" then
                RefreshWaylaid()
            else
                UpdateScanButton()
            end
        end)
    end
end
