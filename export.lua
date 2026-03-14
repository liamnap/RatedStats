-- Rated Stats: Export / Wipe utilities
-- Export window provides REFlex-compatible CSV headings and lets users filter by bracket.
-- Headings + field semantics are taken from REFlex's DumpCSV() implementation.

local function GetPlayerKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

local function GetPlayerFullName()
    return UnitName("player") .. "-" .. GetRealmName()
end

local function ToNumber(v)
    local n = tonumber(v)
    if n then return n end
    return 0
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

-- Map export: match REFlex CSV "Map" column (numeric map ID)
local _mapCodeToID
local _mapNameToID

local function BuildMapLookups()
    if _mapCodeToID and _mapNameToID then return end
    _mapCodeToID = {}
    _mapNameToID = {}

    if type(RSTATS) == "table" and type(RSTATS.MapList) == "table" then
        for id, v in pairs(RSTATS.MapList) do
            if type(id) == "number" and type(v) == "table" then
                if v.code and v.code ~= "" then
                    _mapCodeToID[tostring(v.code)] = id
                end
                if v.name and v.name ~= "" then
                    _mapNameToID[tostring(v.name)] = id
                end
                if v.short and v.short ~= "" then
                    _mapNameToID[tostring(v.short)] = id
                end
            end
        end
    end
end

local function ResolveMapID(entry)
    if type(entry) ~= "table" then return 0 end
    local mapName = entry.mapName
    if mapName == nil then return 0 end

    -- Already numeric?
    local n = tonumber(mapName)
    if n then return n end

    BuildMapLookups()

    local key = tostring(mapName)

    -- 1) Arena code match (NPG/EC/TR/COC/etc)
    local id = _mapCodeToID[key]
    if id then return id end

    -- 2) Full name match (BGs tend to store full names)
    id = _mapNameToID[key]
    if id then return id end

    -- 3) If mapShortCodes exists (FullName -> ShortCode), expand ShortCode back to FullName then map.
    if type(mapShortCodes) == "table" then
        for full, short in pairs(mapShortCodes) do
            if tostring(short) == key then
                id = _mapNameToID[tostring(full)]
                if id then return id end
                break
            end
        end
    end

    return 0
end

local function GetMapExportValue(entry)
    local id = ResolveMapID(entry)
    if not id or id <= 0 then
        return "0"
    end
    return tostring(id)
end

local function ParseDurationStringToSeconds(s)
    if type(s) ~= "string" then return nil end

    -- Handle "MM:SS" / "HH:MM:SS"
    if s:match("^%d+:%d+:%d+$") then
        local h, m, sec = s:match("^(%d+):(%d+):(%d+)$")
        if h and m and sec then
            return (tonumber(h) * 3600) + (tonumber(m) * 60) + tonumber(sec)
        end
    elseif s:match("^%d+:%d+$") then
        local m, sec = s:match("^(%d+):(%d+)$")
        if m and sec then
            return (tonumber(m) * 60) + tonumber(sec)
        end
    end

    -- Handle Blizzard SecondsToTime style: "1 Hr 2 Min 3 Sec" / "2 Min 10 Sec" / "45 Sec"
    local lower = s:lower()
    local h = lower:match("(%d+)%s*hr") or lower:match("(%d+)%s*hour")
    local m = lower:match("(%d+)%s*min")
    local sec = lower:match("(%d+)%s*sec")

    if h or m or sec then
        local total = 0
        if h then total = total + (tonumber(h) * 3600) end
        if m then total = total + (tonumber(m) * 60) end
        if sec then total = total + tonumber(sec) end
        if total > 0 then return total end
    end

    return nil
end

