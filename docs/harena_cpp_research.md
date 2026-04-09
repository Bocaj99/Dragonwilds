# Harena v3 — C++ Modding Research

Comprehensive research into UE4SS C++ modding capabilities and how they apply to every Harena CTF system. Generated 2026-04-10.

---

## Table of Contents

1. [UE4SS Installation Status](#1-ue4ss-installation-status)
2. [C++ Mod Architecture](#2-c-mod-architecture)
3. [Project Setup & Build](#3-project-setup--build)
4. [Core C++ API Reference](#4-core-c-api-reference)
5. [Function Hooking (C++ vs Lua)](#5-function-hooking-c-vs-lua)
6. [Damage Pipeline Deep Dive](#6-damage-pipeline-deep-dive)
7. [All Harena Systems — C++ Opportunities](#7-all-harena-systems--c-opportunities)
8. [Priority Matrix](#8-priority-matrix)
9. [Testing Checklist](#9-testing-checklist)
10. [Resources & References](#10-resources--references)

---

## 1. UE4SS Installation Status

**Version:** UE4SS v3.0.1 Beta #0 (git SHA: 0196ef29)
**Engine:** Unreal Engine 5.6
**Build Config:** Game__Shipping__Win64 (MSVC)
**DLL:** `ue4ss/UE4SS.dll` (16 MB)

**Current Mod Type:** All 11 active mods are **Lua-only**. No C++ DLL mods exist yet.

**Active Mods (from mods.txt):**
- CheatManagerEnablerMod, ConsoleCommandsMod, ConsoleEnablerMod
- BPML_GenericFunctions, BPModLoaderMod
- Harena (14 Lua files), Keybinds
- CTFDiscovery (disabled), CTFBuildingTool (enabled for testing)

**Key Config (UE4SS-settings.ini):**
- Hot reload: enabled (Ctrl+R)
- Debug console: enabled (GUI + DX11)
- ProcessEvent hooks: enabled
- CXXHeaderDump: 2,842 generated .hpp files

**No C++ infrastructure present:** No `dlls/` folders, no `.lib` files, no CMakeLists.txt, no build scripts.

---

## 2. C++ Mod Architecture

### How C++ Mods Work in UE4SS

C++ mods are compiled DLLs loaded by UE4SS alongside Lua mods. They have **deeper access** than Lua:

| Capability | Lua | C++ |
|---|---|---|
| Hook UFunctions | Yes (RegisterHook) | Yes (ProcessEvent callbacks) |
| Hook delegates/multicast events | **No** | **Yes** (direct binding) |
| Hook C++ virtual functions | **No** | **Yes** (vtable override) |
| Modify function return values | Limited | **Full control** |
| Override BlueprintImplementableEvents | **No** | **Yes** |
| Memory-level function detours | **No** | **Yes** (address hooking) |
| Create UObjects at runtime | Limited | **Yes** |
| Access non-reflected properties | **No** | **Yes** (offset-based) |

### DLL Loading Convention

```
ue4ss/Mods/
└── MyMod/
    ├── dlls/
    │   └── main.dll          <-- MUST be named "main.dll"
    └── enabled.txt           <-- "1" to enable
```

UE4SS discovers and loads `main.dll` from the `dlls/` subfolder. The game waits for all `start_mod()` functions to complete before continuing.

### Mod Lifecycle

```
Game boots → UE4SS loads → start_mod() called → on_unreal_init() fires → hooks registered
                                                                          ↓
                                                              on_update() every frame
                                                                          ↓
                                                              Game exits → uninstall_mod()
```

---

## 3. Project Setup & Build

### Prerequisites

- Visual Studio 2019+ (C++ desktop workload)
- CMake 3.22+
- Git with submodules
- Windows 11

### Directory Structure

```
HarenaCpp/
├── RE-UE4SS/                  (UE4SS framework, cloned as submodule)
├── CMakeLists.txt             (root project)
└── HarenaDamage/
    ├── CMakeLists.txt
    └── dllmain.cpp
```

### Root CMakeLists.txt

```cmake
cmake_minimum_required(VERSION 3.22)
project(HarenaCpp)

add_subdirectory(RE-UE4SS)
add_subdirectory(HarenaDamage)
```

### Per-Mod CMakeLists.txt

```cmake
add_library(HarenaDamage SHARED dllmain.cpp)
include_directories(${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(HarenaDamage UE4SS)
```

### Build Commands

```bash
cmake -B build -G "Visual Studio 17 2022"
cmake --build build --config Game__Shipping__Win64
```

Output: `build/HarenaDamage/Game__Shipping__Win64/HarenaDamage.dll`
Rename to `main.dll` and place in `ue4ss/Mods/HarenaDamage/dlls/main.dll`.

### Template Repos

- **UE4SS-CppModBase:** https://github.com/Dekita/UE4SS-CppModBase (barebones template)
- **DekitaMod:** https://github.com/Dekita/DekitaMod (example with hooks)

---

## 4. Core C++ API Reference

### Essential Includes

```cpp
#include <Mod/CppUserModBase.hpp>
#include <Unreal/UObject/UObject.hpp>
#include <Unreal/Hooks.hpp>
#include <Unreal/Containers/FName.hpp>
```

### Key Namespaces

- `RC` — Core UE4SS namespace
- `RC::Unreal` — Unreal Engine reflection
- `RC::Unreal::Hook` — Function hooking
- `RC::UObjectGlobals` — Object discovery

### Mod Base Class

```cpp
#include <Mod/CppUserModBase.hpp>

using namespace RC;
using namespace RC::Unreal;

class HarenaDamageMod : public CppUserModBase {
public:
    HarenaDamageMod() {
        ModName = STR("HarenaDamage");
        ModVersion = STR("1.0.0");
        ModDescription = STR("Pre-damage friendly fire prevention for Harena CTF");
        ModAuthors = STR("Jacob");
    }

    // Called after Unreal Engine is initialized — safe to access UObjects
    virtual void on_unreal_init() override {
        // Register hooks here
    }

    // Called every frame
    virtual void on_update() override {
        // Per-frame logic (use sparingly)
    }
};

// Required DLL exports
extern "C" {
    DLLEXPORT CppUserModBase* __cdecl start_mod() {
        return new HarenaDamageMod();
    }
    DLLEXPORT void __cdecl uninstall_mod(CppUserModBase* mod) {
        delete mod;
    }
}
```

### Finding Objects

```cpp
// By full path
UObject* obj = UObjectGlobals::StaticFindObject<UObject*>(
    nullptr, nullptr, STR("/Script/Dominion.DamageComponent")
);

// By class
UClass* cls = UObjectGlobals::StaticFindObject<UClass*>(
    nullptr, nullptr, STR("/Script/Dominion.PlayerDamageComponent")
);

// Find function on class
UFunction* func = cls->FindFunctionByName(STR("CanBeDamagedBy"));
```

### Accessing Properties

```cpp
// Read property (searches inheritance chain)
bool* pvpEnabled = obj->GetValuePtrByPropertyNameInChain<bool>(STR("bIsPvpEnabled"));
if (pvpEnabled) {
    *pvpEnabled = false;  // Write directly through pointer
}

// Float property
float* dmgMult = obj->GetValuePtrByPropertyNameInChain<float>(STR("DamageMultiplierMelee"));
```

### Logging

```cpp
Output::send<LogLevel::Verbose>(STR("Hook registered"));
Output::send<LogLevel::Warning>(STR("Something unexpected"));
Output::send<LogLevel::Error>(STR("Hook failed"));

// With formatting
Output::send<LogLevel::Verbose>(std::format(STR("Damage: {}"), amount));
```

---

## 5. Function Hooking (C++ vs Lua)

### Why Lua Hooks Fail on Certain Functions

UE4SS Lua `RegisterHook` only works on **UFunctions** that go through Unreal's `ProcessEvent` dispatch. Many C++ functions in the header dump are:

- **Delegates** (multicast events) — not UFunctions, can't be hooked from Lua
- **BlueprintImplementableEvents** — stubs that the BP class never overrides, so UE4SS can't find them
- **Native C++ calls** — bypass ProcessEvent entirely, invisible to Lua

### C++ Hook Methods

**1. ProcessEvent Pre/Post Callbacks (for UFunctions):**
```cpp
UFunction* func = /* find function */;

// Pre-hook: fires BEFORE function executes, can block/modify params
Unreal::Hook::RegisterProcessEventPreCallback(func,
    [](UObject* obj, UFunction* func, void* params) {
        // Modify params, or block execution
    }
);

// Post-hook: fires AFTER function executes, can modify return values
Unreal::Hook::RegisterProcessEventPostCallback(func,
    [](UObject* obj, UFunction* func, void* params) {
        // Read/modify output params and return value
    }
);
```

**2. Virtual Function Override (for non-UFunction methods):**
```cpp
// Override vtable entry to intercept C++ virtual calls
// This can hook CanBeDamagedBy, ModifyDamage, etc. that Lua can't reach
```

**3. Direct Memory Detour (for any function by address):**
```cpp
// Hook any function by memory address (requires offset from header dump)
// Most powerful but most fragile across game updates
```

### What This Unlocks for Harena

| Function | Lua Result | C++ Capability |
|---|---|---|
| `OnWillReceiveDamageDynamic` | FAILED (delegate) | **Can bind directly** |
| `BP_OnWillReceiveDamage` | Registered, never fired | **Can override as virtual** |
| `CanBeDamagedBy` | Registered, never fired | **Can override return value** |
| `ModifyDamage` | Not hookable | **Can override on DamageModifier** |
| `OnRespawnDynamic` | FAILED (delegate) | **Can bind directly** |
| `OnPlayerLoggedIn/Out` | FAILED (delegate) | **Can bind directly** |
| `OnAuthoritativeHealthChangedDynamic` | FAILED (delegate) | **Can bind directly** |

---

## 6. Damage Pipeline Deep Dive

### Damage Flow (from CXX header analysis)

```
Attacker swings weapon
    ↓
Engine creates FDominionDamageEvent {
    Amount: float,              // 0x0008
    AmountAbsorbedByShield: float,  // 0x000C
    DamageClass: EDamageClass,  // 0x0010 (None/Melee/Magical/Ranged)
    Instigator: AActor*,        // 0x0040
    Source: UObject*,           // 0x0048
    bIsFatalHit: bool,          // 0x00E0
    AttackProperties: int32,    // 0x00B0
    ...
}
    ↓
DamageComponent::CanBeDamagedBy(Instigator)  ← C++ HOOK POINT (return false = block)
    ↓
DamageComponent::CanTakeDamage()  ← C++ HOOK POINT (return false = block)
    ↓
DamageModifiers[] iterated:
    ModifyDamage(amount, damageInfo) → returns multiplied amount  ← C++ HOOK POINT (return 0 = negate)
    ↓
OnWillReceiveDamageDynamic fires  ← C++ DELEGATE BIND POINT (set Amount=0)
BP_OnWillReceiveDamage called     ← C++ VIRTUAL OVERRIDE POINT
    ↓
*** DAMAGE APPLIED TO HEALTH ***
    ↓
OnDamageReceivedDynamic fires     ← ONLY LUA HOOK POINT (too late, damage done)
BP_OnDamageReceived called
OnDamageReceivedDynamic_Event fires (BP path — what Lua currently hooks)
```

### Key Interception Points (C++ Only)

**Point 1: `CanBeDamagedBy(AActor* Instigator)` → return false**
- Earliest possible block
- Has instigator actor for team checking
- Blocks ALL downstream processing (no shield loss, no durability, no flinch)
- Signature: `bool CanBeDamagedBy(const class AActor* Instigator);` (Dominion.hpp:14515)

**Point 2: `ModifyDamage()` on DamageModifier → return 0.0**
- Runs per-modifier, can check instigator from DamageInfo
- Signature: `float ModifyDamage(float InModifiedAmount, const FHealthComponentIncomingDamageInfo& DamageInfo, FGameplayTag& OutOptionalMessageTag);` (Dominion.hpp:14581)
- DamageInfo contains: `UObject* Instigator` (0x0008), `float Amount` (0x0000)

**Point 3: `OnWillReceiveDamageDynamic` delegate → set Amount=0**
- Fires before damage applied
- Receives full FDominionDamageEvent with Instigator
- Signature: `void(AActor* Target, const FDominionDamageEvent& DamageEvent, float DamageTime)` (Dominion.hpp:14493)

### Damage Data Structures

**FDominionDamageEvent** (Dominion.hpp:2114-2140, Size: 0xF0):
```
Offset  Type                    Field
0x0008  float                   Amount
0x000C  float                   AmountAbsorbedByShield
0x0010  EDamageClass            DamageClass (None=0, Melee=1, Magical=2, Ranged=3)
0x0040  AActor*                 Instigator
0x0048  UObject*                Source
0x00B0  int32                   AttackProperties
0x00E0  bool                    bIsFatalHit
```

**FHealthComponentIncomingDamageInfo** (Dominion.hpp:2928-2936, Size: 0x38):
```
Offset  Type        Field
0x0000  float       Amount
0x0008  UObject*    Instigator
0x0010  UObject*    Source
0x0018  FVector     Location
0x0030  int32       AttackProperties
```

### Damage-Related Classes

**UDamageComponent** (Dominion.hpp:14488-14523):
- `TArray<UDamageModifier*> DamageModifiers` (0x0150) — modifier array
- `bool bCanTakeDamage` (0x025B) — master damage toggle
- `bool bCanReceiveCriticalHits` (0x0259)
- `bool bShowDamageFloaties` (0x025A)
- `FDominionDamageEvent LastDamageEvent` (0x0168)
- Functions: `SetCanTakeDamage()`, `CanTakeDamage()`, `CanBeDamagedBy()`, `PredictDamage()`

**UPlayerDamageComponent** extends UDamageComponent (Dominion.hpp:24272-24294):
- `bool bIsPvpEnabled` (0x02F8) — per-player PvP toggle
- `float RespawnInvulnerabilityLength` (0x02FC)
- `FGameplayTag InvulnerableEvadeTag` (0x0300)

**UDamageModifier** (Dominion.hpp:14579-14583):
- `float ModifyDamage(float, FHealthComponentIncomingDamageInfo&, FGameplayTag&)`
- Base class for all damage modification logic

**Damage Attribute Classes** (all inherit UFloatAttribute):
- `UDamageNegationAttribute` (14641) — negate incoming damage
- `UDamageMultiplierAllCombatStylesAttribute` (14625)
- `UDamageMultiplierMeleeAttribute` (14629)
- `UDamageMultiplierMagicAttribute` (14633)
- `UDamageMultiplierRangedAttribute` (14637)
- `UDamageModifierReceiverType[Demon|Mage|Spectral|Undead|Wolf]` (14597-14621)
- `UDamageModifierWeaponType[OneHanded|Staff|TwoHanded]` (14585-14595)

### Invulnerability System

- `GE_Invulnerable_C` — gameplay effect, grants full invulnerability
- `GE_Invulnerable_Evade_C` — invulnerability during evade/dodge
- `domSetInvulnerable(bool)` — cheat manager function (per-player or global TBD)

---

## 7. All Harena Systems — C++ Opportunities

### 7.1 Friendly Fire Prevention

**Current Lua:** `combat.lua` lines 176-214 — `OnDamageReceivedDynamic_Event` hook + `SetHealth` heal
**Limitation:** Post-damage only. Health flickers, shield/armor lost, can't restore durability.
**Stale ref bug:** Handler captures `get_player_team_fn` at init time.

**C++ Solution:** Hook `CanBeDamagedBy(AActor* Instigator)` or bind `OnWillReceiveDamageDynamic` delegate.
- Check if Instigator is player → get team → compare to victim team → return false if same team
- Zero health flicker, zero shield loss, zero durability loss, zero flinch animation

**C++ Signature:**
```cpp
bool UDamageComponent::CanBeDamagedBy(const AActor* Instigator); // Dominion.hpp:14515
```

**Priority: 1 (Critical)** | **Effort: Low** | **Benefit: High**

---

### 7.2 Respawn Detection & Teleport

**Current Lua:** `combat.lua` lines 52-94 — `Multicast_Respawn` hook + 500ms `ExecuteWithDelay`
**Limitation:** 500ms delay is a timing guess, introduces race conditions, doesn't work reliably in Creative mode (8s delay hack).

**C++ Solution:** Bind `URespawnComponent::OnRespawnDynamic` delegate directly.
- Fires immediately on respawn completion
- No delay needed, synchronous

**C++ Signature:**
```cpp
// Delegate at offset 0x00C0
FRespawnComponentOnRespawnDynamic OnRespawnDynamic;
void OnRespawnSignatureDynamic(); // Dominion.hpp ~14400s
```

**Priority: 1 (Critical)** | **Effort: Low** | **Benefit: High**

---

### 7.3 Player Join/Leave Detection

**Current Lua:** `main.lua` lines 79-105 — `LoopAsync(3000)` polling all players via `FindAllOf`
**Limitation:** 3s polling delay, expensive FindAllOf every iteration, no logout detection.

**C++ Solution:** Bind `ADominionGameMode::OnPlayerLoggedIn/Out` delegates.
- Instant detection, proper logout event, controller reference provided

**C++ Signature:**
```cpp
FDominionGameModeOnPlayerLoggedIn OnPlayerLoggedIn;   // 0x0368
void OnPlayerLoggedIn(ADominionPlayerController* Player);

FDominionGameModeOnPlayerLoggedOut OnPlayerLoggedOut;  // 0x0378
void OnPlayerLoggedOut(ADominionPlayerController* Player);
```

**Priority: 2** | **Effort: Low** | **Benefit: Medium**

---

### 7.4 Building Health Regen

**Current Lua:** `buildings.lua` lines 73-102 — `LoopAsync(5000)` polling all HealthComponents, heal to max
**Limitation:** Polls every 5s even when nothing changed, expensive FindAllOf, string-matching exclusion filter ("Bush", "Tree").

**C++ Solution:** Bind `UHealthComponent::OnAuthoritativeHealthChangedDynamic` on building pieces only.
- Event-driven: fires only when health actually changes
- Per-component: only affected buildings trigger handler

**C++ Signature:**
```cpp
// Delegate at offset 0x00E8
FHealthComponentOnAuthoritativeHealthChangedDynamic OnAuthoritativeHealthChangedDynamic;
void OnAuthoritativeHealthChangedSignatureDynamic(float CurrentHealth, float PreviousHealth, float MaxHealth);
```

**Priority: 2** | **Effort: Low** | **Benefit: Medium**

---

### 7.5 Building Demolish Prevention

**Current Lua:** `buildings.lua` lines 206-224 — `Server_Interact` hook detects destroy (type=3), triggers regen
**Limitation:** Can only react after destroy, cannot prevent it. Regen is reactive workaround.

**C++ Solution:** Limited improvement. The demolish action bypasses damage hooks entirely.
- Could try hooking the actual destroy path deeper in C++
- `bCanBeDamaged = false` already prevents damage but not UI demolish
- **Current Lua approach (detect + instant regen) is the best available**

**Priority: 4 (Low)** | **Effort: High** | **Benefit: Low**

---

### 7.6 Flag Pickup/Capture

**Current Lua:** `flags.lua` lines 188-240 — `LoopAsync(500)` polling all players against flag positions
**Limitation:** 500ms polling overhead, distance calculation every cycle for all players.

**C++ Solution:** Bind `UInteractionComponent` events on flag actors.
- `OnShowInteractionPrompt` fires when player enters range
- `OnInteractionEvent` fires on actual interaction

**C++ Signature:**
```cpp
FInteractionComponentOnShowInteractionPrompt OnShowInteractionPrompt; // 0x02B0
void OnInteractionPromptDisplayChange(ADominionPlayerCharacter* Player);

FInteractionComponentOnInteractionEvent OnInteractionEvent;           // 0x0260
void OnInteraction(ADominionPlayerCharacter* Player);
```

**Risk:** Need to verify InteractionComponent can be attached to spawned flag actors.

**Priority: 2** | **Effort: Medium** | **Benefit: High**

---

### 7.7 Powerup Pickup

**Current Lua:** `powerups.lua` lines 275-358 — `LoopAsync(1000)` polling all players against powerup positions
**Limitation:** 1s polling overhead, could miss pickups in edge cases.

**C++ Solution:** Same InteractionComponent approach as flags.

**Priority: 2** | **Effort: Medium** | **Benefit: Medium**

---

### 7.8 PvE Mob Spawning

**Current Lua:** `pve.lua` lines 36-57 — `StaticFindObject` class lookup + `world:SpawnActor()`
**Limitation:** Two-step process, expensive class path lookup.

**C++ Solution:** Use cheat manager `domSpawnAi(name, x, y, z, level)` — single call with power level.

**C++ Signature:**
```cpp
void domSpawnAi(FString AIClass, float LocationX, float LocationY, float LocationZ, int32 Level);
```

**Risk:** Need to test if accepts short names ("Wolf") or full paths.

**Priority: 3** | **Effort: Low** | **Benefit: Medium**

---

### 7.9 Scoreboard Updates

**Current Lua:** `scoreboard.lua` lines 69-129 — `LoopAsync(1000)` updates ModActor variables
**Limitation:** Polls every 1s even when nothing changed.

**C++ Solution:** Event-driven updates from Lua side (on kill, flag cap, death events). No C++ needed.

**Priority: 3 (Lua fix)** | **Effort: Low** | **Benefit: Low**

---

### 7.10 Team/Class Selection Proximity

**Current Lua:** `match.lua` / `teams.lua` — `LoopAsync(500)` polling against lodestone positions
**Limitation:** 500ms polling, distance checks per player per lodestone.

**C++ Solution:** InteractionComponent events on lodestone actors (same approach as flags).

**Priority: 3** | **Effort: Medium** | **Benefit: Medium**

---

### 7.11 Flag Carrier Movement Slow

**Current Lua:** `flags.lua` lines 115-124 — `SetMaxStamina(0)` blocks sprint only
**Limitation:** Carrier can still walk at full speed.

**C++ Solution:** Write `MovementSpeedMultiplier` attribute directly.

**C++ Signature:**
```cpp
float MovementSpeedMultiplier;  // offset 0x101C on DominionPlayerCharacter
```

Could also be done from Lua (test if writable). Set to 0.7 for flag carriers.

**Priority: 3** | **Effort: Low** | **Benefit: Low**

---

### 7.12 Assassin Stealth (Powerup Buff)

**Current Lua:** `powerups.lua` lines 185-197 — `PlayDespawnVFX()` fake invisibility
**Limitation:** Visual only, AI still sees player.

**C++ Solution:** Use `UPlayerStealthComponent::Multicast_EnterStealth()` for real stealth.

**C++ Signature:**
```cpp
class UPlayerStealthComponent : public UActorComponent
// Delegates:
FPlayerStealthComponentBP_OnEnteredStealthDelegate BP_OnEnteredStealthDelegate;
FPlayerStealthComponentBP_OnExitedStealthDelegate BP_OnExitedStealthDelegate;
```

**Priority: 3** | **Effort: Low** | **Benefit: High (gameplay)**

---

### 7.13 Spawn Protection

**Current Lua:** Timing-based (8s delay post-respawn)
**Limitation:** Not proper invulnerability, timing-based.

**C++ Solution:** `domSetInvulnerable(true)` during spawn window, or leverage `RespawnInvulnerabilityLength` property on `PlayerDamageComponent`.

**Priority: 3** | **Effort: Low** | **Benefit: Low**

---

### 7.14 Inventory Batch Operations

**Current Lua:** Individual `AddItemByData` calls with 500ms stagger delays
**Limitation:** Race conditions, crashes from overflow, slow equip sequences.

**C++ Solution:** `AddItemsByData(TArray<ItemData*>, TArray<int32>, durability, tags)` — batch add.

**Priority: 3** | **Effort: Medium** | **Benefit: Medium**

---

### 7.15 PvP Kill Attribution

**Current Lua:** `combat.lua` — reads `LastDamageEvent.Instigator` from death hook
**Limitation:** Works but is post-facto. Misattributes DOT/fall damage kills.

**C++ Solution:** Hook the actual kill event at a deeper level to get precise instigator.
- `UHealthComponent::OnAuthoritativeHealthChangedDynamic` with health <= 0 check
- Or `FFatalDamageInfo` struct on DamageComponent (offset 0x02C8)

**Priority: 3** | **Effort: Medium** | **Benefit: Low**

---

### 7.16 Damage Multipliers (Class Balancing)

**Current Lua:** All classes deal same base damage.

**C++ Solution:** Per-player writable attributes:
- `UDamageMultiplierMeleeAttribute` — Berserker/Guardian boost
- `UDamageMultiplierMagicAttribute` — Fire Mage/Air Mage boost
- `UDamageMultiplierRangedAttribute` — Archer boost
- `UDamageMultiplierAllCombatStylesAttribute` — global multiplier

**Priority: 4** | **Effort: Low** | **Benefit: Medium (balancing)**

---

### 7.17 Infinite Stamina / No Magic Cost

**Current Lua:** Not using cheat manager functions (manages runes via inventory).

**C++ Solution:**
- `domInfiniteStamina(true)` — unlimited stamina during match
- `domNoMagicCost(true)` — free spells

**Risk:** May be global (all players) rather than per-player. Needs testing.

**Priority: 4** | **Effort: Low** | **Benefit: Low**

---

### 7.18 Mob Respawn Monitoring

**Current Lua:** `pve.lua` lines 137-218 — `LoopAsync(3000)` polling mob alive status
**Already has:** `BP_OnDeath` hook in combat.lua

**C++ Solution:** Already event-driven via death hook. The 3s respawn loop is for respawn timing, not detection. Keep as-is.

**Priority: 5 (No change needed)**

---

### 7.19 PvP Toggle (Match Phase)

**Current Lua:** `combat.lua` lines 258-271 — Sets `bIsPvpEnabled` per player
**Limitation:** None — already works correctly via direct property write.

**C++ Solution:** No improvement needed. Keep Lua approach.

**Priority: 5 (No change needed)**

---

### 7.20 Bed Claiming

**Current Lua:** `buildings.lua` lines 49-71 — Calls `BedComponent:Claim(player)` directly
**Limitation:** None — already using native API correctly.

**C++ Solution:** No improvement needed.

**Priority: 5 (No change needed)**

---

## 8. Priority Matrix

### Tier 1 — Critical (High Impact, C++ Required)

| # | System | C++ Hook/Function | Benefit |
|---|---|---|---|
| 7.1 | **Friendly Fire** | `CanBeDamagedBy` override OR `OnWillReceiveDamageDynamic` delegate | Eliminates health flicker, shield/armor loss, durability drain |
| 7.2 | **Respawn Teleport** | `OnRespawnDynamic` delegate | Eliminates 500ms delay hack, works in all modes |

### Tier 2 — High Value (Removes Polling Loops)

| # | System | C++ Hook/Function | Benefit |
|---|---|---|---|
| 7.3 | **Player Join/Leave** | `OnPlayerLoggedIn/Out` delegates | Removes 3s polling, instant detection |
| 7.4 | **Building Health** | `OnAuthoritativeHealthChangedDynamic` delegate | Removes 5s polling, event-driven regen |
| 7.6 | **Flag Pickup** | `InteractionComponent` events | Removes 500ms polling, instant detection |
| 7.7 | **Powerup Pickup** | `InteractionComponent` events | Removes 1s polling |

### Tier 3 — Nice to Have (Gameplay Improvements)

| # | System | C++ Hook/Function | Benefit |
|---|---|---|---|
| 7.8 | **PvE Spawning** | `domSpawnAi()` | Cleaner single-call spawn |
| 7.10 | **Team/Class Select** | `InteractionComponent` events | Removes 500ms polling |
| 7.11 | **Carrier Slow** | `MovementSpeedMultiplier` | Proper speed reduction |
| 7.12 | **Assassin Stealth** | `PlayerStealthComponent` | Real stealth (AI-aware) |
| 7.13 | **Spawn Protection** | `domSetInvulnerable` | Proper invulnerability |
| 7.14 | **Batch Inventory** | `AddItemsByData` | Faster equip, fewer crashes |

### Tier 4 — Future / Optional

| # | System | C++ Hook/Function | Benefit |
|---|---|---|---|
| 7.15 | **Kill Attribution** | `FFatalDamageInfo` | Better kill tracking |
| 7.16 | **Damage Multipliers** | Float attributes | Class balancing |
| 7.17 | **Infinite Stamina** | Cheat manager functions | Simpler resource management |

### No Change Needed

- 7.5 Building Demolish (Lua approach optimal)
- 7.9 Scoreboard (Lua event-driven fix)
- 7.18 Mob Respawn (already event-driven)
- 7.19 PvP Toggle (already works)
- 7.20 Bed Claiming (already works)

---

## 9. Testing Checklist

Before implementing C++ hooks, these need verification:

### Damage System
- [ ] Can `CanBeDamagedBy` return value be overridden from C++ ProcessEvent hook?
- [ ] Does `OnWillReceiveDamageDynamic` delegate fire before damage is applied?
- [ ] Can `FDominionDamageEvent.Amount` be modified in pre-damage delegate?
- [ ] Does blocking `CanBeDamagedBy` prevent shield/armor loss?
- [ ] Does blocking `CanBeDamagedBy` prevent hit reaction animation?

### Delegates
- [ ] Can C++ mod bind to `OnRespawnDynamic` multicast delegate?
- [ ] Can C++ mod bind to `OnPlayerLoggedIn/Out` multicast delegates?
- [ ] Can C++ mod bind to `OnAuthoritativeHealthChangedDynamic`?
- [ ] Do delegate bindings survive hot-reload?

### InteractionComponent
- [ ] Can InteractionComponent be attached to spawned flag actors from C++?
- [ ] Does `OnShowInteractionPrompt` fire for dynamically created components?
- [ ] Can interaction range be configured per-component?

### Cheat Manager
- [ ] `domSpawnAi` — accepts short names or full paths?
- [ ] `domNoMagicCost` — per-player or global?
- [ ] `domInfiniteStamina` — per-player or global?
- [ ] `domSetInvulnerable` — per-player or global?

### Properties
- [ ] `MovementSpeedMultiplier` — writable from Lua? (if yes, no C++ needed)
- [ ] `UDamageNegationAttribute` — writable per-player? What value blocks all damage?
- [ ] `PlayerStealthComponent::Multicast_EnterStealth` — callable from Lua?

---

## 10. Resources & References

### Official Documentation
- UE4SS Docs: https://docs.ue4ss.com/
- C++ API Reference: https://docs.ue4ss.com/cpp-api.html
- Creating a C++ Mod: https://docs.ue4ss.com/guides/creating-a-c++-mod.html
- Installing a C++ Mod: https://docs.ue4ss.com/guides/installing-a-c++-mod.html
- Accessing UE Properties (C++): https://docs.ue4ss.com/dev/guides/accessing-ue-properties-c++.html

### GitHub
- UE4SS Source: https://github.com/UE4SS-RE/RE-UE4SS
- CppModBase Template: https://github.com/Dekita/UE4SS-CppModBase
- DekitaMod Example: https://github.com/Dekita/DekitaMod
- Build Guide: https://github.com/modestimpala/UE4SS-Build-Guide

### Community
- UE4SS DeepWiki: https://deepwiki.com/UE4SS-RE/RE-UE4SS/11-tutorials-and-guides
- Version Compatibility: https://deepwiki.com/UE4SS-RE/RE-UE4SS/12.3-version-compatibility-guide

### Local Files
- CXX Header Dump: `ue4ss/CXXHeaderDump/Dominion.hpp` (30,977 lines)
- Enums: `ue4ss/CXXHeaderDump/Dominion_enums.hpp`
- UE4SS Config: `ue4ss/UE4SS-settings.ini`
- Harena Source: `ue4ss/Mods/Harena/scripts/` (14 files)
- Architecture Doc: `C:\Users\Jacob\ctf_v2_architecture.md`
- Optimization Tasks: `C:\Users\Jacob\ctf_optimisation_tasks.md`
