# Stat Utils Documentation (EN)

[한국어 버전](README.ko.md)

This section documents only integration and runtime behavior (no install/introduction details).

<a id="en-1-registration"></a>
### 1) Registration (Integration)

#### 1-1. Basic Rule

- `StatUtils` is a global table, so you can use it without `require`.
- Always guard with an existence check in your mod.

```lua
if not StatUtils then return end
```

#### 1-2. Multiplier Registration Example

`SetItemMultiplier` overwrites the value for the same `itemID + statType`, so calling it repeatedly in `MC_EVALUATE_CACHE` is safe.

```lua
local mod = RegisterMod("My Mod", 1)
local ITEM_ID = Isaac.GetItemIdByName("My Item")
local ITEM_KEY = "my_mod:my_item"

mod:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, function(_, player, cacheFlag)
    if not StatUtils then return end

    if cacheFlag == CacheFlag.CACHE_DAMAGE then
        if player:HasCollectible(ITEM_ID) then
            local count = player:GetCollectibleNum(ITEM_ID)
            StatUtils.stats.unifiedMultipliers:SetItemMultiplier(
                player,
                ITEM_KEY,
                "Damage",
                1.2 ^ count,
                "My Item"
            )
        else
            StatUtils.stats.unifiedMultipliers:RemoveItemMultiplier(player, ITEM_KEY, "Damage")
        end
    end
end)
```

#### 1-3. Addition / Additive Multiplier Example

`SetItemAddition` and `SetItemAdditiveMultiplier` are cumulative.
If called every frame with the same value, they keep accumulating.

Use an event/edge pattern (apply only when state changes):

```lua
local mod = RegisterMod("My Mod", 1)
local ITEM_ID = Isaac.GetItemIdByName("My Item")
local ITEM_KEY = "my_mod:my_item"
local lastCount = {}

mod:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, function(_, player)
    if not StatUtils then return end

    local ptr = GetPtrHash(player)
    local now = player:GetCollectibleNum(ITEM_ID)
    local prev = lastCount[ptr] or 0

    if now > prev then
        for _ = 1, (now - prev) do
            StatUtils.stats.unifiedMultipliers:SetItemAddition(player, ITEM_KEY, "Tears", 0.3, "My Item")
        end
    elseif now < prev then
        -- RemoveItemAddition clears both Addition and AdditiveMultiplier
        StatUtils.stats.unifiedMultipliers:RemoveItemAddition(player, ITEM_KEY, "Tears")
    end

    lastCount[ptr] = now
end)
```

#### 1-4. Temporary Disable Example (Multiplier)

`SetItemMultiplierDisabled` toggles a multiplier entry without deleting it.

```lua
local um = StatUtils.stats.unifiedMultipliers

-- Multiplier must exist first
um:SetItemMultiplier(player, ITEM_KEY, "Damage", 1.5, "My Item")

-- Temporary disable (keeps stored value, stops applying it)
um:SetItemMultiplierDisabled(player, ITEM_KEY, "Damage", true)

-- Re-enable
um:SetItemMultiplierDisabled(player, ITEM_KEY, "Damage", false)
```

<a id="en-2-api"></a>
### 2) API

#### 2-1. Register APIs

- `SetItemMultiplier(player, itemID, statType, multiplier, description)`
  - Register/update multiplicative value (overwrite)
- `SetItemAddition(player, itemID, statType, addition, description)`
  - Register additive value (cumulative)
- `SetItemAdditiveMultiplier(player, itemID, statType, multiplierValue, description)`
  - Register additive multiplier (internally accumulates `multiplierValue - 1`)

#### 2-2. Remove/Disable APIs

- `RemoveItemMultiplier(player, itemID, statType)`
  - Removes multiplier only
- `SetItemMultiplierDisabled(player, itemID, statType, disabled)`
  - Disables/enables an existing multiplier entry without deleting it
  - `true` = disable, `false` = enable
  - Return value: success flag (`boolean`)
- `RemoveItemAddition(player, itemID, statType)`
  - Removes both addition and additive multiplier

#### 2-3. Query APIs

- `GetMultipliers(player, statType)`
  - Returns `current, total`
- `GetAllMultipliers(player)`
  - Returns all tracked stat data for the player

#### 2-4. Valid `statType` Strings

- `"Damage"`
- `"Tears"`
- `"Speed"`
- `"Range"`
- `"Luck"`
- `"ShotSpeed"`

#### 2-5. Damage/Poison Synchronization

- If both `player:GetTearPoisonDamage` and `player:SetTearPoisonDamage` exist,
  Poison damage is updated alongside unified damage cache application.
- Unified damage formula: `(base + add) * multiplier`

<a id="en-3-runtime-flow"></a>
### 3) Runtime Flow

#### 3-1. Initialization

1. `main.lua` loads `scripts/stat_utils_core.lua`
2. `stat_utils_core.lua` creates global `StatUtils`
3. Loads `scripts/lib/stats.lua`, `scripts/lib/vanilla_multipliers.lua`, `scripts/lib/damage_utils.lua`
4. Registers HUD render callback

#### 3-2. Apply Flow After Registration

1. External mod calls a `SetItem*` API
2. Internal player data is updated and `RecalculateStatMultiplier` runs
3. Target cache flag is queued in `pendingCache`
4. `MC_POST_UPDATE` flushes queue with `AddCacheFlags` + `EvaluateItems`
5. `MC_EVALUATE_CACHE` applies final values to actual player stats

#### 3-3. Save/Load Flow

- `MC_PRE_GAME_EXIT`: saves per-player multiplier state
- `MC_POST_GAME_STARTED`:
  - New run: clear data
  - Continue run: load data and re-evaluate cache

<a id="en-4-files"></a>
### 4) File Roles

- `main.lua`
  - Core loader only (`require("scripts/stat_utils_core")`)

- `scripts/stat_utils_core.lua`
  - Creates global `StatUtils`
  - Logging/debug/save system
  - Sub-module loading
  - Exit-time save callback

- `scripts/lib/stats.lua`
  - Core logic
  - Unified multiplier data model
  - `SetItem*`, `Remove*`, `Get*` APIs
  - Cache queue/apply (`MC_POST_UPDATE`, `MC_EVALUATE_CACHE`)
  - HUD rendering

- `scripts/lib/vanilla_multipliers.lua`
  - Vanilla character/item multiplier tables
  - Scaling utility functions

- `scripts/lib/damage_utils.lua`
  - Provides `isSelfInflictedDamage(flags, source)`
  - Self-damage detection helper from flag/source context

<a id="en-5-notes"></a>
### 5) Common Pitfalls

- `SetItemAddition` and `SetItemAdditiveMultiplier` are cumulative.
- `SetItemMultiplierDisabled` only applies to multiplier entries (`SetItemMultiplier`).
- Disabled state is persisted through save/load.
- If Mod Config Menu is installed, you can toggle HUD rendering at `Stat Utils > Display > Multiplier HUD`.
- HUD position follows Isaac's `Options.HUDOffset`, and can be fine-tuned with `Stat Utils > Display > HUD Offset X/Y`.
- `RemoveItemAddition` removes additive multiplier data as well.
- `statType` typos/case mismatch will not apply.
- Always check `if not StatUtils then return end` before calling API.
