-- AltArmy TBC — Shared UI theme (warm bronze / dark panel design language).
-- Inspired by AHPriceGraph; Graphs tab values are canonical for AltArmy.
-- Loaded before Core.lua in the .toc; must bootstrap the namespace here.

AltArmy = AltArmy or {}
AltArmy.Theme = AltArmy.Theme or {}

local Theme = AltArmy.Theme

Theme.HOVER_TINT_BG = "Interface\\Tooltips\\UI-Tooltip-Background"
Theme.HOVER_TINT_ALPHA = 0.22

Theme.COLORS = {
    -- Shell: semi-transparent so gaps between opaque section panels show the game through.
    windowBg      = { 0.08, 0.08, 0.10, 0.55 },
    windowBorder  = { 0.45, 0.38, 0.22, 0.75 },
    -- In-tab panels: nearly opaque cards on top of the shell.
    panelBg       = { 0.08, 0.08, 0.10, 0.95 },
    sectionBg     = { 0.10, 0.10, 0.12, 0.95 },
    graphBg       = { 0.08, 0.08, 0.10, 0.95 },
    dialogBg      = { 0.08, 0.08, 0.10, 0.97 },
    inputBg       = { 0.06, 0.06, 0.08, 1.00 },

    panelBorder   = { 0.45, 0.38, 0.22, 0.90 },
    sectionBorder = { 0.45, 0.38, 0.22, 0.90 },
    inputBorder   = { 0.22, 0.22, 0.26, 0.80 },

    sepLine       = { 0.55, 0.46, 0.22, 0.70 },

    title         = { 0.85, 0.78, 0.42, 1.00 },
    label         = { 0.69, 0.69, 0.69, 1.00 },
    value         = { 0.92, 0.92, 0.92, 1.00 },
    groupHeader   = { 0.55, 0.55, 0.60, 1.00 },

    btnBg         = { 0.14, 0.14, 0.18, 1.00 },
    btnBorder     = { 0.28, 0.25, 0.20, 0.90 },
    btnHoverBg    = { 0.20, 0.18, 0.14, 1.00 },
    btnHoverBorder= { 0.45, 0.38, 0.18, 1.00 },
    btnPressBg    = { 0.08, 0.08, 0.10, 1.00 },
    btnActiveBg   = { 0.30, 0.24, 0.08, 1.00 },
    btnActiveBorder = { 0.82, 0.68, 0.22, 1.00 },
    btnText       = { 0.90, 0.88, 0.80, 1.00 },
    btnTextHover  = { 1.00, 0.94, 0.70, 1.00 },

    btnDangerBg       = { 0.24, 0.06, 0.06, 1.00 },
    btnDangerBorder   = { 0.78, 0.20, 0.14, 1.00 },
    btnDangerHoverBg  = { 0.34, 0.08, 0.06, 1.00 },
    btnDangerHoverBorder = { 0.92, 0.28, 0.18, 1.00 },
    btnDangerPressBg  = { 0.16, 0.04, 0.04, 1.00 },
    btnDangerText     = { 1.00, 0.55, 0.45, 1.00 },

    rowHover      = { 0.20, 0.18, 0.12, 0.40 },
    rowSelected   = { 0.22, 0.20, 0.10, 0.60 },
    rowAccent     = { 0.55, 0.46, 0.22, 1.00 },

    gridHeaderBg  = { 0.12, 0.12, 0.15, 1.00 },
    scrollTrack   = { 0.08, 0.08, 0.08, 0.80 },
    scrollThumb   = { 0.50, 0.50, 0.60, 1.00 },

    headerBg      = { 0.10, 0.10, 0.12, 0.65 },
    settingsGlow  = { 1.00, 0.82, 0.20, 0.55 },

    green         = { 0.20, 0.85, 0.35, 1.00 },
    red           = { 1.00, 0.28, 0.18, 1.00 },
    yellow        = { 0.92, 0.82, 0.18, 1.00 },

    -- Graph tooltip palette (aligned with GraphCore)
    tooltipBg     = { 0.12, 0.12, 0.14, 0.97 },
    tooltipBorder = { 0.70, 0.58, 0.28, 0.90 },
}

local C = Theme.COLORS

local BG_FILE = "Interface\\ChatFrame\\ChatFrameBackground"
local EDGE_FILE = "Interface\\Tooltips\\UI-Tooltip-Border"

