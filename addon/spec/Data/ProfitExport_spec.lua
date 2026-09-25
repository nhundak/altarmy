--[[
  Unit tests for ProfitExport.lua: the string the altarmy-profit site's Upload tab takes.
  Run from project root: npm test

  spec/fixtures/profit_export_v1.txt is the golden export of CHARACTERS below. The altarmy-profit repo keeps a
  copy (tests/fixtures/altarmy_export_v1.txt) that its parser must read back, so a change here that alters the
  string needs that copy updated too.
]]

local CHARACTERS = {
  Dreamscythe = {
    Frell = {
      faction = "Horde",
      classFile = "MAGE",
      level = 70,
      Professions = {
        Tailoring = {
          rank = 375,
          maxRank = 375,
          Recipes = {
            [26745] = { color = 1, primaryRecipeID = 26745 },
            [26746] = { color = 2, primaryRecipeID = 26746, resultItemID = 21845 },
            [31460] = { color = 2, primaryRecipeID = 26746 }, -- an alias of 26746
          },
        },
        Enchanting = {
          rank = 300,
          maxRank = 375,
          Recipes = {
            [7418] = { color = 3 }, -- Enchanting rows carry only a color
            [7420] = 2, -- a pre-migration row
          },
        },
        Cooking = { rank = 1, maxRank = 75 },
      },
    },
  },
  ["Classic Beta PvE"] = {
    ["Tailor Guy"] = { classFile = "PRIEST", level = 20 }, -- never scanned: no faction, no professions
  },
}

local LINES = table.concat({
  "V|1|20506|2.5.6.69795",
  "C|Classic Beta PvE|Tailor Guy||PRIEST|20",
  "C|Dreamscythe|Frell|Horde|MAGE|70",
  "P|Cooking|1|75|",
  "P|Enchanting|300|375|7418,7420",
  "P|Tailoring|375|375|26745,26746",
}, "\n")

describe("ProfitExport", function()
  local ProfitExport, LibDeflate

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua;AltArmy_TBC/Libs/LibDeflate/?.lua"
    LibDeflate = require("LibDeflate")
    require("ProfitExport")
    ProfitExport = AltArmy.ProfitExport
  end)

  it("lists realms, characters, professions and recipe ids in a stable order", function()
    assert.are.equal(LINES, ProfitExport.Lines(CHARACTERS, 20506, "2.5.6.69795"))
  end)

  it("resolves recipe aliases to their primary recipe id", function()
    local text = ProfitExport.Lines(CHARACTERS, 20506, "2.5.6.69795")
    assert.is_nil(text:find("31460", 1, true))
  end)

  it("drops separators from names so a line always splits the same way", function()
    local odd = { ["Realm|X"] = { ["A\nB"] = { faction = "Horde", classFile = "MAGE", level = 1 } } }
    assert.are.equal("V|1|16001|1.60.1\nC|RealmX|AB|Horde|MAGE|1", ProfitExport.Lines(odd, 16001, "1.60.1"))
  end)

  it("exports nothing but the version line without characters", function()
    assert.are.equal("V|1|16001|1.60.1", ProfitExport.Lines(nil, 16001, "1.60.1"))
  end)

  it("encodes as AAX1: plus LibDeflate's printable raw DEFLATE, matching the golden fixture", function()
    local encoded = ProfitExport.Encode(LINES, LibDeflate)
    assert.are.equal("AAX1:", encoded:sub(1, 5))
    assert.are.equal(LINES, LibDeflate:DecompressDeflate(LibDeflate:DecodeForPrint(encoded:sub(6))))
    local f = assert(io.open("spec/fixtures/profit_export_v1.txt", "rb"))
    local golden = f:read("*a"):gsub("%s+$", "")
    f:close()
    assert.are.equal(golden, encoded)
  end)
end)
