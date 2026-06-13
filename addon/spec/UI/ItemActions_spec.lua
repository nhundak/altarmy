--[[
  Unit tests for AltArmy_TBC/UI/ItemActions.lua.
  Covers modified-click routing, item link resolution, and Dressing Room preview.
  Run from project root: npm test
]]

describe("AltArmy.ItemActions", function()
    local ItemActions

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/UI/?.lua"
        package.loaded["ItemActions"] = nil
        require("ItemActions")
        ItemActions = AltArmy.ItemActions
    end)

    after_each(function()
        _G.GetItemInfo = nil
        _G.DressUpItemLink = nil
        _G.ChatEdit_InsertLink = nil
    end)

    describe("GetClickAction", function()
        it("returns preview for control + left click", function()
            assert.are.equal("preview", ItemActions.GetClickAction("LeftButton", false, true))
        end)

        it("returns chatlink for shift + left click", function()
            assert.are.equal("chatlink", ItemActions.GetClickAction("LeftButton", true, false))
        end)

        it("prefers preview when both control and shift are held", function()
            assert.are.equal("preview", ItemActions.GetClickAction("LeftButton", true, true))
        end)

        it("returns nil for an unmodified left click", function()
            assert.is_nil(ItemActions.GetClickAction("LeftButton", false, false))
        end)

        it("returns nil for non-left buttons regardless of modifiers", function()
            assert.is_nil(ItemActions.GetClickAction("RightButton", true, true))
        end)
    end)

    describe("ResolveItemLink", function()
        it("returns a fresh link from a numeric item ID", function()
            _G.GetItemInfo = function(id)
                if id == 123 then
                    return "Thunderfury", "|cff00ccff|Hitem:123::::|h[Thunderfury]|h|r"
                end
            end
            assert.are.equal(
                "|cff00ccff|Hitem:123::::|h[Thunderfury]|h|r",
                ItemActions.ResolveItemLink(123))
        end)

        it("refreshes a stale string link via its item ID", function()
            _G.GetItemInfo = function(id)
                if id == 456 then
                    return "Fresh", "|cffffffff|Hitem:456::::|h[Fresh]|h|r"
                end
            end
            assert.are.equal(
                "|cffffffff|Hitem:456::::|h[Fresh]|h|r",
                ItemActions.ResolveItemLink("item:456"))
        end)

        it("falls back to the original string link when GetItemInfo has no data", function()
            _G.GetItemInfo = function() return nil end
            assert.are.equal("item:789", ItemActions.ResolveItemLink("item:789"))
        end)

        it("returns nil for nil input", function()
            assert.is_nil(ItemActions.ResolveItemLink(nil))
        end)

        it("returns nil for a string that is not an item link", function()
            _G.GetItemInfo = function() return nil end
            assert.is_nil(ItemActions.ResolveItemLink("not a link"))
        end)
    end)

    describe("PreviewInDressingRoom", function()
        it("dresses up the resolved link and returns true", function()
            local dressed
            _G.GetItemInfo = function() return "X", "|cff00ccff|Hitem:123::::|h[X]|h|r" end
            _G.DressUpItemLink = function(link) dressed = link end
            assert.is_true(ItemActions.PreviewInDressingRoom(123))
            assert.are.equal("|cff00ccff|Hitem:123::::|h[X]|h|r", dressed)
        end)

        it("returns false and does not call DressUpItemLink when the link cannot resolve", function()
            local called = false
            _G.GetItemInfo = function() return nil end
            _G.DressUpItemLink = function() called = true end
            assert.is_false(ItemActions.PreviewInDressingRoom(nil))
            assert.is_false(called)
        end)
    end)

    describe("InsertLinkIntoChat", function()
        it("inserts a valid item link into chat", function()
            local inserted
            _G.GetItemInfo = function() return "X", "|cff00ccff|Hitem:123::::|h[X]|h|r" end
            _G.ChatEdit_InsertLink = function(link) inserted = link end
            assert.is_true(ItemActions.InsertLinkIntoChat(123))
            assert.are.equal("|cff00ccff|Hitem:123::::|h[X]|h|r", inserted)
        end)

        it("does not insert when the link is not a bracketed item link", function()
            local called = false
            _G.GetItemInfo = function() return nil end
            _G.ChatEdit_InsertLink = function() called = true end
            assert.is_false(ItemActions.InsertLinkIntoChat("item:999"))
            assert.is_false(called)
        end)
    end)
end)
