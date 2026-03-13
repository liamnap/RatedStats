local Config = RSTATS.Config
RatedStatsFilters = RatedStatsFilters or {}

-- Helper to fetch filters scoped to current tab
local function GetCurrentFilters()
	local tabID = PanelTemplates_GetSelectedTab(RSTATS.UIConfig)
	RatedStatsFilters[tabID] = RatedStatsFilters[tabID] or {}
	return RatedStatsFilters[tabID]
end

-- Tab ID based map lists
local MapListsByTab = {
	[1] = { -- Solo Shuffle
		"NPG", "M", "HP", "BEA",
		"ED", "NA", "TTP", "DS",
		"ROL", "AF", "COC"
	},
	[2] = { -- 2v2
		"NPG", "M", "HP", "BEA",
		"ED", "NA", "TTP", "DS",
		"ROL", "AF", "COC"
	},
	[3] = { -- 3v3
		"NPG", "M", "HP", "BEA",
		"ED", "NA", "TTP", "DS",
		"ROL", "AF", "COC"
	},
	[4] = { -- RBG
		"Arathi Basin", "Battle for Gilneas", "Deepwind Gorge", "Eye of the Storm",
		"Silvershard Mines", "Temple of Kotmogu", "Warsong Gulch", "Twin Peaks", "Deephaul Ravine"
	},
	[5] = { -- Solo RBG
		"Arathi Basin", "Battle for Gilneas", "Deepwind Gorge", "Eye of the Storm",
		"Silvershard Mines", "Temple of Kotmogu", "Warsong Gulch", "Twin Peaks", "Deephaul Ravine"
	}
}

