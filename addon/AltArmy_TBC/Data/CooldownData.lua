-- AltArmy TBC — Cooldown categories, row building, mats, and alert evaluation (data only).
-- Consumed by TabCooldowns.lua and CooldownAlerts.lua.

if not AltArmy then return end

AltArmy.CooldownData = AltArmy.CooldownData or {}
local CD = AltArmy.CooldownData

---@class CooldownCategoryDef
---@field key string Stable id (e.g. "transmute").
---@field title string UI label.
---@field mode "group"|"single" group = one row if any spell in spellIds matches; single = per spell row.
---@field spellIds number[]|nil For single-mode or group membership.
---@field spellId number|nil Primary spell for single mode (same as spellIds[1]).

CD.CATEGORY_ORDER = {
    "transmute",
    "spellcloth",
    "shadowcloth",
    "primal_mooncloth",
    "salt_shaker",
    "void_shatter",
}

-- TBC: transmute spells (alchemy). Used for category membership + preferred recipe filtering.
CD.TRANSMUTE_SPELL_IDS = {
    17559, 17560, 17561, 17562, 17563, 17564, 17565, 17566,
    28566, 28567, 28568, 28569, 28580, 28581, 28582, 28583, 28584, 28585,
    29688,
    -- Transmute: Arcanite (automatic fallback after Primal Might).
    17187,
}

--- Automatic cooldown display order when preference is "choose automatically" (per character).
CD.TRANSMUTE_AUTOMATIC_FALLBACK_SPELL_IDS = {
    29688, -- Transmute: Primal Might
    17187, -- Transmute: Arcanite
}

local function KeySet(list)
    local s = {}
    for _, id in ipairs(list) do
        s[id] = true
    end
    return s
end

CD.TRANSMUTE_SPELL_SET = KeySet(CD.TRANSMUTE_SPELL_IDS)

-- Salt Shaker (item 15846): use effect is spell 19566 (3-day), not engineering craft 19567.
CD.SALT_SHAKER_ITEM_ID = 15846
CD.SALT_SHAKER_COOLDOWN_SPELL_ID = 19566
CD.SALT_SHAKER_LEATHERWORKING_MIN = 250
local SPELL_ID_LEATHERWORKING = 2108

--- @param dataStore table must provide GetContainerItemCount(self, char, itemId)
function CD.CharacterQualifiesSaltShakerCooldown(char, dataStore)
    if not char or not dataStore or not dataStore.GetContainerItemCount then
        return false
    end
    if (dataStore:GetContainerItemCount(char, CD.SALT_SHAKER_ITEM_ID) or 0) < 1 then
        return false
    end
    local lwName = GetSpellInfo and GetSpellInfo(SPELL_ID_LEATHERWORKING)
    if not lwName or not char.Professions then
        return false
    end
    local p = char.Professions[lwName]
    local rank = (p and p.rank) or 0
    return rank >= CD.SALT_SHAKER_LEATHERWORKING_MIN
end

CD.CATEGORIES = {
    transmute = {
        key = "transmute",
        title = "Transmute",
        mode = "group",
        spellIds = CD.TRANSMUTE_SPELL_IDS,
    },
    spellcloth = {
        key = "spellcloth",
        title = "Spellcloth",
        mode = "single",
        spellId = 31373,
        spellIds = { 31373 },
    },
    shadowcloth = {
        key = "shadowcloth",
        title = "Shadowcloth",
        mode = "single",
        spellId = 36686,
        spellIds = { 36686 },
    },
    primal_mooncloth = {
        key = "primal_mooncloth",
        title = "Primal Mooncloth",
        mode = "single",
        spellId = 26751,
        spellIds = { 26751 },
    },
    -- Engineering spell 19567 crafts the device; cooldown is on item use (19566), LW 250.
    salt_shaker = {
        key = "salt_shaker",
        title = "Salt Shaker",
        mode = "single",
        spellId = 19566,
        spellIds = { 19566 },
    },
    void_shatter = {
        key = "void_shatter",
        title = "Void Shatter",
        mode = "single",
        spellId = 33358,
        spellIds = { 33358 },
    },
}

-- Reagent lists for mats + tooltips come from AltArmyTBC_Data.RecipeReagents, filled when you
-- open a tradeskill or craft window (ScanRecipes / ScanCraftRecipes read the client APIs).

