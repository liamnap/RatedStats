-- Rated Stats: Export / Wipe utilities
-- Export window provides REFlex-compatible CSV headings and lets users filter by bracket.

local function GetPlayerKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

local function ToNumber(v)
    local n = tonumber(v)
    if n then return n end
    return 0
end

local function IsWin(winLoss)
    return winLoss == "W" or winLoss == true or winLoss == 1
end

local function VictoryString(entry)
    -- REFlex: for Solo Shuffle, Victory is literally "nil" in CSV.
    if type(entry) == "table" and entry.isSoloShuffle then
        return "nil"
    end
    local wl = type(entry) == "table" and (entry.friendlyWinLoss or entry.winLoss) or nil
    return tostring(IsWin(wl))
end

local function CleanCSVField(v)
    if v == nil then return "" end
    v = tostring(v)
    -- REFlex CSV uses semicolon separators; sanitize semicolons/newlines.
    v = v:gsub(";", ",")
    v = v:gsub("\r", " ")
    v = v:gsub("\n", " ")
    return v
end

local function GetDurationSeconds(entry)
    if type(entry) ~= "table" then return 0 end
    local n = tonumber(entry.matchDuration) or tonumber(entry.durationSeconds) or tonumber(entry.durationRaw) or tonumber(entry.duration)
    if n then return n end
    return 0
end

local function GetMyPlayerStat(entry)
    if type(entry) ~= "table" then return nil end
    local ps = entry.playerStats
    if type(ps) ~= "table" then return nil end
    local myGUID = UnitGUID and UnitGUID("player") or nil
    local myKey = GetPlayerKey()
    for _, p in ipairs(ps) do
        if type(p) == "table" then
            if myGUID and p.guid and p.guid == myGUID then return p end
            if p.name and p.name == myKey then return p end
        end
    end
    return nil
end

local CLASS_TOKEN_BY_LOCALIZED
local function BuildClassTokenMap()
    if CLASS_TOKEN_BY_LOCALIZED then return end
    CLASS_TOKEN_BY_LOCALIZED = {}
    if type(LOCALIZED_CLASS_NAMES_MALE) == "table" then
        for token, loc in pairs(LOCALIZED_CLASS_NAMES_MALE) do
            CLASS_TOKEN_BY_LOCALIZED[loc] = token
        end
    end
    if type(LOCALIZED_CLASS_NAMES_FEMALE) == "table" then
        for token, loc in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do
            CLASS_TOKEN_BY_LOCALIZED[loc] = token
        end
    end
end

local function ClassTokenFromLocalized(loc)
    BuildClassTokenMap()
    if not loc then return "" end
    return CLASS_TOKEN_BY_LOCALIZED[loc] or tostring(loc)
end

local function NormalizeMapName(mapName)
    -- Your DB often stores short arena codes (NPG/EC/COC/etc). REFlex uses readable names.
    if not mapName then return "" end
    mapName = tostring(mapName)
    if type(mapShortCodes) == "table" then
        -- Build reverse on the fly (small table).
        for full, short in pairs(mapShortCodes) do
            if short == mapName then
                return full
            end
        end
    end
    return mapName
end

local function FormatComp(players)
    -- REFlex comp tokens: CLASS-SPEC-NAME, comma separated.
    if type(players) ~= "table" then return "" end
    local out = {}
    for _, p in ipairs(players) do
        if type(p) == "table" then
            local cls = ClassTokenFromLocalized(p.class)
            local spec = p.spec and tostring(p.spec) or ""
            local name = p.name and tostring(p.name) or ""
            table.insert(out, cls .. "-" .. spec .. "-" .. name)
        end
    end
    table.sort(out)
    return table.concat(out, ",")
end

local function GetArenaComps(entry)
    if type(entry) ~= "table" or type(entry.playerStats) ~= "table" then
        return "", ""
    end
    local me = GetMyPlayerStat(entry)
    local myTeamIndex = entry.myTeamIndex or (me and me.teamIndex) or nil
    local team, enemy = {}, {}
    for _, p in ipairs(entry.playerStats) do
        if type(p) == "table" then
            if myTeamIndex ~= nil and p.teamIndex == myTeamIndex then
                table.insert(team, p)
            else
                table.insert(enemy, p)
            end
        end
    end
    return FormatComp(team), FormatComp(enemy)
end

