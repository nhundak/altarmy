-- AltArmy TBC — Shared item interaction helpers (modified-click routing, Dressing Room preview).
-- Used by Gear and Search tabs so click behavior stays consistent.

if not AltArmy then return end

AltArmy.ItemActions = AltArmy.ItemActions or {}

local ItemActions = AltArmy.ItemActions

--- Decide what a left-click should do based on held modifiers.
--- Control previews the item in the Dressing Room; Shift links it into chat.
--- Control takes precedence when both are held. Non-left buttons do nothing.
--- @return string|nil "preview", "chatlink", or nil
function ItemActions.GetClickAction(button, isShift, isControl)
    if button ~= "LeftButton" then return nil end
    if isControl then return "preview" end
    if isShift then return "chatlink" end
    return nil
end

--- Resolve an item link or item ID to a usable item link string.
--- Prefers a fresh link from GetItemInfo(itemID) so stale/stored links resolve correctly;
--- falls back to the original string when it is already an item link.
--- @return string|nil
function ItemActions.ResolveItemLink(itemLinkOrID)
    local itemID
    if type(itemLinkOrID) == "number" then
        itemID = itemLinkOrID
    elseif type(itemLinkOrID) == "string" and itemLinkOrID ~= "" then
        itemID = tonumber(string.match(itemLinkOrID, "item:(%d+)"))
    end
    if itemID and GetItemInfo then
        local _, freshLink = GetItemInfo(itemID)
        if freshLink and freshLink ~= "" then
            return freshLink
        end
    end
    if type(itemLinkOrID) == "string" and string.find(itemLinkOrID, "item:") then
        return itemLinkOrID
    end
    return nil
end

--- Preview an item in the game's Dressing Room (try-on) feature.
--- @return boolean true if the item was sent to the Dressing Room
function ItemActions.PreviewInDressingRoom(itemLinkOrID)
    local link = ItemActions.ResolveItemLink(itemLinkOrID)
    if link and DressUpItemLink then
        DressUpItemLink(link)
        return true
    end
    return false
end

--- Insert an item link into the chat edit box (same as shift-clicking an item in bags).
--- Only inserts a valid, bracketed item link to avoid blank "()" from bad/stale links.
--- @return boolean true if a link was inserted
function ItemActions.InsertLinkIntoChat(itemLinkOrID)
    local link = ItemActions.ResolveItemLink(itemLinkOrID)
    if link and ChatEdit_InsertLink and string.find(link, "item:") and string.find(link, "%[") then
        ChatEdit_InsertLink(link)
        return true
    end
    return false
end
