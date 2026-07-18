--[[
  Unit tests for VirtualList.lua (viewport → render-range math).
  Run from project root: npm test
]]

describe("VirtualList", function()
  local VirtualList

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/UI/?.lua"
    package.loaded["VirtualList"] = nil
    require("VirtualList")
    VirtualList = AltArmy.VirtualList
  end)

  describe("GetRenderRange", function()
    it("returns nil when count is zero or negative", function()
      assert.is_nil(VirtualList.GetRenderRange(0, 180, 21, 18, 0, 3))
      assert.is_nil(VirtualList.GetRenderRange(0, 180, 21, 18, -1, 3))
    end)

    it("starts at row 1 when scroll is above the section", function()
      local range = VirtualList.GetRenderRange(0, 180, 21, 18, 100, 3)
      assert.are.equal(1, range.firstVisible)
      assert.are.equal(8, range.lastVisible)
      assert.are.equal(1, range.firstRender)
      assert.are.equal(11, range.lastRender)
      assert.are.equal(11, range.renderCount)
    end)

    it("computes mid-list visible and buffered ranges", function()
      -- sectionTop 21; scroll so row 6 is at the top of the section
      local scrollValue = 21 + 5 * 18
      local range = VirtualList.GetRenderRange(scrollValue, 180, 21, 18, 100, 3)
      assert.are.equal(6, range.firstVisible)
      assert.are.equal(15, range.lastVisible)
      assert.are.equal(3, range.firstRender)
      assert.are.equal(18, range.lastRender)
      assert.are.equal(16, range.renderCount)
    end)

    it("clamps the buffered range to the list bounds", function()
      local range = VirtualList.GetRenderRange(0, 180, 21, 18, 5, 3)
      assert.are.equal(1, range.firstRender)
      assert.are.equal(5, range.lastRender)
      assert.are.equal(5, range.renderCount)

      -- Near the end of a long list
      local endScroll = 21 + 90 * 18
      range = VirtualList.GetRenderRange(endScroll, 180, 21, 18, 100, 3)
      assert.are.equal(100, range.lastRender)
      assert.is_true(range.firstRender >= 1)
      assert.is_true(range.renderCount >= 1)
    end)

    it("defaults buffer to 0 when omitted", function()
      local range = VirtualList.GetRenderRange(0, 180, 21, 18, 100)
      assert.are.equal(1, range.firstRender)
      assert.are.equal(range.lastVisible, range.lastRender)
    end)
  end)

  describe("RowTopOffset", function()
    it("returns negative Y for the section's first row", function()
      assert.are.equal(-21, VirtualList.RowTopOffset(21, 1, 18))
    end)

    it("steps down by rowHeight for later indices", function()
      assert.are.equal(-21 - 2 * 18, VirtualList.RowTopOffset(21, 3, 18))
    end)
  end)

  describe("GroupPoolSpan", function()
    it("returns nil when the group does not intersect the render range", function()
      assert.is_nil(VirtualList.GroupPoolSpan({ start = 1, count = 2 }, 10, 20))
      assert.is_nil(VirtualList.GroupPoolSpan({ start = 30, count = 2 }, 10, 20))
    end)

    it("maps intersecting group rows to pool indices", function()
      local span = VirtualList.GroupPoolSpan({ start = 5, count = 4 }, 4, 10)
      -- group covers data 5..8; clipped to 5..8; pool relative to firstRender=4
      assert.are.equal(2, span.firstPoolIdx) -- data 5
      assert.are.equal(5, span.lastPoolIdx)  -- data 8
    end)

    it("clips groups that partially overlap the render window", function()
      local span = VirtualList.GroupPoolSpan({ start = 1, count = 10 }, 4, 8)
      assert.are.equal(1, span.firstPoolIdx) -- data 4
      assert.are.equal(5, span.lastPoolIdx)  -- data 8
    end)
  end)

  describe("IsVisibleRangeCovered", function()
    it("returns false when painted bounds are missing", function()
      assert.is_false(VirtualList.IsVisibleRangeCovered(1, 5, nil, 10, 1))
      assert.is_false(VirtualList.IsVisibleRangeCovered(1, 5, 1, nil, 1))
    end)

    it("is true while visible stays inside painted range with margin", function()
      -- painted 7..23, margin 1 → safe while visible within 8..22
      assert.is_true(VirtualList.IsVisibleRangeCovered(10, 20, 7, 23, 1))
      assert.is_true(VirtualList.IsVisibleRangeCovered(8, 22, 7, 23, 1))
    end)

    it("is false when visible reaches the painted edge within margin", function()
      assert.is_false(VirtualList.IsVisibleRangeCovered(7, 20, 7, 23, 1))
      assert.is_false(VirtualList.IsVisibleRangeCovered(10, 23, 7, 23, 1))
      assert.is_false(VirtualList.IsVisibleRangeCovered(15, 25, 7, 23, 1))
    end)
  end)

  describe("ForEachPoolSlot", function()
    it("invokes show for renderCount slots and hide for the rest", function()
      local shown = {}
      local hidden = {}
      VirtualList.ForEachPoolSlot(5, 3, 2, function(poolIdx, dataIndex)
        shown[#shown + 1] = { poolIdx, dataIndex }
      end, function(poolIdx)
        hidden[#hidden + 1] = poolIdx
      end)
      assert.are.same({ { 1, 3 }, { 2, 4 } }, shown)
      assert.are.same({ 3, 4, 5 }, hidden)
    end)

    it("hides the entire pool when renderCount is 0", function()
      local hidden = {}
      VirtualList.ForEachPoolSlot(3, 1, 0, function()
        error("should not show")
      end, function(poolIdx)
        hidden[#hidden + 1] = poolIdx
      end)
      assert.are.same({ 1, 2, 3 }, hidden)
    end)
  end)

  describe("ShouldFillPoolRow", function()
    it("skips fill when scrolling reuses the same data index", function()
      assert.is_false(VirtualList.ShouldFillPoolRow(false, 3, 3))
    end)

    it("fills when the pool slot binds a different data index", function()
      assert.is_true(VirtualList.ShouldFillPoolRow(false, 3, 7))
      assert.is_true(VirtualList.ShouldFillPoolRow(false, nil, 1))
    end)

    it("fills on force paint even when data index is unchanged", function()
      -- Query/highlight changes keep the same row indices; must refill for highlight text.
      assert.is_true(VirtualList.ShouldFillPoolRow(true, 3, 3))
    end)
  end)
end)
