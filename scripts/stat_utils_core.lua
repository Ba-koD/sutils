-- Stat Utils - Core Module
-- Standalone stat multiplier management library for Isaac mods
-- Exposes global 'StatUtils' table for use by other mods
--
-- Usage from another mod:
--   if StatUtils then
--       StatUtils.stats.unifiedMultipliers:SetItemMultiplier(player, itemID, "Damage", 1.5, "My Item")
--       StatUtils.stats.unifiedMultipliers:SetItemAddition(player, itemID, "Damage", 2.0, "My Item")
--       StatUtils.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, itemID, "Damage", 1.2, "My Item")
--       StatUtils.stats.damage.applyMultiplier(player, 1.5)
--   end

local json = require("json")

local mod = RegisterMod("Stat Utils", 1)
local _mcmModule = nil
local _mcmSetupDone = false

---@class StatUtils
StatUtils = {}
StatUtils.mod = mod
StatUtils.VERSION = "1.0.0"
StatUtils.DEBUG = false
StatUtils.DEFAULT_SETTINGS = {
    displayEnabled = true,
    displayOffsetX = 0,
    displayOffsetY = 0
}
StatUtils.settings = {
    displayEnabled = true,
    displayOffsetX = 0,
    displayOffsetY = 0
}

---------------------------------------------
-- Logging
---------------------------------------------
function StatUtils.print(msg)
    local text = "[StatUtils] " .. tostring(msg)
    Isaac.ConsoleOutput(text .. "\n")
    Isaac.DebugString(text)
end

function StatUtils.printDebug(msg)
    if not StatUtils.DEBUG then return end
    local text = "[StatUtils][DEBUG] " .. tostring(msg)
    Isaac.ConsoleOutput(text .. "\n")
    Isaac.DebugString(text)
end

function StatUtils.printError(msg)
    local text = "[StatUtils][ERROR] " .. tostring(msg)
    Isaac.ConsoleOutput(text .. "\n")
    Isaac.DebugString(text)
end

---------------------------------------------
-- Simple Run-Based Save System
---------------------------------------------
StatUtils._runData = { players = {} }

local function _normalizeSettings(rawSettings)
    local function clampNumber(value, minValue, maxValue)
        if value < minValue then
            return minValue
        end
        if value > maxValue then
            return maxValue
        end
        return value
    end

    local function toBoolean(value, defaultValue)
        if type(value) == "boolean" then
            return value
        end
        if type(value) == "number" then
            return value ~= 0
        end
        if type(value) == "string" then
            local v = string.lower(value)
            if v == "false" or v == "0" or v == "off" or v == "no" then
                return false
            end
            if v == "true" or v == "1" or v == "on" or v == "yes" then
                return true
            end
        end
        return defaultValue
    end

    local function toInteger(value, defaultValue, minValue, maxValue)
        local num = nil
        if type(value) == "number" then
            num = value
        elseif type(value) == "string" then
            local parsed = tonumber(value)
            if type(parsed) == "number" then
                num = parsed
            end
        end

        if type(num) ~= "number" then
            num = defaultValue
        end

        if num >= 0 then
            num = math.floor(num + 0.5)
        else
            num = math.ceil(num - 0.5)
        end
        return clampNumber(num, minValue, maxValue)
    end

    local normalized = {
        displayEnabled = true,
        displayOffsetX = 0,
        displayOffsetY = 0
    }
    if type(rawSettings) == "table" then
        normalized.displayEnabled = toBoolean(rawSettings.displayEnabled, true)
        normalized.displayOffsetX = toInteger(rawSettings.displayOffsetX, 0, -200, 200)
        normalized.displayOffsetY = toInteger(rawSettings.displayOffsetY, 0, -200, 200)
    end
    return normalized
end

function StatUtils:IsDisplayEnabled()
    if type(self.settings) ~= "table" then
        self.settings = _normalizeSettings(nil)
    end
    return self.settings.displayEnabled ~= false
end

