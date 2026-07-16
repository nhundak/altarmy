-- AltArmy TBC — Guild tab: guildmates shared via guild data sharing, grouped by main.
-- Always present when the guildShare feature flag is on (button visibility handled in Core.lua).
-- Layout:
--   * fixed header: guild name + tabard (left), search field aligned with main header search (right, extended to close)
--   * scroll body: fixed Name / Character Count / Online column headers (click to sort), then
--     one row per main (preferred name + character count + last online), expandable to reveal
--     each character (class-colored name, gray level, primary professions, last online)
--   * recipe detail: Back + character title, profession tabs, recipe search (top right), scrollable recipe list
-- Two content states, driven by the user's OWN sharing setting (not the feature flag):
--   * sharing enabled  -> the header + list above
--   * sharing disabled -> a message plus a link to open the sharing options.

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Guild
if not frame then return end

local Theme = AltArmy.Theme
local CC = AltArmy.ClassColor
local GTD = AltArmy.GuildTabData
local SECTION_INSET = Theme.TAB_SECTION_INSET
local SECTION_GAP = Theme.SECTION_GAP
local PAD = Theme.TAB_CONTENT_PADDING
local SCROLL_GUTTER = Theme.VerticalScrollBarGutter()
-- Layout metrics packed to stay under Lua 5.1's 200-local / function limit.
local UI = {
    GRID_SPLIT_FRACTION = 0.6,
    HEADER_HEIGHT = 32,
    RECIPE_TITLE_HEIGHT = 32,
    PROF_TAB_HEIGHT = 26,
    PROF_TAB_GAP = 4,
    RECIPE_ROW_HEIGHT = 18,
    RECIPE_SKILL_COL_WIDTH = 72,
    RECIPE_COL_HEADER_HEIGHT = 18,
    -- Match TabCooldowns row height (18) and flush row packing (no inter-group gap).
    MAIN_ROW_HEIGHT = 18,
    CHAR_ROW_HEIGHT = 18,
    GROUP_GAP = 0,
    CHAR_INDENT = 12,
    LIST_COL_HEADER_HEIGHT = 18,
    GRAY = "|cff808080",
    -- Second column (group character count, character professions) shares one left edge.
    SECOND_COLUMN = 180,
    NAME_COLUMN_GAP = 8,
    -- Third column on main rows: most recent last-online across the group's characters.
    LAST_ONLINE_COLUMN_WIDTH = 72,
    OLD_DATA_ICON_WIDTH = 14,
    SETTINGS_ICON_WIDTH = 18,
    PIN_ICON_SIZE = 14,
    PIN_ICON_GAP = 2,
    MAIN_STAR_ICON_SIZE = 12,
    MAIN_STAR_ICON_GAP = 2,
    RIGHT_ICON_GAP = 2,
    LEFT_ICON_PAD = 4,
    TABARD_SIZE = 24,
    SEARCH_PLACEHOLDER = "Search for characters or professions",
    MAIN_STAR_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
}
-- Right edge reserves space for the settings gear only (old-data warning lives on the left).
UI.RIGHT_TRAILING_RESERVE = UI.SETTINGS_ICON_WIDTH + UI.RIGHT_ICON_GAP + 4

local function currentGuild()
    if GetGuildInfo then
        local g = GetGuildInfo("player")
        if g and g ~= "" then return g end
    end
    return nil
end

local function currentRealm()
    local GSS = AltArmy.GuildShareSettings
    if GSS and GSS._CurrentRealm then
        local r = GSS._CurrentRealm()
        if r and r ~= "" then return r end
    end
    return (GetRealmName and GetRealmName()) or ""
end

--- Guilds owned by account characters on the current realm (picker / auto-browse).
local function collectCurrentRealmGuilds()
    if GTD.CollectGuildsOnRealm then
        return GTD.CollectGuildsOnRealm(currentRealm())
    end
    return GTD.CollectAccountGuilds and GTD.CollectAccountGuilds() or {}
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
-- Recipe detail view: filter recipes by name (session-only).
local recipeSearchText = ""
-- Recipe detail view state (session-only).
local selectedCharacter = nil
local selectedCharacterKey = nil
local selectedProfIndex = 1
local recipeSortKey = "recipe"
local recipeSortAscending = true
-- Focused recipe when opened from search (green border + scroll-into-view once).
local focusRecipeID = nil
local focusScrollPending = false
-- Guild list column sort (session-only). Defaults applied when guild lookup mode changes.
local listSortKey = "name"
local listSortAscending = true
-- Tracks whether the current default was applied for in-guild roster lookup capability.
local listSortCanLookupOnline = nil
-- When the current character is not guilded, browse a guild from account alts.
local selectedBrowseGuild = nil
-- Group settings side panel (session-only).
local selectedSettingsGroup = nil
local deleteConfirmPending = false
local openGroupSettings
local closeGroupSettings
local updateGroupSettingsPanel
local ApplyGroupSettingsPanelLayout
local isGroupSettingsShown
local updateGuildHeaderForListMode
local applyListColumnLayout
local syncMainRowSettingsIcons

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
    return #(collectCurrentRealmGuilds()) > 1
end

local function shouldShowBrowseBackButton()
    return isBrowsingWithoutGuild() and #(collectCurrentRealmGuilds()) > 1
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
    return GTD.ResolveRecipeDisplay(recipeID, resultItemID)
end

local showRecipeView
local showGuildList
local layoutRecipeView
local refresh
local clearRecipeFocus
local applyRecipeFocus
local updateWhisperButton

-- Item ids whose icons were missing on last layout; refreshed when GET_ITEM_INFO_RECEIVED fires.
local pendingRecipeIconIds = {}
local recipeIconEvents

local function clearPendingRecipeIcons()
    for k in pairs(pendingRecipeIconIds) do
        pendingRecipeIconIds[k] = nil
    end
end

local function trackPendingRecipeIcon(itemID)
    if not itemID then return end
    pendingRecipeIconIds[itemID] = true
    if not recipeIconEvents and CreateFrame then
        recipeIconEvents = CreateFrame("Frame")
        recipeIconEvents:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        recipeIconEvents:SetScript("OnEvent", function(_, _, itemId)
            itemId = tonumber(itemId)
            if not itemId or not pendingRecipeIconIds[itemId] then return end
            pendingRecipeIconIds[itemId] = nil
            if selectedCharacter then
                layoutRecipeView(selectedCharacter)
            end
        end)
    end
end

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

local function groupPrefsRealm(group)
    for _, m in ipairs((group and group.members) or {}) do
        if m.realm and m.realm ~= "" then
            return m.realm
        end
    end
    if group and group.prefsRealm and group.prefsRealm ~= "" then
        return group.prefsRealm
    end
    local GSS = AltArmy.GuildShareSettings
    return (GSS and GSS._CurrentRealm and GSS._CurrentRealm())
        or (GetRealmName and GetRealmName())
        or ""
end

local function applyGroupUiPrefs(groups)
    local GSS = AltArmy.GuildShareSettings
    if not GSS then return end
    for _, g in ipairs(groups or {}) do
        local realm = groupPrefsRealm(g)
        g.prefsRealm = realm
        g.overrideName = (GSS.GetGroupOverrideName and GSS.GetGroupOverrideName(g.main, realm)) or nil
        g.pinned = (GSS.IsGroupPinned and GSS.IsGroupPinned(g.main, realm)) and true or false
    end
end

-- *** Layout: panel + message state ***

local panel = Theme.CreateTabContentPanel(frame)
panel:SetPoint("TOPLEFT", frame, "TOPLEFT", SECTION_INSET, -SECTION_INSET)
panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SECTION_INSET, SECTION_INSET)
local inner = Theme.CreatePanelInnerContent(panel)

-- Group settings side panel (60% list / 40% settings when open).
local groupSettingsPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
Theme.ApplyBackdrop(groupSettingsPanel, "section")
ApplyGroupSettingsPanelLayout = function()
    local w = frame:GetWidth()
    if w <= 0 then return end
    groupSettingsPanel:ClearAllPoints()
    local settingsLeft = w * UI.GRID_SPLIT_FRACTION + SECTION_GAP
    groupSettingsPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", settingsLeft, -SECTION_INSET)
    groupSettingsPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", settingsLeft, SECTION_INSET)
    groupSettingsPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SECTION_INSET, -SECTION_INSET)
    groupSettingsPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SECTION_INSET, SECTION_INSET)
end
ApplyGroupSettingsPanelLayout()
groupSettingsPanel:Hide()

local groupSettingsContent = Theme.CreateSettingsPanelContent(groupSettingsPanel)
local groupSettingsTitle = groupSettingsContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
groupSettingsTitle:SetPoint("TOPLEFT", groupSettingsContent, "TOPLEFT", 0, 0)
groupSettingsTitle:SetPoint("TOPRIGHT", groupSettingsContent, "TOPRIGHT", 0, 0)
groupSettingsTitle:SetJustifyH("LEFT")
groupSettingsTitle:SetText("Settings")
Theme.SetTitleColor(groupSettingsTitle)

local function formatGroupSettingsTitle(group)
    local displayName = GTD.ResolveGroupDisplayName(group)
    local coloredName = formatName(displayName, group and group.classFile)
    local suffix = " settings"
    local t = Theme.COLORS and Theme.COLORS.title
    if t and CC and CC.formatHex then
        suffix = CC.formatHex(t[1], t[2], t[3], suffix)
    end
    return coloredName .. suffix
end

local function setGroupSettingsTitle(group)
    if not group then
        groupSettingsTitle:SetText("Settings")
        Theme.SetTitleColor(groupSettingsTitle)
        return
    end
    groupSettingsTitle:SetText(formatGroupSettingsTitle(group))
    -- White base so embedded class/title color codes render as authored.
    groupSettingsTitle:SetTextColor(1, 1, 1, 1)
end

local groupSettingsBody = CreateFrame("Frame", nil, groupSettingsContent)
groupSettingsBody:SetPoint("TOPLEFT", groupSettingsTitle, "BOTTOMLEFT", 0, -8)
groupSettingsBody:SetPoint("BOTTOMRIGHT", groupSettingsContent, "BOTTOMRIGHT", 0, 0)

local groupPinRow = Theme.CreateLabeledCheckbox(groupSettingsBody, {
    point = "TOPLEFT",
    x = 0,
    y = 0,
    text = "Pin",
    fullWidthHover = true,
    onClick = function(checked)
        if not selectedSettingsGroup then return end
        local GSS = AltArmy.GuildShareSettings
        local realm = groupPrefsRealm(selectedSettingsGroup)
        if GSS and GSS.SetGroupPinned then
            GSS.SetGroupPinned(selectedSettingsGroup.main, realm, checked)
        end
        selectedSettingsGroup.pinned = checked and true or false
        if refresh then refresh() end
    end,
})

local overrideLabel = Theme.CreateOptionsSectionLabel(groupSettingsBody, {
    point = "TOPLEFT",
    relativeTo = groupPinRow,
    relativePoint = "BOTTOMLEFT",
    x = 0,
    y = -14,
    text = "Override name in my UI",
})

