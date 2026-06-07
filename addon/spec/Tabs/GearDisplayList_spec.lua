--[[
  Unit tests for Gear tab display list ordering (showSelfFirst behavior).
  Mirrors the split/sort logic from TabGear.lua GetDisplayList.
  Run from project root: npm test
]]

describe("Gear display list showSelfFirst", function()
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

    --- Mirror TabGear GetDisplayList split/sort (no hidden filter, realm filter, or item drop).
    local function buildDisplayList(visible, opts)
        opts = opts or {}
        local primary = opts.primarySort or "Time Played"
        local secondary = opts.secondarySort or "Name"
        local showSelfFirst = opts.showSelfFirst ~= false
        local currentName = opts.currentName or "Me"
        local currentRealm = opts.currentRealm or "RealmA"
        local charSettings = opts.charSettings or {}

        local function GetCharSetting(name, realm, key)
            local c = charSettings[(realm or "") .. "\\" .. (name or "")]
            if not c then return false end
            return c[key] == true
        end

        local selfEntry = nil
        local pinned = {}
        local nonPinned = {}
        for i = 1, #visible do
            local e = visible[i]
            local isSelf = (e.name == currentName and e.realm == currentRealm)
            if isSelf and showSelfFirst then
                selfEntry = e
            elseif GetCharSetting(e.name, e.realm, "pin") then
                pinned[#pinned + 1] = e
            else
                nonPinned[#nonPinned + 1] = e
            end
        end

        table.sort(pinned, function(a, b) return CompareBySort(a, b, primary, secondary) end)
        table.sort(nonPinned, function(a, b) return CompareBySort(a, b, primary, secondary) end)

        local list = {}
        if showSelfFirst and selfEntry then list[#list + 1] = selfEntry end
        for i = 1, #pinned do list[#list + 1] = pinned[i] end
        for i = 1, #nonPinned do list[#list + 1] = nonPinned[i] end
        return list
    end

    local sampleChars = {
        { name = "Alice", realm = "RealmA", played = 100 },
        { name = "Me", realm = "RealmA", played = 50 },
        { name = "Bob", realm = "RealmA", played = 75 },
    }

    it("puts self first when showSelfFirst is enabled", function()
        local list = buildDisplayList(sampleChars, { showSelfFirst = true })
        assert.are.equal("Me", list[1].name)
        assert.are.equal("Alice", list[2].name)
        assert.are.equal("Bob", list[3].name)
    end)

    it("sorts self by primary sort when showSelfFirst is disabled", function()
        local list = buildDisplayList(sampleChars, { showSelfFirst = false })
        assert.are.equal("Alice", list[1].name)
        assert.are.equal("Bob", list[2].name)
        assert.are.equal("Me", list[3].name)
    end)

    it("respects pin when showSelfFirst is disabled for self", function()
        local list = buildDisplayList(sampleChars, {
            showSelfFirst = false,
            charSettings = {
                ["RealmA\\Me"] = { pin = true },
            },
        })
        assert.are.equal("Me", list[1].name)
        assert.are.equal("Alice", list[2].name)
        assert.are.equal("Bob", list[3].name)
    end)
end)
