--[[
  Unit tests for Gear tab compare panel height (two-column layout).
  Mirrors EstimateComparePanelHeight from TabGear.lua.
]]

describe("Gear compare panel height", function()
    local COMPARE_ROW_HEIGHT = 14
    local COMPARE_SECTION_GAP = 6
    local COMPARE_PANEL_PAD = 8
    local COMPARE_PANEL_MIN_HEIGHT = 100
    local COMPARE_ITEMS_ROW_HEIGHT = 40
    local COMPARE_OPTIONS_SECTION_HEIGHT = 72

    local function estimateComparePanelHeight(comparison, warningCount)
        if not comparison then return 0 end
        local leftH = COMPARE_ITEMS_ROW_HEIGHT + 8
        warningCount = tonumber(warningCount) or 0
        if warningCount > 0 then
            leftH = leftH + warningCount * COMPARE_ROW_HEIGHT + (warningCount - 1) * 2 + 4
        end
        local sections = comparison.sections or {}
        for s = 1, #sections do
            local section = sections[s]
            leftH = leftH + COMPARE_SECTION_GAP + COMPARE_ROW_HEIGHT
            leftH = leftH + #(section.rows or {}) * COMPARE_ROW_HEIGHT
        end
        local contentH = math.max(leftH, COMPARE_OPTIONS_SECTION_HEIGHT)
        return math.max(COMPARE_PANEL_MIN_HEIGHT, COMPARE_PANEL_PAD * 2 + contentH)
    end

    it("uses the taller of stats column and settings column", function()
        local shortStats = { sections = { { title = "Stats", rows = { { label = "AP" } } } } }
        local tallStats = {
            sections = {
                { title = "Stats", rows = { { label = "a" }, { label = "b" }, { label = "c" }, { label = "d" } } },
                { title = "More", rows = { { label = "e" }, { label = "f" } } },
            },
        }
        local shortHeight = estimateComparePanelHeight(shortStats, false)
        local tallHeight = estimateComparePanelHeight(tallStats, false)
        assert.is_true(shortHeight >= COMPARE_PANEL_MIN_HEIGHT)
        assert.is_true(tallHeight > shortHeight)
    end)

    it("includes compare warnings in left column height", function()
        local comparison = {
            sections = { { title = "Stats", rows = { { label = "a" }, { label = "b" } } } },
        }
        local without = estimateComparePanelHeight(comparison, 0)
        local withOne = estimateComparePanelHeight(comparison, 1)
        local withTwo = estimateComparePanelHeight(comparison, 2)
        assert.are.equal(COMPARE_ROW_HEIGHT + 4, withOne - without)
        assert.are.equal(COMPARE_ROW_HEIGHT + 2, withTwo - withOne)
    end)

    local GRID_SPLIT_FRACTION = 0.6
    local SECTION_GAP = 4

    local function getSettingsColumnLeftX(frameWidth)
        if frameWidth <= 0 then return 0 end
        return frameWidth * GRID_SPLIT_FRACTION + SECTION_GAP
    end

    it("aligns compare settings column with gear settings width", function()
        assert.are.equal(604, getSettingsColumnLeftX(1000))
        assert.are.equal(0, getSettingsColumnLeftX(0))
    end)

    local function shouldHideCompareSettingsSection(layoutMode, gearSettingsOpen)
        return layoutMode == "focus_compare" and gearSettingsOpen
    end

    it("hides compare settings panel when gear settings is open in compare mode", function()
        assert.is_true(shouldHideCompareSettingsSection("focus_compare", true))
        assert.is_false(shouldHideCompareSettingsSection("focus_compare", false))
        assert.is_false(shouldHideCompareSettingsSection("focus", true))
    end)
end)
