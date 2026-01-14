-- summary.lua

local _, RSTATS = ...

RSTATS.Summary = RSTATS.Summary or {}
local Summary = RSTATS.Summary

local Stats = _G.RSTATS_STATS

local BRACKETS = {
    {
        tabID = 1,
        name = "Solo Shuffle",
        bracketID = 7,
        historyKey = "SoloShuffleHistory",
        crKey = "CurrentCRforSoloShuffle",
        mmrKey = "CurrentMMRforSoloShuffle",
    },
    {
        tabID = 2,
        name = "2v2",
        bracketID = 1,
        historyKey = "v2History",
        crKey = "CurrentCRfor2v2",
        mmrKey = "CurrentMMRfor2v2",
    },
    {
        tabID = 3,
        name = "3v3",
        bracketID = 2,
        historyKey = "v3History",
        crKey = "CurrentCRfor3v3",
        mmrKey = "CurrentMMRfor3v3",
    },
    {
        tabID = 4,
        name = "RBG",
        bracketID = 4,
        historyKey = "RBGHistory",
        crKey = "CurrentCRforRBG",
        mmrKey = "CurrentMMRforRBG",
    },
    {
        tabID = 5,
        name = "Solo RBG",
        bracketID = 9,
        historyKey = "SoloRBGHistory",
        crKey = "CurrentCRforSoloRBG",
        mmrKey = "CurrentMMRforSoloRBG",
    },
}

local function GetDB()
    return _G.RSTATS_Database or RSTATS.Database
end

local function GetPlayerFullName()
    return UnitName("player") .. "-" .. GetRealmName()
end

local function SafeNumber(v)
    v = tonumber(v)
    if not v then return 0 end
    return v
end

local function SortByEndTime(a, b)
    return (a.endTime or a.timestamp or 0) < (b.endTime or b.timestamp or 0)
end

local function GetLast25CRDelta(history)
    if not history or #history == 0 then return 0, 0 end
    table.sort(history, SortByEndTime)
    local n = #history
    local start = math.max(1, n - 25 + 1)
    local delta = 0
    local counted = 0
    local me = GetPlayerFullName()
    for i = start, n do
        local m = history[i]
        for _, ps in ipairs(m.playerStats or {}) do
            if ps.name == me then
                delta = delta + SafeNumber(ps.ratingChange)
                counted = counted + 1
                break
            end
        end
    end
    return delta, counted
end

--
-- Sparkline (pure Blizzard API): uses Frame:CreateLine() segments.
--
local function ClearSpark(frame)
    if frame._lines then
        for _, l in ipairs(frame._lines) do
            l:Hide()
        end
    end
    frame._lines = {}
end

local function DrawSpark(frame, values, yMinFixed, yMaxFixed)
    ClearSpark(frame)

    if not values or #values < 2 then
        return
    end

    local w = frame:GetWidth() or 0
    local h = frame:GetHeight() or 0
    if w <= 1 or h <= 1 then
        return
    end

    local yMin, yMax
    if yMinFixed ~= nil and yMaxFixed ~= nil then
        yMin, yMax = yMinFixed, yMaxFixed
    else
        yMin, yMax = math.huge, -math.huge
        for i = 1, #values do
            local v = values[i]
            if v ~= nil then
                if v < yMin then yMin = v end
                if v > yMax then yMax = v end
            end
        end
        if yMin == math.huge then
            yMin, yMax = 0, 1
        end
    end

    if yMax == yMin then
        yMax = yMin + 1
    end

    local n = #values
    local xStep = w / (n - 1)

    local function mapY(v)
        local t = (v - yMin) / (yMax - yMin)
        if t < 0 then t = 0 end
        if t > 1 then t = 1 end
        local y = t * h
        if y < 1 then y = 1 end
        return y
    end

    for i = 1, n - 1 do
        local v1 = values[i]
        local v2 = values[i + 1]
        if v1 ~= nil and v2 ~= nil then
            local x1, x2 = (i - 1) * xStep, i * xStep
            local y1, y2 = mapY(v1), mapY(v2)

            local line = frame:CreateLine(nil, "ARTWORK")
            line:SetThickness(1.5)
            line:SetColorTexture(1, 0.82, 0.2, 0.95) -- gold
            line:SetStartPoint("BOTTOMLEFT", frame, x1, y1)
            line:SetEndPoint("BOTTOMLEFT", frame, x2, y2)
            table.insert(frame._lines, line)
        end
    end

    return yMin, yMax
end

