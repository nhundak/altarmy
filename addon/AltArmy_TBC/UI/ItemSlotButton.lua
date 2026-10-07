-- AltArmy TBC — an item slot drawn like the stock bag windows (ItemButtonTemplate's pieces, by hand so
-- both clients draw the same): the UI-Quickslot2 slot art, the empty-slot well, the icon, the stack count
-- in the outlined number font and the quality border. Hovering shows the item tooltip; Shift-click links
-- it to chat and Ctrl-click previews it, through UI/ItemActions.lua like the Gear and Search tabs.
-- Used by the Inventory tab for bags, bank and mail attachments.
-- luacheck: globals GameTooltip ITEM_QUALITY_COLORS

AltArmy = AltArmy or {}
AltArmy.ItemSlotButton = AltArmy.ItemSlotButton or {}
local ISB = AltArmy.ItemSlotButton

ISB.SIZE = 37 -- ContainerFrameItemButtonTemplate
ISB.SPACING = 5 -- the stock 42 px pitch
ISB.SLOT_ART_SIZE = 64 -- UI-Quickslot2 is drawn 64 px around a 37 px button
ISB.NORMAL_TEXTURE = "Interface\\Buttons\\UI-Quickslot2"
ISB.PUSHED_TEXTURE = "Interface\\Buttons\\UI-Quickslot-Depress"
ISB.HIGHLIGHT_TEXTURE = "Interface\\Buttons\\ButtonHilight-Square"
ISB.BORDER_TEXTURE = "Interface\\Common\\WhiteIconFrame" -- ItemButtonTemplate's IconBorder
ISB.EMPTY_ATLAS = "bags-item-slot64" -- retail / Forever ContainerFrame (NativeUI caps.bagSlotAtlas)
ISB.EMPTY_TEXTURE = "Interface\\PaperDoll\\UI-Backpack-EmptySlot" -- the classic well
ISB.UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
ISB.MIN_BORDER_QUALITY = 2 -- uncommon and better, as the stock bags

-- Fallbacks for ITEM_QUALITY_COLORS (uncommon, rare, epic, legendary).
local QUALITY_RGB = { [2] = { 0, 1, 0 }, [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 } }

local function resolveCaps(opts)
    if opts and opts.caps then return opts.caps end
    local NativeUI = AltArmy.NativeUI
    return NativeUI and NativeUI.GetCaps and NativeUI.GetCaps() or {}
end

local function countFont()
    local Theme = AltArmy.Theme
    return Theme and Theme.FONTS and Theme.FONTS.count or "NumberFontNormal"
end

--- name, quality, texture for an item id or link, from whichever item API the client has.
local function itemInfo(itemIDOrLink)
    local DS = AltArmy.DataStore
    local name, quality, texture
    if DS and DS.CompatGetItemInfo then
        local n, _, q, _, _, _, _, _, _, t = DS.CompatGetItemInfo(itemIDOrLink)
        name, quality, texture = n, q, t
    elseif _G.GetItemInfo then
        local n, _, q, _, _, _, _, _, _, t = _G.GetItemInfo(itemIDOrLink)
        name, quality, texture = n, q, t
    end
    return name, quality, texture
end

local function itemIcon(itemID)
    if not itemID then return nil end
    if _G.GetItemIcon then
        local icon = _G.GetItemIcon(itemID)
        if icon then return icon end
    end
    local CI = _G.C_Item
    if CI and CI.GetItemIconByID then
        return CI.GetItemIconByID(itemID)
    end
    return nil
end

local function itemQuality(itemID)
    local CI = _G.C_Item
    if itemID and CI and CI.GetItemQualityByID then
        return CI.GetItemQualityByID(itemID)
    end
    return nil
end

--- The border colour for a quality, or nil when no border is drawn.
function ISB.QualityColor(quality)
    if type(quality) ~= "number" or quality < ISB.MIN_BORDER_QUALITY then return nil end
    local c = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality]
    if c and c.r then return c.r, c.g, c.b end
    local f = QUALITY_RGB[quality] or QUALITY_RGB[5]
    return f[1], f[2], f[3]
end

local function onEnter(btn)
    local entry = btn.entry
    if not entry or not GameTooltip then return end
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    if entry.link and entry.link ~= "" then
        GameTooltip:SetHyperlink(entry.link)
    elseif entry.itemID and GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(entry.itemID)
    elseif entry.name then
        GameTooltip:SetText(entry.name)
    else
        GameTooltip:Hide()
        return
    end
    if btn.tooltipExtra then
        btn.tooltipExtra(btn, GameTooltip, entry)
    end
    GameTooltip:Show()
end

local function onLeave()
    if GameTooltip then GameTooltip:Hide() end
end

local function onClick(btn, button)
    local entry = btn.entry
    local IA = AltArmy.ItemActions
    if not entry or not IA then return end
    local target = entry.link or entry.itemID
    if not target then return end
    local shift = _G.IsShiftKeyDown and _G.IsShiftKeyDown()
    local ctrl = _G.IsControlKeyDown and _G.IsControlKeyDown()
    local action = IA.GetClickAction(button, shift, ctrl)
    if action == "preview" then
        IA.PreviewInDressingRoom(target)
    elseif action == "chatlink" then
        IA.InsertLinkIntoChat(target)
    end
