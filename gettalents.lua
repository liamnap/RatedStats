local _, RSTATS = ...

RSTATS.GetTalents = RSTATS.GetTalents or {}
local GetTalents = RSTATS.GetTalents

local PendingPvPTalents = {}
RSTATS.DetectedPlayerTalents = RSTATS.DetectedPlayerTalents or {}

local completedUnits = {}
local GUIDToUnitToken = {}
local FriendlyInspectQueue = {}
local InspectInProgress = false
local InspectRetryByGUID = {}

local scanning = false
local maxRetries = 30
local retryCount = 0
local retryInterval = 10  -- ⏱️ Inspect every 10 seconds

-- PTR/Midnight: ensure we never use secret-tainted GUID values as table keys
local function NormalizeGUID(guid)
    if not guid then return nil end
    return tostring(guid)
end

local function GetPlayerFullName(unit)
    local name, realm = UnitName(unit)
    realm = realm or GetRealmName()
    if not name then return nil end
    return realm and realm ~= "" and (name .. "-" .. realm) or name
end

-- Utility: Match unit to a playerStats entry
local function MatchPlayer(unit, playerStats)
	if not unit or not UnitExists(unit) then return nil end
    local name, realm = UnitName(unit)
	local fullName = GetPlayerFullName(unit)

    for _, player in ipairs(playerStats) do
        if player.name == fullName then
            return player
        end
    end
    return nil
end

local function IsRatedPvP()
    return C_PvP.IsRatedBattleground() or C_PvP.IsRatedArena() or C_PvP.IsRatedSoloShuffle() or C_PvP.IsSoloRBG()
end

local function GetUnitTokenByGUID(guid)
    guid = NormalizeGUID(guid)
    return guid and GUIDToUnitToken[guid]
end

local function GetRelevantUnits(callback)
    local tokenTypes = {}
    local expectedMax = 0

    if C_PvP.IsRatedSoloShuffle() then
        expectedMax = 6
        tokenTypes = { "party" } -- Midnight: do not scan enemies (arena tokens)
    elseif C_PvP.IsRatedArena() then
        local matchBracket = C_PvP.GetActiveMatchBracket()
        expectedMax = (matchBracket == 0) and 4 or 6
        tokenTypes = { "party" } -- Midnight: do not scan enemies (arena tokens)
    elseif C_PvP.IsRatedBattleground() then
        expectedMax = 20
        tokenTypes = { "raid", "nameplate" } -- nameplates filtered to friendlies below
    elseif C_PvP.IsSoloRBG() then
        expectedMax = 16
        tokenTypes = { "raid", "nameplate" } -- nameplates filtered to friendlies below
    end

    local seen = {}
    local foundCount = 0
    local seededPlayer = false

    local function ScanLoop()
        -- Always include self once (party/raid tokens do not include "player")
        if not seededPlayer and UnitExists("player") and UnitIsPlayer("player") then
            local pguid = NormalizeGUID(UnitGUID("player"))
            if pguid and not seen[pguid] then
                seen[pguid] = true
                foundCount = foundCount + 1
                callback("player", pguid)
            end
            seededPlayer = true
        end

        for _, prefix in ipairs(tokenTypes) do
            for i = 1, 20 do
                local unit = prefix .. i
                if UnitExists(unit) and UnitIsPlayer(unit) then
                    -- Midnight: only process friendlies; enemies can produce "secret" values.
                    if UnitIsFriend("player", unit) then
                        local guid = NormalizeGUID(UnitGUID(unit))
                        if guid and not seen[guid] then
                            seen[guid] = true
                            foundCount = foundCount + 1
                            callback(unit, guid) -- ⏱️ Send unit to processing immediately
                        end
                    end
                end
            end
        end

        if foundCount < expectedMax then
            C_Timer.After(1.0, ScanLoop)
        else
        end
    end

    ScanLoop()
end

-- Queue a friendly unit for inspect
local function QueueInspect(unit)
    table.insert(FriendlyInspectQueue, unit)
end

-- Process one friendly unit from the queue every 10s
local function ProcessInspectQueue()
    if InspectInProgress or #FriendlyInspectQueue == 0 then return end

    local unit = table.remove(FriendlyInspectQueue, 1)
    if not unit or not UnitExists(unit) or not CanInspect(unit) then
        C_Timer.After(0.1, ProcessInspectQueue)
        return
    end

    InspectInProgress = true
    NotifyInspect(unit)

    C_Timer.After(10, function()
        local guid = NormalizeGUID(UnitGUID(unit))
        if not guid then
            InspectInProgress = false
            ProcessInspectQueue()
            return
        end

        if not C_Traits.HasValidInspectData() then
            -- ❌ Requeue if invalid
            table.insert(FriendlyInspectQueue, unit)
            InspectInProgress = false
            ProcessInspectQueue()
            return
        end

        local talents = RSTATS.DetectedPlayerTalents[guid] or {}

        local importString = C_Traits.GenerateInspectImportString(unit)
        if importString and type(importString) == "string" and importString ~= "" and (not issecretvalue or not issecretvalue(importString)) then
            talents.loadout = importString
            talents.nameplate = unit
            RSTATS.DetectedPlayerTalents[guid] = talents
            completedUnits[guid] = true
        else
            -- ❌ Requeue if missing/secret data, but don't loop forever
            InspectRetryByGUID[guid] = (InspectRetryByGUID[guid] or 0) + 1
            if InspectRetryByGUID[guid] <= maxRetries then
                table.insert(FriendlyInspectQueue, unit)
            else
                completedUnits[guid] = true
            end
        end

        ClearInspectPlayer()
        InspectInProgress = false
        ProcessInspectQueue()
    end)
