-- Define the InitializeTrace function
local function InitializeTrace()
    -- Simulate typing the /etrace command in the chat
    ChatFrame1EditBox:SetText("/etrace")
    -- Simulate pressing Enter to send the command
    ChatEdit_SendText(ChatFrame1EditBox, 0)
    -- Optionally print a message to confirm the trace command was issued
    DEFAULT_CHAT_FRAME:AddMessage("Running /etrace for event tracing.")
end

-- InitializeTrace()

-- Function to print only match entries from SoloShuffleHistory
function PrintSoloRBGMatchEntries(historyTable)
    if not historyTable or #historyTable == 0 then
        return
    end

    -- Iterate over the matches in the history table
    for i, matchEntry in ipairs(historyTable) do
        -- Attempt to convert timestamp to human-readable format
        if type(matchEntry.timestamp) == "number" then
            local formattedDate = date("%Y-%m-%d %H:%M:%S", matchEntry.timestamp)
        else
        end
    end
end

--------------------------------------
-- Namespaces
--------------------------------------
local _, RSTATS = ... -- The first line sets up the local variables `_` and `RSTATS`, where `_` is typically used to ignore values, and `RSTATS` is the namespace for the addon
local playerName = UnitName("player") .. "-" .. GetRealmName()

RSTATS.Database = RSTATS_Database or {} -- adds Database table to RSTATS namespace
RSTATS.Database[playerName] = RSTATS.Database[playerName] or {} -- Ensure the character-specific table exists within RSTATS_Database
Database = RSTATS.Database[playerName]

-- Initialize the Config table
RSTATS.Config = RSTATS.Config or {}; -- adds Config table to RSTATS namespace
-- The Config table will store configuration settings and functions related to the addon's configuration.
local Config = RSTATS.Config
-- Initialize the UIConfig variable, which will hold the main configuration UI frame.
local UIConfig

Database.combatLogEvents = Database.combatLogEvents or {}
combatLogEvents = Database.combatLogEvents

-- Define a function to print table contents
local function PrintTable(tbl, name)
    if not tbl then
        DEFAULT_CHAT_FRAME:AddMessage(name .. " is nil")
        return
    end

    DEFAULT_CHAT_FRAME:AddMessage(name .. ":")
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            PrintTable(v, k)  -- Recursively print tables
        else
            DEFAULT_CHAT_FRAME:AddMessage("  " .. tostring(k) .. ": " .. tostring(v))
        end
    end
end

-- Define a function to simulate /dump command
function SimulateDumpCommand(tableName)
    if tableName == "RSTATS_Database" then
        PrintTable(RSTATS_Database, "RSTATS_Database")
    elseif tableName == "RSTATS.Config" then
        PrintTable(RSTATS.Config, "RSTATS.Config")
    else
        DEFAULT_CHAT_FRAME:AddMessage("Unknown table: " .. tableName)
    end
end

------- Example of calling the function
-----SimulateDumpCommand("RSTATS_Database")  -- Dumps RSTATS_Database
------- or
-----SimulateDumpCommand("RSTATS.Config")  -- Dumps RSTATS.Config

--------------------------------------
-- Defaults (usually a database!)
--------------------------------------

local defaults = {
    theme = {
        r = 0,
        g = 0.8, -- 204/255
        b = 1,
        hex = "00ccff"
    }
}

local rowSpacing = {
    SoloShuffle = 3,
    ["2v2"] = 2,
    ["3v3"] = 3,
    RBG = 10,
    SoloRBG = 8
}

--------------------------------------
-- Config functions
--------------------------------------

function Config:Toggle()
	Config:CreateMenu()
    local menu = UIConfig or Config:CreateMenu();
    menu:SetShown(not menu:IsShown());
end

-- Removing Config:GetThemeColor causes a lua error, needs investigating before removing

function Config:GetThemeColor()
    local c = defaults.theme;
    return c.r, c.g, c.b, c.hex;
end

----- local function ScrollFrame_OnMouseWheel(self, delta)
-----     local newValue = self:GetVerticalScroll() - (delta * 20);
----- 
-----     if (newValue < 0) then
-----         newValue = 0;
-----     elseif (newValue > self:GetVerticalScrollRange()) then
-----         newValue = self:GetVerticalScrollRange();
-----     end
----- 
-----     self:SetVerticalScroll(newValue);
----- end
----- 
----- local function HorizontalScrollFrame_OnMouseWheel(self, delta)
-----     local newValue = self:GetHorizontalScroll() - (delta * 20);
----- 
-----     if (newValue < 0) then
-----         newValue = 0;
-----     elseif (newValue > self:GetHorizontalScrollRange()) then
-----         newValue = self:GetHorizontalScrollRange();
-----     end
----- 
-----     self:SetHorizontalScroll(newValue);
----- end

local function Tab_OnClick(self)
    PanelTemplates_SetTab(self:GetParent(), self:GetID());

    local scrollChild = UIConfig.ScrollFrame:GetScrollChild();
    if (scrollChild) then
        scrollChild:Hide();
    end

    UIConfig.ScrollFrame:SetScrollChild(self.content);
    self.content:Show();
end

local function SetTabs(frame, numTabs, ...)
    frame.numTabs = numTabs;

    local contents = {};
    local frameName = frame:GetName();

    for i = 1, numTabs do
        local tab = CreateFrame("Button", frameName.."Tab"..i, frame, "PanelTabButtonTemplate");
        tab:SetID(i);
        tab:SetText(select(i, ...));
        tab:SetScript("OnClick", Tab_OnClick);

        tab.content = CreateFrame("Frame", nil, UIConfig.ScrollFrame, "BackdropTemplate"); -- Ensure BackdropTemplate is used
        tab.content:SetSize(1800, 500);
        tab.content:Hide();

        table.insert(contents, tab.content);

        if (i == 1) then
            tab:SetPoint("TOPLEFT", UIConfig, "BOTTOMLEFT", 10, 7); -- Changes the initial position of first tab
        else
            tab:SetPoint("TOPLEFT", _G[frameName.."Tab"..(i - 1)], "TOPRIGHT", -2, 0); -- Changes the position of the subsequent tabs eg overlap
        end
    end

    Tab_OnClick(_G[frameName.."Tab1"]);

    return unpack(contents);
end

----------------------------------
-- Utility functions
----------------------------------

local function GetTimestamp()
    return time()
end

function SaveData()
    RSTATS.Database[playerName] = Database  -- Make sure global table reflects local changes
    RSTATS_Database = RSTATS.Database
    RSTATS.Config = Config
end

function LoadData()
    -- Check if the global RSTATS_Database exists
    if not RSTATS_Database then
        RSTATS_Database = {}  -- Initialize an empty global table if it's nil
        return false
    end

    -- Set the addon-specific Database reference
    RSTATS.Database = RSTATS_Database

    -- Ensure player-specific data is initialized
    local playerName = UnitName("player") .. "-" .. GetRealmName()
    
    if not RSTATS.Database[playerName] then
        RSTATS.Database[playerName] = {}  -- Initialize player-specific data
        return false
    end

    -- Assign the player-specific data to the local Database reference
    Database = RSTATS.Database[playerName]

    -- Ensure all necessary tables are initialized for the player
    Database.SoloShuffleHistory = Database.SoloShuffleHistory or {}
    Database.v2History = Database.v2History or {}
    Database.v3History = Database.v3History or {}
    Database.RBGHistory = Database.RBGHistory or {}
    Database.SoloRBGHistory = Database.SoloRBGHistory or {}

    -- Initialize CR, MMR, and played values if they don't exist
    Database.CurrentCRforSoloShuffle = Database.CurrentCRforSoloShuffle or 0
    Database.CurrentMMRforSoloShuffle = Database.CurrentMMRforSoloShuffle or 0
    Database.CurrentCRfor2v2 = Database.CurrentCRfor2v2 or 0
    Database.CurrentMMRfor2v2 = Database.CurrentMMRfor2v2 or 0
    Database.CurrentCRfor3v3 = Database.CurrentCRfor3v3 or 0
    Database.CurrentMMRfor3v3 = Database.CurrentMMRfor3v3 or 0
    Database.CurrentCRforRBG = Database.CurrentCRforRBG or 0
    Database.CurrentMMRforRBG = Database.CurrentMMRforRBG or 0
    Database.CurrentCRforSoloRBG = Database.CurrentCRforSoloRBG or 0
    Database.CurrentMMRforSoloRBG = Database.CurrentMMRforSoloRBG or 0

    -- Initialize played values if they don't exist
    Database.PlayedforSoloShuffle = Database.PlayedforSoloShuffle or 0
    Database.Playedfor2v2 = Database.Playedfor2v2 or 0
    Database.Playedfor3v3 = Database.Playedfor3v3 or 0
    Database.PlayedforRBG = Database.PlayedforRBG or 0
    Database.PlayedforSoloRBG = Database.PlayedforSoloRBG or 0

    return true
end

-- Define a function to clear the database, only use to debug
function ClearDatabase()
    RSTATS_Database = {}
    RSTATS.Database[playerName] = {}
    Database = {}
    RSTATS.Config = {}
end

-- Function to get CR and MMR based on categoryID
function GetCRandMMR(categoryID)
    local cr = select(1, GetPersonalRatedInfo(categoryID))
    local mmr = select(10, GetPersonalRatedInfo(categoryID))
    return cr, mmr
end

function IsDataValid()

    -- Check if Database is a table
    if not Database or type(Database) ~= "table" then
        return false
    end

    -- Check that at least one history table is **not empty**
    local function hasHistoryEntries(historyTable)
        return type(historyTable) == "table" and #historyTable > 0
    end

    if not hasHistoryEntries(Database.SoloShuffleHistory) and
       not hasHistoryEntries(Database.v2History) and
       not hasHistoryEntries(Database.v3History) and
       not hasHistoryEntries(Database.RBGHistory) and
       not hasHistoryEntries(Database.SoloRBGHistory) then
        return false  -- Data is NOT valid if there's no match history
    end

    -- Check CR/MMR values
    if type(Database.CurrentCRforSoloShuffle) ~= "number" or
       type(Database.CurrentMMRforSoloShuffle) ~= "number" then
        return false
    end

    if type(Database.CurrentCRfor2v2) ~= "number" or
       type(Database.CurrentMMRfor2v2) ~= "number" then
        return false
    end

    if type(Database.CurrentCRfor3v3) ~= "number" or
       type(Database.CurrentMMRfor3v3) ~= "number" then
        return false
    end

    if type(Database.CurrentCRforRBG) ~= "number" or
       type(Database.CurrentMMRforRBG) ~= "number" then
        return false
    end

    if type(Database.CurrentCRforSoloRBG) ~= "number" or
       type(Database.CurrentMMRforSoloRBG) ~= "number" then
        return false
    end

    return true
end

local function GetCurrentMapID()
    local _, _, _, _, _, _, _, instanceMapID = GetInstanceInfo()
    return instanceMapID
end

-- Helper functions to get map names and colors
local function GetMapName(mapID)
    -- Try to get the name from RSTATS.MapList
    local map = RSTATS.MapList[mapID]
    
    -- If not found, fall back to the Blizzard API function GetRealZoneText
    if not map or map == "" then
        map = GetRealZoneText(mapID)
    end
    
    -- If still not found, return "Unknown Map" instead of "E..."
    if not map or map == "" then
        return "Unknown Map"
    end
    
    return map
end

local function GetShortMapName(mapName)
    local mapNameTemp = {strsplit(" ", mapName)}
    local mapShortName = ""
    for i=1, #mapNameTemp do
        mapShortName = mapShortName..strsub(mapNameTemp[i],1,1)
    end
    return mapShortName
end

RSTATS.MapList = {
    [30] = GetRealZoneText(30),
    [2107] = GetRealZoneText(2107),
    [1191] = GetRealZoneText(1191),
    [1691] = GetRealZoneText(1691),
    [2245] = GetRealZoneText(2245),
    [1105] = GetRealZoneText(1105),
    [566] = GetRealZoneText(566),
    [968] = GetRealZoneText(566),
    [628] = GetRealZoneText(628),
    [727] = GetRealZoneText(727),
    [607] = GetRealZoneText(607),
    [1035] = GetRealZoneText(1035),
    [761] = GetRealZoneText(761),
    [726] = GetRealZoneText(726),
    [2106] = GetRealZoneText(2106),
    [1280] = GetRealZoneText(1280),
    [1803] = GetRealZoneText(1803),
    [2118] = GetRealZoneText(2118),
    [1552] = GetShortMapName(GetRealZoneText(1552)),
    [1504] = GetShortMapName(GetRealZoneText(1504)),
    [562] = GetShortMapName(GetRealZoneText(1672)),
    [1672] = GetShortMapName(GetRealZoneText(1672)),
    [2547] = GetShortMapName(GetRealZoneText(2547)),
    [2373] = GetShortMapName(GetRealZoneText(2373)),
    [617] = GetShortMapName(GetRealZoneText(617)),
    [559] = GetShortMapName(GetRealZoneText(1505)),
    [1505] = GetShortMapName(GetRealZoneText(1505)),
    [572] = GetShortMapName(GetRealZoneText(572)),
    [1134] = GetShortMapName(GetRealZoneText(1134)),
    [980] = GetShortMapName(GetRealZoneText(980)),
    [1911] = GetShortMapName(GetRealZoneText(1911)),
    [1825] = GetShortMapName(GetRealZoneText(1825)),
    [2167] = GetShortMapName(GetRealZoneText(2167)),
    [2509] = GetShortMapName(GetRealZoneText(2509)),
    [2563] = GetShortMapName(GetRealZoneText(2563))
}

-- Register events to dynamically track raid leader
local raidLeaderFrame = CreateFrame("Frame")
raidLeaderFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
raidLeaderFrame:RegisterEvent("PARTY_LEADER_CHANGED")

local friendlyRaidLeader = "N/A"

local function UpdateFriendlyRaidLeader()
    local foundLeader = false
    for i = 1, GetNumGroupMembers() do
        local unit = "raid" .. i
        if UnitIsGroupLeader(unit) then
            local name, realm = UnitName(unit)
            if name then
                if realm and realm ~= "" then
                    name = name .. "-" .. realm
                else
                    name = name .. "-" .. GetRealmName()
                end
                friendlyRaidLeader = name
                foundLeader = true
                break
            end
        end
    end
    if not foundLeader then
        friendlyRaidLeader = "N/A"
    end
end

raidLeaderFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "GROUP_ROSTER_UPDATE" or event == "PARTY_LEADER_CHANGED" then
        UpdateFriendlyRaidLeader()
    end
end)

local function UnregisterRaidLeaderEvents()
    raidLeaderFrame:UnregisterEvent("GROUP_ROSTER_UPDATE")
    raidLeaderFrame:UnregisterEvent("PARTY_LEADER_CHANGED")
end

-- Function to get the full player name including realm
local function GetFullPlayerName(unit)
    local name, realm = UnitName(unit)
    if realm and realm ~= "" then
        return name .. "-" .. realm
    else
        return name .. "-" .. GetRealmName()
    end
end

-- Function to get the enemy raid leader's name
local function GetEnemyRaidLeaderName(enemyFaction, enemyPlayers)
    local enemyRaidLeader = "defaultERL"

    -- Iterate through the existing enemyPlayers table to identify the raid leader
    for _, player in ipairs(enemyPlayers) do
        if player.role == "RAID_LEADER" then
            enemyRaidLeader = player.name
            break
        end
    end

    -- If no raid leader was found, default to the first enemy player
    if enemyRaidLeader == "defaultERL" and #enemyPlayers > 0 then
        enemyRaidLeader = enemyPlayers[1].name
    end

    return enemyRaidLeader
