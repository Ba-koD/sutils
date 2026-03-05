-- Stat Utils - Vanilla Item Damage Multipliers Table
-- Based on Epiphany mod's collectible_damage_multipliers.lua (Repentance+ accurate)
-- Provides vanilla item/character damage and fire rate multiplier lookup

StatUtils.VanillaMultipliers = {}

-- Damage multipliers for vanilla collectibles (Rep+ accurate, from Epiphany)
StatUtils.VanillaMultipliers.CollectibleDamage = {
    [CollectibleType.COLLECTIBLE_MEGA_MUSH] = function(player)
        if not player:GetEffects():HasCollectibleEffect(CollectibleType.COLLECTIBLE_MEGA_MUSH) then return 1 end
        return 4
    end,
    [CollectibleType.COLLECTIBLE_CRICKETS_HEAD] = 1.5,
    [CollectibleType.COLLECTIBLE_MAGIC_MUSHROOM] = function(player)
        if player:HasCollectible(CollectibleType.COLLECTIBLE_CRICKETS_HEAD) then return 1 end
        return 1.5
    end,
    [CollectibleType.COLLECTIBLE_BLOOD_OF_THE_MARTYR] = function(player)
        if not player:GetEffects():HasCollectibleEffect(CollectibleType.COLLECTIBLE_BOOK_OF_BELIAL) then return 1 end
        if player:HasCollectible(CollectibleType.COLLECTIBLE_CRICKETS_HEAD)
            or player:GetEffects():HasCollectibleEffect(CollectibleType.COLLECTIBLE_MAGIC_MUSHROOM)
        then
            return 1
        end
        return 1.5
    end,
    [CollectibleType.COLLECTIBLE_POLYPHEMUS] = 2,
    [CollectibleType.COLLECTIBLE_SACRED_HEART] = 2.3,
    [CollectibleType.COLLECTIBLE_EVES_MASCARA] = 2,
    [CollectibleType.COLLECTIBLE_ODD_MUSHROOM_THIN] = 0.9,
    [CollectibleType.COLLECTIBLE_20_20] = 0.75,
    [CollectibleType.COLLECTIBLE_SOY_MILK] = function(player)
        if player:HasCollectible(CollectibleType.COLLECTIBLE_ALMOND_MILK) then return 1 end
        return 0.2
    end,
    [CollectibleType.COLLECTIBLE_CROWN_OF_LIGHT] = function(player)
        if player:GetEffects():HasCollectibleEffect(CollectibleType.COLLECTIBLE_CROWN_OF_LIGHT) then return 2 end
        return 1
    end,
    [CollectibleType.COLLECTIBLE_ALMOND_MILK] = 0.33,
    [CollectibleType.COLLECTIBLE_IMMACULATE_HEART] = 1.2,
}

-- Character-specific damage multipliers (Rep+ accurate, from Epiphany)
StatUtils.VanillaMultipliers.CharacterDamage = {
    [PlayerType.PLAYER_ISAAC] = 1,
    [PlayerType.PLAYER_MAGDALENE] = 1,
    [PlayerType.PLAYER_CAIN] = 1.2,
    [PlayerType.PLAYER_JUDAS] = 1.35,
    [PlayerType.PLAYER_BLUEBABY] = 1.05,
    [PlayerType.PLAYER_EVE] = function(player)
        if player:GetEffects():HasCollectibleEffect(CollectibleType.COLLECTIBLE_WHORE_OF_BABYLON) then return 1 end
        return 0.75
    end,
    [PlayerType.PLAYER_SAMSON] = 1,
    [PlayerType.PLAYER_AZAZEL] = 1.5,
    [PlayerType.PLAYER_LAZARUS] = 1,
    [PlayerType.PLAYER_EDEN] = 1,
    [PlayerType.PLAYER_THELOST] = 1,
    [PlayerType.PLAYER_LAZARUS2] = 1.4,
    [PlayerType.PLAYER_BLACKJUDAS] = 2,
    [PlayerType.PLAYER_LILITH] = 1,
    [PlayerType.PLAYER_KEEPER] = 1.2,
    [PlayerType.PLAYER_APOLLYON] = 1,
    [PlayerType.PLAYER_THEFORGOTTEN] = 1.5,
    [PlayerType.PLAYER_THESOUL] = 1,
    [PlayerType.PLAYER_BETHANY] = 1,
    [PlayerType.PLAYER_JACOB] = 1,
    [PlayerType.PLAYER_ESAU] = 1,
    [PlayerType.PLAYER_ISAAC_B] = 1,
    [PlayerType.PLAYER_MAGDALENE_B] = 0.75,
    [PlayerType.PLAYER_CAIN_B] = 1,
    [PlayerType.PLAYER_JUDAS_B] = 1,
    [PlayerType.PLAYER_BLUEBABY_B] = 1,
    [PlayerType.PLAYER_EVE_B] = 1.2,
    [PlayerType.PLAYER_SAMSON_B] = 1,
    [PlayerType.PLAYER_AZAZEL_B] = 1.5,
    [PlayerType.PLAYER_LAZARUS_B] = 1,
    [PlayerType.PLAYER_EDEN_B] = 1,
    [PlayerType.PLAYER_THELOST_B] = 1.3,
    [PlayerType.PLAYER_LILITH_B] = 1,
    [PlayerType.PLAYER_KEEPER_B] = 1,
    [PlayerType.PLAYER_APOLLYON_B] = 1,
    [PlayerType.PLAYER_THEFORGOTTEN_B] = 1.5,
    [PlayerType.PLAYER_BETHANY_B] = 1,
    [PlayerType.PLAYER_JACOB_B] = 1,
    [PlayerType.PLAYER_LAZARUS2_B] = 1.5,
}

