--[[
  Unit tests for SlideTransition.lua (horizontal page-slide offset math).
  Run from project root: npm test
]]

describe("SlideTransition", function()
  local SlideTransition

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/UI/?.lua"
    package.loaded["SlideTransition"] = nil
    require("SlideTransition")
    SlideTransition = AltArmy.SlideTransition
  end)

  describe("EaseOut", function()
    it("returns 0 at progress 0 and 1 at progress 1", function()
      assert.are.equal(0, SlideTransition.EaseOut(0))
      assert.are.equal(1, SlideTransition.EaseOut(1))
    end)

    it("clamps progress outside [0, 1]", function()
      assert.are.equal(0, SlideTransition.EaseOut(-0.5))
      assert.are.equal(1, SlideTransition.EaseOut(1.5))
    end)

    it("moves faster at the start than linear (ease-out)", function()
      local mid = SlideTransition.EaseOut(0.5)
      assert.is_true(mid > 0.5)
      assert.is_true(mid < 1)
    end)
  end)

  describe("ComputeOffsets", function()
    it("at progress 0: outgoing at 0, incoming off-screen in the entry direction", function()
      local outX, inX = SlideTransition.ComputeOffsets(0, 200, "forward")
      assert.are.equal(0, outX)
      assert.are.equal(200, inX)

      outX, inX = SlideTransition.ComputeOffsets(0, 200, "back")
      assert.are.equal(0, outX)
      assert.are.equal(-200, inX)
    end)

    it("at progress 1: outgoing off-screen, incoming at 0", function()
      local outX, inX = SlideTransition.ComputeOffsets(1, 200, "forward")
      assert.are.equal(-200, outX)
      assert.are.equal(0, inX)

      outX, inX = SlideTransition.ComputeOffsets(1, 200, "back")
      assert.are.equal(200, outX)
      assert.are.equal(0, inX)
    end)

    it("defaults unknown direction to forward", function()
      local outX, inX = SlideTransition.ComputeOffsets(1, 100, nil)
      assert.are.equal(-100, outX)
      assert.are.equal(0, inX)
    end)

    it("treats non-positive width as zero offsets", function()
      local outX, inX = SlideTransition.ComputeOffsets(0.5, 0, "forward")
      assert.are.equal(0, outX)
      assert.are.equal(0, inX)
    end)

    it("applies ease-out so midpoint is past half the distance", function()
      local outX, inX = SlideTransition.ComputeOffsets(0.5, 100, "forward")
      -- ease-out(0.5) > 0.5, so outgoing further left than -50
      assert.is_true(outX < -50)
      assert.is_true(inX > 0)
      assert.is_true(inX < 50)
    end)
  end)

  describe("Step", function()
    it("returns not-done before duration and done at/after duration", function()
      local duration = SlideTransition.DEFAULT_DURATION
      local r = SlideTransition.Step(0, duration, 120, "forward")
      assert.is_false(r.done)
      assert.are.equal(0, r.outX)
      assert.are.equal(120, r.inX)

      r = SlideTransition.Step(duration, duration, 120, "forward")
      assert.is_true(r.done)
      assert.are.equal(-120, r.outX)
      assert.are.equal(0, r.inX)

      r = SlideTransition.Step(duration + 1, duration, 120, "forward")
      assert.is_true(r.done)
    end)

    it("uses DEFAULT_DURATION when duration is nil or non-positive", function()
      local r = SlideTransition.Step(0, nil, 100, "forward")
      assert.is_false(r.done)
      local mid = SlideTransition.Step(SlideTransition.DEFAULT_DURATION / 2, nil, 100, "forward")
      assert.is_false(mid.done)
      local endStep = SlideTransition.Step(SlideTransition.DEFAULT_DURATION, 0, 100, "forward")
      assert.is_true(endStep.done)
    end)
  end)
end)
