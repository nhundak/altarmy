-- AltArmy TBC — RAID class color helpers (RGB + WoW escape sequences).

AltArmy = AltArmy or {}
AltArmy.ClassColor = AltArmy.ClassColor or {}

local CC = AltArmy.ClassColor

local NEUTRAL = { r = 0.7, g = 0.7, b = 0.7 }

--- @param classFile string|nil
--- @return number r, number g, number b
function CC.getRGB(classFile)
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        return c.r, c.g, c.b
    end
    return NEUTRAL.r, NEUTRAL.g, NEUTRAL.b
end

--- @param classFile string|nil
--- @param defaultR number
--- @param defaultG number
--- @param defaultB number
--- @return number r, number g, number b
function CC.getRGBOr(classFile, defaultR, defaultG, defaultB)
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        return c.r, c.g, c.b
    end
    return defaultR, defaultG, defaultB
end

--- @param r number
--- @param g number
--- @param b number
--- @param text string|nil
--- @return string
function CC.formatHex(r, g, b, text)
    return string.format(
        "|cff%02x%02x%02x%s|r",
        math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5),
        text or ""
    )
end

--- @param name string|nil
--- @param classFile string|nil
--- @return string WoW color escape sequences
function CC.formatName(name, classFile)
    name = name or "?"
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        return CC.formatHex(c.r, c.g, c.b, name)
    end
    return "|cffffffff" .. name .. "|r"
end

--- Like formatName but returns plain text when class color is unavailable.
--- @param text string|nil
--- @param classFile string|nil
--- @return string
function CC.wrapName(text, classFile)
    text = text or "?"
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        return CC.formatName(text, classFile)
    end
    return text
end

--- Class-colored name plus an optional suffix (e.g. " options"), optionally title-colored.
--- @param name string|nil
--- @param classFile string|nil
--- @param suffix string|nil
--- @param suffixRgb table|nil { r, g, b } or { r, g, b, a }
--- @return string
function CC.formatNameWithSuffix(name, classFile, suffix, suffixRgb)
    local coloredName = CC.formatName(name, classFile)
    if not suffix or suffix == "" then
        return coloredName
    end
    if suffixRgb and suffixRgb[1] and CC.formatHex then
        return coloredName .. CC.formatHex(suffixRgb[1], suffixRgb[2], suffixRgb[3], suffix)
    end
    return coloredName .. suffix
end
