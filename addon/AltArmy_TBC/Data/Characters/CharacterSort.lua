-- AltArmy TBC — Shared character list sort comparators (Gear / Reputation tabs).

AltArmy = AltArmy or {}
AltArmy.CharacterSort = AltArmy.CharacterSort or {}

local CS = AltArmy.CharacterSort

--- Sort value for an entry by key (Name, Level, Avg Item Level, Time Played). Numeric = high first, Name = A–Z.
function CS.GetSortValue(entry, sortKey)
    if sortKey == "Name" then return entry.name or "" end
    if sortKey == "Level" then return tonumber(entry.level) or 0 end
    if sortKey == "Avg Item Level" then return tonumber(entry.avgItemLevel) or 0 end
    if sortKey == "Time Played" then return tonumber(entry.played) or 0 end
    if entry.scores and entry.scores[sortKey] ~= nil then
        return tonumber(entry.scores[sortKey]) or 0
    end
    return 0
end

--- Compare two entries by primary then secondary sort (numeric high-first, string A–Z).
function CS.CompareBySort(entryA, entryB, primary, secondary)
    local va = CS.GetSortValue(entryA, primary)
    local vb = CS.GetSortValue(entryB, primary)
    if primary == "Name" then
        if va ~= vb then return va < vb end
    else
        if va ~= vb then return va > vb end
    end
    va = CS.GetSortValue(entryA, secondary)
    vb = CS.GetSortValue(entryB, secondary)
    if secondary == "Name" then
        return va < vb
    else
        return va > vb
    end
end
