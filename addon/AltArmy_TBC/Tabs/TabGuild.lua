-- AltArmy TBC — Guild tab: guildmates shared via guild data sharing, grouped by main.
-- Always present when the guildShare feature flag is on (button visibility handled in Core.lua).
-- Layout:
--   * fixed header: guild name + tabard (left), search field aligned with main header search (right)
--   * scroll body: one row per main (preferred name + character count), expandable to reveal
--     each character (class-colored name, gray level, primary professions)
--   * recipe detail: Back + character title, profession tabs, scrollable recipe list
-- Two content states, driven by the user's OWN sharing setting (not the feature flag):
--   * sharing enabled  -> the header + list above
--   * sharing disabled -> a message plus a link to open the sharing options.

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Guild
if not frame then return end

local Theme = AltArmy.Theme
local CC = AltArmy.ClassColor
local GTD = AltArmy.GuildTabData
local SECTION_INSET = Theme.TAB_SECTION_INSET
local PAD = Theme.TAB_CONTENT_PADDING
local SCROLL_GUTTER = Theme.VerticalScrollBarGutter()

local HEADER_HEIGHT = 32
local RECIPE_TITLE_HEIGHT = 32
local PROF_TAB_HEIGHT = 26
local PROF_TAB_GAP = 4
local RECIPE_ROW_HEIGHT = 18
local MAIN_ROW_HEIGHT = 20
local CHAR_ROW_HEIGHT = 18
local GROUP_GAP = 4
local CHAR_INDENT = 24
local GRAY = "|cff808080"
-- Professions column starts this far right of the character name column's left edge, so
-- every character's professions share one left edge regardless of name/level width.
local PROF_COLUMN = 180
local NAME_COLUMN_GAP = 8
local TABARD_SIZE = 24
local SEARCH_PLACEHOLDER = "Search for characters or professions"

local function currentGuild()
    if GetGuildInfo then
        local g = GetGuildInfo("player")
        if g and g ~= "" then return g end
    end
    return nil
end

local function formatName(name, classFile)
    if CC and CC.formatName then return CC.formatName(name, classFile) end
    return name or "?"
end

-- Session-only expand state, keyed by group main character name.
local expandedMains = {}
-- Snapshot of expand state before search began; restored when the search box is cleared.
local savedExpandedMains = nil
-- Current search text (trimmed lower handled by GuildTabData.NormalizeSearchQuery).
local searchText = ""
-- Recipe detail view state (session-only).
local selectedCharacter = nil
local selectedCharacterKey = nil
local selectedProfIndex = 1
-- When the current character is not guilded, browse a guild from account alts.
local selectedBrowseGuild = nil

local function activeGuild()
    local g = currentGuild()
    if g then return g end
    return selectedBrowseGuild
end

local function isBrowsingWithoutGuild()
    return not currentGuild() and selectedBrowseGuild ~= nil
end

local function shouldShowGuildPicker()
    if currentGuild() or selectedBrowseGuild then return false end
    return #(GTD.CollectAccountGuilds()) > 1
end

local function shouldShowBrowseBackButton()
    return isBrowsingWithoutGuild() and #(GTD.CollectAccountGuilds()) > 1
end

local function memberKey(entry)
    return (entry.realm or "") .. "\0" .. (entry.name or "")
end

local function GetRecipeLink(recipeID)
    if not recipeID then return nil end
    if _G.GetSpellLink then
        local link = _G.GetSpellLink(recipeID)
        if link and link ~= "" then return link end
    end
    if GetItemInfo then
        local _, link = GetItemInfo(recipeID)
        if link and link ~= "" then return link end
    end
    return nil
end

local function resolveRecipeDisplay(recipeID, resultItemID)
    local recipeName = "Recipe " .. tostring(recipeID or "?")
    local iconPath = "Interface\\Icons\\INV_Misc_QuestionMark"
    if GetSpellInfo and recipeID then
        local name = GetSpellInfo(recipeID)
        if name then recipeName = name end
    end
    if recipeName == ("Recipe " .. tostring(recipeID or "?")) and GetItemInfo and recipeID then
        local name = GetItemInfo(recipeID)
        if name then recipeName = name end
    end
    if resultItemID and GetItemInfo then
        local _, _, _, _, _, _, _, _, _, resultIcon = GetItemInfo(resultItemID)
        if resultIcon then iconPath = resultIcon end
    end
    if not resultItemID and GetItemInfo and recipeID then
        local _, _, _, _, _, _, _, _, _, icon = GetItemInfo(recipeID)
        if icon then iconPath = icon end
    end
    if not resultItemID and GetSpellInfo and recipeID then
        local _, _, spellIcon = GetSpellInfo(recipeID)
        if spellIcon then iconPath = spellIcon end
    end
    return recipeName, iconPath