end

--- A slot button on `parent`. opts.size (default ISB.SIZE), opts.caps (tests).
function ISB.Create(parent, opts)
    opts = opts or {}
    local caps = resolveCaps(opts)
    local size = opts.size or ISB.SIZE
    local scale = size / ISB.SIZE
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)
    if btn.RegisterForClicks then btn:RegisterForClicks("LeftButtonUp", "RightButtonUp") end

    -- The well behind the icon: the retail atlas where the client has it, else the classic texture.
    local empty = btn:CreateTexture(nil, "BACKGROUND")
    empty:SetAllPoints(btn)
    if caps.bagSlotAtlas and empty.SetAtlas then
        empty:SetAtlas(ISB.EMPTY_ATLAS)
        btn.emptyIsAtlas = true
    else
        empty:SetTexture(ISB.EMPTY_TEXTURE)
    end
    btn.emptyBg = empty

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(btn)
    icon:Hide()
    btn.icon = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture(ISB.BORDER_TEXTURE)
    border:SetSize(size, size)
    border:SetPoint("CENTER", btn, "CENTER", 0, 0)
    border:Hide()
    btn.border = border

    local count = btn:CreateFontString(nil, "OVERLAY", countFont())
    count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -5 * scale, 2 * scale)
    count:SetJustifyH("RIGHT")
    count:Hide()
    btn.count = count

    -- The slot frame around the button (ItemButtonTemplate's NormalTexture), with its push and hover art.
    if btn.SetNormalTexture then
        btn:SetNormalTexture(ISB.NORMAL_TEXTURE)
        local normal = btn.GetNormalTexture and btn:GetNormalTexture()
        if normal and normal.SetSize then
            normal:SetSize(ISB.SLOT_ART_SIZE * scale, ISB.SLOT_ART_SIZE * scale)
            normal:ClearAllPoints()
            normal:SetPoint("CENTER", btn, "CENTER", 0, -1 * scale)
        end
    end
    if btn.SetPushedTexture then btn:SetPushedTexture(ISB.PUSHED_TEXTURE) end
    if btn.SetHighlightTexture then btn:SetHighlightTexture(ISB.HIGHLIGHT_TEXTURE, "ADD") end

    btn:SetScript("OnEnter", onEnter)
    btn:SetScript("OnLeave", onLeave)
    btn:SetScript("OnClick", onClick)
    btn.entry = nil
    return btn
end

--- Show nothing in the slot.
function ISB.SetEmpty(btn)
    btn.entry = nil
    btn.icon:Hide()
    btn.border:Hide()
    btn.count:Hide()
    btn.count:SetText("")
    btn.emptyBg:Show()
end

--- Show an item: entry = { itemID, count, link, icon }. Returns the item id when its icon is not in the
--- client's cache yet (shown as a question mark), so the caller can redraw on GET_ITEM_INFO_RECEIVED.
--- An entry with only `icon` (and a `name` for its tooltip) draws that icon: the bag bar's backpack.
function ISB.SetItem(btn, entry)
    if not entry or not (entry.itemID or entry.link or entry.icon) then
        ISB.SetEmpty(btn)
        return nil
    end
    btn.entry = entry
    local quality, texture
    if entry.itemID or entry.link then
        local _
        _, quality, texture = itemInfo(entry.link or entry.itemID)
    end
    local icon = entry.icon or texture or itemIcon(entry.itemID)
    local pending = nil
    if not icon then
        icon = ISB.UNKNOWN_ICON
        pending = entry.itemID
    end
    btn.icon:SetTexture(icon)
    btn.icon:Show()
    btn.emptyBg:Show()

    if quality == nil and entry.itemID then
        quality = itemQuality(entry.itemID)
    end
    local r, g, b = ISB.QualityColor(quality)
    if r then
        btn.border:SetVertexColor(r, g, b)
        btn.border:Show()
    else
        btn.border:Hide()
    end

    local n = entry.count or 1
    if n > 1 then
        btn.count:SetText(tostring(n))
        btn.count:Show()
    else
        btn.count:SetText("")
        btn.count:Hide()
    end
    return pending
end

--- A pool of slot buttons on `parent`: Acquire() hands out a shown button (made with opts), ReleaseAll()
--- hides them all. `active` lists the buttons handed out since the last release.
function ISB.CreatePool(parent, opts)
    local pool = { free = {}, active = {} }
    function pool.Acquire()
        local btn = table.remove(pool.free)
        if not btn then
            btn = ISB.Create(parent, opts)
        end
        btn:Show()
        pool.active[#pool.active + 1] = btn
        return btn
    end
    function pool.ReleaseAll()
        for i = #pool.active, 1, -1 do
            local btn = pool.active[i]
            pool.active[i] = nil
            ISB.SetEmpty(btn)
            btn:Hide()
            btn:ClearAllPoints()
            pool.free[#pool.free + 1] = btn
        end
    end
    return pool
end
