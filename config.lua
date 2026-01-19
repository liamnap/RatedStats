--------------------------------------
-- Namespaces
--------------------------------------
local _, RSTATS = ... -- The first line sets up the local variables `_` and `RSTATS`, where `_` is typically used to ignore values, and `RSTATS` is the namespace for the addon
local playerName = UnitName("player") .. "-" .. GetRealmName()
-- Get the region dynamically
local regionName = GetCurrentRegionName()  -- This will return the region as a string (e.g., "US", "EU", "KR")

-- Combine the player name with the region dynamically
local playerNameWithRegion = playerName .. "-" .. regionName

RSTATS.Database = RSTATS_Database or {} -- adds Database table to RSTATS namespace
RSTATS.Database[playerName] = RSTATS.Database[playerName] or {} -- Ensure the character-specific table exists within RSTATS_Database
Database = RSTATS.Database[playerName]

-- The Config table will store configuration settings and functions related to the addon's configuration.
local Config = RSTATS.Config
-- Initialize the UIConfig variable, which will hold the main configuration UI frame.
local UIConfig
local contentFrames = {}
local scrollFrames = {}
local scrollContents = {}
local headerFontSize = 10
local entryFontSize = 8

Database.combatLogEvents = Database.combatLogEvents or {}
combatLogEvents = Database.combatLogEvents

local c = function(text) return RSTATS:ColorText(text) end

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
    local wasHidden = not menu:IsShown()

    menu:SetShown(wasHidden)

    -- ✅ If we're showing the menu now, check for historyTable growth
    if wasHidden then
        local tabID = PanelTemplates_GetSelectedTab(RSTATS.UIConfig)

        -- If spec/talents changed while the window was closed, force a rebuild on open.
        if RSTATS.__SpecDirty then
            RSTATS.__SpecDirty = nil
            C_Timer.After(0, function()
                if not menu:IsShown() then return end
                local openTabID = PanelTemplates_GetSelectedTab(RSTATS.UIConfig)
                if openTabID == 6 and RSTATS.Summary and RSTATS.Summary.Refresh then
                    RSTATS.Summary:Refresh()
                else
                    local dropdown = RSTATS.Dropdowns and RSTATS.Dropdowns[openTabID]
                    local selected = dropdown and UIDropDownMenu_GetText(dropdown) or "Today"
                    local filterKey = selected:lower():gsub(" ", "") or "today"

                    local content = RSTATS.ScrollContents and RSTATS.ScrollContents[openTabID]
                    if content then
                        ClearStaleMatchFrames(content)
                    end

                    FilterAndSearchMatches(RatedStatsSearchBox and RatedStatsSearchBox:GetText() or "")
                    RSTATS:UpdateStatsView(filterKey, openTabID)
                    UpdateCompactHeaders(openTabID)
                end
            end)
        end

        -- ✅ Summary: refresh after the frame is actually shown + laid out.
        -- Without this, Summary can open "blank" until you tab away/back.
        if tabID == 6 and RSTATS.Summary and RSTATS.Summary.Refresh then
            C_Timer.After(0, function()
                if menu:IsShown() and PanelTemplates_GetSelectedTab(RSTATS.UIConfig) == 6 then
                    RSTATS.Summary:Refresh()
                end
            end)
        end

        -- Growth detection must be spec-aware for SS/RBGB.
        local data
        if (tabID == 1 or tabID == 5) and RSTATS and RSTATS.GetHistoryForTab then
            data = RSTATS:GetHistoryForTab(tabID)
        else
            data = ({
                [1] = Database.SoloShuffleHistory,
                [2] = Database.v2History,
                [3] = Database.v3History,
                [4] = Database.RBGHistory,
                [5] = Database.SoloRBGHistory,
            })[tabID]
        end

        if data then
            RatedStatsFilters = RatedStatsFilters or {}
            RSTATS.__LastHistoryCount = RSTATS.__LastHistoryCount or {}

            local current = #data
            local prev

            -- For SS/RBGB, store count per spec so swapping spec doesn't reuse the old count.
            if tabID == 1 or tabID == 5 then
                local specID = RSTATS.GetActiveSpecIDAndName and RSTATS.GetActiveSpecIDAndName() or nil
                RSTATS.__LastHistoryCountBySpec = RSTATS.__LastHistoryCountBySpec or {}
                RSTATS.__LastHistoryCountBySpec[tabID] = RSTATS.__LastHistoryCountBySpec[tabID] or {}
                prev = (specID and RSTATS.__LastHistoryCountBySpec[tabID][specID]) or 0
                if specID then
                    RSTATS.__LastHistoryCountBySpec[tabID][specID] = current
                end
            else
                prev = RSTATS.__LastHistoryCount[tabID] or 0
                RSTATS.__LastHistoryCount[tabID] = current
            end

            if current > prev then
                -- ✅ History grew, reset filters and re-run display
                RatedStatsFilters[tabID] = {}
                C_Timer.After(0.1, function()
                    FilterAndSearchMatches(RatedStatsSearchBox and RatedStatsSearchBox:GetText() or "")
                end)
            end
        end
    end
end

-- Removing Config:GetThemeColor causes a lua error, needs investigating before removing

function Config:GetThemeColor()
    local c = defaults.theme;
    return c.r, c.g, c.b, c.hex;
end

local function Tab_OnClick(self)
    PanelTemplates_SetTab(self:GetParent(), self:GetID());
    self.content:Show();
end

--- local function SetTabs(frame, numTabs, ...)
---     frame.numTabs = numTabs;
--- 
---     local contents = {};
---     local frameName = frame:GetName();
--- 
---     for i = 1, numTabs do
---         local tab = CreateFrame("Button", frameName.."Tab"..i, frame, "PanelTabButtonTemplate");
--- 		local parentWidth  = RatedStatsConfig:GetWidth()
--- 		local parentHeight = RatedStatsConfig:GetHeight()
---         tab:SetID(i);
---         tab:SetText(select(i, ...));
---         tab:SetScript("OnClick", Tab_OnClick);
--- 
---         tab.content = CreateFrame("Frame", nil, UIConfig.ScrollFrame, "BackdropTemplate"); -- Ensure BackdropTemplate is used
---         tab.content:SetSize(parentWidth * 0.5, parentHeight);
---         tab.content:Hide();
--- 
---         table.insert(contents, tab.content);
--- 
---         if (i == 1) then
---             tab:SetPoint("TOPLEFT", UIConfig, "BOTTOMLEFT", 10, 7); -- Changes the initial position of first tab
---         else
---             tab:SetPoint("TOPLEFT", _G[frameName.."Tab"..(i - 1)], "TOPRIGHT", -2, 0); -- Changes the position of the subsequent tabs eg overlap
---         end
---     end
--- 
---     Tab_OnClick(_G[frameName.."Tab1"]);
--- 
---     return unpack(contents);
--- end

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
	
    -- Ensure our settings table carries over (defaults to enabled)
    Database.settings = Database.settings or {}
    if Database.settings.achievementTracking == nil then
        Database.settings.achievementTracking = true
    end
 
    -- Settings defaults (shared with RatedStats_Achiev)
    if Database.settings.mainTellUpdates == nil then
        Database.settings.mainTellUpdates = true
    end
    if Database.settings.achievTellUpdates == nil then
        Database.settings.achievTellUpdates = true
    end
    if Database.settings.achievAnnounceOnQueue == nil then
        Database.settings.achievAnnounceOnQueue = true
    end

    -- Dropdown values:
    -- 0=none, 1=self (print), 2=party, 3=instance, 4=say, 5=yell, 6=raid, 7=party(only5)
    if Database.settings.achievAnnounceSS == nil then
        Database.settings.achievAnnounceSS = 3 -- instance
    end
    if Database.settings.achievAnnounce2v2 == nil then
        Database.settings.achievAnnounce2v2 = 2 -- party
    end
    if Database.settings.achievAnnounce3v3 == nil then
        Database.settings.achievAnnounce3v3 = 2 -- party
    end
    if Database.settings.achievAnnounceRBG == nil then
        Database.settings.achievAnnounceRBG = 1 -- self
    end
    if Database.settings.achievAnnounceRBGB == nil then
        Database.settings.achievAnnounceRBGB = 1 -- self
    end

    -- Migrate old/invalid achievement announce settings to numeric dropdown values.
    local function CoerceAnnounceValue(v, fallback)
        if type(v) == "number" then
            if v >= 1 and v <= 7 then return v end
            return fallback
        end
        if type(v) == "string" then
            local s = v:lower()
            if s == "none" or s == "off" or s == "disabled" then return 0 end
            if s == "self" or s == "print" then return 1 end
            if s == "party" then return 2 end
            if s == "party(only5)" or s == "party_only5" or s == "partyonly5" then return 7 end
            if s == "raid" then return 6 end
            if s == "instance" or s == "instance_chat" or s == "instancechat" then return 3 end
            if s == "say" then return 4 end
            if s == "yell" then return 5 end
            return fallback
        end
        return fallback
    end

    Database.settings.achievAnnounceSS   = CoerceAnnounceValue(Database.settings.achievAnnounceSS,   3)
    Database.settings.achievAnnounce2v2  = CoerceAnnounceValue(Database.settings.achievAnnounce2v2,  2)
    Database.settings.achievAnnounce3v3  = CoerceAnnounceValue(Database.settings.achievAnnounce3v3,  2)
    Database.settings.achievAnnounceRBG  = CoerceAnnounceValue(Database.settings.achievAnnounceRBG,  1)
    Database.settings.achievAnnounceRBGB = CoerceAnnounceValue(Database.settings.achievAnnounceRBGB, 1)

    -- Enforce bracket-valid sets so the UI never shows "Custom"
    -- SS: none/self/say/yell/instance
    do
        local v = Database.settings.achievAnnounceSS
        if not (v == 0 or v == 1 or v == 4 or v == 5 or v == 3) then
            Database.settings.achievAnnounceSS = 3
        end
    end
    -- 2v2: none/self/say/yell/party
    do
        local v = Database.settings.achievAnnounce2v2
        if not (v == 0 or v == 1 or v == 4 or v == 5 or v == 2) then
            Database.settings.achievAnnounce2v2 = 2
        end
    end
    -- 3v3: none/self/say/yell/party
    do
        local v = Database.settings.achievAnnounce3v3
        if not (v == 0 or v == 1 or v == 4 or v == 5 or v == 2) then
            Database.settings.achievAnnounce3v3 = 2
        end
    end
    -- RBG: none/self/say/yell/party(only5)/raid/instance
    do
        local v = Database.settings.achievAnnounceRBG
        -- If anyone previously used plain party (2), convert to party(only5) (7)
        if v == 2 then v = 7 end
        if not (v == 0 or v == 1 or v == 4 or v == 5 or v == 7 or v == 6 or v == 3) then
            v = 1
        end
        Database.settings.achievAnnounceRBG = v
    end
    -- RBGB: none/self/say/yell/instance
    do
        local v = Database.settings.achievAnnounceRBGB
        if not (v == 0 or v == 1 or v == 4 or v == 5 or v == 3) then
            Database.settings.achievAnnounceRBGB = 1
        end
    end

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
function RSTATS:ClearDatabase()
    RSTATS_Database = {}
    RSTATS.Database[playerName] = {}
    Database = {}
    RSTATS.Config = {}
end

