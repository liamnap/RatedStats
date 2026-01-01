-- core.lua
local _, RSTATS = ...
_G.RSTATS = RSTATS

----------------------------------------
-- 1) Initialize your Saved-Vars table  --
----------------------------------------
-- Make sure RSTATS.Database always exists
RSTATS.Database = RSTATS.Database or {}

----------------------------------------
-- 2) Module registry & APIs          --
----------------------------------------
RSTATS.Modules = {}

function RSTATS:RegisterModule(id, title, defaultEnabled)
    self.Modules[id] = {
      title          = title,
      defaultEnabled = defaultEnabled,
      loaded         = false,
    }
end

function RSTATS:ToggleModule(id, enabled)
    local mod = self.Modules[id]
    if not mod then return end

    local key = UnitName("player").."-"..GetRealmName()
    local db  = self.Database[key]
    db.modules = db.modules or {}
    db.modules[id] = enabled

    if enabled and not mod.loaded then
        C_AddOns.LoadAddOn("RatedStats_" .. id)
        mod.loaded = true
    end

    ReloadUI()
end

----------------------------------------
-- 3) Them­ing & Helpers                --
----------------------------------------
RSTATS.Config = RSTATS.Config or {}
RSTATS.Config.ThemeColor = "cffb69e86"

function RSTATS:ColorText(text)
    local hex = self.Config.ThemeColor:upper()
    return string.format("|cffb69e86%s%s|r", hex, text)
end

function GetUnicodeSafeFont()
    local locale = GetLocale()
    if locale == "koKR" then
        return "Fonts\\2002.TTF"
    elseif locale == "zhCN" then
        return "Fonts\\ARKai_T.ttf"
    elseif locale == "zhTW" then
        return "Fonts\\blei00d.TTF"
    else
        return "Fonts\\ARIALN.TTF"
    end
end

----------------------------------------
-- 4) Bootstrap & Auto-load Modules  --
----------------------------------------
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(self, _, addon)
        if addon ~= "RatedStats" then return end

        local key = UnitName("player").."-"..GetRealmName()

        -- Guarantee the per-char table exists
        RSTATS.Database[key] = RSTATS.Database[key] or {}

        local db = RSTATS.Database[key]

        -- Guarantee the modules sub-table exists
        db.modules = db.modules or {}

        -- Now load each module by saved/default state
        for id, mod in pairs(RSTATS.Modules) do
            local enabled = (db.modules[id] == nil) and mod.defaultEnabled or db.modules[id]
            if enabled then
                C_AddOns.LoadAddOn("RatedStats_" .. id)
                mod.loaded = true
            end
        end

        f:UnregisterEvent("ADDON_LOADED")
    end)
end
