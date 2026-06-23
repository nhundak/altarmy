--[[
  Unit tests for ItemStats.lua.
  Run from project root: npm test
]]

describe("ItemStats", function()
    local IS

    local function mockGetItemInfo(item)
        local id = type(item) == "number" and item
            or tonumber(tostring(item):match("item:(%d+)"))
        local items = {
            [10] = { "Old Helm", nil, 2, 20, 20, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
            [11] = { "New Helm", nil, 3, 35, 35, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
            [99] = { "Monkey Greaves", nil, 2, 43, 43, "Armor", "Mail", nil, "INVTYPE_FEET" },
        }
        local info = items[id]
        if not info then return end
        local link = "|cff|Hitem:" .. tostring(id) .. ":0|h[" .. info[1] .. "]|h|r"
        return info[1], link, info[3], info[4], info[5], info[6], info[7], nil, info[9]
    end

    local function mockGetItemStats(link)
        local id = tonumber(tostring(link):match("item:(%d+)"))
        if id == 11 then
            return { ["ITEM_MOD_INTELLECT_SHORT"] = 20, ["ITEM_MOD_STAMINA_SHORT"] = 10 }
        end
        if id == 10 then
            return { ["ITEM_MOD_INTELLECT_SHORT"] = 5, ["ITEM_MOD_STAMINA_SHORT"] = 5 }
        end
        return {}
    end

    local function makeTooltipMock(lineTexts)
        local fontStrings = {}
        for i, text in ipairs(lineTexts) do
            fontStrings[i] = {
                IsObjectType = function(_, t)
                    return t == "FontString"
                end,
                GetText = function()
                    return text
                end,
            }
        end
        return {
            lineTexts = lineTexts,
            SetOwner = function() end,
            ClearLines = function(self)
                self.lineTexts = {}
            end,
            SetHyperlink = function(self, _)
                self.lineTexts = lineTexts
            end,
            GetRegions = function()
                return unpack(fontStrings)
            end,
            NumLines = function(self)
                return #(self.lineTexts or {})
            end,
            GetName = function()
                return "AltArmyTBC_ItemStatsScanTooltip"
            end,
        }
    end

    setup(function()
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        _G.AltArmy = _G.AltArmy or {}
        _G.GetItemInfo = mockGetItemInfo
        _G.GetItemStats = mockGetItemStats
        _G.ITEM_MOD_AGILITY_SHORT = "Agility"
        _G.ITEM_MOD_STAMINA_SHORT = "Stamina"
        _G.ITEM_MOD_AGILITY = "+ %d Agility"
        _G.ITEM_MOD_STAMINA = "+ %d Stamina"
        _G.CreateFrame = _G.CreateFrame or function(frameType, name)
            if frameType == "GameTooltip" then
                return makeTooltipMock({})
            end
            if frameType == "Frame" then
                return {
                    RegisterEvent = function() end,
                    SetScript = function() end,
                }
            end
            return { SetScript = function() end, RegisterEvent = function() end }
        end
        _G.UIParent = _G.UIParent or {}
        _G.PawnGetItemData = nil
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()
        IS.SetOnUpdated(nil)
    end)

    it("GetNormalized uses Pawn when available", function()
        _G.PawnGetItemData = function(link)
            if link:find("item:99") then
                return { Stats = { Agility = 10, Stamina = 10 } }
            end
        end
        local link = "|Hitem:99:0|h[Monkey Greaves]|h"
        local stats = IS.GetNormalized(link)
        assert.are.equal(10, stats.agi)
        assert.are.equal(10, stats.sta)
        assert.are.equal("pawn", IS.GetSource(link))
        _G.PawnGetItemData = nil
    end)

    it("GetNormalized uses GetItemStats API", function()
        local stats = IS.GetNormalized("|Hitem:11:0|h[New Helm]|h")
        assert.are.equal(20, stats.int)
        assert.are.equal(10, stats.sta)
        assert.are.equal("api", IS.GetSource("|Hitem:11:0|h[New Helm]|h"))
    end)

    it("GetNormalized parses color-coded tooltip lines", function()
        _G.GetItemStats = function() return {} end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "|cffffffff+10 Agility|r",
                    "+10 Stamina",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local link = "|Hitem:99:0|h[Monkey Greaves]|h"
        local stats = IS.GetNormalized(link)
        assert.are.equal(10, stats.agi)
        assert.are.equal(10, stats.sta)
        assert.are.equal("tooltip", IS.GetSource(link))
    end)

    it("GetNormalized normalizes reversed stat order", function()
        _G.GetItemStats = function() return {} end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({ "Stamina +10", "+8 Agility" })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local stats = IS.GetNormalized("|Hitem:99:0|h[Monkey Greaves]|h")
        assert.are.equal(8, stats.agi)
        assert.are.equal(10, stats.sta)
    end)

    it("GetNormalized returns pending when item is not cached", function()
        local oldGetItemInfo = _G.GetItemInfo
        _G.GetItemInfo = function()
            return nil
        end
        IS.ClearCache()
        local link = "|Hitem:404:0|h[Unknown]|h"
        local stats = IS.GetNormalized(link)
        assert.are.same({}, stats)
        assert.are.equal("pending", IS.GetSource(link))
        _G.GetItemInfo = oldGetItemInfo
    end)

    it("GetNormalized parses green suffix item when API is empty", function()
        _G.GetItemStats = function() return {} end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "+10 Agility",
                    "+10 Stamina",
                    "181 Armor",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local link = "|Hitem:99:0|h[Monkey Greaves]|h"
        local stats = IS.GetNormalized(link)
        assert.are.equal(10, stats.agi)
        assert.are.equal(10, stats.sta)
        assert.are.equal("tooltip", IS.GetSource(link))
    end)
end)