-- Function to get CR and MMR based on categoryID
function GetCRandMMR(categoryID)
    local cr = select(1, GetPersonalRatedInfo(categoryID))
    local mmr

    -- Arena MMR: GetPersonalRatedInfo no longer provides this (select(10) is nil -> 0).
    -- While the post-game scoreboard is up, team info has ratingMMR.
    if (categoryID == 1 or categoryID == 2)
        and C_PvP and C_PvP.GetTeamInfo
        and C_PvP.IsRatedArena and C_PvP.IsRatedArena()
    then
        local teamInfo = C_PvP.GetTeamInfo(0)
        mmr = teamInfo and teamInfo.ratingMMR
    end

    -- Legacy fallback (harmless if nil)
    if mmr == nil then
        mmr = select(10, GetPersonalRatedInfo(categoryID))
    end

    -- Spec-based brackets: NEVER fall back to saved non-spec values.
    -- If the API returns 0/nil for a spec you haven't played yet, keep it 0
    -- unless we can recover from THIS spec's history bucket.
    if categoryID == 7 or categoryID == 9 then
        cr  = tonumber(cr)  or 0
        mmr = tonumber(mmr) or 0

        if (cr == 0 or mmr == 0) and EnsureSpecHistory and RSTATS.GetActiveSpecIDAndName then
            local specID, specName = RSTATS.GetActiveSpecIDAndName()
            if specID then
                local t = EnsureSpecHistory(categoryID, specID, specName)
                if type(t) == "table" and #t > 0 then
                    -- Find the last non-initial row if possible
                    for i = #t, 1, -1 do
                        local e = t[i]
                        if e and not e.isInitial then
                            cr  = tonumber(e.friendlyCR)  or cr
                            mmr = tonumber(e.friendlyMMR) or mmr
                            break
                        end
                    end

                    -- If we only have Initial, that is still spec-correct (usually 0/0)
                    if cr == 0 or mmr == 0 then
                        local e = t[#t]
                        if e then
                            cr  = tonumber(e.friendlyCR)  or cr
                            mmr = tonumber(e.friendlyMMR) or mmr
                        end
                    end
                end
            end
        end

        return cr, mmr
    end

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
	if mapShortName == "Cage of Carnage" then
		mapShortName = "COC"
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
-- Solo Shuffle: remember which scoreboard "team index" we belonged to at the
-- moment the round ended (so we can keep our team on the left even if the UI
-- reshuffles groups afterwards).
local soloShuffleMyTeamIndexAtDeath = nil
-- Solo Shuffle: per-round allies (GUID set) captured at the moment the round ends.
-- This is the only reliable way to force "my team" on the left in SS.
local soloShuffleAlliesGUIDAtDeath = nil
local soloShuffleAlliesKBAtDeath   = nil  -- Solo Shuffle: per-round ally KB snapshot at round end

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

local soloShuffleLastFriendlyKBTotal = nil
local soloShuffleLastEnemyKBTotal    = nil

-- Main frame for registering events
local frame = CreateFrame("Frame")
frame:RegisterEvent("PVP_MATCH_ACTIVE")
frame:RegisterEvent("PVP_MATCH_COMPLETE")
frame:RegisterEvent("UPDATE_UI_WIDGET")
frame:SetScript("OnEvent", OnWidgetUpdate)

local function BuildObjectiveTextFromStats(stats)
    if type(stats) ~= "table" or #stats == 0 then
        return "-"
    end

    local byName = {}
    local ordered = {}

    for _, s in ipairs(stats) do
        local name = (s.name or ""):lower()
        local val  = tonumber(s.pvpStatValue) or 0
        if name ~= "" then
            byName[name] = val
        end
        ordered[#ordered + 1] = { orderIndex = tonumber(s.orderIndex) or 0, value = val }
    end

    local function findAny(substrings)
        for _, sub in ipairs(substrings) do
            for n, v in pairs(byName) do
                if n:find(sub, 1, true) then
                    return v
                end
            end
        end
        return nil
    end

    local baseCaps = findAny({ "bases assaulted", "bases captured" })
    local baseDefs = findAny({ "bases defended" })
    local flagCaps = findAny({ "flags captured", "flag captures" })
    local flagRets = findAny({ "flags returned", "flag returns" })

    -- EOTS: flag caps + base caps/defs
    if flagCaps ~= nil and baseCaps ~= nil then
        baseDefs = baseDefs or 0
        return string.format("%d / %d / %d", flagCaps, baseCaps, baseDefs)
    end

    -- WSG / Twin Peaks: flag caps + returns
    if flagCaps ~= nil and flagRets ~= nil then
        return string.format("%d / %d", flagCaps, flagRets)
    end

    -- AB / DWG / BfG: base caps/defs
    if baseCaps ~= nil and baseDefs ~= nil then
        return string.format("%d / %d", baseCaps, baseDefs)
    end

    -- Deephaul Ravine: crystal + cart points (prefer crystal detection so SSM doesn't steal it)
    local crystalPts = findAny({ "crystal points", "deephaul crystal", "crystal score", "crystals captured" })
    if crystalPts ~= nil then
        local cartPts = findAny({ "cart points", "mine cart points", "cart score" }) or 0
        return string.format("%d / %d", crystalPts, cartPts)
    end

    -- Temple of Kotmogu: orbs + points
    local orbsHeld  = findAny({ "orbs held", "orb holds", "orb possessions", "orb possession" })
    if orbsHeld ~= nil then
        local orbPts = findAny({ "orb points", "points", "score" }) or 0
        return string.format("%d / %d", orbsHeld, orbPts)
    end

    -- Silvershard Mines: cart points (and sometimes cart captures)
    local cartCaps = findAny({ "carts captured", "mine carts captured", "carts controlled", "mine carts controlled" })
    local cartPts  = findAny({ "cart points", "mine cart points", "points", "score" })
    if cartCaps ~= nil and cartPts ~= nil then
        return string.format("%d / %d", cartCaps, cartPts)
    end
    if cartPts ~= nil then
        return tostring(cartPts)
    end

    -- Fallback: show first 3 stats by orderIndex (still better than blank)
    table.sort(ordered, function(a, b) return a.orderIndex < b.orderIndex end)
    local parts = {}
    for i = 1, math.min(3, #ordered) do
        parts[#parts + 1] = tostring(ordered[i].value)
    end
    return (#parts > 0) and table.concat(parts, " / ") or "-"
end

-- RBGB: if queued as a 2-man home party, return the partner Name-Realm, otherwise nil.
local function GetRBGBDuoPartnerNameRealm()
    if not IsInGroup(LE_PARTY_CATEGORY_HOME) then return nil end
    if IsInRaid(LE_PARTY_CATEGORY_HOME) then return nil end

    local n = GetNumGroupMembers(LE_PARTY_CATEGORY_HOME) or 0
    if n ~= 2 then return nil end

    local myName = UnitName("player")
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) and UnitIsPlayer(unit) then
            local name, realm = UnitFullName(unit)
            if name and name ~= myName then
                if not realm or realm == "" then
                    realm = GetRealmName()
                end
                return name .. "-" .. realm
            end
        end
    end

    return nil
end

local function GetPlayerStatsEndOfMatch(cr, mmr, historyTable, roundIndex, categoryName, categoryID, startTime)
    local mapID = GetCurrentMapID()
    local mapName = GetMapName(mapID) or "Unknown"
    local endTime = GetTimestamp()
    local isSoloShuffle = (C_PvP.IsRatedSoloShuffle and C_PvP.IsRatedSoloShuffle()) or false
    local isArena = (C_PvP.IsRatedArena and C_PvP.IsRatedArena()) and not isSoloShuffle

    -- Default (BG logic): Horde/Alliance
    local teamFaction = GetPlayerFactionGroup()  -- "Horde" or "Alliance"
    local enemyFaction = teamFaction == "Horde" and "Alliance" or "Horde"

    -- Arena: overwrite to Purple/Gold using numeric team index.
    -- Purple = 0, Gold = 1
    local myArenaTeamIndex
    if isArena then
        local myGUID = UnitGUID("player")
        for i = 1, GetNumBattlefieldScores() do
            local s = C_PvP.GetScoreInfo(i)
            if s and s.guid and s.guid == myGUID then
                myArenaTeamIndex = s.faction
                break
            end
        end
        if myArenaTeamIndex ~= nil then
            if myArenaTeamIndex == 1 then
                teamFaction = "Gold"
                enemyFaction = "Purple"
            else
                teamFaction = "Purple"
                enemyFaction = "Gold"
            end
        end
    end

    -- For Solo Shuffle we want to anchor "my team" based on the team index we
    -- belonged to at the moment the round ended, not whatever reshuffles the
    -- scoreboard UI may have done afterwards.
    local alliesGUID = soloShuffleAlliesGUIDAtDeath

    -- Ensure "my team" set always includes me (defensive; depends on how you fill soloShuffleAlliesGUIDAtDeath)
    if C_PvP.IsRatedSoloShuffle and C_PvP.IsRatedSoloShuffle() then
        alliesGUID = alliesGUID or {}
        local myGUID = UnitGUID("player")
        if myGUID then
            alliesGUID[myGUID] = true
        end
    end

    local friendlyTotalDamage, friendlyTotalHealing, enemyTotalDamage, enemyTotalHealing = 0, 0, 0, 0
    -- Win/Loss:
    -- - Arena uses numeric team index (0/1)
    -- - BG uses Horde/Alliance mapping (0 Horde, 1 Alliance)
    local battlefieldWinnerRaw = GetBattlefieldWinner()
    local friendlyWinLoss
    if isArena and myArenaTeamIndex ~= nil then
        friendlyWinLoss = (battlefieldWinnerRaw == myArenaTeamIndex) and "+   W" or "+   L"
    else
        local battlefieldWinner = (battlefieldWinnerRaw == 0) and "Horde" or "Alliance"
        friendlyWinLoss = (battlefieldWinner == teamFaction) and "+   W" or "+   L"
    end
	previousRoundsWon = previousRoundsWon or 0
    roundsWon = roundsWon or 0
	local duration = GetBattlefieldInstanceRunTime() / 1000  -- duration in seconds
	local damp = C_Commentator.GetDampeningPercent()
    -- BG objectives (per-player), pulled from scoreInfo.stats
    local objectiveByGUID = {}

    -- ------------------------------------------------------------
    -- Solo Shuffle: determine THIS round's win via KB increment on the 3 allies
    -- captured at PVP_MATCH_STATE_CHANGED ("Death").
    --
    -- Why: SS players rotate teams. A running total delta across *different*
    -- ally sets causes "ghost wins" when a player with existing KB rotates onto
    -- your next team. So we snapshot the 3 allies' KB at Death, then on the next
    -- PVP_MATCH_ACTIVE we check whether any of those 3 gained +1 KB.
    --
    -- No extra guard variable: we still only update roundsWon and keep your
    -- existing (roundsWon > previousRoundsWon) W/L logic below.
    -- ------------------------------------------------------------
    if C_PvP.IsRatedSoloShuffle and C_PvP.IsRatedSoloShuffle() and roundIndex then
        alliesGUID = soloShuffleAlliesGUIDAtDeath or alliesGUID or {}
        local myGUID = UnitGUID("player")
        if myGUID then
            alliesGUID[myGUID] = true
        end

        -- Snapshot BEFORE we possibly increment this round.
        previousRoundsWon = roundsWon

        local wonThisRound = false
        if soloShuffleAlliesKBAtDeath then
            for i = 1, GetNumBattlefieldScores() do
                local scoreInfo = C_PvP.GetScoreInfo(i)
                if scoreInfo and scoreInfo.guid and alliesGUID[scoreInfo.guid] then
                    local prevKB = soloShuffleAlliesKBAtDeath[scoreInfo.guid]
                    if prevKB ~= nil then
                        local nowKB = tonumber(scoreInfo.killingBlows) or 0
                        if nowKB > prevKB then
                            wonThisRound = true
                            break
                        end
                    end
                end
            end
        end

        -- If any of the 3 allies gained a KB since Death, count it as a round win.
        -- If not, treat it as not-a-win (loss/timeout) as you requested.
        if wonThisRound then
            roundsWon = roundsWon + 1
        end
    end

	if C_PvP.IsRatedSoloShuffle() and roundIndex then
		-- Hard guard: Solo Shuffle rounds are 1..6. If upstream forgot to reset, don't let it poison math/UI.
		if type(roundIndex) ~= "number" or roundIndex < 1 or roundIndex > 6 then
			roundIndex = 1
		end

		-- If startTime wasn't recorded, derive it from the current round duration.
		if type(startTime) ~= "number" then
			startTime = endTime - duration
		end

		local totalPreviousDuration = 0
		local totalRoundsToLookBack = roundIndex - 1

		-- Sum durations of previous rounds
		for i = 1, #historyTable do
			local entry = historyTable[i]
			if entry and entry.duration and totalRoundsToLookBack > 0 and type(entry.duration) == "number" then
				totalPreviousDuration = totalPreviousDuration + entry.duration
				totalRoundsToLookBack = totalRoundsToLookBack - 1
			end
		end
	
		duration = (endTime - startTime) - totalPreviousDuration
		if duration < 0 then duration = 0 end
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
            local deaths = tonumber(scoreInfo.deaths) or 0
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
            local guid = scoreInfo.guid
            local stats = scoreInfo.stats
            if guid then
                objectiveByGUID[guid] = BuildObjectiveTextFromStats(stats)
            end

            -- Ensure damageDone and healingDone are numbers
            damageDone = tonumber(damageDone) or 0
            healingDone = tonumber(healingDone) or 0

            if C_PvP.IsRatedSoloShuffle and C_PvP.IsRatedSoloShuffle() and alliesGUID then
                -- Solo Shuffle: friendly == me + party1 + party2 for THIS round.
                if guid and alliesGUID[guid] then
                    friendlyTotalDamage = friendlyTotalDamage + damageDone
                    friendlyTotalHealing = friendlyTotalHealing + healingDone
                else
                    enemyTotalDamage = enemyTotalDamage + damageDone
                    enemyTotalHealing = enemyTotalHealing + healingDone
                end
            else
                -- Non-SS:
               -- Arena uses numeric team index; BG can be Horde/Alliance (string) or 0/1 (number).
               if isArena and myArenaTeamIndex ~= nil then
                   if faction == myArenaTeamIndex then
                       friendlyTotalDamage = friendlyTotalDamage + damageDone
                       friendlyTotalHealing = friendlyTotalHealing + healingDone
                   else
                       enemyTotalDamage = enemyTotalDamage + damageDone
                       enemyTotalHealing = enemyTotalHealing + healingDone
                   end
               else
                   local factionKey = faction
                   if type(factionKey) == "number" then
                       factionKey = (factionKey == 0) and "Horde" or "Alliance"
                   end
                   if factionKey == teamFaction then
                       friendlyTotalDamage = friendlyTotalDamage + damageDone
                       friendlyTotalHealing = friendlyTotalHealing + healingDone
                   elseif factionKey == enemyFaction then
                       enemyTotalDamage = enemyTotalDamage + damageDone
                       enemyTotalHealing = enemyTotalHealing + healingDone
                   end
                end
            end
        end
    end

    -- Debug: Print final team scores before saving

    -- Unregister the events after obtaining the raid leader information
    UnregisterRaidLeaderEvents()

    AppendHistory(historyTable, roundIndex, cr, mmr, mapName, endTime, duration, teamFaction, enemyFaction, friendlyTotalDamage, friendlyTotalHealing, enemyTotalDamage, enemyTotalHealing, friendlyWinLoss, friendlyRaidLeader, enemyRaidLeader, friendlyRatingChange, enemyRatingChange, allianceTeamScore, hordeTeamScore, roundsWon, categoryName, categoryID, damp, objectiveByGUID)

    -- Safe to clear AFTER stats capture:
    -- GetPlayerStatsEndOfMatch has consumed soloShuffleAlliesGUIDAtDeath/KBAtDeath
    -- for totals + W/L, and AppendHistory has consumed them for per-player "isFriendly".
    if C_PvP.IsRatedSoloShuffle and C_PvP.IsRatedSoloShuffle() then
        soloShuffleMyTeamIndexAtDeath = nil
        soloShuffleAlliesGUIDAtDeath  = nil
        soloShuffleAlliesKBAtDeath    = nil
    end

	-- Call CheckPlayerTalents to process talents for new matches
--	CheckPlayerTalents(playerName, true)  -- `true` indicates this is a new game and should check talents

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

function InitialCRMMRExists()
    local historyTables = {
        "SoloShuffleHistory",
        "v2History",
        "v3History",
        "RBGHistory",
        "SoloRBGHistory"
    }

    for _, tableName in ipairs(historyTables) do
        local history = Database[tableName]
        if history then
            for _, match in ipairs(history) do
                if match.isInitial then
                    return true
                end
            end
        end
    end

    return false
end

function RefreshDataEvent(self, event, ...)

	local roundWasWon = false

    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(3, function()
            local dataExists = LoadData()
            local isValidData = IsDataValid()

			if not dataExists or not isValidData then
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
            -- Make sure we always have a round index for Shuffle.
            if roundIndex == nil then
                roundIndex = 1
            end

            -- If we saw a round-ending "Death" (via PVP_MATCH_STATE_CHANGED),
            -- treat this PVP_MATCH_ACTIVE as the point where the scoreboard is
            -- final and create the row now.
            if self.isSoloShuffle and roundIndex and playerDeathSeen then
				local thisRound = roundIndex
				roundIndex = roundIndex + 1
			
				C_Timer.After(1, function()
					local cr, mmr = GetCRandMMR(7)
					local historyTable = Database.SoloShuffleHistory
					Database.CurrentCRforSoloShuffle = cr
					Database.CurrentMMRforSoloShuffle = mmr
					GetPlayerStatsEndOfMatch(cr, mmr, historyTable, thisRound, "SoloShuffle", 7, startTime)
				end)

                C_Timer.After(45, function()
                    GetTalents:Start()
                end)
            end

            previousRoundsWon = roundsWon or 0
            -- Reset per-round flags for the upcoming round.
            lastLoggedRound = {}
            scoreboardDeaths = {}
            scoreboardKBTotal = 0
	
			elseif C_PvP.IsRatedArena() or C_PvP.IsRatedBattleground() or C_PvP.IsSoloRBG() then
				self.isSoloShuffle = nil
	
				-- ✅ Start talent scan for other brackets (2v2, 3v3, RBG, etc.)
				local matchBracket = C_PvP.GetActiveMatchBracket()
				local tableMap = {
					[0] = "v2History",
					[1] = "v3History",
					[4] = "RBGHistory",
					[9] = "SoloRBGHistory",
				}
				local historyKey = tableMap[matchBracket]
				local historyTable = historyKey and Database[historyKey]
				
				C_Timer.After(120, function()
					GetTalents:Start()
				end)
			end
		end)

    elseif event == "PVP_MATCH_COMPLETE" then
        C_Timer.After(1, function()
			if GetTalents then
				GetTalents:Stop(false)
			end

            if self.isSoloShuffle then
                if roundIndex and playerDeathSeen then
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
                scoreboardKBTotal = nil
				soloShuffleMyTeamIndexAtDeath = nil
                soloShuffleAlliesGUIDAtDeath = nil
                soloShuffleAlliesKBAtDeath   = nil
                soloShuffleLastFriendlyKBTotal = nil
                soloShuffleLastEnemyKBTotal    = nil
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

-- Debug toggle (off by default). Enable with: /run RSTATS_DEBUG_SPEC=true
-- Disable with: /run RSTATS_DEBUG_SPEC=false
local function SpecDebug(...)
    if not _G.RSTATS_DEBUG_SPEC then return end
    local msg = string.format(...)
    print(string.format("|cffb69e86Rated Stats:|r [Spec] t=%.3f %s", GetTime(), msg))
end

-- Refresh UI + seed spec-scoped Initials when the player changes spec/talents.
-- Must run even if the window is closed (talents UI closes Rated Stats).
do
    local specRefreshFrame = CreateFrame("Frame")
    specRefreshFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    specRefreshFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    specRefreshFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    specRefreshFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    specRefreshFrame:RegisterEvent("PVP_RATED_STATS_UPDATE")  -- Covers CR/MMR changes on spec switching

    local lastspecID
    local pendingSeedSpecID
    local pendingSeedSpecName

    local function GetAPISpecIDAndName()
        local sidx = GetSpecialization and GetSpecialization() or nil
        if not sidx or not GetSpecializationInfo then return nil end
        local sid, name = GetSpecializationInfo(sidx)
        return sid, name
    end

    local function QueueInitialSeedIfNeeded()
        if not (EnsureSpecHistory and GetInitialCRandMMR) then return end

        local specID, specName = GetAPISpecIDAndName()
        if not specID then return end

        local ss   = EnsureSpecHistory(7, specID, specName) -- Solo Shuffle
        local rbgb = EnsureSpecHistory(9, specID, specName) -- Solo RBG

        if (type(ss) == "table" and #ss == 0) or (type(rbgb) == "table" and #rbgb == 0) then
            pendingSeedSpecID = specID
            pendingSeedSpecName = specName
            RequestRatedInfo() -- triggers PVP_RATED_STATS_UPDATE when fresh
        end
    end

    local function DoFullRefresh()
        -- Spec/talent changed: force rebuild next time the window opens.
        RSTATS.__SpecDirty = true

        -- Queue seeding, but ONLY perform it after PVP_RATED_STATS_UPDATE so stats are fresh for the new spec.
        QueueInitialSeedIfNeeded()

        -- If the window is open right now, refresh displays immediately.
        if UIConfig and UIConfig.IsShown and UIConfig:IsShown() then
            UpdateSoloShuffleDisplay()
            Update2v2Display()
            Update3v3Display()
            UpdateRBGDisplay()
            UpdateSoloRBGDisplay()

            local tabID = PanelTemplates_GetSelectedTab(RSTATS.UIConfig)
            if tabID then
                local dropdown = RSTATS.Dropdowns and RSTATS.Dropdowns[tabID]
                local selected = dropdown and UIDropDownMenu_GetText(dropdown) or "Today"
                local filterKey = selected:lower():gsub(" ", "") or "today"

                local content = RSTATS.ScrollContents and RSTATS.ScrollContents[tabID]
                if content then
                    ClearStaleMatchFrames(content)
                end

                FilterAndSearchMatches(RatedStatsSearchBox and RatedStatsSearchBox:GetText() or "")
                RSTATS:UpdateStatsView(filterKey, tabID)
                UpdateCompactHeaders(tabID)
            end

            if RSTATS.Summary and RSTATS.Summary.frame and RSTATS.Summary.frame:IsShown() then
                RSTATS.Summary:Refresh()
            end
        end
    end

    local function InitLastSpec()
        local sid = GetAPISpecIDAndName()
        if sid then
            lastSpecID = sid
        end
    end

    specRefreshFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_ENTERING_WORLD" then
            InitLastSpec()
            -- Pre-backfill the current spec buckets so opening the window doesn't show "waiting".
            local sid, sname = GetAPISpecIDAndName()
            if sid and EnsureSpecHistory then
                EnsureSpecHistory(7, sid, sname)
                EnsureSpecHistory(9, sid, sname)
            end
            RequestRatedInfo()
            return
        end

        if event == "PVP_RATED_STATS_UPDATE" then
            if pendingSeedSpecID and GetInitialCRandMMR then
                local sid = select(1, GetAPISpecIDAndName())
                if sid and sid == pendingSeedSpecID then
                    pendingSeedSpecID = nil
                    pendingSeedSpecName = nil
                    GetInitialCRandMMR()
                end
            end
            return
        end

        if event == "PLAYER_TALENT_UPDATE" then
            -- Force the rated stats refresh for the new spec (Blizzard does this too).
            RequestRatedInfo()
        end

        -- Burst events fire while Blizzard swaps spec; poll briefly until API spec id flips.
        if specRefreshFrame._specTicker then
            specRefreshFrame._specTicker:Cancel()
            specRefreshFrame._specTicker = nil
        end

        local beforeID = lastSpecID
        local tries = 0

        specRefreshFrame._specTicker = C_Timer.NewTicker(0.05, function()
            tries = tries + 1

            local sid = select(1, GetAPISpecIDAndName())

            -- If spec changed (or we never had one), refresh now.
            if sid and (not beforeID or sid ~= beforeID) then
                lastSpecID = sid
                specRefreshFrame._specTicker:Cancel()
                specRefreshFrame._specTicker = nil

                -- Clear tab-scoped filters for SS/RBGB so the new spec's Initial can't be hidden.
                RatedStatsFilters = RatedStatsFilters or {}
                RatedStatsFilters[1] = {}
                RatedStatsFilters[5] = {}

                -- Reset growth counters so the next open/reflow isn't stuck.
                RSTATS.__LastHistoryCount = RSTATS.__LastHistoryCount or {}
                RSTATS.__LastHistoryCount[1] = 0
                RSTATS.__LastHistoryCount[5] = 0

                DoFullRefresh()
                return
            end

            -- Failsafe after ~0.5s: refresh anyway (covers talent-only edits).
            if tries >= 10 then
                if sid then lastSpecID = sid end
                specRefreshFrame._specTicker:Cancel()
                specRefreshFrame._specTicker = nil
                DoFullRefresh()
            end
        end)
    end)
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
            [1473] = 8,      -- Augmentation Evoker (DPS)
        
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

-- ==========================================================
-- Active spec helpers (used by initial entries + spec history)
-- ==========================================================
function RSTATS.GetActiveSpecIDAndName()
    local specIndex = GetSpecialization()
    if not specIndex then return nil, nil end
    local specID, specName = GetSpecializationInfo(specIndex)
    return specID, specName
end

-- ==========================================================
-- Spec-scoped history helpers (SS / Solo RBG)
-- ==========================================================
if not EnsureSpecHistory then
    function EnsureSpecHistory(categoryID, specID, specName)
        if not Database or not categoryID or not specID then return nil end

        local bySpecKey = (categoryID == 7 and "SoloShuffleHistoryBySpec")
                       or (categoryID == 9 and "SoloRBGHistoryBySpec")
                       or nil
        if not bySpecKey then return nil end

        Database[bySpecKey] = Database[bySpecKey] or {}
        local bucket = Database[bySpecKey]

        bucket._specNames = bucket._specNames or {}
        if specName and specName ~= "" then
            bucket._specNames[specID] = specName
        end

        if type(bucket[specID]) ~= "table" then
            bucket[specID] = {}
        end

        -- One-time backfill from the main history table so spec switching shows existing rows.
        bucket._backfilled = bucket._backfilled or {}
        if not bucket._backfilled[specID] and #bucket[specID] == 0 then
            local baseKey = (categoryID == 7 and "SoloShuffleHistory")
                        or (categoryID == 9 and "SoloRBGHistory")
                        or nil
            local base = baseKey and Database[baseKey]
            if type(base) == "table" then
                for _, entry in ipairs(base) do
                    if entry then
                        local match = false
                        if entry.specID and entry.specID == specID then
                            match = true
                        elseif specName and entry.specName and entry.specName == specName then
                            match = true
                        elseif specName and type(entry.playerStats) == "table" then
                            for _, ps in ipairs(entry.playerStats) do
                                if ps and ps.name == (_G.playerName or playerName) and ps.spec == specName then
                                    match = true
                                    break
                                end
                            end
                        end
                        if match then
                            table.insert(bucket[specID], entry)
                        end
                    end
                end
            end
            bucket._backfilled[specID] = true
        end
        return bucket[specID]
    end
end

-- If another file already defines this, don't override it.
if RSTATS and not RSTATS.GetHistoryForTab then
    function RSTATS:GetHistoryForTab(tabID)
        if tabID == 1 then
            local specID, specName = RSTATS.GetActiveSpecIDAndName()
            local t = specID and EnsureSpecHistory(7, specID, specName)
            if specID then
                return EnsureSpecHistory(7, specID, specName) or {}
            end
            return (Database.SoloShuffleHistory or {})
        elseif tabID == 5 then
            local specID, specName = RSTATS.GetActiveSpecIDAndName()
            local t = specID and EnsureSpecHistory(9, specID, specName)
            if specID then
                return EnsureSpecHistory(9, specID, specName) or {}
            end
            return (Database.SoloRBGHistory or {})
        end

        return ({
            [2] = Database.v2History,
            [3] = Database.v3History,
            [4] = Database.RBGHistory,
        })[tabID] or {}
    end
end

-- Function to get initial and current CR and MMR values
function GetInitialCRandMMR()
    local function EntryMatchesSpec(entry, specID, specName)
        if not entry or not specID then return false end
        if entry.specID and entry.specID == specID then
            return true
        end
        if specName and entry.specName and entry.specName == specName then
            return true
        end
        if specName and type(entry.playerStats) == "table" then
            for _, ps in ipairs(entry.playerStats) do
                if ps and ps.name == playerName and ps.spec == specName then
                    return true
                end
            end
        end
        return false
    end

    local function SpecHasAnyHistory(categoryID, baseKey, specID, specName)
        if EnsureSpecHistory then
            local t = EnsureSpecHistory(categoryID, specID, specName)
            if type(t) == "table" and #t > 0 then
                return true
            end
        end
        local base = Database and Database[baseKey]
        if type(base) == "table" then
            for _, entry in ipairs(base) do
                if EntryMatchesSpec(entry, specID, specName) then
                    return true
                end
            end
        end
        return false
    end

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
        local historyTable = Database[historyTableName]

        -- Get initial CR, MMR, and played games
        local cr = GetInitialCR(categoryID)
        local mmr = GetInitialMMR(categoryID)
        local played = GetPlayedGames(categoryID)

		-- Store played games per bracket
		local playedField = "Playedfor" .. categoryName
		Database[playedField] = played

        local duoPartner = nil
        if categoryID == 9 then -- Solo RBG (RBGB)
            duoPartner = GetRBGBDuoPartnerNameRealm()
        end

        local mySpecID, mySpecName = RSTATS.GetActiveSpecIDAndName()

        -- Only insert an initial entry if this bracket actually has no history.
        -- For spec-based ladders (SS/RBGB), only insert if THIS spec has no history.
         if categoryID == 7 or categoryID == 9 then
            if mySpecID and mySpecName then
                -- 1) Prefer the spec bucket (new storage)
                if EnsureSpecHistory then
                    local specTable = EnsureSpecHistory(categoryID, mySpecID, mySpecName)
                    if type(specTable) == "table" and #specTable > 0 then
                        return
                    end
                end

                -- 2) Legacy safety net: if the main table already contains rows for this spec,
                --    do NOT create a new Initial (backfill may fail on old name formats).
                for _, entry in ipairs(historyTable) do
                    if entry then
                        if entry.specID and entry.specID == mySpecID then
                            return
                        end
                        if entry.specName and entry.specName == mySpecName then
                            return
                        end
                        if mySpecName and type(entry.playerStats) == "table" then
                            for _, ps in ipairs(entry.playerStats) do
                                if ps and ps.name == playerName and ps.spec == mySpecName then
                                    return
                                end
                            end
                        end
                    end
                end
            else
                -- No spec info available: fall back to main table.
                if #historyTable > 0 then
                    return
                end
            end
        else
            if #historyTable > 0 then
                return
            end
        end

        -- Create an entry with the current timestamp
        local entry = {
			matchID = 1,
            timestamp = GetTimestamp(),
            specID = mySpecID,
            specName = mySpecName,
            cr = cr,
            mmr = "-",
            isInitial = true,
            winLoss = "I",  -- Initial
			friendlyWinLoss = "I",
            mapName = "N/A",
            endTime = GetTimestamp(),
            duration = "N/A",
            duoPartner = duoPartner,
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
                    faction = UnitFactionGroup("player"),
                    race = UnitRace("player"),
                    class = UnitClass("player"),
                    spec = GetSpecialization() and select(2, GetSpecializationInfo(GetSpecialization())) or "N/A",
                    role = GetPlayerRole(),
                    newrating = cr,
                    killingBlows = "-",
                    honorableKills = "-",
                    deaths = "-",
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
				faction = "-",
				race = "-",
				class = "-",
				spec = "-",
				role = "-",
				newrating = "-",
				killingBlows = "-",
				honorableKills = "-",
                deaths = "-",
				damage = "-",
				healing = "-",
				ratingChange = "-"
			})
		end

        -- Insert the entry:
        -- - Non-spec brackets: main table only
        -- - SS/RBGB: insert into spec table; only insert into main if it's completely empty (keeps main clean)
        if categoryID == 7 or categoryID == 9 then
            if EnsureSpecHistory and mySpecID then
                local specTable = EnsureSpecHistory(categoryID, mySpecID, mySpecName)
                if type(specTable) == "table" then
                    table.insert(specTable, 1, entry)
                end
            end
            if #historyTable == 0 then
                table.insert(historyTable, 1, entry)
            end
        else
            table.insert(historyTable, 1, entry)
        end

    end

    -- Iterate over categories and store initial CR, MMR, and played games
    for categoryName in pairs(categoryMappings) do
        StoreInitialCRMMRandPlayed(categoryName)
    end

    SaveData()
end

-- ==========================================================
-- Spec-based rated ladders (SS / Solo RBG) need spec-scoped history
-- ==========================================================
-- Helper function to get player full name
function GetPlayerFullName()
    local name = UnitName("player")
    local realm = GetRealmName()
    return name .. "-" .. realm
end

-- Prevent overlapping login retries from creating duplicate "missed game" inserts.
local _missedGamesRunToken = 0

function CheckForMissedGames()
---    local function Log(msg)
---        -- Green [Debug] label, yellow message
---        print("|cff00ff00[Debug]|r " .. "|cffffff00" .. msg .. "|r")
---    end

---    Log("CheckForMissedGames triggered.")
    _missedGamesRunToken = _missedGamesRunToken + 1
    local runToken = _missedGamesRunToken

    local categoryMappings = {
        SoloShuffle = { id = 7, historyTable = "SoloShuffleHistory", displayName = "SoloShuffle" },
        ["2v2"] = { id = 1, historyTable = "v2History", displayName = "2v2" },
        ["3v3"] = { id = 2, historyTable = "v3History", displayName = "3v3" },
        RBG = { id = 4, historyTable = "RBGHistory", displayName = "RBG" },
        SoloRBG = { id = 9, historyTable = "SoloRBGHistory", displayName = "SoloRBG" }
    }

	local function StoreMissedGame(categoryName, category, attempts)
        -- If a newer CheckForMissedGames() call started, abandon this chain.
        if runToken ~= _missedGamesRunToken then
            return
        end

		local _, _, _, totalGames = GetPersonalRatedInfo(category.id)
		attempts = attempts or 0
		
		if not totalGames or totalGames == 0 then
			if attempts < 10 then
---			Log("Skipped category ID " .. category.id .. " — totalGames is nil.")
				C_Timer.After(3, function()
                    if runToken ~= _missedGamesRunToken then return end
					StoreMissedGame(categoryName, category, attempts + 1)
				end)
			end
			return
		end
	
		local playedField = "Playedfor" .. categoryName
		-- If this bracket has never been initialised for THIS character,
		-- do NOT backfill their entire lifetime as "missed games".
		-- Just sync the counter and move on.
		if Database[playedField] == nil then
			Database[playedField] = totalGames
			return
		end

		local lastRecorded = tonumber(Database[playedField]) or 0
		local historyTable = Database[category.historyTable]
		if type(historyTable) ~= "table" then
			historyTable = {}
			Database[category.historyTable] = historyTable
		end
	
        -- If we already have history rows but Playedfor* is missing/stale, do NOT backfill.
        -- Just sync Playedfor* to the API value.
        if lastRecorded == 0 and #historyTable > 0 then
            Database[playedField] = totalGames
            return
        end

        local gap = totalGames - lastRecorded
        -- Sanity guard: a disconnect should not create dozens of missed games.
        -- If this ever happens, it’s a DB mismatch, so just sync and do nothing.
        if gap > 3 then
            Database[playedField] = totalGames
            return
        end

		-- Same deal: empty history means no baseline; sync count and stop.
		if #historyTable == 0 then
			Database[playedField] = totalGames
			return
		end

---		Log(string.format("Checking category ID %d | Last Recorded: %d | Total Games: %d", category.id, lastRecorded, totalGames))
	
		if totalGames > lastRecorded then
			local currentCR, currentMMR = GetCRandMMR(category.id)
			currentCR  = tonumber(currentCR)  or 0
			currentMMR = tonumber(currentMMR) or 0	
---			Log(string.format("Missed game detected in category ID %d | Previous CR: %d | Current CR: %d | Change: %+d", category.id, previousCR, currentCR, crChange))
	
			local highestMatchID = 0
			local highestMatchEntry = nil
			for _, e in ipairs(historyTable) do
				local mid = tonumber(e.matchID)
				if mid and mid > highestMatchID then
					highestMatchID = mid
					highestMatchEntry = e
				end
			end

			local previousCR = 0
			if highestMatchEntry then
				previousCR = tonumber(highestMatchEntry.cr) or tonumber(highestMatchEntry.rating) or 0
			end
			if currentCR == 0 and previousCR > 0 then
				currentCR = previousCR
			end

			-- MMR fallback for missed games:
			-- - SS: repeat *player* postmatchMMR from last row if possible
			-- - 2v2/3v3: repeat team (friendlyMMR) from last row
			-- - RBG/RBGB: repeat friendlyMMR if present, else last row mmr
			local function GetPreviousMMR()
				if not highestMatchEntry then return 0 end

				local myName = GetPlayerFullName()
				if category.id == 7 and type(highestMatchEntry.playerStats) == "table" then
					for _, s in ipairs(highestMatchEntry.playerStats) do
						if s.name == myName then
							local v = tonumber(s.postmatchMMR) or tonumber(s.postMatchMMR) or 0
							if v > 0 then return v end
							break
						end
					end
				end

				local v = tonumber(highestMatchEntry.friendlyMMR) or 0
				if v > 0 then return v end

				v = tonumber(highestMatchEntry.mmr) or tonumber(highestMatchEntry.postMatchMMR) or 0
				if v > 0 then return v end

				return 0
			end

			local prevMMR = GetPreviousMMR()
			if currentMMR <= 0 and prevMMR > 0 then
				currentMMR = prevMMR
			end

                local mySpecID, mySpecName = RSTATS.GetActiveSpecIDAndName()

                for n = 1, gap do
				local matchID = highestMatchID + n
				local crChange = (n == gap) and (currentCR - previousCR) or 0

				local entry = {
					matchID = matchID,
					isMissedGame = true,
					winLoss = "Missed Game",
					friendlyWinLoss = "Missed Game",
					timestamp = GetTimestamp(),
                    specID = mySpecID,
                    specName = mySpecName,
					-- keep both naming styles so the rest of the addon stays happy
					cr = currentCR,
					mmr = currentMMR,
					rating = currentCR,
					postMatchMMR = currentMMR,
					ratingChange = crChange,
					note = (gap > 1)
						and ("Disconnected or Crashed, Missing Data (" .. n .. "/" .. gap .. ")")
						or "Disconnected or Crashed, Missing Data",
			
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
						faction = UnitFactionGroup("player"),
						race = UnitRace("player"),
						class = UnitClass("player"),
                        spec = mySpecName or (GetSpecialization() and select(2, GetSpecializationInfo(GetSpecialization())) or "N/A"),
						role = GetPlayerRole(),
						newrating = currentCR,
                        postmatchMMR = currentMMR,
						killingBlows = "-",
						honorableKills = "-",
                        deaths = "-",
						damage = "-",
						healing = "-",
						ratingChange = crChange
					},
				}
			}
			
				-- Repeat the enemy placeholder for the second half of the row
				table.insert(entry.playerStats, {
					name = "-",
					faction = "-",
					race = "-",
					class = "-",
					spec = "-",
					role = "-",
					newrating = "-",
					killingBlows = "-",
					honorableKills = "-",
					deaths = "-",
					damage = "-",
					healing = "-",
					ratingChange = "-"
				})

				table.insert(historyTable, 1, entry)
                if (category.id == 7 or category.id == 9) and mySpecID then
                    local specTable = EnsureSpecHistory(category.id, mySpecID, mySpecName)
                    if specTable then
                        table.insert(specTable, 1, entry)
                    end
                end
			end
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

local function CreateIconWithTooltip(parentFrame, content, tooltipText, xOffset, yOffset, columnWidth, rowHeight, isAtlas)
    if isAtlas then
        -- draw a texture from an Atlas
        local tex = parentFrame:CreateTexture(nil, "ARTWORK")
        tex:SetSize(12, 12)
        tex:SetPoint("CENTER", parentFrame, "TOPLEFT", xOffset + (columnWidth/2), yOffset - (rowHeight/2))
        tex:SetAtlas(content, false)   -- `content` is your atlas name
        tex:SetScript("OnEnter", function()
            GameTooltip:SetOwner(tex, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltipText, 1,1,1,1, true)
            GameTooltip:Show()
        end)
        tex:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        return tex
    else
        -- existing text path
        local icon = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        icon:SetFont(GetUnicodeSafeFont(), 14)
        icon:SetText(content)         -- `content` is your text or texture-string
        icon:SetPoint("CENTER", parentFrame, "TOPLEFT", xOffset + (columnWidth/2), yOffset - (rowHeight/2))
        icon:SetScript("OnEnter", function()
            GameTooltip:SetOwner(icon, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltipText, 1,1,1,1, true)
            GameTooltip:Show()
        end)
        icon:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        return icon
    end
end

local mapShortName = {
    -- Battlegrounds
    ["Warsong Gulch"] = "WSG",
    ["Arathi Basin"] = "AB",
    ["Eye of the Storm"] = "EOTS",
    ["The Battle for Gilneas"] = "TBfG",
    ["Twin Peaks"] = "TP",
    ["Silvershard Mines"] = "SSM",
    ["Temple of Kotmogu"] = "TOK",
    ["Deepwind Gorge"] = "DWG",
    ["Seething Shore"] = "SS",
    ["Deephaul Ravine"] = "DHR",

    -- Arenas
    ["Nagrand Arena"] = "NA",
    ["Blade's Edge Arena"] = "BEA",
    ["Dalaran Arena"] = "DA",
    ["Ruins of Lordaeron"] = "ROL",
    ["The Tiger's Peak"] = "TTP",
    ["Tol'viron Arena"] = "TV",
    ["Empyrean Domain"] = "ED",
    ["Mugambala"] = "M",
    ["Hook Point"] = "HP",
    ["Enigma Crucible"] = "EC",
    ["Valdrakken Arena"] = "VA",
    ["Nokhudon Proving Grounds"] = "NPG",
	["Cage of Carnage"] = "COC",
}

function AppendHistory(historyTable, roundIndex, cr, mmr, mapName, endTime, duration, teamFaction, enemyFaction, friendlyTotalDamage, friendlyTotalHealing, enemyTotalDamage, enemyTotalHealing, friendlyWinLoss, friendlyRaidLeader, enemyRaidLeader, friendlyRatingChange, enemyRatingChange, allianceTeamScore, hordeTeamScore, roundsWon, categoryName, categoryID, damp, objectiveByGUID)
    -- Solo Shuffle rounds 1-5 are inserted after a delay, so #historyTable doesn't change immediately.
    -- Reserve a unique matchID up-front to avoid duplicates.
    Database._nextMatchID = Database._nextMatchID or {}
    local key = categoryName or "Unknown"
    local nextID = Database._nextMatchID[key]
    if not nextID then
        local highest = 0
        for _, e in ipairs(historyTable) do
            local id = tonumber(e.matchID)
            if id and id > highest then
                highest = id
            end
        end
        nextID = highest + 1
    end
    local appendHistoryMatchID = nextID
    Database._nextMatchID[key] = nextID + 1
    local playerFullName = GetPlayerFullName() -- Get the player's full name
    local myTeamIndex
    local ssAlliesGUID = soloShuffleAlliesGUIDAtDeath or nil
    local isSoloShuffle = (C_PvP.IsRatedSoloShuffle and C_PvP.IsRatedSoloShuffle()) or false
    local isArena = (C_PvP.IsRatedArena and C_PvP.IsRatedArena()) and not isSoloShuffle

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
	
    -- Pre-pass: in arenas, grab MY team index so we can keep "my team" left consistently.
    if isArena then
        local myGUID = UnitGUID("player")
        for i = 1, GetNumBattlefieldScores() do
            local s = C_PvP.GetScoreInfo(i)
            if s and s.guid and s.guid == myGUID then
                myTeamIndex = s.faction
                break
            end
        end
    end

    for i = 1, GetNumBattlefieldScores() do
        local scoreInfo = C_PvP.GetScoreInfo(i)
        if scoreInfo then
            local name = scoreInfo.name
            if name == UnitName("player") then
                name = playerFullName
            elseif name and not name:find("-", 1, true) then
                -- Normalize same-realm names to Name-Realm so PendingPvPTalents + display matching works.
                name = name .. "-" .. GetRealmName()
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
            local teamIndex = faction  -- C_PvP.GetScoreInfo().faction is a numeric team index
            if guid and guid == UnitGUID("player") then
                myTeamIndex = teamIndex
            end
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

			-- Fetch BattleTag for the player using GUID
            local bnet = ""
            if guid then
                local accountInfo = C_BattleNet.GetAccountInfoByGUID(guid)
                if accountInfo then
                    bnet = accountInfo.battleTag or ""  -- Get BattleTag
                end
            end

            -- Create player data entry
            local playerData = {
                name = name,
                guid = guid,
				bnet = bnet,
                faction = translatedFaction,
                teamIndex = teamIndex,
                isFriendly = (
                    C_PvP.IsRatedSoloShuffle and C_PvP.IsRatedSoloShuffle()
                    and guid
                    and (
                        guid == UnitGUID("player")
                        or (ssAlliesGUID and ssAlliesGUID[guid])
                    )
                ) or false,
                race = raceName,
                class = className,
                spec = talentSpec,
                role = roleAssigned,
                cr = cr,  -- Keep original cr
                mmr = mmr,
                killingBlows = killingBlows,
                deaths = deaths,
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
                objective = (objectiveByGUID and guid and objectiveByGUID[guid]) or "-"
            }

            -- Ensure all damage and healing values are numbers
            friendlyTotalDamage = tonumber(friendlyTotalDamage) or 0
            friendlyTotalHealing = tonumber(friendlyTotalHealing) or 0
            enemyTotalDamage = tonumber(enemyTotalDamage) or 0
            enemyTotalHealing = tonumber(enemyTotalHealing) or 0

            if C_PvP.IsRatedSoloShuffle() then
                if playerData.isFriendly then
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
            else
                -- Non-SS: prefer numeric teamIndex split (works for Arena + Rated BG/Blitz),
                -- fallback to faction string if teamIndex isn't reliable.
                local isRatedBG = (C_PvP.IsRatedBattleground and C_PvP.IsRatedBattleground()) or false

                if myTeamIndex ~= nil and (isArena or isRatedBG) then
                    if playerData.teamIndex == myTeamIndex then
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
                else
                    -- Fallback: split by faction string (old behaviour)
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
        end
    end
    
    -- Overwrite the match-level labels for arenas (what DisplayHistory shows under "Team").
    if (C_PvP.IsRatedArena() or C_PvP.IsRatedSoloShuffle()) and myTeamIndex ~= nil then
        if myTeamIndex == 1 then
            teamFaction = "Gold"
            enemyFaction = "Purple"
        else
            teamFaction = "Purple"
            enemyFaction = "Gold"
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

    local duoPartner = nil
    if categoryID == 9 then -- Solo RBG (RBGB)
        duoPartner = GetRBGBDuoPartnerNameRealm()
    end

    -- Track the player's active spec for spec-based rated ladders (and spec-based UI display).
    local mySpecID, mySpecName
    do
        local specIndex = GetSpecialization()
        if specIndex then
            mySpecID, mySpecName = GetSpecializationInfo(specIndex)
        end
    end

    local entry = {
        matchID = appendHistoryMatchID,
        isSoloShuffle = C_PvP.IsRatedSoloShuffle and C_PvP.IsRatedSoloShuffle() or false,
        timestamp = endTime,
        specID = mySpecID,
        specName = mySpecName,
        cr = cr,
        mmr = mmr,
        isInitial = false,
        friendlyWinLoss = friendlyWinLoss,  -- Win/Loss status
        mapName = mapName,
        endTime = endTime,
        duration = duration,
        duoPartner = duoPartner,
		damp = damp,
        teamFaction = teamFaction,
        myTeamIndex = myTeamIndex,
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

	for _, player in ipairs(playerStats) do
		-- 1. Inject from PendingPvPTalents (inspect loadout only)
		local pending = PendingPvPTalents[player.name]
		if pending and pending.loadout and pending.loadout ~= "" and (not issecretvalue or not issecretvalue(pending.loadout)) then
			player.loadout = pending.loadout
			player.talentSource = "inspect"
			PendingPvPTalents[player.name] = nil
		end
	
		-- 2. Inject from DetectedPlayerTalents (loadout only)
		if player.guid then
			local detected = RSTATS.DetectedPlayerTalents[player.guid]
			if detected and detected.loadout and player.loadout == nil and (not issecretvalue or not issecretvalue(detected.loadout)) then
				player.loadout = detected.loadout
				player.talentSource = player.talentSource or "detected"
			end
		end
	end

    if C_PvP.IsRatedSoloShuffle() and roundIndex >= 1 and roundIndex <= 5 then
        -- Skip table insert for now, let the 20second delay handle it
    else
        table.insert(historyTable, 1, entry)
        if categoryID == 7 or categoryID == 9 then
            local specTable = EnsureSpecHistory(categoryID, mySpecID, mySpecName)
            if specTable then
                table.insert(specTable, 1, entry)
            end
        end
        SaveData()
    end

	--- Solo Shuffle logic with a 20-second delay only for round 1-5
	if C_PvP.IsRatedSoloShuffle() and roundIndex >= 1 and roundIndex <= 5 then
	
		local matchIDToUpdate = appendHistoryMatchID
	
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
					local name = scoreInfo.name
					if name == UnitName("player") then
						name = playerFullName
                    elseif name and not name:find("-", 1, true) then
                        name = name .. "-" .. GetRealmName()
					end
                    local guid2 = scoreInfo.guid

					for _, playerData in ipairs(playerStats) do
						if (guid2 and playerData.guid and playerData.guid == guid2) or playerData.name == name then
							playerData.killingBlows   = tonumber(scoreInfo.killingBlows) or 0
							playerData.honorableKills = tonumber(scoreInfo.honorableKills) or 0
							playerData.deaths         = tonumber(scoreInfo.deaths) or 0
							playerData.damage         = tonumber(scoreInfo.damageDone) or 0
							playerData.healing        = tonumber(scoreInfo.healingDone) or 0
							playerData.rating         = tonumber(scoreInfo.rating) or 0
							playerData.ratingChange   = tonumber(scoreInfo.ratingChange) or 0
							playerData.mmrChange      = tonumber(scoreInfo.mmrChange) or 0
							playerData.postmatchMMR   = tonumber(scoreInfo.postmatchMMR) or 0
							playerData.honorLevel     = tonumber(scoreInfo.honorLevel) or 0

							-- Solo Shuffle rounds won comes from scoreInfo.stats
							do
								local wins = 0
                                if scoreInfo.stats and #scoreInfo.stats > 0 then
                                    -- Solo Shuffle stat column is the first stat entry
                                    wins = tonumber(scoreInfo.stats[1].pvpStatValue) or 0 -- roundsWon from SS stats Scoreboard, not main Scoreboard
                                end
								playerData.wins = wins
							end

							-- Totals: Solo Shuffle uses the frozen ally team for this round; non-SS uses teamFaction.
							if C_PvP.IsRatedSoloShuffle() then
								if playerData.isFriendly then
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
							else
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
							end
							-- Stop scanning playerStats for this scoreInfo row.
							break
						end
					end
				end
			end

			local friendlyAvgCR = friendlyPlayerCount > 0 and math.floor(friendlyRatingTotal / friendlyPlayerCount) or "N/A"
			local enemyAvgCR = enemyPlayerCount > 0 and math.floor(enemyRatingTotal / enemyPlayerCount) or "N/A"
			local friendlyAvgRatingChange = friendlyPlayerCount > 0 and math.floor(friendlyRatingChangeTotal / friendlyPlayerCount) or "N/A"
			local enemyAvgRatingChange = enemyPlayerCount > 0 and math.floor(enemyRatingChangeTotal / enemyPlayerCount) or "N/A"

            local ssRoundData = {
                matchID = appendHistoryMatchID,
                isSoloShuffle = true,
                timestamp = endTime,
                specID = mySpecID,
                specName = mySpecName,
                cr = cr,
                mmr = mmr,
                isInitial = false,
                friendlyWinLoss = friendlyWinLoss,
                mapName = mapName,
                endTime = endTime,
                duration = duration,
                damp = damp,
                teamFaction = teamFaction,
                myTeamIndex = myTeamIndex,
                friendlyRaidLeader = friendlyRaidLeader,
                friendlyAvgCR = friendlyAvgCR,
                friendlyMMR = friendlyPostMatchMMR,
                friendlyTotalDamage = friendlyTotalDamage,
                friendlyTotalHealing = friendlyTotalHealing,
                friendlyRatingChange = friendlyAvgRatingChange,
                allianceTeamScore = allianceTeamScore,
                enemyFaction = enemyFaction,
                enemyRaidLeader = enemyRaidLeader,
                enemyAvgCR = enemyAvgCR,
                enemyMMR = enemyPostMatchMMR,
                enemyTotalDamage = enemyTotalDamage,
                enemyTotalHealing = enemyTotalHealing,
                enemyRatingChange = enemyAvgRatingChange,
                hordeTeamScore = hordeTeamScore,
                roundsWon = roundsWon or 0,
                playerStats = playerStats,
            }

            table.insert(historyTable, 1, ssRoundData)
            do
                local specTable = EnsureSpecHistory(7, mySpecID, mySpecName)
                if specTable then
                    table.insert(specTable, 1, ssRoundData)
                end
            end
			SaveData()
            playerDeathSeen = false
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
                    elseif name and not name:find("-", 1, true) then
                        name = name .. "-" .. GetRealmName()
                    end
    
					local guid2 = scoreInfo.guid
                    for _, playerData in ipairs(playerStats) do
						if (guid2 and playerData.guid and playerData.guid == guid2) or playerData.name == name then
                            -- Update the playerData fields with new stats
                            playerData.killingBlows = tonumber(scoreInfo.killingBlows) or 0
                            playerData.honorableKills = tonumber(scoreInfo.honorableKills) or 0
                            playerData.deaths = tonumber(scoreInfo.deaths) or 0
                            playerData.damage = tonumber(scoreInfo.damageDone) or 0
                            playerData.healing = tonumber(scoreInfo.healingDone) or 0
                            playerData.rating = tonumber(scoreInfo.rating) or 0
                            playerData.ratingChange = tonumber(scoreInfo.ratingChange) or 0
                            playerData.mmrChange = tonumber(scoreInfo.mmrChange) or 0
                            playerData.postmatchMMR = tonumber(scoreInfo.postmatchMMR) or 0
                            playerData.honorLevel = tonumber(scoreInfo.honorLevel) or 0

							-- Solo Shuffle rounds won comes from scoreInfo.stats
							do
								local wins = 0
                                if scoreInfo.stats and #scoreInfo.stats > 0 then
                                    -- Solo Shuffle stat column is the first stat entry
                                    wins = tonumber(scoreInfo.stats[1].pvpStatValue) or 0 -- roundsWon from SS stats Scoreboard, not main Scoreboard
                                end
								playerData.wins = wins
							end    

                            -- Calculate totals based on player's team 
						    if C_PvP.IsRatedSoloShuffle() then
							    if playerData.isFriendly then
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
						    else
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
		
		    if GetTalents then
			    GetTalents:ReallyClearMemory() -- now safe to clear everything
		    end
		
		    -- Re-run filters to refresh the UI with the new match included
		    local tabIDByCategoryID = {
			    [7] = 1, -- Solo Shuffle
			    [1] = 2, -- 2v2
			    [2] = 3, -- 3v3
			    [4] = 4, -- RBG
			    [9] = 5, -- Solo RBG
		    }
		
		    local tabID = tabIDByCategoryID[categoryID]
		    if tabID and RSTATS.UIConfig and RSTATS.ContentFrames then
			    RatedStatsFilters[tabID] = {} -- ✅ Optional: wipe filters when adding a match
			    RSTATS.__LastHistoryCount = RSTATS.__LastHistoryCount or {}
			    RSTATS.__LastHistoryCount[tabID] = #(Database.SoloShuffleHistory or {})
		
			    -- ✅ Soft-refresh UI: update the correct tab
			    C_Timer.After(0.1, function()
					-- Select the correct content frame
    				local content = RSTATS.ScrollContents[tabID]
	    			local frame   = RSTATS.ContentFrames[tabID]
		    		local mmrID   = ({
			    		[1] = 7,
				    	[2] = 1,
					    [3] = 2,
					    [4] = 4,
					    [5] = 9
				    })[tabID]
		
				    if content and frame then
					    -- Clear match frames cache so DisplayHistory redraws fresh
					    content.matchFrames = {}
					    content.matchFrameByID = {}
		
					    local mmrLabel = DisplayCurrentCRMMR(frame, mmrID)
					    FilterAndSearchMatches(RatedStatsSearchBox:GetText())
					    RSTATS:UpdateStatsView(filterKey, tabID)
				    end
			    end)
            end
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

-- Use this helper function to calculate the maximum height of a set of font strings
local function CalculateRowHeight(fontStrings, padding)
    local maxHeight = 0
    for _, fs in pairs(fontStrings) do
        local h = fs:GetStringHeight() or 0
        if h > maxHeight then
            maxHeight = h
        end
    end
    return maxHeight + (padding or 4)  -- add a little padding
end

-- AdjustContentHeight reflows the scroll child based on total height of match rows.
function AdjustContentHeight(content)
    local matchFrames = content.matchFrames
    if not matchFrames or #matchFrames == 0 then
        content:SetHeight(400)
        return
    end

    local totalHeight = 0
    for _, row in ipairs(matchFrames) do
        local h = row:GetHeight() or 0
        totalHeight = totalHeight + h + 5  -- include spacing between rows
    end

    -- Add buffer to avoid scrollbar "snapping"
    totalHeight = totalHeight + 20

    -- Cap it, but allow scrolling
    local scrollFrame = content:GetParent()
    local maxAllowed = RatedStatsConfig:GetHeight() * 3
    content:SetHeight(math.min(totalHeight, maxAllowed))

    -- Debug
end

--------------------------------------------------
-- New Helper Functions for Localized Reflowing
--------------------------------------------------

-- Returns the index of the given targetFrame in content.matchFrames.
local function GetRowIndex(content, targetFrame)
    local matchFrames = content.matchFrames
    for i, row in ipairs(matchFrames) do
        if row == targetFrame then
            return i
        end
    end
    return nil
end

-- Modified ToggleNestedTable function that uses localized reflow.
function ToggleNestedTable(matchFrame, nestedTable, content)
    local matchID = matchFrame.matchData and matchFrame.matchData.matchID or "??"
    if nestedTable:IsShown() then
        nestedTable:Hide()
        matchFrame:SetHeight(matchFrame.baseHeight)
		matchFrame:SetFrameStrata("HIGH")
		matchFrame:SetFrameLevel(22)
    else
        nestedTable:Show()
        nestedTable:SetParent(matchFrame)
        nestedTable:ClearAllPoints()
        nestedTable:SetPoint("TOPLEFT", matchFrame, "TOPLEFT", 0, -14)
		nestedTable:SetFrameStrata("HIGH")
		nestedTable:SetFrameLevel(22)
        local ntHeight = nestedTable:GetHeight() or 0
		
        matchFrame:SetHeight(matchFrame.baseHeight + ntHeight + 10)
		matchFrame:SetFrameStrata("HIGH")
		matchFrame:SetFrameLevel(22)
    end

---    if ACTIVE_TAB_ID == 1 then
---        DebugSelectedMatchFrame(matchFrame, "ToggleNestedTable - matchFrame after toggle")
---        DebugSelectedMatchFrame(nestedTable, "ToggleNestedTable - nestedTable after toggle")
---    end

    local index = GetRowIndex(content, matchFrame)
    if index then
        ReflowRows(content)  -- fallback in case index wasn't found
    end
end

------------------------------------------------------------------------------
-- ReflowRows: Anchor each matchFrame one under the other, accounting for height.
------------------------------------------------------------------------------
function ReflowRows(content)
    local matchFrames = content.matchFrames
    if not matchFrames or #matchFrames == 0 then 
        return 
    end

    local seenMatchIDs = {}  -- Table to record which matchIDs we’ve seen

    -- Loop through each matchFrame in the array.
    for i, row in ipairs(matchFrames) do
        row:ClearAllPoints() -- Clear any existing anchor points

        -- Check for duplicate matchIDs: warn if the same matchID appears more than once.
        local matchID = (row.matchData and row.matchData.matchID) or "??"
		-- Get the current height of the row (this may have changed if expanded)
        local rowHeight = row:GetHeight() or 0
        if seenMatchIDs[matchID] then
        else
            seenMatchIDs[matchID] = true
        end

        if i == 1 then
            -- Anchor the first row relative to the fixed base anchor
            row:SetPoint("TOPLEFT", content.rowsAnchor, "BOTTOMLEFT", 0, 0)
        else
            -- Anchor this row relative to the above row's "BOTTOMLEFT"
            local prevRow = matchFrames[i - 1]
			local prevHeight = prevRow:GetHeight() or 0
            local dynamicOffset = -(prevHeight + 5)
            row:SetPoint("TOPLEFT", prevRow, "BOTTOMLEFT", 0, -5)
        end
		
		row:SetFrameStrata("HIGH")
		row:SetFrameLevel(22)

    end

    AdjustContentHeight(content)
end

-- Cleanup helper for ToggleNestedTable to fully remove hidden ghost rows
function ClearStaleMatchFrames(content)
    if not content or not content.matchFrames then return end

		-- 🧹 Clean up lingering placeholder text
	if content.placeholder then
		content.placeholder:Hide()
		content.placeholder:SetText("")
		content.placeholder:SetParent(nil)
		content.placeholder = nil
	end

    for _, frame in ipairs(content.matchFrames) do
        if frame.nestedTable then
            if frame.nestedTable.headerTexts then
                for _, h in ipairs(frame.nestedTable.headerTexts) do
                    h:SetText("")
                    h:Hide()
                    h:SetParent(nil)
                end
                wipe(frame.nestedTable.headerTexts)
            end
            frame.nestedTable:Hide()
            frame.nestedTable:SetParent(nil)
            frame.nestedTable:ClearAllPoints()
            frame.nestedTable = nil
        end

        if frame.fontStrings then
            for _, fs in ipairs(frame.fontStrings) do
                fs:SetText("")
                fs:Hide()
                fs:SetParent(nil)
            end
            wipe(frame.fontStrings)
        end

        frame:Hide()
        frame:SetParent(nil)
        frame:ClearAllPoints()
		
        -- Only attempt to remove from _G if it's really global
        local frameName = frame:GetName()
        if frameName and _G[frameName] == frame then
            _G[frameName] = nil
        end
    end

    wipe(content.matchFrames)
	content.matchFrameByID = {}
end

function SafeTabClick(tab)
    local id = tab:GetID()
    if ACTIVE_TAB_ID == id then return end
    ACTIVE_TAB_ID = id

    PanelTemplates_SetTab(RatedStatsConfig, id)

    for i, frame in ipairs(RSTATS.ContentFrames) do
        frame:SetShown(i == id)
    end

    -- ✅ Trigger filter update when tab changes
    if RSTATS.ScrollContents and RSTATS.ScrollContents[id] then
        local content = RSTATS.ScrollContents[id]
        if not content._initialized then
            content._initialized = true
        end

        -- Run filter + stat view update
        C_Timer.After(0.1, function()
            local filterText = UIDropDownMenu_GetText(RSTATS.Dropdowns[id]) or "Today"
            local currentFilter = filterText:lower():gsub(" ", "")
			
			local content = RSTATS.ScrollContents[id]
			ClearStaleMatchFrames(content) -- ✅ Prevent ghosting/duplication
            
            FilterAndSearchMatches(RatedStatsSearchBox and RatedStatsSearchBox:GetText() or "")
            RSTATS:UpdateStatsView(currentFilter, id)
        end)
    end
end

------------------------------------------------------------------------------
-- DisplayHistory: Builds the header and creates each match row. Every row
-- is parented to the main content frame (not the previous row) so that we
-- can reposition all rows by calling ReflowRows.
------------------------------------------------------------------------------
function RSTATS:DisplayHistory(content, historyTable, mmrLabel, tabID, isFiltered)
    ClearStaleMatchFrames(content)		-- needed for rows to not overlap

    -- If a placeholder was previously shown (e.g. during initial menu build),
    -- always remove it before rebuilding rows.
    if content.placeholder then
        content.placeholder:Hide()
        content.placeholder = nil
    end

    -- 1) Sort history by matchID ascending
    table.sort(historyTable, function(a, b)
        return (a.matchID or 0) < (b.matchID or 0)
    end)

    content.matchFrames = {}
	content.matchFrameByID = {}

    -- 3) Create headers
    local scoreHeaderText = (tabID == 2 or tabID == 3) and "" or "Score"
	local c = function(text) return RSTATS:ColorText(text) end
    local factionHeaderText = (tabID == 1 or tabID == 2 or tabID == 3) and "Team" or "Faction"
    local duoHeaderText = (tabID == 5) and c("Duo") or ""

	local headers = {
		c("Win/Loss"), duoHeaderText,c(scoreHeaderText), c("Map"), c("Match End Time"), c("Duration"), "",
		c(factionHeaderText), c("Raid Leader"), c("Avg CR"), c("MMR"), c("Damage"), c("Healing"), c("Avg Rat Chg"), "",
		 "", c(factionHeaderText), c("Raid Leader"), c("Avg CR"), c("MMR"), c("Damage"), c("Healing"), c("Avg Rat Chg"), c("Note")
	}
	local columnOffsets = {}
	local spacing = 8
	local headerFont = GetUnicodeSafeFont()
	local headerFontSize = 10
	
	if UIConfig.isCompact then
		headerFrameWidth = content:GetWidth() * 2
	else
		headerFrameWidth = content:GetWidth() * 0.98
	end
	
	local splitIndex = 15  -- This is where you start the second faction header set
	local splitX = headerFrameWidth * 0.65
	local xOffset = 0
	
	local tempFS = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	tempFS:SetFont(headerFont, headerFontSize)
	
	local rawColumnWidths = {}
	
	-- Step 1: Measure headers
	for i, text in ipairs(headers) do
		tempFS:SetText(text)
		rawColumnWidths[i] = tempFS:GetStringWidth() + spacing
	end

    -- 4) Format each match entry's columns.
    local function formatMatch(match)
        local scoreText = "-"
        if match.friendlyTeamScore then
            if match.teamFaction == "Alliance" then
                scoreText = (match.friendlyTeamScore or "-").."  : "..(match.enemyTeamScore or "-")
            else
                scoreText = (match.enemyTeamScore or "-").."  : "..(match.friendlyTeamScore or "-")
            end
        elseif match.allianceTeamScore and match.teamFaction == "Alliance" then
            scoreText = (match.allianceTeamScore or "-").." : "..(match.hordeTeamScore or "-")
        else
            scoreText = (match.hordeTeamScore or "-").."  : "..(match.allianceTeamScore or "-")
        end
        if tabID == 1 then
            scoreText = (match.roundsWon or 0) .. " / 6"
        elseif tabID == 2 or tabID == 3 then
            scoreText = ""
        end
        if type(match.duration) == "number" then
            match.duration = SecondsToTime(match.duration)
        end
		
		local mapDisplay = mapShortName[match.mapName] or match.mapName or "N/A"

        local duoText = ""
        if tabID == 5 then
            duoText = match.duoPartner or "Solo"
        end

        return {
            (match.friendlyWinLoss or "-"),
            duoText,
            scoreText,
            (mapDisplay or "N/A"),
            date("%a %d %b %Y - %H:%M:%S", match.endTime) or "N/A",
            (match.duration or "N/A"),
            "",
            (match.teamFaction or "N/A"),
            (match.friendlyRaidLeader or "N/A"),
            (match.friendlyAvgCR or "N/A"),
            (match.friendlyMMR or "N/A"),
            FormatNumber(match.friendlyTotalDamage) or "N/A",
            FormatNumber(match.friendlyTotalHealing) or "N/A",
            (match.friendlyRatingChange or "N/A"),
            "",
            "",
            (match.enemyFaction or "N/A"),
            (match.enemyRaidLeader or "N/A"),
            (match.enemyAvgCR or "N/A"),
            (match.enemyMMR or "N/A"),
            FormatNumber(match.enemyTotalDamage) or "N/A",
            FormatNumber(match.enemyTotalHealing) or "N/A",
            (match.enemyRatingChange or "N/A"),
			(match.note or "")
        }
    end
	
	-- Step 2: Measure row content using formatMatch
	for _, match in ipairs(historyTable) do
		local row = formatMatch(match)
		for i, value in ipairs(row) do
			tempFS:SetText(value or "")
			local w = tempFS:GetStringWidth() + spacing
			if w > (rawColumnWidths[i] or 0) then
				rawColumnWidths[i] = w
			end
		end
	end
	
	-- Step 3: Calculate final offsets using max widths
	local columnOffsets = {}
	local columnWidths = {}
	local xOffset = 0
	for i, width in ipairs(rawColumnWidths) do
		if i == splitIndex + 1 then
			xOffset = splitX
		end
		columnOffsets[i] = xOffset
		columnWidths[i] = width
		xOffset = xOffset + width
	end
	
	-- ─────── Persist offsets for paging later ───────
     content.columnOffsets = columnOffsets
     content.columnWidths  = columnWidths
     content.splitIndex    = splitIndex
	 content.splitX		   = splitX
     -- ────────────────────────────────────────────────
	
	tempFS:Hide()

	local columnWidths = {}
	for i = 1, #headers do
		if i < #headers then
			columnWidths[i] = columnOffsets[i + 1] - columnOffsets[i]
		else
			columnWidths[i] = headerFrameWidth - columnOffsets[i]
		end
	end

	-- -----------------------------------------------------------
	-- Header-row ― build once, reuse; never shrink in compact view
	-- -----------------------------------------------------------
	local contentFrame  = RSTATS.ContentFrames[tabID]
	local headerFrame   = content.headerFrame   -- already built for this tab?
	
	if not headerFrame then
		-- First time on this tab → actually create the widgets
		headerFrame = CreateFrame("Frame", "HeaderFrame", contentFrame)
		headerFrame:SetPoint("TOPLEFT", mmrLabel, "BOTTOMLEFT", 0, -8)
		
		if UIConfig.isCompact then
			startWidth = contentFrame:GetWidth() * 2
		else
			startWidth = contentFrame:GetWidth() - 20          -- full-view width
		end
		
		headerFrame:SetSize(startWidth, 14)
		headerFrame.fullWidth = startWidth                       -- remember “wide” size
	
		headerFrame:SetFrameStrata("HIGH")
		headerFrame:SetFrameLevel(24)
		headerFrame:SetClipsChildren(true)
		headerFrame:SetClampRectInsets(0,0,0,0)
		content.headerFrame = headerFrame
	
		-- Build the label fontStrings only once
		local headerTexts = {}
		for i, name in ipairs(headers) do
			local h = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			h:SetFont(GetUnicodeSafeFont(), headerFontSize)
			h:SetJustifyH("CENTER")
			h:SetTextColor(1,1,1)
			h:SetShadowOffset(1,-1)
			h:SetText(name)
			table.insert(headerTexts, h)
		end
		content.headerTexts = headerTexts
		content.header      = headerTexts[1]     -- first header = anchor
	else
		-- Header already exists → only (possibly) widen it
		local want = math.max(headerFrame.fullWidth or 0,
							contentFrame:GetWidth() - 20)
		headerFrame:SetWidth(want)
		headerFrame.fullWidth = want
	end
	
	-- Re-anchor the texts every call (handles window growth)
	for i, h in ipairs(content.headerTexts) do
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", columnOffsets[i], 0)
	end

	-- If no history, show a placeholder.
	if not historyTable or #historyTable == 0 then
		-- Clean up any old placeholder if it somehow already exists
		if content.placeholder then
			content.placeholder:Hide()
			content.placeholder = nil
		end
	
		local placeholder = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
		placeholder:SetFont(GetUnicodeSafeFont(), 10)
		placeholder:SetPoint("TOPLEFT", content.header, "BOTTOMLEFT", 0, -20)
	
		if isFiltered then
			placeholder:SetText("|cffff5555No data found.|r")
		else
			placeholder:SetText("|cff00ccffWaiting for game data to initialise...|r")
		end
	
		placeholder:SetJustifyH("LEFT")
		placeholder:SetWidth(900)
		placeholder:SetHeight(50)
		placeholder:SetWordWrap(true)
		content.placeholder = placeholder -- ✅ Store reference for later cleanup
	
		return headerTexts, {}
	end

	-- After creating your headerTexts, pick the first header as the anchor
	local anchorForRows = content.headerTexts[1]

    -- 5) Create a base anchor frame placed immediately below mmrLabel.
    local baseAnchor = CreateFrame("Frame", "HeadingAnchor", content)
    baseAnchor:SetSize(1, 1)
    baseAnchor:SetPoint("TOPLEFT", mmrLabel, "BOTTOMLEFT", 0, -12)
    content.baseAnchor = baseAnchor

    -- 6) Create each match row (all parented to content)
    for i = #historyTable, 1, -1 do
		local match = historyTable[i]
		local matchID = match.matchID or i
        -- matchID can be duplicated (especially from delayed SS inserts), so don't cache frames by matchID alone.
        local frameKey = tostring(matchID) .. ":" .. tostring(i)
		local parentWidth  = UIConfig:GetWidth()
		local parentHeight = UIConfig:GetHeight()
		
		if content.matchFrameByID[frameKey] then
            table.insert(content.matchFrames, content.matchFrameByID[frameKey])
        else
            local frameName = "MatchFrame_" .. tostring(matchID) .. "_" .. tostring(i)
            local matchFrame = CreateFrame("Frame", frameName, nil, "BackdropTemplate")
			if UIConfig.isCompact then
				matchFrame:SetSize(parentWidth * 2, parentHeight) -- double the width of the matchFrame in compact mode
			else
				matchFrame:SetSize(parentWidth * 1.06, parentHeight)  -- Width controls the offset for left of row text -- Initial minimal height
			end
			matchFrame:SetFrameStrata("HIGH")
			matchFrame:SetFrameLevel(22)
			matchFrame:SetParent(content)
			matchFrame.matchData = match  -- Store the match data for reference
			matchFrame.fontStrings = {}
			
			local rowFontStrings = {}
			local columns = formatMatch(match)
			for j, colText in ipairs(columns) do
				local fs = matchFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
				fs:SetFont(GetUnicodeSafeFont(), entryFontSize)
				fs:SetJustifyH("LEFT")
				fs:SetPoint("TOPLEFT", matchFrame, "TOPLEFT", columnOffsets[j], -2)
				fs:SetWidth(columnWidths[j] or 60)  -- Fallback in case
				fs:SetWordWrap(false)  -- Optional: disable wrapping if you want single-line
				fs:SetText(colText)
				table.insert(matchFrame.fontStrings, fs)
				table.insert(rowFontStrings, fs)
	
				-- Color code column one if necessary.
				if j == 1 then
					if colText:find("%+%s+W") then
						fs:SetTextColor(0, 1, 0)
					elseif colText:find("%+%s+L") then
						fs:SetTextColor(1, 0, 0)
					elseif colText:find("~%s+D") then
						fs:SetTextColor(0.5, 0.5, 0.5)
					else
						fs:SetTextColor(1, 1, 1)
					end
				end
	
				-- Add dampening tooltip if applicable.
				if j == 5 and match.damp and (tabID == 1 or tabID == 2 or tabID == 3) then
					fs:EnableMouse(true)
					fs:SetScript("OnEnter", function()
						GameTooltip:SetOwner(fs, "ANCHOR_CURSOR")
						GameTooltip:ClearLines()
						GameTooltip:AddLine(string.format("%d%% Dampening", match.damp), 1, 1, 1)
						GameTooltip:Show()
					end)
					fs:SetScript("OnLeave", function() GameTooltip:Hide() end)
				end
			end
	
			local rowHeight = CalculateRowHeight(rowFontStrings, 4)
			matchFrame:SetHeight(rowHeight)
			matchFrame.baseHeight = rowHeight
			matchFrame:SetClipsChildren(true)
	
			-- Set the background color based on dampening or faction.
			matchFrame:SetBackdrop({bgFile = "Interface/Tooltips/UI-Tooltip-Background"})
			if match.damp and (tabID == 1 or tabID == 2 or tabID == 3) then
				local dv = match.damp
				if dv <= 10 then
					matchFrame:SetBackdropColor(0.5, 0.5, 0.5, 0.7)
				elseif dv <= 20 then
					matchFrame:SetBackdropColor(1, 1, 0, 0.7)
				elseif dv <= 30 then
					matchFrame:SetBackdropColor(1, 0.55, 0, 0.7)
				elseif dv <= 39 then
					matchFrame:SetBackdropColor(1, 0.4, 0, 0.7)
				else
					matchFrame:SetBackdropColor(1, 0, 0, 0.7)
				end
			else
				if match.teamFaction == "Horde" then
					matchFrame:SetBackdropColor(1, 0, 0, 0.7)
				else
					matchFrame:SetBackdropColor(0, 0, 1, 0.7)
				end
			end
	
			-- Create the nested table (for match details) and parent it to the row.
			local nestedTable = CreateNestedTable(matchFrame, match.playerStats or {}, match.teamFaction, match.isInitial, match.isMissedGame, content, match, tabID)
			nestedTable:SetParent(matchFrame)
			nestedTable:SetPoint("TOPLEFT", matchFrame, "TOPLEFT", 0, -14)
			nestedTable:SetFrameStrata("HIGH")
			nestedTable:SetFrameLevel(22)
			nestedTable:Hide()
			nestedTable:UpdateTeamView()
			matchFrame.nestedTable = nestedTable
	
			-- Set a click handler for the row to toggle its nested table and reflow all rows.
			matchFrame:SetScript("OnMouseUp", function()
				ReflowRows(content)
				ToggleNestedTable(matchFrame, nestedTable, content)
			end)
			
			content.matchFrameByID[frameKey] = matchFrame
			table.insert(content.matchFrames, matchFrame)
		end
    end

    -- 7) Reflow rows so they are anchored one below the other as desired.
    ReflowRows(content)

    SaveData()
    return content.headerTexts, content.matchFrames
