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
end)
