--[[
  Unit tests for TopTabs.lua (spellbook-style tabs hanging above a panel).
  Run from project root: npm test
]]

describe("TopTabs", function()
  local TopTabs
  local saved
  local GLOBALS = { "CreateFrame", "CreateFramePool" }
  local created

  local function stubFrame(kind, template)
    local f = { kind = kind, template = template, points = {}, scripts = {}, shown = true }
    function f:SetPoint(...) table.insert(self.points, { ... }) end
    function f:ClearAllPoints() self.points = {} end
    function f:SetSize(w, h) self.w, self.h = w, h end
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:SetText(t) self.text = t end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    table.insert(created, f)
    return f
  end

  local function tabSystemStub(f)
    f.tabs = {}
    function f:SetTabSelectedCallback(cb) self.cb = cb end
    function f:AddTab(text, icon)
      local btn = stubFrame("Button", self.tabTemplate)
      btn.tabText, btn.tabIcon = text, icon
      function btn:SetTooltipText(t) self.tooltipText = t end
      table.insert(self.tabs, btn)
      return #self.tabs
    end
    function f:GetTabButton(id) return self.tabs[id] end
    function f:SetTabVisuallySelected(id) self.selectedID = id end
    function f:SetTab(id, isUser)
      if not self.cb(id, isUser) then self:SetTabVisuallySelected(id) end
    end
  end

  local defs = {
    { name = "crafting", label = "Crafting", icon = "Interface\\Icons\\Trade_Alchemy" },
    { name = "raids", label = "Dungeons", icon = "Interface\\Icons\\INV_Misc_Key_13" },
  }

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/UI/?.lua"
    require("TopTabs")
    TopTabs = AltArmy.TopTabs
  end)

  before_each(function()
    saved = {}
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
    created = {}
    _G.CreateFrame = function(kind, _, _, template)
      local f = stubFrame(kind, template)
      if template == "TabSystemTemplate" then tabSystemStub(f) end
      return f
    end
    _G.CreateFramePool = function(_, _, template) return { template = template } end
  end)

  after_each(function()
    for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
  end)

  it("builds square icon tabs on the Forever TabSystem, with names as tooltips", function()
    local tabs = TopTabs.Create({}, defs, { caps = { topTabs = true, iconTabs = true } })
    local sys = tabs.frame
    assert.are.equal("TabSystemTemplate", sys.template)
    assert.are.equal("TabSystemTopButtonTemplate", sys.tabPool.template)
    assert.is_nil(sys.tabs[1].tabText)
    assert.are.equal("Interface\\Icons\\Trade_Alchemy", sys.tabs[1].tabIcon)
    assert.are.equal("Dungeons", sys.tabs[2].tooltipText)
  end)

  it("uses text top tabs when the client has no icon tab art (TBC)", function()
    local tabs = TopTabs.Create({}, defs, { caps = { topTabs = true, iconTabs = false } })
    assert.are.equal("Crafting", tabs.frame.tabs[1].tabText)
    assert.is_nil(tabs.frame.tabs[1].tabIcon)
  end)

  it("reports user clicks by name and selects visually by name", function()
    local picked
    local tabs = TopTabs.Create({}, defs, {
      caps = { topTabs = true, iconTabs = true },
      onSelect = function(name) picked = name end,
    })
    tabs.frame:SetTab(2, true)
    assert.are.equal("raids", picked)
    tabs:SetSelected("crafting")
    assert.are.equal(1, tabs.frame.selectedID)
  end)

  it("does not report programmatic selection as a user click", function()
    local picked
    local tabs = TopTabs.Create({}, defs, {
      caps = { topTabs = true, iconTabs = true },
      onSelect = function(name) picked = name end,
    })
    tabs.frame:SetTab(1, false)
    assert.is_nil(picked)
  end)

  describe("classic panel top tabs (TBC Anniversary: no TabSystem)", function()
    local savedSelect, savedDeselect, savedResize, calls

    before_each(function()
      savedSelect, savedDeselect, savedResize =
        _G.PanelTemplates_SelectTab, _G.PanelTemplates_DeselectTab, _G.PanelTemplates_TabResize
      calls = {}
      _G.PanelTemplates_SelectTab = function(tab) calls[#calls + 1] = { "select", tab } end
      _G.PanelTemplates_DeselectTab = function(tab) calls[#calls + 1] = { "deselect", tab } end
      _G.PanelTemplates_TabResize = function(tab, pad) tab.resized = pad end
    end)

    after_each(function()
      _G.PanelTemplates_SelectTab, _G.PanelTemplates_DeselectTab, _G.PanelTemplates_TabResize =
        savedSelect, savedDeselect, savedResize
    end)

    it("uses named PanelTopTabButtonTemplate text tabs sized to their labels", function()
      local tabs = TopTabs.Create({}, defs, { caps = { panelTopTabs = true } })
      local crafting = tabs.buttons.crafting
      assert.are.equal("PanelTopTabButtonTemplate", crafting.template)
      assert.are.equal("Crafting", crafting.text)
      assert.is_not_nil(crafting.resized)
      assert.are.equal("BOTTOMLEFT", crafting.points[1][1])
    end)

    it("selects one tab and deselects the rest via PanelTemplates", function()
      local tabs = TopTabs.Create({}, defs, { caps = { panelTopTabs = true } })
      tabs:SetSelected("raids")
      local selected, deselected = {}, {}
      for _, c in ipairs(calls) do
        if c[1] == "select" then selected[#selected + 1] = c[2] else deselected[#deselected + 1] = c[2] end
      end
      assert.are.same({ tabs.buttons.raids }, selected)
      assert.are.same({ tabs.buttons.crafting }, deselected)
    end)

    it("reports clicks by name", function()
      local picked
      local tabs = TopTabs.Create({}, defs, {
        caps = { panelTopTabs = true },
        onSelect = function(name) picked = name end,
      })
      tabs.buttons.raids.scripts.OnClick()
      assert.are.equal("raids", picked)
    end)
  end)

  it("falls back to toggle buttons without TabSystem", function()
    local skinned = {}
    AltArmy.Theme = AltArmy.Theme or {}
    local savedSkin = AltArmy.Theme.SkinButton
    AltArmy.Theme.SkinButton = function(btn, toggle)
      skinned[#skinned + 1] = toggle
      function btn:SetSelected(on) self.selected = on end
    end
    local picked
    local tabs = TopTabs.Create({}, defs, { caps = {}, onSelect = function(n) picked = n end })
    AltArmy.Theme.SkinButton = savedSkin
    assert.are.same({ true, true }, skinned)
    tabs.buttons.raids.scripts.OnClick()
    assert.are.equal("raids", picked)
    tabs:SetSelected("raids")
    assert.is_true(tabs.buttons.raids.selected)
    assert.is_false(tabs.buttons.crafting.selected)
  end)
end)