Theme.WINDOW_BACKDROP = {
    bgFile = BG_FILE,
    edgeFile = EDGE_FILE,
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

Theme.SECTION_BACKDROP = {
    bgFile = BG_FILE,
    edgeFile = EDGE_FILE,
    tile = false,
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

Theme.GRAPH_BACKDROP = Theme.SECTION_BACKDROP

Theme.TOOLTIP_BACKDROP = {
    bgFile = BG_FILE,
    edgeFile = EDGE_FILE,
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

Theme.BUTTON_BACKDROP = {
    bgFile = BG_FILE,
    edgeFile = EDGE_FILE,
    tile = false,
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

local TIER_BACKDROP = {
    window = Theme.WINDOW_BACKDROP,
    section = Theme.SECTION_BACKDROP,
    graph = Theme.GRAPH_BACKDROP,
    tooltip = Theme.TOOLTIP_BACKDROP,
    button = Theme.BUTTON_BACKDROP,
}

local TIER_BG = {
    window = C.windowBg,
    dialog = C.dialogBg,
    section = C.sectionBg,
    graph = C.graphBg,
    tooltip = C.tooltipBg,
    button = C.btnBg,
}

local TIER_BORDER = {
    window = C.windowBorder,
    dialog = C.panelBorder,
    section = C.sectionBorder,
    graph = C.sectionBorder,
    tooltip = C.tooltipBorder,
    button = C.btnBorder,
}

function Theme.EnsureBackdrop(frame)
    if frame.SetBackdrop then return end
    if Mixin and BackdropTemplateMixin then
        Mixin(frame, BackdropTemplateMixin)
        if frame.HookScript and frame.OnBackdropSizeChanged then
            frame:HookScript("OnSizeChanged", frame.OnBackdropSizeChanged)
        end
    end
end

function Theme.ApplyBackdrop(frame, tier)
    if not frame then return end
    Theme.EnsureBackdrop(frame)
    if not frame.SetBackdrop then return end

    local backdrop = TIER_BACKDROP[tier] or TIER_BACKDROP.section
    local bg = TIER_BG[tier] or C.sectionBg
    local border = TIER_BORDER[tier] or C.sectionBorder

    frame:SetBackdrop(backdrop)
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    if frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
    end
end

function Theme.CreatePanel(parent, tier, name)
    local frame = CreateFrame("Frame", name, parent, "BackdropTemplate")
    Theme.ApplyBackdrop(frame, tier or "section")
    return frame
end

local function applyButtonColors(btn, bg, border)
    if not btn or not btn.SetBackdropColor then return end
    btn:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    if btn.SetBackdropBorderColor and border then
        btn:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
    end
end

local function getButtonFontString(btn)
    if btn.GetFontString then
        local fs = btn:GetFontString()
        if fs then return fs end
    end
    return btn.label
end

local function setButtonTextColor(btn, color)
    local fs = getButtonFontString(btn)
    if fs and fs.SetTextColor and color then
        fs:SetTextColor(color[1], color[2], color[3])
    end
end

local function stripButtonTemplate(btn)
    if btn.Left then btn.Left:SetAlpha(0) end
    if btn.Right then btn.Right:SetAlpha(0) end
    if btn.Middle then btn.Middle:SetAlpha(0) end
    local nt = btn.GetNormalTexture and btn:GetNormalTexture()
    if nt and nt.SetTexture then nt:SetTexture(nil) end
    local ht = btn.GetHighlightTexture and btn:GetHighlightTexture()
    if ht and ht.SetTexture then ht:SetTexture(nil) end
    local pt = btn.GetPushedTexture and btn:GetPushedTexture()
    if pt and pt.SetTexture then pt:SetTexture(nil) end
end

function Theme.SkinButton(btn, isToggle)
    if not btn or btn._skinned then return end
    btn._skinned = true

    stripButtonTemplate(btn)

    Theme.ApplyBackdrop(btn, "button")
    setButtonTextColor(btn, C.btnText)

    local function restoreNormal(self)
        if self._selected then
            applyButtonColors(self, C.btnActiveBg, C.btnActiveBorder)
            setButtonTextColor(self, C.btnTextHover)
        else
            applyButtonColors(self, C.btnBg, C.btnBorder)
            setButtonTextColor(self, C.btnText)
        end
    end

    if btn.HookScript then
        btn:HookScript("OnEnter", function(self)
            if not self._selected then
                applyButtonColors(self, C.btnHoverBg, C.btnHoverBorder)
            end
            setButtonTextColor(self, C.btnTextHover)
        end)
        btn:HookScript("OnLeave", restoreNormal)
        btn:HookScript("OnMouseDown", function(self)
            applyButtonColors(self, C.btnPressBg, C.btnBorder)
        end)
        btn:HookScript("OnMouseUp", restoreNormal)
    end

    if isToggle then
        btn.SetSelected = function(self, on)
            self._selected = on
            if on then
                applyButtonColors(self, C.btnActiveBg, C.btnActiveBorder)
                setButtonTextColor(self, C.btnTextHover)
            else
                applyButtonColors(self, C.btnBg, C.btnBorder)
                setButtonTextColor(self, C.btnText)
            end
        end
    end
end

function Theme.SkinDangerButton(btn)
    if not btn or btn._skinned then return end
    btn._skinned = true
    stripButtonTemplate(btn)
    Theme.ApplyBackdrop(btn, "button")
    applyButtonColors(btn, C.btnDangerBg, C.btnDangerBorder)
    setButtonTextColor(btn, C.btnDangerText)

    local function restoreNormal(self)
        applyButtonColors(self, C.btnDangerBg, C.btnDangerBorder)
        setButtonTextColor(self, C.btnDangerText)
    end

    if btn.HookScript then
        btn:HookScript("OnEnter", function(self)
            applyButtonColors(self, C.btnDangerHoverBg, C.btnDangerHoverBorder)
            setButtonTextColor(self, C.red)
        end)
        btn:HookScript("OnLeave", restoreNormal)
        btn:HookScript("OnMouseDown", function(self)
            applyButtonColors(self, C.btnDangerPressBg, C.btnDangerBorder)
        end)
        btn:HookScript("OnMouseUp", restoreNormal)
    end
end

function Theme.InstallHoverTint(target, layerOrBandHeight, bandCenter, bandYOffset)
    if not target or target.altArmyHoverTint then return end
    local layer = "BACKGROUND"
    local bandHeight = nil
    if type(layerOrBandHeight) == "string" then
        layer = layerOrBandHeight
    elseif type(layerOrBandHeight) == "number" then
        bandHeight = layerOrBandHeight
    end
    bandYOffset = bandYOffset or 0
    local t = target:CreateTexture(nil, layer)
    t:SetTexture(Theme.HOVER_TINT_BG)
    if bandHeight then
        t:SetPoint("LEFT", target, "LEFT", 0, bandYOffset)
        t:SetPoint("RIGHT", target, "RIGHT", 0, bandYOffset)
        t:SetHeight(bandHeight)
        if bandCenter then
            t:SetPoint("CENTER", target, "CENTER", 0, bandYOffset)
        else
            t:SetPoint("TOP", target, "TOP", 0, bandYOffset)
        end
    else
        t:SetAllPoints(true)
    end
    t:SetVertexColor(1, 1, 1, 0)
    target.altArmyHoverTint = t
end

function Theme.SetHoverTint(target, on)
    local t = target and target.altArmyHoverTint
    if t then
        t:SetVertexColor(1, 1, 1, on and Theme.HOVER_TINT_ALPHA or 0)
    end
end

--- Tab-strip settings gear: yellow square glow on hover (matches active settings state).
function Theme.InstallSettingsButtonGlow(btn, key)
    if not btn then return nil end
    key = key or "glow"
    if btn[key] then return btn[key] end
    local glow = btn:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("TOPLEFT", btn, "TOPLEFT", -3, 3)
    glow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 3, -3)
    Theme.ApplySettingsGlow(glow)
    glow:Hide()
    btn[key] = glow
    return glow
end

function Theme.SetSettingsButtonGlow(btn, on, key)
    local glow = btn and btn[key or "glow"]
    if glow and glow.SetShown then
        glow:SetShown(on)
    end
end

function Theme.SkinSettingsIconButton(btn)
    if not btn or btn._settingsIconSkinned then return end
    btn._settingsIconSkinned = true

    Theme.InstallSettingsButtonGlow(btn, "hoverGlow")

    local function setHoverGlow(on)
        if btn.glow and btn.glow.IsShown and btn.glow:IsShown() then
            return
        end
        Theme.SetSettingsButtonGlow(btn, on, "hoverGlow")
    end

    if btn.HookScript then
        btn:HookScript("OnEnter", function()
            setHoverGlow(true)
        end)
        btn:HookScript("OnLeave", function()
            setHoverGlow(false)
        end)
    end
end

--- Wire OnEnter/OnLeave row highlight (Graphs Compare panel style).
function Theme.BindInteractableHover(target, opts)
    if not target then return end
    opts = opts or {}
    Theme.InstallHoverTint(target, opts.bandHeight or opts.layer, opts.bandCenter, opts.bandYOffset)
    local function onEnter()
        Theme.SetHoverTint(target, true)
        if opts.onEnter then opts.onEnter(target) end
    end
    local function onLeave()
        Theme.SetHoverTint(target, false)
        if opts.onLeave then opts.onLeave(target) end
    end
    if target.EnableMouse then target:EnableMouse(true) end
    target:SetScript("OnEnter", onEnter)
    target:SetScript("OnLeave", onLeave)
    if opts.children then
        for i = 1, #opts.children do
            local child = opts.children[i]
            if child then
                if child.EnableMouse then child:EnableMouse(true) end
                child:SetScript("OnEnter", onEnter)
                child:SetScript("OnLeave", onLeave)
            end
        end
    end
    return onEnter, onLeave
end

function Theme.InstallRowHoverHighlight(row)
    if not row or row.altArmyRowHighlight then return end
    local highlight = row:CreateTexture(nil, "BACKGROUND")
    highlight:SetTexture(BG_FILE)
    highlight:SetAllPoints(row)
    highlight:SetVertexColor(C.rowHover[1], C.rowHover[2], C.rowHover[3], C.rowHover[4])
    row:SetHighlightTexture(highlight)
    row.altArmyRowHighlight = highlight
end

function Theme.InstallRowAccentBar(row)
    if not row or row.altArmyAccentBar then return end
    local bar = row:CreateTexture(nil, "ARTWORK")
    bar:SetWidth(2)
    bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    bar:SetColorTexture(C.rowAccent[1], C.rowAccent[2], C.rowAccent[3], C.rowAccent[4])
    bar:Hide()
    row.altArmyAccentBar = bar
end

function Theme.SetRowSelected(row, on)
    if not row then return end
    if row.altArmyRowBg and row.altArmyRowBg.SetVertexColor then
        if on then
            row.altArmyRowBg:SetVertexColor(C.rowSelected[1], C.rowSelected[2], C.rowSelected[3], C.rowSelected[4])
        else
            row.altArmyRowBg:SetVertexColor(0, 0, 0, 0)
        end
    end
    if row.altArmyAccentBar then
        if on then row.altArmyAccentBar:Show() else row.altArmyAccentBar:Hide() end
    end
end

Theme.SCROLL_KNOB_TEXTURE = "Interface\\Buttons\\UI-ScrollBar-Knob"
Theme.SCROLL_THUMB_LENGTH = 24
Theme.SCROLL_BAR_WIDTH = 14
Theme.SCROLL_BAR_GAP = 2 -- space between scroll viewport and track
Theme.SCROLL_BAR_RIGHT_INSET = 4 -- track ends this far inside the bronze border (Graphs Compare panel)

function Theme.StyleScrollKnob(texture)
    if texture then
        texture:SetTexture(Theme.SCROLL_KNOB_TEXTURE)
    end
end

--- @deprecated use StyleScrollKnob or SetupScrollBar
function Theme.StyleScrollThumb(texture)
    Theme.StyleScrollKnob(texture)
end

function Theme.StyleScrollTrack(texture)
    if not texture then return end
    local track = C.scrollTrack
    texture:SetColorTexture(track[1], track[2], track[3], track[4])
end

--- Apply Compare-panel scrollbar chrome: dark track + Blizzard knob thumb.
--- opts.thickness: bar width (vertical) or height (horizontal); defaults from slider size.
--- opts.thumbLength: knob length along the scroll axis (default 24).
--- opts.horizontal: true for horizontal scroll bars.
function Theme.SetupScrollBar(slider, opts)
    if not slider then return nil end
    opts = opts or {}
    local horizontal = opts.horizontal == true
    local thumbLength = opts.thumbLength or Theme.SCROLL_THUMB_LENGTH
    local thickness = opts.thickness
    if not thickness then
        if horizontal and slider.GetHeight then
            thickness = slider:GetHeight() or 14
        elseif slider.GetWidth then
            thickness = slider:GetWidth() or 14
        else
            thickness = 14
        end
    end

    if not slider.altArmyScrollTrack then
        local track = slider:CreateTexture(nil, "BACKGROUND")
        track:SetAllPoints(slider)
        slider.altArmyScrollTrack = track
    end
    Theme.StyleScrollTrack(slider.altArmyScrollTrack)

    local thumb = slider.altArmyScrollThumb
    if not thumb then
        thumb = slider:CreateTexture(nil, "OVERLAY")
        slider.altArmyScrollThumb = thumb
    end
    if horizontal then
        thumb:SetSize(thumbLength, thickness + 4)
    else
        thumb:SetSize(thickness + 4, thumbLength)
    end
    Theme.StyleScrollKnob(thumb)
    slider:SetThumbTexture(thumb)
    return thumb
end

--- Horizontal space reserved beside a vertical scroll viewport (inset + track + gap).
function Theme.VerticalScrollBarGutter(opts)
    opts = opts or {}
    local w = opts.width or Theme.SCROLL_BAR_WIDTH
    local gap = opts.gap or Theme.SCROLL_BAR_GAP
    local inset = opts.rightInset
    if inset == nil then
        inset = Theme.SCROLL_BAR_RIGHT_INSET
    end
    return w + gap + inset
end

--- Anchor a vertical scrollbar beside scrollFrame; track ends rightInset inside gutterEdge's right edge.
--- scrollFrame should end at -(VerticalScrollBarGutter()) from gutterEdge's right edge.
function Theme.AnchorVerticalScrollBar(scrollBar, _gutterEdge, scrollFrame, opts)
    if not scrollBar or not scrollFrame then return scrollBar end
    opts = opts or {}
    local w = opts.width or Theme.SCROLL_BAR_WIDTH
    local gap = opts.gap or Theme.SCROLL_BAR_GAP
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:SetWidth(w)
    scrollBar:ClearAllPoints()
    scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", gap, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", gap, 0)
    Theme.SetupScrollBar(scrollBar, { thickness = w, thumbLength = opts.thumbLength })
    return scrollBar
end

function Theme.StyleGridHeader(texture)
    if not texture then return end
    local hdr = C.gridHeaderBg
    texture:SetColorTexture(hdr[1], hdr[2], hdr[3], hdr[4])
end

Theme.SETTINGS_PANEL_PADDING = 8
Theme.TAB_CONTENT_PADDING = 8
-- Section panels sit flush on the tab frame; Core CONTENT_INSET (8px) is the window-edge gutter.
Theme.TAB_SECTION_INSET = 0
-- Gap between adjacent section panels within a tab (Graphs tab graph | selector).
Theme.SECTION_GAP = 4

--- Bordered section panel for main tab content (matches settings panel styling).
function Theme.CreateTabContentPanel(parent)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Theme.ApplyBackdrop(panel, "section")
    return panel
end

--- Inset content area inside a bordered panel (keeps controls off the edge).
function Theme.CreatePanelInnerContent(panel, padding)
    local p = padding or Theme.TAB_CONTENT_PADDING
    local content = CreateFrame("Frame", nil, panel)
    content:SetPoint("TOPLEFT", panel, "TOPLEFT", p, -p)
    content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -p, p)
    return content
end

--- Inset content area inside a bordered settings panel (keeps controls off the edge).
function Theme.CreateSettingsPanelContent(panel)
    return Theme.CreatePanelInnerContent(panel, Theme.SETTINGS_PANEL_PADDING)
end

function Theme.CreateSeparator(parent, width)
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    if width then
        sep:SetWidth(width)
    else
        sep:SetPoint("LEFT", parent, "LEFT", 0, 0)
        sep:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    end
    local line = C.sepLine
    sep:SetColorTexture(line[1], line[2], line[3], line[4])
    return sep
end

function Theme.ApplyInputTextures(editBox)
    if not editBox then return end
    if not editBox.altArmyInputBg then
        local bg = editBox:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(editBox)
        editBox.altArmyInputBg = bg
        local border = editBox:CreateTexture(nil, "BORDER")
        border:SetPoint("TOPLEFT", editBox, "TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", editBox, "BOTTOMRIGHT", 1, -1)
        editBox.altArmyInputBorder = border
    end
    local ibg = C.inputBg
    local ibr = C.inputBorder
    editBox.altArmyInputBg:SetColorTexture(ibg[1], ibg[2], ibg[3], ibg[4])
    editBox.altArmyInputBorder:SetColorTexture(ibr[1], ibr[2], ibr[3], ibr[4])
end

function Theme.SetTitleColor(fontString)
    if fontString and fontString.SetTextColor then
        local t = C.title
        fontString:SetTextColor(t[1], t[2], t[3], t[4])
    end
end

function Theme.SetGroupHeaderColor(fontString)
    if fontString and fontString.SetTextColor then
        local g = C.groupHeader
        fontString:SetTextColor(g[1], g[2], g[3], g[4])
    end
end

function Theme.SetLabelColor(fontString)
    if fontString and fontString.SetTextColor then
        local l = C.label
        fontString:SetTextColor(l[1], l[2], l[3], l[4])
    end
end

function Theme.ApplyHeaderBar(texture)
    if not texture then return end
    local h = C.headerBg
    texture:SetColorTexture(h[1], h[2], h[3], h[4])
end

function Theme.ApplySettingsGlow(texture)
    if not texture then return end
    local g = C.settingsGlow
    texture:SetColorTexture(g[1], g[2], g[3], g[4])
end

function Theme.StyleHorizontalScrollBar(slider, opts)
    if not slider then return end
    local o = opts or {}
    o.horizontal = true
    Theme.SetupScrollBar(slider, o)
end

--- Scale-aware horizontal drag math shared by tab horizontal scroll bars.
--- thumbLength: knob size along the scroll axis; the thumb travels (barWidth - thumbLength).
function Theme.HorizontalDragValue(startValue, cursorPx, startPx, scale, barWidth, minVal, maxVal, thumbLength)
    if not barWidth or barWidth <= 0 or not scale or scale <= 0 or maxVal <= minVal then
        return startValue
    end
    local cursorX = cursorPx / scale
    local startX = startPx / scale
    local deltaX = cursorX - startX
    local travel = barWidth - (thumbLength or 0)
    if travel <= 0 then
        travel = barWidth
    end
    local value = startValue + deltaX * (maxVal - minVal) / travel
    return math.max(minVal, math.min(maxVal, value))
end

--- Horizontal scrollbar with manual scale-aware thumb drag (TBC Slider workaround).
--- opts: name, thickness, onScroll(value), isShown() -> bool
function Theme.CreateHorizontalScrollBar(parent, opts)
    opts = opts or {}
    local bar = CreateFrame("Slider", opts.name, parent)
    bar:SetOrientation("HORIZONTAL")
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(1)
    bar:SetValue(0)
    bar:EnableMouse(true)

    local thumbLength = opts.thumbLength or Theme.SCROLL_THUMB_LENGTH
    local lastValue = nil
    local dragging = false
    local dragStartX = 0
    local dragStartValue = 0

    local function apply(value)
        lastValue = value
        if opts.onScroll then
            opts.onScroll(value)
        end
    end

    local function sync()
        local value = bar:GetValue()
        if lastValue == value then return end
        apply(value)
    end

    local function stopDragging()
        if not dragging then return end
        dragging = false
        bar:SetScript("OnUpdate", nil)
        if opts.onDragEnd then opts.onDragEnd() end
    end

    bar:SetScript("OnValueChanged", function()
        sync()
    end)

    bar:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        dragging = true
        dragStartX = select(1, GetCursorPosition())
        dragStartValue = bar:GetValue()
        if opts.onDragStart then opts.onDragStart() end
        bar:SetScript("OnUpdate", function()
            if opts.isShown and not opts.isShown() then return end
            if not dragging then return end
            if not IsMouseButtonDown(1) then
                stopDragging()
                return
            end
            local minVal, maxVal = bar:GetMinMaxValues()
            local barWidth = bar:GetWidth()
            if barWidth and barWidth > 0 and maxVal > minVal then
                local scale = (bar.GetEffectiveScale and bar:GetEffectiveScale())
                    or (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
                if scale <= 0 then scale = 1 end
                local cursorX = select(1, GetCursorPosition())
                local value = Theme.HorizontalDragValue(
                    dragStartValue, cursorX, dragStartX, scale, barWidth, minVal, maxVal, thumbLength)
                if lastValue == nil or math.abs(value - lastValue) >= 0.5 then
                    bar:SetValue(value)
                end
            end
        end)
    end)

    if opts.thickness then
        bar:SetHeight(opts.thickness)
    end
    Theme.SetupScrollBar(bar, {
        horizontal = true,
        thickness = opts.thickness,
        thumbLength = thumbLength,
    })

    local api = {}
    api.bar = bar

    function api:SetRange(minVal, maxVal)
        bar:SetMinMaxValues(minVal, maxVal)
    end

    function api:Apply(value)
        apply(value)
    end

    function api:Sync()
        sync()
    end

    function api:Reset()
        bar:SetValue(0)
        apply(0)
    end

    return api
end

--- Max vertical scroll offset from content and viewport heights.
function Theme.ScrollMax(childHeight, viewHeight)
    return math.max(0, (childHeight or 0) - (viewHeight or 0))
end

--- Clamp a scroll offset to [0, maxScroll].
function Theme.ClampScroll(offset, maxScroll)
    return math.max(0, math.min(maxScroll or 0, offset or 0))
end

--- Vertical ScrollFrame + Slider + wheel handler with unified range/clamp behavior.
--- opts: parent, gutterEdge, name, anchorTop/anchorBottom tables {point, rel, relPoint, x, y},
--- valueStep, wheelStep, wheelSource ("scroll"|"slider"), wheelOnChild, enableMouse, enableMouseWheel,
--- syncChildWidth, fallbackViewHeight, minScrollToShow
function Theme.CreateVerticalScrollViewport(opts)
    opts = opts or {}
    local parent = opts.parent
    local gutterEdge = opts.gutterEdge or parent
    local scroll = CreateFrame("ScrollFrame", opts.name, parent)

    local function anchorFrame(frame, spec)
        if spec then
            frame:SetPoint(spec[1], spec[2], spec[3], spec[4], spec[5])
        end
    end
    anchorFrame(scroll, opts.anchorTop)
    anchorFrame(scroll, opts.anchorBottom)

    if opts.enableMouse then
        scroll:EnableMouse(true)
    end
    if opts.enableMouseWheel then
        scroll:EnableMouseWheel(true)
    end

    local valueStep = opts.valueStep or Theme.CHAR_LIST_ROW_HEIGHT
    local wheelStep = opts.wheelStep or (valueStep * 2)
    local wheelSource = opts.wheelSource or "scroll"
    local wheelOnChild = opts.wheelOnChild ~= false
    local minScrollToShow = opts.minScrollToShow or 0

    local scrollBar = CreateFrame("Slider", nil, gutterEdge)
    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:SetValueStep(valueStep)
    scrollBar:SetValue(0)
    scrollBar:EnableMouse(true)
    Theme.AnchorVerticalScrollBar(scrollBar, gutterEdge, scroll)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    child:SetWidth(opts.childWidth or 1)
    scroll:SetScrollChild(child)

    local function viewHeight()
        local h = scroll:GetHeight() or 0
        if h <= 0 and opts.fallbackViewHeight then
            return opts.fallbackViewHeight
        end
        return h
    end

    local function maxScroll()
        return Theme.ScrollMax(child:GetHeight(), viewHeight())
    end

    local function setOffset(offset)
        local maxVal = maxScroll()
        local value = Theme.ClampScroll(offset, maxVal)
        scroll:SetVerticalScroll(value)
        scrollBar:SetValue(value)
    end

    local function updateRange()
        local maxVal = maxScroll()
        local cur = scroll:GetVerticalScroll()
        cur = Theme.ClampScroll(cur, maxVal)
        scroll:SetVerticalScroll(cur)
        scrollBar:SetMinMaxValues(0, maxVal)
        scrollBar:SetValueStep(valueStep)
        scrollBar:SetValue(cur)
        scrollBar:SetShown(maxVal > minScrollToShow)
    end

    scrollBar:SetScript("OnValueChanged", function(_, value)
        scroll:SetVerticalScroll(value)
    end)

    local function onWheel(_, delta)
        if wheelSource == "slider" then
            local cur = scrollBar:GetValue()
            local lo, hi = scrollBar:GetMinMaxValues()
            scrollBar:SetValue(math.max(lo, math.min(hi, cur - delta * wheelStep)))
        else
            setOffset(scroll:GetVerticalScroll() - delta * wheelStep)
        end
    end

    scroll:SetScript("OnMouseWheel", onWheel)
    if wheelOnChild then
        child:SetScript("OnMouseWheel", onWheel)
    end

    if opts.syncChildWidth ~= false then
        scroll:SetScript("OnSizeChanged", function(s, w)
            child:SetWidth(w or s:GetWidth() or 1)
            updateRange()
        end)
    end

    local api = {
        scroll = scroll,
        child = child,
        scrollBar = scrollBar,
        UpdateRange = updateRange,
        SetOffset = setOffset,
    }
    return api
end

function Theme.ApplyCheckboxBackground(texture)
    if not texture then return end
    local bg = C.inputBg
    texture:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
end

Theme.CHAR_LIST_CHECKBOX_SIZE = 18
Theme.CHAR_LIST_ROW_HEIGHT = 20

--- Themed checkbox chrome (background + check texture); callers own layout and labels.
function Theme.CreateThemeCheckbox(parent, size)
    local checkSize = size or Theme.CHAR_LIST_CHECKBOX_SIZE
    local check = CreateFrame("CheckButton", nil, parent)
    check:SetSize(checkSize, checkSize)
    local checkBg = check:CreateTexture(nil, "BACKGROUND")
    checkBg:SetAllPoints(check)
    Theme.ApplyCheckboxBackground(checkBg)
    local checkTex = check:CreateTexture(nil, "OVERLAY")
    checkTex:SetAllPoints(check)
    checkTex:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:SetCheckedTexture(checkTex)
    return check
end

--- Settings-row checkbox matching CharacterPinHideList (18px, hover band, label toggles).
function Theme.CreateLabeledCheckbox(parent, opts)
    opts = opts or {}
    local rowHeight = opts.rowHeight or Theme.CHAR_LIST_ROW_HEIGHT
    local checkSize = opts.checkSize or Theme.CHAR_LIST_CHECKBOX_SIZE

    local row = CreateFrame("Frame", nil, parent)
    if opts.relativeTo then
        row:SetPoint(opts.point or "TOPLEFT", opts.relativeTo, opts.relativePoint or "TOPLEFT",
            opts.x or 0, opts.y or 0)
    else
        row:SetPoint(opts.point or "TOPLEFT", parent, opts.relativePoint or "TOPLEFT", opts.x or 0, opts.y or 0)
    end
    row:SetHeight(rowHeight)
    local rightInset = opts.rightInset or 0
    row:SetPoint("RIGHT", parent, "RIGHT", -rightInset, 0)

    local hoverRegion = CreateFrame("Frame", nil, row)
    if opts.fullWidthHover then
        hoverRegion:SetAllPoints(row)
    else
        hoverRegion:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        hoverRegion:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    end
    Theme.InstallHoverTint(hoverRegion)

    local check = Theme.CreateThemeCheckbox(row, checkSize)
    check:SetPoint("LEFT", row, "LEFT", 0, 0)

    local label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    label:SetText(opts.text or "")

    if not opts.fullWidthHover then
        hoverRegion:SetPoint("RIGHT", label, "RIGHT", 4, 0)
    end
    hoverRegion:EnableMouse(true)
    hoverRegion:SetScript("OnEnter", function()
        Theme.SetHoverTint(hoverRegion, true)
    end)
    hoverRegion:SetScript("OnLeave", function()
        Theme.SetHoverTint(hoverRegion, false)
    end)
    hoverRegion:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            check:Click()
        end
    end)

    check:HookScript("OnEnter", function()
        Theme.SetHoverTint(hoverRegion, true)
    end)
    check:HookScript("OnLeave", function()
        Theme.SetHoverTint(hoverRegion, false)
    end)

    if opts.onClick then
        check:SetScript("OnClick", function()
            opts.onClick(check:GetChecked())
        end)
    end

    hoverRegion:SetFrameLevel(row:GetFrameLevel())
    check:SetFrameLevel(row:GetFrameLevel() + 4)

    row.check = check
    row.label = label
    row.hoverRegion = hoverRegion
    return row
