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
    it("counts Mails + MailCache when both exist", function()
      local char = { Mails = { {}, {} }, MailCache = { {}, {}, {} } }
      assert.are.equal(5, DS:GetNumMails(char))
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
    it("includes MailCache entries in counts", function()
      local char = {
        Mails = { { itemID = 100, count = 2 } },
        MailCache = { { itemID = 100, count = 3 }, { itemID = 200, count = 9 } },
      }
      assert.are.equal(5, DS:GetMailItemCount(char, 100))
      assert.are.equal(9, DS:GetMailItemCount(char, 200))
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
    it("can read info from MailCache after Mails entries", function()
      local char = {
        Mails = { { icon = "m1", itemID = 1, count = 1, lastCheck = 0, daysLeft = 30 } },
        MailCache = { { icon = "c1", itemID = 2, count = 5, link = "lk", money = 0, subject = "sub", sender = "Me", lastCheck = 0, daysLeft = 30, returned = true } },
      }
      local old = _G.time
      _G.time = function() return 0 end
      local icon, count, link, money, subject, sender, daysLeft, returned = DS:GetMailInfo(char, 2)
      _G.time = old
      assert.are.equal("c1", icon)
      assert.are.equal(5, count)
      assert.are.equal("lk", link)
      assert.are.equal(0, money)
      assert.are.equal("sub", subject)
      assert.are.equal("Me", sender)
      assert.are.equal(30, daysLeft)
      assert.are.equal(true, returned)
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

  describe("Cache + scan interactions", function()
    it("SaveMailAttachmentToCache appends an entry with expiry metadata", function()
      local char = { Mails = {}, MailCache = {} }
      local old = _G.time
      _G.time = function() return 123 end
      DS:SaveMailAttachmentToCache(char, "ic", 100, "link", 2, "Sender", "Subj", false)
      _G.time = old
      assert.are.equal(1, #char.MailCache)
      assert.are.equal(100, char.MailCache[1].itemID)
      assert.are.equal(2, char.MailCache[1].count)
      assert.are.equal("Sender", char.MailCache[1].sender)
      assert.are.equal("Subj", char.MailCache[1].subject)
      assert.are.equal(30, char.MailCache[1].daysLeft)
      assert.are.equal(123, char.MailCache[1].lastCheck)
      assert.are.equal(false, char.MailCache[1].returned)
    end)

    it("SaveMailToCache appends a money/body entry", function()
      local char = { Mails = {}, MailCache = {} }
      DS:SaveMailToCache(char, 500, "body", "sub", "Sender", false)
      assert.are.equal(1, #char.MailCache)
      assert.are.equal(500, char.MailCache[1].money)
      assert.are.equal("body", char.MailCache[1].text)
      assert.are.equal("sub", char.MailCache[1].subject)
      assert.are.equal("Sender", char.MailCache[1].sender)
    end)

    it("ScanMailbox clears MailCache once a real scan occurs", function()
      local char = { Mails = {}, MailCache = { { itemID = 100, count = 1 } } }
      -- Force current character table to this instance.
      DS._GetCurrentCharTable = function() return char end
      _G.GetInboxNumItems = function() return 0 end
      _G.CheckInbox = function() end
      local old = _G.time
      _G.time = function() return 999 end
      DS:ScanMailbox()
      _G.time = old
      assert.are.equal(0, #char.MailCache)
      assert.are.equal(999, char.lastMailCheck)
    end)
  end)
end)
