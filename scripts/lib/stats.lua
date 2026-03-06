-- StatsAPI - Stats Library
-- Unified multiplier management, HUD display UI, and stat application functions
-- Standalone version (no external dependencies except Isaac API)

StatsAPI.stats = StatsAPI.stats or {}

-- base stats
StatsAPI.stats.BASE_STATS = {
    damage = 3.5,
    tears = 7,
    speed = 1.0,
    range = 6.5,
    luck = 0,
    shotSpeed = 1.0
}

-------------------------------------------------------------------------------
-- Unified Multiplier Management System
-------------------------------------------------------------------------------
StatsAPI.stats.unifiedMultipliers = StatsAPI.stats.unifiedMultipliers or {}

local function _playerScopedSourceKey(sourceKey)
    if sourceKey == nil then
        return nil
    end
    return "__player_scope__:" .. tostring(sourceKey)
end

-- Initialize unified multiplier system for a player
function StatsAPI.stats.unifiedMultipliers:InitPlayer(player)
    if not player then return end

    if not self._tableRefLogged then
        self._tableRefLogged = true
        StatsAPI.printDebug(string.format("[Unified] table ref = %s", tostring(self)))
    end

    local playerID = StatsAPI:GetPlayerInstanceKey(player)
    if not self[playerID] then
        self[playerID] = {
            itemMultipliers = {},
            itemAdditions = {},
            itemAdditiveMultipliers = {},
            statMultipliers = {},
            lastUpdateFrame = 0,
            sequenceCounter = 0,
            pendingCache = {}
        }
        StatsAPI.printDebug(string.format("Unified Multipliers: Initialized for player %s", playerID))
    end
end

-- Helper: convert an addition to an equivalent multiplier for display purposes
local function _toEquivalentMultiplierFromAddition(player, statType, addition)
    if not player or type(addition) ~= "number" then return 1.0 end
    if statType == "Damage" then
        local base = player.Damage
        if base == 0 then return 1.0 end
        return (base + addition) / base
    elseif statType == "Tears" then
        local baseFD = player.MaxFireDelay
        local baseSPS = 30 / (baseFD + 1)
        if baseSPS <= 0 then return 1.0 end
        return (baseSPS + addition) / baseSPS
    elseif statType == "Speed" then
        local base = player.MoveSpeed
        if base == 0 then return 1.0 end
        return (base + addition) / base
    elseif statType == "Range" then
        local base = player.TearRange
        if base == 0 then return 1.0 end
        return (base + addition) / base
    elseif statType == "ShotSpeed" then
        local base = player.ShotSpeed
        if base == 0 then return 1.0 end
        return (base + addition) / base
    elseif statType == "Luck" then
        return 1.0
    end
    return 1.0
end

local function _isVanillaDisplayTrackingEnabled()
    if StatsAPI and type(StatsAPI.IsVanillaDisplayTrackingEnabled) == "function" then
        return StatsAPI:IsVanillaDisplayTrackingEnabled()
    end
    if StatsAPI and type(StatsAPI.settings) == "table" then
        return StatsAPI.settings.trackVanillaDisplay ~= false
    end
    return true
end

local function _getVanillaDisplayMultiplier(player, statType)
    if not player or not _isVanillaDisplayTrackingEnabled() then
        return 1.0
    end
    if not StatsAPI or type(StatsAPI.VanillaMultipliers) ~= "table" then
        return 1.0
    end

    local vanillaMultiplier = 1.0
    if statType == "Damage"
        and type(StatsAPI.VanillaMultipliers.GetPlayerDamageMultiplier) == "function" then
        vanillaMultiplier = StatsAPI.VanillaMultipliers:GetPlayerDamageMultiplier(player) or 1.0
    elseif statType == "Tears"
        and type(StatsAPI.VanillaMultipliers.GetPlayerFireRateMultiplier) == "function" then
        vanillaMultiplier = StatsAPI.VanillaMultipliers:GetPlayerFireRateMultiplier(player) or 1.0
    end

    if type(vanillaMultiplier) ~= "number" or vanillaMultiplier <= 0 then
        return 1.0
    end
    return vanillaMultiplier
end

-- Add or update multiplier for a specific item and stat
function StatsAPI.stats.unifiedMultipliers:SetItemMultiplier(player, itemID, statType, multiplier, description)
    if not player or not itemID or not statType or not multiplier then
        StatsAPI.printError("SetItemMultiplier: Invalid parameters")
        return
    end

    self:InitPlayer(player)
    local playerID = StatsAPI:GetPlayerInstanceKey(player)
    local currentFrame = Game():GetFrameCount()
    self[playerID].lastSetFrame = self[playerID].lastSetFrame or {}
    local key = tostring(itemID) .. ":" .. tostring(statType)

    local existing = self[playerID].itemMultipliers[itemID]
        and self[playerID].itemMultipliers[itemID][statType]
        or nil
    if self[playerID].lastSetFrame[key] == currentFrame
        and existing
        and type(existing.value) == "number"
        and existing.value == multiplier
        and existing.disabled ~= true then
        StatsAPI.printDebug(string.format("SetItemMultiplier skipped (same frame, same active value) for %s", key))
        return
    end

    StatsAPI.printDebug(string.format("SetItemMultiplier: Player %s, Item %s, Stat %s, Value %.2fx",
        playerID, tostring(itemID), statType, multiplier))

    if not self[playerID].itemMultipliers[itemID] then
        self[playerID].itemMultipliers[itemID] = {}
        StatsAPI.printDebug(string.format("  Created new item entry for item %s", tostring(itemID)))
    end

    local willAdvanceSequence = true
    if existing and type(existing.value) == "number" and existing.value == multiplier then
        willAdvanceSequence = false
    end

    if willAdvanceSequence then
        self[playerID].sequenceCounter = self[playerID].sequenceCounter + 1
    end
    local currentSequence = self[playerID].sequenceCounter

    if willAdvanceSequence then
        StatsAPI.printDebug(string.format("  Advancing sequence to %d for %s", currentSequence, key))
    else
        StatsAPI.printDebug(string.format("  Sequence unchanged (%d) for %s (same value)", currentSequence, key))
    end

    self[playerID].itemMultipliers[itemID][statType] = {
        value = multiplier,
        description = description or (existing and existing.description) or "Unknown",
        sequence = currentSequence,
        lastType = "multiplier",
        disabled = existing and existing.disabled == true or false
    }

    StatsAPI.printDebug(string.format("  Stored: Item %s %s = %.2fx (Sequence: %d)", tostring(itemID), statType, multiplier, self[playerID].sequenceCounter))

    StatsAPI.printDebug(string.format("  Current multipliers for item %s:", tostring(itemID)))
    for stat, data in pairs(self[playerID].itemMultipliers[itemID]) do
        StatsAPI.printDebug(string.format("    %s: %.2fx (%s)", stat, data.value, data.description))
    end

    self:RecalculateStatMultiplier(player, statType)
    self[playerID].lastSetFrame[key] = currentFrame
end

-- Add or update addition entry for a specific item and stat
function StatsAPI.stats.unifiedMultipliers:SetItemAddition(player, itemID, statType, addition, description)
    if not player or not itemID or not statType or type(addition) ~= "number" then
        StatsAPI.printError("SetItemAddition: Invalid parameters")
        return
    end

    self:InitPlayer(player)
    local playerID = StatsAPI:GetPlayerInstanceKey(player)
    local currentFrame = Game():GetFrameCount()
    self[playerID].lastSetFrameAdd = self[playerID].lastSetFrameAdd or {}
    local key = tostring(itemID) .. ":" .. tostring(statType)

    if self[playerID].lastSetFrameAdd[key] == currentFrame then
        StatsAPI.printDebug(string.format("SetItemAddition skipped (same frame) for %s", key))
        return
    end

    StatsAPI.printDebug(string.format("SetItemAddition: Player %s, Item %s, Stat %s, Value %+0.2f",
        playerID, tostring(itemID), statType, addition))

    if not self[playerID].itemAdditions[itemID] then
        self[playerID].itemAdditions[itemID] = {}
        StatsAPI.printDebug(string.format("  Created new addition entry for item %s", tostring(itemID)))
    end

    local existing = self[playerID].itemAdditions[itemID][statType]
    self[playerID].sequenceCounter = self[playerID].sequenceCounter + 1
    local currentSequence = self[playerID].sequenceCounter

    local eqMult = _toEquivalentMultiplierFromAddition(player, statType, addition)

    self[playerID].itemAdditions[itemID][statType] = {
        lastDelta = addition,
        cumulative = (existing and existing.cumulative or 0) + addition,
        description = description or (existing and existing.description) or "Unknown",
        sequence = currentSequence,
        lastType = "addition",
        eqMult = eqMult,
        isAdditiveMultiplier = false,
        disabled = existing and existing.disabled == true or false
    }

    StatsAPI.printDebug(string.format("  Stored Addition: Item %s %s = %+0.2f (Cumulative: %+0.2f, Sequence: %d)",
        tostring(itemID), statType, addition, self[playerID].itemAdditions[itemID][statType].cumulative, currentSequence))

    self:RecalculateStatMultiplier(player, statType)
    self[playerID].lastSetFrameAdd[key] = currentFrame
end

-- Add or update additive-multiplier entry for a specific item and stat
function StatsAPI.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, itemID, statType, multiplierValue, description)
    if not player or not itemID or not statType or type(multiplierValue) ~= "number" then
        StatsAPI.printError("SetItemAdditiveMultiplier: Invalid parameters")
        return
    end

    self:InitPlayer(player)
    local playerID = StatsAPI:GetPlayerInstanceKey(player)
    local currentFrame = Game():GetFrameCount()
    self[playerID].lastSetFrameAddMul = self[playerID].lastSetFrameAddMul or {}
    local key = tostring(itemID) .. ":" .. tostring(statType)

    if self[playerID].lastSetFrameAddMul[key] == currentFrame then
        local existing = self[playerID].itemAdditiveMultipliers[itemID] and self[playerID].itemAdditiveMultipliers[itemID][statType]
        local prevDelta = existing and existing.lastDelta or nil
        local newDelta = multiplierValue - 1.0
        if prevDelta and math.abs(prevDelta - newDelta) < 0.00001 then
            StatsAPI.printDebug(string.format("SetItemAdditiveMultiplier skipped (same frame, same delta) for %s", key))
            return
        end
    end

    local delta = multiplierValue - 1.0
    StatsAPI.printDebug(string.format("SetItemAdditiveMultiplier: Player %s, Item %s, Stat %s, Mult %.2fx (Delta %+0.2f)",
        playerID, tostring(itemID), statType, multiplierValue, delta))

    if not self[playerID].itemAdditiveMultipliers[itemID] then
        self[playerID].itemAdditiveMultipliers[itemID] = {}
        StatsAPI.printDebug(string.format("  Created new additive-mult entry for item %s", tostring(itemID)))
    end

    local existing = self[playerID].itemAdditiveMultipliers[itemID][statType]
    self[playerID].sequenceCounter = self[playerID].sequenceCounter + 1
    local currentSequence = self[playerID].sequenceCounter

    local entry = self[playerID].itemAdditiveMultipliers[itemID][statType] or {}
    entry.lastDelta = delta
    entry.cumulative = (entry.cumulative or 0) + delta
    entry.description = description or entry.description or "Unknown"
    entry.sequence = currentSequence
    entry.lastType = "additive_multiplier"
    entry.eqMult = multiplierValue
    entry.disabled = entry.disabled == true
    if entry.firstAddMultFrame == nil then
        entry.firstAddMultFrame = currentFrame
    end
    self[playerID].itemAdditiveMultipliers[itemID][statType] = entry

    StatsAPI.printDebug(string.format("  Stored Additive Mult: Item %s %s = x%.2f (Delta %+0.2f, Seq %d)",
        tostring(itemID), statType, multiplierValue, delta, currentSequence))

    self:RecalculateStatMultiplier(player, statType)
    self[playerID].lastSetFrameAddMul[key] = currentFrame
end

-- Enable/disable multiplier entry for a specific item and stat without deleting data
function StatsAPI.stats.unifiedMultipliers:SetItemMultiplierDisabled(player, itemID, statType, disabled)
    if not player or not itemID or not statType then
        return false
    end

    self:InitPlayer(player)
    local playerID = StatsAPI:GetPlayerInstanceKey(player)
    local target = (disabled == true)
    local foundEntry = false
    local changed = false

    local function setDisabledOn(bucket)
        if type(bucket) ~= "table" then
            return
        end
        local perItem = bucket[itemID]
        if type(perItem) ~= "table" then
            return
        end
        local entry = perItem[statType]
        if type(entry) ~= "table" then
            return
        end

        foundEntry = true
        if entry.disabled ~= target then
            -- Keep the original sequence so "current" display keeps reflecting
            -- the last real multiplier/addition update.
            entry.disabled = target
            changed = true
        end
    end

    setDisabledOn(self[playerID].itemMultipliers)
    setDisabledOn(self[playerID].itemAdditions)
    setDisabledOn(self[playerID].itemAdditiveMultipliers)

    if not foundEntry then
        return false
    end

    if changed then
        self:RecalculateStatMultiplier(player, statType)
        StatsAPI.printDebug(string.format(
            "Unified Multipliers: %s Item %s %s (disabled=%s)",
            target and "Disabled" or "Enabled",
            tostring(itemID),
            statType,
            tostring(target)
        ))
    end

    return true