-- Build epoch timestamps from UTC calendar fields (so DST/local-machine timezone doesn't corrupt season boundaries).
local function UtcTime(y, mo, d, h, mi, s)
    local localGuess = time({
        year = y, month = mo, day = d,
        hour = h or 0, min = mi or 0, sec = s or 0,
    })
    local utcTable = date("!*t", localGuess)
    local offset = localGuess - time(utcTable) -- local - utc at that moment (includes DST)
    return localGuess + offset
end

local REGION = (GetCurrentRegion and GetCurrentRegion()) or 3 -- default EU if unknown

-- Weekly reset anchors (UTC):
-- NA: Tuesday 15:00 UTC
-- EU: Wednesday 04:00 UTC
-- KR: Thursday 08:00 KST
-- TW: Thursday 07:00 CST

-- NOTE: For KR/TW, we express the weekly reset moment as 23:00 UTC on the previous day.
local function KR_TW_ResetUTC(y, mo, d)
    return UtcTime(y, mo, d, 0, 0, 0) - 3600 -- 23:00 UTC the previous day
end

local function BuildSeasons_US()
    return {
        -- Start aligned to weekly reset (maintenance start). Finish aligned to Blizzard "ratings lock" time when known.
        -- DF S4: NA July 22 10:00pm PDT => July 23 05:00 UTC
        { label = "DF S4",  start = UtcTime(2024, 4, 23, 15, 0, 0), finish = UtcTime(2024, 7, 23, 5, 0, 0) },
        -- TWW S1: ratings lock 10:00pm local night before Feb 25 update (NA)
        { label = "TWW S1", start = UtcTime(2024, 9, 10, 15, 0, 0), finish = UtcTime(2025, 2, 25, 6, 0, 0) },
        -- TWW S2: ratings lock 10:00pm local night before Aug 5 update (NA)
        { label = "TWW S2", start = UtcTime(2025, 3, 4, 15, 0, 0),  finish = UtcTime(2025, 8, 5, 5, 0, 0) },
        -- TWW S3: NA Jan 19 10:00pm PST => Jan 20 06:00 UTC
        { label = "TWW S3", start = UtcTime(2025, 8, 12, 15, 0, 0), finish = UtcTime(2026, 1, 20, 6, 0, 0) },
        -- Midnight S1 (your planned dates): align start to reset; finish left as "night before maintenance" pattern.
        { label = "MN S1", start = UtcTime(2026, 3, 17, 15, 0, 0), finish = UtcTime(2026, 8, 4, 5, 0, 0) },
    }
end

local function BuildSeasons_EU()
    return {
        -- DF S4: EU July 23 22:00 CEST => July 23 20:00 UTC
        { label = "DF S4",  start = UtcTime(2024, 4, 24, 4, 0, 0),  finish = UtcTime(2024, 7, 23, 20, 0, 0) },
        -- TWW S1: ratings lock 22:00 local night before Feb 26 update (EU) => Feb 25 21:00 UTC
        { label = "TWW S1", start = UtcTime(2024, 9, 11, 4, 0, 0),  finish = UtcTime(2025, 2, 25, 21, 0, 0) },
        -- TWW S2: EU forums: Season 2 PvP ends 22:00 CEST on Aug 5 => 20:00 UTC
        { label = "TWW S2", start = UtcTime(2025, 3, 5, 4, 0, 0),   finish = UtcTime(2025, 8, 5, 20, 0, 0) },
        -- TWW S3: EU Jan 20 22:00 CET => 21:00 UTC
        { label = "TWW S3", start = UtcTime(2025, 8, 13, 4, 0, 0),  finish = UtcTime(2026, 1, 20, 21, 0, 0) },
        { label = "MN S1", start = UtcTime(2026, 3, 18, 4, 0, 0), finish = UtcTime(2026, 8, 5, 20, 0, 0) },
    }
end

local function BuildSeasons_KR()
    return {
        -- Starts aligned to KR weekly reset moment (Thu 08:00 KST == Wed 23:00 UTC).
        -- DF S4: ends July 24 22:00 KR.
        { label = "DF S4",  start = KR_TW_ResetUTC(2024, 4, 25), finish = UtcTime(2024, 7, 24, 13, 0, 0) },
        { label = "TWW S1", start = KR_TW_ResetUTC(2024, 9, 12), finish = UtcTime(2025, 2, 26, 13, 0, 0) },
        { label = "TWW S2", start = KR_TW_ResetUTC(2025, 3, 6),  finish = UtcTime(2025, 8, 6, 13, 0, 0) },
        { label = "TWW S3", start = KR_TW_ResetUTC(2025, 8, 14), finish = UtcTime(2026, 1, 21, 13, 0, 0) },
        { label = "MN S1", start = KR_TW_ResetUTC(2026, 3, 19), finish = UtcTime(2026, 8, 6, 13, 0, 0) },
    }
end

local function BuildSeasons_TW()
    return {
        -- Starts aligned to TW weekly reset moment (Thu 07:00 CST == Wed 23:00 UTC).
        -- DF S4: ends July 24 22:00 TW. :contentReference[oaicite:18]{index=18}
        { label = "DF S4",  start = KR_TW_ResetUTC(2024, 4, 25), finish = UtcTime(2024, 7, 24, 14, 0, 0) },
        { label = "TWW S1", start = KR_TW_ResetUTC(2024, 9, 12), finish = UtcTime(2025, 2, 26, 14, 0, 0) },
        { label = "TWW S2", start = KR_TW_ResetUTC(2025, 3, 6),  finish = UtcTime(2025, 8, 6, 14, 0, 0) },
        { label = "TWW S3", start = KR_TW_ResetUTC(2025, 8, 14), finish = UtcTime(2026, 1, 21, 14, 0, 0) },
        { label = "MN S1", start = KR_TW_ResetUTC(2026, 3, 19), finish = UtcTime(2026, 8, 6, 14, 0, 0) },
    }
end

if REGION == 1 then
    RatedStatsSeasons = BuildSeasons_US()
elseif REGION == 2 then
    RatedStatsSeasons = BuildSeasons_KR()
elseif REGION == 4 then
    RatedStatsSeasons = BuildSeasons_TW()
else
    RatedStatsSeasons = BuildSeasons_EU()
end

function RSTATS:GetCurrentSeasonStart()
	local now = time()
	for _, season in ipairs(RatedStatsSeasons or {}) do
		if now >= season.start and now <= season.finish then
			return season.start
		end
	end
	return nil
end

function RSTATS:GetCurrentSeasonFinish()
	local now = time()
	for _, season in ipairs(RatedStatsSeasons or {}) do
		if now >= season.start and now <= season.finish then
			return season.finish
		end
	end
	return nil
end

local Seasons = RatedStatsSeasons

local CRBrackets = {
	{ label = "0 - 1400", min = 0, max = 1400 },
	{ label = "1401 - 1600", min = 1401, max = 1600 },
	{ label = "1601 - 1800", min = 1601, max = 1800 },
	{ label = "1801 - 1950", min = 1801, max = 1950 },
	{ label = "1951 - 2100", min = 1951, max = 2100 },
	{ label = "2101 - 2400", min = 2101, max = 2400 },
	{ label = "2400+", min = 2401, max = math.huge },
}
local MMRBrackets = CopyTable(CRBrackets)

local function GetSeasonLabel(timestamp)
	for _, season in ipairs(Seasons) do
		if timestamp and timestamp >= season.start and timestamp <= season.finish then
			return season.label
		end
	end
	return "Unknown"
end

local function UpdateClearButtonVisibility()
	if not RSTATS or not RSTATS.UIConfig or not RSTATS.UIConfig.clearFilterButton then return end

	local currentTabID = PanelTemplates_GetSelectedTab(RSTATS.UIConfig)
	local filters = RatedStatsFilters[currentTabID]
	if not filters then
		RSTATS.UIConfig.clearFilterButton:Hide()
		return
	end

	for _, v in pairs(filters) do
		if v then
			RSTATS.UIConfig.clearFilterButton:Show()
			return
		end
	end

	RSTATS.UIConfig.clearFilterButton:Hide()
end

function Config:CreateSearchBox(parent)
	local searchBox = CreateFrame("EditBox", "RatedStatsSearchBox", parent, "SearchBoxTemplate")
	searchBox:SetSize(180, 20)
	searchBox:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -40, -34)
	searchBox:SetAutoFocus(false)

	-- Fix layering so placeholder sits behind typed text
	if searchBox.Instructions then
		searchBox.Instructions:SetDrawLayer("BACKGROUND")
	end

	searchBox:SetScript("OnTextChanged", function(self)
		FilterAndSearchMatches(self:GetText())

		-- Fix placeholder alpha when typing
		if self.Instructions then
			if self:GetText() == "" then
				self.Instructions:SetAlpha(1)
			else
				self.Instructions:SetAlpha(0)
			end
		end
	end)

	parent.searchBox = searchBox

	-- 🔘 Filters Button
	local filterButton = CreateFrame("Button", "RatedStatsFilterButton", parent, "UIPanelButtonTemplate")
	filterButton:SetSize(70, 22)
	filterButton:SetText("Filters")
	filterButton:SetPoint("RIGHT", searchBox, "LEFT", -5, 0)
	parent.filterButton = filterButton

	-- ❌ AH-style Red X inside filter button
	local clearBtn = CreateFrame("Button", nil, filterButton)
	clearBtn:SetSize(16, 16)
	clearBtn:SetPoint("TOPRIGHT", filterButton, "TOPRIGHT", 4, 4)
	clearBtn:SetNormalAtlas("auctionhouse-ui-filter-redx")
	clearBtn:Hide()

	clearBtn:SetScript("OnClick", function()
		local tabID = PanelTemplates_GetSelectedTab(RSTATS.UIConfig)
		RatedStatsFilters[tabID] = {}
		FilterAndSearchMatches(RatedStatsSearchBox:GetText())
		UpdateClearButtonVisibility()
	end)

	clearBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Clear all filters", 1, 1, 1)
		GameTooltip:Show()
	end)

	clearBtn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	parent.clearFilterButton = clearBtn
