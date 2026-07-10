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

local function DefaultTieBreak(entryA, entryB)
    return (entryA.name or "") < (entryB.name or "")
end

--- Sort character rows by earned rep for factionID. Undiscovered always after discovered.
--- @param tieBreak function(a, b) -> boolean used when rep values are equal (defaults to name).
function RS.CompareByFactionRep(DS, entryA, entryB, factionID, highFirst, tieBreak)
    tieBreak = tieBreak or DefaultTieBreak
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
    return tieBreak(entryA, entryB)
end

--- Build the displayed column order: pinned characters first (in the current sort order),
--- then non-pinned (in the current sort order). When selfFirst is true, the current character
--- is grouped with the pinned characters; when false, an unpinned self is appended last.
--- @param visible table list of character entries (already filtered for hidden, etc.)
--- @param isPinned function(entry) -> boolean
--- @param isSelf function(entry) -> boolean
--- @param selfFirst boolean treat the current character as pinned
--- @param compare function(a, b) -> boolean comparator for the active sort
function RS.BuildSortedDisplayList(visible, isPinned, isSelf, selfFirst, compare)
    local selfEntry = nil
    local pinned = {}
    local nonPinned = {}
    for i = 1, #visible do
        local e = visible[i]
        local self_ = isSelf(e) == true
        if isPinned(e) == true or (selfFirst and self_) then
            pinned[#pinned + 1] = e
        elseif self_ then
            selfEntry = e
        else
            nonPinned[#nonPinned + 1] = e
        end
    end
    table.sort(pinned, compare)
    table.sort(nonPinned, compare)
    local list = {}
    for i = 1, #pinned do list[#list + 1] = pinned[i] end
    for i = 1, #nonPinned do list[#list + 1] = nonPinned[i] end
    if not selfFirst and selfEntry then list[#list + 1] = selfEntry end
    return list
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
