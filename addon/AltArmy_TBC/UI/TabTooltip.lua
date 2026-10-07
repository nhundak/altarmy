-- AltArmy TBC — Tab tooltips: the tab's name, then the slash command that opens it in gray
-- (UI/MainTabs.lua's SlashCommand). Used by the side tabs (UI/SideTabs.lua) and sub-view tabs (UI/TopTabs.lua).

AltArmy = AltArmy or {}
AltArmy.TabTooltip = AltArmy.TabTooltip or {}

local TabTooltip = AltArmy.TabTooltip

TabTooltip.COMMAND_COLOR = { 0.5, 0.5, 0.5 }

local function isOwned(owner)
    if GameTooltip.IsShown and not GameTooltip:IsShown() then return false end
    if GameTooltip.IsOwned then return GameTooltip:IsOwned(owner) end
    return GameTooltip.GetOwner and GameTooltip:GetOwner() == owner
end

--- Show `label` with `command` (may be nil) under it. A tooltip the button's template already shows for it
--- (native side tabs, TabSystem icon tabs) keeps its own text and only gains the command.
function TabTooltip.Show(owner, label, command, anchor)
    if not isOwned(owner) then
        GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
        GameTooltip:SetText(label)
    end
    if command then
        local c = TabTooltip.COMMAND_COLOR
        GameTooltip:AddLine(command, c[1], c[2], c[3])
    end
    GameTooltip:Show()
end

--- After a template's own OnEnter (or none), show the tab's tooltip with its command; hide what we showed.
function TabTooltip.Hook(button, label, command, anchor)
    if not command then return end
    button:HookScript("OnEnter", function(self)
        TabTooltip.Show(self, label, command, anchor)
    end)
    button:HookScript("OnLeave", function(self)
        if isOwned(self) then GameTooltip:Hide() end
    end)
end