end

-- Player-scoped wrappers: use sourceKey instead of itemID
function StatsAPI.stats.unifiedMultipliers:SetPlayerMultiplier(player, sourceKey, statType, multiplier, description)
    local scopedKey = _playerScopedSourceKey(sourceKey)
    if not scopedKey then
        return false
    end
    self:SetItemMultiplier(player, scopedKey, statType, multiplier, description)
    return true
end

function StatsAPI.stats.unifiedMultipliers:SetPlayerAddition(player, sourceKey, statType, addition, description)
    local scopedKey = _playerScopedSourceKey(sourceKey)
    if not scopedKey then
        return false
    end
    self:SetItemAddition(player, scopedKey, statType, addition, description)
    return true
end

function StatsAPI.stats.unifiedMultipliers:SetPlayerAdditiveMultiplier(player, sourceKey, statType, multiplierValue, description)
    local scopedKey = _playerScopedSourceKey(sourceKey)
    if not scopedKey then
        return false
    end
    self:SetItemAdditiveMultiplier(player, scopedKey, statType, multiplierValue, description)
    return true
end

function StatsAPI.stats.unifiedMultipliers:SetPlayerMultiplierDisabled(player, sourceKey, statType, disabled)
    local scopedKey = _playerScopedSourceKey(sourceKey)
    if not scopedKey then
        return false
    end
    return self:SetItemMultiplierDisabled(player, scopedKey, statType, disabled)
end

function StatsAPI.stats.unifiedMultipliers:RemovePlayerMultiplier(player, sourceKey, statType)
    local scopedKey = _playerScopedSourceKey(sourceKey)
    if not scopedKey then
        return false
    end
    self:RemoveItemMultiplier(player, scopedKey, statType)
    return true
end

function StatsAPI.stats.unifiedMultipliers:RemovePlayerAddition(player, sourceKey, statType)
    local scopedKey = _playerScopedSourceKey(sourceKey)
    if not scopedKey then
        return false
    end
    self:RemoveItemAddition(player, scopedKey, statType)
    return true
end

-- Remove multiplier for a specific item and stat
function StatsAPI.stats.unifiedMultipliers:RemoveItemMultiplier(player, itemID, statType)
    if not player or not itemID or not statType then return end

    local playerID = StatsAPI:GetPlayerInstanceKey(player)
    local removed = false

    if self[playerID] and self[playerID].itemMultipliers[itemID] then
        self[playerID].itemMultipliers[itemID][statType] = nil
        if not next(self[playerID].itemMultipliers[itemID]) then
            self[playerID].itemMultipliers[itemID] = nil
        end
        removed = true
    end

    if self[playerID] and self[playerID].itemAdditions and self[playerID].itemAdditions[itemID] then
        self[playerID].itemAdditions[itemID][statType] = nil
        if not next(self[playerID].itemAdditions[itemID]) then
            self[playerID].itemAdditions[itemID] = nil
        end
        removed = true
    end

    if self[playerID] and self[playerID].itemAdditiveMultipliers and self[playerID].itemAdditiveMultipliers[itemID] then
        self[playerID].itemAdditiveMultipliers[itemID][statType] = nil
        if not next(self[playerID].itemAdditiveMultipliers[itemID]) then
            self[playerID].itemAdditiveMultipliers[itemID] = nil
        end
        removed = true
    end

    if removed then
        self:RecalculateStatMultiplier(player, statType)
        StatsAPI.printDebug(string.format("Unified Multipliers: Removed source %s %s (base/add/addMul)", tostring(itemID), statType))
    end
end

-- Remove addition AND additive multiplier for a specific item and stat
function StatsAPI.stats.unifiedMultipliers:RemoveItemAddition(player, itemID, statType)
    if not player or not itemID or not statType then return end

    local playerID = StatsAPI:GetPlayerInstanceKey(player)
    local removed = false

    if self[playerID] and self[playerID].itemAdditions and self[playerID].itemAdditions[itemID] then
        self[playerID].itemAdditions[itemID][statType] = nil
        if not next(self[playerID].itemAdditions[itemID]) then
            self[playerID].itemAdditions[itemID] = nil
        end
        removed = true
    end

    if self[playerID] and self[playerID].itemAdditiveMultipliers and self[playerID].itemAdditiveMultipliers[itemID] then
        self[playerID].itemAdditiveMultipliers[itemID][statType] = nil
        if not next(self[playerID].itemAdditiveMultipliers[itemID]) then
            self[playerID].itemAdditiveMultipliers[itemID] = nil
        end
        removed = true
    end

    if removed then
        self:RecalculateStatMultiplier(player, statType)
        StatsAPI.printDebug(string.format("Unified Multipliers: Removed Addition/AdditiveMult Item %s %s", tostring(itemID), statType))
    end
end

-- Recalculate total multiplier for a specific stat
function StatsAPI.stats.unifiedMultipliers:RecalculateStatMultiplier(player, statType)
    if not player or not statType then return end

    local playerID = StatsAPI:GetPlayerInstanceKey(player)
    if not self[playerID] then return end

    local totalMultiplierApply = 1.0
    local totalAdditionApply = 0.0
    local totalMultiplierDisplay = 1.0
    local lastDisplayCurrentVal = 1.0
    local lastDisplayItemID = nil
    local lastDisplayDescription = ""
    local lastDisplaySequence = 0
    local lastDisplayType = "multiplier"

    StatsAPI.printDebug(string.format("Recalculating %s for player %s:", statType, playerID))

    -- Build union of touched itemIDs
    local touched = {}
    for itemID, itemData in pairs(self[playerID].itemMultipliers) do
        if itemData[statType] then touched[itemID] = true end
    end
    if self[playerID].itemAdditions then
        for itemID, itemData in pairs(self[playerID].itemAdditions) do
            if itemData[statType] then touched[itemID] = true end
        end
    end
    if self[playerID].itemAdditiveMultipliers then
        for itemID, itemData in pairs(self[playerID].itemAdditiveMultipliers) do
            if itemData[statType] then touched[itemID] = true end
        end
    end

    local function setDisplayCandidate(seq, value, valueType, itemID, description)
        if type(seq) ~= "number" or seq <= lastDisplaySequence then
            return
        end
        lastDisplaySequence = seq
        lastDisplayCurrentVal = value
        lastDisplayType = valueType
        lastDisplayItemID = itemID
        lastDisplayDescription = description or ""
    end

    -- Aggregate per item
    for itemID, _ in pairs(touched) do
        local baseM, baseSeq, baseDesc, baseType = 1.0, 0, "", "multiplier"
        local baseEnabled = false
        if self[playerID].itemMultipliers[itemID] and self[playerID].itemMultipliers[itemID][statType] then
            local baseEntry = self[playerID].itemMultipliers[itemID][statType]
            baseEnabled = not (baseEntry.disabled == true)
            if baseEnabled then
                baseM = baseEntry.value or 1.0
            end
            baseSeq = baseEntry.sequence or 0
            baseDesc = baseEntry.description or ""
            baseType = baseEntry.lastType or "multiplier"
            if baseEnabled and baseType == "remove_mult" then
                baseType = "multiplier"
            end
        end

        local addCum, addSeq, addLastDelta, addDesc = 0, 0, 0, ""
        local addEnabled = false
        if self[playerID].itemAdditions and self[playerID].itemAdditions[itemID] and self[playerID].itemAdditions[itemID][statType] then
            local ad = self[playerID].itemAdditions[itemID][statType]
            addEnabled = not (ad.disabled == true)
            if addEnabled then
                addCum = ad.cumulative or 0
                addLastDelta = ad.lastDelta or 0
            end
            addSeq = ad.sequence or 0
            addDesc = ad.description or ""
        end

        local addMulDelta = 0.0
        local addMulSeq = 0
        local addMulLastDelta = 0
        local addMulDesc = ""
        local hasAddMul = false
        local addMulEnabled = false
        if self[playerID].itemAdditiveMultipliers and self[playerID].itemAdditiveMultipliers[itemID] and self[playerID].itemAdditiveMultipliers[itemID][statType] then
            local am = self[playerID].itemAdditiveMultipliers[itemID][statType]
            addMulEnabled = not (am.disabled == true)
            if addMulEnabled then
                addMulDelta = am.cumulative or 0
                addMulLastDelta = am.lastDelta or 0
            end
            addMulSeq = am.sequence or 0
            addMulDesc = am.description or ""
            hasAddMul = true
        end

        local effectiveM = (baseM or 1.0) + (addMulDelta or 0.0)
        if effectiveM <= 0 then effectiveM = 0 end
        totalMultiplierApply = totalMultiplierApply * effectiveM
        totalAdditionApply = totalAdditionApply + addCum

        if hasAddMul and addMulEnabled and addMulSeq > 0 then
            local addMulType = (addMulLastDelta or 0) < 0 and "remove_mult" or "add_mult"
            local addMulValue = addMulLastDelta

            -- Same-source additive stacking rule:
            -- first additive-multiplier application should be shown as xN (multiplier),
            -- later updates for the same source remain +/- delta display.
            local isFirstAddMulForSource = (not baseEnabled)
                and math.abs((addMulDelta or 0) - (addMulLastDelta or 0)) < 0.00001

            if isFirstAddMulForSource then
                addMulType = "multiplier"
                addMulValue = effectiveM
            end

            setDisplayCandidate(addMulSeq, addMulValue, addMulType, itemID, addMulDesc)
        end

        if baseEnabled and baseSeq > 0 then
            setDisplayCandidate(baseSeq, baseM, baseType, itemID, baseDesc)
        end

        StatsAPI.printDebug(string.format(
            "  Item %s: base=%.2f (enabled=%s), addMulDelta=%+0.2f (enabled=%s), eff=%.2f, addCum=%+0.2f (enabled=%s)",
            tostring(itemID),
            baseM,
            tostring(baseEnabled),
            addMulDelta,
            tostring(addMulEnabled),
            effectiveM,
            addCum,
            tostring(addEnabled)
        ))
    end

    local computedTotalApply = totalMultiplierApply
    local vanillaDisplayMultiplier = _getVanillaDisplayMultiplier(player, statType)
    totalMultiplierDisplay = computedTotalApply * vanillaDisplayMultiplier

    if not self[playerID].statMultipliers then
        self[playerID].statMultipliers = {}
    end

    self[playerID].statMultipliers[statType] = {
        current = lastDisplayCurrentVal,
        displayCurrent = lastDisplayCurrentVal,
        total = computedTotalApply,
        totalDisplay = totalMultiplierDisplay,
        vanillaDisplay = vanillaDisplayMultiplier,
        totalApply = computedTotalApply,
        totalAdditions = totalAdditionApply,
        lastItemID = lastDisplayItemID,
        description = lastDisplayDescription,
        sequence = lastDisplaySequence,
        currentType = lastDisplayType,
        displayType = lastDisplayType,
        displaySequence = lastDisplaySequence
    }

    if lastDisplayType == "add_mult" or lastDisplayType == "remove_mult" then
        StatsAPI.printDebug(string.format(
            "Unified Multipliers: %s recalculated - Current: %+0.2f (from %s, seq: %d), Total: %.2fx (display, vanilla %.2fx), Apply: %.2fx",
            statType,
            lastDisplayCurrentVal,
            tostring(lastDisplayItemID),
            lastDisplaySequence,
            totalMultiplierDisplay,
            vanillaDisplayMultiplier,
            computedTotalApply
        ))
    else
        StatsAPI.printDebug(string.format(
            "Unified Multipliers: %s recalculated - Current: %.2fx (from %s, seq: %d), Total: %.2fx (display, vanilla %.2fx), Apply: %.2fx",
            statType,
            lastDisplayCurrentVal,
            tostring(lastDisplayItemID),
            lastDisplaySequence,
            totalMultiplierDisplay,
            vanillaDisplayMultiplier,
            computedTotalApply
        ))
    end

    if StatsAPI.stats.multiplierDisplay then
        StatsAPI.stats.multiplierDisplay:UpdateFromUnifiedSystem(
            player,
            statType,
            lastDisplayCurrentVal,
            totalMultiplierDisplay,
            lastDisplayType
        )
    end

    if not self._isEvaluatingCache then
        self:QueueCacheUpdate(player, statType)
    end
end

-- Get current and total multipliers for a stat
function StatsAPI.stats.unifiedMultipliers:GetMultipliers(player, statType)
    if not player or not statType then return 1.0, 1.0 end

    local playerID = StatsAPI:GetPlayerInstanceKey(player)
    if not self[playerID] or not self[playerID].statMultipliers[statType] then
        return 1.0, 1.0
    end

    local data = self[playerID].statMultipliers[statType]
    return data.current, data.total
end

-- Get all multipliers for a player
function StatsAPI.stats.unifiedMultipliers:GetAllMultipliers(player)
    if not player then return {} end

    local playerID = StatsAPI:GetPlayerInstanceKey(player)
    if not self[playerID] or not self[playerID].statMultipliers then
        return {}
    end

    return self[playerID].statMultipliers
end

