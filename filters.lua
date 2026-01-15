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

RatedStatsSeasons = {
    { label = "DF S4", start = time({ year = 2024, month = 4, day = 23 }), finish = time({ year = 2024, month = 7, day = 22 }) },
    { label = "TWW S1", start = time({ year = 2024, month = 9, day = 10 }), finish = time({ year = 2025, month = 2, day = 25 }) },
    { label = "TWW S2", start = time({ year = 2025, month = 3, day = 4 }), finish = time({ year = 2025, month = 8, day = 5 }) },
    { label = "TWW S3", start = time({ year = 2025, month = 8, day = 12 }), finish = time({ year = 2026, month = 1, day = 20 }) },
    { label = "Midnight S1", start = time({ year = 2026, month = 3, day = 4 }), finish = time({ year = 2026, month = 8, day = 5 }) },
}

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
		local ts = match.timestamp
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

function ApplyFilters(match)
	local f = GetCurrentFilters()

	-- 🧹 Auto-hide 'Initial' games if history has > 2 matches
	if match.friendlyWinLoss == "I" then
		local tabID = PanelTemplates_GetSelectedTab(RSTATS.UIConfig)
		local tableByTab = {
			[1] = Database.SoloShuffleHistory,
			[2] = Database.v2History,
			[3] = Database.v3History,
			[4] = Database.RBGHistory,
			[5] = Database.SoloRBGHistory,
		}
		local historyTable = tableByTab[tabID]
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
	if f["DF S4"] or f["TWW S1"] or f["TWW S2"] then
		local season = GetSeasonLabel(match.timestamp)
		if not f[season] then return false end
	end

	return true
end

function FilterAndSearchMatches(query)
	query = (query or ""):lower()
	local tabID = PanelTemplates_GetSelectedTab(RSTATS.UIConfig)

	-- 🧠 Detect table growth per tab
	RSTATS.__LastHistoryCount = RSTATS.__LastHistoryCount or {}

	local data = ({
		[1] = { id = 7, table = Database.SoloShuffleHistory },
		[2] = { id = 1, table = Database.v2History },
		[3] = { id = 2, table = Database.v3History },
		[4] = { id = 4, table = Database.RBGHistory },
		[5] = { id = 9, table = Database.SoloRBGHistory },
	})[tabID]

	if not data or not data.table then return end

	local prevCount = RSTATS.__LastHistoryCount[tabID] or 0
	local currentCount = #data.table
	local forceRedraw = currentCount > prevCount
	RSTATS.__LastHistoryCount[tabID] = currentCount

	local filtered = {}
	for _, match in ipairs(data.table) do
		local matches = ApplyFilters(match)

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
		local headerTexts, matchFrames = RSTATS:DisplayHistory(scrollContent, filtered, mmrLabel, tabID, true)

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