local function GetDurationSeconds(entry)
    if type(entry) ~= "table" then return 0 end

    -- Prefer numeric fields first
    local d =
        tonumber(entry.durationSeconds) or
        tonumber(entry.durationSec) or
        tonumber(entry.matchDuration) or
        tonumber(entry.durationRaw)

    if not d then
        if type(entry.duration) == "number" then
            d = entry.duration
        elseif type(entry.duration) == "string" then
            d = ParseDurationStringToSeconds(entry.duration)
        end
    end

    d = tonumber(d)
    if not d or d <= 0 then return 0 end

    -- Some APIs return ms; matches will never be > 60,000 seconds, so treat big numbers as ms.
    if d > 60000 then d = d / 1000 end
    return math.floor(d + 0.5)
end

local function VictoryString(modeKey, entry)
    -- REFlex uses tostring(boolean) => "true"/"false", and for Solo Shuffle returns nil => "nil".
    if modeKey == "SoloShuffle" then
        return "nil"
    end

    local wl = (type(entry) == "table" and (entry.friendlyWinLoss or entry.winLoss))
    if wl == "W" then return "true" end
    if wl == "L" then return "false" end

    -- If it isn't W/L (e.g. "I"/"Initial"), REFlex doesn't have that concept; treat as false.
    return "false"
end


local function GetSpecString(entry, s)
    local spec = (s and s.spec) or (type(entry) == "table" and entry.specName) or ""
    return tostring(spec or "")
end

local function GetMyPlayerStat(entry)
    if type(entry) ~= "table" or type(entry.playerStats) ~= "table" then return nil end

    local myGUID = UnitGUID("player")
    local myName = GetPlayerFullName()

    -- 1) Exact GUID match
    if myGUID then
        for _, p in ipairs(entry.playerStats) do
            if type(p) == "table" and p.guid and p.guid == myGUID then
                return p
            end
        end
    end

    -- 2) Exact Name-Realm match
    for _, p in ipairs(entry.playerStats) do
        if type(p) == "table" and p.name and p.name == myName then
            return p
        end
    end

    -- 3) First friendly (best-effort)
    for _, p in ipairs(entry.playerStats) do
        if type(p) == "table" and p.isFriendly then
            return p
        end
    end

    return entry.playerStats[1]
end

local function ClassNameToToken(className)
    if not className or className == "" then return "" end

    -- Invert Blizzard tables (localized -> token)
    if type(LOCALIZED_CLASS_NAMES_MALE) == "table" then
        for token, loc in pairs(LOCALIZED_CLASS_NAMES_MALE) do
            if loc == className then return token end
        end
    end
    if type(LOCALIZED_CLASS_NAMES_FEMALE) == "table" then
        for token, loc in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do
            if loc == className then return token end
        end
    end

    -- Last resort: return whatever we have
    return tostring(className)
end

local function BuildArenaTeamCSV(entry, wantFriendly)
    -- Match REFlex format: "CLASS-SPEC-NAME" comma-separated, sorted.
    if type(entry) ~= "table" or type(entry.playerStats) ~= "table" then return "" end

    local out = {}

    -- Prefer explicit team indices for non-SS arenas/BGs
    local haveTeamIndex = (entry.myTeamIndex ~= nil)

    for _, p in ipairs(entry.playerStats) do
        if type(p) == "table" and p.name and p.name ~= "-" then
            local isFriendly

            if p.isFriendly ~= nil then
                isFriendly = p.isFriendly
            elseif haveTeamIndex and p.teamIndex ~= nil then
                isFriendly = (p.teamIndex == entry.myTeamIndex)
            else
                isFriendly = false
            end

            local pick = wantFriendly and isFriendly or (not wantFriendly and not isFriendly)
            if pick then
                local classToken = ClassNameToToken(p.class)
                local specName = tostring(p.spec or "")
                local name = tostring(p.name)
                table.insert(out, classToken .. "-" .. specName .. "-" .. name)
            end
        end
    end

    table.sort(out)
    return table.concat(out, ",")
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

    -- Reuse the addon helper for spec-aware history (SS / SoloRBG) when available.
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


