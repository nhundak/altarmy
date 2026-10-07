-- AltArmy TBC — items whose icon (or name) was not in the client's cache when a view drew them. A
-- tracker remembers their ids and, when GET_ITEM_INFO_RECEIVED brings one, calls back once per frame
-- however many arrive together, so a view with many uncached items redraws once, not once per item.
-- Used by the Inventory views and the Guild tab's recipe list.

AltArmy = AltArmy or {}
AltArmy.PendingItemIcons = AltArmy.PendingItemIcons or {}
local P = AltArmy.PendingItemIcons

--- A tracker: Track(itemID) remembers an id, Clear() forgets them all (do it before a redraw),
--- IsPending(itemID). `onReceived()` runs on the next frame after a tracked id arrives.
function P.Create(onReceived)
    local tracker = { pending = {}, scheduled = false, events = nil }

    local function fire()
        tracker.scheduled = false
        onReceived()
    end

    local function schedule()
        if tracker.scheduled then return end
        local timer = _G.C_Timer
        if timer and timer.After then
            tracker.scheduled = true
            timer.After(0, fire)
        else
            onReceived()
        end
    end

    function tracker.Track(itemID)
        if not itemID then return end
        tracker.pending[itemID] = true
        if not tracker.events and _G.CreateFrame then
            tracker.events = CreateFrame("Frame")
            tracker.events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
            tracker.events:SetScript("OnEvent", function(_, _, itemId)
                itemId = tonumber(itemId)
                if not itemId or not tracker.pending[itemId] then return end
                tracker.pending[itemId] = nil
                schedule()
            end)
        end
    end

    function tracker.Clear()
        for k in pairs(tracker.pending) do tracker.pending[k] = nil end
    end

    function tracker.IsPending(itemID)
        return tracker.pending[itemID] == true
    end

    return tracker
end