-- Reset all multipliers for a player (for new game)
function StatsAPI.stats.unifiedMultipliers:ResetPlayer(player)
    if not player then return end

    local playerID = StatsAPI:GetPlayerInstanceKey(player)
    self[playerID] = nil

    StatsAPI.printDebug(string.format("Unified Multipliers: Reset for player %s", playerID))
end

-- Save multipliers (uses StatsAPI built-in save system)
function StatsAPI.stats.unifiedMultipliers:SaveToSaveManager(player)
    if not player then return end

    local playerID = StatsAPI:GetPlayerInstanceKey(player)
    if not self[playerID] then return end

    local playerSave = StatsAPI:GetPlayerRunData(player)

    if playerSave then
        local function serializeItemKey(itemID)
            if type(itemID) == "number" then
                return "n_" .. tostring(itemID)
            end
            return "s_" .. tostring(itemID)
        end

        local serialItemMultipliers = {}
        if self[playerID].itemMultipliers then
            for itemID, perItem in pairs(self[playerID].itemMultipliers) do
                local key = serializeItemKey(itemID)
                serialItemMultipliers[key] = {}
                for statType, data in pairs(perItem) do
                    serialItemMultipliers[key][statType] = {
                        value = data.value,
                        description = data.description,
                        sequence = data.sequence,
                        lastType = data.lastType,
                        disabled = data.disabled == true
                    }
                end
            end
        end

        local serialItemAdditions = {}
        if self[playerID].itemAdditions then
            for itemID, perItem in pairs(self[playerID].itemAdditions) do
                local key = serializeItemKey(itemID)
                serialItemAdditions[key] = {}
                for statType, data in pairs(perItem) do
                    serialItemAdditions[key][statType] = {
                        lastDelta = data.lastDelta,
                        cumulative = data.cumulative,
                        description = data.description,
                        sequence = data.sequence,
                        lastType = data.lastType,
                        eqMult = data.eqMult,
                        disabled = data.disabled == true
                    }
                end
            end
        end

        local serialItemAdditiveMultipliers = {}
        if self[playerID].itemAdditiveMultipliers then
            for itemID, perItem in pairs(self[playerID].itemAdditiveMultipliers) do
                local key = serializeItemKey(itemID)
                serialItemAdditiveMultipliers[key] = {}
                for statType, data in pairs(perItem) do
                    serialItemAdditiveMultipliers[key][statType] = {
                        lastDelta = data.lastDelta,
                        cumulative = data.cumulative,
                        description = data.description,
                        sequence = data.sequence,
                        lastType = data.lastType,
                        eqMult = data.eqMult,
                        firstAddMultFrame = data.firstAddMultFrame,
                        disabled = data.disabled == true
                    }
                end
            end
        end

        playerSave.unifiedMultipliers = {
            itemMultipliers = serialItemMultipliers,
            itemAdditions = serialItemAdditions,
            itemAdditiveMultipliers = serialItemAdditiveMultipliers,
            statMultipliers = self[playerID].statMultipliers
        }

        local multCount = 0
        for _ in pairs(serialItemMultipliers) do multCount = multCount + 1 end
        local addCount = 0
        for _ in pairs(serialItemAdditions) do addCount = addCount + 1 end
        local addMultCount = 0
        for _ in pairs(serialItemAdditiveMultipliers) do addMultCount = addMultCount + 1 end
        StatsAPI.printDebug(string.format("Unified Multipliers: Saved for player %s (mults:%d, adds:%d, addMults:%d)",
            playerID, multCount, addCount, addMultCount))
    end
end

-- Load multipliers (uses StatsAPI built-in save system)
function StatsAPI.stats.unifiedMultipliers:LoadFromSaveManager(player)
    if not player then return end

    local playerID = StatsAPI:GetPlayerInstanceKey(player)
    local playerSave = StatsAPI:GetPlayerRunData(player)

    if playerSave and playerSave.unifiedMultipliers then
        self:InitPlayer(player)
        local function deserializeItemKey(key)
            local id = tostring(key)
            local num = id:match("^n_(-?%d+)$")
            if num then
                return tonumber(num)
            end

            local str = id:match("^s_(.+)$")
            if str then
                return str
            end

            -- Legacy compatibility (older saves used i_<number>)
            local legacyNum = id:match("^i_(%d+)$")
            if legacyNum then
                return tonumber(legacyNum)
            end

            return key
        end

        self[playerID].itemMultipliers = {}
        if playerSave.unifiedMultipliers.itemMultipliers then
            for key, perItem in pairs(playerSave.unifiedMultipliers.itemMultipliers) do
                local itemID = deserializeItemKey(key)
                self[playerID].itemMultipliers[itemID] = perItem
            end
        end

        self[playerID].itemAdditions = {}
        if playerSave.unifiedMultipliers.itemAdditions then
            for key, perItem in pairs(playerSave.unifiedMultipliers.itemAdditions) do
                local itemID = deserializeItemKey(key)
                self[playerID].itemAdditions[itemID] = perItem
            end
        end

        self[playerID].itemAdditiveMultipliers = {}
        if playerSave.unifiedMultipliers.itemAdditiveMultipliers then
            for key, perItem in pairs(playerSave.unifiedMultipliers.itemAdditiveMultipliers) do
                local itemID = deserializeItemKey(key)
                self[playerID].itemAdditiveMultipliers[itemID] = perItem
            end
        end

        self[playerID].statMultipliers = playerSave.unifiedMultipliers.statMultipliers or {}

        local multCount = 0
        for _ in pairs(self[playerID].itemMultipliers) do multCount = multCount + 1 end
        local addCount = 0
        for _ in pairs(self[playerID].itemAdditions) do addCount = addCount + 1 end
        local addMultCount = 0
        for _ in pairs(self[playerID].itemAdditiveMultipliers) do addMultCount = addMultCount + 1 end
        StatsAPI.printDebug(string.format("Unified Multipliers: Loaded for player %s (mults:%d, adds:%d, addMults:%d)",
            playerID, multCount, addCount, addMultCount))

        local allStatTypes = {}
        for statType, _ in pairs(self[playerID].statMultipliers) do
            allStatTypes[statType] = true
        end
        for _, itemData in pairs(self[playerID].itemMultipliers) do
            for statType, _ in pairs(itemData) do
                allStatTypes[statType] = true
            end
        end
        for _, itemData in pairs(self[playerID].itemAdditions) do
            for statType, _ in pairs(itemData) do
                allStatTypes[statType] = true
            end
        end
        for _, itemData in pairs(self[playerID].itemAdditiveMultipliers) do
            for statType, _ in pairs(itemData) do
                allStatTypes[statType] = true
            end
        end

        for statType, _ in pairs(allStatTypes) do
            self:RecalculateStatMultiplier(player, statType)
            StatsAPI.printDebug(string.format("[Unified] Recalculated %s after loading", statType))
        end

        self._justLoaded = true
    end
end

-------------------------------------------------------------------------------
-- Multiplier Display System (HUD overlay)
-------------------------------------------------------------------------------
StatsAPI.stats.multiplierDisplay = StatsAPI.stats.multiplierDisplay or {}

local StatsFont = Font()
StatsFont:Load("font/luaminioutlined.fnt")
StatsAPI.printDebug("Using Isaac default font for multiplier display")

local ButtonAction_ACTION_MAP = ButtonAction.ACTION_MAP

-- Display settings
local TICKS_PER_SECOND = 30
local TAB_HOLD_SECONDS_MIN = 0
local TAB_HOLD_SECONDS_MAX = 10
local DISPLAY_DURATION_SECONDS_MIN = 0
local DISPLAY_DURATION_SECONDS_MAX = 30
local FADE_IN_SECONDS_MIN = 0
local FADE_IN_SECONDS_MAX = 10
local FADE_OUT_SECONDS_MIN = 0
local FADE_OUT_SECONDS_MAX = 10
local DEFAULT_TAB_HOLD_SECONDS = 0
local DEFAULT_DISPLAY_DURATION_SECONDS = 5
local DEFAULT_FADE_IN_SECONDS = 0.2
local DEFAULT_FADE_OUT_SECONDS = 0.6
local DEFAULT_MULTIPLIER_DISPLAY_DURATION = math.floor((DEFAULT_DISPLAY_DURATION_SECONDS * TICKS_PER_SECOND) + 0.5)
local MULTIPLIER_DISPLAY_DURATION = DEFAULT_MULTIPLIER_DISPLAY_DURATION
local MULTIPLIER_MOVEMENT_DURATION = 10
local MULTIPLIER_FADING_DURATION = 40
local TAB_DISPLAY_MAX_ALPHA = 0.8

-- HUD base positions matched to Stats Plus behavior.
local SINGLE_PLAYER_STAT_POSITIONS = {
    Speed = {x = 17, y = 88},
    Tears = {x = 17, y = 100},
    Damage = {x = 17, y = 112},
    Range = {x = 17, y = 124},
    ShotSpeed = {x = 17, y = 136},
    Luck = {x = 17, y = 148}
}

local MULTI_PLAYER_STAT_POSITIONS = {
    Speed = {x = 17, y = 84},
    Tears = {x = 17, y = 98},
    Damage = {x = 17, y = 112},
    Range = {x = 17, y = 126},
    ShotSpeed = {x = 17, y = 140},
    Luck = {x = 17, y = 154}
}

local JACOB_MAIN_STAT_POSITIONS = {
    Speed = {x = 17, y = 87},
    Tears = {x = 17, y = 96},
    Damage = {x = 17, y = 110},
    Range = {x = 17, y = 124},
    ShotSpeed = {x = 17, y = 138},
    Luck = {x = 17, y = 152}
}

local STATS_PLUS_SPACING_X = 5
local BASE_STAT_OFFSET_X = 48
local BASE_STAT_OFFSET_Y = 1

StatsAPI.stats.multiplierDisplay.playerData = {}

function StatsAPI.stats.multiplierDisplay:InitPlayer(player)
    if not self._tableRefLogged then
        self._tableRefLogged = true
        StatsAPI.printDebug(string.format("[Display] table ref = %s", tostring(self)))
    end

    local playerID = StatsAPI:GetPlayerInstanceKey(player)
    if not self.playerData[playerID] then
        StatsAPI.printDebug(string.format("InitPlayer: Creating new player data for player ID %s", playerID))
        self.playerData[playerID] = {
            displayStartFrame = 0,
            isDisplaying = false,
            tabDisplayStartFrame = 0,
            tabPressStartFrame = nil,
            tabFadeInStartFrame = nil,
            tabFadeOutStartFrame = nil,
            tabFadeOutStartAlpha = nil,
            tabAlpha = 0,
            isTabDisplaying = false,
            lastDebugState = nil,
            lastDisplayLogicState = nil,
            lastDisplayState = nil,
            lastTabState = nil
        }
    end
end

function StatsAPI.stats.multiplierDisplay:UpdateFromUnifiedSystem(player, statType, currentValue, totalMult, currentType)
    if not player or not statType then return end

    self:InitPlayer(player)
    local playerID = StatsAPI:GetPlayerInstanceKey(player)

    -- Do not display plain additions
    if currentType == "addition" then
        return
    end

    if not self.playerData[playerID].unifiedData then
        self.playerData[playerID].unifiedData = {}
    end

    local storeType = currentType or "multiplier"
    local storeCurrent = currentValue
    self.playerData[playerID].unifiedData[statType] = {
        current = storeCurrent,
        total = totalMult,
        currentType = storeType,
        timestamp = Game():GetFrameCount()
    }

    self.playerData[playerID].displayStartFrame = Game():GetFrameCount()
    self.playerData[playerID].isDisplaying = true

    if currentType == "addition" then
        StatsAPI.printDebug(string.format("Multiplier Display Updated: %s - Current: %+0.2f, Total: %.2fx (addition)",
            statType, currentValue, totalMult))
    else
        StatsAPI.printDebug(string.format("Multiplier Display Updated: %s - Current: %.2fx, Total: %.2fx",
            statType, currentValue, totalMult))
    end

    StatsAPI.printDebug(string.format("  Current unified data for player %s:", playerID))
    for stat, data in pairs(self.playerData[playerID].unifiedData) do
        if data.currentType == "addition" then
            StatsAPI.printDebug(string.format("    %s: Current=%+0.2f, Total=%.2fx", stat, data.current, data.total))
        else
            StatsAPI.printDebug(string.format("    %s: Current=%.2fx, Total=%.2fx", stat, data.current, data.total))
        end
    end
end

function StatsAPI.stats.multiplierDisplay:ForceDisplay(player, statType, currentValue, totalMult, currentType)
    if not player or not statType then return end
    self:InitPlayer(player)
    local playerID = StatsAPI:GetPlayerInstanceKey(player)
    if not self.playerData[playerID].unifiedData then
        self.playerData[playerID].unifiedData = {}
    end
    self.playerData[playerID].unifiedData[statType] = {
        current = currentValue,
        total = totalMult,
        currentType = currentType or "multiplier",
        timestamp = Game():GetFrameCount()
    }
    self.playerData[playerID].displayStartFrame = Game():GetFrameCount()
    self.playerData[playerID].isDisplaying = true
end