local overrideResetBtn = CreateFrame("Button", nil, groupSettingsBody, "UIPanelButtonTemplate")
overrideResetBtn:SetSize(56, 22)
overrideResetBtn:SetPoint("TOP", overrideLabel, "BOTTOM", 0, -4)
overrideResetBtn:SetPoint("RIGHT", groupSettingsBody, "RIGHT", 0, 0)
overrideResetBtn:SetText("Reset")
Theme.SkinButton(overrideResetBtn)

local overrideEdit = CreateFrame("EditBox", nil, groupSettingsBody)
overrideEdit:SetPoint("TOPLEFT", overrideLabel, "BOTTOMLEFT", 0, -4)
overrideEdit:SetPoint("RIGHT", overrideResetBtn, "LEFT", -6, 0)
overrideEdit:SetHeight(22)
overrideEdit:SetFontObject("GameFontHighlight")
overrideEdit:SetAutoFocus(false)
overrideEdit:SetTextInsets(6, 6, 0, 0)
local overrideMaxLen = AltArmy.GuildShareSettings and AltArmy.GuildShareSettings.DISPLAY_NAME_MAX_LENGTH
if overrideEdit.SetMaxLetters and overrideMaxLen then
    overrideEdit:SetMaxLetters(overrideMaxLen)
end
Theme.ApplyInputTextures(overrideEdit)
overrideEdit:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
overrideEdit:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
local function applyOverrideFromEdit(box)
    if not selectedSettingsGroup then return end
    local GSS = AltArmy.GuildShareSettings
    local realm = groupPrefsRealm(selectedSettingsGroup)
    local text = box:GetText() or ""
    if GSS and GSS.SetGroupOverrideName then
        GSS.SetGroupOverrideName(selectedSettingsGroup.main, realm, text)
    end
    local newOverride = (GSS and GSS.GetGroupOverrideName
        and GSS.GetGroupOverrideName(selectedSettingsGroup.main, realm)) or nil
    if newOverride == selectedSettingsGroup.overrideName then
        return
    end
    selectedSettingsGroup.overrideName = newOverride
    setGroupSettingsTitle(selectedSettingsGroup)
    if refresh then refresh() end
end
overrideEdit:SetScript("OnTextChanged", function(box)
    applyOverrideFromEdit(box)
end)
overrideEdit:SetScript("OnEditFocusLost", function(box)
    applyOverrideFromEdit(box)
end)
overrideResetBtn:SetScript("OnClick", function()
    if Theme.ClearEditBoxText then
        Theme.ClearEditBoxText(overrideEdit)
    else
        overrideEdit:SetText("")
        if overrideEdit.ClearFocus then
            overrideEdit:ClearFocus()
        end
    end
    applyOverrideFromEdit(overrideEdit)
end)

local groupDeleteBtn = CreateFrame("Button", nil, groupSettingsBody, "UIPanelButtonTemplate")
groupDeleteBtn:SetHeight(22)
groupDeleteBtn:SetPoint("BOTTOMLEFT", groupSettingsBody, "BOTTOMLEFT", 0, 0)
groupDeleteBtn:SetPoint("BOTTOMRIGHT", groupSettingsBody, "BOTTOMRIGHT", 0, 0)
groupDeleteBtn:SetText("Delete")
Theme.SkinDangerButton(groupDeleteBtn)
groupDeleteBtn:SetScript("OnClick", function(self)
    if not selectedSettingsGroup then return end
    if deleteConfirmPending then
        deleteConfirmPending = false
        local main = selectedSettingsGroup.main
        local realm = groupPrefsRealm(selectedSettingsGroup)
        local GSD = AltArmy.GuildShareData
        local GSS = AltArmy.GuildShareSettings
        if GSD and GSD.RemoveGroup then
            GSD.RemoveGroup(main, realm)
        end
        if GSS and GSS.ClearGroupUiPrefs then
            GSS.ClearGroupUiPrefs(main, realm)
        end
        closeGroupSettings()
        local Comm = AltArmy.GuildShareComm
        if Comm and Comm.NotifyDataChanged then
            Comm.NotifyDataChanged()
        elseif refresh then
            refresh()
        end
    else
        deleteConfirmPending = true
        self:SetText("Really delete?")
    end
end)

isGroupSettingsShown = function()
    return groupSettingsPanel:IsShown()
end

local function applyMainPanelLayout()
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", frame, "TOPLEFT", SECTION_INSET, -SECTION_INSET)
    if isGroupSettingsShown() then
        panel:SetPoint("BOTTOMRIGHT", groupSettingsPanel, "BOTTOMLEFT", -SECTION_GAP, 0)
    else
        panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SECTION_INSET, SECTION_INSET)
    end
end

closeGroupSettings = function()
    selectedSettingsGroup = nil
    deleteConfirmPending = false
    groupDeleteBtn:SetText("Delete")
    groupSettingsPanel:Hide()
    applyMainPanelLayout()
    if updateGuildHeaderForListMode then
        updateGuildHeaderForListMode()
    end
    if applyListColumnLayout then
        applyListColumnLayout()
    end
    if syncMainRowSettingsIcons then
        syncMainRowSettingsIcons()
    end
end

updateGroupSettingsPanel = function()
    if not selectedSettingsGroup then return end
    setGroupSettingsTitle(selectedSettingsGroup)
    if groupPinRow.check then
        groupPinRow.check:SetChecked(selectedSettingsGroup.pinned and true or false)
    end
    local override = selectedSettingsGroup.overrideName or ""
    if overrideEdit:GetText() ~= override then
        if Theme.SetEditBoxText then
            Theme.SetEditBoxText(overrideEdit, override)
        else
            overrideEdit:SetText(override)
        end
    end
    local GSS = AltArmy.GuildShareSettings
    local ownMain = GSS and GSS.GetMain and GSS.GetMain(groupPrefsRealm(selectedSettingsGroup)) or nil
    local isOwn = GTD.IsOwnGroup and GTD.IsOwnGroup(selectedSettingsGroup, ownMain)
    if isOwn then
        groupDeleteBtn:Hide()
        deleteConfirmPending = false
        groupDeleteBtn:SetText("Delete")
    else
        groupDeleteBtn:Show()
        if not deleteConfirmPending then
            groupDeleteBtn:SetText("Delete")
        end
    end
end

openGroupSettings = function(group)
    if not group then return end
    if selectedSettingsGroup and selectedSettingsGroup.main == group.main and isGroupSettingsShown() then
        closeGroupSettings()
        return
    end
    selectedSettingsGroup = group
    deleteConfirmPending = false
    groupDeleteBtn:SetText("Delete")
    ApplyGroupSettingsPanelLayout()
    groupSettingsPanel:Show()
    applyMainPanelLayout()
    updateGroupSettingsPanel()
    if updateGuildHeaderForListMode then
        updateGuildHeaderForListMode()
    end
    if applyListColumnLayout then
        applyListColumnLayout()
    end
    if syncMainRowSettingsIcons then
        syncMainRowSettingsIcons()
    end
end

frame:HookScript("OnSizeChanged", function()
    if isGroupSettingsShown() then
        ApplyGroupSettingsPanelLayout()
        applyMainPanelLayout()
    end
end)

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
header:SetHeight(UI.HEADER_HEIGHT)
header:SetFrameLevel(listView:GetFrameLevel() + 5)

local guildNameText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
guildNameText:SetPoint("LEFT", header, "LEFT", 2, 0)
guildNameText:SetJustifyH("LEFT")
Theme.SetTitleColor(guildNameText)

-- Guild tabard: three stacked textures composed by SetLargeGuildTabardTextures.
local tabardFrame = CreateFrame("Frame", nil, header)
tabardFrame:SetSize(UI.TABARD_SIZE, UI.TABARD_SIZE)
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

-- Search fields: same left edge as main header search; extend to the close button.
local headerSearchRef = _G.AltArmyTBC_HeaderSearchEdit
local headerCloseRef = _G.AltArmyTBC_HeaderCloseButton

local function anchorGuildHeaderSearch(edit)
    edit:SetHeight(20)
    edit:SetPoint("TOP", header, "TOP", 0, -6)
    if headerSearchRef and headerCloseRef then
        edit:SetPoint("LEFT", headerSearchRef, "LEFT", 0, 0)
        edit:SetPoint("RIGHT", headerCloseRef, "LEFT", 2, 0)
    elseif headerSearchRef then
        edit:SetPoint("LEFT", headerSearchRef, "LEFT", 0, 0)
        edit:SetPoint("RIGHT", headerSearchRef, "RIGHT", 0, 0)
    else
        edit:SetSize(288, 20)
        edit:SetPoint("RIGHT", header, "RIGHT", -20, 0)
    end
end

local searchEdit = CreateFrame("EditBox", "AltArmyTBC_GuildSearchEdit", header)
anchorGuildHeaderSearch(searchEdit)
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
    Theme.ClearEditBoxText(searchEdit)
end)

Theme.SetupEditBoxPlaceholder(searchEdit, UI.SEARCH_PLACEHOLDER)

local function updateSearchClearVisibility()
    local text = searchEdit:GetText()
    local trimmed = text and text:match("^%s*(.-)%s*$") or ""
    if trimmed == "" then
        searchClearBtn:Hide()
    else
        searchClearBtn:Show()
    end
end

