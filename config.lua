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

SLASH_RATEDSTATSDEBUG1 = "/rsdebug"
SlashCmdList["RATEDSTATSDEBUG"] = function()
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
            local entry = historyTable[1]  -- 🔹 Latest match (at the top)

            print("==========")
            print("Latest Match in", info.name)
            print("Match ID:", entry.matchID or "N/A")
            print("Map:", entry.mapName or "Unknown")
            print("Players with detected talents:")

            for _, stats in ipairs(entry.playerStats or {}) do
                local hasUseful =
                    (stats.pvptalent1 and stats.pvptalent1 ~= "N/A") or
                    (stats.pvptalent2 and stats.pvptalent2 ~= "N/A") or
                    (stats.pvptalent3 and stats.pvptalent3 ~= "N/A") or
                    (stats.heroSpec and stats.heroSpec ~= "N/A") or
                    (stats.loadout and stats.loadout ~= "N/A" and stats.loadout ~= "")

                if hasUseful then
                    print("-----------")
                    print("Name:", stats.name or "Unknown")
                    print("GUID:", stats.guid or "Unknown")

                    if stats.nameplate and stats.nameplate ~= "N/A" then
                        print("  Nameplate:", stats.nameplate)
                    end

                    if stats.loadout and stats.loadout ~= "N/A" and stats.loadout ~= "" then
                        print("  Loadout:", stats.loadout)
                    end

                    for i = 1, 3 do
                        local talentID = stats["pvptalent" .. i]
                        if talentID and talentID ~= "N/A" then
                            local talentName = "UnknownSpell"
                            if stats.loadout and stats.loadout ~= "N/A" and stats.loadout ~= "" then
                                -- Friendly player: assume proper PvP Talent ID
                                talentName = select(2, GetPvpTalentInfoByID(talentID)) or "UnknownTalent"
                            else
                                -- Enemy player: it's a spellID
                                local spellInfo = C_Spell.GetSpellInfo(talentID)
            talentName = (spellInfo and spellInfo.name) or "UnknownSpell"
                            end
                            print("  PvP Talent " .. i .. ":", talentName, "(" .. talentID .. ")")
                        end
                    end

                    if stats.heroSpec and stats.heroSpec ~= "N/A" then
                        print("  Hero Spec:", stats.heroSpec)
                    end

					if stats.playerTrackedSpells and next(stats.playerTrackedSpells) then
						local spellList = {}
						for _, spellID in ipairs(stats.playerTrackedSpells) do
							local spellInfo = C_Spell.GetSpellInfo(spellID)
							if spellInfo and spellInfo.name then
								table.insert(spellList, spellInfo.name .. " (" .. spellID .. ")")
							else
								table.insert(spellList, tostring(spellID))
							end
						end
						table.sort(spellList)
						print("  Player Tracked Spells:", table.concat(spellList, ", "))
					end
                end
            end
        end
    end
end

SLASH_SHOWSPELLS1 = "/showspells"
SlashCmdList["SHOWSPELLS"] = function()
    local tabs = {
      { name = "SoloShuffle", tableKey = "SoloShuffleHistory" },
      { name = "2v2",         tableKey = "v2History"         },
      { name = "3v3",         tableKey = "v3History"         },
      { name = "RBG",         tableKey = "RBGHistory"        },
      { name = "SoloRBG",     tableKey = "SoloRBGHistory"    },
    }

    for _, info in ipairs(tabs) do
        local history = Database[info.tableKey]
        if history and #history > 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00---- "..info.name.." ----|r")
            for _, matchEntry in ipairs(history) do
                local when = date("%Y-%m-%d %H:%M:%S", matchEntry.timestamp or time())

                for _, stats in ipairs(matchEntry.playerStats or {}) do
                    -- 1) Tracked spells
                    local spells = stats.playerTrackedSpells or {}
                    if #spells > 0 then
                        DEFAULT_CHAT_FRAME:AddMessage(
                          ("[%s] %s → Spells:"):format( when, stats.name or "Unknown" )
                        )
                        for _, spellID in ipairs(spells) do
                            -- C_Spell.GetSpellInfo(spellID) now returns a table
                            local sinfo = C_Spell.GetSpellInfo(spellID)
                            local sname = (type(sinfo)=="table" and sinfo.name) or sinfo or "ID:"..spellID
                            -- new SpellInfo table has field `iconID`
                            local iconID = (type(sinfo)=="table" and sinfo.iconID) or nil
                            DEFAULT_CHAT_FRAME:AddMessage(
                              ("    • %s (%d) — iconID: %s"):format(
                                sname, spellID, iconID or "n/a"
                              )
                            )
                        end
                    end

                    -- 2) Gladiator's Medallion
                    do
                        local medID = stats.trinketSpellID
                        if medID and medID > 0 then
                            local minfo = C_Spell.GetSpellInfo(medID)
                            local mname = (type(minfo)=="table" and minfo.name) or minfo or "ID:"..medID
                            local mid   = (type(minfo)=="table" and minfo.iconID)
                            DEFAULT_CHAT_FRAME:AddMessage(
                              ("    Medallion: %s (%d) — iconID: %s")
                              :format(mname, medID, mid or "n/a")
                            )
                        else
                            DEFAULT_CHAT_FRAME:AddMessage("    Medallion: none")
                        end
                    end

                    -- 3) PvP talents 1–3
                    for i=1,3 do
                        local tid = stats["pvptalent"..i]
                        if tid and tid > 0 then
                            -- SpecializationInfo API in 10.2+
                            local tinfo = C_SpecializationInfo.GetPvpTalentInfo(tid)
                            local tname = tinfo and tinfo.name or "ID:"..tid
                            local tidx  = tinfo and tinfo.icon or "n/a"
                            DEFAULT_CHAT_FRAME:AddMessage(
                              ("    PvP Talent %d: %s (%d) — iconID: %s")
                              :format(i, tname, tid, tidx)
                            )
                        else
                            DEFAULT_CHAT_FRAME:AddMessage(
                              ("    PvP Talent %d: none"):format(i)
                            )
                        end
                    end
                end
            end
        end
    end
