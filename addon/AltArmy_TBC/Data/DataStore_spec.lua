--[[
  Unit tests for DataStore.lua (MigrateDataVersions).
  Run from project root: npm test
]]

describe("DataStore", function()
  local DS

  setup(function()
    -- Stub WoW globals so DataStore.lua can load outside the game.
    if not _G.AltArmy then
      _G.AltArmy = {}
    end
    if not _G.AltArmyTBC_Data then
      _G.AltArmyTBC_Data = {}
    end
    if not _G.CreateFrame then
      _G.CreateFrame = function()
        return { SetScript = function() end, RegisterEvent = function() end }
      end
    end
    if not _G.UIParent then
      _G.UIParent = {}
    end
    -- Allow require("DataStore") to find AltArmy_TBC/Data/DataStore.lua (cwd = project root).
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("DataStore")
    DS = AltArmy.DataStore
  end)

  describe("_MigrateDataVersions", function()
    it("does nothing when Characters is empty", function()
      local data = { Characters = {} }
      assert.has_no.errors(function()
        DS._MigrateDataVersions(data)
      end)
    end)

    it("initializes dataVersions on each character", function()
      local data = {
        Characters = {
          Realm1 = { Char1 = {} },
        },
      }
      DS._MigrateDataVersions(data)
      assert.truthy(data.Characters.Realm1.Char1.dataVersions)
      assert.are.same(data.Characters.Realm1.Char1.dataVersions, {})
    end)

    it("sets character = 1 when char has name", function()
      local data = {
        Characters = {
          Realm1 = { Char1 = { name = "Alice" } },
        },
      }
      DS._MigrateDataVersions(data)
      assert.are.equal(data.Characters.Realm1.Char1.dataVersions.character, 1)
    end)

    it("does not set character when char has no name", function()
      local data = {
        Characters = {
          Realm1 = { Char1 = {} },
        },
      }
      DS._MigrateDataVersions(data)
      assert.is_nil(data.Characters.Realm1.Char1.dataVersions.character)
    end)

    it("does not overwrite existing dataVersions.character", function()
      local data = {
        Characters = {
          Realm1 = {
            Char1 = {
              name = "Alice",
              dataVersions = { character = 2 },
            },
          },
        },
      }
      DS._MigrateDataVersions(data)
      assert.are.equal(data.Characters.Realm1.Char1.dataVersions.character, 2)
    end)

    it("sets containers = 1 when char has non-empty Containers", function()
      local data = {
        Characters = {
          Realm1 = { Char1 = { Containers = { [0] = { slots = 16 } } } },
        },
      }
      DS._MigrateDataVersions(data)
      assert.are.equal(data.Characters.Realm1.Char1.dataVersions.containers, 1)
    end)

    it("does not set containers when Containers is empty", function()
      local data = {
        Characters = {
          Realm1 = { Char1 = { Containers = {} } },
        },
      }
      DS._MigrateDataVersions(data)
      assert.is_nil(data.Characters.Realm1.Char1.dataVersions.containers)
    end)

    it("sets equipment = 1 when char has non-empty Inventory", function()
      local data = {
        Characters = {
          Realm1 = { Char1 = { Inventory = { [16] = 12345 } } },
        },
      }
      DS._MigrateDataVersions(data)
      assert.are.equal(data.Characters.Realm1.Char1.dataVersions.equipment, 1)
    end)

    it("does not set equipment when Inventory is empty", function()
      local data = {
        Characters = {
          Realm1 = { Char1 = { Inventory = {} } },
        },
      }
      DS._MigrateDataVersions(data)
      assert.is_nil(data.Characters.Realm1.Char1.dataVersions.equipment)
    end)

    it("migrates all realms and characters", function()
      local data = {
        Characters = {
          Realm1 = {
            Char1 = { name = "A" },
            Char2 = { name = "B" },
          },
          Realm2 = { Char3 = { name = "C" } },
        },
      }
      DS._MigrateDataVersions(data)
      assert.are.equal(data.Characters.Realm1.Char1.dataVersions.character, 1)
      assert.are.equal(data.Characters.Realm1.Char2.dataVersions.character, 1)
      assert.are.equal(data.Characters.Realm2.Char3.dataVersions.character, 1)
    end)

    it("uses passed-in data instead of global AltArmyTBC_Data", function()
      local globalData = { Characters = { R = { C = { name = "Global" } } } }
      local mockData = { Characters = { R = { C = { name = "Mock" } } } }
      _G.AltArmyTBC_Data = globalData
      DS._MigrateDataVersions(mockData)
      assert.are.equal(mockData.Characters.R.C.dataVersions.character, 1)
      assert.is_nil(globalData.Characters.R.C.dataVersions)
    end)
  end)

  describe("GetRealms", function()
    it("returns realm keys as table with true values", function()
      _G.AltArmyTBC_Data = { Characters = { RealmA = {}, RealmB = {} } }
      local out = DS:GetRealms()
      assert.truthy(out.RealmA)
      assert.truthy(out.RealmB)
      local n = 0
      for _ in pairs(out) do n = n + 1 end
      assert.are.equal(n, 2)
    end)
    it("returns empty when Characters is empty", function()
      _G.AltArmyTBC_Data = { Characters = {} }
      local out = DS:GetRealms()
      local n = 0
      for _ in pairs(out) do n = n + 1 end
      assert.are.equal(n, 0)
    end)
  end)

  describe("GetCharacters", function()
    it("returns realm table when realm exists", function()
      _G.AltArmyTBC_Data = { Characters = { R1 = { Alice = {}, Bob = {} } } }
      local chars = DS:GetCharacters("R1")
      assert.truthy(chars.Alice)
      assert.truthy(chars.Bob)
    end)
    it("returns empty table when realm is nil", function()
      _G.AltArmyTBC_Data = { Characters = { R1 = {} } }
      assert.are.same(DS:GetCharacters(nil), {})
    end)
    it("returns empty table when realm missing", function()
      _G.AltArmyTBC_Data = { Characters = { R1 = {} } }
      assert.are.same(DS:GetCharacters("Missing"), {})
    end)
  end)

  describe("GetCharacter", function()
    it("returns char when name and realm exist", function()
      _G.AltArmyTBC_Data = { Characters = { R1 = { Alice = { name = "Alice" } } } }
      local char = DS:GetCharacter("Alice", "R1")
      assert.truthy(char)
      assert.are.equal(char.name, "Alice")
    end)
    it("returns nil when name is nil", function()
      _G.AltArmyTBC_Data = { Characters = { R1 = { Alice = {} } } }
      assert.is_nil(DS:GetCharacter(nil, "R1"))
    end)
    it("returns nil when realm is nil", function()
      _G.AltArmyTBC_Data = { Characters = { R1 = { Alice = {} } } }
      assert.is_nil(DS:GetCharacter("Alice", nil))
    end)
    it("returns nil when character missing", function()
      _G.AltArmyTBC_Data = { Characters = { R1 = {} } }
      assert.is_nil(DS:GetCharacter("Alice", "R1"))
    end)
  end)

  describe("HasModuleData", function()
    it("returns false when char is nil", function()
      assert.is_false(DS:HasModuleData(nil, "character"))
    end)
    it("returns false when moduleName is nil", function()
      assert.is_false(DS:HasModuleData({ dataVersions = {} }, nil))
    end)
    it("returns false when dataVersions missing or zero", function()
      assert.is_false(DS:HasModuleData({}, "character"))
      assert.is_false(DS:HasModuleData({ dataVersions = { character = 0 } }, "character"))
    end)
    it("returns true when dataVersions.character is 1", function()
      assert.is_true(DS:HasModuleData({ dataVersions = { character = 1 } }, "character"))
    end)
  end)

  describe("GetDataVersion", function()
    it("returns 0 when char is nil", function()
      assert.are.equal(DS:GetDataVersion(nil, "character"), 0)
    end)
    it("returns 0 when moduleName is nil", function()
      assert.are.equal(DS:GetDataVersion({ dataVersions = { character = 1 } }, nil), 0)
    end)
    it("returns 0 when key missing", function()
      assert.are.equal(DS:GetDataVersion({ dataVersions = {} }, "character"), 0)
    end)
    it("returns version when present", function()
      assert.are.equal(DS:GetDataVersion({ dataVersions = { character = 2 } }, "character"), 2)
    end)
  end)

  describe("NeedsRescan", function()
    it("returns true when char is nil", function()
      assert.is_true(DS:NeedsRescan(nil, "character"))
    end)
    it("returns true when moduleName is nil", function()
      assert.is_true(DS:NeedsRescan({}, nil))
    end)
    it("returns false when moduleName unknown", function()
      assert.is_false(DS:NeedsRescan({ dataVersions = {} }, "unknown_module"))
    end)
    it("returns true when stored version < current", function()
      assert.is_true(DS:NeedsRescan({ dataVersions = {} }, "character"))
      assert.is_true(DS:NeedsRescan({ dataVersions = { character = 0 } }, "character"))
    end)
    it("returns false when stored version == current", function()
      assert.is_false(DS:NeedsRescan({ dataVersions = { character = 1 } }, "character"))
    end)
  end)

  describe("GetAllDataVersions", function()
    it("returns empty when char is nil", function()
      assert.are.same(DS:GetAllDataVersions(nil), {})
    end)
    it("returns copy of dataVersions", function()
      local dv = { character = 1, equipment = 1 }
      local char = { dataVersions = dv }
      local out = DS:GetAllDataVersions(char)
      assert.are.same(dv, out)
      assert.is_true(out ~= dv)
    end)
    it("returns empty when dataVersions nil", function()
      assert.are.same(DS:GetAllDataVersions({}), {})
    end)
  end)
end)