end

local SETTINGS_INFO_ICON_SIZE = 14

--- Help icon on the right of a settings row; tooltip matches Graphs option rows (title + gray body).
function Theme.AttachSettingsHelpIcon(row, tooltipOpts)
    tooltipOpts = tooltipOpts or {}
    local title = tooltipOpts.title or ""
    local lines = tooltipOpts.lines or {}

    local btn = CreateFrame("Button", nil, row)
    btn:SetSize(SETTINGS_INFO_ICON_SIZE, SETTINGS_INFO_ICON_SIZE)
    btn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(btn)
    tex:SetTexture("Interface\\Common\\help-i")

    if row.label then
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
        row.label:SetPoint("RIGHT", btn, "LEFT", -4, 0)
        row.label:SetJustifyH("LEFT")
    end

    local tooltipAnchor = row

    local function showTooltip()
        if not GameTooltip or not tooltipAnchor then return end
        GameTooltip:SetOwner(tooltipAnchor, "ANCHOR_NONE")
        GameTooltip:ClearLines()
        if title ~= "" then
            GameTooltip:AddLine(title, 1, 1, 1, true)
        end
        for i = 1, #lines do
            GameTooltip:AddLine(lines[i], 0.9, 0.9, 0.9, true)
        end
        GameTooltip:SetPoint("TOPLEFT", tooltipAnchor, "TOPRIGHT", 8, 0)
        GameTooltip:Show()
    end

    local function hideTooltip()
        if GameTooltip then GameTooltip:Hide() end
    end

    local function onTooltipEnter()
        if row.hoverRegion then
            Theme.SetHoverTint(row.hoverRegion, true)
        end
        showTooltip()
    end

    local function onTooltipLeave()
        if row.hoverRegion then
            Theme.SetHoverTint(row.hoverRegion, false)
        end
        hideTooltip()
    end

    btn:SetScript("OnEnter", onTooltipEnter)
    btn:SetScript("OnLeave", onTooltipLeave)

    if row.hoverRegion then
        row.hoverRegion:HookScript("OnEnter", showTooltip)
        row.hoverRegion:HookScript("OnLeave", hideTooltip)
    end
    if row.check then
        row.check:HookScript("OnEnter", showTooltip)
        row.check:HookScript("OnLeave", hideTooltip)
    end

    row.helpBtn = btn
    return btn
