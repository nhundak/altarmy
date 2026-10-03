-- AltArmy TBC — Characters tab (placeholder)

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Characters
if not frame then return end

local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
label:SetPoint("CENTER", frame, "CENTER", 0, 0)
label:SetText("Characters — select a character; containers view will go here")