end


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
        local data = ({
            [1] = Database.SoloShuffleHistory,
            [2] = Database.v2History,
            [3] = Database.v3History,
            [4] = Database.RBGHistory,
            [5] = Database.SoloRBGHistory,
        })[tabID]

        if data then
            RSTATS.__LastHistoryCount = RSTATS.__LastHistoryCount or {}
            local prev = RSTATS.__LastHistoryCount[tabID] or 0
            local current = #data

            if current > prev then
                -- ✅ History grew, reset filters and re-run display
                RatedStatsFilters[tabID] = {}
                RSTATS.__LastHistoryCount[tabID] = current
                C_Timer.After(0.1, function()
                    FilterAndSearchMatches(RatedStatsSearchBox:GetText())
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

local function GetPlayerStatsEndOfMatch(cr, mmr, historyTable, roundIndex, categoryName, categoryID, startTime)
    local mapID = GetCurrentMapID()
    local mapName = GetMapName(mapID) or "Unknown"
    local endTime = GetTimestamp()
    local teamFaction = GetPlayerFactionGroup()  -- Returns "Horde" or "Alliance"
    local enemyFaction = teamFaction == "Horde" and "Alliance" or "Horde"  -- Opposite faction
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
    local battlefieldWinner = GetBattlefieldWinner() == 0 and "Horde" or "Alliance"  -- Convert to "Horde" or "Alliance"
    local friendlyWinLoss = battlefieldWinner == teamFaction and "+   W" or "+   L"  -- Determine win/loss status
	previousRoundsWon = previousRoundsWon or 0
    roundsWon = roundsWon or 0
	local duration = GetBattlefieldInstanceRunTime() / 1000  -- duration in seconds
	local damp = C_Commentator.GetDampeningPercent()
	
    -- ------------------------------------------------------------
    -- Solo Shuffle: increment roundsWon via scoreboard KB delta.
    -- Uses alliesGUID captured at PVP_MATCH_STATE_CHANGED ("Death"),
    -- NOT whatever the scoreboard UI reshuffles later.
    --
    -- No extra guard variable: we just update roundsWon and keep your
    -- existing (roundsWon > previousRoundsWon) W/L logic.
    -- ------------------------------------------------------------
    if C_PvP.IsRatedSoloShuffle and C_PvP.IsRatedSoloShuffle() and roundIndex then
        alliesGUID = alliesGUID or {}
        local myGUID = UnitGUID("player")
        if myGUID then
            alliesGUID[myGUID] = true
        end

        -- Snapshot BEFORE we possibly increment this round.
        previousRoundsWon = roundsWon

        local friendlyKBNow, enemyKBNow = 0, 0
        for i = 1, GetNumBattlefieldScores() do
            local scoreInfo = C_PvP.GetScoreInfo(i)
            if scoreInfo and scoreInfo.guid then
                local kb = tonumber(scoreInfo.killingBlows) or 0
                if alliesGUID[scoreInfo.guid] then
                    friendlyKBNow = friendlyKBNow + kb
                else
                    enemyKBNow = enemyKBNow + kb
                end
            end
        end

        local friendlyPrev = tonumber(soloShuffleLastFriendlyKBTotal) or 0
        local enemyPrev    = tonumber(soloShuffleLastEnemyKBTotal) or 0
        local friendlyDelta = friendlyKBNow - friendlyPrev
        local enemyDelta    = enemyKBNow    - enemyPrev

        -- If my team gained more KB than enemy since last round, count it as a round win.
        -- If 0/0/0 (or equal deltas), we treat as not-a-win (loss/timeout) as you requested.
        if friendlyDelta > enemyDelta then
            roundsWon = roundsWon + 1
        end

        -- Persist totals for next round delta calculation (win or loss).
        soloShuffleLastFriendlyKBTotal = friendlyKBNow
        soloShuffleLastEnemyKBTotal    = enemyKBNow
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
		-- historyTable newest-first (index 1). So walk forward from 1 to pick the immediately previous rounds.
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
            local guid = scoreInfo.guid
            local stats = scoreInfo.stats

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
                -- Non-shuffle brackets keep the old Horde/Alliance logic.
                if faction == teamFaction then
                    friendlyTotalDamage = friendlyTotalDamage + damageDone
                    friendlyTotalHealing = friendlyTotalHealing + healingDone
                elseif faction == enemyFaction then
                    enemyTotalDamage = enemyTotalDamage + damageDone
                    enemyTotalHealing = enemyTotalHealing + healingDone
                end
            end
        end
    end

    -- Debug: Print final team scores before saving

    -- Unregister the events after obtaining the raid leader information
    UnregisterRaidLeaderEvents()

    AppendHistory(historyTable, roundIndex, cr, mmr, mapName, endTime, duration, teamFaction, enemyFaction, friendlyTotalDamage, friendlyTotalHealing, enemyTotalDamage, enemyTotalHealing, friendlyWinLoss, friendlyRaidLeader, enemyRaidLeader, friendlyRatingChange, enemyRatingChange, allianceTeamScore, hordeTeamScore, roundsWon, categoryName, categoryID, damp)

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
				if not InitialCRMMRExists() then
					GetInitialCRandMMR()
				else
				end
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

				    soloShuffleMyTeamIndexAtDeath = nil
                    soloShuffleAlliesGUIDAtDeath = nil
				end)

                playerDeathSeen = false

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
            mmr = "-",
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
    local myTeamIndex

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
                        or (soloShuffleAlliesGUIDAtDeath and soloShuffleAlliesGUIDAtDeath[guid])
                    )
                ) or false,
                race = raceName,
                evaluatedrace = remappedRace,
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

            if C_PvP.IsRatedSoloShuffle then
                if playerData.isFriendly then
                    friendlyTotalDamage = friendlyTotalDamage + damageDone
                    friendlyTotalHealing = friendlyTotalHealing + healingDone
                    friendlyRatingTotal = friendlyRatingTotal + playerData.rating + playerData.ratingChange
                    friendlyRatingChangeTotal = friendlyRatingChangeTotal + playerData.ratingChange
                    friendlyPlayerCount = friendlyPlayerCount + 1
                    table.insert(friendlyPlayers, playerData)
                else
                    enemyTotalDamage = enemyTotalDamage + damageDone
                    enemyTotalHealing = enemyTotalHealing + healingDone
                    enemyRatingTotal = enemyRatingTotal + playerData.rating + playerData.ratingChange
                    enemyRatingChangeTotal = enemyRatingChangeTotal + playerData.ratingChange
                    enemyPlayerCount = enemyPlayerCount + 1
                    table.insert(enemyPlayers, playerData)  
                end
            else
                if playerData.faction == teamFaction then
                    friendlyTotalDamage = friendlyTotalDamage + damageDone
                    friendlyTotalHealing = friendlyTotalHealing + healingDone
                    friendlyRatingTotal = friendlyRatingTotal + playerData.rating + playerData.ratingChange
                    friendlyRatingChangeTotal = friendlyRatingChangeTotal + playerData.ratingChange
                    friendlyPlayerCount = friendlyPlayerCount + 1
                    table.insert(friendlyPlayers, playerData)
                else
                    enemyTotalDamage = enemyTotalDamage + damageDone
                    enemyTotalHealing = enemyTotalHealing + healingDone
                    enemyRatingTotal = enemyRatingTotal + playerData.rating + playerData.ratingChange
                    enemyRatingChangeTotal = enemyRatingChangeTotal + playerData.ratingChange
                    enemyPlayerCount = enemyPlayerCount + 1
                    table.insert(enemyPlayers, playerData)
                end
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
        isSoloShuffle = C_PvP.IsRatedSoloShuffle and C_PvP.IsRatedSoloShuffle() or false,
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
		-- 1. Inject from PendingPvPTalents (highest priority - direct inspect)
		local pending = PendingPvPTalents[player.name]
		if pending and (pending.loadout or pending.pvptalent1 or pending.pvptalent2 or pending.pvptalent3) then
			for k, v in pairs(pending) do
				player[k] = v
			end
			player.talentSource = "inspect"
			PendingPvPTalents[player.name] = nil
		end
	
		-- 2. Inject from DetectedPlayerTalents (CLEU + Inspect hybrid via GUID)
		if player.guid then
			local detected = RSTATS.DetectedPlayerTalents[player.guid]
			if detected and (detected.heroSpec or detected.pvptalent1 or detected.loadout or detected.playerTrackedSpells) then
				for k, v in pairs(detected) do
					if k ~= "name" and player[k] == nil then
						player[k] = v
					end
				end
				player.talentSource = player.talentSource or "detected"
			end
		end
	end

    if not (C_PvP.IsRatedSoloShuffle() and roundIndex >= 1 and roundIndex <= 5) then
        table.insert(historyTable, 1, entry)
        SaveData()
    end

	--- Solo Shuffle logic with a 20-second delay only for round 1-5
	if C_PvP.IsRatedSoloShuffle() and roundIndex >= 1 and roundIndex <= 5 then
	
		local matchIDToUpdate = appendHistoryMatchID
	
		C_Timer.After(20, function()
			local friendlyTotalDamage2, friendlyTotalHealing2 = 0, 0
			local enemyTotalDamage2, enemyTotalHealing2 = 0, 0
			local friendlyRatingTotal2, enemyRatingTotal2 = 0, 0
			local friendlyRatingChangeTotal2, enemyRatingChangeTotal2 = 0, 0
			local friendlyPlayerCount2, enemyPlayerCount2 = 0, 0
	
			-- Recompute totals from the scoreboard snapshot at this time.
			for i = 1, GetNumBattlefieldScores() do
				local scoreInfo = C_PvP.GetScoreInfo(i)
				if scoreInfo then
					local guid2 = scoreInfo.guid
					local damage2 = tonumber(scoreInfo.damageDone) or 0
					local healing2 = tonumber(scoreInfo.healingDone) or 0
					local rating2 = tonumber(scoreInfo.rating) or 0
					local ratingChange2 = tonumber(scoreInfo.ratingChange) or 0
					local newrating2 = rating2 + ratingChange2
	
                    local isSS = C_PvP.IsRatedSoloShuffle and C_PvP.IsRatedSoloShuffle()
                    local alliesGUID = soloShuffleAlliesGUIDAtDeath
                    if isSS and alliesGUID and guid2 and alliesGUID[guid2] then
						friendlyTotalDamage2 = friendlyTotalDamage2 + damage2
						friendlyTotalHealing2 = friendlyTotalHealing2 + healing2
						friendlyRatingTotal2 = friendlyRatingTotal2 + newrating2
						friendlyRatingChangeTotal2 = friendlyRatingChangeTotal2 + ratingChange2
						friendlyPlayerCount2 = friendlyPlayerCount2 + 1
					else
						enemyTotalDamage2 = enemyTotalDamage2 + damage2
						enemyTotalHealing2 = enemyTotalHealing2 + healing2
						enemyRatingTotal2 = enemyRatingTotal2 + newrating2
						enemyRatingChangeTotal2 = enemyRatingChangeTotal2 + ratingChange2
						enemyPlayerCount2 = enemyPlayerCount2 + 1
					end
				end
			end
	
			local friendlyAvgCR2 = friendlyPlayerCount2 > 0 and math.floor(friendlyRatingTotal2 / friendlyPlayerCount2) or "N/A"
			local enemyAvgCR2 = enemyPlayerCount2 > 0 and math.floor(enemyRatingTotal2 / enemyPlayerCount2) or "N/A"
			local friendlyAvgRatingChange2 = friendlyPlayerCount2 > 0 and math.floor(friendlyRatingChangeTotal2 / friendlyPlayerCount2) or "N/A"
			local enemyAvgRatingChange2 = enemyPlayerCount2 > 0 and math.floor(enemyRatingChangeTotal2 / enemyPlayerCount2) or "N/A"
	
			for _, entry in ipairs(historyTable) do
				if entry.matchID == matchIDToUpdate then
					entry.friendlyTotalDamage = friendlyTotalDamage2
					entry.friendlyTotalHealing = friendlyTotalHealing2
					entry.enemyTotalDamage = enemyTotalDamage2
					entry.enemyTotalHealing = enemyTotalHealing2
					entry.friendlyAvgCR = friendlyAvgCR2
					entry.enemyAvgCR = enemyAvgCR2
					entry.friendlyRatingChange = friendlyAvgRatingChange2
					entry.enemyRatingChange = enemyAvgRatingChange2
					break
				end
			end

            table.insert(historyTable, 1, entry)	
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
    
                            -- Calculate totals based on player's team 
						    if C_PvP.IsRatedSoloShuffle then
							    if playerData.isFriendly then
                                    friendlyTotalDamage = friendlyTotalDamage + playerData.damage
							        friendlyTotalHealing = friendlyTotalHealing + playerData.healing
							        friendlyRatingTotal = friendlyRatingTotal + playerData.rating + playerData.ratingChange
							        friendlyRatingChangeTotal = friendlyRatingChangeTotal + playerData.ratingChange
							        friendlyPlayerCount = friendlyPlayerCount + 1
							        table.insert(friendlyPlayers, playerData)
                                else
                                    enemyTotalDamage = enemyTotalDamage + playerData.damage
							        enemyTotalHealing = enemyTotalHealing + playerData.healing
							        enemyRatingTotal = enemyRatingTotal + playerData.rating + playerData.ratingChange
							        enemyRatingChangeTotal = enemyRatingChangeTotal + playerData.ratingChange
							        enemyPlayerCount = enemyPlayerCount + 1
							        table.insert(enemyPlayers, playerData)
                                end
						    else
                                if playerData.faction == teamFaction then
							        friendlyTotalDamage = friendlyTotalDamage + playerData.damage
							        friendlyTotalHealing = friendlyTotalHealing + playerData.healing
							        friendlyRatingTotal = friendlyRatingTotal + playerData.rating + playerData.ratingChange
							        friendlyRatingChangeTotal = friendlyRatingChangeTotal + playerData.ratingChange
							        friendlyPlayerCount = friendlyPlayerCount + 1
							        table.insert(friendlyPlayers, playerData)
						        else
    							    enemyTotalDamage = enemyTotalDamage + playerData.damage
							        enemyTotalHealing = enemyTotalHealing + playerData.healing
							        enemyRatingTotal = enemyRatingTotal + playerData.rating + playerData.ratingChange
							        enemyRatingChangeTotal = enemyRatingChangeTotal + playerData.ratingChange
							        enemyPlayerCount = enemyPlayerCount + 1
							        table.insert(enemyPlayers, playerData)
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
--                    entry.playerStats = playerStats
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

    -- 1) Sort history by matchID ascending
    table.sort(historyTable, function(a, b)
        return (a.matchID or 0) < (b.matchID or 0)
    end)

    content.matchFrames = {}
	content.matchFrameByID = {}

    -- 3) Create headers
    local scoreHeaderText = (tabID == 2 or tabID == 3) and "" or "Score"
	local c = function(text) return RSTATS:ColorText(text) end
	local headers = {
		c("Win/Loss"), c(scoreHeaderText), c("Map"), c("Match End Time"), c("Duration"), "", "",
		c("Faction"), c("Raid Leader"), c("Avg CR"), c("MMR"), c("Damage"), c("Healing"), c("Avg Rat Chg"), "",
		 "", c("Faction"), c("Raid Leader"), c("Avg CR"), c("MMR"), c("Damage"), c("Healing"), c("Avg Rat Chg"), c("Note")
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

        return {
            (match.friendlyWinLoss or "-"),
            scoreText,
            (mapDisplay or "N/A"),
            date("%a %d %b %Y - %H:%M:%S", match.endTime) or "N/A",
            (match.duration or "N/A"),
            "",
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
		headerFrame:SetPoint("TOPLEFT", mmrLabel, "BOTTOMLEFT", 0, -30)
		
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
    baseAnchor:SetPoint("TOPLEFT", mmrLabel, "BOTTOMLEFT", 0, -35)
    content.baseAnchor = baseAnchor

    -- 6) Create each match row (all parented to content)
    for i = #historyTable, 1, -1 do
		local match = historyTable[i]
		local matchID = match.matchID or i
		local parentWidth  = UIConfig:GetWidth()
		local parentHeight = UIConfig:GetHeight()
		
		if content.matchFrameByID[matchID] then
            table.insert(content.matchFrames, content.matchFrameByID[matchID])
        else
			local matchFrame = CreateFrame("Frame", "MatchFrame", nil, "BackdropTemplate")
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
				if j == 4 and match.damp and (tabID == 1 or tabID == 2 or tabID == 3) then
					fs:EnableMouse(true)
					fs:SetScript("OnEnter", function()
						GameTooltip:SetOwner(fs, "ANCHOR_RIGHT")
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
			local nestedTable = CreateNestedTable(matchFrame, match.playerStats or {}, match.teamFaction, match.isInitial, match.isMissedGame, content, match)
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
			
			content.matchFrameByID[matchID] = matchFrame
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

-- Function to check and process player talents for new games
local function CheckPlayerTalents(playerName, isNewGame)
    if isNewGame then
        -- Check the history table and process talents for new games only
        local playerStats = Database.SoloShuffleHistory[playerName]
        
        if not playerStats.talentCode then
            -- This is a new game, so retrieve and store the talent code
            local talentCode = GetPlayerTalentCode(playerName)  -- You need to define this function to get the talent code
            playerStats.talentCode = talentCode  -- Store the talent code in the player's stats
        end
    end
end

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
    -- ----------------------------------------------------------------------------
    -- 0) clear any old icons
    -- ----------------------------------------------------------------------------
    if parent.spellIcons then
        for _, ic in ipairs(parent.spellIcons) do ic:Hide() end
    end
    parent.spellIcons = {}

    -- ----------------------------------------------------------------------------
    -- A) draw the four “PvP” icons row (always)
    -- ----------------------------------------------------------------------------

    do
        local topOff    = -45
        local padding   = 4
        local size      = 20

        -- build our list: medallion, pvp1, pvp2, pvp3
		local pvp = {}
	
		-- 1) grab all “Prized …” trinkets from tracked spells
		local found = {}
        for _, spellID in ipairs(stats.playerTrackedSpells or {}) do
            local sinfo = C_Spell.GetSpellInfo(spellID)
            local sname = sinfo and sinfo.name
            if sname then
                -- look for Insignia/Medallion/Emblem at end, or Badge of Ferocity, or Sigil anywhere
                if sname:match("Insignia$") 
                or sname:match("Medallion$") 
                or sname:match("Badge$") 
                or sname:find("Emblem$") 
                or sname:match("Adapted") then
                    tinsert(found, spellID)
                end
            end
        end
	
		-- 2) if we found at least one, insert them all; otherwise one placeholder
		if #found > 0 then
			for _, id in ipairs(found) do
				tinsert(pvp, id)
			end
		else
			tinsert(pvp, "X")
		end
	
		-- 3) now append the three PvP talents as before
		for i = 1, 3 do
			local tid = stats["pvptalent"..i]
			if tid and tid > 0 then
				tinsert(pvp, tid)
			else
				tinsert(pvp, "X")
			end
		end

        -- center that row
        local count   = #pvp
        local rowW    = count*size + (count-1)*padding
        local startX  = (parent:GetWidth() - rowW)/2

		for i, eid in ipairs(pvp) do
			local btn = CreateFrame("Button", "PlayerPvPTalentFrame", parent, "BackdropTemplate")
			btn:SetSize(size, size)
			btn:SetPoint("TOPLEFT", parent, "TOPLEFT",
						startX + (i-1)*(size+padding),
						topOff)
		
			-- 1) pick your texture, remember if we fell back to the red-X
			local isTalent       = (i > 1)
			local lookupID       = tonumber(eid)     -- will be nil for "X"
			local tex, didFallback, fromTalentInfo
		
			if not lookupID then
				-- no ID at all → hard fallback
				tex         = "Interface\\Icons\\Achievement_PVP_P_250K.blp"
				didFallback = true
		
			elseif isTalent then
				-- PvP talents: try talent→spell first
				local tinfo = C_SpecializationInfo.GetPvpTalentInfo(lookupID)
				if tinfo and tinfo.spellID then
					fromTalentInfo = true
					tex, _         = C_Spell.GetSpellTexture(tinfo.spellID)
				end
				-- next try the raw talentID as a “spell”
				if not tex then
					tex, _        = C_Spell.GetSpellTexture(lookupID)
				end
				-- last resort: red-X
				if not tex then
					tex           = "Interface\\Icons\\Achievement_PVP_P_250K.blp"
					didFallback   = true
				end
		
			else
				-- medallion is a normal spellID
				tex, _         = C_Spell.GetSpellTexture(lookupID)
				if not tex then
					tex         = select(3, C_Spell.GetSpellInfo(lookupID))
				end
			end
		
			btn.icon = btn:CreateTexture(nil, "BACKGROUND")
			btn.icon:SetAllPoints(btn)
			btn.icon:SetTexture(tex)
		
			-- 2) tooltip
			btn:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				if didFallback then
					GameTooltip:AddLine("Undetected",1,0,0)
				elseif fromTalentInfo then
					GameTooltip:SetPvpTalent(lookupID)
				else
					GameTooltip:SetSpellByID(lookupID)
				end
				GameTooltip:Show()
			end)
			btn:SetScript("OnLeave", GameTooltip_Hide)
		
			btn:Show()
			tinsert(parent.spellIcons, btn)
		end
    end

    -- ----------------------------------------------------------------------------
    -- B) loadout present? show that and stop
    -- ----------------------------------------------------------------------------
    if stats.loadout and stats.loadout ~= "" then
        -- ensure our loadoutBox & label exist
        if not parent.loadoutBox then
            local eb = CreateFrame("EditBox", "PlayerLoadoutFrame", parent, "BackdropTemplate")
            eb:SetSize(280, 40)
            eb:SetPoint("TOP", parent, "TOP", 0, -80)
            eb:SetFontObject(ChatFontNormal)
            eb:SetAutoFocus(false)
            eb:EnableMouse(true)
            eb:SetScript("OnEscapePressed", eb.ClearFocus)
            parent.loadoutBox = eb

            local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            lbl:SetPoint("TOPLEFT", eb, "TOPLEFT", 4, 4)
            lbl:SetText("Loadout Copy:")
            lbl:SetFont(GetUnicodeSafeFont(), 8)
            parent.loadoutLabel = lbl
        end

        parent.loadoutLabel:Show()
        parent.loadoutBox:Show()
        parent.loadoutBox:SetText(stats.loadout)
        parent.loadoutBox:SetFont(GetUnicodeSafeFont(), 8, "OUTLINE")
        parent.loadoutBox:HighlightText(0)
        parent.loadoutBox:SetCursorPosition(0)

        return
    end

    -- ----------------------------------------------------------------------------
    -- C) no loadout → hide loadout UI and draw tracked-spell icons grid
    -- ----------------------------------------------------------------------------
    if parent.loadoutBox then parent.loadoutBox:Hide() end
    if parent.loadoutLabel then parent.loadoutLabel:Hide() end

    -- gather spells (history first, then detection)
    local spells = stats.playerTrackedSpells
               or ((stats.guid and RSTATS.DetectedPlayerTalents[stats.guid]
                    and RSTATS.DetectedPlayerTalents[stats.guid].playerTrackedSpells)
                   or {})

    -- grid layout
    local leftMarg  = 20
    local padding   = 4
    local iconSize  = 12
    local topStart  = -40 - (24 + padding*2)  -- push below the PvP row
    local usableW   = parent:GetWidth() - leftMarg*2
    local cols      = math.max(1, math.floor(usableW / (iconSize + padding)))

    for idx, spellID in ipairs(spells) do
        local row = math.floor((idx-1) / cols)
        local col = (idx-1) % cols

        local x = leftMarg + col * (iconSize + padding)
        local y = topStart - row * (iconSize + padding)

        local icon = CreateFrame("Button", "PlayerSpellsFrame", parent)
        icon:SetSize(iconSize, iconSize)
        icon:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

        local tex = (C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID))
                  or select(3, C_Spell.GetSpellInfo(spellID))
        icon.texture = icon:CreateTexture(nil, "BACKGROUND")
        icon.texture:SetAllPoints(icon)
        icon.texture:SetTexture(tex)

        icon:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(spellID)
            GameTooltip:Show()
        end)
        icon:SetScript("OnLeave", GameTooltip_Hide)

        tinsert(parent.spellIcons, icon)
    end
