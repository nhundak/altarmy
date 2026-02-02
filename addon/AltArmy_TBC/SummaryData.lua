-- AltArmy TBC — Summary data layer: character list for the Summary tab.
-- First implementation: current character only (native APIs).
-- Later: DataStore can supply all characters with the same format.

AltArmy.SummaryData = AltArmy.SummaryData or {}

-- Returns a list of character entries: { { name = string, realm = string }, ... }
-- Stateless; reads live from the client. Current implementation: one entry for the logged-in character.
-- Uses UnitName (TBC-friendly); fallback to GetUnitName/GetRealmName if needed.
function AltArmy.SummaryData.GetCharacterList()
    local name, realm
    if UnitName then
        name, realm = UnitName("player")
    end
    if (not name or name == "") and GetUnitName then
        name = GetUnitName("player")
        realm = GetRealmName and GetRealmName() or nil
    end
    if not realm and GetRealmName then
        realm = GetRealmName()
    end
    if not name or name == "" then
        if AltArmy.DebugLog then
            AltArmy.DebugLog("Character list: no player unit, returning empty")
        end
        return {}
    end
    local list = {
        { name = name, realm = realm or "" },
    }
    if AltArmy.DebugLog then
        AltArmy.DebugLog("Character list loaded: " .. #list .. " character(s)")
    end
    return list
end