end

local rowCounts = {
    ["Solo Shuffle"] = 3,
    ["2v2"] = 2,
    ["3v3"] = 3,
    ["RBG"] = 10,
    ["Solo RBG"] = 8,
}

-- Function to send a Battle.net invite using player's GUID or BattleTag
local function SendBattleNetInvite(playerName)
    local foundStats = nil

    -- Loop through the history table to find the player entry
    local categoryMappings = {
        { id = 7, name = "SoloShuffle", tableKey = "SoloShuffleHistory" },
        { id = 1, name = "2v2", tableKey = "v2History" },
        { id = 2, name = "3v3", tableKey = "v3History" },
        { id = 4, name = "RBG", tableKey = "RBGHistory" },
        { id = 9, name = "SoloRBG", tableKey = "SoloRBGHistory" },
    }

    for _, info in ipairs(categoryMappings) do
        local historyTable = Database[info.tableKey]

        if historyTable and #historyTable > 0 then
            -- Loop through the entries to find the matching player name and get their GUID
            for _, entry in ipairs(historyTable) do
                for _, stats in ipairs(entry.playerStats or {}) do
                    if stats.name == playerName then
                        foundStats = stats
                        break
                    end
                end
                if foundStats then break end
            end

            if foundStats then
                -- We found the player and have their GUID or BattleTag
                local bnet = foundStats.bnet or nil
                local playerGUID = foundStats.guid
                local accountInfo = nil

                if bnet ~= nil and bnet ~= "" then
                    -- If BattleTag exists, use it to send the invite
                    accountInfo = bnet
                elseif playerGUID then
                    -- Otherwise, use GUID to get BattleTag
                    accountInfo = C_BattleNet.GetAccountInfoByGUID(playerGUID)
                end

                if accountInfo then
                    -- Check if the player is already on your friend list
                    local isFriend = C_FriendList.IsFriend(accountInfo.battleTag)

                    if isFriend then
                        -- Replace "Add Friend" button with "Already Friends" text
                        -- (Add your UI button update code here)
                    else
                        -- Send Battle.net invite using BattleTag
                        C_FriendList.AddFriend(accountInfo.battleTag)
                    end
                else
                end
            else
            end
        else
        end
    end
