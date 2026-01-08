local addonName, RSTATS = ...

-- Rated Stats: Settings (Retail Settings UI)
-- Uses Blizzard's Settings API (Dragonflight+).

local CATEGORY_NAME = "Rated Stats"

local function GetPlayerKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

local function GetPlayerDB()
    -- Ensure the SavedVariables reference is wired up.
    if type(LoadData) == "function" then
        LoadData()
    end

    if not RSTATS or not RSTATS.Database then
        return nil
    end

    local key = GetPlayerKey()
    return RSTATS.Database[key]
end

function RSTATS:OpenSettings()
    if Settings and Settings.OpenToCategory and self and self.SettingsCategoryID then
        Settings.OpenToCategory(self.SettingsCategoryID)
    end
end

local function MaybeAnnounceVersion(db, enabledKey, lastSeenKey, addon, label)
    if not db or not db.settings then return end
    if not db.settings[enabledKey] then return end

    local current = C_AddOns.GetAddOnMetadata(addon, "Version")
    if not current or current == "" then
        return
    end

    local last = db.settings[lastSeenKey]
    if last == current then
        return
    end

    -- First install: just store the version silently.
    if last == nil then
        db.settings[lastSeenKey] = current
        return
    end

    print(string.format("|cffb69e86%s|r updated: %s", label, current))
    db.settings[lastSeenKey] = current
end

EventUtil.ContinueOnAddOnLoaded("RatedStats", function()
    local db = GetPlayerDB()
    if not db then return end
    db.settings = db.settings or {}

    -- Main addon category
    local category = Settings.RegisterVerticalLayoutCategory(CATEGORY_NAME)
    -- Store the ID so the UI button can reliably open the correct page later
    RSTATS.SettingsCategoryID = category:GetID()
    do
        local setting = Settings.RegisterAddOnSetting(
            category,
            "RSTATS_MAIN_TELL_UPDATES",
            "mainTellUpdates",
            db.settings,
            Settings.VarType.Boolean,
            "Tell me of new updates",
            true
        )
        Settings.CreateCheckbox(category, setting, "Will announce on login if updates are available.")
    end

    Settings.RegisterAddOnCategory(category)

    -- Login announcements (main + Achievements module)
    local login = CreateFrame("Frame")
    login:RegisterEvent("PLAYER_LOGIN")
    login:SetScript("OnEvent", function()
        local db2 = GetPlayerDB()
        if not db2 then return end
        db2.settings = db2.settings or {}

        MaybeAnnounceVersion(db2, "mainTellUpdates", "mainLastSeenVersion", "RatedStats", "Rated Stats")

        -- Only announce Achievements updates if the module is enabled.
        if C_AddOns.GetAddOnEnableState("RatedStats_Achiev", nil) ~= 0 then
            MaybeAnnounceVersion(db2, "achievTellUpdates", "achievLastSeenVersion", "RatedStats_Achiev", "Rated Stats - Achievements")
        end
    end)
end)
