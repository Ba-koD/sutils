# StatsAPI 문서 (KO)

[English version](README.en.md)

이 문서는 설치/소개를 빼고, **다른 모드에서 어떻게 등록하고 어떻게 동작하는지**만 정리합니다.

<a id="kr-1-registration"></a>
### 1) 등록 방법 (연동 코드)

#### 1-1. 기본 규칙

- `StatsAPI`는 전역 테이블이라 `require` 없이 바로 사용합니다.
- 다른 모드에서는 항상 먼저 존재 여부를 체크합니다.

```lua
if not StatsAPI then return end
```

#### 1-2. 배율(Multiplier) 등록 예시

`SetItemMultiplier`는 같은 `itemID + statType`를 다시 호출하면 **덮어쓰기**라서, `MC_EVALUATE_CACHE`에서 반복 호출해도 안전합니다.

```lua
local mod = RegisterMod("My Mod", 1)
local ITEM_ID = Isaac.GetItemIdByName("My Item")
local ITEM_KEY = "my_mod:my_item"

mod:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, function(_, player, cacheFlag)
    if not StatsAPI then return end

    if cacheFlag == CacheFlag.CACHE_DAMAGE then
        if player:HasCollectible(ITEM_ID) then
            local count = player:GetCollectibleNum(ITEM_ID)
            StatsAPI.stats.unifiedMultipliers:SetItemMultiplier(
                player,
                ITEM_KEY,
                "Damage",
                1.2 ^ count,
                "My Item"
            )
        else
            StatsAPI.stats.unifiedMultipliers:RemoveItemMultiplier(player, ITEM_KEY, "Damage")
        end
    end
end)
```

#### 1-3. 덧셈(Addition) / 가산 배율(Additive Multiplier) 등록 예시

`SetItemAddition`, `SetItemAdditiveMultiplier`는 **누적형**입니다.
같은 값을 프레임마다 계속 호출하면 값이 계속 더해집니다.

그래서 아래처럼 "변화가 생긴 순간"에만 호출하는 패턴을 권장합니다.

```lua
local mod = RegisterMod("My Mod", 1)
local ITEM_ID = Isaac.GetItemIdByName("My Item")
local ITEM_KEY = "my_mod:my_item"
local lastCount = {}

mod:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, function(_, player)
    if not StatsAPI then return end

    local ptr = GetPtrHash(player)
    local now = player:GetCollectibleNum(ITEM_ID)
    local prev = lastCount[ptr] or 0

    if now > prev then
        for _ = 1, (now - prev) do
            StatsAPI.stats.unifiedMultipliers:SetItemAddition(player, ITEM_KEY, "Tears", 0.3, "My Item")
        end
    elseif now < prev then
        -- RemoveItemAddition은 Addition + AdditiveMultiplier를 같이 제거함
        StatsAPI.stats.unifiedMultipliers:RemoveItemAddition(player, ITEM_KEY, "Tears")
    end

    lastCount[ptr] = now
end)
```

#### 1-4. 배율 임시 비활성화(Disable) 예시

`SetItemMultiplierDisabled`는 multiplier 엔트리를 삭제하지 않고 ON/OFF 합니다.

```lua
local um = StatsAPI.stats.unifiedMultipliers

-- 먼저 multiplier가 등록되어 있어야 함
um:SetItemMultiplier(player, ITEM_KEY, "Damage", 1.5, "My Item")

-- 임시 비활성화 (값은 저장된 채 적용만 중지)
um:SetItemMultiplierDisabled(player, ITEM_KEY, "Damage", true)

-- 다시 활성화
um:SetItemMultiplierDisabled(player, ITEM_KEY, "Damage", false)
```

<a id="kr-2-api"></a>
### 2) API 설명

#### 2-1. 등록 API

- `SetItemMultiplier(player, itemID, statType, multiplier, description)`
  - 곱셈 배율 등록/갱신 (덮어쓰기)
- `SetItemAddition(player, itemID, statType, addition, description)`
  - 덧셈 등록 (누적)
- `SetItemAdditiveMultiplier(player, itemID, statType, multiplierValue, description)`
  - 가산 배율 등록 (내부적으로 `multiplierValue - 1` 누적)

#### 2-2. 해제/비활성화 API

- `RemoveItemMultiplier(player, itemID, statType)`
  - multiplier만 제거
