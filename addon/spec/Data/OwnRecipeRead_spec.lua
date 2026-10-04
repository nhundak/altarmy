--[[ Unit tests for OwnRecipeRead.lua (reading the player's own recipes through a trade link) — run: npm test ]]

describe("OwnRecipeRead", function()
    local R, DS
    local timers, links, closes, combat, panel, chatActive
    local frame, otherAddonFrame, registered
    local profs, spellbook
    local saved = {}
    local TOUCHED = {
        "C_Timer", "UnitGUID", "UnitName", "GetRealmName", "GetProfessions", "GetProfessionInfo", "C_SpellBook",
        "C_TradeSkillUI", "GetNumTradeSkills", "GetTradeSkillLine", "InCombatLockdown", "GetUIPanel",
        "ProfessionsFrame", "GetFramesRegisteredForEvent", "ChatEdit_GetActiveWindow", "CreateFrame", "UIParent",
        "AltArmyTBC_Options", "AltArmyTBC_Data", "time",
    }

    local clock = 0

    --- Move the clock `seconds` on, running each timer that comes due (and those they queue) in time order.
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

    --- A fake frame that records its event registrations and runs hooked OnShow/OnHide scripts.
    local function newFrame(name)
        local f = { name = name, shown = false, alpha = 1, scale = 1, mouse = true, hooks = {}, events = {} }
        function f:HookScript(script, fn)
            self.hooks[script] = self.hooks[script] or {}
            table.insert(self.hooks[script], fn)
        end
        local function run(self, script)
            for _, fn in ipairs(self.hooks[script] or {}) do fn(self) end
        end
        function f:Show() if not self.shown then self.shown = true; run(self, "OnShow") end end
        function f:Hide() if self.shown then self.shown = false; run(self, "OnHide") end end
        function f:IsShown() return self.shown end
        function f:SetAlpha(a) self.alpha = a end
        function f:GetAlpha() return self.alpha end
        function f:SetScale(s) self.scale = s end
        function f:GetScale() return self.scale end
        function f:EnableMouse(on) self.mouse = on end
        function f:IsMouseEnabled() return self.mouse end
        function f:GetParent() return nil end
        function f:RegisterEvent(event) self.events[event] = true end
        function f:UnregisterEvent(event) self.events[event] = nil end
        f.events.TRADE_SKILL_SHOW = true
        return f
    end

    local function lastLink() return links[#links] end

    --- The server's answer to a read: the window opens (unless silenced) and the DataStore scan stores it.
    local function reply(professionName)
        if frame.events.TRADE_SKILL_SHOW then frame:Show() end
        R.OnRecipesScanned(professionName)
    end

    local function login()
        R.OnEvent("PLAYER_ENTERING_WORLD", true, false)
        advance(R.LOGIN_DELAY)
    end

    setup(function()
        for _, k in ipairs(TOUCHED) do saved[k] = _G[k] end
        _G.AltArmy = _G.AltArmy or {}
        _G.AltArmyTBC_Data = { Characters = {} }
        _G.CreateFrame = function()
            return { SetScript = function() end, RegisterEvent = function() end }
        end
        _G.UIParent = {}
        require("DataStore")
        require("DataStoreItemSpellCompat")
        require("CooldownData")
        require("DataStoreProfessions")
        package.loaded["OwnRecipeRead"] = nil
        require("OwnRecipeRead")
        R = AltArmy.OwnRecipeRead
        DS = AltArmy.DataStore
        assert.truthy(R)
    end)

    teardown(function()
        for _, k in ipairs(TOUCHED) do _G[k] = saved[k] end
    end)

    before_each(function()
        R._ResetForTests()
        timers, links, closes, combat, panel, chatActive = {}, {}, 0, false, nil, nil
        _G.AltArmyTBC_Options = nil
        _G.AltArmyTBC_Data = { Characters = {} }
        DS.accountData = _G.AltArmyTBC_Data
        _G.time = function() return 1000 end
        clock = 0
        _G.C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { at = clock + seconds, fn = fn } end }
        _G.UnitGUID = function(unit) if unit == "player" then return "Player-1-ABC" end end
        _G.UnitName = function() return "Me" end
        _G.GetRealmName = function() return "Realm" end
        -- Slots: 1 Tailoring, 2 Mining (its first spellbook spell is Find Minerals), 5 Cooking (rank 0).
        profs = {
            [1] = { name = "Tailoring", rank = 150, max = 225, numSpells = 1, offset = 10, line = 197 },
            [2] = { name = "Mining", rank = 75, max = 150, numSpells = 2, offset = 20, line = 186 },
            [5] = { name = "Cooking", rank = 0, max = 75, numSpells = 1, offset = 30, line = 185 },
        }
        spellbook = { [11] = 3908, [21] = 2580, [22] = 2656, [31] = 2550 }
        _G.GetProfessions = function() return 1, 2, nil, nil, 5, nil end
        _G.GetProfessionInfo = function(i)
            local p = profs[i]
            if not p then return nil end
            return p.name, "icon", p.rank, p.max, p.numSpells, p.offset, p.line
        end
        _G.C_SpellBook = {
            GetSpellBookItemInfo = function(slot)
                return spellbook[slot] and { spellID = spellbook[slot] } or nil
            end,
        }
        _G.GetNumTradeSkills, _G.GetTradeSkillLine = nil, nil
        frame = newFrame("ProfessionsFrame")
        otherAddonFrame = newFrame("SomeAddonFrame")
        registered = { frame, _G.UIParent, otherAddonFrame }
        _G.UIParent.RegisterEvent = function(self, event) self.tradeSkillShow = event == "TRADE_SKILL_SHOW" or nil end
        _G.UIParent.UnregisterEvent = function(self) self.tradeSkillShow = nil end
        _G.UIParent.tradeSkillShow = true
        _G.ProfessionsFrame = frame
        _G.C_TradeSkillUI = {
            GetAllRecipeIDs = function() return {} end,
            GetBaseProfessionInfo = function() return { professionName = "Tailoring" } end,
            GetRecipeInfo = function() return nil end,
            CloseTradeSkill = function()
                closes = closes + 1
                frame:Hide()
            end,
        }
        _G.GetFramesRegisteredForEvent = function() return unpack(registered) end
        _G.InCombatLockdown = function() return combat end
        _G.GetUIPanel = function() return panel end
        _G.ChatEdit_GetActiveWindow = function() return chatActive end
        _G.CreateFrame = function(kind)
            if kind == "GameTooltip" then
                return {
                    SetOwner = function() end,
                    Hide = function() end,
                    SetHyperlink = function(_, link) links[#links + 1] = link end,
                }
            end
            return { SetScript = function() end, RegisterEvent = function() end }
        end
    end)

    describe("when it runs", function()
        it("is on by default and can be turned off", function()
            assert.is_true(R.IsEnabled())
            R.SetEnabled(false)
            assert.is_false(R.IsEnabled())
            assert.is_false(AltArmyTBC_Options.autoReadRecipes)
            R.SetEnabled(true)
            assert.is_true(R.IsEnabled())
        end)

        it("reads the first profession after login, with a trade link to the player", function()
            R.OnEvent("PLAYER_ENTERING_WORLD", true, false)
            advance(R.LOGIN_DELAY - 1)
            assert.are.equal(0, #links)
            advance(1)
            assert.are.same({ "trade:Player-1-ABC:3908:197" }, links)
        end)

        it("reads after a UI reload but not after zoning", function()
            R.OnEvent("PLAYER_ENTERING_WORLD", false, false)
            advance(60)
            assert.are.equal(0, #links)
            R.OnEvent("PLAYER_ENTERING_WORLD", false, true)
            advance(R.LOGIN_DELAY)
            assert.are.equal(1, #links)
        end)

        it("does nothing when turned off", function()
            R.SetEnabled(false)
            login()
            advance(60)
            assert.are.equal(0, #links)
        end)

        it("does nothing on clients with the legacy trade skill API (TBC)", function()
            _G.GetNumTradeSkills = function() return 0 end
            _G.GetTradeSkillLine = function() return "Tailoring" end
            assert.is_false(R.HasApi())
            login()
            advance(60)
            assert.are.equal(0, #links)
        end)

        it("skips professions without a rank or without a recipe window", function()
            profs[2] = { name = "Riding", rank = 75, max = 75, numSpells = 1, offset = 20, line = 762 }
            assert.are.equal(1, R.QueueAll())
        end)
    end)

    describe("a read", function()
        it("runs one profession at a time and closes the window once it is scanned", function()
            login()
            assert.are.equal(1, #links)
            advance(R.TIMEOUT - 1)
            assert.are.equal(1, #links)
            assert.is_true(R.IsReading())
            reply("Tailoring")
            assert.are.equal(1, closes)
            assert.is_false(R.IsReading())
            advance(R.GAP)
            assert.are.same({ "trade:Player-1-ABC:3908:197", "trade:Player-1-ABC:2580:186" }, links)
        end)

        it("is finished by the DataStore's own recipe scan", function()
            _G.C_TradeSkillUI.GetAllRecipeIDs = function() return { 100 } end
            _G.C_TradeSkillUI.GetRecipeInfo = function()
                return { name = "Bolt of Linen Cloth", learned = true, relativeDifficulty = 0 }
            end
            login()
            DS:ScanRecipes()
            assert.is_false(R.IsReading())
            local char = AltArmyTBC_Data.Characters.Realm["Player-1-ABC"]
            assert.truthy(char.Professions.Tailoring.Recipes[100])
        end)

        it("tries the profession's next spell when one gets no answer, and remembers the one that worked", function()
            login()
            reply("Tailoring")
            advance(R.GAP)
            assert.are.equal("trade:Player-1-ABC:2580:186", lastLink())
            advance(R.TIMEOUT)
            assert.are.equal(2, closes)
            advance(R.GAP)
            assert.are.equal("trade:Player-1-ABC:2656:186", lastLink())
            reply("Mining")
            advance(R.GAP)
            assert.are.equal(3, #links)

            R.Queue("Mining")
            advance(R.GAP)
            assert.are.equal("trade:Player-1-ABC:2656:186", lastLink())
        end)

        it("gives up on a profession once every spell went unanswered", function()
            login()
            advance(R.TIMEOUT)
            assert.is_false(R.IsReading())
            advance(R.GAP)
            assert.are.equal("trade:Player-1-ABC:2580:186", lastLink())
            advance(R.TIMEOUT + R.GAP)
            assert.are.equal("trade:Player-1-ABC:2656:186", lastLink())
            advance(60)
            assert.are.equal(3, #links)
            assert.is_false(R.IsReading())
        end)
    end)

    describe("waiting its turn", function()
        local function blockedThenFreed(block, free)
            block()
            login()
            assert.are.equal(0, #links)
            advance(R.RETRY)
            assert.are.equal(0, #links)
            free()
            advance(R.RETRY)
            assert.are.equal(1, #links)
        end

        it("waits out combat", function()
            blockedThenFreed(function() combat = true end, function() combat = false end)
        end)

        it("waits while another panel is open", function()
            blockedThenFreed(function() panel = {} end, function() panel = nil end)
        end)

        it("waits while the player has a profession window open", function()
            blockedThenFreed(function() frame:Show() end, function() frame:Hide() end)
        end)

        it("waits while the player is typing", function()
            blockedThenFreed(function() chatActive = {} end, function() chatActive = nil end)
        end)

        it("waits until the client knows the player's GUID", function()
            local guid = _G.UnitGUID
            blockedThenFreed(function() _G.UnitGUID = function() return nil end end,
                function() _G.UnitGUID = guid end)
        end)

        it("stops for combat mid-read and tries again afterwards", function()
            login()
            frame:Show()
            combat = true
            R.OnEvent("PLAYER_REGEN_DISABLED")
            assert.is_false(R.IsReading())
            assert.are.equal(1, closes)
            assert.are.equal(1, frame.alpha)
            assert.is_true(frame.events.TRADE_SKILL_SHOW)
            combat = false
            advance(R.RETRY)
            assert.are.same({ "trade:Player-1-ABC:3908:197", "trade:Player-1-ABC:3908:197" }, links)
        end)
    end)

    describe("staying out of sight", function()
        it("silences only Blizzard's profession window while reading", function()
            login()
            assert.is_nil(frame.events.TRADE_SKILL_SHOW)
            assert.is_nil(_G.UIParent.tradeSkillShow)
            assert.is_true(otherAddonFrame.events.TRADE_SKILL_SHOW)
            reply("Tailoring")
            assert.is_true(frame.events.TRADE_SKILL_SHOW)
            assert.is_true(_G.UIParent.tradeSkillShow)
        end)

        it("gives the window back after a read that got no answer", function()
            login()
            advance(R.TIMEOUT)
            assert.is_true(frame.events.TRADE_SKILL_SHOW)
        end)

        it("gives the window back at logout", function()
            login()
            R.OnEvent("PLAYER_LOGOUT")
            assert.is_true(frame.events.TRADE_SKILL_SHOW)
        end)

        it("hides the window if it opens anyway, and restores it on close", function()
            login()
            frame:Show()
            assert.are.equal(0, frame.alpha)
            assert.is_true(frame.scale < 0.1)
            assert.is_false(frame.mouse)
            R.OnRecipesScanned("Tailoring")
            assert.is_false(frame.shown)
            assert.are.equal(1, frame.alpha)
            assert.are.equal(1, frame.scale)
            assert.is_true(frame.mouse)
        end)

        it("leaves a window the player opens alone", function()
            frame:Show()
            assert.are.equal(1, frame.alpha)
        end)
    end)

    describe("only stale professions", function()
        local function professions(entries)
            local char = DS._GetCurrentCharTable()
            char.Professions = entries
            return char
        end
        local recipes = { [100] = { color = 1 } }

        it("reads nothing at login when every profession has its recipes", function()
            professions({
                Tailoring = { rank = 150, Recipes = recipes },
                Mining = { rank = 75, Recipes = recipes },
            })
            assert.are.equal(0, R.QueueAll())
            login()
            advance(60)
            assert.are.equal(0, #links)
        end)

        it("reads a profession marked stale, and only that one", function()
            local char = professions({
                Tailoring = { rank = 150, Recipes = recipes },
                Mining = { rank = 75, Recipes = recipes },
            })
            char.professionsNeedingRecipeScan = { Mining = true }
            login()
            reply("Mining")
            advance(60)
            assert.are.same({ "trade:Player-1-ABC:2580:186" }, links)
        end)

        it("reads a profession with no recipes stored", function()
            professions({
                Tailoring = { rank = 150, Recipes = recipes },
                Mining = { rank = 75, Recipes = {} },
            })
            login()
            reply("Mining")
            advance(60)
            assert.are.same({ "trade:Player-1-ABC:2580:186" }, links)
        end)

        it("reads stale professions in the game's order", function()
            login()
            assert.are.same({ "trade:Player-1-ABC:3908:197" }, links)
        end)

        it("doesn't read a profession asked for by name unless it is stale", function()
            local char = professions({
                Tailoring = { rank = 150, Recipes = recipes },
                Mining = { rank = 75, Recipes = recipes },
            })
            assert.are.equal(0, R.Queue("Tailoring"))
            char.professionsNeedingRecipeScan = { Tailoring = true }
            assert.are.equal(1, R.Queue("Tailoring"))
            assert.are.same({ "trade:Player-1-ABC:3908:197" }, links)
        end)
    end)

    describe("after learning a recipe", function()
        it("reads that profession again", function()
            R.OnRecipeLearned("Mining")
            advance(R.LEARN_DELAY)
            assert.are.same({ "trade:Player-1-ABC:2580:186" }, links)
        end)

        it("reads every profession when it can't tell which", function()
            R.OnRecipeLearned(nil)
            advance(R.LEARN_DELAY)
            reply("Tailoring")
            advance(R.GAP)
            assert.are.equal(2, #links)
        end)

        it("doesn't read when the bundled recipe data stored the learned recipe", function()
            local savedRI = AltArmy.RecipeInfo
            AltArmy.RecipeInfo = {
                FindRecipeLearnInfo = function()
                    return { professionName = "Tailoring", recipeID = 200, resultItemID = 2996 }
                end,
                GetRecipe = function() return {} end,
                GetDifficulty = function() return "orange" end,
            }
            local char = DS._GetCurrentCharTable()
            char.Professions = { Tailoring = { rank = 150, maxRank = 225, Recipes = { [100] = { color = 1 } } } }
            DS:OnRecipeLearnDetected(200, nil)
            AltArmy.RecipeInfo = savedRI
            advance(60)
            assert.truthy(char.Professions.Tailoring.Recipes[200])
            assert.are.equal(0, #links)
        end)

        it("is told by the DataStore when a recipe is learned", function()
            local char = DS._GetCurrentCharTable()
            char.Professions = { Tailoring = { rank = 150, maxRank = 225, Recipes = {} } }
            DS:OnRecipeLearnDetected(nil, nil)
            advance(R.LEARN_DELAY)
            assert.are.equal(1, #links)
        end)
    end)
end)
