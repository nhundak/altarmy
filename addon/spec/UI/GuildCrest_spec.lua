--[[
  Unit tests for GuildCrest.lua (player guild tabard drawn into three textures).
  Run from project root: npm test
]]

describe("GuildCrest", function()
  local GC
  local saved
  local GLOBALS = { "IsInGuild", "SetLargeGuildTabardTextures", "C_GuildInfo" }

  local function tex()
    local t = {}
    function t:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function t:SetTexture(f) self.texture = f end
    return t
  end

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/UI/?.lua"
    require("GuildCrest")
    GC = AltArmy.GuildCrest
  end)

  before_each(function()
    saved = {}
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
  end)

  after_each(function()
    for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
  end)

  it("draws nothing when the player is not in a guild", function()
    _G.IsInGuild = function() return false end
    local called = false
    _G.SetLargeGuildTabardTextures = function() called = true end
    assert.is_false(GC.Apply(tex(), tex(), tex()))
    assert.is_false(called)
  end)

  it("uses SetLargeGuildTabardTextures(player, emblem, background, border)", function()
    _G.IsInGuild = function() return true end
    local args
    _G.SetLargeGuildTabardTextures = function(...) args = { ... } end
    local bg, emblem, border = tex(), tex(), tex()
    assert.is_true(GC.Apply(bg, emblem, border))
    assert.are.same({ "player", emblem, bg, border }, args)
  end)

  it("falls back to C_GuildInfo tabard info", function()
    _G.IsInGuild = function() return true end
    _G.SetLargeGuildTabardTextures = nil
    _G.C_GuildInfo = {
      GetGuildTabardInfo = function()
        return { backgroundColor = { r = 0.1, g = 0.2, b = 0.3 }, emblemFileID = 123 }
      end,
    }
    local bg, emblem, border = tex(), tex(), tex()
    assert.is_true(GC.Apply(bg, emblem, border))
    assert.are.same({ 0.1, 0.2, 0.3, 1 }, bg.color)
    assert.are.equal(123, emblem.texture)
  end)

  it("reports false when no tabard API is available", function()
    _G.IsInGuild = function() return true end
    _G.SetLargeGuildTabardTextures, _G.C_GuildInfo = nil, nil
    assert.is_false(GC.Apply(tex(), tex(), tex()))
  end)

  describe("CreateLayers backdrop", function()
    local function parent()
      local p = { created = {} }
      function p:CreateTexture(_, layer, _, sub)
        local t = tex()
        t.layer, t.sub, t.shown = layer, sub, true
        function t:SetAllPoints() end
        function t:Hide() self.shown = false end
        function t:SetShown(on) self.shown = on end
        table.insert(p.created, t)
        return t
      end
      return p
    end

    it("adds an opaque backing under the crest, shown only when a crest is drawn", function()
      local p = parent()
      local layers = GC.CreateLayers(p, {}, { subLevel = 2, backdrop = { 0, 0, 0, 1 } })
      assert.is_not_nil(layers.backdrop)
      assert.are.same({ 0, 0, 0, 1 }, layers.backdrop.color)
      assert.are.equal(2, layers.backdrop.sub)
      assert.are.equal(3, layers.background.sub)
      assert.are.equal(5, layers.border.sub)

      _G.IsInGuild = function() return false end
      assert.is_false(layers:Refresh())
      assert.is_false(layers.backdrop.shown)

      _G.IsInGuild = function() return true end
      _G.SetLargeGuildTabardTextures = function() end
      assert.is_true(layers:Refresh())
      assert.is_true(layers.backdrop.shown)
    end)

    it("creates no backing by default", function()
      local p = parent()
      local layers = GC.CreateLayers(p, {}, {})
      assert.is_nil(layers.backdrop)
      assert.are.equal(3, #p.created)
    end)
  end)
end)
