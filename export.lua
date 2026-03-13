-- Rated Stats: Export / Wipe utilities
-- Provides a copy-to-clipboard style window (EditBox) to export SavedVariables for the current character,
-- and a safe wipe function for the current character's database.

local RS_COLOR = "|cffb69e86"
local function RSPrint(msg)
    print(RS_COLOR .. msg .. "|r")
end

local function GetPlayerKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

-- Basic Lua table serializer (safe-ish):
-- - Skips functions/userdata/threads
-- - Skips secret values (12.0+)
-- - Stable key ordering
local function EscapeString(s)
    s = s:gsub("\\", "\\\\")
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    s = s:gsub("\t", "\\t")
    s = s:gsub("\"", "\\\"")
    return "\"" .. s .. "\""
end

local function IsSecret(v)
    if type(issecretvalue) == "function" then
        local ok, ret = pcall(issecretvalue, v)
        return ok and ret
    end
    return false
end

local function SerializeValue(v, indent, visited)
    local t = type(v)

    if IsSecret(v) then
        return "nil"
    end

    if t == "nil" then
        return "nil"
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    elseif t == "string" then
        return EscapeString(v)
    elseif t == "table" then
        if visited[v] then
            return "nil" -- avoid cycles
        end
        visited[v] = true

        local pad = string.rep(" ", indent)
        local pad2 = string.rep(" ", indent + 2)

        -- collect keys
        local keys = {}
        for k in pairs(v) do
            local kt = type(k)
            if kt == "string" or kt == "number" then
                table.insert(keys, k)
            end
        end

        table.sort(keys, function(a, b)
            local ta, tb = type(a), type(b)
            if ta ~= tb then
                return ta < tb
            end
            return a < b
        end)

        local out = {}
        table.insert(out, "{\n")
        for _, k in ipairs(keys) do
            local keyStr
            if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                keyStr = k
            else
                keyStr = "[" .. SerializeValue(k, indent + 2, visited) .. "]"
            end

            local valStr = SerializeValue(v[k], indent + 2, visited)
            if valStr ~= nil then
                table.insert(out, pad2 .. keyStr .. " = " .. valStr .. ",\n")
            end
        end
        table.insert(out, pad .. "}")
        visited[v] = nil
        return table.concat(out)
    else
        return "nil"
    end
end

local function BuildExportString()
    if type(LoadData) == "function" then
        LoadData()
    end

    local key = GetPlayerKey()
    if not RSTATS_Database or not RSTATS_Database[key] then
        return "-- Rated Stats export\n-- No data found for: " .. key .. "\n"
    end

    local payload = RSTATS_Database[key]
    local body = SerializeValue(payload, 0, {})
    if not body then
        return "-- Rated Stats export\n-- Failed to serialize for: " .. key .. "\n"
    end

    return "-- Rated Stats export\n-- Character: " .. key .. "\n-- Generated: " .. date("%Y-%m-%d %H:%M:%S") .. "\n\n" ..
           "return " .. body .. "\n"
end

local exportFrame

local function EnsureExportFrame()
    if exportFrame then return end

    exportFrame = CreateFrame("Frame", "RatedStatsExportFrame", UIParent, "BasicFrameTemplateWithInset")
    exportFrame:SetSize(780, 520)
    exportFrame:SetPoint("CENTER")
    exportFrame:SetFrameStrata("DIALOG")
    exportFrame:Hide()

    exportFrame.TitleText:SetText("Rated Stats - Export Data")

    -- NOTE: In some UI load orders, passing an inherits/template string to CreateFontString
    -- can result in an unset/invalid font, and the next SetText call can throw
    -- "Wrong object type for function". Set the FontObject explicitly instead.
    local info = exportFrame:CreateFontString(nil, "OVERLAY")
    info:SetFontObject(GameFontHighlightSmall)
    info:SetPoint("TOPLEFT", exportFrame.InsetBg, "TOPLEFT", 10, -8)
    info:SetPoint("TOPRIGHT", exportFrame.InsetBg, "TOPRIGHT", -10, -8)
    -- Some clients throw "Wrong object type for function" on SetJustifyH even though this is a FontString.
    -- It is purely cosmetic, so guard it.
    if info.SetJustifyH then
        info:SetJustifyH("LEFT")
    end
    info:SetText("Select all (Ctrl+A) and copy (Ctrl+C). Paste into a file if you want to keep a backup.")

    -- Parent the scroll frame to the main frame (InsetBg is a texture in this template).
    local scroll = CreateFrame("ScrollFrame", nil, exportFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", exportFrame.InsetBg, "TOPLEFT", 8, -30)
    scroll:SetPoint("BOTTOMRIGHT", exportFrame.InsetBg, "BOTTOMRIGHT", -30, 10)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(720)
    edit:SetTextInsets(6, 6, 6, 6)
    edit:SetScript("OnEscapePressed", function() exportFrame:Hide() end)

    scroll:SetScrollChild(edit)
    exportFrame.EditBox = edit

    -- Refresh text each time it opens
    exportFrame:SetScript("OnShow", function()
        exportFrame.EditBox:SetText(BuildExportString())
        exportFrame.EditBox:HighlightText()
    end)

    -- Right-click quick select
    exportFrame.EditBox:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            self:HighlightText()
        end
    end)
end

function RSTATS:OpenExportWindow()
    EnsureExportFrame()
    exportFrame:Show()
end

StaticPopupDialogs["RSTATS_CONFIRM_WIPE_DB"] = {
    text = "Wipe Rated Stats database for this character?\n\nThis cannot be undone.",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        if RSTATS and RSTATS.WipeDatabase then
            RSTATS:WipeDatabase()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function RSTATS:ConfirmWipeDatabase()
    StaticPopup_Show("RSTATS_CONFIRM_WIPE_DB")
end

function RSTATS:WipeDatabase()
    local key = GetPlayerKey()
    if not RSTATS_Database then
        RSTATS_Database = {}
    end

    RSTATS_Database[key] = {}

    if type(LoadData) == "function" then
        LoadData()
    end

    RSPrint("Rated Stats database wiped for: " .. key)
    RSPrint("Recommendation: /reload")
end