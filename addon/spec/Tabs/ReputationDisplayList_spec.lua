--[[
  Unit tests for Reputation tab display list ordering.
  Pinned characters must always be grouped first (in the current sort order),
  then non-pinned, regardless of which sort is active (incl. faction rep sort).
]]

describe("Reputation display list pin grouping", function()
    local RepSort

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.AltArmyTBC_Data = { Characters = {} }
        _G.CreateFrame = _G.CreateFrame or function()
            return { SetScript = function() end, RegisterEvent = function() end }
        end
        _G.UIParent = _G.UIParent or {}
        _G.DEFAULT_CHAT_FRAME = _G.DEFAULT_CHAT_FRAME or { AddMessage = function() end }
        package.path = package.path .. ";AltArmy_TBC/?.lua;AltArmy_TBC/Data/?.lua"
        require("DataStore")
        require("DataStoreReputations")
        require("CharacterSort")
        assert(loadfile("AltArmy_TBC/ReputationFactionSort.lua"))()
        RepSort = AltArmy.ReputationFactionSort
    end)

    local function makeSet(pinnedNames, selfName)
        local pinSet, selfSet = {}, {}
        for _, n in ipairs(pinnedNames or {}) do pinSet[n] = true end
        if selfName then selfSet[selfName] = true end
        local isPinned = function(e) return pinSet[e.name] == true end
        local isSelf = function(e) return selfSet[e.name] == true end
        return isPinned, isSelf
    end

    -- Comparator that simply sorts by a numeric "rep" field, high first.
    local function byRepHighFirst(a, b)
        return (a.rep or 0) > (b.rep or 0)
    end

    it("puts pinned characters first, each group in sort order", function()
        local visible = {
            { name = "Alice", rep = 100 },
            { name = "Bob", rep = 500 },
            { name = "Cara", rep = 300 },
            { name = "Dan", rep = 50 },
        }
        local isPinned, isSelf = makeSet({ "Cara" }, nil)
        local list = RepSort.BuildSortedDisplayList(visible, isPinned, isSelf, false, byRepHighFirst)
        -- Cara pinned -> first; rest by rep high first
        assert.are.equal("Cara", list[1].name)
        assert.are.equal("Bob", list[2].name)
        assert.are.equal("Alice", list[3].name)
        assert.are.equal("Dan", list[4].name)
    end)

    it("keeps pin grouping even when a reputation-based comparator is active", function()
        -- Pinned char has low rep; must still sort before higher-rep non-pinned chars.
        local visible = {
            { name = "Alice", rep = 100 },
            { name = "Bob", rep = 900 },
            { name = "Pinned", rep = 10 },
        }
        local isPinned, isSelf = makeSet({ "Pinned" }, nil)
        local list = RepSort.BuildSortedDisplayList(visible, isPinned, isSelf, false, byRepHighFirst)
        assert.are.equal("Pinned", list[1].name)
        assert.are.equal("Bob", list[2].name)
        assert.are.equal("Alice", list[3].name)
    end)

    it("treats self as pinned when showSelfFirst is enabled", function()
        local visible = {
            { name = "Alice", rep = 100 },
            { name = "Me", rep = 10 },
            { name = "Bob", rep = 900 },
        }
        local isPinned, isSelf = makeSet({}, "Me")
        local list = RepSort.BuildSortedDisplayList(visible, isPinned, isSelf, true, byRepHighFirst)
        assert.are.equal("Me", list[1].name)
        assert.are.equal("Bob", list[2].name)
        assert.are.equal("Alice", list[3].name)
    end)

    it("appends self last when showSelfFirst is disabled and self is not pinned", function()
        local visible = {
            { name = "Alice", rep = 100 },
            { name = "Me", rep = 900 },
            { name = "Bob", rep = 50 },
        }
        local isPinned, isSelf = makeSet({}, "Me")
        local list = RepSort.BuildSortedDisplayList(visible, isPinned, isSelf, false, byRepHighFirst)
        assert.are.equal("Alice", list[1].name)
        assert.are.equal("Bob", list[2].name)
        assert.are.equal("Me", list[3].name)
    end)

    it("sorts multiple pinned characters within the pinned group", function()
        local visible = {
            { name = "Alice", rep = 100 },
            { name = "PinLow", rep = 20 },
            { name = "PinHigh", rep = 800 },
            { name = "Bob", rep = 500 },
        }
        local isPinned, isSelf = makeSet({ "PinLow", "PinHigh" }, nil)
        local list = RepSort.BuildSortedDisplayList(visible, isPinned, isSelf, false, byRepHighFirst)
        assert.are.equal("PinHigh", list[1].name)
        assert.are.equal("PinLow", list[2].name)
        assert.are.equal("Bob", list[3].name)
        assert.are.equal("Alice", list[4].name)
    end)
end)