local function GetHistoryForExport(modeKey)
    if type(LoadData) == "function" then
        LoadData()
    end

    local db = RSTATS_Database
    if type(db) ~= "table" then return nil end

    local key = GetPlayerKey()
    local pdata = db[key]
    if type(pdata) ~= "table" then return nil end

    -- If available, reuse the addon helper for spec-aware history (SS / SoloRBG).
    if RSTATS and RSTATS.GetHistoryForTab then
        local tabID = ({
            SoloShuffle = 1,
            ["2v2"] = 2,
            ["3v3"] = 3,
            RBG = 4,
            SoloRBG = 5,
        })[modeKey]

        if tabID then
            local ok, data = pcall(RSTATS.GetHistoryForTab, RSTATS, tabID)
            if ok and type(data) == "table" then
                return data
            end
        end
    end

    -- Fallback: direct tables
    return ({
        SoloShuffle = pdata.SoloShuffleHistory,
        ["2v2"] = pdata.v2History,
        ["3v3"] = pdata.v3History,
        RBG = pdata.RBGHistory,
        SoloRBG = pdata.SoloRBGHistory,
    })[modeKey]
end

local function GetArenaComps(entry)
    local friendly = {}
    local enemy = {}

    local teamFaction = entry.teamFaction
    if not teamFaction and type(entry.playerStats) == "table" and entry.playerStats[1] and entry.playerStats[1].faction then
        teamFaction = entry.playerStats[1].faction
    end

    if type(entry.playerStats) == "table" then
        for _, ps in ipairs(entry.playerStats) do
            if ps and ps.name and ps.name ~= "-" then
                local spec = ps.spec or ""
                local token = spec .. "-" .. ps.name
                if teamFaction and ps.faction == teamFaction then
                    table.insert(friendly, token)
                else
                    table.insert(enemy, token)
                end
            end
        end
    end

    table.sort(friendly)
    table.sort(enemy)

    return table.concat(friendly, ","), table.concat(enemy, ",")
end

local function BuildREFlexCSV(modeKey)
    local data = GetHistoryForExport(modeKey)
    if type(data) ~= "table" then
        return "Timestamp;Map;Duration;Victory;KillingBlows;HonorKills;Deaths;Damage;Healing;Honor;RatingChange;MMR;EnemyMMR;Specialization;PrestigeLevel;isRated;isBrawl;isMercenary\n"
    end

    local isBG = (modeKey == "RBG" or modeKey == "SoloRBG")

    local out = {}

    if isBG then
        table.insert(out, "Timestamp;Map;Duration;Victory;KillingBlows;HonorKills;Deaths;Damage;Healing;Honor;RatingChange;MMR;EnemyMMR;Specialization;PrestigeLevel;isRated;isBrawl;isMercenary\n")
        for _, entry in ipairs(data) do
            if type(entry) == "table" and not entry.isInitial then
                local ps = GetMyPlayerStat(entry)

                local ts = ToNumber(entry.timestamp or entry.endTime)
                local map = CleanCSVField(NormalizeMapName(entry.mapName or ""))

                local duration = GetDurationSeconds(entry)
                local victory = VictoryString(entry)

                local kb = ps and ToNumber(ps.killingBlows) or 0
                local hk = ps and ToNumber(ps.honorableKills) or 0
                local deaths = ps and ToNumber(ps.deaths) or 0
                local dmg = ps and ToNumber(ps.damage) or 0
                local heal = ps and ToNumber(ps.healing) or 0

                local honor = ToNumber(entry.honor)
                local ratingChange = ToNumber(ps and ps.ratingChange or entry.friendlyRatingChange)
                local mmr = ToNumber(entry.friendlyMMR or entry.mmr)
                local enemyMMR = ToNumber(entry.enemyMMR)

                local spec = CleanCSVField(entry.specName or "")
                local prestige = ToNumber(entry.prestigeLevel)

                local isRated = 1
                local isBrawl = 0
                local isMerc = 0

                table.insert(out,
                    ts .. ";" .. map .. ";" .. duration .. ";" .. victory .. ";" ..
                    kb .. ";" .. hk .. ";" .. deaths .. ";" .. dmg .. ";" .. heal .. ";" .. honor .. ";" ..
                    ratingChange .. ";" .. mmr .. ";" .. enemyMMR .. ";" .. spec .. ";" .. prestige .. ";" ..
                    isRated .. ";" .. isBrawl .. ";" .. isMerc .. "\n"
                )
            end
        end
    else
        table.insert(out, "Timestamp;Map;PlayersNumber;TeamComposition;EnemyComposition;Duration;Victory;KillingBlows;Damage;Healing;Honor;RatingChange;MMR;EnemyMMR;Specialization;isRated\n")
        local playersNum = ({ SoloShuffle = 6, ["2v2"] = 2, ["3v3"] = 3 })[modeKey] or 0

        for _, entry in ipairs(data) do
            if type(entry) == "table" and not entry.isInitial then
                local ps = GetMyPlayerStat(entry)

                local ts = ToNumber(entry.timestamp or entry.endTime)
                local map = CleanCSVField(NormalizeMapName(entry.mapName or ""))

                local teamComp, enemyComp = GetArenaComps(entry)

                local duration = GetDurationSeconds(entry)
                local victory = VictoryString(entry)

                local kb = ps and ToNumber(ps.killingBlows) or 0
                local dmg = ps and ToNumber(ps.damage) or 0
                local heal = ps and ToNumber(ps.healing) or 0

                local honor = ToNumber(entry.honor)
                local ratingChange = ToNumber(ps and ps.ratingChange or entry.friendlyRatingChange)
                local mmr = ToNumber(entry.friendlyMMR or entry.mmr)
                local enemyMMR = ToNumber(entry.enemyMMR)

                local spec = CleanCSVField(entry.specName or "")
                local isRated = 1

                table.insert(out,
                    ts .. ";" .. map .. ";" .. playersNum .. ";" .. CleanCSVField(teamComp) .. ";" .. CleanCSVField(enemyComp) .. ";" ..
                    duration .. ";" .. victory .. ";" .. kb .. ";" .. dmg .. ";" .. heal .. ";" .. honor .. ";" ..
                    ratingChange .. ";" .. mmr .. ";" .. enemyMMR .. ";" .. spec .. ";" .. isRated .. "\n"
                )
            end
        end
    end

    return table.concat(out)