-- Recipe detail search (top right while viewing one character's recipes).
local recipeSearchEdit = CreateFrame("EditBox", "AltArmyTBC_GuildRecipeSearchEdit", header)
anchorGuildHeaderSearch(recipeSearchEdit)
recipeSearchEdit:SetAutoFocus(false)
recipeSearchEdit:SetFontObject("GameFontHighlight")
if recipeSearchEdit.SetTextInsets then
    recipeSearchEdit:SetTextInsets(6, 6, 0, 0)
end
Theme.ApplyInputTextures(recipeSearchEdit)
recipeSearchEdit:Hide()

local recipeSearchClearBtn = CreateFrame("Button", nil, header)
recipeSearchClearBtn:SetPoint("RIGHT", recipeSearchEdit, "LEFT", -2, 0)
recipeSearchClearBtn:SetSize(18, 18)
recipeSearchClearBtn:Hide()
local recipeSearchClearLabel = recipeSearchClearBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
recipeSearchClearLabel:SetPoint("CENTER", recipeSearchClearBtn, "CENTER", 0, 0)
recipeSearchClearLabel:SetText("X")
recipeSearchClearBtn:SetHighlightFontObject("GameFontNormal")
recipeSearchClearBtn:SetScript("OnClick", function()
    Theme.ClearEditBoxText(recipeSearchEdit)
end)

Theme.SetupEditBoxPlaceholder(recipeSearchEdit, "Search for recipes on this character")

local function updateRecipeSearchPlaceholder(entry)
    Theme.SetEditBoxPlaceholderText(recipeSearchEdit, GTD.FormatRecipeSearchPlaceholder(entry and entry.name))
end

local function updateRecipeSearchClearVisibility()
    local text = recipeSearchEdit:GetText()
    local trimmed = text and text:match("^%s*(.-)%s*$") or ""
    if trimmed == "" then
        recipeSearchClearBtn:Hide()
    else
        recipeSearchClearBtn:Show()
    end
    if selectedCharacter and updateWhisperButton then
        updateWhisperButton(selectedCharacter)
    end
end

local function clearRecipeSearch()
    recipeSearchText = ""
    Theme.ClearEditBoxText(recipeSearchEdit)
    updateRecipeSearchClearVisibility()
end

local suppressRecipeSearchLayout = false

local function clearRecipeSearchQuiet()
    suppressRecipeSearchLayout = true
    clearRecipeSearch()
    suppressRecipeSearchLayout = false
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

local TruncateFontString = AltArmy.Text and AltArmy.Text.TruncateFontString

local recipeTitleFS = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
recipeTitleFS:SetPoint("LEFT", backBtn, "RIGHT", 8, 0)
recipeTitleFS:SetPoint("RIGHT", recipeSearchClearBtn, "LEFT", -8, 0)
recipeTitleFS:SetJustifyH("LEFT")
recipeTitleFS:SetWordWrap(false)
recipeTitleFS:Hide()

local whisperBtn = CreateFrame("Button", nil, header)
whisperBtn:SetHeight(22)
whisperBtn:Hide()
Theme.SkinButton(whisperBtn)
local whisperBtnLabel = whisperBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
whisperBtnLabel:SetPoint("CENTER", whisperBtn, "CENTER", 0, 0)
whisperBtnLabel:SetText("Whisper")
whisperBtn:SetWidth(math.max(64, (whisperBtnLabel:GetStringWidth() or 40) + 16))
whisperBtn:SetScript("OnClick", function(self)
    local target = self.whisperTarget
    if not target or target == "" then return end
    if _G.ChatFrame_SendTell then
        _G.ChatFrame_SendTell(target)
    elseif _G.ChatFrame_OpenChat then
        _G.ChatFrame_OpenChat("/w " .. target .. " ")
    end
end)

--- Right edge reserved for the recipe search clear button (when shown) or the search box.
local function recipeSearchLeftGuard()
    if recipeSearchClearBtn:IsShown() then
        return recipeSearchClearBtn, "LEFT"
    end
    return recipeSearchEdit, "LEFT"
end

local function anchorWhisperFlushRight()
    local guard, point = recipeSearchLeftGuard()
    whisperBtn:ClearAllPoints()
    whisperBtn:SetPoint("RIGHT", guard, point, -8, 0)
end

local function anchorRecipeTitleTo(rightFrame)
    recipeTitleFS:ClearAllPoints()
    recipeTitleFS:SetPoint("LEFT", backBtn, "RIGHT", 8, 0)
    recipeTitleFS:SetPoint("RIGHT", rightFrame, "LEFT", -8, 0)
end

local function recipeTitleMaxWidth()
    local left = backBtn:GetRight() or 0
    local rightFrame = whisperBtn:IsShown() and whisperBtn or select(1, recipeSearchLeftGuard())
    local right = rightFrame and rightFrame:GetLeft() or 0
    return math.max(0, right - left - 16)
end

local function applyRecipeTitleText(entry)
    if not entry then
        recipeTitleFS:SetText("")
        return
    end
    local nameColored = GTD.FormatCharacterTitle(entry, formatName)
    local level = math.floor(tonumber(entry.level) or 0)
    local fullSuffix = GTD.FormatCharacterLevelSuffix(level, "full", UI.GRAY)
    local shortSuffix = GTD.FormatCharacterLevelSuffix(level, "short", UI.GRAY)
    local maxW = recipeTitleMaxWidth()

    recipeTitleFS:SetText(nameColored .. fullSuffix)
    local fitsFull = maxW <= 0 or (recipeTitleFS:GetStringWidth() or 0) <= maxW
    recipeTitleFS:SetText(nameColored .. shortSuffix)
    local fitsShort = maxW <= 0 or (recipeTitleFS:GetStringWidth() or 0) <= maxW
    local mode = GTD.ChooseCharacterTitleLevelMode(fitsFull, fitsShort)

    if mode == "full" then
        recipeTitleFS:SetText(nameColored .. fullSuffix)
    elseif mode == "short" then
        recipeTitleFS:SetText(nameColored .. shortSuffix)
    elseif TruncateFontString then
        TruncateFontString(recipeTitleFS, nameColored, maxW, {
            preserveColorCodes = true,
            suffix = shortSuffix,
        })
    else
        recipeTitleFS:SetText(nameColored .. shortSuffix)
    end
end

updateWhisperButton = function(entry)
    whisperBtn.whisperTarget = nil
    if not entry then
        whisperBtn:Hide()
        anchorRecipeTitleTo(select(1, recipeSearchLeftGuard()))
        applyRecipeTitleText(nil)
        return
    end
    local rosterByName = (GTD.BuildRosterLastOnlineMap and GTD.BuildRosterLastOnlineMap()) or {}
    local members
    local GSD = AltArmy.GuildShareData
    if entry.guildName and GSD and GSD.GetGuildMembersForDisplay then
        members = GSD.GetGuildMembersForDisplay(entry.guildName, entry.realm, true)
    end
    local target = GTD.ResolveOnlineWhisperTarget and GTD.ResolveOnlineWhisperTarget(entry, rosterByName, members)
    if target then
        whisperBtn.whisperTarget = target
        whisperBtn:Show()
        anchorWhisperFlushRight()
        anchorRecipeTitleTo(whisperBtn)
    else
        whisperBtn:Hide()
        anchorRecipeTitleTo(select(1, recipeSearchLeftGuard()))
    end
    applyRecipeTitleText(entry)
end

header:SetScript("OnSizeChanged", function()
    if selectedCharacter and recipeTitleFS:IsShown() then
        updateWhisperButton(selectedCharacter)
    end
end)

local profTabStrip = CreateFrame("Frame", nil, header)
profTabStrip:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
profTabStrip:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -2)
profTabStrip:SetHeight(UI.PROF_TAB_HEIGHT)
profTabStrip:Hide()

local function isCraftLibAvailable()
    local RCL = AltArmy and AltArmy.RecipeCraftLib
    return RCL and RCL.IsAvailable and RCL.IsAvailable() or false
end

local craftLibRecommendBtn = CreateFrame("Button", nil, profTabStrip)
craftLibRecommendBtn:SetHeight(UI.PROF_TAB_HEIGHT - 4)
craftLibRecommendBtn:SetPoint("TOPRIGHT", profTabStrip, "TOPRIGHT", 0, 0)
Theme.SkinButton(craftLibRecommendBtn, true)
Theme.BindInteractableHover(craftLibRecommendBtn)
local craftLibRecommendLabel = craftLibRecommendBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
craftLibRecommendLabel:SetPoint("CENTER", craftLibRecommendBtn, "CENTER", 0, 0)
craftLibRecommendLabel:SetText("Recommended: CraftLib")
craftLibRecommendBtn:Hide()

local craftLibRecommendPanel = Theme.CreateCraftLibInstallCallout(listView, {
    introText = "Install the CraftLib addon to see:",
    bulletLines = {
        "Recipe skill requirements",
        "Color coded difficulty",
        "All recipe icons",
    },
})
craftLibRecommendPanel:SetWidth(300)
craftLibRecommendPanel:SetPoint("TOPRIGHT", craftLibRecommendBtn, "BOTTOMRIGHT", 0, -4)
craftLibRecommendPanel:SetFrameLevel((listView:GetFrameLevel() or 0) + 50)
craftLibRecommendPanel:Hide()

craftLibRecommendBtn:SetScript("OnClick", function()
    craftLibRecommendPanel:SetShown(not craftLibRecommendPanel:IsShown())
end)

local function layoutCraftLibRecommendButton()
    if not craftLibRecommendBtn:IsShown() then
        return
    end
    local textWidth = craftLibRecommendLabel:GetStringWidth() or 120
    craftLibRecommendBtn:SetWidth(math.max(150, textWidth + 16))
end

local function updateCraftLibRecommendUi()
    local available = isCraftLibAvailable()
    craftLibRecommendBtn:SetShown(not available)
    if available then
        craftLibRecommendPanel:Hide()
    else
        layoutCraftLibRecommendButton()
    end
end

local function layoutRecipeRowColumns(row, showSkillCol)
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
    if showSkillCol then
        row.label:SetPoint("RIGHT", row, "RIGHT", -(UI.RECIPE_SKILL_COL_WIDTH + 4), 0)
        row.skillCell:Show()
    else
        row.label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.skillCell:Hide()
    end
end

updateGuildHeaderForListMode = function()
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
        if isGroupSettingsShown and isGroupSettingsShown() then
            searchEdit:Hide()
            searchClearBtn:Hide()
            if searchEdit.ClearFocus then searchEdit:ClearFocus() end
        else
            searchEdit:Show()
            updateSearchClearVisibility()
        end
        tabardFrame:Hide()
        return
    end
    guildBackBtn:Hide()
    guildNameText:ClearAllPoints()
    guildNameText:SetPoint("LEFT", header, "LEFT", 2, 0)
    guildNameText:SetText(activeGuild() or "")
    Theme.SetTitleColor(guildNameText)
    guildNameText:Show()
    if isGroupSettingsShown and isGroupSettingsShown() then
        searchEdit:Hide()
        searchClearBtn:Hide()
        if searchEdit.ClearFocus then searchEdit:ClearFocus() end
    else
        searchEdit:Show()
        updateSearchClearVisibility()
    end
    updateTabard()
end

local function setListHeaderVisible(visible)
    if visible then
        updateGuildHeaderForListMode()
        recipeSearchEdit:Hide()
        recipeSearchClearBtn:Hide()
        whisperBtn:Hide()
        anchorRecipeTitleTo(recipeSearchClearBtn)
    else
        guildNameText:Hide()
        guildBackBtn:Hide()
        searchEdit:Hide()
        searchClearBtn:Hide()
        tabardFrame:Hide()
        recipeSearchEdit:Show()
        updateRecipeSearchClearVisibility()
        Theme.UpdateEditBoxPlaceholderVisibility(recipeSearchEdit)
    end
    backBtn:SetShown(not visible)
    recipeTitleFS:SetShown(not visible)
    if visible then
        whisperBtn:Hide()
    end
    profTabStrip:SetShown(not visible)
end

-- Scroll body below the guild header and fixed column headers.
local listColHeader = CreateFrame("Frame", nil, listView)
listColHeader:SetHeight(UI.LIST_COL_HEADER_HEIGHT)
listColHeader:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -PAD)
listColHeader:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -SCROLL_GUTTER, -PAD)
listColHeader:Hide()

local LIST_HEADER_LABEL = {
    name = "Name",
    characterCount = "Character Count",
    online = "Online",
}
local listHeaderButtons = {}

local function updateListHeaderSortIndicators()
    for key, btn in pairs(listHeaderButtons) do
        if btn.label then
            local base = LIST_HEADER_LABEL[key] or key
            btn.label:SetText(Theme.FormatSortHeaderLabel(base, key == listSortKey, listSortAscending))
        end
    end
