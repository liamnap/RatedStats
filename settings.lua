local addonName, RSTATS = ...

-- Rated Stats: Settings (Retail Settings UI)
-- Uses Blizzard's Settings API (Dragonflight+).

local CATEGORY_NAME = "Rated Stats"
local RS_COLOR = "|cffb69e86"
local function RSPrint(msg)
    print(RS_COLOR .. msg .. "|r")
end

local function GetPlayerKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

-- "Update available" detection (Details/BGE style):
-- You cannot check CurseForge from inside WoW. You can only compare versions seen from other players via addon comms.
local UPDATECHECK_PREFIX_MAIN = "RSTATS_VER"
local UPDATECHECK_PREFIX_ACH  = "RSTATS_ACHV"

local function ParseTagVersion(v)
    if type(v) ~= "string" then return nil end
    v = v:gsub("%s+", "")

    -- Accept: v3.12 / v3.12-beta / 3.12
    local major, build, suffix = v:match("^v?(%d+)%.(%d+)(.*)$")
    if not major or not build then
        return nil
    end

    major = tonumber(major)
    build = tonumber(build)
    if not major or not build then
        return nil
    end

    local isBeta = false
    if suffix and suffix ~= "" then
        isBeta = (suffix:lower():find("beta", 1, true) ~= nil)
    end

    return major, build, isBeta
end

local function IsNewerVersion(theirV, myV)
    local tMaj, tBuild, tBeta = ParseTagVersion(theirV)
    local mMaj, mBuild, mBeta = ParseTagVersion(myV)
    if not tMaj or not mMaj then return false end

    if tMaj ~= mMaj then return tMaj > mMaj end
    if tBuild ~= mBuild then return tBuild > mBuild end

    -- Same numeric: release beats beta
    if mBeta and not tBeta then return true end
    return false
end

