local M = {}
local OFFSET_MIN = -200
local OFFSET_MAX = 200
local DISPLAY_MODE_LAST = "last"
local DISPLAY_MODE_FINAL = "final"
local DISPLAY_MODE_BOTH = "both"
local DISPLAY_MODE_MIN_INDEX = 0
local DISPLAY_MODE_MAX_INDEX = 2
local DISPLAY_MODE_BY_INDEX = {
    [0] = DISPLAY_MODE_LAST,
    [1] = DISPLAY_MODE_FINAL,
    [2] = DISPLAY_MODE_BOTH
}
local DISPLAY_MODE_INDEX_BY_MODE = {
    [DISPLAY_MODE_LAST] = 0,
    [DISPLAY_MODE_FINAL] = 1,
    [DISPLAY_MODE_BOTH] = 2
}
local DISPLAY_MODE_LABELS = {
    [DISPLAY_MODE_LAST] = "Last Multiplier",
    [DISPLAY_MODE_FINAL] = "Final Multiplier",
    [DISPLAY_MODE_BOTH] = "Both"
}
local DISPLAY_MODE_SCROLL_VALUE_BY_MODE = {
    [DISPLAY_MODE_LAST] = 0,
    [DISPLAY_MODE_FINAL] = 5,
    [DISPLAY_MODE_BOTH] = 10
}

local function clampOffset(value)
    local num = tonumber(value) or 0
    if num >= 0 then
        num = math.floor(num + 0.5)
    else
        num = math.ceil(num - 0.5)
    end
    if num < OFFSET_MIN then
        num = OFFSET_MIN
    elseif num > OFFSET_MAX then
        num = OFFSET_MAX
    end
    return num
end

local function normalizeDisplayMode(value)
    if type(value) == "number" then
        local rounded = nil
        if value >= 0 then
            rounded = math.floor(value + 0.5)
        else
            rounded = math.ceil(value - 0.5)
        end
        if rounded < 0 then
            rounded = 0
        elseif rounded > 10 then
            rounded = 10
        end

        -- NUMBER mode: exact 0/1/2
        if rounded >= DISPLAY_MODE_MIN_INDEX and rounded <= DISPLAY_MODE_MAX_INDEX then
            return DISPLAY_MODE_BY_INDEX[rounded] or DISPLAY_MODE_BOTH
        end

        -- SCROLL mode fallback (0~10): bucket into 3 states.
        if rounded <= 3 then
            return DISPLAY_MODE_LAST
        elseif rounded <= 7 then
            return DISPLAY_MODE_FINAL
        end
        return DISPLAY_MODE_BOTH
    end

    if type(value) == "string" then
        local mode = string.lower(value)
        if mode == DISPLAY_MODE_LAST
            or mode == "current"
            or mode == "last_multiplier"
            or mode == "recent" then
            return DISPLAY_MODE_LAST
        elseif mode == DISPLAY_MODE_FINAL
            or mode == "total"
            or mode == "final_multiplier"
            or mode == "total_multiplier" then
            return DISPLAY_MODE_FINAL
        elseif mode == DISPLAY_MODE_BOTH
            or mode == "all" then
            return DISPLAY_MODE_BOTH
        end
    end

    return DISPLAY_MODE_BOTH
end

local function ensureSettingsTable()
    if not StatsAPI then
        return nil
    end
    if type(StatsAPI.settings) ~= "table" then
        StatsAPI.settings = {
            displayEnabled = true,
            displayOffsetX = 0,
            displayOffsetY = 0,
            trackVanillaDisplay = true,
            debugEnabled = false,
            displayMode = DISPLAY_MODE_BOTH
        }
    elseif StatsAPI.settings.trackVanillaDisplay == nil then
        StatsAPI.settings.trackVanillaDisplay = true
    end
    if StatsAPI.settings.debugEnabled == nil then
        StatsAPI.settings.debugEnabled = false
    end
    if StatsAPI.settings.displayMode == nil then
        StatsAPI.settings.displayMode = DISPLAY_MODE_BOTH
    end
    return StatsAPI.settings
end