end

--- Apply default column sort when switching between in-guild and browse-without-guild modes.
local function ensureDefaultListSort(canLookupOnline)
    if listSortCanLookupOnline == canLookupOnline then
        return
    end
    listSortCanLookupOnline = canLookupOnline
    if GTD.GetDefaultListSort then
        listSortKey, listSortAscending = GTD.GetDefaultListSort(canLookupOnline)
    elseif canLookupOnline then
        listSortKey, listSortAscending = "online", true
    else
        listSortKey, listSortAscending = "name", true
    end
    updateListHeaderSortIndicators()
end

local function createListHeaderButton(sortKey, justifyH, anchorFn)
    local btn = CreateFrame("Button", nil, listColHeader)
    btn:SetHeight(UI.LIST_COL_HEADER_HEIGHT)
    btn:EnableMouse(true)
    btn:RegisterForClicks("LeftButtonUp")
    anchorFn(btn)
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", btn, "LEFT", 0, 0)
    label:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
    label:SetHeight(UI.LIST_COL_HEADER_HEIGHT)
    label:SetJustifyH(justifyH or "LEFT")
    label:SetWordWrap(false)
    btn.label = label
    Theme.BindInteractableHover(btn)
    local sortKeyForClick = sortKey
    btn:SetScript("OnClick", function()
        if listSortKey == sortKeyForClick then
            listSortAscending = not listSortAscending
        else
            listSortKey = sortKeyForClick
            -- Character count: first click highest→lowest; other columns: A→Z / least→most.
            listSortAscending = sortKeyForClick ~= "characterCount"
        end
        updateListHeaderSortIndicators()
        refresh()
    end)
    listHeaderButtons[sortKey] = btn
    return btn
end

createListHeaderButton("online", "RIGHT", function(btn)
    btn:SetPoint("RIGHT", listColHeader, "RIGHT", -UI.RIGHT_TRAILING_RESERVE, 0)
    btn:SetWidth(UI.LAST_ONLINE_COLUMN_WIDTH)
end)
createListHeaderButton("name", "LEFT", function(btn)
    btn:SetPoint("LEFT", listColHeader, "LEFT", 4, 0)
    btn:SetPoint("RIGHT", listColHeader, "LEFT", UI.SECOND_COLUMN - UI.NAME_COLUMN_GAP, 0)
end)
createListHeaderButton("characterCount", "LEFT", function(btn)
    btn:SetPoint("LEFT", listColHeader, "LEFT", UI.SECOND_COLUMN, 0)
    btn:SetPoint("RIGHT", listHeaderButtons.online, "LEFT", -UI.NAME_COLUMN_GAP, 0)
end)
updateListHeaderSortIndicators()

local listViewport = CreateFrame("Frame", nil, listView)
-- No horizontal scroll bar on this list; pin to the inner content bottom (panel padding
-- already provides the bronze-border gutter — do not reserve an extra PAD strip).
local function anchorListViewportBelowColHeader()
    listViewport:ClearAllPoints()
    listViewport:SetPoint("TOPLEFT", listColHeader, "BOTTOMLEFT", 0, -2)
    listViewport:SetPoint("BOTTOMRIGHT", listView, "BOTTOMRIGHT", -SCROLL_GUTTER, 0)
end
local function anchorListViewportBelowGuildHeader()
    listViewport:ClearAllPoints()
    listViewport:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -PAD)
    listViewport:SetPoint("BOTTOMRIGHT", listView, "BOTTOMRIGHT", -SCROLL_GUTTER, 0)
end
anchorListViewportBelowColHeader()

local viewport = Theme.CreateVerticalScrollViewport({
    parent = listViewport,
    gutterEdge = listViewport,
    anchorTop = { "TOPLEFT", listViewport, "TOPLEFT", 0, 0 },
    anchorBottom = { "BOTTOMRIGHT", listViewport, "BOTTOMRIGHT", 0, 0 },
    enableMouseWheel = true,
    valueStep = UI.MAIN_ROW_HEIGHT,
})
local scrollChild = viewport.child

-- Gradient under the Name / Character Count / Online header when the list is scrolled.
listColHeader:SetFrameLevel((listView:GetFrameLevel() or 0) + 10)
local listHeaderFade = Theme.CreatePinnedHeaderScrollFade({
    headerFrame = listColHeader,
    scrollFrame = viewport.scroll,
    scrollBar = viewport.scrollBar,
    headerBottomInset = 0,
})
if viewport.scrollBar then
    viewport.scrollBar:HookScript("OnValueChanged", function()
        if listHeaderFade then
            listHeaderFade:Update()
        end
    end)
end

local function updateListHeaderFade()
    if not listHeaderFade then
        return
    end
    if listColHeader:IsShown() then
        listHeaderFade:Update()
    elseif listHeaderFade.frame then
        listHeaderFade.frame:Hide()
    end
end

local WHEEL_STEP = UI.MAIN_ROW_HEIGHT * 3
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
recipeBody:SetPoint("BOTTOMRIGHT", listView, "BOTTOMRIGHT", -SCROLL_GUTTER, 0)
recipeBody:Hide()

local recipeViewportFrame = CreateFrame("Frame", nil, recipeBody)
recipeViewportFrame:Hide()

local recipeColHeader = CreateFrame("Frame", nil, recipeBody)
recipeColHeader:SetHeight(UI.RECIPE_COL_HEADER_HEIGHT)
recipeColHeader:SetPoint("TOPLEFT", recipeBody, "TOPLEFT", 0, 0)
recipeColHeader:SetPoint("TOPRIGHT", recipeBody, "TOPRIGHT", 0, 0)
recipeColHeader:Hide()

local RECIPE_HEADER_LABEL = { recipe = "Recipe", skill = "Skill" }
local recipeHeaderButtons = {}

local function updateRecipeHeaderSortIndicators()
    for key, btn in pairs(recipeHeaderButtons) do
        if btn.label then
            local base = RECIPE_HEADER_LABEL[key] or key
            btn.label:SetText(Theme.FormatSortHeaderLabel(base, key == recipeSortKey, recipeSortAscending))
        end
    end
end

local function createRecipeHeaderButton(sortKey, anchorFn)
    local btn = CreateFrame("Button", nil, recipeColHeader)
    btn:SetHeight(UI.RECIPE_COL_HEADER_HEIGHT)
    btn:EnableMouse(true)
    btn:RegisterForClicks("LeftButtonUp")
    anchorFn(btn)
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", btn, "LEFT", 0, 0)
    label:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
    label:SetHeight(UI.RECIPE_COL_HEADER_HEIGHT)
    label:SetJustifyH(sortKey == "skill" and "RIGHT" or "LEFT")
    btn.label = label
    Theme.BindInteractableHover(btn)
    local sortKeyForClick = sortKey
    btn:SetScript("OnClick", function()
        if recipeSortKey == sortKeyForClick then
            recipeSortAscending = not recipeSortAscending
        else
            recipeSortKey = sortKeyForClick
            recipeSortAscending = sortKeyForClick ~= "skill"
        end
        updateRecipeHeaderSortIndicators()
        if selectedCharacter then
            clearRecipeFocus()
            layoutRecipeView(selectedCharacter)
        end
    end)
    recipeHeaderButtons[sortKey] = btn
    return btn
end

createRecipeHeaderButton("recipe", function(btn)
    btn:SetPoint("TOPLEFT", recipeColHeader, "TOPLEFT", 4, 0)
    btn:SetPoint("TOPRIGHT", recipeColHeader, "TOPRIGHT", -(UI.RECIPE_SKILL_COL_WIDTH + 4), 0)
end)
createRecipeHeaderButton("skill", function(btn)
    btn:SetPoint("TOPRIGHT", recipeColHeader, "TOPRIGHT", -4, 0)
    btn:SetWidth(UI.RECIPE_SKILL_COL_WIDTH)
end)
updateRecipeHeaderSortIndicators()

local function applyRecipeSkillColumnLayout(showSkillCol)
    local skillHeader = recipeHeaderButtons.skill
    local recipeHeader = recipeHeaderButtons.recipe
    if skillHeader then
        skillHeader:SetShown(showSkillCol)
    end
    if recipeHeader then
        recipeHeader:ClearAllPoints()
        recipeHeader:SetPoint("TOPLEFT", recipeColHeader, "TOPLEFT", 4, 0)
        if showSkillCol then
            recipeHeader:SetPoint("TOPRIGHT", recipeColHeader, "TOPRIGHT", -(UI.RECIPE_SKILL_COL_WIDTH + 4), 0)
        else
            recipeHeader:SetPoint("TOPRIGHT", recipeColHeader, "TOPRIGHT", -4, 0)
        end
    end
end

recipeViewportFrame:SetPoint("TOPLEFT", recipeColHeader, "BOTTOMLEFT", 0, 0)
recipeViewportFrame:SetPoint("BOTTOMRIGHT", recipeBody, "BOTTOMRIGHT", 0, 0)

local recipeViewport = Theme.CreateVerticalScrollViewport({
    parent = recipeViewportFrame,
    gutterEdge = recipeBody,
    anchorTop = { "TOPLEFT", recipeViewportFrame, "TOPLEFT", 0, 0 },
    anchorBottom = { "BOTTOMRIGHT", recipeViewportFrame, "BOTTOMRIGHT", 0, 0 },
    enableMouseWheel = true,
    valueStep = UI.RECIPE_ROW_HEIGHT,
})
local recipeScrollChild = recipeViewport.child

-- Gradient under the recipe column header when the list is scrolled (Gear / Search pattern).
recipeColHeader:SetFrameLevel((recipeBody:GetFrameLevel() or 0) + 10)
local recipeHeaderFade = Theme.CreatePinnedHeaderScrollFade({
    headerFrame = recipeColHeader,
    scrollFrame = recipeViewport.scroll,
    scrollBar = recipeViewport.scrollBar,
    -- Pull fade up so it meets the header edge (avoids a 1–2px seam).
    headerBottomInset = 2,
})
if recipeViewport.scrollBar then
    recipeViewport.scrollBar:HookScript("OnValueChanged", function()
        if recipeHeaderFade then
            recipeHeaderFade:Update()
        end
    end)
end

local RECIPE_WHEEL_STEP = UI.RECIPE_ROW_HEIGHT * 3
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
-- Repositioning frames during layout fires OnLeave; ignore those and resync after layout.
local suppressMainRowHoverEvents = false

local function isMainRowSettingsActive(row)
    return selectedSettingsGroup
        and isGroupSettingsShown
        and isGroupSettingsShown()
        and row
        and row.settingsGroup
        and selectedSettingsGroup.main == row.settingsGroup.main
end

local function mainRowIsUnderMouse(row)
    if not row or not row:IsShown() then
        return false
    end
    if MouseIsOver then
        return MouseIsOver(row) and true or false
    end
    local focus = GetMouseFocus and GetMouseFocus()
    return focus == row or (row.settingsBtn and focus == row.settingsBtn) or false
