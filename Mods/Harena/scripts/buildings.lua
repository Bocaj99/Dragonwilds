--[[
    Harena v1 — Building Protection + Bed Claiming + Stability
]]

local Config = require("config")
local Events = require("events")
local Buildings = {}

function Buildings.disable_stability()
    pcall(function()
        local bSub = FindFirstOf("BuildingSubsystem")
        if bSub then bSub.bCheatAlwaysAllowBuilding = true end
        local gbm = FindFirstOf("GlobalBuildingManager")
        if gbm then
            gbm.StabilityComponent:Deactivate()
            gbm.StabilityComponent:SetComponentTickEnabled(false)
        end
    end)
end

function Buildings.protect_all()
    local actors = FindAllOf("BaseBuildingActor")
    if not actors then return 0 end
    local count = 0
    for _, actor in pairs(actors) do
        pcall(function() actor.bCanBeDamaged = false end)
        count = count + 1
    end
    return count
end

function Buildings.lock_mannequins()
    local mannequins = FindAllOf("BP_BaseBuilding_ArmourMannequin_C")
    if not mannequins then return 0 end
    local count = 0
    for _, m in pairs(mannequins) do
        pcall(function()
            local inv = m.BP_Components_WorldItemInventory
            if inv then
                inv.bAllowRemoves = false
                inv.bAllowAdds = false
                count = count + 1
            end
        end)
    end
    return count
end

function Buildings.claim_beds_for_team(team, players)
    local beds = FindAllOf("BedComponent")
    if not beds then return 0 end

    local bed_list = {}
    for _, bc in pairs(beds) do
        table.insert(bed_list, bc)
    end

    -- Assign beds: first 3 to red, next 3 to blue (6 beds total)
    local start_idx = (team == "red") and 1 or 4
    local claimed = 0
    for i, player_ref in ipairs(players) do
        local bed_idx = start_idx + i - 1
        if bed_idx <= #bed_list then
            pcall(function()
                bed_list[bed_idx]:Claim(player_ref)
                claimed = claimed + 1
            end)
        end
    end
    return claimed
end

function Buildings.start_heal_loop()
    LoopAsync(5000, function()
        if not is_world_valid() then return true end
        pcall(function()
            local hcs = FindAllOf("HealthComponent")
            if not hcs then return end
            for _, hc in pairs(hcs) do
                pcall(function()
                    if hc and hc:IsValid() then
                        local full = hc:GetFullName()
                        if not full:find("Tree") and not full:find("Sapling")
                           and not full:find("BP_AI_") and not full:find("PlayerCharacter")
                           and not full:find("Deer") and not full:find("Kebbit")
                           and not full:find("Chinchompa") and not full:find("Sheep")
                           and not full:find("Chicken") and not full:find("Cow")
                           and not full:find("Magpie") and not full:find("Rat")
                           and not full:find("Bush") and not full:find("Flax")
                           and not full:find("OreNode") and not full:find("Spawner") then
                            local max = hc:GetMaxHealth()
                            if max and max > 0 then
                                hc:SetHealth(max, "Heal")
                            end
                        end
                    end
                end)
            end
        end)
        return false
    end)
end

-- Force all players out of build mode
function Buildings.disable_building_for_all()
    local players = FindAllOf("BP_PlayerCharacter_C")
    if not players then return end
    for _, player in pairs(players) do
        pcall(function()
            local ctrl = player:GetInstigatorController()
            if ctrl and ctrl:IsValid() then
                -- Exit build mode if active
                local bmc = ctrl.BuildModeComponent
                if bmc and bmc:IsValid() then
                    bmc:ExitAnyMode()
                end
            end
        end)
    end
end

-- Continuously block build mode during match (checks every 2s)
function Buildings.start_build_blocker()
    LoopAsync(200, function()
        if not is_world_valid() then return true end
        local ok, phase = pcall(function()
            local Match = require("match")
            return Match.state.phase
        end)
        if not ok then return true end
        -- Only block during active match
        if phase ~= "active" and phase ~= "preparation" then return false end

        local players = FindAllOf("BP_PlayerCharacter_C")
        if not players then return false end
        for _, player in pairs(players) do
            pcall(function()
                local ctrl = player:GetInstigatorController()
                if ctrl and ctrl:IsValid() then
                    local bmc = ctrl.BuildModeComponent
                    if bmc and bmc:IsValid() then
                        local mode = bmc:GetCurrentBuildMode()
                        -- If mode is not 0 (None), force exit
                        if mode and mode ~= 0 then
                            bmc:ExitAnyMode()
                        end
                    end
                end
            end)
        end
        return false
    end)
end

-- Track all building pieces for regen
Buildings.piece_registry = {}  -- [posKey] = {dataIndex, x, y, z, pitch, yaw, roll}
Buildings.expected_count = 0

