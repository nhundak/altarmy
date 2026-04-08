-- AltArmy TBC — Reputation grid sort helpers (discovered rep vs undiscovered ordering).

AltArmy = AltArmy or {}
AltArmy.ReputationFactionSort = AltArmy.ReputationFactionSort or {}

local RS = AltArmy.ReputationFactionSort

local NO_FACTION_REP = -999999999

local function GetReputationStorageSortGroup(DS, char)
    if not char then return 0 end
    if not DS.HasModuleData or not DS:HasModuleData(char, "reputations") then
        return 0
    end
    local reps = char.Reputations
    if not reps then return 0 end
    for _, v in pairs(reps) do
        if type(v) == "number" then
            return 1
        end
    end
    return 0
end

local function GetReputationStorageSortGroupForEntry(DS, entry)
    if not entry or not DS or not DS.GetCharacter then return 0 end
    return GetReputationStorageSortGroup(DS, DS:GetCharacter(entry.name, entry.realm))
end

function RS.GetFactionEarnedForEntry(DS, entry, factionID)
    if not entry or not factionID or not DS or not DS.GetCharacter then
        return NO_FACTION_REP
    end
    local char = DS:GetCharacter(entry.name, entry.realm)
    if not char or not DS.HasModuleData or not DS:HasModuleData(char, "reputations") then
        return NO_FACTION_REP
    end
    local reps = char.Reputations
    if not reps then return NO_FACTION_REP end
    local v = reps[factionID]
    if v == nil then return NO_FACTION_REP end
    if type(v) == "table" then
        local e = tonumber(v.e)
        if e == nil then return NO_FACTION_REP end
        return e
    end
    return tonumber(v) or NO_FACTION_REP
end

--- Same notion as grid / GetReputationInfo standing.
function RS.FactionHasDiscoveredRepForCharacter(DS, entry, factionID)
    if not entry or not factionID or not DS or not DS.GetCharacter or not DS.GetReputationInfo then
        return false
    end
    local char = DS:GetCharacter(entry.name, entry.realm)
    if not char then return false end
    local standing = DS:GetReputationInfo(char, factionID)
    return standing ~= nil
end

local function GetSortValue(entry, sortKey)
    if sortKey == "Name" then return entry.name or "" end
    if sortKey == "Level" then return tonumber(entry.level) or 0 end
    if sortKey == "Avg Item Level" then return tonumber(entry.avgItemLevel) or 0 end
    if sortKey == "Time Played" then return tonumber(entry.played) or 0 end
    return 0
end

local function CompareBySort(entryA, entryB, primary, secondary)
    local va = GetSortValue(entryA, primary)
    local vb = GetSortValue(entryB, primary)
    if primary == "Name" then
        if va ~= vb then return va < vb end
    else
        if va ~= vb then return va > vb end
    end
    va = GetSortValue(entryA, secondary)
    vb = GetSortValue(entryB, secondary)
    if secondary == "Name" then
        return va < vb
    else
        return va > vb
    end
end

--- Sort character rows by earned rep for factionID. Undiscovered always after discovered.
function RS.CompareByFactionRep(DS, entryA, entryB, factionID, highFirst, primary, secondary)
    local ga = GetReputationStorageSortGroupForEntry(DS, entryA)
    local gb = GetReputationStorageSortGroupForEntry(DS, entryB)
    if ga ~= gb then
        return ga < gb
    end
    local discA = RS.FactionHasDiscoveredRepForCharacter(DS, entryA, factionID)
    local discB = RS.FactionHasDiscoveredRepForCharacter(DS, entryB, factionID)
    if discA ~= discB then
        return discA
    end
    local ea = RS.GetFactionEarnedForEntry(DS, entryA, factionID)
    local eb = RS.GetFactionEarnedForEntry(DS, entryB, factionID)
    if discA and discB and ea ~= eb then
        if highFirst then
            return ea > eb
        else
            return ea < eb
        end
    end
    return CompareBySort(entryA, entryB, primary, secondary)
end

--- Sort faction rows by the given character column. Undiscovered cells always after discovered.
function RS.CompareFactionRowsForCharacter(DS, charEntry, rowA, rowB, highFirst)
    if not rowA or not rowB then return false end
    local discA = RS.FactionHasDiscoveredRepForCharacter(DS, charEntry, rowA.factionID)
    local discB = RS.FactionHasDiscoveredRepForCharacter(DS, charEntry, rowB.factionID)
    if discA ~= discB then
        return discA
    end
    if discA and discB then
        local ea = RS.GetFactionEarnedForEntry(DS, charEntry, rowA.factionID)
        local eb = RS.GetFactionEarnedForEntry(DS, charEntry, rowB.factionID)
        if ea ~= eb then
            if highFirst then
                return ea > eb
            else
                return ea < eb
            end
        end
    end
    return (rowA.name or "") < (rowB.name or "")
end
