-- AltArmy TBC — Generic search index factory (entries / byId / names).
-- Used by the v2 search engine for items, local recipes, and guild recipes.

AltArmy = AltArmy or {}
AltArmy.SearchIndex = AltArmy.SearchIndex or {}

local SI = AltArmy.SearchIndex

--- Build an index from a flat entry list.
--- opts.getId(entry) -> id
--- opts.getNameLower(entry) -> lowercase name or nil
--- opts.compareWithinId(a, b) optional sort within each byId bucket
--- @return table { entries, byId, names }
function SI.BuildIndex(entries, opts)
    opts = opts or {}
    local getId = opts.getId
    local getNameLower = opts.getNameLower
    local compareWithinId = opts.compareWithinId
    local list = entries or {}
    local byId = {}
    local names = {}
    local nameSeen = {}

    for i = 1, #list do
        local entry = list[i]
        local id = entry and getId and getId(entry)
        if id ~= nil then
            local bucket = byId[id]
            if not bucket then
                bucket = {}
                byId[id] = bucket
            end
            bucket[#bucket + 1] = entry
            if not nameSeen[id] and getNameLower then
                local nameLower = getNameLower(entry)
                if nameLower and nameLower ~= "" then
                    nameSeen[id] = true
                    names[#names + 1] = { id = id, nameLower = nameLower }
                end
            end
        end
    end

    if compareWithinId then
        for _, bucket in pairs(byId) do
            if #bucket > 1 then
                table.sort(bucket, compareWithinId)
            end
        end
    end

    return {
        entries = list,
        byId = byId,
        names = names,
    }
end

--- Return set map id -> true for names whose nameLower contains queryLower.
--- When previousIds is provided, only those ids are considered (prefix-narrowing).
function SI.MatchNameIds(names, queryLower, previousIds)
    local ids = {}
    if not queryLower or queryLower == "" then
        return ids
    end
    if previousIds then
        local nameById = {}
        for i = 1, #(names or {}) do
            local n = names[i]
            if n then
                nameById[n.id] = n.nameLower
            end
        end
        for id in pairs(previousIds) do
            local nameLower = nameById[id]
            if nameLower and nameLower:find(queryLower, 1, true) then
                ids[id] = true
            end
        end
        return ids
    end
    for i = 1, #(names or {}) do
        local n = names[i]
        if n and n.nameLower and n.nameLower:find(queryLower, 1, true) then
            ids[n.id] = true
        end
    end
    return ids
end
