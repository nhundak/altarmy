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
    btnActiveBg   = { 0.18, 0.16, 0.10, 1.00 },
    btnActiveBorder = { 0.55, 0.46, 0.22, 1.00 },
    btnText       = { 0.90, 0.88, 0.80, 1.00 },
    btnTextHover  = { 1.00, 0.94, 0.70, 1.00 },

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

function Theme.SkinButton(btn, isToggle)
    if not btn or btn._skinned then return end
    btn._skinned = true

    if btn.Left then btn.Left:SetAlpha(0) end
    if btn.Right then btn.Right:SetAlpha(0) end
    if btn.Middle then btn.Middle:SetAlpha(0) end
    local nt = btn.GetNormalTexture and btn:GetNormalTexture()
    if nt and nt.SetTexture then nt:SetTexture(nil) end
    local ht = btn.GetHighlightTexture and btn:GetHighlightTexture()
    if ht and ht.SetTexture then ht:SetTexture(nil) end
    local pt = btn.GetPushedTexture and btn:GetPushedTexture()
    if pt and pt.SetTexture then pt:SetTexture(nil) end

    Theme.ApplyBackdrop(btn, "button")
    setButtonTextColor(btn, C.btnText)

    local function restoreNormal(self)
        if self._selected then
            applyButtonColors(self, C.btnActiveBg, C.btnActiveBorder)
        else
            applyButtonColors(self, C.btnBg, C.btnBorder)
        end
        setButtonTextColor(self, C.btnText)
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
            else
                applyButtonColors(self, C.btnBg, C.btnBorder)
            end
        end
    end
end

function Theme.InstallHoverTint(target, layer)
    if not target or target.altArmyHoverTint then return end
    local t = target:CreateTexture(nil, layer or "BACKGROUND")
    t:SetTexture(Theme.HOVER_TINT_BG)
    t:SetAllPoints(true)
    t:SetVertexColor(1, 1, 1, 0)
    target.altArmyHoverTint = t
end

function Theme.SetHoverTint(target, on)
    local t = target and target.altArmyHoverTint
    if t then
        t:SetVertexColor(1, 1, 1, on and Theme.HOVER_TINT_ALPHA or 0)
    end
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

function Theme.StyleGridHeader(texture)
    if not texture then return end
    local hdr = C.gridHeaderBg
    texture:SetColorTexture(hdr[1], hdr[2], hdr[3], hdr[4])
end

Theme.SETTINGS_PANEL_PADDING = 8

--- Inset content area inside a bordered settings panel (keeps controls off the edge).
function Theme.CreateSettingsPanelContent(panel)
    local p = Theme.SETTINGS_PANEL_PADDING
    local content = CreateFrame("Frame", nil, panel)
    content:SetPoint("TOPLEFT", panel, "TOPLEFT", p, -p)
    content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -p, p)
    return content
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

function Theme.ApplyCheckboxBackground(texture)
    if not texture then return end
    local bg = C.inputBg
    texture:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
end

function Theme.ApplyDropdownBackground(frame)
    if not frame then return end
    Theme.ApplyBackdrop(frame, "section")
end