- `SetItemMultiplierDisabled(player, itemID, statType, disabled)`
  - multiplier 엔트리를 삭제하지 않고 비활성화/재활성화
  - `true` = disable, `false` = enable
  - 반환값: 적용 여부(`boolean`)
- `RemoveItemAddition(player, itemID, statType)`
  - addition + additive multiplier를 함께 제거

#### 2-3. 조회 API

- `GetMultipliers(player, statType)`
  - `current, total` 반환
- `GetAllMultipliers(player)`
  - 플레이어의 전체 스탯 데이터 반환

#### 2-4. statType 문자열

아래 문자열만 사용합니다 (대소문자 포함):

- `"Damage"`
- `"Tears"`
- `"Speed"`
- `"Range"`
- `"Luck"`
- `"ShotSpeed"`

#### 2-5. 데미지/Poison 동기화

- `player:GetTearPoisonDamage`와 `player:SetTearPoisonDamage` setter/getter가 존재하면,
  데미지 캐시 적용 시 Poison 데미지도 같은 수식으로 같이 반영됩니다.
- Unified Damage 적용식: `(base + add) * multiplier`

<a id="kr-3-runtime-flow"></a>
### 3) 내부 동작 순서

#### 3-1. 초기화

1. `main.lua`에서 `scripts/statsapi_core.lua` 로드
2. `statsapi_core.lua`에서 `StatsAPI` 전역 생성
3. `scripts/lib/stats.lua`, `scripts/lib/vanilla_multipliers.lua`, `scripts/lib/damage_utils.lua` 로드
4. HUD 렌더 콜백 등록

#### 3-2. 등록 후 적용

1. 외부 모드가 `SetItem*` 호출
2. 내부에서 플레이어별 데이터 갱신 + `RecalculateStatMultiplier` 실행
3. 해당 스탯 캐시 갱신을 `pendingCache`에 큐잉
4. `MC_POST_UPDATE`에서 큐를 모아서 `AddCacheFlags` + `EvaluateItems`
5. `MC_EVALUATE_CACHE`에서 실제 스탯에 반영

#### 3-3. 저장/복원

- `MC_PRE_GAME_EXIT`에서 플레이어별 multiplier 데이터 저장
- `MC_POST_GAME_STARTED`에서
  - 새 런: 데이터 초기화
  - 이어하기: 저장 데이터 로드 후 캐시 재평가

<a id="kr-4-files"></a>
### 4) 파일별 역할

- `main.lua`
  - 코어 로더만 담당 (`require("scripts/statsapi_core")`)

- `scripts/statsapi_core.lua`
  - 전역 `StatsAPI` 생성
  - 로그/디버그/저장 시스템
  - 하위 모듈 로드
  - 종료 시 저장 콜백 등록

- `scripts/lib/stats.lua`
  - 핵심 로직
  - Unified multiplier 데이터 구조
  - `SetItem*`, `Remove*`, `Get*` API
  - 캐시 큐/적용(`MC_POST_UPDATE`, `MC_EVALUATE_CACHE`)
  - HUD 표시 렌더

- `scripts/lib/vanilla_multipliers.lua`
  - 바닐라 캐릭터/아이템 배율 표
  - 스케일 계산용 유틸 함수

- `scripts/lib/damage_utils.lua`
  - `isSelfInflictedDamage(flags, source)` 제공
  - 피해 플래그/소스 기반 자해 판정 유틸

<a id="kr-5-notes"></a>
### 5) 자주 헷갈리는 포인트

- `SetItemAddition`, `SetItemAdditiveMultiplier`는 누적형이라 반복 호출 시 계속 누적됩니다.
- `SetItemMultiplierDisabled`는 multiplier(`SetItemMultiplier`)에만 적용됩니다.
- `disabled` 상태는 저장/불러오기 시 유지됩니다.
- Mod Config Menu가 설치되어 있으면 `StatsAPI > Display > Multiplier HUD`에서 표시 ON/OFF, `HUD Display Mode`에서 `Last Multiplier / Final Multiplier / Both` 선택이 가능합니다.
- HUD 위치는 Isaac `Options.HUDOffset`을 따라가며, `StatsAPI > Display > HUD Offset X/Y`로 추가 미세 조정할 수 있습니다.
- `RemoveItemAddition`은 addition만 지우는 함수가 아니라 additive multiplier도 같이 지웁니다.
- `statType` 오타/대소문자 불일치는 적용되지 않습니다.
- 외부 모드에서는 항상 `if not StatsAPI then return end` 체크를 먼저 두는 게 안전합니다.