function StatsAPI.stats.multiplierDisplay:RefreshFromUnified(player)
    if not player or not StatsAPI.stats or not StatsAPI.stats.unifiedMultipliers then
        return false
    end

    self:InitPlayer(player)
    local playerID = StatsAPI:GetPlayerInstanceKey(player)
    local all = StatsAPI.stats.unifiedMultipliers:GetAllMultipliers(player)
    local hasAny = false

    self.playerData[playerID].unifiedData = {}

    for statType, data in pairs(all) do
        local currentType = data.displayType or data.currentType or "multiplier"
        if currentType ~= "addition" then
            local current = 1.0
            if type(data.displayCurrent) == "number" then
                current = data.displayCurrent
            elseif type(data.current) == "number" then
                current = data.current
            end
            local total = 1.0
            if type(data.totalDisplay) == "number" then
                total = data.totalDisplay
            elseif type(data.total) == "number" then
                total = data.total
            end
            self.playerData[playerID].unifiedData[statType] = {
                current = current,
                total = total,
                currentType = currentType,
                timestamp = Game():GetFrameCount()
            }
            hasAny = true
        end
    end

    if hasAny then
        self.playerData[playerID].displayStartFrame = Game():GetFrameCount()
        self.playerData[playerID].isDisplaying = true
    end

    return hasAny
end

function StatsAPI.stats.multiplierDisplay:RefreshAllFromUnified()
    local hasAny = false
    local numPlayers = Game():GetNumPlayers()
    for i = 0, numPlayers - 1 do
        local player = Isaac.GetPlayer(i)
        if player and self:RefreshFromUnified(player) then
            hasAny = true
        end
    end
    return hasAny
end

local function GetHUDRelativeDisplayOffset()
    local hudOffset = tonumber(Options and Options.HUDOffset) or 0
    local vanillaHUDOffset = Vector(20 * hudOffset, 12 * hudOffset)

    local customX, customY = 0, 0
    if StatsAPI and type(StatsAPI.GetDisplayOffsets) == "function" then
        customX, customY = StatsAPI:GetDisplayOffsets()
    elseif StatsAPI and type(StatsAPI.settings) == "table" then
        customX = tonumber(StatsAPI.settings.displayOffsetX) or 0
        customY = tonumber(StatsAPI.settings.displayOffsetY) or 0
    end

    local customOffset = Vector(customX, customY)
    return vanillaHUDOffset + customOffset
end

local function IsMainPlayerJacob()
    local mainPlayer = Isaac.GetPlayer(0)
    if not mainPlayer then
        return false
    end
    return mainPlayer:GetPlayerType() == PlayerType.PLAYER_JACOB
end

local function GetStatBasePosition(statType)
    local positionSet = SINGLE_PLAYER_STAT_POSITIONS
    if IsMainPlayerJacob() then
        positionSet = JACOB_MAIN_STAT_POSITIONS
    elseif Game():GetNumPlayers() > 1 then
        positionSet = MULTI_PLAYER_STAT_POSITIONS
    end
    return positionSet[statType]
end

local function HasBethanyInParty()
    local numPlayers = Game():GetNumPlayers()
    for i = 0, numPlayers - 1 do
        local p = Isaac.GetPlayer(i)
        if p then
            local pType = p:GetPlayerType()
            if pType == PlayerType.PLAYER_BETHANY or pType == PlayerType.PLAYER_BETHANY_B then
                return true
            end
        end
    end
    return false
end

local function GetPlayerIndexDisplayOffset(player, renderIndex)
    local idx = tonumber(renderIndex)
    if type(idx) ~= "number" then
        idx = tonumber(player and player.Index) or 0
    end
    if idx <= 0 then
        return 0, 0
    end
    return 4, 7 * idx
end

local function ToFixed(value, digits)
    if type(value) ~= "number" then
        return nil
    end

    local factor = 10 ^ digits
    local epsilon = 1e-8
    if value > 0 then
        return math.floor(value * factor + epsilon) / factor
    end
    return math.ceil(value * factor + epsilon) / factor
end

local function ToFixedFormatted(value, digits)
    local fixed = ToFixed(value, digits)
    if type(fixed) ~= "number" then
        return nil
    end

    local text = tostring(fixed)
    if digits <= 0 then
        return text
    end

    local dotIndex = string.find(text, ".", 1, true)
    if not dotIndex then
        return text .. "." .. string.rep("0", digits)
    end

    local fractionLength = #text - dotIndex
    if fractionLength < digits then
        return text .. string.rep("0", digits - fractionLength)
    end
    return text
end

local statReaderByType = {
    Speed = function(p) return math.min(2, p.MoveSpeed) end,
    Tears = function(p) return 30 / (p.MaxFireDelay + 1) end,
    Damage = function(p) return p.Damage end,
    Range = function(p) return p.TearRange / 40 end,
    ShotSpeed = function(p) return p.ShotSpeed end,
    Luck = function(p) return p.Luck end
}

local function GetDisplayedStatValue(player, statType)
    if not player or not statType then
        return nil
    end

    local reader = statReaderByType[statType]
    if type(reader) == "function" then
        return reader(player)
    end

    return nil
end

local function GetDisplayedStatText(player, statType)
    local value = GetDisplayedStatValue(player, statType)
    if type(value) ~= "number" then
        return nil
    end
    return ToFixedFormatted(value, 2)
end

local function GetStatTextWidth(statText)
    if type(statText) ~= "string" or statText == "" then
        return 0
    end

    if type(StatsFont.GetCharacterWidth) == "function" then
        local width = 0
        for i = 1, #statText do
            local ch = string.sub(statText, i, i)
            local chWidth = StatsFont:GetCharacterWidth(ch)
            if type(chWidth) == "number" then
                width = width + chWidth
            end
        end
        return width
    end

    return StatsFont:GetStringWidth(statText)
end

local function GetSharedStatTextOffsetX(player)
    if not player then
        return 0
    end

    local referenceWidth = GetStatTextWidth("0.00")
    local maxWidth = referenceWidth
    local statTypes = {"Speed", "Tears", "Damage", "Range", "ShotSpeed", "Luck"}

    for _, statType in ipairs(statTypes) do
        local statText = GetDisplayedStatText(player, statType)
        local statWidth = GetStatTextWidth(statText)
        if statWidth > maxWidth then
            maxWidth = statWidth
        end
    end

    return maxWidth - referenceWidth
end

local _achievementsEnabledCache = nil

local function AreAchievementsEnabled()
    if type(_achievementsEnabledCache) == "boolean" then
        return _achievementsEnabledCache
    end

    local enabled = false
    local ok, machine = pcall(function()
        return Isaac.Spawn(6, 11, 0, Vector(0, 0), Vector(0, 0), nil)
    end)
    if ok and machine then
        enabled = machine:Exists()
        machine:Remove()
    end

    _achievementsEnabledCache = enabled
    return enabled
end

local function GetIconDisplayOffsetY()
    local challenge = Game().Challenge
    if type(Isaac.GetChallenge) == "function" then
        challenge = Isaac.GetChallenge()
    end

    if Game().Difficulty == Difficulty.DIFFICULTY_NORMAL
        and challenge == Challenge.CHALLENGE_NULL
        and AreAchievementsEnabled() then
        return -16
    end
    return 0
end

local VANILLA_DISPLAY_TRACKED_STATS = {"Damage", "Tears"}

local function GetUnifiedStatEntry(player, statType)
    if not player
        or not StatsAPI
        or not StatsAPI.stats
        or not StatsAPI.stats.unifiedMultipliers
        or type(StatsAPI.GetPlayerInstanceKey) ~= "function" then
        return nil
    end

    local unified = StatsAPI.stats.unifiedMultipliers
    local playerID = StatsAPI:GetPlayerInstanceKey(player)
    local perPlayer = unified and unified[playerID]
    return perPlayer and perPlayer.statMultipliers and perPlayer.statMultipliers[statType] or nil
end

local function HasActiveCustomContribution(player, statType)
    if not player
        or not StatsAPI
        or not StatsAPI.stats
        or not StatsAPI.stats.unifiedMultipliers
        or type(StatsAPI.GetPlayerInstanceKey) ~= "function" then
        return false
    end

    local unified = StatsAPI.stats.unifiedMultipliers
    local playerID = StatsAPI:GetPlayerInstanceKey(player)
    local perPlayer = unified and unified[playerID]
    if type(perPlayer) ~= "table" then
        return false
    end

    local function hasEnabledEntry(bucket)
        if type(bucket) ~= "table" then
            return false
        end
        for _, perItem in pairs(bucket) do
            if type(perItem) == "table" then
                local entry = perItem[statType]
                if type(entry) == "table" and entry.disabled ~= true then
                    return true
                end
            end
        end
        return false
    end

    if hasEnabledEntry(perPlayer.itemMultipliers) then
        return true
    end
    if hasEnabledEntry(perPlayer.itemAdditions) then
        return true
    end
    if hasEnabledEntry(perPlayer.itemAdditiveMultipliers) then
        return true
    end

    return false
end

local function GetVanillaDisplayChangeMultiplier(previousTotal, currentTotal)
    local prev = type(previousTotal) == "number" and previousTotal or 1.0
    local current = type(currentTotal) == "number" and currentTotal or 1.0

    if math.abs(prev) <= 0.00001 then
        return current
    end

    return current / prev
end

local function SyncVanillaOnlyDisplayData(player, data)
    if not player or type(data) ~= "table" then
        return false
    end

    if type(data.unifiedData) ~= "table" then
        data.unifiedData = {}
    end
    if type(data.vanillaSnapshot) ~= "table" then
        data.vanillaSnapshot = {}
    end

    local changed = false
    local trackingEnabled = _isVanillaDisplayTrackingEnabled()
    local currentFrame = Game():GetFrameCount()

    for _, statType in ipairs(VANILLA_DISPLAY_TRACKED_STATS) do
        local vanillaMult = trackingEnabled and _getVanillaDisplayMultiplier(player, statType) or 1.0
        local prevVanillaMult = data.vanillaSnapshot[statType]
        if type(prevVanillaMult) ~= "number" then
            prevVanillaMult = 1.0
        end
        if math.abs(vanillaMult - prevVanillaMult) > 0.00001 then
            changed = true
        end
        data.vanillaSnapshot[statType] = vanillaMult

        local existing = data.unifiedData[statType]
        local hasActiveCustom = HasActiveCustomContribution(player, statType)
        local shouldShowVanillaOnly = trackingEnabled and vanillaMult ~= 1.0 and not hasActiveCustom

        if shouldShowVanillaOnly then
            local currentDisplay = vanillaMult
            if math.abs(vanillaMult - prevVanillaMult) > 0.00001 then
                currentDisplay = GetVanillaDisplayChangeMultiplier(prevVanillaMult, vanillaMult)
            elseif type(existing) == "table" and type(existing.current) == "number" then
                currentDisplay = existing.current
            end

            local prevCurrent = type(existing) == "table" and existing.current or nil
            if type(prevCurrent) ~= "number" or math.abs(prevCurrent - currentDisplay) > 0.00001 then
                changed = true
            end
            data.unifiedData[statType] = {
                current = currentDisplay,
                -- Keep this as pure apply value (x1.00). Live vanilla multiplier gets
                -- merged in GetLiveDisplayTotalMultiplier().
                total = 1.0,
                currentType = "multiplier",
                timestamp = currentFrame,
                isVanillaOnly = true
            }
        elseif type(existing) == "table" and existing.isVanillaOnly == true then
            data.unifiedData[statType] = nil
            changed = true
        end
    end

    return changed
end

local function GetLiveDisplayTotalMultiplier(player, statType, fallbackTotal)
    local baseTotal = nil

    local statEntry = GetUnifiedStatEntry(player, statType)
    if type(statEntry) == "table" then
        if type(statEntry.totalApply) == "number" then
            baseTotal = statEntry.totalApply
        elseif type(statEntry.total) == "number" then
            baseTotal = statEntry.total
        end
    end

    if type(baseTotal) ~= "number" then
        if type(fallbackTotal) == "number" then
            baseTotal = fallbackTotal
        else
            baseTotal = 1.0
        end
    end

    local vanillaDisplayMultiplier = _getVanillaDisplayMultiplier(player, statType)
    return baseTotal * vanillaDisplayMultiplier
end

local function IsRenderableCurrentData(current, currentType)
    return type(current) == "number"
        and type(currentType) == "string"
        and currentType ~= "addition"
end

local function GetLiveDisplayCurrent(player, statType, fallbackCurrent, fallbackType)
    local statEntry = GetUnifiedStatEntry(player, statType)
    if type(statEntry) == "table" then
        local sequence = statEntry.displaySequence
        if type(sequence) ~= "number" then
            sequence = statEntry.sequence
        end
        if type(sequence) ~= "number" or sequence <= 0 then
            return fallbackCurrent, fallbackType
        end

        local current = statEntry.displayCurrent
        local currentType = statEntry.displayType
        if IsRenderableCurrentData(current, currentType) then
            return current, currentType
        end

        current = statEntry.current
        currentType = statEntry.currentType
        if IsRenderableCurrentData(current, currentType) then
            return current, currentType
        end
    end
    return fallbackCurrent, fallbackType
end

local HUD_DISPLAY_MODE_BY_ALIAS = {
    last = "last",
    current = "last",
    recent = "last",
    last_multiplier = "last",
    final = "final",
    total = "final",
    final_multiplier = "final",
    total_multiplier = "final",
    both = "both",
    all = "both"
}

