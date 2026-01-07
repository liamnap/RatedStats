GetTalents = {}
PendingPvPTalents = PendingPvPTalents or {}
RSTATS.DetectedPlayerTalents = RSTATS.DetectedPlayerTalents or {}

local completedUnits = {}
local GUIDToUnitToken = {}
local FriendlyInspectQueue = {}
local InspectInProgress = false

local scanning = false
local maxRetries = 30
local retryCount = 0
local retryInterval = 10  -- ⏱️ Inspect every 10 seconds

function GetPlayerFullName(unit)
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
	return GUIDToUnitToken[guid]
end

local function GetRelevantUnits(callback)
    local tokenTypes = {}
    local expectedMax = 0

    if C_PvP.IsRatedSoloShuffle() then
        expectedMax = 6
        tokenTypes = { "party", "arena" }
    elseif C_PvP.IsRatedArena() then
        local matchBracket = C_PvP.GetActiveMatchBracket()
        expectedMax = (matchBracket == 0) and 4 or 6
        tokenTypes = { "party", "arena" }
    elseif C_PvP.IsRatedBattleground() then
        expectedMax = 20
        tokenTypes = { "raid", "nameplate" }
    elseif C_PvP.IsSoloRBG() then
        expectedMax = 16
        tokenTypes = { "raid", "nameplate" }
    end

    local seen = {}
    local foundCount = 0

    local function ScanLoop()
        for _, prefix in ipairs(tokenTypes) do
            for i = 1, 20 do
                local unit = prefix .. i
                if UnitExists(unit) and UnitIsPlayer(unit) then
                    local guid = UnitGUID(unit)
                    if guid and not seen[guid] then
                        seen[guid] = true
                        foundCount = foundCount + 1
                        callback(unit, guid) -- ⏱️ Send unit to processing immediately
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
        local guid = UnitGUID(unit)
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
            -- ❌ Requeue if missing data
            table.insert(FriendlyInspectQueue, unit)
        end

        InspectInProgress = false
        ProcessInspectQueue()
    end)
end

local function ScanSelfTalents()
    local guid = UnitGUID("player")
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
        local guid = UnitGUID(unitToken)

        if not C_Traits.HasValidInspectData() then return end

        local talents = {
            nameplate = unitToken,
            loadout = C_Traits.GenerateInspectImportString(unitToken),
        }

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
	local guid = UnitGUID(unitToken)
	
	if completedUnits[guid] then
		return false
	end

    NotifyInspect(unitToken)

	C_Timer.After(10, function()
		if not fullName then
			return -- ❌ Don't continue this scan; it will retry on next loop
		end
	
		local guid = UnitGUID(unitToken)
		if not guid then
			return
		end
	
		if not C_Traits.HasValidInspectData() then
			return
		end
	
		local talents = RSTATS.DetectedPlayerTalents[guid] or {}
		
		for i = 1, 3 do
			local pvpTalent = C_SpecializationInfo.GetInspectSelectedPvpTalent(unitToken, i)
			if pvpTalent then
				talents["pvptalent" .. i] = pvpTalent
			end
		end
	
		local importString = C_Traits.GenerateInspectImportString(unitToken)
		talents.loadout = importString or nil
		talents.nameplate = unitToken
	
		-- Only save and mark as completed if valid data
		if importString and importString ~= "" then
			PendingPvPTalents[fullName] = talents
			RSTATS.DetectedPlayerTalents[guid] = RSTATS.DetectedPlayerTalents[guid] or {}
			for k, v in pairs(talents) do
				RSTATS.DetectedPlayerTalents[guid][k] = v
			end
			
			if not NeedsRescan(guid)
			and talents.playerTrackedSpells
			and #talents.playerTrackedSpells >= 50 then
				completedUnits[guid] = true
			end
		end
	
		ClearInspectPlayer()
	end)

    return true
end

function GetTalents:ProcessHeroCheck(unit)
	local name, realm = UnitName(unit)
	if not name or not UnitIsPlayer(unit) then return end

	realm = realm and realm ~= "" and realm or GetRealmName()
	local fullName = name .. "-" .. realm
	local guid = UnitGUID(unit)
	if not guid then return end

	local entry = {
		name = fullName,
		nameplate = unit,
		guid = guid,
		heroSpec = nil,
		pvptalent1 = nil,
		pvptalent2 = nil,
		pvptalent3 = nil,
	}

	local _, class = UnitClass(unit)
	local bestHero = nil
	local bestMatches = 0
	
	for heroName, spellList in pairs(HERO_TALENTS) do
		local specClass = (next(spellList) and spellList[next(spellList)].class) or nil
		local matches = 0
		
		for _, spell in pairs(spellList) do
			local ids = spell.spellID
			if type(ids) ~= "table" then ids = { ids } end
			
			for _, id in ipairs(ids) do
				if TrackedPlayerSpells[guid] and TrackedPlayerSpells[guid][id] then
					matches = matches + 1
					break
				elseif HasAuraBySpellID(unit, id) then
					matches = matches + 1
					break
				end
			end
		end
		
		if specClass == class and matches > bestMatches then
			bestMatches = matches
			bestHero = heroName
		end
	end
	
	if bestHero and bestMatches >= 1 then
		entry.heroSpec = bestHero
	end

	-- PvP Talents (from actual auras)
	local cache = auraScanCache[unit]
	if cache and cache.map then
		for auraSpellID in pairs(cache.map) do
			if C_Spell.IsPvPTalentSpell and C_Spell.IsPvPTalentSpell(auraSpellID) then
				if not entry.pvptalent1 then
					entry.pvptalent1 = auraSpellID
				elseif not entry.pvptalent2 and entry.pvptalent1 ~= auraSpellID then
					entry.pvptalent2 = auraSpellID
				elseif not entry.pvptalent3 and entry.pvptalent2 ~= auraSpellID and entry.pvptalent1 ~= auraSpellID then
					entry.pvptalent3 = auraSpellID
				end
			end
		end
	end

	RSTATS.DetectedPlayerTalents[guid] = RSTATS.DetectedPlayerTalents[guid] or {}
	for k, v in pairs(entry) do
		RSTATS.DetectedPlayerTalents[guid][k] = v
	end
	
	if not NeedsRescan(guid)
	and entry.playerTrackedSpells
	and #entry.playerTrackedSpells >= 50 then
		completedUnits[guid] = true
	end
end

function GetTalents:ProcessHerosandEnemyUnit(unit)
	C_Timer.After(0.01, function()
		GetTalents:ProcessHeroCheck(unit)
	end)
end

function NeedsRescan(guid)
	local entry = RSTATS.DetectedPlayerTalents[guid]
	if not entry then return true end

    -- NEW: if we’ve collected more than 40 distinct spells, force “complete”
    if entry.playerTrackedSpells and #entry.playerTrackedSpells > 40 then
        return false
    end

	local unit = GUIDToUnitToken[guid]
	local isFriendly = unit and UnitIsFriend("player", unit)

	-- Both friendlies and enemies need PvP talents 1-3
	for i = 1, 3 do
		if not entry["pvptalent" .. i] then return true end
	end
	
	-- Need hero spec resolved
	if not entry.heroSpec then return true end
	
	-- Need at least one spell recorded
	if not entry.playerTrackedSpells or #entry.playerTrackedSpells < 50 then
		return true
	end

	return false
end

-- Start scanning logic
function GetTalents:Start()
	if not IsRatedPvP() then return end
	if scanning then return end
	scanning = true
	scannedUnits = {}
	completedUnits = {}
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
