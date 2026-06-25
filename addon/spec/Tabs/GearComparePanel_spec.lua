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

    local COMPARE_WARNING_KIND = {
        MISSING_SPEC = "missing_spec",
        UNPICKED_SPEC = "unpicked_spec",
    }

    local function getCompareWarningSeverity(warning)
        if type(warning) == "table"
            and (warning.kind == COMPARE_WARNING_KIND.MISSING_SPEC
                or warning.kind == COMPARE_WARNING_KIND.UNPICKED_SPEC) then
            return "caution"
        end
        local kind = type(warning) == "table" and warning.kind or nil
        if kind == IU_EQUIP_WARNING_KIND.LEVEL or kind == IU_EQUIP_WARNING_KIND.TRAINING then
            return "caution"
        end
        if kind == IU_EQUIP_WARNING_KIND.NEVER then
            return "blocking"
        end
        local text = type(warning) == "table" and warning.text or warning
        if type(text) == "string" then
            if text:find("must gain ", 1, true) or text:find("must train ", 1, true) then
                return "caution"
            end
            if text:find("can never equip this", 1, true) then
                return "blocking"
            end
        end
        return "blocking"
    end

    local function getCompareWarningColor(warning)
        if getCompareWarningSeverity(warning) == "caution" then
            return COMPARE_WARNING_COLOR_CAUTION[1], COMPARE_WARNING_COLOR_CAUTION[2], COMPARE_WARNING_COLOR_CAUTION[3]
        end
        return COMPARE_WARNING_COLOR_BLOCKING[1], COMPARE_WARNING_COLOR_BLOCKING[2], COMPARE_WARNING_COLOR_BLOCKING[3]
    end

    local function isCompareSpecAssumptionWarning(warning)
        return type(warning) == "table"
            and (warning.kind == COMPARE_WARNING_KIND.MISSING_SPEC
                or warning.kind == COMPARE_WARNING_KIND.UNPICKED_SPEC)
    end

    local function sortCompareWarnings(warnings)
        if not warnings or #warnings < 2 then return warnings end
        table.sort(warnings, function(a, b)
            local aSpec = isCompareSpecAssumptionWarning(a)
            local bSpec = isCompareSpecAssumptionWarning(b)
            if aSpec ~= bSpec then
                return not aSpec
            end
            local aBlocking = getCompareWarningSeverity(a) == "blocking"
            local bBlocking = getCompareWarningSeverity(b) == "blocking"
            if aBlocking ~= bBlocking then
                return aBlocking
            end
            local aKind = type(a) == "table" and a.kind or ""
            local bKind = type(b) == "table" and b.kind or ""
            return aKind < bKind
        end)
        return warnings
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
        local rowCount = #(section.rows or {})
        if rowCount > 0 then
            leftH = leftH + rowCount * COMPARE_ROW_HEIGHT
        end
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

    local function formatCompareChooseCharacterHintText()
        return "Choose a character above to compare against"
    end

    local function formatCompareNoUpgradeHintText()
        return "This isn't a clear upgrade for any of your characters."
            .. "\nClick an item above to compare anyway"
    end

    local function formatCompareEmptyHintText(hasUpgradeOrEventual)
        if hasUpgradeOrEventual then
            return formatCompareChooseCharacterHintText()
        end
        return formatCompareNoUpgradeHintText()
    end

    local function formatCompareEmptyStateText(hasUpgradeOrEventual)
        return formatCompareEmptyHintText(hasUpgradeOrEventual)
    end

    local function formatItemCheckDropMessage()
        return "Drop an item to see who can use it as an upgrade"
    end

    it("formats item check drop message", function()
        assert.are.equal(
            "Drop an item to see who can use it as an upgrade",
            formatItemCheckDropMessage())
    end)

    it("formats choose-character hint when upgrades exist", function()
        local text = formatCompareEmptyHintText(true)
        assert.are.equal("Choose a character above to compare against", text)
    end)

    it("formats no-upgrade hint when no upgrades exist", function()
        local text = formatCompareEmptyHintText(false)
        assert.matches("isn't a clear upgrade", text)
        assert.matches("Click an item above", text)
    end)

    it("empty state text matches choose-character hint", function()
        local text = formatCompareEmptyStateText(true)
        assert.are.equal(formatCompareChooseCharacterHintText(), text)
    end)

    it("empty state text matches no-upgrade hint", function()
        local text = formatCompareEmptyStateText(false)
        assert.are.equal(formatCompareNoUpgradeHintText(), text)
    end)

    it("colors compare deltas green, red, and yellow", function()
        local function getCompareDeltaColor(delta)
            delta = tonumber(delta) or 0
            if delta > 0 then return 0.2, 1, 0.2 end
            if delta < 0 then return 1, 0.4, 0.3 end
            return 1, 0.82, 0
        end
        local upR, upG = getCompareDeltaColor(5)
        assert.are.equal(0.2, upR)
        assert.are.equal(1, upG)
        local downR, downG = getCompareDeltaColor(-3)
        assert.are.equal(1, downR)
        assert.are.equal(0.4, downG)
        local flatR, flatG = getCompareDeltaColor(0)
        assert.are.equal(1, flatR)
        assert.are.equal(0.82, flatG)
    end)

    it("computes compare stat scroll content height from row count", function()
        local COMPARE_ROW_HEIGHT = 14
        local function getCompareStatContentHeight(rowCount)
            rowCount = tonumber(rowCount) or 0
            if rowCount <= 0 then return 0 end
            return rowCount * COMPARE_ROW_HEIGHT + (rowCount - 1) * 2
        end
        assert.are.equal(0, getCompareStatContentHeight(0))
        assert.are.equal(14, getCompareStatContentHeight(1))
        assert.are.equal(30, getCompareStatContentHeight(2))
        assert.are.equal(158, getCompareStatContentHeight(10))
    end)

    it("uses matching content inset from the panel split on both sides", function()
        local COMPARE_PANEL_SPLIT_GAP = 8
        local COMPARE_STAT_ROW_INDENT = 8
        local function insetFromCenter(isLeftSide)
            return COMPARE_PANEL_SPLIT_GAP / 2 + COMPARE_STAT_ROW_INDENT
        end
        assert.are.equal(insetFromCenter(true), insetFromCenter(false))
    end)

    it("formats compare stat weight multipliers", function()
        local function formatCompareNumber(n)
            n = tonumber(n) or 0
            if math.floor(n) == n then return tostring(n) end
            return string.format("%.1f", n)
        end
        local function formatCompareWeight(weight)
            if weight == nil then return "" end
            weight = tonumber(weight) or 0
            if weight < 0.005 then return "x0" end
            if weight < 0.05 then
                return "x" .. string.format("%.2f", weight)
            end
            return "x" .. formatCompareNumber(weight)
        end
        local function getCompareWeightColor(weight)
            weight = tonumber(weight) or 0
            if weight < 0.005 then return 0.5, 0.5, 0.5 end
            return 0.82, 0.68, 0.22
        end
        assert.are.equal("", formatCompareWeight(nil))
        assert.are.equal("x0", formatCompareWeight(0))
        assert.are.equal("x0", formatCompareWeight(0.004))
        assert.are.equal("x0.01", formatCompareWeight(0.01))
        assert.are.equal("x0.04", formatCompareWeight(0.037))
        assert.are.equal("x0.8", formatCompareWeight(0.8))
        assert.are.equal("x1", formatCompareWeight(1))
        local wr, wg, wb = getCompareWeightColor(0.8)
        assert.are.equal(0.82, wr)
        assert.are.equal(0.68, wg)
        assert.are.equal(0.22, wb)
        local zr = getCompareWeightColor(0)
        assert.are.equal(0.5, zr)
        local tinyR = getCompareWeightColor(0.002)
        assert.are.equal(0.5, tinyR)
        local smallR = getCompareWeightColor(0.01)
        assert.are.equal(0.82, smallR)
    end)

    it("formats weighted change as delta with percent in parentheses", function()
        local function formatCompareNumber(n)
            n = tonumber(n) or 0
            if math.floor(n) == n then return tostring(n) end
            return string.format("%.1f", n)
        end
        local function formatCompareDelta(n)
            local s = formatCompareNumber(n)
            if n > 0 then return "+" .. s end
            return s
        end
        local function formatComparePercentInParens(percent)
            percent = tonumber(percent) or 0
            if percent < 0 then
                return "(" .. formatCompareDelta(percent) .. "%)"
            end
            return "(" .. formatCompareNumber(percent) .. "%)"
        end
        local function formatCompareWeightedChange(delta, percent)
            return formatCompareDelta(delta) .. " " .. formatComparePercentInParens(percent)
        end
        assert.are.equal("+1.4 (8.1%)", formatCompareWeightedChange(1.4, 8.1))
        assert.are.equal("-1.4 (-8.1%)", formatCompareWeightedChange(-1.4, -8.1))
        assert.are.equal("0 (0%)", formatCompareWeightedChange(0, 0))
    end)

    it("uses gold label and delta color for weighted summary row", function()
        local function getCompareWeightColor(weight)
            weight = tonumber(weight) or 0
            if weight <= 0 then return 0.5, 0.5, 0.5 end
            return 0.82, 0.68, 0.22
        end
        local function getCompareDeltaColor(delta)
            delta = tonumber(delta) or 0
            if delta > 0 then return 0.2, 1, 0.2 end
            if delta < 0 then return 1, 0.4, 0.3 end
            return 1, 0.82, 0
        end
        local function nameColorForRow(data)
            if data.formatAsWeightedChange then
                return getCompareWeightColor(1)
            end
            return 1, 1, 1
        end
        local function deltaColorForRow(data)
            return getCompareDeltaColor(data.delta)
        end
        local nr, ng, nb = nameColorForRow({ formatAsWeightedChange = true })
        assert.are.equal(0.82, nr)
        assert.are.equal(0.68, ng)
        assert.are.equal(0.22, nb)
        local dr, dg, db = deltaColorForRow({ formatAsWeightedChange = true, delta = 5 })
        assert.are.equal(0.2, dr)
        assert.are.equal(1, dg)
        local downR = deltaColorForRow({ formatAsWeightedChange = true, delta = -3 })
        assert.are.equal(1, downR)
    end)

    it("uses fixed column widths for weighted summary row", function()
        local COMPARE_STAT_ROW_INDENT = 8
        local COMPARE_STAT_COL_NAME = 110
        local COMPARE_STAT_COL_DELTA = 52
        local COMPARE_STAT_COL_WEIGHT = 40
        local COMPARE_STAT_COL_WEIGHTED_NAME = 60
        local COMPARE_STAT_COL_WEIGHTED_DELTA = 102
        local function layoutCompareStatRowColumns(data)
            local indent = COMPARE_STAT_ROW_INDENT
            if data.formatAsWeightedChange then
                return {
                    nameLeft = indent,
                    nameWidth = COMPARE_STAT_COL_WEIGHTED_NAME,
                    deltaLeft = indent + COMPARE_STAT_COL_WEIGHTED_NAME,
                    deltaWidth = COMPARE_STAT_COL_WEIGHTED_DELTA,
                    weightWidth = 0,
                }
            end
            local left = indent
            return {
                nameLeft = left,
                nameWidth = COMPARE_STAT_COL_NAME,
                deltaLeft = left + COMPARE_STAT_COL_NAME,
                deltaWidth = COMPARE_STAT_COL_DELTA,
                weightWidth = COMPARE_STAT_COL_WEIGHT,
            }
        end
        local weighted = layoutCompareStatRowColumns({ formatAsWeightedChange = true })
        local normal = layoutCompareStatRowColumns({})
        assert.are.equal(60, weighted.nameWidth)
        assert.are.equal(102, weighted.deltaWidth)
        assert.are.equal(68, weighted.deltaLeft)
        assert.are.equal(110, normal.nameWidth)
        assert.are.equal(52, normal.deltaWidth)
    end)

    it("uses yellow for level and training warnings, red for never-equip", function()
        local levelR, levelG = getCompareWarningColor({
            text = "Alt must gain 5 levels to equip this",
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

    it("sorts blocking warnings before caution warnings", function()
        local warnings = {
            { text = "Alt must gain 5 levels to equip this", kind = IU_EQUIP_WARNING_KIND.LEVEL },
            { text = "This item is soulbound", kind = IU_EQUIP_WARNING_KIND.SOULBOUND },
            { text = "Alt must train Plate Armor to equip this", kind = IU_EQUIP_WARNING_KIND.TRAINING },
            { text = "Alt can never equip this (Plate Armor)", kind = IU_EQUIP_WARNING_KIND.NEVER },
        }
        sortCompareWarnings(warnings)
        for i = 1, 2 do
            assert.are.equal("blocking", getCompareWarningSeverity(warnings[i]))
        end
        for i = 3, 4 do
            assert.are.equal("caution", getCompareWarningSeverity(warnings[i]))
        end
    end)

    it("sorts spec assumption warnings to the bottom", function()
        local warnings = {
            { kind = COMPARE_WARNING_KIND.MISSING_SPEC, text = "spec missing" },
            { kind = IU_EQUIP_WARNING_KIND.LEVEL, text = "Alt must gain 5 levels to equip this" },
            { kind = COMPARE_WARNING_KIND.UNPICKED_SPEC, text = "spec unpicked" },
            { kind = IU_EQUIP_WARNING_KIND.NEVER, text = "Alt can never equip this (Plate Armor)" },
        }
        sortCompareWarnings(warnings)
        assert.are.equal(IU_EQUIP_WARNING_KIND.NEVER, warnings[1].kind)
        assert.are.equal(IU_EQUIP_WARNING_KIND.LEVEL, warnings[2].kind)
        assert.are.equal(COMPARE_WARNING_KIND.MISSING_SPEC, warnings[3].kind)
        assert.are.equal(COMPARE_WARNING_KIND.UNPICKED_SPEC, warnings[4].kind)
    end)
end)
