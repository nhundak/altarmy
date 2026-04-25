-- AltArmy TBC — DataStore module: professions (skills + recipes).
-- Requires DataStore.lua (core) loaded first.

if not AltArmy or not AltArmy.DataStore then return end

local DS = AltArmy.DataStore
local GetCurrentCharTable = DS._GetCurrentCharTable
local DATA_VERSIONS = DS._DATA_VERSIONS

--- Chat debug for cooldown persistence. Enable: /run ALTARMY_DEBUG_COOLDOWNS=true then open Tailoring etc.
local function LogCooldownScanDebug(msg)
    if not rawget(_G, "ALTARMY_DEBUG_COOLDOWNS") then
        return
    end
    local text = "|cff00ccff[AltArmy:CD]|r " .. tostring(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(text)
    end
end

--- Seconds left from GetTradeSkillCooldown / GetCraftCooldown / GetSpellCooldown-style returns.
--- When `duration` (b) > 0: standard start + duration - GetTime().
--- When b is nil or 0, TBC Classic commonly returns **seconds remaining** in `a` (not start time).
local function CooldownRemainingSeconds(a, b, gt)
    gt = gt or 0
    if type(a) ~= "number" or a < 0 then
        return 0
    end
    if type(b) == "number" and b > 0 then
        return math.max(0, a + b - gt)
    end
    if not b or b == 0 then
        return math.max(0, a)
    end
    return 0
end

local function PrevExpiryUnix(char, spellId)
    if not char or not spellId then return nil end
    local t = char.ProfCooldownExpiry and char.ProfCooldownExpiry[spellId]
    if type(t) == "table" then
        return t.expiresAtUnix
    end
    if type(t) == "number" then
        return t
    end
    return nil
end

--- Persist a scanned cooldown safely.
--- Guard: zoning/loading can transiently return (0,0) for cooldown APIs even when not actually ready.
--- If we already have a future expiry and the scan returns exactly (0,0), keep the existing expiry.
local function PersistCooldownExpiry(char, spellId, a, b, gt, wall, logPrefix)
    if not char or not spellId then return false end
    gt = gt or (GetTime and GetTime() or 0)
    wall = wall or (time and time() or 0)

    local remaining = CooldownRemainingSeconds(a, b, gt)
    char.ProfCooldownExpiry = char.ProfCooldownExpiry or {}

    if remaining <= 0 then
        local prev = PrevExpiryUnix(char, spellId)
        local a0 = type(a) == "number" and a == 0
        local b0 = (b == nil) or (type(b) == "number" and b == 0)
        if a0 and b0 and type(prev) == "number" and prev > (wall + 30) then
            LogCooldownScanDebug(string.format(
                "%s spell=%d suppress overwrite from (0,0); prevExpUnix=%s wall=%s",
                tostring(logPrefix or "Persist"),
                spellId,
                tostring(prev),
                tostring(wall)
            ))
            return false
        end
        char.ProfCooldownExpiry[spellId] = { expiresAtUnix = wall }
        return true
    end

    char.ProfCooldownExpiry[spellId] = { expiresAtUnix = wall + math.ceil(remaining) }
    return true
end

-- Exposed for unit tests (see spec/Data/DataStoreProfessions_spec.lua)
DS._PersistCooldownExpiryForTest = PersistCooldownExpiry

local SkillTypeToColor = { header = 0, optimal = 1, medium = 2, easy = 3, trivial = 4 }
local SPELL_ID_FIRSTAID = 3273
local SPELL_ID_COOKING = 2550
local SPELL_ID_FISHING = 7732

--- Expand all category headers (used by delayed reagent retry; full scan uses snapshot/restore).
local function ExpandAllTradeSkillHeaders()
    if not GetNumTradeSkills or not ExpandTradeSkillSubClass then return end
    for i = GetNumTradeSkills(), 1, -1 do
        local _, skillType, _, _, isExpanded = GetTradeSkillInfo(i)
        if skillType == "header" and not isExpanded then
            ExpandTradeSkillSubClass(i)
        end
    end
end

-- Tradeskill UI snapshot (see DataStore_Crafts): force "All" filters + expand headers for scan, then restore.
local tsFilterSnapshot = {
    selectedIndex = nil,
    subClasses = nil,
    invSlots = nil,
    subClassID = nil,
    invSlotID = nil,
}

local tsHeaderCollapsed = {}

local function TradeSkillSubClassDropdownId()
    if not GetTradeSkillSubClassFilter then return 1 end
    if GetTradeSkillSubClassFilter(0) then
        return 1
    end
    local subs = tsFilterSnapshot.subClasses
    if not subs then return 1 end
    for i = 1, #subs do
        if GetTradeSkillSubClassFilter(i) then
            return i + 1
        end
    end
    return 1
end

local function TradeSkillInvSlotDropdownId()
    if not GetTradeSkillInvSlotFilter then return 1 end
    if GetTradeSkillInvSlotFilter(0) then
        return 1
    end
    local slots = tsFilterSnapshot.invSlots
    if not slots then return 1 end
    for i = 1, #slots do
        if GetTradeSkillInvSlotFilter(i) then
            return i + 1
        end
    end
    return 1
end

--- Returns true if subclass/slot filters were saved and switched to "All" (caller must restore).
local function SaveTradeSkillFiltersForScan()
    if not GetTradeSkillSelectionIndex or not SelectTradeSkill then return false end
    if not SetTradeSkillSubClassFilter or not SetTradeSkillInvSlotFilter then return false end
    if not GetTradeSkillSubClassFilter or not GetTradeSkillInvSlotFilter then return false end
    if not GetTradeSkillSubClasses or not GetTradeSkillInvSlots then return false end

    tsFilterSnapshot.selectedIndex = GetTradeSkillSelectionIndex()
    tsFilterSnapshot.subClasses = { GetTradeSkillSubClasses() }
    tsFilterSnapshot.invSlots = { GetTradeSkillInvSlots() }
    tsFilterSnapshot.subClassID = TradeSkillSubClassDropdownId()
    tsFilterSnapshot.invSlotID = TradeSkillInvSlotDropdownId()

    SetTradeSkillSubClassFilter(0, 1, 1)
    SetTradeSkillInvSlotFilter(0, 1, 1)
    if TradeSkillSubClassDropDown and UIDropDownMenu_SetSelectedID then
        UIDropDownMenu_SetSelectedID(TradeSkillSubClassDropDown, 1)
    end
    if TradeSkillInvSlotDropDown and UIDropDownMenu_SetSelectedID then
        UIDropDownMenu_SetSelectedID(TradeSkillInvSlotDropDown, 1)
    end
    return true
end

local function RestoreTradeSkillFiltersAfterScan()
    if tsFilterSnapshot.selectedIndex == nil then return end
    local subId = tsFilterSnapshot.subClassID
    local invId = tsFilterSnapshot.invSlotID
    local subs = tsFilterSnapshot.subClasses
    local slots = tsFilterSnapshot.invSlots

    if SetTradeSkillSubClassFilter and subId then
        SetTradeSkillSubClassFilter(subId - 1, 1, 1)
    end
    local frame = TradeSkillSubClassDropDown
    if frame and UIDropDownMenu_SetSelectedID and UIDropDownMenu_SetText and subs then
        local text = (subId == 1) and ALL_SUBCLASSES or subs[subId - 1]
        if text then
            UIDropDownMenu_SetSelectedID(frame, subId)
            UIDropDownMenu_SetText(frame, text)
        end
    end

    invId = invId or 1
    if SetTradeSkillInvSlotFilter then
        SetTradeSkillInvSlotFilter(invId - 1, 1, 1)
    end
    frame = TradeSkillInvSlotDropDown
    if frame and UIDropDownMenu_SetSelectedID and UIDropDownMenu_SetText and slots then
        local text = (invId == 1) and ALL_INVENTORY_SLOTS or slots[invId - 1]
        if text then
            UIDropDownMenu_SetSelectedID(frame, invId)
            UIDropDownMenu_SetText(frame, text)
        end
    end

    SelectTradeSkill(tsFilterSnapshot.selectedIndex)

    tsFilterSnapshot.selectedIndex = nil
    tsFilterSnapshot.subClasses = nil
    tsFilterSnapshot.invSlots = nil
    tsFilterSnapshot.subClassID = nil
    tsFilterSnapshot.invSlotID = nil
end

local function SaveTradeSkillHeadersForScan()
    wipe(tsHeaderCollapsed)
    if not GetNumTradeSkills or not GetTradeSkillInfo or not ExpandTradeSkillSubClass then return end
    local headerCount = 0
    for i = GetNumTradeSkills(), 1, -1 do
        local _, skillType, _, isExpanded = GetTradeSkillInfo(i)
        if skillType == "header" then
            headerCount = headerCount + 1
            if not isExpanded then
                ExpandTradeSkillSubClass(i)
                tsHeaderCollapsed[headerCount] = true
            end
        end
    end
end

local function RestoreTradeSkillHeadersAfterScan()
    if not GetNumTradeSkills or not GetTradeSkillInfo then
        wipe(tsHeaderCollapsed)
        return
    end
    local headerCount = 0
    for i = GetNumTradeSkills(), 1, -1 do
        local _, skillType = GetTradeSkillInfo(i)
        if skillType == "header" then
            headerCount = headerCount + 1
            if tsHeaderCollapsed[headerCount] and CollapseTradeSkillSubClass then
                CollapseTradeSkillSubClass(i)
            end
        end
    end
    wipe(tsHeaderCollapsed)
end

--- Spell ID from an item (pattern or crafted result), when the client exposes one (Cooldowns spell ids).
local function SpellIdFromItem(itemRef)
    if not itemRef or not GetItemSpell then return nil end
    local _, spellID = GetItemSpell(itemRef)
    if type(spellID) == "number" and spellID > 0 then
        return spellID
    end
    return nil
end

--- Match row title to Cooldown single-mode spells (hyperlink ids are often enchant/recipe, not cast spell).
local function AddCooldownSpellIdsMatchingRowName(index, add)
    local CD = AltArmy and AltArmy.CooldownData
    if not CD or not CD.CATEGORIES or not CD.CATEGORY_ORDER then return end
    if not GetTradeSkillInfo or not GetSpellInfo then return end
    local rowName = select(1, GetTradeSkillInfo(index))
    if not rowName or rowName == "" then return end
    for _, catKey in ipairs(CD.CATEGORY_ORDER) do
        local cat = CD.CATEGORIES[catKey]
        if cat and cat.mode == "single" and cat.spellId then
            local sid = cat.spellId
            local spellTitle = GetSpellInfo(sid)
            if spellTitle and spellTitle == rowName then
                add(sid)
            end
        end
    end
end

--- All numeric ids for one tradeskill row: link ids + GetItemSpell for pattern/result (match CooldownData spell ids).
local function CollectRecipeIdsFromTradeSkillIndex(index)
    local ids = {}
    local seen = {}
    local function add(id)
        if id and id > 0 and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    if GetTradeSkillRecipeLink then
        local link = GetTradeSkillRecipeLink(index)
        if link then
            add(tonumber(link:match("enchant:(%d+)")))
            add(tonumber(link:match("spell:(%d+)")))
            local itemFromLink = tonumber(link:match("item:(%d+)"))
            add(itemFromLink)
            if itemFromLink then
                add(SpellIdFromItem(itemFromLink))
            end
        end
    end
    if GetTradeSkillItemLink then
        local itemLink = GetTradeSkillItemLink(index)
        local resultItemId = itemLink and tonumber(itemLink:match("item:(%d+)"))
        if resultItemId then
            add(SpellIdFromItem(resultItemId))
        end
    end
    AddCooldownSpellIdsMatchingRowName(index, add)
    return ids
end

--- Persist tailoring/alchemy specialization passives for cooldown option filters (current character).
function DS:ScanCooldownSpecializations(char)
    if not char then return end
    local CD = AltArmy and AltArmy.CooldownData
    local ids = CD and CD.COOLDOWN_SPEC_SPELL_IDS
    if not ids then return end
    char.cooldownSpecs = char.cooldownSpecs or {}
    local cs = char.cooldownSpecs
    local function knows(spellId)
        if not spellId then return false end
        if _G.IsSpellKnown then
            local ok, k = pcall(_G.IsSpellKnown, spellId)
            if ok and k then return true end
        end
        return false
    end
    cs.masterTransmutation = knows(ids.masterTransmutation)
    cs.spellfireTailor = knows(ids.spellfireTailor)
    cs.shadoweaveTailor = knows(ids.shadoweaveTailor)
    cs.moonclothTailor = knows(ids.moonclothTailor)
end

function DS:ScanProfessionLinks()
    local char = GetCurrentCharTable()
    if not char then return end
    if not GetNumSkillLines or not GetSkillLineInfo then return end
    char.Professions = char.Professions or {}
    char.Prof1 = nil
    char.Prof2 = nil
    for i = GetNumSkillLines(), 1, -1 do
        local _, isHeader, isExpanded = GetSkillLineInfo(i)
        if isHeader and not isExpanded and ExpandSkillHeader then
            ExpandSkillHeader(i)
        end
    end
    local category
    for i = 1, GetNumSkillLines() do
        local skillName, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
        if not skillName then break end
        if isHeader then
            category = skillName
        else
            if category and skillName then
                local isPrimary = (category == "Professions")
                local isSecondary = (category == "Secondary Skills")
                if isPrimary or isSecondary then
                    if skillName == "Secourisme" and GetSpellInfo then
                        skillName = GetSpellInfo(SPELL_ID_FIRSTAID) or skillName
                    end
                    local prof = char.Professions[skillName]
                    if not prof then
                        prof = { rank = 0, maxRank = 0, Recipes = {} }
                        char.Professions[skillName] = prof
                    end
                    prof.rank = rank or 0
                    prof.maxRank = maxRank or 0
                    if isPrimary then prof.isPrimary = true end
                    if isSecondary then prof.isSecondary = true end
                    if isPrimary then
                        if not char.Prof1 then char.Prof1 = skillName
                        else char.Prof2 = skillName end
                    end
                end
            end
        end
    end
    char.lastUpdate = time()
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.professions = DATA_VERSIONS.professions
    self:ScanCooldownSpecializations(char)
end

function DS:ScanRecipes()
    local char = GetCurrentCharTable()
    if not char then return end
    local tradeskillName = GetTradeSkillLine and GetTradeSkillLine()
    if not tradeskillName or tradeskillName == "" or tradeskillName == "UNKNOWN" then return end
    if tradeskillName == "Secourisme" and GetSpellInfo then
        tradeskillName = GetSpellInfo(SPELL_ID_FIRSTAID) or tradeskillName
    end
    local numTradeSkills = GetNumTradeSkills and GetNumTradeSkills()
    if not numTradeSkills or numTradeSkills == 0 then return end
    local prof = char.Professions[tradeskillName]
    if not prof then
        prof = { rank = 0, maxRank = 0, Recipes = {} }
        char.Professions[tradeskillName] = prof
    end
    prof.Recipes = prof.Recipes or {}
    for k in pairs(prof.Recipes) do prof.Recipes[k] = nil end
    for i = 1, numTradeSkills do
        local _, recipeSkillType = GetTradeSkillInfo(i)
        -- Include rows whose difficulty string is unknown to our map (otherwise Spellcloth/etc. can be skipped).
        if recipeSkillType ~= "header" and recipeSkillType ~= "subheader" then
            local color = SkillTypeToColor[recipeSkillType] or 0
            -- recipeID must come from the recipe link (spell/enchant/recipe item), not the crafted result
            local recipeID
            if GetTradeSkillRecipeLink then
                local link = GetTradeSkillRecipeLink(i)
                if link then
                    recipeID = tonumber(link:match("enchant:(%d+)"))
                        or tonumber(link:match("spell:(%d+)"))
                        or tonumber(link:match("item:(%d+)"))
                end
            end
            local resultItemID
            if GetTradeSkillItemLink then
                local itemLink = GetTradeSkillItemLink(i)
                if itemLink then
                    resultItemID = tonumber(itemLink:match("item:(%d+)"))
                end
            end
            if recipeID then
                local row = { color = color, resultItemID = resultItemID }
                prof.Recipes[recipeID] = row
                for _, rid in ipairs(CollectRecipeIdsFromTradeSkillIndex(i)) do
                    if rid and rid ~= recipeID then
                        prof.Recipes[rid] = row
                    end
                end
            end
            -- Capture reagents even when recipe link parse fails (ids may come from item links/GetItemSpell).
            self:CaptureTradeSkillReagentsForIndex(i)
        end
    end
    char.lastUpdate = time()
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.professions = DATA_VERSIONS.professions
    self:ScanCooldownSpecializations(char)
end

--- Scan recipes from the Craft window (Enchanting in TBC Classic uses Craft API, not Trade Skill).
--- Only runs when GetCraftSkillLine etc. exist (TBC Classic); no-op on clients that use Trade Skill only.
function DS:ScanCraftRecipes()
    if not GetCraftSkillLine or not GetNumCrafts or not GetCraftInfo or not GetCraftRecipeLink then
        return
    end
    local char = GetCurrentCharTable()
    if not char then return end
    -- Classic client requires a positive index; omitting it errors: Usage: GetCraftSkillLine(index)
    local craftName = GetCraftSkillLine(1)
    if not craftName or craftName == "" then return end
    local numCrafts = GetNumCrafts()
    if not numCrafts or numCrafts == 0 then return end
    char.Professions = char.Professions or {}
    local prof = char.Professions[craftName]
    if not prof then
        prof = { rank = 0, maxRank = 0, Recipes = {} }
        char.Professions[craftName] = prof
    end
    prof.Recipes = prof.Recipes or {}
    for k in pairs(prof.Recipes) do prof.Recipes[k] = nil end
    local craftTypeToColor = { optimal = 1, medium = 2, easy = 3, trivial = 4 }
    for i = 1, numCrafts do
        local _, _, craftType = GetCraftInfo(i)
        if craftType and craftType ~= "header" then
            local color = craftTypeToColor[craftType] or 1
            local link = GetCraftRecipeLink(i)
            if link then
                local recipeID = tonumber(link:match("enchant:(%d+)"))
                if recipeID then
                    prof.Recipes[recipeID] = { color = color, resultItemID = nil }
                    self:CaptureCraftReagentsForIndex(i, recipeID)
                end
            end
        end
    end
    char.lastUpdate = time()
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.professions = DATA_VERSIONS.professions
    if self.ScanCraftCooldownExpiry then
        self:ScanCraftCooldownExpiry()
    end
end

local isRecipeScanInProgress = false

function DS:RunDeferredRecipeScan()
    if isRecipeScanInProgress then
        return
    end
    isRecipeScanInProgress = true
    local filtersSnapshotted = false
    local ok, err = pcall(function()
        filtersSnapshotted = SaveTradeSkillFiltersForScan()
        SaveTradeSkillHeadersForScan()
        self:ScanRecipes()
        if self.ScanTradeSkillCooldownExpiry then
            self:ScanTradeSkillCooldownExpiry()
        end
    end)
    pcall(RestoreTradeSkillHeadersAfterScan)
    if filtersSnapshotted then
        pcall(RestoreTradeSkillFiltersAfterScan)
    end
    isRecipeScanInProgress = false
    if not ok and err then
        error(err)
    end
end

--- Second pass: refresh RecipeReagents only (no recipe wipe). Helps when reagent APIs lag right after open.
function DS:CaptureAllTradeSkillReagentsOnly()
    if not GetNumTradeSkills or not GetTradeSkillLine then return end
    local name = GetTradeSkillLine()
    if not name or name == "" or name == "UNKNOWN" then
        return
    end
    local n = GetNumTradeSkills()
    if not n or n == 0 then return end
    local prevSel = GetTradeSkillSelectionIndex and GetTradeSkillSelectionIndex() or nil
    pcall(function()
        ExpandAllTradeSkillHeaders()
        for i = 1, n do
            local _, skillType = GetTradeSkillInfo(i)
            if skillType ~= "header" and skillType ~= "subheader" then
                pcall(function()
                    self:CaptureTradeSkillReagentsForIndex(i)
                end)
            end
        end
    end)
    if prevSel and SelectTradeSkill then
        pcall(function()
            SelectTradeSkill(prevSel)
        end)
    end
end

--- Enchanting craft UI: capture reagents for every row only (RecipeReagents cache).
function DS:CaptureAllCraftReagentsOnly()
    if not GetNumCrafts or not GetCraftRecipeLink then return end
    local num = GetNumCrafts()
    if not num or num == 0 then return end
    for i = 1, num do
        local _, _, craftType = GetCraftInfo(i)
        if craftType and craftType ~= "header" then
            local link = GetCraftRecipeLink(i)
            local recipeID = link and tonumber(link:match("enchant:(%d+)"))
            if recipeID then
                pcall(function()
                    self:CaptureCraftReagentsForIndex(i, recipeID)
                end)
            end
        end
    end
end

function DS:GetProfessions(char)
    return (char and char.Professions) or {}
end

function DS:GetProfession(char, name)
    if not char or not char.Professions or not name then return nil end
    return char.Professions[name]
end

function DS:GetProfession1(char)
    if not char then return 0, 0, nil end
    local name = char.Prof1
    if not name then return 0, 0, nil end
    local prof = char.Professions and char.Professions[name]
    if not prof then return 0, 0, name end
    return prof.rank or 0, prof.maxRank or 0, name
end

function DS:GetProfession2(char)
    if not char then return 0, 0, nil end
    local name = char.Prof2
    if not name then return 0, 0, nil end
    local prof = char.Professions and char.Professions[name]
    if not prof then return 0, 0, name end
    return prof.rank or 0, prof.maxRank or 0, name
end

function DS:GetCookingRank(char)
    if not char or not GetSpellInfo then return 0, 0 end
    local name = GetSpellInfo(SPELL_ID_COOKING)
    local prof = name and char.Professions and char.Professions[name]
    if not prof then return 0, 0 end
    return prof.rank or 0, prof.maxRank or 0
end

function DS:GetFishingRank(char)
    if not char or not GetSpellInfo then return 0, 0 end
    local name = GetSpellInfo(SPELL_ID_FISHING)
    local prof = name and char.Professions and char.Professions[name]
    if not prof then return 0, 0 end
    return prof.rank or 0, prof.maxRank or 0
end

function DS:GetFirstAidRank(char)
    if not char or not GetSpellInfo then return 0, 0 end
    local name = GetSpellInfo(SPELL_ID_FIRSTAID)
    local prof = name and char.Professions and char.Professions[name]
    if not prof then return 0, 0 end
    return prof.rank or 0, prof.maxRank or 0
end

function DS:GetNumRecipes(char, profName)
    if not char or not char.Professions or not profName then return 0 end
    local prof = char.Professions[profName]
    if not prof or not prof.Recipes then return 0 end
    local n = 0
    for _ in pairs(prof.Recipes) do n = n + 1 end
    return n
end

function DS:IsRecipeKnown(char, profName, spellID)
    if not char or not char.Professions or not profName or not spellID then return false end
    local prof = char.Professions[profName]
    if not prof or not prof.Recipes then return false end
    return prof.Recipes[spellID] ~= nil
end

--- Whether any profession on the character knows this recipe spell id.
function DS:IsRecipeKnownAnyProfession(char, spellID)
    if not char or not char.Professions or not spellID then return false end
    for _, prof in pairs(char.Professions) do
        if prof and prof.Recipes and prof.Recipes[spellID] ~= nil then
            return true
        end
    end
    return false
end

local function RecipeIdFromTradeLink(link)
    if not link then return nil end
    return tonumber(link:match("enchant:(%d+)"))
        or tonumber(link:match("spell:(%d+)"))
        or tonumber(link:match("item:(%d+)"))
end

local function RecipeIdFromEnchantLink(link)
    if not link then return nil end
    return tonumber(link:match("enchant:(%d+)"))
end

local function ItemIdFromItemLink(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)"))
end

--- Account-wide recipe reagent lists { { itemID, qty }, ... } keyed by spell/enchant/item id (Cooldowns tab mats).
function DS:SaveRecipeReagentsMulti(spellIds, reagentList)
    if not spellIds or #spellIds == 0 or not reagentList or #reagentList == 0 then return end
    local db = self.accountData
    if not db then return end
    db.RecipeReagents = db.RecipeReagents or {}
    local copy = {}
    for i, pair in ipairs(reagentList) do
        copy[i] = { pair[1], pair[2] or 1 }
    end
    for _, spellId in ipairs(spellIds) do
        if spellId and spellId > 0 then
            db.RecipeReagents[spellId] = copy
        end
    end
end

function DS:SaveRecipeReagents(spellId, reagentList)
    if not spellId then return end
    self:SaveRecipeReagentsMulti({ spellId }, reagentList)
end

function DS:CaptureTradeSkillReagentsForIndex(tradeSkillIndex)
    if not GetTradeSkillNumReagents or not GetTradeSkillReagentItemLink then return end
    -- Classic clients often require the row to be selected before reagent APIs return data.
    if SelectTradeSkill then
        SelectTradeSkill(tradeSkillIndex)
    end
    local declared = GetTradeSkillNumReagents(tradeSkillIndex) or 0
    local list = {}
    local function pushReagent(r)
        local link = GetTradeSkillReagentItemLink(tradeSkillIndex, r)
        if not link or link == "" then return false end
        local itemId = ItemIdFromItemLink(link)
        local need = 1
        if GetTradeSkillReagentInfo then
            local _, _, cnt = GetTradeSkillReagentInfo(tradeSkillIndex, r)
            if type(cnt) == "number" and cnt > 0 then
                need = cnt
            end
        end
        if itemId then
            list[#list + 1] = { itemId, need }
        end
        return true
    end
    if declared > 0 then
        for r = 1, declared do
            pushReagent(r)
        end
    else
        for r = 1, 16 do
            local link = GetTradeSkillReagentItemLink(tradeSkillIndex, r)
            if not link or link == "" then break end
            pushReagent(r)
        end
    end
    if #list == 0 then
        return
    end
    local ids = CollectRecipeIdsFromTradeSkillIndex(tradeSkillIndex)
    if #ids == 0 and GetTradeSkillRecipeLink then
        local link = GetTradeSkillRecipeLink(tradeSkillIndex)
        local fallback = link and RecipeIdFromTradeLink(link)
        if fallback then
            ids = { fallback }
        end
    end
    if #ids > 0 then
        self:SaveRecipeReagentsMulti(ids, list)
    end
end

function DS:CaptureCraftReagentsForIndex(craftIndex, recipeSpellId)
    if not recipeSpellId or not GetCraftNumReagents then return end
    local n = GetCraftNumReagents(craftIndex)
    if not n or n < 1 then return end
    local list = {}
    for r = 1, n do
        local link = GetCraftReagentItemLink and GetCraftReagentItemLink(craftIndex, r)
        local itemId = ItemIdFromItemLink(link)
        local need = 1
        if GetCraftReagentInfo then
            local _, _, cnt = GetCraftReagentInfo(craftIndex, r)
            if type(cnt) == "number" and cnt > 0 then
                need = cnt
            end
        end
        if itemId then
            list[#list + 1] = { itemId, need }
        end
    end
    if #list > 0 then
        self:SaveRecipeReagents(recipeSpellId, list)
    end
end

--- Leatherworking Salt Shaker item use (spell 19566): cooldown may not appear in GetTradeSkill list.
function DS:TryScanSaltShakerCooldownFromSpellApi()
    local CD = AltArmy and AltArmy.CooldownData
    if not CD or not CD.CharacterQualifiesSaltShakerCooldown or not CD.SALT_SHAKER_COOLDOWN_SPELL_ID then
        return
    end
    if not GetSpellCooldown then return end
    local char = GetCurrentCharTable()
    if not char then return end
    if not CD.CharacterQualifiesSaltShakerCooldown(char, self) then return end
    local spellId = CD.SALT_SHAKER_COOLDOWN_SPELL_ID
    local a, b = GetSpellCooldown(spellId)
    local gt = GetTime and GetTime() or 0
    local wall = time and time() or 0
    PersistCooldownExpiry(char, spellId, a, b, gt, wall, "SaltShaker")
    LogCooldownScanDebug(string.format(
        "SaltShaker spell=%d a=%s b=%s rem=%.1fs -> expUnix=%s",
        spellId,
        tostring(a),
        tostring(b),
        CooldownRemainingSeconds(a, b, gt),
        tostring(char.ProfCooldownExpiry[spellId] and char.ProfCooldownExpiry[spellId].expiresAtUnix)
    ))
end

--- Persist expiry for one tracked spell by reading GetSpellCooldown(spellId).
--- Intended to be called right after a successful cast / use.
function DS:TryScanTrackedCooldownFromSpellApi(spellId)
    local CD = AltArmy and AltArmy.CooldownData
    if not CD or not CD.IsTrackedSpellId then return end
    if not spellId or not CD.IsTrackedSpellId(spellId) then return end
    local GetSpellCooldown = _G.GetSpellCooldown
    if not GetSpellCooldown then return end

    local char = GetCurrentCharTable()
    if not char then return end

    local a, b = GetSpellCooldown(spellId)
    local gt = GetTime and GetTime() or 0
    local wall = time and time() or 0
    PersistCooldownExpiry(char, spellId, a, b, gt, wall, "SpellApi")
    LogCooldownScanDebug(string.format(
        "SpellApi spell=%d a=%s b=%s rem=%.1fs -> expUnix=%s",
        spellId,
        tostring(a),
        tostring(b),
        CooldownRemainingSeconds(a, b, gt),
        tostring(char.ProfCooldownExpiry[spellId] and char.ProfCooldownExpiry[spellId].expiresAtUnix)
    ))
end

--- Scan action bars for tracked spell/item cooldowns (current character only).
--- Useful when the user never opens the profession window, but keeps the cooldown on a bar.
function DS:TryScanTrackedCooldownsFromActionBars()
    local GetActionInfo = _G.GetActionInfo
    local GetActionCooldown = _G.GetActionCooldown
    if not GetActionInfo or not GetActionCooldown then return end
    local GetMacroInfo = _G.GetMacroInfo
    local char = GetCurrentCharTable()
    if not char then return end
    local CD = AltArmy and AltArmy.CooldownData
    if not CD or not CD.IsTrackedSpellId then return end
    local trackedIds = {}
    if CD.CATEGORIES then
        for _, cat in pairs(CD.CATEGORIES) do
            local list = cat and cat.spellIds
            if type(list) == "table" then
                for _, sid in ipairs(list) do
                    -- Keep all category spell ids; we'll filter for persistence via IsTrackedSpellId.
                    trackedIds[#trackedIds + 1] = sid
                end
            end
        end
    end

    local maxSlots = 180 -- fallback: scan more for modern/extra bars (e.g. TBC Anniversary)
    if type(_G.NUM_ACTIONBAR_BUTTONS) == "number"
        and type(_G.NUM_ACTIONBAR_PAGES) == "number"
        and _G.NUM_ACTIONBAR_BUTTONS > 0
        and _G.NUM_ACTIONBAR_PAGES > 0
    then
        maxSlots = math.max(maxSlots, _G.NUM_ACTIONBAR_BUTTONS * _G.NUM_ACTIONBAR_PAGES)
    end
    local gt = GetTime and GetTime() or 0
    local wall = time and time() or 0
    char.ProfCooldownExpiry = char.ProfCooldownExpiry or {}

    local scanned = 0
    local macroHits = 0
    local nonEmpty = 0
    local debugPrinted = 0
    local function persistFromActionCooldown(spellId, slot)
        local a, b = GetActionCooldown(slot)
        PersistCooldownExpiry(char, spellId, a, b, gt, wall, "ActionBar")
        scanned = scanned + 1
        LogCooldownScanDebug(string.format(
            "ActionBar slot=%d type=%s spell=%d a=%s b=%s rem=%.1fs expUnix=%s",
            slot,
            tostring(select(1, GetActionInfo(slot))),
            spellId,
            tostring(a),
            tostring(b),
            CooldownRemainingSeconds(a, b, gt),
            tostring(char.ProfCooldownExpiry[spellId] and char.ProfCooldownExpiry[spellId].expiresAtUnix)
        ))
    end
    for slot = 1, maxSlots do
        local actionType, actionId = GetActionInfo(slot)
        if actionType ~= nil then
            nonEmpty = nonEmpty + 1
            if rawget(_G, "ALTARMY_DEBUG_COOLDOWNS") and debugPrinted < 12 then
                debugPrinted = debugPrinted + 1
                LogCooldownScanDebug(string.format(
                    "ActionBar peek slot=%d type=%s id=%s",
                    slot,
                    tostring(actionType),
                    tostring(actionId)
                ))
            end
        end
        if actionType == "spell" and type(actionId) == "number" then
            local spellId = actionId
            if CD.IsTrackedSpellId(spellId) then
                persistFromActionCooldown(spellId, slot)
            end
        elseif actionType == "item" and type(actionId) == "number" then
            -- Salt Shaker can be placed on bars as an item; treat it as the tracked cooldown spell id.
            if CD.SALT_SHAKER_ITEM_ID
                and CD.SALT_SHAKER_COOLDOWN_SPELL_ID
                and actionId == CD.SALT_SHAKER_ITEM_ID
            then
                local spellId = CD.SALT_SHAKER_COOLDOWN_SPELL_ID
                persistFromActionCooldown(spellId, slot)
            end
        elseif actionType == "macro" and type(actionId) == "number" and GetMacroInfo and GetSpellInfo then
            -- Some profession casts appear on action bars as macros; match tracked spell names in macro body.
            local _, _, body = GetMacroInfo(actionId)
            if type(body) == "string" and body ~= "" then
                local bodyLower = body:lower()
                for _, spellId in ipairs(trackedIds) do
                    local sid = spellId
                    if CD.IsTrackedSpellId(sid) then
                        local sname = GetSpellInfo(sid)
                        if type(sname) == "string" and sname ~= "" then
                            if bodyLower:find(sname:lower(), 1, true) then
                                persistFromActionCooldown(sid, slot)
                                macroHits = macroHits + 1
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    LogCooldownScanDebug(string.format(
        "TryScanTrackedCooldownsFromActionBars maxSlots=%d nonEmpty=%d scanned=%d macroHits=%d trackedIds=%d",
        maxSlots,
        nonEmpty,
        scanned,
        macroHits,
        #trackedIds
    ))
end

--- Persist tracked profession cooldown expiry (unix) for spells used by Cooldowns tab.
function DS:ScanTradeSkillCooldownExpiry()
    local char = GetCurrentCharTable()
    if not char then return end
    local CD = AltArmy and AltArmy.CooldownData
    if not CD or not CD.IsTrackedSpellId then return end

    char.ProfCooldownExpiry = char.ProfCooldownExpiry or {}

    local prevSel = GetTradeSkillSelectionIndex and GetTradeSkillSelectionIndex() or nil
    local tradeLine = (GetTradeSkillLine and GetTradeSkillLine()) or "?"
    LogCooldownScanDebug(string.format(
        "ScanTradeSkillCooldownExpiry start trade=%s prevSel=%s",
        tradeLine,
        tostring(prevSel)
    ))

    pcall(function()
        ExpandAllTradeSkillHeaders()
    end)

    if not GetNumTradeSkills or not GetTradeSkillRecipeLink then
        LogCooldownScanDebug("abort: missing GetNumTradeSkills or GetTradeSkillRecipeLink")
    elseif GetNumTradeSkills then
        local numTradeSkills = GetNumTradeSkills()
        LogCooldownScanDebug("numTradeSkills=" .. tostring(numTradeSkills))
        if numTradeSkills and numTradeSkills > 0 then
            local trackedRows = 0
            for i = 1, numTradeSkills do
                local skillName, skillType = GetTradeSkillInfo(i)
                if skillType and skillType ~= "header" and skillType ~= "subheader" then
                    local link = GetTradeSkillRecipeLink(i)
                    local recipeID = RecipeIdFromTradeLink(link)
                    if recipeID and CD.IsTrackedSpellId(recipeID) then
                        trackedRows = trackedRows + 1
                        -- Cooldown APIs match the tradeskill UI: row must be selected (same as reagent capture).
                        if SelectTradeSkill then
                            pcall(SelectTradeSkill, i)
                        end
                        local gt = GetTime and GetTime() or 0
                        local wall = time and time() or 0
                        local remaining = 0
                        local branch = "none"
                        local a, b
                        if GetTradeSkillCooldown then
                            a, b = GetTradeSkillCooldown(i)
                            if type(b) == "number" and b > 0 then
                                branch = "start+duration"
                            elseif type(a) == "number" and a >= 0 and (not b or b == 0) then
                                branch = "remaining_only"
                            end
                            remaining = CooldownRemainingSeconds(a, b, gt)
                        end
                        local expiresUnix
                        if remaining <= 0 then
                            char.ProfCooldownExpiry[recipeID] = { expiresAtUnix = wall }
                            expiresUnix = wall
                        else
                            expiresUnix = wall + math.ceil(remaining)
                            char.ProfCooldownExpiry[recipeID] = { expiresAtUnix = expiresUnix }
                        end
                        local linkShort = link and link:sub(1, math.min(48, #link)) or "(nil)"
                        LogCooldownScanDebug(string.format(
                            " row=%d id=%d name=%q a=%s b=%s gt=%.3f branch=%s rem=%.1fs -> expUnix=%s (%s)",
                            i,
                            recipeID,
                            skillName or "?",
                            tostring(a),
                            tostring(b),
                            gt,
                            branch,
                            remaining,
                            tostring(expiresUnix),
                            remaining <= 0 and "READY" or "CD"
                        ))
                        LogCooldownScanDebug("  link=" .. linkShort)
                    end
                end
            end
            LogCooldownScanDebug("tracked recipe rows scanned=" .. tostring(trackedRows))
        end
    end

    if prevSel and SelectTradeSkill then
        pcall(function()
            SelectTradeSkill(prevSel)
        end)
    end
    LogCooldownScanDebug("restored selection to " .. tostring(prevSel))

    self:TryScanSaltShakerCooldownFromSpellApi()
end

function DS:ScanCraftCooldownExpiry()
    local char = GetCurrentCharTable()
    if not char then return end
    local CD = AltArmy and AltArmy.CooldownData
    if not CD or not CD.IsTrackedSpellId then return end
    if not GetNumCrafts or not GetCraftRecipeLink then return end
    if not GetCraftCooldown then return end

    char.ProfCooldownExpiry = char.ProfCooldownExpiry or {}
    local wall = time and time() or 0
    local gt = GetTime and GetTime() or 0
    local numCrafts = GetNumCrafts()
    LogCooldownScanDebug("ScanCraftCooldownExpiry numCrafts=" .. tostring(numCrafts))
    if not numCrafts or numCrafts == 0 then return end

    for i = 1, numCrafts do
        local link = GetCraftRecipeLink(i)
        local recipeID = RecipeIdFromEnchantLink(link)
        if recipeID and CD.IsTrackedSpellId(recipeID) then
            local a, b = GetCraftCooldown(i)
            local branch = "none"
            if type(b) == "number" and b > 0 then
                branch = "start+duration"
            elseif type(a) == "number" and a >= 0 and (not b or b == 0) then
                branch = "remaining_only"
            end
            local remaining = CooldownRemainingSeconds(a, b, gt)
            local expiresUnix
            if remaining <= 0 then
                char.ProfCooldownExpiry[recipeID] = { expiresAtUnix = wall }
                expiresUnix = wall
            else
                expiresUnix = wall + math.ceil(remaining)
                char.ProfCooldownExpiry[recipeID] = { expiresAtUnix = expiresUnix }
            end
            LogCooldownScanDebug(string.format(
                " craft row=%d enchantId=%d a=%s b=%s gt=%.3f %s rem=%.1fs expUnix=%s",
                i,
                recipeID,
                tostring(a),
                tostring(b),
                gt,
                branch,
                remaining,
                tostring(expiresUnix)
            ))
        end
    end
end
