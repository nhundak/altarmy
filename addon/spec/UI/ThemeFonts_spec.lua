--[[
  Font role conventions (Theme.FONTS) — see docs/UI_DESIGN.md "Typography".
  Run from project root: npm test
]]

describe("Theme.FONTS", function()
  local Theme

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/UI/?.lua"
    package.loaded["Theme"] = nil
    require("Theme")
    Theme = AltArmy.Theme
  end)

  it("maps native 12pt roles like Blizzard's Character / Reputation panels", function()
    assert.are.equal("GameFontNormal", Theme.FONTS.heading)
    assert.are.equal("GameFontHighlight", Theme.FONTS.body)
    assert.are.equal("GameFontDisable", Theme.FONTS.muted)
    assert.are.equal("GameFontNormalMed3", Theme.FONTS.title)
  end)

  it("uses a larger gray font for centered empty-state messages", function()
    assert.are.equal("GameFontDisableLarge", Theme.FONTS.emptyState)
  end)

  it("has no 10pt text roles; only icon badges stay Small", function()
    for _, role in ipairs({ "gridCell", "gridHeader", "gridMuted", "fineprint", "smallButton" }) do
      assert.is_nil(Theme.FONTS[role], role)
    end
    assert.are.equal("GameFontNormalSmall", Theme.FONTS.badge)
  end)

  -- Modules loaded by their own specs with a stub Theme keep literals equal to their role.
  local ALLOWED = {
    ["AltArmy_TBC/UI/Theme.lua"] = true,
    ["AltArmy_TBC/UI/ScoreSortRow.lua"] = true,         -- body
    ["AltArmy_TBC/UI/GraphCore.lua"] = true,            -- muted
    ["AltArmy_TBC/UI/QuestRewardIndicators.lua"] = true, -- badge
    ["AltArmy_TBC/Tabs/TabCharacters.lua"] = true,      -- unloaded placeholder
  }

  local function luaFiles()
    local files = {}
    local isWindows = package.config:sub(1, 1) == "\\"
    local cmd = isWindows and 'dir /s /b "AltArmy_TBC\\*.lua"' or 'find AltArmy_TBC -name "*.lua"'
    local pipe = io.popen(cmd)
    for line in pipe:lines() do
      local rel = line:gsub("\\", "/"):match("(AltArmy_TBC/.+)$")
      if rel and not rel:match("^AltArmy_TBC/Libs/") and not rel:match("^AltArmy_TBC/ForeverSVFixData/") then
        files[#files + 1] = rel
      end
    end
    pipe:close()
    return files
  end

  it("is used instead of GameFont literals in UI code", function()
    local offenders = {}
    local files = luaFiles()
    assert.is_true(#files > 20)
    for _, rel in ipairs(files) do
      if not ALLOWED[rel] then
        local f = assert(io.open(rel, "r"))
        local n = 0
        for line in f:lines() do
          n = n + 1
          if line:find('"GameFont%a*"') then
            offenders[#offenders + 1] = rel .. ":" .. n
          end
        end
        f:close()
      end
    end
    assert.are.same({}, offenders)
  end)
end)
