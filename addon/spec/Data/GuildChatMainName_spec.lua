--[[
  Unit tests for GuildChatMainName.lua (pure guild-chat main-name annotation).
  Run from project root: npm test
]]

describe("GuildChatMainName", function()
  local GCM

  local function mains(map)
    return function(sender) return map[sender] end
  end

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("GuildChatMainName")
    GCM = AltArmy.GuildChatMainName
    assert.truthy(GCM)
  end)

  it("appends the main name when the sender is a known alt", function()
    local out = GCM.Transform("Alt", "hello", mains({ Alt = "Mainman" }))
    assert.truthy(out:find("Mainman", 1, true))
    assert.truthy(out:find("hello", 1, true))
  end)

  it("leaves the message unchanged when the sender is their own main", function()
    assert.are.equal("hello", GCM.Transform("Mainman", "hello", mains({ Mainman = "Mainman" })))
  end)

  it("leaves the message unchanged when the sender is unknown", function()
    assert.are.equal("hi", GCM.Transform("Stranger", "hi", mains({})))
  end)

  it("leaves the message unchanged with no resolver", function()
    assert.are.equal("hi", GCM.Transform("Alt", "hi", nil))
  end)

  it("does not annotate twice if the main equals the sender name case-sensitively only", function()
    -- Different name -> annotate once.
    local out = GCM.Transform("Alt", "yo", mains({ Alt = "Boss" }))
    local _, count = out:gsub("Boss", "Boss")
    assert.are.equal(1, count)
  end)
end)
