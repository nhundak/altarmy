-- AltArmy TBC — Sequential onboarding dialog queue.
-- luacheck: globals C_Timer CreateFrame

if not AltArmy then return end

AltArmy.OnboardingDialogQueue = AltArmy.OnboardingDialogQueue or {}
local ODQ = AltArmy.OnboardingDialogQueue

local providers = {}
local showing = false
local processScheduled = false
local nextIndex = 1

local function sortProviders()
    table.sort(providers, function(a, b)
        local pa = a.priority or 100
        local pb = b.priority or 100
        if pa ~= pb then return pa < pb end
        return (a.id or "") < (b.id or "")
    end)
end

function ODQ.Register(provider)
    if not provider or not provider.id then return end
    for i = 1, #providers do
        if providers[i].id == provider.id then
            providers[i] = provider
            sortProviders()
            return
        end
    end
    providers[#providers + 1] = provider
    sortProviders()
end

function ODQ.Process()
    if showing then return end
    sortProviders()
    if #providers == 0 then
        nextIndex = 1
        return
    end
    for i = nextIndex, #providers do
        local provider = providers[i]
        local should = provider.shouldPrompt and provider.shouldPrompt() or false
        if should and provider.show then
            showing = true
            provider.show(function()
                showing = false
                nextIndex = i + 1
                if nextIndex > #providers then
                    nextIndex = 1
                else
                    ODQ.Process()
                end
            end)
            return
        end
    end
    nextIndex = 1
end

function ODQ.RequestProcess()
    if processScheduled then return end
    processScheduled = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            processScheduled = false
            nextIndex = 1
            ODQ.Process()
        end)
    else
        processScheduled = false
        nextIndex = 1
        ODQ.Process()
    end
end

function ODQ._ResetForTests()
    providers = {}
    showing = false
    processScheduled = false
    nextIndex = 1
end

local enterFrame = CreateFrame and CreateFrame("Frame")
if enterFrame then
    enterFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    enterFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            ODQ.RequestProcess()
        end
    end)
end
