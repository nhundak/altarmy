--[[ Unit tests for LockoutData.lua — run: npm test ]]

describe("LockoutData", function()
  local LD

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.AltArmyTBC_Options = {}
    package.path = package.path .. ";AltArmy_TBC/Data/Cooldowns/?.lua"
    package.loaded["LockoutData"] = nil
    require("LockoutData")
    LD = AltArmy.LockoutData
    assert.truthy(LD)
  end)

  local function mockDS(realmTable)
    local ds = {
      GetRealms = function()
        local out = {}
        for realm in pairs(realmTable) do
          out[realm] = true
        end
        return out
      end,
      GetCharacters = function(_self, realm)
        return realmTable[realm] or {}
      end,
      ForEachCharacter = function(self, fn)
        for realm in pairs(self:GetRealms()) do
          for charName, charData in pairs(self:GetCharacters(realm)) do
            if fn(realm, charName, charData) == true then
              return
            end
          end
        end
      end,
      GetCharacterClass = function(_self, char)
        if not char then return "", "" end
        return char.class or "", char.classFile or ""
      end,
    }
    return ds
  end

  describe("FormatInstanceLabel", function()
    it("prefixes Heroic for heroic difficultyName", function()
      assert.are.equal(
        "Heroic: The Slave Pens",
        LD.FormatInstanceLabel({ name = "The Slave Pens", difficultyName = "Heroic" })
      )
    end)

    it("omits player-count difficultyName from the label", function()
      assert.are.equal(
        "Karazhan",
        LD.FormatInstanceLabel({ name = "Karazhan", difficultyName = "10 Player", isRaid = true })
      )
    end)

    it("does not append maxPlayers to raid names", function()
      assert.are.equal(
        "Gruul's Lair",
        LD.FormatInstanceLabel({ name = "Gruul's Lair", isRaid = true, maxPlayers = 25 })
      )
    end)

    it("treats difficultyId 2 as heroic when not a raid", function()
      assert.are.equal(
        "Heroic: Shadow Labyrinth",
        LD.FormatInstanceLabel({ name = "Shadow Labyrinth", difficultyId = 2, isRaid = false })
      )
    end)
  end)

  describe("FormatResetRemaining", function()
    it("formats multi-day remaining time", function()
      assert.are.equal("2d 3h 4m", LD.FormatResetRemaining(1000 + 2 * 86400 + 3 * 3600 + 4 * 60, 1000))
    end)

    it("formats hours and minutes", function()
      assert.are.equal("1h 5m", LD.FormatResetRemaining(1000 + 3600 + 5 * 60, 1000))
    end)
  end)

  describe("BuildRows", function()
    it("builds rows for active lockouts across characters", function()
      local now = 5000
      local ds = mockDS({
        TestRealm = {
          Alice = {
            name = "Alice",
            classFile = "MAGE",
            RaidLockouts = {
              {
                name = "Karazhan",
                lockoutId = 1,
                resetAtUnix = now + 3600,
                difficultyName = "10 Player",
                isRaid = true,
                maxPlayers = 10,
                numEncounters = 11,
                encounterProgress = 4,
                extended = false,
              },
            },
          },
          Bob = {
            name = "Bob",
            classFile = "WARRIOR",
            RaidLockouts = {
              {
                name = "The Slave Pens",
                lockoutId = 2,
                resetAtUnix = now + 600,
                difficultyName = "Heroic",
                isRaid = false,
                difficultyId = 2,
                numEncounters = 3,
                encounterProgress = 3,
                extended = true,
              },
            },
          },
        },
      })
      local rows = LD.BuildRows(ds, now)
      assert.are.equal(2, #rows)
      local byName = {}
      for _, r in ipairs(rows) do
        byName[r.name] = r
      end
      assert.are.equal("Karazhan", byName.Alice.instanceLabel)
      assert.are.equal("4/11", byName.Alice.progressText)
      assert.are.equal(now + 3600, byName.Alice.resetAtUnix)
      assert.are.equal("MAGE", byName.Alice.classFile)
      assert.are.equal("Heroic: The Slave Pens", byName.Bob.instanceLabel)
      assert.are.equal("3/3", byName.Bob.progressText)
      assert.is_true(byName.Bob.extended)
    end)

    it("prunes expired lockouts on read", function()
      local now = 5000
      local ds = mockDS({
        TestRealm = {
          Alice = {
            name = "Alice",
            RaidLockouts = {
              { name = "Old", resetAtUnix = now - 1, isRaid = true, numEncounters = 1, encounterProgress = 1 },
              { name = "Live", resetAtUnix = now + 10, isRaid = true, numEncounters = 2, encounterProgress = 1 },
            },
          },
        },
      })
      local rows = LD.BuildRows(ds, now)
      assert.are.equal(1, #rows)
      assert.are.equal("Live", rows[1].instanceName)
    end)

    it("returns empty when no lockouts", function()
      local ds = mockDS({
        TestRealm = {
          Alice = { name = "Alice", RaidLockouts = {} },
        },
      })
      assert.are.equal(0, #LD.BuildRows(ds, 1000))
    end)

    it("includes sort keys for character and reset time", function()
      local now = 1000
      local ds = mockDS({
        ARealm = {
          Zed = {
            name = "Zed",
            RaidLockouts = {
              { name = "Kara", resetAtUnix = now + 100, isRaid = true },
            },
          },
        },
      })
      local rows = LD.BuildRows(ds, now)
      assert.are.equal(1, #rows)
      assert.are.equal("Zed", rows[1].name)
      assert.are.equal("ARealm", rows[1].realm)
      assert.are.equal(now + 100, rows[1].resetAtUnix)
      assert.truthy(rows[1].timeText)
    end)
  end)

  describe("EnsureLockoutListOptions", function()
    it("defaults activeView to crafting and lockout sort to time ascending", function()
      _G.AltArmyTBC_Options = {}
      local opts = LD.EnsureLockoutListOptions()
      assert.are.equal("crafting", opts.activeView)
      assert.are.equal("time", opts.lockoutListSortKey)
      assert.is_true(opts.lockoutListSortAscending)
    end)

    it("preserves valid activeView", function()
      _G.AltArmyTBC_Options = { cooldowns = { activeView = "raids" } }
      local opts = LD.EnsureLockoutListOptions()
      assert.are.equal("raids", opts.activeView)
    end)
  end)
end)
