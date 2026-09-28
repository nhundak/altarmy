-- AltArmy TBC — Canonical saved-var key for a character's per-character settings (realm\name).
-- Character data itself is keyed by GUID (see DataStore.lua); settings stay name-keyed and are
-- moved by RekeyCharSettings when a character's name changes (paid rename, surname now reported).

AltArmy = AltArmy or {}

--- @param name string|nil
--- @param realm string|nil
--- @return string
function AltArmy.CharKey(name, realm)
    return (realm or "") .. "\\" .. (name or "")
end

--- Per-character settings maps keyed by CharKey: { global SavedVariables name, field }.
local CHAR_SETTINGS_TABLES = {
    { "AltArmyTBC_SummarySettings", "characters" },
    { "AltArmyTBC_GearSettings", "characters" },
    { "AltArmyTBC_ReputationSettings", "characters" },
    { "AltArmyTBC_GraphSettings", "selected" },
    { "AltArmyTBC_Options", "bankAlts" },
    { "AltArmyTBC_Options", "bankAltPromptDismissed" },
}

--- Move every per-character setting saved for `oldName` on `realm` to `newName`. A setting already
--- saved under the new name is kept.
function AltArmy.RekeyCharSettings(realm, oldName, newName)
    if type(oldName) ~= "string" or oldName == "" or type(newName) ~= "string" or newName == ""
        or oldName == newName
    then
        return
    end
    local oldKey = AltArmy.CharKey(oldName, realm)
    local newKey = AltArmy.CharKey(newName, realm)
    for _, spec in ipairs(CHAR_SETTINGS_TABLES) do
        local root = _G[spec[1]]
        local map = type(root) == "table" and root[spec[2]] or nil
        if type(map) == "table" and map[oldKey] ~= nil then
            if map[newKey] == nil then
                map[newKey] = map[oldKey]
            end
            map[oldKey] = nil
        end
    end
    local GSS = AltArmy.GuildShareSettings
    if GSS and GSS.RenameCharacter then
        GSS.RenameCharacter(realm, oldName, newName)
    end
end
