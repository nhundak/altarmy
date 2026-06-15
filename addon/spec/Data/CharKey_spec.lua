--[[
  Unit tests for CharKey.lua.
  Run from project root: npm test
]]

describe("CharKey", function()
  local CharKey

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("CharKey")
    CharKey = AltArmy.CharKey
  end)

  it("builds realm\\name key", function()
    assert.are.equal("RealmA\\Alice", CharKey("Alice", "RealmA"))
  end)

  it("handles nil name and realm", function()
    assert.are.equal("\\", CharKey(nil, nil))
    assert.are.equal("RealmA\\", CharKey(nil, "RealmA"))
    assert.are.equal("\\Bob", CharKey("Bob", nil))
  end)

  it("matches saved-var format used in gear settings", function()
    assert.are.equal("RealmA\\Me", CharKey("Me", "RealmA"))
  end)
end)
