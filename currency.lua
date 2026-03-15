local _, RSTATS = ...

RSTATS.CurrencyTracker = RSTATS.CurrencyTracker or {}
local CurrencyTracker = RSTATS.CurrencyTracker

local HONOR_CURRENCY_ID = 1792
local CONQUEST_CURRENCY_ID = 1602

function CurrencyTracker:GetCurrencySummary()
    local honorInfo = C_CurrencyInfo.GetCurrencyInfo(HONOR_CURRENCY_ID)
    local conquestInfo = C_CurrencyInfo.GetCurrencyInfo(CONQUEST_CURRENCY_ID)
    local honorCurrent = honorInfo and (tonumber(honorInfo.quantity) or 0) or 0
    local honorWeekly = honorInfo and (tonumber(honorInfo.quantityEarnedThisWeek) or 0) or 0
    local honorSeason = honorInfo and (tonumber(honorInfo.totalEarned) or 0) or 0
    local honorIconFileID = honorInfo and honorInfo.iconFileID or nil
    local conquestCurrent = conquestInfo and (tonumber(conquestInfo.quantity) or 0) or 0
    local conquestWeekly = conquestInfo and (tonumber(conquestInfo.quantityEarnedThisWeek) or 0) or 0
    local conquestSeason = conquestInfo and (tonumber(conquestInfo.totalEarned) or 0) or 0
    local conquestIconFileID = conquestInfo and conquestInfo.iconFileID or nil
    return {
        honorCurrent = honorCurrent,
        honorWeekly = honorWeekly,
        honorSeason = honorSeason,
        honorIconFileID = honorIconFileID,
        conquestCurrent = conquestCurrent,
        conquestWeekly = conquestWeekly,
        conquestSeason = conquestSeason,
        conquestIconFileID = conquestIconFileID,
    }
end

local function GetPlayerKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

local function GetPlayerDB()
    RSTATS.Database = RSTATS.Database or {}
    local key = GetPlayerKey()
    RSTATS.Database[key] = RSTATS.Database[key] or {}
    return RSTATS.Database[key]
end

local function GetCurrencyData(currencyID)
    if not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyInfo then
        return nil
    end

    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    if not info then
        return nil
    end

    return {
        name = info.name or "",
        quantity = tonumber(info.quantity) or 0,
        quantityEarnedThisWeek = tonumber(info.quantityEarnedThisWeek) or 0,
        totalEarned = tonumber(info.totalEarned) or 0,
        maxQuantity = tonumber(info.maxQuantity) or 0,
        maxWeeklyQuantity = tonumber(info.maxWeeklyQuantity) or 0,
        canEarnPerWeek = info.canEarnPerWeek and true or false,
        iconFileID = info.iconFileID,
    }
end

local function IsCurrencyCapped(info)
    if not info then
        return false
    end

    if info.maxQuantity > 0 and info.quantity >= info.maxQuantity then
        return true
    end

    if info.maxWeeklyQuantity > 0 and info.quantityEarnedThisWeek >= info.maxWeeklyQuantity then
        return true
    end

    return false
end

local function FormatTriple(currentValue, weeklyValue, seasonValue)
    return string.format("%d / %d / %d", currentValue or 0, weeklyValue or 0, seasonValue or 0)
end

local function GetBarMax(info)
    if not info then
        return 1
    end

    if info.maxQuantity and info.maxQuantity > 0 then
        return info.maxQuantity
    end

    if info.maxWeeklyQuantity and info.maxWeeklyQuantity > 0 then
        return info.maxWeeklyQuantity
    end

    if info.totalEarned and info.totalEarned > 0 then
        return info.totalEarned
    end

    if info.quantity and info.quantity > 0 then
        return info.quantity
    end

    return 1
end

local function SetStatusBarMask(statusBar, atlas, point, x, y)
    if not statusBar then
        return
    end

    local texture = statusBar:GetStatusBarTexture()
    if not texture or not texture.AddMaskTexture then
        return
    end

    local mask = statusBar:CreateMaskTexture(nil, "OVERLAY")
    mask:SetAtlas(atlas, true)
    mask:SetPoint(point, x, y)
    texture:AddMaskTexture(mask)
    statusBar._rsMask = mask
end

local function CreateTrackedBar(parent, width, height, point, relativeTo, relativePoint, x, y, r, g, b)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetSize(width, height)
    bar:SetPoint(point, relativeTo, relativePoint, x, y)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetStatusBarColor(r, g, b)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0, 0, 0, 0.45)

    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetFont(GetUnicodeSafeFont(), 6, "OUTLINE")
    bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar.text:SetWidth(width - 6)
    bar.text:SetJustifyH("CENTER")

    return bar
end