local function NormalizeHUDDisplayMode(mode)
    if type(mode) ~= "string" then
        return "both"
    end
    local lowered = string.lower(mode)
    return HUD_DISPLAY_MODE_BY_ALIAS[lowered] or "both"
end

local function GetHUDDisplayMode()
    if StatsAPI and type(StatsAPI.GetDisplayMode) == "function" then
        return NormalizeHUDDisplayMode(StatsAPI:GetDisplayMode())
    end
    if StatsAPI and type(StatsAPI.settings) == "table" then
        return NormalizeHUDDisplayMode(StatsAPI.settings.displayMode)
    end
    return "both"
end

local function NormalizeSeconds(value, defaultValue, minValue, maxValue)
    local num = nil
    if type(value) == "number" then
        num = value
    elseif type(value) == "string" then
        num = tonumber(value)
    end
    if type(num) ~= "number" then
        num = defaultValue
    end
    if num < minValue then
        num = minValue
    elseif num > maxValue then
        num = maxValue
    end
    return num
end

local function GetHUDTimingFrames()
    local holdSeconds = DEFAULT_TAB_HOLD_SECONDS
    local displaySeconds = DEFAULT_DISPLAY_DURATION_SECONDS
    local fadeInSeconds = DEFAULT_FADE_IN_SECONDS
    local fadeOutSeconds = DEFAULT_FADE_OUT_SECONDS

    if StatsAPI then
        if type(StatsAPI.GetTabHoldSeconds) == "function" then
            holdSeconds = StatsAPI:GetTabHoldSeconds()
        elseif type(StatsAPI.settings) == "table" then
            holdSeconds = StatsAPI.settings.tabHoldSeconds
        end

        if type(StatsAPI.GetDisplayDurationSeconds) == "function" then
            displaySeconds = StatsAPI:GetDisplayDurationSeconds()
        elseif type(StatsAPI.settings) == "table" then
            displaySeconds = StatsAPI.settings.displayDurationSeconds
        end

        if type(StatsAPI.GetFadeInSeconds) == "function" then
            fadeInSeconds = StatsAPI:GetFadeInSeconds()
        elseif type(StatsAPI.settings) == "table" then
            fadeInSeconds = StatsAPI.settings.fadeInSeconds
        end

        if type(StatsAPI.GetFadeOutSeconds) == "function" then
            fadeOutSeconds = StatsAPI:GetFadeOutSeconds()
        elseif type(StatsAPI.settings) == "table" then
            fadeOutSeconds = StatsAPI.settings.fadeOutSeconds
        end
    end

    holdSeconds = NormalizeSeconds(
        holdSeconds,
        DEFAULT_TAB_HOLD_SECONDS,
        TAB_HOLD_SECONDS_MIN,
        TAB_HOLD_SECONDS_MAX
    )
    displaySeconds = NormalizeSeconds(
        displaySeconds,
        DEFAULT_DISPLAY_DURATION_SECONDS,
        DISPLAY_DURATION_SECONDS_MIN,
        DISPLAY_DURATION_SECONDS_MAX
    )
    fadeInSeconds = NormalizeSeconds(
        fadeInSeconds,
        DEFAULT_FADE_IN_SECONDS,
        FADE_IN_SECONDS_MIN,
        FADE_IN_SECONDS_MAX
    )
    fadeOutSeconds = NormalizeSeconds(
        fadeOutSeconds,
        DEFAULT_FADE_OUT_SECONDS,
        FADE_OUT_SECONDS_MIN,
        FADE_OUT_SECONDS_MAX
    )

    local holdFrames = math.max(0, math.floor((holdSeconds * TICKS_PER_SECOND) + 0.5))
    local displayFrames = math.max(1, math.floor((displaySeconds * TICKS_PER_SECOND) + 0.5))
    local fadeInFrames = math.max(0, math.floor((fadeInSeconds * TICKS_PER_SECOND) + 0.5))
    local fadeOutFrames = math.max(0, math.floor((fadeOutSeconds * TICKS_PER_SECOND) + 0.5))
    return holdFrames, displayFrames, fadeInFrames, fadeOutFrames
end

-- Render a single multiplier stat
local function RenderMultiplierStat(statType, currentValue, totalMult, currentType, pos, alpha, displayMode)
    if type(currentValue) ~= "number" or type(totalMult) ~= "number" then
        StatsAPI.printError(string.format("RenderMultiplierStat: currentValue and totalMult must be numbers, got %s and %s",
            type(currentValue), type(totalMult)))
        return
    end

    if currentType == "addition" then
        return
    end

    local renderMode = NormalizeHUDDisplayMode(displayMode)
    local showCurrent = renderMode ~= "final"
    local showTotal = renderMode ~= "last"
    local currentText = nil
    if showCurrent then
        if currentType == "add_mult" or currentType == "remove_mult" then
            currentText = string.format("%+0.2f", currentValue)
        else
            currentText = string.format("x%.2f", currentValue)
        end
    end

    local totalValue = nil
    if showTotal then
        if showCurrent and currentText ~= nil then
            totalValue = string.format("/x%.2f", totalMult)
        else
            totalValue = string.format("x%.2f", totalMult)
        end
    end

    if currentText == nil and totalValue == nil then
        return
    end

    local currentColor = nil
    if currentText ~= nil then
        if currentType == "addition" or currentType == "add_mult" or currentType == "remove_mult" then
            if currentValue > 0 then
                currentColor = KColor(0/255, 255/255, 0/255, alpha)
            elseif currentValue < 0 then
                currentColor = KColor(255/255, 0/255, 0/255, alpha)
            else
                currentColor = KColor(255/255, 255/255, 255/255, alpha)
            end
        else
            if currentValue > 1.0 then
                currentColor = KColor(0/255, 255/255, 0/255, alpha)
            elseif currentValue == 1.0 then
                currentColor = KColor(255/255, 255/255, 255/255, alpha)
            else
                currentColor = KColor(255/255, 0/255, 0/255, alpha)
            end
        end
    end

    local totalColor = nil
    if totalValue ~= nil then
        if totalMult > 1.0 then
            totalColor = KColor(100/255, 150/255, 255/255, alpha)
        elseif totalMult == 1.0 then
            totalColor = KColor(150/255, 200/255, 255/255, alpha)
        else
            totalColor = KColor(50/255, 100/255, 200/255, alpha)
        end
    end

    if currentText ~= nil then
        StatsFont:DrawString(
            currentText,
            pos.X,
            pos.Y,
            currentColor,
            0,
            true
        )
    end

    if totalValue ~= nil then
        local totalX = pos.X
        if currentText ~= nil then
            local currentTextWidth = StatsFont:GetStringWidth(currentText)
            local gap = 2
            totalX = pos.X + currentTextWidth + gap
        end

        StatsFont:DrawString(
            totalValue,
            totalX,
            pos.Y,
            totalColor,
            0,
            true
        )
    end
end

-- Render multiplier display for a player
function StatsAPI.stats.multiplierDisplay:RenderPlayer(player, renderIndex, hasBethanyParty)
    self:InitPlayer(player)
    local playerID = StatsAPI:GetPlayerInstanceKey(player)
    local data = self.playerData[playerID]

    local vanillaChanged = SyncVanillaOnlyDisplayData(player, data)
    if vanillaChanged then
        data.displayStartFrame = Game():GetFrameCount()
        data.isDisplaying = true
    end

    if not data.unifiedData or not next(data.unifiedData) then
        return
    end

    local shouldDisplay = false
    local displayType = "none"
    local currentFrame = Game():GetFrameCount()
    local tabHoldFramesRequired, normalDisplayDurationFrames, tabFadeInFrames, tabFadeOutFrames = GetHUDTimingFrames()

    local isTabPressed = Input.IsActionPressed(ButtonAction_ACTION_MAP, player.ControllerIndex or 0)
    local heldFrames = 0
    if isTabPressed then
        if data.tabPressStartFrame == nil then
            data.tabPressStartFrame = currentFrame
        end
        heldFrames = currentFrame - data.tabPressStartFrame
    else
        data.tabPressStartFrame = nil
    end
    local holdSatisfied = isTabPressed and heldFrames >= tabHoldFramesRequired

    if holdSatisfied then
        if not data.isTabDisplaying then
            data.isTabDisplaying = true
            data.tabFadeInStartFrame = currentFrame
            data.tabAlpha = 0
        elseif data.tabFadeOutStartFrame ~= nil then
            local currentAlpha = tonumber(data.tabAlpha) or 0
            data.tabFadeInStartFrame = currentFrame
            if tabFadeInFrames > 0 and currentAlpha > 0 and currentAlpha < TAB_DISPLAY_MAX_ALPHA then
                local progress = currentAlpha / TAB_DISPLAY_MAX_ALPHA
                data.tabFadeInStartFrame = currentFrame - math.floor((progress * tabFadeInFrames) + 0.5)
            end
        elseif data.tabFadeInStartFrame == nil then
            data.tabFadeInStartFrame = currentFrame
        end
        data.tabFadeOutStartFrame = nil
        data.tabFadeOutStartAlpha = nil
    elseif not isTabPressed and data.isTabDisplaying and data.tabFadeOutStartFrame == nil then
        data.tabFadeOutStartFrame = currentFrame
        local startAlpha = tonumber(data.tabAlpha)
        if type(startAlpha) ~= "number" then
            startAlpha = TAB_DISPLAY_MAX_ALPHA
        end
        if startAlpha < 0 then
            startAlpha = 0
        end
        if startAlpha > TAB_DISPLAY_MAX_ALPHA then
            startAlpha = TAB_DISPLAY_MAX_ALPHA
        end
        data.tabFadeOutStartAlpha = startAlpha
        data.tabFadeInStartFrame = nil
    end

    local tabAlpha = 0
    if data.isTabDisplaying then
        if holdSatisfied then
            if tabFadeInFrames <= 0 then
                tabAlpha = TAB_DISPLAY_MAX_ALPHA
            else
                local fadeInStart = data.tabFadeInStartFrame or currentFrame
                local fadeInPercent = (currentFrame - fadeInStart) / tabFadeInFrames
                if fadeInPercent < 0 then
                    fadeInPercent = 0
                elseif fadeInPercent > 1 then
                    fadeInPercent = 1
                end
                tabAlpha = TAB_DISPLAY_MAX_ALPHA * fadeInPercent
            end
        elseif data.tabFadeOutStartFrame ~= nil then
            local fadeOutStartAlpha = tonumber(data.tabFadeOutStartAlpha) or TAB_DISPLAY_MAX_ALPHA
            if tabFadeOutFrames <= 0 then
                tabAlpha = 0
            else
                local fadeOutElapsed = currentFrame - data.tabFadeOutStartFrame
                local fadeOutPercent = 1 - (fadeOutElapsed / tabFadeOutFrames)
                if fadeOutPercent < 0 then
                    fadeOutPercent = 0
                elseif fadeOutPercent > 1 then
                    fadeOutPercent = 1
                end
                tabAlpha = fadeOutStartAlpha * fadeOutPercent
            end
        else
            tabAlpha = TAB_DISPLAY_MAX_ALPHA
        end
    end

    if tabAlpha > 0 then
        data.tabAlpha = tabAlpha
        shouldDisplay = true
        displayType = holdSatisfied and "tab" or "tab_fade"
        if data.isDisplaying then
            data.isDisplaying = false
        end
    else
        data.tabAlpha = 0
        if data.tabFadeOutStartFrame ~= nil then
            data.isTabDisplaying = false
            data.tabFadeOutStartFrame = nil
            data.tabFadeOutStartAlpha = nil
            data.tabFadeInStartFrame = nil
        end
    end

    if not shouldDisplay and not isTabPressed and data.isDisplaying then
        local duration = currentFrame - data.displayStartFrame
        if duration < normalDisplayDurationFrames then
            shouldDisplay = true
            displayType = "normal"
        else
            data.isDisplaying = false
        end
    end

    if not shouldDisplay then
        return
    end

    if not Options.FoundHUD then
        return
    end

    local alpha = 0.5

    if displayType == "tab" or displayType == "tab_fade" then
        alpha = tonumber(data.tabAlpha) or 0
        if alpha < 0 then
            alpha = 0
        elseif alpha > TAB_DISPLAY_MAX_ALPHA then
            alpha = TAB_DISPLAY_MAX_ALPHA
        end
    else
        local duration = currentFrame - data.displayStartFrame
        local movementDuration = math.max(1, math.min(MULTIPLIER_MOVEMENT_DURATION, normalDisplayDurationFrames))
        local fadingDuration = math.max(1, math.min(MULTIPLIER_FADING_DURATION, normalDisplayDurationFrames))

        if duration <= movementDuration then
            local percent = duration / movementDuration
            alpha = 0 + (0.5 - 0) * percent
        end

        if normalDisplayDurationFrames - duration <= fadingDuration then
            local percent = (normalDisplayDurationFrames - duration) / fadingDuration
            alpha = 0 + (0.5 - 0) * percent
        end
    end

    local playerOffsetX, playerOffsetY = GetPlayerIndexDisplayOffset(player, renderIndex)

    if hasBethanyParty == nil then
        hasBethanyParty = HasBethanyInParty()
    end
    local bethanyPartyOffset = hasBethanyParty and 9 or 0
    local jacobMainOffset = IsMainPlayerJacob() and 16 or 0
    local iconOffset = GetIconDisplayOffsetY()

    -- Animation effects
    local animationOffset = 0
    if displayType == "normal" then
        local duration = currentFrame - data.displayStartFrame
        local movementDuration = math.max(1, math.min(MULTIPLIER_MOVEMENT_DURATION, normalDisplayDurationFrames))
        if duration <= movementDuration then
            local percent = duration / movementDuration
            local movementPercent = math.sin((percent * math.pi) / 2)
            animationOffset = 20 + (0 - 20) * movementPercent
        end
    elseif displayType == "tab" or displayType == "tab_fade" then
        animationOffset = 0
    end

    -- Render each stat multiplier.
    local hudRelativeOffset = GetHUDRelativeDisplayOffset()
    local screenShakeOffset = Game().ScreenShakeOffset
    local sharedStatTextOffsetX = GetSharedStatTextOffsetX(player)
    local renderMode = GetHUDDisplayMode()

    for statType, multiplierData in pairs(data.unifiedData) do
        local statPos = GetStatBasePosition(statType)
        if statPos then
            local finalX = statPos.x + BASE_STAT_OFFSET_X + playerOffsetX + sharedStatTextOffsetX + STATS_PLUS_SPACING_X - animationOffset
            local finalY = statPos.y + BASE_STAT_OFFSET_Y + playerOffsetY + bethanyPartyOffset + jacobMainOffset + iconOffset
            local pos = Vector(finalX, finalY) + hudRelativeOffset + screenShakeOffset
            local totalDisplay = GetLiveDisplayTotalMultiplier(player, statType, multiplierData.total)
            local currentDisplay, currentTypeDisplay = GetLiveDisplayCurrent(
                player,
                statType,
                multiplierData.current,
                multiplierData.currentType
            )

            RenderMultiplierStat(statType, currentDisplay, totalDisplay, currentTypeDisplay, pos, alpha, renderMode)
        end
    end
