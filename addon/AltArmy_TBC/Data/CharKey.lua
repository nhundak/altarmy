-- AltArmy TBC — Canonical saved-var key for a character (realm\name).

AltArmy = AltArmy or {}

--- @param name string|nil
--- @param realm string|nil
--- @return string
function AltArmy.CharKey(name, realm)
    return (realm or "") .. "\\" .. (name or "")
end
