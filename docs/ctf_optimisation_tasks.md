# CTF Mod — Optimisation Task List
## Based on CXX Header Dump Discoveries (2026-04-08)

---

## Priority 1: Critical Fixes (Replace Hacks)

### [ ] 1.1 Replace Respawn Delay Hack with OnRespawnDynamic
- **Current:** Death hook → 8s `ExecuteWithDelay` guess
- **New:** Hook `URespawnComponent::OnRespawnDynamic` — fires on ALL respawns, any mode
- **Also:** `UPlayerRespawnComponent::Multicast_Respawn(FVector, FRotator)` gives exact position
- **Impact:** Fixes Creative mode respawn detection, eliminates timing guesses
- **Risk:** Low — additive change, can keep old hack as fallback

### [ ] 1.2 Replace Friendly Fire SetHealth Hack with OnWillReceiveDamageDynamic
- **Current:** `OnDamageReceivedDynamic_Event` hook → `SetHealth(cur + amount)` to undo damage
- **New:** Hook `UDamageComponent::OnWillReceiveDamageDynamic` — fires BEFORE damage applied
- **Action:** Set `DamageEvent.Damage = 0` for same-team targets (check if this affects armor durability too)
- **Impact:** No more heal hack, cleaner damage prevention
- **Risk:** Low — test if DamageEvent struct is writable from Lua

### [ ] 1.3 Implement Bed Claiming via BedComponent:Claim(player)
- **Current:** "NOT possible from Lua" — manual claim only
- **New:** `bedComp:Claim(player)` — programmatic claim
- **Also:** `IsClaimedByPlayer(player)`, `GetClaimingCharacterName()`, `CanSleep(player)`
- **Impact:** Auto-claim beds per team during match setup
- **Risk:** Medium — test on multiplayer (untested)

---

## Priority 2: Performance (Replace LoopAsync Polling)

### [ ] 2.1 Replace Player Join/Leave Polling with GameMode Events
- **Current:** `FindAllOf("BP_PlayerCharacter_C")` polling
- **New:** `ADominionGameMode::OnPlayerLoggedIn(controller)` / `OnPlayerLoggedOut(controller)`
- **Impact:** Instant player detection, removes 1 polling loop

### [ ] 2.2 Replace Health Polling with OnHealthChanged Delegate
- **Current:** Building heal loop polls all HealthComponents every 5s
- **New:** `UHealthComponent::OnAuthoritativeHealthChangedDynamic` — only fires when health changes
- **Impact:** Zero overhead when buildings aren't being attacked

### [ ] 2.3 Replace Proximity Polling with InteractionComponent Events
- **Current:** LoopAsync 500ms distance checks for lodestones, flags, powerups
- **New:** `UInteractionComponent::OnShowInteractionPrompt` (enters range) + `OnInteractionEvent` (interacts)
- **Impact:** Removes 3-5 polling loops, instant detection
- **Risk:** Medium — need to verify InteractionComponent can be attached to spawned actors

### [ ] 2.4 Replace Scoreboard Polling with Event-Driven Updates
- **Current:** LoopAsync 1000ms updates 30 ModActor variables
- **New:** Update scoreboard only when events fire (kill, death, capture, timer tick)
- **Impact:** Reduces constant polling to event-triggered updates

### [ ] 2.5 Use Batch Inventory Operations
- **Current:** Individual `AddItemByData` calls with 500ms stagger delays
- **New:** `AddItemsByData(TArray<ItemData*>, TArray<int32>, durability, tags)` — single batch call
- **Impact:** Fewer crash opportunities, faster equip, less stagger needed

---

## Priority 3: New Capabilities (from Header Dump)

### [ ] 3.1 Use domSpawnAi for PvE Mob Spawning
- **Current:** `StaticFindObject` + `SpawnActor` — requires class loading, template cages
- **New:** `domSpawnAi("Wolf", x, y, z, level)` — spawn by name, no class loading
- **Impact:** Removes mob cage dependency, simpler spawn code
- **Risk:** Low — test parameter format (FString AIClass name)