end

-- Render all players' multiplier displays
function StatsAPI.stats.multiplierDisplay:Render()
    if StatsAPI and StatsAPI.IsDisplayEnabled and not StatsAPI:IsDisplayEnabled() then
        return
    end

    local playerCount = 0
    local numPlayers = Game():GetNumPlayers()
    local hasBethanyParty = HasBethanyInParty()

    for i = 0, numPlayers - 1 do
        local player = Isaac.GetPlayer(i)
        if player then
            self:RenderPlayer(player, i, hasBethanyParty)
            playerCount = playerCount + 1
        end
    end

    if playerCount > 0 and not self.lastProcessedCount then
        StatsAPI.printDebug("Render() completed, processed " .. playerCount .. " players")
        self.lastProcessedCount = playerCount
    end
end

-- Initialize the display system (registers render callback)
function StatsAPI.stats.multiplierDisplay:Initialize()
    local modRef = StatsAPI and StatsAPI.mod or nil
    if modRef == nil then
        return
    end

    -- Re-register render callback when luamod creates a new mod instance.
    if self._renderCallbackOwner == modRef then
        return
    end

    self.initialized = true
    self._renderCallbackOwner = modRef
    StatsAPI.printDebug("Multiplier display system initialized!")

    modRef:AddCallback(ModCallbacks.MC_POST_RENDER, function()
        if StatsAPI.stats and StatsAPI.stats.multiplierDisplay then
            StatsAPI.stats.multiplierDisplay:Render()
        end
    end)
    StatsAPI.print("Render callback registered!")
end

-- Reset all multiplier data for a new game
function StatsAPI.stats.multiplierDisplay:ResetForNewGame()
    StatsAPI.printDebug("Resetting multiplier display data for new game")
    self.playerData = {}
    self.lastProcessedCount = nil
    StatsAPI.printDebug("Multiplier display data reset completed")
end

-- Force show multiplier display
function StatsAPI.stats.multiplierDisplay:ForceShow(player, duration)
    if not player then return end

    self:InitPlayer(player)
    local playerID = StatsAPI:GetPlayerInstanceKey(player)

    self.playerData[playerID].displayStartFrame = Game():GetFrameCount()
    self.playerData[playerID].isDisplaying = true

    local _, defaultDurationFrames = GetHUDTimingFrames()
    StatsAPI.printDebug("Force showing multiplier display for " .. (duration or defaultDurationFrames) .. " frames")
end

-- Legacy functions for backward compatibility (deprecated)
function StatsAPI.stats.multiplierDisplay:ShowDetailedMultipliers(player, statType, currentMult, description, itemID, updateDisplayOnly)
    StatsAPI.printDebug("ShowDetailedMultipliers is deprecated, use unifiedMultipliers:SetItemMultiplier instead")
    return false
end

function StatsAPI.stats.multiplierDisplay:SetMultiplier(player, statType, currentMult, totalMult)
    StatsAPI.printDebug("SetMultiplier is deprecated, use unifiedMultipliers:SetItemMultiplier instead")
    return false
end

function StatsAPI.stats.multiplierDisplay:StoreMultiplierData(player, statType, currentMult, totalMult)
    StatsAPI.printDebug("StoreMultiplierData is deprecated, use unifiedMultipliers:SetItemMultiplier instead")
    return false
end

function StatsAPI.stats.multiplierDisplay:ShowMultipliers(player, statType, currentMult, totalMult)
    StatsAPI.printDebug("ShowMultipliers is deprecated, use unifiedMultipliers:SetItemMultiplier instead")
    return false
end

-------------------------------------------------------------------------------
-- Stat Apply Functions
-------------------------------------------------------------------------------

-- Damage
StatsAPI.stats.damage = {}

function StatsAPI.stats.damage.applyMultiplier(player, multiplier, minDamage, showDisplay)
    if not player then
        StatsAPI.printError("Player not found in StatsAPI.stats.damage.applyMultiplier")
        return
    end

    local baseDamage = player.Damage
    local newDamage = baseDamage * multiplier

    if minDamage then
        newDamage = math.max(minDamage, newDamage)
    end

    player.Damage = newDamage

    StatsAPI.stats.damage.applyPoisonDamageMultiplier(player, multiplier)

    return newDamage
end

function StatsAPI.stats.damage.applyMultiplierScaled(player, multiplier, minDamage, showDisplay)
    if not player then
        StatsAPI.printError("Player not found in StatsAPI.stats.damage.applyMultiplierScaled")
        return
    end

    local vanillaMultiplier = 1.0
    if StatsAPI.VanillaMultipliers and StatsAPI.VanillaMultipliers.GetPlayerDamageMultiplier then
        vanillaMultiplier = StatsAPI.VanillaMultipliers:GetPlayerDamageMultiplier(player)
    end

    local scaledMultiplier = multiplier * vanillaMultiplier
    local baseDamage = player.Damage
    local newDamage = baseDamage * scaledMultiplier

    if minDamage then
        newDamage = math.max(minDamage, newDamage)
    end

    player.Damage = newDamage

    StatsAPI.stats.damage.applyPoisonDamageMultiplier(player, scaledMultiplier)

    StatsAPI.printDebug(string.format("[Damage] MultiplierScaled: %.2fx * %.2fx (vanilla) = %.2fx -> Total: %.2f",
        multiplier, vanillaMultiplier, scaledMultiplier, newDamage))

    return newDamage, scaledMultiplier
end

function StatsAPI.stats.damage.applyAddition(player, addition, minDamage)
    if not player then return end

    local baseDamage = player.Damage
    local newDamage = baseDamage + addition

    if minDamage then
        newDamage = math.max(minDamage, newDamage)
    end

    player.Damage = newDamage

    StatsAPI.stats.damage.applyPoisonDamageAddition(player, addition)

    return newDamage
end

function StatsAPI.stats.damage.applyAdditionScaled(player, addition, minDamage)
    if not player then return end

    local vanillaMultiplier = 1.0
    if StatsAPI.VanillaMultipliers and StatsAPI.VanillaMultipliers.GetPlayerDamageMultiplier then
        vanillaMultiplier = StatsAPI.VanillaMultipliers:GetPlayerDamageMultiplier(player)
    end

    local scaledAddition = addition * vanillaMultiplier
    local baseDamage = player.Damage
    local newDamage = baseDamage + scaledAddition

    if minDamage then
        newDamage = math.max(minDamage, newDamage)
    end

    player.Damage = newDamage

    StatsAPI.stats.damage.applyPoisonDamageAddition(player, scaledAddition)

    StatsAPI.printDebug(string.format("[Damage] AdditionScaled: %.2f * %.2fx (vanilla) = %.2f -> Total: %.2f",
        addition, vanillaMultiplier, scaledAddition, newDamage))

    return newDamage, scaledAddition
end

function StatsAPI.stats.damage.applyPoisonDamageMultiplier(player, multiplier)
    if not player then return end

    if not StatsAPI.stats.damage.supportsTearPoisonAPI(player) then
        return
    end

    local pdata = player:GetData()

    if not pdata.statutils_tpd_base then
        pdata.statutils_tpd_base = player:GetTearPoisonDamage()
    end

    if multiplier == 1.0 then
        pdata.statutils_tpd_base = player:GetTearPoisonDamage()
    end

    local basePoisonDamage = pdata.statutils_tpd_base or 0
    local newPoisonDamage = basePoisonDamage * multiplier

    player:SetTearPoisonDamage(newPoisonDamage)
    pdata.statutils_tpd_lastMult = multiplier

    return newPoisonDamage
end

function StatsAPI.stats.damage.applyPoisonDamageAddition(player, addition)
    if not player then return end

    if not StatsAPI.stats.damage.supportsTearPoisonAPI(player) then
        return
    end

    local pdata = player:GetData()

    if not pdata.statutils_tpd_base then
        pdata.statutils_tpd_base = player:GetTearPoisonDamage()
    end

    local basePoisonDamage = pdata.statutils_tpd_base or 0
    local newPoisonDamage = basePoisonDamage + addition

    player:SetTearPoisonDamage(newPoisonDamage)

    return newPoisonDamage
end

function StatsAPI.stats.damage.applyPoisonDamageCombined(player, multiplier, addition)
    if not player then return end
    if not StatsAPI.stats.damage.supportsTearPoisonAPI(player) then
        return
    end

    local pdata = player:GetData()

    if not pdata.statutils_tpd_base then
        pdata.statutils_tpd_base = player:GetTearPoisonDamage()
    end

    local basePoisonDamage = pdata.statutils_tpd_base or 0
    local add = type(addition) == "number" and addition or 0
    local mult = type(multiplier) == "number" and multiplier or 1.0
    local newPoisonDamage = (basePoisonDamage + add) * mult

    player:SetTearPoisonDamage(newPoisonDamage)
    pdata.statutils_tpd_lastMult = mult
    pdata.statutils_tpd_lastAdd = add

    return newPoisonDamage
end

function StatsAPI.stats.damage.supportsTearPoisonAPI(player)
    return player and type(player.GetTearPoisonDamage) == "function" and type(player.SetTearPoisonDamage) == "function"
end

-- Tears
StatsAPI.stats.tears = {}

function StatsAPI.stats.tears.calculateMaxFireDelay(baseFireDelay, multiplier, minFireDelay)
    if not baseFireDelay or not multiplier then return baseFireDelay end

    local baseSPS = 30 / (baseFireDelay + 1)
    local targetSPS = baseSPS * multiplier
    local newMaxFireDelay = (30 / targetSPS) - 1

    return newMaxFireDelay
end

function StatsAPI.stats.tears.applyMultiplier(player, multiplier, minFireDelay, showDisplay)
    if not player then return end

    local baseFireDelay = player.MaxFireDelay
    local baseSPS = 30 / (baseFireDelay + 1)
    local newFireDelay = StatsAPI.stats.tears.calculateMaxFireDelay(baseFireDelay, multiplier, nil)
    local newSPS = 30 / (newFireDelay + 1)

    StatsAPI.printDebug(string.format("[Tears] Multiplier apply: baseFD=%.4f baseSPS=%.4f mult=%.4f -> newFD=%.4f newSPS=%.4f",
        baseFireDelay, baseSPS, multiplier, newFireDelay, newSPS))

    player.MaxFireDelay = newFireDelay

    return newFireDelay
end

function StatsAPI.stats.tears.applyMultiplierScaled(player, multiplier, minFireDelay, showDisplay)
    if not player then return end

    local vanillaMultiplier = 1.0
    if StatsAPI.VanillaMultipliers and StatsAPI.VanillaMultipliers.GetPlayerFireRateMultiplier then
        vanillaMultiplier = StatsAPI.VanillaMultipliers:GetPlayerFireRateMultiplier(player)
    end

    local scaledMultiplier = multiplier * vanillaMultiplier
    local baseFireDelay = player.MaxFireDelay
    local baseSPS = 30 / (baseFireDelay + 1)
    local newFireDelay = StatsAPI.stats.tears.calculateMaxFireDelay(baseFireDelay, scaledMultiplier, nil)
    local newSPS = 30 / (newFireDelay + 1)

    StatsAPI.printDebug(string.format("[Tears] MultiplierScaled: baseFD=%.4f baseSPS=%.4f mult=%.4f * %.2fx = %.4f -> newFD=%.4f newSPS=%.4f",
        baseFireDelay, baseSPS, multiplier, vanillaMultiplier, scaledMultiplier, newFireDelay, newSPS))

    player.MaxFireDelay = newFireDelay

    return newFireDelay, scaledMultiplier
