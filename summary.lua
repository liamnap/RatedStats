-- summary.lua

local _, RSTATS = ...
local abs = math.abs

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

local function ColorText(text)
    if RSTATS and RSTATS.ColorText then
        return RSTATS:ColorText(text)
    end
    -- fallback (shouldn't happen if core.lua loaded properly)
    local hex = (RSTATS and RSTATS.Config and RSTATS.Config.ThemeColor) or "b69e86"
    return string.format("|cff%s%s|r", tostring(hex):upper(), text)
end

local function GetCurrentSeasonLabel()
    -- If you later add RSTATS:GetCurrentSeasonLabel() in filters.lua, this will use it.
    if RSTATS and RSTATS.GetCurrentSeasonLabel then
        return RSTATS:GetCurrentSeasonLabel()
    end

    -- Otherwise, derive from the season table you already keep in filters.lua
    local seasons = _G.RatedStatsSeasons
    if type(seasons) ~= "table" then return "" end

    local now = time()
    for _, s in ipairs(seasons) do
        local st = tonumber(s.start)
        local en = tonumber(s.finish)
        if st and en and now >= st and now < en then
            return tostring(s.label or "")
        end
    end
    return ""
end

local function GetLatestPostMMRFromHistory(history)
    if not history or #history == 0 then return nil end
    local me = GetPlayerFullName()
    local bestT, bestMMR

    for _, match in ipairs(history) do
        local t = match.endTime or match.timestamp
        if t then
            -- Arena-safe: match-level team MMR (you store friendlyMMR on the match entry)
            local matchMMR = tonumber(match.friendlyMMR) or tonumber(match.mmr)
            if matchMMR and matchMMR > 0 and (not bestT or t > bestT) then
                bestT, bestMMR = t, matchMMR
            end

            -- Fallback: playerStats postmatchMMR (works fine in SS/RBG where it exists)
            if match.playerStats then
                for _, ps in ipairs(match.playerStats) do
                    if ps.name == me then
                        local mmr = tonumber(ps.postmatchMMR)
                        if mmr and mmr > 0 and (not bestT or t > bestT) then
                            bestT, bestMMR = t, mmr
                        end
                        break
                    end
                end
            end
        end
    end
    return bestMMR
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

local function DrawSpark(frame, values, times, xMinFixed, xMaxFixed, yMinFixed, yMaxFixed, xInsetL, xInsetR)
    ClearSpark(frame)

    if not values or #values < 2 then
        return
    end

    local w = frame:GetWidth() or 0
    local h = frame:GetHeight() or 0
    if w <= 1 or h <= 1 then
        return
    end

    xInsetL = tonumber(xInsetL) or 0
    xInsetR = tonumber(xInsetR) or 0
    if xInsetL < 0 then xInsetL = 0 end
    if xInsetR < 0 then xInsetR = 0 end
    if (xInsetL + xInsetR) > (w - 2) then
        xInsetL, xInsetR = 0, 0
    end
    local drawW = w - xInsetL - xInsetR

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
    local useTimeX = (type(times) == "table" and #times == n and xMinFixed and xMaxFixed and xMaxFixed > xMinFixed)
    local xStep = drawW / (n - 1)

    local function mapX(i)
        if useTimeX then
            local t = times[i]
            if not t then return (i - 1) * xStep end
            local u = (t - xMinFixed) / (xMaxFixed - xMinFixed)
            if u < 0 then u = 0 end
            if u > 1 then u = 1 end
            return xInsetL + (u * drawW)
        end
        return xInsetL + ((i - 1) * xStep)
    end

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
            local x1, x2 = mapX(i), mapX(i + 1)
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

local function NearestIndexByTime(times, targetT)
    local bestI, bestD
    for i = 1, #times do
        local t = times[i]
        if t then
            local d = abs(t - targetT)
            if not bestD or d < bestD then
                bestD = d
                bestI = i
            end
        end
    end
    return bestI or 1
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

local function Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function FormatNumber(value)
    if type(value) ~= "number" then
        return tostring(value)
    end

    if value >= 1000000 then
        return string.format("%.1fM", value / 1000000)
    elseif value >= 1000 then
        return string.format("%.1fk", value / 1000)
    else
        return tostring(math.floor(value))
    end
end

local function BuildTopSoloShuffleRecords(history, valueKey, limit, seasonStart, seasonFinish)
    if not history or #history == 0 then
        return {}
    end

    local tmp = {}

    for _, match in ipairs(history) do
        local t = match.endTime or match.timestamp
        if t and seasonStart and seasonFinish and t >= seasonStart and t < seasonFinish then
            for _, ps in ipairs(match.playerStats or {}) do
                local v = tonumber(ps[valueKey])
                if v and v > 0 and ps.name then
                    tmp[#tmp + 1] = { ps = ps, match = match, v = v, t = t }
                end
            end
        end
    end

    table.sort(tmp, function(a, b) return a.v > b.v end)

    local out = {}
    local seen = {}

    for _, r in ipairs(tmp) do
        if not seen[r.ps.name] then
            out[#out + 1] = r
            seen[r.ps.name] = true
            if #out >= (limit or 25) then
                break
            end
        end
    end

    return out
end

local function UpdateRecordCard(card, records)
    if not card or not card.rows then return end

    for i = 1, 25 do
        local row = card.rows[i]
        local rec = records and records[i]

        if rec and row then
            row:Show()
            row._rsPS = rec.ps
            row._rsMatch = rec.match

            row.nameText:SetText(rec.ps.name or "?")

            -- RatedStats_Achiev icon (optional)
            local achievIconPath, _, achievIconTint
            if type(C_AddOns) == "table" and type(C_AddOns.GetAddOnEnableState) == "function" then
                if C_AddOns.GetAddOnEnableState("RatedStats_Achiev", nil) > 0
                    and type(_G.RSTATS_Achiev_GetHighestPvpRank) == "function"
                then
                    achievIconPath, _, achievIconTint = _G.RSTATS_Achiev_GetHighestPvpRank(rec.ps.name)
                end
            end

            if achievIconPath then
                row.iconBtn:Show()
                row.iconTex:SetTexture(achievIconPath)

                if achievIconTint and type(achievIconTint) == "table" then
                    row.iconTex:SetVertexColor(achievIconTint[1] or 1, achievIconTint[2] or 1, achievIconTint[3] or 1)
                else
                    row.iconTex:SetVertexColor(1, 1, 1)
                end

                row.nameBtn:SetPoint("LEFT", row, "LEFT", 14, 0)
            else
                row.iconBtn:Hide()
                row.nameBtn:SetPoint("LEFT", row, "LEFT", 2, 0)
            end

            local when = rec.t and date("%d %b %H:%M", rec.t) or "?"
            row.valueText:SetText(FormatNumber(rec.v) .. "  " .. when)
        elseif row then
            row:Hide()
            row._rsPS = nil
            row._rsMatch = nil
        end
    end
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

    -- Make the chart span the whole season on X (time-based),
    -- and remain flat/zero until our first stored match.
    if #times > 0 then
        local firstWins = winsSeries[1] or 0
        local firstCR   = crSeries[1] or 0
        local firstMMR  = mmrSeries[1] or 0

        local lastWins  = winsSeries[#winsSeries] or firstWins
        local lastCR    = crSeries[#crSeries] or firstCR
        local lastMMR   = mmrSeries[#mmrSeries] or firstMMR

        table.insert(times, 1, seasonStart)
        table.insert(winsSeries, 1, 0)           -- wins are genuinely 0 at season start
        table.insert(crSeries, 1, firstCR)       -- CR/MMR: hold first observed value (not 0)
        table.insert(mmrSeries, 1, firstMMR)

        table.insert(times, seasonFinish)
        table.insert(winsSeries, lastWins)
        table.insert(crSeries, lastCR)
        table.insert(mmrSeries, lastMMR)
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

    local seasonStart = RSTATS and RSTATS.GetCurrentSeasonStart and RSTATS:GetCurrentSeasonStart() or nil
    local seasonFinish = RSTATS and RSTATS.GetCurrentSeasonFinish and RSTATS:GetCurrentSeasonFinish() or nil

    local yMin, yMax = DrawSpark(
        card.spark,
        series or {},
        times,
        seasonStart,
        seasonFinish,
        nil,
        nil,
        card._xInsetL or 0,
        card._xInsetR or 0
    )

    -- Store hover data for tooltip/highlight
    card.spark._hover = card.spark._hover or {}
    local hv = card.spark._hover
    hv.series = series or {}
    hv.times  = times or {}
    hv.yMin   = yMin
    hv.yMax   = yMax
    hv.mode   = mode
    hv.xInsetL = card._xInsetL or 0
    hv.xInsetR = card._xInsetR or 0
    if seasonStart and seasonFinish then
        hv.xMin = seasonStart
        hv.xMax = seasonFinish
        hv.useTimeX = true
    else
        hv.xMin = nil
        hv.xMax = nil
        hv.useTimeX = false
    end

    if card.axisYMin then card.axisYMin:SetText(yMin and tostring(math.floor(yMin)) or "") end
    if card.axisYMax then card.axisYMax:SetText(yMax and tostring(math.floor(yMax)) or "") end

    if seasonStart and seasonFinish then
        if card.axisXStart then card.axisXStart:SetText(date("%d %b", seasonStart)) end
        if card.axisXEnd then card.axisXEnd:SetText(date("%d %b", seasonFinish)) end
    elseif times and #times >= 1 then
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

    C_Timer.NewTicker(5.0, function()
        if not self.frame or not self.frame:IsShown() then return end
        if not self.frame.cards then return end
        for _, card in ipairs(self.frame.cards) do
            if card and card:IsShown() and card._data and not card._pauseGraphCycle then
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
    -- Layout() will position/size this based on card height

    -- Hover dot (highlight point)
    card.spark.hoverDot = card.spark:CreateTexture(nil, "OVERLAY")
    card.spark.hoverDot:SetSize(5, 5)
    card.spark.hoverDot:SetColorTexture(1, 0.82, 0.2, 1) -- match line gold
    card.spark.hoverDot:Hide()

    local function SparkHideHover(spark)
        if spark.hoverDot then spark.hoverDot:Hide() end
        if GameTooltip and GameTooltip:IsOwned(spark) then
            GameTooltip:Hide()
        end
    end

    local function SparkUpdateHover(spark)
        local hv = spark._hover
        if not hv or not hv.series or #hv.series < 2 then
            SparkHideHover(spark)
            return
        end

        local w = spark:GetWidth() or 0
        local h = spark:GetHeight() or 0
        if w <= 2 or h <= 2 then
            SparkHideHover(spark)
            return
        end

        local xInsetL = tonumber(hv.xInsetL) or 0
        local xInsetR = tonumber(hv.xInsetR) or 0
        local drawW = w - xInsetL - xInsetR
        if drawW <= 2 then
            SparkHideHover(spark)
            return
        end

        local x, y = GetCursorPosition()
        local scale = spark:GetEffectiveScale() or 1
        x = x / scale
        y = y / scale

        local left = spark:GetLeft()
        local bottom = spark:GetBottom()
        if not left or not bottom then
            SparkHideHover(spark)
            return
        end

        local lx = x - left
        local ly = y - bottom

        -- Only react when cursor is within spark bounds
        if lx < 0 or lx > w or ly < 0 or ly > h then
            SparkHideHover(spark)
            return
        end

        -- Only within plot area (exclude insets)
        if lx < xInsetL or lx > (w - xInsetR) then
            SparkHideHover(spark)
            return
        end

        local n = #hv.series
        local idx

        local u = (lx - xInsetL) / drawW
        if u < 0 then u = 0 end
        if u > 1 then u = 1 end

        if hv.useTimeX and hv.xMin and hv.xMax and hv.xMax > hv.xMin and type(hv.times) == "table" and #hv.times == n then
            local targetT = hv.xMin + u * (hv.xMax - hv.xMin)
            idx = NearestIndexByTime(hv.times, targetT)
        else
            idx = math.floor(u * (n - 1) + 1.5)
            if idx < 1 then idx = 1 end
            if idx > n then idx = n end
        end

        local v = hv.series[idx]
        if v == nil then
            SparkHideHover(spark)
            return
        end

        local yMin = hv.yMin or 0
        local yMax = hv.yMax or (yMin + 1)
        if yMax == yMin then yMax = yMin + 1 end

        local function mapY(val)
            local t = (val - yMin) / (yMax - yMin)
            if t < 0 then t = 0 end
            if t > 1 then t = 1 end
            local yy = t * h
            if yy < 1 then yy = 1 end
            return yy
        end

        local function mapX(i)
            if hv.useTimeX and hv.xMin and hv.xMax and hv.xMax > hv.xMin and hv.times and hv.times[i] then
                local tt = hv.times[i]
                local uu = (tt - hv.xMin) / (hv.xMax - hv.xMin)
                if uu < 0 then uu = 0 end
                if uu > 1 then uu = 1 end
                return xInsetL + (uu * drawW)
            end
            return xInsetL + ((i - 1) * (drawW / (n - 1)))
        end

        local px = mapX(idx)
        local py = mapY(v)

        spark.hoverDot:ClearAllPoints()
        spark.hoverDot:SetPoint("CENTER", spark, "BOTTOMLEFT", px, py)
        spark.hoverDot:Show()

        local t = hv.times and hv.times[idx] or nil
        local dateText = t and date("%d %b %Y %H:%M", t) or ""
        local valText = tostring(math.floor(tonumber(v) or 0))

        if GameTooltip then
            GameTooltip:SetOwner(spark, "ANCHOR_CURSOR")
            GameTooltip:ClearLines()
            if dateText ~= "" then
                -- Label in addon colour, value left as default (tooltip text is white)
                GameTooltip:AddLine(ColorText(dateText .. ": ") .. valText)
            else
                GameTooltip:AddLine(valText)
            end
            GameTooltip:Show()
        end
    end

    if card.spark.SetBackdrop then
        card.spark:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
        card.spark:SetBackdropColor(0, 0, 0, 0.25)
    end
    card.spark._lines = {}

    -- Hover tooltip/highlight (throttled)
    if not card.spark._hoverHooks then
        card.spark._hoverHooks = true
        card.spark._hoverElapsed = 0

        card.spark:EnableMouse(true)
        card.spark:SetScript("OnEnter", function(self)
            -- Pause ONLY this card's auto-rotation while hovering the graph
            card._pauseGraphCycle = true
            self._hoverElapsed = 0
            self:SetScript("OnUpdate", function(s, elapsed)
                s._hoverElapsed = (s._hoverElapsed or 0) + elapsed
                if s._hoverElapsed < 0.03 then return end
                s._hoverElapsed = 0
                SparkUpdateHover(s)
            end)
        end)

        card.spark:SetScript("OnLeave", function(self)
            -- Resume rotation when mouse leaves graph
            card._pauseGraphCycle = false
            self:SetScript("OnUpdate", nil)
            SparkHideHover(self)
        end)
    end

    -- Simple axes (compact): Y min/max on left, X start/end dates under spark
    card.axisYMax = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.axisYMax:SetPoint("TOPLEFT", card.spark, "TOPLEFT", -4, 2)
    card.axisYMax:SetFont(GetUnicodeSafeFont(), 8, "OUTLINE")
    card.axisYMax:SetJustifyH("RIGHT")

    card.axisYMin = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.axisYMin:SetPoint("BOTTOMLEFT", card.spark, "BOTTOMLEFT", -4, -2)
    card.axisYMin:SetFont(GetUnicodeSafeFont(), 8, "OUTLINE")
    card.axisYMin:SetJustifyH("RIGHT")

    card.axisXStart = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- anchored by Layout()
    card.axisXStart:SetFont(GetUnicodeSafeFont(), 8, "OUTLINE")

    card.axisXEnd = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- anchored by Layout()
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
    -- anchored by Layout()
    card.footerLeft:SetFont(GetUnicodeSafeFont(), 9, "OUTLINE")
    card.footerLeft:SetText("")

    card.footerRight = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- anchored by Layout()
    card.footerRight:SetFont(GetUnicodeSafeFont(), 9, "OUTLINE")
    card.footerRight:SetText("")

    function card:Layout()
        -- Percent-based sizing so it scales with UI.
        -- Keep a clean bottom stack INSIDE the card: spark -> dates -> footer.
        local h = self:GetHeight() or 160

        local padX = 10
        -- 4-digit CR/MMR axis labels need real width; 18px truncates to "1..."
        local yAxisW = 30  -- inner gutter width (used on BOTH sides for symmetrical padding)
        self._xInsetL = yAxisW
        self._xInsetR = yAxisW

        -- scale spacing slightly with card height, but clamp so it doesn't get silly
        local footerGap = Clamp(math.floor(h * 0.02), 3, 8)   -- spacing between date axis and footer
        local axisGap   = Clamp(math.floor(h * 0.03), 8, 14)  -- spacing between spark and date axis
        local footerY   = 4                                   -- keep footer safely inside the card
        local axisY     = footerY + 12 + footerGap            -- axis sits above footer
        local sparkBottom = axisY + axisGap                   -- spark sits above axis

        -- Spark height drives the perceived "gap" between Winrate and the graph header.
        -- Taller graph so it fills the card and reduces the empty gap from winrate -> header.
        -- Force graph block into bottom 50% of the card
        local graphTop = Clamp(math.floor(h * 0.50), 60, 140)  -- y (from bottom) where graph block should NOT exceed
        local labelPad = 14                                    -- reserve for "Wins/CR/MMR" label above spark
        local sparkH = graphTop - sparkBottom - labelPad
        sparkH = Clamp(sparkH, 28, 110)
        if sparkH < 10 then sparkH = 10 end

        self.spark:ClearAllPoints()
        -- Even padding left/right (spark is centred within the card)
        self.spark:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", padX, sparkBottom)
        self.spark:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -padX, sparkBottom)
        self.spark:SetHeight(sparkH)

        -- Y labels live in the LEFT gutter (not the plot area) so they don't get cropped.
        self.axisYMax:ClearAllPoints()
        self.axisYMax:SetPoint("TOPRIGHT", self.spark, "TOPLEFT", yAxisW - 2, 2)
        self.axisYMax:SetWidth(yAxisW)
        self.axisYMax:SetJustifyH("RIGHT")
        self.axisYMax:SetWordWrap(false)

        self.axisYMin:ClearAllPoints()
        self.axisYMin:SetPoint("BOTTOMLEFT", self.spark, "BOTTOMLEFT", yAxisW - 2, -2)
        self.axisYMin:SetWidth(yAxisW)
        self.axisYMin:SetJustifyH("RIGHT")
        self.axisYMin:SetWordWrap(false)

        -- Label sits just above the spark
        self.sparkLabel:ClearAllPoints()
        self.sparkLabel:SetPoint("BOTTOMLEFT", self.spark, "TOPLEFT", 0, 6)

        -- Date axis sits between spark and footer
        self.axisXStart:ClearAllPoints()
        -- align dates to actual plot area start/end (inside the insets)
        self.axisXStart:SetPoint("BOTTOMLEFT", self.spark, "BOTTOMLEFT", yAxisW, axisY - sparkBottom)
 
        self.axisXEnd:ClearAllPoints()
        self.axisXEnd:SetPoint("BOTTOMRIGHT", self.spark, "BOTTOMRIGHT", -yAxisW, axisY - sparkBottom)

        -- Footer is BELOW the dates (still inside the card)
        self.footerLeft:ClearAllPoints()
        self.footerLeft:SetPoint("BOTTOMLEFT", self.spark, "BOTTOMLEFT", yAxisW, footerY - sparkBottom)

        self.footerRight:ClearAllPoints()
        self.footerRight:SetPoint("BOTTOMRIGHT", self.spark, "BOTTOMRIGHT", -yAxisW, footerY - sparkBottom)
    end

    card:SetScript("OnSizeChanged", function(self)
        self:Layout()
        if self._data and Summary and Summary._RenderCardGraph then
            Summary:_RenderCardGraph(self)
        end
    end)

    -- Which graph this card is currently showing:
    -- 1 = Wins (season-week wins)
    -- 2 = CR +/- (cumulative)
    -- 3 = MMR +/- (cumulative)
    card._graphMode = 1

    function card:SetData(data)
        self.title:SetText(data.name)
        self.matchesText:SetText(ColorText("Matches: ") .. tostring(SafeNumber(data.matches)))
        self.crText:SetText(ColorText("Current CR: ") .. tostring(SafeNumber(data.currentCR)))
        self.mmrText:SetText(ColorText("Current MMR: ") .. tostring(SafeNumber(data.currentMMR)))
        self.winrateText:SetText(ColorText("Winrate: ") .. string.format(
            "%d%% (%d/%d/%d)", data.winrate or 0, data.win or 0, data.loss or 0, data.draw or 0
        ))

        self._data = data

        if data.seasonWeekText and data.seasonWeekText ~= "" then
            self.footerLeft:SetText(ColorText("Season Week: ") .. tostring(data.seasonWeekText))
        else
            self.footerLeft:SetText("")
        end

        if data.last25Text and data.last25Text ~= "" then
            self.footerRight:SetText(ColorText("Last 25: ") .. tostring(data.last25Text))
        else
            self.footerRight:SetText("")
        end

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
            self:Layout()
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

    f.seasonNote2 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.seasonNote2:SetPoint("TOP", header, "BOTTOM", 0, -4)
    f.seasonNote2:SetFont(GetUnicodeSafeFont(), 10, "OUTLINE")

    f.seasonNote3 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.seasonNote3:SetPoint("TOP", f.seasonNote2, "BOTTOM", 0, -2)
    f.seasonNote3:SetFont(GetUnicodeSafeFont(), 10, "OUTLINE")

    f.cards = {}

    -- Create cards once; Layout() will size/position using %.
    for i = 1, #BRACKETS do
        f.cards[i] = CreateBracketCard(f)
    end

    function f:LayoutCards()
        local totalW = self:GetWidth()
        local totalH = self:GetHeight()
        if not totalW or totalW <= 1 or not totalH or totalH <= 1 then return end

        -- % based spacing
        local sidePad = Clamp(math.floor(totalW * 0.02), 10, 26)   -- ~2% width
        local gap     = Clamp(math.floor(totalW * 0.01),  8, 20)   -- ~1% width

        -- Raise max so the 30% can actually take effect on larger frames
        local cardH = Clamp(math.floor(totalH * 0.30), 150, 420)

        -- Card width: derived so 5 cards ALWAYS fit with side padding + gaps
        local availW = totalW - (sidePad * 2) - (gap * 4)
        local cardW = math.floor(availW / 5)
        if cardW < 140 then cardW = 140 end

        -- Compute header/notes block height dynamically so cards never overlap it
        local headerH = (self.header and self.header:GetStringHeight()) or 18
        local headerH = (self.header and self.header:GetStringHeight()) or 18
        local n2H = (self.seasonNote2 and self.seasonNote2:GetStringHeight()) or 10
        local n3H = (self.seasonNote3 and self.seasonNote3:GetStringHeight()) or 10

        -- Matches your existing TOP offsets: header at -10, then notes -4 / -2 / -2
        local topBlockH = 10 + headerH + 4 + n2H + 2 + n3H
        local topGap = Clamp(math.floor(totalH * 0.02), 10, 20)  -- space under season notes

        local topY = -(topBlockH + topGap)

        for i = 1, #self.cards do
            local card = self.cards[i]
            card:ClearAllPoints()
            card:SetSize(cardW, cardH)

            if i == 1 then
                card:SetPoint("TOPLEFT", self, "TOPLEFT", sidePad, topY)
            else
                card:SetPoint("LEFT", self.cards[i - 1], "RIGHT", gap, 0)
            end
        end
    end

    f:SetScript("OnShow", function(self) self:LayoutCards() end)
    f:SetScript("OnSizeChanged", function(self) self:LayoutCards() end)
    C_Timer.After(0, function() if f and f.LayoutCards then f:LayoutCards() end end)

    -- Bottom content: Player model (left) + record cards (right)
    f.bottom = CreateFrame("Frame", nil, f, "BackdropTemplate")
    CreateBackdrop(f.bottom)
    f.bottom:SetPoint("TOPLEFT", f.cards[1], "BOTTOMLEFT", 0, -14)
    f.bottom:SetPoint("TOPRIGHT", f.cards[#f.cards], "BOTTOMRIGHT", 0, -14)
    f.bottom:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
    f.bottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)

    -- Left: 3D player model (uses your current character model)
    f.modelPanel = CreateFrame("Frame", nil, f.bottom, "BackdropTemplate")
    CreateBackdrop(f.modelPanel)
    f.modelPanel:SetPoint("TOPLEFT", f.bottom, "TOPLEFT", 10, -10)
    f.modelPanel:SetPoint("BOTTOMLEFT", f.bottom, "BOTTOMLEFT", 10, 10)
    f.modelPanel:SetWidth(290)

    f.modelTitle = f.modelPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.modelTitle:SetFont(GetUnicodeSafeFont(), 14, "OUTLINE")
    f.modelTitle:SetPoint("TOP", f.modelPanel, "TOP", 0, -6)
    f.modelTitle:SetText("Your Legend")

    f.playerModel = CreateFrame("PlayerModel", nil, f.modelPanel)
    f.playerModel:SetPoint("TOPLEFT", f.modelPanel, "TOPLEFT", 6, -24)
    f.playerModel:SetPoint("BOTTOMRIGHT", f.modelPanel, "BOTTOMRIGHT", -6, 6)
    f.playerModel:SetUnit("player")
    if f.playerModel.SetCamDistanceScale then
        f.playerModel:SetCamDistanceScale(0.9)
    end

    f.playerModel._rsRot = 0
    f.playerModel._rsDragging = false
    f.playerModel._rsDragX = nil

    f.playerModel:EnableMouse(true)
    f.playerModel:SetScript("OnEnter", function(self) self._rsHover = true end)
    f.playerModel:SetScript("OnLeave", function(self) self._rsHover = false; self._rsDragging = false; self._rsDragX = nil end)

    f.playerModel:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self._rsDragging = true
            local scale = UIParent and UIParent:GetEffectiveScale() or 1
            local x = (GetCursorPosition() or 0) / scale
            self._rsDragX = x
        end
    end)

    f.playerModel:SetScript("OnMouseUp", function(self)
        self._rsDragging = false
        self._rsDragX = nil
    end)

    f.playerModel:SetScript("OnUpdate", function(self, elapsed)
        elapsed = tonumber(elapsed) or 0
        if self._rsDragging then
            local scale = UIParent and UIParent:GetEffectiveScale() or 1
            local x = (GetCursorPosition() or 0) / scale
            if self._rsDragX then
                local dx = x - self._rsDragX
                self._rsRot = (self._rsRot + (dx * 0.01)) % (2 * math.pi)
                self._rsDragX = x
            else
                self._rsDragX = x
            end
        elseif not self._rsHover then
            self._rsRot = (self._rsRot + elapsed * 0.25) % (2 * math.pi)
        else
            return
        end

        if self.SetFacing then
            self:SetFacing(self._rsRot)
        end
    end)

    -- Right: record cards (scrollable lists)
    f.recordsPanel = CreateFrame("Frame", nil, f.bottom)
    f.recordsPanel:SetPoint("TOPLEFT", f.modelPanel, "TOPRIGHT", 10, 0)
    f.recordsPanel:SetPoint("BOTTOMRIGHT", f.bottom, "BOTTOMRIGHT", -10, 10)

    local function CreateRecordCard(parent, titleText)
        local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        CreateBackdrop(card)

        card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        card.title:SetFont(GetUnicodeSafeFont(), 13, "OUTLINE")
        card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -8)
        card.title:SetText(titleText)

        card.scroll = CreateFrame("ScrollFrame", nil, card, "UIPanelScrollFrameTemplate")
        card.scroll:SetPoint("TOPLEFT", card, "TOPLEFT", 6, -26)
        card.scroll:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -24, 8)

        card.scrollChild = CreateFrame("Frame", nil, card.scroll)
        card.scrollChild:SetSize(1, 1)
        card.scroll:SetScrollChild(card.scrollChild)

        card.rows = {}

        local rowH = 14
        local nameColW = 150

        for i = 1, 25 do
            local row = CreateFrame("Frame", nil, card.scrollChild)
            row:SetHeight(rowH)
            row:SetPoint("TOPLEFT", card.scrollChild, "TOPLEFT", 0, -((i - 1) * rowH))
            row:SetPoint("TOPRIGHT", card.scrollChild, "TOPRIGHT", 0, -((i - 1) * rowH))

            row.iconBtn = CreateFrame("Button", nil, row)
            row.iconBtn:SetSize(10, 10)
            row.iconBtn:SetPoint("LEFT", row, "LEFT", 2, 0)
            row.iconBtn:Hide()

            row.iconTex = row.iconBtn:CreateTexture(nil, "OVERLAY")
            row.iconTex:SetAllPoints()

            row.nameBtn = CreateFrame("Button", nil, row)
            row.nameBtn:SetSize(nameColW, rowH)
            row.nameBtn:SetPoint("LEFT", row, "LEFT", 2, 0)

            row.nameText = row.nameBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.nameText:SetFont(GetUnicodeSafeFont(), 10, "OUTLINE")
            row.nameText:SetPoint("LEFT", row.nameBtn, "LEFT", 0, 0)
            row.nameText:SetJustifyH("LEFT")

            row.valueText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.valueText:SetFont(GetUnicodeSafeFont(), 10, "OUTLINE")
            row.valueText:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            row.valueText:SetJustifyH("RIGHT")

            row.nameBtn:SetScript("OnClick", function(self)
                local parentRow = self:GetParent()
                if parentRow and parentRow._rsPS and parentRow._rsMatch and type(RSTATS) == "table" and type(RSTATS.OpenPlayerDetails) == "function" then
                    RSTATS.OpenPlayerDetails(parentRow._rsPS, parentRow._rsMatch)
                end
            end)

            row.iconBtn:SetScript("OnClick", function(self)
                local parentRow = self:GetParent()
                if parentRow and parentRow._rsPS and parentRow._rsMatch and type(RSTATS) == "table" and type(RSTATS.OpenPlayerDetails) == "function" then
                    RSTATS.OpenPlayerDetails(parentRow._rsPS, parentRow._rsMatch)
                end
            end)

            row.iconBtn:SetScript("OnEnter", function(self)
                local parentRow = self:GetParent()
                if parentRow and parentRow._rsPS and parentRow._rsPS.name
                    and type(_G.RSTATS_Achiev_AddAchievementInfoToTooltip) == "function"
                then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    local baseName, realm = strsplit("-", parentRow._rsPS.name)
                    realm = realm or GetRealmName()
                    _G.RSTATS_Achiev_AddAchievementInfoToTooltip(GameTooltip, baseName, realm)
                    GameTooltip:Show()
                end
            end)

            row.iconBtn:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            card.rows[i] = row
        end

        card.scrollChild:SetHeight(25 * rowH)
        return card
    end

    f.damageCard = CreateRecordCard(f.recordsPanel, "Best 25 Players - Most Damage Done (Solo Shuffle)")
    f.healCard   = CreateRecordCard(f.recordsPanel, "Best 25 Players - Most Healing Done (Solo Shuffle)")

    f.damageCard:SetPoint("TOPLEFT", f.recordsPanel, "TOPLEFT", 0, 0)
    f.damageCard:SetPoint("TOPRIGHT", f.recordsPanel, "TOPRIGHT", 0, 0)
    f.damageCard:SetHeight( (f.recordsPanel:GetHeight() or 220) * 0.5 - 6 )

    f.healCard:SetPoint("TOPLEFT", f.damageCard, "BOTTOMLEFT", 0, -10)
    f.healCard:SetPoint("TOPRIGHT", f.damageCard, "BOTTOMRIGHT", 0, -10)
    f.healCard:SetPoint("BOTTOMLEFT", f.recordsPanel, "BOTTOMLEFT", 0, 0)
    f.healCard:SetPoint("BOTTOMRIGHT", f.recordsPanel, "BOTTOMRIGHT", 0, 0)

    f:SetScript("OnSizeChanged", function(self)
        if self.LayoutCards then self:LayoutCards() end
        if self.damageCard and self.healCard then
            local h = (self.recordsPanel and self.recordsPanel:GetHeight()) or 220
            self.damageCard:SetHeight(h * 0.5 - 6)
        end
    end)

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

    -- Header season info
    if self.frame and self.frame.header then
        local label = GetCurrentSeasonLabel()
        if label ~= "" then
            self.frame.header:SetText("PvP Summary - " .. label)
        else
            self.frame.header:SetText("PvP Summary")
        end

        if self.frame.seasonNote2 then
            if seasonStart then
                self.frame.seasonNote2:SetText(ColorText("Season Start: ") .. date("%d %b %Y", seasonStart))
            else
                self.frame.seasonNote2:SetText(ColorText("Season Start: ") .. "?")
            end
        end

        if self.frame.seasonNote3 then
            if seasonFinish then
                self.frame.seasonNote3:SetText(ColorText("Season End: ") .. date("%d %b %Y", seasonFinish))
            else
                self.frame.seasonNote3:SetText(ColorText("Season End: ") .. "?")
            end
        end

        -- IMPORTANT: first open can overlap because LayoutCards() ran before these strings
        -- had final rendered heights. Re-layout on next frame after text updates.
        if self.frame.LayoutCards then
            C_Timer.After(0, function()
                if Summary and Summary.frame and Summary.frame:IsShown() and Summary.frame.LayoutCards then
                    Summary.frame:LayoutCards()
                end
            end)
        end

    end

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
        if last25Count > 0 then last25Text = string.format("%d games played  %+d CR", last25Count - 1, last25Delta) end

        local cardData = {
            name = bracket.name,
            currentCR = perChar[bracket.crKey] or 0,
            currentMMR = (function()
                local mmr = perChar[bracket.mmrKey] or 0
                if bracket.tabID == 2 or bracket.tabID == 3 then
                    local last = GetLatestPostMMRFromHistory(history)
                    if last then mmr = last end
                end
                return mmr
            end)(),

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

        self.frame.highLines[1]:SetText(ColorText("Most Wins in Day: ") .. tostring(mostWinsDay))
        self.frame.highLines[2]:SetText(ColorText("Net CR This Week: ") .. string.format("%+d", netCRThisWeek))
        self.frame.highLines[3]:SetText(ColorText("Total Matches: ") .. tostring(totalMatches))
        self.frame.highLines[4]:SetText(ColorText("Longest Win Streak: ") .. tostring(longestStreak))
        self.frame.highLines[5]:SetText(ColorText("Total Killing Blows: ") .. tostring(totalKBs))
    elseif self.frame.highLines then
        for i = 1, 6 do
            self.frame.highLines[i]:SetText("")
        end
    end

    -- Bottom record cards (Solo Shuffle)
    if self.frame and self.frame.damageCard and self.frame.healCard then
        local ssHistory = perChar["SoloShuffleHistory"] or {}
        local topDmg  = BuildTopSoloShuffleRecords(ssHistory, "damageDone", 25, seasonStart, seasonFinish)
        local topHeal = BuildTopSoloShuffleRecords(ssHistory, "healingDone", 25, seasonStart, seasonFinish)

        UpdateRecordCard(self.frame.damageCard, topDmg)
        UpdateRecordCard(self.frame.healCard, topHeal)
    end
end