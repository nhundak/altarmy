--[[
  Unit tests for Gear tab focus-mode column visuals (upgrade highlight + fade).
  Mirrors logic from TabGear.lua.
]]

describe("Gear focus visuals", function()
    local CLEAR_UPGRADE_RATIO = 0.5
    local FOCUS_FADE_ALPHA = 0.45

    local function getUpgradeHighlightKind(delta, maxDelta)
        if not delta or delta <= 0 then return nil end
        if not maxDelta or maxDelta <= 0 then return "clear" end
        if delta >= maxDelta * CLEAR_UPGRADE_RATIO then return "clear" end
        return "minor"
    end

    local function getFocusColumnAlpha(focusTier, isSelected)
        if isSelected then return 1 end
        if focusTier == 1 then return 1 end
        return FOCUS_FADE_ALPHA
    end

    it("uses green bucket for clear upgrades", function()
        assert.are.equal("clear", getUpgradeHighlightKind(15, 15))
        assert.are.equal("clear", getUpgradeHighlightKind(10, 15))
    end)

    it("uses yellow bucket for minor upgrades", function()
        assert.are.equal("minor", getUpgradeHighlightKind(3, 15))
    end)

    it("returns nil highlight for non-upgrades", function()
        assert.is_nil(getUpgradeHighlightKind(0, 15))
        assert.is_nil(getUpgradeHighlightKind(nil, 15))
    end)

    it("fades usable and cannot-use columns in focus mode", function()
        assert.are.equal(1, getFocusColumnAlpha(1))
        assert.are.equal(FOCUS_FADE_ALPHA, getFocusColumnAlpha(2))
        assert.are.equal(FOCUS_FADE_ALPHA, getFocusColumnAlpha(3))
    end)

    it("restores full opacity for the selected compare column", function()
        assert.are.equal(1, getFocusColumnAlpha(2, true))
        assert.are.equal(1, getFocusColumnAlpha(3, true))
    end)

    local UPGRADE_BADGE_TEXT = { clear = "+", minor = "~" }

    local function getHeaderUpgradeBadgeText(kind)
        return kind and UPGRADE_BADGE_TEXT[kind] or nil
    end

    it("maps upgrade kinds to header badge glyphs", function()
        assert.are.equal("+", getHeaderUpgradeBadgeText("clear"))
        assert.are.equal("~", getHeaderUpgradeBadgeText("minor"))
        assert.is_nil(getHeaderUpgradeBadgeText(nil))
    end)

    local FOCUS_GRID_HEIGHT_SLACK = 2
    local PAD = 4

    local function getScrollableGridHeight(visibleCount, rowHeight, focused)
        local h = visibleCount * rowHeight + PAD
        if focused then
            h = h + FOCUS_GRID_HEIGHT_SLACK
        end
        return h
    end

    it("adds slack to focused grid height so the viewport avoids vertical scroll", function()
        local rh = 48
        assert.are.equal(1 * rh + PAD + FOCUS_GRID_HEIGHT_SLACK, getScrollableGridHeight(1, rh, true))
        assert.are.equal(2 * rh + PAD + FOCUS_GRID_HEIGHT_SLACK, getScrollableGridHeight(2, rh, true))
        assert.are.equal(2 * rh + PAD, getScrollableGridHeight(2, rh, false))
    end)
end)