### [ ] 3.2 Use domNoMagicCost for Free Spells During Match
- **Current:** Give players 2000 runes per spell type
- **New:** `domNoMagicCost(true)` — all spells free
- **Impact:** Simpler, no rune inventory management
- **Risk:** Low — test if per-player or global

### [ ] 3.3 Use domSetPvpEnabled for Clean PvP Toggle
- **Current:** Manual friendly fire prevention via damage hook
- **New:** `domSetPvpEnabled(true/false)` — native PvP toggle
- **Impact:** Could replace entire FF system if it works per-team
- **Risk:** Medium — may be global only (all PvP or none), test first

### [ ] 3.4 Use Damage Multiplier Attributes for Class Balancing
- **Current:** All classes use same base damage
- **New:** Per-player `DamageMultiplierMeleeAttribute`, `DamageMultiplierMagicAttribute`, etc.
- **Impact:** Fine-tune class damage (berserker +20% melee, mage +15% magic, etc.)
- **Risk:** Low — test if writable and per-player

### [ ] 3.5 Use MovementSpeedMultiplier for Flag Carrier Slow
- **Current:** Sprint block only via inventory lock
- **New:** `player.MovementSpeedMultiplier = 0.7` — direct speed reduction
- **Impact:** Carrier walks slower, not just sprint-blocked
- **Risk:** Low — test if writable

### [ ] 3.6 Use PlayerStealthComponent for Assassin Powerup
- **Current:** `PlayDespawnVFX` → `PlayRespawnVFX` for invisibility
- **New:** `stealth:Multicast_EnterStealth()` / `Multicast_ExitStealth()` — proper stealth system
- **Impact:** Native stealth with proper AI interaction (AI can't see stealthed player)
- **Risk:** Low — test visual effect

### [ ] 3.7 Use domSetInvulnerable for Spawn Protection
- **Current:** Custom invulnerability logic
- **New:** `domSetInvulnerable(true)` during respawn period → `domSetInvulnerable(false)` after
- **Impact:** Cleaner spawn protection
- **Risk:** Low — test if per-player

### [ ] 3.8 Use domLoadBuildingsFromFile for Arena Import
- **Current:** `Server_SpawnBuilding` in loop (works but 9+ minutes)
- **New:** `domLoadBuildingsFromFile("filename")` — might load all buildings instantly
- **Impact:** Instant arena replication if it works
- **Risk:** Medium — unknown file format, needs testing

### [ ] 3.9 Use domInfiniteStamina During Match
- **Current:** Players can run out of stamina
- **New:** `domInfiniteStamina(true)` during match
- **Impact:** No stamina management during PvP (better gameplay flow)
- **Risk:** Low

---

## Priority 4: Code Cleanup

### [ ] 4.1 Remove Redundant LoopAsync Loops After Event Migration
- After implementing Priority 2 items, remove old polling loops
- Target: 29 loops → ~5 remaining (timer tick, periodic scoreboard refresh, mob scanner)

### [ ] 4.2 Consolidate Crash Guards
- `is_world_valid()` guard already on all 29 loops
- After event migration, fewer loops = fewer crash points

### [ ] 4.3 Test All Cheat Manager Functions for Per-Player vs Global
- Many `dom*` functions may be global (affect all players) vs per-player
- Need to verify: domSetInvulnerable, domNoMagicCost, domSetPvpEnabled, domInfiniteStamina
- If global-only, keep current per-player approaches for those

---

## Testing Priority
1. **1.2** Friendly fire (biggest hack replacement)
2. **1.1** Respawn (fixes Creative mode issue)
3. **3.1** domSpawnAi (simplifies PvE significantly)
4. **1.3** Bed claiming (unlocks auto-setup)
5. **2.3** InteractionComponent proximity (biggest polling reduction)
6. **3.5** MovementSpeed for flag carrier
7. **3.8** domLoadBuildingsFromFile (potential instant arena)
