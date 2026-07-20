-- AltArmy TBC — StockpilePlan: pure stack planning for mail attachments.
-- Produces a sequence of operations (attach / merge / split+attach) without calling WoW APIs.

if not AltArmy then return end

AltArmy.StockpilePlan = AltArmy.StockpilePlan or {}
local SP = AltArmy.StockpilePlan

-- stacks: { {bagID=number, slot=number, count=number}, ... }
local function normalizeStacks(stacks)
    local out = {}
    if type(stacks) ~= "table" then return out end
    for _, s in ipairs(stacks) do
        local bagID = s and s.bagID
        local slot = s and s.slot
        local count = s and s.count
        if type(bagID) == "number" and type(slot) == "number" and type(count) == "number" and count > 0 then
            out[#out + 1] = { bagID = bagID, slot = slot, count = count }
        end
    end
    return out
end

local function sumCounts(stacks)
    local total = 0
    for _, s in ipairs(stacks) do
        total = total + (s.count or 0)
    end
    return total
end

local function removeAt(t, idx)
    local v = t[idx]
    table.remove(t, idx)
    return v
end

local function sortExactFirstThenDesc(stacks, target)
    table.sort(stacks, function(a, b)
        local ac, bc = a.count or 0, b.count or 0
        local aExact = ac == target
        local bExact = bc == target
        if aExact ~= bExact then
            return aExact
        end
        if ac ~= bc then
            return ac > bc
        end
        if a.bagID ~= b.bagID then return a.bagID < b.bagID end
        return a.slot < b.slot
    end)
end

local function findBestSplitSourceIndex(stacks, remaining)
    local bestIdx, bestCount = nil, nil
    for i, s in ipairs(stacks) do
        local c = s.count or 0
        if c > remaining then
            if not bestCount or c < bestCount then
                bestIdx, bestCount = i, c
            end
        end
    end
    return bestIdx
end

local function findBestTopUpSplit(stacks, remaining)
    -- Find a destination stack with 0 < dst < remaining, and a source stack to split from.
    -- Returns dstIdx, srcIdx, splitCount.
    local best = nil
    for di, dst in ipairs(stacks) do
        local dc = dst.count or 0
        if dc > 0 and dc < remaining then
            local needSplit = remaining - dc
            local srcIdx = nil
            local srcCount = nil
            for si, src in ipairs(stacks) do
                if si ~= di then
                    local sc = src.count or 0
                    if sc > needSplit then
                        if not srcCount or sc < srcCount then
                            srcIdx = si
                            srcCount = sc
                        end
                    end
                end
            end
            if srcIdx then
                local candidate = {
                    dstIdx = di,
                    srcIdx = srcIdx,
                    splitCount = needSplit,
                    dstCount = dc,
                    srcCount = srcCount,
                }
                if not best then
                    best = candidate
                else
                    -- Prefer larger dst (fewer moves) then smaller src (less churn)
                    if candidate.dstCount > best.dstCount
                        or (candidate.dstCount == best.dstCount and candidate.srcCount < best.srcCount)
                    then
                        best = candidate
                    end
                end
            end
        end
    end
    if not best then return nil, nil, nil end
    return best.dstIdx, best.srcIdx, best.splitCount
end

local function findMergeSetIndices(stacks, remaining, stackLimit)
    -- Greedy: merge smallest into a destination until >= remaining, keeping <= stackLimit.
    -- Returns {dstIndex, srcIndices...} (indices in the current stacks table).
    local idxs = {}
    for i = 1, #stacks do idxs[i] = i end
    table.sort(idxs, function(i, j)
        return (stacks[i].count or 0) < (stacks[j].count or 0)
    end)
    if #idxs < 2 then return nil end

    local dstIdx = idxs[#idxs] -- start with largest as destination to reduce moves
    local dstCount = stacks[dstIdx].count or 0
    if dstCount >= remaining then
        return { dstIdx }
    end

    local srcs = {}
    for k = 1, #idxs - 1 do
        local si = idxs[k]
        local sc = stacks[si].count or 0
        if sc > 0 then
            if dstCount + sc <= stackLimit then
                dstCount = dstCount + sc
                srcs[#srcs + 1] = si
                if dstCount >= remaining then
                    local out = { dstIdx }
                    for _, v in ipairs(srcs) do out[#out + 1] = v end
                    return out
                end
            end
        end
    end
    return nil
end

--- Build a plan to attach exactly `need` units using stacks.
--- @param need number
--- @param stacks table[] {bagID, slot, count}
--- @param constraints table
--- { allowMerge?:boolean, preferExact?:boolean, stackLimit:number, maxAttachments:number, emptySlotsAvailable:number }
--- @return table result { ok:boolean, reason?:string, attachments:number, ops:table[] }
function SP.BuildItemPlan(need, stacks, constraints)
    local n = tonumber(need) or 0
    if n <= 0 then
        return { ok = true, attachments = 0, ops = {} }
    end
    constraints = constraints or {}
    local allowMerge = constraints.allowMerge ~= false
    local preferExact = constraints.preferExact ~= false
    local stackLimit = tonumber(constraints.stackLimit) or 0
    local maxAttachments = tonumber(constraints.maxAttachments) or 12
    local emptySlotsAvailable = tonumber(constraints.emptySlotsAvailable) or 0
    if stackLimit <= 0 then
        return { ok = false, reason = "missing_stack_limit", attachments = 0, ops = {} }
    end

    local st = normalizeStacks(stacks)
    if sumCounts(st) < n then
        return { ok = false, reason = "not_enough_items", attachments = 0, ops = {} }
    end

    local ops = {}
    local attachments = 0
    local remaining = n
    local SMALL_REMAINDER_PREFER_SPLIT = 5

    -- Phase 0: harvest existing full stacks first (H-case).
    if remaining >= stackLimit then
        table.sort(st, function(a, b) return (a.count or 0) > (b.count or 0) end)
        for i = #st, 1, -1 do
            local c = st[i].count or 0
            if c == stackLimit and remaining >= stackLimit then
                ops[#ops + 1] = { op = "attach", bagID = st[i].bagID, slot = st[i].slot, count = c }
                attachments = attachments + 1
                remaining = remaining - c
                removeAt(st, i)
                if attachments > maxAttachments then
                    return { ok = false, reason = "too_many_attachments", attachments = attachments, ops = ops }
                end
            end
        end
    end

    while remaining > 0 do
        local attachmentBudget = maxAttachments - attachments
        if attachmentBudget <= 0 then
            return { ok = false, reason = "too_many_attachments", attachments = attachments, ops = ops }
        end

        if preferExact then
            sortExactFirstThenDesc(st, remaining)
        else
            table.sort(st, function(a, b) return (a.count or 0) > (b.count or 0) end)
        end

        -- If only one attachment remains, we must finish in a single attach (possibly after merges).
        if attachmentBudget == 1 then
            -- Exact attach if possible
            for i, s in ipairs(st) do
                if (s.count or 0) == remaining then
                    local ss = removeAt(st, i)
                    ops[#ops + 1] = { op = "attach", bagID = ss.bagID, slot = ss.slot, count = ss.count }
                    attachments = attachments + 1
                    remaining = 0
                    break
                end
            end
            if remaining == 0 then
                break
            end

            -- Split from the smallest stack that is still > remaining
            local splitIdx = findBestSplitSourceIndex(st, remaining)
            if splitIdx then
                if emptySlotsAvailable <= 0 then
                    return { ok = false, reason = "no_empty_slot_for_split", attachments = attachments, ops = ops }
                end
                local s = st[splitIdx]
                ops[#ops + 1] = { op = "split_attach", bagID = s.bagID, slot = s.slot, count = remaining }
                attachments = attachments + 1
                break
            end

            -- Merge to reach remaining, then attach or split_attach
            if allowMerge then
                local mergeSet = findMergeSetIndices(st, remaining, stackLimit)
                if not mergeSet or #mergeSet < 2 then
                    return { ok = false, reason = "too_many_attachments", attachments = attachments, ops = ops }
                end
                local dstIdx = mergeSet[1]
                local dst = st[dstIdx]
                local srcIdxs = {}
                for k = 2, #mergeSet do srcIdxs[#srcIdxs + 1] = mergeSet[k] end
                table.sort(srcIdxs, function(a, b) return a > b end)
                local mergedCount = dst.count or 0
                for _, si in ipairs(srcIdxs) do
                    local src = st[si]
                    ops[#ops + 1] = {
                        op = "merge",
                        srcBagID = src.bagID,
                        srcSlot = src.slot,
                        dstBagID = dst.bagID,
                        dstSlot = dst.slot,
                        count = src.count,
                    }
                    mergedCount = mergedCount + (src.count or 0)
                    removeAt(st, si)
                    if si < dstIdx then
                        dstIdx = dstIdx - 1
                    end
                end
                dst.count = mergedCount
                if mergedCount == remaining then
                    ops[#ops + 1] = { op = "attach", bagID = dst.bagID, slot = dst.slot, count = mergedCount }
                    attachments = attachments + 1
                    break
                elseif mergedCount > remaining then
                    if emptySlotsAvailable <= 0 then
                        return { ok = false, reason = "no_empty_slot_for_split", attachments = attachments, ops = ops }
                    end
                    ops[#ops + 1] = { op = "split_attach", bagID = dst.bagID, slot = dst.slot, count = remaining }
                    attachments = attachments + 1
                    break
                end
            end

            return { ok = false, reason = "too_many_attachments", attachments = attachments, ops = ops }
        end

        -- 1) Use exact match if present, else largest <= remaining.
        local pickedIdx = nil
        for i, s in ipairs(st) do
            local c = s.count or 0
            if c == remaining then
                pickedIdx = i
                break
            end
        end

        -- Prefer topping up an existing partial stack to avoid consuming an empty slot (and reduce bag churn).
        -- Example: need=2, stacks {8,1} -> split 1 from 8 into the 1 stack, then attach the 2 stack.
        if not pickedIdx then
            local dstIdx, srcIdx, splitCount = findBestTopUpSplit(st, remaining)
            if dstIdx and srcIdx and splitCount then
                local dst = st[dstIdx]
                local src = st[srcIdx]
                ops[#ops + 1] = {
                    op = "split_merge_attach",
                    srcBagID = src.bagID,
                    srcSlot = src.slot,
                    dstBagID = dst.bagID,
                    dstSlot = dst.slot,
                    count = splitCount,
                    finalCount = remaining,
                }
                attachments = attachments + 1
                if attachments > maxAttachments then
                    return { ok = false, reason = "too_many_attachments", attachments = attachments, ops = ops }
                end
                break
            end
        end

        -- Heuristic: for very small remainder, prefer one split_attach (reduces extra 1-stack attachments)
        if not pickedIdx and remaining <= SMALL_REMAINDER_PREFER_SPLIT then
            local splitIdx = findBestSplitSourceIndex(st, remaining)
            if splitIdx then
                if emptySlotsAvailable <= 0 then
                    return { ok = false, reason = "no_empty_slot_for_split", attachments = attachments, ops = ops }
                end
                local s = st[splitIdx]
                ops[#ops + 1] = { op = "split_attach", bagID = s.bagID, slot = s.slot, count = remaining }
                attachments = attachments + 1
                if attachments > maxAttachments then
                    return { ok = false, reason = "too_many_attachments", attachments = attachments, ops = ops }
                end
                break
            end
        end

        if not pickedIdx then
            for i, s in ipairs(st) do
                local c = s.count or 0
                if c > 0 and c <= remaining then
                    pickedIdx = i
                    break
                end
            end
        end

        if pickedIdx then
            local s = removeAt(st, pickedIdx)
            ops[#ops + 1] = { op = "attach", bagID = s.bagID, slot = s.slot, count = s.count }
            attachments = attachments + 1
            remaining = remaining - (s.count or 0)
            if attachments > maxAttachments then
                return { ok = false, reason = "too_many_attachments", attachments = attachments, ops = ops }
            end
        else
            -- 2) Need remaining but no stack <= remaining: either split a larger one or merge smaller ones.
            local splitIdx = findBestSplitSourceIndex(st, remaining)
            if splitIdx then
                if emptySlotsAvailable <= 0 then
                    return { ok = false, reason = "no_empty_slot_for_split", attachments = attachments, ops = ops }
                end
                local s = st[splitIdx]
                ops[#ops + 1] = {
                    op = "split_attach",
                    bagID = s.bagID,
                    slot = s.slot,
                    count = remaining,
                }
                attachments = attachments + 1
                emptySlotsAvailable = emptySlotsAvailable - 1
                remaining = 0
                if attachments > maxAttachments then
                    return { ok = false, reason = "too_many_attachments", attachments = attachments, ops = ops }
                end
            elseif allowMerge then
                local mergeSet = findMergeSetIndices(st, remaining, stackLimit)
                if not mergeSet or #mergeSet < 2 then
                    return { ok = false, reason = "cannot_merge_to_reach_need", attachments = attachments, ops = ops }
                end

                -- mergeSet = {dstIdx, srcIdx1, srcIdx2, ...}
                local dstIdx = mergeSet[1]
                local dst = st[dstIdx]
                -- perform merges; sort src indices descending so removing doesn't shift earlier indices
                local srcIdxs = {}
                for k = 2, #mergeSet do srcIdxs[#srcIdxs + 1] = mergeSet[k] end
                table.sort(srcIdxs, function(a, b) return a > b end)
                local mergedCount = dst.count or 0
                for _, si in ipairs(srcIdxs) do
                    local src = st[si]
                    ops[#ops + 1] = {
                        op = "merge",
                        srcBagID = src.bagID,
                        srcSlot = src.slot,
                        dstBagID = dst.bagID,
                        dstSlot = dst.slot,
                        count = src.count,
                    }
                    mergedCount = mergedCount + (src.count or 0)
                    removeAt(st, si)
                    -- dstIdx might shift if we removed before it; keep dst as object, update later.
                    if si < dstIdx then
                        dstIdx = dstIdx - 1
                    end
                end
                -- update dst count
                dst.count = mergedCount

                -- Now either attach merged directly (if == remaining) or split_attach it.
                if mergedCount == remaining then
                    ops[#ops + 1] = { op = "attach", bagID = dst.bagID, slot = dst.slot, count = mergedCount }
                    attachments = attachments + 1
                    remaining = 0
                    removeAt(st, dstIdx)
                elseif mergedCount > remaining then
                    if emptySlotsAvailable <= 0 then
                        return { ok = false, reason = "no_empty_slot_for_split", attachments = attachments, ops = ops }
                    end
                    ops[#ops + 1] = {
                        op = "split_attach",
                        bagID = dst.bagID,
                        slot = dst.slot,
                        count = remaining,
                    }
                    attachments = attachments + 1
                    emptySlotsAvailable = emptySlotsAvailable - 1
                    remaining = 0
                    -- Keep dst stack in st (it still exists in bags).
                    -- Planner doesn’t model post-split residue precisely.
                end

                if attachments > maxAttachments then
                    return { ok = false, reason = "too_many_attachments", attachments = attachments, ops = ops }
                end
            else
                return { ok = false, reason = "cannot_split_or_merge", attachments = attachments, ops = ops }
            end
        end
    end

    return { ok = true, attachments = attachments, ops = ops }
end

