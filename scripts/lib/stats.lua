-- Stat Utils - Stats Library
-- Unified multiplier management, HUD display UI, and stat application functions
-- Standalone version (no external dependencies except Isaac API)

StatUtils.stats = {}
local REPENTANCE_PLUS = rawget(_G, "REPENTANCE_PLUS")

-- base stats
StatUtils.stats.BASE_STATS = {
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
StatUtils.stats.unifiedMultipliers = {}

local function _playerScopedSourceKey(sourceKey)
    if sourceKey == nil then
        return nil
    end
    return "__player_scope__:" .. tostring(sourceKey)
end

-- Initialize unified multiplier system for a player
function StatUtils.stats.unifiedMultipliers:InitPlayer(player)
    if not player then return end

    local playerID = StatUtils:GetPlayerInstanceKey(player)
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
        StatUtils.printDebug(string.format("Unified Multipliers: Initialized for player %s", playerID))
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

-- Add or update multiplier for a specific item and stat
function StatUtils.stats.unifiedMultipliers:SetItemMultiplier(player, itemID, statType, multiplier, description)
    if not player or not itemID or not statType or not multiplier then
        StatUtils.printError("SetItemMultiplier: Invalid parameters")
        return
    end

    self:InitPlayer(player)
    local playerID = StatUtils:GetPlayerInstanceKey(player)
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
        StatUtils.printDebug(string.format("SetItemMultiplier skipped (same frame, same active value) for %s", key))
        return
    end

    StatUtils.printDebug(string.format("SetItemMultiplier: Player %s, Item %s, Stat %s, Value %.2fx",
        playerID, tostring(itemID), statType, multiplier))

    if not self[playerID].itemMultipliers[itemID] then
        self[playerID].itemMultipliers[itemID] = {}
        StatUtils.printDebug(string.format("  Created new item entry for item %s", tostring(itemID)))
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
        StatUtils.printDebug(string.format("  Advancing sequence to %d for %s", currentSequence, key))
    else
        StatUtils.printDebug(string.format("  Sequence unchanged (%d) for %s (same value)", currentSequence, key))
    end

    self[playerID].itemMultipliers[itemID][statType] = {
        value = multiplier,
        description = description or (existing and existing.description) or "Unknown",
        sequence = currentSequence,
        lastType = "multiplier",
        disabled = existing and existing.disabled == true or false
    }

    StatUtils.printDebug(string.format("  Stored: Item %s %s = %.2fx (Sequence: %d)", tostring(itemID), statType, multiplier, self[playerID].sequenceCounter))

    StatUtils.printDebug(string.format("  Current multipliers for item %s:", tostring(itemID)))
    for stat, data in pairs(self[playerID].itemMultipliers[itemID]) do
        StatUtils.printDebug(string.format("    %s: %.2fx (%s)", stat, data.value, data.description))
    end

    self:RecalculateStatMultiplier(player, statType)
    self[playerID].lastSetFrame[key] = currentFrame
end

-- Add or update addition entry for a specific item and stat
function StatUtils.stats.unifiedMultipliers:SetItemAddition(player, itemID, statType, addition, description)
    if not player or not itemID or not statType or type(addition) ~= "number" then
        StatUtils.printError("SetItemAddition: Invalid parameters")
        return
    end

    self:InitPlayer(player)
    local playerID = StatUtils:GetPlayerInstanceKey(player)
    local currentFrame = Game():GetFrameCount()
    self[playerID].lastSetFrameAdd = self[playerID].lastSetFrameAdd or {}
    local key = tostring(itemID) .. ":" .. tostring(statType)

    if self[playerID].lastSetFrameAdd[key] == currentFrame then
        StatUtils.printDebug(string.format("SetItemAddition skipped (same frame) for %s", key))
        return
    end

    StatUtils.printDebug(string.format("SetItemAddition: Player %s, Item %s, Stat %s, Value %+0.2f",
        playerID, tostring(itemID), statType, addition))

    if not self[playerID].itemAdditions[itemID] then
        self[playerID].itemAdditions[itemID] = {}
        StatUtils.printDebug(string.format("  Created new addition entry for item %s", tostring(itemID)))
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
        isAdditiveMultiplier = false
    }

    StatUtils.printDebug(string.format("  Stored Addition: Item %s %s = %+0.2f (Cumulative: %+0.2f, Sequence: %d)",
        tostring(itemID), statType, addition, self[playerID].itemAdditions[itemID][statType].cumulative, currentSequence))

    self:RecalculateStatMultiplier(player, statType)
    self[playerID].lastSetFrameAdd[key] = currentFrame
end

-- Add or update additive-multiplier entry for a specific item and stat
function StatUtils.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, itemID, statType, multiplierValue, description)
    if not player or not itemID or not statType or type(multiplierValue) ~= "number" then
        StatUtils.printError("SetItemAdditiveMultiplier: Invalid parameters")
        return
    end

    self:InitPlayer(player)
    local playerID = StatUtils:GetPlayerInstanceKey(player)
    local currentFrame = Game():GetFrameCount()
    self[playerID].lastSetFrameAddMul = self[playerID].lastSetFrameAddMul or {}
    local key = tostring(itemID) .. ":" .. tostring(statType)

    if self[playerID].lastSetFrameAddMul[key] == currentFrame then
        local existing = self[playerID].itemAdditiveMultipliers[itemID] and self[playerID].itemAdditiveMultipliers[itemID][statType]
        local prevDelta = existing and existing.lastDelta or nil
        local newDelta = multiplierValue - 1.0
        if prevDelta and math.abs(prevDelta - newDelta) < 0.00001 then
            StatUtils.printDebug(string.format("SetItemAdditiveMultiplier skipped (same frame, same delta) for %s", key))
            return
        end
    end

    local delta = multiplierValue - 1.0
    StatUtils.printDebug(string.format("SetItemAdditiveMultiplier: Player %s, Item %s, Stat %s, Mult %.2fx (Delta %+0.2f)",
        playerID, tostring(itemID), statType, multiplierValue, delta))

    if not self[playerID].itemAdditiveMultipliers[itemID] then
        self[playerID].itemAdditiveMultipliers[itemID] = {}
        StatUtils.printDebug(string.format("  Created new additive-mult entry for item %s", tostring(itemID)))
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
    if entry.firstAddMultFrame == nil then
        entry.firstAddMultFrame = currentFrame
    end
    self[playerID].itemAdditiveMultipliers[itemID][statType] = entry

    StatUtils.printDebug(string.format("  Stored Additive Mult: Item %s %s = x%.2f (Delta %+0.2f, Seq %d)",
        tostring(itemID), statType, multiplierValue, delta, currentSequence))

    self:RecalculateStatMultiplier(player, statType)
    self[playerID].lastSetFrameAddMul[key] = currentFrame
end

-- Enable/disable multiplier entry for a specific item and stat without deleting data
function StatUtils.stats.unifiedMultipliers:SetItemMultiplierDisabled(player, itemID, statType, disabled)
    if not player or not itemID or not statType then
        return false
    end

    self:InitPlayer(player)
    local playerID = StatUtils:GetPlayerInstanceKey(player)
    local perItem = self[playerID].itemMultipliers and self[playerID].itemMultipliers[itemID]
    if not perItem or not perItem[statType] then
        return false
    end

    local entry = perItem[statType]
    local target = (disabled == true)
    if entry.disabled == target then
        return true
    end

    self[playerID].sequenceCounter = self[playerID].sequenceCounter + 1
    entry.sequence = self[playerID].sequenceCounter
    entry.disabled = target
    entry.lastType = target and "remove_mult" or "multiplier"

    self:RecalculateStatMultiplier(player, statType)
    StatUtils.printDebug(string.format(
        "Unified Multipliers: %s Item %s %s (disabled=%s)",
        target and "Disabled" or "Enabled",
        tostring(itemID),
        statType,
        tostring(target)
    ))

    return true
end