local function setDisplayOffset(axis, value)
    local settings = ensureSettingsTable()
    if not settings then
        return
    end

    local key = (axis == "y") and "displayOffsetY" or "displayOffsetX"
    local normalized = clampOffset(value)
    if settings[key] == normalized then
        return
    end

    settings[key] = normalized
    if StatsAPI and type(StatsAPI.SaveRunData) == "function" then
        StatsAPI:SaveRunData()
    end
end

local function resetDisplayDefaults()
    local settings = ensureSettingsTable()
    if not settings then
        return
    end

    local previousTrackVanilla = settings.trackVanillaDisplay
    local previousDebugEnabled = settings.debugEnabled == true
    local previousDisplayMode = normalizeDisplayMode(settings.displayMode)
    settings.displayEnabled = true
    settings.displayOffsetX = 0
    settings.displayOffsetY = 0
    settings.trackVanillaDisplay = true
    settings.debugEnabled = false
    settings.displayMode = DISPLAY_MODE_BOTH

    if previousTrackVanilla ~= true
        and StatsAPI
        and type(StatsAPI.SetVanillaDisplayTrackingEnabled) == "function" then
        StatsAPI:SetVanillaDisplayTrackingEnabled(true)
    end

    if previousDebugEnabled
        and StatsAPI
        and type(StatsAPI.SetDebugModeEnabled) == "function" then
        StatsAPI:SetDebugModeEnabled(false)
    elseif StatsAPI then
        StatsAPI.DEBUG = false
    end

    if previousDisplayMode ~= DISPLAY_MODE_BOTH
        and StatsAPI
        and type(StatsAPI.SetDisplayMode) == "function" then
        StatsAPI:SetDisplayMode(DISPLAY_MODE_BOTH)
    end

    if StatsAPI and StatsAPI.stats and StatsAPI.stats.multiplierDisplay
        and type(StatsAPI.stats.multiplierDisplay.RefreshAllFromUnified) == "function" then
        StatsAPI.stats.multiplierDisplay:RefreshAllFromUnified()
    end

    if StatsAPI and type(StatsAPI.SaveRunData) == "function" then
        StatsAPI:SaveRunData()
    end
end

local function hasMCM()
    return type(ModConfigMenu) == "table"
        and type(ModConfigMenu.AddSetting) == "function"
        and type(ModConfigMenu.OptionType) == "table"
        and ModConfigMenu.OptionType.BOOLEAN ~= nil
end

local function getDisplayEnabled()
    if StatsAPI and type(StatsAPI.IsDisplayEnabled) == "function" then
        return StatsAPI:IsDisplayEnabled()
    end
    return true
end

local function getTrackVanillaDisplay()
    if StatsAPI and type(StatsAPI.IsVanillaDisplayTrackingEnabled) == "function" then
        return StatsAPI:IsVanillaDisplayTrackingEnabled()
    end
    local settings = ensureSettingsTable()
    if settings then
        return settings.trackVanillaDisplay ~= false
    end
    return true
end

local function getDebugEnabled()
    if StatsAPI and type(StatsAPI.IsDebugModeEnabled) == "function" then
        return StatsAPI:IsDebugModeEnabled()
    end
    local settings = ensureSettingsTable()
    if settings then
        return settings.debugEnabled == true
    end
    return StatsAPI and StatsAPI.DEBUG == true or false
end

local function getDisplayOffsetX()
    local settings = ensureSettingsTable()
    if settings then
        return clampOffset(settings.displayOffsetX)
    end
    if StatsAPI and type(StatsAPI.GetDisplayOffsetX) == "function" then
        return clampOffset(StatsAPI:GetDisplayOffsetX())
    end
    return 0
end

local function getDisplayOffsetY()
    local settings = ensureSettingsTable()
    if settings then
        return clampOffset(settings.displayOffsetY)
    end
    if StatsAPI and type(StatsAPI.GetDisplayOffsetY) == "function" then
        return clampOffset(StatsAPI:GetDisplayOffsetY())
    end
    return 0
end

