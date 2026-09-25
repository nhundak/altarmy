-- AltArmy TBC — Export for the altarmy-profit site: characters, professions and learned recipes as one
-- printable string, pasted on the site's Upload tab instead of uploading AltArmy_TBC.lua.
--
-- Format (v1): "AAX1:" .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(lines)), where lines are
--   V|1|<interface>|<build>                       the client, so the site knows which game it is
--   C|<realm>|<name>|<faction>|<CLASS_FILE>|<level>
--   P|<profession>|<rank>|<maxRank>|<recipe ids>  belongs to the C line before it; ids comma-separated
-- Recipe ids are craft spell ids, aliases resolved to primaryRecipeID (as the site reads the file).
-- The altarmy-profit repo parses it in src/altarmy_profit/paste.py; spec/fixtures/profit_export_v1.txt is
-- the shared golden string.

AltArmy = AltArmy or {}

local ProfitExport = {}
AltArmy.ProfitExport = ProfitExport

ProfitExport.PREFIX = "AAX1:"

local function field(value)
    return (tostring(value or ""):gsub("[|\r\n]", ""))
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t or {}) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return keys
end

--- Recipe ids a profession has learned, each alias counted once under its primary id, ascending.
local function recipeIds(prof)
    local seen, ids = {}, {}
    for key, row in pairs(prof.Recipes or {}) do
        local id = type(row) == "table" and type(row.primaryRecipeID) == "number" and row.primaryRecipeID or key
        if type(id) == "number" and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

--- The export's text: `characters` is AltArmyTBC_Data.Characters (realm -> name -> character).
--- @return string
function ProfitExport.Lines(characters, interface, build)
    local out = { table.concat({ "V", "1", field(interface), field(build) }, "|") }
    for _, realm in ipairs(sortedKeys(characters)) do
        local byName = characters[realm]
        for _, name in ipairs(sortedKeys(byName)) do
            local char = byName[name]
            if type(char) == "table" then
                out[#out + 1] = table.concat({
                    "C", field(realm), field(name), field(char.faction), field(char.classFile), field(char.level or 0),
                }, "|")
                for _, profName in ipairs(sortedKeys(char.Professions)) do
                    local prof = char.Professions[profName]
                    if type(prof) == "table" then
                        out[#out + 1] = table.concat({
                            "P", field(profName), field(prof.rank or 0), field(prof.maxRank or 0),
                            table.concat(recipeIds(prof), ","),
                        }, "|")
                    end
                end
            end
        end
    end
    return table.concat(out, "\n")
end

--- The printable string for `text`, compressed with `libDeflate`.
--- @return string
function ProfitExport.Encode(text, libDeflate)
    return ProfitExport.PREFIX .. libDeflate:EncodeForPrint(libDeflate:CompressDeflate(text, { level = 9 }))
end

--- Every character this account has saved, from the running client. nil if LibDeflate is missing.
--- @return string|nil
function ProfitExport.Build()
    local libDeflate = LibStub and LibStub("LibDeflate", true)
    if not libDeflate then
        return nil
    end
    local data = AltArmyTBC_Data --luacheck: ignore 113
    local _, build, _, interface = GetBuildInfo()
    return ProfitExport.Encode(ProfitExport.Lines(data and data.Characters, interface, build), libDeflate)
end
