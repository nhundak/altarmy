--[[
  Unit tests for ClassColor.lua.
  Run from project root: npm test
]]

describe("ClassColor", function()
  local CC

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS or {
      WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
      MAGE = { r = 0.41, g = 0.8, b = 0.94 },
    }
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("ClassColor")
    CC = AltArmy.ClassColor
  end)

  describe("getRGB", function()
    it("returns RAID class color components", function()
      local r, g, b = CC.getRGB("MAGE")
      assert.are.equal(0.41, r)
      assert.are.equal(0.8, g)
      assert.are.equal(0.94, b)
    end)

    it("returns neutral for unknown class", function()
      local r, g, b = CC.getRGB(nil)
      assert.are.equal(0.7, r)
      assert.are.equal(0.7, g)
      assert.are.equal(0.7, b)
    end)
  end)

  describe("getRGBOr", function()
    it("uses caller default when class unknown", function()
      local r, g, b = CC.getRGBOr(nil, 1, 0.82, 0)
      assert.are.equal(1, r)
      assert.are.equal(0.82, g)
      assert.are.equal(0, b)
    end)
  end)

  describe("formatName", function()
    it("wraps name in class color escape sequences", function()
      local out = CC.formatName("Alice", "WARRIOR")
      assert.is_true(out:find("|cff", 1, true) ~= nil)
      assert.is_true(out:find("Alice", 1, true) ~= nil)
      assert.is_true(out:find("|r", 1, true) ~= nil)
    end)

    it("uses white when class unknown", function()
      assert.are.equal("|cffffffffBob|r", CC.formatName("Bob", nil))
    end)
  end)

  describe("wrapName", function()
    it("returns plain text when class unknown", function()
      assert.are.equal("Plain", CC.wrapName("Plain", nil))
    end)

    it("returns colored text when class known", function()
      local out = CC.wrapName("Plain", "MAGE")
      assert.is_true(out:find("|cff", 1, true) ~= nil)
    end)
  end)

  describe("formatNameWithSuffix", function()
    it("appends a title-colored suffix after the class-colored name", function()
      local out = CC.formatNameWithSuffix("Alice", "WARRIOR", " options", { 0.85, 0.78, 0.42 })
      assert.is_true(out:find("Alice", 1, true) ~= nil)
      assert.is_true(out:find(" options", 1, true) ~= nil)
      -- Class-colored name segment, then title-colored suffix segment.
      assert.is_true(out:find("|cff", 1, true) ~= nil)
      assert.is_true(out:find("|r options", 1, true) == nil) -- suffix has its own color wrap
      local nameEnd = out:find("|r", 1, true)
      assert.is_truthy(nameEnd)
      local suffixPart = out:sub(nameEnd + 2)
      assert.is_true(suffixPart:find("|cff", 1, true) ~= nil)
      assert.is_true(suffixPart:find(" options", 1, true) ~= nil)
    end)

    it("leaves suffix uncolored when suffixRgb is nil", function()
      assert.are.equal(
        CC.formatName("Bob", nil) .. " options",
        CC.formatNameWithSuffix("Bob", nil, " options", nil)
      )
    end)
  end)
end)
