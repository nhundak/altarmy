# Rendering High-Quality Graphs in a WoW Addon

A reference distilled from the **AHPriceGraph** addon, documenting the code and
techniques it uses to draw smooth, interactive, good-looking graphs purely with
the WoW UI/widget API (no external libraries). This is intended as a guide for
adding a new **character level progress over time** graph to AltArmy_TBC.

The original code is organized as one shared core module plus several
graph-type modules:

| File | Responsibility |
| --- | --- |
| `GraphCore.lua` | Shared constants, object pools, primitives (lines/labels), axes, grid, time stripes, coordinate transforms, data reduction, tooltip base. |
| `Graph.lua` | Line graph (price over time) with per-segment gradient coloring + hover points. |
| `CandlestickGraph.lua` | OHLC candlesticks aggregated into time buckets. |
| `GraphTrend.lua` | Aggregated/normalized index line across many items. |
| `WeeklyGraph.lua` | Multiple overlaid week-lines with an interactive legend. |

Everything below is framed around what you actually need to reproduce a
high-quality result.

---

## 1. The drawing surface

There is no canvas/bitmap in the WoW API. A "graph" is just a `Frame` onto which
you attach many small `Texture`, `Line`, and `FontString` objects, positioned
with anchor math.

The container frame is a normal frame with a backdrop for the panel chrome:

```lua
local graph = CreateFrame("Frame", nil, parent, "BackdropTemplate")
graph:SetBackdrop({
  bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = false, edgeSize = 12,
  insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
graph:SetBackdropColor(...)
graph:SetBackdropBorderColor(...)
```

All plotted children are anchored relative to this frame's `BOTTOMLEFT`, which
makes the math match standard math conventions (y grows upward).

### Plot area (padding)

A fixed padding reserves room for axis labels so the actual plotting region is
inset from the frame edges:

```lua
PADDING = { left = 56, right = 18, bottom = 30, top = 18 }

function CalculatePlotDimensions(graphFrame)
  local w, h = graphFrame:GetWidth(), graphFrame:GetHeight()
  local plotW = math.max(1, w - PADDING.left - PADDING.right)
  local plotH = math.max(1, h - PADDING.bottom - PADDING.top)
  return plotW, plotH
end
```

`left` is the largest because Y-axis value labels (money / level numbers) live
there. `bottom` holds the X-axis time labels.

---

## 2. Coordinate transforms (data space → screen space)

The single most important technique: build closures that map a data value to a
pixel offset inside the plot region. Everything else (lines, points, grid,
labels) is positioned through these two functions.

```lua
function CreateTransformers(plotW, plotH, tMin, tRange, pMin, pRange)
  local function X(t) return PADDING.left   + plotW * ((t - tMin) / tRange) end
  local function Y(p) return PADDING.bottom + plotH * ((p - pMin) / pRange) end
  return X, Y
end
```

- `tMin/tRange` is the time domain, `pMin/pRange` is the value domain.
- Ranges are computed from the data with a little headroom so the line never
  touches the top/bottom edge:

```lua
function CalculatePriceRange(pts, paddingPercent)
  paddingPercent = paddingPercent or 0.08
  local pMin, pMax = pts[1].p, pts[1].p
  for i = 2, #pts do
    pMin = math.min(pMin, pts[i].p)
    pMax = math.max(pMax, pts[i].p)
  end
  local pad = math.max(1, math.floor((pMax - pMin) * paddingPercent))
  pMin = math.max(0, pMin - pad)
  pMax = pMax + pad
  return pMin, pMax, math.max(1, pMax - pMin)
end
```

For a **level progress** graph the Y domain is well known (1–70 for TBC), so you
can hard-clamp `pMin = 1`, `pMax = 70` instead of auto-ranging, or auto-range on
the visible level window and round to nice boundaries.

---

## 3. Anti-aliased lines (the key to "high quality")

Naive lines drawn as thin rotated rectangles look jagged. AHPriceGraph gets
smooth lines two ways, with a cached capability check and a fallback:

