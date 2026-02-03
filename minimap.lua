local _, RSTATS = ...
local playerName = UnitName("player") .. "-" .. GetRealmName()
local eventFrame = CreateFrame("Frame")
local COLOR_HEX = "b69e86"

eventFrame:RegisterEvent("ADDON_LOADED")

local function PlayerKey()
    local name, realm = UnitFullName("player")
    name = name or UnitName("player") or "player"
    realm = realm or GetRealmName() or "Unknown"
    return name .. "-" .. realm
end

local function PlaceOnMinimap(btn, angle)
    if not Minimap or not Minimap.GetWidth then return end
    angle = tonumber(angle) or 220
    local radius = (Minimap:GetWidth() / 2) + 6
    local rad = math.rad(angle)
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

function RSTATS:InitializeMinimapIcon()
    if RSTATS.MinimapButton then
        local key = PlayerKey()
        local mm = RSTATS.Database[key] and RSTATS.Database[key].minimap
        if mm and mm.hide then
            RSTATS.MinimapButton:Hide()
        else
            RSTATS.MinimapButton:Show()
            PlaceOnMinimap(RSTATS.MinimapButton, mm and mm.minimapPos)
        end
        return
    end

    local btn = CreateFrame("Button", "RatedStats_MinimapButton", Minimap)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:EnableMouse(true)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    -- Blizzard-style minimap button visuals: background + border + masked icon.
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetAllPoints(btn)
    btn.bg = bg

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    -- The tracking border texture is meant to be larger than the 32x32 button.
    -- If you SetAllPoints it, you shrink the ring and it looks wrong.
    border:ClearAllPoints()
    border:SetPoint("CENTER", btn, "CENTER", 10.5, -10.5)
    border:SetSize(54, 54)
    btn.border = border

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\AddOns\\RatedStats\\RatedStats.tga")
    -- Inset so it sits inside the border ring (matches other minimap buttons).
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 6, -6)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -6, 6)
    btn.icon = icon

    -- Circular-ish mask so the icon doesn't look like a hard square.
    local mask = btn:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
    btn.iconMask = mask

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(btn)
    hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    hl:SetBlendMode("ADD")

    btn:SetScript("OnClick", function(_, button)
        if button == "LeftButton" then
            if RSTATS and RSTATS.Config and RSTATS.Config.Toggle then
                RSTATS.Config:Toggle()
            end
            return
        end

        -- RightButton
        if IsShiftKeyDown() and RSTATS and RSTATS.OpenSettings then
            RSTATS:OpenSettings()
            return
        end

        local module = "RatedStats_Achiev"
        local state = C_AddOns.GetAddOnEnableState(module, nil)
        if state > 0 then
            C_AddOns.DisableAddOn(module)
            print("RatedStats: Achiev module disabled. Reload required.")
        else
            C_AddOns.EnableAddOn(module)
            C_AddOns.LoadAddOn(module)
            print("RatedStats: Achiev module enabled.")
        end
        ReloadUI()
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(string.format("|cff%s%s|r", COLOR_HEX, "Rated Stats"))
        GameTooltip:AddLine(string.format("|cff%s%s|r to open your Rated Stats history.", COLOR_HEX, "Left-click"))

        local module = "RatedStats_Achiev"
        local enabled = (C_AddOns.GetAddOnEnableState(module, nil) > 0)
        local stateText = enabled and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"
        GameTooltip:AddLine(string.format("|cff%sRight-click|r to toggle Achievements Tracking: %s", COLOR_HEX, stateText))
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format("|cff%sShift+Right-click|r for Settings", COLOR_HEX))
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(s)
            local key = PlayerKey()
            local mm = RSTATS.Database[key] and RSTATS.Database[key].minimap
            if not mm then return end

            local mx, my = Minimap:GetCenter()
            if not mx or not my then return end

            local cx, cy = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale

            local dx, dy = (cx - mx), (cy - my)
            local ang = math.deg(math.atan2(dy, dx))
            if ang < 0 then ang = ang + 360 end

            mm.minimapPos = ang
            PlaceOnMinimap(s, ang)
        end)
    end)

    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    RSTATS.MinimapButton = btn

    local key = PlayerKey()
    local mm = RSTATS.Database[key] and RSTATS.Database[key].minimap
    if mm and mm.hide then
        btn:Hide()
    else
        btn:Show()
        PlaceOnMinimap(btn, mm and mm.minimapPos)
    end
end

eventFrame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName ~= "RatedStats" then return end
    if event == "PLAYER_LOGIN" then
        if RSTATS and RSTATS.InitializeMinimapIcon then
            RSTATS:InitializeMinimapIcon()
        end
        return
    end
    
    -- Proper Initialization: After saved variables loaded
    RSTATS_Database = RSTATS_Database or {}
    RSTATS.Database = RSTATS_Database
    
    local playerName = PlayerKey()
    RSTATS.Database[playerName] = RSTATS.Database[playerName] or {}
    RSTATS.Database[playerName].minimap = RSTATS.Database[playerName].minimap or {
        hide = false,
        minimapPos = 220
    }
	
	local charDB = RSTATS.Database[playerName]
	-- Create a settings table for Achievements tracking
	charDB.modules = charDB.modules or {}

    -- Only initialize after database is ready!
    RSTATS:InitializeMinimapIcon()
    
    eventFrame:UnregisterEvent("ADDON_LOADED") -- prevent further event firing
end)