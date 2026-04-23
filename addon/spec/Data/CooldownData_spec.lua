--[[ Unit tests for CooldownData.lua — run: npm test ]]

describe("CooldownData", function()
    local CD

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.AltArmyTBC_Options = {}
        _G.AltArmyTBC_Data = _G.AltArmyTBC_Data or {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        require("CooldownData")
        CD = AltArmy.CooldownData
        assert.truthy(CD)
    end)

    before_each(function()
        CD.ResetCooldownOptionsToDefaults()
        -- Same structure as in-game: filled when tradeskill/craft APIs run (see DataStoreProfessions).
        _G.AltArmyTBC_Data.RecipeReagents = {
            [29688] = { { 22452, 1 }, { 21885, 1 }, { 21884, 1 }, { 22451, 1 } },
            [33358] = { { 22450, 1 } },
        }
    end)

    local function mockDS(realmTable)
        return {
            GetRealms = function()
                return { TestRealm = true }
            end,
            GetCharacters = function(_self, realm)
                return realmTable[realm] or {}
            end,
        }
    end

    it("BuildRows omits hidden categories", function()
        AltArmyTBC_Options.cooldowns.categories.spellcloth.hide = true
        local char = {
            name = "A",
            Professions = { Tailoring = { Recipes = { [31373] = { color = 1 } } } },
        }
        local ds = mockDS({ TestRealm = { X = char } })
        local rows = CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000)
        local found = false
        for _, r in ipairs(rows) do
            if r.categoryKey == "spellcloth" then found = true end
        end
        assert.is_false(found)
    end)

    it("BuildRows includes transmute when recipe in set", function()
        local char = {
            name = "T",
            Professions = { Alchemy = { Recipes = { [29688] = { color = 1 } } } },
        }
        local ds = mockDS({ TestRealm = { P = char } })
        local rows = CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000)
        assert.is_true(#rows >= 1)
        assert.are.equal("transmute", rows[1].categoryKey)
    end)

    it("ResolveEffectiveSpellId uses per-character preferred transmute when known", function()
        local char = {
            preferredTransmuteSpellId = 17187,
            Professions = {
                Alchemy = { Recipes = { [29688] = { color = 1 }, [17187] = { color = 1 } } },
            },
        }
        local sid = CD.ResolveEffectiveSpellId("transmute", char, AltArmyTBC_Options.cooldowns)
        assert.are.equal(17187, sid)
    end)

    it("ResolveTransmuteSpellForCharacter uses automatic primal then arcanite order", function()
        local primalOnly = {
            Professions = { Alchemy = { Recipes = { [29688] = {} } } },
        }
        assert.are.equal(29688, CD.ResolveTransmuteSpellForCharacter(primalOnly))

        local arcaniteOnly = {
            Professions = { Alchemy = { Recipes = { [17187] = {} } } },
        }
        assert.are.equal(17187, CD.ResolveTransmuteSpellForCharacter(arcaniteOnly))

        local neither = {
            Professions = { Alchemy = { Recipes = { [28566] = {} } } },
        }
        assert.is_nil(CD.ResolveTransmuteSpellForCharacter(neither))
    end)

    it("ResolveTransmuteSpellForCharacter prefers last cast before primal fallback", function()
        local char = {
            lastTransmute = { spellId = 28566 },
            Professions = { Alchemy = { Recipes = { [28566] = {}, [29688] = {} } } },
        }
        assert.are.equal(28566, CD.ResolveTransmuteSpellForCharacter(char))
    end)

    it("ResolveTransmuteSpellForCharacter skips unknown last cast", function()
        local char = {
            lastTransmute = { spellId = 28566 },
            Professions = { Alchemy = { Recipes = { [29688] = {} } } },
        }
        assert.are.equal(29688, CD.ResolveTransmuteSpellForCharacter(char))
    end)

    it("ResolveTransmuteSpellForCharacter preferred overrides last", function()
        local char = {
            preferredTransmuteSpellId = 29688,
            lastTransmute = { spellId = 28566 },
            Professions = {
                Alchemy = { Recipes = { [29688] = {}, [28566] = {} } },
            },
        }
        assert.are.equal(29688, CD.ResolveTransmuteSpellForCharacter(char))
    end)

    it("RecordSuccessfulTransmuteCast saves known transmute spell ids", function()
        local char = {}
        CD.RecordSuccessfulTransmuteCast(char, 29688)
        assert.are.equal(29688, char.lastTransmute and char.lastTransmute.spellId)
    end)

    it("RecordSuccessfulTransmuteCast ignores non-transmute spells", function()
        local char = {}
        CD.RecordSuccessfulTransmuteCast(char, 999999)
        assert.is_nil(char.lastTransmute)
    end)

    it("TransmuteCategoryDisplayTitle takes text after Transmute colon", function()
        local function gsi()
            return "Alchemy: Transmute: Primal Might"
        end
        assert.are.equal("Primal Might", CD.TransmuteCategoryDisplayTitle(29688, gsi))
        assert.are.equal(
            "Primal Earth to Water",
            CD.TransmuteCategoryDisplayTitle(1, function()
                return "Transmute: Primal Earth to Water"
            end)
        )
    end)

    it("BuildRows sets transmute categoryTitle from spell name", function()
        local oldGi = _G.GetSpellInfo
        _G.GetSpellInfo = function(spellId)
            if spellId == 29688 then
                return "Transmute: Primal Might"
            end
            return oldGi and oldGi(spellId)
        end
        local char = {
            name = "T",
            Professions = { Alchemy = { Recipes = { [29688] = { color = 1 } } } },
        }
        local ds = mockDS({ TestRealm = { P = char } })
        local rows = CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000)
        _G.GetSpellInfo = oldGi
        assert.is_true(#rows >= 1)
        assert.are.equal("Primal Might", rows[1].categoryTitle)
    end)

    it("BuildRows omits transmute when automatic and neither Primal Might nor Arcanite known", function()
        local char = {
            name = "NoMeta",
            Professions = { Alchemy = { Recipes = { [28566] = { color = 1 } } } },
        }
        local ds = mockDS({ TestRealm = { P = char } })
        local rows = CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000)
        for _, r in ipairs(rows) do
            assert.are_not.equal("transmute", r.categoryKey)
        end
    end)

    it("CharacterHasReagents respects counts", function()
        local char = {}
        local function count(_ch, itemId)
            if itemId == 22450 then return 3 end
            return 0
        end
        local ok = CD.CharacterHasReagents(char, 33358, count)
        assert.is_true(ok)
        local bad = CD.CharacterHasReagents(char, 33358, function()
            return 0
        end)
        assert.is_false(bad)
    end)

    it("EnsureCooldownOptions sets list sort key and ascending flag", function()
        CD.EnsureCooldownOptions()
        assert.are.equal("recipe", AltArmyTBC_Options.cooldowns.listSortKey)
        assert.is_true(AltArmyTBC_Options.cooldowns.listSortAscending)
        AltArmyTBC_Options.cooldowns.listSortKey = "invalid"
        CD.EnsureCooldownOptions()
        assert.are.equal("recipe", AltArmyTBC_Options.cooldowns.listSortKey)
    end)

    it("GetMaxCraftableQuantity is minimum over reagents", function()
        local char = {}
        local counts = {
            [22452] = 7,
            [21885] = 99,
            [21884] = 99,
            [22451] = 99,
        }
        local function count(_ch, itemId)
            return counts[itemId] or 0
        end
        local q = CD.GetMaxCraftableQuantity(char, 29688, count)
        assert.are.equal(7, q)
    end)

    it("EvaluateAlerts fires available once until cooldown resumes", function()
        local char = {
            name = "Z",
            Professions = { Alchemy = { Recipes = { [29688] = { color = 1 } } } },
            ProfCooldownExpiry = { [29688] = { expiresAtUnix = 500 } },
        }
        local ds = mockDS({ TestRealm = { Z = char } })
        local state = {}
        local a1 = CD.EvaluateAlerts(ds, AltArmyTBC_Options.cooldowns, 600, state)
        assert.are.equal(1, #a1)
        local a2 = CD.EvaluateAlerts(ds, AltArmyTBC_Options.cooldowns, 601, state)
        assert.are.equal(0, #a2)
        char.ProfCooldownExpiry[29688] = { expiresAtUnix = 700 }
        local a3 = CD.EvaluateAlerts(ds, AltArmyTBC_Options.cooldowns, 650, state)
        assert.are.equal(0, #a3)
        local a4 = CD.EvaluateAlerts(ds, AltArmyTBC_Options.cooldowns, 750, state)
        assert.are.equal(1, #a4)
    end)

    it("BuildRows omits salt shaker without Leatherworking/item", function()
        local oldGi = _G.GetSpellInfo
        _G.GetSpellInfo = function(spellId)
            if spellId == 2108 then return "Leatherworking" end
            return oldGi and oldGi(spellId)
        end
        local char = {
            name = "SaltTest",
            Professions = {
                Engineering = { Recipes = { [19567] = {} }, rank = 375 },
            },
        }
        local ds = mockDS({ TestRealm = { SaltTest = char } })
        ds.GetContainerItemCount = function(_self, _ch, _itemId)
            return 0
        end
        local rows = CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000)
        _G.GetSpellInfo = oldGi
        for _, r in ipairs(rows) do
            assert.are_not.equal("salt_shaker", r.categoryKey)
        end
    end)

    it("BuildRows includes salt shaker with LW 250 and Salt Shaker item", function()
        local oldGi = _G.GetSpellInfo
        _G.GetSpellInfo = function(spellId)
            if spellId == 2108 then return "Leatherworking" end
            return oldGi and oldGi(spellId)
        end
        local char = {
            name = "SaltOk",
            Professions = {
                Leatherworking = { Recipes = {}, rank = 250 },
            },
        }
        local ds = mockDS({ TestRealm = { SaltOk = char } })
        ds.GetContainerItemCount = function(_self, _ch, itemId)
            return itemId == CD.SALT_SHAKER_ITEM_ID and 1 or 0
        end
        local rows = CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000)
        _G.GetSpellInfo = oldGi
        local found = false
        for _, r in ipairs(rows) do
            if r.categoryKey == "salt_shaker" then
                found = true
                assert.are.equal(CD.SALT_SHAKER_COOLDOWN_SPELL_ID, r.spellId)
            end
        end
        assert.is_true(found)
    end)

    it("CollectAccountKnownTransmuteSpellIds dedupes", function()
        _G.AltArmyTBC_Data = {
            Characters = {
                R1 = {
                    A = { Professions = { Alchemy = { Recipes = { [29688] = {} } } } },
                },
                R2 = {
                    B = { Professions = { Alchemy = { Recipes = { [29688] = {} } } } },
                },
            },
        }
        local ids = CD.CollectAccountKnownTransmuteSpellIds(_G.AltArmyTBC_Data, nil)
        assert.are.equal(1, #ids)
        assert.are.equal(29688, ids[1])
    end)
end)