function Buildings.snapshot_pieces()
    local actors = FindAllOf("BaseBuildingActor")
    if not actors then return end
    Buildings.piece_registry = {}
    local count = 0
    for _, actor in pairs(actors) do
        pcall(function()
            local loc = actor:K2_GetActorLocation()
            local rot = actor:K2_GetActorRotation()
            local idx = actor.BuildingPieceDataIndex
            if loc and idx and idx >= 0 then
                local key = string.format("%.0f,%.0f,%.0f", loc.X, loc.Y, loc.Z)
                Buildings.piece_registry[key] = {
                    dataIndex = idx,
                    x = loc.X, y = loc.Y, z = loc.Z,
                    pitch = rot.Pitch or 0, yaw = rot.Yaw or 0, roll = rot.Roll or 0,
                }
                count = count + 1
            end
        end)
    end
    Buildings.expected_count = math.max(count, Buildings.KNOWN_BASELINE or 0)
    print(string.format("[Harena] Building snapshot: %d pieces registered\n", count))
end

-- Periodic regen check (every 5s during match)
function Buildings.start_regen_loop()
    print("[Harena] Regen loop started\n")

    local euler_to_quat = function(pitch, yaw, roll)
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

    -- Hook Server_Interact to detect destroy attempts
    Buildings._regen_at = 0  -- timestamp when regen should run

    if not _G.harena_hooks then _G.harena_hooks = {} end
    if not _G.harena_hooks.build_interact then
        pcall(function()
            RegisterHook("/Script/Dominion.BuildInteractionComponent:Server_Interact", function(self, pieceID, interactionType, inventories, location)
                local itype = 0
                pcall(function() itype = interactionType:get() end)
                if itype == 3 then
                    print(string.format("[Harena] Destroy detected: pieceID=%s\n",
                        tostring(pieceID and pieceID:get() or "?")))
                    -- Run regen on next game thread tick
                    ExecuteInGameThread(function()
                        Buildings.regen_missing()
                    end)
                end
            end)
            _G.harena_hooks.build_interact = true
            print("[Harena] Server_Interact hook registered (regen trigger)\n")
        end)
    end
end

-- Regen missing pieces (called from hook or periodic check)
Buildings._regen_paused = false

function Buildings.regen_missing()
    if Buildings._regen_paused then return end
    if not Buildings.piece_registry or not next(Buildings.piece_registry) then return end

    local actors = FindAllOf("BaseBuildingActor")
    if not actors then return end

    -- Get BMC
    local bmc = nil
    pcall(function()
        local player = FindFirstOf("BP_PlayerCharacter_C")
        if player then
            local ctrl = player:GetInstigatorController()
            if ctrl then bmc = ctrl.BuildModeComponent end
        end
    end)
    if not bmc or not bmc:IsValid() then return end

    -- Build current position set
    local current = {}
    for _, actor in pairs(actors) do
        pcall(function()
            local loc = actor:K2_GetActorLocation()
            if loc then
                local key = string.format("%.0f,%.0f,%.0f", loc.X, loc.Y, loc.Z)
                current[key] = true
            end
        end)
    end

    local euler_to_quat = function(pitch, yaw, roll)
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

    local respawned = 0
    for key, piece in pairs(Buildings.piece_registry) do
        if not current[key] then
            pcall(function()
                local quat = euler_to_quat(piece.pitch, piece.yaw, piece.roll)
                bmc:Server_SpawnBuilding(
                    piece.dataIndex,
                    {
                        Rotation = quat,
                        Translation = {X = piece.x, Y = piece.y, Z = piece.z},
                        Scale3D = {X = 1.0, Y = 1.0, Z = 1.0},
                    },
                    false,
                    {}
                )
                respawned = respawned + 1
            end)
        end
    end

    if respawned > 0 then
        print(string.format("[Harena] Regen: %d pieces respawned\n", respawned))
        Buildings.protect_all()
    end
end

function Buildings.init()
    Buildings.disable_stability()
    local protected = Buildings.protect_all()
    local locked = Buildings.lock_mannequins()
    Buildings.start_heal_loop()
    Buildings.start_build_blocker()

    -- Snapshot pieces for regen — wait 15s for streaming then take snapshot
    -- Use known baseline as minimum (streaming may not load all pieces)
    Buildings.KNOWN_BASELINE = 7669
    ExecuteWithDelay(15000, function()
        ExecuteInGameThread(function()
            Buildings.snapshot_pieces()
            if Buildings.expected_count < Buildings.KNOWN_BASELINE then
                Buildings.expected_count = Buildings.KNOWN_BASELINE
                print(string.format("[Harena] Using known baseline: %d pieces (snapshot was %d)\n",
                    Buildings.KNOWN_BASELINE, Buildings.expected_count))
            end
            Buildings.start_regen_loop()
        end)
    end)

    print(string.format("[Harena] Buildings: %d protected, %d mannequins locked\n", protected, locked))
end

return Buildings