end

-- Function to for Popout Details of Name/Spec/Loadout
-- Pop-out content + layout tweaks
local function CreateFriendAndTalentButtons(stats, matchEntry, parent)
    -- Legacy cleanup (old spell icons)
    if parent.spellIcons then
        for _, ic in ipairs(parent.spellIcons) do
            ic:Hide()
        end
    end
    parent.spellIcons = {}

    -- 1) Loadout label
    if not parent.loadoutLabel then
        parent.loadoutLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        parent.loadoutLabel:SetPoint("TOP", parent, "TOP", 0, -60)
        parent.loadoutLabel:SetText("Loadout Code:")
        parent.loadoutLabel:SetFont(GetUnicodeSafeFont(), 8)
    end
    parent.loadoutLabel:Show()

    -- 2) Loadout box
    if not parent.loadoutBox then
        parent.loadoutBox = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
        parent.loadoutBox:SetSize(220, 20)
        parent.loadoutBox:SetPoint("TOP", parent.loadoutLabel, "BOTTOM", 0, -4)
        parent.loadoutBox:SetAutoFocus(false)
        parent.loadoutBox:SetFont(GetUnicodeSafeFont(), 8, "OUTLINE")
        parent.loadoutBox:SetJustifyH("CENTER")
        parent.loadoutBox:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile     = true, tileSize = 16, edgeSize = 16,
            insets   = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        parent.loadoutBox:SetBackdropColor(0,0,0,0.8)
        parent.loadoutBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    end
    parent.loadoutBox:Show()

    local loadout = stats and stats.loadout

    -- Fallback: loadout may not be injected into matchEntry yet; pull it from detected GUID storage.
    if (not loadout or loadout == "") and stats and stats.guid and RSTATS and RSTATS.DetectedPlayerTalents then
        local detected = RSTATS.DetectedPlayerTalents[stats.guid]
        if detected and detected.loadout then
            loadout = detected.loadout
        end
    end
    if loadout and type(loadout) == "string" and loadout ~= "" and (not issecretvalue or not issecretvalue(loadout)) then
        parent.loadoutBox:SetText(loadout)
    else
        parent.loadoutBox:SetText("No Loadout Available")
    end

    parent.loadoutBox:HighlightText(0)
end

-- Pop-out frame + name box tweaks
function RSTATS.OpenPlayerDetails(stats, matchEntry)
    local frame = CreateFrame("Frame", "CreateCopyNameFrame", UIParent, "BackdropTemplate")
	UIPanelWindows["CreateCopyNameFrame"] = { area = "center", pushable = 0, whileDead = true }
	tinsert(UISpecialFrames, "CreateCopyNameFrame")
    frame:SetSize(300, 140)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop{
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true, tileSize = 32, edgeSize = 32,
        insets   = {left=8,right=8,top=8,bottom=8}
    }
    local bg = frame:CreateTexture(nil,"BACKGROUND", nil, -1)
    bg:SetTexture("Interface\\AddOns\\RatedStats\\RatedStats.tga")
    bg:SetAllPoints(frame)

    -- 1) Title + Name EditBox
    local nameTitle = frame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    nameTitle:SetPoint("TOP", frame, "TOP", 0, -16)
    nameTitle:SetText("Player Name Copy:")
	nameTitle:SetFont(GetUnicodeSafeFont(), 8)

    local nameBox = CreateFrame("EditBox", "CreateCopyNameFrameEditBox", frame, "BackdropTemplate")
    nameBox:SetSize(150, 20)
    nameBox:SetPoint("TOP", nameTitle, "BOTTOM", 0, -4)
    nameBox:SetAutoFocus(false)
    nameBox:SetText(stats.name)
	nameBox:SetFont(GetUnicodeSafeFont(), 8, "OUTLINE")
	nameBox:SetJustifyH("CENTER")
    nameBox:HighlightText(0)
    nameBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		HideUIPanel(self:GetParent())
	end)

    -- 2) Close button
    local close = CreateFrame("Button", "CreateCopyNameFrameEditBoxCloseButton", frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT")

    -- 3) Loadout box / icons
    CreateFriendAndTalentButtons(stats, matchEntry, frame)

    frame:Show()
end

