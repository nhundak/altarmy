-- AltArmy TBC — Realm filter and display name helpers (multi-realm support).

AltArmy.RealmFilter = AltArmy.RealmFilter or {}

local RF = AltArmy.RealmFilter

--- Filter a list of entries (with .realm) by realm.
--- @param list table[] Array of entries with at least .realm
--- @param realmFilter "all"|"currentRealm"
--- @param currentRealm string Current realm name (e.g. from GetRealmName())
--- @return table[] New array; when realmFilter == "currentRealm" only entries where
--- entry.realm == currentRealm; when "all" a copy of list.
function RF.filterListByRealm(list, realmFilter, currentRealm)
    if not list then return {} end
    if realmFilter ~= "currentRealm" then
        local out = {}
        for i = 1, #list do out[i] = list[i] end
        return out
    end
    local out = {}
    for i = 1, #list do
        local e = list[i]
        if (e.realm or "") == (currentRealm or "") then
            out[#out + 1] = e
        end
    end
    return out
end

--- Return true if list has entries from more than one distinct realm.
--- @param list table[] Array of entries with at least .realm
--- @return boolean
function RF.hasMultipleRealms(list)
    if not list or #list == 0 then return false end
    local seen = {}
    for i = 1, #list do
        local r = list[i].realm or ""
        seen[r] = true
    end
    local count = 0
    for _ in pairs(seen) do
        count = count + 1
        if count > 1 then return true end
    end
    return false
end

--- Plain display name: name only or "name-realm".
--- @param name string
--- @param realm string|nil
--- @param showRealmSuffix boolean
--- @return string
function RF.formatCharacterDisplayName(name, realm, showRealmSuffix)
    name = name or ""
    if not showRealmSuffix then return name end
    return name .. "-" .. (realm or "")
end

--- Colored display string for UI: |cFFrrggbbname|r or |cFFrrggbbname|r-realm.
--- @param name string
--- @param realm string|nil
--- @param showRealmSuffix boolean
--- @param r number 0-1 red
--- @param g number 0-1 green
--- @param b number 0-1 blue
--- @return string
function RF.formatCharacterDisplayNameColored(name, realm, showRealmSuffix, r, g, b)
    name = name or ""
    r = (r == nil) and 1 or r
    g = (g == nil) and 0.82 or g
    b = (b == nil) and 0 or b
    local rr = math.floor(math.max(0, math.min(1, r)) * 255)
    local gg = math.floor(math.max(0, math.min(1, g)) * 255)
    local bb = math.floor(math.max(0, math.min(1, b)) * 255)
    local hex = string.format("|cFF%02x%02x%02x%s|r", rr, gg, bb, name)
    if showRealmSuffix then
        hex = hex .. "-" .. (realm or "")
    end
    return hex
end
