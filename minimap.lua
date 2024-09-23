local _, RSTATS = ... -- Use the existing namespace
local playerName = UnitName("player") .. "-" .. GetRealmName()

-- Ensure that the character-specific database exists and is properly formatted for LibDBIcon
RSTATS.Database = RSTATS_Database or {} -- Global saved variable
RSTATS.Database[playerName] = RSTATS.Database[playerName] or {}

-- Ensure that the minimap table follows LibDBIcon's format
RSTATS.Database[playerName].minimap = RSTATS.Database[playerName].minimap or { hide = false, minimapPos = 220 }

local LDB = LibStub("LibDataBroker-1.1"):NewDataObject("RatedStats", {
    type = "data source",
    text = "RatedStats",
    icon = "Interface\\AddOns\\RatedStats\\RatedStats.tga", -- Path to your icon
    OnClick = function(_, button)
        if button == "LeftButton" then
            RSTATS.Config:Toggle() -- Toggle the config menu on left-click
        elseif button == "RightButton" then
            print("Right-click: Save position triggered.") -- Debug message for testing
        end
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine("RatedStats")
        tooltip:AddLine("Left-click to open the config.")
        tooltip:AddLine("Right-click to save minimap position.")
    end,
})

local icon = LibStub("LibDBIcon-1.0")

-- Function to debug and save the new minimap position
local function SaveMinimapPosition()
    -- Since LibDBIcon automatically saves the position, we're only using this for debug purposes
    local newpos = RSTATS.Database[playerName].minimap.minimapPos
    if newpos then
        print("New minimap position saved:", newpos)
    else
        print("Error: newpos is nil.")
    end
end

-- Initialize and register the minimap icon with LibDBIcon
function RSTATS:InitializeMinimapIcon()
    -- Register the icon using the character-specific minimap position from RSTATS.Database
    if not icon:IsRegistered("RatedStats") then
        print("Registering RatedStats minimap icon.")
        -- Register the minimap icon with LibDBIcon
        icon:Register("RatedStats", LDB, RSTATS.Database[playerName].minimap)
        print("Minimap icon registered with position:", RSTATS.Database[playerName].minimap.minimapPos)
    else
        print("Minimap icon is already registered.")
    end

    -- Hook into the drag stop event for debugging and position updating
    local minimapButton = icon:GetMinimapButton("RatedStats")
    if minimapButton then
        minimapButton:HookScript("OnDragStop", function(self)
            print("Minimap icon dragged to new position.")
            -- Since LibDBIcon should handle saving, just log the new position
            SaveMinimapPosition()
        end)
    end
end

RSTATS:InitializeMinimapIcon()
