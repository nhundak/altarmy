--[[ Integration tests for the unique-name SearchData engine. ]]

describe("SearchData engine", function()
    local SD

    local function mockDataStore()
        local chars = {
            {
                realm = "TestRealm",
                name = "Alice",
                classFile = "MAGE",
                containers = {
                    { bagID = 0, slot = 1, itemID = 2589, count = 10, link = "|Hitem:2589|h[Linen Cloth]|h" },
                    { bagID = 0, slot = 2, itemID = 2592, count = 2, link = "|Hitem:2592|h[Wool Cloth]|h" },
                },
                professions = {
                    Tailoring = {
                        rank = 150,
                        Recipes = {
                            [100] = { resultItemID = 2996 },
                            [200] = { resultItemID = 2589 },
                        },
                    },
                },
            },
        }
        AltArmy.DataStore = {
            ForEachCharacter = function(_, fn)
                for _, c in ipairs(chars) do
                    fn(c.realm, c.name, c)
                end
            end,
            GetCharacterName = function(_, charData)
                return charData.name
            end,
            GetCharacterClass = function(_, charData)
                return charData.name, charData.classFile
            end,
            IterateContainerSlots = function(_, charData, fn)
                for _, s in ipairs(charData.containers or {}) do
                    if fn(s.bagID, s.slot, s.itemID, s.count, s.link) then
                        break
                    end
                end
            end,
            GetProfessions = function(_, charData)
                return charData.professions
            end,
            IterateInventory = function() end,
        }
        _G.GetItemInfo = function(idOrLink)
            if type(idOrLink) == "string" then
                local id = tonumber(idOrLink:match("item:(%d+)"))
                if id == 2589 then return "Linen Cloth" end
                if id == 2592 then return "Wool Cloth" end
                return nil
            end
            if idOrLink == 2589 then return "Linen Cloth" end
            if idOrLink == 2592 then return "Wool Cloth" end
            return nil
        end
        _G.GetSpellInfo = function(id)
            if id == 100 then return "Bolt of Linen Cloth" end
            if id == 200 then return "Brown Linen Vest" end
            return nil
        end
    end

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.CreateFrame = _G.CreateFrame or function()
            local f = { scripts = {} }
            function f:SetScript(e, fn) self.scripts[e] = fn end
            function f:GetScript(e) return self.scripts[e] end
            function f:RegisterEvent() end
            function f:UnregisterEvent() end
            function f:Hide() end
            function f:Show() end
            function f:SetOwner() end
            function f:ClearLines() end
            function f:SetHyperlink() end
            function f:NumLines() return 0 end
            function f:GetName() return "AltArmyTBC_ScanTooltip" end
            return f
        end
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        for _, mod in ipairs({
            "SearchIndex", "SearchQuery", "SearchPresent", "SearchTasks", "SearchData",
        }) do
            package.loaded[mod] = nil
        end
        mockDataStore()
        require("SearchIndex")
        require("SearchQuery")
        require("SearchPresent")
        require("SearchTasks")
        require("SearchData")
        SD = AltArmy.SearchData
        assert.truthy(SD)
    end)

    before_each(function()
        mockDataStore()
        SD.ClearCaches()
        AltArmy.SearchSettings = {
            GetSearchSettings = function()
                return {
                    professionFilter = {},
                    recipeLevelFilter = { min = 0, max = 375 },
                    difficultyFilter = {},
                    sourceFilter = {},
                }
            end,
            IsProfessionFilterActive = function() return false end,
            IsRecipeLevelFilterActive = function() return false end,
            IsDifficultyFilterActive = function() return false end,
            IsSourceFilterActive = function() return false end,
            CanShowIncludeGuildmatesToggle = function() return false end,
            IsIncludeGuildmatesEnabled = function() return false end,
        }
    end)

    it("SearchItems finds linen by name", function()
        local main, tip = SD.SearchItems("linen", true)
        assert.is_true(#main >= 1)
        assert.are.equal(2589, main[1].itemID)
        assert.are.equal(0, #tip)
    end)

    it("SearchItems finds by item id", function()
        local main = SD.SearchItems("2592", true)
        assert.are.equal(1, #main)
        assert.are.equal(2592, main[1].itemID)
    end)

    it("SearchRecipes finds bolt of linen", function()
        local rows = SD.SearchRecipes("bolt")
        assert.are.equal(1, #rows)
        assert.are.equal(100, rows[1].recipeID)
        assert.are.equal("Alice", rows[1].characterName)
    end)

    it("ClearCaches forces rebuild", function()
        SD.SearchItems("linen", true)
        SD.ClearCaches()
        local main = SD.SearchItems("wool", true)
        assert.are.equal(1, #main)
        assert.are.equal(2592, main[1].itemID)
    end)
end)