function StatUtils:SetDisplayEnabled(enabled)
    local function toBoolean(value, defaultValue)
        if type(value) == "boolean" then
            return value
        end
        if type(value) == "number" then
            return value ~= 0
        end
        if type(value) == "string" then
            local v = string.lower(value)
            if v == "false" or v == "0" or v == "off" or v == "no" then
                return false
            end
            if v == "true" or v == "1" or v == "on" or v == "yes" then
                return true
            end
        end
        return defaultValue
    end

    if type(self.settings) ~= "table" then
        self.settings = _normalizeSettings(nil)
    end
    self.settings.displayEnabled = toBoolean(enabled, true)

    if self.stats and self.stats.multiplierDisplay then
        if not self.settings.displayEnabled then
            self.stats.multiplierDisplay.playerData = {}
        elseif type(self.stats.multiplierDisplay.RefreshAllFromUnified) == "function" then
            self.stats.multiplierDisplay:RefreshAllFromUnified()
        end
    end

    StatUtils.print("HUD display: " .. (self.settings.displayEnabled and "ON" or "OFF"))
    self:SaveRunData()
end

function StatUtils:GetDisplayOffsetX()
    if type(self.settings) ~= "table" then
        self.settings = _normalizeSettings(nil)
    end
    local x = self.settings.displayOffsetX
    if type(x) ~= "number" then
        x = 0
        self.settings.displayOffsetX = 0
    end
    return x
end

function StatUtils:GetDisplayOffsetY()
    if type(self.settings) ~= "table" then
        self.settings = _normalizeSettings(nil)
    end
    local y = self.settings.displayOffsetY
    if type(y) ~= "number" then
        y = 0
        self.settings.displayOffsetY = 0
    end
    return y
end

function StatUtils:GetDisplayOffsets()
    return self:GetDisplayOffsetX(), self:GetDisplayOffsetY()
end

function StatUtils:SetDisplayOffsets(offsetX, offsetY)
    if type(self.settings) ~= "table" then
        self.settings = _normalizeSettings(nil)
    end

    local normalized = _normalizeSettings({
        displayEnabled = self.settings.displayEnabled,
        displayOffsetX = offsetX,
        displayOffsetY = offsetY
    })

    local changed = false
    if self.settings.displayOffsetX ~= normalized.displayOffsetX then
        self.settings.displayOffsetX = normalized.displayOffsetX
        changed = true
    end
    if self.settings.displayOffsetY ~= normalized.displayOffsetY then
        self.settings.displayOffsetY = normalized.displayOffsetY
        changed = true
    end

    if changed then
        StatUtils.printDebug(string.format(
            "HUD display offset: X %+d, Y %+d",
            self.settings.displayOffsetX,
            self.settings.displayOffsetY
        ))
        self:SaveRunData()
    end
end

function StatUtils:SetDisplayOffsetX(offsetX)
    local currentY = 0
    if type(self.settings) == "table" and type(self.settings.displayOffsetY) == "number" then
        currentY = self.settings.displayOffsetY
    end
    self:SetDisplayOffsets(offsetX, currentY)
end

function StatUtils:SetDisplayOffsetY(offsetY)
    local currentX = 0
    if type(self.settings) == "table" and type(self.settings.displayOffsetX) == "number" then
        currentX = self.settings.displayOffsetX
    end
    self:SetDisplayOffsets(currentX, offsetY)
end

function StatUtils:GetPlayerInstanceKey(player)
    if not player then
        return nil
    end

    local initSeed = player.InitSeed
    if type(initSeed) == "number" then
        return "s" .. tostring(initSeed)
    end

    if type(GetPtrHash) == "function" then
        local ok, hashOrErr = pcall(GetPtrHash, player)
        if ok and type(hashOrErr) == "number" then
            return "h" .. tostring(hashOrErr)
        end
    end

    return "t" .. tostring(player:GetPlayerType())
end

function StatUtils:GetLegacyPlayerTypeKey(player)
    if not player then
        return nil
    end
    return "p" .. tostring(player:GetPlayerType())
end

function StatUtils:GetPlayerRunData(player)
    local key = self:GetPlayerInstanceKey(player) or self:GetLegacyPlayerTypeKey(player)
    if not self._runData.players then
        self._runData.players = {}
    end
    if not self._runData.players[key] then
        local legacyKey = self:GetLegacyPlayerTypeKey(player)
        if legacyKey and self._runData.players[legacyKey] then
            self._runData.players[key] = self._runData.players[legacyKey]
            if legacyKey ~= key then
                self._runData.players[legacyKey] = nil
            end
        else
            self._runData.players[key] = {}
        end
    end
    return self._runData.players[key]
