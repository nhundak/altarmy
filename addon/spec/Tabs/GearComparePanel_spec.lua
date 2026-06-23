--[[
  Unit tests for Gear tab compare panel height (two-column layout).
  Mirrors EstimateComparePanelHeight from TabGear.lua.
]]

describe("Gear compare panel height", function()
    local IU_EQUIP_WARNING_KIND = {
        SOULBOUND = "soulbound",
        NEVER = "never",
        LEVEL = "level",
        TRAINING = "training",
    }
    local COMPARE_WARNING_COLOR_BLOCKING = { 1, 0.4, 0.3 }
    local COMPARE_WARNING_COLOR_CAUTION = { 1, 0.82, 0 }

    local function getCompareWarningColor(warning)
        local kind = type(warning) == "table" and warning.kind or nil
        if kind == IU_EQUIP_WARNING_KIND.LEVEL or kind == IU_EQUIP_WARNING_KIND.TRAINING then
            return COMPARE_WARNING_COLOR_CAUTION[1], COMPARE_WARNING_COLOR_CAUTION[2], COMPARE_WARNING_COLOR_CAUTION[3]
        end
        if kind == IU_EQUIP_WARNING_KIND.NEVER then
            return COMPARE_WARNING_COLOR_BLOCKING[1], COMPARE_WARNING_COLOR_BLOCKING[2], COMPARE_WARNING_COLOR_BLOCKING[3]
        end
        local text = type(warning) == "table" and warning.text or warning
        if type(text) == "string" then
            if text:find("must gain ", 1, true) or text:find("must train ", 1, true) then
                return COMPARE_WARNING_COLOR_CAUTION[1], COMPARE_WARNING_COLOR_CAUTION[2], COMPARE_WARNING_COLOR_CAUTION[3]
            end
            if text:find("can never equip this", 1, true) then
                return COMPARE_WARNING_COLOR_BLOCKING[1], COMPARE_WARNING_COLOR_BLOCKING[2], COMPARE_WARNING_COLOR_BLOCKING[3]
            end
        end
        return COMPARE_WARNING_COLOR_BLOCKING[1], COMPARE_WARNING_COLOR_BLOCKING[2], COMPARE_WARNING_COLOR_BLOCKING[3]
    end

    local COMPARE_ROW_HEIGHT = 14
    local COMPARE_SECTION_GAP = 6
    local COMPARE_PANEL_PAD = 8
    local COMPARE_PANEL_MIN_HEIGHT = 100
    local COMPARE_ITEMS_ROW_HEIGHT = 52
    local COMPARE_OPTIONS_SECTION_HEIGHT = 72

    local function estimateComparePanelHeight(comparison, warningCount, hasVerdict)
        if not comparison then return 0 end
        local leftH = COMPARE_ITEMS_ROW_HEIGHT + 8
        warningCount = tonumber(warningCount) or 0
        if warningCount > 0 then
            leftH = leftH + warningCount * COMPARE_ROW_HEIGHT + (warningCount - 1) * 2 + 4
        end
        if hasVerdict then
            leftH = leftH + COMPARE_ROW_HEIGHT + 4
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
        local without = estimateComparePanelHeight(comparison, 0, false)
        local withOne = estimateComparePanelHeight(comparison, 1, false)
        local withTwo = estimateComparePanelHeight(comparison, 2, false)
        assert.are.equal(COMPARE_ROW_HEIGHT + 4, withOne - without)
        assert.are.equal(COMPARE_ROW_HEIGHT + 2, withTwo - withOne)
    end)

    it("includes verdict row in left column height", function()
        local comparison = {
            sections = { { title = "Stats", rows = { { label = "a" } } } },
        }
        local without = estimateComparePanelHeight(comparison, 0, false)
        local withVerdict = estimateComparePanelHeight(comparison, 0, true)
        assert.are.equal(COMPARE_ROW_HEIGHT + 4, withVerdict - without)
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
        assert.is_false(shouldHideCompareSettingsSection("normal", true))
    end)

    local function formatCompareFocusTitle()
        return "Upgrade check for"
    end

    local function formatCompareEmptyHintText()
        return "This isn't a clear upgrade for any of your characters."
            .. "\nClick an item above to compare anyway"
    end

    local function formatCompareEmptyStateText()
        return formatCompareFocusTitle() .. "\n" .. formatCompareEmptyHintText()
    end

    it("formats compare focus title", function()
        assert.are.equal("Upgrade check for", formatCompareFocusTitle())
    end)

    it("formats compare empty hint message", function()
        local text = formatCompareEmptyHintText()
        assert.matches("isn't a clear upgrade", text)
        assert.matches("Click an item above", text)
    end)

    it("combines focus title and empty hint for legacy formatter", function()
        local text = formatCompareEmptyStateText()
        assert.matches("Upgrade check for", text)
        assert.matches("isn't a clear upgrade", text)
    end)

    it("uses yellow for level and training warnings, red for never-equip", function()
        local levelR, levelG = getCompareWarningColor({
            text = "Alt must gain 5 levels to equip this (requires level 40)",
            kind = IU_EQUIP_WARNING_KIND.LEVEL,
        })
        assert.are.equal(1, levelR)
        assert.are.equal(0.82, levelG)

        local trainR, trainG = getCompareWarningColor({
            text = "Alt must train Plate Armor to equip this",
            kind = IU_EQUIP_WARNING_KIND.TRAINING,
        })
        assert.are.equal(1, trainR)
        assert.are.equal(0.82, trainG)

        local neverR, neverG = getCompareWarningColor({
            text = "Alt can never equip this (Plate Armor)",
            kind = IU_EQUIP_WARNING_KIND.NEVER,
        })
        assert.are.equal(1, neverR)
        assert.are.equal(0.4, neverG)
    end)
end)