end

local function ScanSelfTalents()
    local guid = NormalizeGUID(UnitGUID("player"))
    if not guid then return end

    local importString = C_Traits.GenerateInspectImportString("player")
    local talents = {
        nameplate = "player",
        loadout = (importString and type(importString) == "string" and importString ~= "" and (not issecretvalue or not issecretvalue(importString))) and importString or nil,
    }

    RSTATS.DetectedPlayerTalents[guid] = talents
    if talents.loadout then completedUnits[guid] = true end
end

local function ScanFriendlyUnitTalents(unitToken)
    if not UnitExists(unitToken) or not UnitIsPlayer(unitToken) or not CanInspect(unitToken) then return end

    NotifyInspect(unitToken)

    C_Timer.After(10, function()
        local name, realm = UnitName(unitToken)
        if not name then return end
        realm = realm and realm ~= "" and realm or GetRealmName()
        local fullName = name .. "-" .. realm
        local guid = NormalizeGUID(UnitGUID(unitToken))
		if not guid then return end

        if not C_Traits.HasValidInspectData() then return end
        local talents = {
            nameplate = unitToken,
            loadout = nil,
        }

        local importString = C_Traits.GenerateInspectImportString(unitToken)
        if importString and type(importString) == "string" and importString ~= "" and (not issecretvalue or not issecretvalue(importString)) then
            talents.loadout = importString
        end

        -- Merge/update into DetectedPlayerTalents
        RSTATS.DetectedPlayerTalents[guid] = RSTATS.DetectedPlayerTalents[guid] or {}
        for k, v in pairs(talents) do
            RSTATS.DetectedPlayerTalents[guid][k] = v
        end

        -- ✅ Let CLEU continue inferring heroSpec — don’t mark as complete unless all are present
        if not NeedsRescan(guid) then
            completedUnits[guid] = true
        end
    end)
end

local function TryInspectUnit(unitToken)
	if not IsRatedPvP() or not UnitExists(unitToken) or not UnitIsPlayer(unitToken) or not CanInspect(unitToken) then return false end

	local name, realm = UnitName(unitToken)
	if not name then return false end
	realm = realm and realm ~= "" and realm or GetRealmName()
	local fullName = name .. "-" .. realm
    local guid = NormalizeGUID(UnitGUID(unitToken))
    if not guid then return false end
	
	if completedUnits[guid] then
		return false
	end

    NotifyInspect(unitToken)

	C_Timer.After(10, function()
		if not fullName then
			return -- ❌ Don't continue this scan; it will retry on next loop
		end
	
		local guid = NormalizeGUID(UnitGUID(unitToken))
		if not guid then
			return
		end
	
		if not C_Traits.HasValidInspectData() then
			return
		end
	
        local talents = RSTATS.DetectedPlayerTalents[guid] or {}

        local importString = C_Traits.GenerateInspectImportString(unitToken)
        if importString
            and type(importString) == "string"
            and importString ~= ""
            and (not issecretvalue or not issecretvalue(importString)) then

            talents.loadout = importString
            talents.nameplate = unitToken

            -- Save loadout only (PvP talents / hero / spell tracking removed for Midnight)
            PendingPvPTalents[fullName] = talents
            RSTATS.DetectedPlayerTalents[guid] = RSTATS.DetectedPlayerTalents[guid] or {}
            for k, v in pairs(talents) do
                RSTATS.DetectedPlayerTalents[guid][k] = v
            end

            completedUnits[guid] = true
        end
	
		ClearInspectPlayer()
	end)

    return true
end

function NeedsRescan(guid)
    guid = NormalizeGUID(guid)
    if not guid then return true end
    local entry = RSTATS.DetectedPlayerTalents[guid]
    if not entry then return true end

    local unit = GUIDToUnitToken[guid]
    if not unit or not UnitExists(unit) then return false end
    if not UnitIsFriend("player", unit) then return false end

    return not (entry.loadout and entry.loadout ~= "")
end

-- Start scanning logic
function GetTalents:Start()
	if not IsRatedPvP() then return end
	if scanning then return end
	scanning = true
	scannedUnits = {}
	completedUnits = {}
    InspectRetryByGUID = {}
	retryCount = 0
	GUIDToUnitToken = {}

	GetRelevantUnits(function(unit, guid)
		if not unit or not guid then return end
		if completedUnits[guid] then return end

		GUIDToUnitToken[guid] = unit

		if UnitIsFriend("player", unit) then
			if unit == "player" then
				ScanSelfTalents()
			else
				QueueInspect(unit)
			end
		end
	end)
	
	-- 🔁 Start rescan loop once all initial units discovered
	C_Timer.After(2, ProcessInspectQueue)
end

-- Stop externally (e.g., PVP_MATCH_COMPLETE)
function GetTalents:Stop(shouldClearMemory)
    scanning = false

    -- ⚡ If we passed (false), skip clearing memory for now
    if shouldClearMemory == false then
        return
    end

    -- ✅ Otherwise, clear memory immediately
    GetTalents:ReallyClearMemory()
end

function GetTalents:ReallyClearMemory()
    completedUnits = {}
    GUIDToUnitToken = {}
    PendingPvPTalents = {}
    RSTATS.DetectedPlayerTalents = {}
end

return GetTalents