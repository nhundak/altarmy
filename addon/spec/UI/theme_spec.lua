--[[
  Unit tests for AltArmy_TBC/UI/Theme.lua
  Run from project root: npm test
]]

describe("AltArmy.Theme", function()
    local Theme
    local framesCreated

    local function makeStubTexture()
        local t = { _color = nil, _vertex = nil, _texture = nil }
        function t:SetColorTexture(r, g, b, a) self._color = { r, g, b, a } end
        function t:SetTexture(tex) self._texture = tex end
        function t:SetTexCoord(a, b, c, d, e, f, g, h)
            self._texCoord = { a, b, c, d, e, f, g, h }
        end
        function t:SetGradientAlpha(orientation, sr, sg, sb, sa, er, eg, eb, ea)
            self._gradientAlpha = {
                orientation = orientation,
                start = { sr, sg, sb, sa },
                ["end"] = { er, eg, eb, ea },
            }
        end
        function t:SetGradient(orientation, minColor, maxColor)
            self._gradient = { orientation = orientation, minColor = minColor, maxColor = maxColor }
        end
        function t:SetVertexColor(r, g, b, a) self._vertex = { r, g, b, a } end
        function t:SetAllPoints() end
        function t:SetPoint() end
        function t:SetHeight() end
        function t:SetWidth(w) self._width = w end
        function t:SetSize(w, h) self._width = w self._height = h end
        t._shown = false
        function t:Show() self._shown = true end
        function t:Hide() self._shown = false end
        function t:SetShown(on) self._shown = on end
        function t:IsShown() return self._shown end
        return t
    end

    local function makeStubFrame()
        local f = {
            _scripts = {},
            _backdrop = nil,
            _backdropColor = nil,
            _backdropBorderColor = nil,
            _children = {},
            _textures = {},
            _fontStrings = {},
            _alpha = 1,
            _shown = true,
            _enabled = true,
            _selected = false,
            _skinned = false,
            _text = "",
            Left = { SetAlpha = function() end },
            Right = { SetAlpha = function() end },
            Middle = { SetAlpha = function() end },
        }
        function f:SetBackdrop(bd) self._backdrop = bd end
        function f:GetBackdrop() return self._backdrop end
        function f:SetBackdropColor(r, g, b, a) self._backdropColor = { r, g, b, a } end
        function f:GetBackdropColor() local c = self._backdropColor return c and c[1], c[2], c[3], c[4] end
        function f:SetBackdropBorderColor(r, g, b, a) self._backdropBorderColor = { r, g, b, a } end
        function f:GetBackdropBorderColor() local c = self._backdropBorderColor return c and c[1], c[2], c[3], c[4] end
        function f:HookScript(event, fn) self._scripts[event] = fn end
        function f:GetScript(event) return self._scripts[event] end
        function f:SetScript(event, fn) self._scripts[event] = fn end
        function f:CreateTexture(_, layer)
            local tex = makeStubTexture()
            tex._layer = layer
            table.insert(f._textures, tex)
            return tex
        end
        function f:SetThumbTexture() end
        function f:GetWidth() return self._width or 14 end
        function f:GetHeight() return self._height or 20 end
        function f:SetSize(w, h) self._width = w self._height = h end
        function f:SetWidth(w) self._width = w end
        function f:SetHeight(h) self._height = h end
        function f:GetFrameLevel() return self._frameLevel or 0 end
        function f:SetFrameLevel(level) self._frameLevel = level end
        function f:EnableMouse() end
        function f:EnableMouseWheel() end
        function f:SetPoint() end
        function f:SetCheckedTexture(tex) self._checkedTexture = tex end
        function f:SetMinMaxValues(min, max) self._minVal = min self._maxVal = max end
        function f:GetMinMaxValues() return self._minVal or 0, self._maxVal or 0 end
        function f:SetValue(v)
            if self._value == v then return end
            self._value = v
            local fn = self._scripts and self._scripts["OnValueChanged"]
            if fn then fn(self, v) end
        end
        function f:GetValue() return self._value or 0 end
        function f:SetValueStep() end
        function f:SetOrientation() end
        function f:ClearAllPoints() end
        function f:GetEffectiveScale() return self._scale or 1 end
        function f:SetVerticalScroll(v) self._verticalScroll = v end
        function f:GetVerticalScroll() return self._verticalScroll or 0 end
        function f:SetScrollChild(c) self._scrollChild = c end
        function f:GetScrollChild() return self._scrollChild end
        function f:HookScript(event, fn) self._scripts[event] = fn end
        function f:GetChecked() return self._checked end
        function f:SetChecked(checked) self._checked = checked end
        function f:Click()
            if self._scripts.OnClick then
                self._scripts.OnClick(self)
            end
        end
        function f:CreateFontString(_, layer, template)
            local fs = {
                _shown = true,
                _text = "",
                _layer = layer,
                _template = template,
                _textColorCalls = 0,
                SetTextColor = function(self, r, g, b, a)
                    self._textColor = { r, g, b, a }
                    self._textColorCalls = (self._textColorCalls or 0) + 1
                end,
                SetText = function(self, t) self._text = t end,
                SetPoint = function() end,
                SetWidth = function() end,
                SetJustifyH = function() end,
                SetWordWrap = function(self, on) self._wordWrap = on end,
                Show = function(self) self._shown = true end,
                Hide = function(self) self._shown = false end,
                SetShown = function(self, on) self._shown = on end,
                IsShown = function(self) return self._shown end,
            }
            table.insert(f._fontStrings, fs)
            return fs
        end
        function f:GetFontString() return { SetTextColor = function() end } end
        function f:GetNormalTexture() return nil end
        function f:GetHighlightTexture() return nil end
        function f:GetPushedTexture() return nil end
        function f:SetAlpha(a) self._alpha = a end
        function f:Show() self._shown = true end
        function f:Hide() self._shown = false end
        function f:SetShown(on) self._shown = on end
        function f:IsShown() return self._shown ~= false end
        function f:Enable() self._enabled = true end
        function f:Disable() self._enabled = false end
        function f:IsEnabled() return self._enabled ~= false end
        function f:SetParent() end
        function f:OnBackdropSizeChanged() end
        function f:SetAutoFocus() end
        function f:SetTextInsets() end
        function f:SetFontObject() end
        function f:HighlightText() end
        function f:SetFocus() end
        function f:ClearFocus() end
        function f:GetText() return self._text or "" end
        function f:SetText(t) self._text = t or "" end
        table.insert(framesCreated, f)
        return f
    end

    setup(function()
        framesCreated = {}
        _G.AltArmy = {}
        _G.CreateFrame = function()
            return makeStubFrame()
        end
        _G.Mixin = function(target, mixin)
            for k, v in pairs(mixin) do
                target[k] = v
            end
        end
        _G.BackdropTemplateMixin = {
            OnBackdropSizeChanged = function() end,
            SetBackdrop = function(self, bd) self._backdrop = bd end,
            SetBackdropColor = function(self, r, g, b, a) self._backdropColor = { r, g, b, a } end,
            SetBackdropBorderColor = function(self, r, g, b, a)
                self._backdropBorderColor = { r, g, b, a }
            end,
        }
        package.path = package.path .. ";AltArmy_TBC/UI/?.lua"
        package.loaded["Theme"] = nil
        require("Theme")
        Theme = AltArmy.Theme
    end)

    describe("COLORS", function()
        it("defines tiered background roles", function()
            assert.are.same({ 0.08, 0.08, 0.10, 0.55 }, Theme.COLORS.windowBg)
            assert.are.same({ 0.08, 0.08, 0.10, 0.95 }, Theme.COLORS.sectionBg)
            assert.are.same({ 0.08, 0.08, 0.10, 0.95 }, Theme.COLORS.graphBg)
            assert.is_true(Theme.COLORS.windowBg[4] < Theme.COLORS.sectionBg[4])
        end)

        it("defines warm bronze panel border", function()
            assert.are.same({ 0.45, 0.38, 0.22, 0.90 }, Theme.COLORS.panelBorder)
        end)

        it("defines button and row interaction colors", function()
            assert.is_not_nil(Theme.COLORS.btnBg)
            assert.is_not_nil(Theme.COLORS.rowHover)
            assert.is_not_nil(Theme.COLORS.rowAccent)
        end)

        it("gridHeaderBg matches sectionBg RGB at full opacity for pinned overlays", function()
            local panel = Theme.COLORS.sectionBg
            local header = Theme.COLORS.gridHeaderBg
            assert.are.equal(panel[1], header[1])
            assert.are.equal(panel[2], header[2])
            assert.are.equal(panel[3], header[3])
            assert.are.equal(1, header[4])
        end)
    end)

    describe("backdrop tables", function()
        it("WINDOW_BACKDROP is tiled with 16px edge", function()
            assert.is_true(Theme.WINDOW_BACKDROP.tile)
            assert.are.equal(16, Theme.WINDOW_BACKDROP.edgeSize)
        end)

        it("SECTION_BACKDROP is stretched with 12px edge", function()
            assert.is_false(Theme.SECTION_BACKDROP.tile)
            assert.are.equal(12, Theme.SECTION_BACKDROP.edgeSize)
        end)

        it("TOOLTIP_BACKDROP is tiled", function()
            assert.is_true(Theme.TOOLTIP_BACKDROP.tile)
        end)
    end)

    describe("ApplyBackdrop", function()
        it("applies window tier with semi-transparent shell bg", function()
            local f = makeStubFrame()
            Theme.ApplyBackdrop(f, "window")
            assert.are.equal(0.55, f._backdropColor[4])
        end)

        it("applies section tier colors to a frame", function()
            local f = makeStubFrame()
            Theme.ApplyBackdrop(f, "section")
            assert.is_not_nil(f._backdrop)
            assert.are.equal(0.08, f._backdropColor[1])
            assert.are.equal(0.95, f._backdropColor[4])
            assert.are.equal(0.45, f._backdropBorderColor[1])
        end)

        it("applies graph tier with graphBg", function()
            local f = makeStubFrame()
            Theme.ApplyBackdrop(f, "graph")
            assert.are.equal(0.08, f._backdropColor[1])
        end)

        it("mixes BackdropTemplateMixin when SetBackdrop missing", function()
            local f = makeStubFrame()
            f.SetBackdrop = nil
            Theme.EnsureBackdrop(f)
            assert.is_not_nil(f.SetBackdrop)
            assert.is_not_nil(f.OnBackdropSizeChanged)
        end)
    end)

    describe("CreatePanel", function()
        it("returns a frame with section backdrop applied", function()
            local parent = makeStubFrame()
            local panel = Theme.CreatePanel(parent, "section")
            assert.is_not_nil(panel._backdrop)
            assert.are.equal(0.08, panel._backdropColor[1])
        end)
    end)

    describe("SkinButton", function()
        it("applies button backdrop and wires hover script", function()
            local btn = makeStubFrame()
            Theme.SkinButton(btn, false)
            assert.is_true(btn._skinned)
            assert.is_not_nil(btn._backdrop)
            assert.is_not_nil(btn._scripts.OnEnter)
            btn._scripts.OnEnter(btn)
            assert.are.equal(0.20, btn._backdropColor[1])
        end)

        it("toggle buttons get SetSelected", function()
            local btn = makeStubFrame()
            Theme.SkinButton(btn, true)
            assert.is_not_nil(btn.SetSelected)
            btn:SetSelected(true)
            assert.is_true(btn._selected)
            assert.are.equal(0.30, btn._backdropColor[1])
        end)
    end)

    describe("SkinDangerButton", function()
        it("applies red danger styling", function()
            local btn = makeStubFrame()
            Theme.SkinDangerButton(btn)
            assert.is_true(btn._skinned)
            assert.are.equal(0.24, btn._backdropColor[1])
            assert.are.equal(0.78, btn._backdropBorderColor[1])
            btn._scripts.OnEnter(btn)
            assert.are.equal(0.34, btn._backdropColor[1])
        end)
    end)

    describe("InstallHoverTint", function()
        it("creates a hover tint texture on the frame", function()
            local f = makeStubFrame()
            Theme.InstallHoverTint(f)
            assert.is_not_nil(f.altArmyHoverTint)
            Theme.SetHoverTint(f, true)
            assert.are.equal(Theme.HOVER_TINT_ALPHA, f.altArmyHoverTint._vertex[4])
        end)
    end)

    describe("InstallSettingsButtonGlow", function()
        it("creates a yellow square glow behind the icon", function()
            local btn = makeStubFrame()
            local glow = Theme.InstallSettingsButtonGlow(btn)
            assert.is_not_nil(glow)
            assert.is_not_nil(btn.glow)
            assert.are.equal(Theme.COLORS.settingsGlow[1], glow._color[1])
            assert.is_false(glow._shown)
        end)
    end)

    describe("AttentionFlashAlpha", function()
        it("returns nil when the flash duration is complete", function()
            assert.is_nil(Theme.AttentionFlashAlpha(2, 2, 3))
            assert.is_nil(Theme.AttentionFlashAlpha(2.1, 2, 3))
        end)

        it("pulses between low and high alpha within the duration", function()
            local a0 = Theme.AttentionFlashAlpha(0, 2, 3)
            local aMid = Theme.AttentionFlashAlpha(1 / 6, 2, 3)
            assert.is_true(a0 >= 0.35 and a0 <= 1)
            assert.is_true(aMid > a0)
        end)
    end)

    describe("FlashAttentionHighlight", function()
        it("creates a bordered highlight and hides it when the pulse ends", function()
            local target = makeStubFrame()
            Theme.FlashAttentionHighlight(target, { duration = 0.5, pulses = 2, pad = 3 })
            local hl = target.altArmyAttentionHighlight
            assert.is_not_nil(hl)
            assert.is_not_nil(hl._backdropBorderColor)
            assert.is_true(hl._shown)
            assert.is_not_nil(hl._scripts.OnUpdate)
            hl._scripts.OnUpdate(hl, 0.6)
            assert.is_false(hl._shown)
            assert.is_nil(hl._scripts.OnUpdate)
        end)
    end)

    describe("SkinSettingsIconButton", function()
        it("shows yellow hover glow on enter when settings are not active", function()
            local btn = makeStubFrame()
            local icon = makeStubTexture()
            Theme.SkinSettingsIconButton(btn)
            assert.is_true(btn._settingsIconSkinned)
            assert.is_not_nil(btn.hoverGlow)
            btn._scripts.OnEnter(btn)
            assert.is_true(btn.hoverGlow._shown)
            btn._scripts.OnLeave(btn)
            assert.is_false(btn.hoverGlow._shown)
        end)

        it("does not duplicate glow on hover when settings panel is already open", function()
            local btn = makeStubFrame()
            btn.glow = makeStubTexture()
            btn.glow._shown = true
            local icon = makeStubTexture()
            Theme.SkinSettingsIconButton(btn)
            btn._scripts.OnEnter(btn)
            assert.is_false(btn.hoverGlow._shown)
        end)
    end)

    describe("CreateDropdownMenuItem", function()
        it("installs hover tint and wires enter/leave on dropdown rows", function()
            local parent = makeStubFrame()
            local btn = Theme.CreateDropdownMenuItem(parent, { index = 1, text = "Option" })
            assert.is_not_nil(btn.altArmyHoverTint)
            assert.is_not_nil(btn._scripts.OnEnter)
            btn._scripts.OnEnter()
            assert.are.equal(Theme.HOVER_TINT_ALPHA, btn.altArmyHoverTint._vertex[4])
            btn._scripts.OnLeave()
            assert.are.equal(0, btn.altArmyHoverTint._vertex[4])
        end)

        it("highlights the selected dropdown row", function()
            local parent = makeStubFrame()
            local btn = Theme.CreateDropdownMenuItem(parent, { index = 1, text = "Option", selected = true })
            assert.is_not_nil(btn.altArmyDropdownSelectedBg)
            assert.is_true(btn.altArmyDropdownSelectedBg._shown)
            local c = btn.altArmyDropdownSelectedBg._color
            assert.are.equal(Theme.COLORS.rowSelected[1], c[1])
            assert.are.equal(Theme.COLORS.rowSelected[2], c[2])
            assert.are.equal(Theme.COLORS.rowSelected[3], c[3])
            assert.are.equal(Theme.COLORS.rowSelected[4], c[4])
        end)

        it("SetDropdownSelected toggles selected row highlight", function()
            local parent = makeStubFrame()
            local btn = Theme.CreateDropdownMenuItem(parent, { index = 1, text = "Option", selected = false })
            assert.is_false(btn.altArmyDropdownSelectedBg._shown)
            btn:SetDropdownSelected(true)
            assert.is_true(btn.altArmyDropdownSelectedBg._shown)
            btn:SetDropdownSelected(false)
            assert.is_false(btn.altArmyDropdownSelectedBg._shown)
        end)
    end)

    describe("CreateSingleSelectDropdown", function()
        it("shows selected entry label on the trigger button", function()
            local parent = makeStubFrame()
            local selected = "all"
            local dd = Theme.CreateSingleSelectDropdown({
                parent = parent,
                width = 200,
                entries = {
                    { id = "all", label = "All realms" },
                    { id = "current", label = "Current realm" },
                },
                getSelectedId = function() return selected end,
                onSelect = function(id) selected = id end,
            })
            assert.is_not_nil(dd)
            assert.are.equal("All realms", dd.label._text)
            selected = "current"
            dd:Update()
            assert.are.equal("Current realm", dd.label._text)
        end)

        it("calls onSelect and closes popup when an item is chosen", function()
            local parent = makeStubFrame()
            local selected = "chat"
            local dd = Theme.CreateSingleSelectDropdown({
                parent = parent,
                entries = {
                    { id = "chat", label = "Chat message" },
                    { id = "both", label = "Both" },
                },
                getSelectedId = function() return selected end,
                onSelect = function(id) selected = id end,
            })
            dd.popup:Show()
            assert.is_true(dd.popup:IsShown())
            local bothItem
            for i = 1, #framesCreated do
                local f = framesCreated[i]
                if f.entryId == "both" and f._scripts and f._scripts.OnClick then
                    bothItem = f
                    break
                end
            end
            assert.is_not_nil(bothItem)
            bothItem._scripts.OnClick(bothItem)
            assert.are.equal("both", selected)
            assert.is_false(dd.popup:IsShown())
        end)

        it("SetEnabled disables the trigger and closes the popup", function()
            local parent = makeStubFrame()
            local dd = Theme.CreateSingleSelectDropdown({
                parent = parent,
                entries = { { id = "a", label = "A" } },
                getSelectedId = function() return "a" end,
            })
            dd.popup:Show()
            dd:SetEnabled(false)
            assert.is_false(dd.button:IsEnabled())
            assert.is_false(dd.popup:IsShown())
        end)

        it("does not scroll when entries fit within maxVisibleRows", function()
            local parent = makeStubFrame()
            local rowHeight = 24
            local entries = {}
            for i = 1, 12 do
                entries[i] = { id = tostring(i), label = "Row " .. i }
            end
            local dd = Theme.CreateSingleSelectDropdown({
                parent = parent,
                rowHeight = rowHeight,
                maxVisibleRows = 12,
                entries = entries,
                getSelectedId = function() return "1" end,
            })
            dd.listViewport.scroll._height = dd.popup:GetHeight()
            dd.listViewport.UpdateRange()
            assert.are.equal(12 * rowHeight + 4, dd.popup:GetHeight())
            assert.is_false(dd.scrollBar:IsShown())
        end)

        it("shows a scrollbar when entries exceed maxVisibleRows", function()
            local parent = makeStubFrame()
            local rowHeight = 24
            local entries = {}
            for i = 1, 15 do
                entries[i] = { id = tostring(i), label = "Row " .. i }
            end
            local dd = Theme.CreateSingleSelectDropdown({
                parent = parent,
                rowHeight = rowHeight,
                maxVisibleRows = 12,
                entries = entries,
                getSelectedId = function() return "1" end,
            })
            dd.listViewport.scroll._height = dd.popup:GetHeight()
            dd.listViewport.UpdateRange()
            assert.are.equal(12 * rowHeight + 4, dd.popup:GetHeight())
            assert.is_true(dd.scrollBar:IsShown())
            assert.is_true((dd.listViewport.child:GetHeight() or 0) > dd.popup:GetHeight())
        end)
    end)

    describe("BindInteractableHover", function()
        it("installs tint and wires enter/leave scripts", function()
            local f = makeStubFrame()
            f._scripts = {}
            function f:EnableMouse() end
            Theme.BindInteractableHover(f)
            assert.is_not_nil(f.altArmyHoverTint)
            assert.is_not_nil(f._scripts.OnEnter)
            assert.is_not_nil(f._scripts.OnLeave)
        end)

        it("supports bandHeight for partial-row highlights", function()
            local f = makeStubFrame()
            f._scripts = {}
            function f:EnableMouse() end
            Theme.BindInteractableHover(f, { bandHeight = 18 })
            assert.is_not_nil(f.altArmyHoverTint)
        end)
    end)

    describe("vertical scroll bar layout", function()
        it("defines Graphs-tab width, gap, inset, and gutter", function()
            assert.are.equal(14, Theme.SCROLL_BAR_WIDTH)
            assert.are.equal(2, Theme.SCROLL_BAR_GAP)
            assert.are.equal(4, Theme.SCROLL_BAR_RIGHT_INSET)
            assert.are.equal(20, Theme.VerticalScrollBarGutter())
        end)
    end)

    describe("SetupScrollBar", function()
        it("styles track and knob thumb like the Compare panel", function()
            local slider = makeStubFrame()
            slider.GetWidth = function() return 14 end
            Theme.SetupScrollBar(slider, { thickness = 14 })
            assert.is_not_nil(slider.altArmyScrollTrack)
            assert.are.equal(0.08, slider.altArmyScrollTrack._color[1])
            assert.is_not_nil(slider.altArmyScrollThumb)
            assert.are.equal(Theme.SCROLL_KNOB_TEXTURE, slider.altArmyScrollThumb._texture)
            assert.are.equal(18, slider.altArmyScrollThumb._width)
            assert.are.equal(24, slider.altArmyScrollThumb._height)
        end)

        it("sizes horizontal thumbs along the bar width", function()
            local slider = makeStubFrame()
            slider.GetHeight = function() return 12 end
            Theme.SetupScrollBar(slider, { horizontal = true, thickness = 12 })
            assert.are.equal(24, slider.altArmyScrollThumb._width)
            assert.are.equal(16, slider.altArmyScrollThumb._height)
        end)
    end)

    describe("section layout spacing", function()
        it("defines tab section inset and inter-panel gap matching Graphs tab", function()
            assert.are.equal(0, Theme.TAB_SECTION_INSET)
            assert.are.equal(4, Theme.SECTION_GAP)
        end)
    end)

    describe("sort header arrows", function()
        it("returns the base label when the column is not sorted", function()
            assert.are.equal("Item", Theme.FormatSortHeaderLabel("Item", false, true))
        end)

        it("appends ^ when sorted ascending", function()
            assert.are.equal("Recipe ^", Theme.FormatSortHeaderLabel("Recipe", true, true))
        end)

        it("appends v when sorted descending", function()
            assert.are.equal("Skill v", Theme.FormatSortHeaderLabel("Skill", true, false))
        end)
    end)

    describe("CreateTabContentPanel", function()
        it("creates a section-backed panel for tab content", function()
            local parent = makeStubFrame()
            local panel = Theme.CreateTabContentPanel(parent)
            assert.is_not_nil(panel._backdrop)
            assert.are.equal(Theme.SECTION_BACKDROP.edgeSize, panel._backdrop.edgeSize)
        end)
    end)

    describe("CreateSettingsPanelContent", function()
        it("creates a child content frame with standard padding", function()
            local panel = makeStubFrame()
            assert.are.equal(8, Theme.SETTINGS_PANEL_PADDING)
            assert.are.equal(8, Theme.TAB_CONTENT_PADDING)
            local content = Theme.CreateSettingsPanelContent(panel)
            assert.is_not_nil(content)
        end)
    end)

    describe("CreateSeparator", function()
        it("creates a gold separator texture", function()
            local parent = makeStubFrame()
            local sep = Theme.CreateSeparator(parent, 100)
            assert.are.equal(Theme.COLORS.sepLine[1], sep._color[1])
        end)
    end)

    describe("ScrollMax and ClampScroll", function()
        it("computes max scroll from child and viewport heights", function()
            assert.are.equal(0, Theme.ScrollMax(100, 200))
            assert.are.equal(50, Theme.ScrollMax(250, 200))
        end)

        it("clamps scroll offset to valid range", function()
            assert.are.equal(0, Theme.ClampScroll(-10, 100))
            assert.are.equal(100, Theme.ClampScroll(150, 100))
            assert.are.equal(42, Theme.ClampScroll(42, 100))
        end)
    end)

    describe("CreateVerticalScrollViewport", function()
        it("scrolls by wheelStep on mouse wheel", function()
            local parent = makeStubFrame()
            parent._height = 100
            local viewport = Theme.CreateVerticalScrollViewport({
                parent = parent,
                gutterEdge = parent,
                wheelStep = 40,
                valueStep = 20,
                wheelSource = "scroll",
            })
            viewport.child._height = 300
            viewport.scroll._height = 100
            viewport:UpdateRange()
            viewport.scroll._scripts.OnMouseWheel(viewport.scroll, -1)
            assert.are.equal(40, viewport.scroll:GetVerticalScroll())
            assert.are.equal(40, viewport.scrollBar:GetValue())
        end)

        it("clamps scroll position when range shrinks", function()
            local parent = makeStubFrame()
            local viewport = Theme.CreateVerticalScrollViewport({
                parent = parent,
                gutterEdge = parent,
                wheelStep = 20,
                valueStep = 20,
            })
            viewport.child._height = 500
            viewport.scroll._height = 100
            viewport.scroll:SetVerticalScroll(200)
            viewport.scrollBar:SetValue(200)
            viewport.child._height = 150
            viewport:UpdateRange()
            assert.are.equal(50, viewport.scroll:GetVerticalScroll())
            assert.are.equal(50, viewport.scrollBar:GetValue())
        end)

        it("hides scrollbar when content fits", function()
            local parent = makeStubFrame()
            local viewport = Theme.CreateVerticalScrollViewport({
                parent = parent,
                gutterEdge = parent,
            })
            viewport.child._height = 50
            viewport.scroll._height = 100
            viewport:UpdateRange()
            assert.is_false(viewport.scrollBar:IsShown())
        end)
    end)

    describe("CreatePinnedHeaderScrollFade", function()
        it("creates a texture fade anchored below the pinned header", function()
            local viewport = makeStubFrame()
            local header = makeStubFrame()
            header._frameLevel = 20
            header.GetParent = function() return viewport end
            local fade = Theme.CreatePinnedHeaderScrollFade({
                headerFrame = header,
            })
            assert.is_not_nil(fade.frame)
            assert.are.equal(70, fade.frame:GetFrameLevel())
            assert.are.equal(1, #fade.frame._textures)
            local tex = fade.frame._textures[1]
            assert.are.equal("Interface\\AddOns\\AltArmy_TBC\\Textures\\ScrollFade", tex._texture)
            assert.is_not_nil(tex._vertex)
            assert.are.equal(1, tex._vertex[4])
        end)

        it("hides the fade at scroll offset zero and shows it when scrolled", function()
            local viewport = makeStubFrame()
            local header = makeStubFrame()
            header.GetParent = function() return viewport end
            local scroll = makeStubFrame()
            scroll._verticalScroll = 0
            local fade = Theme.CreatePinnedHeaderScrollFade({
                headerFrame = header,
                scrollFrame = scroll,
            })
            fade:Update()
            assert.is_false(fade.frame:IsShown())
            scroll._verticalScroll = 40
            fade:Update()
            assert.is_true(fade.frame:IsShown())
        end)

        it("prefers scroll bar value for visibility", function()
            local viewport = makeStubFrame()
            local header = makeStubFrame()
            header.GetParent = function() return viewport end
            local scrollBar = makeStubFrame()
            scrollBar._value = 12
            local fade = Theme.CreatePinnedHeaderScrollFade({
                headerFrame = header,
                scrollBar = scrollBar,
            })
            fade:Update()
            assert.is_true(fade.frame:IsShown())
        end)
    end)

    describe("CreatePinnedHorizontalScrollFade", function()
        it("creates a vertical strip on the left edge of a horizontal scroll viewport", function()
            local parent = makeStubFrame()
            local scroll = makeStubFrame()
            scroll._frameLevel = 10
            scroll.GetParent = function() return parent end
            local fade = Theme.CreatePinnedHorizontalScrollFade({
                anchorScrollFrame = scroll,
            })
            assert.is_not_nil(fade.frame)
            assert.are.equal(60, fade.frame:GetFrameLevel())
            assert.are.equal(Theme.PINNED_HORIZONTAL_SCROLL_FADE_WIDTH, fade.frame:GetWidth())
            local tex = fade.frame._textures[1]
            assert.are.equal("Interface\\AddOns\\AltArmy_TBC\\Textures\\ScrollFade", tex._texture)
            assert.are.same({ 0, 0, 0, 0, 1, 1, 1, 1 }, tex._texCoord)
        end)

        it("shows the fade when horizontal scroll offset is greater than zero", function()
            local parent = makeStubFrame()
            local scroll = makeStubFrame()
            scroll.GetParent = function() return parent end
            scroll._horizontalScroll = 0
            function scroll:GetHorizontalScroll() return self._horizontalScroll end
            local fade = Theme.CreatePinnedHorizontalScrollFade({
                anchorScrollFrame = scroll,
                scrollFrame = scroll,
            })
            fade:Update()
            assert.is_false(fade.frame:IsShown())
            scroll._horizontalScroll = 24
            fade:Update()
            assert.is_true(fade.frame:IsShown())
        end)
    end)

    describe("HorizontalDragValue", function()
        it("maps cursor delta across bar width to scroll range", function()
            assert.are.equal(50, Theme.HorizontalDragValue(0, 100, 0, 1, 200, 0, 100))
        end)

        it("accounts for UI scale", function()
            assert.are.equal(25, Theme.HorizontalDragValue(0, 100, 0, 2, 200, 0, 100))
        end)

        it("clamps to min and max", function()
            assert.are.equal(0, Theme.HorizontalDragValue(0, -500, 0, 1, 200, 0, 100))
            assert.are.equal(100, Theme.HorizontalDragValue(0, 500, 0, 1, 200, 0, 100))
        end)

        it("returns start value when bar width or scale is invalid", function()
            assert.are.equal(10, Theme.HorizontalDragValue(10, 200, 0, 1, 0, 0, 100))
            assert.are.equal(10, Theme.HorizontalDragValue(10, 200, 0, 0, 200, 0, 100))
        end)

        it("accounts for thumb length along the track", function()
            -- travel = 200 - 24 = 176; cursor delta 88 -> 50% of range
            assert.are.equal(50, Theme.HorizontalDragValue(0, 88, 0, 1, 200, 0, 100, 24))
        end)
    end)

    describe("CreateHorizontalScrollBar", function()
        it("invokes onScroll via Sync when value changes", function()
            local parent = makeStubFrame()
            local scrolled = nil
            local hbar = Theme.CreateHorizontalScrollBar(parent, {
                thickness = 12,
                onScroll = function(value)
                    scrolled = value
                end,
                isShown = function() return true end,
            })
            hbar.bar:SetValue(42)
            hbar:Sync()
            assert.are.equal(42, scrolled)
            hbar:Sync()
            assert.are.equal(42, scrolled)
        end)

        it("Reset applies zero", function()
            local parent = makeStubFrame()
            local scrolled = nil
            local hbar = Theme.CreateHorizontalScrollBar(parent, {
                onScroll = function(value)
                    scrolled = value
                end,
            })
            hbar.bar:SetValue(50)
            hbar:Reset()
            assert.are.equal(0, hbar.bar:GetValue())
            assert.are.equal(0, scrolled)
        end)

        it("Restore clamps and reapplies saved scroll offset", function()
            local parent = makeStubFrame()
            local scrolled = nil
            local hbar = Theme.CreateHorizontalScrollBar(parent, {
                onScroll = function(value)
                    scrolled = value
                end,
            })
            hbar.bar:SetValue(120)
            hbar:SetRange(0, 80)
            hbar:Restore(80)
            assert.are.equal(80, hbar.bar:GetValue())
            assert.are.equal(80, scrolled)
        end)

        it("SetRange updates slider min/max", function()
            local parent = makeStubFrame()
            local hbar = Theme.CreateHorizontalScrollBar(parent, {})
            hbar:SetRange(0, 300)
            local minVal, maxVal = hbar.bar:GetMinMaxValues()
            assert.are.equal(0, minVal)
            assert.are.equal(300, maxVal)
        end)

        it("drag OnUpdate applies onScroll once per value change via OnValueChanged", function()
            local parent = makeStubFrame()
            local scrollCount = 0
            local hbar = Theme.CreateHorizontalScrollBar(parent, {
                onScroll = function()
                    scrollCount = scrollCount + 1
                end,
                isShown = function() return true end,
            })
            hbar.bar._width = 200
            hbar:SetRange(0, 100)
            local onMouseDown = hbar.bar:GetScript("OnMouseDown")
            local onUpdate = hbar.bar:GetScript("OnUpdate")
            assert.is_nil(onUpdate)
            _G.GetCursorPosition = function() return 0, 0 end
            _G.IsMouseButtonDown = function() return true end
            onMouseDown(hbar.bar, "LeftButton")
            onUpdate = hbar.bar:GetScript("OnUpdate")
            assert.is_not_nil(onUpdate)
            _G.GetCursorPosition = function() return 50, 0 end
            onUpdate(hbar.bar)
            assert.are.equal(1, scrollCount)
            onUpdate(hbar.bar)
            assert.are.equal(1, scrollCount)
        end)

        it("invokes onDragEnd when mouse button is released after drag", function()
            local parent = makeStubFrame()
            parent._width = 200
            local dragEnded = false
            local hbar = Theme.CreateHorizontalScrollBar(parent, {
                onDragEnd = function()
                    dragEnded = true
                end,
                isShown = function() return true end,
            })
            hbar:SetRange(0, 100)
            local onMouseDown = hbar.bar:GetScript("OnMouseDown")
            _G.GetCursorPosition = function() return 0, 0 end
            _G.IsMouseButtonDown = function() return true end
            onMouseDown(hbar.bar, "LeftButton")
            local onUpdate = hbar.bar:GetScript("OnUpdate")
            _G.IsMouseButtonDown = function() return false end
            onUpdate(hbar.bar)
            assert.is_true(dragEnded)
            assert.is_nil(hbar.bar:GetScript("OnUpdate"))
        end)
    end)

    describe("CreateThemeCheckbox", function()
        it("returns a themed CheckButton with background and checked textures", function()
            local parent = makeStubFrame()
            local check = Theme.CreateThemeCheckbox(parent)
            assert.is_not_nil(check)
            assert.are.equal(18, check._width)
            assert.are.equal(18, check._height)
            assert.are.equal(2, #check._textures)
            assert.are.equal("BACKGROUND", check._textures[1]._layer)
            assert.are.equal(Theme.COLORS.inputBg[1], check._textures[1]._color[1])
            assert.are.equal("OVERLAY", check._textures[2]._layer)
            assert.are.equal("Interface\\Buttons\\UI-CheckBox-Check", check._textures[2]._texture)
            assert.are.equal(check._textures[2], check._checkedTexture)
        end)

        it("honors custom size", function()
            local parent = makeStubFrame()
            local check = Theme.CreateThemeCheckbox(parent, 22)
            assert.are.equal(22, check._width)
            assert.are.equal(22, check._height)
        end)
    end)

    describe("EditBox placeholder helpers", function()
        local function makeStubEditBox()
            local box = makeStubFrame()
            box._text = ""
            box._focused = false
            function box:GetText() return self._text end
            function box:SetText(text) self._text = text or "" end
            function box:HasFocus() return self._focused end
            function box:SetFocus() self._focused = true end
            function box:ClearFocus() self._focused = false end
            return box
        end

        it("shows the fallback hint when the field is empty, even while focused", function()
            local box = makeStubEditBox()
            Theme.SetupEditBoxPlaceholder(box, "Search here")
            box:SetFocus()
            Theme.UpdateEditBoxPlaceholderVisibility(box)
            assert.is_true(box.altArmyPlaceholderHint:IsShown())
        end)

        it("hides the fallback hint when the field has text", function()
            local box = makeStubEditBox()
            Theme.SetupEditBoxPlaceholder(box, "Search here")
            box:SetText("abc")
            Theme.UpdateEditBoxPlaceholderVisibility(box)
            assert.is_false(box.altArmyPlaceholderHint:IsShown())
        end)

        it("restores the fallback hint after ClearEditBoxText", function()
            local box = makeStubEditBox()
            Theme.SetupEditBoxPlaceholder(box, "Search here")
            box:SetText("abc")
            box:SetFocus()
            Theme.ClearEditBoxText(box)
            assert.are.equal("", box:GetText())
            assert.is_false(box:HasFocus())
            assert.is_true(box.altArmyPlaceholderHint:IsShown())
        end)

        it("SetEditBoxText replaces text and resets cursor so the value is visible on load", function()
            local box = makeStubEditBox()
            box._cursor = 99
            function box:SetCursorPosition(pos) self._cursor = pos end
            function box:GetCursorPosition() return self._cursor end
            Theme.SetEditBoxText(box, "Frell")
            assert.are.equal("Frell", box:GetText())
            assert.are.equal(0, box:GetCursorPosition())
        end)

        it("SetEditBoxText tolerates EditBoxes without SetCursorPosition", function()
            local box = makeStubEditBox()
            Theme.SetEditBoxText(box, "Frell")
            assert.are.equal("Frell", box:GetText())
        end)
    end)

    describe("CreateOptionsSectionLabel", function()
        it("uses GameFontNormal without custom title color", function()
            local parent = makeStubFrame()
            local anchor = makeStubFrame()
            local label = Theme.CreateOptionsSectionLabel(parent, {
                relativeTo = anchor,
                text = "Transmute",
            })
            assert.are.equal("GameFontNormal", label._template)
            assert.are.equal("Transmute", label._text)
            assert.are.equal(0, label._textColorCalls)
        end)
    end)

    describe("CreateCraftLibInstallCallout", function()
        local function textsByValue(frame, value)
            local matches = {}
            for _, fs in ipairs(frame._fontStrings or {}) do
                if fs._text == value then
                    table.insert(matches, fs)
                end
            end
            return matches
        end

        it("renders gray body text and CurseForge install label by default", function()
            local parent = makeStubFrame()
            local callout = Theme.CreateCraftLibInstallCallout(parent, {
                bodyText = "Install CraftLib for filters",
            })
            local body = textsByValue(callout, "Install CraftLib for filters")[1]
            local install = textsByValue(callout, "Install from CurseForge")[1]
            assert.is_not_nil(body)
            assert.is_not_nil(install)
            assert.are.same(Theme.COLORS.label, body._textColor)
            assert.are.same({ 1, 1, 1, 1 }, install._textColor)
            assert.are.equal(Theme.CRAFTLIB_INSTALL_URL, callout.urlEdit:GetText())
        end)

        it("renders white intro and blue bullet lines when provided", function()
            local parent = makeStubFrame()
            local callout = Theme.CreateCraftLibInstallCallout(parent, {
                introText = "Install CraftLib addon to see:",
                bulletLines = {
                    "Advanced filtering options",
                    "Recipe skill requirements",
                    "Color coded difficulty",
                    "All recipe icons",
                },
            })
            local intro = textsByValue(callout, "Install CraftLib addon to see:")[1]
            local bullet1 = textsByValue(callout, "• Advanced filtering options")[1]
            local bullet2 = textsByValue(callout, "• Recipe skill requirements")[1]
            local bullet3 = textsByValue(callout, "• Color coded difficulty")[1]
            local bullet4 = textsByValue(callout, "• All recipe icons")[1]
            local install = textsByValue(callout, "Install from CurseForge")[1]
            assert.is_not_nil(intro)
            assert.is_not_nil(bullet1)
            assert.is_not_nil(bullet2)
            assert.is_not_nil(bullet3)
            assert.is_not_nil(bullet4)
            assert.is_not_nil(install)
            assert.are.same({ 1, 1, 1, 1 }, intro._textColor)
            assert.are.same({ 0.54, 0.71, 0.97, 1 }, bullet1._textColor)
            assert.are.same({ 0.54, 0.71, 0.97, 1 }, bullet2._textColor)
            assert.are.same({ 0.54, 0.71, 0.97, 1 }, bullet3._textColor)
            assert.are.same({ 0.54, 0.71, 0.97, 1 }, bullet4._textColor)
            assert.are.same({ 1, 1, 1, 1 }, install._textColor)
            -- pad*2 + icon + gaps + intro + 4 bullets + install + url
            assert.are.equal(160, callout._height)
        end)
    end)

    describe("CreateLabeledCheckbox", function()
        it("uses character-list checkbox size and hover region", function()
            local parent = makeStubFrame()
            local clicked = false
            local row = Theme.CreateLabeledCheckbox(parent, {
                text = "Pin current character",
                onClick = function()
                    clicked = true
                end,
            })
            assert.are.equal(18, row.check._width)
            assert.are.equal(18, row.check._height)
            assert.is_not_nil(row.hoverRegion.altArmyHoverTint)
            row.hoverRegion._scripts.OnMouseUp(row.hoverRegion, "LeftButton")
            assert.is_true(clicked)
        end)
    end)
end)