end

local function syncMainRowHoverFromMouse()
    local hoveredRow = nil
    for i = 1, #mainRowPool do
        local row = mainRowPool[i]
        if mainRowIsUnderMouse(row) then
            hoveredRow = row
            break
        end
    end
    for i = 1, #mainRowPool do
        local row = mainRowPool[i]
        if row and row == hoveredRow then
            local focus = GetMouseFocus and GetMouseFocus()
            row.settingsBtnHovered = (row.settingsBtn and focus == row.settingsBtn) and true or false
            if row.setMainRowHover then
                row.setMainRowHover(true)
            end
        elseif row and row.clearMainRowHoverState then
            row.clearMainRowHoverState()
        end
    end
end

syncMainRowSettingsIcons = function()
    for i = 1, #mainRowPool do
        local row = mainRowPool[i]
        if row and row.updateSettingsBtnVisibility then
            row.updateSettingsBtnVisibility()
        elseif row and row.settingsBtn then
            local active = isMainRowSettingsActive(row)
            Theme.SetSettingsButtonGlow(row.settingsBtn, active, "glow")
            Theme.SetSettingsButtonGlow(row.settingsBtn, false, "hoverGlow")
            if active or row.rowHovered or row.settingsBtnHovered then
                row.settingsBtn:Show()
            else
                row.settingsBtn:Hide()
            end
        end
    end
end

applyListColumnLayout = function()
    local showOnline = not (isGroupSettingsShown and isGroupSettingsShown())
    local onlineBtn = listHeaderButtons.online
    local countBtn = listHeaderButtons.characterCount
    if onlineBtn then
        onlineBtn:SetShown(showOnline)
    end
    if countBtn then
        countBtn:ClearAllPoints()
        countBtn:SetPoint("LEFT", listColHeader, "LEFT", UI.SECOND_COLUMN, 0)
        if showOnline and onlineBtn then
            countBtn:SetPoint("RIGHT", onlineBtn, "LEFT", -UI.NAME_COLUMN_GAP, 0)
        else
            countBtn:SetPoint("RIGHT", listColHeader, "RIGHT", -UI.RIGHT_TRAILING_RESERVE, 0)
        end
    end
    for i = 1, #mainRowPool do
        local row = mainRowPool[i]
        if row and row.countFS then
            if row.lastOnlineFS then
                row.lastOnlineFS:SetShown(showOnline)
            end
            row.countFS:ClearAllPoints()
            row.countFS:SetPoint("LEFT", row, "LEFT", UI.SECOND_COLUMN, 0)
            if showOnline and row.lastOnlineFS then
                row.countFS:SetPoint("RIGHT", row.lastOnlineFS, "LEFT", -UI.NAME_COLUMN_GAP, 0)
            elseif row.settingsBtn then
                row.countFS:SetPoint("RIGHT", row.settingsBtn, "LEFT", -UI.NAME_COLUMN_GAP, 0)
            else
                row.countFS:SetPoint("RIGHT", row, "RIGHT", -UI.RIGHT_TRAILING_RESERVE, 0)
            end
        end
    end
    for i = 1, #charRowPool do
        local row = charRowPool[i]
        if row and row.profFS then
            if row.lastOnlineFS then
                row.lastOnlineFS:SetShown(showOnline)
            end
            row.profFS:ClearAllPoints()
            row.profFS:SetPoint("LEFT", row, "LEFT", UI.SECOND_COLUMN, 0)
            if showOnline and row.lastOnlineFS then
                row.profFS:SetPoint("RIGHT", row.lastOnlineFS, "LEFT", -UI.NAME_COLUMN_GAP, 0)
            else
                row.profFS:SetPoint("RIGHT", row, "RIGHT", -UI.RIGHT_TRAILING_RESERVE, 0)
            end
        end
    end
end

-- Left chain: [!] [pin] name. Warning/pin only consume space when visible.
local function layoutMainRowLeftIcons(row, showOld, pinned)
    local leftAnchor = row
    local leftPoint = "LEFT"
    local leftX = UI.LEFT_ICON_PAD

    if row.oldDataIcon then
        row.oldDataIcon.showOldDataTooltip = showOld and true or false
        if showOld then
            row.oldDataIcon:ClearAllPoints()
            row.oldDataIcon:SetPoint("LEFT", row, "LEFT", UI.LEFT_ICON_PAD, 0)
            row.oldDataIcon:EnableMouse(true)
            row.oldDataIcon:Show()
            if row.oldDataIcon.mark then
                row.oldDataIcon.mark:Show()
            end
            leftAnchor = row.oldDataIcon
            leftPoint = "RIGHT"
            leftX = UI.PIN_ICON_GAP
        else
            row.oldDataIcon:EnableMouse(false)
            row.oldDataIcon:Hide()
            if row.oldDataIcon.mark then
                row.oldDataIcon.mark:Hide()
            end
        end
    end

    if row.pinIcon then
        if pinned then
            row.pinIcon:ClearAllPoints()
            row.pinIcon:SetPoint("LEFT", leftAnchor, leftPoint, leftX, 0)
            row.pinIcon:Show()
            leftAnchor = row.pinIcon
            leftPoint = "RIGHT"
            leftX = UI.PIN_ICON_GAP
        else
            row.pinIcon:Hide()
        end
    end

    if row.nameFS then
        row.nameFS:ClearAllPoints()
        row.nameFS:SetPoint("LEFT", leftAnchor, leftPoint, leftX, 0)
        row.nameFS:SetPoint("RIGHT", row, "LEFT", UI.SECOND_COLUMN - UI.NAME_COLUMN_GAP, 0)
    end
end

-- Left chain for character rows: [star?] name. Star only when the main was explicitly set.
local function layoutCharRowLeftIcons(row, showMainStar)
    local leftAnchor = row
    local leftPoint = "LEFT"
    local leftX = UI.CHAR_INDENT

    if row.mainStarIcon then
        row.mainStarIcon.showMainStarTooltip = showMainStar and true or false
        if showMainStar then
            row.mainStarIcon:ClearAllPoints()
            row.mainStarIcon:SetPoint("LEFT", row, "LEFT", UI.CHAR_INDENT, 0)
            row.mainStarIcon:EnableMouse(true)
            row.mainStarIcon:Show()
            leftAnchor = row.mainStarIcon
            leftPoint = "RIGHT"
            leftX = UI.MAIN_STAR_ICON_GAP
        else
            row.mainStarIcon:EnableMouse(false)
            row.mainStarIcon:Hide()
        end
    end

    if row.nameFS then
        row.nameFS:ClearAllPoints()
        row.nameFS:SetPoint("LEFT", leftAnchor, leftPoint, leftX, 0)
        row.nameFS:SetPoint("RIGHT", row, "LEFT", UI.SECOND_COLUMN - UI.NAME_COLUMN_GAP, 0)
    end
end

local function acquireMainRow(index)
    local row = mainRowPool[index]
    if not row then
        row = CreateFrame("Button", nil, scrollChild)
        row:SetHeight(UI.MAIN_ROW_HEIGHT)
        Theme.InstallHoverTint(row)
        -- Keep hover tint off the settings icon so it does not brighten on row hover.
        if row.altArmyHoverTint then
            local tint = row.altArmyHoverTint
            tint:ClearAllPoints()
            tint:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            tint:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            tint:SetPoint("RIGHT", row, "RIGHT", -UI.RIGHT_TRAILING_RESERVE, 0)
        end
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", forwardWheel)

        local function updateSettingsBtnVisibility()
            if not row.settingsBtn then return end
            local active = isMainRowSettingsActive(row)
            Theme.SetSettingsButtonGlow(row.settingsBtn, active, "glow")
            if not active then
                Theme.SetSettingsButtonGlow(row.settingsBtn, row.settingsBtnHovered and true or false, "hoverGlow")
            else
                Theme.SetSettingsButtonGlow(row.settingsBtn, false, "hoverGlow")
            end
            if active or row.rowHovered or row.settingsBtnHovered then
                row.settingsBtn:Show()
            else
                row.settingsBtn:Hide()
            end
        end
        row.updateSettingsBtnVisibility = updateSettingsBtnVisibility

        local function clearMainRowHoverState()
            row.rowHovered = false
            row.settingsBtnHovered = false
            Theme.SetHoverTint(row, false)
            updateSettingsBtnVisibility()
        end

        local function setMainRowHover(on)
            Theme.SetHoverTint(row, on)
            row.rowHovered = on and true or false
            if not on then
                row.settingsBtnHovered = false
            end
            updateSettingsBtnVisibility()
        end
        row.setMainRowHover = setMainRowHover
        row.clearMainRowHoverState = clearMainRowHoverState

        row:SetScript("OnEnter", function()
            -- Moving between rows can skip OnLeave on the previous row; clear others.
            for i = 1, #mainRowPool do
                local other = mainRowPool[i]
                if other and other ~= row and other.clearMainRowHoverState then
                    other.clearMainRowHoverState()
                end
            end
            setMainRowHover(true)
        end)
        row:SetScript("OnLeave", function()
            if suppressMainRowHoverEvents then
                return
            end
            -- Entering the settings child fires row OnLeave first; ignore that transition.
            if GetMouseFocus and GetMouseFocus() == row.settingsBtn then
                return
            end
            setMainRowHover(false)
        end)

        -- Far-left stale warning; only participates in layout when shown (see layoutMainRowLeftIcons).
        local oldDataIcon = CreateFrame("Frame", nil, row)
        oldDataIcon:SetSize(UI.OLD_DATA_ICON_WIDTH, UI.MAIN_ROW_HEIGHT)
        oldDataIcon:EnableMouse(false)
        oldDataIcon:Hide()
        local mark = oldDataIcon:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        mark:SetText("!")
        mark:SetPoint("CENTER", oldDataIcon, "CENTER", 0, 0)
        mark:SetTextColor(1, 0.82, 0, 1)
        oldDataIcon.mark = mark
        oldDataIcon:SetScript("OnEnter", function(self)
            setMainRowHover(true)
            if not self.showOldDataTooltip or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Shared data is outdated", 1, 1, 1)
            GameTooltip:AddLine(GTD.GetOldDataTooltipText(), 1, 0.82, 0, true)
            GameTooltip:Show()
        end)
        oldDataIcon:SetScript("OnLeave", function()
            if suppressMainRowHoverEvents then
                return
            end
            if GetMouseFocus and GetMouseFocus() == row.settingsBtn then
                return
            end
            setMainRowHover(false)
            if GameTooltip then GameTooltip:Hide() end
        end)
        row.oldDataIcon = oldDataIcon

        local settingsBtn = CreateFrame("Button", nil, row)
        settingsBtn:SetSize(UI.SETTINGS_ICON_WIDTH, UI.SETTINGS_ICON_WIDTH)
        settingsBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        settingsBtn:RegisterForClicks("LeftButtonUp")
        local settingsIcon = settingsBtn:CreateTexture(nil, "ARTWORK")
        settingsIcon:SetAllPoints(settingsBtn)
        settingsIcon:SetTexture("Interface\\Icons\\Trade_Engineering")
        settingsBtn.icon = settingsIcon
        Theme.SkinSettingsIconButton(settingsBtn)
        Theme.InstallSettingsButtonGlow(settingsBtn, "glow")
        settingsBtn:Hide()
        settingsBtn:SetScript("OnEnter", function()
            row.settingsBtnHovered = true
            Theme.SetHoverTint(row, true)
            updateSettingsBtnVisibility()
        end)
        settingsBtn:SetScript("OnLeave", function()
            if suppressMainRowHoverEvents then
                return
            end
            row.settingsBtnHovered = false
            local focus = GetMouseFocus and GetMouseFocus()
            if focus == row then
                row.rowHovered = true
                Theme.SetHoverTint(row, true)
            else
                row.rowHovered = false
                Theme.SetHoverTint(row, false)
            end
            updateSettingsBtnVisibility()
        end)
        settingsBtn:SetScript("OnClick", function()
            if row.settingsGroup then
                openGroupSettings(row.settingsGroup)
            end
        end)
        row.settingsBtn = settingsBtn

        local pinIcon = row:CreateTexture(nil, "ARTWORK")
        pinIcon:SetSize(UI.PIN_ICON_SIZE, UI.PIN_ICON_SIZE)
        pinIcon:SetTexture("Interface\\AddOns\\AltArmy_TBC\\Media\\PushPin")
        pinIcon:Hide()
        row.pinIcon = pinIcon

        local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameFS:SetPoint("LEFT", row, "LEFT", UI.LEFT_ICON_PAD, 0)
        nameFS:SetPoint("RIGHT", row, "LEFT", UI.SECOND_COLUMN - UI.NAME_COLUMN_GAP, 0)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetWordWrap(false)
        row.nameFS = nameFS
        local lastOnlineFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lastOnlineFS:SetPoint("RIGHT", settingsBtn, "LEFT", -2, 0)
        lastOnlineFS:SetWidth(UI.LAST_ONLINE_COLUMN_WIDTH)
        lastOnlineFS:SetJustifyH("RIGHT")
        lastOnlineFS:SetWordWrap(false)
        row.lastOnlineFS = lastOnlineFS
        local countFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        countFS:SetPoint("LEFT", row, "LEFT", UI.SECOND_COLUMN, 0)
        countFS:SetPoint("RIGHT", lastOnlineFS, "LEFT", -UI.NAME_COLUMN_GAP, 0)
        countFS:SetJustifyH("LEFT")
        countFS:SetWordWrap(false)
        row.countFS = countFS
        mainRowPool[index] = row
    end
    row:Show()
    return row