1. **Native `Line` widget** (`parent:CreateLine`) — hardware anti-aliased,
   anchored by two points so it auto-rescales when the frame resizes.
2. **Fallback**: a rotated `Texture` using a custom soft-edged line texture
   (`SoftLine.tga`, an alpha-gradient strip) so edges fade instead of aliasing.

```lua
local SOFT_LINE_TEX = "Interface\\AddOns\\AHPriceGraph\\Textures\\SoftLine"

function CreateLine(parent, x1, y1, x2, y2, thickness, r, g, b, a)
  local dx, dy = x2 - x1, y2 - y1
  local length = math.sqrt(dx*dx + dy*dy)
  if length <= 0.0001 then return end

  if _useNativeLine == nil then           -- probe once, cache the result
    local ok, testLine = pcall(function() return parent:CreateLine(nil, "ARTWORK") end)
    _useNativeLine = ok and testLine and testLine.SetStartPoint and true or false
  end

  if _useNativeLine then
    local line = parent:CreateLine(nil, "ARTWORK")
    line:SetThickness(thickness + 1)      -- +1 to compensate for soft-edge fade
    line:SetTexture(SOFT_LINE_TEX)
    line:SetVertexColor(r, g, b, a)
    line:SetStartPoint("BOTTOMLEFT", parent, x1, y1)
    line:SetEndPoint("BOTTOMLEFT", parent, x2, y2)
    return line
  end

  -- Fallback: one rotated soft-edge texture centered on the segment midpoint
  local angle = math.atan2(dy, dx)
  local tex = parent:CreateTexture(nil, "ARTWORK")
  tex:SetTexture(SOFT_LINE_TEX)
  tex:SetVertexColor(r, g, b, a)
  tex:SetSize(length, thickness + 1)
  tex:SetPoint("CENTER", parent, "BOTTOMLEFT", (x1+x2)/2, (y1+y2)/2)
  tex:SetRotation(angle)
  return tex
end
```

**Takeaways**

- Prefer the native `Line` widget; it is the cleanest result and survives resizes.
- Ship a `SoftLine.tga` texture (a horizontal white-to-transparent gradient
  strip) and apply it via `SetTexture` so both code paths get soft edges. *(Note:
  the `Textures/` folder must be present in the addon for this to load; reference
  it from your own addon path, e.g. `Interface\AddOns\AltArmy_TBC\Textures\SoftLine`.)*
- A polyline is just `CreateLine` called for each consecutive pair of points.

---

## 4. Object pooling and cleanup (avoid leaks / flicker)

Because every redraw spawns dozens of widgets, they are tracked in tables and
explicitly destroyed before the next draw. WoW cannot truly destroy frames, so
the pattern is `Hide()` + `SetParent(nil)` and then `wipe()` the table.

```lua
GraphCore.graphTextures = {}
GraphCore.graphLabels   = {}
GraphCore.graphLines    = {}

function ClearSharedObjects()
  for _, t in ipairs(graphTextures) do t:Hide(); t:SetParent(nil) end
  wipe(graphTextures)
  for _, l in ipairs(graphLines)  do l:Hide(); l:SetParent(nil) end
  wipe(graphLines)
  for _, fs in ipairs(graphLabels) do fs:Hide(); fs:SetParent(nil) end
  wipe(graphLabels)
end
```

Each graph type also keeps its own pools (hover frames, candle frames, points)
and calls `ClearSharedObjects()` plus its own cleanup at the start of every draw.
Tooltip frames are the exception: created **once** and reused (just `Hide()`),
never destroyed.

> A more advanced optimization (not done here) is real pooling — reusing hidden
> widgets instead of recreating them. For modest point counts the create/destroy
> approach is fine.

---

## 5. Grid, axes, ticks, and labels

Visual structure is layered from back to front:

