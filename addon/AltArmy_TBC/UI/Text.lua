-- AltArmy TBC — FontString text helpers (truncation with optional color-code awareness).

AltArmy = AltArmy or {}
AltArmy.Text = AltArmy.Text or {}

local Text = AltArmy.Text

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
--- opts.suffix — never truncated; appended after name (TabSearch location labels).
--- @param fontString FontString
--- @param fullName string|nil
--- @param maxWidth number
--- @param opts table|nil
--- @return string|boolean displayed text, or boolean when returnBoolean is set
function Text.TruncateFontString(fontString, fullName, maxWidth, opts)
    opts = opts or {}
    local returnBoolean = opts.returnBoolean == true
    local suffix = opts.suffix
    local preserveColorCodes = opts.preserveColorCodes == true

    if preserveColorCodes then
        local maxNameW = maxWidth - 2
        if suffix and suffix ~= "" then
            fontString:SetText(suffix)
            maxNameW = maxNameW - fontString:GetStringWidth()
            if maxNameW < 10 then maxNameW = 10 end
        end
        local prefix, visible = splitColoredText(fullName or "")
        if visible == "" then
            fontString:SetText(suffix or "")
            if returnBoolean then return false end
            return suffix or ""
        end
        fontString:SetText(prefix .. visible .. (prefix ~= "" and "|r" or ""))
        if fontString:GetStringWidth() <= maxNameW then
            local finalText = prefix .. visible .. (prefix ~= "" and "|r" or "") .. (suffix or "")
            fontString:SetText(finalText)
            if returnBoolean then return false end
            return finalText
        end
        for len = #visible - 1, 1, -1 do
            local truncated = visible:sub(1, len) .. "..."
            fontString:SetText(prefix .. truncated .. (prefix ~= "" and "|r" or ""))
            if fontString:GetStringWidth() <= maxNameW then
                local finalText = prefix .. truncated .. (prefix ~= "" and "|r" or "") .. (suffix or "")
                fontString:SetText(finalText)
                if returnBoolean then return true end
                return finalText
            end
        end
        local finalText = prefix .. "..." .. (prefix ~= "" and "|r" or "") .. (suffix or "")
        fontString:SetText(finalText)
        if returnBoolean then return true end
        return finalText
    end

    if not fullName or fullName == "" then
        fontString:SetText("?")
        if returnBoolean then return false end
        return "?"
    end
    fontString:SetText(fullName)
    if fontString:GetStringWidth() <= maxWidth then
        if returnBoolean then return false end
        return fullName
    end
    for len = #fullName - 1, 1, -1 do
        local truncated = fullName:sub(1, len) .. "..."
        fontString:SetText(truncated)
        if fontString:GetStringWidth() <= maxWidth then
            if returnBoolean then return true end
            return truncated
        end
    end
    fontString:SetText("...")
    if returnBoolean then return true end
    return "..."
end
