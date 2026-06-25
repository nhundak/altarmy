--[[
  Unit tests for Gear tab focus-mode column visuals (upgrade highlight + fade).
  Mirrors logic from TabGear.lua and GearUpgrade.lua.
]]

describe("Gear focus visuals", function()
    local CLEAR_UPGRADE_RATIO = 0.10
    local FOCUS_FADE_ALPHA = 0.45

    local function getUpgradeHighlightKind(delta, maxDelta)
        if not delta or delta <= 0 then return nil end
        if not maxDelta or maxDelta <= 0 then return "clear" end
        if delta >= maxDelta * CLEAR_UPGRADE_RATIO then return "clear" end
        return "minor"
    end

    local function getFocusColumnAlpha(shouldDim, isSelected)
        if isSelected then return 1 end
        if shouldDim then return FOCUS_FADE_ALPHA end
        return 1
    end

    it("uses green bucket for clear upgrades", function()
        assert.are.equal("clear", getUpgradeHighlightKind(15, 15))
        assert.are.equal("clear", getUpgradeHighlightKind(10, 15))
    end)

    it("uses yellow bucket for minor upgrades", function()
        assert.are.equal("minor", getUpgradeHighlightKind(0.5, 15))
    end)

    it("returns nil highlight for non-upgrades", function()
        assert.is_nil(getUpgradeHighlightKind(0, 15))
        assert.is_nil(getUpgradeHighlightKind(nil, 15))
    end)

    it("dims never-equip, beyond-level, and downgrade columns", function()
        assert.are.equal(FOCUS_FADE_ALPHA, getFocusColumnAlpha(true))
        assert.are.equal(1, getFocusColumnAlpha(false))
    end)

    it("restores full opacity for the selected compare column", function()
        assert.are.equal(1, getFocusColumnAlpha(true, true))
        assert.are.equal(1, getFocusColumnAlpha(false, true))
    end)

    local UPGRADE_BADGE_TEXT = {
        upgrade = "+",
        sidegrade = "~",
        upgradeFuture = "+",
        sidegradeFuture = "~",
        unusable = "x",
    }

    local function getHeaderUpgradeBadgeText(kind)
        return kind and UPGRADE_BADGE_TEXT[kind] or nil
    end

    it("maps focus badge kinds to glyphs", function()
        assert.are.equal("+", getHeaderUpgradeBadgeText("upgrade"))
        assert.are.equal("~", getHeaderUpgradeBadgeText("sidegrade"))
        assert.are.equal("+", getHeaderUpgradeBadgeText("upgradeFuture"))
        assert.are.equal("~", getHeaderUpgradeBadgeText("sidegradeFuture"))
        assert.are.equal("x", getHeaderUpgradeBadgeText("unusable"))
        assert.is_nil(getHeaderUpgradeBadgeText(nil))
    end)

    local ITEM_ICON_INSET = 2
    local UPGRADE_BADGE_OFFSET_Y = -(ITEM_ICON_INSET + 4)
    local UPGRADE_BADGE_SIDEGRADE_Y_EXTRA = -10
    local UPGRADE_BADGE_UPGRADE_Y_ADJUST = -2
    local UPGRADE_BADGE_SIDEGRADE_Y_ADJUST = 2

    local function getUpgradeBadgeOffsetY(kind)
        local y = UPGRADE_BADGE_OFFSET_Y
        if kind == "upgrade" or kind == "upgradeFuture" then
            y = y + UPGRADE_BADGE_UPGRADE_Y_ADJUST
        elseif kind == "sidegrade" or kind == "sidegradeFuture" then
            y = y + UPGRADE_BADGE_SIDEGRADE_Y_EXTRA + UPGRADE_BADGE_SIDEGRADE_Y_ADJUST
        end
        return y
    end

    it("offsets upgrade and sidegrade badge glyphs separately", function()
        assert.are.equal(UPGRADE_BADGE_OFFSET_Y + UPGRADE_BADGE_UPGRADE_Y_ADJUST, getUpgradeBadgeOffsetY("upgrade"))
        assert.are.equal(UPGRADE_BADGE_OFFSET_Y + UPGRADE_BADGE_UPGRADE_Y_ADJUST, getUpgradeBadgeOffsetY("upgradeFuture"))
        assert.are.equal(
            UPGRADE_BADGE_OFFSET_Y + UPGRADE_BADGE_SIDEGRADE_Y_EXTRA + UPGRADE_BADGE_SIDEGRADE_Y_ADJUST,
            getUpgradeBadgeOffsetY("sidegrade"))
        assert.are.equal(
            UPGRADE_BADGE_OFFSET_Y + UPGRADE_BADGE_SIDEGRADE_Y_EXTRA + UPGRADE_BADGE_SIDEGRADE_Y_ADJUST,
            getUpgradeBadgeOffsetY("sidegradeFuture"))
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