end

function Config:CreateFilterMenu(parent)
	local filterButton = parent.filterButton
	local dropdown = CreateFrame("Frame", "RatedStatsFilterDropdown", UIParent, "UIDropDownMenuTemplate")
	dropdown.displayMode = "MENU"

	filterButton:SetScript("OnClick", function()
		ToggleDropDownMenu(1, nil, dropdown, filterButton, 0, 0)
	end)

	dropdown.initialize = function(self, level, menuList)
		local filters = GetCurrentFilters()
		local info = UIDropDownMenu_CreateInfo()

		if level == 1 then
			for _, section in ipairs({
				{ text = "Win/Loss/Draw", menu = "WLD" },
				{ text = "Map", menu = "MAP" },
				{ text = "Season", menu = "SEASON" },
				{ text = "CR Range", menu = "CR" },
				{ text = "MMR Range", menu = "MMR" }
			}) do
				info.text = section.text
				info.hasArrow = true
				info.menuList = section.menu
				info.notCheckable = true
				UIDropDownMenu_AddButton(info, level)
			end

		elseif menuList == "WLD" then
			for _, opt in ipairs({ "Win", "Loss", "Draw" }) do
				info = UIDropDownMenu_CreateInfo()
				info.text = opt
				info.isNotRadio = true
				info.keepShownOnClick = true
				info.checked = filters[opt]
				info.func = function(_, _, _, checked)
					filters[opt] = checked
					FilterAndSearchMatches(RatedStatsSearchBox:GetText())
				end
				UIDropDownMenu_AddButton(info, level)
			end

		elseif menuList == "MAP" then
			local tabID = PanelTemplates_GetSelectedTab(RSTATS.UIConfig)
			for _, map in ipairs(MapListsByTab[tabID] or {}) do
				info = UIDropDownMenu_CreateInfo()
				info.text = map
				info.isNotRadio = true
				info.keepShownOnClick = true
				info.checked = filters[map]
				info.func = function(_, _, _, checked)
					filters[map] = checked
					FilterAndSearchMatches(RatedStatsSearchBox:GetText())
				end
				UIDropDownMenu_AddButton(info, level)
			end

		elseif menuList == "SEASON" then
			for _, season in ipairs(Seasons) do
				info = UIDropDownMenu_CreateInfo()
				info.text = season.label
				info.isNotRadio = true
				info.keepShownOnClick = true
				info.checked = filters[season.label]
				info.func = function(_, _, _, checked)
					filters[season.label] = checked
					FilterAndSearchMatches(RatedStatsSearchBox:GetText())
				end
				UIDropDownMenu_AddButton(info, level)
			end

		elseif menuList == "CR" then
			for _, range in ipairs(CRBrackets) do
				local key = "CR_" .. range.label
				info = UIDropDownMenu_CreateInfo()
				info.text = range.label
				info.isNotRadio = true
				info.keepShownOnClick = true
				info.checked = filters[key]
				info.func = function(_, _, _, checked)
					filters[key] = checked
					FilterAndSearchMatches(RatedStatsSearchBox:GetText())
				end
				UIDropDownMenu_AddButton(info, level)
			end

		elseif menuList == "MMR" then
			for _, range in ipairs(MMRBrackets) do
				local key = "MMR_" .. range.label
				info = UIDropDownMenu_CreateInfo()
				info.text = range.label
				info.isNotRadio = true
				info.keepShownOnClick = true
				info.checked = filters[key]
				info.func = function(_, _, _, checked)
					filters[key] = checked
					FilterAndSearchMatches(RatedStatsSearchBox:GetText())
				end
				UIDropDownMenu_AddButton(info, level)
			end
		end
	end
