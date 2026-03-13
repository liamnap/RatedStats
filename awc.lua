local function BuildAWCEvents()
    return {
        {
            day = 1,
            start = time({ year = 2026, month = 9, day = 12, hour = 0, min = 0, sec = 0 }),
            finish = time({ year = 2026, month = 9, day = 12, hour = 23, min = 59, sec = 59 }),
            preText = "Next AWC on 12 Sep 2026 at ",
            todayText = "AWC Today at ",
            timeByRegion = {
                [1] = "TBC",
                [2] = "TBC",
                [3] = "TBC",
                [4] = "TBC",
            },
        },
        {
            day = 2,
            start = time({ year = 2026, month = 9, day = 13, hour = 0, min = 0, sec = 0 }),
            finish = time({ year = 2026, month = 9, day = 13, hour = 23, min = 59, sec = 59 }),
            todayText = "Day 2 of AWC Today at ",
            timeByRegion = {
                [1] = "TBC",
                [2] = "TBC",
                [3] = "TBC",
                [4] = "TBC",
            },
        },
        {
            day = 3,
            start = time({ year = 2026, month = 9, day = 14, hour = 0, min = 0, sec = 0 }),
            finish = time({ year = 2026, month = 9, day = 14, hour = 23, min = 59, sec = 59 }),
            todayText = "Weekend Finals today at ",
            timeByRegion = {
                [1] = "TBC",
                [2] = "TBC",
                [3] = "TBC",
                [4] = "TBC",
            },
        },
    }
end

RSTATS.AWCEvents = BuildAWCEvents()

function RSTATS:GetAWCAnnouncement()
    local now = time()
    local region = (GetCurrentRegion and GetCurrentRegion()) or 3

    for i, event in ipairs(self.AWCEvents or {}) do
        local timeText = (event.timeByRegion and event.timeByRegion[region]) or "TBC"

        if now < event.start then
            if i == 1 and event.preText then
                return event.preText .. timeText
            end
            return "Next AWC on " .. date("%d %b %Y", event.start) .. " at " .. timeText
        end

        if now >= event.start and now <= event.finish then
            return (event.todayText or "AWC Today at ") .. timeText
        end
    end

    return nil
end

function RSTATS:GetNextAWCDisplay()
    local now = time()
    local region = (GetCurrentRegion and GetCurrentRegion()) or 3

    for _, event in ipairs(self.AWCEvents or {}) do
        local timeText = (event.timeByRegion and event.timeByRegion[region]) or "TBC"

        if now <= event.finish then
            if event.display then
                return event.display
            end

            return date("%d %b %Y", event.start) .. " | " .. timeText
        end
    end

    return "TBC"
end

local function GetAWCDateKey(ts)
    local t = date("*t", ts or time())
    return string.format("%04d-%02d-%02d", t.year, t.month, t.day)
end

function RSTATS:MaybePrintDailyAWCMessage()
    if not Database or type(Database) ~= "table" then
        return
    end

    local msg = self:GetAWCAnnouncement()
    if not msg or msg == "" then
        return
    end

    local todayKey = GetAWCDateKey()
    if Database.lastAWCAnnouncementDate == todayKey then
        return
    end

    DEFAULT_CHAT_FRAME:AddMessage(
        self:ColorText("Rated Stats: ") .. "|cffffffff" .. msg .. "|r"
    )

    Database.lastAWCAnnouncementDate = todayKey

    if SaveData then
        SaveData()
    end
end

local awcFrame = CreateFrame("Frame")
awcFrame:RegisterEvent("PLAYER_LOGIN")
awcFrame:SetScript("OnEvent", function()
    C_Timer.After(2, function()
        if RSTATS and RSTATS.MaybePrintDailyAWCMessage then
            RSTATS:MaybePrintDailyAWCMessage()
        end
    end)
end)