end

local columns = C_PvP.GetMatchPVPStatColumns()
for _, column in ipairs(columns) do
end

-- Create a frame to register events
local frame = CreateFrame("Frame")
frame:RegisterEvent("PVP_MATCH_ACTIVE")
frame:RegisterEvent("PVP_MATCH_COMPLETE")
frame:RegisterEvent("UPDATE_UI_WIDGET")

local inPvPMatch = false  -- Track if we are in a PvP match

frame:SetScript("OnEvent", function(_, event, widgetID)
    if event == "PVP_MATCH_ACTIVE" then
        inPvPMatch = true
    elseif event == "PVP_MATCH_COMPLETE" then
        inPvPMatch = false
    elseif event == "UPDATE_UI_WIDGET" and inPvPMatch and type(widgetID) == "number" then
        -- Fetch the widget data based on the widgetID
        local widgetData = C_UIWidgetManager.GetDoubleStatusBarWidgetVisualizationInfo(widgetInfo.widgetID)
        if widgetData then
            TrackScores(widgetID)
        else
        end
    end
end)

-- Function to print specific DoubleStatusBar widgets in a PvP instance
function PrintAllWidgets()
    local inInstance, instanceType = IsInInstance()
    if not (inInstance and (instanceType == "pvp" or instanceType == "arena")) then
        return
    end

    -- Loop over a large range of possible widget IDs
    for i = 1, 10000 do
        local widgetInfo = C_UIWidgetManager.GetDoubleStatusBarWidgetVisualizationInfo(i)
        if widgetInfo then
            local widgetID = widgetInfo.widgetID
            -- Check for known DoubleStatusBar widget IDs related to battleground scoring
            if widgetID == 1671 or widgetID == 2074 or widgetID == 1681 then
                local data = C_UIWidgetManager.GetDoubleStatusBarWidgetVisualizationInfo(widgetID)
                if data then
                else
                end
            end
        end
    end
end

-- Manually call this function whenever you're in a battleground.
PrintAllWidgets()

local function StartPrintingWidgets()
    if not C_PvP.IsBattleground() then return end
    C_Timer.NewTicker(60, PrintAllWidgets)  -- Print widgets every 60 seconds
end

-- Start when you enter a battleground
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_BATTLEGROUND")
frame:SetScript("OnEvent", StartPrintingWidgets)

local function IsInPvPMatch()
    return C_PvP.IsRatedBattleground() or C_PvP.IsBattleground() or C_PvP.IsSoloRBG()
end

-- Table to store scores
local RSTATS_ScoreHistory = {}
local allianceTeamScore = 0
local hordeTeamScore = 0
local roundsWon = 0

local RBGScoreWidgets = {
    [529]  = 1671, -- Arathi Basin
    [275]  = 1671, -- Battle for Gilneas
    [566]  = 1671, -- Eye of the Storm
    [998]  = 2929, -- Temple of Kotmogu
    [837]  = 2,    -- Warsong Gulch
    [626]  = 2,    -- Twin Peaks
    [856]  = 2074, -- Deepwind Gorge
    [2345] = 5153, -- Deephaul Ravine
    [643]  = 2928, -- Silvershard Mines
}

local SoloRBGScoreWidgets = {
    [2107]  = 1671, -- Arathi Basin
    [761]  = 1671, -- Battle for Gilneas
    [968]  = 1671, -- Eye of the Storm
    [998]  = 1689, -- Temple of Kotmogu
    [2106]  = 2,    -- Warsong Gulch
    [726]  = 2,    -- Twin Peaks
    [2245]  = 2074, -- Deepwind Gorge
    [2656] = 5153, -- Deephaul Ravine
    [727]  = 1687, -- Silvershard Mines
}

-- Function to get scores for resource-based maps
function GetScores(widgetInfo)
    if not widgetInfo or not widgetInfo.widgetID then return end

    local mapID = GetCurrentMapID()
    if not mapID then return end

    -- Get expected widgetID based on mode
    local widgetID
    if C_PvP.IsSoloRBG then
        widgetID = SoloRBGScoreWidgets[mapID]
    elseif C_PvP.IsRatedBattleground() then
        widgetID = RBGScoreWidgets[mapID]
    end

    if widgetID and widgetInfo.widgetID == widgetID then
        local dataTbl = C_UIWidgetManager.GetDoubleStatusBarWidgetVisualizationInfo(widgetInfo.widgetID)
        if dataTbl and dataTbl.leftBarMax then
            allianceTeamScore = dataTbl.leftBarValue
            hordeTeamScore = dataTbl.rightBarValue
        end
    end
end

-- Event handler for capturing widget updates
local function OnWidgetUpdate(_, event, widgetInfo)
    if event == "UPDATE_UI_WIDGET" and IsInPvPMatch() then
        GetScores(widgetInfo)
    end
end

-- Main frame for registering events
local frame = CreateFrame("Frame")
frame:RegisterEvent("PVP_MATCH_ACTIVE")
frame:RegisterEvent("PVP_MATCH_COMPLETE")
frame:RegisterEvent("UPDATE_UI_WIDGET")
frame:SetScript("OnEvent", OnWidgetUpdate)

local function GetPlayerStatsEndOfMatch(cr, mmr, historyTable, roundIndex, categoryName, categoryID, startTime)
    local mapID = GetCurrentMapID()
    local mapName = GetMapName(mapID) or "Unknown"
    local endTime = GetTimestamp()
    local teamFaction = GetPlayerFactionGroup()  -- Returns "Horde" or "Alliance"
    local enemyFaction = teamFaction == "Horde" and "Alliance" or "Horde"  -- Opposite faction
    local friendlyTotalDamage, friendlyTotalHealing, enemyTotalDamage, enemyTotalHealing = 0, 0, 0, 0
    local battlefieldWinner = GetBattlefieldWinner() == 0 and "Horde" or "Alliance"  -- Convert to "Horde" or "Alliance"
    local friendlyWinLoss = battlefieldWinner == teamFaction and "+   W" or "+   L"  -- Determine win/loss status
	local previousRoundsWon = previousRoundsWon or 0
    local roundsWon = roundsWon or 0
	local duration = GetBattlefieldInstanceRunTime() / 1000  -- duration in seconds
	local damp = C_Commentator.GetDampeningPercent()
	
	if C_PvP.IsRatedSoloShuffle() and roundIndex then
		local totalPreviousDuration = 0
		local totalRoundsToLookBack = roundIndex - 1

		-- Sum durations of previous rounds
		for i = #historyTable, 1, -1 do
			local entry = historyTable[i]
			if entry and entry.duration and totalRoundsToLookBack > 0 and type(entry.duration) == "number" then
				totalPreviousDuration = totalPreviousDuration + entry.duration
				totalRoundsToLookBack = totalRoundsToLookBack - 1
			end
		end
	
		duration = endTime - startTime - totalPreviousDuration
	end


	
	-- Delay storing played games by 5 seconds to give the API time to update
	C_Timer.After(5, function()
		local function GetPlayedGames(categoryID)
			return select(4, GetPersonalRatedInfo(categoryID))
		end
	
		local played = GetPlayedGames(categoryID)
	
		-- Store played games per bracket
		local playedField = "Playedfor" .. categoryName
		Database[playedField] = played

---		print("|cff00ff00[Debug]|r Played games for |cffadd8e6" .. categoryName .. "|r on this update: |cffffff00" .. played .. "|r")

		SaveData() -- Optional: Save again to lock in the new count
	end)
	
	if C_PvP.IsRatedSoloShuffle() then
		if roundIndex == 6 and roundsWon == 3 then
			friendlyWinLoss = "RND " .. roundIndex .. "  ~   D"
		elseif roundsWon > previousRoundsWon then
			friendlyWinLoss = "RND " .. roundIndex .. "  +   W"
		elseif roundIndex == nil then
			roundIndex = 1
			friendlyWinLoss = "RND " .. roundIndex .. "  +   L"
		else
			friendlyWinLoss = "RND " .. roundIndex .. "  +   L"
		end
	end

    -- Calculate total damage and healing for friendly and enemy teams
    for i = 1, GetNumBattlefieldScores() do
        local scoreInfo = C_PvP.GetScoreInfo(i)
        if scoreInfo then
            local name = scoreInfo.name
            local killingBlows = scoreInfo.killingBlows
            local honorableKills = scoreInfo.honorableKills
            local deaths = scoreInfo.deaths
            local honorGained = scoreInfo.honorGained
            local faction = scoreInfo.faction
            local raceName = scoreInfo.raceName
            local className = scoreInfo.className
            local classToken = scoreInfo.classToken
            local damageDone = scoreInfo.damageDone
            local healingDone = scoreInfo.healingDone
            local rating = scoreInfo.rating
            local ratingChange = scoreInfo.ratingChange
            local prematchMMR = scoreInfo.prematchMMR
            local mmrChange = scoreInfo.mmrChange
            local postmatchMMR = scoreInfo.postmatchMMR
            local talentSpec = scoreInfo.talentSpec
            local honorLevel = scoreInfo.honorLevel
            local roleAssigned = scoreInfo.roleAssigned
            local stats = scoreInfo.stats

            -- Ensure damageDone and healingDone are numbers
            damageDone = tonumber(damageDone) or 0
            healingDone = tonumber(healingDone) or 0

            if faction == teamFaction then
                friendlyTotalDamage = friendlyTotalDamage + damageDone
                friendlyTotalHealing = friendlyTotalHealing + healingDone
            elseif faction == enemyFaction then
                enemyTotalDamage = enemyTotalDamage + damageDone
                enemyTotalHealing = enemyTotalHealing + healingDone
            end
        end
    end

    -- Debug: Print final team scores before saving

    -- Unregister the events after obtaining the raid leader information
    UnregisterRaidLeaderEvents()

    AppendHistory(historyTable, roundIndex, cr, mmr, mapName, endTime, duration, teamFaction, enemyFaction, friendlyTotalDamage, friendlyTotalHealing, enemyTotalDamage, enemyTotalHealing, friendlyWinLoss, friendlyRaidLeader, enemyRaidLeader, friendlyRatingChange, enemyRatingChange, allianceTeamScore, hordeTeamScore, roundsWon, categoryName, categoryID, damp)

    SaveData() -- Updated to call SaveData function
end

-- Function to detect if the current match is Solo Shuffle based on the map name
local function IsSoloShuffleMatch()
    local mapName = GetRealZoneText()

    if mapName == "Solo Shuffle" then
        return true
    else
        return false
    end
end

function RefreshDataEvent(self, event, ...)

	local roundWasWon = false

    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(3, function()
            local dataExists = LoadData()
            local isValidData = IsDataValid()

            if not dataExists or not isValidData and (select(1, GetPersonalRatedInfo(7))) ~= 0 then
                GetInitialCRandMMR()
			else
				CheckForMissedGames()
            end
			
            -- SAFELY detect Solo Shuffle and set startTime
            if C_PvP.IsRatedSoloShuffle and C_PvP.IsRatedSoloShuffle() then
                startTime = GetTimestamp()
            end
        end)
				
    elseif event == "PVP_MATCH_ACTIVE" then
        C_Timer.After(1, function()
            if C_PvP.IsRatedSoloShuffle() then
                self.isSoloShuffle = true
					if self.isSoloShuffle and roundIndex and not playerDeathSeen then		
						local cr, mmr = GetCRandMMR(7)
						local historyTable = Database.SoloShuffleHistory
						Database.CurrentCRforSoloShuffle = cr
						Database.CurrentMMRforSoloShuffle = mmr
						GetPlayerStatsEndOfMatch(cr, mmr, historyTable, roundIndex, "SoloShuffle", 7, startTime)
					
						if roundIndex < 6 then roundIndex = roundIndex + 1 end
					end

                previousRoundsWon = roundsWon or 0
                if roundIndex == nil then
                    roundIndex = 1
                end
                lastLoggedRound = {}
                playerDeathSeen = false
            else
                self.isSoloShuffle = nil
            end
        end)

    elseif self.isSoloShuffle and (event == "UNIT_HEALTH" or event == "UNIT_AURA" or event == "COMBAT_LOG_EVENT_UNFILTERED") then

        confirmedDeaths = confirmedDeaths or {}

        local function IsRecentlyConfirmed(player)
            return confirmedDeaths[player] and GetTime() < confirmedDeaths[player]
        end

		local function IsFeignDeath(unit)
			if UnitIsFeignDeath(unit) then return true end
			for i = 1, 40 do
				local name, _, _, _, _, _, _, _, _, spellId = UnitAura(unit, i, "HELPFUL")
				if not name then break end
				if spellId == 5384 then
					return true
				end
			end
			return false
		end

        local function ProcessPlayerDeath(name)
            playerDeathSeen = true

            local cr, mmr = GetCRandMMR(7)
            local historyTable = Database.SoloShuffleHistory
            Database.CurrentCRforSoloShuffle = cr
            Database.CurrentMMRforSoloShuffle = mmr
            GetPlayerStatsEndOfMatch(cr, mmr, historyTable, roundIndex, "SoloShuffle", 7, startTime)

            if roundIndex < 6 then roundIndex = roundIndex + 1 end
        end

		if event == "UNIT_HEALTH" then
			local unit = ...
			if not unit or not UnitExists(unit) then return end
			if not (unit == "player" or unit:match("^party[1-3]$") or unit:match("^arena[1-3]$")) then return end
		
			if UnitIsPlayer(unit) and UnitIsDeadOrGhost(unit) then
				C_Timer.After(0.05, function()
					local isFeign = IsFeignDeath(unit)
		
					local unitName = UnitName(unit)
					local player = unitName and unitName:match("([^%-]+)")
		
					if not isFeign and unitName then
						if not IsRecentlyConfirmed(player) and lastLoggedRound[player] ~= roundIndex then
							lastLoggedRound[player] = roundIndex
							confirmedDeaths[player] = GetTime() + 3
							ProcessPlayerDeath(player)
						end
					elseif isFeign then
					end
				end)
			end
		end

		if event == "COMBAT_LOG_EVENT_UNFILTERED" then
			local _, subEvent, _, _, sourceName, _, _, destGUID, destName, destFlags, _, _, _, overkill = CombatLogGetCurrentEventInfo()
	
			-- ✅ WIN: Party kill against a real player
			if subEvent == "PARTY_KILL" and bit.band(destFlags or 0, COMBATLOG_OBJECT_TYPE_PLAYER) > 0 then
				previousRoundsWon = roundsWon or 0
				roundsWon = (roundsWon or 0) + 1
			end
		end

    elseif event == "PVP_MATCH_COMPLETE" then
        C_Timer.After(1, function()
            if self.isSoloShuffle then
                if roundIndex and not playerDeathSeen then
                    local cr, mmr = GetCRandMMR(7)
                    local historyTable = Database.SoloShuffleHistory
                    Database.CurrentCRforSoloShuffle = cr
                    Database.CurrentMMRforSoloShuffle = mmr
                    GetPlayerStatsEndOfMatch(cr, mmr, historyTable, roundIndex or 6, "SoloShuffle", 7, startTime)
                else
                end

                -- Cleanup
                self.isSoloShuffle = nil
                roundIndex = nil
                roundsWon = nil
                previousRoundsWon = nil
                playerDeathSeen = false
            elseif C_PvP.IsRatedArena() then
                local matchBracket = C_PvP.GetActiveMatchBracket()
                if matchBracket == 0 then
                    local cr, mmr = GetCRandMMR(1)
                    local historyTable = Database.v2History
                    Database.CurrentCRfor2v2 = cr
                    Database.CurrentMMRfor2v2 = mmr
                    GetPlayerStatsEndOfMatch(cr, mmr, historyTable, nil, "2v2", 1)
                elseif matchBracket == 1 then
                    local cr, mmr = GetCRandMMR(2)
                    local historyTable = Database.v3History
                    Database.CurrentCRfor3v3 = cr
                    Database.CurrentMMRfor3v3 = mmr
                    GetPlayerStatsEndOfMatch(cr, mmr, historyTable, nil, "3v3", 2)
                end
            elseif C_PvP.IsRatedBattleground() then
                local cr, mmr = GetCRandMMR(4)
                local historyTable = Database.RBGHistory
                Database.CurrentCRforRBG = cr
                Database.CurrentMMRforRBG = mmr
                GetPlayerStatsEndOfMatch(cr, mmr, historyTable, nil, "RBG", 4)
            elseif C_PvP.IsSoloRBG() then
                local cr, mmr = GetCRandMMR(9)
                local historyTable = Database.SoloRBGHistory
                Database.CurrentCRforSoloRBG = cr
                Database.CurrentMMRforSoloRBG = mmr
                GetPlayerStatsEndOfMatch(cr, mmr, historyTable, nil, "SoloRBG", 9)
            end
        end)
    end
