-- Author      : liamp
-- Create Date : 7/26/2024 7:16:49 PM

local _, RSTATS = ...; -- Namespace
RSTATS.Database = RSTATS_Database or {}
local Database = RSTATS.Database

RSTATS.Config = RSTATS.Config or {}
local Config = RSTATS.Config

--------------------------------------
-- Custom Slash Command
--------------------------------------
RSTATS.commands = {
	["config"] = Config.Toggle, -- this is a function (no knowledge of Config object)
	
	["help"] = function()
		print(" ");
		RSTATS:Print("List of slash commands:")
		RSTATS:Print("|cff00cc66/ratedstats config|r - shows config menu");
		RSTATS:Print("|cff00cc66/ratedstats help|r - shows help info");
		print(" ");
	end,
	
	["example"] = {
		["test"] = function(...)
			RSTATS:Print("My Value:", tostringall(...));
		end
	}
};

local function HandleSlashCommands(str)	
	if (#str == 0) then	
		-- User just entered "/ratedstats" with no additional args.
		RSTATS.commands.help();
		return;		
	end	
	
	local args = {};
	for _, arg in ipairs({ string.split(' ', str) }) do
		if (#arg > 0) then
			table.insert(args, arg);
		end
	end
	
	local path = RSTATS.commands; -- required for updating found table.
	
	for id, arg in ipairs(args) do
		if (#arg > 0) then -- if string length is greater than 0.
			arg = arg:lower();			
			if (path[arg]) then
				if (type(path[arg]) == "function") then				
					-- all remaining args passed to our function!
					path[arg](select(id + 1, unpack(args))); 
					return;					
				elseif (type(path[arg]) == "table") then				
					path = path[arg]; -- another sub-table found!
				end
			else
				-- does not exist!
				RSTATS.commands.help();
				return;
			end
		end
	end
end

function RSTATS:Print(...)
    local hex = "00ccff" -- Use the hex color directly
    local prefix = string.format("|cff%s%s|r", hex:upper(), "Rated Stats:");    
    DEFAULT_CHAT_FRAME:AddMessage(string.join(" ", prefix, ...));
end

-- WARNING: self automatically becomes events frame!
function RSTATS:init(event, name)
	if (name ~= "RatedStats") then return end 

	-- allows using left and right buttons to move through chat 'edit' box
	for i = 1, NUM_CHAT_WINDOWS do
		_G["ChatFrame"..i.."EditBox"]:SetAltArrowKeyMode(false);
	end

	SLASH_RatedStats1 = "/ratedstats";
	SlashCmdList.RatedStats = HandleSlashCommands;
	
    RSTATS:Print("Welcome back", UnitName("player").."!");
end

local events = CreateFrame("Frame");
events:RegisterEvent("ADDON_LOADED");
events:SetScript("OnEvent", RSTATS.init);