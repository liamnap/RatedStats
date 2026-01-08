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

    -- Achievements subcategory (only if the module is installed + enabled)
    local achievName = "Rated Stats - Achievements"
    local achievAddon = "RatedStats_Achiev"

    local function GetAnnounceOptionsFor(kind)
        local container = Settings.CreateControlTextContainer()

        if kind == "SS" then
            -- SS - none/self/say/yell/instance
            container:Add(0, "None")
            container:Add(1, "Self (print)")
            container:Add(4, "Say")
            container:Add(5, "Yell")
            container:Add(3, "Instance")
            return container
        end

        if kind == "2V2" then
            -- 2s - none/self/say/yell/party
            container:Add(0, "None")
            container:Add(1, "Self (print)")
            container:Add(4, "Say")
            container:Add(5, "Yell")
            container:Add(2, "Party")
            return container
        end

        if kind == "3V3" then
            -- 3s - none/self/say/yell/party
            container:Add(0, "None")
            container:Add(1, "Self (print)")
            container:Add(4, "Say")
            container:Add(5, "Yell")
            container:Add(2, "Party")
            return container
        end

        if kind == "RBG" then
            -- RBG - none/self/say/yell/party(only5)/raid/instance
            container:Add(0, "None")
            container:Add(1, "Self (print)")
            container:Add(4, "Say")
            container:Add(5, "Yell")
            container:Add(7, "Party (only 5)")
            container:Add(6, "Raid")
            container:Add(3, "Instance")
            return container
        end

        if kind == "RBGB" then
            -- RBGB - none/self/say/yell/instance
            container:Add(0, "None")
            container:Add(1, "Self (print)")
            container:Add(4, "Say")
            container:Add(5, "Yell")
            container:Add(3, "Instance")
            return container
        end

        return container
    end

    if C_AddOns and C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist(achievAddon)
        and C_AddOns.GetAddOnEnableState and (C_AddOns.GetAddOnEnableState(achievAddon, nil) ~= 0) then

        local subcategory, layout = Settings.RegisterVerticalLayoutSubcategory(category, achievName)

        -- Dropdown option containers (must not be nil; Blizzard asserts if they are)
        local optsSS = Settings.CreateControlTextContainer()
        optsSS:Add(0, "None")
        optsSS:Add(1, "Self (print)")
        optsSS:Add(4, "Say")
        optsSS:Add(5, "Yell")
        optsSS:Add(3, "Instance")

        local opts2v2 = Settings.CreateControlTextContainer()
        opts2v2:Add(0, "None")
        opts2v2:Add(1, "Self (print)")
        opts2v2:Add(4, "Say")
        opts2v2:Add(5, "Yell")
        opts2v2:Add(2, "Party")

        local opts3v3 = Settings.CreateControlTextContainer()
        opts3v3:Add(0, "None")
        opts3v3:Add(1, "Self (print)")
        opts3v3:Add(4, "Say")
        opts3v3:Add(5, "Yell")
        opts3v3:Add(2, "Party")

        local optsRBG = Settings.CreateControlTextContainer()
        optsRBG:Add(0, "None")
        optsRBG:Add(1, "Self (print)")
        optsRBG:Add(4, "Say")
        optsRBG:Add(5, "Yell")
        optsRBG:Add(7, "Party (only 5)")
        optsRBG:Add(6, "Raid")
        optsRBG:Add(3, "Instance")

        local optsRBGB = Settings.CreateControlTextContainer()
        optsRBGB:Add(0, "None")
        optsRBGB:Add(1, "Self (print)")
        optsRBGB:Add(4, "Say")
        optsRBGB:Add(5, "Yell")
        optsRBGB:Add(3, "Instance")

        do
            local setting = Settings.RegisterAddOnSetting(
                subcategory,
                "RSTATS_ACHIEV_TELL_UPDATES",
                "achievTellUpdates",
                db.settings,
                Settings.VarType.Boolean,
                "Tell me of new updates",
                true
            )
            Settings.CreateCheckbox(subcategory, setting, "Will announce on login if updates are available.")
        end

        do
            local setting = Settings.RegisterAddOnSetting(
                subcategory,
                "RSTATS_ACHIEV_ANNOUNCE_ON_QUEUE",
                "achievAnnounceOnQueue",
                db.settings,
                Settings.VarType.Boolean,
                "Announce on PvP queue",
                true
            )
            Settings.CreateCheckbox(subcategory, setting, "Will announce party/raid achievements when you all accept the PvP queue.")
        end

        if layout and CreateSettingsListSectionHeaderInitializer then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(
                "The below options let you choose how you would like to see or share the achievements of friendly and enemy players detected during the game modes."
            ))
        end

        do
            local setting = Settings.RegisterAddOnSetting(
                subcategory,
                "RSTATS_ACHIEV_ANNOUNCE_SS",
                "achievAnnounceSS",
                db.settings,
                Settings.VarType.Number,
                "Announce Solo Shuffle Achievements to",
                3
            )
            Settings.CreateDropdown(subcategory, setting, optsSS, nil)
        end

        do
            local setting = Settings.RegisterAddOnSetting(
                subcategory,
                "RSTATS_ACHIEV_ANNOUNCE_2V2",
                "achievAnnounce2v2",
                db.settings,
                Settings.VarType.Number,
                "Announce 2v2 Achievements to",
                2
            )
            Settings.CreateDropdown(subcategory, setting, opts2v2, nil)
        end

        do
            local setting = Settings.RegisterAddOnSetting(
                subcategory,
                "RSTATS_ACHIEV_ANNOUNCE_3V3",
                "achievAnnounce3v3",
                db.settings,
                Settings.VarType.Number,
                "Announce 3v3 Achievements to",
                2
            )
            Settings.CreateDropdown(subcategory, setting, opts3v3, nil)
        end

        do
            local setting = Settings.RegisterAddOnSetting(
                subcategory,
                "RSTATS_ACHIEV_ANNOUNCE_RBG",
                "achievAnnounceRBG",
                db.settings,
                Settings.VarType.Number,
                "Announce RBG Achievements to",
                1
            )
            Settings.CreateDropdown(subcategory, setting, optsRBG, nil)
        end

        do
            local setting = Settings.RegisterAddOnSetting(
                subcategory,
                "RSTATS_ACHIEV_ANNOUNCE_RBGB",
                "achievAnnounceRBGB",
                db.settings,
                Settings.VarType.Number,
                "Announce RBGB Achievements to",
                1
            )
            Settings.CreateDropdown(subcategory, setting, optsRBGB, nil)
        end
    end

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