end

-- 🕒 Time-based filtering helper
function FilterMatchesByTimeRange(matches, filterType)
	if not filterType then return matches end

	local now = time()
	local filtered = {}
	local seasonStart, seasonFinish

	-- Season ranges ("This Season" or explicit season labels like "TWW S3")
	if filterType == "thisSeason" then
		seasonStart  = RSTATS and RSTATS.GetCurrentSeasonStart  and RSTATS:GetCurrentSeasonStart()  or nil
		seasonFinish = RSTATS and RSTATS.GetCurrentSeasonFinish and RSTATS:GetCurrentSeasonFinish() or nil
	else
		for _, season in ipairs(Seasons or {}) do
			if season.label == filterType then
				seasonStart, seasonFinish = season.start, season.finish
				break
			end
		end
	end

	local function isSameDay(ts1, ts2)
		return date("%x", ts1) == date("%x", ts2)
	end

	local function isSameWeek(ts)
		return tonumber(date("%W", ts)) == tonumber(date("%W", now))
	end

	local function isSameMonth(ts)
		local nowTable = date("*t", now)
		local thenTable = date("*t", ts)
		return nowTable.month == thenTable.month and nowTable.year == thenTable.year
	end

	local function isYesterday(ts)
		local today = date("*t", now)
		local yday = time({ year = today.year, month = today.month, day = today.day }) - 86400
		return isSameDay(ts, yday)
	end

	for _, match in ipairs(matches) do
		local ts = match.timestamp or match.endTime
		if ts then
			local include = false

			if seasonStart and seasonFinish then
				include = (ts >= seasonStart and ts <= seasonFinish)
			elseif filterType == "today" and isSameDay(ts, now) then include = true
			elseif filterType == "yesterday" and isYesterday(ts) then include = true
			elseif filterType == "thisWeek" and isSameWeek(ts) then include = true
			elseif filterType == "thisMonth" and isSameMonth(ts) then include = true
			elseif filterType == "thisSeason" then include = true end

			if include then
				table.insert(filtered, match)
			end
		end
	end

	return filtered
