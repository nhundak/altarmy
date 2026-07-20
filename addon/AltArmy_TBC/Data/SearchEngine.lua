-- AltArmy TBC — Search engine facade over SearchData.
-- TabSearch and other UI call through this module for a stable public API.

AltArmy = AltArmy or {}
AltArmy.SearchEngine = AltArmy.SearchEngine or {}

local SE = AltArmy.SearchEngine

local function eng()
    return AltArmy.SearchData
end

function SE.SearchItems(query, skipTooltip)
    local e = eng()
    if e.SearchItems then
        return e.SearchItems(query, skipTooltip)
    end
    return e.SearchWithLocationGroups(query, skipTooltip)
end

function SE.SearchWithLocationGroups(query, skipTooltip)
    return SE.SearchItems(query, skipTooltip)
end

function SE.SearchRecipes(query)
    return eng().SearchRecipes(query)
end

function SE.SearchGuildRecipes(query)
    local e = eng()
    if e.SearchGuildRecipes then
        return e.SearchGuildRecipes(query)
    end
    return {}
end

function SE.MergeRecipeSearchResults(localList, guildList)
    local e = eng()
    if e.MergeRecipeSearchResults then
        return e.MergeRecipeSearchResults(localList, guildList)
    end
    local out = {}
    local n = 0
    for i = 1, #(localList or {}) do
        n = n + 1
        out[n] = localList[i]
    end
    for i = 1, #(guildList or {}) do
        n = n + 1
        out[n] = guildList[i]
    end
    return out
end

function SE.SortItemResults(list, sortKey, ascending)
    return eng().SortItemResults(list, sortKey, ascending)
end

function SE.SortRecipeResults(list, sortKey, ascending, craftLibAvailable)
    return eng().SortRecipeResults(list, sortKey, ascending, craftLibAvailable)
end

function SE.CollapseGuildRecipeRows(sortedList, expandedSet)
    local e = eng()
    if e.CollapseGuildRecipeRows then
        return e.CollapseGuildRecipeRows(sortedList, expandedSet)
    end
    return sortedList
end

function SE.EnsureRecipeDisplayCache(entry)
    local e = eng()
    if e.EnsureRecipeDisplayCache then
        return e.EnsureRecipeDisplayCache(entry)
    end
    return entry
end

function SE.EnrichRecipeEntry(entry)
    local e = eng()
    if e.EnrichRecipeEntry then
        return e.EnrichRecipeEntry(entry)
    end
    if e._EnrichRecipeEntry then
        return e._EnrichRecipeEntry(entry)
    end
    return entry
end

SE._EnrichRecipeEntry = SE.EnrichRecipeEntry

function SE.GetSearchTailDebounceSecs(trimmedQuery)
    local e = eng()
    if e.GetSearchTailDebounceSecs then
        return e.GetSearchTailDebounceSecs(trimmedQuery)
    end
    return 0.4
end

function SE.GetAllContainerSlots()
    local e = eng()
    if e.GetAllContainerSlots then
        return e.GetAllContainerSlots()
    end
    return {}
end

function SE._ParseItemSearchQuery(query)
    local e = eng()
    if e._ParseItemSearchQuery then
        return e._ParseItemSearchQuery(query)
    end
    local queryLower = type(query) == "string" and query:lower() or nil
    local queryID = nil
    if type(query) == "number" then
        queryID = query
    elseif type(query) == "string" and query:match("^%d+$") then
        queryID = tonumber(query)
    end
    return queryLower, queryID
end

function SE._IsMainSearchMatch(entry, queryLower, queryID)
    local e = eng()
    if e._IsMainSearchMatch then
        return e._IsMainSearchMatch(entry, queryLower, queryID)
    end
    return false
end

function SE._GetSearchableTextForItem(itemID, itemLink)
    local e = eng()
    if e._GetSearchableTextForItem then
        return e._GetSearchableTextForItem(itemID, itemLink)
    end
    return nil
end

function SE._EnsureItemName(entry)
    local e = eng()
    if e._EnsureItemName then
        return e._EnsureItemName(entry)
    end
    return entry and entry.itemName
end

function SE._AggregateAndSort(raw, queryLower, timings)
    local e = eng()
    if e._AggregateAndSort then
        return e._AggregateAndSort(raw, queryLower, timings)
    end
    return raw or {}
end

function SE.StartRecipeResultPrewarm(list)
    local e = eng()
    if e.StartRecipeResultPrewarm then
        e.StartRecipeResultPrewarm(list)
    end
end

function SE.BeginScrollPaintDebug()
    local e = eng()
    if e and e.BeginScrollPaintDebug then
        return e.BeginScrollPaintDebug()
    end
    return nil
end

function SE.EndScrollPaintDebug(stats, now)
    local e = eng()
    if e and e.EndScrollPaintDebug then
        return e.EndScrollPaintDebug(stats, now)
    end
    return false
end

function SE.NoteScrollItemPaint(stats)
    local e = eng()
    if e and e.NoteScrollItemPaint then
        e.NoteScrollItemPaint(stats)
    end
end

function SE.NoteScrollRecipePaint(stats, entry)
    local e = eng()
    if e and e.NoteScrollRecipePaint then
        e.NoteScrollRecipePaint(stats, entry)
    end
end

function SE.NoteScrollTooltipPaint(stats)
    local e = eng()
    if e and e.NoteScrollTooltipPaint then
        e.NoteScrollTooltipPaint(stats)
    end
end

function SE.NotifyContainerDataChanged()
    local e = eng()
    if e and e.NotifyContainerDataChanged then
        e.NotifyContainerDataChanged()
    end
end

function SE.NotifyRecipesChanged()
    local e = eng()
    if e and e.NotifyRecipesChanged then
        e.NotifyRecipesChanged()
    end
end
