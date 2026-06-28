-- AltArmy TBC — Global per-character bank alt flag.
-- Saved under AltArmyTBC_Options.bankAlts (CharKey -> true).

if not AltArmy then return end

AltArmy.BankAlt = AltArmy.BankAlt or {}
local B = AltArmy.BankAlt

local BANK_ICON = "Interface\\MINIMAP\\TRACKING\\Banker"

local function charKey(name, realm)
    return AltArmy.CharKey(name, realm)
end

function B.Ensure()
    _G.AltArmyTBC_Options = _G.AltArmyTBC_Options or {}
    AltArmyTBC_Options.bankAlts = AltArmyTBC_Options.bankAlts or {}
end

--- @param name string|nil
--- @param realm string|nil
--- @return boolean
function B.Is(name, realm)
    B.Ensure()
    if not name or not realm then return false end
    return AltArmyTBC_Options.bankAlts[charKey(name, realm)] == true
end

--- @param name string|nil
--- @param realm string|nil
--- @param value boolean|nil
function B.Set(name, realm, value)
    B.Ensure()
    if not name or not realm then return end
    local key = charKey(name, realm)
    if value == true then
        AltArmyTBC_Options.bankAlts[key] = true
    else
        AltArmyTBC_Options.bankAlts[key] = nil
    end
end

--- Inline texture for FontString / chat (prepend before colored name).
--- @return string
function B.IconMarkup()
    return "|T" .. BANK_ICON .. ":0|t"
end

B.Ensure()