end

function ApplyFilters(match, tabID, historyTable)
	local f = GetCurrentFilters()

	-- 🧹 Auto-hide 'Initial' games if history has > 2 matches
	if match.friendlyWinLoss == "I" then
        -- Use the resolved table from FilterAndSearchMatches().
        -- For SS/RBGB this is the active spec bucket.
        -- For other tabs it's the base DB table.
		if historyTable and #historyTable > 2 then
			return false
		end
	end

	-- 🏆 Win/Loss
	if f.Win or f.Loss or f.Draw then
		local result
		if match.friendlyWinLoss:find("W") then result = "Win"
		elseif match.friendlyWinLoss:find("L") then result = "Loss"
		elseif match.friendlyWinLoss:find("D") then result = "Draw" end

		if result and not f[result] then return false end
	end

	-- 📉 Rating Change
	if f.High or f.Average or f.Small or f.Negative then
		local change = tonumber(match.friendlyRatingChange) or 0
		if change >= 20 and not f.High then return false end
		if change >= 10 and change < 20 and not f.Average then return false end
		if change >= 0 and change < 10 and not f.Small then return false end
		if change < 0 and not f.Negative then return false end
	end

	-- 📊 CR Range
	local crFiltersActive = false
	for _, r in ipairs(CRBrackets) do
		if f["CR_" .. r.label] then crFiltersActive = true break end
	end
	if crFiltersActive then
		local cr = tonumber(match.cr or 0)
		local pass = false
		for _, r in ipairs(CRBrackets) do
			if f["CR_" .. r.label] and cr >= r.min and cr <= r.max then
				pass = true
				break
			end
		end
		if not pass then return false end
	end

	-- 📊 MMR Range
	local mmrFiltersActive = false
	for _, r in ipairs(MMRBrackets) do
		if f["MMR_" .. r.label] then mmrFiltersActive = true break end
	end
	if mmrFiltersActive then
		local mmr = tonumber(match.friendlyMMR or 0)
		local pass = false
		for _, r in ipairs(MMRBrackets) do
			if f["MMR_" .. r.label] and mmr >= r.min and mmr <= r.max then
				pass = true
				break
			end
		end
		if not pass then return false end
	end

	-- 🗺️ Map
	local tabID = PanelTemplates_GetSelectedTab(RSTATS.UIConfig)
	local activeMapFilters = {}
	for _, map in ipairs(MapListsByTab[tabID] or {}) do
		if f[map] then
			activeMapFilters[map] = true
		end
	end
	if next(activeMapFilters) then
		if not activeMapFilters[match.mapName] then
			return false
		end
	end

	-- 📅 Season
	do
		local anySeason = false
		for _, s in ipairs(Seasons or {}) do
			if f[s.label] then anySeason = true break end
		end
		if anySeason then
			local ts = match.endTime or match.timestamp
			local season = GetSeasonLabel(ts)
			if not f[season] then return false end
		end
	end

	return true
