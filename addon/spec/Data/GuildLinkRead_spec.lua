--[[ Unit tests for GuildLinkRead.lua (guildmates' professions read through profession links) — run: npm test ]]

describe("GuildLinkRead", function()
    local GLR, GSD, GMG, P
    local timers, clock, enqueued, logs, requested, notified, rosterCalls, roster
    local R
    local saved, savedModules = {}, {}
    local TOUCHED = {
        "C_Timer", "time", "IsInGuild", "GetNumGuildMembers", "GetGuildRosterInfo", "UnitGUID", "GetRealmName",
        "GetGuildInfo", "canaccessvalue", "GuildRoster", "C_GuildInfo", "CreateFrame", "AltArmyTBC_GuildData",
        "C_Club", "C_CreatureInfo",
    }
    local MODULES = { "OwnRecipeRead", "Debug", "GuildShareComm", "GuildShareSettings" }
    local rosterRows, clubRosterRows
    local NOW = 1700000000

    local function advance(seconds)
        local target = clock + seconds
        local guard = 0
        while true do
            local idx
            for i, t in ipairs(timers) do
                if t.at <= target and (not idx or t.at < timers[idx].at) then idx = i end
            end
            if not idx then break end
            local t = table.remove(timers, idx)
            clock = t.at
            t.fn()
            guard = guard + 1
            assert.is_true(guard < 1000)
        end
        clock = target
    end

    local function tagOf(job) return job.guid .. "|" .. job.skillLine end

    --- Queued jobs not yet finished or cancelled.
    local function queued(guid)
        local out = {}
        for _, j in ipairs(enqueued) do
            if not j.done and (not guid or j.guid == guid) then out[#out + 1] = j end
        end
        return out
    end

    local function job(guid, skillLine)
        for _, j in ipairs(enqueued) do
            if not j.done and j.guid == guid and j.skillLine == skillLine then return j end
        end
        return nil
    end

    local function finish(j, outcome, result, elapsed)
        j.done = true
        j.onResult(outcome, result, elapsed)
    end

    local function okResult(key, name, ids)
        return { key = key, professionName = name, rank = 50, maxRank = 150, ids = ids or { 1, 2 } }
    end

    local function hasLog(pattern)
        for _, line in ipairs(logs) do
            if line:find(pattern, 1, true) then return true end
        end
        return false
    end

    --- Members seen long enough ago that a pass no longer waits for them to announce the addon.
    local function seenBefore()
        for _, r in ipairs(roster) do GLR._State().seen[r.guid] = NOW - GLR.PRESENCE_GRACE end
    end

    setup(function()
        for _, k in ipairs(TOUCHED) do saved[k] = _G[k] end
        _G.AltArmy = _G.AltArmy or {}
        for _, k in ipairs(MODULES) do savedModules[k] = AltArmy[k] end
        _G.CreateFrame = function()
            return { SetScript = function() end, RegisterEvent = function() end }
        end
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        require("GuildShareProtocol")
        require("GuildShareData")
        require("GuildManualGroups")
        package.loaded["GuildLinkRead"] = nil
        require("GuildLinkRead")
        -- The real roster readers (the classic roster, else the Club API's), behind the Comm stub below.
        require("GuildShareComm")
        rosterRows = AltArmy.GuildShareComm.GuildRosterRows
        clubRosterRows = AltArmy.GuildShareComm.ClubRosterRows
        GLR = AltArmy.GuildLinkRead
        GSD = AltArmy.GuildShareData
        GMG = AltArmy.GuildManualGroups
        P = AltArmy.GuildShareProtocol
        assert.truthy(GLR)
    end)

    teardown(function()
        for _, k in ipairs(TOUCHED) do _G[k] = saved[k] end
        for _, k in ipairs(MODULES) do AltArmy[k] = savedModules[k] end
    end)

    before_each(function()
        GLR._ResetForTests()
        GLR.TRY_OTHER_SERVERS = false
        _G.AltArmyTBC_GuildData = nil
        GSD._Ensure()
        GMG._Ensure()
        timers, clock = {}, 0
        enqueued, logs, requested, notified, rosterCalls = {}, {}, {}, 0, 0
        _G.time = function() return NOW + clock end
        _G.C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { at = clock + seconds, fn = fn } end }
        R = {
            CanRunGuildReads = function() return true end,
            JobTag = function(guid, skillLine) return guid .. "|" .. skillLine end,
            IsQueued = function(tag)
                for _, j in ipairs(enqueued) do
                    if not j.done and j.tag == tag then return true end
                end
                return false
            end,
            Enqueue = function(j)
                j.tag = tagOf(j)
                if R.IsQueued(j.tag) then return false end
                enqueued[#enqueued + 1] = j
                return true
            end,
            CancelWhere = function(pred)
                local n = 0
                for _, j in ipairs(enqueued) do
                    if not j.done and pred(j) then
                        j.done, j.cancelled = true, true
                        n = n + 1
                    end
                end
                return n
            end,
            Promote = function(tag, priority)
                for _, j in ipairs(enqueued) do
                    if not j.done and j.tag == tag then
                        j.priority = priority
                        return true
                    end
                end
                return false
            end,
        }
        AltArmy.OwnRecipeRead = R
        AltArmy.Debug = { LogGuildShare = function(m) logs[#logs + 1] = m end }
        _G.C_Club, _G.C_CreatureInfo = nil, nil
        AltArmy.GuildShareComm = {
            GuildRosterRows = rosterRows,
            ClubRosterRows = clubRosterRows,
            NotifyDataChanged = function() notified = notified + 1 end,
            RequestRecipesForCharacter = function(name, realm, sender, guid)
                requested[#requested + 1] = { name = name, realm = realm, sender = sender, guid = guid }
                return true
            end,
        }
        AltArmy.GuildShareSettings = { _CurrentRealm = function() return "R" end }
        roster = {
            { name = "Alice-Realm", level = 60, classFile = "MAGE", online = true, guid = "Player-5-A" },
            { name = "Bob", level = 30, classFile = "WARRIOR", online = true, guid = "Player-5-B" },
            { name = "Carl", level = 60, classFile = "ROGUE", online = false, guid = "Player-5-C" },
            { name = "Dana", level = 60, classFile = "DRUID", online = true, guid = "Player-7-D" },
        }
        _G.IsInGuild = function() return true end
        _G.GetNumGuildMembers = function() return #roster end
        _G.GetGuildRosterInfo = function(i)
            local r = roster[i]
            return r.name, nil, nil, r.level, nil, nil, nil, nil, r.online, nil, r.classFile,
                nil, nil, nil, nil, nil, r.guid
        end
        _G.UnitGUID = function() return "Player-5-ME" end
        _G.GetGuildInfo = function() return "G" end
        _G.GetRealmName = function() return "R" end
        _G.canaccessvalue = nil
        _G.GuildRoster = function() rosterCalls = rosterCalls + 1 end
        _G.C_GuildInfo = nil
    end)

    describe("the roster", function()
        it("tells players on the same server apart from the rest", function()
            assert.is_true(GLR.SameServer("Player-5-A", "Player-5-B"))
            assert.is_false(GLR.SameServer("Player-7-A", "Player-5-B"))
            assert.is_true(GLR.SameServer("Something-else", "Player-5-B"))
        end)

        it("lists online members with a usable GUID on this server", function()
            local members, skipped = GLR.CollectOnlineMembers()
            assert.are.equal(2, #members)
            assert.are.equal("Alice", members[1].name)
            assert.are.equal("Alice-Realm", members[1].fullName)
            assert.are.equal("Player-5-A", members[1].guid)
            assert.are.equal(60, members[1].level)
            assert.are.equal("MAGE", members[1].classFile)
            assert.are.equal("Bob", members[2].name)
            assert.are.equal(1, skipped.otherServer)
            assert.are.equal(0, skipped.noGuid)
        end)

        it("reads the Club API's members when the classic roster stays empty (WoW Forever)", function()
            roster = {}
            local members = {
                [11] = { name = "Alice", guid = "Player-5-A", level = 60, classID = 8, presence = 1 },
                [12] = { name = "Bob", guid = "Player-5-B", level = 30, classID = 1, presence = 2 },
                [13] = { name = "Carl", guid = "Player-5-C", level = 60, classID = 4, presence = 4 },
                [14] = { name = "Me", guid = "Player-5-ME", level = 60, classID = 8, presence = 1, isSelf = true },
            }
            _G.C_Club = {
                GetGuildClubId = function() return "club-1" end,
                GetClubMembers = function(clubId)
                    assert.are.equal("club-1", clubId)
                    return { 11, 12, 13, 14 }
                end,
                GetMemberInfo = function(_, id) return members[id] end,
            }
            _G.C_CreatureInfo = {
                GetClassInfo = function(id) return { classFile = ({ [1] = "WARRIOR", [4] = "ROGUE", [8] = "MAGE" })[id] } end,
            }
            local online, skipped = GLR.CollectOnlineMembers()
            assert.are.equal("club", skipped.source)
            assert.are.equal(3, skipped.total)
            assert.are.equal(2, #online)
            assert.are.equal("Alice", online[1].name)
            assert.are.equal("MAGE", online[1].classFile)
            assert.are.equal(60, online[1].level)
            assert.are.equal("Carl", online[2].name)
        end)

        it("tries members on another server last when TRY_OTHER_SERVERS is on, without pausing for them", function()
            GLR.TRY_OTHER_SERVERS = true
            local members, skipped = GLR.CollectOnlineMembers()
            assert.are.equal(3, #members)
            assert.are.equal(1, skipped.otherServer)
            assert.is_true(members[3].otherServer)
            seenBefore()
            roster[4].guid = "Player-7-D"
            GLR._State().seen["Player-7-D"] = NOW - GLR.PRESENCE_GRACE
            GLR.RunPass("test")
            local all = queued()
            assert.are.equal(24, #all)
            for i = 17, 24 do assert.are.equal("Player-7-D", all[i].guid) end
            local dana = job("Player-7-D", 185)
            dana.onStart(2550)
            assert.is_true(hasLog("LINK start Dana (other server) [Player-7-D] cooking"))
            finish(job("Player-7-D", 185), "timeout", nil, 3)
            finish(job("Player-7-D", 129), "timeout", nil, 3)
            assert.are.equal(0, #queued("Player-7-D"))
            assert.are.equal(0, GLR._State().timeouts)
            assert.is_false(hasLog("LINK pause"))
            assert.is_true(hasLog("LINK unreachable Dana"))
        end)

        it("passes over values the client keeps secret", function()
            _G.canaccessvalue = function(v) return v ~= "Player-5-B" end
            local members, skipped = GLR.CollectOnlineMembers()
            assert.are.equal(1, #members)
            assert.are.equal(1, skipped.noGuid)
        end)
    end)

    describe("planning", function()
        it("probes an unknown member line by line, Cooking and First Aid first for everyone", function()
            seenBefore()
            local jobs, summary = GLR.PlanJobs(GLR.CollectOnlineMembers(), "R", NOW, GLR._State())
            assert.are.equal(16, #jobs)
            assert.are.equal(2, summary.members)
            assert.are.equal(0, summary.shared)
            local first = {}
            for i = 1, 4 do first[i] = jobs[i].name .. " " .. jobs[i].key end
            assert.are.same({ "Alice cooking", "Alice firstAid", "Bob cooking", "Bob firstAid" }, first)
            assert.is_true(jobs[1].reachability)
            assert.is_false(jobs[5].reachability)
            assert.are.equal("probe", jobs[5].reason)
        end)

        it("gives a member just seen online time to announce the addon", function()
            local st = GLR._State()
            st.seen["Player-5-A"] = NOW
            st.seen["Player-5-B"] = NOW - GLR.PRESENCE_GRACE
            local jobs, summary = GLR.PlanJobs(GLR.CollectOnlineMembers(), "R", NOW, st)
            assert.are.equal(8, #jobs)
            assert.are.equal("Bob", jobs[1].name)
            assert.are.equal(1, summary.graced)
        end)

        it("leaves a member who shares through Alt Army to the guild share messages", function()
            seenBefore()
            GSD.SaveCharCard("Bob", P.ParseCharCard({
                v = 2, from = "Player-5-B", name = "Bob", guid = "Player-5-B", ch = 1,
                profs = { { key = "tailoring", rank = 100, count = 3, rv = 7 } },
            }), "G", "R")
            local jobs, summary = GLR.PlanJobs(GLR.CollectOnlineMembers(), "R", NOW, GLR._State())
            assert.are.equal(1, summary.shared)
            assert.are.equal(8, #jobs)
            for _, j in ipairs(jobs) do assert.are.equal("Alice", j.name) end
        end)

        it("re-reads a member read before without probing their reachability again", function()
            seenBefore()
            GSD.SaveLinkRead("R", {
                guid = "Player-5-A", name = "Alice", guildName = "G", profKey = "tailoring", skillLine = 197,
                ids = { 1 }, readAt = NOW - GSD.LINK_REREAD_SEC,
            })
            local jobs = GLR.PlanJobs({ GLR.CollectOnlineMembers()[1] }, "R", NOW, GLR._State())
            assert.are.equal(8, #jobs)
            assert.are.equal("tailoring", jobs[1].key)
            assert.are.equal("stale", jobs[1].reason)
            assert.are.equal("cooking", jobs[2].key)
            assert.is_false(jobs[2].reachability)
        end)
    end)

    describe("a pass", function()
        it("waits for newcomers, then queues their reads and logs the plan", function()
            GLR.RunPass("test")
            assert.are.equal(0, #enqueued)
            advance(GLR.PRESENCE_GRACE)
            assert.are.equal(16, #queued())
            assert.is_true(hasLog("LINK plan (grace over): roster 4, 3 online (0 without a GUID, 1 on another server); "
                .. "16 read(s) for 2 member(s), 0 shared, 0 waiting to announce; 16 queued, 134 budget left"))
        end)

        it("drops the reads of members gone offline", function()
            seenBefore()
            GLR.RunPass("test")
            roster[2].online = false
            GLR.RunPass("test")
            assert.are.equal(0, #queued("Player-5-B"))
            assert.are.equal(8, #queued("Player-5-A"))
        end)

        it("stops at the session budget", function()
            local budget = GLR.SESSION_BUDGET
            GLR.SESSION_BUDGET = 3
            seenBefore()
            GLR.RunPass("test")
            GLR.SESSION_BUDGET = budget
            assert.are.equal(3, #queued())
            assert.is_true(hasLog("LINK budget: 3 reads this session, stopping"))
        end)

        it("asks for the roster and looks again while the client hasn't got it, a few times", function()
            local asked = 0
            AltArmy.GuildShareComm.RequestGuildRoster = function() asked = asked + 1 return true end
            local rows = roster
            roster = {}
            GLR.RunPass("login")
            assert.are.equal(1, asked)
            assert.is_true(hasLog("LINK roster not loaded yet (login), asked the server for it; looking again in 10s (1/6)"))
            assert.is_false(hasLog("LINK plan"))
            advance(GLR.EMPTY_ROSTER_RETRY_SEC * 2)
            assert.are.equal(3, asked)
            roster = rows
            seenBefore()
            advance(GLR.EMPTY_ROSTER_RETRY_SEC)
            assert.is_true(hasLog("LINK plan (roster retry): roster 4, 3 online"))
            assert.are.equal(16, #queued())
            assert.are.equal(0, GLR._State().emptyRetries)
        end)

        it("stops asking after EMPTY_ROSTER_RETRIES and waits for a roster update", function()
            AltArmy.GuildShareComm.RequestGuildRoster = function() return true end
            roster = {}
            GLR.RunPass("login")
            advance(GLR.EMPTY_ROSTER_RETRY_SEC * (GLR.EMPTY_ROSTER_RETRIES + 2))
            assert.is_true(hasLog("LINK roster still empty after 6 tries; waiting for the next roster update"))
            assert.are.equal(0, #timers)
        end)

        it("says when the roster gives no GUIDs", function()
            _G.canaccessvalue = function(v) return not (type(v) == "string" and v:find("^Player%-")) end
            seenBefore()
            GLR.RunPass("test")
            assert.are.equal(0, #queued())
            assert.is_true(hasLog("LINK roster: 3 online member(s) without a usable GUID"))
        end)
    end)

    describe("a read's outcome", function()
        before_each(function()
            seenBefore()
            GLR.RunPass("test")
        end)

        it("is stored in the Guild tab's shape, announced and logged", function()
            local j = job("Player-5-A", 185)
            j.onStart(2550)
            assert.is_true(hasLog("LINK start Alice [Player-5-A] cooking (185) spell 2550 prio 3 reason=probe"))
            finish(j, "ok", okResult("cooking", "Cooking"), 1.2)
            local entry = GSD.GetCharacter("Player-5-A", "R")
            assert.are.equal("G", entry.guildName)
            assert.are.equal("MAGE", entry.classFile)
            assert.are.equal(60, entry.level)
            assert.is_truthy(entry.Professions.cooking.Recipes[1])
            assert.are.equal("Cooking", entry.Professions.cooking.name)
            assert.are.equal(50, entry.Professions.cooking.rank)
            assert.are.equal(1, notified)
            assert.is_true(hasLog("LINK ok Alice cooking 50/150, 2 recipes, 1.2s"))
        end)

        it("takes an empty answer as a profession they haven't got, and the member as reachable", function()
            finish(job("Player-5-A", 185), "absent", { key = "cooking" }, 0.8)
            finish(job("Player-5-A", 129), "absent", { key = "firstAid" }, 0.8)
            assert.is_true(hasLog("LINK absent Alice cooking: not one of their professions, 0.8s"))
            assert.is_nil(GLR._State().unreachable["Player-5-A"])
            assert.are.equal(6, #queued("Player-5-A"))
            assert.are.equal(0, GLR._State().timeouts)
            assert.is_true(GSD.GetLinkProbe("R", "Player-5-A", 185).absent)
        end)

        it("remembers an unanswered link and logs its backoff", function()
            finish(job("Player-5-B", 171), "timeout", nil, 3)
            assert.are.equal(1, GSD.GetLinkProbe("R", "Player-5-B", 171).misses)
            assert.is_true(hasLog("LINK timeout Bob alchemy 3.0s (miss 1, next in 1d)"))
        end)

        it("gives up on a member whose Cooking and First Aid both go unanswered, for a while", function()
            finish(job("Player-5-A", 185), "timeout", nil, 3)
            assert.are.equal(7, #queued("Player-5-A"))
            finish(job("Player-5-A", 129), "unnamed", nil, 3)
            assert.are.equal(0, #queued("Player-5-A"))
            assert.is_true(hasLog("LINK unreachable Alice: Cooking and First Aid unanswered, 6 read(s) dropped; retry in 30m"))
            GLR.RunPass("again")
            assert.are.equal(0, #queued("Player-5-A"))
            clock = GLR.UNREACHABLE_RETRY_SEC
            GLR.RunPass("later")
            assert.are.equal(6, #queued("Player-5-A"))
        end)

        it("keeps a member one of whose reachability probes answered", function()
            finish(job("Player-5-A", 185), "ok", okResult("cooking", "Cooking"), 1)
            finish(job("Player-5-A", 129), "timeout", nil, 3)
            assert.are.equal(6, #queued("Player-5-A"))
            assert.is_nil(GLR._State().unreachable["Player-5-A"])
        end)

        it("tries a window that named someone else once more", function()
            local j = job("Player-5-A", 185)
            finish(j, "wrong name", { linkedName = "Zed" }, 1)
            assert.is_true(hasLog("LINK wrong-name Alice cooking: window named Zed, trying again"))
            local again = job("Player-5-A", 185)
            assert.truthy(again)
            assert.are_not.equal(j, again)
            finish(again, "wrong name", { linkedName = "Zed" }, 1)
            assert.is_nil(job("Player-5-A", 185))
        end)

        it("pauses after unanswered links in a row, and goes on after PAUSE_SEC", function()
            finish(job("Player-5-A", 185), "timeout", nil, 3)
            finish(job("Player-5-B", 185), "timeout", nil, 3)
            assert.is_true(#queued() > 0)
            finish(job("Player-5-B", 129), "timeout", nil, 3)
            assert.are.equal(0, #queued())
            assert.is_true(hasLog("LINK pause 120s after 3 timeouts"))
            GLR.RunPass("meanwhile")
            assert.are.equal(0, #queued())
            advance(GLR.PAUSE_SEC + GLR.ROSTER_SETTLE)
            -- Bob's reachability probes both went unanswered; Alice's second never ran, so she is read.
            assert.are.equal(7, #queued("Player-5-A"))
            assert.are.equal(0, #queued("Player-5-B"))
        end)
    end)

    describe("a guildmate who shares through Alt Army", function()
        it("is never read by link: their recipes come by the guild share messages", function()
            seenBefore()
            GSD.SaveCharCard("Bob", P.ParseCharCard({
                v = 2, from = "Player-5-B", name = "Bob", guid = "Player-5-B", ch = 1,
                profs = { { key = "tailoring", rank = 100, count = 3, rv = 7 } },
            }), "G", "R")
            GLR.RunPass("test")
            assert.are.equal(0, #queued("Player-5-B"))
            assert.are.equal(8, #queued("Player-5-A"))
            assert.are.equal(0, GLR.RequestNow({ guid = "Player-5-B", realm = "R" }))
            assert.is_nil(GLR.OnPeerOnline)
        end)

        it("is read by link when their addon shares nothing (an empty presence)", function()
            seenBefore()
            GSD.SaveReceived("Bob", P.ParsePresence({ v = 2, from = "Player-5-B", chars = {} }), "G", "R")
            GLR.RunPass("test")
            assert.are.equal(8, #queued("Player-5-B"))
        end)
    end)

    describe("on demand", function()
        it("moves a member's reads to the front of the line", function()
            seenBefore()
            GLR.RunPass("test")
            assert.are.equal(8, GLR.RequestNow({ guid = "Player-5-B", realm = "R" }))
            for _, j in ipairs(queued("Player-5-B")) do assert.are.equal(GLR.PRIORITY_ON_DEMAND, j.priority) end
            for _, j in ipairs(queued("Player-5-A")) do assert.are.equal(GLR.PRIORITY_BACKGROUND, j.priority) end
        end)

        it("queues them ahead of everything when nothing was planned yet", function()
            assert.are.equal(8, GLR.RequestNow({ guid = "Player-5-A", realm = "R" }))
            assert.are.equal(GLR.PRIORITY_ON_DEMAND, queued("Player-5-A")[1].priority)
            assert.are.equal(0, GLR.RequestNow({ guid = "Player-5-C", realm = "R" }))
        end)
    end)

    describe("events", function()
        it("polls the roster after login and then regularly", function()
            GLR.OnEvent("PLAYER_ENTERING_WORLD", true, false)
            advance(GLR.LOGIN_DELAY - 1)
            assert.are.equal(0, rosterCalls)
            advance(1)
            assert.are.equal(1, rosterCalls)
            advance(GLR.ROSTER_POLL)
            assert.are.equal(2, rosterCalls)
        end)

        it("runs one pass once roster updates settle", function()
            seenBefore()
            GLR.OnEvent("GUILD_ROSTER_UPDATE")
            GLR.OnEvent("GUILD_ROSTER_UPDATE")
            advance(GLR.ROSTER_SETTLE)
            local plans = 0
            for _, line in ipairs(logs) do if line:find("LINK plan", 1, true) then plans = plans + 1 end end
            assert.are.equal(1, plans)
        end)

        it("drops every queued read on leaving the guild", function()
            seenBefore()
            GLR.RunPass("test")
            GLR.OnEvent("PLAYER_GUILD_UPDATE")
            assert.are.equal(0, #queued())
        end)
    end)
end)
