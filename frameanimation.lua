local RatedStats, Namespace = ...
local RSTATS = _G.RSTATS

if not RSTATS then return end

local hasPlayedMenuIntroThisSession = false
local hasPendingNewGameBanner = false

local function GetTodayKey()
    return date("%Y-%m-%d")
end

function RSTATS:CreateDailyMenuIntro(menu)
    if not menu or menu.DailyIntro then
        return
    end

    menu.DailyIntro = CreateFrame("Frame", nil, menu)
    menu.DailyIntro:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, -30)
    menu.DailyIntro:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -8, 8)
    menu.DailyIntro:SetFrameStrata("DIALOG")
    menu.DailyIntro:SetFrameLevel(menu:GetFrameLevel() + 50)
    menu.DailyIntro:EnableMouse(false)
    menu.DailyIntro:Hide()
    menu.DailyIntro:SetAlpha(0)

    menu.DailyIntro.Shade = menu.DailyIntro:CreateTexture(nil, "BACKGROUND")
    menu.DailyIntro.Shade:SetAllPoints()
    menu.DailyIntro.Shade:SetColorTexture(0, 0, 0, 0.85)

    menu.DailyIntro.Image = menu.DailyIntro:CreateTexture(nil, "ARTWORK")
    menu.DailyIntro.Image:SetAllPoints()
    menu.DailyIntro.Image:SetTexture("Interface\\AddOns\\RatedStats\\images\\faction_vs.png")

    menu.DailyIntro.Flash = menu.DailyIntro:CreateTexture(nil, "OVERLAY")
    menu.DailyIntro.Flash:SetAllPoints()
    menu.DailyIntro.Flash:SetColorTexture(1, 1, 1, 0.10)
    menu.DailyIntro.Flash:SetBlendMode("ADD")

    menu.DailyIntro.anim = menu.DailyIntro:CreateAnimationGroup()

    local fadeIn = menu.DailyIntro.anim:CreateAnimation("Alpha")
    fadeIn:SetOrder(1)
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.20)

    local hold = menu.DailyIntro.anim:CreateAnimation("Alpha")
    hold:SetOrder(2)
    hold:SetFromAlpha(1)
    hold:SetToAlpha(1)
    hold:SetDuration(2.00)

    local fadeOut = menu.DailyIntro.anim:CreateAnimation("Alpha")
    fadeOut:SetOrder(3)
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(1.25)

    menu.DailyIntro.anim:SetScript("OnFinished", function()
        menu.DailyIntro:Hide()
    end)
end

function RSTATS:PlayDailyMenuIntro(menu)
    if not menu or not menu.DailyIntro then
        return
    end

    if hasPlayedMenuIntroThisSession then
        return
    end

    hasPlayedMenuIntroThisSession = true

    if menu.DailyIntro.anim and menu.DailyIntro.anim:IsPlaying() then
        menu.DailyIntro.anim:Stop()
    end

    menu.DailyIntro:SetAlpha(0)
    menu.DailyIntro:Show()
    PlaySound(10030, "Master")
    menu.DailyIntro.anim:Play()
end

function RSTATS:CreateNewGameBanner(menu)
    if not menu or menu.NewGameBanner then
        return
    end

    menu.NewGameBanner = CreateFrame("Frame", nil, menu)
    menu.NewGameBanner:SetSize(220, 28)
    menu.NewGameBanner:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -92, -34)
    menu.NewGameBanner:SetFrameStrata("DIALOG")
    menu.NewGameBanner:SetFrameLevel(menu:GetFrameLevel() + 40)
    menu.NewGameBanner:EnableMouse(false)
    menu.NewGameBanner:SetAlpha(0)
    menu.NewGameBanner:Hide()

    menu.NewGameBanner.Text = menu.NewGameBanner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    menu.NewGameBanner.Text:SetPoint("RIGHT", menu.NewGameBanner, "RIGHT", 0, 0)
    menu.NewGameBanner.Text:SetJustifyH("RIGHT")
    menu.NewGameBanner.Text:SetText("New Game Added")
    menu.NewGameBanner.Text:SetTextColor(1, 0.82, 0, 1)

    menu.NewGameBanner.Glow = menu.NewGameBanner:CreateTexture(nil, "BACKGROUND")
    menu.NewGameBanner.Glow:SetPoint("TOPLEFT", menu.NewGameBanner.Text, "TOPLEFT", -10, 6)
    menu.NewGameBanner.Glow:SetPoint("BOTTOMRIGHT", menu.NewGameBanner.Text, "BOTTOMRIGHT", 10, -6)
    menu.NewGameBanner.Glow:SetColorTexture(1, 0.82, 0, 0.10)
    menu.NewGameBanner.Glow:SetBlendMode("ADD")

    menu.NewGameBanner.anim = menu.NewGameBanner:CreateAnimationGroup()

    local fadeIn = menu.NewGameBanner.anim:CreateAnimation("Alpha")
    fadeIn:SetOrder(1)
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.15)

    local hold = menu.NewGameBanner.anim:CreateAnimation("Alpha")
    hold:SetOrder(2)
    hold:SetFromAlpha(1)
    hold:SetToAlpha(1)
    hold:SetDuration(2.00)

    local fadeOut = menu.NewGameBanner.anim:CreateAnimation("Alpha")
    fadeOut:SetOrder(3)
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(1.25)

    menu.NewGameBanner.anim:SetScript("OnFinished", function()
        menu.NewGameBanner:Hide()

    end)
end

function RSTATS:PlayNewGameBanner(menu)
    if not menu or not menu.NewGameBanner then
        return
    end

    if menu.NewGameBanner.anim and menu.NewGameBanner.anim:IsPlaying() then
        menu.NewGameBanner.anim:Stop()
    end

    menu.NewGameBanner:SetAlpha(0)
    menu.NewGameBanner:Show()
    menu.NewGameBanner.anim:Play()
end

function RSTATS:NotifyNewGameAdded()
    hasPendingNewGameBanner = true

    if UIConfig and UIConfig:IsShown() then
        if not UIConfig.NewGameBanner then
            RSTATS:CreateNewGameBanner(UIConfig)
        end

        if UIConfig.NewGameBanner and not UIConfig.NewGameBanner.anim:IsPlaying() then
            hasPendingNewGameBanner = false
            RSTATS:PlayNewGameBanner(UIConfig)
        end
    end
end

function RSTATS:FlushQueuedNewGameBanner(menu)
    if not menu or not menu.NewGameBanner then
        return
    end

    if hasPendingNewGameBanner and not menu.NewGameBanner.anim:IsPlaying() then
        hasPendingNewGameBanner = false
        RSTATS:PlayNewGameBanner(menu)
    end
end