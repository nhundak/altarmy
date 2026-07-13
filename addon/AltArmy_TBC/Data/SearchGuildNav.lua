-- AltArmy TBC — Navigation state for opening a guild character from search results.
-- Pure helpers (no frames). Core / TabSearch / TabGuild drive the UI from this state.

local Nav = {}
AltArmy.SearchGuildNav = Nav

local active = false

function Nav.Begin()
    active = true
end

function Nav.End()
    active = false
end

function Nav.IsActive()
    return active and true or false
end

--- While a search→character drill-in is open, any header search change ends it.
--- @return "ignore"|"show_search"|"exit_search"
function Nav.OnHeaderSearchTextChanged(trimmed)
    if not active then
        return "ignore"
    end
    active = false
    if not trimmed or trimmed == "" then
        return "exit_search"
    end
    return "show_search"
end

function Nav.ShouldBackReturnToSearch()
    return active and true or false
end

function Nav.IsGuildRecipeCharacterClickable(entry)
    return entry and entry.isGuild and true or false
end

--- Index of the preferred profession in a GetPrimaryProfessions-style list (1-based).
--- Prefers professionKey match; falls back to case-insensitive name/key; defaults to 1.
function Nav.FindProfessionIndex(profs, professionKey, professionName)
    if type(profs) ~= "table" or #profs == 0 then
        return 1
    end
    if professionKey and professionKey ~= "" then
        for i, prof in ipairs(profs) do
            if prof.key == professionKey then
                return i
            end
        end
    end
    if professionName and professionName ~= "" then
        local want = professionName:lower()
        for i, prof in ipairs(profs) do
            local name = (prof.name or ""):lower()
            local key = (prof.key or ""):lower()
            if name == want or key == want then
                return i
            end
        end
    end
    return 1
end

--- 1-based index of recipeID in a recipe list, or nil.
function Nav.FindRecipeRowIndex(recipes, recipeID)
    if type(recipes) ~= "table" or not recipeID then
        return nil
    end
    local want = tonumber(recipeID) or recipeID
    for i, recipe in ipairs(recipes) do
        if recipe then
            local id = recipe.recipeID
            if id == recipeID or id == want or tonumber(id) == want then
                return i
            end
        end
    end
    return nil
end

--- Desired scroll offset to reveal a row, or nil if already fully visible.
--- Prefers centering the row; clamps to [0, contentHeight - viewHeight].
function Nav.ScrollOffsetToRevealRow(rowTopY, rowHeight, viewHeight, currentOffset, contentHeight)
    rowTopY = tonumber(rowTopY) or 0
    rowHeight = tonumber(rowHeight) or 0
    viewHeight = tonumber(viewHeight) or 0
    currentOffset = tonumber(currentOffset) or 0
    contentHeight = tonumber(contentHeight) or 0
    if viewHeight <= 0 or rowHeight <= 0 then
        return nil
    end
    local rowBottom = rowTopY + rowHeight
    local visibleTop = currentOffset
    local visibleBottom = currentOffset + viewHeight
    if rowTopY >= visibleTop and rowBottom <= visibleBottom then
        return nil
    end
    local target = rowTopY - (viewHeight - rowHeight) / 2
    local maxScroll = contentHeight - viewHeight
    if maxScroll < 0 then maxScroll = 0 end
    if target < 0 then target = 0 end
    if target > maxScroll then target = maxScroll end
    -- Integer-ish for stable tests (WoW scroll accepts floats)
    return math.floor(target + 0.5)
end

--- Resolve the guild-tab member entry for a search recipe row.
function Nav.ResolveGuildMember(characterName, realm)
    if not characterName or characterName == "" then
        return nil
    end
    local GSD = AltArmy.GuildShareData
    if not GSD or not GSD.GetCharacter then
        return nil
    end
    return GSD.GetCharacter(characterName, realm)
end

--- Tooltip lines for a clickable guildmate name in search results, or nil.
--- opts.rosterByName may inject a roster map (tests); defaults to live guild roster.
function Nav.GetGuildCharacterHoverTooltipLines(characterName, realm, opts)
    opts = opts or {}
    local entry = Nav.ResolveGuildMember(characterName, realm)
    if not entry then
        return nil
    end
    local GTD = AltArmy.GuildTabData
    local GSD = AltArmy.GuildShareData
    if not GTD or not GTD.BuildGuildCharacterHoverTooltipLines then
        return nil
    end

    local group
    local guild = entry.guildName
    if guild and GSD and GSD.GetGuildMembersForDisplay and GTD.GroupMembersByMain then
        local members = GSD.GetGuildMembersForDisplay(guild, realm, true)
        local groups = GTD.GroupMembersByMain(members)
        for _, g in ipairs(groups or {}) do
            for _, m in ipairs(g.members or {}) do
                if m.name == entry.name
                    and (not realm or not m.realm or m.realm == realm) then
                    group = g
                    break
                end
            end
            if group then break end
        end
    end
    if not group then
        group = {
            main = entry.main or entry.name,
            preferredName = entry.displayName or entry.main or entry.name,
            members = { entry },
        }
    end

    local preferred = (GTD.ResolveGroupDisplayName and GTD.ResolveGroupDisplayName(group))
        or group.preferredName
        or entry.displayName
        or entry.main
        or entry.name

    local rosterByName = opts.rosterByName
    if rosterByName == nil and GTD.BuildRosterLastOnlineMap then
        rosterByName = GTD.BuildRosterLastOnlineMap()
    end
    local presence = GTD.GetGroupMostRecentOnlineDetail
        and GTD.GetGroupMostRecentOnlineDetail(group, rosterByName or {})

    return GTD.BuildGuildCharacterHoverTooltipLines({
        name = entry.name,
        preferredName = preferred,
        classFile = entry.classFile,
        level = entry.level,
        presenceDetail = presence,
    })
end