end

-- Define global update functions
function UpdateSoloShuffleDisplay()
    if content1 then
        DisplayCurrentCRMMR(content1, 7)
    end
end

function Update2v2Display()
    if content2 then
        DisplayCurrentCRMMR(content2, 1)
    end
end

function Update3v3Display()
    if content3 then
        DisplayCurrentCRMMR(content3, 2)
    end
end

function UpdateRBGDisplay()
    if content4 then
        DisplayCurrentCRMMR(content4, 4)
    end
end

function UpdateSoloRBGDisplay()
    if content5 then
        DisplayCurrentCRMMR(content5, 9)
    end
end

local function GetPlayerRole()
    local role = UnitGroupRolesAssigned("player")
    
    if role and role ~= "NONE" then
        return role
    else
        -- Fallback to spec-based role determination
        local specIndex = GetSpecialization()
        if not specIndex then
            return "UNKNOWN"
        end

        local specID = GetSpecializationInfo(specIndex)
        if not specID then
            return "UNKNOWN"
        end

        local specRoleMap = {
            -- Death Knight
            [250] = 2,       -- Blood Death Knight (TANK)
            [251] = 8,       -- Frost Death Knight (DPS)
            [252] = 8,       -- Unholy Death Knight (DPS)
        
            -- Demon Hunter
            [577] = 8,       -- Havoc Demon Hunter (DPS)
            [581] = 2,       -- Vengeance Demon Hunter (TANK)
        
            -- Druid
            [102] = 8,       -- Balance Druid (DPS)
            [103] = 8,       -- Feral Druid (DPS)
            [104] = 2,       -- Guardian Druid (TANK)
            [105] = 4,       -- Restoration Druid (HEALER)
        
            -- Evoker
            [1467] = 8,      -- Devastation Evoker (DPS)
            [1468] = 4,      -- Preservation Evoker (HEALER)
            [1473] = 2,      -- Augmentation Evoker (TANK)
        
            -- Hunter
            [253] = 8,       -- Beast Mastery Hunter (DPS)
            [254] = 8,       -- Marksmanship Hunter (DPS)
            [255] = 8,       -- Survival Hunter (DPS)
        
            -- Mage
            [62] = 8,        -- Arcane Mage (DPS)
            [63] = 8,        -- Fire Mage (DPS)
            [64] = 8,        -- Frost Mage (DPS)
        
            -- Monk
            [268] = 2,       -- Brewmaster Monk (TANK)
            [270] = 4,       -- Mistweaver Monk (HEALER)
            [269] = 8,       -- Windwalker Monk (DPS)
        
            -- Paladin
            [65] = 4,        -- Holy Paladin (HEALER)
            [66] = 2,        -- Protection Paladin (TANK)
            [70] = 8,        -- Retribution Paladin (DPS)
        
            -- Priest
            [256] = 4,       -- Discipline Priest (HEALER)
            [257] = 4,       -- Holy Priest (HEALER)
            [258] = 8,       -- Shadow Priest (DPS)
        
            -- Rogue
            [259] = 8,       -- Assassination Rogue (DPS)
            [260] = 8,       -- Outlaw Rogue (DPS)
            [261] = 8,       -- Subtlety Rogue (DPS)
        
            -- Shaman
            [262] = 8,       -- Elemental Shaman (DPS)
            [263] = 8,       -- Enhancement Shaman (DPS)
            [264] = 4,       -- Restoration Shaman (HEALER)
        
            -- Warlock
            [265] = 8,       -- Affliction Warlock (DPS)
            [266] = 8,       -- Demonology Warlock (DPS)
            [267] = 8,       -- Destruction Warlock (DPS)
        
            -- Warrior
            [71] = 8,        -- Arms Warrior (DPS)
            [72] = 8,        -- Fury Warrior (DPS)
            [73] = 2         -- Protection Warrior (TANK)
        }

        return specRoleMap[specID] or "UNKNOWN"
    end
end

-- Function to get initial and current CR and MMR values
function GetInitialCRandMMR()
    -- Define category mappings with history table names and display names
    local categoryMappings = {
        SoloShuffle = { id = 7, historyTable = "SoloShuffleHistory", displayName = "SoloShuffle" },
        ["2v2"] = { id = 1, historyTable = "v2History", displayName = "2v2" },
        ["3v3"] = { id = 2, historyTable = "v3History", displayName = "3v3" },
        RBG = { id = 4, historyTable = "RBGHistory", displayName = "RBG" },
        SoloRBG = { id = 9, historyTable = "SoloRBGHistory", displayName = "SoloRBG" }
    }

    -- Helper functions to get CR, MMR, and played games
    local function GetInitialCR(categoryID)
        return select(1, GetPersonalRatedInfo(categoryID))
    end

    local function GetInitialMMR(categoryID)
        return select(10, GetPersonalRatedInfo(categoryID))
    end

    local function GetPlayedGames(categoryID)
        return select(4, GetPersonalRatedInfo(categoryID))
    end

    -- Get the player's full name (character-realm)
    local playerFullName = GetPlayerFullName()

    -- Define a function to store the initial CR, MMR, and played games
    local function StoreInitialCRMMRandPlayed(categoryName)
        local categoryInfo = categoryMappings[categoryName]
        if not categoryInfo then
            return
        end

        local categoryID = categoryInfo.id
        local historyTableName = categoryInfo.historyTable
        local displayName = categoryInfo.displayName

        -- Ensure the history table exists
        if not Database[historyTableName] then
            Database[historyTableName] = {}
        end

        -- Get initial CR, MMR, and played games
        local cr = GetInitialCR(categoryID)
        local mmr = GetInitialMMR(categoryID)
        local played = GetPlayedGames(categoryID)

		-- Store played games per bracket
		local playedField = "Playedfor" .. categoryName
		Database[playedField] = played

        -- Create an entry with the current timestamp
        local entry = {
			matchID = 1,
            timestamp = GetTimestamp(),
            cr = cr,
            mmr = mmr,
            isInitial = true,
            winLoss = "I",  -- Initial
			friendlyWinLoss = "I",
            mapName = "N/A",
            endTime = GetTimestamp(),
            duration = "N/A",
            teamFaction = UnitFactionGroup("player"),
            friendlyRaidLeader = playerFullName, -- Set to the player's full name
            friendlyAvgCR = cr,
            friendlyMMR = mmr,
            friendlyTotalDamage = "-",
            friendlyTotalHealing = "-",
            friendlyRatingChange = "-",
            enemyFaction = "-",
            enemyRaidLeader = "-",
            enemyAvgCR = "-",
            enemyMMR = "-",
            enemyTotalDamage = "-",
            enemyTotalHealing = "-",
            enemyRatingChange = "-",
            playerStats = {
                {
                    name = playerFullName,
                    originalFaction = UnitFactionGroup("player"),
                    race = UnitRace("player"),
                    class = UnitClass("player"),
                    spec = GetSpecialization() and select(2, GetSpecializationInfo(GetSpecialization())) or "N/A",
                    role = GetPlayerRole(),
                    newrating = cr,
                    killingBlows = "-",
                    honorableKills = "-",
                    damage = "-",
                    healing = "-",
                    ratingChange = "-"
                },
            }
        }
        
        -- Repeat the enemy placeholder for the second half of the row
        for i = 1, 1 do
			table.insert(entry.playerStats, {
				name = "-",
				originalFaction = "-",
				race = "-",
				class = "-",
				spec = "-",
				role = "-",
				newrating = "-",
				killingBlows = "-",
				honorableKills = "-",
				damage = "-",
				healing = "-",
				ratingChange = "-"
			})
		end

        -- Insert the entry into the history table
        table.insert(Database[historyTableName], 1, entry)

    end

    -- Iterate over categories and store initial CR, MMR, and played games
    for categoryName in pairs(categoryMappings) do
        StoreInitialCRMMRandPlayed(categoryName)
    end

    SaveData()
end

-- Helper function to get player full name
function GetPlayerFullName()
    local name = UnitName("player")
    local realm = GetRealmName()
    return name .. "-" .. realm
end

function CheckForMissedGames()
---    local function Log(msg)
---        -- Green [Debug] label, yellow message
---        print("|cff00ff00[Debug]|r " .. "|cffffff00" .. msg .. "|r")
---    end

---    Log("CheckForMissedGames triggered.")

    local categoryMappings = {
        SoloShuffle = { id = 7, historyTable = "SoloShuffleHistory", displayName = "SoloShuffle" },
        ["2v2"] = { id = 1, historyTable = "v2History", displayName = "2v2" },
        ["3v3"] = { id = 2, historyTable = "v3History", displayName = "3v3" },
        RBG = { id = 4, historyTable = "RBGHistory", displayName = "RBG" },
        SoloRBG = { id = 9, historyTable = "SoloRBGHistory", displayName = "SoloRBG" }
    }

	local function StoreMissedGame(categoryName, category, attempts)
		local _, _, _, totalGames = GetPersonalRatedInfo(category.id)
		attempts = attempts or 0
		
		if not totalGames or totalGames == 0 then
			if attempts < 10 then
---			Log("Skipped category ID " .. category.id .. " — totalGames is nil.")
				C_Timer.After(3, function()
					StoreMissedGame(categoryName, category, attempts + 1)
				end)
			end
			return
		end
	
		local playedField = "Playedfor" .. categoryName
	
		local lastRecorded = Database[playedField]
		local historyTable = Database[category.historyTable]
	
---		Log(string.format("Checking category ID %d | Last Recorded: %d | Total Games: %d", category.id, lastRecorded, totalGames))
	
		if totalGames > lastRecorded then
			local currentCR, currentMMR = GetCRandMMR(category.id)
	
---			Log(string.format("Missed game detected in category ID %d | Previous CR: %d | Current CR: %d | Change: %+d", category.id, previousCR, currentCR, crChange))
	
			local highestMatchID = 0
			for _, entry in ipairs(historyTable) do
				if entry.matchID and tonumber(entry.matchID) > highestMatchID then
					highestMatchID = tonumber(entry.matchID)
					previousCR = entry.cr
				end
			end

			local crChange = currentCR - previousCR
			local matchID = highestMatchID + 1
	
			local entry = {
				matchID = matchID,
				isMissedGame = true,
				winLoss = "Missed Game",
				friendlyWinLoss = "Missed Game",  -- ✅ Add this
				timestamp = GetTimestamp(),
				rating = currentCR,
				postMatchMMR = currentMMR,
				ratingChange = crChange,
				note = "Disconnected or Crashed, Missing Data",
			
				mapName = "N/A",
				endTime = GetTimestamp(),
				duration = "N/A",
				teamFaction = UnitFactionGroup("player"),
				friendlyRaidLeader = GetPlayerFullName(),
				friendlyAvgCR = currentCR,
				friendlyMMR = currentMMR,
				friendlyTotalDamage = "-",
				friendlyTotalHealing = "-",
				friendlyRatingChange = crChange,
				enemyFaction = "-",
				enemyRaidLeader = "-",
				enemyAvgCR = "-",
				enemyMMR = "-",
				enemyTotalDamage = "-",
				enemyTotalHealing = "-",
				enemyRatingChange = "-",
				playerStats = {
					{
						name = GetPlayerFullName(),
						originalFaction = UnitFactionGroup("player"),
						race = UnitRace("player"),
						class = UnitClass("player"),
						spec = GetSpecialization() and select(2, GetSpecializationInfo(GetSpecialization())) or "N/A",
						role = GetPlayerRole(),
						newrating = currentCR,
						killingBlows = "-",
						honorableKills = "-",
						damage = "-",
						healing = "-",
						ratingChange = crChange
					},
				}
			}
			
			-- Repeat the enemy placeholder for the second half of the row
			for i = 1, 1 do
				table.insert(entry.playerStats, {
					name = "-",
					originalFaction = "-",
					race = "-",
					class = "-",
					spec = "-",
					role = "-",
					newrating = "-",
					killingBlows = "-",
					honorableKills = "-",
					damage = "-",
					healing = "-",
					ratingChange = "-"
				})
			end
	
			table.insert(historyTable, 1, entry)
---			Log("Inserted missed match entry for category ID " .. category.id)
		else
---			Log("No missed game in category ID " .. category.id .. ". Syncing played count.")
		end
	
		-- Sync played count
		Database[playedField] = totalGames
	end

	for categoryName, category in pairs(categoryMappings) do
		StoreMissedGame(categoryName, category)
	end
	
	SaveData()
---	Log("CheckForMissedGames completed.")
end

-- Initialize the Roles table
local function InitializeRoles()
    local GetNumSpecializationsForClassID = GetNumSpecializationsForClassID
    local GetSpecializationInfoForClassID = GetSpecializationInfoForClassID

    RSTATS.Roles = {}
    for classID = 1, MAX_CLASSES do
        local _, classTag = GetClassInfo(classID)
        local specNum = GetNumSpecializationsForClassID(classID)
        RSTATS.Roles[classTag] = {}
        for i = 1, specNum do
            local specID, name, _, _, role = GetSpecializationInfoForClassID(classID, i)
            RSTATS.Roles[classTag][name] = { specID = specID, role = role }
        end
    end
end

-- Call InitializeRoles at the start
InitializeRoles()

local function GetPlayerSpec(unit)
    if UnitIsConnected(unit) then
        local specID = GetInspectSpecialization(unit)
        if specID and specID > 0 then
            local _, specName = GetSpecializationInfoByID(specID)
            return specName
        end
    end
    return "N/A"
end

-- Function to get the unit ID for a player name
local function GetUnitIDByName(name)
    for i = 1, GetNumGroupMembers() do
        local unit = "raid" .. i
        if UnitName(unit) == name then
            return unit
        end
    end
    return nil
end

local function FormatNumber(value)
    -- Check if the value is a number
    if type(value) ~= "number" then
        -- If not a number, return the value as is
        return tostring(value)
    end

    -- Now we know value is a number, we can safely compare it
    if value >= 1000000 then
        return string.format("%.1fM", value / 1000000)
    elseif value >= 1000 then
        return string.format("%.1fk", value / 1000)
    else
        return tostring(value)
    end
