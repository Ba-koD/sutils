-- StatsAPI - Core Module
-- Standalone stat multiplier management library for Isaac mods
-- Exposes global 'StatsAPI' table for use by other mods
--
-- Usage from another mod:
--   if StatsAPI then
--       StatsAPI.stats.unifiedMultipliers:SetItemMultiplier(player, itemID, "Damage", 1.5, "My Item")
--       StatsAPI.stats.unifiedMultipliers:SetItemAddition(player, itemID, "Damage", 2.0, "My Item")
--       StatsAPI.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, itemID, "Damage", 1.2, "My Item")
--       StatsAPI.stats.damage.applyMultiplier(player, 1.5)
--   end

local json = require("json")

local mod = RegisterMod("StatsAPI", 1)
local _mcmModule = nil
local _mcmSetupDone = false
local _normalizeSettings

---@class StatsAPI
local _existingStatsAPI = rawget(_G, "StatsAPI")
if type(_existingStatsAPI) == "table" then
    StatsAPI = _existingStatsAPI
else
    StatsAPI = {}
end

StatsAPI.mod = mod
StatsAPI.VERSION = "1.0.0"
StatsAPI.DEBUG = StatsAPI.DEBUG == true
local DISPLAY_MODE_LAST = "last"
local DISPLAY_MODE_FINAL = "final"
local DISPLAY_MODE_BOTH = "both"
StatsAPI.DEFAULT_SETTINGS = {
    displayEnabled = true,
    displayOffsetX = 0,
    displayOffsetY = 0,
    trackVanillaDisplay = true,
    debugEnabled = false,
    displayMode = DISPLAY_MODE_BOTH
}
if type(StatsAPI.settings) ~= "table" then
    StatsAPI.settings = {
        displayEnabled = true,
        displayOffsetX = 0,
        displayOffsetY = 0,
        trackVanillaDisplay = true,
        debugEnabled = false,
        displayMode = DISPLAY_MODE_BOTH
    }
end
if StatsAPI.DEBUG then
    Isaac.DebugString("[StatsAPI][DEBUG] [Core] Global StatsAPI table ref = " .. tostring(StatsAPI))
end

local game = Game()
local RUNTIME_TEXT_FADE_DELAY = 120
local RUNTIME_TEXT_FADE_STEP = 0.02
local RUNTIME_TEXT_SCALE = 1
local RUNTIME_TEXT_LEFT_PADDING = 18
local RUNTIME_TEXT_BOTTOM_PADDING = 18
local RuntimeOverlay = {
    font = Font(),
    frameOfLastMsg = 0,
    messages = {},
    maxMessages = 10
}
RuntimeOverlay.font:Load("font/pftempestasevencondensed.fnt")

---------------------------------------------
-- Logging
---------------------------------------------
function StatsAPI.print(msg)
    local text = "[StatsAPI] " .. tostring(msg)
    Isaac.ConsoleOutput(text .. "\n")
    Isaac.DebugString(text)
end

function StatsAPI.printDebug(msg)
    if not StatsAPI.DEBUG then return end
    local text = "[StatsAPI][DEBUG] " .. tostring(msg)
    Isaac.ConsoleOutput(text .. "\n")
    Isaac.DebugString(text)
end

function StatsAPI.printError(msg)
    local text = "[StatsAPI][ERROR] " .. tostring(msg)
    Isaac.ConsoleOutput(text .. "\n")
    Isaac.DebugString(text)
end

function StatsAPI:IsDebugModeEnabled()
    if type(self.settings) ~= "table" then
        self.settings = _normalizeSettings(nil)
    end
    return self.settings.debugEnabled == true
end

function StatsAPI:ClearRuntimeNotice()
    RuntimeOverlay.frameOfLastMsg = 0
    RuntimeOverlay.messages = {}
end

function StatsAPI:ShowRuntimeNotice(message, kind)
    if not self:IsDebugModeEnabled() then
        return
    end
    if type(message) ~= "string" or message == "" then
        return
    end

    RuntimeOverlay.frameOfLastMsg = Isaac.GetFrameCount()
    table.insert(RuntimeOverlay.messages, {
        text = message,
        kind = kind or "info"
    })
    if #RuntimeOverlay.messages > RuntimeOverlay.maxMessages then
        table.remove(RuntimeOverlay.messages, 1)
    end
