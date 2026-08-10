-- AltArmy TBC — DataStore module: raid / heroic instance lockouts.
-- Requires DataStore.lua (core) loaded first.
-- Capture path: RequestRaidInfo() → UPDATE_INSTANCE_INFO → GetSavedInstanceInfo.

if not AltArmy or not AltArmy.DataStore then return end

local DS = AltArmy.DataStore
local GetCurrentCharTable = DS._GetCurrentCharTable

local LOCKOUT_REQUEST_DELAY = 2
local lockoutRequestFrame = CreateFrame("Frame", nil, UIParent)
lockoutRequestFrame:SetScript("OnUpdate", nil)
lockoutRequestFrame.elapsed = 0

function DS:RequestLockoutInfo()
    if RequestRaidInfo then
        RequestRaidInfo()
    end
end

--- Deferred RequestRaidInfo for login (instance info can be unavailable on the PEW frame).
function DS:RequestLockoutInfoDelayed()
    lockoutRequestFrame.elapsed = 0
    lockoutRequestFrame:SetScript("OnUpdate", function(f, elapsed)
        f.elapsed = f.elapsed + elapsed
        if f.elapsed >= LOCKOUT_REQUEST_DELAY then
            f:SetScript("OnUpdate", nil)
            DS:RequestLockoutInfo()
        end
    end)
end

--- Scan Blizzard saved-instance list into the current character's RaidLockouts table.
--- Replaces the list each scan so expired / unlocked entries age out.
function DS:ScanSavedInstances()
    local char = GetCurrentCharTable()
    if not char then return end
    if not GetNumSavedInstances or not GetSavedInstanceInfo then
        return
    end

    local now = time and time() or 0
    local out = {}
    local n = GetNumSavedInstances() or 0
    for i = 1, n do
        local name, lockoutId, reset, difficulty, locked, extended, _,
            isRaid, maxPlayers, difficultyName, numEncounters, encounterProgress =
            GetSavedInstanceInfo(i)

        reset = tonumber(reset) or 0
        -- Classic clients may omit `locked`; treat nil as locked when a reset timer exists.
        local isLocked = (locked == true) or (locked == nil and reset > 0)
        if isLocked and reset > 0 and type(name) == "string" and name ~= "" then
            out[#out + 1] = {
                name = name,
                lockoutId = tonumber(lockoutId) or 0,
                resetAtUnix = now + reset,
                difficultyId = tonumber(difficulty) or 0,
                difficultyName = (type(difficultyName) == "string" and difficultyName) or "",
                isRaid = isRaid == true,
                maxPlayers = tonumber(maxPlayers) or 0,
                numEncounters = tonumber(numEncounters) or 0,
                encounterProgress = tonumber(encounterProgress) or 0,
                extended = extended == true,
            }
        end
    end

    char.RaidLockouts = out
    char.lastLockoutScan = now
end
