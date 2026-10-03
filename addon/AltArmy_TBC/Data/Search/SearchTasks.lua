-- AltArmy TBC — Single budgeted OnUpdate task queue for search.

AltArmy = AltArmy or {}
AltArmy.SearchTasks = AltArmy.SearchTasks or {}

local ST = AltArmy.SearchTasks

local state = {
    generation = 0,
    queue = {},
    frame = nil,
}

local function ensureFrame()
    if state.frame then
        return state.frame
    end
    state.frame = CreateFrame("Frame")
    return state.frame
end

local function pump()
    local q = state.queue
    if #q == 0 then
        ensureFrame():SetScript("OnUpdate", nil)
        return
    end
    local task = q[1]
    if task.generation ~= state.generation then
        table.remove(q, 1)
        if #q == 0 then
            ensureFrame():SetScript("OnUpdate", nil)
        end
        return
    end
    local done = true
    if type(task.step) == "function" then
        done = task.step() and true or false
    end
    if done then
        table.remove(q, 1)
        if task.onDone then
            task.onDone()
        end
    end
    if #q == 0 then
        ensureFrame():SetScript("OnUpdate", nil)
    end
end

function ST.BumpGeneration()
    state.generation = state.generation + 1
    state.queue = {}
    if state.frame then
        state.frame:SetScript("OnUpdate", nil)
    end
    return state.generation
end

function ST.Generation()
    return state.generation
end

--- Enqueue a step function. step() returns true when the task is finished.
function ST.Enqueue(step, onDone)
    local gen = state.generation
    state.queue[#state.queue + 1] = {
        generation = gen,
        step = step,
        onDone = onDone,
    }
    local frame = ensureFrame()
    if not frame:GetScript("OnUpdate") then
        frame:SetScript("OnUpdate", function()
            pump()
        end)
    end
end

function ST.IsBusy()
    return #state.queue > 0
end

function ST.TickForTests()
    pump()
end

function ST.ResetForTests()
    state.generation = 0
    state.queue = {}
    if state.frame then
        state.frame:SetScript("OnUpdate", nil)
    end
end
