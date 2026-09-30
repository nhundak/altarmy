-- AltArmy TBC — what each Waylaid Crate on the auction house costs to buy and fill (Economy tab).
-- Pure: reads a decoded order book (AuctionBook.Decode) and the crate list (WaylaidCrates.lua).
-- luacheck: globals AltArmyTBC_Options

if not AltArmy then return end

AltArmy.WaylaidCosts = AltArmy.WaylaidCosts or {}
local W = AltArmy.WaylaidCosts

W.SORT_KEYS = { "crate", "price", "bundle", "bundleCost", "total" }
W.VIEWS = { currency = true, waylaid = true, supply = true }

local TIER_ORDER = { Apprentice = 1, Journeyman = 2, Expert = 3, Artisan = 4 }

--- The Economy tab's saved state, repaired and created on first use.
function W.EnsureOptions()
    if type(AltArmyTBC_Options) ~= "table" then
        AltArmyTBC_Options = {}
    end
    local o = AltArmyTBC_Options.economy
    if type(o) ~= "table" then
        o = {}
        AltArmyTBC_Options.economy = o
    end
    if not W.VIEWS[o.activeView] then
        o.activeView = "currency"
    end
    local validKey = false
    for _, k in ipairs(W.SORT_KEYS) do
        if o.waylaidSortKey == k then validKey = true end
    end
    if not validKey then
        o.waylaidSortKey = "total"
    end
    if type(o.waylaidSortAscending) ~= "boolean" then
        o.waylaidSortAscending = true
    end
    return o
end

--- Copper to buy `n` units, cheapest first up the ladder, or nil if fewer are listed.
--- Second result: true when units came from the tail level, priced at its cheapest (an estimate).
function W.CostForUnits(levels, n)
    if n <= 0 then return 0, false end
    if type(levels) ~= "table" then return nil end
    local left, cost, approx = n, 0, false
    for _, level in ipairs(levels) do
        local take = math.min(left, level.units)
        cost = cost + take * level.price
        if level.tail and take > 0 then approx = true end
        left = left - take
        if left == 0 then return cost, approx end
    end
    return nil
end

local function unitsListed(levels)
    local units = 0
    for _, level in ipairs(levels or {}) do
        units = units + level.units
    end
    return units
end

--- Cheapest bundle first; bundles that can't be bought in full last (short before unlisted), in list order.
local function sortOptions(options)
    local order = {}
    for i, opt in ipairs(options) do
        order[opt] = i
    end
    table.sort(options, function(a, b)
        if a.cost and b.cost then
            if a.cost ~= b.cost then return a.cost < b.cost end
        elseif a.cost or b.cost then
            return a.cost ~= nil
        elseif (a.listed > 0) ~= (b.listed > 0) then
            return a.listed > 0
        end
        return order[a] < order[b]
    end)
end

--- One row per crate listed in `book` (itemID -> ladder): its cheapest price and the cheapest bundle
--- that can be bought in full. `crates` is AltArmy.WaylaidCrates (LIST).
function W.BuildRows(book, crates)
    local rows = {}
    for _, crate in ipairs(crates.LIST) do
        local ladder = book[crate.id]
        if ladder and ladder[1] then
            local row = {
                id = crate.id, name = crate.name, short = crate.short, tier = crate.tier, kind = crate.kind,
                random = crate.random == true, price = ladder[1].price, listed = unitsListed(ladder),
                options = {}, shortBundles = 0, unlisted = 0,
            }
            for _, b in ipairs(crate.bundles) do
                local cost, approx = W.CostForUnits(book[b.item], b.count)
                local listed = unitsListed(book[b.item])
                row.options[#row.options + 1] = { item = b.item, name = b.name, count = b.count,
                    cost = cost, approx = approx, listed = listed }
                if cost then
                    if not row.bundle or cost < row.bundle.cost then
                        row.bundle = row.options[#row.options]
                    end
                elseif listed > 0 then
                    row.shortBundles = row.shortBundles + 1
                else
                    row.unlisted = row.unlisted + 1
                end
            end
            sortOptions(row.options)
            if row.bundle then
                row.total = row.price + row.bundle.cost
                row.bundleText = row.bundle.count .. " x " .. row.bundle.name
            elseif row.random then
                row.bundleText = "random"
            elseif row.shortBundles > 0 then
                row.bundleText = "not enough listed"
            else
                row.bundleText = "none listed"
            end
            rows[#rows + 1] = row
        end
    end
    return rows
end

local function tierRank(row)
    return TIER_ORDER[row.tier] or 99
end

--- table.sort order for rows by `key` (one of SORT_KEYS: "bundle" is the cheapest fill's name).
--- Rows without the money being sorted stay last in both directions; ties fall back to tier then name.
function W.Compare(a, b, key, ascending)
    local function ordered(x, y)
        if x == y then return nil end
        if ascending then return x < y end
        return x > y
    end
    local r
    if key == "total" or key == "bundleCost" then
        local x, y
        if key == "total" then
            x, y = a.total, b.total
        else
            x, y = a.bundle and a.bundle.cost, b.bundle and b.bundle.cost
        end
        if x == nil and y ~= nil then return false end
        if y == nil and x ~= nil then return true end
        if x ~= nil then r = ordered(x, y) end
    elseif key == "price" then
        r = ordered(a.price or 0, b.price or 0)
    elseif key == "bundle" then
        r = ordered(a.bundle and a.bundle.name or "~", b.bundle and b.bundle.name or "~")
    else -- crate: tier, then name
        r = ordered(tierRank(a), tierRank(b))
        if r == nil then r = ordered(a.name or "", b.name or "") end
    end
    if r ~= nil then return r end
    r = ordered(tierRank(a), tierRank(b))
    if r ~= nil then return r end
    return (a.name or "") < (b.name or "")
end

--- "Scanned 2 hr ago", from the scan's time and now (server time); `fmt` formats seconds.
function W.AgeText(scanTime, now, fmt)
    local age = (now or 0) - (scanTime or 0)
    if age < 60 then
        return "Scanned just now"
    end
    return "Scanned " .. fmt(age) .. " ago"
end

--- How much to trust a scan's prices by its age: "fresh" under 15 min, "stale" up to 30, then "old".
function W.AgeLevel(scanTime, now)
    local age = (now or 0) - (scanTime or 0)
    if age < 15 * 60 then
        return "fresh"
    elseif age <= 30 * 60 then
        return "stale"
    end
    return "old"
end
