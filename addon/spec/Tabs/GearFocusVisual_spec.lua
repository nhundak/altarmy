--[[
  Unit tests for Gear tab focus-mode column visuals (upgrade highlight + fade).
  Mirrors logic from TabGear.lua and GearUpgrade.lua.
]]

describe("Gear focus visuals", function()
    local UPGRADE_THRESHOLD_PERCENT = 5
    local FOCUS_FADE_ALPHA = 0.45

    --- Mirrors equipped-relative GetUpgradeHighlightKind (delta vs oldTotal).
    local function getUpgradeHighlightKind(delta, oldTotal, thresholdPercent)
        thresholdPercent = thresholdPercent or UPGRADE_THRESHOLD_PERCENT
        if not delta or delta <= 0 then return nil end
        oldTotal = tonumber(oldTotal) or 0
        local percent
        if oldTotal > 0 then
            percent = delta / oldTotal * 100
        elseif delta > 0 then
            percent = 100
        else
            percent = 0
        end
        if percent >= thresholdPercent then return "clear" end
        return "minor"
    end

    local function getFocusColumnAlpha(shouldDim, isSelected)
        if isSelected then return 1 end
        if shouldDim then return FOCUS_FADE_ALPHA end
        return 1
    end

    it("uses green bucket for clear upgrades", function()
        assert.are.equal("clear", getUpgradeHighlightKind(15, 100))
        assert.are.equal("clear", getUpgradeHighlightKind(5, 100))
        assert.are.equal("clear", getUpgradeHighlightKind(10, 0))
    end)

    it("uses yellow bucket for minor upgrades", function()
        assert.are.equal("minor", getUpgradeHighlightKind(4, 100))
        assert.are.equal("minor", getUpgradeHighlightKind(0.5, 100))
    end)

    it("returns nil highlight for non-upgrades", function()
        assert.is_nil(getUpgradeHighlightKind(0, 100))
        assert.is_nil(getUpgradeHighlightKind(nil, 100))
    end)

    it("dims never-equip, beyond-level, and downgrade columns", function()
        assert.are.equal(FOCUS_FADE_ALPHA, getFocusColumnAlpha(true))
        assert.are.equal(1, getFocusColumnAlpha(false))
    end)

    --- Mirror TabGear.GetFocusColumnDimmed soulbound policy.
    local function getFocusColumnDimmed(entry, soulbound, isCurrent, baseDimmed)
        if soulbound and not isCurrent then return true end
        return baseDimmed == true
    end

    it("dims non-current characters when the focused item is soulbound", function()
        assert.is_true(getFocusColumnDimmed({ name = "Alt" }, true, false, false))
        assert.is_false(getFocusColumnDimmed({ name = "Me" }, true, true, false))
    end)

    it("still dims current character for downgrade or unusable when soulbound", function()
        assert.is_true(getFocusColumnDimmed({ name = "Me" }, true, true, true))
    end)

    it("does not soulbound-dim when the focused item is not soulbound", function()
        assert.is_false(getFocusColumnDimmed({ name = "Alt" }, false, false, false))
    end)

    it("restores full opacity for the selected compare column", function()
        assert.are.equal(1, getFocusColumnAlpha(true, true))
        assert.are.equal(1, getFocusColumnAlpha(false, true))
    end)

    it("keeps class color on dimmed columns instead of forcing grayscale", function()
        local function headerNameColor(useGrayscale, classR, classG, classB)
            if useGrayscale then
                return 0.5, 0.5, 0.5
            end
            return classR, classG, classB
        end
        local r, g, b = headerNameColor(false, 0.96, 0.55, 0.73)
        assert.are.equal(0.96, r)
        assert.are.equal(0.55, g)
        assert.are.equal(0.73, b)
    end)

    it("shows header name highlight when compare column is selected", function()
        local UPGRADE_HIGHLIGHT_COLUMN_INSET = 2
        local SELECTED_CELL_HIGHLIGHT_INSET = UPGRADE_HIGHLIGHT_COLUMN_INSET + 2
        local ITEM_ICON_INSET = 2
        local ICON_SIZE = 32
        local function getSelectedHighlightWidth()
            local cellSize = ICON_SIZE + 2 * ITEM_ICON_INSET
            return cellSize + 2 * SELECTED_CELL_HIGHLIGHT_INSET
        end
        local function shouldShowHeaderSelectionHighlight(droppedItemLink, selectedKey, compareKey)
            return droppedItemLink ~= nil and selectedKey == compareKey
        end
        assert.is_true(shouldShowHeaderSelectionHighlight(
            "|Hitem:1|h", "Realm\\Bob", "Realm\\Bob"))
        assert.is_false(shouldShowHeaderSelectionHighlight(
            "|Hitem:1|h", "Realm\\Bob", "Realm\\Alice"))
        assert.is_false(shouldShowHeaderSelectionHighlight(
            nil, "Realm\\Bob", "Realm\\Bob"))
        assert.are.equal(4, SELECTED_CELL_HIGHLIGHT_INSET)
        assert.are.equal(44, getSelectedHighlightWidth())
    end)

    it("includes character name in header tooltip whenever tooltip is shown", function()
        local function resolveHeaderTooltipText(droppedItemLink, truncated, showRealmSuffix, hasRealm, formattedName)
            if droppedItemLink or truncated or (showRealmSuffix and hasRealm) then
                return formattedName
            end
            return nil
        end
        local name = "Bob-Thunderlord"
        assert.are.equal(name, resolveHeaderTooltipText("|Hitem:1|h", false, false, false, name))
        assert.are.equal(name, resolveHeaderTooltipText(nil, true, false, false, name))
        assert.are.equal(name, resolveHeaderTooltipText(nil, false, true, true, name))
        assert.is_nil(resolveHeaderTooltipText(nil, false, false, false, name))
        assert.is_nil(resolveHeaderTooltipText(nil, false, true, false, name))
    end)

    it("formats compare click hint with focused item name", function()
        local function formatCompareClickHint(itemName)
            if itemName and itemName ~= "" then
                return "Click to compare with " .. itemName
            end
            return "Click to compare"
        end
        assert.are.equal(
            "Click to compare with Fel Iron Plate Helm",
            formatCompareClickHint("Fel Iron Plate Helm"))
        assert.are.equal("Click to compare", formatCompareClickHint(nil))
        assert.are.equal("Click to compare", formatCompareClickHint(""))
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