function RSTATS.CreateClickableName(parent, stats, matchEntry, x, y, columnWidth, rowHeight)
  local playerName = stats.name

  -- RatedStats_Achiev (optional): show highest PvP achievement icon if available
  local achievIconPath, achievIconTint

  if type(C_AddOns) == "table" and type(C_AddOns.GetAddOnEnableState) == "function" then
      if C_AddOns.GetAddOnEnableState("RatedStats_Achiev", nil) > 0
          and type(_G.RSTATS_Achiev_GetHighestPvpRank) == "function"
          and type(_G.RSTATS_Achiev_AddAchievementInfoToTooltip) == "function"
      then
          achievIconPath, _, achievIconTint = _G.RSTATS_Achiev_GetHighestPvpRank(playerName)
      end
  end

  local nameOffsetX = 0
  local iconSize = 8

  -- If we have an icon, place it inside the Character column and nudge the name right
  if achievIconPath then
      nameOffsetX = (iconSize * 0.5) + 2

      local iconBtn = CreateFrame("Button", nil, parent)
      iconBtn:SetSize(iconSize, iconSize)
      iconBtn:SetPoint("CENTER", parent, "TOPLEFT", x + (iconSize * 0.5) + 2, y - rowHeight/2)

      local iconTex = iconBtn:CreateTexture(nil, "OVERLAY")
      iconTex:SetAllPoints()
      iconTex:SetTexture(achievIconPath)

      if achievIconTint and type(achievIconTint) == "table" then
          iconTex:SetVertexColor(achievIconTint[1] or 1, achievIconTint[2] or 1, achievIconTint[3] or 1)
      else
          iconTex:SetVertexColor(1, 1, 1)
      end

      iconBtn:SetScript("OnEnter", function(self)
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          local baseName, realm = strsplit("-", playerName)
          realm = realm or GetRealmName()
          _G.RSTATS_Achiev_AddAchievementInfoToTooltip(GameTooltip, baseName, realm)
          GameTooltip:Show()
      end)
      iconBtn:SetScript("OnLeave", function()
          GameTooltip:Hide()
      end)
  end

  local nameText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  nameText:SetFont(GetUnicodeSafeFont(), 8, "OUTLINE")
  nameText:SetPoint("CENTER", parent, "TOPLEFT", x + columnWidth/2 + nameOffsetX, y - rowHeight/2)
  nameText:SetText(playerName)
  nameText:SetFont(GetUnicodeSafeFont(), 8)

  local clickableFrame = CreateFrame("Button", "ClickableName", parent)
  clickableFrame:SetSize(nameText:GetStringWidth(), nameText:GetStringHeight())
  clickableFrame:SetPoint("CENTER", nameText, "CENTER")

  clickableFrame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(c("Click me to copy name and see loadout"))
    GameTooltip:Show()
  end)
  clickableFrame:SetScript("OnLeave", GameTooltip_Hide)

  clickableFrame:SetScript("OnClick", function()
    RSTATS.OpenPlayerDetails(stats, matchEntry)
  end)

  return nameText
end

