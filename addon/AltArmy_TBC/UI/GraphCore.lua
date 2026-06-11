-- AltArmy TBC — Shared graph rendering primitives (axes, grid, anti-aliased lines).

if not AltArmy then return end

AltArmy.GraphCore = AltArmy.GraphCore or {}

local Core = AltArmy.GraphCore

Core.PADDING = { left = 48, right = 12, bottom = 28, top = 14 }
Core.AXIS_COLOR = { r = 0.40, g = 0.36, b = 0.28, a = 0.70 }
Core.GRID_COLOR = { r = 0.25, g = 0.23, b = 0.20, a = 0.25 }
Core.Y_TICKS = 4
Core.X_TICKS = 5

Core.COLORS = {
    headerText = { 0.92, 0.92, 0.92 },
    labelText = { 0.69, 0.69, 0.69 },
    valueText = { 0.92, 0.92, 0.92 },
    border = { 0.70, 0.58, 0.28 },
    bgTop = { 0.12, 0.12, 0.14 },
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

function Core.CreateTransformers(plotW, plotH, xMin, xRange, yMin, yRange)
    local pad = Core.PADDING

    local function X(x)
        return pad.left + plotW * ((x - xMin) / xRange)
    end

    local function Y(y)
        return pad.bottom + plotH * ((y - yMin) / yRange)
    end

    return X, Y
end

function Core.RenderGridLines(parent, plotW, plotH)
    local pad = Core.PADDING
    local grid = Core.GRID_COLOR

    for i = 1, Core.Y_TICKS - 1 do
        local frac = i / Core.Y_TICKS
        local y = pad.bottom + frac * plotH
        Core.CreateLine(parent, pad.left, y, pad.left + plotW, y, 1,
            grid.r, grid.g, grid.b, grid.a)
    end

    for i = 1, Core.X_TICKS - 1 do
        local frac = i / Core.X_TICKS
        local x = pad.left + frac * plotW
        Core.CreateLine(parent, x, pad.bottom, x, pad.bottom + plotH, 1,
            grid.r, grid.g, grid.b, grid.a)
    end
end

function Core.RenderAxes(parent, plotW, plotH)
    local pad = Core.PADDING
    local ax = Core.AXIS_COLOR

    Core.CreateLine(parent, pad.left, pad.bottom, pad.left + plotW, pad.bottom, 2,
        ax.r, ax.g, ax.b, ax.a)
    Core.CreateLine(parent, pad.left, pad.bottom, pad.left, pad.bottom + plotH, 2,
        ax.r, ax.g, ax.b, ax.a)
end

function Core.RenderYLabels(parent, plotH, yMin, yRange, formatFunc)
    local pad = Core.PADDING
    local ax = Core.AXIS_COLOR
    formatFunc = formatFunc or function(v) return tostring(math.floor(v + 0.5)) end

    for i = 0, Core.Y_TICKS do
        local frac = i / Core.Y_TICKS
        local val = yMin + frac * yRange
        local y = pad.bottom + frac * plotH

        Core.CreateLine(parent, pad.left - 5, y, pad.left, y, 2, ax.r, ax.g, ax.b, ax.a)

        local fs = AcquireFontString(parent)
        fs:ClearAllPoints()
        fs:SetText(formatFunc(val))
        fs:SetPoint("RIGHT", parent, "BOTTOMLEFT", pad.left - 8, y - 5)
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

        Core.CreateLine(parent, x, pad.bottom, x, pad.bottom + 5, 2, ax.r, ax.g, ax.b, ax.a)

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
        local x = pad.left + plotW * ((level - xMin) / xRange)

        Core.CreateLine(parent, x, pad.bottom, x, pad.bottom + 5, 2, ax.r, ax.g, ax.b, ax.a)

        local fs = AcquireFontString(parent)
        fs:ClearAllPoints()
        fs:SetText(formatFunc(level))
        fs:SetPoint("TOP", parent, "BOTTOMLEFT", x, pad.bottom - 2)

        level = level + interval
    end
end

function Core.CreateTooltipBase(_parent, width, height)
    local colors = Core.COLORS

    local tooltip = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    tooltip:SetFrameStrata("TOOLTIP")
    tooltip:SetFrameLevel(200)
    tooltip:SetSize(width, height)
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
