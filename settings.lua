local addonName, RSTATS = ...

-- Rated Stats - Achievements: Settings (Retail Settings UI)

local PARENT_CATEGORY_NAME = "Rated Stats"
local CATEGORY_NAME = "Rated Stats - Achievements"

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

local function GetAnnounceOptions()
    local container = Settings.CreateControlTextContainer()
    container:Add(1, "Self (print)")
    container:Add(2, "Party")
    container:Add(3, "Instance")
    container:Add(4, "Say")
    container:Add(5, "Yell")
    return container
end

EventUtil.ContinueOnAddOnLoaded("RatedStats_Achiev", function()
    local db = GetPlayerDB()
    if not db then return end
    db.settings = db.settings or {}

    local parentCategory = Settings.GetCategory(PARENT_CATEGORY_NAME)
    if not parentCategory then
        -- Parent category should be created by the main addon.
        return
    end

    local category, layout = Settings.RegisterVerticalLayoutSubcategory(parentCategory, CATEGORY_NAME)

    do
        local setting = Settings.RegisterAddOnSetting(
            category,
            "RSTATS_ACHIEV_TELL_UPDATES",
            "achievTellUpdates",
            db.settings,
            Settings.VarType.Boolean,
            "Tell me of new updates",
            true
        )
        Settings.CreateCheckbox(category, setting, "Will announce on login if updates are available.")
    end

    do
        local setting = Settings.RegisterAddOnSetting(
            category,
            "RSTATS_ACHIEV_ANNOUNCE_ON_QUEUE",
            "achievAnnounceOnQueue",
            db.settings,
            Settings.VarType.Boolean,
            "Announce on PvP queue",
            true
        )
        Settings.CreateCheckbox(category, setting, "Will announce party/raid achievements when you all accept the PvP queue.")
    end

    if layout and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(
            "The below options let you choose how you would like to see or share the achievements of friendly and enemy players detected during the game modes."
        ))
    end

    do
        local setting = Settings.RegisterAddOnSetting(
            category,
            "RSTATS_ACHIEV_ANNOUNCE_SS",
            "achievAnnounceSS",
            db.settings,
            Settings.VarType.Number,
            "Announce Solo Shuffle Achievements to",
            3
        )
        Settings.CreateDropdown(category, setting, GetAnnounceOptions, nil)
    end

    do
        local setting = Settings.RegisterAddOnSetting(
            category,
            "RSTATS_ACHIEV_ANNOUNCE_2V2",
            "achievAnnounce2v2",
            db.settings,
            Settings.VarType.Number,
            "Announce 2v2 Achievements to",
            2
        )
        Settings.CreateDropdown(category, setting, GetAnnounceOptions, nil)
    end

    do
        local setting = Settings.RegisterAddOnSetting(
            category,
            "RSTATS_ACHIEV_ANNOUNCE_3V3",
            "achievAnnounce3v3",
            db.settings,
            Settings.VarType.Number,
            "Announce 3v3 Achievements to",
            2
        )
        Settings.CreateDropdown(category, setting, GetAnnounceOptions, nil)
    end

    do
        local setting = Settings.RegisterAddOnSetting(
            category,
            "RSTATS_ACHIEV_ANNOUNCE_RBG",
            "achievAnnounceRBG",
            db.settings,
            Settings.VarType.Number,
            "Announce RBG Achievements to",
            1
        )
        Settings.CreateDropdown(category, setting, GetAnnounceOptions, nil)
    end

    do
        local setting = Settings.RegisterAddOnSetting(
            category,
            "RSTATS_ACHIEV_ANNOUNCE_RBGB",
            "achievAnnounceRBGB",
            db.settings,
            Settings.VarType.Number,
            "Announce RBGB Achievements to",
            1
        )
        Settings.CreateDropdown(category, setting, GetAnnounceOptions, nil)
    end
end)