--- Lookup order matches DataStoreProfession captures (accountData then SavedVariables root).
local function RecipeReagentsTableForSpell(spellId)
    if not spellId then return nil end
    local tries = {}
    local seenDb = {}
    local function append(db)
        if db and type(db) == "table" and not seenDb[db] then
            seenDb[db] = true
            tries[#tries + 1] = db
        end
    end
    local DS = AltArmy and AltArmy.DataStore
    append(DS and DS.accountData)
    append(rawget(_G, "AltArmyTBC_Data"))
    append(AltArmy and AltArmy.DB)
    for _, db in ipairs(tries) do
        local rr = db.RecipeReagents
        if type(rr) == "table" then
            local list = rr[spellId]
            if type(list) == "table" and #list > 0 then
                return list
            end
        end
    end
    return nil
end

--- Flat set of every spell id we persist cooldown expiry for.
function CD.GetAllTrackedSpellIds()
    local out = {}
    local seen = {}
    for _, id in ipairs(CD.TRANSMUTE_SPELL_IDS) do
        if not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    for _, key in ipairs(CD.CATEGORY_ORDER) do
        local cat = CD.CATEGORIES[key]
        if cat and cat.spellIds then
            for _, sid in ipairs(cat.spellIds) do
                if not seen[sid] then
                    seen[sid] = true
                    out[#out + 1] = sid
                end
            end
        end
    end
    return out, seen
end

local _, TRACKED_SET = CD.GetAllTrackedSpellIds()
CD._TRACKED_SPELL_SET = TRACKED_SET

--- Defaults for AltArmyTBC_Options.cooldowns (SavedVariables).
function CD.ResetCooldownOptionsToDefaults()
    _G.AltArmyTBC_Options = _G.AltArmyTBC_Options or {}
    _G.AltArmyTBC_Options.cooldowns = nil
    CD.EnsureCooldownOptions()
end

function CD.EnsureCooldownOptions()
    _G.AltArmyTBC_Options = _G.AltArmyTBC_Options or {}
    local root = _G.AltArmyTBC_Options
    root.cooldowns = root.cooldowns or {}
    local cd = root.cooldowns
    cd.categories = cd.categories or {}
    for _, key in ipairs(CD.CATEGORY_ORDER) do
        local cat = cd.categories[key]
        if not cat then
            cat = {}
            cd.categories[key] = cat
        end
        if cat.hide == nil then cat.hide = false end
        if cat.alertWhenAvailable == nil then cat.alertWhenAvailable = true end
        if cat.alertMinutesBefore == nil then cat.alertMinutesBefore = false end
        if cat.alertMinutesBeforeMinutes == nil then cat.alertMinutesBeforeMinutes = 15 end
    end
    local sk = cd.listSortKey
    if sk ~= "recipe" and sk ~= "character" and sk ~= "mats" and sk ~= "time" then
        cd.listSortKey = "recipe"
    end
    if cd.listSortAscending == nil then
        cd.listSortAscending = true
    end
    return cd
end

function CD.IsTrackedSpellId(spellId)
    return spellId and TRACKED_SET[spellId] == true
end

--- @param char table
--- @param spellId number
--- @return boolean, string|nil professionName
function CD.FindRecipeProfession(char, spellId)
    if not char or not spellId or not char.Professions then
        return false, nil
    end
    for profName, prof in pairs(char.Professions) do
        if prof and prof.Recipes and prof.Recipes[spellId] then
            return true, profName
        end
    end
    return false, nil
end

--- Known transmute if recipe id is in transmute set OR name contains "Transmute" (fallback).
function CD.CharacterKnowsTransmute(char, getSpellInfoFn)
    if not char or not char.Professions then return false end
    for _, prof in pairs(char.Professions) do
        if prof and prof.Recipes then
            for rid in pairs(prof.Recipes) do
                if CD.TRANSMUTE_SPELL_SET[rid] then
                    return true
                end
            end
        end
    end
    local gsi = getSpellInfoFn or GetSpellInfo
    if gsi then
        for _, prof in pairs(char.Professions) do
            if prof and prof.Recipes then
                for rid in pairs(prof.Recipes) do
                    local name = gsi(rid)
                    if type(name) == "string" and name:lower():find("transmute", 1, true) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

--- Collect transmute spell ids known anywhere on the account (for options dropdown).
function CD.CollectAccountKnownTransmuteSpellIds(data, getSpellInfoFn)
    local out = {}
    local seen = {}
    local gsi = getSpellInfoFn or GetSpellInfo
    if not data or not data.Characters then return out end
    for _, realmTable in pairs(data.Characters) do
        for _, char in pairs(realmTable or {}) do
            if char and char.Professions then
                for _, prof in pairs(char.Professions) do
                    if prof and prof.Recipes then
                        for rid in pairs(prof.Recipes) do
                            if not seen[rid] and CD.IsTransmuteSpellId(rid, gsi) then
                                seen[rid] = true
                                out[#out + 1] = rid
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(out)
    return out
end

--- Known transmute spell IDs on one character (for Preferred Transmute dropdown).
function CD.CollectCharacterKnownTransmuteSpellIds(char, getSpellInfoFn)
    local out = {}
    local seen = {}
    local gsi = getSpellInfoFn or GetSpellInfo
    if not char or not char.Professions then return out end
    for _, prof in pairs(char.Professions) do
        if prof and prof.Recipes then
            for rid in pairs(prof.Recipes) do
                if rid and not seen[rid] and CD.IsTransmuteSpellId(rid, gsi) then
                    seen[rid] = true
                    out[#out + 1] = rid
                end
            end
        end
    end
    table.sort(out)
    return out
end

--- True if spellId is an alchemy transmute (ID set or localized name contains "transmute").
function CD.IsTransmuteSpellId(spellId, getSpellInfoFn)
    if not spellId then return false end
    if CD.TRANSMUTE_SPELL_SET[spellId] then return true end
    local gsi = getSpellInfoFn or GetSpellInfo
    if gsi then
        local name = gsi(spellId)
        if type(name) == "string" and name:lower():find("transmute", 1, true) then
            return true
        end
    end
    return false
end

--- Called when the player completes a spell cast that is a transmute (combat log).
--- Persists char.lastTransmute = { spellId = number, ... } for future fields.
function CD.RecordSuccessfulTransmuteCast(char, spellId)
    if not char or type(spellId) ~= "number" then return end
    if not CD.IsTransmuteSpellId(spellId, GetSpellInfo) then return end
    char.lastTransmute = { spellId = spellId }
end

--- Effective transmute spell for cooldown rows:
--- 1) explicit preferred when set and known,
--- 2) last successful transmute when still known,
--- 3) automatic Primal Might then Arcanite.
--- nil = do not show transmute row.
function CD.ResolveTransmuteSpellForCharacter(char)
    if not char then return nil end
    local pref = char.preferredTransmuteSpellId
    if type(pref) == "number" then
        if select(1, CD.FindRecipeProfession(char, pref)) then
            return pref
        end
    end
    local last = char.lastTransmute
    local lastId = type(last) == "table" and type(last.spellId) == "number" and last.spellId or nil
    if lastId and select(1, CD.FindRecipeProfession(char, lastId)) then
        return lastId
    end
    for _, sid in ipairs(CD.TRANSMUTE_AUTOMATIC_FALLBACK_SPELL_IDS) do
        if select(1, CD.FindRecipeProfession(char, sid)) then
            return sid
        end
    end
    return nil
end

--- Short label for the Recipe column when category is transmute (from effective spell name).
--- e.g. "Transmute: Primal Might" / "Alchemy: Transmute: Primal Might" -> "Primal Might".
function CD.TransmuteCategoryDisplayTitle(spellId, getSpellInfoFn)
    local fallback = (CD.CATEGORIES.transmute and CD.CATEGORIES.transmute.title) or "Transmute"
    if not spellId or type(getSpellInfoFn) ~= "function" then
        return fallback
    end
    local name = getSpellInfoFn(spellId)
    if type(name) ~= "string" or name == "" then
        return fallback
    end
    local after = name:match("Transmute:%s*(.+)$") or name:match("transmute:%s*(.+)$")
    if after and after ~= "" then
        return after:gsub("^%s+", "")
    end
    return name
end

--- Per-category spell used for mats / tooltip.
function CD.ResolveEffectiveSpellId(categoryKey, char, _options)
    local cat = CD.CATEGORIES[categoryKey]
    if not cat then return nil end
    if categoryKey == "transmute" then
        return CD.ResolveTransmuteSpellForCharacter(char)
    end
    if cat.mode == "single" and cat.spellId then
        return cat.spellId
    end
    return cat.spellIds and cat.spellIds[1] or nil
end

--- {{ itemID, quantity }, ...} from account cache (see DataStoreProfessions capture), else nil.
function CD.GetReagentList(spellId)
    if not spellId then return nil end
    return RecipeReagentsTableForSpell(spellId)
end

--- @param char table
--- @param spellId number
--- @param getContainerItemCount fun(char, itemID): number
--- Maximum crafts from inventory, or nil if RecipeReagents not loaded yet (open tradeskill once).
function CD.GetMaxCraftableQuantity(char, spellId, getContainerItemCount)
    local list = CD.GetReagentList(spellId)
    if not list then
        return nil
    end
    if not char or not getContainerItemCount then
        return nil
    end
    local minCrafts = math.huge
    for _, pair in ipairs(list) do
        local itemId, need = pair[1], pair[2] or 1
        if need <= 0 then
            need = 1
        end
        local have = getContainerItemCount(char, itemId) or 0
        local n = math.floor(have / need)
        if n < minCrafts then
            minCrafts = n
        end
    end
    if minCrafts == math.huge then
        return 0
    end
    return minCrafts
end

--- Maximum crafts possible after transferring all reagents from source to target.
--- Returns nil when reagent list is unknown (open tradeskill once).
--- @param target table
--- @param source table
--- @param spellId number
--- @param getTargetCount fun(char, itemID): number
--- @param getSourceCount fun(char, itemID): number
function CD.GetMaxCraftableQuantityAfterTransfer(target, source, spellId, getTargetCount, getSourceCount)
    local list = CD.GetReagentList(spellId)
    if not list then
        return nil
    end
    if not target or not source or not getTargetCount or not getSourceCount then
        return nil
    end
    local minCrafts = math.huge
    for _, pair in ipairs(list) do
        local itemId, need = pair[1], pair[2] or 1
        if need <= 0 then
            need = 1
        end
        local haveTarget = getTargetCount(target, itemId) or 0
        local haveSource = getSourceCount(source, itemId) or 0
        local n = math.floor((haveTarget + haveSource) / need)
        if n < minCrafts then
            minCrafts = n
        end
    end
    if minCrafts == math.huge then
        return 0
    end
    return minCrafts
end

--- For a requested craft count, compute per-reagent quantities needed from source to reach it.
--- Assumes requestedCrafts is within feasible range; callers should validate vs max-after-transfer.
--- Returns nil when reagent list is unknown.
--- @return table[]|nil rows { itemID, need, targetHave, sourceHave, requiredToSend }
function CD.GetReagentSendPlan(target, source, spellId, requestedCrafts, getTargetCount, getSourceCount)
    local list = CD.GetReagentList(spellId)
    if not list then
        return nil
    end
    if not target or not source or not getTargetCount or not getSourceCount then
        return nil
    end
    local crafts = tonumber(requestedCrafts) or 0
    if crafts < 0 then crafts = 0 end
    local rows = {}
    for _, pair in ipairs(list) do
        local itemId, need = pair[1], pair[2] or 1
        if need <= 0 then
            need = 1
        end
        local targetHave = getTargetCount(target, itemId) or 0
        local sourceHave = getSourceCount(source, itemId) or 0
        local required = crafts * need - targetHave
        if required < 0 then required = 0 end
        rows[#rows + 1] = {
            itemID = itemId,
            need = need,
            targetHave = targetHave,
            sourceHave = sourceHave,
            requiredToSend = required,
        }
    end
    return rows
end

--- true / false when reagents known; nil when RecipeReagents missing for this spell.
function CD.CharacterHasReagents(char, spellId, getContainerItemCount)
    local qty = CD.GetMaxCraftableQuantity(char, spellId, getContainerItemCount)
    if qty == nil then
        return nil
    end
    return qty >= 1
end

--- @param char table
--- @param spellId number
--- @param getContainerItemCount fun(char, itemID): number
function CD.GetReagentHaveCounts(char, spellId, getContainerItemCount)
    local list = CD.GetReagentList(spellId)
    if not list or not char or not getContainerItemCount then return {} end
    local rows = {}
    for _, pair in ipairs(list) do
        local itemId, need = pair[1], pair[2] or 1
        rows[#rows + 1] = {
            itemID = itemId,
            need = need,
            have = getContainerItemCount(char, itemId) or 0,
        }
    end
    return rows
end

local function CategoryRowVisible(categoryKey, options)
    local o = options and options.categories and options.categories[categoryKey]
    if o and o.hide then
        return false
    end
    return true
end

--- @param expiresUnix number|nil When spell cooldown ends (unix); nil = unknown / never scanned.
--- @param now number unix time
function CD.FormatTimeRemaining(expiresUnix, now)
    now = now or (time and time() or 0)
    if expiresUnix == nil then
        return "Unscanned"
    end
    if expiresUnix <= now then
        return "Ready"
    end
    local sec = math.floor(expiresUnix - now)
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    if h > 0 then
        return string.format("%dh %dm", h, m)
    end
    if m > 0 then
        return string.format("%dm %ds", m, s)
    end
    return string.format("%ds", s)
end

--- Read unix expiry for a spell from char.ProfCooldownExpiry
function CD.GetExpiryUnix(char, spellId)
    if not char or not spellId then return nil end
    local t = char.ProfCooldownExpiry and char.ProfCooldownExpiry[spellId]
    if t == nil then return nil end
    if type(t) == "table" then
        return t.expiresAtUnix
    end
    if type(t) == "number" then
        return t
    end
    return nil
end

--- @param DS table AltArmy.DataStore
--- @param options table AltArmyTBC_Options.cooldowns shape
--- @param now number|nil unix
--- @return table[] rows { categoryKey, categoryTitle, name, realm, spellId, expiresUnix }
function CD.BuildRows(DS, options, now)
    now = now or (time and time() or 0)
    local rows = {}
    if not DS or not DS.GetRealms then return rows end

    for _, catKey in ipairs(CD.CATEGORY_ORDER) do
        if CategoryRowVisible(catKey, options) then
            local cat = CD.CATEGORIES[catKey]
            if cat then
                for realm in pairs(DS:GetRealms()) do
                    for charName, char in pairs(DS:GetCharacters(realm)) do
                        local displayName = (char and char.name) or charName
                        local include = false
                        if catKey == "transmute" then
                            include = CD.ResolveTransmuteSpellForCharacter(char) ~= nil
                        elseif catKey == "salt_shaker" then
                            include = CD.CharacterQualifiesSaltShakerCooldown(char, DS)
                        elseif cat.mode == "single" and cat.spellId then
                            include = select(1, CD.FindRecipeProfession(char, cat.spellId))
                        end
                        if include then
                            local spellId = CD.ResolveEffectiveSpellId(catKey, char, options)
                            local expires = CD.GetExpiryUnix(char, spellId)
                            local gsi = type(_G.GetSpellInfo) == "function" and _G.GetSpellInfo or nil
                            local title = cat.title
                            if catKey == "transmute" then
                                title = CD.TransmuteCategoryDisplayTitle(spellId, gsi)
                            end
                            rows[#rows + 1] = {
                                categoryKey = catKey,
                                categoryTitle = title,
                                charKeyName = charName,
                                name = displayName,
                                realm = realm,
                                spellId = spellId,
                                expiresUnix = expires,
                                timeText = CD.FormatTimeRemaining(expires, now),
                            }
                        end
                    end
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.categoryTitle ~= b.categoryTitle then
            return a.categoryTitle < b.categoryTitle
        end
        if a.name ~= b.name then
            return a.name < b.name
        end
        return (a.realm or "") < (b.realm or "")
    end)
    return rows
