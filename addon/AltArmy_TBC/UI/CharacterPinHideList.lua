-- AltArmy TBC — Reusable character Pin/Hide list for settings panels (Gear, Summary).
-- Requires: AltArmy, AltArmy.Characters, AltArmy.RealmFilter (optional).

if not AltArmy then return end

local CHAR_LIST_ROW = 20
local ROW_RIGHT_INSET = 120

local function TruncateName(fontString, fullName, maxWidth)
    if not fullName or fullName == "" then
        fontString:SetText("?")
        return "?"
    end
    fontString:SetText(fullName)
    if fontString:GetStringWidth() <= maxWidth then
        return fullName
    end
    for len = #fullName - 1, 1, -1 do
        local truncated = fullName:sub(1, len) .. "..."
        fontString:SetText(truncated)
        if fontString:GetStringWidth() <= maxWidth then
            return truncated
        end
    end
    fontString:SetText("...")
    return "..."
end

--- Create a scrollable character list with Pin/Hide checkboxes.
--- @param parent Frame Parent (e.g. settings content frame).
--- @param anchorBelow Frame Anchor the top of the list below this frame (e.g. realm dropdown button).
--- @param opts table getSettings, getCharSetting, setCharSetting, onChange (optional)
--- @return Frame scrollFrame, function Refresh()
function AltArmy.CreateCharacterPinHideList(parent, anchorBelow, opts)
    local getSettings = opts.getSettings or function() return {} end
    local getCharSetting = opts.getCharSetting or function() return false end
    local setCharSetting = opts.setCharSetting or function() end
    local onChange = opts.onChange or function() end

    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT", anchorBelow, "BOTTOMLEFT", 0, -8)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    scroll:EnableMouse(true)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    child:SetWidth(1)
    scroll:SetScrollChild(child)

    scroll:SetScript("OnMouseWheel", function(_, delta)
        local scrollVal = scroll:GetVerticalScroll()
        local newScroll = scrollVal - delta * CHAR_LIST_ROW * 2
        local maxScroll = math.max(0, child:GetHeight() - scroll:GetHeight())
        newScroll = math.max(0, math.min(maxScroll, newScroll))
        scroll:SetVerticalScroll(newScroll)
    end)

    local rowPool = {}
    local function GetRow(i)
        if not rowPool[i] then
            local row = CreateFrame("Frame", nil, child)
            row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * CHAR_LIST_ROW)
            row:SetHeight(CHAR_LIST_ROW)
            row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.nameText:SetPoint("LEFT", row, "LEFT", 0, 0)
            row.nameText:SetPoint("RIGHT", row, "RIGHT", -ROW_RIGHT_INSET, 0)
            row.nameText:SetJustifyH("LEFT")
            row.nameText:SetWordWrap(false)
            row.pinBtn = CreateFrame("CheckButton", nil, row)
            row.pinBtn:SetPoint("RIGHT", row, "RIGHT", -60, 0)
            row.pinBtn:SetSize(18, 18)
            local pinBg = row.pinBtn:CreateTexture(nil, "BACKGROUND")
            pinBg:SetAllPoints(row.pinBtn)
            pinBg:SetColorTexture(0.25, 0.25, 0.25, 0.9)
            row.pinBtn.tex = row.pinBtn:CreateTexture(nil, "OVERLAY")
            row.pinBtn.tex:SetAllPoints(row.pinBtn)
            row.pinBtn.tex:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            row.pinBtn:SetCheckedTexture(row.pinBtn.tex)
            local pinLabel = row.pinBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            pinLabel:SetPoint("RIGHT", row.pinBtn, "LEFT", -2, 0)
            pinLabel:SetText("Pin")
            row.hideBtn = CreateFrame("CheckButton", nil, row)
            row.hideBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            row.hideBtn:SetSize(18, 18)
            local hideBg = row.hideBtn:CreateTexture(nil, "BACKGROUND")
            hideBg:SetAllPoints(row.hideBtn)
            hideBg:SetColorTexture(0.25, 0.25, 0.25, 0.9)
            row.hideBtn.tex = row.hideBtn:CreateTexture(nil, "OVERLAY")
            row.hideBtn.tex:SetAllPoints(row.hideBtn)
            row.hideBtn.tex:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            row.hideBtn:SetCheckedTexture(row.hideBtn.tex)
            local hideLabel = row.hideBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            hideLabel:SetPoint("RIGHT", row.hideBtn, "LEFT", -2, 0)
            hideLabel:SetText("Hide")
            local nameOverlay = CreateFrame("Frame", nil, row)
            nameOverlay:SetPoint("LEFT", row, "LEFT", 0, 0)
            nameOverlay:SetPoint("RIGHT", row, "RIGHT", -ROW_RIGHT_INSET, 0)
            nameOverlay:SetHeight(CHAR_LIST_ROW)
            nameOverlay:EnableMouse(true)
            nameOverlay:SetScript("OnEnter", function(self)
                if self.fullNameDisplay and self.wasTruncated and GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                    GameTooltip:ClearLines()
                    GameTooltip:AddLine(self.fullNameDisplay, 1, 1, 1, true)
                    GameTooltip:Show()
                end
            end)
            nameOverlay:SetScript("OnLeave", function()
                if GameTooltip then GameTooltip:Hide() end
            end)
            row.nameOverlay = nameOverlay
            rowPool[i] = row
        end
        return rowPool[i]
    end

    function scroll:Refresh()
        local rawList = (AltArmy.Characters and AltArmy.Characters.GetList and AltArmy.Characters:GetList()) or {}
        local list = {}
        for i = 1, #rawList do list[i] = rawList[i] end
        table.sort(list, function(a, b)
            local na, nb = (a.name or ""):lower(), (b.name or ""):lower()
            if na ~= nb then return na < nb end
            return (a.realm or ""):lower() < (b.realm or ""):lower()
        end)
        local s = getSettings()
        local currentRealm = (GetRealmName and GetRealmName()) or ""
        local RF = AltArmy.RealmFilter
        if RF and RF.filterListByRealm then
            list = RF.filterListByRealm(list, s.realmFilter or "all", currentRealm)
        end
        local showRealmSuffix = (s.realmFilter == "all") and RF and RF.hasMultipleRealms and RF.hasMultipleRealms(list)
        for _, row in pairs(rowPool) do
            row:Hide()
        end
        local n = #list
        child:SetWidth(scroll:GetWidth() or 350)
        child:SetHeight(math.max(1, n * CHAR_LIST_ROW))
        for i = 1, n do
            local entry = list[i]
            local row = GetRow(i)
            row:Show()
            local r, g, b = 1, 0.82, 0
            if entry.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.classFile] then
                local rc = RAID_CLASS_COLORS[entry.classFile]
                r, g, b = rc.r, rc.g, rc.b
            end
            local nameDisplayStr
            local tooltipDisplayStr
            if showRealmSuffix and RF and RF.formatCharacterDisplayNameColored and RF.formatCharacterDisplayName then
                nameDisplayStr = RF.formatCharacterDisplayNameColored(
                    RF.formatCharacterDisplayName(entry.name or "?", entry.realm, true), nil, false, r, g, b)
                tooltipDisplayStr = nameDisplayStr
                row.nameText:SetText(nameDisplayStr)
            else
                nameDisplayStr = entry.name or "?"
                tooltipDisplayStr = string.format("|cFF%02x%02x%02x%s|r",
                    math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), nameDisplayStr)
                row.nameText:SetText(nameDisplayStr)
                row.nameText:SetTextColor(r, g, b, 1)
            end
            local nameW = row.nameText:GetWidth()
            local displayed = nameDisplayStr
            if nameW and nameW > 4 then
                displayed = TruncateName(row.nameText, nameDisplayStr, nameW - 2)
            end
            if row.nameOverlay then
                row.nameOverlay.fullNameDisplay = tooltipDisplayStr
                row.nameOverlay.wasTruncated = (displayed ~= nameDisplayStr)
            end
            row.entry = entry
            local pin = getCharSetting(entry.name, entry.realm, "pin")
            local hide = getCharSetting(entry.name, entry.realm, "hide")
            row.pinBtn:SetChecked(pin)
            row.hideBtn:SetChecked(hide)
            row.pinBtn:SetScript("OnClick", function()
                local newPin = not getCharSetting(entry.name, entry.realm, "pin")
                setCharSetting(entry.name, entry.realm, newPin, false)
                row.pinBtn:SetChecked(newPin)
                row.hideBtn:SetChecked(false)
                onChange()
            end)
            row.hideBtn:SetScript("OnClick", function()
                local newHide = not getCharSetting(entry.name, entry.realm, "hide")
                setCharSetting(entry.name, entry.realm, false, newHide)
                row.hideBtn:SetChecked(newHide)
                row.pinBtn:SetChecked(false)
                onChange()
            end)
        end
    end

    return scroll, scroll.Refresh
end