end

function StatsAPI.stats.tears.applyAddition(player, addition, minFireDelay)
    if not player then return end

    local baseFireDelay = player.MaxFireDelay
    local baseSPS = 30 / (baseFireDelay + 1)
    local targetSPS = baseSPS + addition
    local newMaxFireDelay = (30 / targetSPS) - 1
    local newSPS = 30 / (newMaxFireDelay + 1)

    StatsAPI.printDebug(string.format("[Tears] Addition apply: baseFD=%.4f baseSPS=%.4f addSPS=%+.4f -> newFD=%.4f newSPS=%.4f",
        baseFireDelay, baseSPS, addition, newMaxFireDelay, newSPS))

    player.MaxFireDelay = newMaxFireDelay

    return newMaxFireDelay
end

function StatsAPI.stats.tears.applyAdditionScaled(player, addition, minFireDelay)
    if not player then return end

    local vanillaMultiplier = 1.0
    if StatsAPI.VanillaMultipliers and StatsAPI.VanillaMultipliers.GetPlayerFireRateMultiplier then
        vanillaMultiplier = StatsAPI.VanillaMultipliers:GetPlayerFireRateMultiplier(player)
    end

    local scaledAddition = addition * vanillaMultiplier
    local baseFireDelay = player.MaxFireDelay
    local baseSPS = 30 / (baseFireDelay + 1)
    local targetSPS = baseSPS + scaledAddition
    local newMaxFireDelay = (30 / targetSPS) - 1
    local newSPS = 30 / (newMaxFireDelay + 1)

    StatsAPI.printDebug(string.format("[Tears] AdditionScaled: baseFD=%.4f baseSPS=%.4f addSPS=%+.4f * %.2fx = %+.4f -> newFD=%.4f newSPS=%.4f",
        baseFireDelay, baseSPS, addition, vanillaMultiplier, scaledAddition, newMaxFireDelay, newSPS))

    player.MaxFireDelay = newMaxFireDelay

    return newMaxFireDelay, scaledAddition
end

-- Speed
StatsAPI.stats.speed = {}

function StatsAPI.stats.speed.applyMultiplier(player, multiplier, minSpeed, showDisplay)
    if not player then return end

    local baseSpeed = player.MoveSpeed
    local newSpeed = baseSpeed * multiplier

    if minSpeed then
        newSpeed = math.max(minSpeed, newSpeed)
    end

    player.MoveSpeed = newSpeed

    return newSpeed
end

function StatsAPI.stats.speed.applyMultiplierScaled(player, multiplier, minSpeed, showDisplay)
    if not player then return end

    local vanillaMultiplier = 1.0
    local scaledMultiplier = multiplier * vanillaMultiplier
    local baseSpeed = player.MoveSpeed
    local newSpeed = baseSpeed * scaledMultiplier

    if minSpeed then
        newSpeed = math.max(minSpeed, newSpeed)
    end

    player.MoveSpeed = newSpeed

    StatsAPI.printDebug(string.format("[Speed] MultiplierScaled: %.2fx * %.2fx = %.2fx -> Total: %.2f",
        multiplier, vanillaMultiplier, scaledMultiplier, newSpeed))

    return newSpeed, scaledMultiplier
end

function StatsAPI.stats.speed.applyAddition(player, addition, minSpeed)
    if not player then return end

    local baseSpeed = player.MoveSpeed
    local newSpeed = baseSpeed + addition

    if minSpeed then
        newSpeed = math.max(minSpeed, newSpeed)
    end

    player.MoveSpeed = newSpeed

    return newSpeed
end

function StatsAPI.stats.speed.applyAdditionScaled(player, addition, minSpeed)
    if not player then return end

    local vanillaMultiplier = 1.0
    local scaledAddition = addition * vanillaMultiplier
    local baseSpeed = player.MoveSpeed
    local newSpeed = baseSpeed + scaledAddition

    if minSpeed then
        newSpeed = math.max(minSpeed, newSpeed)
    end

    player.MoveSpeed = newSpeed

    StatsAPI.printDebug(string.format("[Speed] AdditionScaled: %.2f * %.2fx = %.2f -> Total: %.2f",
        addition, vanillaMultiplier, scaledAddition, newSpeed))

    return newSpeed, scaledAddition
end

-- Range
StatsAPI.stats.range = {}

function StatsAPI.stats.range.applyMultiplier(player, multiplier, minRange, showDisplay)
    if not player then return end

    local baseRange = player.TearRange
    local newRange = baseRange * multiplier

    if minRange then
        newRange = math.max(minRange, newRange)
    end

    player.TearRange = newRange

    return newRange
end

function StatsAPI.stats.range.applyMultiplierScaled(player, multiplier, minRange, showDisplay)
    if not player then return end

    local vanillaMultiplier = 1.0
    local scaledMultiplier = multiplier * vanillaMultiplier
    local baseRange = player.TearRange
    local newRange = baseRange * scaledMultiplier

    if minRange then
        newRange = math.max(minRange, newRange)
    end

    player.TearRange = newRange

    StatsAPI.printDebug(string.format("[Range] MultiplierScaled: %.2fx * %.2fx = %.2fx -> Total: %.2f",
        multiplier, vanillaMultiplier, scaledMultiplier, newRange))

    return newRange, scaledMultiplier
end

function StatsAPI.stats.range.applyAddition(player, addition, minRange)
    if not player then return end

    local baseRange = player.TearRange
    local newRange = baseRange + addition

    if minRange then
        newRange = math.max(minRange, newRange)
    end

    player.TearRange = newRange

    return newRange
end

function StatsAPI.stats.range.applyAdditionScaled(player, addition, minRange)
    if not player then return end

    local vanillaMultiplier = 1.0
    local scaledAddition = addition * vanillaMultiplier
    local baseRange = player.TearRange
    local newRange = baseRange + scaledAddition

    if minRange then
        newRange = math.max(minRange, newRange)
    end

    player.TearRange = newRange

    StatsAPI.printDebug(string.format("[Range] AdditionScaled: %.2f * %.2fx = %.2f -> Total: %.2f",
        addition, vanillaMultiplier, scaledAddition, newRange))

    return newRange, scaledAddition
end

-- Luck
StatsAPI.stats.luck = {}

function StatsAPI.stats.luck.applyMultiplier(player, multiplier, minLuck, showDisplay)
    if not player then return end

    local baseLuck = player.Luck
    local newLuck = baseLuck

    if baseLuck == 0 then
        newLuck = 0
    else
        newLuck = baseLuck * multiplier
        if minLuck then
            newLuck = math.max(minLuck, newLuck)
        end
    end

    player.Luck = newLuck

    return newLuck
end

function StatsAPI.stats.luck.applyMultiplierScaled(player, multiplier, minLuck, showDisplay)
    if not player then return end

    local vanillaMultiplier = 1.0
    local scaledMultiplier = multiplier * vanillaMultiplier
    local baseLuck = player.Luck
    local newLuck = baseLuck

    if baseLuck == 0 then
        newLuck = 0
    else
        newLuck = baseLuck * scaledMultiplier
        if minLuck then
            newLuck = math.max(minLuck, newLuck)
        end
    end

    player.Luck = newLuck

    StatsAPI.printDebug(string.format("[Luck] MultiplierScaled: %.2fx * %.2fx = %.2fx -> Total: %.2f",
        multiplier, vanillaMultiplier, scaledMultiplier, newLuck))

    return newLuck, scaledMultiplier
end

function StatsAPI.stats.luck.applyAddition(player, addition, minLuck)
    if not player then return end

    local baseLuck = player.Luck
    local newLuck = baseLuck + addition

    if minLuck then
        newLuck = math.max(minLuck, newLuck)
    end

    player.Luck = newLuck

    return newLuck
end

function StatsAPI.stats.luck.applyAdditionScaled(player, addition, minLuck)
    if not player then return end

    local vanillaMultiplier = 1.0
    local scaledAddition = addition * vanillaMultiplier
    local baseLuck = player.Luck
    local newLuck = baseLuck + scaledAddition

    if minLuck then
        newLuck = math.max(minLuck, newLuck)
    end

    player.Luck = newLuck

    StatsAPI.printDebug(string.format("[Luck] AdditionScaled: %.2f * %.2fx = %.2f -> Total: %.2f",
        addition, vanillaMultiplier, scaledAddition, newLuck))

    return newLuck, scaledAddition
end

-- Shot Speed
StatsAPI.stats.shotSpeed = {}

function StatsAPI.stats.shotSpeed.applyMultiplier(player, multiplier, minShotSpeed, showDisplay)
    if not player then return end

    local baseShotSpeed = player.ShotSpeed
    local newShotSpeed = baseShotSpeed * multiplier

    if minShotSpeed then
        newShotSpeed = math.max(minShotSpeed, newShotSpeed)
    end

    player.ShotSpeed = newShotSpeed

    return newShotSpeed
end

function StatsAPI.stats.shotSpeed.applyMultiplierScaled(player, multiplier, minShotSpeed, showDisplay)
    if not player then return end

    local vanillaMultiplier = 1.0
    local scaledMultiplier = multiplier * vanillaMultiplier
    local baseShotSpeed = player.ShotSpeed
    local newShotSpeed = baseShotSpeed * scaledMultiplier

    if minShotSpeed then
        newShotSpeed = math.max(minShotSpeed, newShotSpeed)
    end

    player.ShotSpeed = newShotSpeed

    StatsAPI.printDebug(string.format("[ShotSpeed] MultiplierScaled: %.2fx * %.2fx = %.2fx -> Total: %.2f",
        multiplier, vanillaMultiplier, scaledMultiplier, newShotSpeed))

    return newShotSpeed, scaledMultiplier
end

function StatsAPI.stats.shotSpeed.applyAddition(player, addition, minShotSpeed)
    if not player then return end

    local baseShotSpeed = player.ShotSpeed
    local newShotSpeed = baseShotSpeed + addition

    if minShotSpeed then
        newShotSpeed = math.max(minShotSpeed, newShotSpeed)
    end

    player.ShotSpeed = newShotSpeed

    return newShotSpeed
end

function StatsAPI.stats.shotSpeed.applyAdditionScaled(player, addition, minShotSpeed)
    if not player then return end

    local vanillaMultiplier = 1.0
    local scaledAddition = addition * vanillaMultiplier
    local baseShotSpeed = player.ShotSpeed
    local newShotSpeed = baseShotSpeed + scaledAddition

    if minShotSpeed then
        newShotSpeed = math.max(minShotSpeed, newShotSpeed)
    end

    player.ShotSpeed = newShotSpeed

    StatsAPI.printDebug(string.format("[ShotSpeed] AdditionScaled: %.2f * %.2fx = %.2f -> Total: %.2f",
        addition, vanillaMultiplier, scaledAddition, newShotSpeed))

    return newShotSpeed, scaledAddition
end

-------------------------------------------------------------------------------
-- Unified Stat Apply Functions
-------------------------------------------------------------------------------
StatsAPI.stats.unified = {}

function StatsAPI.stats.unified.applyMultiplierToAll(player, multiplier, minStats, showDisplay)
    if not player then return end

    minStats = minStats or StatsAPI.stats.BASE_STATS

    StatsAPI.stats.damage.applyMultiplier(player, multiplier, minStats.damage * 0.4, showDisplay)
    StatsAPI.stats.tears.applyMultiplier(player, multiplier, nil, showDisplay)
    StatsAPI.stats.speed.applyMultiplier(player, multiplier, minStats.speed * 0.4, showDisplay)
    StatsAPI.stats.range.applyMultiplier(player, multiplier, minStats.range * 0.4, showDisplay)
    StatsAPI.stats.luck.applyMultiplier(player, multiplier, minStats.luck * 0.4, showDisplay)
    StatsAPI.stats.shotSpeed.applyMultiplier(player, multiplier, minStats.shotSpeed * 0.4, showDisplay)

    return true
end

function StatsAPI.stats.unified.applyAdditionToAll(player, addition, minStats)
    if not player then return end

    minStats = minStats or StatsAPI.stats.BASE_STATS

    StatsAPI.stats.damage.applyAddition(player, addition, minStats.damage * 0.4)
    StatsAPI.stats.tears.applyAddition(player, addition, nil)
    StatsAPI.stats.speed.applyAddition(player, addition, minStats.speed * 0.4)
    StatsAPI.stats.range.applyAddition(player, addition, minStats.range * 0.4)
    StatsAPI.stats.luck.applyAddition(player, addition, minStats.luck * 0.4)
    StatsAPI.stats.shotSpeed.applyAddition(player, addition, minStats.shotSpeed * 0.4)

    return true
end

function StatsAPI.stats.unified.updateCache(player, cacheFlag)
    if not player then return end

    if cacheFlag then
        player:AddCacheFlags(cacheFlag)
    else
        player:AddCacheFlags(CacheFlag.CACHE_ALL)
    end

    player:EvaluateItems()
end

local statModuleByType = {
    damage = StatsAPI.stats.damage,
    tears = StatsAPI.stats.tears,
    speed = StatsAPI.stats.speed,
    range = StatsAPI.stats.range,
    luck = StatsAPI.stats.luck,
    shotSpeed = StatsAPI.stats.shotSpeed
}

