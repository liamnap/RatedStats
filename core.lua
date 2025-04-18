-- core.lua
local _, RSTATS = ...
_G.RSTATS = RSTATS or {}
_G.RSTATS.Config = RSTATS.Config or {}

-- Define color hex code once
RSTATS.Config.ThemeColor = "00ccff"-- core.lua (continued)
function RSTATS:ColorText(text)
    local hex = self.Config.ThemeColor:upper()
    return string.format("|cff%s%s|r", hex, text)
end
