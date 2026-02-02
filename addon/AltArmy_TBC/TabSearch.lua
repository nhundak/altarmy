-- AltArmy TBC — Search tab (placeholder)

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Search
if not frame then return end

local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
label:SetPoint("CENTER", frame, "CENTER", 0, 0)
label:SetText("Search — item search across characters will go here")