local function Downsample(values, times, maxPoints)
    local n = values and #values or 0
    if n <= maxPoints then return values, times end
    if maxPoints < 2 then maxPoints = 2 end

    local outV, outT = {}, {}
    local step = (n - 1) / (maxPoints - 1)
    for i = 1, maxPoints do
        local idx = math.floor((i - 1) * step + 1.5)
        if idx < 1 then idx = 1 end
        if idx > n then idx = n end
        outV[i] = values[idx]
        outT[i] = times and times[idx] or nil
    end
    return outV, outT
end

-- Build per-season-week series.
-- 1) wins: winrate% per week (0..100)
-- 2) cr: cumulative CR delta across weeks
-- 3) mmr: cumulative MMR delta across weeks
--
local function BuildSeasonMatchSeries(history)
    if not history or #history == 0 then
        return {}, {}, {}, {}
    end

    local seasonStart = RSTATS:GetCurrentSeasonStart()
    local seasonFinish = RSTATS:GetCurrentSeasonFinish()
    if not seasonStart or not seasonFinish then
        return {}, {}, {}, {}
    end

    local playerName = GetPlayerFullName()

    table.sort(history, SortByEndTime)

    local winsSeries, crSeries, mmrSeries, times = {}, {}, {}, {}
    local winsCum = 0

    for _, match in ipairs(history) do
        local t = match.endTime or match.timestamp
        if t and t >= seasonStart and t < seasonFinish then
            local wl = match.friendlyWinLoss or ""
            if wl:find("W") then winsCum = winsCum + 1 end

            local cr = tonumber(match.cr)
            local mmr = tonumber(match.mmr)

            if match.playerStats then
                for _, ps in ipairs(match.playerStats) do
                    if ps.name == playerName then
                        cr  = tonumber(ps.newrating) or cr
                        mmr = tonumber(ps.postmatchMMR) or mmr
                        break
                    end
                end
            end

            table.insert(times, t)
            table.insert(winsSeries, winsCum)
            table.insert(crSeries, cr or 0)
            table.insert(mmrSeries, mmr or 0)
        end
    end

    return winsSeries, crSeries, mmrSeries, times
end

local function CreateBackdrop(frame)
    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.45)
end

