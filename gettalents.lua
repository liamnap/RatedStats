TalentTracker = {}
PendingPvPTalents = PendingPvPTalents or {}

local scannedUnits = {}
local completedUnits = {}
local scanning = false
local retryInterval = 1
local maxRetries = 30
local retryCount = 0

function GetPlayerFullName(unit)
    local name, realm = UnitName(unit)
    realm = realm or GetRealmName()
    if not name then return nil end
    return realm and realm ~= "" and (name .. "-" .. realm) or name
end

-- Utility: Match unit to a playerStats entry
local function MatchPlayer(unit, playerStats)
    if not UnitExists(unit) then return nil end
    local name, realm = UnitName(unit)
	local fullName = GetPlayerFullName(unitToken)

    for _, player in ipairs(playerStats) do
        if player.name == fullName then
            return player
        end
    end
    return nil
end

local function TryInspectUnit(unitToken)
    if not UnitExists(unitToken) or not UnitIsPlayer(unitToken) or not CanInspect(unitToken) then return false end

    local guid = UnitGUID(unitToken)
    local name, realm = UnitName(unitToken)
    local fullName = (realm and realm ~= "") and (name .. "-" .. realm) or name

    NotifyInspect(unitToken)

    C_Timer.After(0.5, function()
        local talents = {}
        for i = 1, 3 do
            local pvpTalent = C_SpecializationInfo.GetInspectSelectedPvpTalent(unitToken, i)
            if pvpTalent then
                talents["pvptalent" .. i] = pvpTalent
            end
        end

        local importString = C_Traits.GenerateInspectImportString(unitToken)
        talents.loadout = importString or nil
		
        -- ✅ Store in Pending table for later injection
        PendingPvPTalents[fullName] = talents

        print("|cff33ff99[TalentTracker]|r Queued PvP talents for:", fullName)
        for k, v in pairs(talents) do
            print("  → " .. k .. ": " .. tostring(v))
        end

        ClearInspectPlayer()
    end)

    return true
end

-- Get relevant unit tokens for current bracket
local function GetRelevantUnits()
    local units = {}

    if C_PvP.IsRatedSoloShuffle() or C_PvP.IsRatedArena() then
        for i = 1, 3 do
            table.insert(units, "party" .. i)
            table.insert(units, "arena" .. i)
        end
    elseif C_PvP.IsRatedBattleground() or C_PvP.IsSoloRBG() then
        for i = 1, 10 do
            table.insert(units, "raid" .. i)
            table.insert(units, "enemy" .. i)
        end
    end

    return units
end

-- Start scanning logic
function TalentTracker:Start()
    if scanning then return end
    scanning = true
    scannedUnits = {}
    completedUnits = {}
    retryCount = 0

    local units = GetRelevantUnits()

    local function ScanLoop()
        if retryCount > maxRetries or not scanning then
            print("|cffff5555[TalentTracker]|r Stopping scan. Max retries reached or manually stopped.")
            scanning = false
            return
        end

        retryCount = retryCount + 1

        for _, unit in ipairs(units) do
            if not completedUnits[unit] then
                TryInspectUnit(unit)
            end
        end

        -- Check if all are done
        local allDone = true
        for _, unit in ipairs(units) do
            if not completedUnits[unit] then
                allDone = false
                break
            end
        end

        if allDone then
            print("|cff00ff00[TalentTracker]|r All unit talents collected.")
            scanning = false
        else
            C_Timer.After(retryInterval, ScanLoop)
        end
    end

    ScanLoop()
end

-- Stop externally (e.g., PVP_MATCH_COMPLETE)
function TalentTracker:Stop()
    scanning = false
end

return TalentTracker