function CreateNestedTable(parent, playerStats, friendlyFaction, isInitial, isMissedGame, content, matchEntry, tabID)
    local nestedName = parent:GetName() and ("NestedTable_" .. parent:GetName()) or nil
    local nestedTable = CreateFrame("Frame", nestedName, parent, "BackdropTemplate")

    -- Determine the match type using the correct function
    local matchType = IdentifyPvPMatchType()

    -- Determine the actual number of players per team (assuming equal teams)
    local playersPerTeam = #playerStats / 2

    -- Get the number of rows based on the match type
    local numberOfRows = playersPerTeam
    
    -- Calculate the size of the nested table
    local rowHeight = 15  -- Adjust this value based on your actual row height
    local tableHeight = playersPerTeam * rowHeight + 30  -- Adjust for padding or additional spacing
	local enemyBaseX	
	local baseWidth

	-- Set base width as a percentage of the full config width
    if UIConfig.isCompact then
       enemyBaseX = parent:GetWidth() * 0.65 -- start exactly one pane right
	   baseWidth = parent:GetWidth()    -- previously we doubled nested table width when in compact
	else
	   enemyBaseX = parent:GetWidth() * 0.65  -- first enemy col
	   baseWidth = parent:GetWidth()
	end

	nestedTable:SetSize(baseWidth, tableHeight)
	nestedTable:SetFrameStrata("HIGH")
	nestedTable:SetFrameLevel(22)
	nestedTable:Hide()
	
    local isSS = (tabID == 1)
    local is2v2 = (tabID == 2)
    local is3v3 = (tabID == 3)
    local isRBG = (tabID == 4)
    local isSoloRBG = (tabID == 5)
    local showDeaths = (isRBG or isSoloRBG)

    -- ------------------------------------------------------------------
    -- column geometry (dynamic based on parent:GetWidth())
    -- ------------------------------------------------------------------
    -- percentages for each of the 13 base-pixel columns (for a 2004px parent)
	local baseFracs = {
		0.049900,  -- 1 Character
		0.019960,  -- 2 Faction
		0.019960,  -- 3 Race
		0.024950,  -- 4 Class
		0.029940,  -- 5 Spec
		0.019960,  -- 6 Role
		0.024950,  -- 7 CR
		0.019960,  -- 8 KBs
		(is2v2 or is3v3) and 0 or 0.019960,                         -- 9 HK/Wins (collapses)
		0.029940,  -- 10 Damage
		0.029940,  -- 11 Healing
		0.039920,  -- 12 Rating Chg
		((is2v2 or is3v3) and (0.019960 + 0.019960) or 0.019960),   -- 13 Objective absorbs slack
	}

	if showDeaths then
		-- Insert Deaths after HKs/Wins (RBG / RBGB only)
		table.insert(baseFracs, 10, 0.019960)
	end

    local COLS_PER_TEAM = #baseFracs                             -- still =13
    
    -- build ally+enemy columnWidths at runtime
    local columnWidths = {}
    do
        local totalW = baseWidth
        for i = 1, COLS_PER_TEAM do
            columnWidths[i] = baseFracs[i] * totalW
        end
        for i = 1, COLS_PER_TEAM do
            columnWidths[#columnWidths+1] = baseFracs[i] * totalW
        end
    end
	 
    -- running X positions (+5px padding; enemy side starts at 50%)
    local columnPositions = {}
    do
        local totalW = baseWidth
        local halfW  = totalW * 0.5
        -- your team (cols 1..COLS_PER_TEAM)
        local x = 0
        for i = 1, COLS_PER_TEAM do
            columnPositions[i] = x + 5
            x = x + columnWidths[i]
        end
        -- enemy team (cols COLS_PER_TEAM+1 .. 2*COLS_PER_TEAM)
        local x2 = halfW
        for i = 1, COLS_PER_TEAM do
            columnPositions[COLS_PER_TEAM + i] = x2 + 5
            x2 = x2 + columnWidths[COLS_PER_TEAM + i]
        end
    end

    -- Hide Wins/HKs column for 2v2/3v3 (no meaningful data)
    local hideWinHK = (is2v2 or is3v3)
    local WINHK_COL = 9 -- per-team column index (1..13)
    local function IsHiddenWinHKCol(colIndex)
        if not hideWinHK then return false end
        return (colIndex == WINHK_COL) or (colIndex == (COLS_PER_TEAM + WINHK_COL))
    end

    local winHKHeader = (isSS and "Wins") or (hideWinHK and "") or "HKs"

    local objectiveHeader = ((isSS or is2v2 or is3v3) and "" or "Objective")

    local headersPerTeam = {
        "Character", "Faction", "Race", "Class", "Spec", "Role", "CR / MMR", "KBs", winHKHeader
    }
    if showDeaths then
        table.insert(headersPerTeam, 10, "Deaths")
    end
    table.insert(headersPerTeam, "Damage")
    table.insert(headersPerTeam, "Healing")
    table.insert(headersPerTeam, "Rating Chg")
    table.insert(headersPerTeam, objectiveHeader)

    local headers = {}
    for i = 1, #headersPerTeam do headers[#headers+1] = headersPerTeam[i] end
    for i = 1, #headersPerTeam do headers[#headers+1] = headersPerTeam[i] end

    local headerHeight = 18  -- Height of the header row

    -- Create "Your Team" header
    local yourTeamHeader = nestedTable:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    yourTeamHeader:SetFont(GetUnicodeSafeFont(), headerFontSize)
    yourTeamHeader:SetJustifyH("LEFT")
    yourTeamHeader:SetPoint("TOPLEFT", nestedTable, "TOPLEFT", parent:GetWidth() * 0.15, 0)  -- Adjust position above friendly players
    yourTeamHeader:SetText("Your Team")

    -- Create "Enemy Team" header
	local enemyTeamHeader = nestedTable:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	enemyTeamHeader:SetFont(GetUnicodeSafeFont(), headerFontSize)
	enemyTeamHeader:SetJustifyH("CENTER")
	-- we’ll anchor it *after* we calculate enemyBaseX
	enemyTeamHeader:SetText("Enemy Team")

    -- Create nested table header row
	local totalColumnsPerTeam = COLS_PER_TEAM
	local parentWidth = parent:GetWidth()
	local columnWidth = (parentWidth * 0.5) / totalColumnsPerTeam
	local headerY = -headerHeight  -- Keep vertical spacing consistent
--	local paneW     = parent:GetParent():GetParent():GetWidth()   -- visible-pane width
	
	-- table now spans 13 cols (friendly) + 13 cols (enemy)
--	local baseWidth = paneW * 1.92          -- 0.92 ≈ 13/14 → use real ratio
	nestedTable:SetWidth(baseWidth)
	enemyTeamHeader:ClearAllPoints()
	enemyTeamHeader:SetPoint("TOPLEFT", nestedTable, "TOPLEFT", enemyBaseX, 0)
	
	for i, header in ipairs(headers) do
		local headerText = nestedTable:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		headerText:SetFont(GetUnicodeSafeFont(), headerFontSize)
		headerText:SetJustifyH("CENTER")
		headerText:SetText(header)
	
		local xPos
		if i <= totalColumnsPerTeam then
			-- “Your team” columns
			xPos = columnPositions[i]
		else
			-- “Enemy team” columns already include the half-width offset in columnPositions
			xPos = columnPositions[i]
		end
		
		local width = columnWidths[i]
	
		headerText:SetPoint("TOPLEFT", nestedTable, "TOPLEFT", xPos, -headerHeight)
		headerText:SetWidth(width)

        -- Tooltips for combined CR/MMR + change columns
        do
            -- Normalize to per-team column index (1..COLS_PER_TEAM)
            local perTeamIndex = (i <= totalColumnsPerTeam) and i or (i - totalColumnsPerTeam)
            local CR_COL = 7
            local CHG_COL = showDeaths and 13 or 12

            if perTeamIndex == CR_COL then
                headerText:EnableMouse(true)
                headerText:SetScript("OnEnter", function()
                    GameTooltip:SetOwner(headerText, "ANCHOR_RIGHT")
                    GameTooltip:ClearLines()
                    GameTooltip:AddLine("CR / MMR", 1, 1, 1)
                    GameTooltip:AddLine("Post-match Combat Rating / Post-match Matchmaking Rating", 1, 1, 1)
                    GameTooltip:Show()
                end)
                headerText:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
            elseif perTeamIndex == CHG_COL then
                headerText:EnableMouse(true)
                headerText:SetScript("OnEnter", function()
                    GameTooltip:SetOwner(headerText, "ANCHOR_RIGHT")
                    GameTooltip:ClearLines()
                    GameTooltip:AddLine("CR / MMR Change", 1, 1, 1)
                    GameTooltip:AddLine("CR change / MMR change for this match", 1, 1, 1)
                    GameTooltip:Show()
                end)
                headerText:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
            end
        end

        -- Fully hide the Wins/HKs header text for 2v2/3v3
        if IsHiddenWinHKCol(i) then
            headerText:SetText("")
        end
	end
    -- Separate friendly and enemy player stats
    local friendlyPlayers = {}
    local enemyPlayers = {}

    if isInitial or isMissedGame then
        -- For initial entries, the player's stats are on the left and placeholders on the right
        table.insert(friendlyPlayers, playerStats[1])  -- Assume the player is the first entry
        for i = 1, playersPerTeam do
            table.insert(enemyPlayers, {
                name = "-", faction = "-", race = "-", class = "-", spec = "-", role = "-", 
                newrating = "-", killingBlows = "-", honorableKills = "-", deaths = "-", damage = "-", healing = "-", ratingChange = "-"
            })  -- Add placeholder entries for the enemy
        end
    elseif matchEntry and matchEntry.isSoloShuffle then
        -- Solo Shuffle: trust persisted isFriendly
        for _, player in ipairs(playerStats) do
            if player.isFriendly then
                table.insert(friendlyPlayers, player)
            else
                table.insert(enemyPlayers, player)
            end
        end
    elseif matchEntry and matchEntry.myTeamIndex ~= nil then
        -- Solo Shuffle / cross-faction: separate by numeric team index
        for _, player in ipairs(playerStats) do
            if player.teamIndex ~= nil and player.teamIndex == matchEntry.myTeamIndex then
                table.insert(friendlyPlayers, player)
            else
                table.insert(enemyPlayers, player)
            end
        end
    else
        -- Fallback: separate players by faction string (old behaviour)
        for _, player in ipairs(playerStats) do
            if player.faction == friendlyFaction then
                table.insert(friendlyPlayers, player)
            else
                table.insert(enemyPlayers, player)
            end
        end
    end

    -- ------------------------------------------------------------------
    -- Sort rows per team:
    -- If YOU are a healer (role=4) sort by healing, otherwise sort by damage.
    -- Sorting is per-team only (friendly sorted within friendly, enemy within enemy).
    -- ------------------------------------------------------------------
    local function GetNumericStat(p, field)
        if not p then return 0 end
        local v = p[field]
        v = tonumber(v)
        return v or 0
    end

    if not (isInitial or isMissedGame) then
        local myName = playerName
        local myRole = nil

        local function NamesMatch(a, b)
            if not (a and b) then return false end
            if a == b then return true end
            -- allow comparing "Name-Realm" vs "Name"
            local abase = a:match("^(.-)%-") or a
            local bbase = b:match("^(.-)%-") or b
            return abase == bbase
        end

        for _, p in ipairs(friendlyPlayers) do
            if p and NamesMatch(p.name, myName) then
                myRole = p.role
                break
            end
        end

        local isHealer =
            (myRole == 4) or
            (myRole == "HEALER")

        local sortField = isHealer and "healing" or "damage"

        table.sort(friendlyPlayers, function(a, b)
            return GetNumericStat(a, sortField) > GetNumericStat(b, sortField)
        end)

        table.sort(enemyPlayers, function(a, b)
            return GetNumericStat(a, sortField) > GetNumericStat(b, sortField)
        end)
    end
    
    -- ------------------------------------------------------------------
    -- Theme colour (kept - removing Config:GetThemeColor causes a lua error)
    -- BUT: row highlighting should use the addon text colour (COLOR_HEX),
    -- not the theme (00ccff).
    -- ------------------------------------------------------------------
    local themeR, themeG, themeB = Config:GetThemeColor()

    local function HexToRGB01(hex)
        if type(hex) ~= "string" then return nil end
        hex = hex:gsub("^|cff", ""):gsub("^#", "")
        if #hex == 8 then
            -- if someone ever feeds AARRGGBB, drop AA
            hex = hex:sub(3)
        end
        if #hex ~= 6 then return nil end
        local r = tonumber(hex:sub(1, 2), 16)
        local g = tonumber(hex:sub(3, 4), 16)
        local b = tonumber(hex:sub(5, 6), 16)
        if not (r and g and b) then return nil end
        return r / 255, g / 255, b / 255
    end

    local highlightR, highlightG, highlightB = themeR, themeG, themeB
    do
        -- Use the actual addon text colour (core.lua -> RSTATS.Config.ThemeColor = "b69e86")
        local addonHex = (RSTATS and RSTATS.Config and RSTATS.Config.ThemeColor) or COLOR_HEX
        local r, g, b = HexToRGB01(addonHex)
        if r then
            highlightR, highlightG, highlightB = r, g, b
        end
    end

    -- ------------------------------------------------------------------
    -- Damage/Healing rank indicators (team + overall)
    -- ------------------------------------------------------------------
    local function BuildRankMap(players, field)
        local items = {}
        for _, p in ipairs(players) do
            local v = p and p[field]
            v = tonumber(v)
            if v then
                items[#items + 1] = { p = p, v = v }
            end
        end

        table.sort(items, function(a, b)
            return a.v > b.v
        end)

        local map = {}
        local lastV, rank = nil, 0
        for idx, it in ipairs(items) do
            if lastV == nil or it.v ~= lastV then
                rank = idx
                lastV = it.v
            end
            map[it.p] = rank
        end
        return map
    end

    local function CreateRankIndicator(parentFrame, xPos, width, rowOffset, rowHeight, teamRank, teamSize, overallRank, totalSize, fontSize, highlightRow)
        if not (teamRank and overallRank and teamSize and totalSize) then
            return
        end

        local rightX  = xPos + width - 6
        local centerY = rowOffset - (rowHeight / 2)

        local topFS = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        topFS:SetFont(GetUnicodeSafeFont(), fontSize)
        topFS:SetJustifyH("RIGHT")
        topFS:SetPoint("RIGHT", parentFrame, "TOPLEFT", rightX, centerY + 4)
        topFS:SetText(string.format("%d/%d", teamRank, teamSize))

        local botFS = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        botFS:SetFont(GetUnicodeSafeFont(), fontSize)
        botFS:SetJustifyH("RIGHT")
        botFS:SetPoint("RIGHT", parentFrame, "TOPLEFT", rightX, centerY - 4)
        botFS:SetText(string.format("%d/%d", overallRank, totalSize))

        if highlightRow then
            topFS:SetTextColor(highlightR, highlightG, highlightB)
            botFS:SetTextColor(highlightR, highlightG, highlightB)
        end

        local hit = CreateFrame("Frame", nil, parentFrame)
        hit:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", xPos + width - 26, rowOffset)
        hit:SetSize(24, rowHeight)
        hit:EnableMouse(true)
        hit:SetScript("OnEnter", function()
            GameTooltip:SetOwner(hit, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Top row is your position in your team", 1, 1, 1)
            GameTooltip:AddLine("Bottom row is your position overall", 1, 1, 1)
            GameTooltip:Show()
        end)
        hit:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    local allPlayers = {}
    for _, p in ipairs(friendlyPlayers) do
        allPlayers[#allPlayers + 1] = p
    end
    for _, p in ipairs(enemyPlayers) do
        allPlayers[#allPlayers + 1] = p
    end

    local friendlyDamageRank  = BuildRankMap(friendlyPlayers, "damage")
    local enemyDamageRank     = BuildRankMap(enemyPlayers, "damage")
    local overallDamageRank   = BuildRankMap(allPlayers, "damage")

    local friendlyHealingRank = BuildRankMap(friendlyPlayers, "healing")
    local enemyHealingRank    = BuildRankMap(enemyPlayers, "healing")
    local overallHealingRank  = BuildRankMap(allPlayers, "healing")

    local friendlyTeamSize  = #friendlyPlayers
    local enemyTeamSize     = #enemyPlayers
    local totalPlayerCount  = #allPlayers

    -- CR/MMR display helpers (scoreboard provides rating + (pre/post)match MMR in rated brackets)
    local function HasMMR(p)
        if not p then return false end
        local post = tonumber(p.postmatchMMR) or 0
        local pre  = tonumber(p.prematchMMR) or 0
        return (post > 0) or (pre > 0)
    end

    local function FormatSignedNumber(n)
        n = tonumber(n)
        if n == nil then return "-" end
        if n > 0 then
            return "+" .. n
        end
        return tostring(n)
    end

    local function FormatCRMMR(p)
        local crVal = tonumber(p and p.newrating) or tonumber(p and p.rating)
        if crVal == nil then
            return "-"
        end
        if HasMMR(p) then
            local mmrVal = tonumber(p and p.postmatchMMR) or tonumber(p and p.prematchMMR) or 0
            return string.format("%d / %d", crVal, mmrVal)
        end
        return tostring(crVal)
    end

    local function FormatCRMMRChange(p)
        local crTxt = FormatSignedNumber(p and p.ratingChange)
        if HasMMR(p) then
            local pre  = tonumber(p and p.prematchMMR) or 0
            local post = tonumber(p and p.postmatchMMR) or 0
            local delta = 0

            if pre > 0 and post > 0 then
                delta = post - pre
            end

            local mmrTxt = FormatSignedNumber(delta)
            return crTxt .. " / " .. mmrTxt
        end
        return crTxt
    end

    -- Highlight rules:
    -- - Always tint YOUR row
    -- - RBGB only: if the match was a duo, also tint the duo partner row
    local myGUID = UnitGUID("player")
    local duoPartnerName = (tabID == 5 and matchEntry and matchEntry.duoPartner) or nil

    local function NamesMatch(a, b)
        if not (a and b) then return false end
        if a == b then return true end
        -- allow comparing "Name-Realm" vs "Name"
        local abase = a:match("^(.-)%-") or a
        local bbase = b:match("^(.-)%-") or b
        return abase == bbase
    end

    local function ShouldHighlightRow(p)
        if not p then return false end
        if myGUID and p.guid and p.guid == myGUID then return true end
        if p.name and playerName and NamesMatch(p.name, playerName) then return true end
        if duoPartnerName and p.name and NamesMatch(p.name, duoPartnerName) then return true end
        return false
    end

    -- Populate friendly player stats
    for index, player in ipairs(friendlyPlayers) do
        local rowOffset = -(headerHeight + 15 * index)  -- Adjust rowOffset to account for headers
        local highlightRow = ShouldHighlightRow(player)
        local nameText = RSTATS.CreateClickableName(nestedTable, player, matchEntry, columnPositions[1], rowOffset, columnWidths[1], rowHeight)
        if nameText and highlightRow then
            nameText:SetTextColor(highlightR, highlightG, highlightB)
        end
        local winHKValue = (isSS and player.wins) or (hideWinHK and "") or player.honorableKills

        local DAMAGE_COL = showDeaths and 11 or 10
        local HEAL_COL   = showDeaths and 12 or 11

        local rowStats
        if showDeaths then
            rowStats = {
			    "",
                factionIcons[player.faction] or player.faction,
                raceIcons[player.race] or player.race,
                classIcons[player.class] or player.class,
                specIcons[player.spec] or player.spec,
                roleIcons[player.role] or player.role,
                FormatCRMMR(player),
                player.killingBlows,
                winHKValue,
                player.deaths or "-",
                FormatNumber(player.damage),
                FormatNumber(player.healing),
                FormatCRMMRChange(player),
                ((isSS or is2v2 or is3v3) and "" or (player.objective or "-"))
            }
        else
            rowStats = {
			    "",
                factionIcons[player.faction] or player.faction,
                raceIcons[player.race] or player.race,
                classIcons[player.class] or player.class,
                specIcons[player.spec] or player.spec,
                roleIcons[player.role] or player.role,
                FormatCRMMR(player),
                player.killingBlows,
                winHKValue,
                FormatNumber(player.damage),
                FormatNumber(player.healing),
                FormatCRMMRChange(player),
                ((isSS or is2v2 or is3v3) and "" or (player.objective or "-"))
            }
        end

        for i, stat in ipairs(rowStats) do
            if i == 2 then
                CreateIconWithTooltip(nestedTable, stat, player.faction, columnPositions[i], rowOffset, columnWidths[i], rowHeight)
            elseif i == 3 then
                CreateIconWithTooltip(nestedTable, stat, player.race, columnPositions[i], rowOffset, columnWidths[i], rowHeight)
            elseif i == 4 then
                CreateIconWithTooltip(nestedTable, stat, player.class, columnPositions[i], rowOffset, columnWidths[i], rowHeight)
            elseif i == 5 then
                CreateIconWithTooltip(nestedTable, stat, player.spec, columnPositions[i], rowOffset, columnWidths[i], rowHeight)
            elseif i == 6 then
                -- Add role tooltip
                CreateIconWithTooltip(nestedTable, stat, roleTooltips[player.role], columnPositions[i], rowOffset, columnWidths[i], rowHeight)
            elseif i == COLS_PER_TEAM then
                local textValue = stat or "-"
                local fs = nestedTable:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                fs:SetFont(GetUnicodeSafeFont(), entryFontSize)
                fs:SetJustifyH("CENTER")
                fs:SetPoint("CENTER", nestedTable, "TOPLEFT", columnPositions[i] + (columnWidths[i] / 2), rowOffset - (rowHeight / 2))
                fs:SetText(tostring(textValue))
                if highlightRow then
                    fs:SetTextColor(highlightR, highlightG, highlightB)
                end

                -- Add objective tooltip
                fs:EnableMouse(true)
                fs:SetScript("OnEnter", function()
                    GameTooltip:SetOwner(fs, "ANCHOR_RIGHT")
                    GameTooltip:ClearLines()

                    -- Show friendly label based on map name
                    local mapLabel = matchEntry and matchEntry.mapName or ""
                    local tooltipText
                    if mapShortName[mapLabel] == "EOTS" then
                        tooltipText = "Flags Capped / Bases Capped / Bases Defended"
                    elseif mapShortName[mapLabel] == "WSG" or mapShortName[mapLabel] == "TP" then
                        tooltipText = "Flags Capped / Flags Returned"
                    elseif mapShortName[mapLabel] == "AB" or mapShortName[mapLabel] == "DWG" or mapShortName[mapLabel] == "BfG" then
                        tooltipText = "Bases Capped / Bases Defended"
                    elseif mapShortName[mapLabel] == "TOK" then
                        tooltipText = "Orbs Held / Points"
                    elseif mapShortName[mapLabel] == "SSM" then
                        tooltipText = "Carts / Points"
                    elseif mapShortName[mapLabel] == "DHR" then
                        tooltipText = "Crystal Points / Cart Points"
                    else
                        tooltipText = "Objective"
                    end

                    GameTooltip:AddLine(tooltipText, 1, 1, 1)
                    GameTooltip:Show()
                end)
                fs:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
            else
                local textValue = stat or "-"  -- Provide a default value if stat is nil
                local text = nestedTable:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                local xPos = columnPositions[i]
                local width = columnWidths[i]

                text:SetFont(GetUnicodeSafeFont(), entryFontSize)

                if i == DAMAGE_COL or i == HEAL_COL then
                    local rankFontSize = math.max(7, (entryFontSize or 11) - 6)
                    local teamRank, overallRank, teamSize = nil, nil, friendlyTeamSize

                    if i == DAMAGE_COL then
                        teamRank = friendlyDamageRank[player]
                        overallRank = overallDamageRank[player]
                    else
                        teamRank = friendlyHealingRank[player]
                        overallRank = overallHealingRank[player]
                    end

                    if teamRank and overallRank and teamSize and teamSize > 0 and totalPlayerCount and totalPlayerCount > 0 then
                        -- Right-justify the number and reserve space for the 2-line rank indicator
                        text:SetJustifyH("RIGHT")
                        text:SetWidth(width - 30)
                        text:SetPoint("RIGHT", nestedTable, "TOPLEFT", xPos + width - 28, rowOffset - (rowHeight / 2))
                        text:SetText(tostring(textValue))
                        if highlightRow then
                            text:SetTextColor(highlightR, highlightG, highlightB)
                        end

                        CreateRankIndicator(nestedTable, xPos, width, rowOffset, rowHeight, teamRank, teamSize, overallRank, totalPlayerCount, rankFontSize, highlightRow)
                    else
                        text:SetJustifyH("CENTER")
                        text:SetPoint("CENTER", nestedTable, "TOPLEFT", xPos + (width / 2), rowOffset - (rowHeight / 2))
                        text:SetText(tostring(textValue))
                        if highlightRow then
                            text:SetTextColor(highlightR, highlightG, highlightB)
                        end
                    end
                else
                    text:SetJustifyH("CENTER")
                    text:SetPoint("CENTER", nestedTable, "TOPLEFT", xPos + (width / 2), rowOffset - (rowHeight / 2))
                    text:SetText(tostring(textValue))  -- Ensure the value is converted to a string
                    if highlightRow then
                            text:SetTextColor(highlightR, highlightG, highlightB)
                    end
                end
            end
        end  -- This 'end' closes the inner 'for' loop
    end  -- This 'end' closes the outer 'for' loop
    
    -- Populate enemy player stats
    for index, player in ipairs(enemyPlayers) do
		local rowOffset = -(headerHeight + 15 * index)  -- Adjust rowOffset to account for headers
        RSTATS.CreateClickableName(nestedTable, player, matchEntry, columnPositions[COLS_PER_TEAM + 1], rowOffset, columnWidths[COLS_PER_TEAM + 1], rowHeight)
        local winHKValue = (isSS and player.wins) or (hideWinHK and "") or player.honorableKills

        local DAMAGE_COL = showDeaths and 11 or 10
        local HEAL_COL   = showDeaths and 12 or 11

        local rowStats
        if showDeaths then
            rowStats = {
                "",
                factionIcons[player.faction] or player.faction,
                raceIcons[player.race] or player.race,
                classIcons[player.class] or player.class,
                specIcons[player.spec] or player.spec,
                roleIcons[player.role] or player.role,
                FormatCRMMR(player),
                player.killingBlows,
                winHKValue,
                player.deaths or "-",
                FormatNumber(player.damage),
                FormatNumber(player.healing),
                FormatCRMMRChange(player),
                ((isSS or is2v2 or is3v3) and "" or (player.objective or "-"))
            }
        else
            rowStats = {
                "",
                factionIcons[player.faction] or player.faction,
                raceIcons[player.race] or player.race,
                classIcons[player.class] or player.class,
                specIcons[player.spec] or player.spec,
                roleIcons[player.role] or player.role,
                FormatCRMMR(player),
                player.killingBlows,
                winHKValue,
                FormatNumber(player.damage),
                FormatNumber(player.healing),
                FormatCRMMRChange(player),
                ((isSS or is2v2 or is3v3) and "" or (player.objective or "-"))
            }
        end

        for i, stat in ipairs(rowStats) do
            local ci    = COLS_PER_TEAM + i
            local xPos  = columnPositions[ci]
            local width = columnWidths[ci]

            if i == 2 then
                CreateIconWithTooltip(nestedTable, stat, player.faction, xPos, rowOffset, width, rowHeight)
            elseif i == 3 then
                CreateIconWithTooltip(nestedTable, stat, player.race, xPos, rowOffset, width, rowHeight)
            elseif i == 4 then
                CreateIconWithTooltip(nestedTable, stat, player.class, xPos, rowOffset, width, rowHeight)
            elseif i == 5 then
                CreateIconWithTooltip(nestedTable, stat, player.spec, xPos, rowOffset, width, rowHeight)
            elseif i == 6 then
                -- Add role tooltip
                CreateIconWithTooltip(nestedTable, stat, roleTooltips[player.role], xPos, rowOffset, width, rowHeight)
            elseif i == COLS_PER_TEAM then
                local textValue = stat or "-"
                local fs = nestedTable:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                fs:SetFont(GetUnicodeSafeFont(), entryFontSize)
                fs:SetJustifyH("CENTER")
                fs:SetPoint("CENTER", nestedTable, "TOPLEFT", xPos + (width / 2), rowOffset - (rowHeight / 2))
                fs:SetText(tostring(textValue))

                -- Add objective tooltip
                fs:EnableMouse(true)
                fs:SetScript("OnEnter", function()
                    GameTooltip:SetOwner(fs, "ANCHOR_RIGHT")
                    GameTooltip:ClearLines()

                    -- Show enemy label based on map name
                    local mapLabel = matchEntry and matchEntry.mapName or ""
                    local tooltipText
                    if mapShortName[mapLabel] == "EOTS" then
                        tooltipText = "Flags Capped / Bases Capped / Bases Defended"
                    elseif mapShortName[mapLabel] == "WSG" or mapShortName[mapLabel] == "TP" then
                        tooltipText = "Flags Capped / Flags Returned"
                    elseif mapShortName[mapLabel] == "AB" or mapShortName[mapLabel] == "DWG" or mapShortName[mapLabel] == "BfG" then
                        tooltipText = "Bases Capped / Bases Defended"
                    elseif mapShortName[mapLabel] == "TOK" then
                        tooltipText = "Orbs Held / Points"
                    elseif mapShortName[mapLabel] == "SSM" then
                        tooltipText = "Carts / Points"
                    elseif mapShortName[mapLabel] == "DHR" then
                        tooltipText = "Crystal Points / Cart Points"
                    else
                        tooltipText = "Objective"
                    end

                    GameTooltip:AddLine(tooltipText, 1, 1, 1)
                    GameTooltip:Show()
                end)
                fs:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
            else
                local textValue = stat or "-"  -- Provide a default value if stat is nil
                local text = nestedTable:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                text:SetFont(GetUnicodeSafeFont(), entryFontSize)

                if i == DAMAGE_COL or i == HEAL_COL then
                    local rankFontSize = math.max(7, (entryFontSize or 11) - 6)
                    local teamRank, overallRank, teamSize = nil, nil, enemyTeamSize

                    if i == DAMAGE_COL then
                        teamRank = enemyDamageRank[player]
                        overallRank = overallDamageRank[player]
                    else
                        teamRank = enemyHealingRank[player]
                        overallRank = overallHealingRank[player]
                    end

                    if teamRank and overallRank and teamSize and teamSize > 0 and totalPlayerCount and totalPlayerCount > 0 then
                        -- Right-justify the number and reserve space for the 2-line rank indicator
                        text:SetJustifyH("RIGHT")
                        text:SetWidth(width - 30)
                        text:SetPoint("RIGHT", nestedTable, "TOPLEFT", xPos + width - 28, rowOffset - (rowHeight / 2))
                        text:SetText(tostring(textValue))

                        CreateRankIndicator(nestedTable, xPos, width, rowOffset, rowHeight, teamRank, teamSize, overallRank, totalPlayerCount, rankFontSize)
                    else
                        text:SetJustifyH("CENTER")
                        text:SetPoint("CENTER", nestedTable, "TOPLEFT", xPos + (width / 2), rowOffset - (rowHeight / 2))
                        text:SetText(tostring(textValue))
                    end
                else
                    text:SetJustifyH("CENTER")
                    text:SetPoint("CENTER", nestedTable, "TOPLEFT", xPos + (width / 2), rowOffset - (rowHeight / 2))
                    text:SetText(tostring(textValue))  -- Ensure the value is converted to a string
                end
            end
        end  -- This 'end' closes the inner 'for' loop
    end  -- This 'end' closes the outer 'for' loop

    -- Add placeholders for missing friendly players if necessary
    if not (isInitial or isMissedGame) and #friendlyPlayers < numberOfRows then
        for index = #friendlyPlayers + 1, numberOfRows do
            local rowOffset = -(headerHeight + 15 * index)
            for i = 1, COLS_PER_TEAM do
                local text = nestedTable:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
				local xPos = columnPositions[i]
				local width = columnWidths[i]
				text:SetPoint("CENTER", nestedTable, "TOPLEFT", xPos + (width / 2), rowOffset - (rowHeight / 2))
				text:SetWidth(width)
				text:SetFont(GetUnicodeSafeFont(), entryFontSize)
				text:SetJustifyH("CENTER")
				text:SetText(IsHiddenWinHKCol(i) and "" or "-")
            end
        end
    end
    
    -- Add placeholders for missing enemy players if necessary
    if not (isInitial or isMissedGame) and #enemyPlayers < numberOfRows then
        for index = #enemyPlayers + 1, numberOfRows do
            local rowOffset = -(headerHeight + 15 * index)
            for i = (COLS_PER_TEAM + 1), (COLS_PER_TEAM * 2) do
                local text = nestedTable:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
				local xPos = columnPositions[i]
				local width = columnWidths[i]
				text:SetPoint("CENTER", nestedTable, "TOPLEFT", xPos + (width / 2), rowOffset - (rowHeight / 2))
				text:SetWidth(width)
				text:SetFont(GetUnicodeSafeFont(), entryFontSize)
				text:SetJustifyH("CENTER")
				text:SetText(IsHiddenWinHKCol(i) and "" or "-")
            end
        end
    end

	function nestedTable:UpdateTeamView()
		if UIConfig.isCompact and UIConfig.ActiveTeamView == 2 then
			baseWidth = parent:GetWidth() * 2    -- double nested table width when in compact
		end
	-- **Re-anchor** using the new offset: keep the same relative Y,
	-- but shift X by `offset` pixels.
	self:ClearAllPoints()
	self:SetWidth(baseWidth)
	self:SetPoint("TOPLEFT", self:GetParent(), "TOPLEFT", 0, -14)
	end

    SaveData()

	RSTATS.LastNestedTable = nestedTable
	nestedTable:UpdateTeamView()

    return nestedTable

end

-- Define the DisplayCurrentCRMMR function
function DisplayCurrentCRMMR(contentFrame, categoryID)
    -- Retrieve CR and MMR using GetPersonalRatedInfo for the specified categoryID
    -- categoryID here is the rated bracket index (1=2v2, 2=3v3, 4=RBG, 7=Solo Shuffle, 9=Blitz)
    -- We prefer the last match entry for CR/MMR display (most reliable), but tier icons are derived from the same bracket.

    local currentCR  = 0
    local currentMMR = 0
    local useSpec = (categoryID == 7 or categoryID == 9)
    local _, playerClassTag = UnitClass("player")

    local function GetActiveSpecID()
        local specIndex = GetSpecialization()
        if not specIndex then return nil end
        return select(1, GetSpecializationInfo(specIndex))
    end

    local function ResolveEntrySpecID(entry)
        if not entry or type(entry) ~= "table" then return nil end
        if entry.specID then return entry.specID end
        local specName = entry.specName
        if (not specName or specName == "") and type(entry.playerStats) == "table" then
            for _, stats in ipairs(entry.playerStats) do
                if stats and stats.name == playerName then
                    specName = stats.spec
                    break
                end
            end
        end

        if specName and playerClassTag and RSTATS and RSTATS.Roles
            and RSTATS.Roles[playerClassTag]
            and RSTATS.Roles[playerClassTag][specName]
            and RSTATS.Roles[playerClassTag][specName].specID
        then
            entry.specID = RSTATS.Roles[playerClassTag][specName].specID
            return entry.specID
        end

        return nil
    end

    local activeSpecID = useSpec and GetActiveSpecID() or nil

    -- Live rating: updates immediately when the player swaps spec.
    do
        local crLive, mmrLive = GetCRandMMR(categoryID)
        currentCR  = tonumber(crLive)  or 0
        currentMMR = tonumber(mmrLive) or 0

        -- IMPORTANT:
        -- For SS (7) + RBGB (9) we do NOT want to "lock in" the live/API MMR,
        -- because it can be misleading. These brackets should prefer the last
        -- stored post-match MMR from our history (playerStats / friendlyMMR).
        if categoryID == 7 or categoryID == 9 then
            currentMMR = 0
        end
    end

    local categoryMappings = {
        [1] = "v2History",
        [2] = "v3History",
        [4] = "RBGHistory",
        [7] = "SoloShuffleHistory",
        [9] = "SoloRBGHistory",
    }
	
    local historyTable = Database[categoryMappings[categoryID]]
    local highestMatchID = nil
    local highestMatchEntry = nil

    -- 1) First, find the entry with the highest matchID
    if historyTable and #historyTable > 0 then
        local useSpec = (categoryID == 7 or categoryID == 9)
        for _, entry in ipairs(historyTable) do
            local ok = true
            if useSpec then
                -- SS/RBGB are spec-scoped. If we cannot resolve active spec, do NOT pick a row.
                if not activeSpecID then
                    ok = false
                else
                    local sid = ResolveEntrySpecID(entry)
                    ok = (sid == activeSpecID)
                end
            end

            -- Never let placeholder "Missed Game" rows drive Current CR/MMR display.
            local isMissed = entry and (entry.isMissedGame or entry.winLoss == "Missed Game" or entry.friendlyWinLoss == "Missed Game")
            if ok and (not isMissed) and entry.matchID and (not highestMatchID or entry.matchID > highestMatchID) then
                highestMatchID = entry.matchID
                highestMatchEntry = entry
            end
        end
    end

    -- 2) If we found an entry with the highest matchID, get the stats from that match
    if highestMatchEntry then
        -- Only use history as a fallback. Live CR is the truth for spec-based ratings.
        if (categoryID ~= 7 and categoryID ~= 9) and (not currentCR or currentCR == 0) then
            currentCR = tonumber(highestMatchEntry.cr) or currentCR
        end
        local teamMMR = tonumber(highestMatchEntry.friendlyMMR)
        if teamMMR and teamMMR > 0 then
            if not currentMMR or currentMMR <= 0 then currentMMR = teamMMR end
        else
            if not currentMMR or currentMMR <= 0 then currentMMR = tonumber(highestMatchEntry.mmr) or currentMMR end
        end

        local isArena = (categoryID == 1 or categoryID == 2)

        if highestMatchEntry.playerStats then
            for _, stats in ipairs(highestMatchEntry.playerStats) do
                if stats.name == playerName then
                    local mmr = tonumber(stats.postmatchMMR)
                    local cr  = tonumber(stats.newrating)
                    -- Again: do not override a valid live CR/MMR.
                    if (not currentCR or currentCR == 0) and cr then currentCR = cr end
                    -- For SS/RBGB: ALWAYS prefer playerStats.postmatchMMR when available.
                    if (categoryID == 7 or categoryID == 9) and mmr and mmr > 0 then
                        currentMMR = mmr
                    elseif (not currentMMR or currentMMR <= 0) and mmr and mmr > 0 then
                        currentMMR = mmr
                    end
                    break
                end
            end
        end
        if isArena then
            local teamMMR2 = tonumber(highestMatchEntry.friendlyMMR)
            local curMMR   = tonumber(currentMMR)
            if teamMMR2 and teamMMR2 > 0 and (not curMMR or curMMR <= 0) then
                currentMMR = teamMMR2
            end
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
    
	-- Replace the legacy CR/MMR + helper text block with a tier badge panel.
	-- (We still keep currentCR/currentMMR logic above, because last-match data is most reliable.)
    if contentFrame.crLabel then contentFrame.crLabel:Hide() end
    if contentFrame.mmrLabel then contentFrame.mmrLabel:Hide() end
    if contentFrame.instructionLabel then contentFrame.instructionLabel:Hide() end

    local function LabelNum(label, num)
        return RSTATS:ColorText(label) .. "|cffffffff" .. tostring(num) .. "|r"
    end

    local function ReachCR(cr)
        return LabelNum("Reach: ", cr) .. " " .. RSTATS:ColorText("CR")
    end

    local function DropCR(cr)
        return LabelNum("Drop below: ", cr) .. " " .. RSTATS:ColorText("CR")
    end

    local function ReachAndWins(crReq, winsReq)
        -- Reach: 2400 CR and 25 Wins above 2400 CR
        return LabelNum("Reach: ", crReq) .. " " .. RSTATS:ColorText("CR")
            .. " " .. RSTATS:ColorText("and ")
            .. "|cffffffff" .. tostring(winsReq) .. "|r"
            .. " " .. RSTATS:ColorText("Wins above ")
            .. "|cffffffff" .. tostring(crReq) .. "|r"
            .. " " .. RSTATS:ColorText("CR")
    end

    local function ProgressLine(cur, max)
        return RSTATS:ColorText("Progress: ")
            .. "|cffffffff" .. tostring(cur) .. "|r"
            .. RSTATS:ColorText(" / ")
            .. "|cffffffff" .. tostring(max) .. "|r"
    end

    local function CountWinsAboveCR(bracketID, crReq, winsMode)
        local key = categoryMappings[bracketID]
        local tbl = key and Database[key]
        if type(tbl) ~= "table" then return 0 end

        crReq = tonumber(crReq) or 0
        local total = 0

        for _, e in ipairs(tbl) do
            local ecr = tonumber(e and e.cr) or 0
            if ecr >= crReq then
                if winsMode == "ss_rounds" then
                    -- Solo Shuffle: we store per-player rounds won as playerData.wins
                    local added = 0
                    if e.playerStats then
                        for _, ps in ipairs(e.playerStats) do
                            if ps and ps.name == playerName then
                                added = tonumber(ps.wins) or 0
                                break
                            end
                        end
                    end
                    if added <= 0 then
                        added = tonumber(e.roundsWon) or 0
                    end
                    total = total + added
                else
                    -- Other brackets: count match wins from friendlyWinLoss
                    local wl = e and e.friendlyWinLoss
                    if type(wl) == "string" and wl:find("W", 1, true) then
                        total = total + 1
                    end
                end
            end
        end

        return total
    end

    -- ------------------------------------------------------------------
    -- PvP Tier (Combatant -> Elite) MUST come from the API (same as filters).
    -- We use pvpTier from GetPersonalRatedInfo, then GetPvpTierInfo for name/icon/thresholds.
    -- ------------------------------------------------------------------
    local function GetApiTierInfo(bracketID)
        if not (C_PvP and C_PvP.GetPvpTierInfo) then return nil, nil, nil end
        local pvpTier = select(10, GetPersonalRatedInfo(bracketID))
        pvpTier = tonumber(pvpTier) or 0
        if pvpTier <= 0 then return nil, nil, nil end

        local cur = C_PvP.GetPvpTierInfo(pvpTier)
        if not cur then return nil, nil, nil end

        local down = (cur.descendTier and tonumber(cur.descendTier) and tonumber(cur.descendTier) > 0)
            and C_PvP.GetPvpTierInfo(cur.descendTier) or nil

        local up = (cur.ascendTier and tonumber(cur.ascendTier) and tonumber(cur.ascendTier) > 0)
            and C_PvP.GetPvpTierInfo(cur.ascendTier) or nil

        return cur, down, up
    end

    local function SetIcon(tex, path, tint)
        tex:SetTexture(path or "Interface\\Icons\\INV_Misc_QuestionMark")
        if tint and type(tint) == "table" then
            tex:SetVertexColor(tint[1] or 1, tint[2] or 1, tint[3] or 1)
        else
            tex:SetVertexColor(1, 1, 1)
        end
    end

    -- ------------------------------------------------------------------
    -- Bracket milestone "up" badge (Strategist / Legend / Glad / 3's Company / HotX / R1)
    -- Uses the same base-game icon paths + tints you already defined in Achiev.
    -- ------------------------------------------------------------------
    local function GetMilestoneForBracket(bracketID, cr)
        cr = tonumber(cr) or 0

        -- icon paths + tints copied from RatedStats_Achiev/achievements.lua
        local ICON_ELITEPLUS = "Interface\\PVPFrame\\Icons\\UI_RankedPvP_07_Small.blp"
        local ICON_3C        = "Interface\\Icons\\Achievement_Arena_3v3_7"
        local ICON_HERO_H    = "Interface\\PvPRankBadges\\PvPRankHorde.blp"
        local ICON_HERO_A    = "Interface\\PvPRankBadges\\PvPRankAlliance.blp"

        local TINT_STRAT = { 0.20, 1.00, 0.20 }
        local TINT_GLAD  = { 1.00, 0.35, 0.95 }
        local TINT_LEG   = { 1.00, 0.35, 0.20 }

        -- Only meaningful once you're at/above Elite (2400+). Caller gates display.

        if bracketID == 9 then
            local progStrat = CountWinsAboveCR(9, 2400, "match_wins")
            if progStrat < 25 then
                return { name="Strategist", icon=ICON_ELITEPLUS, tint=TINT_STRAT, reqCR=2400, reqWins=25, winsMode="match_wins" }
            end
            local progR1 = CountWinsAboveCR(9, 2400, "match_wins")
            if progR1 < 50 then
                return { name="Rank 1", icon=ICON_ELITEPLUS, tint=nil, reqCR=2400, reqWins=50, topText="Top 0.1% of Season", winsMode="match_wins" }
            end
            return nil
        end

        if bracketID == 7 then
            local progLeg = CountWinsAboveCR(7, 2400, "ss_rounds")
            if progLeg < 100 then
                return { name="Legend", icon=ICON_ELITEPLUS, tint=TINT_LEG, reqCR=2400, reqWins=100, winsMode="ss_rounds" }
            end
            local progR1 = CountWinsAboveCR(7, 2400, "ss_rounds")
            if progR1 < 50 then
                return { name="Rank 1", icon=ICON_ELITEPLUS, tint=nil, reqCR=2400, reqWins=50, topText="Top 0.1% of Season", winsMode="ss_rounds" }
            end
            return nil
        end

        if bracketID == 2 then
            local progGlad = CountWinsAboveCR(2, 2400, "match_wins")
            if progGlad < 50 then
                return { name="Gladiator", icon=ICON_ELITEPLUS, tint=TINT_GLAD, reqCR=2400, reqWins=50, winsMode="match_wins" }
            end
            if cr < 2700 then
                return { name="Three's Company", icon=ICON_3C, tint=nil, reqCR=2700 }
            end
            local progR1 = CountWinsAboveCR(2, 2700, "match_wins")
            if progR1 < 50 then
                return { name="Rank 1", icon=ICON_ELITEPLUS, tint=nil, reqCR=2700, reqWins=50, topText="Top 0.1% of Season", winsMode="match_wins" }
            end
            return nil
        end

        if bracketID == 4 then
            -- HotX: 2400 + X wins + Top 0.1%. Wins counted only at/above 2400.
            local faction = UnitFactionGroup("player")
            local icon = (faction == "Horde") and ICON_HERO_H or ICON_HERO_A
            local prog = CountWinsAboveCR(4, 2400, "match_wins")
            if prog < 50 then
                return { name="HotX", icon=icon, tint=nil, reqCR=2400, reqWins=50, topText="Top 0.1% of Season", winsMode="match_wins" }
            end
            return nil
        end

        return nil
    end

    -- Panel: 3 icons (down << current >> up). No extra icon row.
    local panel = contentFrame.rankPanel
    if not panel then
        panel = CreateFrame("Frame", nil, contentFrame)
        panel:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -6)
        panel:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", 0, -6)
        panel:SetHeight(96)
        contentFrame.rankPanel = panel

        panel.centerIcon = panel:CreateTexture(nil, "OVERLAY")
        panel.centerIcon:SetSize(58, 58)
        panel.centerIcon:SetPoint("TOP", panel, "TOP", 0, 0)

        panel.leftIcon = panel:CreateTexture(nil, "OVERLAY")
        panel.leftIcon:SetSize(42, 42)
        panel.leftIcon:SetPoint("RIGHT", panel.centerIcon, "LEFT", -54, -2)

        panel.rightIcon = panel:CreateTexture(nil, "OVERLAY")
        panel.rightIcon:SetSize(42, 42)
        panel.rightIcon:SetPoint("LEFT", panel.centerIcon, "RIGHT", 54, -2)

        panel.leftArrow = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        panel.leftArrow:SetFont(GetUnicodeSafeFont(), 18, "OUTLINE")
        panel.leftArrow:SetPoint("RIGHT", panel.centerIcon, "LEFT", -14, 6)
        panel.leftArrow:SetText(RSTATS:ColorText("<<"))

        panel.rightArrow = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        panel.rightArrow:SetFont(GetUnicodeSafeFont(), 18, "OUTLINE")
        panel.rightArrow:SetPoint("LEFT", panel.centerIcon, "RIGHT", 14, 6)
        panel.rightArrow:SetText(RSTATS:ColorText(">>"))

        panel.centerTierText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        panel.centerTierText:SetFont(GetUnicodeSafeFont(), 13, "OUTLINE")
        panel.centerTierText:SetPoint("TOP", panel.centerIcon, "BOTTOM", 0, -2)

        panel.centerCRMMR = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        panel.centerCRMMR:SetFont(GetUnicodeSafeFont(), 12, "OUTLINE")
        panel.centerCRMMR:SetPoint("TOP", panel.centerTierText, "BOTTOM", 0, -2)

        panel.leftTierText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        panel.leftTierText:SetFont(GetUnicodeSafeFont(), 12, "OUTLINE")
        panel.leftTierText:SetJustifyH("RIGHT")
        panel.leftTierText:SetPoint("TOPRIGHT", panel.leftIcon, "BOTTOMRIGHT", 0, -2)

        panel.leftReqText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        panel.leftReqText:SetFont(GetUnicodeSafeFont(), 11, "OUTLINE")
        panel.leftReqText:SetJustifyH("RIGHT")
        panel.leftReqText:SetPoint("TOPRIGHT", panel.leftTierText, "BOTTOMRIGHT", 0, -2)

        panel.rightTierText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        panel.rightTierText:SetFont(GetUnicodeSafeFont(), 12, "OUTLINE")
        panel.rightTierText:SetJustifyH("LEFT")
        panel.rightTierText:SetPoint("TOPLEFT", panel.rightIcon, "BOTTOMLEFT", 0, -2)

        panel.rightReqText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        panel.rightReqText:SetFont(GetUnicodeSafeFont(), 11, "OUTLINE")
        panel.rightReqText:SetJustifyH("LEFT")
        panel.rightReqText:SetPoint("TOPLEFT", panel.rightTierText, "BOTTOMLEFT", 0, -2)
    end

    -- Tier MUST come from API for THIS BRACKET (matches filters.lua behaviour)
    local curTier, downTier, upTier = GetApiTierInfo(categoryID)

    if curTier and curTier.tierIconID then
        SetIcon(panel.centerIcon, curTier.tierIconID, nil)
        panel.centerTierText:SetText(RSTATS:ColorText(curTier.name or ""))
    else
        SetIcon(panel.centerIcon, "Interface\\Icons\\INV_Misc_QuestionMark", nil)
        panel.centerTierText:SetText("")
    end

    panel.centerCRMMR:SetText(
        LabelNum("CR: ", currentCR) .. "   " .. LabelNum("MMR: ", currentMMR)
    )

    -- Left (down)
    if downTier and downTier.tierIconID and curTier and curTier.descendRating and tonumber(curTier.descendRating) and tonumber(curTier.descendRating) > 0 then
        panel.leftIcon:Show()
        panel.leftArrow:Show()
        panel.leftTierText:Show()
        panel.leftReqText:Show()

        SetIcon(panel.leftIcon, downTier.tierIconID, nil)
        panel.leftTierText:SetText(RSTATS:ColorText(downTier.name or ""))

        panel.leftReqText:SetText(DropCR(curTier.descendRating))
    else
        panel.leftIcon:Hide()
        panel.leftArrow:Hide()
        panel.leftTierText:Hide()
        panel.leftReqText:Hide()
    end

    -- Right (up): bracket milestone first; otherwise next PvP tier
    local isTopTier = (curTier and (not curTier.ascendTier or tonumber(curTier.ascendTier) == 0))
    local canShowMilestone = isTopTier and (tonumber(currentCR) or 0) >= 2400
    local milestone = canShowMilestone and GetMilestoneForBracket(categoryID, currentCR) or nil

    if milestone and milestone.icon and milestone.name then
        panel.rightIcon:Show()
        panel.rightArrow:Show()
        panel.rightTierText:Show()
        panel.rightReqText:Show()

        SetIcon(panel.rightIcon, milestone.icon, milestone.tint)
        panel.rightTierText:SetText(RSTATS:ColorText(milestone.name))

        local lines = {}

        -- CR-gated milestones (Strategist/Legend/Glad/R1/3's Company)
        if milestone.reqCR and tonumber(milestone.reqCR) and tonumber(milestone.reqCR) > 0 then
            if milestone.reqWins and tonumber(milestone.reqWins) and tonumber(milestone.reqWins) > 0 then
                local prog = CountWinsAboveCR(categoryID, milestone.reqCR, milestone.winsMode)
                lines[#lines + 1] = ReachAndWins(milestone.reqCR, milestone.reqWins)
                lines[#lines + 1] = ProgressLine(prog, milestone.reqWins)
                if milestone.topText then
                    lines[#lines + 1] = RSTATS:ColorText(milestone.topText)
                end
            else
                lines[#lines + 1] = ReachCR(milestone.reqCR)
            end

        -- Percent/wins-only milestone (Hero)
        elseif milestone.reqWins and tonumber(milestone.reqWins) and tonumber(milestone.reqWins) > 0 then
            local prog = CountWinsAboveCR(categoryID, 0, milestone.winsMode)
            lines[#lines + 1] = LabelNum("Wins: ", milestone.reqWins)
            if milestone.topText then
                lines[#lines + 1] = RSTATS:ColorText(milestone.topText)
            end
            lines[#lines + 1] = ProgressLine(prog, milestone.reqWins)
        end

        panel.rightReqText:SetText(table.concat(lines, "\n"))
    elseif upTier and upTier.tierIconID and curTier and curTier.ascendRating and tonumber(curTier.ascendRating) and tonumber(curTier.ascendRating) > 0 then
        panel.rightIcon:Show()
        panel.rightArrow:Show()
        panel.rightTierText:Show()
        panel.rightReqText:Show()

        SetIcon(panel.rightIcon, upTier.tierIconID, nil)
        panel.rightTierText:SetText(RSTATS:ColorText(upTier.name or ""))

        panel.rightReqText:SetText(ReachCR(curTier.ascendRating))
    else
        panel.rightIcon:Hide()
        panel.rightArrow:Hide()
        panel.rightTierText:Hide()
        panel.rightReqText:Hide()
    end

    return panel
end

----------------------------------
-- Config functions continued
----------------------------------

function Config:CreateMenu()
    if UIConfig then return UIConfig end

    local scrollFrames  = {}
    local scrollContents = {}
    local contentFrames  = {}
    
    -- forward declare so tab OnClick can force full mode for Summary
    local ApplyCompactState

    local parentWidth  = UIParent:GetWidth()
    local parentHeight = UIParent:GetHeight()

    UIConfig = CreateFrame("Frame", "RatedStatsConfig", UIParent, "PortraitFrameTemplate")
	UIPanelWindows["RatedStatsConfig"] = {
	area     = "center",    -- center of the screen
	pushable = 0,           -- don’t push other panels
	whileDead = true,       -- allow even when dead (optional)
	}
	-- …and flag it to close on ESC
	tinsert(UISpecialFrames, "RatedStatsConfig")
    UIConfig:SetSize(parentWidth * 0.9, parentHeight * 0.8)
    UIConfig:SetPoint("CENTER", UIParent, "CENTER", 0, 75)
    UIConfig:SetResizable(true)
    UIConfig:SetMovable(true)
    UIConfig:EnableMouse(true)
    UIConfig:RegisterForDrag("LeftButton")
    UIConfig:SetScript("OnDragStart", UIConfig.StartMoving)
    UIConfig:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    UIConfig:SetFrameStrata("HIGH")
    UIConfig:SetFrameLevel(1)
    UIConfig:SetClampedToScreen(true)
    UIConfig:SetTitle("Rated Stats")
	UIConfig.fullContentWidth = parentWidth * 0.9        -- <- same number you used for SetSize()
	
    -- Now change title to our addon colour
    if UIConfig.TitleText then
        UIConfig.TitleText:SetText(
            string.format("|cff%s%s|r", COLOR_HEX, "Rated Stats")
        )
	end

    -- Background
    local faction = UnitFactionGroup("player")
    local bgPath = (faction == "Alliance")
       and "Interface\\AddOns\\RatedStats\\images\\alliancebackground"
        or "Interface\\AddOns\\RatedStats\\images\\hordebackground"

    UIConfig.BG = UIConfig:CreateTexture(nil, "BACKGROUND")
	UIConfig.BG:SetDrawLayer("BACKGROUND", -1)
	UIConfig.BG:SetPoint("TOPLEFT",     UIConfig, "TOPLEFT",     8, -30)
	UIConfig.BG:SetPoint("BOTTOMRIGHT", UIConfig, "BOTTOMRIGHT", -8,   8)
    UIConfig.BG:SetTexture(bgPath)
    UIConfig.BG:SetAlpha(0.4)

    -- Portrait
    local portrait = UIConfig.PortraitContainer:CreateTexture(nil, "ARTWORK")
    portrait:SetTexture("Interface\\AddOns\\RatedStats\\RatedStats")
    portrait:SetSize(50, 50)
	portrait:SetPoint("CENTER", UIConfig.PortraitContainer, "BOTTOMRIGHT", 23, -23)
    portrait:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    portrait:SetDrawLayer("ARTWORK", -1)
    UIConfig.portrait = portrait

    -- Example extra UI
    Config:CreateSearchBox(UIConfig)
    Config:CreateFilterMenu(UIConfig)

	local statsBar = CreateFrame("Frame", "MatchStatsBar", UIConfig)
	statsBar:SetSize(800, 24)
	statsBar:SetPoint("BOTTOMLEFT", UIConfig, "BOTTOMLEFT", 16, 15)
	statsBar:SetPoint("BOTTOMRIGHT", UIConfig, "BOTTOMRIGHT", -16, 15)
	
	RSTATS.StatsBar = {
		summaryLines = {}
	}
	RSTATS.Dropdowns = {}

	-- Add this after contentFrame or other existing children are positioned
	local timeFilterOptions = {
		{ text = "Today", value = "today" },
		{ text = "Yesterday", value = "yesterday" },
		{ text = "This Week", value = "thisWeek" },
		{ text = "This Month", value = "thisMonth" },
		{ text = "This Season", value = "thisSeason" }
	}

	-- Also allow explicit season lookups (DF S4 / TWW S1 / etc.)
	for _, season in ipairs(RatedStatsSeasons or {}) do
		table.insert(timeFilterOptions, { text = season.label, value = season.label })
	end

    -- Create 5 frames + scrollFrames for the match-history tabs
    for i = 1, 5 do
        local frame = CreateFrame("Frame", "TabFrame", UIConfig)
        frame:SetPoint("TOPLEFT", UIConfig, "TOPLEFT", 20, -100)
        frame:SetPoint("BOTTOMRIGHT", UIConfig, "BOTTOMRIGHT", -20, 40)
		frame:SetClipsChildren(true)
        frame:Hide()
        contentFrames[i] = frame

		-- Create scroll frame inside the content frame
		local scrollFrame = CreateFrame("ScrollFrame", "RatedStatsScrollFrame"..i, frame, "UIPanelScrollFrameTemplate")
		-- Anchor the scrollFrame statically below the header and give it a fixed height
---		scrollFrame:SetPoint("TOPLEFT", scrollContent.header, "BOTTOMLEFT", -5, -5)
		scrollFrame:ClearAllPoints()
		scrollFrame:SetPoint("TOPLEFT",     frame, "TOPLEFT",     20, -100)
		scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20,  40)
		scrollFrame:SetClipsChildren(true)
		scrollFrame:EnableMouseWheel(true)

        scrollFrame:SetScript("OnMouseWheel", function(self,delta)
            local scrollbar = self.ScrollBar or (self:GetName().."ScrollBar")
            if not scrollbar then return end
            local step = scrollbar:GetValueStep() or 20
            if delta < 0 then
                scrollbar:SetValue(scrollbar:GetValue() + step)
            else
                scrollbar:SetValue(scrollbar:GetValue() - step)
            end
        end)

        local content = CreateFrame("Frame", "RatedStatsScrollChild"..i, scrollFrame)
		content:SetPoint("TOPLEFT",     scrollFrame, "TOPLEFT",     0,  0)  -- only anchor to top left for mouse wheel scrolling
--		content:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 0,  0)
--		if UIConfig.isCompact then
--			content:SetWidth(UIConfig.fullContentWidth * 0.5, 0) -- optional if overridden later
--			print("scrollFrame: ", scrollFrame:GetWidth())
--		else
--			content:SetWidth(UIConfig.fullContentWidth, 0)
--		end
		scrollFrame:SetScrollChild(content)

		scrollFrame:SetScript("OnSizeChanged", function(self, width, height)
			content:SetWidth(width)
		end)

        local scrollbar = scrollFrame.ScrollBar
        if scrollbar then
			scrollbar:ClearAllPoints()
            scrollbar:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", 0, -20)
            scrollbar:SetPoint("BOTTOMRIGHT",scrollFrame,"BOTTOMRIGHT",-2,16)
            scrollbar:Show()
			scrollbar:EnableMouseWheel(true)
        end

		local rowsAnchor = CreateFrame("Frame", "RatedStatsRowsAnchor"..i, content)
		rowsAnchor:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
		if UIConfig.isCompact then
			rowsAnchor:SetSize(content:GetWidth() * 0.5, 1)  -- Height is not important
		else
			rowsAnchor:SetSize(content:GetWidth() * 0.96, 1)  -- Height is not important
		end
		content.rowsAnchor = rowsAnchor
		
		-- Create a per-tab dropdown
		local dropdown = CreateFrame("Frame", "RatedStatsTimeFilterDropdown"..i, frame, "UIDropDownMenuTemplate")
		dropdown:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
		UIDropDownMenu_SetWidth(dropdown, 120)
		UIDropDownMenu_SetText(dropdown, "Today")
		
		RSTATS.Dropdowns[i] = dropdown  -- Store reference
		content.dropdown = dropdown
		
		UIDropDownMenu_Initialize(dropdown, function(self, level, menuList)
			local info
			local currentSelected = UIDropDownMenu_GetText(dropdown)
		
			for _, option in ipairs(timeFilterOptions) do
				info = UIDropDownMenu_CreateInfo()
				info.text = option.text
				info.checked = (option.text == currentSelected) -- ✅ Only one shows gold
				info.isNotRadio = false                          -- ✅ Makes it look like a radio button (gold circle)
				info.func = function()
					UIDropDownMenu_SetSelectedName(dropdown, option.text)
					UIDropDownMenu_SetText(dropdown, option.text)
					RSTATS:UpdateStatsView(option.value, i)
				end
				UIDropDownMenu_AddButton(info)
			end
		end)
		
		-- Summary line anchored to the tab's dropdown
		local summaryLine = statsBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		summaryLine:SetPoint("LEFT", dropdown, "RIGHT", 12, 0)
		summaryLine:SetPoint("RIGHT", statsBar, "RIGHT", -8, 1)
		summaryLine:SetJustifyH("CENTER")
		
		RSTATS.StatsBar.summaryLines[i] = summaryLine
        scrollFrames[i]   = scrollFrame
        scrollContents[i] = content
    end

	-- Summary tab (Option B) content frame: no scroll rows, dashboard only.
	-- Keep it as a normal contentFrame so the tab switching stays simple.
	local summaryFrame = CreateFrame("Frame", "RatedStatsSummaryTab", UIConfig)
	summaryFrame:SetPoint("TOPLEFT", UIConfig, "TOPLEFT", 20, -100)
	summaryFrame:SetPoint("BOTTOMRIGHT", UIConfig, "BOTTOMRIGHT", -20, 40)
	summaryFrame:SetClipsChildren(true)
	summaryFrame:Hide()
	contentFrames[6] = summaryFrame

     -- expose frames before any history is built
    RSTATS.UIConfig       = UIConfig
    RSTATS.ContentFrames  = contentFrames
    RSTATS.ScrollFrames   = scrollFrames
    RSTATS.ScrollContents = scrollContents
	
	-- Build the Summary dashboard UI (in a new file) once UIConfig exists.
	if RSTATS.Summary and RSTATS.Summary.Create then
		RSTATS.Summary:Create(summaryFrame)
	end

	local selectedTimeFilter = "today"
	
	local Filters = RatedStatsFilters  -- Already exposed globally
	local Stats = RSTATS_STATS         -- Our new global from stats.lua
	
	function RSTATS:UpdateStatsView(filterType, tabID)
		tabID = tabID or PanelTemplates_GetSelectedTab(RSTATS.UIConfig)

		-- Tab 6 is Summary (dashboard only). It has no match rows/stat bar filtering.
		if tabID == 6 then
			return
		end

        local allMatches
		if self.GetHistoryForTab then
			allMatches = self:GetHistoryForTab(tabID) or {}
		else
			-- Fallback (should only happen if spec-history helper was not loaded)
			allMatches = ({
				[1] = Database.SoloShuffleHistory,
				[2] = Database.v2History,
				[3] = Database.v3History,
				[4] = Database.RBGHistory,
				[5] = Database.SoloRBGHistory,
			})[tabID] or {}
		end
		-- Apply current tab filters
		local filtered = {}
		for _, match in ipairs(allMatches) do
			if ApplyFilters(match) then
				table.insert(filtered, match)
			end
		end
	
		-- Apply time range filter
		local timeFiltered = FilterMatchesByTimeRange(filtered, filterType)
	
		-- Get summary stats
		-- Bracket ID mapping for PvP API
		local bracketIDMap = {
			[1] = 7, -- Solo Shuffle
			[2] = 1, -- 2v2
			[3] = 2, -- 3v3
			[4] = 4, -- RBG
			[5] = 9, -- Solo RBG / Wargame BG
		}
		
		local bracketID = bracketIDMap[tabID] or 1
		local summary = Stats.CalculateSummary(timeFiltered, allMatches, bracketID)
		
		-- Inline icon for tier
		local function GetIconMarkup(fileID)
			return fileID and string.format("|T%d:16|t", fileID) or "-"
		end
				
		local text = string.format(
			"%s %d   %s %d   %s %d/%d/%d (%d%%)         %s %s %s         %s %s   %s %s",
			c("CR +/-:"), summary.crDelta,
			c("MMR +/-:"), summary.mmrDelta,
			c("W/L/D:"), summary.win, summary.loss, summary.draw, summary.winrate,
			c("You are a"), GetIconMarkup(summary.currentIconID),
			c("fighting") .. " " .. GetIconMarkup(summary.enemyIconID) .. c(" 's"),
			c("Best Map:"), summary.bestMap or "-",
			c("Worst Map:"), summary.worstMap or "-"
		)
		
		-- Hide all summary lines first
		for i, line in ipairs(RSTATS.StatsBar.summaryLines) do
			if line then line:Hide() end
		end
		
		-- Show and update the one for this tab
		local summaryLine = RSTATS.StatsBar.summaryLines[tabID]
		if summaryLine then
			summaryLine:SetText(text)
			summaryLine:Show()
		
			summaryLine:EnableMouse(true)
			summaryLine:SetScript("OnEnter", function()
				GameTooltip:SetOwner(summaryLine, "ANCHOR_TOPRIGHT", -450, 0)
				GameTooltip:ClearLines()
		
				if summary.currentBracket then
					GameTooltip:AddDoubleLine("Your Bracket:", summary.currentBracket, 1, 1, 1, 1, 0.82, 0)
				end
				if summary.enemyBracket then
					GameTooltip:AddDoubleLine("Enemy Bracket:", summary.enemyBracket, 1, 1, 1, 0.9, 0.2, 0.2)
				end
		
				GameTooltip:Show()
			end)
		
			summaryLine:SetScript("OnLeave", function()
				GameTooltip:Hide()
			end)
		end
	end
	
	-- FontString helpers
	local function AddStat(label, anchor, xOff)
		local text = statsBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetPoint("LEFT", anchor, "RIGHT", xOff or 20, 0)
		text:SetText(label)
		return text
	end
	
	C_Timer.After(0.05, function()
		local dropdown = RSTATS.Dropdowns[DEFAULT_TAB_ID]
		local selected = dropdown and UIDropDownMenu_GetText(dropdown) or "Today"
		local filterKey = selected:lower():gsub(" ", "") or "today"
	
		FilterAndSearchMatches("")
		RSTATS:UpdateStatsView(filterKey, DEFAULT_TAB_ID)
	end)

    -- Logic to toggle state
    UIConfig.ActiveTeamView = 1  -- Default view
    local function UpdateArrowState()
        if UIConfig.ActiveTeamView == 1 then
            UIConfig.TeamLeftButton:Disable()
            UIConfig.TeamRightButton:Enable()
        else
            UIConfig.TeamRightButton:Disable()
            UIConfig.TeamLeftButton:Enable()
        end
    end
	
	local function RefreshAllNestedTables(scrollFrame)
		local function walk(f)
			if f.UpdateTeamView then f:UpdateTeamView() end
			for i = 1, f:GetNumChildren() do
				walk(select(i, f:GetChildren()))
			end
		end
		local root = scrollFrame and scrollFrame:GetScrollChild()
		if root then walk(root) end
	end

	function UpdateCompactHeaders(tabID)
	local content     = RSTATS.ScrollContents[tabID]
	if not content or not content.headerFrame then return end
	
	local off         = content.columnOffsets
	local splitIdx    = content.splitIndex
	local hf          = content.headerFrame
	local headerTexts = content.headerTexts
	
	-- 1) compute of the *frame* width once
	local shift = content:GetWidth()
	
	for i, h in ipairs(headerTexts) do
		h:ClearAllPoints()
	
		if UIConfig.isCompact then
			if UIConfig.ActiveTeamView == 1 then
				-- friendly page: no shift
				h:SetPoint("TOPLEFT", hf, "TOPLEFT", off[i], 0)
				h:SetShown(i <= splitIdx)
			else
				-- enemy page: subtract a fixed shift
				h:SetPoint("TOPLEFT", hf, "TOPLEFT", off[i] - shift, 0)
				h:SetShown(i > splitIdx)
			end
			else
			-- full view: all headers, original offsets
			h:SetPoint("TOPLEFT", hf, "TOPLEFT", off[i], 0)
			h:Show()
			end
		end
	end

    -- Tab buttons
    local tabNames = { "Solo Shuffle", "2v2", "3v3", "RBG", "Solo RBG", "Summary" }
    local tabs = {}
    for i, name in ipairs(tabNames) do
        local tab = CreateFrame("Button","RatedStatsTab"..i,UIConfig,"PanelTabButtonTemplate")
        tab:SetID(i)
        tab:SetText(name)
        PanelTemplates_TabResize(tab,0)

        if i == 1 then
            tab:SetPoint("TOPLEFT", UIConfig, "BOTTOMLEFT", 10, 2)
        elseif i == 6 then
			-- Summary sits far-right, outside the frame (matches your screenshot)
			tab:SetPoint("TOPRIGHT", UIConfig, "BOTTOMRIGHT", -10, 2)
        else
            tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", -8, 0)
        end

        -- OnClick just shows/hides the frames
        tab:SetScript("OnClick", function(self)
			local tabID = self:GetID()
			PanelTemplates_SetTab(UIConfig, tabID)
		
			for j, f in ipairs(contentFrames) do
			f:SetShown(j == tabID)
			end
			
			-- Summary tab hides search/filters + bottom stats bar.
			local isSummary = (tabID == 6)
			if UIConfig.searchBox then UIConfig.searchBox:SetShown(not isSummary) end
			if UIConfig.filterButton then UIConfig.filterButton:SetShown(not isSummary) end
			if UIConfig.clearFilterButton then UIConfig.clearFilterButton:SetShown(not isSummary) end
			if statsBar then statsBar:SetShown(not isSummary) end

			-- Summary has no friendly/enemy paging.
			if UIConfig.TeamLeftButton then UIConfig.TeamLeftButton:SetShown(UIConfig.isCompact and not isSummary) end
			if UIConfig.TeamRightButton then UIConfig.TeamRightButton:SetShown(UIConfig.isCompact and not isSummary) end

            -- Summary must always be full mode: force compact OFF when switching to Summary.
            if isSummary and UIConfig.isCompact and ApplyCompactState then
                ApplyCompactState(false)
            end

            -- Summary has no compact button: hide it and shift Settings right.
            if isSummary then
                if UIConfig.ToggleViewButton then UIConfig.ToggleViewButton:Hide() end
                if UIConfig.SettingsButton then
                    UIConfig.SettingsButton:ClearAllPoints()
                    UIConfig.SettingsButton:SetPoint("RIGHT", UIConfig.CloseButton, "LEFT", 0, 0)
                end
            else
                -- Match tabs: show compact button and keep Settings left of it.
                if UIConfig.ToggleViewButton then UIConfig.ToggleViewButton:Show() end
                if UIConfig.SettingsButton and UIConfig.ToggleViewButton then
                    UIConfig.SettingsButton:ClearAllPoints()
                    UIConfig.SettingsButton:SetPoint("RIGHT", UIConfig.ToggleViewButton, "LEFT", 0, 0)
                end
            end

			-- always go back to page 1 on a brand-new tab
			UIConfig.ActiveTeamView = 1
			UpdateArrowState()
		
			ACTIVE_TAB_ID = tabID
			
			-- Summary refresh is separate (no rows, no filtering pass).
			if isSummary then
				if RSTATS.Summary and RSTATS.Summary.frame then
					RSTATS.Summary.frame:Show()
				end
				if RSTATS.Summary and RSTATS.Summary.Refresh then
					RSTATS.Summary:Refresh()
				end
				return
			end

			-- ✅ Adjust horizontal scroll to match current team view
			local scrollFrame = RSTATS.ScrollFrames[tabID]
			if UIConfig.isCompact then
				local pageWidth = scrollFrame:GetWidth()       -- ← width of the visible pane
				scrollFrame:SetHorizontalScroll(
					UIConfig.ActiveTeamView == 2 and pageWidth or 0)
			else
				scrollFrame:SetHorizontalScroll(0)             -- full view
			end

			UpdateArrowState()
			
			local dropdown = RSTATS.Dropdowns[tabID]
			local selected = dropdown and UIDropDownMenu_GetText(dropdown) or "Today"
			local filterKey = selected:lower():gsub(" ", "") or "today"
		
			-- 🧹 Clear old stuff
			local content = RSTATS.ScrollContents[tabID]
			if content.headerFrame then
				local fullWidth = content:GetWidth()
				content.headerFrame:SetWidth(fullWidth * 0.98)
			end

			ClearStaleMatchFrames(content)
		
			-- ✅ Refresh tab view immediately
			FilterAndSearchMatches(RatedStatsSearchBox and RatedStatsSearchBox:GetText() or "")
			RSTATS:UpdateStatsView(filterKey, tabID)
			
			-- ensure the ScrollFrame is at the correct pane in compact
			local sf = RSTATS.ScrollFrames[tabID]
			if UIConfig.isCompact then sf:SetHorizontalScroll(0) end
			
			UpdateCompactHeaders(tabID)
		end)

        tab:Show()
        tabs[i] = tab
    end
    PanelTemplates_SetNumTabs(UIConfig, #tabs)
    PanelTemplates_SetTab(UIConfig, 6)
    contentFrames[6]:Show()

    -- A local function that calls your revised DisplayHistory (shown below)
    local function RefreshDisplay()
        -- For each bracket
        local mmrLabel1 = DisplayCurrentCRMMR(contentFrames[1],7)
        local headers1, frames1 = RSTATS:DisplayHistory(scrollContents[1], RSTATS:GetHistoryForTab(1), mmrLabel1, 1)
        AdjustContentHeight(scrollContents[1])   -- simplified call

        local mmrLabel2 = DisplayCurrentCRMMR(contentFrames[2],1)
        local headers2, frames2 = RSTATS:DisplayHistory(scrollContents[2], Database.v2History, mmrLabel2, 2)
        AdjustContentHeight(scrollContents[2])

        local mmrLabel3 = DisplayCurrentCRMMR(contentFrames[3],2)
        local headers3, frames3 = RSTATS:DisplayHistory(scrollContents[3], Database.v3History, mmrLabel3, 3)
        AdjustContentHeight(scrollContents[3])

        local mmrLabel4 = DisplayCurrentCRMMR(contentFrames[4],4)
        local headers4, frames4 = RSTATS:DisplayHistory(scrollContents[4], Database.RBGHistory, mmrLabel4, 4)
        AdjustContentHeight(scrollContents[4])

        local mmrLabel5 = DisplayCurrentCRMMR(contentFrames[5],9)
        local headers5, frames5 = RSTATS:DisplayHistory(scrollContents[5], RSTATS:GetHistoryForTab(5), mmrLabel5, 5)
        AdjustContentHeight(scrollContents[5])

    end

    -- Optional ToggleViewButton
    UIConfig.ToggleViewButton = CreateFrame("Button","FrameCloseButton",UIConfig)
    UIConfig.ToggleViewButton:SetSize(24,24)
    UIConfig.ToggleViewButton:SetPoint("RIGHT",UIConfig.CloseButton,"LEFT",0,0)
    UIConfig.ToggleViewButton:SetFrameStrata("DIALOG")
    UIConfig.ToggleViewButton:SetFrameLevel(UIConfig.CloseButton:GetFrameLevel())
    UIConfig.ToggleViewButton:SetNormalAtlas("RedButton-Condense")
    UIConfig.ToggleViewButton:SetPushedAtlas("RedButton-Condense-Pressed")
    UIConfig.ToggleViewButton:SetDisabledAtlas("RedButton-Condense-Disabled")
    UIConfig.ToggleViewButton:SetHighlightAtlas("RedButton-Highlight")

    local tex = UIConfig.ToggleViewButton:GetNormalTexture()
    if tex then
        tex:SetDrawLayer("OVERLAY",7)
    end
	
    -- Settings button (matches the red button style)
    UIConfig.SettingsButton = CreateFrame("Button", "RatedStatsSettingsButton", UIConfig)
    UIConfig.SettingsButton:SetSize(24, 24)
    UIConfig.SettingsButton:SetPoint("RIGHT", UIConfig.ToggleViewButton, "LEFT", 0, 0)
    UIConfig.SettingsButton:SetFrameStrata("DIALOG")
    UIConfig.SettingsButton:SetFrameLevel(UIConfig.CloseButton:GetFrameLevel())
    UIConfig.SettingsButton:SetHighlightAtlas("RedButton-Highlight", "ADD")

    -- Base red button (uses the same atlas family as Close/Condense)
    UIConfig.SettingsButton.BG = UIConfig.SettingsButton:CreateTexture(nil, "ARTWORK")
    UIConfig.SettingsButton.BG:SetAllPoints()
    UIConfig.SettingsButton.BG:SetAtlas("RedButton-Exit")

    -- Cover the baked-in "X" so we can place a gear instead
    UIConfig.SettingsButton.Cover = UIConfig.SettingsButton:CreateTexture(nil, "OVERLAY")
    UIConfig.SettingsButton.Cover:SetPoint("TOPLEFT", 4, -4)
    UIConfig.SettingsButton.Cover:SetPoint("BOTTOMRIGHT", -4, 4)
    UIConfig.SettingsButton.Cover:SetColorTexture(0.33, 0.06, 0.06, 1)

    -- Gear icon
    UIConfig.SettingsButton.Icon = UIConfig.SettingsButton:CreateTexture(nil, "OVERLAY")
    UIConfig.SettingsButton.Icon:SetPoint("CENTER", 0, 0)
    UIConfig.SettingsButton.Icon:SetAtlas("GM-icon-settings", false)
    UIConfig.SettingsButton.Icon:SetSize(24, 24)
    UIConfig.SettingsButton.Icon:SetTexCoord(0.10, 0.90, 0.10, 0.90)
    UIConfig.SettingsButton.Icon:SetVertexColor(1, 0.82, 0.2, 1) -- match the yellow-ish button glyphs

    UIConfig.SettingsButton:SetScript("OnMouseDown", function(self)
        if self.BG then self.BG:SetAtlas("RedButton-exit-pressed") end
        if self.Icon then self.Icon:SetPoint("CENTER", 1, -1) end
    end)
    UIConfig.SettingsButton:SetScript("OnMouseUp", function(self)
        if self.BG then self.BG:SetAtlas("RedButton-Exit") end
        if self.Icon then self.Icon:SetPoint("CENTER", 0, 0) end
    end)
    UIConfig.SettingsButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Settings", 1, 1, 1)
        GameTooltip:AddLine("Open Rated Stats settings.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    UIConfig.SettingsButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    UIConfig.SettingsButton:SetScript("OnClick", function()
        if RSTATS and RSTATS.OpenSettings then
            RSTATS:OpenSettings()
        end
    end)

    UIConfig.ToggleViewButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
        GameTooltip:SetText("Toggle View",1,1,1)
        GameTooltip:AddLine("Switch between full and compact layout.", 0.8,0.8,0.8)
        GameTooltip:Show()
    end)
    UIConfig.ToggleViewButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Centralized compact apply so Summary can force full mode cleanly.
    ApplyCompactState = function(enabled)
        UIConfig.isCompact = enabled and true or false
        if UIConfig.isCompact then
            UIConfig:SetWidth(parentWidth * 0.5)
            UIConfig.ToggleViewButton:SetNormalAtlas("RedButton-Expand")
		    UIConfig.TeamLeftButton:Show()
			UIConfig.TeamRightButton:Show()
        else
            UIConfig:SetWidth(parentWidth * 0.9)
            UIConfig.ToggleViewButton:SetNormalAtlas("RedButton-Condense")
			UIConfig.TeamLeftButton:Hide()
			UIConfig.TeamRightButton:Hide()
			UIConfig.ActiveTeamView = 1
            local tabID = ACTIVE_TAB_ID or UIConfig.selectedTab
            local sf = RSTATS.ScrollFrames and tabID and RSTATS.ScrollFrames[tabID]
            if sf and sf.SetHorizontalScroll then
                sf:SetHorizontalScroll(0)
            end
			UpdateArrowState()  -- This ensures arrow buttons visually reflect current team view
        end
        for _, f in ipairs(contentFrames) do
            f:SetWidth(UIConfig:GetWidth()-40)
        end
        for _, c in ipairs(scrollContents) do
            c:SetWidth(UIConfig.fullContentWidth * 2)                  -- this controls the width of the nested table row in compact

			-- 🔧 keep its rowsAnchor in sync –
			--     that’s what all NestedTables are parented to
			if c.rowsAnchor then
				c.rowsAnchor:SetWidth(c:GetWidth())
			end
			
			----------------------------------------------------------------
			--  🔧  NEW: shrink/grow every existing row + its nested table  -
			----------------------------------------------------------------
			if c.matchFrames then
				local newRowW   = c:GetWidth()                     -- row width
				local newTableW = newRowW				-- both teams
				-- resize nested tables to full-UI width
				local fullTableW = UIConfig.fullContentWidth
				for _, row in ipairs(c.matchFrames) do
					if row.nestedTable then
						row.nestedTable:SetWidth(fullTableW)
						row.nestedTable:UpdateTeamView()
					end
				end
			end
        end
		
		----------------------------------------------------------
		--  NEW: keep every scroll pane in step with the window  --
		----------------------------------------------------------
		for i, sf in ipairs(RSTATS.ScrollFrames) do
			local w = RSTATS.ContentFrames[i]:GetWidth() - 8   -- same margin you used before
			sf:SetWidth(w)
	
			-- keep its scrollbar snug
			local bar = sf.ScrollBar
			if bar then
				bar:ClearAllPoints()
				bar:SetPoint("TOPRIGHT",  sf, "TOPRIGHT", 0, -20)
				bar:SetPoint("BOTTOMRIGHT",sf,"BOTTOMRIGHT",-2,16)
			end
		end
		----------------------------------------------------------
	
		RefreshAllNestedTables(RSTATS.ScrollFrames[ACTIVE_TAB_ID])
		
		-- Resize header frame to match new width
		local activeContent = RSTATS.ScrollContents[ACTIVE_TAB_ID]
		local header = activeContent and activeContent.headerFrame
		if header then
			local frameWidth = RSTATS.ContentFrames[ACTIVE_TAB_ID]:GetWidth()
			header:SetWidth(frameWidth - 20)
		end
		-- Also update the most recent nested table’s width
		-- Refresh every nested table in the now-active scrollFrame
		RefreshAllNestedTables(RSTATS.ScrollFrames[ACTIVE_TAB_ID])
		UpdateCompactHeaders(ACTIVE_TAB_ID)
    end

    UIConfig.ToggleViewButton:SetScript("OnClick", function()
        -- Compact is not allowed on Summary.
        local tabID = PanelTemplates_GetSelectedTab(UIConfig) or ACTIVE_TAB_ID or 1
        if tabID == 6 then return end
        ApplyCompactState(not UIConfig.isCompact)
    end)
	
    -- Small Arrow Buttons for Team View (like Spellbook arrows)
    local arrowSize = 24
    UIConfig.TeamLeftButton = CreateFrame("Button", "TeamLeftButton", UIConfig, "UIPanelButtonTemplate")
    UIConfig.TeamLeftButton:SetSize(arrowSize, arrowSize)
    UIConfig.TeamLeftButton:SetPoint("BOTTOMRIGHT", UIConfig, "BOTTOMRIGHT", -48, 12)
    UIConfig.TeamLeftButton:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    UIConfig.TeamLeftButton:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
    UIConfig.TeamLeftButton:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled")
    UIConfig.TeamLeftButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    UIConfig.TeamLeftButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 1)
        GameTooltip:SetText("Your Team", 1, 1, 1)
        GameTooltip:Show()
    end)
    UIConfig.TeamLeftButton:SetScript("OnLeave", GameTooltip_Hide)

    UIConfig.TeamRightButton = CreateFrame("Button", "TeamRightButton", UIConfig, "UIPanelButtonTemplate")
    UIConfig.TeamRightButton:SetSize(arrowSize, arrowSize)
    UIConfig.TeamRightButton:SetPoint("BOTTOMRIGHT", UIConfig, "BOTTOMRIGHT", -20, 12)
    UIConfig.TeamRightButton:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    UIConfig.TeamRightButton:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    UIConfig.TeamRightButton:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled")
    UIConfig.TeamRightButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    UIConfig.TeamRightButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 1)
        GameTooltip:SetText("Enemy Team", 1, 1, 1)
        GameTooltip:Show()
    end)
    UIConfig.TeamRightButton:SetScript("OnLeave", GameTooltip_Hide)

	UIConfig.TeamLeftButton:SetScript("OnClick", function()
		local scrollFrame = RSTATS.ScrollFrames[ACTIVE_TAB_ID]
		scrollFrame:SetHorizontalScroll(0)         -- friendly half
		UIConfig.ActiveTeamView = 1
		UpdateArrowState()
		RSTATS:UpdateStatsView(selectedTimeFilter, ACTIVE_TAB_ID)
		RefreshAllNestedTables(scrollFrame)
		UpdateCompactHeaders(ACTIVE_TAB_ID)
	end)
		
	UIConfig.TeamRightButton:SetScript("OnClick", function()
		local scrollFrame = RSTATS.ScrollFrames[ACTIVE_TAB_ID]
		local pageWidth = scrollFrame:GetWidth()  -- one “pane” right
		scrollFrame:SetHorizontalScroll(pageWidth) -- enemy half
		UIConfig.ActiveTeamView = 2
		UpdateArrowState()
		RSTATS:UpdateStatsView(selectedTimeFilter, ACTIVE_TAB_ID)
		RefreshAllNestedTables(scrollFrame)
		UpdateCompactHeaders(ACTIVE_TAB_ID)
	end)

    UpdateArrowState()
	
	-- Show/hide arrows based on view
	if UIConfig.isCompact then
		UIConfig.TeamLeftButton:Show()
		UIConfig.TeamRightButton:Show()
	else
		UIConfig.TeamLeftButton:Hide()
		UIConfig.TeamRightButton:Hide()
	end
	
	-- Build all tabs once at startup
	RefreshDisplay()
    UIConfig:Hide()
	
	-- In Config:CreateMenu, after all frames and tabs are set up:

	local DEFAULT_TAB_ID = 6
	for i = 1, 5 do
		local frame = contentFrames[i]
		local content = scrollContents[i]
	
		if frame and content then
			frame:SetScript("OnShow", function()
				if not content._initialized then
					content._initialized = true
					C_Timer.After(0.05, function()
						FilterAndSearchMatches(RatedStatsSearchBox and RatedStatsSearchBox:GetText() or "")
					end)
				end
			end)
		end
	end
	
	PanelTemplates_SetTab(UIConfig, DEFAULT_TAB_ID)
	contentFrames[DEFAULT_TAB_ID]:Show()
	ACTIVE_TAB_ID = DEFAULT_TAB_ID
	
	-- Default view is Summary: hide match controls and refresh the dashboard.
	if UIConfig.searchBox then UIConfig.searchBox:Hide() end
	if UIConfig.filterButton then UIConfig.filterButton:Hide() end
	if UIConfig.clearFilterButton then UIConfig.clearFilterButton:Hide() end
	if statsBar then statsBar:Hide() end
	if UIConfig.TeamLeftButton then UIConfig.TeamLeftButton:Hide() end
	if UIConfig.TeamRightButton then UIConfig.TeamRightButton:Hide() end

	C_Timer.After(0.05, function()
		local tabID = PanelTemplates_GetSelectedTab(RSTATS.UIConfig) or 1
		if tabID > 5 then return end -- Summary tab: do not run row filtering / stats bar updates

		local dropdown = RSTATS.Dropdowns[tabID]
		local selected = dropdown and UIDropDownMenu_GetText(dropdown) or "Today"
		local filterKey = selected:lower():gsub(" ", "") or "today"

		FilterAndSearchMatches(RatedStatsSearchBox and RatedStatsSearchBox:GetText() or "")
		RSTATS:UpdateStatsView(filterKey, tabID)
	end)

    -- ↪ When the main window closes, also tear down the copy‐name popup if open
    UIConfig:HookScript("OnHide", function(self)
      local cf = _G["CreateCopyNameFrame"]
      if cf and cf:IsShown() then
        HideUIPanel(cf)
      end
    end)

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

local function OnSoloShuffleStateChanged(event, ...)
    if not (C_PvP.IsRatedSoloShuffle and C_PvP.IsRatedSoloShuffle()) then
        return
    end

    -- One latch per round; multiple state changes are normal.
    if playerDeathSeen then
        return
    end

    -- Freeze our allies for THIS round, but only when we have the full set.
    -- In Solo Shuffle, player + party1 + party2 should be 3 GUIDs.
    local allies = {}

    local g = UnitGUID("player")
    if g then allies[g] = true end

    g = UnitGUID("party1")
    if g then allies[g] = true end

    g = UnitGUID("party2")
    if g then allies[g] = true end

    local count = 0
    for _ in pairs(allies) do
        count = count + 1
    end

    -- Not ready yet: do NOT latch. Wait for the next state change event.
    if count < 3 then
        return
    end

    -- Snapshot allies' Killing Blows at the moment the round ends.
    -- We will compare this snapshot against the next PVP_MATCH_ACTIVE scoreboard to decide win/loss.
    local kbSnapshot = {}
    for i = 1, GetNumBattlefieldScores() do
        local scoreInfo = C_PvP.GetScoreInfo(i)
        if scoreInfo and scoreInfo.guid and allies[scoreInfo.guid] then
            kbSnapshot[scoreInfo.guid] = tonumber(scoreInfo.killingBlows) or 0
        end
    end

    local kbCount = 0
    for _ in pairs(kbSnapshot) do
        kbCount = kbCount + 1
    end

    -- Not ready yet: do NOT latch. Wait for the next state change event.
    if kbCount < 3 then
        return
    end

    soloShuffleAlliesGUIDAtDeath = allies
    soloShuffleAlliesKBAtDeath   = kbSnapshot
    playerDeathSeen = true
end

-- Initialize and register events
function Initialize()
    local frame = CreateFrame("Frame")

    -- Register events for the main addon functionality
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")      -- Register for the PLAYER_ENTERING_WORLD event
    frame:RegisterEvent("PVP_MATCH_COMPLETE")         -- Register for the PVP_MATCH_COMPLETE event
    frame:RegisterEvent("PVP_MATCH_ACTIVE")           -- Register for the PVP_MATCH_ACTIVE event
    frame:RegisterEvent("UPDATE_UI_WIDGET")
        
    frame:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_ENTERING_WORLD"
            or event == "PVP_MATCH_COMPLETE"
            or event == "PVP_MATCH_ACTIVE"
        then
            RefreshDataEvent(self, event, ...)
            RequestBattlefieldScoreData()
        end
    end)

    -- Separate lightweight listener for Solo Shuffle state changes; this does
    -- *not* invoke RefreshDataEvent, it just marks death state for Shuffle.
    local shuffleFrame = CreateFrame("Frame")
    shuffleFrame:RegisterEvent("PVP_MATCH_STATE_CHANGED")
    shuffleFrame:SetScript("OnEvent", function(_, event, ...)
        OnSoloShuffleStateChanged(event, ...)
    end)
end

Initialize()