end

function StatUtils:SaveRunData()
    local payload = {
        runData = self._runData,
        settings = _normalizeSettings(self.settings)
    }
    local ok, encoded = pcall(function()
        return json.encode(payload)
    end)
    if ok and encoded then
        self.mod:SaveData(encoded)
        StatUtils.printDebug("Run data saved successfully")
    else
        StatUtils.printError("Failed to save run data: " .. tostring(encoded))
    end
end

function StatUtils:LoadRunData()
    if not self.mod:HasData() then
        StatUtils.printDebug("No saved data found")
        self.settings = _normalizeSettings(self.settings)
        return
    end
    local raw = self.mod:LoadData()
    local ok, data = pcall(function()
        return json.decode(raw)
    end)
    if ok and data and type(data) == "table" then
        local loadedRunData = data
        if type(data.runData) == "table" then
            loadedRunData = data.runData
        end
        self._runData = loadedRunData
        if not self._runData.players then
            self._runData.players = {}
        end
        self.settings = _normalizeSettings(data.settings)
        StatUtils.printDebug("Run data loaded successfully")
    else
        StatUtils.printError("Failed to load run data: " .. tostring(data))
        self._runData = { players = {} }
        self.settings = _normalizeSettings(nil)
    end
end

function StatUtils:ClearRunData()
    self._runData = { players = {} }
    self:SaveRunData()
    StatUtils.printDebug("Run data cleared (settings preserved)")
end

---------------------------------------------
-- Console Command: Toggle Debug
---------------------------------------------
mod:AddCallback(ModCallbacks.MC_EXECUTE_CMD, function(_, cmd, args)
    if cmd == "statutils_debug" then
        StatUtils.DEBUG = not StatUtils.DEBUG
        StatUtils.print("Debug mode: " .. (StatUtils.DEBUG and "ON" or "OFF"))
    end
end)

---------------------------------------------
-- Load Sub-Modules
---------------------------------------------

local function requireFreshModule(modulePath)
    local loadedTable = package and package.loaded
    local hadPrevious = false
    local previousValue = nil

    if type(loadedTable) == "table" then
        if loadedTable[modulePath] ~= nil then
            hadPrevious = true
            previousValue = loadedTable[modulePath]
        end
        loadedTable[modulePath] = nil
    end

    local ok, result = pcall(require, modulePath)

    if type(loadedTable) == "table" then
        if hadPrevious then
            loadedTable[modulePath] = previousValue
        else
            loadedTable[modulePath] = nil
        end
    end

    return ok, result
end

local function hasStatsLibrary()
    return type(StatUtils.stats) == "table"
        and type(StatUtils.stats.unifiedMultipliers) == "table"
        and type(StatUtils.stats.multiplierDisplay) == "table"
end

local function hasVanillaMultipliers()
    return type(StatUtils.VanillaMultipliers) == "table"
        and type(StatUtils.VanillaMultipliers.GetPlayerDamageMultiplier) == "function"
end

local function hasDamageUtils()
    return type(StatUtils.DamageUtils) == "table"
        and type(StatUtils.DamageUtils.isSelfInflictedDamage) == "function"
end

-- Load stats library (unified multiplier system + display + stat apply functions)
do
    local statsSuccess, statsErr = requireFreshModule("scripts.lib.stats")
    if not statsSuccess then
        StatUtils.printError("Stats library require failed: " .. tostring(statsErr))
    end

    if not hasStatsLibrary() and type(include) == "function" then
        local includeSuccess, includeErr = pcall(include, "scripts.lib.stats")
        if not includeSuccess then
            StatUtils.printError("Stats library include fallback failed: " .. tostring(includeErr))
        end
    end

    if hasStatsLibrary() then
        StatUtils.print("Stats library loaded successfully!")
    else
        StatUtils.printError("Stats library unavailable after load attempts")
    end
end