end

local exportFrame
local selectedModeKey = "SoloShuffle"

local function EnsureExportFrame()
    if exportFrame then return end

    exportFrame = CreateFrame("Frame", "RatedStatsExportFrame", UIParent, "BasicFrameTemplateWithInset")
    exportFrame:SetSize(820, 560)
    exportFrame:SetPoint("CENTER")
    exportFrame:SetFrameStrata("DIALOG")
    exportFrame:Hide()

    exportFrame.TitleText:SetText("Rated Stats - Export Data (REFlex CSV)")

    -- Mode buttons (top row inside inset)
    local modes = {
        { key = "SoloShuffle", label = "SS" },
        { key = "2v2", label = "2v2" },
        { key = "3v3", label = "3v3" },
        { key = "RBG", label = "RBG" },
        { key = "SoloRBG", label = "SoloRBG" },
    }

    local prev
    exportFrame.ModeButtons = {}

    for i = 1, #modes do
        local m = modes[i]
        local b = CreateFrame("Button", nil, exportFrame, "UIPanelButtonTemplate")
        b:SetSize(74, 22)
        if prev then
            b:SetPoint("TOPLEFT", prev, "TOPRIGHT", 6, 0)
        else
            b:SetPoint("TOPLEFT", exportFrame.InsetBg, "TOPLEFT", 10, -8)
        end
        b:SetText(m.label)
        b:SetScript("OnClick", function()
            selectedModeKey = m.key
            if exportFrame and exportFrame.EditBox then
                exportFrame.EditBox:SetText(BuildREFlexCSV(selectedModeKey))
                exportFrame.EditBox:HighlightText()
            end
        end)
        exportFrame.ModeButtons[m.key] = b
        prev = b
    end

    local scroll = CreateFrame("ScrollFrame", nil, exportFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", exportFrame.InsetBg, "TOPLEFT", 8, -36)
    scroll:SetPoint("BOTTOMRIGHT", exportFrame.InsetBg, "BOTTOMRIGHT", -30, 10)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(760)
    edit:SetTextInsets(6, 6, 6, 6)
    edit:SetScript("OnEscapePressed", function() exportFrame:Hide() end)

    scroll:SetScrollChild(edit)
    exportFrame.EditBox = edit

    exportFrame:SetScript("OnShow", function()
        exportFrame.EditBox:SetText(BuildREFlexCSV(selectedModeKey))
        exportFrame.EditBox:HighlightText()
    end)

    exportFrame.EditBox:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            self:HighlightText()
        end
    end)
end

function RSTATS:OpenExportWindow()
    EnsureExportFrame()
    exportFrame:Show()
end

StaticPopupDialogs["RSTATS_CONFIRM_WIPE_DB"] = {
    text = "Wipe Rated Stats database for this character?\n\nThis cannot be undone.",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        if RSTATS and RSTATS.WipeDatabase then
            RSTATS:WipeDatabase()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function RSTATS:ConfirmWipeDatabase()
    StaticPopup_Show("RSTATS_CONFIRM_WIPE_DB")
end

function RSTATS:WipeDatabase()
    local key = GetPlayerKey()
    if not RSTATS_Database then
        RSTATS_Database = {}
    end

    RSTATS_Database[key] = {}

    if type(LoadData) == "function" then
        LoadData()
    end

    print("|cffb69e86Rated Stats:|r Database wiped for: " .. key)
    print("|cffb69e86Rated Stats:|r Recommendation: /reload")
end