end

local roleIcons = {
    [2] = "|TInterface\\LFGFrame\\UI-LFG-ICON-ROLES:12:12:0:0:64:64:0:16:16:32|t",  -- Tank icon (Middle Left)
    [4] = "|TInterface\\LFGFrame\\UI-LFG-ICON-ROLES:12:12:0:0:64:64:16:32:0:16|t",  -- Healer icon (Top Middle)
    [8] = "|TInterface\\LFGFrame\\UI-LFG-ICON-ROLES:12:12:0:0:64:64:16:32:16:32|t",  -- DPS icon (Middle Middle)
    ["-"] = "-"  -- This will preserve the hyphen in the text
}

local roleTooltips = {
    [2] = "Tank",
    [4] = "Healer",
    [8] = "DPS",
    ["-"] = "-"  -- This will preserve the hyphen in the text
}

local factionIcons = {
    ["Horde"] = "|TInterface\\PVPFrame\\PVP-Currency-Horde:12:12:12:0:64:64:0:64:0:64|t",
    ["Alliance"] = "|TInterface\\PVPFrame\\PVP-Currency-Alliance:14:14:12:0:64:64:0:64:0:64|t",
    ["Neutral"] = "|TInterface\\Scenarios\\hordeallianceincursions:24:36:0:16:64:64:0:64:0:64|t",
    ["-"] = "-"  -- This will preserve the hyphen in the text
}

local raceIcons = {
    ["Blood Elf"] = "|TInterface\\Icons\\Achievement_Character_Bloodelf_Male.blp:12:12:0:0:64:64:0:64:0:64|t",
    ["Dark Iron Dwarf"] = "|TInterface\\Icons\\Achievement_AlliedRace_DarkIronDwarf:12:12:0:0:64:64:0:64:0:64|t",
    ["Draenei"] = "|TInterface\\Icons\\Achievement_Character_Draenei_Male.blp:12:12:0:0:64:64:0:64:0:64|t",
    ["Dracthyr"] = "|TInterface\\Icons\\UI_Dracthyr.blp:12:12:0:0:64:64:0:64:0:64|t",
    ["Dwarf"] = "|TInterface\\Icons\\Achievement_Character_Dwarf_Male.blp:12:12:0:0:64:64:0:64:0:64|t",
	["Earthen"] = "|TInterface\\CHARACTERFRAME\\TemporaryPortrait-Male-Dwarf.blp:12:12:0:0:64:64:0:64:0:64|t",
    ["Goblin"] = "|TInterface\\Icons\\achievement_Goblinhead.blp:12:12:0:0:64:64:0:64:0:64|t",
    ["Gnome"] = "|TInterface\\Icons\\Achievement_Character_Gnome_Male.blp:12:12:0:0:64:64:0:64:0:64|t",
    ["Highmountain Tauren"] = "|TInterface\\Icons\\INV_Misc_Head_Tauren_01.blp:12:12:0:0:64:64:0:64:0:64|t",
    ["Human"] = "|TInterface\\Icons\\Achievement_Character_Human_Male.blp:12:12:0:0:64:64:0:64:0:64|t",
    ["Kul Tiran"] = "|TInterface\\CHARACTERFRAME\\TemporaryPortrait-Male-KulTiran.blp:12:12:0:0:64:64:0:64:0:64|t", 
    ["Lightforged Draenei"] = "|TInterface\\CHARACTERFRAME\\TemporaryPortrait-Male-LightforgedDraenei.blp:12:12:0:0:64:64:0:64:0:64|t",
    ["Mag'har Orc"] = "|TInterface\\Icons\\ACHIEVEMENT_CHARACTER_ORC_MALE_BRN.blp:12:12:0:0:64:64:0:64:0:64|t",
    ["Mechagnome"] = "|TInterface\\Icons\\Achievement_Character_Mechagnome_Male.blp:12:12:0:0:64:64:0:64:0:64|t",
    ["Night Elf"] = "|TInterface\\Icons\\Achievement_Character_Nightelf_Male.blp:12:12:0:0:64:64:0:64:0:64|t",
    ["Nightborne"] = "|TInterface\\Icons\\INV_NightborneMale.blp:12:12:0:0:64:64:0:64:0:64|t",
    ["Orc"] = "|TInterface\\Icons\\Achievement_Character_Orc_Male.blp:12:12:0:0:64:64:0:64:0:64|t",
    ["Pandaren"] = "|TInterface\\Icons\\Achievement_Character_Pandaren_Female.blp:12:12:0:0:64:64:0:64:0:64|t",
    ["Tauren"] = "|TInterface\\Icons\\Achievement_Character_Tauren_Male.blp:12:12:0:0:64:64:0:64:0:64|t",
    ["Troll"] = "|TInterface\\Icons\\Achievement_Character_Troll_Male.blp:12:12:0:0:64:64:0:64:0:64|t",
    ["Undead"] = "|TInterface\\Icons\\Achievement_Character_Undead_Male.blp:12:12:0:0:64:64:0:64:0:64|t",
    ["Void Elf"] = "|TInterface\\Icons\\INV_Misc_Head_Elf_02.blp:12:12:0:0:64:64:0:64:0:64|t",
    ["Vulpera"] = "|TInterface\\CHARACTERFRAME\\TemporaryPortrait-Male-Vulpera.blp:12:12:0:0:64:64:0:64:0:64|t",
    ["Worgen"] = "|TInterface\\CHARACTERFRAME\\TEMPORARYPORTRAIT-MALE-WORGEN.BLP:12:12:0:0:64:64:0:64:0:64|t",
    ["Zandalari Troll"] = "|TInterface\\CHARACTERFRAME\\TemporaryPortrait-Male-ZandalariTroll.blp:12:12:0:0:64:64:0:64:0:64|t",
    ["-"] = "-"  -- This will preserve the hyphen in the text
}

local classIcons = {
    ["Warrior"] = "|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:12:12:0:0:256:256:0:64:0:64|t",        -- Row 1, Col 1
    ["Mage"] = "|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:12:12:0:0:256:256:64:128:0:64|t",          -- Row 1, Col 2
    ["Rogue"] = "|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:12:12:0:0:256:256:128:192:0:64|t",        -- Row 1, Col 3
    ["Druid"] = "|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:12:12:0:0:256:256:192:256:0:64|t",        -- Row 1, Col 4
    ["Hunter"] = "|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:12:12:0:0:256:256:0:64:64:128|t",        -- Row 2, Col 1
    ["Shaman"] = "|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:12:12:0:0:256:256:64:128:64:128|t",      -- Row 2, Col 2
    ["Priest"] = "|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:12:12:0:0:256:256:128:192:64:128|t",     -- Row 2, Col 3
    ["Warlock"] = "|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:12:12:0:0:256:256:192:256:64:128|t",    -- Row 2, Col 4
    ["Paladin"] = "|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:12:12:0:0:256:256:0:64:128:192|t",      -- Row 3, Col 1
    ["Death Knight"] = "|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:12:12:0:0:256:256:64:128:128:192|t",-- Row 3, Col 2
    ["Monk"] = "|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:12:12:0:0:256:256:128:192:128:192|t",      -- Row 3, Col 3
    ["Demon Hunter"] = "|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:12:12:0:0:256:256:192:256:128:192|t",-- Row 3, Col 4
    ["Evoker"] = "|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:12:12:0:0:256:256:0:64:192:256|t",       -- Row 4, Col 1
    ["-"] = "-"  -- This will preserve the hyphen in the text
}

local specIcons = {
    -- Death Knight
    ["Blood"] = "|TInterface\\Icons\\Spell_Deathknight_BloodPresence:12:12:0:0:64:64:0:64:0:64|t",
    ["Frost"] = "|TInterface\\Icons\\Spell_Deathknight_FrostPresence:12:12:0:0:64:64:0:64:0:64|t",
    ["Unholy"] = "|TInterface\\Icons\\Spell_Deathknight_UnholyPresence:12:12:0:0:64:64:0:64:0:64|t",

    -- Demon Hunter
    ["Havoc"] = "|TInterface\\Icons\\Ability_DemonHunter_SpecDPS:12:12:0:0:64:64:0:64:0:64|t",
    ["Vengeance"] = "|TInterface\\Icons\\Ability_DemonHunter_SpecTank:12:12:0:0:64:64:0:64:0:64|t",

    -- Druid
    ["Balance"] = "|TInterface\\Icons\\Spell_Nature_StarFall:12:12:0:0:64:64:0:64:0:64|t",
    ["Feral"] = "|TInterface\\Icons\\Ability_Druid_CatForm:12:12:0:0:64:64:0:64:0:64|t",
    ["Guardian"] = "|TInterface\\Icons\\Ability_Racial_BearForm:12:12:0:0:64:64:0:64:0:64|t",
    ["Restoration"] = "|TInterface\\Icons\\Spell_Nature_HealingTouch:12:12:0:0:64:64:0:64:0:64|t",

    -- Evoker
    ["Devastation"] = "|TInterface\\Icons\\ClassIcon_Evoker_Devastation:12:12:0:0:64:64:0:64:0:64|t",
    ["Preservation"] = "|TInterface\\Icons\\ClassIcon_Evoker_Preservation:12:12:0:0:64:64:0:64:0:64|t",
    ["Augmentation"] = "|TInterface\\Icons\\ClassIcon_Evoker_Augmentation:12:12:0:0:64:64:0:64:0:64|t",

    -- Hunter
    ["Beast Mastery"] = "|TInterface\\Icons\\Ability_Hunter_BeastMastery:12:12:0:0:64:64:0:64:0:64|t",
    ["Marksmanship"] = "|TInterface\\Icons\\Ability_Hunter_FocusedAim:12:12:0:0:64:64:0:64:0:64|t",
    ["Survival"] = "|TInterface\\Icons\\Ability_Hunter_SurvivalInstincts:12:12:0:0:64:64:0:64:0:64|t",

    -- Mage
    ["Arcane"] = "|TInterface\\Icons\\Spell_Holy_MagicalSentry:12:12:0:0:64:64:0:64:0:64|t",
    ["Fire"] = "|TInterface\\Icons\\Spell_Fire_FireBolt02:12:12:0:0:64:64:0:64:0:64|t",
    ["Frost"] = "|TInterface\\Icons\\Spell_Frost_FrostBolt02:12:12:0:0:64:64:0:64:0:64|t",

    -- Monk
    ["Brewmaster"] = "|TInterface\\Icons\\Spell_Monk_Brewmaster_Spec:12:12:0:0:64:64:0:64:0:64|t",
    ["Mistweaver"] = "|TInterface\\Icons\\Spell_Monk_MistWeaver_Spec:12:12:0:0:64:64:0:64:0:64|t",
    ["Windwalker"] = "|TInterface\\Icons\\Spell_Monk_WindWalker_Spec:12:12:0:0:64:64:0:64:0:64|t",

    -- Paladin
    ["Holy"] = "|TInterface\\Icons\\Spell_Holy_HolyBolt:12:12:0:0:64:64:0:64:0:64|t",
    ["Protection"] = "|TInterface\\Icons\\Ability_Paladin_ShieldoftheTemplar:12:12:0:0:64:64:0:64:0:64|t",
    ["Retribution"] = "|TInterface\\Icons\\Spell_Holy_AuraOfLight:12:12:0:0:64:64:0:64:0:64|t",

    -- Priest
    ["Discipline"] = "|TInterface\\Icons\\Spell_Holy_PowerWordShield:12:12:0:0:64:64:0:64:0:64|t",
    ["Holy"] = "|TInterface\\Icons\\Spell_Holy_GuardianSpirit:12:12:0:0:64:64:0:64:0:64|t",
    ["Shadow"] = "|TInterface\\Icons\\Spell_Shadow_ShadowWordPain:12:12:0:0:64:64:0:64:0:64|t",

    -- Rogue
    ["Assassination"] = "|TInterface\\Icons\\Ability_Rogue_DeadlyBrew:12:12:0:0:64:64:0:64:0:64|t",
    ["Outlaw"] = "|TInterface\\Icons\\Ability_Rogue_Waylay:12:12:0:0:64:64:0:64:0:64|t",
    ["Subtlety"] = "|TInterface\\Icons\\Ability_Stealth:12:12:0:0:64:64:0:64:0:64|t",

    -- Shaman
    ["Elemental"] = "|TInterface\\Icons\\Spell_Nature_Lightning:12:12:0:0:64:64:0:64:0:64|t",
    ["Enhancement"] = "|TInterface\\Icons\\Spell_Shaman_ImprovedStormstrike:12:12:0:0:64:64:0:64:0:64|t",
    ["Restoration"] = "|TInterface\\Icons\\Spell_Nature_MagicImmunity:12:12:0:0:64:64:0:64:0:64|t",

    -- Warlock
    ["Affliction"] = "|TInterface\\Icons\\Spell_Shadow_DeathCoil:12:12:0:0:64:64:0:64:0:64|t",
    ["Demonology"] = "|TInterface\\Icons\\Spell_Shadow_Metamorphosis:12:12:0:0:64:64:0:64:0:64|t",
    ["Destruction"] = "|TInterface\\Icons\\Spell_Shadow_RainOfFire:12:12:0:0:64:64:0:64:0:64|t",

    -- Warrior
    ["Arms"] = "|TInterface\\Icons\\Ability_Warrior_SavageBlow:12:12:0:0:64:64:0:64:0:64|t",
    ["Fury"] = "|TInterface\\Icons\\Ability_Warrior_InnerRage:12:12:0:0:64:64:0:64:0:64|t",
    ["Protection"] = "|TInterface\\Icons\\Ability_Warrior_DefensiveStance:12:12:0:0:64:64:0:64:0:64|t",

    ["-"] = "-"  -- This will preserve the hyphen in the text
}

