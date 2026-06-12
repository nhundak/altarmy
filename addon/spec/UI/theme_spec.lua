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
        function t:SetVertexColor(r, g, b, a) self._vertex = { r, g, b, a } end
        function t:SetTexture(tex) self._texture = tex end
        function t:SetAllPoints() end
        function t:SetPoint() end
        function t:SetHeight() end
        function t:SetWidth() end
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
            _alpha = 1,
            _shown = true,
            _enabled = true,
            _selected = false,
            _skinned = false,
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
        function f:CreateTexture() return makeStubTexture() end
        function f:CreateFontString() return { SetTextColor = function() end } end
        function f:GetFontString() return { SetTextColor = function() end } end
        function f:GetNormalTexture() return nil end
        function f:GetHighlightTexture() return nil end
        function f:GetPushedTexture() return nil end
        function f:SetAlpha(a) self._alpha = a end
        function f:Show() self._shown = true end
        function f:Hide() self._shown = false end
        function f:Enable() self._enabled = true end
        function f:Disable() self._enabled = false end
        function f:OnBackdropSizeChanged() end
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
            assert.are.same({ 0.08, 0.08, 0.10, 0.95 }, Theme.COLORS.panelBg)
            assert.are.same({ 0.10, 0.10, 0.12, 0.95 }, Theme.COLORS.sectionBg)
            assert.are.same({ 0.08, 0.08, 0.10, 0.95 }, Theme.COLORS.graphBg)
        end)

        it("defines warm bronze panel border", function()
            assert.are.same({ 0.45, 0.38, 0.22, 0.90 }, Theme.COLORS.panelBorder)
        end)

        it("defines button and row interaction colors", function()
            assert.is_not_nil(Theme.COLORS.btnBg)
            assert.is_not_nil(Theme.COLORS.rowHover)
            assert.is_not_nil(Theme.COLORS.rowAccent)
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
        it("applies section tier colors to a frame", function()
            local f = makeStubFrame()
            Theme.ApplyBackdrop(f, "section")
            assert.is_not_nil(f._backdrop)
            assert.are.equal(0.10, f._backdropColor[1])
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
            assert.are.equal(0.10, panel._backdropColor[1])
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
            assert.are.equal(0.18, btn._backdropColor[1])
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

    describe("StyleScrollThumb", function()
        it("sets tooltip background texture and thumb color", function()
            local tex = makeStubTexture()
            Theme.StyleScrollThumb(tex)
            assert.are.equal(Theme.HOVER_TINT_BG, tex._texture)
            assert.are.equal(0.50, tex._vertex[1])
        end)
    end)

    describe("CreateSeparator", function()
        it("creates a gold separator texture", function()
            local parent = makeStubFrame()
            local sep = Theme.CreateSeparator(parent, 100)
            assert.are.equal(Theme.COLORS.sepLine[1], sep._color[1])
        end)
    end)
end)