local function IsInitialEntry(entry)
    if type(entry) ~= "table" then return true end
    if entry.isInitial then return true end
    if entry.matchType == "Initial" then return true end
    if entry.map == "Initial" then return true end
    if entry.bracket == "Initial" then return true end
    return false
end
local function GetFilteredEntries(modeKey, specFilter)
    local data = GetHistoryForExport(modeKey)
    if type(data) ~= "table" then return nil end

    local out = {}
    for _, entry in ipairs(data) do
        if type(entry) == "table" and not IsInitialEntry(entry) then
            local s = GetMyPlayerStat(entry)
            local specRaw = GetSpecString(entry, s)
            if not specFilter or specFilter == "ALL" or specRaw == specFilter then
                table.insert(out, entry)
            end
        end
    end
    return out
end

local function HasRows(modeKey, specFilter)
    local data = GetFilteredEntries(modeKey, specFilter)
    return (type(data) == "table" and #data > 0)
end

local function GetSpecsForMode(modeKey)
    local data = GetFilteredEntries(modeKey, "ALL")
    local seen = {}
    local specs = {}
    if type(data) == "table" then
        for _, entry in ipairs(data) do
            local s = GetMyPlayerStat(entry)
            local specRaw = GetSpecString(entry, s)
            if specRaw and specRaw ~= "" and not seen[specRaw] then
                seen[specRaw] = true
                table.insert(specs, specRaw)
            end
        end
    end
    table.sort(specs)
    return specs
end


local function BuildREFlexCSV(modeKey, specFilter)
    local data = GetHistoryForExport(modeKey)

    -- Headers are EXACTLY what REFlex writes in DumpCSV().
    local headerBG = "Timestamp;Map;Duration;Victory;KillingBlows;HonorKills;Deaths;Damage;Healing;Honor;RatingChange;MMR;EnemyMMR;Specialization;PrestigeLevel;isRated;isBrawl;isMercenary\n"
    local headerArena = "Timestamp;Map;PlayersNumber;TeamComposition;EnemyComposition;Duration;Victory;KillingBlows;Damage;Healing;Honor;RatingChange;MMR;EnemyMMR;Specialization;isRated\n"

    if type(data) ~= "table" then
        -- Return a valid header even if there is no data.
        if modeKey == "RBG" or modeKey == "SoloRBG" then
            return headerBG
        else
            return headerArena
        end
    end

    local isBG = (modeKey == "RBG" or modeKey == "SoloRBG")
    local out = {}

    if isBG then
        table.insert(out, headerBG)

        for _, entry in ipairs(data) do
            if type(entry) == "table" and not IsInitialEntry(entry) then
                local s = GetMyPlayerStat(entry)

                local specRaw = GetSpecString(entry, s)
                local okSpec = (not specFilter) or (specFilter == "ALL") or (specRaw == specFilter)
                if okSpec then

                local ts = ToNumber(entry.timestamp or entry.endTime)
                local map = CleanCSVField(GetMapExportValue(entry))
                local duration = GetDurationSeconds(entry)

                local victory = VictoryString(modeKey, entry)

                local kb = s and ToNumber(s.killingBlows) or 0
                local hk = s and ToNumber(s.honorableKills) or 0
                local deaths = s and ToNumber(s.deaths) or 0
                local dmg = s and ToNumber(s.damage) or 0
                local heal = s and ToNumber(s.healing) or 0

                -- Rated Stats does not currently store honor gained as a per-match field like REFlex.
                local honor = 0

                local ratingChange = s and ToNumber(s.ratingChange) or 0

                -- REFlex prints 0 if not rated; we always export numeric.
                local mmr = ToNumber(entry.friendlyMMR)
                local enemyMMR = ToNumber(entry.enemyMMR)

                local spec = CleanCSVField(s and s.spec or entry.specName or "")
                local prestige = s and ToNumber(s.honorLevel) or 0

                -- We do not track brawls/mercenary in Rated Stats history currently.
                local isRated = "true"
                local isBrawl = "false"
                local isMerc = "false"

                table.insert(out,
                    ts .. ";" .. map .. ";" .. duration .. ";" .. victory .. ";" ..
                    kb .. ";" .. hk .. ";" .. deaths .. ";" .. dmg .. ";" .. heal .. ";" .. honor .. ";" ..
                    ratingChange .. ";" .. mmr .. ";" .. enemyMMR .. ";" .. spec .. ";" .. prestige .. ";" ..
                    isRated .. ";" .. isBrawl .. ";" .. isMerc .. "\n"
                )
                end
            end
        end
    else
        table.insert(out, headerArena)

        -- REFlex uses d.PlayersNum (2/3). It does NOT export Solo Shuffle at all.
        -- We still allow SS export for your filter buttons; PlayersNumber is set to 6 and Victory is "nil".
        local playersNum = ({ SoloShuffle = 6, ["2v2"] = 2, ["3v3"] = 3 })[modeKey] or 0

        for _, entry in ipairs(data) do
            if type(entry) == "table" and not IsInitialEntry(entry) then
                local s = GetMyPlayerStat(entry)

                local specRaw = GetSpecString(entry, s)
                local okSpec = (not specFilter) or (specFilter == "ALL") or (specRaw == specFilter)
                if okSpec then

                local ts = ToNumber(entry.timestamp or entry.endTime)
                local map = CleanCSVField(GetMapExportValue(entry))

                local teamComp = BuildArenaTeamCSV(entry, true)
                local enemyComp = BuildArenaTeamCSV(entry, false)

                local duration = GetDurationSeconds(entry)
                local victory = VictoryString(modeKey, entry)

                local kb = s and ToNumber(s.killingBlows) or 0
                local dmg = s and ToNumber(s.damage) or 0
                local heal = s and ToNumber(s.healing) or 0

                -- Rated Stats does not currently store honor gained as a per-match field like REFlex.
                local honor = 0

                local ratingChange = s and ToNumber(s.ratingChange) or 0
                local mmr = ToNumber(entry.friendlyMMR)
                local enemyMMR = ToNumber(entry.enemyMMR)

                local spec = CleanCSVField(s and s.spec or entry.specName or "")
                local isRated = "true"

                table.insert(out,
                    ts .. ";" .. map .. ";" .. playersNum .. ";" .. CleanCSVField(teamComp) .. ";" .. CleanCSVField(enemyComp) .. ";" ..
                    duration .. ";" .. victory .. ";" .. kb .. ";" .. dmg .. ";" .. heal .. ";" .. honor .. ";" ..
                    ratingChange .. ";" .. mmr .. ";" .. enemyMMR .. ";" .. spec .. ";" .. isRated .. "\n"
                )
                end
            end
        end
    end

    return table.concat(out)
end

local exportFrame
local selectedModeKey = "SoloShuffle"
local selectedSpecKey = "ALL"

local function EnsureExportFrame()
    if exportFrame then return end

    exportFrame = CreateFrame("Frame", "RatedStatsExportFrame", UIParent, "BasicFrameTemplateWithInset")
    exportFrame:SetSize(820, 560)
    exportFrame:SetPoint("CENTER")
    exportFrame:SetFrameStrata("DIALOG")
    exportFrame:Hide()

    exportFrame.TitleText:SetText("Rated Stats - Export Data (REFlex CSV)")

    -- Spec buttons (row 1) + Mode buttons (row 2)
    local modes = {
        { key = "SoloShuffle", label = "SS" },
        { key = "2v2", label = "2v2" },
        { key = "3v3", label = "3v3" },
        { key = "RBG", label = "RBG" },
        { key = "SoloRBG", label = "SoloRBG" },
    }

    local function SetButtonGrey(b, grey)
        if not b then return end
        if grey then
            b:SetAlpha(0.40)
            b:SetEnabled(true)
        else
            b:SetAlpha(1.0)
            b:SetEnabled(true)
        end
    end

    local function RefreshExportText()
        if exportFrame and exportFrame.EditBox then
            exportFrame.EditBox:SetText(BuildREFlexCSV(selectedModeKey, selectedSpecKey))
            exportFrame.EditBox:HighlightText()
        end
    end

    local function RebuildSpecButtons()
        if not exportFrame then return end
        exportFrame.SpecButtons = exportFrame.SpecButtons or {}

        -- Hide old buttons
        for _, b in ipairs(exportFrame.SpecButtons) do
            b:Hide()
            b:SetParent(nil)
        end
        wipe(exportFrame.SpecButtons)

        local specs = GetSpecsForMode(selectedModeKey)
        local labels = { { key = "ALL", label = "All" } }
        for _, specName in ipairs(specs) do
            table.insert(labels, { key = specName, label = specName })
        end

        local prev
        for i = 1, #labels do
            local sp = labels[i]
            local b = CreateFrame("Button", nil, exportFrame, "UIPanelButtonTemplate")
            b:SetSize(120, 22)
            if prev then
                b:SetPoint("TOPLEFT", prev, "TOPRIGHT", 6, 0)
            else
                b:SetPoint("TOPLEFT", exportFrame.InsetBg, "TOPLEFT", 10, -8)
            end
            b:SetText(sp.label)
            b:SetScript("OnClick", function()
                selectedSpecKey = sp.key
                RefreshExportText()
                if exportFrame.UpdateButtonStates then exportFrame.UpdateButtonStates() end
            end)
            table.insert(exportFrame.SpecButtons, b)
            prev = b
        end
    end

    local prev
    exportFrame.ModeButtons = {}

    for i = 1, #modes do
        local m = modes[i]
        local b = CreateFrame("Button", nil, exportFrame, "UIPanelButtonTemplate")
        b:SetSize(74, 22)
        if prev then
            b:SetPoint("TOPLEFT", prev, "TOPRIGHT", 6, 0)
        else
            -- Mode row is below spec buttons row
            b:SetPoint("TOPLEFT", exportFrame.InsetBg, "TOPLEFT", 10, -34)
        end
        b:SetText(m.label)
        b:SetScript("OnClick", function()
            selectedModeKey = m.key
            -- When changing mode, rebuild spec list (spec availability differs per bracket)
            selectedSpecKey = "ALL"
            RebuildSpecButtons()
            RefreshExportText()
            if exportFrame.UpdateButtonStates then exportFrame.UpdateButtonStates() end
        end)
        exportFrame.ModeButtons[m.key] = b
        prev = b
    end

    local function UpdateButtonStates()
        -- Grey out mode buttons that have no rows for the selected spec
        for _, m in ipairs(modes) do
            local b = exportFrame.ModeButtons[m.key]
            SetButtonGrey(b, not HasRows(m.key, selectedSpecKey))
        end

        -- Grey out spec buttons that have no rows for the selected mode
        if exportFrame.SpecButtons then
            for _, b in ipairs(exportFrame.SpecButtons) do
                local label = b:GetText()
                local key = (label == "All") and "ALL" or label
                SetButtonGrey(b, not HasRows(selectedModeKey, key))
            end
        end
    end

    exportFrame.UpdateButtonStates = UpdateButtonStates
    exportFrame.RebuildSpecButtons = RebuildSpecButtons
    exportFrame.RefreshExportText = RefreshExportText

    RebuildSpecButtons()
    UpdateButtonStates()

    local scroll = CreateFrame("ScrollFrame", nil, exportFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", exportFrame.InsetBg, "TOPLEFT", 8, -62)
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
        if exportFrame.RebuildSpecButtons then exportFrame.RebuildSpecButtons() end
        if exportFrame.UpdateButtonStates then exportFrame.UpdateButtonStates() end
        if exportFrame.RefreshExportText then exportFrame.RefreshExportText() end
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