end

local showRecipeView
local showGuildList
local layoutRecipeView
local refresh

local function copyExpandState(src)
    local out = {}
    for key, value in pairs(src or {}) do
        if value then out[key] = true end
    end
    return out
end

local function normalizedSearchText()
    return GTD.NormalizeSearchQuery(searchText)
end

local function applySearchExpansion(groups)
    if normalizedSearchText() == "" then
        if savedExpandedMains ~= nil then
            expandedMains = copyExpandState(savedExpandedMains)
            savedExpandedMains = nil
        end
        return
    end
    if savedExpandedMains == nil then
        savedExpandedMains = copyExpandState(expandedMains)
    end
    for _, g in ipairs(groups) do
        expandedMains[g.main] = true
    end
end

-- *** Layout: panel + message state ***

local panel = Theme.CreateTabContentPanel(frame)
panel:SetPoint("TOPLEFT", frame, "TOPLEFT", SECTION_INSET, -SECTION_INSET)
panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SECTION_INSET, SECTION_INSET)
local inner = Theme.CreatePanelInnerContent(panel)

-- Disabled / no-guild message state
local messageView = CreateFrame("Frame", nil, inner)
messageView:SetAllPoints(inner)
messageView:Hide()

local messageText = messageView:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
messageText:SetPoint("TOP", messageView, "TOP", 0, -60)
messageText:SetWidth(360)
messageText:SetJustifyH("CENTER")

local optionsBtn = CreateFrame("Button", nil, messageView)
optionsBtn:SetSize(180, 24)
optionsBtn:SetPoint("TOP", messageText, "BOTTOM", 0, -16)
Theme.SkinButton(optionsBtn)
local optionsBtnLabel = optionsBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
optionsBtnLabel:SetPoint("CENTER", optionsBtn, "CENTER", 0, 0)
optionsBtnLabel:SetText("Open sharing options")
optionsBtn:SetScript("OnClick", function()
    if AltArmy.OpenInterfaceOptions then
        AltArmy.OpenInterfaceOptions()
    end
end)

-- *** List state (header + scroll body) ***

local listView = CreateFrame("Frame", nil, inner)
listView:SetAllPoints(inner)
listView:Hide()

-- Fixed header (does not scroll)
local header = CreateFrame("Frame", nil, listView)
header:SetPoint("TOPLEFT", listView, "TOPLEFT", 0, 0)
header:SetPoint("TOPRIGHT", listView, "TOPRIGHT", 0, 0)
header:SetHeight(HEADER_HEIGHT)
header:SetFrameLevel(listView:GetFrameLevel() + 5)

local guildNameText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
guildNameText:SetPoint("LEFT", header, "LEFT", 2, 0)
guildNameText:SetJustifyH("LEFT")
Theme.SetTitleColor(guildNameText)

-- Guild tabard: three stacked textures composed by SetLargeGuildTabardTextures.
local tabardFrame = CreateFrame("Frame", nil, header)
tabardFrame:SetSize(TABARD_SIZE, TABARD_SIZE)
tabardFrame:SetPoint("LEFT", guildNameText, "RIGHT", 6, 0)
tabardFrame:Hide()
local tabardBackground = tabardFrame:CreateTexture(nil, "BACKGROUND")
tabardBackground:SetAllPoints(tabardFrame)
local tabardEmblem = tabardFrame:CreateTexture(nil, "ARTWORK")
tabardEmblem:SetAllPoints(tabardFrame)
local tabardBorder = tabardFrame:CreateTexture(nil, "OVERLAY")
tabardBorder:SetAllPoints(tabardFrame)

local function updateTabard()
    if not currentGuild() or isBrowsingWithoutGuild() then
        tabardFrame:Hide()
        return
    end
    if SetLargeGuildTabardTextures then
        SetLargeGuildTabardTextures("player", tabardEmblem, tabardBackground, tabardBorder)
        tabardFrame:Show()
        return
    end
    -- Fallback: modern C_GuildInfo emblem info (background color only; emblem needs the helper).
    if C_GuildInfo and C_GuildInfo.GetGuildTabardInfo then
        local info = C_GuildInfo.GetGuildTabardInfo("player")
        if info and info.backgroundColor then
            local c = info.backgroundColor
            tabardBackground:SetColorTexture(c.r or 0, c.g or 0, c.b or 0, 1)
            tabardEmblem:SetTexture(info.emblemFileID)
            tabardBorder:SetTexture(nil)
            tabardFrame:Show()
            return
        end
    end
    tabardFrame:Hide()
