# CTF Mod — Complete Feature Rollout

## Core Systems (All Built & Functional)

### 1. Match Flow (F5)
- **Phases**: idle → lobby → class_select → countdown → active → ended
- **Lobby**: 60s team/class selection via lodestone proximity
- **Countdown**: 10s with per-second chat display
- **Match**: 15-minute timer, synced to HUD
- **Lines**: 4706-5083

### 2. Team System
- Auto-balanced team assignment (red/blue)
- Team colors (red RGB, blue RGB)
- Team spawn positions (red: 130710,-41007,-7093 | blue: 131130,-39181,-7270)
- Lodestone-based selection with 3.5s cooldown
- **Lines**: 615-632, 713-749, 999-1013

### 3. Class System (6 Classes)
| Class | Spell | Ammo |
|-------|-------|------|
| Archer | Snare (Astral+Nature) | Tiered arrows |
| Assassin | Enchant Air (Air+Astral) | — |
| Guardian | Tempest Shield (Air) | — |
| Berserker | Enchant Fire (Fire+Astral) | — |
| Fire Mage | Surge (Astral+Law) | Fire runes (2000) |
| Air Mage | Surge (Astral+Law) | Air runes (2000) |

- Class preview at lodestones (T6 gear)
- Full loadout equip pipeline (armor + weapons + cape + runes)
- **Lines**: 824-928, 1246-1388

### 4. PvP Kill Tracking & Progression
- Kill attribution via `LastDamageEvent.Instigator`
- Kill feed with team colors ("PlayerA defeated PlayerB")
- Per-player: kills, deaths tracked
- **Specialization**: 3 personal kills → T3 class gear + runes
- **Weapon tiers**: 12/24/36 team PvP kills → T4/T5/T6 weapons
- **Trinket**: 12 personal PvP kills → class-specific amulet/ring
- **Cape upgrades**: Adventurer → Dyad → Hex → Skillcape
- **Lines**: 4206-4440, 930-937

### 5. PvE Events (3 Tiers)
| Event | Power Level | Wolves | Archers | Mages | Tanks | Boss | Reward |
|-------|-------------|--------|---------|-------|-------|------|--------|
| 1: Garou Assault | 4 | 12 wolf | 6 garou_hunter | 6 garou_druid | 3 garou_berserker | 1 abyssal_demon | T4 armor |
| 2: Rotsworn Invasion | 5 | 12 dragonwolf | 6 skeletal_archer | 6 rotsworn_necromancer | 3 rotsworn_marauder | 1 zogre | T5 armor |
| 3: Dark Siege | 6 | 12 hellhound | 6 blackknight_ranged | 6 mage_of_zamorak | 3 blackknight_2h | 1 dragon_blue | T6 armor |

- Role-based kill caps (wolf:10, archer:4, mage:4, tank:2, boss:1)
- Mob respawning on timers (5s-30s per role)
- Per-team independent tracking
- Auto-promote unspecialized players on completion
- Staggered mob destruction on event clear (250ms/mob)
- PvE auto-starts 60s after match GO
- **Lines**: 1858-2470

### 6. Friendly Fire Prevention
- `OnDamageReceivedDynamic_Event` hook (must register via Numpad 8)
- Same-team hit → `SetHealth(cur + amount, "Heal")` → damage negated
- Death hook backup: prevent kill attribution + revive on same-team kill
- **Lines**: 511-531, 4364-4393

### 7. Respawn System
- Death detected via `OnPlayerDeath` hook
- 15s respawn timer (10s wait + 5s countdown)
- Teleport to team spawn with offset
- `PlayRespawnVFX()` visual effect
- Only during active match
- **Lines**: 4400-4438

### 8. HUD / Scoreboard (.pak mod)
- **Score bar** (always visible after F5): Red score | Timer | Blue score
- **Stats panel** (Caps Lock toggle): 6 player rows × 5 columns
  - NAME, CLASS, KILLS, DEATHS, FLAGS
  - Red-shaded rows (3) + Blue-shaded rows (3)
  - Divider lines between rows
- **30 ModActor variables** updated every 1000ms via LoopAsync
- Font: BonaNovaSC-Bold (matches RS style)
- StatsPanel hidden by default, toggled via Caps Lock
- **Files**: WBP_CTFScoreboard + ModActor in .pak

### 9. Equip Pipeline
- `equip_loadout()`: Safe staggered equip (clear → 500ms → add items)
- Per-player variants: `unlock_inv_for()`, `clear_all_for()`, `add_to_loadout_for()`
- Lock/unlock inventory controls
- **Lines**: 51-122, 1246-1276

### 10. PvP Setup (Numpad 9)
- Enable damage floaties (`bShowDamageFloaties = true`)
- Hide nametags (`SetVisibility(false)`)
- Hide compass/map icons (`CaptureAreaSize = 0`)
- **Lines**: 4084-4203