end

local function acquireCharRow(index)
    local row = charRowPool[index]
    if not row then
        row = CreateFrame("Button", nil, scrollChild)
        row:SetHeight(UI.CHAR_ROW_HEIGHT)
        Theme.InstallHoverTint(row)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", forwardWheel)
        row:SetScript("OnEnter", function() Theme.SetHoverTint(row, true) end)
        row:SetScript("OnLeave", function() Theme.SetHoverTint(row, false) end)

        local mainStarIcon = CreateFrame("Frame", nil, row)
        mainStarIcon:SetSize(UI.MAIN_STAR_ICON_SIZE, UI.CHAR_ROW_HEIGHT)
        mainStarIcon:EnableMouse(false)
        mainStarIcon:Hide()
        local starTex = mainStarIcon:CreateTexture(nil, "ARTWORK")
        starTex:SetSize(UI.MAIN_STAR_ICON_SIZE, UI.MAIN_STAR_ICON_SIZE)
        starTex:SetPoint("CENTER", mainStarIcon, "CENTER", 0, 0)
        starTex:SetTexture(UI.MAIN_STAR_TEXTURE)
        mainStarIcon.tex = starTex
        mainStarIcon:SetScript("OnEnter", function(self)
            Theme.SetHoverTint(row, true)
            if not self.showMainStarTooltip then return end
            local m = row.memberEntry
            local isOwn = not m or m.source == "local" or not m.source
            if GTD.PresentMainStarTooltip then
                GTD.PresentMainStarTooltip(self, "ANCHOR_BOTTOMLEFT", {
                    name = m and m.name,
                    classFile = m and m.classFile,
                    isOwn = isOwn,
                    showConfigureHint = isOwn,
                })
            end
        end)
        mainStarIcon:SetScript("OnLeave", function()
            Theme.SetHoverTint(row, false)
            if GameTooltip then GameTooltip:Hide() end
        end)
        mainStarIcon:SetScript("OnMouseUp", function(_, button)
            if button ~= "LeftButton" then return end
            local m = row.memberEntry
            local isOwn = not m or m.source == "local" or not m.source
            if isOwn and AltArmy.OpenInterfaceOptions then
                AltArmy.OpenInterfaceOptions("general", { flash = "main" })
            end
        end)
        row.mainStarIcon = mainStarIcon

        local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameFS:SetPoint("LEFT", row, "LEFT", UI.CHAR_INDENT, 0)
        nameFS:SetPoint("RIGHT", row, "LEFT", UI.SECOND_COLUMN - UI.NAME_COLUMN_GAP, 0)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetWordWrap(false)
        row.nameFS = nameFS
        local lastOnlineFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lastOnlineFS:SetPoint("RIGHT", row, "RIGHT", -UI.RIGHT_TRAILING_RESERVE, 0)
        lastOnlineFS:SetWidth(UI.LAST_ONLINE_COLUMN_WIDTH)
        lastOnlineFS:SetJustifyH("RIGHT")
        lastOnlineFS:SetWordWrap(false)
        row.lastOnlineFS = lastOnlineFS
        local profFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        profFS:SetPoint("LEFT", row, "LEFT", UI.SECOND_COLUMN, 0)
        profFS:SetPoint("RIGHT", lastOnlineFS, "LEFT", -UI.NAME_COLUMN_GAP, 0)
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
        local row = mainRowPool[i]
        if row then
            if row.clearMainRowHoverState then
                row.clearMainRowHoverState()
            end
            row:Hide()
        end
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
        row:SetHeight(UI.MAIN_ROW_HEIGHT)
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
    listColHeader:Hide()
    anchorListViewportBelowGuildHeader()
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
        y = y + UI.MAIN_ROW_HEIGHT
    end
    hideGuildPickerRowsFrom(#guilds + 1)
    scrollChild:SetWidth(width)
    scrollChild:SetHeight(math.max(1, y))
    if viewport.UpdateRange then viewport.UpdateRange() end
    updateListHeaderFade()
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

local FOCUS_BORDER_COLOR = (Theme.COLORS and Theme.COLORS.green) or { 0.20, 0.85, 0.35, 1 }
local RECIPE_FOCUS_SCROLL_DURATION = 0.28
local recipeFocusAnim = CreateFrame("Frame")
-- Preferred profession for search drill-in (re-applied when profs arrive after load).
local focusProfessionKey = nil
local focusProfessionName = nil
-- Skip the automatic OnShow refresh while opening from search (avoids list flash + races).
local suppressGuildOnShowRefresh = false

local function stopRecipeFocusScroll()
    recipeFocusAnim:SetScript("OnUpdate", nil)
end

local function clearRecipeFocusBorders()
    for i = 1, #recipeRowPool do
        local row = recipeRowPool[i]
        if row and row.focusBorder then
            row.focusBorder:Hide()
        end
    end
end

clearRecipeFocus = function()
    stopRecipeFocusScroll()
    clearRecipeFocusBorders()
    focusRecipeID = nil
    focusScrollPending = false
    focusProfessionKey = nil
    focusProfessionName = nil
end

local function ensureRecipeFocusBorder(row)
    if not row or row.focusBorder then return end
    local border = CreateFrame("Frame", nil, row)
    border:SetAllPoints(row)
    border:SetFrameLevel(row:GetFrameLevel() + 5)
    local r = FOCUS_BORDER_COLOR[1] or 0.2
    local g = FOCUS_BORDER_COLOR[2] or 0.85
    local b = FOCUS_BORDER_COLOR[3] or 0.35
    local a = FOCUS_BORDER_COLOR[4] or 1
    local top = border:CreateTexture(nil, "OVERLAY")
    top:SetColorTexture(r, g, b, a)
    top:SetHeight(1)
    top:SetPoint("TOPLEFT", border, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", border, "TOPRIGHT", 0, 0)
    local bottom = border:CreateTexture(nil, "OVERLAY")
    bottom:SetColorTexture(r, g, b, a)
    bottom:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT", border, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", 0, 0)
    local left = border:CreateTexture(nil, "OVERLAY")
    left:SetColorTexture(r, g, b, a)
    left:SetWidth(1)
    left:SetPoint("TOPLEFT", border, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", border, "BOTTOMLEFT", 0, 0)
    local right = border:CreateTexture(nil, "OVERLAY")
    right:SetColorTexture(r, g, b, a)
    right:SetWidth(1)
    right:SetPoint("TOPRIGHT", border, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", 0, 0)
    border:Hide()
    row.focusBorder = border
end

local function smoothScrollRecipeListTo(targetOffset)
    stopRecipeFocusScroll()
    local start = recipeViewport.scroll:GetVerticalScroll() or 0
    if math.abs(start - targetOffset) < 0.5 then
        recipeViewport.SetOffset(targetOffset)
        return
    end
    local elapsed = 0
    recipeFocusAnim:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (dt or 0)
        local t = elapsed / RECIPE_FOCUS_SCROLL_DURATION
        if t >= 1 then
            recipeViewport.SetOffset(targetOffset)
            stopRecipeFocusScroll()
            return
        end
        -- Cubic ease-in-out
        local eased
        if t < 0.5 then
            eased = 4 * t * t * t
        else
            local u = -2 * t + 2
            eased = 1 - (u * u * u) / 2
        end
        recipeViewport.SetOffset(start + (targetOffset - start) * eased)
    end)
end

--- Apply green border + deferred scroll until the viewport has a real height.
--- Retries across frames (and across later layouts) while focusScrollPending is set.
--- preserveScroll: when true and there is no focused recipe, leave the current offset alone
--- (guild presence refreshes rebuild the row tables without changing recipe IDs).
applyRecipeFocus = function(recipes, preserveScroll)
    if not focusRecipeID then
        clearRecipeFocusBorders()
        if not preserveScroll then
            recipeViewport.SetOffset(0)
        end
        return
    end

    local Nav = AltArmy.SearchGuildNav
    local idx = Nav and Nav.FindRecipeRowIndex and Nav.FindRecipeRowIndex(recipes, focusRecipeID)

    local function findRow()
        if idx and recipeRowPool[idx] and recipeRowPool[idx].recipeID then
            local row = recipeRowPool[idx]
            local id = row.recipeID
            if id == focusRecipeID or tonumber(id) == tonumber(focusRecipeID) then
                return row, idx
            end
        end
        for i = 1, #recipeRowPool do
            local row = recipeRowPool[i]
            if row and row:IsShown() and row.recipeID then
                local id = row.recipeID
                if id == focusRecipeID or tonumber(id) == tonumber(focusRecipeID) then
                    return row, i
                end
            end
        end
        return nil, nil
    end

    local row, rowIndex = findRow()
    if not row then
        -- Recipes may still be loading; keep focusScrollPending for a later layout.
        return
    end

    clearRecipeFocusBorders()
    ensureRecipeFocusBorder(row)
    row.focusBorder:Show()

    if not focusScrollPending then
        return
    end

    local attempts = 0
    stopRecipeFocusScroll()
    recipeFocusAnim:SetScript("OnUpdate", function(f)
        attempts = attempts + 1
        local liveRow, liveIndex = findRow()
        if liveRow then
            clearRecipeFocusBorders()
            ensureRecipeFocusBorder(liveRow)
            liveRow.focusBorder:Show()
            rowIndex = liveIndex
        end
        local viewH = recipeViewport.scroll:GetHeight() or 0
        local contentH = recipeScrollChild:GetHeight() or 0
        if (not liveRow or viewH <= 0) and attempts < 60 then
            return
        end
        f:SetScript("OnUpdate", nil)
        focusScrollPending = false
        if not liveRow or viewH <= 0 or not rowIndex then
            return
        end
        recipeViewport.SetOffset(0)
        local rowTop = (rowIndex - 1) * UI.RECIPE_ROW_HEIGHT
        local target = Nav.ScrollOffsetToRevealRow
            and Nav.ScrollOffsetToRevealRow(rowTop, UI.RECIPE_ROW_HEIGHT, viewH, 0, contentH)
        if target then
            smoothScrollRecipeListTo(target)
        end
    end)
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
        row:SetHeight(UI.RECIPE_ROW_HEIGHT)
        row:EnableMouse(true)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", forwardRecipeWheel)
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", row, "LEFT", 4, 0)
        label:SetPoint("RIGHT", row, "RIGHT", -(UI.RECIPE_SKILL_COL_WIDTH + 4), 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        row.label = label
        local skillCell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        skillCell:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        skillCell:SetWidth(UI.RECIPE_SKILL_COL_WIDTH)
        skillCell:SetJustifyH("RIGHT")
        row.skillCell = skillCell
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

layoutRecipeView = function(entry)
    if not entry then return end
    clearPendingRecipeIcons()
    updateRecipeSearchPlaceholder(entry)
    local profs = GTD.GetPrimaryProfessions(entry)
    -- Re-resolve preferred profession while search focus is still pending (profs may load late).
    if focusScrollPending and (focusProfessionKey or focusProfessionName) then
        local Nav = AltArmy.SearchGuildNav
        if Nav and Nav.FindProfessionIndex then
            selectedProfIndex = Nav.FindProfessionIndex(profs, focusProfessionKey, focusProfessionName)
        end
    end
    if selectedProfIndex < 1 or selectedProfIndex > #profs then
        selectedProfIndex = 1
    end

    updateWhisperButton(entry)

    noProfText:Hide()
    loadingText:Hide()
    recipeViewportFrame:Hide()
    recipeColHeader:Hide()
    if recipeHeaderFade and recipeHeaderFade.frame then
        recipeHeaderFade.frame:Hide()
    end
    hideRecipeRowsFrom(1)
    hideProfTabsFrom(1)

    recipeBody:ClearAllPoints()
    recipeBody:SetPoint("BOTTOMRIGHT", listView, "BOTTOMRIGHT", -SCROLL_GUTTER, 0)

    if #profs == 0 then
        profTabStrip:Hide()
        craftLibRecommendBtn:Hide()
        craftLibRecommendPanel:Hide()
        header:SetHeight(UI.RECIPE_TITLE_HEIGHT)
        recipeBody:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -PAD)
        noProfText:SetText(GTD.FormatNoProfessionsMessage(entry, formatName))
        noProfText:Show()
        return
    end

    header:SetHeight(UI.RECIPE_TITLE_HEIGHT)
    profTabStrip:Show()
    updateCraftLibRecommendUi()
    recipeBody:SetPoint("TOPLEFT", profTabStrip, "BOTTOMLEFT", 0, -PAD)

    local tabX = 0
    local tabRightReserve = craftLibRecommendBtn:IsShown() and (craftLibRecommendBtn:GetWidth() + 8) or 0
    for i, prof in ipairs(profs) do
        local tab = profTabPool[i]
        if not tab then
            tab = CreateFrame("Button", nil, profTabStrip)
            tab:SetHeight(UI.PROF_TAB_HEIGHT - 4)
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
        if tabRightReserve > 0 then
            local stripWidth = profTabStrip:GetWidth() or 0
            if tabX + tab:GetWidth() > stripWidth - tabRightReserve then
                tab:SetWidth(math.max(64, stripWidth - tabRightReserve - tabX))
            end
        end
        tab:SetSelected(i == selectedProfIndex)
        tab:Show()
        tab:SetScript("OnClick", function()
            clearRecipeFocus()
            selectedProfIndex = i
            layoutRecipeView(selectedCharacter)
        end)
        tabX = tabX + tab:GetWidth() + UI.PROF_TAB_GAP
    end
    hideProfTabsFrom(#profs + 1)

    local selectedProf = profs[selectedProfIndex]
    local profKey = selectedProf and selectedProf.key
    local recipesPending = isLoadingRecipes(entry, profKey)
    local allRecipes = GTD.GetProfessionRecipes(entry, profKey)
    if recipesPending and #allRecipes == 0 then
        loadingText:Show()
        -- Keep retrying focus once recipes finish loading (RefreshGuildTab also re-layouts).
        if focusRecipeID and focusScrollPending then
            stopRecipeFocusScroll()
            local attempts = 0
            recipeFocusAnim:SetScript("OnUpdate", function(f)
                attempts = attempts + 1
                if not focusRecipeID or not focusScrollPending then
                    f:SetScript("OnUpdate", nil)
                    return
                end
                if attempts > 120 then
                    f:SetScript("OnUpdate", nil)
                    return
                end
                if selectedCharacter and (
                    not isLoadingRecipes(selectedCharacter, profKey)
                    or #(GTD.GetProfessionRecipes(selectedCharacter, profKey)) > 0
                ) then
                    f:SetScript("OnUpdate", nil)
                    layoutRecipeView(selectedCharacter)
                end
            end)
        end
        return
    end
    loadingText:Hide()

    if #allRecipes == 0 then
        recipeColHeader:Hide()
        recipeViewportFrame:Hide()
        hideRecipeRowsFrom(1)
        noProfText:SetText(GTD.FormatNoProfessionRecipesMessage(
            entry, formatName))
        noProfText:Show()
        return
    end

    local filteredRecipes = GTD.FilterRecipesBySearch(allRecipes, recipeSearchText, function(recipe)
        return select(1, resolveRecipeDisplay(recipe.recipeID, recipe.resultItemID))
    end)
    local showSkillCol = isCraftLibAvailable()
    if not showSkillCol and recipeSortKey == "skill" then
        recipeSortKey = "recipe"
        recipeSortAscending = true
    end
    local recipes = GTD.SortRecipes(filteredRecipes, recipeSortKey, recipeSortAscending, {
        professionName = selectedProf and selectedProf.name,
        skillRank = selectedProf and selectedProf.rank or 0,
        getRecipeName = function(recipe)
            return select(1, resolveRecipeDisplay(recipe.recipeID, recipe.resultItemID))
        end,
    })
    local preserveScroll = GTD.AreRecipeListsEqual(recipeViewport._lastRecipes, recipes)
    recipeViewport._lastRecipes = recipes
    applyRecipeSkillColumnLayout(showSkillCol)
    recipeColHeader:Show()
    updateRecipeHeaderSortIndicators()
    recipeViewportFrame:Show()
    local profName = selectedProf and selectedProf.name
    local skillRank = selectedProf and selectedProf.rank or 0
    local y = 0
    local width = math.max(1, (recipeScrollChild:GetWidth() or recipeBody:GetWidth() or 1))
    for i, recipe in ipairs(recipes) do
        local row = acquireRecipeRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", recipeScrollChild, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", recipeScrollChild, "TOPRIGHT", 0, -y)
        row.recipeID = recipe.recipeID
        layoutRecipeRowColumns(row, showSkillCol)
        local enriched = GTD.EnrichRecipeEntry(recipe, profName, skillRank)
        local recipeName, iconPath, pendingItemID = resolveRecipeDisplay(enriched.recipeID, enriched.resultItemID)
        trackPendingRecipeIcon(pendingItemID)
        local highlightedName = GTD.FormatTextWithSearchHighlight(recipeName, nil, recipeSearchText)
        row.label:SetText(("|T%s:0|t %s"):format(iconPath, highlightedName))
        if showSkillCol then
            local RCL = AltArmy and AltArmy.RecipeCraftLib
            if RCL and RCL.FormatSkillCell then
                row.skillCell:SetText(RCL.FormatSkillCell(
                    enriched.recipeSkillRequired, enriched.skillRank, enriched.difficulty))
            else
                row.skillCell:SetText(GTD.FormatRecipeSkillCell(recipe, profName, skillRank))
            end
        end
        y = y + UI.RECIPE_ROW_HEIGHT
    end
    hideRecipeRowsFrom(#recipes + 1)
    recipeScrollChild:SetWidth(width)
    recipeScrollChild:SetHeight(math.max(1, y))
    if recipeViewport.UpdateRange then recipeViewport.UpdateRange() end
    if recipeHeaderFade then
        recipeHeaderFade:Update()
    end
    applyRecipeFocus(recipes, preserveScroll)
end

showGuildList = function()
    clearRecipeFocus()
    selectedCharacter = nil
    selectedCharacterKey = nil
    selectedProfIndex = 1
    recipeViewport._lastRecipes = nil
    clearPendingRecipeIcons()
    clearRecipeSearch()
    header:SetHeight(UI.HEADER_HEIGHT)
    setListHeaderVisible(true)
    listColHeader:Show()
    anchorListViewportBelowColHeader()
    listViewport:Show()
    recipeBody:Hide()
    profTabStrip:Hide()
    craftLibRecommendBtn:Hide()
    craftLibRecommendPanel:Hide()
    updateListHeaderFade()
end

showRecipeView = function(entry, preferredProfKey, preferredProfName, preferredRecipeID)
    closeGroupSettings()
    selectedCharacter = entry
    selectedCharacterKey = memberKey(entry)
    selectedProfIndex = 1
    recipeViewport._lastRecipes = nil
    local Nav = AltArmy.SearchGuildNav
    if (preferredProfKey or preferredProfName) and Nav and Nav.FindProfessionIndex then
        selectedProfIndex = Nav.FindProfessionIndex(
            GTD.GetPrimaryProfessions(entry), preferredProfKey, preferredProfName)
    end
    recipeSortKey, recipeSortAscending = GTD.GetDefaultRecipeSort(isCraftLibAvailable())
    -- Quiet clear so OnTextChanged does not layout/wipe focus mid-open.
    clearRecipeSearchQuiet()
    if preferredRecipeID then
        focusRecipeID = preferredRecipeID
        focusScrollPending = true
        focusProfessionKey = preferredProfKey
        focusProfessionName = preferredProfName
    else
        clearRecipeFocus()
    end
    setListHeaderVisible(false)
    listColHeader:Hide()
    listViewport:Hide()
    emptyText:Hide()
    updateListHeaderFade()
    recipeBody:Show()
    if entry.source and entry.source ~= "local" then
        local Comm = AltArmy.GuildShareComm
        if Comm and Comm.RequestRecipesForCharacter then
            Comm.RequestRecipesForCharacter(entry.name, entry.realm, entry.source)
        end
    end
    layoutRecipeView(entry)
end

--- Open character recipe detail from search; Back returns via SearchGuildNav / Core.
function frame:ShowCharacterFromSearch(entry, professionKey, professionName, recipeID)
    if not entry then return end
    messageView:Hide()
    listView:Show()
    -- Show first so viewport sizes exist; suppress OnShow refresh which would race list layout.
    suppressGuildOnShowRefresh = true
    self:Show()
    suppressGuildOnShowRefresh = false
    showRecipeView(entry, professionKey, professionName, recipeID)
end

--- Leave search drill-in without switching to the guild member list as the active destination.
function frame:ClearSearchDrillIn()
    showGuildList()
    self:Hide()
end

backBtn:SetScript("OnClick", function()
    local Nav = AltArmy.SearchGuildNav
    if Nav and Nav.ShouldBackReturnToSearch and Nav.ShouldBackReturnToSearch()
        and AltArmy.ReturnToSearchFromGuildCharacter then
        AltArmy.ReturnToSearchFromGuildCharacter()
        return
    end
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
    closeGroupSettings()
    selectedCharacter = nil
    selectedCharacterKey = nil
    selectedBrowseGuild = nil
    listView:Hide()
    messageView:Show()
    messageText:SetText(text)
    optionsBtn:SetShown(withButton and true or false)
end

local function ensureGuildRosterIncludesOffline()
    if SetGuildRosterShowOffline then
        pcall(SetGuildRosterShowOffline, true)
    end
    if GuildRoster then
        pcall(GuildRoster)
    end
end

local function layoutList(groups, query, rosterByName, forceHoverMain)
    suppressMainRowHoverEvents = true
    hideGuildPickerRowsFrom(1)
    local mainIndex = 0
    local charIndex = 0
    local y = 0
    local width = math.max(1, (scrollChild:GetWidth() or listViewport:GetWidth() or 1))
    local activeQuery = GTD.NormalizeSearchQuery(query)
    rosterByName = rosterByName or {}
    local lastOnlineOpts = nil
    if not currentGuild() then
        lastOnlineOpts = { showUnknownWhenMissing = true }
    end

    local GSS = AltArmy.GuildShareSettings
    for _, g in ipairs(groups) do
        mainIndex = mainIndex + 1
        local isExpanded = expandedMains[g.main] and true or false
        local row = acquireMainRow(mainIndex)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -y)
        local ownMain = GSS and GSS.GetMain and GSS.GetMain(groupPrefsRealm(g)) or nil
        local isOwn = GTD.IsOwnGroup and GTD.IsOwnGroup(g, ownMain)
        row.nameFS:SetText(GTD.FormatMainRowName(
            g, formatName, activeQuery ~= "" and activeQuery or nil, isOwn))
        local isOld = GTD.GroupHasOldData and GTD.GroupHasOldData(g)
        layoutMainRowLeftIcons(row, isOld and true or false, g.pinned and true or false)
        row.countFS:SetText(GTD.FormatMainRowCount(g))
        if row.lastOnlineFS then
            local status = GTD.GetGroupLastOnlineStatus and GTD.GetGroupLastOnlineStatus(g, rosterByName)
            row.lastOnlineFS:SetText(
                (GTD.FormatRosterLastOnline and GTD.FormatRosterLastOnline(status, lastOnlineOpts)) or "")
        end
        row.groupMain = g.main
        row.settingsGroup = g
        row:SetScript("OnClick", function()
            expandedMains[g.main] = not expandedMains[g.main]
            layoutList(groups, query, rosterByName, g.main)
        end)
        y = y + UI.MAIN_ROW_HEIGHT

        if isExpanded then
            for _, m in ipairs(g.members) do
                charIndex = charIndex + 1
                local charRow = acquireCharRow(charIndex)
                charRow:ClearAllPoints()
                charRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
                charRow:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -y)
                charRow.nameFS:SetText(GTD.FormatCharacterName(
                    m, formatName, activeQuery ~= "" and activeQuery or nil))
                layoutCharRowLeftIcons(charRow, GTD.IsExplicitMain(m))
                charRow.profFS:SetText(GTD.FormatProfessions(
                    m, activeQuery ~= "" and activeQuery or nil))
                if charRow.lastOnlineFS then
                    local key = GTD.NormalizeRosterName and GTD.NormalizeRosterName(m.name)
                    local status = key and rosterByName[key] or nil
                    charRow.lastOnlineFS:SetText(
                        (GTD.FormatRosterLastOnline and GTD.FormatRosterLastOnline(status, lastOnlineOpts)) or "")
                end
                charRow.memberEntry = m
                charRow:SetScript("OnClick", function()
                    showRecipeView(m)
                end)
                y = y + UI.CHAR_ROW_HEIGHT
            end
        end
        y = y + UI.GROUP_GAP
    end

    hideMainRowsFrom(mainIndex + 1)
    hideCharRowsFrom(charIndex + 1)
    if applyListColumnLayout then
        applyListColumnLayout()
    end
    suppressMainRowHoverEvents = false
    if forceHoverMain then
        local forced = nil
        for i = 1, #mainRowPool do
            local row = mainRowPool[i]
            if row and row:IsShown() and row.groupMain == forceHoverMain then
                forced = row
                break
            end
        end
        for i = 1, #mainRowPool do
            local row = mainRowPool[i]
            if row and row == forced and row.setMainRowHover then
                row.setMainRowHover(true)
            elseif row and row.clearMainRowHoverState then
                row.clearMainRowHoverState()
            end
        end
    else
        syncMainRowHoverFromMouse()
    end
    if syncMainRowSettingsIcons then
        syncMainRowSettingsIcons()
    end
    scrollChild:SetWidth(width)
    scrollChild:SetHeight(math.max(1, y))
    if viewport.UpdateRange then viewport.UpdateRange() end
    updateListHeaderFade()
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
        local autoBrowse = GTD.GetAutoBrowseGuild(collectCurrentRealmGuilds())
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
            Theme.UpdateEditBoxPlaceholderVisibility(searchEdit)
            layoutGuildPicker(collectCurrentRealmGuilds())
            return
        end
        showMessage("You are not in a guild.", false)
        return
    end

    messageView:Hide()
    listView:Show()

    local realm = currentRealm()
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
            listColHeader:Hide()
            listViewport:Hide()
            emptyText:Hide()
            updateListHeaderFade()
            recipeBody:Show()
            layoutRecipeView(selectedCharacter)
            return
        end
        selectedCharacterKey = nil
    end

    showGuildList()
    Theme.UpdateEditBoxPlaceholderVisibility(searchEdit)

    local groups = GTD.GroupMembersByMain(members)
    applyGroupUiPrefs(groups)
    local filtered = GTD.FilterGroups(groups, searchText)
    applySearchExpansion(filtered)

    local rosterByName = {}
    local canLookupOnline = currentGuild() and true or false
    ensureDefaultListSort(canLookupOnline)
    if canLookupOnline and GTD.BuildRosterLastOnlineMap then
        rosterByName = GTD.BuildRosterLastOnlineMap()
    end
    if GTD.SortGroups then
        filtered = GTD.SortGroups(filtered, listSortKey, listSortAscending, rosterByName)
    end

    if selectedSettingsGroup then
        local stillPresent
        for _, g in ipairs(filtered) do
            if g.main == selectedSettingsGroup.main then
                stillPresent = g
                break
            end
        end
        if stillPresent then
            selectedSettingsGroup = stillPresent
            updateGroupSettingsPanel()
        else
            closeGroupSettings()
        end
    end

    if #filtered == 0 then
        hideMainRowsFrom(1)
        hideCharRowsFrom(1)
        scrollChild:SetHeight(1)
        if viewport.UpdateRange then viewport.UpdateRange() end
        updateListHeaderFade()
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
    layoutList(filtered, searchText, rosterByName)
end
refresh = refreshImpl

searchEdit:SetScript("OnTextChanged", function(box)
    local text = box:GetText() or ""
    searchText = text
    Theme.UpdateEditBoxPlaceholderVisibility(searchEdit)
    updateSearchClearVisibility()
    refresh()
end)
searchEdit:SetScript("OnEditFocusGained", function(self)
    Theme.UpdateEditBoxPlaceholderVisibility(self)
end)
searchEdit:SetScript("OnEditFocusLost", function(self)
    Theme.UpdateEditBoxPlaceholderVisibility(self)
end)
searchEdit:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
searchEdit:SetScript("OnEscapePressed", function(box)
    Theme.ClearEditBoxText(box)
end)
updateSearchClearVisibility()

recipeSearchEdit:SetScript("OnTextChanged", function(box)
    recipeSearchText = box:GetText() or ""
    Theme.UpdateEditBoxPlaceholderVisibility(recipeSearchEdit)
    updateRecipeSearchClearVisibility()
    if suppressRecipeSearchLayout or not selectedCharacter then
        return
    end
    -- Programmatic clears / Show of this field during search→character open must not
    -- wipe recipe focus. Only user-typed filter text dismisses the highlight.
    local trimmed = recipeSearchText:match("^%s*(.-)%s*$") or ""
    if trimmed ~= "" then
        clearRecipeFocus()
    end
    layoutRecipeView(selectedCharacter)
end)
recipeSearchEdit:SetScript("OnEditFocusGained", function(self)
    Theme.UpdateEditBoxPlaceholderVisibility(self)
end)
recipeSearchEdit:SetScript("OnEditFocusLost", function(self)
    Theme.UpdateEditBoxPlaceholderVisibility(self)
end)
recipeSearchEdit:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
recipeSearchEdit:SetScript("OnEscapePressed", function(box)
    Theme.ClearEditBoxText(box)
end)
updateRecipeSearchClearVisibility()

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

-- Roster last-online updates asynchronously after GuildRoster(); refresh when data arrives.
local rosterEvents = CreateFrame("Frame")
rosterEvents:RegisterEvent("GUILD_ROSTER_UPDATE")
rosterEvents:SetScript("OnEvent", function()
    if frame:IsShown() then
        refresh()
    end
end)

AltArmy.RefreshGuildTab = refresh
frame:SetScript("OnShow", function()
    if suppressGuildOnShowRefresh then
        return
    end
    ensureGuildRosterIncludesOffline()
    refresh()
end)
frame:HookScript("OnHide", function()
    closeGroupSettings()
end)