local function CreateIconWithTooltip(parentFrame, text, tooltipText, xOffset, yOffset)
    local icon = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    icon:SetFont("Fonts\\FRIZQT__.TTF", 14)
    icon:SetText(text)
    icon:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", xOffset, yOffset)

    icon:SetScript("OnEnter", function()
        GameTooltip:SetOwner(icon, "ANCHOR_RIGHT")
        GameTooltip:SetText(tooltipText, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)

    icon:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return icon
end

-- Helper function to sanitize player names by removing region suffix, but keeping the realm
local function SanitizePlayerName(name)
    if name then
        -- Match anything before the second hyphen, which typically would be "Player-Realm-Region"
        local sanitizedName = name:match("^(.-%-.+)%-") or name
        return sanitizedName
    end
    return name
end

-- Table to store combat log events
local inPvPMatch = false  -- Flag to track if we are in a PvP match

local function OnCombatLogEvent(self, event, ...)
    if event == "PVP_MATCH_ACTIVE" then
        inPvPMatch = true
    elseif event == "PVP_MATCH_COMPLETE" then
        inPvPMatch = false
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" and inPvPMatch then
        local timestamp, subevent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, spellId, spellName = CombatLogGetCurrentEventInfo()

        -- Only handle successful spell casts
        if subevent == "SPELL_CAST_SUCCESS" then
            if sourceName then
                -- Define faction mappings for racial abilities
                local racialFactionMapping = {
                    ["Will to Survive"] = "Alliance",  -- Human
                    ["Blood Fury"] = "Horde",  -- Orc
                    ["War Stomp"] = "Horde",  -- Tauren
                    ["Stoneform"] = "Alliance",  -- Dwarf
                    ["Berserking"] = "Horde",  -- Troll
                    ["Escape Artist"] = "Alliance",  -- Gnome
                    ["Shadowmeld"] = "Alliance",  -- Night Elf
                    ["Will of the Forsaken"] = "Horde",  -- Undead
                    ["Arcane Torrent"] = "Horde",  -- Blood Elf
                    ["Gift of the Naaru"] = "Alliance",  -- Draenei
                    ["Quaking Palm"] = "Neutral",  -- Pandaren
                }

                -- Check for racial abilities
                if racialFactionMapping[spellName] then

                    local sanitizedSourceName = SanitizePlayerName(sourceName)
                    -- Store the relevant event data
                    combatLogEvents[sanitizedSourceName] = combatLogEvents[sanitizedSourceName] or {}
                    table.insert(combatLogEvents[sanitizedSourceName], {
                        spellId = spellId,
                        spellName = spellName,
                        timestamp = timestamp,
                        eventType = "Racial",
                        sourceName = sanitizedSourceName,
                        faction = racialFactionMapping[spellName],  -- Store the determined faction
                    })
                end
            end
        elseif subevent == "SPELL_SUMMON" then
            if destName == "Horde Battle Standard" or destName == "Alliance Battle Standard" then
                local bannerFaction = (destName == "Horde Battle Standard") and "Horde" or "Alliance"

                local sanitizedSourceName = SanitizePlayerName(sourceName)
                -- Store the event details, associating the banner with the player
                combatLogEvents[sanitizedSourceName] = combatLogEvents[sanitizedSourceName] or {}
                table.insert(combatLogEvents[sanitizedSourceName], {
                    spellId = spellId,
                    spellName = spellName,
                    timestamp = timestamp,
                    sourceName = sanitizedSourceName,
                    bannerFaction = bannerFaction,
                    eventType = "Summon",
                })
            end
        end
    end
end

-- Register the event handler for combat log events and PvP match start/end
local frame = CreateFrame("Frame")
frame:RegisterEvent("PVP_MATCH_ACTIVE")
frame:RegisterEvent("PVP_MATCH_COMPLETE")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:SetScript("OnEvent", OnCombatLogEvent)

-- Function to get combat log events for a specific player
function GetCombatLogEventsForPlayer(playerName)
    
    -- Sanitize the playerName to match with the stored sourceNames
    local sanitizedPlayerName = SanitizePlayerName(playerName)

    if combatLogEvents[sanitizedPlayerName] then
        for i, event in ipairs(combatLogEvents[sanitizedPlayerName]) do
        end
    else
    end
    
    return combatLogEvents[sanitizedPlayerName] or {}
end

-- Define the complete mapping for races
local raceFactionMapping = {
    ["Blood Elf"] = "Human", -- Horde to Alliance mapping
    ["Orc"] = "Human",
    ["Tauren"] = "Night Elf",
    ["Troll"] = "Night Elf",
    ["Undead"] = "Human",
    ["Goblin"] = "Gnome",
    ["Nightborne"] = "Night Elf",
    ["Highmountain Tauren"] = "Dwarf",
    ["Mag'har Orc"] = "Dwarf",
    ["Zandalari Troll"] = "Night Elf",
    ["Vulpera"] = "Gnome",

    ["Human"] = "Blood Elf", -- Alliance to Horde mapping
    ["Dwarf"] = "Orc",
    ["Night Elf"] = "Tauren",
    ["Gnome"] = "Goblin",
    ["Draenei"] = "Troll",
    ["Worgen"] = "Undead",
    ["Void Elf"] = "Nightborne",
    ["Lightforged Draenei"] = "Highmountain Tauren",
    ["Dark Iron Dwarf"] = "Mag'har Orc",
    ["Kul Tiran"] = "Zandalari Troll",
    ["Mechagnome"] = "Vulpera",
}

local racialFactionMapping = {
    ["Will to Survive"] = "Alliance",  -- Human
    ["Blood Fury"] = "Horde",  -- Orc
    ["War Stomp"] = "Horde",  -- Tauren
    ["Stoneform"] = "Alliance",  -- Dwarf
    ["Berserking"] = "Horde",  -- Troll
    ["Escape Artist"] = "Alliance",  -- Gnome
    ["Shadowmeld"] = "Alliance",  -- Night Elf
    ["Will of the Forsaken"] = "Horde",  -- Undead
    ["Arcane Torrent"] = "Horde",  -- Blood Elf
    ["Gift of the Naaru"] = "Alliance",  -- Draenei
    ["Quaking Palm"] = "Neutral",  -- Pandaren
}

-- Function to determine the original faction of a player based on their combat log events
function DetermineOriginalFaction(playerData, playerCombatLogEvents)
    
    -- Check for racial abilities in combat log events
    for _, event in ipairs(playerCombatLogEvents) do
        if event.sourceName == playerData.name then
            local combatlogfaction = racialFactionMapping[event.spellName]
            if combatlogfaction then
                return combatlogfaction, "Racial"
            end
        end
    end

    -- If no racial ability is found, check for faction banners
    for _, event in ipairs(playerCombatLogEvents) do
        if event.sourceName == playerData.name and event.eventType == "Summon" and event.bannerFaction then
            return event.bannerFaction, "Banner"
        end
    end

    -- If no faction is determined from the above checks, use the player's current faction as the default
    return playerData.faction, "Default"
end

function AppendHistory(historyTable, roundIndex, cr, mmr, mapName, endTime, duration, teamFaction, enemyFaction, friendlyTotalDamage, friendlyTotalHealing, enemyTotalDamage, enemyTotalHealing, friendlyWinLoss, friendlyRaidLeader, enemyRaidLeader, friendlyRatingChange, enemyRatingChange, allianceTeamScore, hordeTeamScore, roundsWon, categoryName, categoryID, damp)
    local appendHistoryMatchID = #historyTable + 1  -- Unique match ID
    local playerFullName = GetPlayerFullName() -- Get the player's full name

    -- Fetch team information
    local friendlyTeamInfo = C_PvP.GetTeamInfo(0)  -- Assuming 0 is the index for friendly team
    local enemyTeamInfo = C_PvP.GetTeamInfo(1)  -- Assuming 1 is the index for enemy team

    -- Extract postmatch MMR for friendly and enemy teams
    local friendlyPostMatchMMR = friendlyTeamInfo and friendlyTeamInfo.ratingMMR or "N/A"
    local enemyPostMatchMMR = enemyTeamInfo and enemyTeamInfo.ratingMMR or "N/A"

    -- Initialize player stats and team-specific tables
    local playerStats = {}
    local friendlyPlayers = {}
    local enemyPlayers = {}
    local friendlyRatingTotal, enemyRatingTotal = 0, 0
    local friendlyPlayerCount, enemyPlayerCount = 0, 0
    local friendlyRatingChangeTotal, enemyRatingChangeTotal = 0, 0
	
    for i = 1, GetNumBattlefieldScores() do
        local scoreInfo = C_PvP.GetScoreInfo(i)
        if scoreInfo then
            local name = scoreInfo.name
            if name == UnitName("player") then
                name = playerFullName
            end

            -- Get faction group tag and localized faction
            local killingBlows = tonumber(scoreInfo.killingBlows) or 0
            local honorableKills = tonumber(scoreInfo.honorableKills) or 0
            local deaths = tonumber(scoreInfo.deaths) or 0
            local honorGained = tonumber(scoreInfo.honorGained) or 0
            local faction = scoreInfo.faction
            local raceName = scoreInfo.raceName
            local className = scoreInfo.className
            local classToken = scoreInfo.classToken
            local damageDone = tonumber(scoreInfo.damageDone) or 0  -- Ensure damageDone is a number
            local healingDone = tonumber(scoreInfo.healingDone) or 0  -- Ensure healingDone is a number
            local rating = tonumber(scoreInfo.rating) or 0
            local ratingChange = tonumber(scoreInfo.ratingChange) or 0
            local prematchMMR = tonumber(scoreInfo.prematchMMR) or 0
            local mmrChange = tonumber(scoreInfo.mmrChange) or 0
            local postmatchMMR = tonumber(scoreInfo.postmatchMMR) or 0
            local talentSpec = scoreInfo.talentSpec
            local honorLevel = tonumber(scoreInfo.honorLevel) or 0
            local roleAssigned = scoreInfo.roleAssigned
            local stats = scoreInfo.stats
            local guid = scoreInfo.guid
---            local roundsWon = roundsWon or 0  -- Capture rounds won
         
            -- Display additional stats
            if stats then
                for _, stat in ipairs(stats) do
                end
            end
          
            local newrating = rating + ratingChange
            local translatedFaction = (faction == 0 and "Horde" or "Alliance")

            -- Create player data entry
            local playerData = {
                name = name,
                guid = guid,
                faction = translatedFaction,
                race = raceName,
                evaluatedrace = remappedRace,
                class = className,
                spec = talentSpec,
                role = roleAssigned,
                cr = cr,  -- Keep original cr
                mmr = mmr,
                killingBlows = killingBlows,
                honorableKills = honorableKills,
                damage = damageDone,
                healing = healingDone,
                rating = rating,
                ratingChange = ratingChange,
                prematchMMR = prematchMMR,
                mmrChange = mmrChange,
                postmatchMMR = postmatchMMR,
                honorLevel = honorLevel,
                newrating = newrating,  -- New field for adjusted rating
                originalFaction = nil,
---                roundsWon = roundsWon or 0,
            }

            -- Get combat log events
            local playerCombatLogEvents = GetCombatLogEventsForPlayer(playerData.name)
            playerCombatLogEvents = playerCombatLogEvents or {}
            
            -- Determine original faction based on combat log events
            local originalFaction, factionSource = DetermineOriginalFaction(playerData, playerCombatLogEvents)
     
            -- Set the originalFaction in playerData
            playerData.originalFaction = originalFaction
            playerData.originalFactionSource = factionSource  -- Store the source of the original faction
            
            -- Determine if race remapping is necessary
            local remappedRace = raceFactionMapping[raceName]
            
            -- Remap the player's race if necessary
            local remappedRace = raceFactionMapping[raceName]
            if playerData.originalFaction and playerData.originalFaction ~= playerData.faction and remappedRace then
                playerData.race = remappedRace
            end

            -- Ensure all damage and healing values are numbers
            friendlyTotalDamage = tonumber(friendlyTotalDamage) or 0
            friendlyTotalHealing = tonumber(friendlyTotalHealing) or 0
            enemyTotalDamage = tonumber(enemyTotalDamage) or 0
            enemyTotalHealing = tonumber(enemyTotalHealing) or 0


            if playerData.faction == teamFaction then
                friendlyTotalDamage = friendlyTotalDamage + damageDone
                friendlyTotalHealing = friendlyTotalHealing + healingDone
                friendlyRatingTotal = friendlyRatingTotal + playerData.newrating
                friendlyRatingChangeTotal = friendlyRatingChangeTotal + playerData.ratingChange
                friendlyPlayerCount = friendlyPlayerCount + 1
                table.insert(friendlyPlayers, playerData)
            else
                enemyTotalDamage = enemyTotalDamage + damageDone
                enemyTotalHealing = enemyTotalHealing + healingDone
                enemyRatingTotal = enemyRatingTotal + playerData.newrating
                enemyRatingChangeTotal = enemyRatingChangeTotal + playerData.ratingChange
                enemyPlayerCount = enemyPlayerCount + 1
                table.insert(enemyPlayers, playerData)
            end
        end
    end

    local function GetPlayedGames(categoryID)
        return select(4, GetPersonalRatedInfo(categoryID))
    end

    local played = GetPlayedGames(categoryID)

    local playedField = "Playedfor" .. categoryName
    Database[playedField] = played

    for _, player in ipairs(friendlyPlayers) do
    end
    
    for _, player in ipairs(enemyPlayers) do
    end

    -- Calculate average newrating for friendly and enemy teams
    local friendlyAvgCR = friendlyPlayerCount > 0 and math.floor(friendlyRatingTotal / friendlyPlayerCount) or "N/A"
    local enemyAvgCR = enemyPlayerCount > 0 and math.floor(enemyRatingTotal / enemyPlayerCount) or "N/A"

    -- Calculate average ratingChange for friendly and enemy teams
    local friendlyAvgRatingChange = friendlyPlayerCount > 0 and math.floor(friendlyRatingChangeTotal / friendlyPlayerCount) or "N/A"
    local enemyAvgRatingChange = enemyPlayerCount > 0 and math.floor(enemyRatingChangeTotal / enemyPlayerCount) or "N/A"

    -- Combine friendly and enemy players into playerStats
    for _, player in ipairs(friendlyPlayers) do
        table.insert(playerStats, player)
    end
    for _, player in ipairs(enemyPlayers) do
        table.insert(playerStats, player)
    end

    -- Update raid leaders
    UpdateFriendlyRaidLeader()
    local enemyRaidLeader = GetEnemyRaidLeaderName(enemyFaction, enemyPlayers)

	if C_PvP.IsRatedBattleground() and (allianceTeamScore == hordeTeamScore) then
	--- Insert or C_PvP.SoloRBG above when we get scores from RBGB.
		friendlyWinLoss = "~   D"
	end

    local entry = {
        matchID = appendHistoryMatchID,
        timestamp = endTime,
        cr = cr,
        mmr = mmr,
        isInitial = false,
        friendlyWinLoss = friendlyWinLoss,  -- Win/Loss status
        mapName = mapName,
        endTime = endTime,
        duration = duration,
		damp = damp,
        teamFaction = teamFaction,
        friendlyRaidLeader = friendlyRaidLeader,
        friendlyAvgCR = friendlyAvgCR,  -- Average newrating for friendly team
        friendlyMMR = friendlyPostMatchMMR,
        friendlyTotalDamage = friendlyTotalDamage,
        friendlyTotalHealing = friendlyTotalHealing,
        friendlyRatingChange = friendlyAvgRatingChange,
        allianceTeamScore = allianceTeamScore,
        enemyFaction = enemyFaction,
        enemyRaidLeader = enemyRaidLeader,
        enemyAvgCR = enemyAvgCR,  -- Average newrating for enemy team
        enemyMMR = enemyPostMatchMMR,
        enemyTotalDamage = enemyTotalDamage,
        enemyTotalHealing = enemyTotalHealing,
        enemyRatingChange = enemyAvgRatingChange,
        hordeTeamScore = hordeTeamScore,
		roundsWon = roundsWon or 0,
        playerStats = playerStats -- Nested table with player-specific details
    }

    table.insert(historyTable, 1, entry) -- Insert at the beginning to keep the latest at the top
    SaveData() -- Updated to call SaveData function

    -- Solo Shuffle logic with a 15-second delay only for round 1-5
    if C_PvP.IsRatedSoloShuffle() and roundIndex >= 1 and roundIndex <= 5 then
    
        local matchIDToUpdate = appendHistoryMatchID -- Track the matchID for updating the correct match entry
    
        -- Add a delay of 20 seconds before fetching final stats
        C_Timer.After(20, function()
            friendlyTotalDamage = 0
            friendlyTotalHealing = 0
            enemyTotalDamage = 0
            enemyTotalHealing = 0
            friendlyRatingTotal = 0
            enemyRatingTotal = 0
            friendlyRatingChangeTotal = 0
            enemyRatingChangeTotal = 0
            friendlyPlayerCount = 0
            enemyPlayerCount = 0
    
            -- Fetch updated player stats after delay
            for i = 1, GetNumBattlefieldScores() do
                local scoreInfo = C_PvP.GetScoreInfo(i)
                if scoreInfo then
                    -- Update playerStats directly with the provided values
                    local name = scoreInfo.name
                    if name == UnitName("player") then
                        name = playerFullName
                    end
    
                    for _, playerData in ipairs(playerStats) do
                        if playerData.name == name then
                            -- Update the playerData fields with new stats
                            playerData.killingBlows = tonumber(scoreInfo.killingBlows) or 0
                            playerData.honorableKills = tonumber(scoreInfo.honorableKills) or 0
                            playerData.damage = tonumber(scoreInfo.damageDone) or 0
                            playerData.healing = tonumber(scoreInfo.healingDone) or 0
                            playerData.rating = tonumber(scoreInfo.rating) or 0
                            playerData.ratingChange = tonumber(scoreInfo.ratingChange) or 0
                            playerData.mmrChange = tonumber(scoreInfo.mmrChange) or 0
                            playerData.postmatchMMR = tonumber(scoreInfo.postmatchMMR) or 0
                            playerData.honorLevel = tonumber(scoreInfo.honorLevel) or 0
---                            playerData.roundsWon = roundsWon or 0
    
                            -- Calculate totals based on player's faction
                            if playerData.faction == teamFaction then
                                friendlyTotalDamage = friendlyTotalDamage + playerData.damage
                                friendlyTotalHealing = friendlyTotalHealing + playerData.healing
                                friendlyRatingTotal = friendlyRatingTotal + playerData.rating + playerData.ratingChange
                                friendlyRatingChangeTotal = friendlyRatingChangeTotal + playerData.ratingChange
                                friendlyPlayerCount = friendlyPlayerCount + 1
                            else
                                enemyTotalDamage = enemyTotalDamage + playerData.damage
                                enemyTotalHealing = enemyTotalHealing + playerData.healing
                                enemyRatingTotal = enemyRatingTotal + playerData.rating + playerData.ratingChange
                                enemyRatingChangeTotal = enemyRatingChangeTotal + playerData.ratingChange
                                enemyPlayerCount = enemyPlayerCount + 1
                            end
    
                            -- Debug output to confirm update
                        end
                    end
                end
            end
    
            -- Calculate average newrating for friendly and enemy teams
            local friendlyAvgCR = friendlyPlayerCount > 0 and math.floor(friendlyRatingTotal / friendlyPlayerCount) or "N/A"
            local enemyAvgCR = enemyPlayerCount > 0 and math.floor(enemyRatingTotal / enemyPlayerCount) or "N/A"
    
            -- Calculate average ratingChange for friendly and enemy teams
            local friendlyAvgRatingChange = friendlyPlayerCount > 0 and math.floor(friendlyRatingChangeTotal / friendlyPlayerCount) or "N/A"
            local enemyAvgRatingChange = enemyPlayerCount > 0 and math.floor(enemyRatingChangeTotal / enemyPlayerCount) or "N/A"
    
            -- Now update the corresponding entry in historyTable based on matchID
            for _, entry in ipairs(historyTable) do
                if entry.matchID == matchIDToUpdate then
                    -- Update the match entry with the new totals and averages
                    entry.friendlyTotalDamage = friendlyTotalDamage
                    entry.friendlyTotalHealing = friendlyTotalHealing
                    entry.enemyTotalDamage = enemyTotalDamage
                    entry.enemyTotalHealing = enemyTotalHealing
                    entry.friendlyAvgCR = friendlyAvgCR
                    entry.enemyAvgCR = enemyAvgCR
                    entry.friendlyRatingChange = friendlyAvgRatingChange
                    entry.enemyRatingChange = enemyAvgRatingChange
                    -- Update playerStats with the new player data
                    entry.playerStats = playerStats
                    break
                end
            end
    
            -- Save the updated data
            SaveData()
        end)
    end

    if C_PvP.IsRatedSoloShuffle() and roundIndex == 6 then  
        local matchIDToUpdate = appendHistoryMatchID -- Track the matchID for updating the correct match entry
    
        -- Add a delay of 1 second before fetching final stats
        C_Timer.After(1, function()
            friendlyTotalDamage = 0
            friendlyTotalHealing = 0
            enemyTotalDamage = 0
            enemyTotalHealing = 0
            friendlyRatingTotal = 0
            enemyRatingTotal = 0
            friendlyRatingChangeTotal = 0
            enemyRatingChangeTotal = 0
            friendlyPlayerCount = 0
            enemyPlayerCount = 0
    
            -- Fetch updated player stats after delay
            for i = 1, GetNumBattlefieldScores() do
                local scoreInfo = C_PvP.GetScoreInfo(i)
                if scoreInfo then
                    -- Update playerStats directly with the provided values
                    local name = scoreInfo.name
                    if name == UnitName("player") then
                        name = playerFullName
                    end
    
                    for _, playerData in ipairs(playerStats) do
                        if playerData.name == name then
                            -- Update the playerData fields with new stats
                            playerData.killingBlows = tonumber(scoreInfo.killingBlows) or 0
                            playerData.honorableKills = tonumber(scoreInfo.honorableKills) or 0
                            playerData.damage = tonumber(scoreInfo.damageDone) or 0
                            playerData.healing = tonumber(scoreInfo.healingDone) or 0
                            playerData.rating = tonumber(scoreInfo.rating) or 0
                            playerData.ratingChange = tonumber(scoreInfo.ratingChange) or 0
                            playerData.mmrChange = tonumber(scoreInfo.mmrChange) or 0
                            playerData.postmatchMMR = tonumber(scoreInfo.postmatchMMR) or 0
                            playerData.honorLevel = tonumber(scoreInfo.honorLevel) or 0
---                            playerData.roundsWon = roundsWon or 0
    
                            -- Calculate totals based on player's faction
                            if playerData.faction == teamFaction then
                                friendlyTotalDamage = friendlyTotalDamage + playerData.damage
                                friendlyTotalHealing = friendlyTotalHealing + playerData.healing
                                friendlyRatingTotal = friendlyRatingTotal + playerData.rating + playerData.ratingChange
                                friendlyRatingChangeTotal = friendlyRatingChangeTotal + playerData.ratingChange
                                friendlyPlayerCount = friendlyPlayerCount + 1
                            else
                                enemyTotalDamage = enemyTotalDamage + playerData.damage
                                enemyTotalHealing = enemyTotalHealing + playerData.healing
                                enemyRatingTotal = enemyRatingTotal + playerData.rating + playerData.ratingChange
                                enemyRatingChangeTotal = enemyRatingChangeTotal + playerData.ratingChange
                                enemyPlayerCount = enemyPlayerCount + 1
                            end
    
                            -- Debug output to confirm update
                        end
                    end
                end
            end
    
            -- Calculate average newrating for friendly and enemy teams
            local friendlyAvgCR = friendlyPlayerCount > 0 and math.floor(friendlyRatingTotal / friendlyPlayerCount) or "N/A"
            local enemyAvgCR = enemyPlayerCount > 0 and math.floor(enemyRatingTotal / enemyPlayerCount) or "N/A"
    
            -- Calculate average ratingChange for friendly and enemy teams
            local friendlyAvgRatingChange = friendlyPlayerCount > 0 and math.floor(friendlyRatingChangeTotal / friendlyPlayerCount) or "N/A"
            local enemyAvgRatingChange = enemyPlayerCount > 0 and math.floor(enemyRatingChangeTotal / enemyPlayerCount) or "N/A"
    
            -- Now update the corresponding entry in historyTable based on matchID
            for _, entry in ipairs(historyTable) do
                if entry.matchID == matchIDToUpdate then
                    -- Update the match entry with the new totals and averages
                    entry.friendlyTotalDamage = friendlyTotalDamage
                    entry.friendlyTotalHealing = friendlyTotalHealing
                    entry.enemyTotalDamage = enemyTotalDamage
                    entry.enemyTotalHealing = enemyTotalHealing
                    entry.friendlyAvgCR = friendlyAvgCR
                    entry.enemyAvgCR = enemyAvgCR
                    entry.friendlyRatingChange = friendlyAvgRatingChange
                    entry.enemyRatingChange = enemyAvgRatingChange
                    -- Update playerStats with the new player data
                    entry.playerStats = playerStats
                    break
                end
            end
    
            -- Save the updated data
            SaveData()
        end)
    end
end

local function convertToTimestamp(dateString)
    -- Updated pattern to correctly match the format of your date string
    local pattern = "(%a+) (%d+) (%a+) (%d+) %- (%d+):(%d+):(%d+)"
    local dayName, day, monthName, year, hour, minute, second = dateString:match(pattern)
    
    -- Make sure all components are correctly parsed
    if not day or not monthName or not year or not hour or not minute or not second then
        -- If any component is missing, print an error and return a default value (like 0)
        return 0
    end
    
    -- Convert the month name to a number
    local month = ({
        Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6,
        Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12
    })[monthName]
    
    -- Ensure the month is valid
    if not month then
        return 0
    end
    
    -- Convert to a timestamp
    return time({
        year = tonumber(year),
        month = month,
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(minute),
        sec = tonumber(second)
    })
end

-- Update DisplayHistory to include initial entries
function DisplayHistory(content, historyTable, mmrLabel, tabID)

    -- Sort historyTable by `matchID` in descending order (most recent first)
    table.sort(historyTable, function(matchA, matchB)
        -- Compare the matchID of each entry
        local matchIDA = matchA.matchID or 0  -- Default to 0 if matchID is nil, although all should have a matchID
        local matchIDB = matchB.matchID or 0  -- Same for matchIDB

        return matchIDA < matchIDB
    end)

    local scoreHeaderText = "Score"
	if tabID == 2 or tabID == 3 then  -- Solo Shuffle, 2v2, 3v3 tab IDs
        scoreHeaderText = ""  -- Hide the "Score" header
    end

    -- Define main table headers
    local headers = {
        "Win/Loss", "Map", "Match End Time", "Duration", "", "", "Faction", "Raid Leader", "Avg CR", "Team MMR",
        "Damage", "Healing", "Avg Rat Chg", "", scoreHeaderText, "", "Faction", "Raid Leader", "Avg CR", "Team MMR", "Damage",
        "Healing", "Avg Rat Chg"
    }
   
    local columnOffsets = {
        0,      -- 0: Starting offset
        60,     -- 1: Win/Loss
        150,    -- 2: Map
        270,    -- 3: Match End Time
        330,    -- 4: Duration
        350,    -- 5: Empty column
        370,    -- 6: Empty column
        430,    -- 7: Faction
        580,    -- 8: Raid Leader
        640,    -- 9: Avg CR
        700,    -- 10: Team MMR
        760,    -- 11: Damage
        810,    -- 12: Healing
        860,    -- 13: Avg Rat Chg
        900,    -- 14: Empty column
        960,    -- 15: Score
        1000,   -- 16: Empty column
        1060,   -- 17: Faction
        1210,   -- 18: Raid Leader
        1270,   -- 19: Avg CR
        1330,   -- 20: Team MMR
        1390,   -- 21: Damage
        1450,   -- 22: Healing
        1510    -- 23: Avg Rat Chg
    }

    local headerFontSize = 10  -- Font size for headers
    local entryFontSize = 8    -- Font size for entries

    -- Create main table header row
    local headerTexts = {}
    local headerYPosition = -25
    for i, header in ipairs(headers) do
        local headerText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        headerText:SetFont("Fonts\\FRIZQT__.TTF", headerFontSize)  -- Set font size
        headerText:SetJustifyH("CENTER")  -- Center text
        headerText:SetPoint("TOPLEFT", mmrLabel, "BOTTOMLEFT", columnOffsets[i], headerYPosition)  -- Adjust position
        headerText:SetText(header)
        table.insert(headerTexts, headerText)
    end
	
	local dataNotReady = not historyTable or #historyTable == 0

	if dataNotReady then
		local placeholder = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
		placeholder:SetFont("Fonts\\FRIZQT__.TTF", 10)
		placeholder:SetPoint("TOPLEFT", headerTexts[1], "BOTTOMLEFT", 0, -20)
		placeholder:SetText("|cff00ccffWaiting for game data to initialise. Once PvP data is available within the API rows will appear!|r")
		placeholder:SetJustifyH("LEFT")
		placeholder:SetJustifyV("TOP")
		placeholder:SetWidth(900)
		placeholder:SetHeight(50)
		placeholder:SetWordWrap(true)
		
		return headerTexts, {}  -- Return early to skip match drawing
	end

    -- Function to format match entry
    local function formatMatchEntry(match)
---        local winLoss = match.isInitial and "I" or (match.friendlyWinLoss or "-")

		local scoreText = "-"

		if match.friendlyTeamScore then
			if match.teamFaction == "Alliance" then
				scoreText = (match.friendlyTeamScore or "-") .. "  : " .. (match.enemyTeamScore or "-")
			else
				scoreText = (match.enemyTeamScore or "-") .. "  : " .. (match.friendlyTeamScore or "-")
			end
		elseif match.allianceTeamScore and match.teamFaction == "Alliance" then
			scoreText = (match.allianceTeamScore or "-") .. " : " .. (match.hordeTeamScore or "-")
		else
			scoreText = (match.hordeTeamScore or "-") .. "  : " .. (match.allianceTeamScore or "-")
		end

        -- Hide the score text if the current content is Solo Shuffle
        if tabID == 1 then
			scoreText = (match.roundsWon or 0) .. " / 6"
		elseif tabID == 2 or tabID == 3 then  -- 2v2, 3v3 tab IDs
            scoreText = ""
        end
		
		if type(match.duration) == "number" then
			match.duration = SecondsToTime(match.duration)
		end

        return {
            match.friendlyWinLoss or "-",
            match.mapName or "N/A",
            date("%a %d %b %Y - %H:%M:%S", match.endTime) or "N/A",
			match.duration or "N/A",
            "",
            "", 
            match.teamFaction or "N/A",
            match.friendlyRaidLeader or "N/A",
            match.friendlyAvgCR or "N/A",
            match.friendlyMMR or "N/A",
            FormatNumber(match.friendlyTotalDamage) or "N/A",
            FormatNumber(match.friendlyTotalHealing) or "N/A",
            match.friendlyRatingChange or "N/A",
            "",
            scoreText, -- Use the function to conditionally show/hide the score
            "", 
            match.enemyFaction or "N/A",
            match.enemyRaidLeader or "N/A",
            match.enemyAvgCR or "N/A",
            match.enemyMMR or "N/A",
            FormatNumber(match.enemyTotalDamage) or "N/A",
            FormatNumber(match.enemyTotalHealing) or "N/A",
            match.enemyRatingChange or "N/A",
        }
    end
	
    -- Remove previous match frames
    for _, child in ipairs({content:GetChildren()}) do
        if child ~= mmrLabel then
            child:Hide()
        end
    end

    -- Display each match entry
    local previousFrame = headerTexts[1] -- Start with the first header as reference
    local matchFrames = {}
    for i = #historyTable, 1, -1 do
        local match = historyTable[i]
        local formattedEntry = formatMatchEntry(match)
        local matchFrame = CreateFrame("Frame", nil, content, "BackdropTemplate")
        matchFrame:SetSize(1920, 5) -- Change the size of the match data row here
        matchFrame:SetPoint("TOPLEFT", previousFrame, "BOTTOMLEFT", 0, -5)

		-- Always set the backdrop file once
		matchFrame:SetBackdrop({bgFile = "Interface/Tooltips/UI-Tooltip-Background"})
		
		-- Then choose color based on damp or faction
		if match.damp and tabID == (1 or 2 or 3) then
			local dampVal = match.damp
			if dampVal <= 10 then
				matchFrame:SetBackdropColor(0.5, 0.5, 0.5, 0.7)  -- Grey
			elseif dampVal <= 20 then
				matchFrame:SetBackdropColor(1, 1, 0, 0.7)        -- Yellow
			elseif dampVal <= 30 then
				matchFrame:SetBackdropColor(1, 0.55, 0, 0.7)     -- Amber
			elseif dampVal <= 39 then
				matchFrame:SetBackdropColor(1, 0.4, 0, 0.7)      -- Orange
			else
				matchFrame:SetBackdropColor(1, 0, 0, 0.7)        -- Red
			end
		
		else
			-- No dampening: color by faction
			if match.teamFaction == "Horde" then
				matchFrame:SetBackdropColor(1, 0, 0, 0.7)  -- Horde = red
			elseif match.teamFaction == "Alliance" then
				matchFrame:SetBackdropColor(0, 0, 1, 0.7)  -- Alliance = blue
			end
		end

        for j, column in ipairs(formattedEntry) do
            local text = matchFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            text:SetFont("Fonts\\FRIZQT__.TTF", entryFontSize)
            text:SetJustifyH("CENTER")
            text:SetPoint("TOPLEFT", matchFrame, "TOPLEFT", columnOffsets[j], 0)
            text:SetText(column)
            -- Ensure the Win/Loss column has the correct color
            if j == 1 then
                if column == "+   W" or column == "RND 1  +   W" or column == "RND 2  +   W" or column == "RND 3  +   W" or column == "RND 4  +   W" or column == "RND 5  +   W" or column == "RND 6  +   W" then
                    text:SetTextColor(0, 1, 0)  -- Green for win
                elseif column == "+   L" or column == "RND 1  +   L" or column == "RND 2  +   L" or column == "RND 3  +   L" or column == "RND 4  +   L" or column == "RND 5  +   L" or column == "RND 6  +   L" then
                    text:SetTextColor(1, 0, 0)  -- Red for loss
				elseif column =="~   D" or column == "RND 1  ~   D" or column == "RND 2  ~   D" or column == "RND 3  ~   D" or column == "RND 4  ~   D" or column == "RND 5  ~   D" or column == "RND 6  ~   D" then
					text:SetTextColor(0.5, 0.5, 0.5)
                else
                    text:SetTextColor(1, 1, 1)  -- Default color for other cases
                end		
            end
			
			    -- If this is the Duration column (j == 4) and we have match.damp, show a tooltip
			if j == 4 and match.damp and tabID == (1 or 2 or 3) then
				-- Make sure our text can handle mouse events
				text:EnableMouse(true)
		
				text:SetScript("OnEnter", function()
					GameTooltip:SetOwner(text, "ANCHOR_RIGHT")
					GameTooltip:ClearLines()
					GameTooltip:AddLine(string.format("%d%% Dampening", match.damp), 1, 1, 1)
					GameTooltip:Show()
				end)
		
				text:SetScript("OnLeave", function()
					GameTooltip:Hide()
				end)
			end		
        end

        -- Get player stats and create nested table
        local playerStats = match.playerStats or {}
        local nestedTable = CreateNestedTable(matchFrame, playerStats, match.teamFaction, match.isInitial, match.isMissedGame)
        matchFrame.nestedTable = nestedTable  -- Assign the nested table to the matchFrame

        -- Make matchFrame interactive to toggle nested table
        matchFrame:SetScript("OnMouseUp", function()
            ToggleNestedTable(nestedTable, content, matchFrames, headerTexts)
        end)

        table.insert(matchFrames, matchFrame)
        previousFrame = matchFrame
    end

    SaveData()

    -- Return headerTexts and matchFrames for further use
    return headerTexts, matchFrames
end

local rowCounts = {
    ["Solo Shuffle"] = 3,
    ["2v2"] = 2,
    ["3v3"] = 3,
    ["RBG"] = 10,
    ["Solo RBG"] = 8,
}

local function CreateCopyNameFrame(playerName)
    -- Create a new frame for the popup
    local frame = CreateFrame("Frame", "CopyNameFrame", UIParent, "BackdropTemplate")
    frame:SetSize(300, 100)  -- Adjust size as needed
    frame:SetPoint("CENTER", UIParent, "CENTER")  -- Position in the center of the screen
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(10)

    -- Set the background texture to the image
    local bgTexture = frame:CreateTexture(nil, "BACKGROUND")
    bgTexture:SetTexture("Interface\\AddOns\\RatedStats\\RatedStats.tga")  -- Path to your image
    bgTexture:SetAllPoints(frame)  -- Make the texture fit the entire frame

    -- Add a backdrop to the frame (optional, for visibility)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    frame:SetBackdropColor(0, 0, 0, 1)
    frame:SetBackdropBorderColor(0, 0, 0, 1)

    -- Create an EditBox inside the frame
    local editBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    editBox:SetSize(200, 40)
    editBox:SetPoint("CENTER", frame, "CENTER")
    editBox:SetFont(STANDARD_TEXT_FONT, 8, "OUTLINE")
    editBox:SetText(playerName)
    editBox:SetFocus()  -- Automatically focus the EditBox
    editBox:HighlightText()  -- Highlight the text for easy copying
    editBox:SetAutoFocus(false)  -- Prevent the EditBox from losing focus
    editBox:SetAlpha(1)

    -- Close the frame when the user presses Escape
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)

    -- Handle clicking outside the EditBox to focus it again
    frame:SetScript("OnMouseDown", function() editBox:SetFocus() end)
    
    -- Allow the frame to be closed by clicking a close button
    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT")

    -- Show the frame
    frame:Show()