### 11. Windstep Blocking
- Block: Set Windstep cooldown to 9999s (prevents teleport spam)
- Unblock: Restore original cooldown on reset
- **Lines**: 1368-1388

### 12. Asset Preloading
- 47 mob classes loaded via LoadAsset on startup
- Ambush raid assets force-loaded
- 3000ms discovery scanner caches live instances
- Building subsystem auto-enabled
- **Lines**: 5132-5275

---

## FULLY IMPLEMENTED (as of 2026-04-07)

### Flag/CTF Mechanics — WORKING
- Colored torches (red/blue) at team bases
- Proximity pickup (500u) → torch equip + inventory lock + sprint block
- Capture at own base → score + re-equip class gear + flag reset
- Carrier death → flag returns to enemy base
- Scoreboard shows captures (top bar + per-player flags column)

### Wild Anima Powerups — INTEGRATED
- 3 spawn positions in arena center
- Proximity pickup (250u) → class-specific buff + green glitter VFX
- 45s duration, 120s respawn
- Class buffs: Archer=ammo upgrade, Assassin=invisibility, Guardian=+50HP, Berserker=weapon upgrade, Mages=+30HP
- **TODO**: Test class-specific effects in live match

### Win Condition — WORKING
- Most captures when 15min timer ends
- Winner announcement + final score
- 5s delay → all players teleported to bed lobby

### Match Flow (F3) — WORKING
- F3 → team selection (3 zones: red/blue/random, 3-player cap)
- Team assigned → teleported to team class lobby
- Class selection via team-specific lodestones (T6 preview)
- 60s lobby timer → base kit equip → 10s countdown → arena teleport
- Flags + powerups spawn 2s after GO

### Building Protection — WORKING
- bCanBeDamaged=false on all BaseBuilding actors
- Continuous heal loop (every 5s) on all HealthComponents except trees/mobs/players
- Mannequin inventory locked

### Spawn System — WORKING
- Fixed initial spawns per team (7 positions)
- Random respawns (17-18 positions per team)
- Facing direction + camera snap via K2_SetActorLocationAndRotation
- Invulnerable during respawn wait

### PvE Events — IMPLEMENTED
- 3 events with interleaved spawning
- Per-team spawn areas (diamond + alleyways)
- Per-team kill tracking: mobs stop respawning on YOUR side when YOUR team kills them
- Auto-start at 3:30 intervals (Event 1 at 3:30, Event 2 at 7:00, Event 3 at 10:30)
- Kill req: wolf:10, archer:4, mage:4, tank:2, boss:1
- Completion → armor tier upgrade + cape upgrade for whole team
- Auto-promote unspecialized players on PvE completion

### PvP Progression — WIRED INTO MULTIPLAYER
- 3 personal kills → Specialization (T3 class gear + runes)
- 12 personal kills → Trinket
- 12/24/36 team PvP kills → Weapon tier T4/T5/T6 for whole team
- Auto-promote at 12 team kills
- All triggered from multiplayer death hook (not F5 debug)

---

## Admin Keybinds (Host Controls)

| Key | Function | Category |
|-----|----------|----------|
| F1 | Scan all players | Debug |
| F2 | Teleport all to host | Admin |
| F3 | Spawn lodestones | Setup |
| F4 | Show coordinates | Debug |
| F5 | **START MATCH** | **Core** |
| F6 | Quick lobby | Setup |
| F7 | Start next PvE event | Admin |
| F8 | Kill all nearby mobs | Admin |
| F9 | Give class runes | Admin |
| F10 | Scan nearest mob | Debug |
| F11 | Quick team select | Setup |
| F12 | Building export | Debug |
| Numpad 0 | Full reset | Admin |
| Numpad 2 | Probe mob stats | Debug |
| Numpad 3-5 | Spawn tier 1/2/3 mobs | Debug |
| Numpad 6-7 | Spawn specific mobs | Debug |
| Numpad 8 | Register FF prevention | Setup |
| Numpad 9 | PvP setup (floaties/nametags) | Setup |
| Caps Lock | Toggle scoreboard panel | Player |
| 0 (Zero) | Full reset | Admin |

---

## File Inventory

| File | Location | Purpose |
|------|----------|---------|
| test_apis.lua | ue4ss/Mods/CTFDiscovery/scripts/ | Main mod (5477 lines) |
| main.lua | ue4ss/Mods/CTFDiscovery/scripts/ | Loader (requires test_apis) |
| CTFScoreboard.pak | Content/Paks/LogicMods/ | Widget .pak (11MB) |
| CTFScoreboard.ucas | Content/Paks/LogicMods/ | Widget container (293MB) |
| CTFScoreboard.utoc | Content/Paks/LogicMods/ | Widget TOC (236KB) |
| ModActor | UE Project: Content/Mods/CTFScoreboard/ | Actor with 33+ String vars |
| WBP_CTFScoreboard | UE Project: Content/Mods/CTFScoreboard/ | Widget Blueprint |
| building_export.txt | ue4ss/Mods/CTFBuildingTool/ | Arena export (10,734 pieces) |
| building_export_golden.txt | RSDragonwilds-Server/ | Golden backup of export |
| Dominion.hpp | ue4ss/CXXHeaderDump/ | Full C++ header dump (Ctrl+H) |

