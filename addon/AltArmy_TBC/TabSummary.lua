-- AltArmy TBC — Summary tab (placeholder)

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Summary
if not frame then return end

local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
label:SetPoint("CENTER", frame, "CENTER", 0, 0)
label:SetText("Summary — character list will go here")
