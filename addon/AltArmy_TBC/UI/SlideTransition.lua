-- AltArmy TBC — Horizontal slide transitions between sibling page frames.

AltArmy = AltArmy or {}
AltArmy.SlideTransition = AltArmy.SlideTransition or {}

local SlideTransition = AltArmy.SlideTransition

SlideTransition.DEFAULT_DURATION = 0.2

--- Quadratic ease-out: starts fast, settles into place.
function SlideTransition.EaseOut(t)
    if not t or t <= 0 then return 0 end
    if t >= 1 then return 1 end
    local u = 1 - t
    return 1 - u * u
end

--- Outgoing / incoming x-offsets for a horizontal page slide.
--- direction "forward": outgoing left, incoming from right.
--- direction "back": outgoing right, incoming from left.
--- @return number, number outX, inX
function SlideTransition.ComputeOffsets(progress, width, direction)
    width = width or 0
    if width <= 0 then
        return 0, 0
    end
    local t = SlideTransition.EaseOut(progress)
    -- forward: outgoing slides left (-), incoming enters from right (+)
    -- back:    outgoing slides right (+), incoming enters from left (-)
    local sign = (direction == "back") and 1 or -1
    local outX = sign * width * t
    local inX = -sign * width * (1 - t)
    return outX, inX
end

--- Advance a slide by elapsed time. Returns { outX, inX, done }.
function SlideTransition.Step(elapsed, duration, width, direction)
    duration = duration or SlideTransition.DEFAULT_DURATION
    if duration <= 0 then
        duration = SlideTransition.DEFAULT_DURATION
    end
    elapsed = elapsed or 0
    local progress = elapsed / duration
    if progress >= 1 then
        local outX, inX = SlideTransition.ComputeOffsets(1, width, direction)
        return { outX = outX, inX = inX, done = true }
    end
    local outX, inX = SlideTransition.ComputeOffsets(progress, width, direction)
    return { outX = outX, inX = inX, done = false }
end

-- *** Frame runner (WoW UI) ***

local activeRun = nil
local driver = nil

local function capturePoints(frame)
    if not frame or not frame.GetNumPoints then return nil end
    local points = {}
    local n = frame:GetNumPoints() or 0
    for i = 1, n do
        local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint(i)
        points[i] = {
            point = point,
            relativeTo = relativeTo,
            relativePoint = relativePoint,
            xOfs = xOfs or 0,
            yOfs = yOfs or 0,
        }
    end
    return points
end

local function applyOffset(frame, points, dx)
    if not frame or not points then return end
    frame:ClearAllPoints()
    for i = 1, #points do
        local p = points[i]
        frame:SetPoint(p.point, p.relativeTo, p.relativePoint, p.xOfs + (dx or 0), p.yOfs)
    end
end

local function restorePoints(frame, points)
    applyOffset(frame, points, 0)
end

local function finishRun(run, skipped)
    if not run then return end
    if run.from then
        restorePoints(run.from, run.fromPoints)
        if run.from.Hide then run.from:Hide() end
    end
    if run.to then
        restorePoints(run.to, run.toPoints)
        if run.to.Show then run.to:Show() end
    end
    if driver then
        driver:SetScript("OnUpdate", nil)
    end
    activeRun = nil
    if run.onFinish and not skipped then
        run.onFinish()
    end
end

--- Snap any in-flight transition to its end state (hides from, shows to, restores anchors).
function SlideTransition.Cancel()
    if not activeRun then return end
    local run = activeRun
    finishRun(run, true)
end

--- Animate from -> to with a horizontal slide.
--- opts: { from, to, width, direction, duration, onFinish }
--- direction: "forward" | "back"
function SlideTransition.Run(opts)
    if not opts or not opts.from or not opts.to then return end
    if activeRun then
        SlideTransition.Cancel()
    end

    local width = opts.width
    if not width or width <= 0 then
        if opts.to.GetWidth then
            width = opts.to:GetWidth() or 0
        end
    end
    if not width or width <= 0 then
        if opts.from.GetWidth then
            width = opts.from:GetWidth() or 0
        end
    end
    if not width or width <= 0 then
        width = 1
    end

    local direction = opts.direction or "forward"
    local duration = opts.duration or SlideTransition.DEFAULT_DURATION
    if duration <= 0 then
        duration = SlideTransition.DEFAULT_DURATION
    end

    local fromPoints = capturePoints(opts.from)
    local toPoints = capturePoints(opts.to)
    if not fromPoints or not toPoints then
        if opts.from.Hide then opts.from:Hide() end
        if opts.to.Show then opts.to:Show() end
        if opts.onFinish then opts.onFinish() end
        return
    end

    -- Both pages visible during the slide; start incoming off-screen.
    if opts.from.Show then opts.from:Show() end
    if opts.to.Show then opts.to:Show() end
    local startOut, startIn = SlideTransition.ComputeOffsets(0, width, direction)
    applyOffset(opts.from, fromPoints, startOut)
    applyOffset(opts.to, toPoints, startIn)

    local run = {
        from = opts.from,
        to = opts.to,
        fromPoints = fromPoints,
        toPoints = toPoints,
        width = width,
        direction = direction,
        duration = duration,
        elapsed = 0,
        onFinish = opts.onFinish,
    }
    activeRun = run

    if not driver then
        driver = CreateFrame("Frame")
    end
    driver:SetScript("OnUpdate", function(_, dt)
        if not activeRun then
            driver:SetScript("OnUpdate", nil)
            return
        end
        local r = activeRun
        r.elapsed = r.elapsed + (dt or 0)
        local step = SlideTransition.Step(r.elapsed, r.duration, r.width, r.direction)
        applyOffset(r.from, r.fromPoints, step.outX)
        applyOffset(r.to, r.toPoints, step.inX)
        if step.done then
            finishRun(r, false)
        end
    end)
end

function SlideTransition.IsRunning()
    return activeRun ~= nil
end