-- Get total damage multiplier from vanilla items for a player
---@param player EntityPlayer
---@return number totalMultiplier
function StatUtils.VanillaMultipliers:GetPlayerDamageMultiplier(player)
    if not player then return 1.0 end

    local charMult = self.CharacterDamage[player:GetPlayerType()]
    local totalMultiplier = 1.0

    if charMult then
        if type(charMult) == "function" then
            totalMultiplier = charMult(player)
        else
            totalMultiplier = charMult
        end
    end

    local effects = player:GetEffects()
    for itemID, mult in pairs(self.CollectibleDamage) do
        if player:HasCollectible(itemID) or effects:HasCollectibleEffect(itemID) then
            local actualMult = mult
            if type(mult) == "function" then
                actualMult = mult(player)
            end
            totalMultiplier = totalMultiplier * actualMult
        end
    end

    return totalMultiplier
end

-- Get total fire rate multiplier from vanilla items (Rep+ accurate)
---@param player EntityPlayer
---@return number totalMultiplier
function StatUtils.VanillaMultipliers:GetPlayerFireRateMultiplier(player)
    if not player then return 1.0 end

    local multi = 1.0
    local playerType = player:GetPlayerType()

    if playerType == PlayerType.PLAYER_THEFORGOTTEN or playerType == PlayerType.PLAYER_THEFORGOTTEN_B then
        multi = multi * 0.5
    end

    if player:HasCollectible(CollectibleType.COLLECTIBLE_ALMOND_MILK) then
        multi = multi * 4
    elseif player:HasCollectible(CollectibleType.COLLECTIBLE_SOY_MILK) then
        multi = multi * 5.5
    end

    if player:HasCollectible(CollectibleType.COLLECTIBLE_POLYPHEMUS) then
        multi = multi * 0.42
    end

    if player:HasCollectible(CollectibleType.COLLECTIBLE_EVES_MASCARA) then
        multi = multi * 0.66
    end

    if player:HasCollectible(CollectibleType.COLLECTIBLE_MONSTROS_LUNG) then
        multi = multi * 0.23
    end

    if player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE) then
        multi = multi * 0.33
    end

    return multi
end

-- Apply bonus damage with vanilla multiplier consideration
---@param player EntityPlayer
---@param bonusDamage number
---@return number actualBonus
function StatUtils.VanillaMultipliers:ApplyBonusDamage(player, bonusDamage)
    if not player or type(bonusDamage) ~= "number" then return 0 end

    local multiplier = self:GetPlayerDamageMultiplier(player)
    local actualBonus = bonusDamage * multiplier

    player.Damage = player.Damage + actualBonus

    StatUtils.printDebug(string.format("[VanillaMultipliers] Applied bonus damage: %.2f * %.2fx = %.2f",
        bonusDamage, multiplier, actualBonus))

    return actualBonus
end

-- Check if a specific item affects damage multiplier
---@param itemID CollectibleType
---@return boolean
function StatUtils.VanillaMultipliers:HasDamageMultiplier(itemID)
    return self.CollectibleDamage[itemID] ~= nil
end

-- Get the damage multiplier for a specific item
---@param player EntityPlayer
---@param itemID CollectibleType
---@return number
function StatUtils.VanillaMultipliers:GetItemDamageMultiplier(player, itemID)
    local mult = self.CollectibleDamage[itemID]
    if not mult then return 1.0 end

    if type(mult) == "function" then
        return mult(player)
    end
    return mult
end

StatUtils.printDebug("Vanilla Multipliers table loaded successfully! (Rep+ accurate from Epiphany)")
