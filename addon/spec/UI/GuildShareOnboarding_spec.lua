--[[
  Unit tests for GuildShareOnboarding.lua (default main selection + realm dropdown entries).
  Run from project root: npm test
]]

describe("GuildShareOnboarding", function()
  local GSO

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.CreateFrame = _G.CreateFrame or function()
      local f = {
        RegisterEvent = function() end,
        SetScript = function() end,
        Hide = function() end,
        Show = function() end,
        CreateFontString = function()
          return {
            SetPoint = function() end,
            SetText = function() end,
            SetTextColor = function() end,
            SetJustifyH = function() end,
            SetWordWrap = function() end,
            SetWidth = function() end,
          }
        end,
        SetSize = function() end,
        SetPoint = function() end,
        EnableMouse = function() end,
        SetMovable = function() end,
        SetClampedToScreen = function() end,
        SetFrameStrata = function() end,
        RegisterForDrag = function() end,
        SetHeight = function() end,
        SetAllPoints = function() end,
        SetText = function() end,
        SetTextInsets = function() end,
        SetFontObject = function() end,
        SetAutoFocus = function() end,
      }
      return f
    end
    AltArmy.Theme = AltArmy.Theme or {
      CreatePanel = function() return CreateFrame("Frame") end,
      CreateTabContentPanel = function() return CreateFrame("Frame") end,
      CreatePanelInnerContent = function() return CreateFrame("Frame") end,
      ApplyBackdrop = function() end,
      SetTitleColor = function() end,
      CreateSingleSelectDropdown = function() return { button = CreateFrame("Frame") } end,
      CreateLabeledCheckbox = function() return {} end,
      ApplyInputTextures = function() end,
      SkinButton = function() end,
      TAB_CONTENT_PADDING = 8,
    }
    AltArmy.Text = AltArmy.Text or {
      ONBOARDING_DISMISS_FOOTNOTE = "This message will only show once but you can make changes later in Options",
    }
    _G.UIParent = _G.UIParent or {}
    _G.UISpecialFrames = _G.UISpecialFrames or {}
    _G.tinsert = _G.tinsert or table.insert
    package.path = package.path .. ";AltArmy_TBC/UI/?.lua;AltArmy_TBC/Data/?.lua"
    package.loaded["GuildShareOnboarding"] = nil
    require("GuildShareOnboarding")
    GSO = AltArmy.GuildShareOnboarding
    assert.truthy(GSO)
  end)

  describe("CompareMainCandidates", function()
    local opts = {
      getLevel = function(char) return char.level or 0 end,
      getGearScore = function(char) return char.gearScore or 0 end,
      getItemLevel = function(char) return char.itemLevel or 0 end,
    }

    it("prefers higher level", function()
      local a = { name = "Low", char = { level = 60 } }
      local b = { name = "High", char = { level = 70 } }
      assert.is_true(GSO.CompareMainCandidates(b, a, opts) > 0)
      assert.is_true(GSO.CompareMainCandidates(a, b, opts) < 0)
    end)

    it("breaks level ties with gear score", function()
      local a = { name = "A", char = { level = 70, gearScore = 1000 } }
      local b = { name = "B", char = { level = 70, gearScore = 1500 } }
      assert.is_true(GSO.CompareMainCandidates(b, a, opts) > 0)
    end)

    it("breaks gear score ties with item level", function()
      local a = { name = "A", char = { level = 70, gearScore = 1500, itemLevel = 100 } }
      local b = { name = "B", char = { level = 70, gearScore = 1500, itemLevel = 115 } }
      assert.is_true(GSO.CompareMainCandidates(b, a, opts) > 0)
    end)

    it("breaks remaining ties alphabetically by name", function()
      local a = { name = "Zulu", char = { level = 70, gearScore = 1500, itemLevel = 115 } }
      local b = { name = "Alpha", char = { level = 70, gearScore = 1500, itemLevel = 115 } }
      assert.is_true(GSO.CompareMainCandidates(b, a, opts) > 0)
    end)
  end)

  describe("PickDefaultMain", function()
    it("returns nil for an empty list", function()
      assert.is_nil(GSO.PickDefaultMain({}))
    end)

    it("picks the best candidate using level, gear score, item level, then name", function()
      local name = GSO.PickDefaultMain({
        { name = "Bank", char = { level = 1 } },
        { name = "Main", char = { level = 70, gearScore = 2000, itemLevel = 120 } },
        { name = "Alt", char = { level = 70, gearScore = 2000, itemLevel = 110 } },
      }, {
        getLevel = function(char) return char.level or 0 end,
        getGearScore = function(char) return char.gearScore or 0 end,
        getItemLevel = function(char) return char.itemLevel or 0 end,
      })
      assert.are.equal("Main", name)
    end)
  end)

  describe("FormatCharacterDropdownLabel", function()
    it("appends a gray floored level suffix after the colored name", function()
      local label = GSO.FormatCharacterDropdownLabel("Bob", "WARRIOR", 59.9, function(name)
        return "<<" .. name .. ">>"
      end)
      assert.are.equal("<<Bob>> |cff808080(level 59)|r", label)
    end)
  end)

  describe("GetSharingDisclosureTooltip", function()
    it("includes shared, not shared, and audience sections", function()
      local tip = GSO.GetSharingDisclosureTooltip()
      assert.are.equal(6, #tip.lines)
      assert.is_true(tip.lines[1].heading)
      assert.are.equal(GSO.SHARED_HEADING, tip.lines[1].text)
      assert.is_true(tip.lines[3].heading)
      assert.are.equal(GSO.NOT_SHARED_HEADING, tip.lines[3].text)
      assert.are.equal(GSO.NOT_SHARED_LIST, tip.lines[4].text)
      assert.is_true(tip.lines[5].heading)
      assert.matches("guild", tip.lines[6].text:lower())
    end)
  end)

  describe("BuildRealmCharEntries", function()
    local opts = {
      getLevel = function(char) return char.level or 0 end,
      getGearScore = function(char) return char.gearScore or 0 end,
      getItemLevel = function(char) return char.itemLevel or 0 end,
    }

    it("includes every character on the realm sorted by main ranking", function()
      local entries = GSO.BuildRealmCharEntries({
        Zara = { classFile = "MAGE", level = 70, gearScore = 2000, itemLevel = 120 },
        Bob = { classFile = "WARRIOR", level = 1 },
        Alt = { classFile = "ROGUE", level = 70, gearScore = 2000, itemLevel = 110 },
      }, nil, opts)
      assert.are.equal(3, #entries)
      assert.are.equal("Zara", entries[1].id)
      assert.are.equal("Alt", entries[2].id)
      assert.are.equal("Bob", entries[3].id)
      assert.matches("level 70", entries[1].label)
      assert.matches("808080", entries[1].label)
    end)
  end)
end)
