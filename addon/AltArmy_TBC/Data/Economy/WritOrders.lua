-- AltArmy TBC — what a Craftsman's Writ really asks for, read from the quest log (Economy tab).
-- The game data names the item a writ wants but not how many (Writs.lua assumes one craft's output), so
-- whenever a character holds a writ's quest its objective ("Lesser Wizard's Robe: 0/2") is read and kept
-- account-wide: AltArmyTBC_Data.WritOrders[questID] = { item, count, t }. `item` is the objective's name
-- resolved among the writ's candidate items (nil when it matches none: the count still counts).
-- Blizzard's quest APIs are not otherwise used by the addon and differ between clients, so every call is
-- existence-checked and pcall'd; without them nothing is recorded and the view keeps its assumptions.
-- With master debug on (/altarmy debug on) each scan also dumps the raw objectives of the writ quests held
-- and the tooltip lines of the writs in the character's bags (dev dumps `writOrders` and `writTooltips`),
-- so the formats can be checked from the SavedVariables file and the parsing tightened.
-- luacheck: globals AltArmyTBC_Data C_QuestLog GetNumQuestLogEntries GetQuestLogTitle GetNumQuestLeaderBoards
-- luacheck: globals GetQuestLogLeaderBoard C_Timer C_EventUtils

if not AltArmy then return end

AltArmy.WritOrders = AltArmy.WritOrders or {}
local O = AltArmy.WritOrders

O.SCAN_DELAY = 1 -- seconds the quest log's events are coalesced over

--- A name as it is compared: lower case, letters and digits only (the generator's normalize).
function O.Normalize(name)
    return (tostring(name or ""):lower():gsub("[^%w]", ""))
end

--- An objective's text ("Lesser Wizard's Robe: 0/2") as name, units had, units needed; nil when it isn't
--- of that shape.
function O.ParseObjective(text)
    if type(text) ~= "string" then return nil end
    local name, have, need = text:match("^%s*(.-)%s*:%s*(%d+)%s*/%s*(%d+)%s*$")
    if not name or name == "" then return nil end
    return name, tonumber(have), tonumber(need)
end

--- The item among `candidates` (item ids) named `name`, by `items` (id -> { name }); nil when none is.
function O.Resolve(name, candidates, items)
    local wanted = O.Normalize(name)
    if wanted == "" then return nil end
    for _, item in ipairs(candidates or {}) do
        local entry = items and items[item]
        if entry and O.Normalize(entry.name) == wanted then
            return item
        end
    end
    return nil
end

--- Keep the order `questID` asks for in `store`; true when it is news.
function O.Record(store, questID, item, count, now)
    if type(count) ~= "number" or count < 1 then return false end
    local old = store[questID]
    if old and old.item == item and old.count == count then
        return false
    end
    store[questID] = { item = item, count = count, t = now }
    return true
end

--- The account-wide orders table, created on first use.
function O.Orders()
    if type(AltArmyTBC_Data) ~= "table" then return {} end
    if type(AltArmyTBC_Data.WritOrders) ~= "table" then
        AltArmyTBC_Data.WritOrders = {}
    end
    return AltArmyTBC_Data.WritOrders
end

-- ---------------------------------------------------------------------------------------------------
-- The client: reading the quest log

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d, e, f, g, h
end

--- Every quest in the log as { questID, index, title }, through whichever API the client has.
local function questLogEntries()
    local out = {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local n = call(C_QuestLog.GetNumQuestLogEntries) or 0
        for i = 1, n do
            local info = call(C_QuestLog.GetInfo, i)
            if type(info) == "table" and not info.isHeader and type(info.questID) == "number" then
                out[#out + 1] = { questID = info.questID, index = i, title = info.title }
            end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        local n = call(GetNumQuestLogEntries) or 0
        for i = 1, n do
            local title, _, _, isHeader, _, _, _, questID = call(GetQuestLogTitle, i)
            if not isHeader and type(questID) == "number" then
                out[#out + 1] = { questID = questID, index = i, title = title }
            end
        end
    end
    return out
end

--- A quest's objectives as { text, type, numRequired, numFulfilled, finished }.
local function objectives(entry)
    local out = {}
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local list = call(C_QuestLog.GetQuestObjectives, entry.questID)
        if type(list) == "table" then
            for _, o in ipairs(list) do
                if type(o) == "table" then
                    out[#out + 1] = { text = o.text, type = o.type, numRequired = o.numRequired,
                        numFulfilled = o.numFulfilled, finished = o.finished }
                end
            end
            return out
        end
    end
    if GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
        local n = call(GetNumQuestLeaderBoards, entry.index) or 0
        for j = 1, n do
            local text, kind, finished = call(GetQuestLogLeaderBoard, j, entry.index)
            if text then
                out[#out + 1] = { text = text, type = kind, finished = finished }
            end
        end
    end
    return out
end

--- Read the writ quests held and keep their orders; true when any order is news.
function O.Scan()
    local Writs = AltArmy.Writs
    if not (Writs and Writs.ByQuest) then return false end
    local store, now, changed = O.Orders(), time and time() or 0, false
    local raw = {}
    for _, entry in ipairs(questLogEntries()) do
        local writ = Writs.ByQuest[entry.questID]
        if writ then
            local list = objectives(entry)
            raw[entry.questID] = { title = entry.title, objectives = list }
            for _, o in ipairs(list) do
                local name, _, need = O.ParseObjective(o.text)
                local count = tonumber(o.numRequired) or need
                if name and count then
                    local item = O.Resolve(name, writ.items, Writs.ITEMS)
                    if O.Record(store, entry.questID, item, count, now) then changed = true end
                end
            end
        end
    end
    O.DumpForDebug(raw)
    return changed
end

--- Dev dumps for the formats (no-ops unless master debug is on): the writ quests' raw objectives and the
--- tooltip lines of every writ in the current character's bags.
function O.DumpForDebug(raw)
    local Debug = AltArmy.Debug
    if not (Debug and Debug.IsEnabled and Debug.IsEnabled() and Debug.Dump) then return end
    Debug.Dump("writOrders", raw)
    local DS, IS, Writs = AltArmy.DataStore, AltArmy.ItemStats, AltArmy.Writs
    local char = DS and DS.GetCurrentCharacter and DS:GetCurrentCharacter()
    if not (char and IS and IS.GetTooltipLines and Writs) then return end
    local tooltips = {}
    for _, writ in ipairs(Writs.LIST) do
        if (DS:GetBagItemCount(char, writ.id) or 0) > 0 then
            local ok, lines = pcall(IS.GetTooltipLines, "item:" .. writ.id)
            tooltips[writ.id] = ok and lines or tostring(lines)
        end
    end
    Debug.Dump("writTooltips", tooltips)
end

if CreateFrame then
    local frame = CreateFrame("Frame")
    local pending = false

    local function SafeRegisterEvent(eventName)
        if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(eventName) then
            return
        end
        pcall(frame.RegisterEvent, frame, eventName)
    end

    local function scanSoon()
        if pending then return end
        pending = true
        local function run()
            pending = false
            if O.Scan() then
                local economy = AltArmy.TabFrames and AltArmy.TabFrames.Economy
                if economy and economy.RefreshWrits then economy.RefreshWrits() end
            end
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(O.SCAN_DELAY, run)
        else
            run()
        end
    end

    SafeRegisterEvent("PLAYER_ENTERING_WORLD")
    SafeRegisterEvent("QUEST_ACCEPTED")
    SafeRegisterEvent("QUEST_LOG_UPDATE")
    frame:SetScript("OnEvent", scanSoon)
end
