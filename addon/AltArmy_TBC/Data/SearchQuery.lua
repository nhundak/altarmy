-- AltArmy TBC — Search query: name scan, expand via byId, prefix-narrowing memo.

AltArmy = AltArmy or {}
AltArmy.SearchQuery = AltArmy.SearchQuery or {}

local SQ = AltArmy.SearchQuery

function SQ.ParseQuery(query)
    local queryLower = type(query) == "string" and query:lower() or nil
    local queryID = nil
    if type(query) == "number" then
        queryID = query
    elseif type(query) == "string" and query:match("^%d+$") then
        queryID = tonumber(query)
    end
    return queryLower, queryID
end

local function canNarrow(memo, queryLower)
    if not memo or not memo.prevQuery or not memo.prevIds or not queryLower then
        return false
    end
    local prev = memo.prevQuery
    if prev == "" or #queryLower < #prev then
        return false
    end
    return queryLower:sub(1, #prev) == prev
end

local function expandIds(byId, ids, dest, seen)
    for id in pairs(ids or {}) do
        local rows = byId and byId[id]
        if rows then
            for i = 1, #rows do
                local entry = rows[i]
                if entry and not seen[entry] then
                    seen[entry] = true
                    dest[#dest + 1] = entry
                end
            end
        end
    end
end

local function profileMark(timings, key)
    if not timings then
        return
    end
    local ms = 0
    if debugprofilestop then
        ms = debugprofilestop()
    end
    timings[key] = (timings[key] or 0) + ms
    timings.total = (timings.total or 0) + ms
    if debugprofilestart then
        debugprofilestart()
    end
end

--- Match item index; updates memo.prevQuery / memo.prevIds for narrowing.
--- Optional timings table records lookup / expand ms (debugprofilestart must already be running).
function SQ.MatchAndExpandItems(index, queryLower, queryID, memo, timings)
    local results = {}
    local seen = {}
    if not index then
        return results
    end
    memo = memo or {}
    local matchedIds = {}

    if queryID ~= nil then
        matchedIds[queryID] = true
        expandIds(index.byId, matchedIds, results, seen)
    end

    if queryLower and queryLower ~= "" then
        local SI = AltArmy.SearchIndex
        local prevIds = canNarrow(memo, queryLower) and memo.prevIds or nil
        local ids = SI.MatchNameIds(index.names, queryLower, prevIds)
        for id in pairs(ids) do
            matchedIds[id] = true
        end
        profileMark(timings, "lookup")
        expandIds(index.byId, ids, results, seen)

        -- Link-only fallback for IDs not matched by name.
        for itemID, rows in pairs(index.byId or {}) do
            if not matchedIds[itemID] then
                local entry = rows[1]
                if entry and entry.itemLink and entry.itemLink:lower():find(queryLower, 1, true) then
                    matchedIds[itemID] = true
                    expandIds(index.byId, { [itemID] = true }, results, seen)
                end
            end
        end
        profileMark(timings, "expand")

        memo.prevQuery = queryLower
        memo.prevIds = matchedIds
    else
        profileMark(timings, "lookup")
        profileMark(timings, "expand")
        memo.prevQuery = nil
        memo.prevIds = nil
    end

    return results
end

function SQ.MatchAndExpandRecipes(index, queryLower, memo, timings)
    local results = {}
    local seen = {}
    if not index or not queryLower or queryLower == "" then
        profileMark(timings, "lookup")
        profileMark(timings, "expand")
        return results
    end
    memo = memo or {}
    local SI = AltArmy.SearchIndex
    local prevIds = canNarrow(memo, queryLower) and memo.prevIds or nil
    local ids = SI.MatchNameIds(index.names, queryLower, prevIds)
    profileMark(timings, "lookup")
    -- recipeNameLower is stamped onto entries at index build (stampNameKey).
    expandIds(index.byId, ids, results, seen)
    profileMark(timings, "expand")
    memo.prevQuery = queryLower
    memo.prevIds = ids
    return results
end