-- Player-scoped wrappers: use sourceKey instead of itemID
function StatUtils.stats.unifiedMultipliers:SetPlayerMultiplier(player, sourceKey, statType, multiplier, description)
    local scopedKey = _playerScopedSourceKey(sourceKey)
    if not scopedKey then
        return false
    end
    self:SetItemMultiplier(player, scopedKey, statType, multiplier, description)
    return true
end

function StatUtils.stats.unifiedMultipliers:SetPlayerAddition(player, sourceKey, statType, addition, description)
    local scopedKey = _playerScopedSourceKey(sourceKey)
    if not scopedKey then
        return false
    end
    self:SetItemAddition(player, scopedKey, statType, addition, description)
    return true
end

function StatUtils.stats.unifiedMultipliers:SetPlayerAdditiveMultiplier(player, sourceKey, statType, multiplierValue, description)
    local scopedKey = _playerScopedSourceKey(sourceKey)
    if not scopedKey then
        return false
    end
    self:SetItemAdditiveMultiplier(player, scopedKey, statType, multiplierValue, description)
    return true
end

function StatUtils.stats.unifiedMultipliers:SetPlayerMultiplierDisabled(player, sourceKey, statType, disabled)
    local scopedKey = _playerScopedSourceKey(sourceKey)
    if not scopedKey then
        return false
    end
    return self:SetItemMultiplierDisabled(player, scopedKey, statType, disabled)
end

function StatUtils.stats.unifiedMultipliers:RemovePlayerMultiplier(player, sourceKey, statType)
    local scopedKey = _playerScopedSourceKey(sourceKey)
    if not scopedKey then
        return false
    end
    self:RemoveItemMultiplier(player, scopedKey, statType)
    return true
end

function StatUtils.stats.unifiedMultipliers:RemovePlayerAddition(player, sourceKey, statType)
    local scopedKey = _playerScopedSourceKey(sourceKey)
    if not scopedKey then
        return false
    end
    self:RemoveItemAddition(player, scopedKey, statType)
    return true
end

-- Remove multiplier for a specific item and stat
function StatUtils.stats.unifiedMultipliers:RemoveItemMultiplier(player, itemID, statType)
    if not player or not itemID or not statType then return end

    local playerID = StatUtils:GetPlayerInstanceKey(player)
    if self[playerID] and self[playerID].itemMultipliers[itemID] then
        self[playerID].itemMultipliers[itemID][statType] = nil

        if not next(self[playerID].itemMultipliers[itemID]) then
            self[playerID].itemMultipliers[itemID] = nil
        end

        self:RecalculateStatMultiplier(player, statType)
        StatUtils.printDebug(string.format("Unified Multipliers: Removed Item %s %s", tostring(itemID), statType))
    end
end

-- Remove addition AND additive multiplier for a specific item and stat
function StatUtils.stats.unifiedMultipliers:RemoveItemAddition(player, itemID, statType)
    if not player or not itemID or not statType then return end

    local playerID = StatUtils:GetPlayerInstanceKey(player)
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
        StatUtils.printDebug(string.format("Unified Multipliers: Removed Addition/AdditiveMult Item %s %s", tostring(itemID), statType))
    end
end

-- Recalculate total multiplier for a specific stat
function StatUtils.stats.unifiedMultipliers:RecalculateStatMultiplier(player, statType)
    if not player or not statType then return end

    local playerID = StatUtils:GetPlayerInstanceKey(player)
    if not self[playerID] then return end

    local totalMultiplierApply = 1.0
    local totalAdditionApply = 0.0
    local totalMultiplierDisplay = 1.0
    local lastItemCurrentVal = 1.0
    local lastItemID = nil
    local lastDescription = ""
    local lastSequence = 0
    local lastType = "multiplier"

    StatUtils.printDebug(string.format("Recalculating %s for player %s:", statType, playerID))

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

    -- Aggregate per item
    for itemID, _ in pairs(touched) do
        local baseM, baseSeq, baseDesc, baseType = 1.0, 0, "", "multiplier"
        if self[playerID].itemMultipliers[itemID] and self[playerID].itemMultipliers[itemID][statType] then
            local baseEntry = self[playerID].itemMultipliers[itemID][statType]
            if not (baseEntry.disabled == true) then
                baseM = baseEntry.value or 1.0
            end
            baseSeq = baseEntry.sequence or 0
            baseDesc = baseEntry.description or ""
            baseType = baseEntry.lastType or "multiplier"
        end

        local addCum, addSeq, addLastDelta, addDesc = 0, 0, 0, ""
        if self[playerID].itemAdditions and self[playerID].itemAdditions[itemID] and self[playerID].itemAdditions[itemID][statType] then
            local ad = self[playerID].itemAdditions[itemID][statType]
            addCum = ad.cumulative or 0
            addLastDelta = ad.lastDelta or 0
            addSeq = ad.sequence or 0
            addDesc = ad.description or ""
        end

        local addMulDelta = 0.0
        local addMulSeq = 0
        local addMulLastDelta = 0
        local addMulDesc = ""
        local hasAddMul = false
        if self[playerID].itemAdditiveMultipliers and self[playerID].itemAdditiveMultipliers[itemID] and self[playerID].itemAdditiveMultipliers[itemID][statType] then
            local am = self[playerID].itemAdditiveMultipliers[itemID][statType]
            addMulDelta = am.cumulative or 0
            addMulLastDelta = am.lastDelta or 0
            addMulSeq = am.sequence or 0
            addMulDesc = am.description or ""
            hasAddMul = true
        end

        local effectiveM = (baseM or 1.0) + (addMulDelta or 0.0)
        if effectiveM <= 0 then effectiveM = 0 end
        totalMultiplierApply = totalMultiplierApply * effectiveM
        totalAdditionApply = totalAdditionApply + addCum

        local latestSeq = math.max(baseSeq, addSeq, addMulSeq)

        if latestSeq > lastSequence then
            if addMulSeq == latestSeq and hasAddMul then
                local am = self[playerID].itemAdditiveMultipliers[itemID][statType]
                local isFirstMultiplier = math.abs((am.cumulative or 0) - (am.lastDelta or 0)) < 0.00001
                if isFirstMultiplier then
                    lastItemCurrentVal = 1.0 + (addMulLastDelta or 0)
                    lastType = "multiplier"
                    StatUtils.printDebug(string.format("  First additive mult for item %s %s: x%.2f", tostring(itemID), statType, lastItemCurrentVal))
                else
                    lastItemCurrentVal = addMulLastDelta
                    lastType = "add_mult"
                    StatUtils.printDebug(string.format("  Subsequent additive mult for item %s %s: %+.2f (cumulative=%.2f)",
                        tostring(itemID), statType, lastItemCurrentVal, am.cumulative or 0))
                end
                lastItemID = itemID
                lastDescription = addMulDesc
                lastSequence = addMulSeq
            elseif addSeq == latestSeq and addSeq > 0 then
                lastItemCurrentVal = addLastDelta
                lastType = "addition"
                lastItemID = itemID
                lastDescription = addDesc
                lastSequence = addSeq
            elseif baseSeq == latestSeq then
                lastItemCurrentVal = baseM
                lastItemID = itemID
                lastDescription = baseDesc
                lastSequence = baseSeq
                lastType = baseType
            end
            StatUtils.printDebug(string.format("  Item %s: base=%.2f, addMulDelta=%+0.2f, eff=%.2f, addCum=%+0.2f", tostring(itemID), baseM, addMulDelta, effectiveM, addCum))
        end
    end

    local computedTotalApply = totalMultiplierApply
    totalMultiplierDisplay = computedTotalApply

    if not self[playerID].statMultipliers then
        self[playerID].statMultipliers = {}
    end

    self[playerID].statMultipliers[statType] = {
        current = lastItemCurrentVal,
        total = totalMultiplierDisplay,
        totalApply = computedTotalApply,
        totalAdditions = totalAdditionApply,
        lastItemID = lastItemID,
        description = lastDescription,
        sequence = lastSequence,
        currentType = lastType
    }

    if lastType == "addition" then
        StatUtils.printDebug(string.format("Unified Multipliers: %s recalculated - Current: %+0.2f (from %s, seq: %d), Total: %.2fx (display), Apply: %.2fx",
            statType, lastItemCurrentVal, tostring(lastItemID), lastSequence, totalMultiplierDisplay, computedTotalApply))
    else
        StatUtils.printDebug(string.format("Unified Multipliers: %s recalculated - Current: %.2fx (from %s, seq: %d), Total: %.2fx (display), Apply: %.2fx",
            statType, lastItemCurrentVal, tostring(lastItemID), lastSequence, totalMultiplierDisplay, computedTotalApply))
    end

    if StatUtils.stats.multiplierDisplay then
        StatUtils.stats.multiplierDisplay:UpdateFromUnifiedSystem(player, statType, lastItemCurrentVal, totalMultiplierDisplay, lastType)
    end

    if not self._isEvaluatingCache then
        self:QueueCacheUpdate(player, statType)
    end