end

--- Alert evaluation: returns list of fired alerts { categoryKey, name, realm, spellId, kind }
--- kind = "available" | "soon"
--- stateMutate: availAnnounced, soonAnnounced — cleared when cooldown no longer in that state
function CD.EvaluateAlerts(DS, options, now, stateMutate)
    local results = {}
    if not DS or not options then return results end
    now = now or (time and time() or 0)
    stateMutate = stateMutate or {}
    stateMutate.availAnnounced = stateMutate.availAnnounced or {}
    stateMutate.soonAnnounced = stateMutate.soonAnnounced or {}

    local rows = CD.BuildRows(DS, options, now)
    for _, row in ipairs(rows) do
        local catKey = row.categoryKey
        local catOpts = options.categories and options.categories[catKey] or {}
        if not catOpts.hide and catOpts.alertWhenAvailable ~= false then
            local exp = row.expiresUnix
            local key = (row.realm or "") .. "\0" .. (row.name or "") .. "\0" .. catKey

            if exp ~= nil and exp <= now then
                stateMutate.soonAnnounced[key] = nil
                if not stateMutate.availAnnounced[key] then
                    stateMutate.availAnnounced[key] = true
                    results[#results + 1] = {
                        categoryKey = catKey,
                        name = row.name,
                        realm = row.realm,
                        spellId = row.spellId,
                        kind = "available",
                    }
                end
            else
                stateMutate.availAnnounced[key] = nil
            end

            if catOpts.alertMinutesBefore and tonumber(catOpts.alertMinutesBeforeMinutes) then
                local mins = tonumber(catOpts.alertMinutesBeforeMinutes) or 15
                local leadSec = math.max(0, mins * 60)
                if exp and exp > now and (exp - now) <= leadSec then
                    if not stateMutate.soonAnnounced[key] then
                        stateMutate.soonAnnounced[key] = true
                        results[#results + 1] = {
                            categoryKey = catKey,
                            name = row.name,
                            realm = row.realm,
                            spellId = row.spellId,
                            kind = "soon",
                        }
                    end
                else
                    stateMutate.soonAnnounced[key] = nil
                end
            end
        end
    end
    return results
end