end

-- Search field: same width and left edge as the main header search (Core.lua).
local headerSearchRef = _G.AltArmyTBC_HeaderSearchEdit
local searchEdit = CreateFrame("EditBox", "AltArmyTBC_GuildSearchEdit", header)
if headerSearchRef then
    searchEdit:SetPoint("LEFT", headerSearchRef, "LEFT", 0, 0)
    searchEdit:SetPoint("RIGHT", headerSearchRef, "RIGHT", 0, 0)
else
    searchEdit:SetSize(288, 20)
    searchEdit:SetPoint("RIGHT", header, "RIGHT", -20, 0)
end
searchEdit:SetHeight(20)
searchEdit:SetPoint("TOP", header, "TOP", 0, -6)
searchEdit:SetAutoFocus(false)
searchEdit:SetFontObject("GameFontHighlight")
if searchEdit.SetTextInsets then
    searchEdit:SetTextInsets(6, 6, 0, 0)
end
Theme.ApplyInputTextures(searchEdit)

local searchClearBtn = CreateFrame("Button", nil, header)
searchClearBtn:SetPoint("RIGHT", searchEdit, "LEFT", -2, 0)
searchClearBtn:SetSize(18, 18)
searchClearBtn:Hide()
local searchClearLabel = searchClearBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
searchClearLabel:SetPoint("CENTER", searchClearBtn, "CENTER", 0, 0)
searchClearLabel:SetText("X")
searchClearBtn:SetHighlightFontObject("GameFontNormal")
searchClearBtn:SetScript("OnClick", function()
    searchEdit:SetText("")
    searchEdit:SetFocus()
end)

if searchEdit.SetPlaceholderText then
    searchEdit:SetPlaceholderText(SEARCH_PLACEHOLDER)
else
    local hint = searchEdit:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    hint:SetPoint("LEFT", searchEdit, "LEFT", 6, 0)
    hint:SetPoint("RIGHT", searchEdit, "RIGHT", -6, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText(SEARCH_PLACEHOLDER)
    hint:SetTextColor(0.5, 0.5, 0.5, 1)
    searchEdit.placeholderHint = hint
end

local function updateSearchPlaceholderVisibility()
    local hint = searchEdit.placeholderHint
    if not hint then return end
    local text = searchEdit:GetText()
    local trimmed = text and text:match("^%s*(.-)%s*$") or ""
    if trimmed == "" and not searchEdit:HasFocus() then
        hint:Show()
    else
        hint:Hide()
    end
end

local function updateSearchClearVisibility()
    local text = searchEdit:GetText()
    local trimmed = text and text:match("^%s*(.-)%s*$") or ""
    if trimmed == "" then
        searchClearBtn:Hide()
    else
        searchClearBtn:Show()
    end
end

-- Recipe detail header chrome (Back + title + profession tabs).
local guildBackBtn = CreateFrame("Button", nil, header)
guildBackBtn:SetSize(52, 22)
guildBackBtn:SetPoint("LEFT", header, "LEFT", 2, 0)
guildBackBtn:Hide()
Theme.SkinButton(guildBackBtn)
local guildBackBtnLabel = guildBackBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
guildBackBtnLabel:SetPoint("CENTER", guildBackBtn, "CENTER", 0, 0)
guildBackBtnLabel:SetText("Back")

local backBtn = CreateFrame("Button", nil, header)
backBtn:SetSize(52, 22)
backBtn:SetPoint("LEFT", header, "LEFT", 2, 0)
backBtn:Hide()
Theme.SkinButton(backBtn)
local backBtnLabel = backBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
backBtnLabel:SetPoint("CENTER", backBtn, "CENTER", 0, 0)
backBtnLabel:SetText("Back")

local recipeTitleFS = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
recipeTitleFS:SetPoint("LEFT", backBtn, "RIGHT", 8, 0)
recipeTitleFS:SetPoint("RIGHT", header, "RIGHT", -8, 0)
recipeTitleFS:SetJustifyH("LEFT")
recipeTitleFS:Hide()

local profTabStrip = CreateFrame("Frame", nil, header)
profTabStrip:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
profTabStrip:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -2)
profTabStrip:SetHeight(PROF_TAB_HEIGHT)
profTabStrip:Hide()