end

function StatsAPI:RenderRuntimeNotice()
    if not self:IsDebugModeEnabled() then
        self:ClearRuntimeNotice()
        return
    end

    if #RuntimeOverlay.messages == 0 or RuntimeOverlay.frameOfLastMsg == 0 then
        return
    end

    if AwaitingTextInput then
        return
    end

    if game:IsPaused() then
        return
    end

    if ModConfigMenu ~= nil and ModConfigMenu.IsVisible then
        return
    end

    local elapsed = Isaac.GetFrameCount() - RuntimeOverlay.frameOfLastMsg
    local alpha = 1
    if elapsed > RUNTIME_TEXT_FADE_DELAY then
        alpha = 1 - (RUNTIME_TEXT_FADE_STEP * (elapsed - RUNTIME_TEXT_FADE_DELAY))
    end
    if alpha <= 0 then
        self:ClearRuntimeNotice()
        return
    end

    local lineHeight = RuntimeOverlay.font:GetLineHeight() * RUNTIME_TEXT_SCALE
    local x = RUNTIME_TEXT_LEFT_PADDING
    local startY = Isaac.GetScreenHeight() - RUNTIME_TEXT_BOTTOM_PADDING - ((#RuntimeOverlay.messages - 1) * lineHeight)

    for i, entry in ipairs(RuntimeOverlay.messages) do
        local color = KColor(1, 1, 1, alpha)
        if entry.kind == "success" then
            color = KColor(0, 1, 0, alpha)
        elseif entry.kind == "error" then
            color = KColor(1, 0, 0, alpha)
        end

        RuntimeOverlay.font:DrawStringScaledUTF8(
            entry.text,
            x,
            startY + ((i - 1) * lineHeight),
            RUNTIME_TEXT_SCALE,
            RUNTIME_TEXT_SCALE,
            color,
            0,
            true
        )
    end
end

---------------------------------------------
-- Simple Run-Based Save System
---------------------------------------------
StatsAPI._runData = { players = {} }
local RUNTIME_QUEUE_PREFIX = "__SAPIQ__"
local RUNTIME_POLL_INTERVAL = 3
local _lastRuntimePollFrame = -RUNTIME_POLL_INTERVAL

local function _startsWith(text, prefix)
    return type(text) == "string"
        and type(prefix) == "string"
        and string.sub(text, 1, #prefix) == prefix
end

local function _getRawModData(modRef)
    if not modRef or not modRef:HasData() then
        return ""
    end
    local ok, raw = pcall(function()
        return modRef:LoadData()
    end)
    if ok and type(raw) == "string" then
        return raw
    end
    return ""
end

local function _extractPersistentData(raw)
    if type(raw) ~= "string" or raw == "" then
        return "{}"
    end

    local lines = {}
    for line in string.gmatch(raw, "[^\r\n]+") do
        if not _startsWith(line, RUNTIME_QUEUE_PREFIX) then
            table.insert(lines, line)
        end
    end

    local cleaned = table.concat(lines, "\n")
    if cleaned == "" then
        return "{}"
    end
    return cleaned
end

local function _parseRuntimeQueue(raw)
    local queue = {}
    if type(raw) ~= "string" or raw == "" then
        return queue
    end

    for line in string.gmatch(raw, "[^\r\n]+") do
        if _startsWith(line, RUNTIME_QUEUE_PREFIX) then
            local payload = string.sub(line, #RUNTIME_QUEUE_PREFIX + 1)
            local sep = string.find(payload, "|", 1, true)
            if sep and sep > 1 then
                local kind = string.sub(payload, 1, sep - 1)
                local data = string.sub(payload, sep + 1)
                if kind == "CMD" and data ~= "" then
                    table.insert(queue, { type = "command", data = data })
                elseif kind == "MSG" and data ~= "" then
                    table.insert(queue, { type = "msg", data = data })
                end
            end
        end
    end

    return queue
end

local function _consumeRuntimeQueue(modRef)
    local raw = _getRawModData(modRef)
    local queue = _parseRuntimeQueue(raw)
    if #queue == 0 then
        return queue
    end

    local persistent = _extractPersistentData(raw)
    pcall(function()
        modRef:SaveData(persistent)
    end)

    return queue
end

local function normalizeDisplayMode(value, defaultValue)
    local fallback = defaultValue or DISPLAY_MODE_BOTH
    if type(fallback) ~= "string" then
        fallback = DISPLAY_MODE_BOTH
    end
    fallback = string.lower(fallback)
    if fallback ~= DISPLAY_MODE_LAST
        and fallback ~= DISPLAY_MODE_FINAL
        and fallback ~= DISPLAY_MODE_BOTH then
        fallback = DISPLAY_MODE_BOTH
    end

    if type(value) == "number" then
        local rounded = nil
        if value >= 0 then
            rounded = math.floor(value + 0.5)
        else
            rounded = math.ceil(value - 0.5)
        end

        if rounded == 0 then
            return DISPLAY_MODE_LAST
        elseif rounded == 1 then
            return DISPLAY_MODE_FINAL
        elseif rounded == 2 then
            return DISPLAY_MODE_BOTH
        end
        return fallback
    end

    if type(value) ~= "string" then
        return fallback
    end

    local mode = string.lower(value)
    if mode == DISPLAY_MODE_LAST
        or mode == "current"
        or mode == "recent"
        or mode == "last_multiplier" then
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

    return fallback
end

_normalizeSettings = function(rawSettings)
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
        displayOffsetY = 0,
        trackVanillaDisplay = true,
        debugEnabled = false,
        displayMode = DISPLAY_MODE_BOTH
    }
    if type(rawSettings) == "table" then
        normalized.displayEnabled = toBoolean(rawSettings.displayEnabled, true)
        normalized.displayOffsetX = toInteger(rawSettings.displayOffsetX, 0, -200, 200)
        normalized.displayOffsetY = toInteger(rawSettings.displayOffsetY, 0, -200, 200)
        normalized.trackVanillaDisplay = toBoolean(rawSettings.trackVanillaDisplay, true)
        normalized.debugEnabled = toBoolean(rawSettings.debugEnabled, false)
        normalized.displayMode = normalizeDisplayMode(rawSettings.displayMode, DISPLAY_MODE_BOTH)
    end
    return normalized
end

function StatsAPI:IsDisplayEnabled()
    if type(self.settings) ~= "table" then
        self.settings = _normalizeSettings(nil)
    end
    return self.settings.displayEnabled ~= false
end

function StatsAPI:SetDisplayEnabled(enabled)
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

    StatsAPI.print("HUD display: " .. (self.settings.displayEnabled and "ON" or "OFF"))
    self:SaveRunData()
end

function StatsAPI:GetDisplayOffsetX()
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

function StatsAPI:GetDisplayOffsetY()
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

function StatsAPI:GetDisplayOffsets()
    return self:GetDisplayOffsetX(), self:GetDisplayOffsetY()
end

function StatsAPI:GetDisplayMode()
    if type(self.settings) ~= "table" then
        self.settings = _normalizeSettings(nil)
    end
    local mode = normalizeDisplayMode(self.settings.displayMode, DISPLAY_MODE_BOTH)
    if self.settings.displayMode ~= mode then
        self.settings.displayMode = mode
    end
    return mode
end

function StatsAPI:SetDisplayMode(mode)
    if type(self.settings) ~= "table" then
        self.settings = _normalizeSettings(nil)
    end

    local target = normalizeDisplayMode(mode, DISPLAY_MODE_BOTH)
    if self.settings.displayMode == target then
        return
    end

    self.settings.displayMode = target

    if self.stats
        and self.stats.multiplierDisplay
        and type(self.stats.multiplierDisplay.RefreshAllFromUnified) == "function" then
        self.stats.multiplierDisplay:RefreshAllFromUnified()
    end

    StatsAPI.print("HUD multiplier display mode: " .. target)
    self:SaveRunData()
end

function StatsAPI:IsVanillaDisplayTrackingEnabled()
    if type(self.settings) ~= "table" then
        self.settings = _normalizeSettings(nil)
    end
    return self.settings.trackVanillaDisplay ~= false
end

function StatsAPI:SetDebugModeEnabled(enabled)
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

    local target = toBoolean(enabled, false)
    local changed = (self.settings.debugEnabled ~= target) or (self.DEBUG ~= target)
    self.settings.debugEnabled = target
    self.DEBUG = target

    if not target then
        self:ClearRuntimeNotice()
    else
        self:ShowRuntimeNotice("Debug mode ON", "success")
    end

    if changed then
        StatsAPI.print("Debug mode: " .. (target and "ON" or "OFF"))
        self:SaveRunData()
    end
end

function StatsAPI:SetVanillaDisplayTrackingEnabled(enabled)
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

    local target = toBoolean(enabled, true)
    if self.settings.trackVanillaDisplay == target then
        return
    end

    self.settings.trackVanillaDisplay = target

    if self.stats
        and self.stats.unifiedMultipliers
        and type(self.stats.unifiedMultipliers.RecalculateStatMultiplier) == "function" then
        local unified = self.stats.unifiedMultipliers
        local prevEvaluatingState = unified._isEvaluatingCache
        unified._isEvaluatingCache = true
        local numPlayers = Game():GetNumPlayers()
        for i = 0, numPlayers - 1 do
            local player = Isaac.GetPlayer(i)
            if player then
                local playerID = self:GetPlayerInstanceKey(player)
                local perPlayer = unified[playerID]
                if perPlayer and perPlayer.statMultipliers then
                    for statType, _ in pairs(perPlayer.statMultipliers) do
                        unified:RecalculateStatMultiplier(player, statType)
                    end
                end
            end
        end
        unified._isEvaluatingCache = prevEvaluatingState
    end

    if self.stats
        and self.stats.multiplierDisplay
        and type(self.stats.multiplierDisplay.RefreshAllFromUnified) == "function" then
        self.stats.multiplierDisplay:RefreshAllFromUnified()
    end

    StatsAPI.print("Vanilla display tracking: " .. (target and "ON" or "OFF"))
    self:SaveRunData()
end

function StatsAPI:SetDisplayOffsets(offsetX, offsetY)
    if type(self.settings) ~= "table" then
        self.settings = _normalizeSettings(nil)
    end

    local normalized = _normalizeSettings({
        displayEnabled = self.settings.displayEnabled,
        displayOffsetX = offsetX,
        displayOffsetY = offsetY,
        trackVanillaDisplay = self.settings.trackVanillaDisplay,
        debugEnabled = self.settings.debugEnabled,
        displayMode = self.settings.displayMode
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
        StatsAPI.printDebug(string.format(
            "HUD display offset: X %+d, Y %+d",
            self.settings.displayOffsetX,
            self.settings.displayOffsetY
        ))
        self:SaveRunData()
    end
end

function StatsAPI:SetDisplayOffsetX(offsetX)
    local currentY = 0
    if type(self.settings) == "table" and type(self.settings.displayOffsetY) == "number" then
        currentY = self.settings.displayOffsetY
    end
    self:SetDisplayOffsets(offsetX, currentY)
end

function StatsAPI:SetDisplayOffsetY(offsetY)
    local currentX = 0
    if type(self.settings) == "table" and type(self.settings.displayOffsetX) == "number" then
        currentX = self.settings.displayOffsetX
    end
    self:SetDisplayOffsets(currentX, offsetY)
end

function StatsAPI:GetPlayerInstanceKey(player)
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

function StatsAPI:GetLegacyPlayerTypeKey(player)
    if not player then
        return nil
    end
    return "p" .. tostring(player:GetPlayerType())
end

function StatsAPI:GetPlayerRunData(player)
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

function StatsAPI:SaveRunData()
    local payload = {
        runData = self._runData,
        settings = _normalizeSettings(self.settings)
    }
    local ok, encoded = pcall(function()
        return json.encode(payload)
    end)
    if ok and encoded then
        self.mod:SaveData(encoded)
        StatsAPI.printDebug("Run data saved successfully")
    else
        StatsAPI.printError("Failed to save run data: " .. tostring(encoded))
    end
end

function StatsAPI:LoadRunData()
    if not self.mod:HasData() then
        StatsAPI.printDebug("No saved data found")
        self.settings = _normalizeSettings(self.settings)
        self.DEBUG = self.settings.debugEnabled == true
        return
    end
    local raw = _getRawModData(self.mod)
    local persistent = _extractPersistentData(raw)
    local ok, data = pcall(function()
        return json.decode(persistent)
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
        self.DEBUG = self.settings.debugEnabled == true
        StatsAPI.printDebug("Run data loaded successfully")
    else
        StatsAPI.printError("Failed to load run data: " .. tostring(data))
        self._runData = { players = {} }
        self.settings = _normalizeSettings(nil)
        self.DEBUG = self.settings.debugEnabled == true
    end
end

function StatsAPI:ClearRunData()
    self._runData = { players = {} }
    self:SaveRunData()
    StatsAPI.printDebug("Run data cleared (settings preserved)")
end

function StatsAPI:PollRuntimeQueue()
    local frame = Isaac.GetFrameCount()
    if (frame - _lastRuntimePollFrame) < RUNTIME_POLL_INTERVAL then
        return
    end
    _lastRuntimePollFrame = frame

    local queue = _consumeRuntimeQueue(self.mod)
    if type(queue) ~= "table" or #queue == 0 then
        return
    end

    for _, entry in ipairs(queue) do
        if type(entry) == "table" and type(entry.data) == "string" and entry.data ~= "" then
            if entry.type == "msg" then
                StatsAPI.print("[runtime] " .. entry.data)
                local kind = "info"
                local lowered = string.lower(entry.data)
                if _startsWith(lowered, "reloaded") or _startsWith(lowered, "reload complete") then
                    kind = "success"
                elseif _startsWith(lowered, "error") then
                    kind = "error"
                end
                self:ShowRuntimeNotice(entry.data, kind)
            elseif entry.type == "command" then
                StatsAPI.print("[runtime] Executing command: " .. entry.data)
                self:ShowRuntimeNotice("Executing: " .. entry.data, "info")
                Isaac.ExecuteCommand(entry.data)
            end
        end
    end
end

---------------------------------------------
-- Console Command: Toggle Debug
---------------------------------------------
mod:AddCallback(ModCallbacks.MC_EXECUTE_CMD, function(_, cmd, args)
    if cmd == "statutils_debug" then
        StatsAPI:SetDebugModeEnabled(not StatsAPI.DEBUG)
    end
end)

mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if StatsAPI and type(StatsAPI.PollRuntimeQueue) == "function" then
        StatsAPI:PollRuntimeQueue()
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
    return type(StatsAPI.stats) == "table"
        and type(StatsAPI.stats.unifiedMultipliers) == "table"
        and type(StatsAPI.stats.multiplierDisplay) == "table"
end

local function hasVanillaMultipliers()
    return type(StatsAPI.VanillaMultipliers) == "table"
        and type(StatsAPI.VanillaMultipliers.GetPlayerDamageMultiplier) == "function"
end

local function hasDamageUtils()
    return type(StatsAPI.DamageUtils) == "table"
        and type(StatsAPI.DamageUtils.isSelfInflictedDamage) == "function"
end

-- Load stats library (unified multiplier system + display + stat apply functions)
do
    local statsSuccess, statsErr = requireFreshModule("scripts.lib.stats")
    if not statsSuccess then
        StatsAPI.printError("Stats library require failed: " .. tostring(statsErr))
    end

    if not hasStatsLibrary() and type(include) == "function" then
        local includeSuccess, includeErr = pcall(include, "scripts.lib.stats")
        if not includeSuccess then
            StatsAPI.printError("Stats library include fallback failed: " .. tostring(includeErr))
        end
    end

    if hasStatsLibrary() then
        StatsAPI.print("Stats library loaded successfully!")
    else
        StatsAPI.printError("Stats library unavailable after load attempts")
    end
end

-- Load vanilla multipliers table
do
    local vanillaMultSuccess, vanillaMultErr = requireFreshModule("scripts.lib.vanilla_multipliers")
    if not vanillaMultSuccess then
        StatsAPI.printError("Vanilla Multipliers require failed: " .. tostring(vanillaMultErr))
    end

    if not hasVanillaMultipliers() and type(include) == "function" then
        local includeSuccess, includeErr = pcall(include, "scripts.lib.vanilla_multipliers")
        if not includeSuccess then
            StatsAPI.printError("Vanilla Multipliers include fallback failed: " .. tostring(includeErr))
        end
    end

    if hasVanillaMultipliers() then
        StatsAPI.print("Vanilla Multipliers table loaded successfully!")
    else
        StatsAPI.printError("Vanilla Multipliers table unavailable after load attempts")
    end
end

-- Load damage utilities
do
    local damageUtilsSuccess, damageUtilsResult = requireFreshModule("scripts.lib.damage_utils")
    if damageUtilsSuccess and type(damageUtilsResult) == "table" then
        StatsAPI.DamageUtils = damageUtilsResult
    end
    if not damageUtilsSuccess then
        StatsAPI.printError("Damage Utils require failed: " .. tostring(damageUtilsResult))
    end

    if not hasDamageUtils() and type(include) == "function" then
        local includeSuccess, includeResultOrErr = pcall(include, "scripts.lib.damage_utils")
        if includeSuccess and type(includeResultOrErr) == "table" then
            StatsAPI.DamageUtils = includeResultOrErr
        elseif not includeSuccess then
            StatsAPI.printError("Damage Utils include fallback failed: " .. tostring(includeResultOrErr))
        end
    end

    if hasDamageUtils() then
        StatsAPI.print("Damage Utils loaded successfully!")
    else
        StatsAPI.printError("Damage Utils unavailable after load attempts")
    end
end

-- Load MCM integration (optional)
do
    local mcmSuccess, mcmResultOrErr = requireFreshModule("scripts.statsapi_mcm")
    if mcmSuccess and type(mcmResultOrErr) == "table" and type(mcmResultOrErr.Setup) == "function" then
        _mcmModule = mcmResultOrErr
    elseif not mcmSuccess then
        StatsAPI.printDebug("MCM module load skipped: " .. tostring(mcmResultOrErr))
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
        StatsAPI.printError("MCM setup failed: " .. tostring(setupResultOrErr))
        return false
    end

    if setupResultOrErr then
        _mcmSetupDone = true
        StatsAPI.print("MCM integration loaded!")
        return true
    end

    StatsAPI.printDebug("MCM not available yet; will retry on game start")
    return false
end

-- Try once at load time, then retry on game start for load-order-safe setup.
trySetupMCM()
mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
    if not _mcmSetupDone then
        trySetupMCM()
    end
    if StatsAPI and type(StatsAPI.RenderRuntimeNotice) == "function" then
        StatsAPI:RenderRuntimeNotice()
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
if StatsAPI.stats and StatsAPI.stats.multiplierDisplay then
    StatsAPI.stats.multiplierDisplay:Initialize()
    StatsAPI.print("Stats display system initialized!")
else
    StatsAPI.printError("Stats display system not found during initialization!")
end

---------------------------------------------
-- Save/Load Callbacks
---------------------------------------------

-- Save data on game exit
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function(_, shouldSave)
    if shouldSave then
        -- Save unified multiplier data for all players
        if StatsAPI.stats and StatsAPI.stats.unifiedMultipliers then
            local numPlayers = Game():GetNumPlayers()
            for i = 0, numPlayers - 1 do
                local player = Isaac.GetPlayer(i)
                if player then
                    StatsAPI.stats.unifiedMultipliers:SaveToSaveManager(player)
                end
            end
        end
        StatsAPI:SaveRunData()
        StatsAPI.printDebug("Game exit: data saved")
    end
end)

StatsAPI.print("StatsAPI v" .. StatsAPI.VERSION .. " loaded!")
