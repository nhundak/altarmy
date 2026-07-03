-- AltArmy TBC — Detect and resolve RestedXP quest reward upgrade indicator conflict.

if not AltArmy then return end

AltArmy.RestedXpQuestRewardConflict = AltArmy.RestedXpQuestRewardConflict or {}
local RC = AltArmy.RestedXpQuestRewardConflict

local RXI = AltArmy.RestedXpIntegration
local GU = AltArmy.GearUpgrade

function RC.EnsureDismiss()
    _G.AltArmyTBC_Options = _G.AltArmyTBC_Options or {}
end

function RC.IsDismissed()
    RC.EnsureDismiss()
    return AltArmyTBC_Options.restedXpQuestRewardConflictDismissed == true
end

function RC.Dismiss()
    RC.EnsureDismiss()
    AltArmyTBC_Options.restedXpQuestRewardConflictDismissed = true
end

local function refreshIndicators()
    local QRI = AltArmy.QuestRewardIndicators
    if QRI and QRI.Refresh then
        QRI.Refresh()
    end
end

function RC.ShouldPrompt(opts)
    opts = opts or {}
    if not opts.skipDismiss and RC.IsDismissed() then
        return false
    end
    if not RXI or not RXI.IsLoaded or not RXI.IsLoaded() then
        return false
    end
    local guOpts = GU and GU.GetOptions and GU.GetOptions() or {}
    if guOpts.showQuestRewardUpgradeIndicator == false then
        return false
    end
    local rxpEnabled = RXI.IsQuestRewardUpgradeRecommendationEnabled()
    if rxpEnabled == nil then
        if RXI.SchedulePromptRecheck then
            RXI.SchedulePromptRecheck()
        end
        return false
    end
    if not rxpEnabled then
        return false
    end
    return true
end

function RC.ChooseAltArmy()
    if RXI and RXI.SetQuestRewardUpgradeRecommendationEnabled then
        RXI.SetQuestRewardUpgradeRecommendationEnabled(false)
    end
    if RXI and RXI.SetQuestRewardGoldRecommendationEnabled then
        RXI.SetQuestRewardGoldRecommendationEnabled(false)
    end
    RC.Dismiss()
    refreshIndicators()
end

function RC.ChooseRestedXp()
    if GU and GU.EnsureGearUpgradeOptions then
        local guOpts = GU.EnsureGearUpgradeOptions()
        guOpts.showQuestRewardUpgradeIndicator = false
        guOpts.showQuestRewardVendorIndicator = false
    end
    RC.Dismiss()
    refreshIndicators()
end

function RC.DismissWithoutChoice()
    RC.Dismiss()
    refreshIndicators()
end

function RC.RegisterOnboardingProviders()
    local ODQ = AltArmy.OnboardingDialogQueue
    local dialog = AltArmy.RestedXpQuestRewardConflictDialog
    if not ODQ or not ODQ.Register or not dialog or not dialog.Show then
        return
    end
    ODQ.Register({
        id = "restedXpQuestRewardConflict",
        priority = 5,
        shouldPrompt = function()
            return RC.ShouldPrompt()
        end,
        show = function(onDismiss)
            dialog.Show(onDismiss)
        end,
    })

    local BD = AltArmy.BankAltDetect
    local bankDialog = AltArmy.BankAltSuggestDialog
    if not BD or not BD.Evaluate or not bankDialog or not bankDialog.Show then
        return
    end
    ODQ.Register({
        id = "bankAltSuggest",
        priority = 10,
        shouldPrompt = function()
            local DS = AltArmy.DataStore
            if not DS or not DS.GetCurrentCharacter then return false end
            local char = DS:GetCurrentCharacter()
            if not char then return false end
            local result = BD.Evaluate(char, DS, { isCurrent = true })
            return result.shouldPrompt == true
        end,
        show = function(onDismiss)
            local DS = AltArmy.DataStore
            if not DS or not DS.GetCurrentCharacter then
                onDismiss()
                return
            end
            local char = DS:GetCurrentCharacter()
            if not char then
                onDismiss()
                return
            end
            local result = BD.Evaluate(char, DS, { isCurrent = true })
            if not result.shouldPrompt then
                onDismiss()
                return
            end
            bankDialog.Show(result, onDismiss)
        end,
    })
end

RC.EnsureDismiss()
