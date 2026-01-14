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
    return (a.endTime or 0) < (b.endTime or 0)
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
        return t * h
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
            line:SetStartPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x1, y1)
            line:SetEndPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x2, y2)
            table.insert(frame._lines, line)
        end
    end
end

--
-- Build per-season-week series.
-- 1) wins: winrate% per week (0..100)
-- 2) cr: cumulative CR delta across weeks
-- 3) mmr: cumulative MMR delta across weeks
--
local function BuildSeasonWeeklySeries(history)
    if not history or #history == 0 then
        return {}, {}, {}, 0
    end

    local seasonStart = RSTATS:GetCurrentSeasonStart()
    local seasonFinish = RSTATS:GetCurrentSeasonFinish()
    if not seasonStart or not seasonFinish then
        return {}, {}, {}, 0
    end

    local now = time()
    local endClamp = math.min(now, seasonFinish)
    local weeks = math.max(1, math.floor((endClamp - seasonStart) / 604800) + 1)

    local playerName = GetPlayerFullName()
    local buckets = {}
    for i = 1, weeks do
        buckets[i] = {
            w = 0,
            l = 0,
            d = 0,
            cr = 0,
            mmrFirst = nil,
            mmrLast = nil,
        }
    end

    table.sort(history, SortByEndTime)

    for _, match in ipairs(history) do
        local t = match.endTime
        if t and t >= seasonStart and t < seasonFinish then
            local week = math.floor((t - seasonStart) / 604800) + 1
            if week >= 1 and week <= weeks then
                local b = buckets[week]

                local wl = match.friendlyWinLoss or ""
                if wl:find("W") then
                    b.w = b.w + 1
                elseif wl:find("L") then
                    b.l = b.l + 1
                elseif wl:find("D") then
                    b.d = b.d + 1
                end

                -- Pull personal CR/MMR deltas from playerStats (same approach as stats.lua)
                if match.playerStats then
                    for _, ps in ipairs(match.playerStats) do
                        if ps.name == playerName then
                            b.cr = b.cr + SafeNumber(ps.ratingChange)

                            local mmr = tonumber(ps.postmatchMMR)
                            if mmr then
                                if not b.mmrFirst then b.mmrFirst = mmr end
                                b.mmrLast = mmr
                            end
                            break
                        end
                    end
                end
            end
        end
    end

    local winsSeries = {}
    local crSeries = {}
    local mmrSeries = {}

    local crCum = 0
    local mmrCum = 0

    for i = 1, weeks do
        local b = buckets[i]
        local total = b.w + b.l + b.d
        winsSeries[i] = (total > 0) and ((b.w / total) * 100) or 0

        crCum = crCum + b.cr
        crSeries[i] = crCum

        local mmrDeltaWeek = 0
        if b.mmrFirst and b.mmrLast then
            mmrDeltaWeek = b.mmrLast - b.mmrFirst
        end
        mmrCum = mmrCum + mmrDeltaWeek
        mmrSeries[i] = mmrCum
    end

    return winsSeries, crSeries, mmrSeries, weeks
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

local function CreateBracketCard(parent)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    CreateBackdrop(card)

    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -8)
    card.title:SetFont(GetUnicodeSafeFont(), 12, "OUTLINE")

    card.crText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.crText:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -6)
    card.crText:SetFont(GetUnicodeSafeFont(), 11, "OUTLINE")

    card.mmrText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.mmrText:SetPoint("TOPLEFT", card.crText, "BOTTOMLEFT", 0, -2)
    card.mmrText:SetFont(GetUnicodeSafeFont(), 11, "OUTLINE")

    card.winrateText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.winrateText:SetPoint("TOPLEFT", card.mmrText, "BOTTOMLEFT", 0, -6)
    card.winrateText:SetFont(GetUnicodeSafeFont(), 10, "OUTLINE")

    -- Graph labels (left) + sparklines (right)
    card.graphArea = CreateFrame("Frame", nil, card)
    card.graphArea:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 8)
    card.graphArea:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 8)
    card.graphArea:SetHeight(66)

    local function makeRow(yOff, label)
        local row = CreateFrame("Frame", nil, card.graphArea)
        row:SetPoint("TOPLEFT", card.graphArea, "TOPLEFT", 0, yOff)
        row:SetPoint("TOPRIGHT", card.graphArea, "TOPRIGHT", 0, yOff)
        row:SetHeight(20)

        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.label:SetFont(GetUnicodeSafeFont(), 9, "OUTLINE")
        row.label:SetText(label)

        -- Needs BackdropTemplate or SetBackdrop() won't exist.
        row.spark = CreateFrame("Frame", nil, row, "BackdropTemplate")
        row.spark:SetPoint("LEFT", row.label, "RIGHT", 6, 0)
        row.spark:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.spark:SetHeight(16)
        -- Some builds can still strip backdrop methods; this keeps us safe.
        if row.spark.SetBackdrop then
            row.spark:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
            row.spark:SetBackdropColor(0, 0, 0, 0.25)
        end

        row.spark._lines = {}
        return row
    end

    card.rowWins = makeRow(0, "Wins")
    card.rowCR   = makeRow(-22, "CR")
    card.rowMMR  = makeRow(-44, "MMR")

    function card:SetData(data)
        self.title:SetText(data.name)
        self.crText:SetText(string.format("Current CR: %d", SafeNumber(data.currentCR)))
        self.mmrText:SetText(string.format("Current MMR: %d", SafeNumber(data.currentMMR)))
        self.winrateText:SetText(string.format("Winrate: %d%% (%d/%d/%d)", data.winrate or 0, data.win or 0, data.loss or 0, data.draw or 0))

        -- wins fixed 0..100 so the line is stable.
        DrawSpark(self.rowWins.spark, data.seriesWins or {}, 0, 100)
        DrawSpark(self.rowCR.spark,   data.seriesCR or {})
        DrawSpark(self.rowMMR.spark,  data.seriesMMR or {})
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
end

function Summary:Refresh()
    if not self.frame or not self.frame.cards then return end

    local Database = GetDB() or {}
    local playerKey = GetPlayerFullName()
    local perChar = Database[playerKey] or {}

    for i, bracket in ipairs(BRACKETS) do
        local history = perChar[bracket.historyKey] or {}
        local seasonMatches = {}
        local seasonStart = RSTATS:GetCurrentSeasonStart()
        local seasonFinish = RSTATS:GetCurrentSeasonFinish()

        if seasonStart and seasonFinish then
            for _, m in ipairs(history) do
                if m.endTime and m.endTime >= seasonStart and m.endTime < seasonFinish then
                    table.insert(seasonMatches, m)
                end
            end
        end

        -- Use existing stats engine for win/loss/draw + winrate
        local summary = Stats and Stats.CalculateSummary(seasonMatches, history, bracket.bracketID) or {
            win = 0, loss = 0, draw = 0, winrate = 0,
        }

        local winsSeries, crSeries, mmrSeries = BuildSeasonWeeklySeries(history)

        local cardData = {
            name = bracket.name,
            currentCR = perChar[bracket.crKey] or 0,
            currentMMR = perChar[bracket.mmrKey] or 0,

            win = summary.win or 0,
            loss = summary.loss or 0,
            draw = summary.draw or 0,
            winrate = summary.winrate or 0,

            seriesWins = winsSeries,
            seriesCR = crSeries,
            seriesMMR = mmrSeries,
        }

        self.frame.cards[i]:SetData(cardData)
    end
end
