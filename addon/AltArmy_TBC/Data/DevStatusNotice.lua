-- AltArmy TBC — One-time development-status notice (SavedVariables load-failure caveat).
-- Shows once, ever, ahead of every other onboarding dialog, then blocks the rest of the
-- onboarding queue for the remainder of the session so it isn't buried by other prompts.

if not AltArmy then return end

AltArmy.DevStatusNotice = AltArmy.DevStatusNotice or {}
local DSN = AltArmy.DevStatusNotice

function DSN.EnsureDismiss()
    _G.AltArmyTBC_Options = _G.AltArmyTBC_Options or {}
end

function DSN.IsDismissed()
    DSN.EnsureDismiss()
    return AltArmyTBC_Options.devStatusNoticeShown == true
end

function DSN.Dismiss()
    DSN.EnsureDismiss()
    AltArmyTBC_Options.devStatusNoticeShown = true
end

function DSN.ShouldPrompt(opts)
    opts = opts or {}
    if not opts.skipDismiss and DSN.IsDismissed() then
        return false
    end
    return true
end

function DSN.RegisterOnboardingProvider()
    local ODQ = AltArmy.OnboardingDialogQueue
    local dialog = AltArmy.DevStatusNoticeDialog
    if not ODQ or not ODQ.Register or not dialog or not dialog.Show then
        return
    end
    ODQ.Register({
        id = "devStatusNotice",
        priority = 0,
        shouldPrompt = function()
            return DSN.ShouldPrompt()
        end,
        show = function(onDismiss)
            dialog.Show(onDismiss)
        end,
    })
end

DSN.EnsureDismiss()
