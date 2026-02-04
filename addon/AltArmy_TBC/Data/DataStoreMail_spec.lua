--[[
  Unit tests for DataStoreMail.lua (GetNumMails, GetMailItemCount, GetMailInfo, GetMailboxLastVisit).
  Run from project root: npm test
]]

describe("DataStoreMail", function()
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
    require("DataStoreMail")
    DS = AltArmy.DataStore
  end)

  describe("GetNumMails", function()
    it("returns 0 when char is nil", function()
      assert.are.equal(DS:GetNumMails(nil), 0)
    end)
    it("returns 0 when Mails nil", function()
      assert.are.equal(DS:GetNumMails({}), 0)
    end)
    it("returns length of Mails", function()
      local char = { Mails = { {}, {}, {} } }
      assert.are.equal(3, DS:GetNumMails(char))
    end)
  end)

  describe("GetMailItemCount", function()
    it("returns 0 when char or itemID nil", function()
      assert.are.equal(0, DS:GetMailItemCount(nil, 100))
      assert.are.equal(0, DS:GetMailItemCount({ Mails = {} }, nil))
    end)
    it("sums count for matching itemID", function()
      local char = {
        Mails = {
          { itemID = 100, count = 2 },
          { itemID = 200, count = 1 },
          { itemID = 100, count = 3 },
        },
      }
      assert.are.equal(5, DS:GetMailItemCount(char, 100))
      assert.are.equal(1, DS:GetMailItemCount(char, 200))
      assert.are.equal(0, DS:GetMailItemCount(char, 999))
    end)
    it("treats missing count as 1", function()
      local char = { Mails = { { itemID = 100 } } }
      assert.are.equal(1, DS:GetMailItemCount(char, 100))
    end)
  end)

  describe("GetMailInfo", function()
    it("returns nil,... when index out of range", function()
      local char = { Mails = {} }
      local icon = DS:GetMailInfo(char, 1)
      assert.is_nil(icon)
    end)
    it("returns icon, count, link, money, subject, sender, daysLeft, returned", function()
      local char = {
        Mails = {
          {
            icon = "x", count = 5, link = "l", money = 100, subject = "s", sender = "S",
            daysLeft = 30, lastCheck = 0, returned = false,
          },
        },
      }
      local old = _G.time
      _G.time = function() return 86400 end
      local icon, count, link, money, subject, sender, _, returned = DS:GetMailInfo(char, 1)
      _G.time = old
      assert.are.equal("x", icon)
      assert.are.equal(5, count)
      assert.are.equal("l", link)
      assert.are.equal(100, money)
      assert.are.equal("s", subject)
      assert.are.equal("S", sender)
      assert.are.equal(false, returned)
    end)
  end)

  describe("GetMailboxLastVisit", function()
    it("returns 0 when char nil", function()
      assert.are.equal(0, DS:GetMailboxLastVisit(nil))
    end)
    it("returns lastMailCheck or 0", function()
      assert.are.equal(12345, DS:GetMailboxLastVisit({ lastMailCheck = 12345 }))
      assert.are.equal(0, DS:GetMailboxLastVisit({}))
    end)
  end)
end)