end

local function CreateClickableName(parent, playerName, x, y)
    -- Create a FontString to display the player name
    local nameText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameText:SetFont(STANDARD_TEXT_FONT, 8, "OUTLINE")
    nameText:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    nameText:SetText(playerName)

    -- Create a clickable frame over the text
    local clickableFrame = CreateFrame("Button", nil, parent)
    clickableFrame:SetSize(nameText:GetStringWidth(), nameText:GetStringHeight())
    clickableFrame:SetPoint("TOPLEFT", nameText, "TOPLEFT")

    -- On click, open the copy name frame
    clickableFrame:SetScript("OnClick", function()
        CreateCopyNameFrame(playerName)
    end)

    return nameText
end

function CreateNestedTable(parent, playerStats, friendlyFaction, isInitial, isMissedGame)
    local nestedTable = CreateFrame("Frame", nil, parent, "BackdropTemplate")

    -- Determine the match type using the correct function
    local matchType = IdentifyPvPMatchType()

    -- Determine the actual number of players per team (assuming equal teams)
    local playersPerTeam = #playerStats / 2

    -- Get the number of rows based on the match type
    local numberOfRows = playersPerTeam
    
    -- Calculate the size of the nested table
    local rowHeight = 15  -- Adjust this value based on your actual row height
    local tableHeight = playersPerTeam * rowHeight + 30  -- Adjust for padding or additional spacing
    
    nestedTable:SetSize(1920, tableHeight)
    nestedTable:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -25)
    nestedTable:Hide()

    local headers = {
        "Character", "Faction", "Race", "Class", "Spec", "Role", "CR", "KBs", "HKs", "Damage", "Healing", "Rating Chg",
        "Character", "Faction", "Race", "Class", "Spec", "Role", "CR", "KBs", "HKs", "Damage", "Healing", "Rating Chg"
    }
    local columnOffsets = {
        0,    -- 0: Character
        150,  -- 1: Faction
        190,  -- 2: Race
        230,  -- 3: Class
        270,  -- 4: Spec
        310,  -- 5: Role
        340,  -- 6: CR
        390,  -- 7: KBs
        420,  -- 8: HKs
        450,  -- 9: Damage
        500,  -- 10: Healing
        560,  -- 11: Rating Chg
    
        820, -- 12: Character (Second set)
        970, -- 13: Faction (Second set)
        1010, -- 14: Race (Second set)
        1050, -- 15: Class (Second set)
        1090, -- 16: Spec (Second set)
        1130, -- 17: Role (Second set)
        1160, -- 18: CR (Second set)
        1210, -- 19: KBs (Second set)
        1240, -- 20: HKs (Second set)
        1270, -- 21: Damage (Second set)
        1320, -- 22: Healing (Second set)
        1380  -- 23: Rating Chg (Second set)
    }
    local headerFontSize = 10
    local entryFontSize = 8
    local headerHeight = 18  -- Height of the header row

    -- Create "Your Team" header
    local yourTeamHeader = nestedTable:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    yourTeamHeader:SetFont("Fonts\\FRIZQT__.TTF", headerFontSize)
    yourTeamHeader:SetJustifyH("CENTER")
    yourTeamHeader:SetPoint("TOPLEFT", nestedTable, "TOPLEFT", 0, 0)  -- Adjust position above friendly players
    yourTeamHeader:SetText("                                                                                                            Your Team")

    -- Create "Enemy Team" header
    local enemyTeamHeader = nestedTable:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    enemyTeamHeader:SetFont("Fonts\\FRIZQT__.TTF", headerFontSize)
    enemyTeamHeader:SetJustifyH("CENTER")
    enemyTeamHeader:SetPoint("TOPLEFT", nestedTable, "TOPLEFT", columnOffsets[13], 0)  -- Adjust position above enemy players
    enemyTeamHeader:SetText("                                                                                                           Enemy Team")

    -- Create nested table header row
    for i, header in ipairs(headers) do
        local headerText = nestedTable:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        headerText:SetFont("Fonts\\FRIZQT__.TTF", headerFontSize)  -- Set font size
        headerText:SetJustifyH("CENTER")  -- Center text
        headerText:SetPoint("TOPLEFT", yourTeamHeader, "TOPLEFT", columnOffsets[i], -18)  -- Adjust position
        headerText:SetText(header)
    end

    -- Separate friendly and enemy player stats
    local friendlyPlayers = {}
    local enemyPlayers = {}

    if isInitial or isMissedGame then
        -- For initial entries, the player's stats are on the left and placeholders on the right
        table.insert(friendlyPlayers, playerStats[1])  -- Assume the player is the first entry
        for i = 1, playersPerTeam do
            table.insert(enemyPlayers, {
                name = "-", originalFaction = "-", race = "-", class = "-", spec = "-", role = "-", 
                newrating = "-", killingBlows = "-", honorableKills = "-", damage = "-", healing = "-", ratingChange = "-"
            })  -- Add placeholder entries for the enemy
        end
    else
        -- Separate players by faction
        for _, player in ipairs(playerStats) do
            if player.faction == friendlyFaction then
                table.insert(friendlyPlayers, player)
            else
                table.insert(enemyPlayers, player)
            end
        end
    end

    -- Populate friendly player stats
    for index, player in ipairs(friendlyPlayers) do
        local rowOffset = -(headerHeight + 15 * index)  -- Adjust rowOffset to account for headers
        local nameText = CreateClickableName(nestedTable, player.name, columnOffsets[1], rowOffset)
        for i, stat in ipairs({
            player.name,
            factionIcons[player.originalFaction] or player.originalFaction, 
            raceIcons[player.race] or player.race, 
            classIcons[player.class] or player.class, 
            specIcons[player.spec] or player.spec, 
            roleIcons[player.role] or player.role,  -- Replace numeric role with icon
            player.newrating, 
            player.killingBlows, 
            player.honorableKills, 
            FormatNumber(player.damage), 
            FormatNumber(player.healing), 
            player.ratingChange
        }) do
            if i == 2 then
                CreateIconWithTooltip(nestedTable, stat, player.originalFaction, columnOffsets[i], rowOffset)
            elseif i == 3 then
                CreateIconWithTooltip(nestedTable, stat, player.race, columnOffsets[i], rowOffset)
            elseif i == 4 then
                CreateIconWithTooltip(nestedTable, stat, player.class, columnOffsets[i], rowOffset)
            elseif i == 5 then
                CreateIconWithTooltip(nestedTable, stat, player.spec, columnOffsets[i], rowOffset)
            elseif i == 6 then
                -- Add role tooltip
                CreateIconWithTooltip(nestedTable, stat, roleTooltips[player.role], columnOffsets[i], rowOffset)
            else
                local textValue = stat or "-"  -- Provide a default value if stat is nil
                local text = nestedTable:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                text:SetFont("Fonts\\FRIZQT__.TTF", entryFontSize)
                text:SetJustifyH("CENTER")
                text:SetPoint("TOPLEFT", nestedTable, "TOPLEFT", columnOffsets[i], rowOffset)
                text:SetText(tostring(textValue))  -- Ensure the value is converted to a string
            end
        end  -- This 'end' closes the inner 'for' loop
    end  -- This 'end' closes the outer 'for' loop
    
    -- Populate enemy player stats
    for index, player in ipairs(enemyPlayers) do
        local rowOffset = -(headerHeight + 15 * index)  -- Adjust rowOffset to account for headers
        local nameText = CreateClickableName(nestedTable, player.name, columnOffsets[13], rowOffset)
        for i, stat in ipairs({
            player.name,
            factionIcons[player.originalFaction] or player.originalFaction, 
            raceIcons[player.race] or player.race, 
            classIcons[player.class] or player.class, 
            specIcons[player.spec] or player.spec, 
            roleIcons[player.role] or player.role,  -- Replace numeric role with icon
            player.newrating, 
            player.killingBlows, 
            player.honorableKills, 
            FormatNumber(player.damage), 
            FormatNumber(player.healing), 
            player.ratingChange
        }) do
            local adjustedOffset = columnOffsets[i + 12]
            if i == 2 then
                CreateIconWithTooltip(nestedTable, stat, player.originalFaction, adjustedOffset, rowOffset)
            elseif i == 3 then
                CreateIconWithTooltip(nestedTable, stat, player.race, adjustedOffset, rowOffset)
            elseif i == 4 then
                CreateIconWithTooltip(nestedTable, stat, player.class, adjustedOffset, rowOffset)
            elseif i == 5 then
                CreateIconWithTooltip(nestedTable, stat, player.spec, adjustedOffset, rowOffset)
            elseif i == 6 then
                -- Add role tooltip
                CreateIconWithTooltip(nestedTable, stat, roleTooltips[player.role], adjustedOffset, rowOffset)
            else
                local textValue = stat or "-"  -- Provide a default value if stat is nil
                local text = nestedTable:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                text:SetFont("Fonts\\FRIZQT__.TTF", entryFontSize)
                text:SetJustifyH("CENTER")
                text:SetPoint("TOPLEFT", nestedTable, "TOPLEFT", adjustedOffset, rowOffset)
                text:SetText(tostring(textValue))  -- Ensure the value is converted to a string
            end
        end  -- This 'end' closes the inner 'for' loop
    end  -- This 'end' closes the outer 'for' loop

    -- Add placeholders for missing friendly players if necessary
    if not (isInitial or isMissedGame) and #friendlyPlayers < numberOfRows then
        for index = #friendlyPlayers + 1, numberOfRows do
            local rowOffset = -15 * index
            for i = 1, #headers do
                local text = nestedTable:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                text:SetFont("Fonts\\FRIZQT__.TTF", entryFontSize)
                text:SetJustifyH("CENTER")
                text:SetPoint("TOPLEFT", nestedTable, "TOPLEFT", columnOffsets[i], rowOffset)
                text:SetText("-")
            end
        end
    end
    
    -- Add placeholders for missing enemy players if necessary
    if not (isInitial or isMissedGame) and #enemyPlayers < numberOfRows then
        for index = #enemyPlayers + 1, numberOfRows do
            local rowOffset = -15 * index
            for i = 1, #headers do
                local text = nestedTable:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                text:SetFont("Fonts\\FRIZQT__.TTF", entryFontSize)
                text:SetJustifyH("CENTER")
                text:SetPoint("TOPLEFT", nestedTable, "TOPLEFT", columnOffsets[i + 12], rowOffset)
                text:SetText("-")
            end
        end
    end

    SaveData()

    return nestedTable

