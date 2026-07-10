-- AltArmy TBC — FontString text helpers (truncation with optional color-code awareness).

AltArmy = AltArmy or {}
AltArmy.Text = AltArmy.Text or {}

local Text = AltArmy.Text

Text.ONBOARDING_DISMISS_FOOTNOTE =
    "This message will only show once but you can make changes later in Options"

local function affixWidth(fontString, affix)
    if not affix or affix == "" then
        return 0
    end
    fontString:SetText(affix)
    return fontString:GetStringWidth()
end

local function splitColoredText(fullName)
    local prefix = fullName:match("^|c%x%x%x%x%x%x%x%x")
    if prefix and #fullName >= 12 and fullName:sub(-2) == "|r" then
        return prefix, fullName:sub(11, -3)
    end
    return "", fullName
end

--- Truncate text to fit maxWidth on a FontString.
--- opts.returnBoolean — return whether truncated (TabSummary).
--- opts.preserveColorCodes — keep |cff…|r wrapper while truncating visible portion (TabSearch).
--- opts.prefix — never truncated; prepended before name (TabSearch item icons).
--- opts.suffix — never truncated; appended after name (TabSearch location labels, item counts).
--- @param fontString FontString
--- @param fullName string|nil
--- @param maxWidth number
--- @param opts table|nil
--- @return string|boolean displayed text, or boolean when returnBoolean is set
function Text.TruncateFontString(fontString, fullName, maxWidth, opts)
    opts = opts or {}
    local returnBoolean = opts.returnBoolean == true
    local affixPrefix = opts.prefix or ""
    local suffix = opts.suffix or ""
    local preserveColorCodes = opts.preserveColorCodes == true

    if preserveColorCodes then
        local maxNameW = maxWidth - 2
        if affixPrefix ~= "" then
            maxNameW = maxNameW - affixWidth(fontString, affixPrefix)
        end
        if suffix ~= "" then
            maxNameW = maxNameW - affixWidth(fontString, suffix)
        end
        if maxNameW < 10 then maxNameW = 10 end
        local colorPrefix, visible = splitColoredText(fullName or "")
        if visible == "" then
            local emptyText = affixPrefix .. suffix
            fontString:SetText(emptyText)
            if returnBoolean then return false end
            return emptyText
        end
        fontString:SetText(colorPrefix .. visible .. (colorPrefix ~= "" and "|r" or ""))
        if fontString:GetStringWidth() <= maxNameW then
            local finalText = affixPrefix .. colorPrefix .. visible
                .. (colorPrefix ~= "" and "|r" or "") .. suffix
            fontString:SetText(finalText)
            if returnBoolean then return false end
            return finalText
        end
        for len = #visible - 1, 1, -1 do
            local truncated = visible:sub(1, len) .. "..."
            fontString:SetText(colorPrefix .. truncated .. (colorPrefix ~= "" and "|r" or ""))
            if fontString:GetStringWidth() <= maxNameW then
                local finalText = affixPrefix .. colorPrefix .. truncated
                    .. (colorPrefix ~= "" and "|r" or "") .. suffix
                fontString:SetText(finalText)
                if returnBoolean then return true end
                return finalText
            end
        end
        local finalText = affixPrefix .. colorPrefix .. "..."
            .. (colorPrefix ~= "" and "|r" or "") .. suffix
        fontString:SetText(finalText)
        if returnBoolean then return true end
        return finalText
    end

    if not fullName or fullName == "" then
        local emptyText = affixPrefix .. "?" .. suffix
        fontString:SetText(emptyText)
        if returnBoolean then return false end
        return emptyText
    end

    local maxTextW = maxWidth - 2
    if affixPrefix ~= "" then
        maxTextW = maxTextW - affixWidth(fontString, affixPrefix)
    end
    if suffix ~= "" then
        maxTextW = maxTextW - affixWidth(fontString, suffix)
    end
    if maxTextW < 10 then maxTextW = 10 end

    fontString:SetText(fullName)
    if fontString:GetStringWidth() <= maxTextW then
        local finalText = affixPrefix .. fullName .. suffix
        fontString:SetText(finalText)
        if returnBoolean then return false end
        return finalText
    end
    for len = #fullName - 1, 1, -1 do
        local truncated = fullName:sub(1, len) .. "..."
        fontString:SetText(truncated)
        if fontString:GetStringWidth() <= maxTextW then
            local finalText = affixPrefix .. truncated .. suffix
            fontString:SetText(finalText)
            if returnBoolean then return true end
            return finalText
        end
    end
    local finalText = affixPrefix .. "..." .. suffix
    fontString:SetText(finalText)
    if returnBoolean then return true end
    return finalText
end