end

function FilterAndSearchMatches(query)
	query = (query or ""):lower()
	local tabID = PanelTemplates_GetSelectedTab(RSTATS.UIConfig)

	-- 🧠 Detect table growth per tab
	RSTATS.__LastHistoryCount = RSTATS.__LastHistoryCount or {}

	local data
	if (tabID == 1 or tabID == 5) and RSTATS and RSTATS.GetHistoryForTab then
		data = { id = (tabID == 1 and 7 or 9), table = RSTATS:GetHistoryForTab(tabID) or {} }
	else
		data = ({
			[1] = { id = 7, table = Database.SoloShuffleHistory },
			[2] = { id = 1, table = Database.v2History },
			[3] = { id = 2, table = Database.v3History },
			[4] = { id = 4, table = Database.RBGHistory },
			[5] = { id = 9, table = Database.SoloRBGHistory },
		})[tabID]
	end

	if not data or not data.table then return end

	local prevCount = RSTATS.__LastHistoryCount[tabID] or 0
	local currentCount = #data.table
	local forceRedraw = currentCount > prevCount
	RSTATS.__LastHistoryCount[tabID] = currentCount

    local historyTable = data.table

    local filtered = {}
    for _, match in ipairs(historyTable) do
        local matches = ApplyFilters(match, tabID, historyTable)
		if query ~= "" then
			local found = (match.mapName and match.mapName:lower():find(query))
			if not found then
				for _, p in ipairs(match.playerStats or {}) do
					if p.name and p.name:lower():find(query) then
						found = true
						break
					end
				end
			end
			if not found then matches = false end
		end

		if matches then
			table.insert(filtered, match)
		end
	end

	local scrollContent = RSTATS.ScrollContents and RSTATS.ScrollContents[tabID]
	local contentFrame  = RSTATS.ContentFrames and RSTATS.ContentFrames[tabID]
	local scrollFrame   = RSTATS.ScrollFrames   and RSTATS.ScrollFrames[tabID]

	if scrollContent and contentFrame and scrollFrame then
		local mmrLabel = DisplayCurrentCRMMR(contentFrame, data.id)
		contentFrame:Show()
		local hasFilters = false
		local f = RatedStatsFilters and RatedStatsFilters[tabID]
		if f then
			for _, v in pairs(f) do
				if v then hasFilters = true break end
			end
		end
		local isFiltered = (query ~= "") or hasFilters
		local headerTexts, matchFrames = RSTATS:DisplayHistory(scrollContent, filtered, mmrLabel, tabID, isFiltered)

		local headerAnchor = scrollContent.headerFrame
		if headerAnchor then
			scrollFrame:ClearAllPoints()
			scrollFrame:SetPoint("TOPLEFT", headerAnchor, "BOTTOMLEFT", 0, -5)
			scrollFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -20, 40)
		end

		-- 🚀 Trigger reflow if table grew (new match was added)
		if forceRedraw then
			RatedStatsFilters[tabID] = {}
			UpdateClearButtonVisibility()
		end
	end

	UpdateClearButtonVisibility()
end