1. **Time stripes** (alternating background bands) — `BACKGROUND` layer.
2. **Grid lines** — faint, low-alpha.
3. **Axes** — X and Y, slightly stronger color.
4. **Tick marks + labels**.
5. **Data** (lines, candles, points) — `ARTWORK`/`OVERLAY`.
6. **Tooltips** — `TOOLTIP` strata, on top of everything.

```lua
Y_TICKS = 4
X_TICKS = 5

function RenderGridLines(parent, plotW, plotH)      -- evenly spaced internal lines
  for i = 1, Y_TICKS - 1 do
    local y = PADDING.bottom + (i / Y_TICKS) * plotH
    CreateLine(parent, PADDING.left, y, PADDING.left + plotW, y, 1, GRID...)
  end
  for i = 1, X_TICKS - 1 do
    local x = PADDING.left + (i / X_TICKS) * plotW
    CreateLine(parent, x, PADDING.bottom, x, PADDING.bottom + plotH, 1, GRID...)
  end
end
```

### Y labels with a pluggable formatter

The Y label renderer takes a `formatFunc`, so the same code formats money, a
percentage, or a level number:

```lua
function RenderYLabels(parent, plotH, pMin, pRange, formatFunc)
  formatFunc = formatFunc or function(v) return Utils.CopperToMoneyString(v) end
  for i = 0, Y_TICKS do
    local frac = i / Y_TICKS
    local val  = math.floor(pMin + frac * pRange + 0.5)
    local y    = PADDING.bottom + frac * plotH
    CreateLine(parent, PADDING.left - 5, y, PADDING.left, y, 2, AXIS...) -- tick
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetText(formatFunc(val))
    fs:SetPoint("RIGHT", parent, "BOTTOMLEFT", PADDING.left - 8, y - 5)
  end
end
```

For level progress you would pass `function(v) return tostring(math.floor(v)) end`.

### X labels are time-aware

X labels are produced by a `formatFunc(ts, tMin, tMax, span)` that adapts the
label to the span (minutes / hours / days / dates):

```lua
local function FormatTickLabel(ts, tMin, tMax, span)
  local rel = ts - tMax                       -- relative to "now"
  if rel >= -60         then return "0"
  elseif rel > -3600    then return string.format("%dm", math.floor(rel/60+0.5))
  elseif rel > -86400   then return string.format("%dh", math.floor(rel/3600+0.5))
  else                       return string.format("%dd", math.floor(rel/86400+0.5)) end
end
```

Built-in Lua `date()` / `time()` are used heavily for absolute labels like
`date("%m/%d %H:%M", ts)`.

---

## 6. Time-aligned background stripes

To make time readable at a glance, alternating bands are drawn and **snapped to
calendar boundaries** (even hours / midnights / multi-day blocks) depending on
the visible window:

```lua
local function GetStripeConfig(windowSeconds)
  if windowSeconds <= DAY then
    return 2*HOUR, snapToEvenHour, function(ts) return date("%Hh", ts) end
  elseif windowSeconds <= 7*DAY then
    return DAY,    snapToMidnight, function(ts) return date("%a", ts) end  -- Mon, Tue
  ...
  end
end
```

Each stripe is a flat `BACKGROUND` texture sized to its clipped time interval and
positioned through the `X()` transform. For level progress this is great for
showing day boundaries (e.g. "leveled 5 bars on Saturday").

---

## 7. Data reduction / downsampling (performance + clarity)

Plotting thousands of raw points is slow and noisy. Two strategies:

### a) Merge + downsample for line graphs

Points within a small fraction of the time span are merged into buckets, then the
result is uniformly downsampled to a max count (last point always preserved):

```lua
function ReduceDataPoints(pts, maxPoints, mergeThreshold)   -- e.g. 50, 0.02
  -- 1. sort by time
  -- 2. greedily merge points whose time gap <= span * mergeThreshold
  --    averaging time, taking the min (or last) value per bucket
  -- 3. if still too many, sample every (n-1)/(max-1) and force-keep the last
end
```

### b) OHLC aggregation for candlesticks