end

function ToggleNestedTable(nestedTable, content, matchFrames, headerTexts)
    if nestedTable:IsShown() then
        nestedTable:Hide()
    else
        nestedTable:Show()
    end
    AdjustSiblingFrames(content, matchFrames, headerTexts)
end

function AdjustSiblingFrames(content, matchFrames, headerTexts)
    local previousFrame = headerTexts[1] -- Start with the first header as reference
    for _, matchFrame in ipairs(matchFrames) do
        local nestedTable = matchFrame.nestedTable
        matchFrame:ClearAllPoints()
        matchFrame:SetPoint("TOPLEFT", previousFrame, "BOTTOMLEFT", 0, -5)
        previousFrame = matchFrame
        if nestedTable:IsShown() then
            nestedTable:ClearAllPoints()
            nestedTable:SetPoint("TOPLEFT", matchFrame, "BOTTOMLEFT", 0, -5)
            previousFrame = nestedTable
        end
    end
end

-- Define the DisplayCurrentCRMMR function
function DisplayCurrentCRMMR(contentFrame, categoryID)
    -- Retrieve CR and MMR using GetPersonalRatedInfo for the specified categoryID
    local currentCR = select(1, GetPersonalRatedInfo(categoryID)) or "N/A"
	local currentMMR = 0
	
    local categoryMappings = {
        SoloShuffle = { id = 7, historyTable = "SoloShuffleHistory", displayName = "SoloShuffle" },
        ["2v2"] = { id = 1, historyTable = "v2History", displayName = "2v2" },
        ["3v3"] = { id = 2, historyTable = "v3History", displayName = "3v3" },
        RBG = { id = 4, historyTable = "RBGHistory", displayName = "RBG" },
        SoloRBG = { id = 9, historyTable = "SoloRBGHistory", displayName = "SoloRBG" }
    }	

	-- Find the correct history table name from categoryID
	local selectedHistoryTable
	for _, info in pairs(categoryMappings) do
		if info.id == categoryID then
			selectedHistoryTable = Database[info.historyTable]
			break
		end
	end
	
	-- Look up this player's most recent postmatchMMR
	if selectedHistoryTable and #selectedHistoryTable > 0 then
		local lastEntry = selectedHistoryTable[#selectedHistoryTable]
		if lastEntry and lastEntry.playerStats and lastEntry.playerStats[playerName] then
			currentMMR = lastEntry.playerStats[playerName].postmatchMMR or "N/A"
		end
	end
   
    -- Save these values to the Database
    if categoryID == 7 then
        Database.CurrentCRforSoloShuffle = currentCR
        Database.CurrentMMRforSoloShuffle = currentMMR
    elseif categoryID == 1 then
        Database.CurrentCRfor2v2 = currentCR
        Database.CurrentMMRfor2v2 = currentMMR
    elseif categoryID == 2 then
        Database.CurrentCRfor3v3 = currentCR
        Database.CurrentMMRfor3v3 = currentMMR
    elseif categoryID == 4 then
        Database.CurrentCRforRBG = currentCR
        Database.CurrentMMRforRBG = currentMMR
    elseif categoryID == 9 then
        Database.CurrentCRforSoloRBG = currentCR
        Database.CurrentMMRforSoloRBG = currentMMR
    end
    
	if not contentFrame.crLabel then
		contentFrame.crLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		contentFrame.crLabel:SetFont("Fonts\\FRIZQT__.TTF", 14)
		contentFrame.crLabel:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, -10)
	end
	contentFrame.crLabel:SetText("Current CR: " .. currentCR)
	
	if not contentFrame.mmrLabel then
		contentFrame.mmrLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		contentFrame.mmrLabel:SetFont("Fonts\\FRIZQT__.TTF", 14)
		contentFrame.mmrLabel:SetPoint("TOPLEFT", contentFrame.crLabel, "BOTTOMLEFT", 0, -5)
	end
	contentFrame.mmrLabel:SetText("Current MMR: " .. currentMMR)
	
	if not contentFrame.instructionLabel then
		contentFrame.instructionLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		contentFrame.instructionLabel:SetFont("Fonts\\FRIZQT__.TTF", 12)
		contentFrame.instructionLabel:SetPoint("TOP", contentFrame, "TOP", 0, -10)
		contentFrame.instructionLabel:SetJustifyH("RIGHT")
	end
	contentFrame.instructionLabel:SetText("Click on rows to expand.\nClick on player name to copy.\nShift+MouseWheel to scroll left and right.")
    
    -- Return the last label for potential further positioning
    return contentFrame.mmrLabel