-- Render the currently selected graph mode on a card.
function Summary:_RenderCardGraph(card)
    if not card or not card._data or not card.spark then return end

    local data = card._data
    local mode = card._graphMode or 1
    local w = card.spark:GetWidth() or 0
    local maxPoints = math.floor(w / 6)
    if maxPoints < 2 then maxPoints = 2 end

    local series, times

    if mode == 1 then
        card.sparkLabel:SetText("Wins")
        series, times = Downsample(data.seriesWins or {}, data.seriesTimes or {}, maxPoints)
    elseif mode == 2 then
        card.sparkLabel:SetText("CR +/-")
        series, times = Downsample(data.seriesCR or {}, data.seriesTimes or {}, maxPoints)
    else
        card.sparkLabel:SetText("MMR +/-")
        series, times = Downsample(data.seriesMMR or {}, data.seriesTimes or {}, maxPoints)
    end

    local yMin, yMax = DrawSpark(card.spark, series or {})
    if card.axisYMin then card.axisYMin:SetText(yMin and tostring(math.floor(yMin)) or "") end
    if card.axisYMax then card.axisYMax:SetText(yMax and tostring(math.floor(yMax)) or "") end

    if times and #times >= 1 then
        local t1, t2 = times[1], times[#times]
        if card.axisXStart then card.axisXStart:SetText(t1 and date("%d %b", t1) or "") end
        if card.axisXEnd then card.axisXEnd:SetText(t2 and date("%d %b", t2) or "") end
    else
        if card.axisXStart then card.axisXStart:SetText("") end
        if card.axisXEnd then card.axisXEnd:SetText("") end
    end

end

function Summary:_StartAutoCycle()
    if self._autoCycleStarted then return end
    self._autoCycleStarted = true

    C_Timer.NewTicker(2.0, function()
        if not self.frame or not self.frame:IsShown() then return end
        if not self.frame.cards then return end
        for _, card in ipairs(self.frame.cards) do
            if card and card:IsShown() and card._data then
                card._graphMode = (card._graphMode % 3) + 1
                self:_RenderCardGraph(card)
            end
        end
    end)
end

local function CreateBracketCard(parent)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    CreateBackdrop(card)

    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -8)
    card.title:SetFont(GetUnicodeSafeFont(), 12, "OUTLINE")

    card.matchesText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.matchesText:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -6)
    card.matchesText:SetFont(GetUnicodeSafeFont(), 10, "OUTLINE")

    card.crText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.crText:SetPoint("TOPLEFT", card.matchesText, "BOTTOMLEFT", 0, -2)
    card.crText:SetFont(GetUnicodeSafeFont(), 11, "OUTLINE")

    card.mmrText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.mmrText:SetPoint("TOPLEFT", card.crText, "BOTTOMLEFT", 0, -2)
    card.mmrText:SetFont(GetUnicodeSafeFont(), 11, "OUTLINE")

    card.winrateText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.winrateText:SetPoint("TOPLEFT", card.mmrText, "BOTTOMLEFT", 0, -6)
    card.winrateText:SetFont(GetUnicodeSafeFont(), 10, "OUTLINE")

    -- Single sparkline strip (matches your mock layout).
    card.sparkLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.sparkLabel:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 52)
    card.sparkLabel:SetFont(GetUnicodeSafeFont(), 9, "OUTLINE")
    card.sparkLabel:SetText("Wins")

    card.spark = CreateFrame("Frame", nil, card, "BackdropTemplate")
    card.spark:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 28)
    card.spark:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 28)
    card.spark:SetHeight(30)
    if card.spark.SetBackdrop then
        card.spark:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
        card.spark:SetBackdropColor(0, 0, 0, 0.25)
    end
    card.spark._lines = {}

    -- Simple axes (compact): Y min/max on left, X start/end dates under spark
    card.axisYMax = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.axisYMax:SetPoint("TOPLEFT", card.spark, "TOPLEFT", -6, 6)
    card.axisYMax:SetFont(GetUnicodeSafeFont(), 8, "OUTLINE")
    card.axisYMax:SetJustifyH("RIGHT")

    card.axisYMin = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.axisYMin:SetPoint("BOTTOMLEFT", card.spark, "BOTTOMLEFT", -6, -6)
    card.axisYMin:SetFont(GetUnicodeSafeFont(), 8, "OUTLINE")
    card.axisYMin:SetJustifyH("RIGHT")

    card.axisXStart = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.axisXStart:SetPoint("TOPLEFT", card.spark, "BOTTOMLEFT", 0, -2)
    card.axisXStart:SetFont(GetUnicodeSafeFont(), 8, "OUTLINE")

    card.axisXEnd = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.axisXEnd:SetPoint("TOPRIGHT", card.spark, "BOTTOMRIGHT", 0, -2)
    card.axisXEnd:SetFont(GetUnicodeSafeFont(), 8, "OUTLINE")
    card.axisXEnd:SetJustifyH("RIGHT")

        -- Graphs often draw "too early" (spark has 0 width/height) on first open.
    -- Redraw once the frame is actually sized and shown.
    if not card._sparkHooks then
        card._sparkHooks = true

        card.spark:SetScript("OnShow", function()
            if card._data and Summary and Summary._RenderCardGraph then
                C_Timer.After(0, function()
                    if card.spark and card.spark:GetWidth() > 2 and card.spark:GetHeight() > 2 then
                        Summary:_RenderCardGraph(card)
                    end
                end)
            end
        end)

        card.spark:SetScript("OnSizeChanged", function()
            if card._data and Summary and Summary._RenderCardGraph then
                if card.spark:GetWidth() > 2 and card.spark:GetHeight() > 2 then
                    Summary:_RenderCardGraph(card)
                end
            end
        end)
    end

    card.footerLeft = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.footerLeft:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 2)
    card.footerLeft:SetFont(GetUnicodeSafeFont(), 9, "OUTLINE")
    card.footerLeft:SetText("")

    card.footerRight = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.footerRight:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 2)
    card.footerRight:SetFont(GetUnicodeSafeFont(), 9, "OUTLINE")
    card.footerRight:SetText("")

    -- Which graph this card is currently showing:
    -- 1 = Wins (season-week wins)
    -- 2 = CR +/- (cumulative)
    -- 3 = MMR +/- (cumulative)
    card._graphMode = 1

    function card:SetData(data)
        self.title:SetText(data.name)
        self.matchesText:SetText(string.format("Matches: %d", SafeNumber(data.matches)))
        self.crText:SetText(string.format("Current CR: %d", SafeNumber(data.currentCR)))
        self.mmrText:SetText(string.format("Current MMR: %d", SafeNumber(data.currentMMR)))
        self.winrateText:SetText(string.format("Winrate: %d%% (%d/%d/%d)", data.winrate or 0, data.win or 0, data.loss or 0, data.draw or 0))

        self._data = data

        self.footerLeft:SetText(data.seasonWeekText or "")
        self.footerRight:SetText(data.last25Text or "")

        -- Click on a card to cycle the graph (Wins -> CR -> MMR).
        if not self._graphOnClickHooked then
            self._graphOnClickHooked = true
            self:EnableMouse(true)
            self:SetScript("OnMouseDown", function()
                self._graphMode = (self._graphMode % 3) + 1
                if Summary and Summary._RenderCardGraph then
                    Summary:_RenderCardGraph(self)
                end
            end)
        end

        C_Timer.After(0, function()
            if Summary and Summary._RenderCardGraph then
                Summary:_RenderCardGraph(self)
            end
        end)
    end

    return card