local function updateGuildHeaderForListMode()
    if shouldShowGuildPicker() then
        guildBackBtn:Hide()
        guildNameText:ClearAllPoints()
        guildNameText:SetPoint("LEFT", header, "LEFT", 2, 0)
        guildNameText:SetText("Select a guild")
        Theme.SetTitleColor(guildNameText)
        guildNameText:Show()
        searchEdit:Hide()
        searchClearBtn:Hide()
        tabardFrame:Hide()
        return
    end
    if isBrowsingWithoutGuild() and shouldShowBrowseBackButton() then
        guildBackBtn:Show()
        guildNameText:ClearAllPoints()
        guildNameText:SetPoint("LEFT", guildBackBtn, "RIGHT", 8, 0)
        guildNameText:SetText(selectedBrowseGuild or "")
        Theme.SetTitleColor(guildNameText)
        guildNameText:Show()
        searchEdit:Show()
        updateSearchClearVisibility()
        tabardFrame:Hide()
        return
    end
    guildBackBtn:Hide()
    guildNameText:ClearAllPoints()
    guildNameText:SetPoint("LEFT", header, "LEFT", 2, 0)
    guildNameText:SetText(activeGuild() or "")
    Theme.SetTitleColor(guildNameText)
    guildNameText:Show()
    searchEdit:Show()
    updateSearchClearVisibility()
    updateTabard()
end

local function setListHeaderVisible(visible)
    if visible then
        updateGuildHeaderForListMode()
    else
        guildNameText:Hide()
        guildBackBtn:Hide()
        searchEdit:Hide()
        searchClearBtn:Hide()
        tabardFrame:Hide()
    end
    backBtn:SetShown(not visible)
    recipeTitleFS:SetShown(not visible)
    profTabStrip:SetShown(not visible)
end

-- Scroll body below the header
local listViewport = CreateFrame("Frame", nil, listView)
listViewport:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -PAD)
listViewport:SetPoint("BOTTOMRIGHT", listView, "BOTTOMRIGHT", -SCROLL_GUTTER, PAD)

local viewport = Theme.CreateVerticalScrollViewport({
    parent = listViewport,
    gutterEdge = listViewport,
    anchorTop = { "TOPLEFT", listViewport, "TOPLEFT", 0, 0 },
    anchorBottom = { "BOTTOMRIGHT", listViewport, "BOTTOMRIGHT", 0, 0 },
    enableMouseWheel = true,
    valueStep = MAIN_ROW_HEIGHT,
})
local scrollChild = viewport.child

local WHEEL_STEP = MAIN_ROW_HEIGHT * 3
local function forwardWheel(_, delta)
    viewport.SetOffset(viewport.scroll:GetVerticalScroll() - delta * WHEEL_STEP)
end

-- Empty-state hint shown inside the list area (header stays visible).
local emptyText = listViewport:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
emptyText:SetPoint("TOP", listViewport, "TOP", 0, -40)
emptyText:SetWidth(360)
emptyText:SetJustifyH("CENTER")
emptyText:Hide()

-- Recipe detail body (below header / profession tabs).
local recipeBody = CreateFrame("Frame", nil, listView)
recipeBody:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -PAD)
recipeBody:SetPoint("BOTTOMRIGHT", listView, "BOTTOMRIGHT", -SCROLL_GUTTER, PAD)
recipeBody:Hide()

local recipeViewportFrame = CreateFrame("Frame", nil, recipeBody)
recipeViewportFrame:SetAllPoints(recipeBody)

local recipeViewport = Theme.CreateVerticalScrollViewport({
    parent = recipeViewportFrame,
    gutterEdge = recipeBody,
    anchorTop = { "TOPLEFT", recipeViewportFrame, "TOPLEFT", 0, 0 },
    anchorBottom = { "BOTTOMRIGHT", recipeViewportFrame, "BOTTOMRIGHT", 0, 0 },
    enableMouseWheel = true,
    valueStep = RECIPE_ROW_HEIGHT,
})
local recipeScrollChild = recipeViewport.child

local RECIPE_WHEEL_STEP = RECIPE_ROW_HEIGHT * 3
local function forwardRecipeWheel(_, delta)
    recipeViewport.SetOffset(recipeViewport.scroll:GetVerticalScroll() - delta * RECIPE_WHEEL_STEP)
