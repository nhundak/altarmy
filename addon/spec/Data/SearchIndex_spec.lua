--[[ Unit tests for SearchIndex.lua — generic index factory. ]]

describe("SearchIndex", function()
    local SI

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        package.loaded["SearchIndex"] = nil
        require("SearchIndex")
        SI = AltArmy.SearchIndex
        assert.truthy(SI)
    end)

    it("BuildIndex groups by id and builds unique names list", function()
        local entries = {
            { id = 10, name = "Linen Cloth", characterName = "Alice" },
            { id = 10, name = "Linen Cloth", characterName = "Bob" },
            { id = 20, name = "Wool Cloth", characterName = "Alice" },
        }
        local index = SI.BuildIndex(entries, {
            getId = function(e) return e.id end,
            getNameLower = function(e) return e.name:lower() end,
            compareWithinId = function(a, b)
                return (a.characterName or "") < (b.characterName or "")
            end,
        })
        assert.are.equal(3, #index.entries)
        assert.are.equal(2, #index.byId[10])
        assert.are.equal("Alice", index.byId[10][1].characterName)
        assert.are.equal("Bob", index.byId[10][2].characterName)
        assert.are.equal(2, #index.names)
        local byIdName = {}
        for i = 1, #index.names do
            byIdName[index.names[i].id] = index.names[i].nameLower
        end
        assert.are.equal("linen cloth", byIdName[10])
        assert.are.equal("wool cloth", byIdName[20])
    end)

    it("BuildIndex skips entries without id or name", function()
        local entries = {
            { id = nil, name = "x" },
            { id = 1, name = nil },
            { id = 2, name = "Ok" },
        }
        local index = SI.BuildIndex(entries, {
            getId = function(e) return e.id end,
            getNameLower = function(e)
                return e.name and e.name:lower() or nil
            end,
        })
        assert.are.equal(1, #(index.byId[2] or {}))
        assert.are.equal(1, #index.names)
        assert.are.equal(2, index.names[1].id)
    end)

    it("MatchNameIds finds substring matches", function()
        local names = {
            { id = 1, nameLower = "linen cloth" },
            { id = 2, nameLower = "wool cloth" },
            { id = 3, nameLower = "silk cloth" },
        }
        local ids = SI.MatchNameIds(names, "cloth")
        assert.is_true(ids[1])
        assert.is_true(ids[2])
        assert.is_true(ids[3])
        local linen = SI.MatchNameIds(names, "linen")
        assert.is_true(linen[1])
        assert.is_nil(linen[2])
    end)

    it("MatchNameIds can narrow from a previous id set", function()
        local names = {
            { id = 1, nameLower = "linen cloth" },
            { id = 2, nameLower = "wool cloth" },
            { id = 3, nameLower = "silk bolt" },
        }
        local prev = { [1] = true, [2] = true }
        local ids = SI.MatchNameIds(names, "linen", prev)
        assert.is_true(ids[1])
        assert.is_nil(ids[2])
        assert.is_nil(ids[3])
    end)
end)
