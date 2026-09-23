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
      assert.truthy(def.icon:match("^Interface\\Icons\\")
        or def.icon:match("^Interface\\AddOns\\AltArmy_TBC\\Textures\\Icons\\"))
    end
    assert.is_string(MainTabs.Get("Search").icon)
  end)

  describe("native side-tab icons", function()
    local savedProject, savedMainline

    local function reload(project)
      _G.WOW_PROJECT_ID, _G.WOW_PROJECT_MAINLINE = project, 1
      package.loaded["MainTabs"] = nil
      AltArmy.MainTabs = nil
      require("MainTabs")
      return AltArmy.MainTabs
    end

    before_each(function()
      savedProject, savedMainline = _G.WOW_PROJECT_ID, _G.WOW_PROJECT_MAINLINE
    end)

    after_each(function()
      _G.WOW_PROJECT_ID, _G.WOW_PROJECT_MAINLINE = savedProject, savedMainline
      MainTabs = reload(savedProject)
    end)

    it("uses the CharacterFrame Reputation / Statistics tab icons on Forever", function()
      local tabs = reload(1)
      assert.are.equal("Interface\\Icons\\INV_SideTab_Reputation2_c60", tabs.Get("Reputation").icon)
      assert.are.equal("Interface\\Icons\\INV_SideTab_Stats_c60", tabs.Get("Graph").icon)
    end)

    it("uses the bundled copies of those icons on TBC Anniversary, which lacks the files", function()
      local tabs = reload(5)
      assert.are.equal(
        "Interface\\AddOns\\AltArmy_TBC\\Textures\\Icons\\INV_SideTab_Reputation2_c60",
        tabs.Get("Reputation").icon)
      assert.are.equal(
        "Interface\\AddOns\\AltArmy_TBC\\Textures\\Icons\\INV_SideTab_Stats_c60",
        tabs.Get("Graph").icon)
    end)

    it("ships the bundled icon files", function()
      for _, name in ipairs({ "INV_SideTab_Reputation2_c60", "INV_SideTab_Stats_c60" }) do
        local f = io.open("AltArmy_TBC/Textures/Icons/" .. name .. ".blp", "rb")
        assert.is_not_nil(f, name)
        assert.are.equal("BLP2", f:read(4))
        f:close()
      end
    end)

    it("keeps stock game icons for tabs without a native side-tab icon", function()
      assert.are.equal("Interface\\Icons\\INV_Misc_PocketWatch_01", reload(5).Get("Cooldowns").icon)
    end)

    it("marks the Guild tab to show the guild crest", function()
      assert.is_true(reload(1).Get("Guild").guildCrest)
      assert.are.equal("Interface\\Icons\\INV_Shirt_GuildTabard_01", MainTabs.Get("Guild").icon)
    end)
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