end

function Theme.ApplyDropdownBackground(frame)
    if not frame then return end
    Theme.ApplyBackdrop(frame, "section")
end

local DROPDOWN_MENU_PAD_TOP = 2
local DROPDOWN_MENU_PAD_SIDE = 2

--- Single selectable row inside a custom dropdown popup (hover matches settings list rows).
function Theme.CreateDropdownMenuItem(parent, opts)
    opts = opts or {}
    local rowHeight = opts.rowHeight or Theme.CHAR_LIST_ROW_HEIGHT or 20
    local padTop = opts.padTop or DROPDOWN_MENU_PAD_TOP
    local padSide = opts.padSide or DROPDOWN_MENU_PAD_SIDE
    local idx = opts.index or 1

    local btn = CreateFrame("Button", nil, parent)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", padSide, -padTop - (idx - 1) * rowHeight)
    btn:SetPoint("LEFT", parent, "LEFT", padSide, 0)
    btn:SetPoint("RIGHT", parent, "RIGHT", -padSide, 0)
    btn:SetHeight(rowHeight - 2)

    Theme.BindInteractableHover(btn)

    local selBg = btn:CreateTexture(nil, "ARTWORK")
    selBg:SetAllPoints(true)
    selBg:SetColorTexture(C.rowSelected[1], C.rowSelected[2], C.rowSelected[3], C.rowSelected[4])
    selBg:Hide()
    btn.altArmyDropdownSelectedBg = selBg

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", btn, "LEFT", 4, 0)
    label:SetText(opts.text or "")
    btn.label = label

    function btn:SetDropdownSelected(on)
        selBg:SetShown(on == true)
    end
    btn:SetDropdownSelected(opts.selected == true)

    if opts.onClick then
        btn:SetScript("OnClick", function(self)
            opts.onClick(self)
        end)
    end

    return btn
