-- AltArmy TBC — full auction house scans for altarmy-profit.
-- Asks the client for every listing (C_AuctionHouse.ReplicateItems: once per 15 minutes per account) and
-- reads what comes back into AuctionBook's ladders, a batch a frame. It also reads a scan another addon
-- asked for (Auctionator's full scan): the listings event is the client's, whoever asked.
-- Only a scan read to its end is stored; one the auction house closed on is dropped.
-- With the automatic scan on (AltArmyTBC_Options.auctionAutoScan, the Auction House options), a scan starts
-- AUTO_DELAY seconds after the auction house opens, if the client allows one and none is under way.
-- A scan Alt Army starts (the button, /altarmy scan or the automatic scan) says in chat when it starts and how
-- it ended; one another addon asked for is read quietly.
-- luacheck: globals GetServerTime AltArmyTBC_Options

if not AltArmy then return end

AltArmy.AuctionScan = AltArmy.AuctionScan or {}
local S = AltArmy.AuctionScan

S.BATCH = 2000 -- listings read a frame
S.TIMEOUT = 60 -- seconds to wait for the listings
S.REPEAT = 30 -- seconds after a scan in which the client repeating its event is not a new scan
S.AUTO_DELAY = 1 -- seconds after the auction house opens before the automatic scan (the frame settles first)

local state = "idle" -- idle | waiting (asked, no listings yet) | reading
local open = false
local visit = 0 -- which opening of the auction house the automatic scan's timer belongs to
local run = 0 -- which scan the timers belong to
local tally, index, total, source
local finishedAt
local ours = false -- the scan under way is one Start asked for, so its end is said in chat
local listeners = {}

local function now()
    if GetServerTime then return GetServerTime() end
    return time and time() or 0
end

local ALTARMY_GOLD = "|cfffecc00"

local function say(text)
    local chat = _G.DEFAULT_CHAT_FRAME
    if chat and chat.AddMessage then
        chat:AddMessage(ALTARMY_GOLD .. "Alt Army|r " .. text)
    end
end

local function book()
    return AltArmy.AuctionBook
end

local function set(new)
    state = new
    for i = 1, #listeners do
        listeners[i](state)
    end
end

--- idle, waiting or reading.
function S.State()
    return state
end

--- How much of the scan being read is read, 0..1.
function S.Progress()
    if state ~= "reading" or not total or total == 0 then return 0 end
    return index / total
end

--- Seconds until the client allows another scan.
function S.CooldownLeft()
    return book().CooldownLeft(now())
end

function S.IsOpen()
    return open
end

--- Call `fn(state)` whenever the state changes or a batch was read.
function S.OnChange(fn)
    listeners[#listeners + 1] = fn
end

--- True where Alt Army scans: WoW Forever (altarmy-profit takes Forever's prices from these scans alone),
--- with the client's full-scan API. Off elsewhere (TBC Anniversary) even if the client has the API, so no
--- button, options section, automatic scan or reading of other addons' scans.
function S.HasApi()
    local DS = AltArmy.DataStore
    if not (DS and DS.IsWowForever) then return false end
    local api = C_AuctionHouse
    return type(api) == "table" and type(api.ReplicateItems) == "function"
        and type(api.GetNumReplicateItems) == "function" and type(api.GetReplicateItemInfo) == "function"
end

local function stop()
    if ours then
        say("Auction house scan stopped before it finished; nothing was saved.")
        ours = false
    end
    run = run + 1
    tally, index, total, source = nil, nil, nil, nil
    set("idle")
end

local function store()
    local faction = UnitFactionGroup and UnitFactionGroup("player") or nil
    local realm = GetRealmName and GetRealmName() or nil
    if tally.listings > 0 and faction and faction ~= "" and realm and realm ~= "" then
        book().Store({
            t = now(),
            realm = realm,
            faction = faction,
            complete = true,
            listings = tally.listings,
            bidOnly = tally.bidOnly,
            source = source,
            items = book().Encode(tally),
        }, now())
        if ours then
            say(string.format("Auction house scan complete: %d listings saved.", tally.listings))
        end
    elseif ours then
        say("Auction house scan complete: no listings to save.")
    end
    ours = false
    finishedAt = now()
end

local function readBatch(mine)
    if run ~= mine or state ~= "reading" then return end
    local last = math.min(index + S.BATCH, total)
    local ok = pcall(function()
        for i = index, last - 1 do
            local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID =
                C_AuctionHouse.GetReplicateItemInfo(i)
            book().Add(tally, itemID, count, buyout)
        end
    end)
    if not ok then
        stop()
        return
    end
    index = last
    if index >= total then
        store()
        stop()
        return
    end
    set("reading")
    C_Timer.After(0, function() readBatch(mine) end)
end

local function read()
    local asked = state == "waiting"
    if not asked then
        if finishedAt and now() - finishedAt < S.REPEAT then return end
        book().NoteRequest(now()) -- another addon's scan spends the cooldown too
    end
    run = run + 1
    tally, index, total = book().NewTally(), 0, C_AuctionHouse.GetNumReplicateItems() or 0
    source = asked and "own" or "heard"
    state = "reading"
    readBatch(run)
end

--- Whether a scan starts by itself when the auction house opens (off until turned on).
function S.IsAutoScanEnabled()
    return type(AltArmyTBC_Options) == "table" and AltArmyTBC_Options.auctionAutoScan == true
end

function S.SetAutoScanEnabled(on)
    if type(AltArmyTBC_Options) ~= "table" then
        AltArmyTBC_Options = {}
    end
    AltArmyTBC_Options.auctionAutoScan = on == true
end

local function scheduleAutoScan()
    if not S.IsAutoScanEnabled() or not S.HasApi() or not (C_Timer and C_Timer.After) then return end
    local mine = visit
    C_Timer.After(S.AUTO_DELAY, function()
        -- Start refuses when closed, busy (another addon's scan came first) or cooling down.
        if visit == mine and open and state == "idle" then
            S.Start()
        end
    end)
end

function S.OnEvent(event)
    if event == "AUCTION_HOUSE_SHOW" then
        open = true
        visit = visit + 1
        set(state)
        scheduleAutoScan()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        open = false
        visit = visit + 1
        stop()
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        if state ~= "reading" and S.HasApi() then
            read()
        end
    end
end

--- Ask for every listing. Returns true once asked; false and why otherwise: "missing" (the client has no
--- full scan), "closed" (no auction house open), "busy", "cooldown", "error" (the client refused).
function S.Start()
    if not S.HasApi() then return false, "missing" end
    if not open then return false, "closed" end
    if state ~= "idle" then return false, "busy" end
    if S.CooldownLeft() > 0 then return false, "cooldown" end
    if not pcall(C_AuctionHouse.ReplicateItems) then return false, "error" end
    book().NoteRequest(now())
    run = run + 1
    local mine = run
    ours = true
    say("Auction house scan started. Keep the auction house open until it completes.")
    set("waiting")
    C_Timer.After(S.TIMEOUT, function()
        if run == mine and state == "waiting" then
            stop()
        end
    end)
    return true
end

function S._ResetForTests()
    state, open, run, visit = "idle", false, 0, 0
    tally, index, total, source, finishedAt = nil, nil, nil, nil, nil
    ours = false
    listeners = {}
end

local frame = CreateFrame and CreateFrame("Frame")
if frame then
    frame:RegisterEvent("AUCTION_HOUSE_SHOW")
    frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
    -- Not every client has the event: registering an unknown one raises.
    pcall(frame.RegisterEvent, frame, "REPLICATE_ITEM_LIST_UPDATE")
    frame:SetScript("OnEvent", function(_, event) S.OnEvent(event) end)
end
