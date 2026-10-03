-- AltArmy TBC — Zygor Guides Viewer integration helpers.
-- Opens matching reputation guides from the Reputation tab when Zygor is installed.
-- luacheck: globals ZGV

if not AltArmy then return end

AltArmy.ZygorIntegration = AltArmy.ZygorIntegration or {}
local ZI = AltArmy.ZygorIntegration

local ICON_RELATIVE = "\\Skins\\addon-icon"

-- factionID -> sanitized Zygor guide title (after SanitizeGuideTitle).
-- Umbrella guides: Steamwheedle Cartel covers four goblin cities; Gelkis & Magram covers both clans.
local FACTION_GUIDES = {
    -- Classic
    [87] = "REPUTATIONS\\Classic\\Bloodsail Buccaneers",
    [910] = "REPUTATIONS\\Classic\\Brood of Nozdormu",
    [609] = "REPUTATIONS\\Classic\\Cenarion Circle",
    [92] = "REPUTATIONS\\Classic\\Gelkis & Magram Centaur Clans",
    [93] = "REPUTATIONS\\Classic\\Gelkis & Magram Centaur Clans",
    [749] = "REPUTATIONS\\Classic\\Hydraxian Waterlords",
    [349] = "REPUTATIONS\\Classic\\Ravenholdt",
    [21] = "REPUTATIONS\\Classic\\Steamwheedle Cartel",  -- Booty Bay
    [577] = "REPUTATIONS\\Classic\\Steamwheedle Cartel", -- Everlook
    [369] = "REPUTATIONS\\Classic\\Steamwheedle Cartel", -- Gadgetzan
    [470] = "REPUTATIONS\\Classic\\Steamwheedle Cartel", -- Ratchet
    [576] = "REPUTATIONS\\Classic\\Timbermaw Hold",
    [59] = "REPUTATIONS\\Classic\\Thorium Brotherhood",
    [589] = "REPUTATIONS\\Classic\\Wintersaber Trainers",
    [69] = "REPUTATIONS\\Classic\\Darnassus",
    [54] = "REPUTATIONS\\Classic\\Gnomeregan Exiles",
    [47] = "REPUTATIONS\\Classic\\Ironforge",
    [72] = "REPUTATIONS\\Classic\\Stormwind City",
    [529] = "REPUTATIONS\\Classic\\Argent Dawn",
    [530] = "REPUTATIONS\\Classic\\Darkspear Trolls",
    [76] = "REPUTATIONS\\Classic\\Orgrimmar",
    [81] = "REPUTATIONS\\Classic\\Thunder Bluff",
    [68] = "REPUTATIONS\\Classic\\Undercity",
    -- The Burning Crusade
    [932] = "REPUTATIONS\\The Burning Crusade\\The Aldor",
    [934] = "REPUTATIONS\\The Burning Crusade\\The Scryers",
    [935] = "REPUTATIONS\\The Burning Crusade\\The Sha'tar",
    [942] = "REPUTATIONS\\The Burning Crusade\\Cenarion Expedition",
    [946] = "REPUTATIONS\\The Burning Crusade\\Honor Hold",
    [947] = "REPUTATIONS\\The Burning Crusade\\Thrallmar",
    [978] = "REPUTATIONS\\The Burning Crusade\\The Kurenai",
    [941] = "REPUTATIONS\\The Burning Crusade\\The Mag'har",
    [933] = "REPUTATIONS\\The Burning Crusade\\The Consortium",
    [1011] = "REPUTATIONS\\The Burning Crusade\\Lower City",
    [989] = "REPUTATIONS\\The Burning Crusade\\Keepers of Time",
    [990] = "REPUTATIONS\\The Burning Crusade\\The Scale of the Sands",
    [967] = "REPUTATIONS\\The Burning Crusade\\The Violet Eye",
    [970] = "REPUTATIONS\\The Burning Crusade\\Sporeggar",
    [1015] = "REPUTATIONS\\The Burning Crusade\\Netherwing",
    [1038] = "REPUTATIONS\\The Burning Crusade\\Ogri'la",
    [1031] = "REPUTATIONS\\The Burning Crusade\\Sha'tari Skyguard",
}

function ZI.IsLoaded()
    return rawget(_G, "ZGV") ~= nil
end

local function showMissingGuidesEnabled()
    local D = AltArmy.Debug
    if D and D.IsShowZygorMissingGuides then
        return D.IsShowZygorMissingGuides()
    end
    return false
end

--- Prefer Options > Debug > "Show Zygor guides (trial placeholders)".
--- Kept for /run and unit tests: AltArmy.ZygorIntegration.SetDevShowMissingGuides(true)
function ZI.SetDevShowMissingGuides(enabled)
    local D = AltArmy.Debug
    if D and D.SetShowZygorMissingGuides then
        D.SetShowZygorMissingGuides(enabled)
    end
    if D and D.RefreshZygorDependentUi then
        D.RefreshZygorDependentUi()
    end
end

function ZI.GetGuideForFaction(factionID)
    if not factionID then return nil end
    local zgv = rawget(_G, "ZGV")
    if not zgv then return nil end

    local title = FACTION_GUIDES[factionID]
    if not title then return nil end

    if not zgv.GetGuideByTitle then return nil end
    local guide = zgv:GetGuideByTitle(title)
    if not guide then return nil end
    if guide.missing and not showMissingGuidesEnabled() then
        return nil
    end
    return guide.title or title
end

function ZI.OpenGuide(title)
    if not title then return false end
    local zgv = rawget(_G, "ZGV")
    if not zgv then return false end
    if zgv.SetVisible then
        zgv:SetVisible(nil, true)
    end
    -- Prefer Tabs:LoadGuideToTab so the guide opens in a new tab (or activates an
    -- existing tab for that guide) instead of replacing the current tab via SetGuide.
    local tabs = zgv.Tabs
    if tabs and tabs.LoadGuideToTab then
        tabs:LoadGuideToTab(title, 1)
        return true
    end
    if zgv.SetGuide then
        zgv:SetGuide(title)
        return true
    end
    return false
end

function ZI.GetIconTexturePath()
    local zgv = rawget(_G, "ZGV")
    if not zgv or not zgv.DIR then return nil end
    return zgv.DIR .. ICON_RELATIVE
end