---

## CXX Header Dump Discoveries (2026-04-08)

### Building System — Server_SpawnBuilding (PERSISTENT)
```lua
local bmc = controller.BuildModeComponent
bmc:Server_SpawnBuilding(dataIndex, {
    Rotation = {W=qw, X=qx, Y=qy, Z=qz},
    Translation = {X=x, Y=y, Z=z},
    Scale3D = {X=1, Y=1, Z=1},
}, false, {})
```
- Creates properly registered pieces that survive restarts
- `BuildingPieceDataIndex` per piece type (e.g. 187 = T3_Foundation_Large)
- Must disable stability first for unsupported pieces
- Export/import pipeline: Num1 export → Num0 import (20 pieces/sec)

### Bed Claiming — BedComponent:Claim (NOW WORKS)
```lua
bedComp:Claim(player)                 -- claim for player
bedComp:IsClaimedByPlayer(player)     -- check
bedComp:IsClaimedByAnyPlayer()        -- check any
bedComp:GetClaimingCharacterName()    -- get name
bedComp:Sleep(player)                 -- force sleep
bedComp:CanSleep(player)              -- check
bedComp.bRequiresClaimingToSleepIn = false  -- disable requirement
```

### DominionCheatManager — Key Native Functions
| Function | Use Case |
|----------|----------|
| `domSpawnAi(name, x, y, z, level)` | Mob spawn without class loading |
| `domNoMagicCost(true)` | Free spells |
| `domSetPvpEnabled(true)` | PvP toggle |
| `domSetInvulnerable(true)` | God mode |
| `domSetIgnoredByAi(true)` | AI ignores player |
| `domTogglePlayerVisibility()` | Hide/show player |
| `domInfiniteStamina(true)` | No stamina drain |
| `domNoUtilityMagicCooldown(true)` | No spell cooldowns |
| `domOverrideWeaponDamagesAmount(true, amt)` | Override weapon damage |
| `domAddItem(name, count, durability)` | Add item by name |
| `domLoadBuildingsFromFile(name)` | Load buildings from file |
| `domBuildingIgnoreMaterialRequirements(true)` | Free building |
| `domQuickSave()` / `domSaveBuildings("")` | Force save |

### Event-Driven Architecture (Replaces LoopAsync Polling)

**Respawn (FIXES Creative mode 8s delay hack):**
- `URespawnComponent::OnRespawnDynamic` — fires on ALL respawns, any mode
- `UPlayerRespawnComponent::Multicast_Respawn(FVector, FRotator)` — exact position

**Friendly Fire (FIXES SetHealth hack):**
- `UDamageComponent::OnWillReceiveDamageDynamic` — fires BEFORE damage applied
- Can set damage to 0 for same-team targets

**Player Join/Leave:**
- `ADominionGameMode::OnPlayerLoggedIn(controller)`
- `ADominionGameMode::OnPlayerLoggedOut(controller)`

**Inventory Changes:**
- `UInventoryComponent::OnInventoryChanged` — exact add/remove/change arrays
- `AddItemsByData()` / `RemoveItemsByData()` — batch operations (safer than individual calls)

**Health Changes:**
- `UHealthComponent::OnAuthoritativeHealthChangedDynamic` — server-side health events
- `UHealthComponent::OnDeathDynamic` — death event

**Interaction/Proximity:**
- `UInteractionComponent::OnShowInteractionPrompt` — player enters range
- `UInteractionComponent::OnHideInteractionPrompt` — player leaves range
- `UInteractionComponent::OnInteractionEvent` — player interacts

**Gameplay Event System:**
- `ListenForGameplayEventOnActor(actor, callback, eventTag)` — subscribe to events
- `BroadcastCombatGameplayEventOnActor(actor, tag, source, target)` — broadcast

### Per-Player Attributes (Writable)
| Attribute | Type |
|-----------|------|
| `DamageMultiplierAllCombatStylesAttribute` | Float |
| `DamageMultiplierMeleeAttribute` | Float |
| `DamageMultiplierMagicAttribute` | Float |
| `DamageMultiplierRangedAttribute` | Float |
| `MovementSpeedMultiplier` | Float |
| `CombatModeMovementSpeedMultiplier` | Float |
| `CombatModeSprintSpeedMultiplier` | Float |

### Player Stealth
```lua
stealth:Multicast_EnterStealth()   -- enter stealth
stealth:Multicast_ExitStealth()    -- exit stealth
stealth:IsInStealth()              -- check
```
