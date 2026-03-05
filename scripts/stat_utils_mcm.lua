local M = {}
local OFFSET_MIN = -200
local OFFSET_MAX = 200

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

local function ensureSettingsTable()
    if not StatUtils then
        return nil
    end
    if type(StatUtils.settings) ~= "table" then
        StatUtils.settings = {
            displayEnabled = true,
            displayOffsetX = 0,
            displayOffsetY = 0
        }
    end
    return StatUtils.settings
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
    if StatUtils and type(StatUtils.SaveRunData) == "function" then
        StatUtils:SaveRunData()
    end
end

local function resetDisplayDefaults()
    local settings = ensureSettingsTable()
    if not settings then
        return
    end

    settings.displayEnabled = true
    settings.displayOffsetX = 0
    settings.displayOffsetY = 0

    if StatUtils and StatUtils.stats and StatUtils.stats.multiplierDisplay
        and type(StatUtils.stats.multiplierDisplay.RefreshAllFromUnified) == "function" then
        StatUtils.stats.multiplierDisplay:RefreshAllFromUnified()
    end

    if StatUtils and type(StatUtils.SaveRunData) == "function" then
        StatUtils:SaveRunData()
    end
end

local function hasMCM()
    return type(ModConfigMenu) == "table"
        and type(ModConfigMenu.AddSetting) == "function"
        and type(ModConfigMenu.OptionType) == "table"
        and ModConfigMenu.OptionType.BOOLEAN ~= nil
end

local function getDisplayEnabled()
    if StatUtils and type(StatUtils.IsDisplayEnabled) == "function" then
        return StatUtils:IsDisplayEnabled()
    end
    return true
end

local function getDisplayOffsetX()
    local settings = ensureSettingsTable()
    if settings then
        return clampOffset(settings.displayOffsetX)
    end
    if StatUtils and type(StatUtils.GetDisplayOffsetX) == "function" then
        return clampOffset(StatUtils:GetDisplayOffsetX())
    end
    return 0
end

local function getDisplayOffsetY()
    local settings = ensureSettingsTable()
    if settings then
        return clampOffset(settings.displayOffsetY)
    end
    if StatUtils and type(StatUtils.GetDisplayOffsetY) == "function" then
        return clampOffset(StatUtils:GetDisplayOffsetY())
    end
    return 0
end

function M.Setup()
    if not hasMCM() then
        return false
    end

    local category = "Stat Utils"
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
        Info = { "Toggle Stat Utils multiplier HUD rendering." },
        OnChange = function(value)
            if StatUtils and StatUtils.SetDisplayEnabled then
                StatUtils:SetDisplayEnabled(value)
            end
        end
    })

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
                "Horizontal offset for Stat Utils HUD display.",
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
                "Vertical offset for Stat Utils HUD display.",
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
            "Display ON, Offset X 0, Offset Y 0."
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
