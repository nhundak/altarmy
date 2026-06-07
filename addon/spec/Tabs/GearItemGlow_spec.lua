--[[
  Unit tests for Gear tab item quality glow eligibility.
  Mirrors GetQualityGlowColor from TabGear.lua.
  Run from project root: npm test
]]

describe("Gear item quality glow", function()
    local function GetQualityGlowColor(quality)
        if quality == nil or quality < 2 or quality > 5 then return nil end
        if quality == 2 then return 0, 1, 0 end
        if quality == 3 then return 0, 0.44, 0.87 end
        if quality == 4 then return 0.64, 0.21, 0.93 end
        return 1, 0.5, 0
    end

    it("returns no glow color for poor and common items", function()
        assert.is_nil(GetQualityGlowColor(0))
        assert.is_nil(GetQualityGlowColor(1))
    end)

    it("returns glow color for uncommon through legendary", function()
        assert.are.equal(0, select(1, GetQualityGlowColor(2)))
        assert.are.equal(1, select(2, GetQualityGlowColor(2)))
        assert.are.equal(0, select(3, GetQualityGlowColor(2)))

        assert.are.equal(0, select(1, GetQualityGlowColor(3)))
        assert.are.equal(0.44, select(2, GetQualityGlowColor(3)))

        assert.are.equal(0.64, select(1, GetQualityGlowColor(4)))
        assert.are.equal(0.21, select(2, GetQualityGlowColor(4)))

        assert.are.equal(1, select(1, GetQualityGlowColor(5)))
        assert.are.equal(0.5, select(2, GetQualityGlowColor(5)))
    end)

    it("returns no glow for qualities outside TBC item tiers", function()
        assert.is_nil(GetQualityGlowColor(nil))
        assert.is_nil(GetQualityGlowColor(6))
    end)
end)
