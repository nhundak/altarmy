-- AltArmy TBC — read the player's own recipes without them opening each profession window (WoW Forever).
-- luacheck: globals ProfessionsFrame ProfessionsFrame_LoadUI GetUIPanel C_SpellBook GetFramesRegisteredForEvent
-- luacheck: globals ChatEdit_GetActiveWindow ChatFrameUtil
--
-- C_TradeSkillUI.OpenTradeSkill needs a click, but a hidden tooltip's SetHyperlink on a profession link,
-- "trade:<player GUID>:<profession spell>:<skill line>", does not: the client asks the server for that
-- profession and opens it as if the player had. The DataStore's own TRADE_SKILL_SHOW /
-- TRADE_SKILL_DATA_SOURCE_CHANGED handlers then scan it (ScanRecipesViaTradeSkillUI), which calls
-- R.OnRecipesScanned, and the window is closed again. Learned from the Linked Inn addon (Reader.ReadOwn);
-- see docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md, "Eighth".
--
-- Only stale professions are read (marked by the Summary warning, or with no recipes stored), since each read
-- opens the window and so plays its sound. Reads run one at a time, after login and after a recipe is
-- learned that the bundled recipe data couldn't store, never in combat, while typing, or
-- while any panel (the player's own profession window included) is open. While one runs, Blizzard's
-- profession window is kept from opening (its TRADE_SKILL_SHOW handlers are unregistered; other addons'
-- are left alone) and, should it open anyway, hidden. Only on clients with C_TradeSkillUI and no legacy
-- trade skill API (Forever); TBC's Enchanting has no trade skill window at all.

if not AltArmy or not AltArmy.DataStore then return end

local DS = AltArmy.DataStore

AltArmy.OwnRecipeRead = AltArmy.OwnRecipeRead or {}
local R = AltArmy.OwnRecipeRead

R.LOGIN_DELAY = 10 -- seconds after login or a reload before the first read
R.LEARN_DELAY = 3  -- seconds after a recipe is learned before its profession is read again
R.GAP = 1          -- seconds between reads
R.RETRY = 5        -- seconds before trying again while something is in the way
R.TIMEOUT = 3      -- seconds a read may take before its link counts as unanswered

local PANELS = { "left", "center", "right", "doublewide", "fullscreen" }
local CONCEALED_SCALE = 0.01
-- Reads on which silencing Blizzard's window never once got an answer before it is given up (the window is
-- then only hidden): keeps a client where the silenced window holds the data back from never reading.
local QUIET_GIVE_UP = 6

local queue = {}
local pending
local pumpScheduled = false
local workedSpell = {} -- skill line -> the spell whose link was answered (this session)
local frameHooked = false
local concealed = false
local savedLook
local silenced
local quietTries, quietWorks, quietOff = 0, 0, false
local tooltip
local readLog = {}
local attempts = 0 -- each start's own number, so an old start's timeout can't end a newer one

--- Debug only: the last reads, written as a dev dump when /altarmy debug is on (docs/DEV_DUMPS.md).
local function note(entry)
    local D = AltArmy.Debug
    if not (D and D.Dump) then return end
    table.insert(readLog, 1, entry)
    if #readLog > 20 then table.remove(readLog) end
    D.Dump("ownRecipeRead", { reads = readLog, quietOff = quietOff, quietTries = quietTries,
        quietWorks = quietWorks })
end

function R.HasApi()
    local api = C_TradeSkillUI
    return DS.IsUsingTradeSkillUiFallback ~= nil and DS.IsUsingTradeSkillUiFallback()
        and api ~= nil and api.CloseTradeSkill ~= nil
        and GetProfessions ~= nil and GetProfessionInfo ~= nil
        and C_SpellBook ~= nil and C_SpellBook.GetSpellBookItemInfo ~= nil
        and UnitGUID ~= nil
end

--- Whether recipes are read in the background (on until turned off in Options > General > Advanced).
function R.IsEnabled()
    return not (type(AltArmyTBC_Options) == "table" and AltArmyTBC_Options.autoReadRecipes == false)
end

function R.SetEnabled(on)
    if type(AltArmyTBC_Options) ~= "table" then
        AltArmyTBC_Options = {}
    end
    AltArmyTBC_Options.autoReadRecipes = on == true
end

local function active()
    return R.HasApi() and R.IsEnabled()
end

--- True while a read is waiting for its window (ScanRecipesViaTradeSkillUI trusts an unnamed link then).
function R.IsReading()
    return pending ~= nil
end

-- Finding the professions --------------------------------------------------------------------------------

local function spellAt(slot)
    local enum = _G.Enum
    local bank = enum and enum.SpellBookSpellBank and enum.SpellBookSpellBank.Player or 0
    local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, slot, bank)
    return ok and type(info) == "table" and tonumber(info.spellID) or nil
end