local function GetSendScope()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
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

    RSPrint(string.format("%s updated: %s", label, current))
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
        Settings.CreateCheckbox(category, setting, "Will announce when a newer version is seen in your group (and when you have updated).")
    end

    Settings.RegisterAddOnCategory(category)

    -- Achievements subcategory (only if the module is installed + enabled)
    local achievName = "Rated Stats - Achievements"
    local achievAddon = "RatedStats_Achiev"

    if C_AddOns and C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist(achievAddon)
        and C_AddOns.GetAddOnEnableState and (C_AddOns.GetAddOnEnableState(achievAddon, nil) ~= 0) then

        local subcategory, layout = Settings.RegisterVerticalLayoutSubcategory(category, achievName)

        -- Dropdown option containers (must not be nil; Blizzard asserts if they are)
        local optsSS = Settings.CreateControlTextContainer()
        optsSS:Add(0, "None")
        optsSS:Add(1, "Self")
        optsSS:Add(4, "Say")
        optsSS:Add(5, "Yell")
        optsSS:Add(3, "Instance")

        local opts2v2 = Settings.CreateControlTextContainer()
        opts2v2:Add(0, "None")
        opts2v2:Add(1, "Self")
        opts2v2:Add(4, "Say")
        opts2v2:Add(5, "Yell")
        opts2v2:Add(2, "Party")

        local opts3v3 = Settings.CreateControlTextContainer()
        opts3v3:Add(0, "None")
        opts3v3:Add(1, "Self")
        opts3v3:Add(4, "Say")
        opts3v3:Add(5, "Yell")
        opts3v3:Add(2, "Party")

        local optsRBG = Settings.CreateControlTextContainer()
        optsRBG:Add(0, "None")
        optsRBG:Add(1, "Self")
        optsRBG:Add(4, "Say")
        optsRBG:Add(5, "Yell")
        optsRBG:Add(7, "Party")
        optsRBG:Add(6, "Raid")
        optsRBG:Add(3, "Instance")

        local optsRBGB = Settings.CreateControlTextContainer()
        optsRBGB:Add(0, "None")
        optsRBGB:Add(1, "Self")
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
            Settings.CreateCheckbox(subcategory, setting, "Will announce when a newer version is seen in your group (and when you have updated).")
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

        if layout then
            -- Plain instructional text (HandyNotes style). Different client builds expose this initializer differently.
            local TextInit =
                _G.CreateSettingsListTextInitializer
                or (Settings and Settings.CreateSettingsListTextInitializer)

            local SubHeaderInit =
                _G.CreateSettingsListSubsectionHeaderInitializer
                or (Settings and Settings.CreateSettingsListSubsectionHeaderInitializer)

            if TextInit then
                layout:AddInitializer(TextInit("Options for Achievements Announcements"))
            elseif SubHeaderInit then
                -- Fallback: smaller than a full section header.
                layout:AddInitializer(SubHeaderInit("Options for Achievements Announcements"))
            elseif _G.CreateSettingsListSectionHeaderInitializer then
                -- Last resort (big header).
                layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Options for Achievements Announcements"))
            end
        end

        do
            local setting = Settings.RegisterAddOnSetting(
                subcategory,
                "RSTATS_ACHIEV_ANNOUNCE_SS",
                "achievAnnounceSS",
                db.settings,
                Settings.VarType.Number,
                "In SS announce to",
                3
            )
            Settings.CreateDropdown(subcategory, setting, function() return optsSS:GetData() end, nil)
        end

        do
            local setting = Settings.RegisterAddOnSetting(
                subcategory,
                "RSTATS_ACHIEV_ANNOUNCE_2V2",
                "achievAnnounce2v2",
                db.settings,
                Settings.VarType.Number,
                "In 2v2 announce to",
                2
            )
            Settings.CreateDropdown(subcategory, setting, function() return opts2v2:GetData() end, nil)
        end

        do
            local setting = Settings.RegisterAddOnSetting(
                subcategory,
                "RSTATS_ACHIEV_ANNOUNCE_3V3",
                "achievAnnounce3v3",
                db.settings,
                Settings.VarType.Number,
                "In 3v3 announce to",
                2
            )
            Settings.CreateDropdown(subcategory, setting, function() return opts3v3:GetData() end, nil)
        end

        do
            local setting = Settings.RegisterAddOnSetting(
                subcategory,
                "RSTATS_ACHIEV_ANNOUNCE_RBG",
                "achievAnnounceRBG",
                db.settings,
                Settings.VarType.Number,
                "In RBG announce to",
                1
            )
            Settings.CreateDropdown(subcategory, setting, function() return optsRBG:GetData() end, nil)
        end

        do
            local setting = Settings.RegisterAddOnSetting(
                subcategory,
                "RSTATS_ACHIEV_ANNOUNCE_RBGB",
                "achievAnnounceRBGB",
                db.settings,
                Settings.VarType.Number,
                "In RBGB announce to",
                1
            )
            Settings.CreateDropdown(subcategory, setting, function() return optsRBGB:GetData() end, nil)
        end
    end

    -- Battleground Enemies subcategory (only if the module is installed + enabled)
    local bgeName  = "Rated Stats - Battleground Enemies"
    local bgeAddon = "RatedStats_BattlegroundEnemies"

    if C_AddOns and C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist(bgeAddon)
        and C_AddOns.GetAddOnEnableState and (C_AddOns.GetAddOnEnableState(bgeAddon, nil) ~= 0) then

        local subcategory, layout = Settings.RegisterVerticalLayoutSubcategory(category, bgeName)

        local function NotifyBGE()
            if _G.RSTATS_BGE and type(_G.RSTATS_BGE.ApplySettings) == "function" then
                _G.RSTATS_BGE:ApplySettings()
            end
        end

        local TextInit =
            _G.CreateSettingsListTextInitializer
            or (Settings and Settings.CreateSettingsListTextInitializer)

        local SubHeaderInit =
            _G.CreateSettingsListSubsectionHeaderInitializer
            or (Settings and Settings.CreateSettingsListSubsectionHeaderInitializer)

        if layout and TextInit then
            layout:AddInitializer(TextInit("Enemy frames built from NAME_PLATE_UNIT_* events. Only enemies with an active nameplate can be shown."))
        elseif layout and SubHeaderInit then
            layout:AddInitializer(SubHeaderInit("Battleground Enemies"))
        end

        do
            local setting = Settings.RegisterAddOnSetting(
                subcategory,
                "RSTATS_BGE_ENABLED",
                "bgeEnabled",
                db.settings,
                Settings.VarType.Boolean,
                "Enable",
                true
            )
            setting:SetValueChangedCallback(function() NotifyBGE() end)
            Settings.CreateCheckbox(subcategory, setting, "Show enemy frames when in PvP instances.")
        end

        do
            local setting = Settings.RegisterAddOnSetting(
                subcategory,
                "RSTATS_BGE_LOCKED",
                "bgeLocked",
                db.settings,
                Settings.VarType.Boolean,
                "Lock frame",
                true
            )
            setting:SetValueChangedCallback(function() NotifyBGE() end)
            Settings.CreateCheckbox(subcategory, setting, "When unlocked, you can drag the frame to move it.")
        end

        do
            local optsLayout = Settings.CreateControlTextContainer()
            optsLayout:Add(1, "Single list")
            optsLayout:Add(2, "Grouped (sorted)")

            local setting = Settings.RegisterAddOnSetting(
                subcategory,
                "RSTATS_BGE_LAYOUT",
                "bgeLayout",
                db.settings,
                Settings.VarType.Number,
                "Layout",
                1
            )
            setting:SetValueChangedCallback(function() NotifyBGE() end)
            Settings.CreateDropdown(subcategory, setting, function() return optsLayout:GetData() end, nil)
        end

        do
            local setting = Settings.RegisterAddOnSetting(
                subcategory,
                "RSTATS_BGE_SHOW_ACHIEV_ICON",
                "bgeShowAchievIcon",
                db.settings,
                Settings.VarType.Boolean,
                "Show achievement icon",
                false
            )
            setting:SetValueChangedCallback(function() NotifyBGE() end)
            Settings.CreateCheckbox(subcategory, setting, "Shows an icon if Rated Stats - Achievements exposes an icon lookup API.")
        end

        do
            local setting = Settings.RegisterAddOnSetting(
                subcategory,
                "RSTATS_BGE_SHOW_POWER",
                "bgeShowPower",
                db.settings,
                Settings.VarType.Boolean,
                "Show power bar",
                true
            )
            setting:SetValueChangedCallback(function() NotifyBGE() end)
            Settings.CreateCheckbox(subcategory, setting, "Shows mana/energy/rage/etc (when available).")
        end

        do
            local opts = Settings.CreateControlTextContainer()
            opts:Add(1, "Current")
            opts:Add(2, "Current/Total")
            opts:Add(3, "%")

            local setting = Settings.RegisterAddOnSetting(
                subcategory,
                "RSTATS_BGE_HEALTH_TEXT",
                "bgeHealthTextMode",
                db.settings,
                Settings.VarType.Number,
                "Health text",
                2
            )
            setting:SetValueChangedCallback(function() NotifyBGE() end)
            Settings.CreateDropdown(subcategory, setting, function() return opts:GetData() end, nil)
        end

        do
            local setting = Settings.RegisterAddOnSetting(
                subcategory,
                "RSTATS_BGE_PREVIEW",
                "bgePreview",
                db.settings,
                Settings.VarType.Boolean,
                "Preview outside PvP",
                false
            )
            setting:SetValueChangedCallback(function() NotifyBGE() end)
            Settings.CreateCheckbox(subcategory, setting, "Shows the frame out of PvP so you can tune size/position.")
        end

        do
            local setting = Settings.RegisterAddOnSetting(
                subcategory,
                "RSTATS_BGE_PREVIEW_COUNT",
                "bgePreviewCount",
                db.settings,
                Settings.VarType.Number,
                "Preview rows",
                8
            )
            setting:SetValueChangedCallback(function() NotifyBGE() end)
            local options = Settings.CreateSliderOptions(1, 10, 1)
            if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label and options.SetLabelFormatter then
                options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
            end
            Settings.CreateSlider(subcategory, setting, options, "How many blank rows to show in preview mode.")
        end

        do
            local setting = Settings.RegisterAddOnSetting(
                subcategory,
                "RSTATS_BGE_COLUMNS",
                "bgeColumns",
                db.settings,
                Settings.VarType.Number,
                "Columns",
                1
            )
            setting:SetValueChangedCallback(function() NotifyBGE() end)
            local options = Settings.CreateSliderOptions(1, 8, 1)
            if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label and options.SetLabelFormatter then
                options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
            end
            Settings.CreateSlider(subcategory, setting, options, "Number of columns (e.g. 2 for 2x20).")
        end

        do
            local setting = Settings.RegisterAddOnSetting(
                subcategory,
                "RSTATS_BGE_ROWS_PER_COL",
                "bgeRowsPerCol",
                db.settings,
                Settings.VarType.Number,
                "Rows per column",
                20
            )
            setting:SetValueChangedCallback(function() NotifyBGE() end)
            local options = Settings.CreateSliderOptions(1, 40, 1)
            if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label and options.SetLabelFormatter then
                options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
            end
            Settings.CreateSlider(subcategory, setting, options, "Wrap after this many rows (e.g. 20 for 2x20).")
        end

        do
            local setting = Settings.RegisterAddOnSetting(
                subcategory,
                "RSTATS_BGE_COL_GAP",
                "bgeColGap",
                db.settings,
                Settings.VarType.Number,
                "Column gap",
                6
            )
            setting:SetValueChangedCallback(function() NotifyBGE() end)
            local options = Settings.CreateSliderOptions(0, 30, 1)
            if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label and options.SetLabelFormatter then
                options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
            end
            Settings.CreateSlider(subcategory, setting, options, "Space between columns.")
        end

        do
            local setting = Settings.RegisterAddOnSetting(
                subcategory,
                "RSTATS_BGE_ROW_WIDTH",
                "bgeRowWidth",
                db.settings,
                Settings.VarType.Number,
                "Row width",
                240
            )
            setting:SetValueChangedCallback(function() NotifyBGE() end)
            local options = Settings.CreateSliderOptions(50, 520, 1)
            if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label and options.SetLabelFormatter then
                options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
            end
            Settings.CreateSlider(subcategory, setting, options, "Width of each row.")
        end

        do
            local setting = Settings.RegisterAddOnSetting(
                subcategory,
                "RSTATS_BGE_ROW_HEIGHT",
                "bgeRowHeight",
                db.settings,
                Settings.VarType.Number,
                "Row height",
                18
            )
            setting:SetValueChangedCallback(function() NotifyBGE() end)
            local options = Settings.CreateSliderOptions(15, 80, 1)
            if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label and options.SetLabelFormatter then
                options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
            end
            Settings.CreateSlider(subcategory, setting, options, "Height of each row.")
        end

        do
            local setting = Settings.RegisterAddOnSetting(
                subcategory,
                "RSTATS_BGE_ROW_GAP",
                "bgeRowGap",
                db.settings,
                Settings.VarType.Number,
                "Row gap",
                2
            )
            setting:SetValueChangedCallback(function() NotifyBGE() end)
            local options = Settings.CreateSliderOptions(0, 10, 1)
            if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label and options.SetLabelFormatter then
                options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
            end
            Settings.CreateSlider(subcategory, setting, options, "Space between rows.")
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

    -- Comms-based "update available" checker
    local ver = CreateFrame("Frame")
    ver:RegisterEvent("CHAT_MSG_ADDON")
    ver:RegisterEvent("GROUP_ROSTER_UPDATE")
    ver:RegisterEvent("PLAYER_ENTERING_WORLD")

    local announcedMainFor = nil
    local announcedAchFor  = nil

    local function MaybeSendMyVersions(reason)
        if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end

        local db3 = GetPlayerDB()
        if not db3 then return end
        db3.settings = db3.settings or {}

        local scope = GetSendScope()
        if not scope then return end

        local myMainVer = C_AddOns.GetAddOnMetadata("RatedStats", "Version") or ""
        local myAchVer  = ""
        if C_AddOns.GetAddOnEnableState("RatedStats_Achiev", nil) ~= 0 then
            myAchVer = C_AddOns.GetAddOnMetadata("RatedStats_Achiev", "Version") or ""
        end

        -- Persisted "send once until state changes" guards
        local newestMain = db3.settings.mainNewestSeenVersion or ""
        local newestAch  = db3.settings.achievNewestSeenVersion or ""

        local sentMainVer   = db3.settings.mainLastBroadcastVersion or ""
        local sentMainSeen  = db3.settings.mainLastBroadcastNewestSeen or ""
        local sentAchVer    = db3.settings.achievLastBroadcastVersion or ""
        local sentAchSeen   = db3.settings.achievLastBroadcastNewestSeen or ""

        -- MAIN
        if myMainVer ~= "" and ParseTagVersion(myMainVer) then
            -- Send once if:
            --  - we haven't sent this installed version yet, OR
            --  - the "newest seen" state has advanced since the last time we sent
            if (sentMainVer ~= myMainVer) or (sentMainSeen ~= newestMain) then
                C_ChatInfo.SendAddonMessage(UPDATECHECK_PREFIX_MAIN, myMainVer, scope)
                db3.settings.mainLastBroadcastVersion = myMainVer
                db3.settings.mainLastBroadcastNewestSeen = newestMain
            end
        end

        -- ACHIEV
        if myAchVer ~= "" and ParseTagVersion(myAchVer) then
            if (sentAchVer ~= myAchVer) or (sentAchSeen ~= newestAch) then
                C_ChatInfo.SendAddonMessage(UPDATECHECK_PREFIX_ACH, myAchVer, scope)
                db3.settings.achievLastBroadcastVersion = myAchVer
                db3.settings.achievLastBroadcastNewestSeen = newestAch
            end
        end
    end

    local function SendMyVersions()
        if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end

        local scope = GetSendScope()
        if not scope then return end

        local now = GetTime()
        if (now - lastSendAt) < 15 then return end
        lastSendAt = now

        local myMainVer = C_AddOns.GetAddOnMetadata("RatedStats", "Version") or ""
        if myMainVer ~= "" then
            C_ChatInfo.SendAddonMessage(UPDATECHECK_PREFIX_MAIN, myMainVer, scope)
        end

        if C_AddOns.GetAddOnEnableState("RatedStats_Achiev", nil) ~= 0 then
            local myAchVer = C_AddOns.GetAddOnMetadata("RatedStats_Achiev", "Version") or ""
            if myAchVer ~= "" then
                C_ChatInfo.SendAddonMessage(UPDATECHECK_PREFIX_ACH, myAchVer, scope)
            end
        end
    end

    local function HandleIncoming(prefix, msg, sender)
        local db3 = GetPlayerDB()
        if not db3 then return end
        db3.settings = db3.settings or {}

        if prefix == UPDATECHECK_PREFIX_MAIN then
            if not db3.settings.mainTellUpdates then return end

            local myMainVer = C_AddOns.GetAddOnMetadata("RatedStats", "Version") or ""
            if not ParseTagVersion(myMainVer) then return end
            if not ParseTagVersion(msg) then return end

            if not IsNewerVersion(msg, myMainVer) then return end

            local stored = db3.settings.mainNewestSeenVersion
            if stored and ParseTagVersion(stored) and not IsNewerVersion(msg, stored) then
                return
            end
            db3.settings.mainNewestSeenVersion = msg

            if announcedMainFor ~= msg then
                RSPrint(string.format("Rated Stats update available: you have %s, seen %s from %s.", myMainVer, msg, sender or "someone"))
                announcedMainFor = msg
            end
            MaybeSendMyVersions("main_newer_seen")

        elseif prefix == UPDATECHECK_PREFIX_ACH then
            if C_AddOns.GetAddOnEnableState("RatedStats_Achiev", nil) == 0 then return end
            if not db3.settings.achievTellUpdates then return end

            local myAchVer = C_AddOns.GetAddOnMetadata("RatedStats_Achiev", "Version") or ""
            if not ParseTagVersion(myAchVer) then return end
            if not ParseTagVersion(msg) then return end

            if not IsNewerVersion(msg, myAchVer) then return end

            local stored = db3.settings.achievNewestSeenVersion
            if stored and ParseTagVersion(stored) and not IsNewerVersion(msg, stored) then
                return
            end
            db3.settings.achievNewestSeenVersion = msg

            if announcedAchFor ~= msg then
                RSPrint(string.format("Rated Stats - Achievements update available: you have %s, seen %s from %s.", myAchVer, msg, sender or "someone"))
                announcedAchFor = msg
            end
            MaybeSendMyVersions("ach_newer_seen")
        end
    end

    ver:SetScript("OnEvent", function(_, event, prefix, msg, _, sender)
        if event == "CHAT_MSG_ADDON" then
            if prefix ~= UPDATECHECK_PREFIX_MAIN and prefix ~= UPDATECHECK_PREFIX_ACH then return end
            if type(msg) ~= "string" or msg == "" then return end
            HandleIncoming(prefix, msg, sender)
            return
        end

        -- group/zone changes: broadcast ONCE (persisted across reloads) unless state changed
        MaybeSendMyVersions(event)
    end)

    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(UPDATECHECK_PREFIX_MAIN)
        C_ChatInfo.RegisterAddonMessagePrefix(UPDATECHECK_PREFIX_ACH)
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(2, function() MaybeSendMyVersions("initial") end)
    else
        MaybeSendMyVersions("initial")
    end
end)

