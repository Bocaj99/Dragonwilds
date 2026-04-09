# CTF Mod v2.0 — Architecture Plan

## Why Rewrite
- v1 (test_apis.lua): 5,500+ lines, 29 LoopAsync polling loops, multiple hacks
- v2: Event-driven, modular files, native API calls, half the code, fewer crashes

## Module Structure

```
ue4ss/Mods/CTFv2/scripts/
  main.lua           -- Entry point, startup, keybinds
  config.lua         -- All coordinates, timings, class definitions, constants
  events.lua         -- Event bus (register/fire/listen pattern)
  teams.lua          -- Team assignment, lodestone interaction, auto-balance
  classes.lua        -- 6 class definitions, loadout equip pipeline
  match.lua          -- State machine (idle → lobby → countdown → active → ended)
  combat.lua         -- FF prevention (OnWillReceiveDamage), kill tracking, death/respawn
  flags.lua          -- Flag spawn/pickup/capture/return (InteractionComponent events)
  pve.lua            -- PvE events, mob spawning (domSpawnAi), kill caps, rewards
  powerups.lua       -- Wild Anima spawns, class buffs, movement speed, stealth
  progression.lua    -- Specialization, weapon tiers, trinkets, cape upgrades
  buildings.lua      -- Protection (bCanBeDamaged), bed claiming, stability disable
  scoreboard.lua     -- ModActor variable updates (event-driven, not polling)
  ui.lua             -- Chat messaging, announcements
  admin.lua          -- Host keybinds (F-keys), debug commands
```

## Core Architecture Changes

### 1. Event Bus (events.lua)
Central pub/sub system replacing LoopAsync polling:
```lua
local Events = {}
Events.listeners = {}
function Events.on(event, callback) ... end
function Events.fire(event, data) ... end
-- Usage: Events.on("player_killed", function(data) ... end)
```

### 2. Native Event Hooks (registered once in main.lua)
Replace 29 LoopAsync loops with ~8 native hooks:
| Hook | Replaces |
|------|----------|
| OnRespawnDynamic | 8s delay hack from death hook |
| OnWillReceiveDamageDynamic | SetHealth FF hack |
| OnPlayerLoggedIn/Out | Player count polling |
| OnAuthoritativeHealthChanged | Building heal polling |
| OnInventoryChanged | Inventory tracking |
| OnInteractionEvent | Proximity polling for lodestones/flags/powerups |
| BP_OnDeath (AI) | Mob kill detection (keep — already works) |
| OnPlayerDeath | Player death (keep — already works) |

### 3. Cheat Manager Integration
Replace complex workarounds with single calls:
| Old Approach | New Approach |
|---|---|
| StaticFindObject + SpawnActor for mobs | domSpawnAi(name, x, y, z, level) |
| Give 2000 runes per spell type | domNoMagicCost(true) |
| PlayDespawnVFX for invisibility | Multicast_EnterStealth() |
| Custom invulnerability | domSetInvulnerable(true/false) |
| Stagger AddItemByData calls | AddItemsByData() batch |
| Manual stability disable code | domBuildingTickStability(false) |

### 4. State Machine (match.lua)
Clean state machine with event-driven transitions:
```
States: idle → lobby → class_select → countdown → active → ended
Transitions triggered by events, not polling loops
Timer: single LoopAsync(1000) for match clock (only loop needed)
```

### 5. Remaining LoopAsync (minimal)
Only 3-4 loops needed:
- Match timer tick (1000ms) — during active match only
- Scoreboard refresh (2000ms) — during active match only  
- Mob scanner (3000ms) — startup only, stops after initial scan
- PvE auto-spawner (configurable) — during PvE events only

All with is_world_valid() guard.

## Config-Driven Design (config.lua)
All magic numbers extracted to one file:
- Arena coordinates (red base, blue base, spawns, lobby, platform)
- Class definitions (weapons, armor, spells, per tier)
- PvE event definitions (mob types, counts, power levels, rewards)
- Timings (match length, respawn delay, countdown, cooldowns)
- Distances (pickup radius, capture radius, lodestone range)

## Migration Path
1. Build v2 as separate mod (CTFv2) alongside existing CTFDiscovery
2. Test each module independently
3. Switch mods.txt from CTFDiscovery to CTFv2 when ready
4. Keep CTFDiscovery as backup

## Open Questions
- domSpawnAi: Does the FString param match class short name ("Wolf") or full path?
- domNoMagicCost: Per-player or global?
- domSetPvpEnabled: Per-player or global? Does it work with teams?
- domSetInvulnerable: Per-player or global?
- InteractionComponent: Can we attach to spawned actors (flags, powerups)?
- OnWillReceiveDamageDynamic: Can we modify DamageEvent from Lua? Does it prevent armor durability loss?
- OnRespawnDynamic: Does it fire on both server and client?
- Batch AddItemsByData: Does it reduce crash risk vs individual calls?

## Estimated Scope
- ~14 modules, ~2000-3000 lines total (vs 5500+ in v1)
- Each module: 100-300 lines, single responsibility
- Testing: module by module, verify each hook before building on it