-- Load vanilla multipliers table
do
    local vanillaMultSuccess, vanillaMultErr = requireFreshModule("scripts.lib.vanilla_multipliers")
    if not vanillaMultSuccess then
        StatUtils.printError("Vanilla Multipliers require failed: " .. tostring(vanillaMultErr))
    end

    if not hasVanillaMultipliers() and type(include) == "function" then
        local includeSuccess, includeErr = pcall(include, "scripts.lib.vanilla_multipliers")
        if not includeSuccess then
            StatUtils.printError("Vanilla Multipliers include fallback failed: " .. tostring(includeErr))
        end
    end

    if hasVanillaMultipliers() then
        StatUtils.print("Vanilla Multipliers table loaded successfully!")
    else
        StatUtils.printError("Vanilla Multipliers table unavailable after load attempts")
    end
end

-- Load damage utilities
do
    local damageUtilsSuccess, damageUtilsResult = requireFreshModule("scripts.lib.damage_utils")
    if damageUtilsSuccess and type(damageUtilsResult) == "table" then
        StatUtils.DamageUtils = damageUtilsResult
    end
    if not damageUtilsSuccess then
        StatUtils.printError("Damage Utils require failed: " .. tostring(damageUtilsResult))
    end

    if not hasDamageUtils() and type(include) == "function" then
        local includeSuccess, includeResultOrErr = pcall(include, "scripts.lib.damage_utils")
        if includeSuccess and type(includeResultOrErr) == "table" then
            StatUtils.DamageUtils = includeResultOrErr
        elseif not includeSuccess then
            StatUtils.printError("Damage Utils include fallback failed: " .. tostring(includeResultOrErr))
        end
    end

    if hasDamageUtils() then
        StatUtils.print("Damage Utils loaded successfully!")
    else
        StatUtils.printError("Damage Utils unavailable after load attempts")
    end
end

-- Load MCM integration (optional)
do
    local mcmSuccess, mcmResultOrErr = requireFreshModule("scripts.stat_utils_mcm")
    if mcmSuccess and type(mcmResultOrErr) == "table" and type(mcmResultOrErr.Setup) == "function" then
        _mcmModule = mcmResultOrErr
    elseif not mcmSuccess then
        StatUtils.printDebug("MCM module load skipped: " .. tostring(mcmResultOrErr))
    end
end

local function trySetupMCM()
    if _mcmSetupDone then
        return true
    end
    if not _mcmModule or type(_mcmModule.Setup) ~= "function" then
        return false
    end

    local setupSuccess, setupResultOrErr = pcall(_mcmModule.Setup)
    if not setupSuccess then
        StatUtils.printError("MCM setup failed: " .. tostring(setupResultOrErr))
        return false
    end

    if setupResultOrErr then
        _mcmSetupDone = true
        StatUtils.print("MCM integration loaded!")
        return true
    end

    StatUtils.printDebug("MCM not available yet; will retry on game start")
    return false
end

-- Try once at load time, then retry on game start for load-order-safe setup.
trySetupMCM()
mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
    if not _mcmSetupDone then
        trySetupMCM()
    end
end)
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
    if not _mcmSetupDone then
        trySetupMCM()
    end
end)

---------------------------------------------
-- Initialize Display System
---------------------------------------------
if StatUtils.stats and StatUtils.stats.multiplierDisplay then
    StatUtils.stats.multiplierDisplay:Initialize()
    StatUtils.print("Stats display system initialized!")
else
    StatUtils.printError("Stats display system not found during initialization!")
end

---------------------------------------------
-- Save/Load Callbacks
---------------------------------------------

-- Save data on game exit
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function(_, shouldSave)
    if shouldSave then
        -- Save unified multiplier data for all players
        if StatUtils.stats and StatUtils.stats.unifiedMultipliers then
            local numPlayers = Game():GetNumPlayers()
            for i = 0, numPlayers - 1 do
                local player = Isaac.GetPlayer(i)
                if player then
                    StatUtils.stats.unifiedMultipliers:SaveToSaveManager(player)
                end
            end
        end
        StatUtils:SaveRunData()
        StatUtils.printDebug("Game exit: data saved")
    end
end)

StatUtils.print("Stat Utils v" .. StatUtils.VERSION .. " loaded!")
