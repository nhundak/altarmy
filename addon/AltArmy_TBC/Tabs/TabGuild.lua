-- AltArmy TBC — Guild tab: guildmates shared via guild data sharing, grouped by main.
-- Always present when the guildShare feature flag is on (button visibility handled in Core.lua).
-- Layout:
--   * fixed header: guild name + tabard (left), "Search for guild members" field (right)
--   * scroll body: one row per main (preferred name + character count), expandable to reveal
--     each character (class-colored name, gray level, primary professions)
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
local MAIN_ROW_HEIGHT = 20
local CHAR_ROW_HEIGHT = 18
local GROUP_GAP = 4
local CHAR_INDENT = 24
-- Professions column starts this far right of the character name column's left edge, so
-- every character's professions share one left edge regardless of name/level width.
local PROF_COLUMN = 180
local NAME_COLUMN_GAP = 8
local TABARD_SIZE = 24
local SEARCH_WIDTH = 200
local SEARCH_PLACEHOLDER = "Search for guild members"

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
-- Current search text (trimmed lower handled by GuildTabData.FilterGroups).
local searchText = ""

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
    if not (IsInGuild and IsInGuild()) then
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

-- Search field (right side of header)
local searchEdit = CreateFrame("EditBox", "AltArmyTBC_GuildSearchEdit", header)
searchEdit:SetSize(SEARCH_WIDTH, 20)
searchEdit:SetPoint("RIGHT", header, "RIGHT", -2, 0)
searchEdit:SetAutoFocus(false)
searchEdit:SetFontObject("GameFontHighlight")
if searchEdit.SetTextInsets then
    searchEdit:SetTextInsets(6, 6, 0, 0)
end
Theme.ApplyInputTextures(searchEdit)

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
        row = CreateFrame("Frame", nil, scrollChild)
        row:SetHeight(CHAR_ROW_HEIGHT)
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

-- *** Refresh ***

local function showMessage(text, withButton)
    listView:Hide()
    messageView:Show()
    messageText:SetText(text)
    optionsBtn:SetShown(withButton and true or false)
end

local function layoutList(groups)
    local mainIndex = 0
    local charIndex = 0
    local y = 0
    local width = math.max(1, (scrollChild:GetWidth() or listViewport:GetWidth() or 1))

    for _, g in ipairs(groups) do
        mainIndex = mainIndex + 1
        local isExpanded = expandedMains[g.main] and true or false
        local row = acquireMainRow(mainIndex)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -y)
        row.label:SetText(GTD.FormatMainRowLabel(g, formatName))
        row.groupMain = g.main
        row:SetScript("OnClick", function()
            expandedMains[g.main] = not expandedMains[g.main]
            layoutList(groups)
        end)
        y = y + MAIN_ROW_HEIGHT

        if isExpanded then
            for _, m in ipairs(g.members) do
                charIndex = charIndex + 1
                local charRow = acquireCharRow(charIndex)
                charRow:ClearAllPoints()
                charRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", CHAR_INDENT, -y)
                charRow:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
                charRow.nameFS:SetText(GTD.FormatCharacterName(m, formatName))
                charRow.profFS:SetText(GTD.FormatProfessions(m))
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

local function refresh()
    if not frame:IsShown() then return end
    local GSS = AltArmy.GuildShareSettings
    local GSD = AltArmy.GuildShareData

    if not GSS or not GSS.IsSharingEnabled() then
        showMessage("Guild sharing is disabled.\n\nEnable it to see the professions and characters"
            .. " your guildmates are sharing, and to share your own.", true)
        return
    end

    local guild = currentGuild()
    if not guild then
        showMessage("You are not in a guild.", false)
        return
    end

    messageView:Hide()
    listView:Show()
    guildNameText:SetText(guild)
    updateTabard()
    updateSearchPlaceholderVisibility()

    local realm = (GSS._CurrentRealm and GSS._CurrentRealm())
        or (GetRealmName and GetRealmName()) or ""
    local members = (GSD and GSD.GetGuildMembersForDisplay(guild, realm)) or {}
    local groups = GTD.GroupMembersByMain(members)
    local filtered = GTD.FilterGroups(groups, searchText)

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
    layoutList(filtered)
end

searchEdit:SetScript("OnTextChanged", function(box)
    local text = box:GetText() or ""
    searchText = text
    updateSearchPlaceholderVisibility()
    refresh()
end)
searchEdit:SetScript("OnEditFocusGained", updateSearchPlaceholderVisibility)
searchEdit:SetScript("OnEditFocusLost", updateSearchPlaceholderVisibility)
searchEdit:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
searchEdit:SetScript("OnEscapePressed", function(box)
    box:SetText("")
    box:ClearFocus()
end)

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
