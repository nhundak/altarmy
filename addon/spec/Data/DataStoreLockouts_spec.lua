--[[
  Unit tests for DataStoreLockouts.lua (ScanSavedInstances / RequestLockoutInfo).
  Run from project root: npm test
]]

describe("DataStoreLockouts", function()
  local DS
  local requestCalls
  local savedInstances
  local nowUnix

  local function stubSavedInstance(fields)
    -- name, lockoutId, reset, difficulty, locked, extended, instanceIDMostSig,
    -- isRaid, maxPlayers, difficultyName, numEncounters, encounterProgress
    return {
      fields.name,
      fields.lockoutId or 1,
      fields.reset or 0,
      fields.difficulty or 0,
      fields.locked,
      fields.extended == true,
      fields.instanceIDMostSig or 0,
      fields.isRaid == true,
      fields.maxPlayers or 0,
      fields.difficultyName or "",
      fields.numEncounters or 0,
      fields.encounterProgress or 0,
    }
  end

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.AltArmyTBC_Data = { Characters = {} }
    _G.CreateFrame = _G.CreateFrame or function()
      return { SetScript = function() end, RegisterEvent = function() end }
    end
    _G.UIParent = _G.UIParent or {}
    _G.UnitName = function() return "Tester" end
    _G.GetRealmName = function() return "TestRealm" end
    requestCalls = 0
    savedInstances = {}
    nowUnix = 1000000
    _G.RequestRaidInfo = function()
      requestCalls = requestCalls + 1
    end
    _G.GetNumSavedInstances = function()
      return #savedInstances
    end
    -- Return by index (not unpack) so a nil `locked` does not truncate later fields.
    _G.GetSavedInstanceInfo = function(index)
      local row = savedInstances[index]
      if not row then return end
      return row[1], row[2], row[3], row[4], row[5], row[6],
        row[7], row[8], row[9], row[10], row[11], row[12]
    end
    _G.time = function()
      return nowUnix
    end
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua;AltArmy_TBC/Data/DataStore/?.lua"
    package.loaded["DataStore"] = nil
    package.loaded["DataStoreLockouts"] = nil
    require("DataStore")
    require("DataStoreLockouts")
    DS = AltArmy.DataStore
  end)

  before_each(function()
    requestCalls = 0
    savedInstances = {}
    nowUnix = 1000000
    AltArmyTBC_Data.Characters = {
      TestRealm = {
        Tester = { name = "Tester" },
      },
    }
  end)

  it("RequestLockoutInfo calls RequestRaidInfo", function()
    DS:RequestLockoutInfo()
    assert.are.equal(1, requestCalls)
  end)

  it("ScanSavedInstances stores locked instances with resetAtUnix", function()
    savedInstances = {
      stubSavedInstance({
        name = "Karazhan",
        lockoutId = 42,
        reset = 3600,
        locked = true,
        isRaid = true,
        maxPlayers = 10,
        difficultyName = "10 Player",
        numEncounters = 11,
        encounterProgress = 3,
        extended = false,
      }),
    }
    DS:ScanSavedInstances()
    local char = AltArmyTBC_Data.Characters.TestRealm.Tester
    assert.are.equal(1, #char.RaidLockouts)
    local e = char.RaidLockouts[1]
    assert.are.equal("Karazhan", e.name)
    assert.are.equal(42, e.lockoutId)
    assert.are.equal(nowUnix + 3600, e.resetAtUnix)
    assert.are.equal(true, e.isRaid)
    assert.are.equal(10, e.maxPlayers)
    assert.are.equal("10 Player", e.difficultyName)
    assert.are.equal(11, e.numEncounters)
    assert.are.equal(3, e.encounterProgress)
    assert.are.equal(false, e.extended)
    assert.are.equal(nowUnix, char.lastLockoutScan)
  end)

  it("ScanSavedInstances skips unlocked and zero-reset entries", function()
    savedInstances = {
      stubSavedInstance({ name = "Historic", reset = 100, locked = false, isRaid = true }),
      stubSavedInstance({ name = "Expired", reset = 0, locked = true, isRaid = true }),
      stubSavedInstance({
        name = "The Slave Pens",
        reset = 1200,
        locked = true,
        isRaid = false,
        difficulty = 2,
        difficultyName = "Heroic",
        numEncounters = 3,
        encounterProgress = 1,
      }),
    }
    DS:ScanSavedInstances()
    local char = AltArmyTBC_Data.Characters.TestRealm.Tester
    assert.are.equal(1, #char.RaidLockouts)
    assert.are.equal("The Slave Pens", char.RaidLockouts[1].name)
    assert.are.equal(false, char.RaidLockouts[1].isRaid)
  end)

  it("ScanSavedInstances treats nil locked as locked when reset > 0", function()
    savedInstances = {
      stubSavedInstance({
        name = "Gruul's Lair",
        reset = 500,
        locked = nil,
        isRaid = true,
        maxPlayers = 25,
      }),
    }
    DS:ScanSavedInstances()
    local char = AltArmyTBC_Data.Characters.TestRealm.Tester
    assert.are.equal(1, #char.RaidLockouts)
    assert.are.equal("Gruul's Lair", char.RaidLockouts[1].name)
  end)

  it("ScanSavedInstances replaces previous RaidLockouts list", function()
    local char = AltArmyTBC_Data.Characters.TestRealm.Tester
    char.RaidLockouts = {
      { name = "Stale", lockoutId = 1, resetAtUnix = nowUnix + 999 },
    }
    savedInstances = {
      stubSavedInstance({ name = "Magtheridon's Lair", reset = 100, locked = true, isRaid = true }),
    }
    DS:ScanSavedInstances()
    assert.are.equal(1, #char.RaidLockouts)
    assert.are.equal("Magtheridon's Lair", char.RaidLockouts[1].name)
  end)

  it("ScanSavedInstances clears list when nothing is locked", function()
    local char = AltArmyTBC_Data.Characters.TestRealm.Tester
    char.RaidLockouts = {
      { name = "Stale", lockoutId = 1, resetAtUnix = nowUnix + 999 },
    }
    savedInstances = {}
    DS:ScanSavedInstances()
    assert.are.equal(0, #char.RaidLockouts)
    assert.are.equal(nowUnix, char.lastLockoutScan)
  end)
end)