local methodByOperation = {
    multiplier = "applyMultiplier",
    addition = "applyAddition"
}

local function GetStatApplier(statType, operationType)
    if type(statType) ~= "string" or type(operationType) ~= "string" then
        return nil
    end

    local module = statModuleByType[statType]
    local methodName = methodByOperation[operationType]
    if type(module) ~= "table" or type(methodName) ~= "string" then
        return nil
    end

    local method = module[methodName]
    if type(method) ~= "function" then
        return nil
    end
    return method
end

-- Convenience functions
StatsAPI.stats.applyToAll = function(player, statType, multiplier, minValue, showDisplay)
    if not player or not statType then return false end
    local applyMultiplier = GetStatApplier(statType, "multiplier")
    if type(applyMultiplier) ~= "function" then
        return false
    end
    return applyMultiplier(player, multiplier, minValue, showDisplay)
end

StatsAPI.stats.addToAll = function(player, statType, addition, minValue)
    if not player or not statType then return false end
    local applyAddition = GetStatApplier(statType, "addition")
    if type(applyAddition) ~= "function" then
        return false
    end
    return applyAddition(player, addition, minValue)
end

StatsAPI.stats.getCurrentStats = function(player)
    if not player then return {} end

    return {
        damage = player.Damage,
        tears = 30 / (player.MaxFireDelay + 1),
        speed = player.MoveSpeed,
        range = player.TearRange,
        luck = player.Luck,
        shotSpeed = player.ShotSpeed
    }
end

StatsAPI.stats.getBaseStats = function()
    return StatsAPI.stats.BASE_STATS
end

local function BuildPlayerStatSnapshot(player)
    return {
        Tears = player.MaxFireDelay,
        Damage = player.Damage,
        Range = player.TearRange,
        Luck = player.Luck,
        Speed = player.MoveSpeed,
        ShotSpeed = player.ShotSpeed
    }
end

-- Apply stat multiplier to actual player stat
function StatsAPI.stats.unifiedMultipliers:ApplyStatMultiplier(player, statType, totalMultiplier)
    if not player or not statType or not totalMultiplier then return end

    StatsAPI.printDebug(string.format("Applying %s multiplier %.2fx to player", statType, totalMultiplier))

    local originalValues = BuildPlayerStatSnapshot(player)

    StatsAPI.printDebug(string.format("Original values - Tears: %.2f, Damage: %.2f, Range: %.2f, Luck: %.2f, Speed: %.2f, ShotSpeed: %.2f",
        originalValues.Tears, originalValues.Damage, originalValues.Range, originalValues.Luck, originalValues.Speed, originalValues.ShotSpeed))

    if statType == "Tears" then
        StatsAPI.stats.tears.applyMultiplier(player, totalMultiplier, nil, false)
    elseif statType == "Damage" then
        StatsAPI.stats.damage.applyMultiplier(player, totalMultiplier, 0.1, false)
    elseif statType == "Range" then
        StatsAPI.stats.range.applyMultiplier(player, totalMultiplier, 0.1, false)
    elseif statType == "Luck" then
        StatsAPI.stats.luck.applyMultiplier(player, totalMultiplier, 0.1, false)
    elseif statType == "Speed" then
        StatsAPI.stats.speed.applyMultiplier(player, totalMultiplier, 0.1, false)
    elseif statType == "ShotSpeed" then
        StatsAPI.stats.shotSpeed.applyMultiplier(player, totalMultiplier, 0.1, false)
    end

    player:AddCacheFlags(CacheFlag.CACHE_ALL)
    player:EvaluateItems()

    local newValues = BuildPlayerStatSnapshot(player)

    StatsAPI.printDebug(string.format("New values - Tears: %.2f, Damage: %.2f, Range: %.2f, Luck: %.2f, Speed: %.2f, ShotSpeed: %.2f",
        newValues.Tears, newValues.Damage, newValues.Range, newValues.Luck, newValues.Speed, newValues.ShotSpeed))

    if newValues[statType] == originalValues[statType] then
        StatsAPI.printDebug(string.format("WARNING: %s value did not change, forcing direct update", statType))

        if statType == "Tears" then
            local baseSPS = 30 / (originalValues.Tears + 1)
            local targetSPS = baseSPS * totalMultiplier
            local newFireDelay = (30 / targetSPS) - 1
            player.MaxFireDelay = newFireDelay
            StatsAPI.printDebug(string.format("Direct update: MaxFireDelay %.2f -> %.2f", originalValues.Tears, newFireDelay))
        elseif statType == "Damage" then
            local newDamage = originalValues.Damage * totalMultiplier
            player.Damage = newDamage
            StatsAPI.printDebug(string.format("Direct update: Damage %.2f -> %.2f", originalValues.Damage, newDamage))
        elseif statType == "Range" then
            local newRange = originalValues.Range * totalMultiplier
            player.TearRange = newRange
            StatsAPI.printDebug(string.format("Direct update: Range %.2f -> %.2f", originalValues.Range, newRange))
        elseif statType == "Luck" then
            local newLuck = originalValues.Luck * totalMultiplier
            player.Luck = newLuck
            StatsAPI.printDebug(string.format("Direct update: Luck %.2f -> %.2f", originalValues.Luck, newLuck))
        elseif statType == "Speed" then
            local newSpeed = originalValues.Speed * totalMultiplier
            player.MoveSpeed = newSpeed
            StatsAPI.printDebug(string.format("Direct update: Speed %.2f -> %.2f", originalValues.Speed, newSpeed))
        elseif statType == "ShotSpeed" then
            local newShotSpeed = originalValues.ShotSpeed * totalMultiplier
            player.ShotSpeed = newShotSpeed
            StatsAPI.printDebug(string.format("Direct update: ShotSpeed %.2f -> %.2f", originalValues.ShotSpeed, newShotSpeed))
        end

        player:AddCacheFlags(CacheFlag.CACHE_ALL)
        player:EvaluateItems()
    end

    StatsAPI.printDebug(string.format("Applied %s multiplier %.2fx and updated cache", statType, totalMultiplier))
end

-------------------------------------------------------------------------------
-- Centralized Cache Handler + Callback Registration
-------------------------------------------------------------------------------
do
    local CACHE_FLAG_TO_STAT = {
        [CacheFlag.CACHE_DAMAGE] = "Damage",
        [CacheFlag.CACHE_FIREDELAY] = "Tears",
        [CacheFlag.CACHE_SPEED] = "Speed",
        [CacheFlag.CACHE_RANGE] = "Range",
        [CacheFlag.CACHE_LUCK] = "Luck",
        [CacheFlag.CACHE_SHOTSPEED] = "ShotSpeed"
    }

    function StatsAPI.stats.unifiedMultipliers:OnEvaluateCache(player, cacheFlag)
        if not player or not cacheFlag then return end
        local statType = CACHE_FLAG_TO_STAT[cacheFlag]
        if not statType then return end
        self._isEvaluatingCache = true

        self:InitPlayer(player)
        local playerID = StatsAPI:GetPlayerInstanceKey(player)
        local total = 1.0
        if self[playerID]
            and self[playerID].statMultipliers
            and self[playerID].statMultipliers[statType]
            and type(self[playerID].statMultipliers[statType].totalApply) == "number" then
            total = self[playerID].statMultipliers[statType].totalApply
        end

        StatsAPI.printDebug(string.format("[Unified] Evaluating %s cache: applying pure total %.2fx", statType, total))

        if statType == "Tears" then
            StatsAPI.stats.tears.applyMultiplier(player, total, nil, false)
            local add = self[playerID] and self[playerID].statMultipliers and self[playerID].statMultipliers[statType] and (self[playerID].statMultipliers[statType].totalAdditions or 0) or 0
            if add ~= 0 then
                StatsAPI.stats.tears.applyAddition(player, add, nil)
                StatsAPI.printDebug(string.format("[Unified] Applied Tears SPS addition at cache: %+0.4f", add))
            end
        elseif statType == "Damage" then
            local add = self[playerID] and self[playerID].statMultipliers and self[playerID].statMultipliers[statType] and (self[playerID].statMultipliers[statType].totalAdditions or 0) or 0
            local baseDamage = player.Damage
            local finalDamage = (baseDamage + add) * total

            StatsAPI.printDebug(string.format("[Unified] Damage calc: (%.2f base + %.2f add) x %.2fx mult = %.2f final",
                baseDamage, add, total, finalDamage))

            player.Damage = math.max(0.1, finalDamage)
            StatsAPI.stats.damage.applyPoisonDamageCombined(player, total, add)
        elseif statType == "Range" then
            StatsAPI.stats.range.applyMultiplier(player, total, 0.1, false)
        elseif statType == "Luck" then
            StatsAPI.stats.luck.applyMultiplier(player, total, 0.1, false)
        elseif statType == "Speed" then
            StatsAPI.stats.speed.applyMultiplier(player, total, 0.1, false)
        elseif statType == "ShotSpeed" then
            StatsAPI.stats.shotSpeed.applyMultiplier(player, total, 0.1, false)
        end
        self._isEvaluatingCache = false
    end

    -- Register MC_EVALUATE_CACHE callback
    StatsAPI.mod:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, function(_, player, cacheFlag)
        if StatsAPI.stats and StatsAPI.stats.unifiedMultipliers and StatsAPI.stats.unifiedMultipliers.OnEvaluateCache then
            StatsAPI.stats.unifiedMultipliers:OnEvaluateCache(player, cacheFlag)
        end
    end)

    -- Auto-load/reset on game start
    StatsAPI.mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContinued)
        if not isContinued then
            -- New run: clear all data
            -- Keep persisted settings intact; save happens naturally on later updates/exit.
            StatsAPI:ClearRunData(true)
            if StatsAPI.stats.multiplierDisplay then
                StatsAPI.stats.multiplierDisplay:ResetForNewGame()
            end
            -- Reset unified multipliers for all known players
            StatsAPI.stats.unifiedMultipliers._justLoaded = false
            StatsAPI.printDebug("[Unified] New game: cleared all data")
        else
            -- Continue: load saved data
            StatsAPI:LoadRunData()
        end

        local numPlayers = Game():GetNumPlayers()
        for i = 0, numPlayers - 1 do
            local player = Isaac.GetPlayer(i)
            if player then
                if isContinued then
                    StatsAPI.stats.unifiedMultipliers:LoadFromSaveManager(player)
                end
                player:AddCacheFlags(CacheFlag.CACHE_ALL)
                player:EvaluateItems()
            end
        end
        StatsAPI.printDebug("[Unified] Loaded multipliers for all players on POST_GAME_STARTED")
    end)

    -- Map stat to cache flag
    local STAT_TO_CACHE_FLAG = {
        Damage = CacheFlag.CACHE_DAMAGE,
        Tears = CacheFlag.CACHE_FIREDELAY,
        Speed = CacheFlag.CACHE_SPEED,
        Range = CacheFlag.CACHE_RANGE,
        Luck = CacheFlag.CACHE_LUCK,
        ShotSpeed = CacheFlag.CACHE_SHOTSPEED
    }

    -- Queue a cache update for a specific stat to be processed next frame
    function StatsAPI.stats.unifiedMultipliers:QueueCacheUpdate(player, statType)
        if not player or not statType then return end
        self:InitPlayer(player)
        local playerID = StatsAPI:GetPlayerInstanceKey(player)
        local flag = STAT_TO_CACHE_FLAG[statType] or CacheFlag.CACHE_ALL
        self[playerID].pendingCache[flag] = true
        self._hasPending = true
        StatsAPI.printDebug(string.format("[Unified] Queued cache update for %s (flag %d)", statType, flag))
    end

    -- Flush all queued cache updates safely in POST_UPDATE
    StatsAPI.mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
        if not StatsAPI.stats or not StatsAPI.stats.unifiedMultipliers or not StatsAPI.stats.unifiedMultipliers._hasPending then
            return
        end
        local um = StatsAPI.stats.unifiedMultipliers
        local numPlayers = Game():GetNumPlayers()
        for i = 0, numPlayers - 1 do
            local player = Isaac.GetPlayer(i)
            if player then
                local playerID = StatsAPI:GetPlayerInstanceKey(player)
                if um[playerID] and um[playerID].pendingCache then
                    local combined = 0
                    local hadPending = false
                    for flag, pending in pairs(um[playerID].pendingCache) do
                        if pending then
                            hadPending = true
                            if type(flag) == "number" then
                                -- Cache flags are bit values; summing unique flags is equivalent to bitwise OR.
                                combined = combined + flag
                            else
                                combined = CacheFlag.CACHE_ALL
                            end
                        end
                    end
                    if hadPending and combined == 0 then
                        combined = CacheFlag.CACHE_ALL
                    end
                    if combined ~= 0 then
                        StatsAPI.printDebug(string.format(
                            "[Unified] Flushing pending cache for %s (mask %d)",
                            tostring(playerID),
                            combined
                        ))
                        player:AddCacheFlags(combined)
                        player:EvaluateItems()
                        if um._justLoaded then
                            player:AddCacheFlags(CacheFlag.CACHE_ALL)
                            player:EvaluateItems()
                        end
                        um[playerID].pendingCache = {}
                    end
                end
            end
        end
        um._hasPending = false
        um._justLoaded = false
    end)
end

StatsAPI.printDebug("Enhanced Stats library with unified multiplier system loaded successfully!")
