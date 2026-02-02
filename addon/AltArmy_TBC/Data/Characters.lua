-- AltArmy TBC — Characters list/view for Summary tab (Altoholic-style).
-- Builds a list from SummaryData.GetCharacterList(); optional view and sort.
-- Exposes InvalidateView(), GetView(), and Sort() for the UI layer.

AltArmy.Characters = AltArmy.Characters or {}

local ns = AltArmy.Characters

local characterList
local view
local isViewValid

local function BuildList()
    characterList = characterList or {}
    wipe(characterList)
    local raw = AltArmy.SummaryData and AltArmy.SummaryData.GetCharacterList and AltArmy.SummaryData.GetCharacterList()
    if raw then
        for _, entry in ipairs(raw) do
            table.insert(characterList, entry)
        end
    end
end

local function BuildView()
    view = view or {}
    wipe(view)
    if not characterList then return view end
    for i = 1, #characterList do
        table.insert(view, i)
    end
    isViewValid = true
    return view
end

function ns:InvalidateView()
    isViewValid = nil
end

--- Returns the current view (indices into the character list). Rebuilds list and view if invalidated.
--- @return number[] view Array of indices into the character list.
function ns:GetView()
    if not isViewValid then
        BuildList()
        BuildView()
    end
    return view or {}
end

--- Returns the character list (same order as view indices). Rebuilds if invalidated.
--- @return table[] list Array of entries { name = string, realm = string }.
function ns:GetList()
    if not isViewValid then
        BuildList()
        BuildView()
    end
    return characterList or {}
end

--- Sort the character list in place. Call InvalidateView() before if data changed.
--- @param ascending boolean
--- @param sortKey string "name", "realm", "level", "restXp", "money", "played", or "lastOnline"
function ns:Sort(ascending, sortKey)
    local list = self:GetList()
    if #list == 0 then return end
    sortKey = sortKey or "name"
    local numericKeys = { level = true, restXp = true, money = true, played = true, lastOnline = true, bagSlots = true, bagFree = true, equipmentCount = true }
    if numericKeys[sortKey] then
        table.sort(list, function(a, b)
            local va, vb
            if sortKey == "lastOnline" then
                -- Current player has lastOnline = nil; treat as 0 so they stay at top (ascending) or bottom (descending)
                va = a.lastOnline
                vb = b.lastOnline
                if va == nil then va = 0 end
                if vb == nil then vb = 0 end
            else
                va = tonumber(a[sortKey]) or 0
                vb = tonumber(b[sortKey]) or 0
            end
            if ascending then
                return va < vb
            else
                return va > vb
            end
        end)
    else
        table.sort(list, function(a, b)
            local va = a[sortKey] or ""
            local vb = b[sortKey] or ""
            if ascending then
                return va < vb
            else
                return va > vb
            end
        end)
    end
end
