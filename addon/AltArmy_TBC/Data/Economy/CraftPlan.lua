-- AltArmy TBC — the cheapest way to get an item: buy it from a vendor, buy it up the auction house's
-- ladder, or craft it from reagents got the same way, by whichever of the player's characters knows the
-- recipe (Economy tab, Craftsman's Writs). Pure: everything comes in through `ctx`.
--
-- ctx = {
--   book       itemID -> ladder (AuctionBook.Decode: { price, units, listings, tail } cheapest first); {} with no scan
--   items      itemID -> { name, stack, vendor = copper per `per` units (a vendor sells it), bop = true }
--   recipes    spellID -> { out, n, prof, name, reagents = { { item, count }, ... } }
--   byOutput   itemID -> { spellID, ... } the recipes making it
--   knownBy    function(spellID) -> the name of a character who knows it, or nil
--   discountOf function(name or nil) -> that character's vendor discount, 0..1 (nil: the current character)
--   current    the current character's name
--   maxDepth   how many crafts deep a plan may go (default MAX_DEPTH)
-- }
-- A node: { item, qty, option = "vendor"|"ah"|"craft", cost, who, short, approx, spell, casts, children }.
-- `who` is who buys (the character the units are for) or who crafts; `short` the units the auction house
-- is short of, priced at its dearest level; `approx` when a cost rests on a folded tail level (a summary
-- scan's one level per item is taken as it is: the view marks only the scan as a summary). A craft's
-- reagents are bought at its crafter's discount. Casts are whole, and what a cast makes beyond the units
-- wanted is not credited. Each branch is planned as if the cheapest listings were its own; `Share` then
-- re-costs the auction house buys of one item across branches up its ladder, which can leave a chosen craft
-- dearer than the buy it beat (the plan stays as chosen).

if not AltArmy then return end

AltArmy.CraftPlan = AltArmy.CraftPlan or {}
local P = AltArmy.CraftPlan

P.MAX_DEPTH = 8

--- Copper for one unit at a vendor, the discount taken off and rounded up.
function P.VendorUnitPrice(entry, discount)
    return math.ceil(entry.vendor / (entry.per or 1) * (1 - (discount or 0)))
end

--- Copper for `n` units off the auction house, cheapest first, after `skip` units already taken from the
--- ladder; units the book is short of cost its dearest level. Returns cost, units short, approx (the tail
--- level was touched), or nil when nothing is listed.
function P.AhCost(levels, n, skip)
    if type(levels) ~= "table" or not levels[1] then return nil end
    local left, toSkip, cost, approx = n, skip or 0, 0, false
    for _, level in ipairs(levels) do
        local units = level.units
        local skipped = math.min(toSkip, units)
        toSkip, units = toSkip - skipped, units - skipped
        local take = math.min(left, units)
        if take > 0 then
            cost = cost + take * level.price
            left = left - take
            if level.tail then approx = true end
        end
        if left == 0 then return cost, 0, approx end
    end
    return cost + left * levels[#levels].price, left, approx
end

local function cheaper(a, b)
    return a and (not b or a.cost < b.cost)
end

local plan -- forward

--- The cheapest craft of `qty` units of `item` by a known recipe, or nil.
local function craft(item, qty, ctx, depth, visiting)
    local best
    for _, spell in ipairs(ctx.byOutput[item] or {}) do
        local recipe = ctx.recipes[spell]
        local who = recipe and ctx.knownBy(spell)
        if who then
            local casts = math.ceil(qty / recipe.n)
            local node = { item = item, qty = qty, option = "craft", who = who, spell = spell, casts = casts,
                cost = 0, short = 0, approx = false, children = {} }
            for _, r in ipairs(recipe.reagents) do
                local child = plan(r.item, r.count * casts, ctx, who, depth + 1, visiting)
                if not child then
                    node = nil
                    break
                end
                node.children[#node.children + 1] = child
                node.cost = node.cost + child.cost
                node.short = node.short + child.short
                node.approx = node.approx or child.approx
            end
            if cheaper(node, best) then best = node end
        end
    end
    return best
end

function plan(item, qty, ctx, consumer, depth, visiting)
    if visiting[item] then return nil end -- a recipe consuming its own output
    local entry = ctx.items[item]
    local best
    if entry and entry.vendor then
        local unit = P.VendorUnitPrice(entry, ctx.discountOf(consumer))
        best = { item = item, qty = qty, option = "vendor", who = consumer or ctx.current, cost = unit * qty,
            short = 0, approx = false }
    end
    if not (entry and entry.bop) then
        local cost, short, approx = P.AhCost(ctx.book[item], qty)
        if cost then
            local node = { item = item, qty = qty, option = "ah", cost = cost, short = short, approx = approx }
            if cheaper(node, best) then best = node end
        end
    end
    if depth < (ctx.maxDepth or P.MAX_DEPTH) then
        visiting[item] = true
        local node = craft(item, qty, ctx, depth, visiting)
        visiting[item] = nil
        if cheaper(node, best) then best = node end
    end
    return best
end

--- The cheapest plan for `qty` units of `item`, bought for `consumer` (nil: the current character), or
--- nil when there is no way to get it.
function P.Plan(item, qty, ctx, consumer)
    return plan(item, qty, ctx, consumer, 0, {})
end

--- The cheapest plan that crafts `qty` units of `item` (its reagents got their cheapest way), or nil when
--- nobody knows a recipe for it or a reagent has no route.
function P.Craft(item, qty, ctx)
    return craft(item, qty, ctx, 0, { [item] = true })
end

local function countAhBuys(node, buys)
    if node.option == "ah" then
        buys[node.item] = (buys[node.item] or 0) + 1
    end
    for _, child in ipairs(node.children or {}) do
        countAhBuys(child, buys)
    end
end

local function recost(node, ctx, shared, taken)
    if node.option == "ah" and shared[node.item] then
        local skip = taken[node.item] or 0
        taken[node.item] = skip + node.qty
        local cost, short, approx = P.AhCost(ctx.book[node.item], node.qty, skip)
        return { item = node.item, qty = node.qty, option = "ah", cost = cost, short = short, approx = approx }
    end
    if not node.children then return node end
    local out = {}
    for k, v in pairs(node) do out[k] = v end
    out.children, out.cost, out.short, out.approx = {}, 0, 0, false
    for i, child in ipairs(node.children) do
        local c = recost(child, ctx, shared, taken)
        out.children[i] = c
        out.cost = out.cost + c.cost
        out.short = out.short + c.short
        out.approx = out.approx or c.approx
    end
    return out
end

--- `node` with the auction house buys of an item that several branches buy re-costed as one walk up the
--- item's ladder, in the plan's order; the plan given is left alone. The same plan when nothing is shared.
function P.Share(node, ctx)
    local buys = {}
    countAhBuys(node, buys)
    local shared, any = {}, false
    for item, times in pairs(buys) do
        if times > 1 then
            shared[item], any = true, true
        end
    end
    if not any then return node end
    return recost(node, ctx, shared, {})
end

local function collect(node, steps, index)
    if node.option == "craft" then
        for _, child in ipairs(node.children) do
            collect(child, steps, index)
        end
        local key = "craft:" .. node.spell .. ":" .. node.who
        local step = index[key]
        if step then
            step.qty = step.qty + node.qty
            step.casts = step.casts + node.casts
        else
            step = { kind = "craft", who = node.who, item = node.item, qty = node.qty, spell = node.spell,
                casts = node.casts }
            index[key] = step
            steps.crafts[#steps.crafts + 1] = step
        end
        return
    end
    local list, key = steps.ah, "ah:" .. node.item
    if node.option == "vendor" then
        list, key = steps.vendor, "vendor:" .. node.who .. ":" .. node.item
    end
    local step = index[key]
    if step then
        step.qty = step.qty + node.qty
        step.cost = step.cost + node.cost
        step.short = step.short + node.short
        step.approx = step.approx or node.approx
    else
        step = { kind = node.option, who = node.who, item = node.item, qty = node.qty, cost = node.cost,
            short = node.short, approx = node.approx }
        index[key] = step
        list[#list + 1] = step
    end
end

--- The plan as steps: vendor buys (per buyer and item), then auction house buys (per item), then crafts
--- bottom up (per recipe and crafter), each { kind, who, item, qty, cost, short, approx } or
--- { kind = "craft", who, item, qty, spell, casts }.
function P.Steps(node)
    local steps = { vendor = {}, ah = {}, crafts = {} }
    collect(node, steps, {})
    local out = {}
    for _, list in ipairs({ steps.vendor, steps.ah, steps.crafts }) do
        for _, step in ipairs(list) do
            out[#out + 1] = step
        end
    end
    return out
end