end

-- Get current and total multipliers for a stat
function StatUtils.stats.unifiedMultipliers:GetMultipliers(player, statType)
    if not player or not statType then return 1.0, 1.0 end

    local playerID = StatUtils:GetPlayerInstanceKey(player)
    if not self[playerID] or not self[playerID].statMultipliers[statType] then
        return 1.0, 1.0
    end

    local data = self[playerID].statMultipliers[statType]
    return data.current, data.total
end

-- Get all multipliers for a player
function StatUtils.stats.unifiedMultipliers:GetAllMultipliers(player)
    if not player then return {} end

    local playerID = StatUtils:GetPlayerInstanceKey(player)
    if not self[playerID] or not self[playerID].statMultipliers then
        return {}
    end

    return self[playerID].statMultipliers
end

-- Reset all multipliers for a player (for new game)
function StatUtils.stats.unifiedMultipliers:ResetPlayer(player)
    if not player then return end

    local playerID = StatUtils:GetPlayerInstanceKey(player)
    self[playerID] = nil

    StatUtils.printDebug(string.format("Unified Multipliers: Reset for player %s", playerID))
end

-- Save multipliers (uses StatUtils built-in save system)
function StatUtils.stats.unifiedMultipliers:SaveToSaveManager(player)
    if not player then return end

    local playerID = StatUtils:GetPlayerInstanceKey(player)
    if not self[playerID] then return end

    local playerSave = StatUtils:GetPlayerRunData(player)

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
                        eqMult = data.eqMult
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
                        firstAddMultFrame = data.firstAddMultFrame
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
        StatUtils.printDebug(string.format("Unified Multipliers: Saved for player %s (mults:%d, adds:%d, addMults:%d)",
            playerID, multCount, addCount, addMultCount))
    end
end

