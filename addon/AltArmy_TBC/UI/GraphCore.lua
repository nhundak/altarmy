-- AltArmy TBC — Shared graph rendering primitives (axes, grid, anti-aliased lines).

if not AltArmy then return end

AltArmy.GraphCore = AltArmy.GraphCore or {}

local Core = AltArmy.GraphCore

Core.PADDING = { left = 48, right = 12, bottom = 28, top = 14 }
Core.AXIS_COLOR = { r = 0.40, g = 0.36, b = 0.28, a = 0.70 }
Core.GRID_COLOR = { r = 0.25, g = 0.23, b = 0.20, a = 0.25 }
Core.Y_TICKS = 4
Core.X_TICKS = 5
Core.Y_TICK_LENGTH = 5
Core.Y_LABEL_INSET = 3

local Theme = AltArmy.Theme
local TC = Theme and Theme.COLORS

Core.COLORS = {
    headerText = TC and TC.value or { 0.92, 0.92, 0.92 },
    labelText = TC and TC.label or { 0.69, 0.69, 0.69 },
    valueText = TC and TC.value or { 0.92, 0.92, 0.92 },
    border = TC and TC.tooltipBorder or { 0.70, 0.58, 0.28 },
    bgTop = TC and TC.tooltipBg or { 0.12, 0.12, 0.14 },
}

Core.graphTextures = {}
Core.graphLabels = {}
Core.graphLines = {}

local SOFT_LINE_TEX = "Interface\\AddOns\\AltArmy_TBC\\Textures\\SoftLine"
local _useNativeLine = nil

local linePool = { free = {} }
local texturePool = { free = {} }
local fontStringPool = { free = {} }

local function AcquireFromPool(pool, createFn)
    local obj = table.remove(pool.free)
    if not obj then
        obj = createFn()
    end
    obj:Show()
    return obj
end

local function ReleaseToPool(pool, obj)
    if not obj then return end
    obj:Hide()
    table.insert(pool.free, obj)
end

local function RemoveFromActiveList(activeList, obj)
    for i = #activeList, 1, -1 do
        if activeList[i] == obj then
            table.remove(activeList, i)
            return true
        end
    end
    return false
end

function Core.ReleaseDrawnObject(obj)
    if not obj then return end
    if RemoveFromActiveList(Core.graphLines, obj) then
        ReleaseToPool(linePool, obj)
        return
    end
    if RemoveFromActiveList(Core.graphTextures, obj) then
        ReleaseToPool(texturePool, obj)
        return
    end
    if RemoveFromActiveList(Core.graphLabels, obj) then
        ReleaseToPool(fontStringPool, obj)
    end
end

local function AcquireFontString(parent)
    local fs = AcquireFromPool(fontStringPool, function()
        return parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    end)
    table.insert(Core.graphLabels, fs)
    return fs
end

local function DetectNativeLine(parent)
    if _useNativeLine ~= nil then return end
    local ok, testLine = pcall(function() return parent:CreateLine(nil, "ARTWORK") end)
    _useNativeLine = ok and testLine and testLine.SetStartPoint and testLine.SetEndPoint and true or false
    if _useNativeLine and testLine then
        testLine:Hide()
        table.insert(linePool.free, testLine)
    end
end

