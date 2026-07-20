-- AltArmy TBC — Global per-character bank alt flag.
-- Saved under AltArmyTBC_Options.bankAlts (CharKey -> true).

if not AltArmy then return end

AltArmy.BankAlt = AltArmy.BankAlt or {}
local B = AltArmy.BankAlt

local BANK_ICON = "Interface\\MINIMAP\\TRACKING\\Banker"
B.ICON_TEXTURE = BANK_ICON

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

--- Tooltip line: class-colored name + " is a bank alt".
--- @param name string|nil
--- @param classFile string|nil
--- @return string
function B.GetTooltipText(name, classFile)
    local CC = AltArmy.ClassColor
    local coloredName = CC and CC.formatName and CC.formatName(name, classFile)
        or ("|cffffffff" .. (name or "?") .. "|r")
    return coloredName .. " is a bank alt"
end

--- @param owner Frame
--- @param anchor string|nil
--- @param name string|nil
--- @param realm string|nil
--- @param classFile string|nil
--- @return boolean true if tooltip was shown
function B.PresentTooltip(owner, anchor, name, realm, classFile)
    if not owner or not B.Is(name, realm) or not GameTooltip then return false end
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_BOTTOMLEFT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(B.GetTooltipText(name, classFile), 1, 1, 1, true)
    GameTooltip:AddLine("Click to configure", 0.5, 0.5, 0.5, true)
    GameTooltip:Show()
    return true
end

B.Ensure()