For candlesticks, raw points are aggregated into fixed-size time buckets, picking
a "nice" bucket size (1h, 2h, 4h, 6h, 12h, 24h) so a target candle count is hit:

```lua
function CalculateBucketSize(pts, targetCandleCount) ... end   -- snaps to nice sizes
function AggregateIntoBuckets(pts, bucketSize)                 -- -> {open, high, low, close, pointCount}
```

For **level progress**, the natural reduction is one point per level-up event (or
one per XP snapshot), which is already sparse — but the same merge/downsample
keeps very long histories cheap to draw.

---

## 8. Interactivity: hover points and tooltips

High-quality graphs feel alive. Each data point gets an invisible, slightly
oversized `Frame` with mouse enabled; `OnEnter`/`OnLeave` show a styled tooltip
and grow the dot:

```lua
local hoverFrame = CreateFrame("Frame", nil, parent)
hoverFrame:SetSize(POINT_SIZE*2, POINT_SIZE*2)         -- larger than the dot = easy to hit
hoverFrame:SetPoint("CENTER", parent, "BOTTOMLEFT", x, y)
hoverFrame:SetFrameStrata("HIGH")
hoverFrame:EnableMouse(true)

hoverFrame:SetScript("OnEnter", function()
  tooltip:ClearAllPoints()
  tooltip:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x + 12, y + 12)
  SetTooltipContent(tooltip, value, timestamp, prevValue)
  tooltip:Show()
  pointTex:SetSize(POINT_SIZE + 4, POINT_SIZE + 4)      -- grow on hover
end)
hoverFrame:SetScript("OnLeave", function()
  tooltip:Hide()
  pointTex:SetSize(POINT_SIZE, POINT_SIZE)
end)
```

### Reusable tooltip with backdrop + shadow

The tooltip base is built once with a bordered backdrop and a separate, slightly
larger frame behind it for a soft shadow/glow — a cheap way to make it look
polished:

```lua
function CreateTooltipBase(parent, width, height)
  local tooltip = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  tooltip:SetFrameStrata("TOOLTIP")
  tooltip:SetBackdrop({ bgFile=..., edgeFile="...UI-Tooltip-Border", edgeSize=12, ... })
  tooltip:SetBackdropColor(...)          -- dark charcoal
  tooltip:SetBackdropBorderColor(...)    -- muted gold

  local shadow = CreateFrame("Frame", nil, tooltip, "BackdropTemplate")
  shadow:SetPoint("TOPLEFT", -4, 4); shadow:SetPoint("BOTTOMRIGHT", 4, -4)
  shadow:SetFrameLevel(tooltip:GetFrameLevel() - 1)
  shadow:SetBackdropColor(0,0,0,0.5)
  return tooltip
end
```

Tooltip rows are pre-created `FontString`s (label + value columns) whose text is
just updated on hover — never recreated.

---

## 9. Color as information

Color encodes meaning, which is a big part of perceived quality:

- **Per-segment gradient** on the line: red→green based on the % change between
  consecutive points (`GetGradientColor`).
- **Candle bull/bear/neutral** colors from `close` vs `open`.
- **A consistent palette** (`COLORS`) for header/label/value text, positive
  (green), negative (red), accent (blue), border (gold), backgrounds.
- **Reference lines**: a median line and dashed alert threshold lines (drawn as
  many short segments to fake a dash pattern).

```lua
-- dashed horizontal line
local x = startX
while x < endX do
  local ex = math.min(x + dashWidth, endX)
  CreateLine(parent, x, y, ex, y, 1, r, g, b, a)
  x = ex + gapWidth
end
```

For **level progress** good color ideas: color the line by XP/hour rate, mark
"ding" events with a bright dot, or draw faint horizontal reference lines at each
level boundary.

---

## 10. Overlaying multiple series (the Weekly pattern)

`WeeklyGraph.lua` shows how to overlay multiple lines and let the user toggle
them — directly relevant if you want to compare **multiple characters'** level
curves:

