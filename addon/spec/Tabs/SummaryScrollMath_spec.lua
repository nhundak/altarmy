--[[
  Documents virtual-list vertical scroll math for TabSummary.lua (fixed row pool).
  Constants must match TabSummary.lua ROW_HEIGHT and NUM_ROWS.
]]

describe("Summary tab virtual list scroll math", function()
    local ROW_HEIGHT = 18
    local NUM_ROWS = 14

    --- Mirrors TabSummary Update(): max pixel scroll for the slider / ScrollFrame.
    local function maxScrollPixels(numItems)
        return math.max(0, (numItems - NUM_ROWS) * ROW_HEIGHT)
    end

    it("allows one ROW_HEIGHT scroll when there is exactly one row beyond the pool", function()
        assert.are.equal(ROW_HEIGHT, maxScrollPixels(NUM_ROWS + 1))
    end)

    it("does not require scroll when all items fit in the row pool", function()
        assert.are.equal(0, maxScrollPixels(NUM_ROWS))
        assert.are.equal(0, maxScrollPixels(3))
    end)

    it("does not tie max scroll to viewport height (tall viewport bug)", function()
        -- Wrong formula would be numItems * ROW_HEIGHT - viewportH; with a viewport taller than
        -- NUM_ROWS * ROW_HEIGHT that shrinks max scroll and hides last rows.
        local numItems = 30
        local wrong = math.max(0, numItems * ROW_HEIGHT - 400)
        local right = maxScrollPixels(numItems)
        assert.is_true(right > wrong)
    end)
end)
