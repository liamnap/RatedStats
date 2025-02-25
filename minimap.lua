local _, RSTATS = ...
local playerName = UnitName("player") .. "-" .. GetRealmName()
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")

local LDB = LibStub("LibDataBroker-1.1"):NewDataObject("RatedStats", {
    type = "data source",
    text = "RatedStats",
    icon = "Interface\\AddOns\\RatedStats\\RatedStats.tga",
    OnClick = function(_, button)
        if button == "LeftButton" then
            RSTATS.Config:Toggle()
        end
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine("RatedStats")
        tooltip:AddLine("Left-click to open the config.")
        tooltip:AddLine("Right-click to save minimap position.")
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