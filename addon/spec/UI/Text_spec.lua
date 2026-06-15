--[[
  Unit tests for Text.lua (TruncateFontString).
  Run from project root: npm test
]]

describe("Text", function()
  local Text

  local function mockFontString()
    local text = ""
    return {
      SetText = function(_, value)
        text = value or ""
      end,
      GetText = function()
        return text
      end,
      GetStringWidth = function()
        return #text * 8
      end,
    }
  end

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/UI/?.lua"
    require("Text")
    Text = AltArmy.Text
  end)

  it("returns full text when it fits", function()
    local fs = mockFontString()
    local out = Text.TruncateFontString(fs, "Bob", 100)
    assert.are.equal("Bob", out)
    assert.are.equal("Bob", fs:GetText())
  end)

  it("truncates with ellipsis when too wide", function()
    local fs = mockFontString()
    local out = Text.TruncateFontString(fs, "LongNameHere", 10)
    assert.are.equal("...", out)
  end)

  it("returnBoolean reports truncation", function()
    local fs = mockFontString()
    assert.is_false(Text.TruncateFontString(fs, "Short", 100, { returnBoolean = true }))
    assert.is_true(Text.TruncateFontString(fs, "LongNameHere", 10, { returnBoolean = true }))
  end)

  it("preserves color codes and optional suffix", function()
    local fs = mockFontString()
    local colored = "|cff00ff00LongCharacterName|r"
    Text.TruncateFontString(fs, colored, 80, {
      preserveColorCodes = true,
      suffix = "|cffffffff (Bags)|r",
    })
    local text = fs:GetText()
    assert.is_true(text:find("|cff00ff00", 1, true) ~= nil)
    assert.is_true(text:find("|r", 1, true) ~= nil)
    assert.is_true(text:find("(Bags)", 1, true) ~= nil)
  end)
end)