--- A profession's link candidates: its spellbook spells (a gathering profession's first may be a Find
--- spell that opens nothing), the one answered before first.
local function candidateSpells(numSpells, offset, skillLine)
    local spells = {}
    local known = workedSpell[skillLine]
    if known then spells[1] = known end
    for i = 1, math.max(tonumber(numSpells) or 1, 1) do
        local spellID = spellAt(offset + i)
        if spellID and spellID ~= known then
            spells[#spells + 1] = spellID
        end
    end
    return spells
end

--- One job per profession with recipes: { name, skillLine, spells }.
local function professionJobs()
    local jobs = {}
    local slots = { GetProfessions() }
    for i = 1, 6 do
        local index = slots[i]
        if i ~= 3 and type(index) == "number" then -- 3 is Archaeology
            local name, _, rank, _, numSpells, offset, skillLine = GetProfessionInfo(index)
            name = DS.NormalizeProfessionName and DS.NormalizeProfessionName(name) or name
            if type(name) == "string" and name ~= "" and (tonumber(rank) or 0) > 0
                and type(offset) == "number" and type(skillLine) == "number"
                and not DS.ProfessionHasNoRecipeWindow(name) then
                local spells = candidateSpells(numSpells, offset, skillLine)
                if #spells > 0 then
                    jobs[#jobs + 1] = { name = name, skillLine = skillLine, spells = spells }
                end
            end
        end
    end
    return jobs
end

--- Whether a profession's stored recipes need reading: marked stale (Summary warning) or none stored. Only
--- those are read, since each read opens the profession window, which plays its sound.
local function isStale(name)
    local char = DS._GetCurrentCharTable and DS._GetCurrentCharTable()
    if not char then return true end
    local needing = char.professionsNeedingRecipeScan
    if type(needing) == "table" and needing[name] then return true end
    return DS:GetNumRecipes(char, name) == 0
end

local function isQueued(name)
    if pending and pending.name == name then return true end
    for _, job in ipairs(queue) do
        if job.name == name then return true end
    end
    return false
end

-- Keeping the window out of sight ------------------------------------------------------------------------

local function conceal(frame)
    if not concealed then
        savedLook = {
            alpha = frame.GetAlpha and frame:GetAlpha() or 1,
            scale = frame.GetScale and frame:GetScale() or 1,
            mouse = frame.IsMouseEnabled and frame:IsMouseEnabled(),
        }
    end
    concealed = true
    pcall(frame.SetAlpha, frame, 0)
    pcall(frame.SetScale, frame, CONCEALED_SCALE)
    pcall(frame.EnableMouse, frame, false)
end

local function reveal()
    local frame = ProfessionsFrame
    if concealed and frame and savedLook then
        pcall(frame.SetAlpha, frame, savedLook.alpha)
        pcall(frame.SetScale, frame, savedLook.scale)
        if savedLook.mouse ~= nil then
            pcall(frame.EnableMouse, frame, savedLook.mouse)
        end
    end
    concealed = false
    savedLook = nil
end

local function hookFrame()
    local frame = ProfessionsFrame
    if frameHooked or not frame or not frame.HookScript then return end
    frameHooked = true
    frame:HookScript("OnShow", function(self)
        if pending then conceal(self) end
    end)
    frame:HookScript("OnHide", reveal)
end

local function ensureFrame()
    if not ProfessionsFrame then
        if ProfessionsFrame_LoadUI then
            pcall(ProfessionsFrame_LoadUI)
        elseif C_AddOns and C_AddOns.LoadAddOn then
            pcall(C_AddOns.LoadAddOn, "Blizzard_Professions")
        end
    end
    hookFrame()
end

--- Blizzard's own handlers that open the profession window: UIParent's and ProfessionsFrame's (and its
--- children's). Other addons' frames are never touched.
local function isBlizzardWindowFrame(frame)
    if frame == UIParent then return true end
    local window = ProfessionsFrame
    local depth = 0
    while type(frame) == "table" and depth < 20 do
        if frame == window then return true end
        if not frame.GetParent then return false end
        local ok, parent = pcall(frame.GetParent, frame)
        if not ok then return false end
        frame = parent
        depth = depth + 1
    end
    return false
end

local function silence()
    if silenced or quietOff or not GetFramesRegisteredForEvent then return end
    silenced = {}
    quietTries = quietTries + 1
    local frames = { pcall(GetFramesRegisteredForEvent, "TRADE_SKILL_SHOW") }
    for i = 2, #frames do
        local frame = frames[i]
        if type(frame) == "table" and frame.UnregisterEvent and isBlizzardWindowFrame(frame)
            and pcall(frame.UnregisterEvent, frame, "TRADE_SKILL_SHOW") then
            silenced[#silenced + 1] = frame
        end
    end
end

local function unsilence()
    if not silenced then return end
    for _, frame in ipairs(silenced) do
        pcall(frame.RegisterEvent, frame, "TRADE_SKILL_SHOW")
    end
    silenced = nil
end

local function closeWindow()
    pcall(C_TradeSkillUI.CloseTradeSkill)
    reveal()
    unsilence()
end

-- Waiting for a quiet moment -----------------------------------------------------------------------------

local function chatActive()
    local fn = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow) or ChatEdit_GetActiveWindow
    if not fn then return false end
    local ok, box = pcall(fn)
    return ok and box ~= nil
end

local function panelOpen()
    local frame = ProfessionsFrame
    if frame and frame.IsShown and frame:IsShown() and not concealed then
        return true
    end
    if not GetUIPanel then return false end
    for _, key in ipairs(PANELS) do
        local ok, open = pcall(GetUIPanel, key)
        if ok and open then return true end
    end
    return false
end

local function blocked()
    return (InCombatLockdown and InCombatLockdown()) or chatActive() or panelOpen()
end

-- The queue ----------------------------------------------------------------------------------------------

local pump

local function schedulePump(delay)
    if pumpScheduled then return end
    pumpScheduled = true
    C_Timer.After(delay, function()
        pumpScheduled = false
        pump()
    end)
end

local function finish(job, outcome)
    if pending ~= job then return end
    pending = nil
    job.attempt = nil
    closeWindow()
    local spell = job.spells[job.try]
    if outcome == "ok" and job.quiet then
        quietWorks = quietWorks + 1
    end
    if not quietOff and quietWorks == 0 and quietTries >= QUIET_GIVE_UP then
        quietOff = true
    end
    note({ profession = job.name, spell = spell, outcome = outcome, try = job.try })
    if outcome == "ok" then
        workedSpell[job.skillLine] = spell
    elseif job.try < #job.spells then
        table.insert(queue, 1, job) -- its next spell
    end
    schedulePump(R.GAP)
end

local function start(job)
    local guid = UnitGUID("player")
    if type(guid) ~= "string" or guid == "" then
        table.insert(queue, 1, job)
        schedulePump(R.RETRY)
        return
    end
    job.try = (job.try or 0) + 1
    local spell = job.spells[job.try]
    ensureFrame()
    pending = job
    silence()
    job.quiet = silenced ~= nil
    if not tooltip then
        tooltip = CreateFrame("GameTooltip", "AltArmyTBC_OwnRecipeReadTooltip", UIParent, "GameTooltipTemplate")
    end
    pcall(tooltip.SetOwner, tooltip, UIParent, "ANCHOR_NONE")
    local link = string.format("trade:%s:%d:%d", guid, spell, job.skillLine)
    local ok = pcall(tooltip.SetHyperlink, tooltip, link)
    pcall(tooltip.Hide, tooltip)
    if not ok then
        finish(job, "error")
        return
    end
    attempts = attempts + 1
    local mine = attempts
    job.attempt = mine
    C_Timer.After(R.TIMEOUT, function()
        if job.attempt == mine then
            finish(job, "timeout")
        end
    end)
end

pump = function()
    if pending or #queue == 0 or not active() then return end
    if blocked() then
        schedulePump(R.RETRY)
        return
    end
    start(table.remove(queue, 1))
end

--- Queue every stale profession, in the game's order. Returns how many were queued.
function R.QueueAll()
    if not active() then return 0 end
    local added = 0
    for _, job in ipairs(professionJobs()) do
        if isStale(job.name) and not isQueued(job.name) then
            queue[#queue + 1] = job
            added = added + 1
        end
    end
    if added > 0 then pump() end
    return added
end

--- Queue one profession by name if it is stale; every stale one when it is not among the character's.
function R.Queue(name)
    if not active() then return 0 end
    for _, job in ipairs(professionJobs()) do
        if job.name == name then
            if not isStale(name) or isQueued(name) then return 0 end
            queue[#queue + 1] = job
            pump()
            return 1
        end
    end
    return R.QueueAll()
end

--- The DataStore stored the open window's recipes (DS:ScanRecipes): ends the read waiting for it.
function R.OnRecipesScanned(professionName)
    if pending then
        local job = pending
        if professionName ~= job.name then
            note({ profession = job.name, scanned = professionName, outcome = "scanned another name" })
        end
        finish(job, "ok")
    end
end

--- A recipe was learned (DS:OnRecipeLearnDetected): read its profession, or every one when unknown.
function R.OnRecipeLearned(professionName)
    if not active() then return end
    C_Timer.After(R.LEARN_DELAY, function()
        if professionName then
            R.Queue(professionName)
        else
            R.QueueAll()
        end
    end)
end

local function abort()
    local job = pending
    if not job then
        unsilence()
        return
    end
    pending = nil
    job.attempt = nil
    closeWindow()
    job.try = job.try - 1
    table.insert(queue, 1, job)
    schedulePump(R.RETRY)
end

function R.OnEvent(event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        if (isInitialLogin or isReloadingUi) and active() then
            C_Timer.After(R.LOGIN_DELAY, R.QueueAll)
        end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_LOGOUT" then
        abort()
    elseif event == "ADDON_LOADED" then
        if ... == "Blizzard_Professions" then hookFrame() end
    end
end

function R._ResetForTests()
    queue, pending, pumpScheduled, workedSpell = {}, nil, false, {}
    frameHooked, concealed, savedLook, silenced = false, false, nil, nil
    quietTries, quietWorks, quietOff = 0, 0, false
    tooltip, readLog, attempts = nil, {}, 0
end

local frame = CreateFrame and CreateFrame("Frame")
if frame then
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_LOGOUT", "ADDON_LOADED" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function(_, event, ...) R.OnEvent(event, ...) end)
end