end

local noProfText = recipeBody:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
noProfText:SetPoint("CENTER", recipeBody, "CENTER", 0, 0)
noProfText:SetWidth(360)
noProfText:SetJustifyH("CENTER")
noProfText:Hide()

local loadingText = recipeBody:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
loadingText:SetPoint("CENTER", recipeBody, "CENTER", 0, 0)
loadingText:SetWidth(360)
loadingText:SetJustifyH("CENTER")
loadingText:SetText("Loading recipes…")
loadingText:Hide()

local profTabPool = {}
local recipeRowPool = {}

-- *** Row pools ***

local mainRowPool = {}
local charRowPool = {}

local function acquireMainRow(index)
    local row = mainRowPool[index]
    if not row then
        row = CreateFrame("Button", nil, scrollChild)
        row:SetHeight(MAIN_ROW_HEIGHT)
        Theme.InstallHoverTint(row)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", forwardWheel)
        row:SetScript("OnEnter", function() Theme.SetHoverTint(row, true) end)
        row:SetScript("OnLeave", function() Theme.SetHoverTint(row, false) end)
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", row, "LEFT", 4, 0)
        label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        label:SetJustifyH("LEFT")
        row.label = label
        mainRowPool[index] = row
    end
    row:Show()
    return row
end

local function acquireCharRow(index)
    local row = charRowPool[index]
    if not row then
        row = CreateFrame("Button", nil, scrollChild)
        row:SetHeight(CHAR_ROW_HEIGHT)
        Theme.InstallHoverTint(row)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", forwardWheel)
        row:SetScript("OnEnter", function() Theme.SetHoverTint(row, true) end)
        row:SetScript("OnLeave", function() Theme.SetHoverTint(row, false) end)
        local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameFS:SetPoint("LEFT", row, "LEFT", 0, 0)
        nameFS:SetPoint("RIGHT", row, "LEFT", PROF_COLUMN - NAME_COLUMN_GAP, 0)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetWordWrap(false)
        row.nameFS = nameFS
        local profFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        profFS:SetPoint("LEFT", row, "LEFT", PROF_COLUMN, 0)
        profFS:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        profFS:SetJustifyH("LEFT")
        profFS:SetWordWrap(false)
        row.profFS = profFS
        charRowPool[index] = row
    end
    row:Show()
    return row
end

local function hideMainRowsFrom(index)
    for i = index, #mainRowPool do
        if mainRowPool[i] then mainRowPool[i]:Hide() end
    end
end

local function hideCharRowsFrom(index)
    for i = index, #charRowPool do
        if charRowPool[i] then charRowPool[i]:Hide() end
    end
end

local guildPickerRowPool = {}

local function hideGuildPickerRowsFrom(index)
    for i = index, #guildPickerRowPool do
        if guildPickerRowPool[i] then guildPickerRowPool[i]:Hide() end
    end
end

local function acquireGuildPickerRow(index)
    local row = guildPickerRowPool[index]
    if not row then
        row = CreateFrame("Button", nil, scrollChild)
        row:SetHeight(MAIN_ROW_HEIGHT)
        Theme.InstallHoverTint(row)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", forwardWheel)
        row:SetScript("OnEnter", function() Theme.SetHoverTint(row, true) end)
        row:SetScript("OnLeave", function() Theme.SetHoverTint(row, false) end)
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", row, "LEFT", 4, 0)
        label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        label:SetJustifyH("LEFT")
        row.label = label
        guildPickerRowPool[index] = row
    end
    row:Show()
    return row
end

