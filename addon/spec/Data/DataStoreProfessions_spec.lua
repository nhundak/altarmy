--[[
  Unit tests for DataStoreProfessions.lua (getters).
  Run from project root: npm test
]]

describe("DataStoreProfessions", function()
  local DS

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.AltArmyTBC_Data = _G.AltArmyTBC_Data or { Characters = {} }
    _G.CreateFrame = _G.CreateFrame or function()
      return { SetScript = function() end, RegisterEvent = function() end }
    end
    _G.UIParent = _G.UIParent or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("DataStore")
    require("CooldownData")
    require("DataStoreProfessions")
    DS = AltArmy.DataStore
  end)

  describe("GetProfessions", function()
    it("returns empty when char nil", function()
      assert.are.same({}, DS:GetProfessions(nil))
    end)
    it("returns char.Professions or empty", function()
      local profs = { Mining = { rank = 300, maxRank = 375 } }
      local char = { Professions = profs }
      assert.are.same(profs, DS:GetProfessions(char))
      assert.are.same({}, DS:GetProfessions({}))
    end)
  end)

  describe("GetProfession", function()
    it("returns nil when char or name nil", function()
      assert.is_nil(DS:GetProfession(nil, "Mining"))
      assert.is_nil(DS:GetProfession({ Professions = {} }, nil))
    end)
    it("returns profession table when present", function()
      local prof = { rank = 300, maxRank = 375 }
      local char = { Professions = { Mining = prof } }
      assert.are.same(prof, DS:GetProfession(char, "Mining"))
    end)
  end)

  describe("ResolveSpecializationLabel", function()
    it("returns the label of the first known specialization spell", function()
      local knows = function(id) return id == 28677 end -- Master of Elixirs
      assert.are.equal("Elixir", DS.ResolveSpecializationLabel("alchemy", knows))
    end)

    it("prefers the more specific specialization listed first", function()
      -- Knows both Weaponsmith (general) and Master Swordsmith (specific) -> Swordsmith wins.
      local knows = function(id) return id == 17041 or id == 9787 end
      assert.are.equal("Swordsmith", DS.ResolveSpecializationLabel("blacksmithing", knows))
    end)

    it("returns nil when no specialization spell is known", function()
      assert.is_nil(DS.ResolveSpecializationLabel("alchemy", function() return false end))
    end)

    it("returns nil for professions without specializations or bad args", function()
      assert.is_nil(DS.ResolveSpecializationLabel("mining", function() return true end))
      assert.is_nil(DS.ResolveSpecializationLabel(nil, function() return true end))
      assert.is_nil(DS.ResolveSpecializationLabel("alchemy", nil))
    end)
  end)

  describe("GetProfession1 / GetProfession2", function()
    it("returns 0, 0, nil when char nil", function()
      local r, m, n = DS:GetProfession1(nil)
      assert.are.equal(0, r)
      assert.are.equal(0, m)
      assert.is_nil(n)
    end)
    it("returns rank, maxRank, name for Prof1", function()
      local char = { Prof1 = "Mining", Professions = { Mining = { rank = 300, maxRank = 375 } } }
      local r, m, n = DS:GetProfession1(char)
      assert.are.equal(300, r)
      assert.are.equal(375, m)
      assert.are.equal("Mining", n)
    end)
    it("returns 0, 0, name when prof missing", function()
      local char = { Prof1 = "Mining", Professions = {} }
      local r, m, n = DS:GetProfession1(char)
      assert.are.equal(0, r)
      assert.are.equal(0, m)
      assert.are.equal("Mining", n)
    end)
    it("GetProfession2 returns rank, maxRank, name", function()
      local char = { Prof2 = "Herbalism", Professions = { Herbalism = { rank = 350, maxRank = 375 } } }
      local r, m, n = DS:GetProfession2(char)
      assert.are.equal(350, r)
      assert.are.equal(375, m)
      assert.are.equal("Herbalism", n)
    end)
  end)

  describe("GetNumRecipes", function()
    it("returns 0 when char or profName nil", function()
      assert.are.equal(0, DS:GetNumRecipes(nil, "Mining"))
      assert.are.equal(0, DS:GetNumRecipes({ Professions = {} }, nil))
    end)
    it("returns count of Recipes", function()
      local char = { Professions = { Mining = { Recipes = { [1] = 1, [2] = 1, [3] = 1 } } } }
      assert.are.equal(3, DS:GetNumRecipes(char, "Mining"))
    end)
    it("returns 0 when prof or Recipes missing", function()
      assert.are.equal(0, DS:GetNumRecipes({ Professions = {} }, "Mining"))
      assert.are.equal(0, DS:GetNumRecipes({ Professions = { Mining = {} } }, "Mining"))
    end)
  end)

  describe("SaveRecipeReagentsMulti", function()
    it("stores one list under every spell id key", function()
      assert.is_not_nil(DS.accountData)
      DS.accountData.RecipeReagents = {}
      DS.SaveRecipeReagentsMulti(DS, { 26751, 31373 }, { { 21840, 1 }, { 14341, 1 } })
      assert.are.same({ { 21840, 1 }, { 14341, 1 } }, DS.accountData.RecipeReagents[26751])
      assert.are.equal(DS.accountData.RecipeReagents[26751], DS.accountData.RecipeReagents[31373])
    end)
  end)

  describe("ScanTradeSkillCooldownExpiry", function()
    it("persists cooldown under cast spell id when recipe link is an item id", function()
      local oldTime = _G.time
      local oldGt = _G.GetTime
      _G.UnitName = function()
        return "TestPlayer"
      end
      _G.GetRealmName = function()
        return "TestRealm"
      end
      _G.time = function()
        return 1000
      end
      _G.GetTime = function()
        return 50
      end
      _G.GetTradeSkillLine = function()
        return "Alchemy"
      end
      _G.GetTradeSkillSelectionIndex = function()
        return 1
      end
      _G.SelectTradeSkill = function() end
      _G.ExpandAllTradeSkillHeaders = nil
      _G.GetNumTradeSkills = function()
        return 1
      end
      _G.GetTradeSkillInfo = function()
        return "Transmute: Earthstorm Diamond", "optimal"
      end
      _G.GetTradeSkillRecipeLink = function()
        return "|cff0070dd|Hitem:25868|h[Recipe: Transmute: Earthstorm Diamond]|h|r"
      end
      _G.GetTradeSkillItemLink = function()
        return "|cffa335ee|Hitem:25867|h[Earthstorm Diamond]|h|r"
      end
      _G.GetItemSpell = function(itemRef)
        if itemRef == 25868 or itemRef == 25867 then
          return "Transmute: Earthstorm Diamond", 28566
        end
        return nil
      end
      _G.GetTradeSkillCooldown = function()
        return 3600, 0
      end
      _G.GetSpellCooldown = function() end

      DS:ScanTradeSkillCooldownExpiry()

      _G.time = oldTime
      _G.GetTime = oldGt

      local char = AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.is_not_nil(char)
      assert.is_not_nil(char.ProfCooldownExpiry[28566])
      assert.is_true(char.ProfCooldownExpiry[28566].expiresAtUnix > 1000)
    end)
  end)

  describe("Cooldown expiry persistence guard", function()
    it("does not overwrite a known future expiry when scan returns (0,0)", function()
      local char = { ProfCooldownExpiry = { [123] = { expiresAtUnix = 1000 } } }
      local changed = DS._PersistCooldownExpiryForTest(char, 123, 0, 0, 0, 900, "Test")
      assert.is_false(changed)
      assert.are.equal(1000, char.ProfCooldownExpiry[123].expiresAtUnix)
    end)

    it("does overwrite when prior expiry is not meaningfully in the future", function()
      local char = { ProfCooldownExpiry = { [123] = { expiresAtUnix = 905 } } }
      local changed = DS._PersistCooldownExpiryForTest(char, 123, 0, 0, 0, 900, "Test")
      assert.is_true(changed)
      assert.are.equal(900, char.ProfCooldownExpiry[123].expiresAtUnix)
    end)
  end)

  describe("CooldownRemainingSecondsFromSpellApi", function()
    it("computes start+duration remaining for normal GetSpellCooldown values", function()
      local rem = DS._CooldownRemainingSecondsFromSpellApiForTest(50, 3600, 100, 1000)
      assert.are.equal(3550, rem)
    end)

    it("uses duration when start exceeds GetTime (corrupted multi-day CD)", function()
      -- Repro: Mindfrell Shadowcloth — start >> gt inflated remaining by ~46 days.
      local gt = 114269856
      local duration = 331200
      local start = gt + 3935573
      local rem = DS._CooldownRemainingSecondsFromSpellApiForTest(start, duration, gt, 1781451396)
      assert.are.equal(duration, rem)
    end)

    it("does not cap absurd remaining from spell cooldown math", function()
      local rem = DS._CooldownRemainingSecondsFromSpellApiForTest(50, 5000000, 100, 1000)
      assert.are.equal(4999950, rem)
    end)
  end)

  describe("CooldownRemainingSecondsFromTradeSkillApi", function()
    it("treats first return as seconds remaining", function()
      assert.are.equal(331200, DS._CooldownRemainingSecondsFromTradeSkillApiForTest(331200, 0))
    end)

    it("ignores isDayCooldown flag in second return", function()
      assert.are.equal(331200, DS._CooldownRemainingSecondsFromTradeSkillApiForTest(331200, 1))
    end)
  end)

  describe("PersistCooldownExpiry tradeskill API", function()
    it("does not overwrite future expiry when tradeskill scan returns (0,0)", function()
      local char = { ProfCooldownExpiry = { [36686] = { expiresAtUnix = 5000 } } }
      local changed = DS._PersistCooldownExpiryForTest(char, 36686, 0, 0, 50, 1000, "TradeSkill", "tradeskill")
      assert.is_false(changed)
      assert.are.equal(5000, char.ProfCooldownExpiry[36686].expiresAtUnix)
    end)

    it("persists shadowcloth duration from corrupted spell scan via duration fallback", function()
      local wall = 1781451396
      local gt = 114269856
      local duration = 331200
      local start = gt + 3935573
      local char = {}
      DS._PersistCooldownExpiryForTest(char, 36686, start, duration, gt, wall, "SpellApi", "spell")
      assert.are.equal(wall + duration, char.ProfCooldownExpiry[36686].expiresAtUnix)
    end)
  end)

  describe("ScanCraftRecipes", function()
    local scheduleCount

    before_each(function()
      scheduleCount = 0
      AltArmy.GuildShareComm = {
        ScheduleBroadcast = function()
          scheduleCount = scheduleCount + 1
        end,
      }
    end)

    after_each(function()
      AltArmy.GuildShareComm = nil
    end)

    it("calls GetCraftSkillLine with index 1 (client requires a positive index)", function()
      local oldTime = _G.time
      _G.UnitName = function()
        return "TestPlayer"
      end
      _G.GetRealmName = function()
        return "TestRealm"
      end
      local receivedIndex
      _G.GetCraftSkillLine = function(index)
        if index == nil then
          error("Usage: GetCraftSkillLine(index)")
        end
        receivedIndex = index
        return "Poisons"
      end
      _G.GetNumCrafts = function()
        return 1
      end
      _G.GetCraftInfo = function()
        return nil, nil, "optimal"
      end
      _G.GetCraftRecipeLink = function()
        return "enchant:12345"
      end
      _G.GetCraftDisplaySkillLine = function()
        return "Poisons", 340, 375
      end
      _G.time = function()
        return 0
      end
      DS:ScanCraftRecipes()
      _G.time = oldTime
      assert.are.equal(1, receivedIndex)
      local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.is_not_nil(char)
      assert.are.equal(340, char.Professions.Poisons.rank)
      assert.are.equal(375, char.Professions.Poisons.maxRank)
    end)

    it("schedules a guild-share presence broadcast after scanning craft recipes", function()
      _G.UnitName = function() return "TestPlayer" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.GetCraftSkillLine = function() return "Enchanting" end
      _G.GetNumCrafts = function() return 1 end
      _G.GetCraftInfo = function() return nil, nil, "optimal" end
      _G.GetCraftRecipeLink = function() return "enchant:7411" end
      _G.GetCraftDisplaySkillLine = function() return "Enchanting", 1, 75 end
      _G.time = function() return 0 end
      DS:ScanCraftRecipes()
      assert.are.equal(1, scheduleCount)
    end)

    it("updates trade skill rank from GetTradeSkillLine during ScanRecipes", function()
      _G.UnitName = function()
        return "TestPlayer"
      end
      _G.GetRealmName = function()
        return "TestRealm"
      end
      _G.GetTradeSkillLine = function()
        return "Alchemy", 360, 375
      end
      _G.GetNumTradeSkills = function()
        return 0
      end
      _G.time = function()
        return 0
      end
      DS:ScanRecipes()
      local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.is_not_nil(char)
      assert.are.equal(360, char.Professions.Alchemy.rank)
      assert.are.equal(375, char.Professions.Alchemy.maxRank)
    end)

    it("schedules a guild-share presence broadcast after scanning trade-skill recipes", function()
      _G.UnitName = function() return "TestPlayer" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.GetTradeSkillLine = function() return "Alchemy", 1, 75 end
      _G.GetNumTradeSkills = function() return 1 end
      _G.GetTradeSkillInfo = function() return "Minor Healing Potion", "optimal" end
      _G.GetTradeSkillRecipeLink = function()
        return "|Hitem:118:0:0:0:0:0:0:0|h[Minor Healing Potion]|h"
      end
      _G.GetTradeSkillItemLink = function() return nil end
      _G.GetTradeSkillNumReagents = function() return 0 end
      _G.time = function() return 0 end
      DS:ScanRecipes()
      assert.are.equal(1, scheduleCount)
    end)
  end)

  describe("IsRecipeKnownAnyProfession", function()
    it("returns false when spell missing", function()
      local char = { Professions = { Mining = { Recipes = { [1] = {} } } } }
      assert.is_false(DS:IsRecipeKnownAnyProfession(char, 99))
    end)
    it("returns true when any profession has recipe", function()
      local char = {
        Professions = {
          Mining = { Recipes = {} },
          Alchemy = { Recipes = { [29688] = { color = 1 } } },
        },
      }
      assert.is_true(DS:IsRecipeKnownAnyProfession(char, 29688))
    end)
  end)

  describe("IsRecipeKnown", function()
    it("returns false when char or profName or spellID nil", function()
      assert.is_false(DS:IsRecipeKnown(nil, "Mining", 123))
      assert.is_false(DS:IsRecipeKnown({ Professions = {} }, nil, 123))
      assert.is_false(DS:IsRecipeKnown({ Professions = {} }, "Mining", nil))
    end)
    it("returns true when recipe in prof.Recipes", function()
      local char = { Professions = { Mining = { Recipes = { [123] = 1 } } } }
      assert.is_true(DS:IsRecipeKnown(char, "Mining", 123))
    end)
    it("returns false when recipe not in prof.Recipes", function()
      local char = { Professions = { Mining = { Recipes = { [123] = 1 } } } }
      assert.is_false(DS:IsRecipeKnown(char, "Mining", 999))
    end)
  end)

  describe("MigrateRecipePrimaryIds", function()
    before_each(function()
      _G.AltArmyTBC_Data = {
        Characters = {},
        recipePrimaryIdsMigrated = nil,
      }
      DS.accountData = _G.AltArmyTBC_Data
    end)

    it("backfills primaryRecipeID and skips effect spell aliases", function()
      local row = { color = 1, resultItemID = 9187 }
      _G.AltArmyTBC_Data.Characters = {
        Realm1 = {
          Char1 = {
            Professions = {
              Alchemy = {
                Recipes = {
                  [11449] = row,
                  [11334] = row,
                },
              },
            },
          },
        },
      }
      _G.GetItemSpell = function(itemID)
        if itemID == 9187 then return "Agility", 11334 end
        return nil
      end
      _G.GetSpellInfo = function(id)
        if id == 11449 then return "Elixir of Agility" end
        if id == 11334 then return "Agility" end
        return nil
      end
      local updated = DS:MigrateRecipePrimaryIds()
      assert.is_true(updated > 0)
      assert.are.equal(11449, row.primaryRecipeID)
      assert.is_true(_G.AltArmyTBC_Data.recipePrimaryIdsMigrated)
    end)

    it("repairs split rows sharing resultItemID", function()
      local rowCraft = { color = 1, primaryRecipeID = 11449, resultItemID = 8949 }
      local rowEffect = { color = 1, primaryRecipeID = 11328, resultItemID = 8949 }
      _G.AltArmyTBC_Data.Characters = {
        Realm1 = {
          Char1 = {
            Professions = {
              Alchemy = {
                Recipes = {
                  [11449] = rowCraft,
                  [11328] = rowEffect,
                },
              },
            },
          },
        },
      }
      _G.GetItemSpell = function(itemID)
        if itemID == 8949 then return "Agility", 11328 end
        return nil
      end
      _G.GetSpellInfo = function(id)
        if id == 11449 then return "Elixir of Agility" end
        if id == 11328 then return "Agility" end
        return nil
      end
      local updated = DS:MigrateRecipePrimaryIds()
      assert.is_true(updated > 0)
      assert.are.equal(11449, rowCraft.primaryRecipeID)
      assert.are.equal(11449, rowEffect.primaryRecipeID)
    end)

    it("converts numeric legacy recipe rows to tables", function()
      _G.AltArmyTBC_Data.Characters = {
        Realm1 = {
          Char1 = {
            Professions = {
              Mining = { Recipes = { [12345] = 2 } },
            },
          },
        },
      }
      DS:MigrateRecipePrimaryIds()
      local row = _G.AltArmyTBC_Data.Characters.Realm1.Char1.Professions.Mining.Recipes[12345]
      assert.are.same({ color = 2, primaryRecipeID = 12345 }, row)
    end)

    it("runs only once per account", function()
      _G.AltArmyTBC_Data.Characters = {
        Realm1 = {
          Char1 = {
            Professions = {
              Alchemy = { Recipes = { [1] = { color = 1 } } },
            },
          },
        },
      }
      DS:MigrateRecipePrimaryIds()
      assert.is_true(_G.AltArmyTBC_Data.recipePrimaryIdsMigrated)
      local row = _G.AltArmyTBC_Data.Characters.Realm1.Char1.Professions.Alchemy.Recipes[1]
      row.primaryRecipeID = nil
      assert.are.equal(0, DS:MigrateRecipePrimaryIds())
      assert.is_nil(row.primaryRecipeID)
    end)

    it("runs when recipePrimaryIdsMigrated is unset", function()
      local row = { color = 1 }
      _G.AltArmyTBC_Data.Characters = {
        Realm1 = {
          Char1 = {
            Professions = {
              Alchemy = { Recipes = { [11449] = row } },
            },
          },
        },
      }
      assert.is_nil(_G.AltArmyTBC_Data.recipePrimaryIdsMigrated)
      local updated = DS:MigrateRecipePrimaryIds()
      assert.is_true(updated > 0)
      assert.are.equal(11449, row.primaryRecipeID)
      assert.is_true(_G.AltArmyTBC_Data.recipePrimaryIdsMigrated)
    end)

    it("skips immediately when recipePrimaryIdsMigrated is already true", function()
      local rowCraft = { color = 1, primaryRecipeID = 11449, resultItemID = 8949 }
      local rowEffect = { color = 1, primaryRecipeID = 11328, resultItemID = 8949 }
      _G.AltArmyTBC_Data.recipePrimaryIdsMigrated = true
      _G.AltArmyTBC_Data.Characters = {
        Realm1 = {
          Char1 = {
            Professions = {
              Alchemy = {
                Recipes = {
                  [11449] = rowCraft,
                  [11328] = rowEffect,
                },
              },
            },
          },
        },
      }
      assert.are.equal(0, DS:MigrateRecipePrimaryIds())
      assert.are.equal(11328, rowEffect.primaryRecipeID)
    end)

    it("RemigrateRecipePrimaryIdsDebug clears flag and re-runs migration", function()
      local rowCraft = { color = 1, primaryRecipeID = 11449, resultItemID = 8949 }
      local rowEffect = { color = 1, primaryRecipeID = 11328, resultItemID = 8949 }
      _G.AltArmyTBC_Data.recipePrimaryIdsMigrated = true
      _G.AltArmyTBC_Data.Characters = {
        Realm1 = {
          Char1 = {
            Professions = {
              Alchemy = {
                Recipes = {
                  [11449] = rowCraft,
                  [11328] = rowEffect,
                },
              },
            },
          },
        },
      }
      _G.GetItemSpell = function(itemID)
        if itemID == 8949 then return "Agility", 11328 end
        return nil
      end
      _G.GetSpellInfo = function(id)
        if id == 11449 then return "Elixir of Agility" end
        if id == 11328 then return "Agility" end
        return nil
      end
      local updated = DS:RemigrateRecipePrimaryIdsDebug()
      assert.is_true(updated > 0)
      assert.are.equal(11449, rowEffect.primaryRecipeID)
      assert.is_true(_G.AltArmyTBC_Data.recipePrimaryIdsMigrated)
    end)

    it("marks account migrated even when no recipe rows need changes", function()
      local row = { color = 1, primaryRecipeID = 11449 }
      _G.AltArmyTBC_Data.Characters = {
        Realm1 = {
          Char1 = {
            Professions = {
              Alchemy = { Recipes = { [11449] = row } },
            },
          },
        },
      }
      assert.are.equal(0, DS:MigrateRecipePrimaryIds())
      assert.is_true(_G.AltArmyTBC_Data.recipePrimaryIdsMigrated)
      assert.are.equal(11449, row.primaryRecipeID)
    end)
  end)

  describe("ScanProfessionLinks", function()
    local scheduleCount

    local function mockPlayer(name, realm)
      _G.UnitName = function()
        return name
      end
      _G.GetRealmName = function()
        return realm
      end
      _G.GetSpellInfo = function(id)
        if id == 3273 then return "First Aid" end
        return nil
      end
      _G.time = function()
        return 0
      end
      _G.ExpandSkillHeader = function() end
    end

    local function mockSkillLines(lines)
      _G.GetNumSkillLines = function()
        return #lines
      end
      _G.GetSkillLineInfo = function(i)
        local row = lines[i]
        if not row then return nil end
        return row.name, row.isHeader, nil, row.rank, nil, nil, row.maxRank
      end
    end

    local lastScheduleDelay

    before_each(function()
      scheduleCount = 0
      lastScheduleDelay = nil
      AltArmy.GuildShareComm = {
        PROFESSION_BROADCAST_DEBOUNCE_SEC = 30,
        ScheduleBroadcast = function(delay)
          scheduleCount = scheduleCount + 1
          lastScheduleDelay = delay
        end,
      }
      _G.AltArmyTBC_Data = { Characters = {} }
      DS.accountData = _G.AltArmyTBC_Data
      mockPlayer("TestPlayer", "TestRealm")
    end)

    after_each(function()
      AltArmy.GuildShareComm = nil
    end)

    it("schedules a longer quiet-period guild-share broadcast after profession link scans", function()
      mockSkillLines({
        { name = "Professions", isHeader = true },
        { name = "Alchemy", isHeader = false, rank = 1, maxRank = 75 },
      })
      DS:ScanProfessionLinks()
      assert.are.equal(1, scheduleCount)
      assert.are.equal(30, lastScheduleDelay)
    end)

    it("removes professions no longer present in skill lines", function()
      _G.AltArmyTBC_Data.Characters.TestRealm = {
        TestPlayer = {
          Prof1 = "Alchemy",
          Prof2 = "Herbalism",
          Professions = {
            Alchemy = { rank = 350, maxRank = 375, Recipes = { [1] = { color = 1 } } },
            Herbalism = { rank = 300, maxRank = 375, Recipes = {} },
            Tailoring = { rank = 375, maxRank = 375, Recipes = { [2] = { color = 1 } } },
          },
        },
      }
      mockSkillLines({
        { name = "Professions", isHeader = true },
        { name = "Alchemy", isHeader = false, rank = 350, maxRank = 375 },
        { name = "Herbalism", isHeader = false, rank = 300, maxRank = 375 },
      })
      DS:ScanProfessionLinks()
      local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.is_not_nil(char.Professions.Alchemy)
      assert.is_not_nil(char.Professions.Herbalism)
      assert.is_nil(char.Professions.Tailoring)
      assert.are.equal("Alchemy", char.Prof1)
      assert.are.equal("Herbalism", char.Prof2)
    end)

    it("clears stale primary professions when the character has none trained", function()
      _G.AltArmyTBC_Data.Characters.TestRealm = {
        TestPlayer = {
          Prof1 = "Tailoring",
          Professions = {
            Tailoring = { rank = 375, maxRank = 375, Recipes = { [1] = { color = 1 } } },
          },
        },
      }
      mockSkillLines({
        { name = "Professions", isHeader = true },
      })
      DS:ScanProfessionLinks()
      local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.is_nil(char.Prof1)
      assert.is_nil(char.Prof2)
      assert.is_nil(char.Professions.Tailoring)
    end)

    it("does not prune when profession skill categories are not loaded yet", function()
      _G.AltArmyTBC_Data.Characters.TestRealm = {
        TestPlayer = {
          Professions = {
            Alchemy = { rank = 350, maxRank = 375, Recipes = {} },
          },
        },
      }
      mockSkillLines({
        { name = "Weapon Skills", isHeader = true },
        { name = "Axes", isHeader = false, rank = 300, maxRank = 300 },
      })
      DS:ScanProfessionLinks()
      local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.is_not_nil(char.Professions.Alchemy)
    end)
  end)
end)