end

----------------------------------
-- Config functions continued
----------------------------------

function Config:CreateMenu()
    -- Check if UIConfig already exists and return it if so
    if UIConfig then
        return UIConfig
    end
	
    local offsetY = 200
	local parentWidth = UIParent:GetWidth()
	local parentHeight = UIParent:GetHeight()

    UIConfig = CreateFrame("Frame", "RatedStatsConfig", UIParent, "UIPanelDialogTemplate")
	UIConfig:SetSize(parentWidth * 0.9, parentHeight * 0.8)
    UIConfig:SetPoint("CENTER", UIParent, "CENTER", 0, offsetY)
	UIConfig:SetResizable(true)
	-- Bring RatedStats to front of spell buttons
	UIConfig:SetFrameStrata("DIALOG")
	UIConfig:SetFrameLevel(20)
	UIConfig:SetClampedToScreen(true) -- so it doesn’t get dragged or resized offscreen
	
	-- Enable dragging of the frame
	UIConfig:SetMovable(true)
	UIConfig:EnableMouse(true)
	UIConfig:RegisterForDrag("LeftButton")
	UIConfig:SetScript("OnDragStart", UIConfig.StartMoving)
	UIConfig:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		-- Optionally save the new position here
	end)
	
	-- Create a resize button (the "grip") in the bottom-right corner
	local resizeGrip = CreateFrame("Button", nil, UIConfig)
	resizeGrip:SetPoint("BOTTOMRIGHT", UIConfig, "BOTTOMRIGHT", -6, 7)  -- Adjust offsets as needed
	resizeGrip:SetSize(16, 16)
	
	-- Give it a texture that looks like a resizer (the default "SizeGrabber" is a good choice)
	local resizeTexture = resizeGrip:CreateTexture(nil, "BACKGROUND")
	resizeTexture:SetAllPoints()
	resizeTexture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	
	-- Start resizing on left-click
	resizeGrip:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then
			UIConfig:StartSizing("BOTTOMRIGHT")
		end
	end)
	
	-- Stop resizing on mouse up
	resizeGrip:SetScript("OnMouseUp", function(self, button)
		UIConfig:StopMovingOrSizing()
		-- If you want to do anything after the size changes (e.g. re-anchor stuff), do it here.
	end)

    UIConfig.Title:ClearAllPoints()
    UIConfig.Title:SetFontObject("GameFontHighlight")
    UIConfig.Title:SetPoint("LEFT", RatedStatsConfigTitleBG, "LEFT", 8, 1)
    UIConfig.Title:SetText("Rated Stats Ratings")

    -- Create Scroll Frame with vertical scroll
    UIConfig.ScrollFrame = CreateFrame("ScrollFrame", nil, UIConfig, "UIPanelScrollFrameTemplate")
    UIConfig.ScrollFrame:SetPoint("TOPLEFT", RatedStatsConfigDialogBG, "TOPLEFT", 4, -8)
    UIConfig.ScrollFrame:SetPoint("BOTTOMRIGHT", RatedStatsConfigDialogBG, "BOTTOMRIGHT", -3, 24) -- Leave space for horizontal scroll
    UIConfig.ScrollFrame:SetClipsChildren(true)

    -- Content Frame within the Scroll Frame for scrollable content
    local content = CreateFrame("Frame", nil, UIConfig.ScrollFrame)
    content:SetSize(1600, 2000) -- Adjust size as needed
    UIConfig.ScrollFrame:SetScrollChild(content)

    -- Positioning Vertical Scroll Bar
    UIConfig.ScrollFrame.ScrollBar:ClearAllPoints()
    UIConfig.ScrollFrame.ScrollBar:SetPoint("TOPRIGHT", UIConfig.ScrollFrame, "TOPRIGHT", 0, -18)
    UIConfig.ScrollFrame.ScrollBar:SetPoint("BOTTOMRIGHT", UIConfig.ScrollFrame, "BOTTOMRIGHT", -7, 18)

    -- Horizontal Scroll Bar at bottom
    local horizontalScrollBar = CreateFrame("Slider", nil, UIConfig, "UIPanelScrollBarTemplate")
    horizontalScrollBar:SetOrientation("HORIZONTAL")
    horizontalScrollBar:SetPoint("BOTTOMLEFT", UIConfig.ScrollFrame, "BOTTOMLEFT", 16, 0)
    horizontalScrollBar:SetPoint("BOTTOMRIGHT", UIConfig.ScrollFrame, "BOTTOMRIGHT", -16, 0)
    horizontalScrollBar:SetMinMaxValues(0, content:GetWidth() - UIConfig.ScrollFrame:GetWidth())
    horizontalScrollBar:SetValueStep(1)
    horizontalScrollBar:SetValue(0)
	horizontalScrollBar:Show()  -- Ensure it is shown

    -- Hook horizontal scroll to ScrollFrame
    horizontalScrollBar:SetScript("OnValueChanged", function(self, value)
        UIConfig.ScrollFrame:SetHorizontalScroll(value)
    end)

    -- Enable mouse wheel scrolling for both directions
    UIConfig.ScrollFrame:EnableMouseWheel(true)
    UIConfig.ScrollFrame:SetScript("OnMouseWheel", function(_, delta)
        if IsShiftKeyDown() then
            local currentValue = horizontalScrollBar:GetValue()
            horizontalScrollBar:SetValue(currentValue - delta * 20)
        else
            local currentValue = UIConfig.ScrollFrame.ScrollBar:GetValue()
            UIConfig.ScrollFrame.ScrollBar:SetValue(currentValue - delta * 20)
        end
    end)

    -- Define SetTabs function and positioning for content frames
    local content1, content2, content3, content4, content5 = SetTabs(UIConfig, 5, "Solo Shuffle", "2v2", "3v3", "RBG", "Solo RBG")
    local function AdjustContentPositioning(content)
        content:SetPoint("TOPLEFT", UIConfig.ScrollFrame, "TOPLEFT", 10, -40)
        content:SetPoint("BOTTOMRIGHT", UIConfig.ScrollFrame, "BOTTOMRIGHT", -10, 10)
    end

    -- Position content frames
    AdjustContentPositioning(content1)
    AdjustContentPositioning(content2)
    AdjustContentPositioning(content3)
    AdjustContentPositioning(content4)
    AdjustContentPositioning(content5)

    local function RefreshDisplay()
        local mmrLabel1 = DisplayCurrentCRMMR(content1, 7)
        local headerTexts1, matchFrames1 = DisplayHistory(content1, Database.SoloShuffleHistory, mmrLabel1, 1)
        local mmrLabel2 = DisplayCurrentCRMMR(content2, 1)
        local headerTexts2, matchFrames2 = DisplayHistory(content2, Database.v2History, mmrLabel2, 2)
        local mmrLabel3 = DisplayCurrentCRMMR(content3, 2)
        local headerTexts3, matchFrames3 = DisplayHistory(content3, Database.v3History, mmrLabel3, 3)
        local mmrLabel4 = DisplayCurrentCRMMR(content4, 4)
        local headerTexts4, matchFrames4 = DisplayHistory(content4, Database.RBGHistory, mmrLabel4, 4)
        local mmrLabel5 = DisplayCurrentCRMMR(content5, 9)
        local headerTexts5, matchFrames5 = DisplayHistory(content5, Database.SoloRBGHistory, mmrLabel5, 5)
    end

    -- Refresh UI when the frame is shown
    UIConfig:SetScript("OnShow", function()
        RefreshDisplay()
    end)

    UIConfig:Hide()
    return UIConfig
end

----------------------------------
-- PvP Match State Change Handling
----------------------------------

-- Function to identify PvP match type based on state
function IdentifyPvPMatchType()
    if C_PvP.IsRatedBattleground() then
        return "RBG";
    elseif C_PvP.IsRatedArena() then
        return "Rated Arena";
    elseif C_PvP.IsRatedSoloShuffle() then
        return "Rated Solo Shuffle";  -- Specify rated Solo Shuffle
    elseif C_PvP.IsSoloShuffle() then
        return "Unrated Solo Shuffle";  -- Differentiate unrated Solo Shuffle
    elseif C_PvP.IsSoloRBG() then
        return "Solo RBG";
    elseif C_PvP.IsBattleground() or C_PvP.IsArena() then
        return "Unrated Battleground or Skirmish";
    else
        return "Unknown"
    end
end

-- Event handler for PvP match state changes
local function OnPvPMatchEvent(self, event, arg1, arg2)
    if event == "PVP_MATCH_COMPLETE" then
        C_Timer.After(1, function()  -- Increased delay to 1 second for better state sync
            local matchType = IdentifyPvPMatchType()

            -- Determine which tab to show based on the match type
            if matchType == "Rated Solo Shuffle" or matchType == "Unrated Solo Shuffle" then
                Tab_OnClick(_G["RatedStatsConfigTab1"]); -- Handle Solo Shuffle (rated and unrated)
            elseif matchType == "Rated Arena" then
                local arenaSize = C_PvP.GetArenaSize(); -- Get the arena size
                if arenaSize == 0 then
                    Tab_OnClick(_G["RatedStatsConfigTab2"]); -- 2v2
                elseif arenaSize == 1 then
                    Tab_OnClick(_G["RatedStatsConfigTab3"]); -- 3v3
                end
            elseif matchType == "RBG" then
                Tab_OnClick(_G["RatedStatsConfigTab4"]); -- RBG
            elseif matchType == "Solo RBG" then
                Tab_OnClick(_G["RatedStatsConfigTab5"]); -- Solo RBG
                -- Ensure Solo RBG tab is updated
            else
            end
        end)
    end
end

-- Initialize and register events

function Initialize()
    local frame = CreateFrame("Frame")

    -- Register events for the main addon functionality
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")      -- Register for the PLAYER_ENTERING_WORLD event
    frame:RegisterEvent("PVP_MATCH_COMPLETE")         -- Register for the PVP_MATCH_COMPLETE event
    frame:RegisterEvent("PVP_MATCH_ACTIVE")           -- Register for the PVP_MATCH_ACTIVE event
    frame:RegisterEvent("UPDATE_UI_WIDGET")
    frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	frame:RegisterEvent("UNIT_HEALTH")
	frame:RegisterEvent("UNIT_AURA")
	frame:RegisterEvent("PVP_RATED_STATS_UPDATE")
    
    frame:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_ENTERING_WORLD" or event == "PVP_MATCH_COMPLETE" or event == "PVP_MATCH_ACTIVE" or event == "COMBAT_LOG_EVENT_UNFILTERED" or event == "UNIT_HEALTH" or event == "UNIT_AURA" then
            RefreshDataEvent(self, event, ...)
        end
    end)
end

Initialize()
