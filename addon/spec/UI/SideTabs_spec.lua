--[[
  Unit tests for SideTabs.lua (right-edge icon flyout tabs).
  Run from project root: npm test
]]

describe("SideTabs", function()
  local SideTabs
  local savedCreateFrame, savedTooltip

  local function stubRegion()
    local r = { points = {} }
    function r:SetPoint(...) table.insert(self.points, { ... }) end
    function r:ClearAllPoints() self.points = {} end
    function r:SetAllPoints() end
    function r:SetSize(w, h) self.w, self.h = w, h end
    function r:SetTexture(t) self.texture = t end
    function r:SetBlendMode() end
    return r
  end

  local function stubFrame(kind, template)
    local f = stubRegion()
    f.kind, f.template, f.shown, f.scripts = kind, template, true, {}
    function f:SetHeight(h) self.h = h end
    function f:GetHeight() return self.h or 0 end
    function f:SetShown(on) self.shown = on and true or false end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:CreateTexture() return stubRegion() end
    function f:SetNormalTexture(t) self.normal = t end
    function f:SetHighlightTexture(t) self.highlight = t end
    function f:SetCheckedTexture(t) self.checkedTex = t end
    function f:SetChecked(on) self.checked = on and true or false end
    function f:GetChecked() return self.checked end
    if template == "LargeSideTabButtonTemplate" then
      f.h = 55
      f.Icon = stubRegion()
      function f:SetFillToInterior(on) self.fill = on end
      function f:SetCustomOnMouseUpHandler(fn) self.mouseUp = fn end
    end
    return f
  end

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/UI/?.lua"
    require("SideTabs")
    SideTabs = AltArmy.SideTabs
  end)

  before_each(function()
    savedCreateFrame, savedTooltip = _G.CreateFrame, _G.GameTooltip
    _G.CreateFrame = function(kind, _, _, template) return stubFrame(kind, template) end
    _G.GameTooltip = {
      SetOwner = function(self, owner) self.owner = owner end,
      SetText = function(self, t) self.text = t end,
      Hide = function(self) self.hidden = true end,
    }
  end)

  after_each(function()
    _G.CreateFrame, _G.GameTooltip = savedCreateFrame, savedTooltip
  end)

  describe("ComputeOffsets", function()
    it("stacks visible tabs by stride and skips hidden ones", function()
      local offsets = SideTabs.ComputeOffsets({ "A", "B", "C", "D" }, { B = true }, 55)
      assert.are.same({ A = 0, C = -55, D = -110 }, offsets)
    end)

    it("returns an empty map when everything is hidden", function()
      assert.are.same({}, SideTabs.ComputeOffsets({ "A" }, { A = true }, 10))
    end)
  end)

  local defs = {
    { name = "Summary", label = "Summary", icon = "Interface\\Icons\\a" },
    { name = "Gear", label = "Gear", icon = "Interface\\Icons\\b" },
    { name = "Guild", label = "Guild", icon = "Interface\\Icons\\c" },
  }

  describe("native (Forever) tabs", function()
    local tabs, selected
    before_each(function()
      selected = nil
      tabs = SideTabs.Create(stubFrame("Frame"), defs, {
        native = true,
        onSelect = function(name) selected = name end,
      })
    end)

    it("uses LargeSideTabButtonTemplate with icon and tooltip text", function()
      local t = tabs.tabs.Gear
      assert.are.equal("LargeSideTabButtonTemplate", t.template)
      assert.are.equal("Interface\\Icons\\b", t.Icon.texture)
      assert.are.equal("Gear", t.tooltipText)
      assert.is_true(t.fill)
    end)

    it("stacks tabs flush using the template height", function()
      assert.are.same({ "TOPLEFT", tabs.container, "TOPLEFT", 0, -55 }, tabs.tabs.Gear.points[1])
    end)

    it("anchors the container like CharacterFrame ModeTabs", function()
      local p = tabs.container.points[1]
      assert.are.equal("TOPLEFT", p[1])
      assert.are.equal("TOPRIGHT", p[3])
      assert.are.equal(SideTabs.NATIVE.anchorY, p[5])
    end)

    it("selects on left mouse-up inside the tab only", function()
      tabs.tabs.Gear.mouseUp(tabs.tabs.Gear, "RightButton", true)
      assert.is_nil(selected)
      tabs.tabs.Gear.mouseUp(tabs.tabs.Gear, "LeftButton", false)
      assert.is_nil(selected)
      tabs.tabs.Gear.mouseUp(tabs.tabs.Gear, "LeftButton", true)
      assert.are.equal("Gear", selected)
    end)

    it("checks exactly the selected tab, or none for nil", function()
      tabs:SetSelected("Gear")
      assert.is_true(tabs.tabs.Gear.checked)
      assert.is_false(tabs.tabs.Summary.checked)
      tabs:SetSelected(nil)
      assert.is_false(tabs.tabs.Gear.checked)
    end)

    describe("guild crest", function()
      local savedGC
      before_each(function() savedGC = AltArmy.GuildCrest end)
      after_each(function() AltArmy.GuildCrest = savedGC end)

      local function stubCrest(drawn)
        AltArmy.GuildCrest = {
          CreateLayers = function(_, anchor, opts)
            local layers = { anchor = anchor, mask = opts and opts.mask, shown = false }
            function layers.SetShown(self, on) self.shown = on end
            function layers.Refresh(self) self.shown = drawn; return drawn end
            return layers
          end,
        }
      end

      it("replaces the icon with the crest, clipped by the tab mask, when drawn", function()
        stubCrest(true)
        local t = tabs.tabs.Guild
        t.Mask = {}
        function t.Icon:SetShown(on) self.shown = on end
        tabs:RefreshCrest("Guild")
        assert.is_true(t.altArmyCrest.shown)
        assert.are.equal(t.Icon, t.altArmyCrest.anchor)
        assert.are.equal(t.Mask, t.altArmyCrest.mask)
        assert.is_false(t.Icon.shown)
      end)

      it("keeps the fallback icon when there is no crest", function()
        stubCrest(false)
        local t = tabs.tabs.Guild
        function t.Icon:SetShown(on) self.shown = on end
        tabs:RefreshCrest("Guild")
        assert.is_true(t.Icon.shown)
      end)
    end)

    it("re-flows when a tab is hidden", function()
      tabs:SetTabShown("Gear", false)
      assert.is_false(tabs.tabs.Gear.shown)
      assert.are.same({ "TOPLEFT", tabs.container, "TOPLEFT", 0, -55 }, tabs.tabs.Guild.points[1])
    end)
  end)

  describe("classic (TBC) fallback tabs", function()
    local tabs, selected
    before_each(function()
      selected = nil
      tabs = SideTabs.Create(stubFrame("Frame"), defs, {
        native = false,
        onSelect = function(name) selected = name end,
      })
    end)

    it("builds spellbook-style CheckButtons", function()
      local t = tabs.tabs.Summary
      assert.are.equal("CheckButton", t.kind)
      assert.are.equal(SideTabs.CLASSIC.size, t.w)
      assert.are.equal("Interface\\Icons\\a", t.normal)
    end)

    it("uses the spellbook stride (size + gap)", function()
      local stride = SideTabs.CLASSIC.size + SideTabs.CLASSIC.gap
      assert.are.same({ "TOPLEFT", tabs.container, "TOPLEFT", 0, -stride }, tabs.tabs.Gear.points[1])
    end)

    it("selects on click and keeps the checked state in sync", function()
      tabs.tabs.Gear.scripts.OnClick(tabs.tabs.Gear)
      assert.are.equal("Gear", selected)
      tabs:SetSelected("Summary")
      assert.is_true(tabs.tabs.Summary.checked)
      assert.is_false(tabs.tabs.Gear.checked)
    end)

    it("shows the tab label as a tooltip", function()
      tabs.tabs.Guild.scripts.OnEnter(tabs.tabs.Guild)
      assert.are.equal("Guild", GameTooltip.text)
      assert.are.equal(tabs.tabs.Guild, GameTooltip.owner)
      tabs.tabs.Guild.scripts.OnLeave(tabs.tabs.Guild)
      assert.is_true(GameTooltip.hidden)
    end)
  end)
end)
