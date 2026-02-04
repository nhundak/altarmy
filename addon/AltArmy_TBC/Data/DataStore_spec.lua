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
end)