local function getDisplayMode()
    if StatsAPI and type(StatsAPI.GetDisplayMode) == "function" then
        return normalizeDisplayMode(StatsAPI:GetDisplayMode())
    end
    local settings = ensureSettingsTable()
    if settings then
        return normalizeDisplayMode(settings.displayMode)
    end
    return DISPLAY_MODE_BOTH
end

local function getDisplayModeIndex()
    local mode = getDisplayMode()
    return DISPLAY_MODE_INDEX_BY_MODE[mode] or DISPLAY_MODE_INDEX_BY_MODE[DISPLAY_MODE_BOTH]
end

local function getDisplayModeScrollValue()
    local mode = getDisplayMode()
    return DISPLAY_MODE_SCROLL_VALUE_BY_MODE[mode] or DISPLAY_MODE_SCROLL_VALUE_BY_MODE[DISPLAY_MODE_BOTH]
end

local function setDisplayMode(value)
    local mode = normalizeDisplayMode(value)
    if StatsAPI and type(StatsAPI.SetDisplayMode) == "function" then
        StatsAPI:SetDisplayMode(mode)
        return
    end

    local settings = ensureSettingsTable()
    if not settings then
        return
    end

    if settings.displayMode == mode then
        return
    end
    settings.displayMode = mode

    if StatsAPI and StatsAPI.stats and StatsAPI.stats.multiplierDisplay
        and type(StatsAPI.stats.multiplierDisplay.RefreshAllFromUnified) == "function" then
        StatsAPI.stats.multiplierDisplay:RefreshAllFromUnified()
    end
    if StatsAPI and type(StatsAPI.SaveRunData) == "function" then
        StatsAPI:SaveRunData()
    end
end

