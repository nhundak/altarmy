--[[
  Unit tests for mail expiry warnings (DataStoreMail.GetSoonestMailDaysLeft + MailAlerts).
  Run from project root: npm test
]]

describe("Mail expiry alerts", function()
  local DS
  local MA

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.AltArmyTBC_Data = _G.AltArmyTBC_Data or { Characters = {} }
    _G.CreateFrame = _G.CreateFrame or function()
      return {
        SetScript = function() end,
        RegisterEvent = function() end,
      }
    end
    _G.UIParent = _G.UIParent or {}
    _G.RAID_CLASS_COLORS = {
      MAGE = { r = 0.41, g = 0.8, b = 0.94 },
      WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    }
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    package.loaded["DataStore"] = nil
    package.loaded["DataStoreMail"] = nil
    package.loaded["ClassColor"] = nil
    package.loaded["MailAlerts"] = nil
    require("DataStore")
    require("DataStoreMail")
    require("ClassColor")
    require("MailAlerts")
    DS = AltArmy.DataStore
    MA = AltArmy.MailAlerts
  end)

  describe("GetSoonestMailDaysLeft", function()
    it("returns nil when char is nil or has no mail", function()
      assert.is_nil(DS:GetSoonestMailDaysLeft(nil))
      assert.is_nil(DS:GetSoonestMailDaysLeft({}))
      assert.is_nil(DS:GetSoonestMailDaysLeft({ Mails = {}, MailCache = {} }))
    end)

    it("returns adjusted daysLeft for a single scanned mail", function()
      local char = {
        Mails = {
          { daysLeft = 30, lastCheck = 0 },
        },
      }
      local left = DS:GetSoonestMailDaysLeft(char, 5 * 86400)
      assert.is_near(25, left, 0.001)
    end)

    it("returns the minimum across Mails and MailCache", function()
      local char = {
        Mails = {
          { daysLeft = 10, lastCheck = 0 },
          { daysLeft = 8, lastCheck = 0 },
        },
        MailCache = {
          { daysLeft = 30, lastCheck = 0 },
          { daysLeft = 3, lastCheck = 0 },
        },
      }
      local left = DS:GetSoonestMailDaysLeft(char, 0)
      assert.is_near(3, left, 0.001)
    end)

    it("accounts for elapsed time since lastCheck on each entry", function()
      local now = 10 * 86400
      local char = {
        Mails = {
          -- 6 days left at check 4 days ago => 2 days left now
          { daysLeft = 6, lastCheck = 6 * 86400 },
          -- 20 days left at check just now => 20 days left
          { daysLeft = 20, lastCheck = now },
        },
      }
      local left = DS:GetSoonestMailDaysLeft(char, now)
      assert.is_near(2, left, 0.001)
    end)
  end)

  describe("FormatDuration", function()
    it("formats whole days", function()
      assert.are.equal("5 days", MA.FormatDuration(5))
      assert.are.equal("1 day", MA.FormatDuration(1))
    end)

    it("includes hours when fractional days remain", function()
      assert.are.equal("2 days 12 hours", MA.FormatDuration(2.5))
      assert.are.equal("1 day 6 hours", MA.FormatDuration(1.25))
    end)

    it("formats sub-day durations in hours/minutes", function()
      assert.are.equal("12 hours", MA.FormatDuration(0.5))
      assert.are.equal("1 hour", MA.FormatDuration(1 / 24))
      assert.are.equal("30 minutes", MA.FormatDuration(0.5 / 24))
    end)

    it("formats non-positive as less than an hour", function()
      assert.are.equal("less than an hour", MA.FormatDuration(0))
      assert.are.equal("less than an hour", MA.FormatDuration(-1))
    end)
  end)

  describe("FormatMessage", function()
    it("includes class-colored name and duration", function()
      local msg = MA.FormatMessage("Arthas", "MAGE", 3)
      assert.matches("Arthas", msg)
      assert.matches("has mail which will be returned in 3 days", msg)
      assert.matches("|cff", msg)
    end)
  end)

  describe("CollectWarnings", function()
    local function stubCharacters(charactersByRealm)
      AltArmyTBC_Data.Characters = charactersByRealm
    end

    it("returns only characters with soonest mail at or under threshold", function()
      stubCharacters({
        RealmA = {
          Alice = {
            name = "Alice",
            classFile = "MAGE",
            Mails = { { daysLeft = 4, lastCheck = 0 } },
          },
          Bob = {
            name = "Bob",
            classFile = "WARRIOR",
            Mails = { { daysLeft = 10, lastCheck = 0 } },
          },
          Carol = {
            name = "Carol",
            classFile = "MAGE",
            MailCache = { { daysLeft = 5, lastCheck = 0 } },
          },
        },
      })
      local warnings = MA.CollectWarnings(DS, 0, 5)
      assert.are.equal(2, #warnings)
      assert.are.equal("Alice", warnings[1].name)
      assert.is_near(4, warnings[1].daysLeft, 0.001)
      assert.are.equal("Carol", warnings[2].name)
      assert.is_near(5, warnings[2].daysLeft, 0.001)
    end)

    it("returns empty when no characters are near expiry", function()
      stubCharacters({
        RealmA = {
          Bob = {
            name = "Bob",
            Mails = { { daysLeft = 12, lastCheck = 0 } },
          },
        },
      })
      local warnings = MA.CollectWarnings(DS, 0, 5)
      assert.are.equal(0, #warnings)
    end)

    it("sorts by soonest expiry first", function()
      stubCharacters({
        RealmA = {
          Zed = {
            name = "Zed",
            Mails = { { daysLeft = 5, lastCheck = 0 } },
          },
          Ann = {
            name = "Ann",
            Mails = { { daysLeft = 1, lastCheck = 0 } },
          },
        },
      })
      local warnings = MA.CollectWarnings(DS, 0, 5)
      assert.are.equal("Ann", warnings[1].name)
      assert.are.equal("Zed", warnings[2].name)
    end)
  end)

  describe("AnnounceWarnings", function()
    it("posts one chat line per warning with Alt Army prefix", function()
      local lines = {}
      _G.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, text)
          lines[#lines + 1] = text
        end,
      }
      MA.AnnounceWarnings({
        { name = "Alice", classFile = "MAGE", daysLeft = 2 },
        { name = "Bob", classFile = "WARRIOR", daysLeft = 4 },
      })
      assert.are.equal(2, #lines)
      assert.matches("Alt Army", lines[1])
      assert.matches("Alice", lines[1])
      assert.matches("returned in 2 days", lines[1])
      assert.matches("Bob", lines[2])
      assert.matches("returned in 4 days", lines[2])
    end)
  end)

  describe("DebugAnnounceForCharacter", function()
    it("announces even when duration is above the login threshold", function()
      AltArmyTBC_Data.Characters = {
        RealmA = {
          Alice = {
            name = "Alice",
            classFile = "MAGE",
            Mails = { { daysLeft = 20, lastCheck = 0 } },
          },
        },
      }
      local lines = {}
      _G.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, text)
          lines[#lines + 1] = text
        end,
      }
      local old = _G.time
      _G.time = function() return 0 end
      local ok = MA.DebugAnnounceForCharacter("Alice")
      _G.time = old
      assert.is_true(ok)
      assert.are.equal(1, #lines)
      assert.matches("Alice", lines[1])
      assert.matches("returned in 20 days", lines[1])
    end)

    it("reports when the character has no mail", function()
      AltArmyTBC_Data.Characters = {
        RealmA = {
          Alice = { name = "Alice", classFile = "MAGE", Mails = {} },
        },
      }
      local lines = {}
      _G.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, text)
          lines[#lines + 1] = text
        end,
      }
      local ok = MA.DebugAnnounceForCharacter("Alice")
      assert.is_false(ok)
      assert.are.equal(1, #lines)
      assert.matches("no mail", lines[1]:lower())
    end)

    it("reports when the character is not found", function()
      AltArmyTBC_Data.Characters = { RealmA = {} }
      local lines = {}
      _G.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, text)
          lines[#lines + 1] = text
        end,
      }
      local ok = MA.DebugAnnounceForCharacter("Missing")
      assert.is_false(ok)
      assert.are.equal(1, #lines)
      assert.matches("not found", lines[1]:lower())
    end)

    it("matches character names case-insensitively", function()
      AltArmyTBC_Data.Characters = {
        RealmA = {
          Alice = {
            name = "Alice",
            classFile = "MAGE",
            MailCache = { { daysLeft = 7, lastCheck = 0 } },
          },
        },
      }
      local lines = {}
      _G.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, text)
          lines[#lines + 1] = text
        end,
      }
      local old = _G.time
      _G.time = function() return 0 end
      local ok = MA.DebugAnnounceForCharacter("alice")
      _G.time = old
      assert.is_true(ok)
      assert.matches("Alice", lines[1])
    end)
  end)
end)
