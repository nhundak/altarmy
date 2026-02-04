--[[
  Unit tests for SummaryData.lua (formatting helpers).
  Run from project root: npm test
]]

describe("SummaryData", function()
  local SD

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("SummaryData")
    SD = AltArmy.SummaryData
  end)

  describe("GetMoneyString", function()
    it("formats copper only", function()
      local s = SD.GetMoneyString(99)
      assert.truthy(s:find("99"))
      assert.truthy(s:find("|t"))
    end)
    it("formats silver and copper when no gold", function()
      local s = SD.GetMoneyString(150)
      assert.truthy(s:find("1"))
      assert.truthy(s:find("50"))
    end)
    it("formats gold, silver, copper", function()
      local s = SD.GetMoneyString(10000)
      assert.truthy(s:find("1"))
      assert.truthy(s:find("0"))
    end)
    it("treats nil as 0", function()
      local s = SD.GetMoneyString(nil)
      assert.truthy(s:find("0"))
    end)
  end)

  describe("FormatRestXp", function()
    it("returns empty string for nil", function()
      assert.are.equal(SD.FormatRestXp(nil), "")
    end)
    it("rounds to one decimal", function()
      assert.are.equal(SD.FormatRestXp(50.34), "50.3%")
      assert.are.equal(SD.FormatRestXp(50.36), "50.4%")
    end)
    it("formats integer rate", function()
      assert.are.equal(SD.FormatRestXp(100), "100.0%")
    end)
  end)

  describe("GetTimeString", function()
    it("uses fallback when SecondsToTime missing", function()
      local old = _G.SecondsToTime
      _G.SecondsToTime = nil
      local s = SD.GetTimeString(0)
      assert.truthy(s:find("0"))
      assert.truthy(s:find("m"))
      _G.SecondsToTime = old
    end)
    it("fallback formats days and hours", function()
      local old = _G.SecondsToTime
      _G.SecondsToTime = nil
      local s = SD.GetTimeString(90061)
      assert.truthy(s:find("1d") or s:find("1"))
      _G.SecondsToTime = old
    end)
    it("treats nil as 0", function()
      local old = _G.SecondsToTime
      _G.SecondsToTime = nil
      local s = SD.GetTimeString(nil)
      assert.truthy(#s > 0)
      _G.SecondsToTime = old
    end)
  end)

  describe("FormatLastOnline", function()
    it("returns Online when isCurrent", function()
      assert.are.equal(SD.FormatLastOnline(nil, true), "Online")
      assert.are.equal(SD.FormatLastOnline(0, true), "Online")
    end)
    it("returns Unknown when lastLogout is nil", function()
      assert.are.equal(SD.FormatLastOnline(nil, false), "Unknown")
    end)
    it("returns Unknown when lastLogout >= sentinel", function()
      assert.are.equal(SD.FormatLastOnline(5000000000, false), "Unknown")
      assert.are.equal(SD.FormatLastOnline(6000000000, false), "Unknown")
    end)
    it("returns Just now when ago < 60 seconds", function()
      local old = _G.time
      _G.time = function() return 100 end
      assert.are.equal(SD.FormatLastOnline(50, false), "Just now")
      _G.time = old
    end)
    it("returns Xm ago when ago in minutes", function()
      local old = _G.time
      _G.time = function() return 1000 end
      local s = SD.FormatLastOnline(100)
      assert.truthy(s:find("ago"))
      assert.truthy(s:find("m") or s:find("h") or s:find("d"))
      _G.time = old
    end)
  end)
end)