function M.Setup()
    if not hasMCM() then
        return false
    end

    local hasNumberOption = ModConfigMenu.OptionType.NUMBER ~= nil
    local hasScrollOption = ModConfigMenu.OptionType.SCROLL ~= nil
    if not hasNumberOption and not hasScrollOption then
        return false
    end
    local modeOptionType = hasNumberOption and ModConfigMenu.OptionType.NUMBER or ModConfigMenu.OptionType.SCROLL

    local category = "StatsAPI"
    local subcategory = "Display"

    if type(ModConfigMenu.RemoveCategory) == "function" then
        pcall(ModConfigMenu.RemoveCategory, category)
    end

    if type(ModConfigMenu.AddSpace) == "function" then
        ModConfigMenu.AddSpace(category, subcategory)
    end
    if type(ModConfigMenu.AddText) == "function" then
        ModConfigMenu.AddText(category, subcategory, "--- HUD Display ---")
    end

    ModConfigMenu.AddSetting(category, subcategory, {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function()
            return getDisplayEnabled()
        end,
        Display = function()
            local enabled = getDisplayEnabled()
            return "Multiplier HUD: " .. (enabled and "ON" or "OFF")
        end,
        Info = { "Toggle StatsAPI multiplier HUD rendering." },
        OnChange = function(value)
            if StatsAPI and StatsAPI.SetDisplayEnabled then
                StatsAPI:SetDisplayEnabled(value)
            end
        end
    })

    ModConfigMenu.AddSetting(category, subcategory, {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function()
            return getTrackVanillaDisplay()
        end,
        Display = function()
            local enabled = getTrackVanillaDisplay()
            return "Track Vanilla Multiplier: " .. (enabled and "ON" or "OFF")
        end,
        Info = {
            "Include vanilla character/item multipliers in total display.",
            "Applies per-player (item holder character context)."
        },
        OnChange = function(value)
            local enabled = value ~= false
            if StatsAPI and type(StatsAPI.SetVanillaDisplayTrackingEnabled) == "function" then
                StatsAPI:SetVanillaDisplayTrackingEnabled(enabled)
                return
            end

            local settings = ensureSettingsTable()
            if not settings then
                return
            end
            settings.trackVanillaDisplay = enabled

            if StatsAPI and StatsAPI.stats and StatsAPI.stats.multiplierDisplay
                and type(StatsAPI.stats.multiplierDisplay.RefreshAllFromUnified) == "function" then
                StatsAPI.stats.multiplierDisplay:RefreshAllFromUnified()
            end

            if StatsAPI and type(StatsAPI.SaveRunData) == "function" then
                StatsAPI:SaveRunData()
            end
        end
    })

    ModConfigMenu.AddSetting(category, subcategory, {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function()
            return getDebugEnabled()
        end,
        Display = function()
            local enabled = getDebugEnabled()
            return "Debug Mode (Watcher Log): " .. (enabled and "ON" or "OFF")
        end,
        Info = {
            "Enable debug mode and show watcher runtime logs at bottom-left.",
            "Used by watch.sh runtime queue MSG/CMD notifications."
        },
        OnChange = function(value)
            local enabled = value == true
            if StatsAPI and type(StatsAPI.SetDebugModeEnabled) == "function" then
                StatsAPI:SetDebugModeEnabled(enabled)
                return
            end

            local settings = ensureSettingsTable()
            if not settings then
                return
            end
            settings.debugEnabled = enabled
            if StatsAPI then
                StatsAPI.DEBUG = enabled
            end
            if StatsAPI and type(StatsAPI.SaveRunData) == "function" then
                StatsAPI:SaveRunData()
            end
        end
    })

    local modeSetting = {
        Type = modeOptionType,
        CurrentSetting = function()
            if modeOptionType == ModConfigMenu.OptionType.NUMBER then
                return getDisplayModeIndex()
            end
            return getDisplayModeScrollValue()
        end,
        Display = function()
            local mode = getDisplayMode()
            local label = DISPLAY_MODE_LABELS[mode] or DISPLAY_MODE_LABELS[DISPLAY_MODE_BOTH]
            return "HUD Display Mode: " .. label
        end,
        Info = {
            "Choose what to render on stat multiplier HUD text.",
            "Last Multiplier: show only latest changed multiplier.",
            "Final Multiplier: show only final combined multiplier.",
            "Both: show latest/final together (default)."
        },
        OnChange = function(value)
            setDisplayMode(value)
        end
    }
    if modeOptionType == ModConfigMenu.OptionType.NUMBER then
        modeSetting.Minimum = DISPLAY_MODE_MIN_INDEX
        modeSetting.Maximum = DISPLAY_MODE_MAX_INDEX
    end
    ModConfigMenu.AddSetting(category, subcategory, modeSetting)

    if ModConfigMenu.OptionType.NUMBER ~= nil then
        ModConfigMenu.AddSetting(category, subcategory, {
            Type = ModConfigMenu.OptionType.NUMBER,
            CurrentSetting = function()
                return getDisplayOffsetX()
            end,
            Minimum = OFFSET_MIN,
            Maximum = OFFSET_MAX,
            Display = function()
                return string.format("HUD Offset X: %+d", getDisplayOffsetX())
            end,
            Info = {
                "Horizontal offset for StatsAPI HUD display.",
                "Positive moves right, negative moves left."
            },
            OnChange = function(value)
                setDisplayOffset("x", value)
            end
        })

        ModConfigMenu.AddSetting(category, subcategory, {
            Type = ModConfigMenu.OptionType.NUMBER,
            CurrentSetting = function()
                return getDisplayOffsetY()
            end,
            Minimum = OFFSET_MIN,
            Maximum = OFFSET_MAX,
            Display = function()
                return string.format("HUD Offset Y: %+d", getDisplayOffsetY())
            end,
            Info = {
                "Vertical offset for StatsAPI HUD display.",
                "Positive moves down, negative moves up."
            },
            OnChange = function(value)
                setDisplayOffset("y", value)
            end
        })
    end

    if type(ModConfigMenu.AddSpace) == "function" then
        ModConfigMenu.AddSpace(category, subcategory)
    end
    ModConfigMenu.AddSetting(category, subcategory, {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function()
            return false
        end,
        Display = function()
            return "Reset Display To Default"
        end,
        Info = {
            "Reset Multiplier HUD to defaults:",
            "Display ON, Mode BOTH, Track Vanilla ON, Debug OFF, Offset X 0, Offset Y 0."
        },
        OnChange = function(value)
            if value then
                resetDisplayDefaults()
            end
            return false
        end
    })

    return true
end

return M