- Bucket data into series (there: by week; for you: by character).
- A fixed `WEEK_COLORS` palette + an `alpha` ramp so older/secondary series fade.
- Draw oldest/back series first so the primary series sits on top.
- An interactive **legend bar** of buttons that toggle each series' visibility and
  trigger a redraw; recompute the value range from only the visible series.
- A normalized common X axis (there: offset within the week) so series align even
  when their absolute timestamps differ — for character comparison you'd
  normalize the X axis to "time since character creation" or "played time".

---

## 11. Putting it together — the draw pipeline

Every graph type follows the same top-level recipe. A level-progress version
would look like:

```lua
function LevelGraph.DrawForCharacter(charKey)
  ClearObjects()                                   -- 1. wipe previous widgets

  local pts = GetLevelPoints(charKey)              -- 2. {t = timestamp, p = level (or XP%)}
  if #pts < 2 then showHint(); return end

  local plotW, plotH = Core.CalculatePlotDimensions(graph)         -- 3. dimensions
  local tMin, tMax, tRange = Core.CalculateTimeRange(pts)          -- 4. domains
  local pMin, pMax, pRange = Core.CalculatePriceRange(pts)         --    (or clamp 1..70)
  local X, Y = Core.CreateTransformers(plotW, plotH, tMin, tRange, pMin, pRange)

  Core.RenderTimeStripes(graph, plotW, plotH, tMin, tMax, windowSeconds)  -- 5. back→front
  Core.RenderGridLines(graph, plotW, plotH)
  Core.RenderAxes(graph, plotW, plotH)
  Core.RenderYLabels(graph, plotH, pMin, pRange, function(v) return tostring(math.floor(v)) end)
  Core.RenderXLabels(graph, plotW, tMin, tMax, FormatTickLabel)

  for i = 1, #pts - 1 do                           -- 6. the line
    Core.CreateLine(graph, X(pts[i].t), Y(pts[i].p), X(pts[i+1].t), Y(pts[i+1].p), 2, r,g,b,a)
  end
  RenderHoverPoints(graph, pts, X, Y)              -- 7. interactivity
end
```

---

## 12. Data model notes for level progress

The price addon stores, per item, `points = { { t = <unix time>, p = <copper> }, ... }`
appended on each scan. The equivalent for level progress:

- Per character: `points = { { t = <unix time>, p = <level> }, ... }`, appended on
  `PLAYER_LEVEL_UP` (and optionally periodic XP snapshots for sub-level
  granularity, storing fractional level = `level + XP/maxXP`).
- Persist in SavedVariables keyed by `realm-character`.
- Sort by `t` before drawing; the transform/reduce helpers assume time order.

The reusable, graph-type-agnostic helpers you can lift almost verbatim from
`GraphCore.lua`: `CalculatePlotDimensions`, `Calculate*Range`, `CreateTransformers`,
`CreateLine`, `CreateLabel`, `RenderGridLines`, `RenderAxes`, `RenderYLabels`,
`RenderXLabels`, `RenderTimeStripes`, `ReduceDataPoints`, `ClearSharedObjects`,
and `CreateTooltipBase`.

---

## Summary checklist for a "high quality" feel

- [ ] Closures (`X`, `Y`) mapping data → pixels; auto/clamped ranges with headroom.
- [ ] Native `Line` widget with a soft-edge texture for anti-aliasing (+ fallback).
- [ ] Layered draw order with a backdrop, grid, time-snapped stripes, axes.
- [ ] Pluggable label formatters (level numbers, dates, percentages).
- [ ] Data reduction (merge + downsample) for long histories.
- [ ] Interactive oversized hover frames + a reusable, shadowed tooltip.
- [ ] Meaningful color (rate gradient, ding markers, reference lines).
- [ ] Strict object pooling + `Hide()`/`SetParent(nil)` cleanup each redraw.
- [ ] Optional multi-series overlay + toggle legend for comparing characters.
