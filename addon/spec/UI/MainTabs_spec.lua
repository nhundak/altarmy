--[[
  Unit tests for MainTabs.lua (main window tab registry).
  Run from project root: npm test
]]

describe("MainTabs", function()
  local MainTabs

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/UI/?.lua"
    require("MainTabs")
    MainTabs = AltArmy.MainTabs
  end)

  it("lists the side tabs in display order with Guild last", function()
    assert.are.same(
      { "Summary", "Gear", "Reputation", "Cooldowns", "Graph", "Guild" },
      MainTabs.ORDER
    )
  end)

  it("gives every tab (and Search) a label and an icon path", function()
    for _, name in ipairs(MainTabs.ORDER) do
      local def = MainTabs.Get(name)
      assert.is_table(def)
      assert.are.equal(name, def.name)
      assert.is_string(def.label)
      assert.truthy(def.icon:match("^Interface\\Icons\\"))
    end
    assert.is_string(MainTabs.Get("Search").icon)
  end)

  it("labels Graph as Graphs", function()
    assert.are.equal("Graphs", MainTabs.Get("Graph").label)
  end)

  it("returns nil for unknown tabs", function()
    assert.is_nil(MainTabs.Get("Characters"))
    assert.is_nil(MainTabs.Get(nil))
  end)

  describe("Title", function()
    it("prefixes the addon name", function()
      assert.are.equal("Alt Army - Reputation", MainTabs.Title("Reputation"))
      assert.are.equal("Alt Army - Graphs", MainTabs.Title("Graph"))
      assert.are.equal("Alt Army - Search", MainTabs.Title("Search"))
    end)

    it("falls back to the bare addon name", function()
      assert.are.equal("Alt Army", MainTabs.Title("Nope"))
    end)
  end)

  describe("settings", function()
    it("describes toggle-panel settings by frame method names", function()
      local s = MainTabs.Get("Gear").settings
      assert.are.equal("ToggleGearSettings", s.toggle)
      assert.are.equal("IsGearSettingsShown", s.isShown)
      assert.are.equal("ToggleSearchSettings", MainTabs.Get("Search").settings.toggle)
    end)

    it("routes Cooldowns settings to Interface Options", function()
      assert.are.equal("cooldowns", MainTabs.Get("Cooldowns").settings.optionsKey)
    end)

    it("has no settings for Graph or Guild", function()
      assert.is_nil(MainTabs.Get("Graph").settings)
      assert.is_nil(MainTabs.Get("Guild").settings)
    end)
  end)
end)
