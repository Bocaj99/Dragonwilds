--[[
    CTF Building Tool — Export + Import + Protection
    =================================================
    Num0 = Discover building system (Phase 1 — already done)
    Num1 = EXPORT all building pieces to file (class + pos + rot)
    Num2 = PROTECT all buildings (bCanBeDamaged=false + hooks)
    Num3 = SPAWN TEST — spawn a single foundation near player
    Num4 = IMPORT all building pieces from export file
]]

local MOD_NAME = "CTFBuildingTool"
local EXPORT_FILE = "ue4ss\\Mods\\CTFBuildingTool\\building_export.txt"

local function log(msg)
    print(string.format("[%s] %s\n", MOD_NAME, msg))
end

-- =============================================================================
-- Num1: EXPORT — Dump all building pieces to file
-- =============================================================================

local function phase_export()
    log("=== EXPORT: Reading all building pieces ===")

    local actors = FindAllOf("BaseBuildingActor")
    if not actors then
        log("No BaseBuildingActor instances found!")
        return
    end

    local total = 0
    local lines = {}

    for _, actor in pairs(actors) do
        local ok, data = pcall(function()
            local cls = actor:GetClass():GetFullName()
            local loc = actor:K2_GetActorLocation()
            local rot = actor:K2_GetActorRotation()
            local scale = actor:GetActorScale3D()
            local dataIndex = -1
            pcall(function() dataIndex = actor.BuildingPieceDataIndex end)

            -- Extract the asset path from class name
            local path = cls:match("BlueprintGeneratedClass (.+)") or cls:match("Class (.+)") or cls

            local line = string.format("%s|%.2f|%.2f|%.2f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%d",
                path,
                loc.X, loc.Y, loc.Z,
                rot.Pitch, rot.Yaw, rot.Roll,
                scale.X, scale.Y, scale.Z,
                dataIndex
            )
            return line
        end)

        if ok and data then
            total = total + 1
            table.insert(lines, data)
        end
    end

    log(string.format("Read %d building pieces", total))

    -- Write to file
    local file = io.open(EXPORT_FILE, "w")
    if file then
        file:write("-- CTF Building Export\n")
        file:write(string.format("-- Total pieces: %d\n", total))
        file:write("-- Format: ClassPath|X|Y|Z|Pitch|Yaw|Roll|ScaleX|ScaleY|ScaleZ|DataIndex\n")
        for _, line in ipairs(lines) do
            file:write(line .. "\n")
        end
        file:close()
        log("Exported to: " .. EXPORT_FILE)
    else
        log("ERROR: Could not write to " .. EXPORT_FILE)
        -- Fallback path
        local fallback = "building_export.txt"
        file = io.open(fallback, "w")
        if file then
            file:write("-- CTF Building Export\n")
            file:write(string.format("-- Total pieces: %d\n", total))
            file:write("-- Format: ClassPath|X|Y|Z|Pitch|Yaw|Roll|ScaleX|ScaleY|ScaleZ|DataIndex\n")
            for _, line in ipairs(lines) do
                file:write(line .. "\n")
            end
            file:close()
            log("Exported to fallback: " .. fallback)
        else
            log("ERROR: Could not write to fallback either!")
        end
    end

    -- Print type summary
    log("")
    log("--- Type breakdown ---")
    local type_counts = {}
    for _, line in ipairs(lines) do
        local path = line:match("^([^|]+)")
        local short = path:match("([^%.]+)_C$") or path
        type_counts[short] = (type_counts[short] or 0) + 1
    end
    local sorted = {}
    for name, cnt in pairs(type_counts) do
        table.insert(sorted, {name = name, count = cnt})
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)
    for i, entry in ipairs(sorted) do
        if i <= 20 then
            log(string.format("  %s: %d", entry.name, entry.count))
        end
    end

    log("=== EXPORT COMPLETE ===")
end

-- =============================================================================
-- Num5: REPAIR — Only spawn missing pieces (compare export vs current world)
-- =============================================================================

