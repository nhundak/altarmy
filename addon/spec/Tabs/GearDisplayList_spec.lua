--[[
  Unit tests for Gear tab display list ordering (showSelfFirst + score sort).
  Mirrors the split/sort logic from TabGear.lua GetDisplayList.
  Run from project root: npm test
]]

describe("Gear display list showSelfFirst", function()
    local GetSortValue
    local CharKey

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        require("CharKey")
        require("CharacterSort")
        GetSortValue = AltArmy.CharacterSort.GetSortValue
        CharKey = AltArmy.CharKey
    end)

    local function compareBySelectedScore(entryA, entryB, sortKey, descending)
        local va = GetSortValue(entryA, sortKey)
        local vb = GetSortValue(entryB, sortKey)
        if va ~= vb then
            if descending then return va > vb else return va < vb end
        end
        return (entryA.name or "") < (entryB.name or "")
    end

    --- Mirror TabGear GetDisplayList split/sort (no realm filter or item drop).
    local function buildDisplayList(visible, opts)
        opts = opts or {}
        local sortKey = opts.sortKey or "Time Played"
        local descending = opts.scoreSortDescending ~= false
        local showSelfFirst = opts.showSelfFirst ~= false
        local currentName = opts.currentName or "Me"
        local currentRealm = opts.currentRealm or "RealmA"
        local charSettings = opts.charSettings or {}
        local inputList = opts.inputList

        local function GetCharSetting(name, realm, key)
            local c = charSettings[CharKey(name, realm)]
            if not c then return false end
            return c[key] == true
        end

        local filtered = visible
        if inputList then
            filtered = {}
            for i = 1, #inputList do
                local e = inputList[i]
                local isSelf = (e.name == currentName and e.realm == currentRealm)
                local isHidden = GetCharSetting(e.name, e.realm, "hide")
                if not isHidden or (showSelfFirst and isSelf) then
                    filtered[#filtered + 1] = e
                end
            end
        end

        local pinned = {}
        local nonPinned = {}
        for i = 1, #filtered do
            local e = filtered[i]
            local isSelf = (e.name == currentName and e.realm == currentRealm)
            local isPinned = GetCharSetting(e.name, e.realm, "pin")
            if isPinned or (showSelfFirst and isSelf) then
                pinned[#pinned + 1] = e
            else
                nonPinned[#nonPinned + 1] = e
            end
        end

        table.sort(pinned, function(a, b)
            return compareBySelectedScore(a, b, sortKey, descending)
        end)
        table.sort(nonPinned, function(a, b)
            return compareBySelectedScore(a, b, sortKey, descending)
        end)

        local list = {}
        for i = 1, #pinned do list[#list + 1] = pinned[i] end
        for i = 1, #nonPinned do list[#list + 1] = nonPinned[i] end
        return list
    end

    local sampleChars = {
        { name = "Alice", realm = "RealmA", played = 100 },
        { name = "Me", realm = "RealmA", played = 50 },
        { name = "Bob", realm = "RealmA", played = 75 },
    }

    it("puts self in pinned group when showSelfFirst is enabled", function()
        local list = buildDisplayList(sampleChars, { showSelfFirst = true })
        assert.are.equal("Me", list[1].name)
        assert.are.equal("Alice", list[2].name)
        assert.are.equal("Bob", list[3].name)
    end)

    it("sorts pin-current-character with other pinned characters by selected score", function()
        local chars = {
            { name = "Alice", realm = "RealmA", played = 100 },
            { name = "Me", realm = "RealmA", played = 50 },
            { name = "Bob", realm = "RealmA", played = 75 },
        }
        local list = buildDisplayList(chars, {
            showSelfFirst = true,
            charSettings = {
                ["RealmA\\Alice"] = { pin = true },
            },
        })
        assert.are.equal("Alice", list[1].name)
        assert.are.equal("Me", list[2].name)
        assert.are.equal("Bob", list[3].name)
    end)

    it("sorts self by selected score when showSelfFirst is disabled", function()
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

    it("sorts by selected score descending with name tie-break", function()
        local chars = {
            { name = "Bob", avgItemLevel = 100 },
            { name = "Alice", avgItemLevel = 120 },
            { name = "Zed", avgItemLevel = 120 },
        }
        local list = buildDisplayList(chars, {
            showSelfFirst = false,
            sortKey = "Avg Item Level",
            scoreSortDescending = true,
        })
        assert.are.equal("Alice", list[1].name)
        assert.are.equal("Zed", list[2].name)
        assert.are.equal("Bob", list[3].name)
    end)

    it("sorts ascending when scoreSortDescending is false", function()
        local chars = {
            { name = "Bob", avgItemLevel = 100 },
            { name = "Alice", avgItemLevel = 120 },
        }
        local list = buildDisplayList(chars, {
            showSelfFirst = false,
            sortKey = "Avg Item Level",
            scoreSortDescending = false,
        })
        assert.are.equal("Bob", list[1].name)
        assert.are.equal("Alice", list[2].name)
    end)

    it("shows hidden current character when pin current character is enabled", function()
        local chars = {
            { name = "Alice", realm = "RealmA", played = 100 },
            { name = "Me", realm = "RealmA", played = 50 },
            { name = "Bob", realm = "RealmA", played = 75 },
        }
        local list = buildDisplayList(chars, {
            showSelfFirst = true,
            inputList = chars,
            charSettings = {
                ["RealmA\\Me"] = { hide = true },
            },
        })
        assert.are.equal("Me", list[1].name)
        assert.are.equal(3, #list)
    end)

    it("respects hide for current character when pin current character is disabled", function()
        local chars = {
            { name = "Me", realm = "RealmA", played = 50 },
            { name = "Alice", realm = "RealmA", played = 100 },
        }
        local list = buildDisplayList(chars, {
            showSelfFirst = false,
            inputList = chars,
            charSettings = {
                ["RealmA\\Me"] = { hide = true },
            },
        })
        assert.are.equal(1, #list)
        assert.are.equal("Alice", list[1].name)
    end)
end)