function CurrencyTracker:Refresh()
    if not self.frame then
        return
    end

    local honor = GetCurrencyData(HONOR_CURRENCY_ID)
    local conquest = GetCurrencyData(CONQUEST_CURRENCY_ID)

    if self.frame.portrait then
        SetPortraitTexture(self.frame.portrait, "player")
    end

    if honor then
        local honorMax = GetBarMax(honor)
        self.frame.honorBar:SetMinMaxValues(0, honorMax)
        self.frame.honorBar:SetValue(math.min(honor.quantity, honorMax))
        self.frame.honorBar.text:SetText(FormatTriple(honor.quantity, honor.quantityEarnedThisWeek, honor.totalEarned))
    else
        self.frame.honorBar:SetMinMaxValues(0, 1)
        self.frame.honorBar:SetValue(0)
        self.frame.honorBar.text:SetText("0 / 0 / 0")
    end

    if conquest then
        local conquestMax = GetBarMax(conquest)
        self.frame.conquestBar:SetMinMaxValues(0, conquestMax)
        self.frame.conquestBar:SetValue(math.min(conquest.quantity, conquestMax))
        self.frame.conquestBar.text:SetText(FormatTriple(conquest.quantity, conquest.quantityEarnedThisWeek, conquest.totalEarned))
    else
        self.frame.conquestBar:SetMinMaxValues(0, 1)
        self.frame.conquestBar:SetValue(0)
        self.frame.conquestBar.text:SetText("0 / 0 / 0")
    end
end

function CurrencyTracker:Create(parent)
    if self.frame then
        self.frame:SetParent(parent)
        self.frame:Show()
        self:Refresh()
        return self.frame
    end

    local f = CreateFrame("Frame", "RatedStatsCurrencyTrackerFrame", parent)
    f:SetSize(174, 75)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", 29, -84)
    f:SetFrameStrata(parent:GetFrameStrata())
    f:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)

    f.container = CreateFrame("Frame", nil, f)
    f.container:SetAllPoints()

    f.portrait = f.container:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.portrait:SetSize(45, 45)
    f.portrait:SetPoint("TOPLEFT", 18, -14)

    f.portraitMask = f.container:CreateMaskTexture(nil, "BACKGROUND", nil, 2)
    f.portraitMask:SetAtlas("UI-HUD-UnitFrame-Player-Portrait-Mask", true)
    f.portraitMask:SetSize(45, 45)
    f.portraitMask:SetPoint("TOPLEFT", 18, -14)
    f.portrait:AddMaskTexture(f.portraitMask)

    f.frameTexture = f.container:CreateTexture(nil, "BACKGROUND", nil, 3)
    f.frameTexture:SetAtlas("UI-HUD-UnitFrame-Player-PortraitOn", true)
    f.frameTexture:SetScale(0.75)
    f.frameTexture:SetPoint("CENTER", f, "CENTER", 0, 0)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.title:SetFont(GetUnicodeSafeFont(), 8, "OUTLINE")
    f.title:SetWidth(90)
    f.title:SetJustifyH("LEFT")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 64, -19)
    f.title:SetText("Honor / Conquest")

    f.totalsLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.totalsLabel:SetFont(GetUnicodeSafeFont(), 8, "OUTLINE")
    f.totalsLabel:SetWidth(93)
    f.totalsLabel:SetJustifyH("CENTER")
    f.totalsLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 62, -9)
    f.totalsLabel:SetText("Current / Week / Season")

    f.honorBar = CreateTrackedBar(f, 93, 15, "TOPLEFT", f, "TOPLEFT", 62, -28, 0.85, 0.18, 0.18)
    SetStatusBarMask(f.honorBar, "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health-Mask", "TOPLEFT", 0, 4)

    f.conquestBar = CreateTrackedBar(f, 93, 8, "TOPLEFT", f, "TOPLEFT", 62, -43, 1.00, 0.82, 0.00)
    SetStatusBarMask(f.conquestBar, "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana-Mask", "TOPLEFT", 0, 2)

    self.frame = f
    self:Refresh()

    return f
end

function CurrencyTracker:HandleCapReminder()
    local db = GetPlayerDB()
    db.currencyCapReminderCounter = db.currencyCapReminderCounter or {}

    local tracked = {
        [HONOR_CURRENCY_ID] = GetCurrencyData(HONOR_CURRENCY_ID),
        [CONQUEST_CURRENCY_ID] = GetCurrencyData(CONQUEST_CURRENCY_ID),
    }

    for currencyID, info in pairs(tracked) do
        if IsCurrencyCapped(info) then
            db.currencyCapReminderCounter[currencyID] = (db.currencyCapReminderCounter[currencyID] or 0) + 1

            if db.currencyCapReminderCounter[currencyID] % 5 == 0 then
                print(
                    RSTATS:ColorText("Rated Stats: ")
                    .. "|cffffffff"
                    .. (info.name or "Currency")
                    .. " is capped, spend now on gear, recipes, sockets or transfer to an alt!|r"
                )
            end
        else
            db.currencyCapReminderCounter[currencyID] = 0
        end
    end
end

do
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
    eventFrame:RegisterEvent("PVP_MATCH_COMPLETE")

    eventFrame:SetScript("OnEvent", function(_, event, currencyID)
        if event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(2, function()
                if CurrencyTracker then
                    CurrencyTracker:Refresh()
                end
            end)
            return
        end

        if event == "CURRENCY_DISPLAY_UPDATE" then
            if not currencyID or currencyID == HONOR_CURRENCY_ID or currencyID == CONQUEST_CURRENCY_ID then
                CurrencyTracker:Refresh()
            end
            return
        end

        if event == "PVP_MATCH_COMPLETE" then
            C_Timer.After(2, function()
                CurrencyTracker:Refresh()
                CurrencyTracker:HandleCapReminder()
            end)
        end
    end)
end