local function layoutGuildPicker(guilds)
    hideMainRowsFrom(1)
    hideCharRowsFrom(1)
    emptyText:Hide()
    local y = 0
    local width = math.max(1, (scrollChild:GetWidth() or listViewport:GetWidth() or 1))
    for i, guild in ipairs(guilds) do
        local row = acquireGuildPickerRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -y)
        row.label:SetText(guild)
        row:SetScript("OnClick", function()
            selectedBrowseGuild = guild
            refresh()
        end)
        y = y + MAIN_ROW_HEIGHT
    end
    hideGuildPickerRowsFrom(#guilds + 1)
    scrollChild:SetWidth(width)
    scrollChild:SetHeight(math.max(1, y))
    if viewport.UpdateRange then viewport.UpdateRange() end
end

local function hideRecipeRowsFrom(index)
    for i = index, #recipeRowPool do
        if recipeRowPool[i] then recipeRowPool[i]:Hide() end
    end
end

local function hideProfTabsFrom(index)
    for i = index, #profTabPool do
        if profTabPool[i] then profTabPool[i]:Hide() end
    end
end

local function isLoadingRecipes(entry, profKey)
    if not entry or entry.source == "local" or not entry.source then return false end
    local Comm = AltArmy.GuildShareComm
    if not Comm or not Comm.IsGuildMemberOnline or not Comm.IsGuildMemberOnline(entry.source) then
        return false
    end
    local prof = entry.Professions and entry.Professions[profKey]
    if not prof then return false end
    if prof.Recipes and prof.recipesRv == prof.rv then return false end
    return (prof.rv or 0) ~= 0 or (prof.count or 0) > 0
end

local function acquireRecipeRow(index)
    local row = recipeRowPool[index]
    if not row then
        row = CreateFrame("Frame", nil, recipeScrollChild)
        row:SetHeight(RECIPE_ROW_HEIGHT)
        row:EnableMouse(true)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", forwardRecipeWheel)
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", row, "LEFT", 4, 0)
        label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        row.label = label
        row:SetScript("OnEnter", function(self)
            local recipeID = self.recipeID
            if not recipeID or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
            local link = GetRecipeLink(recipeID)
            if link then
                GameTooltip:SetHyperlink(link)
            else
                GameTooltip:SetText("Recipe " .. tostring(recipeID))
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        row:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" or not IsShiftKeyDown() then return end
            local link = GetRecipeLink(self.recipeID)
            if link and ChatEdit_InsertLink then
                ChatEdit_InsertLink(link)
            end
        end)
        recipeRowPool[index] = row
    end
    row:Show()
    return row
end

local function sortRecipesByName(recipes)
    local sorted = {}
    for i = 1, #recipes do sorted[i] = recipes[i] end
    table.sort(sorted, function(a, b)
        local nameA = select(1, resolveRecipeDisplay(a.recipeID, a.resultItemID))
        local nameB = select(1, resolveRecipeDisplay(b.recipeID, b.resultItemID))
        nameA = (nameA or ""):lower()
        nameB = (nameB or ""):lower()
        if nameA ~= nameB then return nameA < nameB end
        return (a.recipeID or 0) < (b.recipeID or 0)
    end)
    return sorted
end

layoutRecipeView = function(entry)
    if not entry then return end
    local profs = GTD.GetPrimaryProfessions(entry)
    if selectedProfIndex < 1 or selectedProfIndex > #profs then
        selectedProfIndex = 1
    end

    local level = math.floor(tonumber(entry.level) or 0)
    recipeTitleFS:SetText(GTD.FormatCharacterTitle(entry, formatName)
        .. " " .. GRAY .. "(level " .. level .. ")|r")

    noProfText:Hide()
    loadingText:Hide()
    recipeViewportFrame:Hide()
    hideRecipeRowsFrom(1)
    hideProfTabsFrom(1)

    recipeBody:ClearAllPoints()
    recipeBody:SetPoint("BOTTOMRIGHT", listView, "BOTTOMRIGHT", -SCROLL_GUTTER, PAD)

    if #profs == 0 then
        profTabStrip:Hide()
        header:SetHeight(RECIPE_TITLE_HEIGHT)
        recipeBody:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -PAD)
        noProfText:SetText(GTD.FormatNoProfessionsMessage(entry, formatName))
        noProfText:Show()
        return
    end

    header:SetHeight(RECIPE_TITLE_HEIGHT)
    profTabStrip:Show()
    recipeBody:SetPoint("TOPLEFT", profTabStrip, "BOTTOMLEFT", 0, -PAD)

    local tabX = 0
    for i, prof in ipairs(profs) do
        local tab = profTabPool[i]
        if not tab then
            tab = CreateFrame("Button", nil, profTabStrip)
            tab:SetHeight(PROF_TAB_HEIGHT - 4)
            Theme.SkinButton(tab, true)
            local tabLabel = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            tabLabel:SetPoint("CENTER", tab, "CENTER", 0, 0)
            tab.label = tabLabel
            profTabPool[i] = tab
        end
        tab:ClearAllPoints()
        tab:SetPoint("LEFT", profTabStrip, "LEFT", tabX, 0)
        local labelText = prof.name or prof.key or "?"
        tab.label:SetText(labelText)
        local textWidth = tab.label:GetStringWidth() or 40
        tab:SetWidth(math.max(64, textWidth + 16))
        tab:SetSelected(i == selectedProfIndex)
        tab:Show()
        tab:SetScript("OnClick", function()
            selectedProfIndex = i
            layoutRecipeView(selectedCharacter)
        end)
        tabX = tabX + tab:GetWidth() + PROF_TAB_GAP
    end
    hideProfTabsFrom(#profs + 1)

    local selectedProf = profs[selectedProfIndex]
    local profKey = selectedProf and selectedProf.key
    if isLoadingRecipes(entry, profKey) then
        loadingText:Show()
        return
    end

    local recipes = sortRecipesByName(GTD.GetProfessionRecipes(entry, profKey))
    recipeViewportFrame:Show()
    local y = 0
    local width = math.max(1, (recipeScrollChild:GetWidth() or recipeBody:GetWidth() or 1))
    for i, recipe in ipairs(recipes) do
        local row = acquireRecipeRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", recipeScrollChild, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", recipeScrollChild, "TOPRIGHT", 0, -y)
        row.recipeID = recipe.recipeID
        local recipeName, iconPath = resolveRecipeDisplay(recipe.recipeID, recipe.resultItemID)
        row.label:SetText(("|T%s:0|t %s"):format(iconPath, recipeName))
        y = y + RECIPE_ROW_HEIGHT
    end
    hideRecipeRowsFrom(#recipes + 1)
    recipeScrollChild:SetWidth(width)
    recipeScrollChild:SetHeight(math.max(1, y))
    if recipeViewport.UpdateRange then recipeViewport.UpdateRange() end
    recipeViewport.SetOffset(0)
end

showGuildList = function()
    selectedCharacter = nil
    selectedCharacterKey = nil
    selectedProfIndex = 1
    header:SetHeight(HEADER_HEIGHT)
    setListHeaderVisible(true)
    listViewport:Show()
    recipeBody:Hide()
    profTabStrip:Hide()
end

showRecipeView = function(entry)
    selectedCharacter = entry
    selectedCharacterKey = memberKey(entry)
    selectedProfIndex = 1
    setListHeaderVisible(false)
    listViewport:Hide()
    emptyText:Hide()
    recipeBody:Show()
    if entry.source and entry.source ~= "local" then
        local Comm = AltArmy.GuildShareComm
        if Comm and Comm.RequestRecipesForCharacter then
            Comm.RequestRecipesForCharacter(entry.name, entry.realm, entry.source)
        end
    end
    layoutRecipeView(entry)
end

backBtn:SetScript("OnClick", function()
    showGuildList()
    refresh()
end)

guildBackBtn:SetScript("OnClick", function()
    selectedBrowseGuild = nil
    selectedCharacter = nil
    selectedCharacterKey = nil
    refresh()
end)

-- *** Refresh ***

local function showMessage(text, withButton)
    selectedCharacter = nil
    selectedCharacterKey = nil
    selectedBrowseGuild = nil
    listView:Hide()
    messageView:Show()
    messageText:SetText(text)
    optionsBtn:SetShown(withButton and true or false)
end

local function layoutList(groups, query)
    hideGuildPickerRowsFrom(1)
    local mainIndex = 0
    local charIndex = 0
    local y = 0
    local width = math.max(1, (scrollChild:GetWidth() or listViewport:GetWidth() or 1))
    local activeQuery = GTD.NormalizeSearchQuery(query)

    for _, g in ipairs(groups) do
        mainIndex = mainIndex + 1
        local isExpanded = expandedMains[g.main] and true or false
        local row = acquireMainRow(mainIndex)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -y)
        row.label:SetText(GTD.FormatMainRowLabel(g, formatName, activeQuery ~= "" and activeQuery or nil))
        row.groupMain = g.main
        row:SetScript("OnClick", function()
            expandedMains[g.main] = not expandedMains[g.main]
            layoutList(groups, query)
        end)
        y = y + MAIN_ROW_HEIGHT

        if isExpanded then
            for _, m in ipairs(g.members) do
                charIndex = charIndex + 1
                local charRow = acquireCharRow(charIndex)
                charRow:ClearAllPoints()
                charRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", CHAR_INDENT, -y)
                charRow:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
                charRow.nameFS:SetText(GTD.FormatCharacterName(
                    m, formatName, activeQuery ~= "" and activeQuery or nil))
                charRow.profFS:SetText(GTD.FormatProfessions(
                    m, activeQuery ~= "" and activeQuery or nil))
                charRow.memberEntry = m
                charRow:SetScript("OnClick", function()
                    showRecipeView(m)
                end)
                y = y + CHAR_ROW_HEIGHT
            end
        end
        y = y + GROUP_GAP
    end

    hideMainRowsFrom(mainIndex + 1)
    hideCharRowsFrom(charIndex + 1)
    scrollChild:SetWidth(width)
    scrollChild:SetHeight(math.max(1, y))
    if viewport.UpdateRange then viewport.UpdateRange() end
