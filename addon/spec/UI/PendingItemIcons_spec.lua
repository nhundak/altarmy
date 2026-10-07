--[[
  Unit tests for PendingItemIcons.lua (redraw once when uncached item icons arrive).
  Run from project root: npm test
]]

describe("PendingItemIcons", function()
  local P
  local saved
  local GLOBALS = { "CreateFrame", "C_Timer" }
  local frames, timers

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/UI/?.lua"
    package.loaded["PendingItemIcons"] = nil
    require("PendingItemIcons")
    P = AltArmy.PendingItemIcons
  end)

  before_each(function()
    saved = {}
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
    frames, timers = {}, {}
    _G.CreateFrame = function()
      local f = { events = {} }
      function f:RegisterEvent(e) self.events[e] = true end
      function f:SetScript(_, fn) self.onEvent = fn end
      table.insert(frames, f)
      return f
    end
    _G.C_Timer = { After = function(_, fn) table.insert(timers, fn) end }
  end)

  after_each(function()
    for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
  end)

  local function runTimers()
    local due = timers
    timers = {}
    for _, fn in ipairs(due) do fn() end
  end

  it("registers one event frame lazily and redraws once per frame for a burst of arrivals", function()
    local redraws = 0
    local t = P.Create(function() redraws = redraws + 1 end)
    assert.are.equal(0, #frames)
    t.Track(100)
    t.Track(200)
    t.Track(nil)
    assert.are.equal(1, #frames)
    assert.is_true(frames[1].events.GET_ITEM_INFO_RECEIVED)
    assert.is_true(t.IsPending(100))
    frames[1].onEvent(frames[1], "GET_ITEM_INFO_RECEIVED", 100)
    frames[1].onEvent(frames[1], "GET_ITEM_INFO_RECEIVED", "200")
    assert.are.equal(0, redraws)
    assert.are.equal(1, #timers)
    runTimers()
    assert.are.equal(1, redraws)
    assert.is_false(t.IsPending(100))
  end)

  it("ignores ids it is not waiting for and forgets everything on Clear", function()
    local redraws = 0
    local t = P.Create(function() redraws = redraws + 1 end)
    t.Track(100)
    frames[1].onEvent(frames[1], "GET_ITEM_INFO_RECEIVED", 999)
    assert.are.equal(0, #timers)
    t.Clear()
    assert.is_false(t.IsPending(100))
    frames[1].onEvent(frames[1], "GET_ITEM_INFO_RECEIVED", 100)
    assert.are.equal(0, #timers)
    assert.are.equal(0, redraws)
  end)

  it("redraws at once without C_Timer", function()
    _G.C_Timer = nil
    local redraws = 0
    local t = P.Create(function() redraws = redraws + 1 end)
    t.Track(7)
    frames[1].onEvent(frames[1], "GET_ITEM_INFO_RECEIVED", 7)
    assert.are.equal(1, redraws)
  end)
end)