local function phase_repair()
    log("=== REPAIR: Checking for missing building pieces ===")

    -- 1. Read export file
    local file = io.open(EXPORT_FILE, "r")
    if not file then
        log("ERROR: Could not open " .. EXPORT_FILE)
        return
    end

    local expected = {}
    for line in file:lines() do
        if not line:match("^%-%-") and line:match("|") then
            local path, x, y, z, pitch, yaw, roll, sx, sy, sz =
                line:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)$")
            if path then
                table.insert(expected, {
                    path = path,
                    x = tonumber(x), y = tonumber(y), z = tonumber(z),
                    pitch = tonumber(pitch), yaw = tonumber(yaw), roll = tonumber(roll),
                    sx = tonumber(sx), sy = tonumber(sy), sz = tonumber(sz),
                })
            end
        end
    end
    file:close()
    log(string.format("Export has %d pieces", #expected))

    -- 2. Read current world pieces — build a lookup by position (rounded)
    local actors = FindAllOf("BaseBuildingActor")
    if not actors then
        log("No BaseBuildingActor in world — running full import instead")
        phase_import()
        return
    end

    local existing = {}
    local world_count = 0
    for _, actor in pairs(actors) do
        world_count = world_count + 1
        local ok, key = pcall(function()
            local loc = actor:K2_GetActorLocation()
            -- Round to nearest integer to handle float precision
            return string.format("%.0f,%.0f,%.0f", loc.X, loc.Y, loc.Z)
        end)
        if ok and key then
            existing[key] = true
        end
    end
    log(string.format("World currently has %d pieces", world_count))

    -- 3. Find missing pieces
    local missing = {}
    for _, p in ipairs(expected) do
        local key = string.format("%.0f,%.0f,%.0f", p.x, p.y, p.z)
        if not existing[key] then
            table.insert(missing, p)
        end
    end
    log(string.format("Missing pieces: %d", #missing))

    if #missing == 0 then
        log("All pieces present — nothing to repair!")
        return
    end

    -- 4. Spawn missing pieces
    local player = FindFirstOf("BP_PlayerCharacter_C")
    if not player or not player:IsValid() then
        log("No player found!")
        return
    end
    local world = player:GetWorld()

    local classCache = {}
    local function getClass(path)
        if classCache[path] then return classCache[path] end
        local ok, cls = pcall(function() return StaticFindObject(path) end)
        if ok and cls and cls:IsValid() then
            classCache[path] = cls
            return cls
        end
        local shortName = path:match("([^%.]+)$")
        if shortName then
            local ok2, inst = pcall(function() return FindFirstOf(shortName) end)
            if ok2 and inst and inst:IsValid() then
                classCache[path] = inst:GetClass()
                return inst:GetClass()
            end
        end
        return nil
    end

    local spawned = 0
    local failed = 0
    local delay_per_piece = 100 -- 10/sec

    log(string.format("Respawning %d missing pieces (10/sec, ~%.0f seconds)...",
        #missing, #missing * delay_per_piece / 1000))

    local i = 1
    local function spawnNext()
        if i > #missing then
            log(string.format("=== REPAIR COMPLETE: %d respawned, %d failed ===", spawned, failed))
            return
        end

        local p = missing[i]
        i = i + 1

        local cls = getClass(p.path)
        if cls then
            local ok, actor = pcall(function()
                return world:SpawnActor(cls, {X = p.x, Y = p.y, Z = p.z}, {Pitch = p.pitch, Yaw = p.yaw, Roll = p.roll})
            end)
            if ok and actor and actor:IsValid() then
                pcall(function()
                    actor:K2_SetActorLocationAndRotation(
                        {X = p.x, Y = p.y, Z = p.z},
                        {Pitch = p.pitch, Yaw = p.yaw, Roll = p.roll},
                        false, {}, true
                    )
                end)
                pcall(function()
                    actor:K2_SetActorRotation({Pitch = p.pitch, Yaw = p.yaw, Roll = p.roll}, false)
                end)
                pcall(function()
                    local root = actor.RootComponent
                    if root and root:IsValid() then
                        root:K2_SetWorldRotation({Pitch = p.pitch, Yaw = p.yaw, Roll = p.roll}, false, {}, true)
                    end
                end)
                pcall(function() actor.bCanBeDamaged = false end)
                spawned = spawned + 1
            else
                failed = failed + 1
            end
        else
            failed = failed + 1
        end

        if spawned % 100 == 0 and spawned > 0 then
            log(string.format("Repair progress: %d/%d respawned, %d failed", spawned, #missing, failed))
        end

        ExecuteWithDelay(delay_per_piece, function()
            ExecuteInGameThread(function()
                spawnNext()
            end)
        end)
    end

    ExecuteInGameThread(function()
        spawnNext()
    end)
end

-- =============================================================================
-- Num2: PROTECT — bCanBeDamaged=false + hooks
-- =============================================================================

local function phase_protect()
    log("=== PROTECT: Applying building protection ===")

    local actors = FindAllOf("BaseBuildingActor")
    if not actors then
        log("No BaseBuildingActor instances found!")
        return
    end

    local total = 0
    local protected = 0
    for _, actor in pairs(actors) do
        total = total + 1
        local ok = pcall(function() actor.bCanBeDamaged = false end)
        if ok then protected = protected + 1 end
    end
    log(string.format("bCanBeDamaged=false: %d/%d pieces", protected, total))

    -- Hook CanBeDestroyedByPlayer
    pcall(function()
        RegisterHook("/Script/Dominion.BaseBuildingActor:CanBeDestroyedByPlayer", function(self, returnValue)
            log("CanBeDestroyedByPlayer called — blocking")
            if returnValue then returnValue:set(false) end
        end)
        log("CanBeDestroyedByPlayer hook registered")
    end)

    -- Auto-protect new pieces
    pcall(function()
        RegisterHook("/Game/Gameplay/BaseBuilding_New/BuildingPieces/BP_BasePiece.BP_BasePiece_C:ReceiveBeginPlay", function(self)
            pcall(function() self:get().bCanBeDamaged = false end)
        end)
        log("Auto-protect new pieces hook registered")
    end)

    log("=== PROTECTION ACTIVE ===")
end

-- =============================================================================
-- Num3: SPAWN TEST — spawn one foundation near player to verify SpawnActor works
-- =============================================================================

local function phase_spawn_test()
    log("=== SPAWN TEST: Trying to spawn a single building piece ===")

    local player = FindFirstOf("BP_PlayerCharacter_C")
    if not player or not player:IsValid() then
        log("No player found!")
        return
    end

    local world = player:GetWorld()
    if not world then
        log("No world!")
        return
    end

    local playerLoc = player:K2_GetActorLocation()
    -- Spawn 500 units in front of player
    local spawnPos = {X = playerLoc.X + 500, Y = playerLoc.Y, Z = playerLoc.Z}
    log(string.format("Player at: X=%.0f Y=%.0f Z=%.0f", playerLoc.X, playerLoc.Y, playerLoc.Z))
    log(string.format("Spawn at:  X=%.0f Y=%.0f Z=%.0f", spawnPos.X, spawnPos.Y, spawnPos.Z))

    -- Method 1: Try using existing instance as template (like torch spawning)
    log("")
    log("--- Method 1: SpawnActor from existing instance class ---")
    local existing = FindFirstOf("BP_T3_Foundation_Large_C")
    if existing and existing:IsValid() then
        log("Found existing foundation: " .. existing:GetFullName())
        local bpClass = existing:GetClass()
        local ok, actor = pcall(function()
            return world:SpawnActor(bpClass, spawnPos, {})
        end)
        if ok and actor and actor:IsValid() then
            log("SpawnActor SUCCESS! " .. actor:GetFullName())
            pcall(function() actor:K2_SetActorLocation(spawnPos, false, {}, true) end)
            local verifyLoc = actor:K2_GetActorLocation()
            log(string.format("Verified location: X=%.0f Y=%.0f Z=%.0f", verifyLoc.X, verifyLoc.Y, verifyLoc.Z))
            -- Try setting bCanBeDamaged
            pcall(function() actor.bCanBeDamaged = false end)
            log("bCanBeDamaged set to false")
        else
            log("SpawnActor FAILED or returned nil")
        end
    else
        log("No existing BP_T3_Foundation_Large_C found for template")
    end

    -- Method 2: Try StaticFindObject for the class
    log("")
    log("--- Method 2: StaticFindObject class ref ---")
    local ok2, classRef = pcall(function()
        return StaticFindObject("/Game/Gameplay/BaseBuilding_New/BuildingPieces/Tier3_Fellhollow/Foundations/BP_T3_Foundation_Large.BP_T3_Foundation_Large_C")
    end)
    if ok2 and classRef and classRef:IsValid() then
        log("StaticFindObject found class: " .. classRef:GetFullName())
        local spawnPos2 = {X = playerLoc.X + 1000, Y = playerLoc.Y, Z = playerLoc.Z}
        local ok3, actor2 = pcall(function()
            return world:SpawnActor(classRef, spawnPos2, {})
        end)
        if ok3 and actor2 and actor2:IsValid() then
            log("SpawnActor via StaticFindObject SUCCESS! " .. actor2:GetFullName())
            pcall(function() actor2:K2_SetActorLocation(spawnPos2, false, {}, true) end)
        else
            log("SpawnActor via StaticFindObject FAILED")
        end
    else
        log("StaticFindObject could not find class")
    end

    -- Method 3: Try spawning a wall
    log("")
    log("--- Method 3: Spawn a wall piece ---")
    local existingWall = FindFirstOf("BP_T3_Wall_Large_C")
    if existingWall and existingWall:IsValid() then
        local wallClass = existingWall:GetClass()
        local spawnPos3 = {X = playerLoc.X + 500, Y = playerLoc.Y + 500, Z = playerLoc.Z}
        local ok4, actor3 = pcall(function()
            return world:SpawnActor(wallClass, spawnPos3, {})
        end)
        if ok4 and actor3 and actor3:IsValid() then
            log("Wall SpawnActor SUCCESS! " .. actor3:GetFullName())
            pcall(function() actor3:K2_SetActorLocation(spawnPos3, false, {}, true) end)
        else
            log("Wall SpawnActor FAILED")
        end
    else
        log("No existing BP_T3_Wall_Large_C found")
    end

    log("")
    log("=== SPAWN TEST COMPLETE — Check in-game if pieces appeared ===")
end

-- =============================================================================
-- Num4: IMPORT — Read export file and spawn all pieces
-- =============================================================================

local function phase_import()
    log("=== IMPORT: Spawning building pieces from export file ===")

    -- Read export file
    local file = io.open(EXPORT_FILE, "r")
    if not file then
        log("ERROR: Could not open " .. EXPORT_FILE)
        log("Run export (Num1) in the source world first!")
        return
    end

    local pieces = {}
    for line in file:lines() do
        if not line:match("^%-%-") and line:match("|") then
            local parts = {}
            for part in line:gmatch("([^|]+)") do
                table.insert(parts, part)
            end
            if #parts >= 10 then
                table.insert(pieces, {
                    path = parts[1],
                    x = tonumber(parts[2]), y = tonumber(parts[3]), z = tonumber(parts[4]),
                    pitch = tonumber(parts[5]), yaw = tonumber(parts[6]), roll = tonumber(parts[7]),
                    sx = tonumber(parts[8]), sy = tonumber(parts[9]), sz = tonumber(parts[10]),
                    dataIndex = #parts >= 11 and tonumber(parts[11]) or -1,
                })
            end
        end
    end
    file:close()
    log(string.format("Loaded %d pieces from export file", #pieces))

    if #pieces == 0 then
        log("No pieces to spawn!")
        return
    end

    local player = FindFirstOf("BP_PlayerCharacter_C")
    if not player or not player:IsValid() then
        log("No player found!")
        return
    end
    local world = player:GetWorld()
    if not world then
        log("No world!")
        return
    end

    -- Position offset: relocate arena to sky position centered on (67614, 170405, 46385)
    -- Original arena center: (33630, 173624, -3700)
    local OFFSET_X = 34349
    local OFFSET_Y = -3346
    local OFFSET_Z = 20123
    log(string.format("Applying offset: X=%+d Y=%+d Z=%+d", OFFSET_X, OFFSET_Y, OFFSET_Z))

    -- Disable stability before importing
    log("Disabling building stability...")
    pcall(function()
        local bSub = FindFirstOf("BuildingSubsystem")
        if bSub then bSub.bCheatAlwaysAllowBuilding = true end
        local gbm = FindFirstOf("GlobalBuildingManager")
        if gbm then
            gbm.StabilityComponent:Deactivate()
            gbm.StabilityComponent:SetComponentTickEnabled(false)
        end
        log("Stability disabled")
    end)

    -- Get BuildModeComponent for Server_SpawnBuilding
    local controller = player:GetInstigatorController()
    if not controller then
        log("No controller!")
        return
    end

    local bmc = nil
    pcall(function() bmc = controller.BuildModeComponent end)
    if not bmc then
        pcall(function() bmc = FindFirstOf("BuildModeComponent") end)
    end

    if not bmc or not bmc:IsValid() then
        log("BuildModeComponent not found! Cannot use Server_SpawnBuilding.")
        return
    end
    log("BuildModeComponent: " .. bmc:GetFullName())

    -- Convert Euler angles (Pitch/Yaw/Roll) to quaternion for FTransform
    local function euler_to_quat(pitch, yaw, roll)
        local p = math.rad(pitch) * 0.5
        local y = math.rad(yaw) * 0.5
        local r = math.rad(roll) * 0.5
        local sp, cp = math.sin(p), math.cos(p)
        local sy, cy = math.sin(y), math.cos(y)
        local sr, cr = math.sin(r), math.cos(r)
        return {
            X = cr * sp * sy - sr * cp * cy,
            Y = -cr * sp * cy - sr * cp * sy,
            Z = cr * cp * sy - sr * sp * cy,
            W = cr * cp * cy + sr * sp * sy,
        }
    end

    -- Spawn pieces: 20 per second (batch of 1 every 50ms)
    local spawned = 0
    local failed = 0
    local skipped = 0
    local batch_size = 1
    local delay_per_batch = 50 -- ms (20 per second)

    local est_minutes = (#pieces * delay_per_batch / 1000) / 60
    log(string.format("Spawning %d pieces via Server_SpawnBuilding (10/sec, ~%.0f minutes)...", #pieces, est_minutes))

    local i = 1
    local function spawnBatch()
        local batch_end = math.min(i + batch_size - 1, #pieces)
        for j = i, batch_end do
            local p = pieces[j]
            if p.dataIndex and p.dataIndex >= 0 then
                local quat = euler_to_quat(p.pitch, p.yaw, p.roll)
                local ok, err = pcall(function()
                    bmc:Server_SpawnBuilding(
                        p.dataIndex,
                        {
                            Rotation = quat,
                            Translation = {X = p.x + OFFSET_X, Y = p.y + OFFSET_Y, Z = p.z + OFFSET_Z},
                            Scale3D = {X = p.sx, Y = p.sy, Z = p.sz},
                        },
                        false,
                        {}
                    )
                end)
                if ok then
                    spawned = spawned + 1
                else
                    failed = failed + 1
                    if failed <= 5 then
                        log("Spawn failed: " .. tostring(err):match("([^\n]+)"))
                    end
                end
            else
                skipped = skipped + 1
                if skipped <= 5 then
                    log("Skipped (no dataIndex): " .. p.path)
                end
            end
        end

        i = batch_end + 1
        if i <= #pieces then
            -- Log progress every 100
            if spawned % 100 < batch_size then
                log(string.format("Progress: %d/%d spawned, %d failed", spawned, #pieces, failed))
            end
            ExecuteWithDelay(delay_per_batch, function()
                ExecuteInGameThread(function()
                    spawnBatch()
                end)
            end)
        else
            log(string.format("=== IMPORT COMPLETE: %d spawned, %d failed, %d skipped out of %d ===", spawned, failed, skipped, #pieces))
        end
    end

    ExecuteInGameThread(function()
        spawnBatch()
    end)
end

-- =============================================================================
-- KEY BINDINGS
-- =============================================================================

log("CTF Building Tool loaded!")
log("  Num1 = EXPORT all pieces to file")
log("  Num2 = REGISTRATION TEST")

RegisterKeyBind(Key.NUM_ZERO, function()
    log("Num0 pressed — importing...")
    ExecuteInGameThread(function()
        phase_import()
    end)
end)

RegisterKeyBind(Key.NUM_ONE, function()
    log("Num1 pressed — exporting...")
    ExecuteInGameThread(function()
        phase_export()
    end)
end)

RegisterKeyBind(Key.NUM_TWO, function()
    log("Num2 pressed — v2 API tests...")
    ExecuteInGameThread(function()
        log("=== V2 API TESTS ===")

        local player = FindFirstOf("BP_PlayerCharacter_C")
        if not player or not player:IsValid() then log("No player!") return end
        local controller = player:GetInstigatorController()
        local playerLoc = player:K2_GetActorLocation()
        local cm = FindFirstOf("DominionCheatManager")

        -- TEST 1: domSpawnAi — try multiple name formats
        log("")
        log("--- TEST 1: domSpawnAi name formats ---")
        if cm and cm:IsValid() then
            local pos = {x = playerLoc.X + 1000, y = playerLoc.Y, z = playerLoc.Z + 300}
            local formats = {
                "Wolf",
                "BP_AI_Wolf_Character",
                "BP_AI_Wolf_Character_C",
                "/Game/Gameplay/AI/Wolf/BP_AI_Wolf_Character.BP_AI_Wolf_Character_C",
            }
            for _, fmt in ipairs(formats) do
                local ok, err = pcall(function()
                    cm:domSpawnAi(fmt, pos.x, pos.y, pos.z, 3)
                end)
                if ok then
                    log("  domSpawnAi('" .. fmt .. "') — called (check if wolf appeared)")
                else
                    log("  domSpawnAi('" .. fmt .. "') — FAILED: " .. tostring(err):match("([^\n]+)"))
                end
                pos.x = pos.x + 500 -- offset each attempt
            end
        else
            log("CheatManager not found")
        end

        -- TEST 2: OnWillReceiveDamageDynamic hook
        log("")
        log("--- TEST 2: OnWillReceiveDamageDynamic hook ---")
        local ok2, err2 = pcall(function()
            RegisterHook("/Script/Dominion.DamageComponent:OnWillReceiveDamageDynamic", function(self, target, damageEvent, damageTime)
                log("OnWillReceiveDamageDynamic FIRED!")
                pcall(function()
                    local tgt = target:get()
                    if tgt and tgt:IsValid() then
                        log("  Target: " .. tgt:GetFullName())
                    end
                end)
            end)
            log("OnWillReceiveDamageDynamic hook REGISTERED")
        end)
        if not ok2 then
            log("OnWillReceiveDamageDynamic hook FAILED: " .. tostring(err2):match("([^\n]+)"))
            -- Try alternate path
            pcall(function()
                RegisterHook("/Script/Dominion.DamageComponent:HandleOnDamageCached", function(self)
                    log("HandleOnDamageCached FIRED!")
                end)
                log("HandleOnDamageCached hook registered as fallback")
            end)
        end

        -- TEST 3: OnRespawnDynamic hook
        log("")
        log("--- TEST 3: OnRespawnDynamic hook ---")
        local ok3, err3 = pcall(function()
            RegisterHook("/Script/Dominion.RespawnComponent:OnRespawnDynamic", function(self)
                log("OnRespawnDynamic FIRED!")
            end)
            log("OnRespawnDynamic hook REGISTERED")
        end)
        if not ok3 then
            log("OnRespawnDynamic FAILED: " .. tostring(err3):match("([^\n]+)"))
        end
        -- Multicast_Respawn + arena teleport test
        local OX, OY, OZ = 34349, -3346, 20123
        local test_spawns = {
            {X = 37605 + OX, Y = 168177 + OY, Z = -3284 + OZ},
            {X = 38323 + OX, Y = 168895 + OY, Z = -3284 + OZ},
            {X = 36887 + OX, Y = 167459 + OY, Z = -3284 + OZ},
            {X = 29654 + OX, Y = 179071 + OY, Z = -3284 + OZ},
            {X = 28936 + OX, Y = 178353 + OY, Z = -3284 + OZ},
        }
        local spawn_idx = 0

        local ok3b, err3b = pcall(function()
            RegisterHook("/Script/Dominion.PlayerRespawnComponent:Multicast_Respawn", function(self, loc, rot)
                log("Multicast_Respawn FIRED! Teleporting to arena spawn...")
                spawn_idx = (spawn_idx % #test_spawns) + 1
                local spawn = test_spawns[spawn_idx]

                ExecuteWithDelay(500, function()
                    ExecuteInGameThread(function()
                        pcall(function()
                            local p = FindFirstOf("BP_PlayerCharacter_C")
                            if p and p:IsValid() then
                                p:K2_SetActorLocationAndRotation(
                                    spawn,
                                    {Pitch = 0, Yaw = 135, Roll = 0},
                                    false, {}, true
                                )
                                p:PlayRespawnVFX()
                                log(string.format("  Teleported to arena spawn #%d: X=%.0f Y=%.0f Z=%.0f", spawn_idx, spawn.X, spawn.Y, spawn.Z))
                            end
                        end)
                    end)
                end)
            end)
            log("Multicast_Respawn hook REGISTERED (with arena teleport)")
        end)
        if not ok3b then
            log("Multicast_Respawn FAILED: " .. tostring(err3b):match("([^\n]+)"))
        end

        -- TEST 4: OnPlayerLoggedIn/Out hooks
        log("")
        log("--- TEST 4: GameMode player events ---")
        local ok4, err4 = pcall(function()
            RegisterHook("/Script/Dominion.DominionGameMode:OnPlayerLoggedIn", function(self, playerCtrl)
                log("OnPlayerLoggedIn FIRED!")
            end)
            log("OnPlayerLoggedIn hook REGISTERED")
        end)
        if not ok4 then log("OnPlayerLoggedIn FAILED: " .. tostring(err4):match("([^\n]+)")) end

        local ok4b, err4b = pcall(function()
            RegisterHook("/Script/Dominion.DominionGameMode:OnPlayerLoggedOut", function(self, playerCtrl)
                log("OnPlayerLoggedOut FIRED!")
            end)
            log("OnPlayerLoggedOut hook REGISTERED")
        end)
        if not ok4b then log("OnPlayerLoggedOut FAILED: " .. tostring(err4b):match("([^\n]+)")) end

        -- TEST 5: BedComponent:Claim
        log("")
        log("--- TEST 5: BedComponent:Claim ---")
        -- Try finding BedComponent directly
        local bedComps = FindAllOf("BedComponent")
        if bedComps then
            local count = 0
            for _, bc in pairs(bedComps) do
                count = count + 1
                if count == 1 then
                    log("BedComponent found via FindAllOf: " .. bc:GetFullName())
                    -- Dump properties
                    bc:GetClass():ForEachProperty(function(prop)
                        log("  BED_PROP: " .. prop:GetFullName())
                    end)
                    bc:GetClass():ForEachFunction(function(func)
                        log("  BED_FUNC: " .. func:GetFullName())
                    end)
                    -- Try claiming
                    local ok5, err5 = pcall(function()
                        local claimed = bc:IsClaimedByAnyPlayer()
                        log("  IsClaimedByAnyPlayer: " .. tostring(claimed))
                        bc:Claim(player)
                        log("  Claim(player) called!")
                        local nowClaimed = bc:IsClaimedByPlayer(player)
                        log("  IsClaimedByPlayer after: " .. tostring(nowClaimed))
                        local name = bc:GetClaimingCharacterName()
                        log("  ClaimingCharacterName: " .. tostring(name))
                    end)
                    if not ok5 then log("  Claim FAILED: " .. tostring(err5):match("([^\n]+)")) end
                end
            end
            log("Total BedComponents: " .. count)
        else
            log("No BedComponent found via FindAllOf")
            -- Try RestingAreaComponent as parent class
            local racs = FindAllOf("RestingAreaComponent")
            if racs then
                local count = 0
                for _, rac in pairs(racs) do
                    count = count + 1
                    if count <= 3 then
                        log("RestingAreaComponent: " .. rac:GetFullName())
                        log("  Class: " .. rac:GetClass():GetFullName())
                    end
                end
                log("Total RestingAreaComponents: " .. count)
            else
                log("No RestingAreaComponent found either")
            end
        end

        -- Also try listing all bed actor properties
        local beds = FindAllOf("BP_BaseBuilding_Bed_C")
        if beds then
            for _, bed in pairs(beds) do
                log("Bed actor: " .. bed:GetFullName())
                bed:GetClass():ForEachProperty(function(prop)
                    log("  BEDACTOR_PROP: " .. prop:GetFullName())
                end)
                -- Walk supers for Dominion-specific
                local super = bed:GetClass():GetSuperStruct()
                while super and super:IsValid() do
                    local sname = super:GetFullName()
                    if sname:find("Dominion") or sname:find("BaseBuilding") then
                        super:ForEachProperty(function(prop)
                            local pn = prop:GetFullName()
                            if pn:find("Bed") or pn:find("Rest") or pn:find("Claim") or pn:find("Sleep") then
                                log("  SUPER_PROP: " .. pn)
                            end
                        end)
                    end
                    if sname:find("Object") then break end
                    super = super:GetSuperStruct()
                end
                break -- first bed only
            end
        end

        -- TEST 6: SelfReviveDelay (death timer)
        log("")
        log("--- TEST 6: SelfReviveDelay ---")
        local respawnComps = FindAllOf("PlayerRespawnComponent")
        if respawnComps then
            local count = 0
            for _, rc in pairs(respawnComps) do
                count = count + 1
                if count == 1 then
                    log("PlayerRespawnComponent found: " .. rc:GetFullName())
                    local ok_r, err_r = pcall(function()
                        local current = rc.SelfReviveDelay
                        log("  Current SelfReviveDelay: " .. tostring(current))
                        rc.SelfReviveDelay = 15.0
                        local after = rc.SelfReviveDelay
                        log("  After setting to 15.0: " .. tostring(after))
                    end)
                    if not ok_r then log("  FAILED: " .. tostring(err_r):match("([^\n]+)")) end
                end
            end
            log("Total PlayerRespawnComponents: " .. count)
        else
            log("No PlayerRespawnComponent found")
        end

        -- TEST 7: Movement speed multiplier
        log("")
        log("--- TEST 7: MovementSpeedMultiplier ---")
        pcall(function()
            local current = player.MovementSpeedMultiplier
            log("Current MovementSpeedMultiplier: " .. tostring(current))
            player.MovementSpeedMultiplier = 0.5
            local after = player.MovementSpeedMultiplier
            log("After setting to 0.5: " .. tostring(after))
            -- Restore
            player.MovementSpeedMultiplier = 1.0
            log("Restored to 1.0")
        end)

        log("")
        log("=== V2 API TESTS COMPLETE ===")
        log("Now: hit something to test OnWillReceiveDamageDynamic")
        log("     die and respawn to test OnRespawnDynamic")
        log("     check if wolves spawned near you")
    end)
end)

------------------------------------------------------------
-- Num8: FF test v3 — CanBeDamagedBy + return override
------------------------------------------------------------
local ff_test_active = false
RegisterKeyBind(Key.NUM_EIGHT, function()
    if ff_test_active then
        log("[FF TEST] Already active — go take damage to test")
        return
    end
    ff_test_active = true
    log("")
    log("=== FF TEST v3: CanBeDamagedBy hook + return override ===")

    -- Hook 1: CanBeDamagedBy on DamageComponent (script path)
    local ok1, err1 = pcall(function()
        RegisterHook("/Script/Dominion.DamageComponent:CanBeDamagedBy", function(self, instigator, returnValue)
            log("[FF TEST] DamageComponent:CanBeDamagedBy FIRED!")
            pcall(function()
                local ins = instigator:get()
                if ins and ins:IsValid() then
                    log("[FF TEST]   Instigator: " .. ins:GetFullName())
                end
            end)
            pcall(function()
                local ret = returnValue:get()
                log("[FF TEST]   Return value: " .. tostring(ret))
                -- Try override to false (block damage)
                returnValue:set(false)
                log("[FF TEST]   Set return to false (block)")
            end)
        end)
    end)
    log("[FF TEST] DC:CanBeDamagedBy: " .. (ok1 and "registered" or ("FAILED: " .. tostring(err1))))

    -- Hook 2: CanBeDamagedBy on PlayerDamageComponent
    local ok2, err2 = pcall(function()
        RegisterHook("/Script/Dominion.PlayerDamageComponent:CanBeDamagedBy", function(self, instigator, returnValue)
            log("[FF TEST] PlayerDamageComponent:CanBeDamagedBy FIRED!")
            pcall(function()
                local ins = instigator:get()
                if ins and ins:IsValid() then
                    log("[FF TEST]   Instigator: " .. ins:GetFullName())
                end
            end)
            pcall(function()
                returnValue:set(false)
                log("[FF TEST]   Set return to false (block)")
            end)
        end)
    end)
    log("[FF TEST] PDC:CanBeDamagedBy: " .. (ok2 and "registered" or ("FAILED: " .. tostring(err2))))

    -- Hook 3: CanTakeDamage on DamageComponent
    local ok3, err3 = pcall(function()
        RegisterHook("/Script/Dominion.DamageComponent:CanTakeDamage", function(self, returnValue)
            log("[FF TEST] DamageComponent:CanTakeDamage FIRED!")
            pcall(function()
                local ret = returnValue:get()
                log("[FF TEST]   Return value: " .. tostring(ret))
                -- Try override to false
                returnValue:set(false)
                log("[FF TEST]   Set return to false (block all)")
            end)
        end)
    end)
    log("[FF TEST] DC:CanTakeDamage: " .. (ok3 and "registered" or ("FAILED: " .. tostring(err3))))

    -- Hook 4: SetCanTakeDamage on DamageComponent
    local ok4, err4 = pcall(function()
        RegisterHook("/Script/Dominion.DamageComponent:SetCanTakeDamage", function(self, bValue)
            log("[FF TEST] DamageComponent:SetCanTakeDamage FIRED! val=" .. tostring(bValue:get()))
        end)
    end)
    log("[FF TEST] DC:SetCanTakeDamage: " .. (ok4 and "registered" or ("FAILED: " .. tostring(err4))))

    -- Hook 5: Known-working reference
    local ok5, err5 = pcall(function()
        RegisterHook("/Game/Gameplay/Character/Player/BP_PlayerCharacter.BP_PlayerCharacter_C:OnDamageReceivedDynamic_Event", function(self, p1, p2)
            log("[FF TEST] OnDamageReceivedDynamic_Event FIRED! (reference)")
        end)
    end)
    log("[FF TEST] OnDamageReceivedDynamic_Event: " .. (ok5 and "registered" or ("FAILED: " .. tostring(err5))))

    log("")
    log("[FF TEST] 5 hooks registered. Go take a hit!")
    log("[FF TEST] If CanBeDamagedBy fires and blocks, you should take NO damage at all.")
end)
