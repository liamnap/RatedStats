local Stats = {}

-- Lookup tier info by MMR and bracket
local function GetTierByMMR(mmr, tierIDs)
    for _, tierID in ipairs(tierIDs) do
		local t = C_PvP.GetPvpTierInfo(tierID)
		if t and mmr > t.descendRating and mmr < t.ascendRating then
			return {
				name = t.name,
				icon = t.tierIconID,
				tierID = tierID
			}
		end
	end

    return nil
end

-- Get your current bracket info by bracketID
local function GetCurrentBracketInfo(bracketID, filteredMatches)
    local tierID = select(10, GetPersonalRatedInfo(bracketID))
    if not tierID then return nil end

    local tierInfo = C_PvP.GetPvpTierInfo(tierID)
    if not tierInfo then return nil end

    return {
        name = tierInfo.name,
        icon = tierInfo.tierIconID,
        tierID = tierID
    }
end

-- Fallback to most recent valid match in season if Today has no games
local function GetMostRecentEnemyMMR(matches)
	local seasonStart = RSTATS:GetCurrentSeasonStart()
	local seasonFinish = RSTATS:GetCurrentSeasonFinish()

	for _, match in ipairs(matches) do
		if not match.isInitial and match.endTime and (match.endTime >= seasonStart and match.endTime < seasonFinish) then
			local mmr = tonumber(match.enemyMMR)
			if mmr then
				return mmr
			end
		end
	end
	return nil
end

-- Main stats calculation
function Stats.CalculateSummary(filteredMatches, fullMatchHistory, bracketID)
    local win, loss, draw = 0, 0, 0
    local crDelta = 0
    local mapStats = {}
	table.sort(filteredMatches, function(a, b)
		return (a.endTime or 0) < (b.endTime or 0)
	end)

    local firstMMR, lastMMR
	local firstMatchID, lastMatchID

    for _, match in ipairs(filteredMatches) do
        -- Win/Loss/Draw
        if match.friendlyWinLoss:find("W") then
            win = win + 1
        elseif match.friendlyWinLoss:find("L") then
            loss = loss + 1
        elseif match.friendlyWinLoss:find("D") then
            draw = draw + 1
        end
		
		local playerName = UnitName("player") .. "-" .. GetRealmName()
        -- CR (personal)
        for _, ps in ipairs(match.playerStats or {}) do
            if ps.name == playerName then
                crDelta = crDelta + (tonumber(ps.ratingChange) or 0)

                local mmr = tonumber(ps.postmatchMMR)
                if mmr then
                    if not firstMMR then 
						firstMMR = mmr
						firstMatchID = match.matchID
					end
                    lastMMR = mmr
					lastMatchID = match.matchID
                end
                break
            end
        end

        -- Map stats
        if match.mapName then
            local delta = match.friendlyWinLoss:find("W") and 1 or -1
            mapStats[match.mapName] = (mapStats[match.mapName] or 0) + delta
        end
    end

    local mmrDelta = 0
    if firstMMR and lastMMR then
        mmrDelta = lastMMR - firstMMR
    end

    -- Winrate
    local total = win + loss + draw
    local winrate = total > 0 and math.floor((win / total) * 100) or 0

    -- Best/Worst maps
    local bestMap, worstMap, bestScore, worstScore = nil, nil, -math.huge, math.huge
    for map, score in pairs(mapStats) do
        if score > bestScore then
            bestScore = score
            bestMap = map
        end
        if score < worstScore then
            worstScore = score
            worstMap = map
        end
    end

    -- Brackets
    local bracketInfo = GetCurrentBracketInfo(bracketID, filteredMatches)

    local enemyMMR = GetMostRecentEnemyMMR(fullMatchHistory)
    local tierRanges = {
        [7] = {303, 304, 305, 306, 307, 308, 309, 310, 311, 312}, -- Solo Shuffle
        [1] = {1, 2, 3, 4, 5, 6, 7, 8, 9},           -- 2v2
        [2] = {11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21}, -- 3v3
        [4] = {206, 207, 208, 209, 210, 211, 212, 213, 214}, -- RBG
        [9] = {383, 384, 385, 386, 387, 389, 390, 391}, -- Solo RBG
    }
    local enemyBracketInfo = enemyMMR and GetTierByMMR(enemyMMR, tierRanges[bracketID] or {}) or nil

    return {
        crDelta = crDelta,
        mmrDelta = mmrDelta,
        win = win,
        loss = loss,
        draw = draw,
        winrate = winrate,
        bestMap = bestMap,
        worstMap = worstMap,
        currentBracket = bracketInfo and bracketInfo.name,
        currentIconID = bracketInfo and bracketInfo.icon,
        enemyBracket = enemyBracketInfo and enemyBracketInfo.name,
        enemyIconID = enemyBracketInfo and enemyBracketInfo.icon
    }
end

RSTATS_STATS = Stats