-- Load multipliers (uses StatUtils built-in save system)
function StatUtils.stats.unifiedMultipliers:LoadFromSaveManager(player)
    if not player then return end

    local playerID = StatUtils:GetPlayerInstanceKey(player)
    local playerSave = StatUtils:GetPlayerRunData(player)

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
        StatUtils.printDebug(string.format("Unified Multipliers: Loaded for player %s (mults:%d, adds:%d, addMults:%d)",
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
            StatUtils.printDebug(string.format("[Unified] Recalculated %s after loading", statType))
        end

        self._justLoaded = true
    end
end

-------------------------------------------------------------------------------
-- Multiplier Display System (HUD overlay)
-------------------------------------------------------------------------------
StatUtils.stats.multiplierDisplay = {}

local StatsFont = Font()
StatsFont:Load("font/luaminioutlined.fnt")
StatUtils.printDebug("Using Isaac default font for multiplier display")

local ButtonAction_ACTION_MAP = ButtonAction.ACTION_MAP

-- Display settings
local MULTIPLIER_DISPLAY_DURATION = 150
local MULTIPLIER_MOVEMENT_DURATION = 10
local MULTIPLIER_FADING_DURATION = 40

-- Tab button display settings
local TAB_DISPLAY_DURATION = 10
local TAB_DISPLAY_FADE_DURATION = 20

-- HUD positions for each stat
local STAT_POSITIONS = {
    Speed = {x = 75, y = 87},
    Tears = {x = 75, y = 99},
    Damage = {x = 75, y = 111},
    Range = {x = 75, y = 123},
    ShotSpeed = {x = 75, y = 135},
    Luck = {x = 75, y = 147}
}

if REPENTANCE_PLUS then
    STAT_POSITIONS.Speed.y = 90
    STAT_POSITIONS.Tears.y = 102
    STAT_POSITIONS.Damage.y = 114
    STAT_POSITIONS.Range.y = 126
    STAT_POSITIONS.ShotSpeed.y = 138
    STAT_POSITIONS.Luck.y = 150
end

StatUtils.stats.multiplierDisplay.playerData = {}

function StatUtils.stats.multiplierDisplay:InitPlayer(player)
    local playerID = StatUtils:GetPlayerInstanceKey(player)
    if not self.playerData[playerID] then
        StatUtils.printDebug(string.format("InitPlayer: Creating new player data for player ID %s", playerID))
        self.playerData[playerID] = {
            displayStartFrame = 0,
            isDisplaying = false,
            tabDisplayStartFrame = 0,
            isTabDisplaying = false,
            lastDebugState = nil,
            lastDisplayLogicState = nil,
            lastDisplayState = nil,
            lastTabState = nil
        }
    end
end

function StatUtils.stats.multiplierDisplay:UpdateFromUnifiedSystem(player, statType, currentValue, totalMult, currentType)
    if not player or not statType then return end

    self:InitPlayer(player)
    local playerID = StatUtils:GetPlayerInstanceKey(player)

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
        StatUtils.printDebug(string.format("Multiplier Display Updated: %s - Current: %+0.2f, Total: %.2fx (addition)",
            statType, currentValue, totalMult))
    else
        StatUtils.printDebug(string.format("Multiplier Display Updated: %s - Current: %.2fx, Total: %.2fx",
            statType, currentValue, totalMult))
    end

    StatUtils.printDebug(string.format("  Current unified data for player %s:", playerID))
    for stat, data in pairs(self.playerData[playerID].unifiedData) do
        if data.currentType == "addition" then
            StatUtils.printDebug(string.format("    %s: Current=%+0.2f, Total=%.2fx", stat, data.current, data.total))
        else
            StatUtils.printDebug(string.format("    %s: Current=%.2fx, Total=%.2fx", stat, data.current, data.total))
        end
    end
end

function StatUtils.stats.multiplierDisplay:ForceDisplay(player, statType, currentValue, totalMult, currentType)
    if not player or not statType then return end
    self:InitPlayer(player)
    local playerID = StatUtils:GetPlayerInstanceKey(player)
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

function StatUtils.stats.multiplierDisplay:RefreshFromUnified(player)
    if not player or not StatUtils.stats or not StatUtils.stats.unifiedMultipliers then
        return false
    end

    self:InitPlayer(player)
    local playerID = StatUtils:GetPlayerInstanceKey(player)
    local all = StatUtils.stats.unifiedMultipliers:GetAllMultipliers(player)
    local hasAny = false

    self.playerData[playerID].unifiedData = {}

    for statType, data in pairs(all) do
        local currentType = data.currentType or "multiplier"
        if currentType ~= "addition" then
            local current = type(data.current) == "number" and data.current or 1.0
            local total = type(data.total) == "number" and data.total or 1.0
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

function StatUtils.stats.multiplierDisplay:RefreshAllFromUnified()
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
    if StatUtils and type(StatUtils.GetDisplayOffsets) == "function" then
        customX, customY = StatUtils:GetDisplayOffsets()
    elseif StatUtils and type(StatUtils.settings) == "table" then
        customX = tonumber(StatUtils.settings.displayOffsetX) or 0
        customY = tonumber(StatUtils.settings.displayOffsetY) or 0
    end

    local customOffset = Vector(customX, customY)
    return vanillaHUDOffset + customOffset
end

-- Render a single multiplier stat
local function RenderMultiplierStat(statType, currentValue, totalMult, currentType, pos, alpha)
    if type(currentValue) ~= "number" or type(totalMult) ~= "number" then
        StatUtils.printError(string.format("RenderMultiplierStat: currentValue and totalMult must be numbers, got %s and %s",
            type(currentValue), type(totalMult)))
        return
    end

    local currentText
    if currentType == "addition" then
        return
    elseif currentType == "add_mult" or currentType == "remove_mult" then
        currentText = string.format("%+0.2f", currentValue)
    else
        currentText = string.format("x%.2f", currentValue)
    end
    local totalValue = nil
    if currentType ~= "addition" then
        totalValue = string.format("/x%.2f", totalMult)
    end

    pos = pos + Game().ScreenShakeOffset

    local currentColor
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

    local totalColor
    if totalValue ~= nil then
        if totalMult > 1.0 then
            totalColor = KColor(100/255, 150/255, 255/255, alpha)
        elseif totalMult == 1.0 then
            totalColor = KColor(150/255, 200/255, 255/255, alpha)
        else
            totalColor = KColor(50/255, 100/255, 200/255, alpha)
        end
    end

    StatsFont:DrawString(
        currentText,
        pos.X,
        pos.Y,
        currentColor,
        0,
        true
    )

    if totalValue ~= nil then
        local currentTextWidth = StatsFont:GetStringWidth(currentText)
        local gap = 2
        local totalX = pos.X + currentTextWidth + gap

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
function StatUtils.stats.multiplierDisplay:RenderPlayer(player)
    local playerID = StatUtils:GetPlayerInstanceKey(player)

    if not self.playerData[playerID] then return end

    local data = self.playerData[playerID]

    if not data.unifiedData or not next(data.unifiedData) then
        return
    end

    local shouldDisplay = false
    local displayType = "none"
    local currentFrame = Game():GetFrameCount()

    local isTabPressed = Input.IsActionPressed(ButtonAction_ACTION_MAP, player.ControllerIndex or 0)

    if isTabPressed then
        if not data.isTabDisplaying then
            data.isTabDisplaying = true
            data.tabDisplayStartFrame = currentFrame
        end
        shouldDisplay = true
        displayType = "tab"
    else
        if data.isTabDisplaying then
            local tabDuration = currentFrame - data.tabDisplayStartFrame
            local totalTabDuration = TAB_DISPLAY_DURATION + TAB_DISPLAY_FADE_DURATION

            if tabDuration < totalTabDuration then
                shouldDisplay = true
                displayType = "tab_fade"
            else
                data.isTabDisplaying = false
            end
        end

        if not shouldDisplay and data.isDisplaying then
            local duration = currentFrame - data.displayStartFrame
            if duration < MULTIPLIER_DISPLAY_DURATION then
                shouldDisplay = true
                displayType = "normal"
            else
                data.isDisplaying = false
            end
        end
    end

    if not shouldDisplay then
        return
    end

    if not Options.FoundHUD then
        return
    end

    local alpha = 0.5

    if displayType == "tab" then
        alpha = 0.8
    elseif displayType == "tab_fade" then
        local tabDuration = currentFrame - data.tabDisplayStartFrame
        local fadeStart = TAB_DISPLAY_DURATION
        local fadeEnd = fadeStart + TAB_DISPLAY_FADE_DURATION

        if tabDuration <= fadeStart then
            alpha = 0.8
        elseif tabDuration <= fadeEnd then
            local fadePercent = (fadeEnd - tabDuration) / TAB_DISPLAY_FADE_DURATION
            alpha = 0.8 * fadePercent
        else
            alpha = 0
        end

        if data.isDisplaying then
            data.isDisplaying = false
        end
    else
        local duration = currentFrame - data.displayStartFrame

        local animationOffset = 0
        if duration <= MULTIPLIER_MOVEMENT_DURATION then
            local percent = duration / MULTIPLIER_MOVEMENT_DURATION
            local movementPercent = math.sin((percent * math.pi) / 2)

            animationOffset = 20 + (0 - 20) * movementPercent
            alpha = 0 + (0.5 - 0) * percent
        end

        if MULTIPLIER_DISPLAY_DURATION - duration <= MULTIPLIER_FADING_DURATION then
            local percent = (MULTIPLIER_DISPLAY_DURATION - duration) / MULTIPLIER_FADING_DURATION
            alpha = 0 + (0.5 - 0) * percent
        end
    end

    -- Multiplayer adjustments
    local multiplayerOffset = 0
    if Game():GetNumPlayers() > 1 then
        if player:GetPlayerType() == PlayerType.PLAYER_ISAAC then
            multiplayerOffset = -4
        else
            multiplayerOffset = 4
        end
    end

    -- Challenge mode adjustments
    local challengeOffset = 0
    if Game().Challenge == Challenge.CHALLENGE_NULL
    and Game().Difficulty == Difficulty.DIFFICULTY_NORMAL then
        challengeOffset = -15.5
    end

    -- Character-specific adjustments
    local characterOffset = 0
    if player:GetPlayerType() == PlayerType.PLAYER_BETHANY then
        characterOffset = 10
    elseif player:GetPlayerType() == PlayerType.PLAYER_BETHANY_B then
        characterOffset = 10
    elseif player:GetPlayerType() == PlayerType.PLAYER_BLUEBABY_B then
        characterOffset = 10
    end

    if player:GetPlayerType() == PlayerType.PLAYER_JACOB or player:GetPlayerType() == PlayerType.PLAYER_ESAU then
        characterOffset = characterOffset + 16
    end

    -- Animation effects
    local animationOffset = 0
    if displayType == "normal" then
        local duration = currentFrame - data.displayStartFrame
        if duration <= MULTIPLIER_MOVEMENT_DURATION then
            local percent = duration / MULTIPLIER_MOVEMENT_DURATION
            local movementPercent = math.sin((percent * math.pi) / 2)
            animationOffset = 20 + (0 - 20) * movementPercent
        end
    elseif displayType == "tab" or displayType == "tab_fade" then
        animationOffset = 0
    end

    -- Render each stat multiplier
    local renderedCount = 0
    -- Keep the overlay anchored to Isaac HUD offset, then apply user X/Y tweak from MCM.
    local hudRelativeOffset = GetHUDRelativeDisplayOffset()

    for statType, multiplierData in pairs(data.unifiedData) do
        local statPos = STAT_POSITIONS[statType]
        if statPos then
            local finalX = statPos.x - animationOffset
            local finalY = statPos.y + multiplayerOffset + challengeOffset + characterOffset
            local pos = Vector(finalX, finalY) + hudRelativeOffset

            RenderMultiplierStat(statType, multiplierData.current, multiplierData.total, multiplierData.currentType, pos, alpha)
            renderedCount = renderedCount + 1
        end
    end
end

-- Render all players' multiplier displays
function StatUtils.stats.multiplierDisplay:Render()
    if StatUtils and StatUtils.IsDisplayEnabled and not StatUtils:IsDisplayEnabled() then
        return
    end

    local playerCount = 0
    local numPlayers = Game():GetNumPlayers()

    for i = 0, numPlayers - 1 do
        local player = Isaac.GetPlayer(i)
        if player then
            self:RenderPlayer(player)
            playerCount = playerCount + 1
        end
    end

    if playerCount > 0 and not self.lastProcessedCount then
        StatUtils.printDebug("Render() completed, processed " .. playerCount .. " players")
        self.lastProcessedCount = playerCount
    end
end

-- Initialize the display system (registers render callback)
function StatUtils.stats.multiplierDisplay:Initialize()
    if not self.initialized then
        self.initialized = true
        StatUtils.printDebug("Multiplier display system initialized!")

        StatUtils.mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
            if StatUtils.stats and StatUtils.stats.multiplierDisplay then
                StatUtils.stats.multiplierDisplay:Render()
            end
        end)
        StatUtils.print("Render callback registered!")
    end
end

-- Reset all multiplier data for a new game
function StatUtils.stats.multiplierDisplay:ResetForNewGame()
    StatUtils.printDebug("Resetting multiplier display data for new game")
    self.playerData = {}
    self.lastProcessedCount = nil
    StatUtils.printDebug("Multiplier display data reset completed")
end

-- Force show multiplier display
function StatUtils.stats.multiplierDisplay:ForceShow(player, duration)
    if not player then return end

    self:InitPlayer(player)
    local playerID = StatUtils:GetPlayerInstanceKey(player)

    self.playerData[playerID].displayStartFrame = Game():GetFrameCount()
    self.playerData[playerID].isDisplaying = true

    StatUtils.printDebug("Force showing multiplier display for " .. (duration or MULTIPLIER_DISPLAY_DURATION) .. " frames")
end

-- Legacy functions for backward compatibility (deprecated)
function StatUtils.stats.multiplierDisplay:ShowDetailedMultipliers(player, statType, currentMult, description, itemID, updateDisplayOnly)
    StatUtils.printDebug("ShowDetailedMultipliers is deprecated, use unifiedMultipliers:SetItemMultiplier instead")
    return false
end

function StatUtils.stats.multiplierDisplay:SetMultiplier(player, statType, currentMult, totalMult)
    StatUtils.printDebug("SetMultiplier is deprecated, use unifiedMultipliers:SetItemMultiplier instead")
    return false
end

function StatUtils.stats.multiplierDisplay:StoreMultiplierData(player, statType, currentMult, totalMult)
    StatUtils.printDebug("StoreMultiplierData is deprecated, use unifiedMultipliers:SetItemMultiplier instead")
    return false
end

function StatUtils.stats.multiplierDisplay:ShowMultipliers(player, statType, currentMult, totalMult)
    StatUtils.printDebug("ShowMultipliers is deprecated, use unifiedMultipliers:SetItemMultiplier instead")
    return false
end

-------------------------------------------------------------------------------
-- Stat Apply Functions
-------------------------------------------------------------------------------

-- Damage
StatUtils.stats.damage = {}

function StatUtils.stats.damage.applyMultiplier(player, multiplier, minDamage, showDisplay)
    if not player then
        StatUtils.printError("Player not found in StatUtils.stats.damage.applyMultiplier")
        return
    end

    local baseDamage = player.Damage
    local newDamage = baseDamage * multiplier

    if minDamage then
        newDamage = math.max(minDamage, newDamage)
    end

    player.Damage = newDamage

    StatUtils.stats.damage.applyPoisonDamageMultiplier(player, multiplier)

    return newDamage
end

function StatUtils.stats.damage.applyMultiplierScaled(player, multiplier, minDamage, showDisplay)
    if not player then
        StatUtils.printError("Player not found in StatUtils.stats.damage.applyMultiplierScaled")
        return
    end

    local vanillaMultiplier = 1.0
    if StatUtils.VanillaMultipliers and StatUtils.VanillaMultipliers.GetPlayerDamageMultiplier then
        vanillaMultiplier = StatUtils.VanillaMultipliers:GetPlayerDamageMultiplier(player)
    end

    local scaledMultiplier = multiplier * vanillaMultiplier
    local baseDamage = player.Damage
    local newDamage = baseDamage * scaledMultiplier

    if minDamage then
        newDamage = math.max(minDamage, newDamage)
    end

    player.Damage = newDamage

    StatUtils.stats.damage.applyPoisonDamageMultiplier(player, scaledMultiplier)

    StatUtils.printDebug(string.format("[Damage] MultiplierScaled: %.2fx * %.2fx (vanilla) = %.2fx -> Total: %.2f",
        multiplier, vanillaMultiplier, scaledMultiplier, newDamage))

    return newDamage, scaledMultiplier
end

function StatUtils.stats.damage.applyAddition(player, addition, minDamage)
    if not player then return end

    local baseDamage = player.Damage
    local newDamage = baseDamage + addition

    if minDamage then
        newDamage = math.max(minDamage, newDamage)
    end

    player.Damage = newDamage

    StatUtils.stats.damage.applyPoisonDamageAddition(player, addition)

    return newDamage
end

function StatUtils.stats.damage.applyAdditionScaled(player, addition, minDamage)
    if not player then return end

    local vanillaMultiplier = 1.0
    if StatUtils.VanillaMultipliers and StatUtils.VanillaMultipliers.GetPlayerDamageMultiplier then
        vanillaMultiplier = StatUtils.VanillaMultipliers:GetPlayerDamageMultiplier(player)
    end

    local scaledAddition = addition * vanillaMultiplier
    local baseDamage = player.Damage
    local newDamage = baseDamage + scaledAddition

    if minDamage then
        newDamage = math.max(minDamage, newDamage)
    end

    player.Damage = newDamage

    StatUtils.stats.damage.applyPoisonDamageAddition(player, scaledAddition)

    StatUtils.printDebug(string.format("[Damage] AdditionScaled: %.2f * %.2fx (vanilla) = %.2f -> Total: %.2f",
        addition, vanillaMultiplier, scaledAddition, newDamage))

    return newDamage, scaledAddition
end

function StatUtils.stats.damage.applyPoisonDamageMultiplier(player, multiplier)
    if not player then return end

    if not StatUtils.stats.damage.supportsTearPoisonAPI(player) then
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

function StatUtils.stats.damage.applyPoisonDamageAddition(player, addition)
    if not player then return end

    if not StatUtils.stats.damage.supportsTearPoisonAPI(player) then
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

function StatUtils.stats.damage.applyPoisonDamageCombined(player, multiplier, addition)
    if not player then return end
    if not StatUtils.stats.damage.supportsTearPoisonAPI(player) then
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

function StatUtils.stats.damage.supportsTearPoisonAPI(player)
    return player and type(player.GetTearPoisonDamage) == "function" and type(player.SetTearPoisonDamage) == "function"
end

-- Tears
StatUtils.stats.tears = {}

function StatUtils.stats.tears.calculateMaxFireDelay(baseFireDelay, multiplier, minFireDelay)
    if not baseFireDelay or not multiplier then return baseFireDelay end

    local baseSPS = 30 / (baseFireDelay + 1)
    local targetSPS = baseSPS * multiplier
    local newMaxFireDelay = (30 / targetSPS) - 1

    return newMaxFireDelay
end

function StatUtils.stats.tears.applyMultiplier(player, multiplier, minFireDelay, showDisplay)
    if not player then return end

    local baseFireDelay = player.MaxFireDelay
    local baseSPS = 30 / (baseFireDelay + 1)
    local newFireDelay = StatUtils.stats.tears.calculateMaxFireDelay(baseFireDelay, multiplier, nil)
    local newSPS = 30 / (newFireDelay + 1)

    StatUtils.printDebug(string.format("[Tears] Multiplier apply: baseFD=%.4f baseSPS=%.4f mult=%.4f -> newFD=%.4f newSPS=%.4f",
        baseFireDelay, baseSPS, multiplier, newFireDelay, newSPS))

    player.MaxFireDelay = newFireDelay

    return newFireDelay
end

function StatUtils.stats.tears.applyMultiplierScaled(player, multiplier, minFireDelay, showDisplay)
    if not player then return end

    local vanillaMultiplier = 1.0
    if StatUtils.VanillaMultipliers and StatUtils.VanillaMultipliers.GetPlayerFireRateMultiplier then
        vanillaMultiplier = StatUtils.VanillaMultipliers:GetPlayerFireRateMultiplier(player)
    end

    local scaledMultiplier = multiplier * vanillaMultiplier
    local baseFireDelay = player.MaxFireDelay
    local baseSPS = 30 / (baseFireDelay + 1)
    local newFireDelay = StatUtils.stats.tears.calculateMaxFireDelay(baseFireDelay, scaledMultiplier, nil)
    local newSPS = 30 / (newFireDelay + 1)

    StatUtils.printDebug(string.format("[Tears] MultiplierScaled: baseFD=%.4f baseSPS=%.4f mult=%.4f * %.2fx = %.4f -> newFD=%.4f newSPS=%.4f",
        baseFireDelay, baseSPS, multiplier, vanillaMultiplier, scaledMultiplier, newFireDelay, newSPS))

    player.MaxFireDelay = newFireDelay

    return newFireDelay, scaledMultiplier
end

function StatUtils.stats.tears.applyAddition(player, addition, minFireDelay)
    if not player then return end

    local baseFireDelay = player.MaxFireDelay
    local baseSPS = 30 / (baseFireDelay + 1)
    local targetSPS = baseSPS + addition
    local newMaxFireDelay = (30 / targetSPS) - 1
    local newSPS = 30 / (newMaxFireDelay + 1)

    StatUtils.printDebug(string.format("[Tears] Addition apply: baseFD=%.4f baseSPS=%.4f addSPS=%+.4f -> newFD=%.4f newSPS=%.4f",
        baseFireDelay, baseSPS, addition, newMaxFireDelay, newSPS))

    player.MaxFireDelay = newMaxFireDelay

    return newMaxFireDelay
end

function StatUtils.stats.tears.applyAdditionScaled(player, addition, minFireDelay)
    if not player then return end

    local vanillaMultiplier = 1.0
    if StatUtils.VanillaMultipliers and StatUtils.VanillaMultipliers.GetPlayerFireRateMultiplier then
        vanillaMultiplier = StatUtils.VanillaMultipliers:GetPlayerFireRateMultiplier(player)
    end

    local scaledAddition = addition * vanillaMultiplier
    local baseFireDelay = player.MaxFireDelay
    local baseSPS = 30 / (baseFireDelay + 1)
    local targetSPS = baseSPS + scaledAddition
    local newMaxFireDelay = (30 / targetSPS) - 1
    local newSPS = 30 / (newMaxFireDelay + 1)

    StatUtils.printDebug(string.format("[Tears] AdditionScaled: baseFD=%.4f baseSPS=%.4f addSPS=%+.4f * %.2fx = %+.4f -> newFD=%.4f newSPS=%.4f",
        baseFireDelay, baseSPS, addition, vanillaMultiplier, scaledAddition, newMaxFireDelay, newSPS))

    player.MaxFireDelay = newMaxFireDelay

    return newMaxFireDelay, scaledAddition
end

-- Speed
StatUtils.stats.speed = {}

function StatUtils.stats.speed.applyMultiplier(player, multiplier, minSpeed, showDisplay)
    if not player then return end

    local baseSpeed = player.MoveSpeed
    local newSpeed = baseSpeed * multiplier

    if minSpeed then
        newSpeed = math.max(minSpeed, newSpeed)
    end

    player.MoveSpeed = newSpeed

    return newSpeed
end

function StatUtils.stats.speed.applyMultiplierScaled(player, multiplier, minSpeed, showDisplay)
    if not player then return end

    local vanillaMultiplier = 1.0
    local scaledMultiplier = multiplier * vanillaMultiplier
    local baseSpeed = player.MoveSpeed
    local newSpeed = baseSpeed * scaledMultiplier

    if minSpeed then
        newSpeed = math.max(minSpeed, newSpeed)
    end

    player.MoveSpeed = newSpeed

    StatUtils.printDebug(string.format("[Speed] MultiplierScaled: %.2fx * %.2fx = %.2fx -> Total: %.2f",
        multiplier, vanillaMultiplier, scaledMultiplier, newSpeed))

    return newSpeed, scaledMultiplier
end

function StatUtils.stats.speed.applyAddition(player, addition, minSpeed)
    if not player then return end

    local baseSpeed = player.MoveSpeed
    local newSpeed = baseSpeed + addition

    if minSpeed then
        newSpeed = math.max(minSpeed, newSpeed)
    end

    player.MoveSpeed = newSpeed

    return newSpeed
end

function StatUtils.stats.speed.applyAdditionScaled(player, addition, minSpeed)
    if not player then return end

    local vanillaMultiplier = 1.0
    local scaledAddition = addition * vanillaMultiplier
    local baseSpeed = player.MoveSpeed
    local newSpeed = baseSpeed + scaledAddition

    if minSpeed then
        newSpeed = math.max(minSpeed, newSpeed)
    end

    player.MoveSpeed = newSpeed

    StatUtils.printDebug(string.format("[Speed] AdditionScaled: %.2f * %.2fx = %.2f -> Total: %.2f",
        addition, vanillaMultiplier, scaledAddition, newSpeed))

    return newSpeed, scaledAddition
end

-- Range
StatUtils.stats.range = {}

function StatUtils.stats.range.applyMultiplier(player, multiplier, minRange, showDisplay)
    if not player then return end

    local baseRange = player.TearRange
    local newRange = baseRange * multiplier

    if minRange then
        newRange = math.max(minRange, newRange)
    end

    player.TearRange = newRange

    return newRange
end

function StatUtils.stats.range.applyMultiplierScaled(player, multiplier, minRange, showDisplay)
    if not player then return end

    local vanillaMultiplier = 1.0
    local scaledMultiplier = multiplier * vanillaMultiplier
    local baseRange = player.TearRange
    local newRange = baseRange * scaledMultiplier

    if minRange then
        newRange = math.max(minRange, newRange)
    end

    player.TearRange = newRange

    StatUtils.printDebug(string.format("[Range] MultiplierScaled: %.2fx * %.2fx = %.2fx -> Total: %.2f",
        multiplier, vanillaMultiplier, scaledMultiplier, newRange))

    return newRange, scaledMultiplier
end

function StatUtils.stats.range.applyAddition(player, addition, minRange)
    if not player then return end

    local baseRange = player.TearRange
    local newRange = baseRange + addition

    if minRange then
        newRange = math.max(minRange, newRange)
    end

    player.TearRange = newRange

    return newRange
end

function StatUtils.stats.range.applyAdditionScaled(player, addition, minRange)
    if not player then return end

    local vanillaMultiplier = 1.0
    local scaledAddition = addition * vanillaMultiplier
    local baseRange = player.TearRange
    local newRange = baseRange + scaledAddition

    if minRange then
        newRange = math.max(minRange, newRange)
    end

    player.TearRange = newRange

    StatUtils.printDebug(string.format("[Range] AdditionScaled: %.2f * %.2fx = %.2f -> Total: %.2f",
        addition, vanillaMultiplier, scaledAddition, newRange))

    return newRange, scaledAddition
end

-- Luck
StatUtils.stats.luck = {}

function StatUtils.stats.luck.applyMultiplier(player, multiplier, minLuck, showDisplay)
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

function StatUtils.stats.luck.applyMultiplierScaled(player, multiplier, minLuck, showDisplay)
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

    StatUtils.printDebug(string.format("[Luck] MultiplierScaled: %.2fx * %.2fx = %.2fx -> Total: %.2f",
        multiplier, vanillaMultiplier, scaledMultiplier, newLuck))

    return newLuck, scaledMultiplier
end

function StatUtils.stats.luck.applyAddition(player, addition, minLuck)
    if not player then return end

    local baseLuck = player.Luck
    local newLuck = baseLuck + addition

    if minLuck then
        newLuck = math.max(minLuck, newLuck)
    end

    player.Luck = newLuck

    return newLuck
end

function StatUtils.stats.luck.applyAdditionScaled(player, addition, minLuck)
    if not player then return end

    local vanillaMultiplier = 1.0
    local scaledAddition = addition * vanillaMultiplier
    local baseLuck = player.Luck
    local newLuck = baseLuck + scaledAddition

    if minLuck then
        newLuck = math.max(minLuck, newLuck)
    end

    player.Luck = newLuck

    StatUtils.printDebug(string.format("[Luck] AdditionScaled: %.2f * %.2fx = %.2f -> Total: %.2f",
        addition, vanillaMultiplier, scaledAddition, newLuck))

    return newLuck, scaledAddition
end

-- Shot Speed
StatUtils.stats.shotSpeed = {}

function StatUtils.stats.shotSpeed.applyMultiplier(player, multiplier, minShotSpeed, showDisplay)
    if not player then return end

    local baseShotSpeed = player.ShotSpeed
    local newShotSpeed = baseShotSpeed * multiplier

    if minShotSpeed then
        newShotSpeed = math.max(minShotSpeed, newShotSpeed)
    end

    player.ShotSpeed = newShotSpeed

    return newShotSpeed
end

function StatUtils.stats.shotSpeed.applyMultiplierScaled(player, multiplier, minShotSpeed, showDisplay)
    if not player then return end

    local vanillaMultiplier = 1.0
    local scaledMultiplier = multiplier * vanillaMultiplier
    local baseShotSpeed = player.ShotSpeed
    local newShotSpeed = baseShotSpeed * scaledMultiplier

    if minShotSpeed then
        newShotSpeed = math.max(minShotSpeed, newShotSpeed)
    end

    player.ShotSpeed = newShotSpeed

    StatUtils.printDebug(string.format("[ShotSpeed] MultiplierScaled: %.2fx * %.2fx = %.2fx -> Total: %.2f",
        multiplier, vanillaMultiplier, scaledMultiplier, newShotSpeed))

    return newShotSpeed, scaledMultiplier
end

function StatUtils.stats.shotSpeed.applyAddition(player, addition, minShotSpeed)
    if not player then return end

    local baseShotSpeed = player.ShotSpeed
    local newShotSpeed = baseShotSpeed + addition

    if minShotSpeed then
        newShotSpeed = math.max(minShotSpeed, newShotSpeed)
    end

    player.ShotSpeed = newShotSpeed

    return newShotSpeed
end

function StatUtils.stats.shotSpeed.applyAdditionScaled(player, addition, minShotSpeed)
    if not player then return end

    local vanillaMultiplier = 1.0
    local scaledAddition = addition * vanillaMultiplier
    local baseShotSpeed = player.ShotSpeed
    local newShotSpeed = baseShotSpeed + scaledAddition

    if minShotSpeed then
        newShotSpeed = math.max(minShotSpeed, newShotSpeed)
    end

    player.ShotSpeed = newShotSpeed

    StatUtils.printDebug(string.format("[ShotSpeed] AdditionScaled: %.2f * %.2fx = %.2f -> Total: %.2f",
        addition, vanillaMultiplier, scaledAddition, newShotSpeed))

    return newShotSpeed, scaledAddition
end

-------------------------------------------------------------------------------
-- Unified Stat Apply Functions
-------------------------------------------------------------------------------
StatUtils.stats.unified = {}

function StatUtils.stats.unified.applyMultiplierToAll(player, multiplier, minStats, showDisplay)
    if not player then return end

    minStats = minStats or StatUtils.stats.BASE_STATS

    StatUtils.stats.damage.applyMultiplier(player, multiplier, minStats.damage * 0.4, showDisplay)
    StatUtils.stats.tears.applyMultiplier(player, multiplier, nil, showDisplay)
    StatUtils.stats.speed.applyMultiplier(player, multiplier, minStats.speed * 0.4, showDisplay)
    StatUtils.stats.range.applyMultiplier(player, multiplier, minStats.range * 0.4, showDisplay)
    StatUtils.stats.luck.applyMultiplier(player, multiplier, minStats.luck * 0.4, showDisplay)
    StatUtils.stats.shotSpeed.applyMultiplier(player, multiplier, minStats.shotSpeed * 0.4, showDisplay)

    return true
end

function StatUtils.stats.unified.applyAdditionToAll(player, addition, minStats)
    if not player then return end

    minStats = minStats or StatUtils.stats.BASE_STATS

    StatUtils.stats.damage.applyAddition(player, addition, minStats.damage * 0.4)
    StatUtils.stats.tears.applyAddition(player, addition, nil)
    StatUtils.stats.speed.applyAddition(player, addition, minStats.speed * 0.4)
    StatUtils.stats.range.applyAddition(player, addition, minStats.range * 0.4)
    StatUtils.stats.luck.applyAddition(player, addition, minStats.luck * 0.4)
    StatUtils.stats.shotSpeed.applyAddition(player, addition, minStats.shotSpeed * 0.4)

    return true
end

function StatUtils.stats.unified.updateCache(player, cacheFlag)
    if not player then return end

    if cacheFlag then
        player:AddCacheFlags(cacheFlag)
    else
        player:AddCacheFlags(CacheFlag.CACHE_ALL)
    end

    player:EvaluateItems()
end

-- Convenience functions
StatUtils.stats.applyToAll = function(player, statType, multiplier, minValue, showDisplay)
    if not player or not statType then return false end

    if statType == "damage" then
        return StatUtils.stats.damage.applyMultiplier(player, multiplier, minValue, showDisplay)
    elseif statType == "tears" then
        return StatUtils.stats.tears.applyMultiplier(player, multiplier, minValue, showDisplay)
    elseif statType == "speed" then
        return StatUtils.stats.speed.applyMultiplier(player, multiplier, minValue, showDisplay)
    elseif statType == "range" then
        return StatUtils.stats.range.applyMultiplier(player, multiplier, minValue, showDisplay)
    elseif statType == "luck" then
        return StatUtils.stats.luck.applyMultiplier(player, multiplier, minValue, showDisplay)
    elseif statType == "shotSpeed" then
        return StatUtils.stats.shotSpeed.applyMultiplier(player, multiplier, minValue, showDisplay)
    end

    return false
end

StatUtils.stats.addToAll = function(player, statType, addition, minValue)
    if not player or not statType then return false end

    if statType == "damage" then
        return StatUtils.stats.damage.applyAddition(player, addition, minValue)
    elseif statType == "tears" then
        return StatUtils.stats.tears.applyAddition(player, addition, minValue)
    elseif statType == "speed" then
        return StatUtils.stats.speed.applyAddition(player, addition, minValue)
    elseif statType == "range" then
        return StatUtils.stats.range.applyAddition(player, addition, minValue)
    elseif statType == "luck" then
        return StatUtils.stats.luck.applyAddition(player, addition, minValue)
    elseif statType == "shotSpeed" then
        return StatUtils.stats.shotSpeed.applyAddition(player, addition, minValue)
    end

    return false
end

StatUtils.stats.getCurrentStats = function(player)
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

StatUtils.stats.getBaseStats = function()
    return StatUtils.stats.BASE_STATS
end

-- Apply stat multiplier to actual player stat
function StatUtils.stats.unifiedMultipliers:ApplyStatMultiplier(player, statType, totalMultiplier)
    if not player or not statType or not totalMultiplier then return end

    StatUtils.printDebug(string.format("Applying %s multiplier %.2fx to player", statType, totalMultiplier))

    local originalValues = {
        Tears = player.MaxFireDelay,
        Damage = player.Damage,
        Range = player.TearRange,
        Luck = player.Luck,
        Speed = player.MoveSpeed,
        ShotSpeed = player.ShotSpeed
    }

    StatUtils.printDebug(string.format("Original values - Tears: %.2f, Damage: %.2f, Range: %.2f, Luck: %.2f, Speed: %.2f, ShotSpeed: %.2f",
        originalValues.Tears, originalValues.Damage, originalValues.Range, originalValues.Luck, originalValues.Speed, originalValues.ShotSpeed))

    if statType == "Tears" then
        StatUtils.stats.tears.applyMultiplier(player, totalMultiplier, nil, false)
    elseif statType == "Damage" then
        StatUtils.stats.damage.applyMultiplier(player, totalMultiplier, 0.1, false)
    elseif statType == "Range" then
        StatUtils.stats.range.applyMultiplier(player, totalMultiplier, 0.1, false)
    elseif statType == "Luck" then
        StatUtils.stats.luck.applyMultiplier(player, totalMultiplier, 0.1, false)
    elseif statType == "Speed" then
        StatUtils.stats.speed.applyMultiplier(player, totalMultiplier, 0.1, false)
    elseif statType == "ShotSpeed" then
        StatUtils.stats.shotSpeed.applyMultiplier(player, totalMultiplier, 0.1, false)
    end

    player:AddCacheFlags(CacheFlag.CACHE_ALL)
    player:EvaluateItems()

    local newValues = {
        Tears = player.MaxFireDelay,
        Damage = player.Damage,
        Range = player.TearRange,
        Luck = player.Luck,
        Speed = player.MoveSpeed,
        ShotSpeed = player.ShotSpeed
    }

    StatUtils.printDebug(string.format("New values - Tears: %.2f, Damage: %.2f, Range: %.2f, Luck: %.2f, Speed: %.2f, ShotSpeed: %.2f",
        newValues.Tears, newValues.Damage, newValues.Range, newValues.Luck, newValues.Speed, newValues.ShotSpeed))

    if newValues[statType] == originalValues[statType] then
        StatUtils.printDebug(string.format("WARNING: %s value did not change, forcing direct update", statType))

        if statType == "Tears" then
            local baseSPS = 30 / (originalValues.Tears + 1)
            local targetSPS = baseSPS * totalMultiplier
            local newFireDelay = (30 / targetSPS) - 1
            player.MaxFireDelay = newFireDelay
            StatUtils.printDebug(string.format("Direct update: MaxFireDelay %.2f -> %.2f", originalValues.Tears, newFireDelay))
        elseif statType == "Damage" then
            local newDamage = originalValues.Damage * totalMultiplier
            player.Damage = newDamage
            StatUtils.printDebug(string.format("Direct update: Damage %.2f -> %.2f", originalValues.Damage, newDamage))
        elseif statType == "Range" then
            local newRange = originalValues.Range * totalMultiplier
            player.TearRange = newRange
            StatUtils.printDebug(string.format("Direct update: Range %.2f -> %.2f", originalValues.Range, newRange))
        elseif statType == "Luck" then
            local newLuck = originalValues.Luck * totalMultiplier
            player.Luck = newLuck
            StatUtils.printDebug(string.format("Direct update: Luck %.2f -> %.2f", originalValues.Luck, newLuck))
        elseif statType == "Speed" then
            local newSpeed = originalValues.Speed * totalMultiplier
            player.MoveSpeed = newSpeed
            StatUtils.printDebug(string.format("Direct update: Speed %.2f -> %.2f", originalValues.Speed, newSpeed))
        elseif statType == "ShotSpeed" then
            local newShotSpeed = originalValues.ShotSpeed * totalMultiplier
            player.ShotSpeed = newShotSpeed
            StatUtils.printDebug(string.format("Direct update: ShotSpeed %.2f -> %.2f", originalValues.ShotSpeed, newShotSpeed))
        end

        player:AddCacheFlags(CacheFlag.CACHE_ALL)
        player:EvaluateItems()
    end

    StatUtils.printDebug(string.format("Applied %s multiplier %.2fx and updated cache", statType, totalMultiplier))
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

    function StatUtils.stats.unifiedMultipliers:OnEvaluateCache(player, cacheFlag)
        if not player or not cacheFlag then return end
        local statType = CACHE_FLAG_TO_STAT[cacheFlag]
        if not statType then return end
        self._isEvaluatingCache = true

        self:InitPlayer(player)
        local playerID = StatUtils:GetPlayerInstanceKey(player)
        local total = 1.0
        if self[playerID]
            and self[playerID].statMultipliers
            and self[playerID].statMultipliers[statType]
            and type(self[playerID].statMultipliers[statType].totalApply) == "number" then
            total = self[playerID].statMultipliers[statType].totalApply
        end

        StatUtils.printDebug(string.format("[Unified] Evaluating %s cache: applying pure total %.2fx", statType, total))

        if statType == "Tears" then
            StatUtils.stats.tears.applyMultiplier(player, total, nil, false)
            local add = self[playerID] and self[playerID].statMultipliers and self[playerID].statMultipliers[statType] and (self[playerID].statMultipliers[statType].totalAdditions or 0) or 0
            if add ~= 0 then
                StatUtils.stats.tears.applyAddition(player, add, nil)
                StatUtils.printDebug(string.format("[Unified] Applied Tears SPS addition at cache: %+0.4f", add))
            end
        elseif statType == "Damage" then
            local add = self[playerID] and self[playerID].statMultipliers and self[playerID].statMultipliers[statType] and (self[playerID].statMultipliers[statType].totalAdditions or 0) or 0
            local baseDamage = player.Damage
            local finalDamage = (baseDamage + add) * total

            StatUtils.printDebug(string.format("[Unified] Damage calc: (%.2f base + %.2f add) x %.2fx mult = %.2f final",
                baseDamage, add, total, finalDamage))

            player.Damage = math.max(0.1, finalDamage)
            StatUtils.stats.damage.applyPoisonDamageCombined(player, total, add)
        elseif statType == "Range" then
            StatUtils.stats.range.applyMultiplier(player, total, 0.1, false)
        elseif statType == "Luck" then
            StatUtils.stats.luck.applyMultiplier(player, total, 0.1, false)
        elseif statType == "Speed" then
            StatUtils.stats.speed.applyMultiplier(player, total, 0.1, false)
        elseif statType == "ShotSpeed" then
            StatUtils.stats.shotSpeed.applyMultiplier(player, total, 0.1, false)
        end
        self._isEvaluatingCache = false
    end

    -- Register MC_EVALUATE_CACHE callback
    StatUtils.mod:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, function(_, player, cacheFlag)
        if StatUtils.stats and StatUtils.stats.unifiedMultipliers and StatUtils.stats.unifiedMultipliers.OnEvaluateCache then
            StatUtils.stats.unifiedMultipliers:OnEvaluateCache(player, cacheFlag)
        end
    end)

    -- Auto-load/reset on game start
    StatUtils.mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContinued)
        if not isContinued then
            -- New run: clear all data
            StatUtils:ClearRunData()
            if StatUtils.stats.multiplierDisplay then
                StatUtils.stats.multiplierDisplay:ResetForNewGame()
            end
            -- Reset unified multipliers for all known players
            StatUtils.stats.unifiedMultipliers._justLoaded = false
            StatUtils.printDebug("[Unified] New game: cleared all data")
        else
            -- Continue: load saved data
            StatUtils:LoadRunData()
        end

        local numPlayers = Game():GetNumPlayers()
        for i = 0, numPlayers - 1 do
            local player = Isaac.GetPlayer(i)
            if player then
                if isContinued then
                    StatUtils.stats.unifiedMultipliers:LoadFromSaveManager(player)
                end
                player:AddCacheFlags(CacheFlag.CACHE_ALL)
                player:EvaluateItems()
            end
        end
        StatUtils.printDebug("[Unified] Loaded multipliers for all players on POST_GAME_STARTED")
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
    function StatUtils.stats.unifiedMultipliers:QueueCacheUpdate(player, statType)
        if not player or not statType then return end
        self:InitPlayer(player)
        local playerID = StatUtils:GetPlayerInstanceKey(player)
        local flag = STAT_TO_CACHE_FLAG[statType] or CacheFlag.CACHE_ALL
        self[playerID].pendingCache[flag] = true
        self._hasPending = true
        StatUtils.printDebug(string.format("[Unified] Queued cache update for %s (flag %d)", statType, flag))
    end

    -- Flush all queued cache updates safely in POST_UPDATE
    StatUtils.mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
        if not StatUtils.stats or not StatUtils.stats.unifiedMultipliers or not StatUtils.stats.unifiedMultipliers._hasPending then
            return
        end
        local um = StatUtils.stats.unifiedMultipliers
        local numPlayers = Game():GetNumPlayers()
        for i = 0, numPlayers - 1 do
            local player = Isaac.GetPlayer(i)
            if player then
                local playerID = StatUtils:GetPlayerInstanceKey(player)
                if um[playerID] and um[playerID].pendingCache then
                    local combined = 0
                    for flag, pending in pairs(um[playerID].pendingCache) do
                        if pending then
                            combined = combined | flag
                        end
                    end
                    if combined ~= 0 then
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

StatUtils.printDebug("Enhanced Stats library with unified multiplier system loaded successfully!")
