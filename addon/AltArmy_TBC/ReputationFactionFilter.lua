-- Case-insensitive plain substring filter on reputation faction row display names (Reputation tab).

AltArmy = AltArmy or {}

local function trim(s)
    if not s then
        return ""
    end
    return s:match("^%s*(.-)%s*$") or ""
end

local function filterRows(rows, filterRaw)
    if not rows then
        return {}
    end
    local needle = trim(filterRaw):lower()
    if needle == "" then
        return rows
    end
    local out = {}
    for i = 1, #rows do
        local row = rows[i]
        local name = row and row.name or ""
        if string.find(name:lower(), needle, 1, true) then
            out[#out + 1] = row
        end
    end
    return out
end

AltArmy.ReputationFactionFilter = {
    trim = trim,
    filterRows = filterRows,
}