end

-- Pop-out frame + name box tweaks
local function CreateCopyNameFrame(stats, matchEntry)
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

local function CreateClickableName(parent, stats, matchEntry, x, y, columnWidth, rowHeight)
  -- stats = matchEntry.playerStats[i], contains .name + .loadout + .playerTrackedSpells
  local playerName = stats.name

  local nameText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  nameText:SetFont(GetUnicodeSafeFont(), 8, "OUTLINE")
  nameText:SetPoint("CENTER", parent, "TOPLEFT", x + columnWidth/2, y - rowHeight/2)
  nameText:SetText(playerName)
  nameText:SetFont(GetUnicodeSafeFont(), 8)

  local clickableFrame = CreateFrame("Button", "ClickableName", parent)
  clickableFrame:SetSize(nameText:GetStringWidth(), nameText:GetStringHeight())
  clickableFrame:SetPoint("CENTER", nameText, "CENTER")

  clickableFrame:SetScript("OnClick", function()
  
--    -- ───────────────────────────────────────────────────────────────────────────
--    -- DEBUG: print out whatever PvP-talent IDs (and trinket) we have
--    -- ───────────────────────────────────────────────────────────────────────────
--    local t1, t2, t3 = stats.pvptalent1, stats.pvptalent2, stats.pvptalent3
--    local med = stats.trinketSpellID
--    DEFAULT_CHAT_FRAME:AddMessage(
--      ("|cff00ccff[%s]|r PvP Talents → medallion:%s 1:%s 2:%s 3:%s"):format(
--        stats.name,
--        med  and tostring(med)  or "<nil>",
--        t1   and tostring(t1)   or "<nil>",
--        t2   and tostring(t2)   or "<nil>",
--        t3   and tostring(t3)   or "<nil>"
--      )
--    )

    CreateCopyNameFrame(stats, matchEntry)
  end)

  return nameText
