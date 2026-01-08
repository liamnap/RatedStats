local _, RSTATS = ...
local playerName = UnitName("player") .. "-" .. GetRealmName()
local eventFrame = CreateFrame("Frame")
local COLOR_HEX = "b69e86"

eventFrame:RegisterEvent("ADDON_LOADED")

local LDB = LibStub("LibDataBroker-1.1"):NewDataObject("RatedStats", {
    type = "data source",
    text = string.format("|cff%s%s|r", COLOR_HEX, "RatedStats"),
    icon = "Interface\\AddOns\\RatedStats\\RatedStats.tga",
    OnClick = function(_, button)
        if button == "LeftButton" then
            RSTATS.Config:Toggle()

        elseif button == "RightButton" then

            -- Shift + Right-click → open settings
            if IsShiftKeyDown() then
                RSTATS.Config:Toggle()
                return
            end

			-- 1) Use the C_AddOns API for your LOD add-on
			local module = "RatedStats_Achiev"
			local state = C_AddOns.GetAddOnEnableState(module, nil)
			if state > 0 then
				-- currently enabled → disable
				C_AddOns.DisableAddOn(module)
				print("RatedStats: Achiev module disabled. Reload required.")
			else
				-- currently disabled → enable + load
				C_AddOns.EnableAddOn(module)
				C_AddOns.LoadAddOn(module)
				print("RatedStats: Achiev module enabled.")
			end

            -- 2) Persist changes by reloading
            ReloadUI()
        end
    end,
    OnTooltipShow = function(tooltip)
		local key = UnitName("player").."-"..GetRealmName()
		local db  = RSTATS.Database[key]
		
		tooltip:AddLine(string.format("|cff%s%s|r", COLOR_HEX, "Rated Stats"))
	
		tooltip:AddLine(string.format("|cff%s%s|r to open your Rated Stats history.", COLOR_HEX, "Left-click"))
	
		-- Show current on/off state:
		local module = "RatedStats_Achiev"
		local enabled = (C_AddOns.GetAddOnEnableState(module, nil)  > 0)
		local state = enabled and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"
	
		tooltip:AddLine(string.format(
			"|cff%sRight-click|r to toggle Achievements Tracking: %s",
			COLOR_HEX, state
		))
        -- Spacer + settings hint
        tooltip:AddLine(" ")
        tooltip:AddLine(string.format(
            "|cff%sShift+Right-click|r for Settings",
            COLOR_HEX
        ))
	end,
})

local icon = LibStub("LibDBIcon-1.0")

local function SaveMinimapPosition()
    local minimapButton = icon:GetMinimapButton("RatedStats")
    if minimapButton then
        local newpos = RSTATS.Database[playerName].minimap.minimapPos
    end
end

function RSTATS:InitializeMinimapIcon()
    if not icon:IsRegistered("RatedStats") then
        icon:Register("RatedStats", LDB, RSTATS.Database[playerName].minimap)
    end

    local minimapButton = icon:GetMinimapButton("RatedStats")
    if minimapButton then
        minimapButton:HookScript("OnDragStop", function(self)
            SaveMinimapPosition()
        end)
    end
end

eventFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "RatedStats" then return end
    
    -- Proper Initialization: After saved variables loaded
    RSTATS_Database = RSTATS_Database or {}
    RSTATS.Database = RSTATS_Database
    
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

    -- Properly handle OnDragStop event
    local minimapButton = icon:GetMinimapButton("RatedStats")
    if minimapButton then
        minimapButton:HookScript("OnDragStop", function(self)
            SaveMinimapPosition()
        end)
    end
    
    eventFrame:UnregisterEvent("ADDON_LOADED") -- prevent further event firing
end)