end

-- luacheck: globals UIDROPDOWNMENU_MENU_LEVEL UIDROPDOWNMENU_MAXLEVELS UIDROPDOWNMENU_MAXBUTTONS
local hooksecurefunc = _G.hooksecurefunc

local function SkinBlizzardDropdownListButton(button)
    if not button or button._altArmyDropdownHover then return end
    button._altArmyDropdownHover = true
    Theme.InstallHoverTint(button)
    local ht = button.GetHighlightTexture and button:GetHighlightTexture()
    if ht and ht.SetAlpha then
        ht:SetAlpha(0)
    end
    if button.HookScript then
        button:HookScript("OnEnter", function()
            Theme.SetHoverTint(button, true)
        end)
        button:HookScript("OnLeave", function()
            Theme.SetHoverTint(button, false)
        end)
    end
end

local function SkinVisibleBlizzardDropdownButtons()
    local maxLevel = UIDROPDOWNMENU_MAXLEVELS or 2
    local maxButtons = UIDROPDOWNMENU_MAXBUTTONS or 32
    for level = 1, maxLevel do
        local listName = "DropDownList" .. level
        for i = 1, maxButtons do
            local button = _G[listName .. "Button" .. i]
            if button and button.IsShown and button:IsShown() then
                SkinBlizzardDropdownListButton(button)
            end
        end
    end
end

--- Hover highlight on Blizzard UIDropDownMenu list rows (Options, Cooldowns, etc.).
function Theme.InstallBlizzardDropdownListHover()
    if Theme._blizzardDropdownHoverInstalled then return end
    Theme._blizzardDropdownHoverInstalled = true
    if not hooksecurefunc then return end
    hooksecurefunc("UIDropDownMenu_AddButton", function()
        SkinVisibleBlizzardDropdownButtons()
    end)
end

Theme.InstallBlizzardDropdownListHover()
