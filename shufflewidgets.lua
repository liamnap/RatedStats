local _, RSTATS = ...

-- Observed in Retail Solo Shuffle: the player's cumulative wins and round.
local WINS_WIDGET, ROUND_WIDGET = 4457, 3521
local Tracker = {}
RSTATS.ShuffleWidgets = Tracker
local records = {}
local generation = 0
local activeRecord

local function ReadText(id)
    local getter = C_UIWidgetManager and C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo
    if not getter then return nil end
    local ok, info = pcall(getter, id)
    if not ok or not info or (issecretvalue and issecretvalue(info)) then return nil end
    local text = info.text
    if issecretvalue and issecretvalue(text) then return nil end
    if type(text) ~= "string" then return nil end
    if issecretvalue and issecretvalue(info.shownState) then return nil end
    if info.shownState == Enum.WidgetShownState.Hidden then return nil end
    return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

function Tracker.ReadRound()
    local text = ReadText(ROUND_WIDGET)
    local round = text and tonumber(text:match("^%s*Round:%s*(%d+)%s*/%s*6%s*$"))
    if round and round >= 1 and round <= 6 then return round end
end

local function ReadWins()
    local text = ReadText(WINS_WIDGET)
    local wins = text and tonumber(text:match("^%s*Wins:%s*(%d+)%s*$"))
    if wins and wins >= 0 and wins <= 6 then return wins end
end

function Tracker.Reset()
    generation = generation + 1
    records = {}
    activeRecord = nil
end

function Tracker.Begin(round)
    if records[round] then activeRecord = records[round]; return end
    local previous = records[round - 1]
    local baseline = previous and previous.total
    -- The first round starts at zero. Joining/reloading later needs a readable baseline.
    if round == 1 then baseline = 0 end
    if baseline == nil and not previous and Tracker.ReadRound() == round then baseline = ReadWins() end
    if baseline and baseline > round - 1 then baseline = nil end
    records[round] = {round = round, baseline = baseline, generation = generation}
    activeRecord = records[round]
end

local function Apply(record)
    for _, row in ipairs(record.rows or {}) do
        row.shuffleResultSource = "widgets"
        row.roundIndex = record.round
        row.roundsWon = record.total
        row.shuffleRoundWon = record.won
        row.friendlyWinLoss = "RND " .. record.round .. (record.won == nil and "  ?" or record.won and "  +   W" or "  +   L")
    end
end

function Tracker.Sample(record, settle)
    if not record or record.generation ~= generation then return end
    if not (C_PvP.IsRatedSoloShuffle and C_PvP.IsRatedSoloShuffle()) then return end
    local round, total = Tracker.ReadRound(), ReadWins()
    -- During preparation the round label may already point at the next round.
    if round ~= record.round and round ~= record.round + 1 then return end
    if total == nil or total > record.round then return end
    if record.total and total < record.total then return end
    local previous = records[record.round - 1]
    if previous then record.baseline = previous.total end
    if record.baseline == nil then
        -- Preserve a readable total even when reload/missing data prevents a round delta.
        -- It supplies the baseline for the following round, without inventing this result.
        if settle then record.total = total; Apply(record) end
        return
    end
    local delta = total - record.baseline
    if delta ~= 0 and delta ~= 1 then return end
    -- A rise proves a win. An unchanged count is not a loss until the settling read.
    if delta == 0 and not settle then return end
    record.total, record.won = total, delta == 1
    Apply(record)
end

function Tracker.EndRound(round)
    Tracker.Begin(round)
    local record = records[round]
    if record.ended then return record end
    record.ended = true
    Tracker.Sample(record, false)
    if round == 6 then
        -- Final round has no next preparation window. Retry after the completion burst.
        for _, delay in ipairs({1, 2, 3, 5}) do
            C_Timer.After(delay, function()
                Tracker.Sample(record, delay == 5)
                if record.generation == generation and record.rows and SaveData then SaveData() end
            end)
        end
    end
    return record
end

function Tracker.Get(round)
    return records[round]
end

function Tracker.Attach(record, row, settle)
    if not record then return end
    record.rows = record.rows or {}
    table.insert(record.rows, row)
    Tracker.Sample(record, settle)
    Apply(record)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UPDATE_UI_WIDGET")
frame:SetScript("OnEvent", function(_, event, info)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Cancel callbacks from an earlier instance; never read a new lobby into old rows.
        Tracker.Reset()
    elseif info and not (issecretvalue and issecretvalue(info.widgetID))
        and (info.widgetID == WINS_WIDGET or info.widgetID == ROUND_WIDGET)
        and activeRecord and activeRecord.ended then
        Tracker.Sample(activeRecord, false)
        if activeRecord.rows and SaveData then SaveData() end
    end
end)