end

function CreateNestedTable(parent, playerStats, friendlyFaction, isInitial, isMissedGame, content, matchEntry)
	local nestedTable = CreateFrame("Frame", "NestedTable_" .. (parent:GetName() or "unknown"), parent, "BackdropTemplate")

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
	
    -- ------------------------------------------------------------------
    -- column geometry (dynamic based on parent:GetWidth())
    -- ------------------------------------------------------------------
    -- percentages for each of the 13 base-pixel columns (for a 2004px parent)
    local baseFracs = {
        0.049900,  -- 100 / 2004
        0.019960,  --  40 / 2004
        0.019960,
        0.024950,  --  50 / 2004
        0.029940,  --  60 / 2004
        0.019960,
        0.019960,
        0.024950,
        0.019960,
        0.019960,
        0.029940,
        0.029940,
        0.039920,  --  80 / 2004
    }
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

    local isSS = C_PvP.IsRatedSoloShuffle and C_PvP.IsRatedSoloShuffle()

    local headers = {
        "Character", "Faction", "Race", "Class", "Spec", "Hero", "Role", "CR", "KBs", (isSS and "Deaths" or "HKs"), "Damage", "Healing", "Rating Chg",
        "Character", "Faction", "Race", "Class", "Spec", "Hero", "Role", "CR", "KBs", (isSS and "Deaths" or "HKs"), "Damage", "Healing", "Rating Chg"
    }

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
	local totalColumnsPerTeam = 13
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
			-- “Enemy team” columns use pre-computed origin
			xPos = parent:GetWidth() * 0.5 + columnPositions[i - totalColumnsPerTeam]
		end
		
		local width = columnWidths[i]
	
		headerText:SetPoint("TOPLEFT", nestedTable, "TOPLEFT", xPos, -headerHeight)
		headerText:SetWidth(width)
	end
    -- Separate friendly and enemy player stats
    local friendlyPlayers = {}
    local enemyPlayers = {}

    if isInitial or isMissedGame then
        -- For initial entries, the player's stats are on the left and placeholders on the right
        table.insert(friendlyPlayers, playerStats[1])  -- Assume the player is the first entry
        for i = 1, playersPerTeam do
            table.insert(enemyPlayers, {
                name = "-", originalFaction = "-", race = "-", class = "-", spec = "-", hero = "-", role = "-", 
                newrating = "-", killingBlows = "-", honorableKills = "-", damage = "-", healing = "-", ratingChange = "-"
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

    -- Populate friendly player stats
    for index, player in ipairs(friendlyPlayers) do
        local rowOffset = -(headerHeight + 15 * index)  -- Adjust rowOffset to account for headers
		CreateClickableName(nestedTable, player, matchEntry, columnPositions[1], rowOffset, columnWidths[1], rowHeight)
        for i, stat in ipairs({
			"",
            factionIcons[player.originalFaction] or player.originalFaction, 
            raceIcons[player.race] or player.race, 
            classIcons[player.class] or player.class, 
            specIcons[player.spec] or player.spec, 
			player.heroSpec or "",
            roleIcons[player.role] or player.role,  -- Replace numeric role with icon
            player.newrating, 
            player.killingBlows, 
            (isSS and player.deaths or player.honorableKills), 
            FormatNumber(player.damage), 
            FormatNumber(player.healing), 
            player.ratingChange
        }) do
            if i == 2 then
                CreateIconWithTooltip(nestedTable, stat, player.originalFaction, columnPositions[i], rowOffset, columnWidths[i], rowHeight)
            elseif i == 3 then
                CreateIconWithTooltip(nestedTable, stat, player.race, columnPositions[i], rowOffset, columnWidths[i], rowHeight)
            elseif i == 4 then
                CreateIconWithTooltip(nestedTable, stat, player.class, columnPositions[i], rowOffset, columnWidths[i], rowHeight)
            elseif i == 5 then
                CreateIconWithTooltip(nestedTable, stat, player.spec, columnPositions[i], rowOffset, columnWidths[i], rowHeight)
            elseif i == 6 then
                -- hero‐talent column (guard against nil/undetected)
                local heroName = player.heroSpec
                if not heroName or not HERO_TALENTS[heroName] then
                    -- no hero spec detected (or not in our table) → show “Undetected”
                    local text = nestedTable:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    text:SetPoint("CENTER", nestedTable, "TOPLEFT",
                                columnPositions[i] + columnWidths[i]/2,
                                rowOffset - rowHeight/2)
					text:SetFont(GetUnicodeSafeFont(), entryFontSize)
                    text:SetText("Undetected")
                else
                   -- we have a mapping!
                   local atlas = HERO_TALENTS[heroName].iconAtlas
                   if atlas then
                       CreateIconWithTooltip(
                         nestedTable,
                         atlas,
                         heroName,
                         columnPositions[i],
                         rowOffset,
                         columnWidths[i],
                         rowHeight,
                         true
                       )
                    else
                        -- you could still fall back to text if you want
                        local text = nestedTable:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                        text:SetPoint("CENTER", nestedTable, "TOPLEFT",
                                    columnPositions[i] + columnWidths[i]/2,
                                    rowOffset - rowHeight/2)
					 	text:SetFont(GetUnicodeSafeFont(), entryFontSize)
                        text:SetText(heroName)
                    end
               end
            elseif i == 7 then
                -- Add role tooltip
                CreateIconWithTooltip(nestedTable, stat, roleTooltips[player.role], columnPositions[i], rowOffset, columnWidths[i], rowHeight)
            else
                local textValue = stat or "-"  -- Provide a default value if stat is nil
                local text = nestedTable:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
				local xPos = columnPositions[i]
				local width = columnWidths[i]
                text:SetFont(GetUnicodeSafeFont(), entryFontSize)
                text:SetJustifyH("CENTER")
                text:SetPoint("CENTER", nestedTable, "TOPLEFT", xPos + (width / 2), rowOffset - (rowHeight / 2))
                text:SetText(tostring(textValue))  -- Ensure the value is converted to a string
            end
        end  -- This 'end' closes the inner 'for' loop
    end  -- This 'end' closes the outer 'for' loop
    
    -- Populate enemy player stats
    for index, player in ipairs(enemyPlayers) do
		local rowOffset = -(headerHeight + 15 * index)  -- Adjust rowOffset to account for headers
        CreateClickableName(nestedTable, player, matchEntry, columnPositions[COLS_PER_TEAM + 1], rowOffset, columnWidths[COLS_PER_TEAM + 1], rowHeight)
        for i, stat in ipairs({
			"",
            factionIcons[player.originalFaction] or player.originalFaction, 
            raceIcons[player.race] or player.race, 
            classIcons[player.class] or player.class, 
            specIcons[player.spec] or player.spec,
			player.heroSpec or "",
            roleIcons[player.role] or player.role,  -- Replace numeric role with icon
            player.newrating, 
            player.killingBlows, 
            (isSS and player.deaths or player.honorableKills), 
            FormatNumber(player.damage), 
            FormatNumber(player.healing), 
            player.ratingChange
        }) do
            local ci    = COLS_PER_TEAM + i
            local xPos  = columnPositions[ci]
            local width = columnWidths[ci]
			

            if i == 2 then
                CreateIconWithTooltip(nestedTable, stat, player.originalFaction, xPos, rowOffset, width, rowHeight)
            elseif i == 3 then
                CreateIconWithTooltip(nestedTable, stat, player.race, xPos, rowOffset, width, rowHeight)
            elseif i == 4 then
                CreateIconWithTooltip(nestedTable, stat, player.class, xPos, rowOffset, width, rowHeight)
            elseif i == 5 then
                CreateIconWithTooltip(nestedTable, stat, player.spec, xPos, rowOffset, width, rowHeight)
           elseif i == 6 then
                -- hero‐talent column (guard against nil/undetected)
				local heroName = player.heroSpec
				if not heroName or not HERO_TALENTS[heroName] then
					local text = nestedTable:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
					text:SetPoint("CENTER", nestedTable, "TOPLEFT",
									xPos + (width / 2),
									rowOffset - (rowHeight / 2))
					text:SetFont(GetUnicodeSafeFont(), entryFontSize)
					text:SetText("Undetected")
				else
					local atlas = HERO_TALENTS[heroName].iconAtlas
					if atlas then
						CreateIconWithTooltip(
							nestedTable,
							atlas,
							heroName,
							xPos,
							rowOffset,
							width,
							rowHeight,
							true
						)
					else
						local text = nestedTable:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
						text:SetPoint("CENTER", nestedTable, "TOPLEFT",
									xPos + (width / 2),
									rowOffset - (rowHeight / 2))
						text:SetFont(GetUnicodeSafeFont(), entryFontSize)
						text:SetText(heroName)
					end
				end
            elseif i == 7 then
                -- Add role tooltip
                CreateIconWithTooltip(nestedTable, stat, roleTooltips[player.role], xPos, rowOffset, width, rowHeight)
            else
                local textValue = stat or "-"  -- Provide a default value if stat is nil
                local text = nestedTable:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                text:SetFont(GetUnicodeSafeFont(), entryFontSize)
                text:SetJustifyH("CENTER")
				text:SetPoint("CENTER", nestedTable, "TOPLEFT", xPos + (width / 2), rowOffset - (rowHeight / 2))
                text:SetText(tostring(textValue))  -- Ensure the value is converted to a string
            end
        end  -- This 'end' closes the inner 'for' loop
    end  -- This 'end' closes the outer 'for' loop

    -- Add placeholders for missing friendly players if necessary
    if not (isInitial or isMissedGame) and #friendlyPlayers < numberOfRows then
        for index = #friendlyPlayers + 1, numberOfRows do
            local rowOffset = -15 * index
            for i = 1, #columnPositions do
                local text = nestedTable:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
				local xPos = columnPositions[i]
				local width = columnWidths[i]
				text:SetPoint("CENTER", nestedTable, "TOPLEFT", xPos + (width / 2), rowOffset - (rowHeight / 2))
				text:SetWidth(width)
				text:SetFont(GetUnicodeSafeFont(), entryFontSize)
				text:SetJustifyH("CENTER")
				text:SetText("-")
            end
        end
    end
    
    -- Add placeholders for missing enemy players if necessary
    if not (isInitial or isMissedGame) and #enemyPlayers < numberOfRows then
        for index = #enemyPlayers + 1, numberOfRows do
            local rowOffset = -15 * index
            for i = 1, #columnPositions do
                local text = nestedTable:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
				local xPos = columnPositions[i]
				local width = columnWidths[i]
				text:SetPoint("CENTER", parent, "TOPLEFT", xPos + (width / 2), rowOffset - (rowHeight / 2))
				text:SetWidth(width)
				text:SetFont(GetUnicodeSafeFont(), entryFontSize)
				text:SetJustifyH("CENTER")
				text:SetText("-")
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
    local currentCR = "-"
	local currentMMR = "-"
	
    local categoryMappings = {
        [1] = "v2History",
        [2] = "v3History",
        [4] = "RBGHistory",
        [7] = "SoloShuffleHistory",
        [9] = "SoloRBGHistory"
    }
	
    local historyTable = Database[categoryMappings[categoryID]]
    local highestMatchID = nil
    local highestMatchEntry = nil

    -- 1) First, find the entry with the highest matchID
    if historyTable and #historyTable > 0 then
        for _, entry in ipairs(historyTable) do
            if entry.matchID and (not highestMatchID or entry.matchID > highestMatchID) then
                highestMatchID = entry.matchID
                highestMatchEntry = entry
            end
        end
    end

    -- 2) If we found an entry with the highest matchID, get the stats from that match
    if highestMatchEntry and highestMatchEntry.playerStats then
        for _, stats in ipairs(highestMatchEntry.playerStats) do
            if stats.name == playerName and stats.postmatchMMR and stats.postmatchMMR > 0 then
                currentCR = stats.newrating or "0"
                currentMMR = stats.postmatchMMR or "0"
                break
            end
        end
    end
    
    -- Display or return currentCR/currentMMR as desired
    -- e.g., update your contentFrame here
   
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
		contentFrame.crLabel:SetFont(GetUnicodeSafeFont(), 14)
		contentFrame.crLabel:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, -10)
	end
	contentFrame.crLabel:SetText(RSTATS:ColorText("Current CR: ") .. currentCR)
	
	if not contentFrame.mmrLabel then
		contentFrame.mmrLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		contentFrame.mmrLabel:SetFont(GetUnicodeSafeFont(), 14)
		contentFrame.mmrLabel:SetPoint("TOPLEFT", contentFrame.crLabel, "BOTTOMLEFT", 0, -5)
	end
	contentFrame.mmrLabel:SetText(RSTATS:ColorText("Current MMR: ") .. currentMMR)
	
	if not contentFrame.instructionLabel then
		contentFrame.instructionLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		contentFrame.instructionLabel:SetFont(GetUnicodeSafeFont(), 12)
		contentFrame.instructionLabel:SetPoint("TOP", contentFrame, "TOP", 0, -10)
		contentFrame.instructionLabel:SetJustifyH("CENTER")
	end
	contentFrame.instructionLabel:SetText("Click on rows to expand.    \nClick on a player name to copy name, see trinkets, pvp talents, loadout codes or get a Spells List.\nAchievements Tracking uses memory due to a large filesize, right click minimap to toggle it ON/OFF.\nBattle.net Add Friend button on nameplates, for when you meet good peeps!")
    
    -- Return the last label for potential further positioning
    return contentFrame.mmrLabel
