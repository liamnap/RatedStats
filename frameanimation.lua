local RatedStats, Namespace = ...
local RSTATS = _G.RSTATS

if not RSTATS then return end

local hasPlayedMenuIntroThisSession = false

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