end

local function refreshImpl()
    if not frame:IsShown() then return end
    local GSS = AltArmy.GuildShareSettings
    local GSD = AltArmy.GuildShareData

    if not GSS or not GSS.IsSharingEnabled() then
        selectedCharacter = nil
        selectedCharacterKey = nil
        selectedBrowseGuild = nil
        showMessage("Guild sharing is disabled.\n\nEnable it to see the professions and characters"
            .. " your guildmates are sharing, and to share your own.", true)
        return
    end

    if currentGuild() then
        selectedBrowseGuild = nil
    elseif not selectedBrowseGuild then
        local autoBrowse = GTD.GetAutoBrowseGuild(GTD.CollectAccountGuilds())
        if autoBrowse then
            selectedBrowseGuild = autoBrowse
        end
    end

    local guild = activeGuild()
    if not guild then
        selectedCharacter = nil
        selectedCharacterKey = nil
        if shouldShowGuildPicker() then
            messageView:Hide()
            listView:Show()
            showGuildList()
            updateSearchPlaceholderVisibility()
            layoutGuildPicker(GTD.CollectAccountGuilds())
            return
        end
        showMessage("You are not in a guild.", false)
        return
    end

    messageView:Hide()
    listView:Show()

    local realm = (GSS._CurrentRealm and GSS._CurrentRealm())
        or (GetRealmName and GetRealmName()) or ""
    local browseAllRealms = isBrowsingWithoutGuild()
    local members = (GSD and GSD.GetGuildMembersForDisplay(guild, realm, browseAllRealms)) or {}

    if selectedCharacterKey then
        local resolved
        for _, entry in ipairs(members) do
            if memberKey(entry) == selectedCharacterKey then
                resolved = entry
                break
            end
        end
        selectedCharacter = resolved or selectedCharacter
        if selectedCharacter then
            setListHeaderVisible(false)
            listViewport:Hide()
            emptyText:Hide()
            recipeBody:Show()
            layoutRecipeView(selectedCharacter)
            return
        end
        selectedCharacterKey = nil
    end

    showGuildList()
    updateSearchPlaceholderVisibility()

    local groups = GTD.GroupMembersByMain(members)
    local filtered = GTD.FilterGroups(groups, searchText)
    applySearchExpansion(filtered)

    if #filtered == 0 then
        hideMainRowsFrom(1)
        hideCharRowsFrom(1)
        scrollChild:SetHeight(1)
        if viewport.UpdateRange then viewport.UpdateRange() end
        if #members == 0 then
            emptyText:SetText("No guild data received yet.\n\n"
                .. "Data is exchanged as guildmates using Alt Army log in.")
        else
            emptyText:SetText("No guild members match your search.")
        end
        emptyText:Show()
        return
    end

    emptyText:Hide()
    layoutList(filtered, searchText)
end
refresh = refreshImpl

searchEdit:SetScript("OnTextChanged", function(box)
    local text = box:GetText() or ""
    searchText = text
    updateSearchPlaceholderVisibility()
    updateSearchClearVisibility()
    refresh()
end)
searchEdit:SetScript("OnEditFocusGained", updateSearchPlaceholderVisibility)
searchEdit:SetScript("OnEditFocusLost", updateSearchPlaceholderVisibility)
searchEdit:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
searchEdit:SetScript("OnEscapePressed", function(box)
    box:SetText("")
    box:ClearFocus()
end)
updateSearchClearVisibility()

-- Refresh the tabard when guild identity changes while the tab is visible.
local tabardEvents = CreateFrame("Frame")
tabardEvents:RegisterEvent("PLAYER_GUILD_UPDATE")
-- GUILDTABARD_UPDATE fires when the tabard changes; not present on every client build.
pcall(function() tabardEvents:RegisterEvent("GUILDTABARD_UPDATE") end)
tabardEvents:SetScript("OnEvent", function()
    if frame:IsShown() then
        updateTabard()
    end
end)

AltArmy.RefreshGuildTab = refresh
frame:SetScript("OnShow", refresh)