end

----------------------------------
-- Config functions continued
----------------------------------

function Config:CreateMenu()
    if UIConfig then return UIConfig end

    local scrollFrames  = {}
    local scrollContents = {}
    local contentFrames  = {}
    
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

    -- Create 5 frames + scrollFrames for each tab
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
	
     -- expose frames before any history is built
    RSTATS.UIConfig       = UIConfig
    RSTATS.ContentFrames  = contentFrames
    RSTATS.ScrollFrames   = scrollFrames
    RSTATS.ScrollContents = scrollContents
	
	local selectedTimeFilter = "today"
	
	local Filters = RatedStatsFilters  -- Already exposed globally
	local Stats = RSTATS_STATS         -- Our new global from stats.lua
	
	function RSTATS:UpdateStatsView(filterType, tabID)
		tabID = tabID or PanelTemplates_GetSelectedTab(RSTATS.UIConfig)

		local allMatches = ({
			[1] = Database.SoloShuffleHistory,
			[2] = Database.v2History,
			[3] = Database.v3History,
			[4] = Database.RBGHistory,
			[5] = Database.SoloRBGHistory,
		})[tabID] or {}
	
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

	local function UpdateCompactHeaders(tabID)
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
    local tabNames = { "Solo Shuffle", "2v2", "3v3", "RBG", "Solo RBG" }
    local tabs = {}
    for i, name in ipairs(tabNames) do
        local tab = CreateFrame("Button","RatedStatsTab"..i,UIConfig,"PanelTabButtonTemplate")
        tab:SetID(i)
        tab:SetText(name)
        PanelTemplates_TabResize(tab,0)

        if i == 1 then
            tab:SetPoint("TOPLEFT", UIConfig, "BOTTOMLEFT", 10, 2)
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
			
			-- always go back to page 1 on a brand-new tab
			UIConfig.ActiveTeamView = 1
			UpdateArrowState()
		
			ACTIVE_TAB_ID = tabID
			
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
    PanelTemplates_SetTab(UIConfig, 1)
    contentFrames[1]:Show()

    -- A local function that calls your revised DisplayHistory (shown below)
    local function RefreshDisplay()
        -- For each bracket
        local mmrLabel1 = DisplayCurrentCRMMR(contentFrames[1],7)
        local headers1, frames1 = RSTATS:DisplayHistory(scrollContents[1], Database.SoloShuffleHistory, mmrLabel1, 1)
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
        local headers5, frames5 = RSTATS:DisplayHistory(scrollContents[5], Database.SoloRBGHistory, mmrLabel5, 5)
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
	
    UIConfig.ToggleViewButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
        GameTooltip:SetText("Toggle View",1,1,1)
        GameTooltip:AddLine("Switch between full and compact layout.", 0.8,0.8,0.8)
        GameTooltip:Show()
    end)
    UIConfig.ToggleViewButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UIConfig.ToggleViewButton:SetScript("OnClick", function()
        UIConfig.isCompact = not UIConfig.isCompact
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
			RSTATS.ScrollFrames[ACTIVE_TAB_ID]:SetHorizontalScroll(0)
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

	local DEFAULT_TAB_ID = 1
	for i, name in ipairs(tabNames) do
		local frame = contentFrames[i]
		local content = scrollContents[i]
	
		frame:SetScript("OnShow", function()
			if not content._initialized then
				content._initialized = true
				C_Timer.After(0.05, function()
					FilterAndSearchMatches(RatedStatsSearchBox and RatedStatsSearchBox:GetText() or "")
				end)
			end
		end)
	end
	
	PanelTemplates_SetTab(UIConfig, DEFAULT_TAB_ID)
	contentFrames[DEFAULT_TAB_ID]:Show()
	ACTIVE_TAB_ID = DEFAULT_TAB_ID
	
	-- Run filter on first visible tab
	scrollContents[DEFAULT_TAB_ID]._initialized = true
	C_Timer.After(0.05, function()
		local dropdown = RSTATS.Dropdowns[DEFAULT_TAB_ID]
		local selected = dropdown and UIDropDownMenu_GetText(dropdown) or "Today"
		local filterKey = selected:lower():gsub(" ", "") or "today"
	
		FilterAndSearchMatches("")
		RSTATS:UpdateStatsView(filterKey, DEFAULT_TAB_ID)
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

    -- Mark round as ended
    playerDeathSeen = true

    -- Freeze our allies for THIS round.
    -- In Solo Shuffle, party1/party2 are your teammates for the current round.
    soloShuffleAlliesGUIDAtDeath = {}

    local g = UnitGUID("player")
    if g then soloShuffleAlliesGUIDAtDeath[g] = true end

    g = UnitGUID("party1")
    if g then soloShuffleAlliesGUIDAtDeath[g] = true end

    g = UnitGUID("party2")
    if g then soloShuffleAlliesGUIDAtDeath[g] = true end
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
    
    frame:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_ENTERING_WORLD"
            or event == "PVP_MATCH_COMPLETE"
            or event == "PVP_MATCH_ACTIVE"
        then
            RefreshDataEvent(self, event, ...)
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