local function PointAlongPolyline(points, distance)
    if #points < 2 then
        local p = points[1]
        return p and p.x or 0, p and p.y or 0
    end

    local travelled = 0
    for i = 2, #points do
        local prev = points[i - 1]
        local curr = points[i]
        local dx = curr.x - prev.x
        local dy = curr.y - prev.y
        local segLen = math.sqrt(dx * dx + dy * dy)
        if segLen > 0.0001 then
            if travelled + segLen >= distance then
                local frac = (distance - travelled) / segLen
                return prev.x + dx * frac, prev.y + dy * frac
            end
            travelled = travelled + segLen
        end
    end

    local last = points[#points]
    return last.x, last.y
end

function Core.CreateDashedPolyline(parent, points, thickness, r, g, b, a, dashWidth, gapWidth)
    dashWidth = dashWidth or 6
    gapWidth = gapWidth or 4
    thickness = thickness or 1

    if not points or #points < 2 then
        return
    end

    local totalLength = 0
    for i = 2, #points do
        local dx = points[i].x - points[i - 1].x
        local dy = points[i].y - points[i - 1].y
        totalLength = totalLength + math.sqrt(dx * dx + dy * dy)
    end
    if totalLength <= 0.0001 then
        return
    end

    local pos = 0
    while pos < totalLength do
        local dashEnd = math.min(pos + dashWidth, totalLength)
        local sx, sy = PointAlongPolyline(points, pos)
        local ex, ey = PointAlongPolyline(points, dashEnd)
        Core.CreateLine(parent, sx, sy, ex, ey, thickness, r, g, b, a)
        pos = dashEnd + gapWidth
    end
end

function Core.CreateDashedLine(parent, x1, y1, x2, y2, thickness, r, g, b, a, dashWidth, gapWidth)
    dashWidth = dashWidth or 6
    gapWidth = gapWidth or 4
    thickness = thickness or 1

    local dx, dy = x2 - x1, y2 - y1
    local length = math.sqrt(dx * dx + dy * dy)
    if length <= 0.0001 then return end

    local ux, uy = dx / length, dy / length
    local pos = 0
    while pos < length do
        local dashEnd = math.min(pos + dashWidth, length)
        local sx = x1 + ux * pos
        local sy = y1 + uy * pos
        local ex = x1 + ux * dashEnd
        local ey = y1 + uy * dashEnd
        Core.CreateLine(parent, sx, sy, ex, ey, thickness, r, g, b, a)
        pos = dashEnd + gapWidth
    end
end

function Core.CreateLine(parent, x1, y1, x2, y2, thickness, r, g, b, a)
    local dx, dy = x2 - x1, y2 - y1
    local length = math.sqrt(dx * dx + dy * dy)
    if length <= 0.0001 then return end

    r = r or 0.6
    g = g or 0.6
    b = b or 0.6
    a = a or 0.95
    thickness = thickness or 2

    DetectNativeLine(parent)

    if _useNativeLine then
        local line = AcquireFromPool(linePool, function()
            return parent:CreateLine(nil, "ARTWORK")
        end)
        line:ClearAllPoints()
        line:SetThickness(thickness + 1)
        line:SetTexture(SOFT_LINE_TEX)
        line:SetVertexColor(r, g, b, a)
        line:SetStartPoint("BOTTOMLEFT", parent, x1, y1)
        line:SetEndPoint("BOTTOMLEFT", parent, x2, y2)
        table.insert(Core.graphLines, line)
        return line
    end

    local angle = math.atan2(dy, dx)
    local midx, midy = (x1 + x2) / 2, (y1 + y2) / 2
    local tex = AcquireFromPool(texturePool, function()
        return parent:CreateTexture(nil, "ARTWORK")
    end)
    tex:ClearAllPoints()
    tex:SetTexture(SOFT_LINE_TEX)
    tex:SetVertexColor(r, g, b, a)
    tex:SetSize(length, thickness + 1)
    tex:SetPoint("CENTER", parent, "BOTTOMLEFT", midx, midy)
    tex:SetRotation(angle)
    table.insert(Core.graphTextures, tex)
    return tex
end

function Core.ClearObjects()
    for i = #Core.graphLines, 1, -1 do
        ReleaseToPool(linePool, Core.graphLines[i])
    end
    wipe(Core.graphLines)

    for i = #Core.graphTextures, 1, -1 do
        ReleaseToPool(texturePool, Core.graphTextures[i])
    end
    wipe(Core.graphTextures)

    for i = #Core.graphLabels, 1, -1 do
        ReleaseToPool(fontStringPool, Core.graphLabels[i])
    end
    wipe(Core.graphLabels)
end

function Core.CalculatePlotDimensions(graphFrame)
    local pad = Core.PADDING
    local w, h = graphFrame:GetWidth(), graphFrame:GetHeight()
    local plotW = math.max(1, w - pad.left - pad.right)
    local plotH = math.max(1, h - pad.bottom - pad.top)
    return plotW, plotH
end

function Core.CreateTransformers(plotW, plotH, xMin, xRange, yMin, yRange, opts)
    local pad = Core.PADDING
    opts = opts or {}
    local yAxisMode = opts.yAxisMode or "linear"
    local logMin = opts.logMin
    local logMax = opts.logMax

    local function X(x)
        return pad.left + plotW * ((x - xMin) / xRange)
    end

    local function Y(y)
        if yAxisMode == "log" then
            local clamped = math.max(y, yMin)
            local logY = math.log(clamped) / math.log(10)
            local logRange = logMax - logMin
            if logRange <= 0 then
                return pad.bottom
            end
            return pad.bottom + plotH * ((logY - logMin) / logRange)
        end
        return pad.bottom + plotH * ((y - yMin) / yRange)
    end

    return X, Y
end

function Core.RenderGridLines(parent, plotW, plotH, opts)
    local pad = Core.PADDING
    local grid = Core.GRID_COLOR
    opts = opts or {}

    if opts.logYTicks and opts.logMin and opts.logMax then
        local logRange = opts.logMax - opts.logMin
        for _, val in ipairs(opts.logYTicks) do
            if logRange > 0 then
                local logY = math.log(val) / math.log(10)
                local frac = (logY - opts.logMin) / logRange
                local y = pad.bottom + frac * plotH
                Core.CreateLine(parent, pad.left, y, pad.left + plotW, y, 1,
                    grid.r, grid.g, grid.b, grid.a)
            end
        end
    elseif opts.linearYTicks and opts.yMin and opts.yRange and opts.yRange > 0 then
        for _, val in ipairs(opts.linearYTicks) do
            if val > opts.yMin + 0.001 then
                local frac = (val - opts.yMin) / opts.yRange
                local y = pad.bottom + frac * plotH
                Core.CreateLine(parent, pad.left, y, pad.left + plotW, y, 1,
                    grid.r, grid.g, grid.b, grid.a)
            end
        end
    else
        for i = 1, Core.Y_TICKS - 1 do
            local frac = i / Core.Y_TICKS
            local y = pad.bottom + frac * plotH
            Core.CreateLine(parent, pad.left, y, pad.left + plotW, y, 1,
                grid.r, grid.g, grid.b, grid.a)
        end
    end

    if opts.xInterval and opts.xMin and opts.xRange then
        local xMax = opts.xMin + opts.xRange
        local interval = opts.xInterval
        local level = math.floor(opts.xMin / interval) * interval
        while level <= xMax + 0.001 do
            if level >= opts.xMin - 0.001 then
                local x = pad.left + plotW * ((level - opts.xMin) / opts.xRange)
                Core.CreateLine(parent, x, pad.bottom, x, pad.bottom + plotH, 1,
                    grid.r, grid.g, grid.b, grid.a)
            end
            level = level + interval
        end
    else
        for i = 1, Core.X_TICKS - 1 do
            local frac = i / Core.X_TICKS
            local x = pad.left + frac * plotW
            Core.CreateLine(parent, x, pad.bottom, x, pad.bottom + plotH, 1,
                grid.r, grid.g, grid.b, grid.a)
        end
    end
end

Core.Y_AXIS_BREAK_HEIGHT = 10
Core.Y_AXIS_BREAK_AMPLITUDE = 3

local function RenderYAxisWithBreak(parent, x, yBottom, yTop, thickness, ax, breakHeight, amplitude)
    breakHeight = breakHeight or Core.Y_AXIS_BREAK_HEIGHT
    amplitude = amplitude or Core.Y_AXIS_BREAK_AMPLITUDE
    local yBreakTop = yBottom + breakHeight
    if yTop <= yBreakTop + 0.001 then
        Core.CreateLine(parent, x, yBottom, x, yTop, thickness, ax.r, ax.g, ax.b, ax.a)
        return
    end

    Core.CreateLine(parent, x, yBreakTop, x, yTop, thickness, ax.r, ax.g, ax.b, ax.a)

    local step = breakHeight / 4
    local y = yBreakTop
    local points = {
        { x = x, y = y },
        { x = x + amplitude, y = y - step },
        { x = x - amplitude, y = y - step * 2 },
        { x = x + amplitude, y = y - step * 3 },
        { x = x, y = yBottom },
    }
    for i = 1, #points - 1 do
        local fromPt = points[i]
        local toPt = points[i + 1]
        Core.CreateLine(parent, fromPt.x, fromPt.y, toPt.x, toPt.y, thickness,
            ax.r, ax.g, ax.b, ax.a)
    end
end

function Core.RenderAxes(parent, plotW, plotH, opts)
    local pad = Core.PADDING
    local ax = Core.AXIS_COLOR
    opts = opts or {}

    Core.CreateLine(parent, pad.left, pad.bottom, pad.left + plotW + 1, pad.bottom, 2,
        ax.r, ax.g, ax.b, ax.a)

    local yTop = pad.bottom + plotH
    if opts.yAxisBreak then
        RenderYAxisWithBreak(parent, pad.left, pad.bottom, yTop, 2, ax,
            opts.yAxisBreakHeight, opts.yAxisBreakAmplitude)
    else
        Core.CreateLine(parent, pad.left, pad.bottom, pad.left, yTop, 2,
            ax.r, ax.g, ax.b, ax.a)
    end
end

function Core.RenderYLabels(parent, plotH, yMin, yRange, formatFunc, opts)
    local pad = Core.PADDING
    local ax = Core.AXIS_COLOR
    local tickLen = Core.Y_TICK_LENGTH
    local labelX = pad.left - Core.Y_LABEL_INSET
    formatFunc = formatFunc or function(v) return tostring(math.floor(v + 0.5)) end
    opts = opts or {}

    if opts.logYTicks and opts.logMin and opts.logMax then
        local logRange = opts.logMax - opts.logMin
        for _, val in ipairs(opts.logYTicks) do
            if logRange > 0 then
                local logY = math.log(val) / math.log(10)
                local frac = (logY - opts.logMin) / logRange
                local y = pad.bottom + frac * plotH
                local atBottomEdge = math.abs(y - pad.bottom) < 0.5

                if not atBottomEdge then
                    Core.CreateLine(parent, pad.left, y, pad.left + tickLen, y, 2, ax.r, ax.g, ax.b, ax.a)
                end

                local fs = AcquireFontString(parent)
                fs:ClearAllPoints()
                fs:SetJustifyV("MIDDLE")
                fs:SetText(formatFunc(val))
                fs:SetPoint("RIGHT", parent, "BOTTOMLEFT", labelX, y)
            end
        end
        return
    end

    if opts.linearYTicks and opts.yMin and opts.yRange and opts.yRange > 0 then
        for _, val in ipairs(opts.linearYTicks) do
            local frac = (val - opts.yMin) / opts.yRange
            local y = pad.bottom + frac * plotH
            local atBottomEdge = math.abs(y - pad.bottom) < 0.5

            if not atBottomEdge then
                Core.CreateLine(parent, pad.left, y, pad.left + tickLen, y, 2, ax.r, ax.g, ax.b, ax.a)
            end

            local fs = AcquireFontString(parent)
            fs:ClearAllPoints()
            fs:SetJustifyV("MIDDLE")
            fs:SetText(formatFunc(val))
            fs:SetPoint("RIGHT", parent, "BOTTOMLEFT", labelX, y)
        end
        return
    end

    for i = 0, Core.Y_TICKS do
        local frac = i / Core.Y_TICKS
        local val = yMin + frac * yRange
        local y = pad.bottom + frac * plotH

        if frac > 0.0001 then
            Core.CreateLine(parent, pad.left, y, pad.left + tickLen, y, 2, ax.r, ax.g, ax.b, ax.a)
        end

        local fs = AcquireFontString(parent)
        fs:ClearAllPoints()
        fs:SetJustifyV("MIDDLE")
        fs:SetText(formatFunc(val))
        fs:SetPoint("RIGHT", parent, "BOTTOMLEFT", labelX, y)
    end
end

function Core.RenderXLabels(parent, plotW, xMin, xRange, formatFunc)
    local pad = Core.PADDING
    local ax = Core.AXIS_COLOR
    formatFunc = formatFunc or function(v) return tostring(math.floor(v + 0.5)) end

    for i = 0, Core.X_TICKS do
        local frac = i / Core.X_TICKS
        local val = xMin + frac * xRange
        local x = pad.left + frac * plotW

        if frac > 0.0001 then
            Core.CreateLine(parent, x, pad.bottom, x, pad.bottom + 5, 2, ax.r, ax.g, ax.b, ax.a)
        end

        local fs = AcquireFontString(parent)
        fs:ClearAllPoints()
        fs:SetText(formatFunc(val))
        fs:SetPoint("TOP", parent, "BOTTOMLEFT", x, pad.bottom - 2)
    end
end

function Core.RenderXLabelsAtInterval(parent, plotW, xMin, xRange, interval, formatFunc)
    local pad = Core.PADDING
    local ax = Core.AXIS_COLOR
    local xMax = xMin + xRange
    interval = interval or 10
    formatFunc = formatFunc or function(v) return tostring(math.floor(v + 0.5)) end

    local level = math.floor(xMin / interval) * interval
    while level <= xMax + 0.001 do
        if level >= xMin - 0.001 then
            local x = pad.left + plotW * ((level - xMin) / xRange)
            local atLeftEdge = math.abs(level - xMin) < 0.001

            if not atLeftEdge then
                Core.CreateLine(parent, x, pad.bottom, x, pad.bottom + 5, 2, ax.r, ax.g, ax.b, ax.a)
            end

            local fs = AcquireFontString(parent)
            fs:ClearAllPoints()
            fs:SetText(formatFunc(level))
            fs:SetPoint("TOP", parent, "BOTTOMLEFT", x, pad.bottom - 2)
        end

        level = level + interval
    end
end

function Core.CreateTooltipBase(_parent, width, height)
    local colors = Core.COLORS

    local tooltip = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    tooltip:SetFrameStrata("TOOLTIP")
    tooltip:SetFrameLevel(200)
    tooltip:SetSize(width, height)
    if Theme and Theme.ApplyBackdrop then
        Theme.ApplyBackdrop(tooltip, "tooltip")
    else
        tooltip:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        tooltip:SetBackdropColor(colors.bgTop[1], colors.bgTop[2], colors.bgTop[3], 0.97)
        tooltip:SetBackdropBorderColor(colors.border[1], colors.border[2], colors.border[3], 0.9)
    end

    local shadow = CreateFrame("Frame", nil, tooltip, "BackdropTemplate")
    shadow:SetPoint("TOPLEFT", -4, 4)
    shadow:SetPoint("BOTTOMRIGHT", 4, -4)
    shadow:SetFrameLevel(tooltip:GetFrameLevel() - 1)
    shadow:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        tile = true,
        tileSize = 16,
        edgeSize = 4,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    shadow:SetBackdropColor(0, 0, 0, 0.5)
    shadow:SetBackdropBorderColor(0, 0, 0, 0.4)
    tooltip.shadow = shadow

    tooltip:Hide()
    return tooltip
end

--- Format seconds as a compact axis duration label (e.g. "1h 30m", "45m").
function Core.FormatDurationAxis(seconds)
    seconds = seconds or 0
    if seconds <= 0 then
        return "0s"
    end
    if seconds < 60 then
        return string.format("%ds", math.floor(seconds + 0.5))
    end

    local totalMinutes = math.floor(seconds / 60 + 0.5)
    if totalMinutes < 60 then
        return string.format("%dm", totalMinutes)
    end

    if seconds >= 86400 then
        local days = math.floor(seconds / 86400 + 0.5)
        local hours = math.floor((seconds % 86400) / 3600 + 0.5)
        if hours >= 24 then
            days = days + 1
            hours = 0
        end
        if hours == 0 then
            return string.format("%dd", days)
        end
        return string.format("%dd %dh", days, hours)
    end

    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60 + 0.5)
    if minutes >= 60 then
        hours = hours + 1
        minutes = 0
    end
    if minutes == 0 then
        return string.format("%dh", hours)
    end
    return string.format("%dh %dm", hours, minutes)
end

--- Format seconds as a compact duration label (e.g. "2h", "45m").
function Core.FormatDuration(seconds)
    seconds = seconds or 0
    if seconds < 60 then
        return string.format("%ds", math.floor(seconds + 0.5))
    elseif seconds < 3600 then
        return string.format("%dm", math.floor(seconds / 60 + 0.5))
    elseif seconds < 86400 then
        return string.format("%dh", math.floor(seconds / 3600 + 0.5))
    end
    local d = math.floor(seconds / 86400)
    local h = math.floor((seconds % 86400) / 3600)
    if h > 0 then
        return string.format("%dd %dh", d, h)
    end
    return string.format("%dd", d)
end