end

function Summary:Create(parentFrame)
    if self.frame then
        self.frame:Show()
        return
    end

    local f = CreateFrame("Frame", "RatedStatsSummaryFrame", parentFrame)
    f:SetAllPoints(parentFrame)
    self.frame = f

    local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOP", f, "TOP", 0, -10)
    header:SetFont(GetUnicodeSafeFont(), 16, "OUTLINE")
    header:SetText("PvP Summary")
    f.header = header

    f.cards = {}

    -- Layout: 5 cards across (same idea as your mock). If the window is narrow, they will still fit but be tighter.
    local padding = 12
    local totalW = parentFrame:GetWidth() > 0 and parentFrame:GetWidth() or 1000
    local cardW = math.floor((totalW - (padding * 6)) / 5)
    local cardH = 160

    for i = 1, #BRACKETS do
        local card = CreateBracketCard(f)
        card:SetSize(cardW, cardH)
        if i == 1 then
            card:SetPoint("TOPLEFT", f, "TOPLEFT", padding, -44)
        else
            card:SetPoint("LEFT", f.cards[i - 1], "RIGHT", padding, 0)
        end
        f.cards[i] = card
    end

    -- Overall Highlights panel (bottom half)
    f.highlights = CreateFrame("Frame", nil, f, "BackdropTemplate")
    CreateBackdrop(f.highlights)
    f.highlights:SetPoint("TOPLEFT", f.cards[1], "BOTTOMLEFT", 0, -14)
    f.highlights:SetPoint("TOPRIGHT", f.cards[#f.cards], "BOTTOMRIGHT", 0, -14)
    f.highlights:SetHeight(90)

    f.highTitle = f.highlights:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.highTitle:SetPoint("TOP", f.highlights, "TOP", 0, -6)
    f.highTitle:SetFont(GetUnicodeSafeFont(), 14, "OUTLINE")
    f.highTitle:SetText("Overall Highlights")

    f.highLines = {}
    for i = 1, 6 do
        local fs = f.highlights:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetFont(GetUnicodeSafeFont(), 12, "OUTLINE")
        f.highLines[i] = fs
    end

    -- 2 rows of 3 (like your mock)
    f.highLines[1]:SetPoint("TOPLEFT", f.highlights, "TOPLEFT", 14, -34)
    f.highLines[2]:SetPoint("LEFT", f.highLines[1], "RIGHT", 220, 0)
    f.highLines[3]:SetPoint("LEFT", f.highLines[2], "RIGHT", 220, 0)

    f.highLines[4]:SetPoint("TOPLEFT", f.highLines[1], "BOTTOMLEFT", 0, -10)
    f.highLines[5]:SetPoint("LEFT", f.highLines[4], "RIGHT", 220, 0)
    f.highLines[6]:SetPoint("LEFT", f.highLines[5], "RIGHT", 220, 0)

    -- Start auto-cycling the per-card graphs (optional but looks good)
    self:_StartAutoCycle()

	-- First open: DB/current CR/MMR values may not be ready yet.
	-- Run a delayed refresh so text/sparklines populate without needing a tab switch.
	if not self._initialRefreshQueued then
		self._initialRefreshQueued = true
		C_Timer.After(0.10, function()
			if Summary and Summary.Refresh then
				Summary:Refresh()
			end
		end)
	end
end

function Summary:Refresh()
    if not self.frame or not self.frame.cards then return end

    local Database = GetDB() or {}
    local playerKey = GetPlayerFullName()
    local perChar = Database[playerKey] or {}

    -- overall aggregates (across all brackets, this season)
    local overallSeasonMatches = {}
    local overallWinsByDay = {}
    local totalKBs = 0
    local longestStreak = 0
    local currentStreak = 0
    local seasonStart = RSTATS:GetCurrentSeasonStart()
    local seasonFinish = RSTATS:GetCurrentSeasonFinish()
    local me = GetPlayerFullName()

    for i, bracket in ipairs(BRACKETS) do
        local history = perChar[bracket.historyKey] or {}
        local seasonMatches = {}

        if seasonStart and seasonFinish then
            for _, m in ipairs(history) do
                if m.endTime and m.endTime >= seasonStart and m.endTime < seasonFinish then
                    table.insert(seasonMatches, m)
                    table.insert(overallSeasonMatches, m)
                end
            end
        end

        -- Use existing stats engine for win/loss/draw + winrate
        local summary = Stats and Stats.CalculateSummary(seasonMatches, history, bracket.bracketID) or {
            win = 0, loss = 0, draw = 0, winrate = 0,
        }

        -- Build the 3 graph series (this was missing, so graphs never draw)
        local winsSeries, crSeries, mmrSeries, times = BuildSeasonMatchSeries(history)

        local last25Delta, last25Count = GetLast25CRDelta(history)

        local last25Text = ""
        if last25Count > 0 then last25Text = string.format("%d games  %+d", last25Count, last25Delta) end

        local cardData = {
            name = bracket.name,
            currentCR = perChar[bracket.crKey] or 0,
            currentMMR = perChar[bracket.mmrKey] or 0,

            win = summary.win or 0,
            loss = summary.loss or 0,
            draw = summary.draw or 0,
            winrate = summary.winrate or 0,
            matches = (summary.win or 0) + (summary.loss or 0) + (summary.draw or 0),

            seriesWins = winsSeries,
            seriesCR = crSeries,
            seriesMMR = mmrSeries,
            seriesTimes = times,

            seasonWeekText = seasonWeekText,
            last25Text = last25Text,
        }

        self.frame.cards[i]:SetData(cardData)
    end

    -- Overall Highlights (placement-safe, no "highest gain" nonsense)
    if self.frame.highLines and #overallSeasonMatches > 0 then
        table.sort(overallSeasonMatches, SortByEndTime)

        for _, m in ipairs(overallSeasonMatches) do
            local wl = m.friendlyWinLoss or ""
            local isWin = wl:find("W") ~= nil
            if isWin then
                currentStreak = currentStreak + 1
                if currentStreak > longestStreak then longestStreak = currentStreak end
            else
                currentStreak = 0
            end

            if m.endTime then
                local dayKey = date("%Y-%m-%d", m.endTime)
                overallWinsByDay[dayKey] = overallWinsByDay[dayKey] or 0
                if isWin then overallWinsByDay[dayKey] = overallWinsByDay[dayKey] + 1 end
            end

            for _, ps in ipairs(m.playerStats or {}) do
                if ps.name == me then
                    totalKBs = totalKBs + SafeNumber(ps.killingBlows)
                    break
                end
            end
        end

        local mostWinsDay = 0
        for _, c in pairs(overallWinsByDay) do
            if c > mostWinsDay then mostWinsDay = c end
        end

        -- "This week" net CR change across all brackets (season-week bucket)
        local netCRThisWeek = 0
        if seasonStart and seasonFinish then
            local now = time()
            local endClamp = math.min(now, seasonFinish)
            local week = math.max(1, math.floor((endClamp - seasonStart) / 604800) + 1)
            local weekStart = seasonStart + (week - 1) * 604800
            local weekEnd = weekStart + 604800

            for _, m in ipairs(overallSeasonMatches) do
                if m.endTime and m.endTime >= weekStart and m.endTime < weekEnd then
                    for _, ps in ipairs(m.playerStats or {}) do
                        if ps.name == me then
                            netCRThisWeek = netCRThisWeek + SafeNumber(ps.ratingChange)
                            break
                        end
                    end
                end
            end
        end

        local totalMatches = #overallSeasonMatches

        self.frame.highLines[1]:SetText(string.format("Most Wins in Day  %d", mostWinsDay))
        self.frame.highLines[2]:SetText(string.format("Net CR This Week  %+d", netCRThisWeek))
        self.frame.highLines[3]:SetText(string.format("Total Matches  %d", totalMatches))
        self.frame.highLines[4]:SetText(string.format("Longest Win Streak  %d", longestStreak))
        self.frame.highLines[5]:SetText(string.format("Total Killing Blows  %d", totalKBs))
    elseif self.frame.highLines then
        for i = 1, 6 do
            self.frame.highLines[i]:SetText("")
        end
    end
end