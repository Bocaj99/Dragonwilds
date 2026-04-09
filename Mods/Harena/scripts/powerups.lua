--[[
    Harena v1 — Powerup System (Wild Anima)
    3 spawn positions, proximity pickup, class-specific buffs.
]]

local Config = require("config")
local Events = require("events")
local UI = require("ui")
local Powerups = {}

Powerups.spawns = {}  -- {pos, actor, active, respawn_at}
Powerups.buffs = {}   -- [player_id] = {class, expire_time, vfx_loop_active}

-- =============================================================================
-- Spawn anima at position (MUST use fresh StaticFindObject)
-- =============================================================================
local function spawn_anima(pos)
    local player = FindFirstOf("BP_PlayerCharacter_C")
    if not player then return nil end
    local world = player:GetWorld()
    if not world then return nil end

    local freshClass = StaticFindObject(Config.ANIMA_ASSET)
    if not freshClass or not freshClass:IsValid() then return nil end

    local anima_pos = {X = pos.X - 11, Y = pos.Y - 4, Z = pos.Z - 18}
    local ok, actor = pcall(function() return world:SpawnActor(freshClass, anima_pos, {}) end)
    if ok and actor and actor:IsValid() then
        pcall(function() actor:K2_SetActorLocation(anima_pos, false, {}, true) end)
        pcall(function() actor:SetActorEnableCollision(false) end)
        return actor
    end
    return nil
end

-- =============================================================================
-- Setup powerup spawn points
-- =============================================================================
-- Spawn aura: AnimaVent (beam) + Niagara orb. Returns {vent_actor, orb_component}
local function spawn_aura(pos, world)
    local result = {vent = nil, orb = nil}

    local player = FindFirstOf("BP_PlayerCharacter_C")
    if not player then return result end

    -- Spawn AnimaVent at -670 (beam column)
    pcall(function()
        local existing = FindFirstOf("BP_AnimaVent_C")
        if existing and existing:IsValid() then
            local cls = existing:GetClass()
            local a = world:SpawnActor(cls, {X = pos.X, Y = pos.Y, Z = pos.Z - 670}, {})
            if a and a:IsValid() then
                pcall(function() a:SetActorEnableCollision(false) end)
                result.vent = a
                print("[Harena] Aura: AnimaVent beam spawned\n")
            end
        end
    end)

    -- Spawn Niagara orb
    local niagaraLib = nil
    pcall(function() niagaraLib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary") end)
    if not niagaraLib then return result end

    local orb_pos = {X = pos.X - 7, Y = pos.Y, Z = pos.Z + 25}

    -- Spawn dual orbs: Air + Astral combined
    result.orbs = {}
    local dual_variants = {"Air", "Astral"}
    for _, v in ipairs(dual_variants) do
        pcall(function()
            local sys = StaticFindObject("/Game/Art/VFX/Library/Env/AnimaVent/" .. v .. "/NS_Anima_Loop_" .. v .. ".NS_Anima_Loop_" .. v)
            if sys and sys:IsValid() then
                local comp = niagaraLib:SpawnSystemAtLocation(
                    player, sys, orb_pos,
                    {Pitch = 0, Yaw = 0, Roll = 0},
                    {X = 1, Y = 1, Z = 1},
                    false, true, 0, false
                )
                if comp then
                    table.insert(result.orbs, comp)
                    print(string.format("[Harena] Aura: %s orb spawned\n", v))
                end
            end
        end)
    end
    result.orb = result.orbs[1]  -- keep reference for deactivation

    -- Fallback: try VFXMagic from vent data
    if not result.orb then
        local vent = FindFirstOf("BP_AnimaVent_C")
        if vent and vent:IsValid() then
            pcall(function()
                local vfx_data = vent:GetAnimaVentVFX()
                if vfx_data and vfx_data.VFXMagic and vfx_data.VFXMagic:IsValid() then
                    result.orb = niagaraLib:SpawnSystemAtLocation(
                        player, vfx_data.VFXMagic, orb_pos,
                        {Pitch = 0, Yaw = 0, Roll = 0},
                        {X = 1, Y = 1, Z = 1},
                        false, true, 0, false
                    )
                    print("[Harena] Aura: VFXMagic orb spawned (fallback)\n")
                end
            end)
        end
    end

    return result
end

function Powerups.setup()
    Powerups.spawns = {}
    Powerups.buffs = {}

    local player = FindFirstOf("BP_PlayerCharacter_C")
    local world = player and player:GetWorld() or nil

    -- Stagger anima spawns (500ms apart)
    for i, pos in ipairs(Config.POWERUP_POSITIONS) do
        table.insert(Powerups.spawns, {
            pos = pos,
            actor = nil,
            aura_torches = {},
            active = false,
            respawn_at = 0,
        })
        ExecuteWithDelay((i - 1) * 500, function()
            ExecuteInGameThread(function()
                pcall(function()
                    local actor = spawn_anima(pos)
                    if actor then
                        Powerups.spawns[i].actor = actor
                        Powerups.spawns[i].active = true
                        -- Spawn aura (vent beam + orb)
                        if world then
                            local aura_result = spawn_aura(pos, world)
                            Powerups.spawns[i].vent = aura_result.vent
                            Powerups.spawns[i].orb = aura_result.orb
                            Powerups.spawns[i].orbs = aura_result.orbs
                        end
                        print(string.format("[Harena] Powerup %d spawned with aura\n", i))
                    else
                        print(string.format("[Harena] Powerup %d FAILED to spawn\n", i))
                    end
                end)
            end)
        end)
    end
end

-- =============================================================================
-- Apply class-specific buff
-- =============================================================================
local function apply_buff(player, ctrl, player_id, class_name)
    Powerups.buffs[player_id] = {
        class = class_name,
        expire_time = os.time() + Config.POWERUP_BUFF_DURATION,
    }

    UI.send(ctrl, "[HARENA] POWERUP: " .. string.upper(class_name) .. " buff active!", 0, 1, 0.5)

    -- VFX
    pcall(function() player:DissolveTeleport() end)
    pcall(function() player:PlayRespawnVFX() end)

    if class_name == "archer" then
        -- Upgraded ammo (next tier)
        local pd_kills = 0
        pcall(function()
            local Match = require("match")
            local pd = Match.player_data[player_id]
            if pd then pd_kills = pd.weapon_tier or 0 end
        end)
        local ammo_tier = math.min(pd_kills + 1, 4)
        local ammo = Config.ARCHER_AMMO[ammo_tier]
        if ammo then
            ExecuteInGameThread(function()
                pcall(function()
                    local data = StaticFindObject(ammo)
                    if data then ctrl.BP_Components_Inventory:AddItemByData(data, 100, 1.0, {}) end
                end)
            end)
        end

    elseif class_name == "assassin" then
        -- Invisibility
        pcall(function() player:PlayDespawnVFX() end)
        ExecuteWithDelay(Config.POWERUP_BUFF_DURATION * 1000, function()
            ExecuteInGameThread(function()
                pcall(function()
                    if player and player:IsValid() then
                        player:PlayRespawnVFX()
                    end
                end)
            end)
        end)

    elseif class_name == "guardian" then
        -- +50 max HP
        pcall(function()
            player.BP_Components_Health:ModifyMaxHealth(50)
            local max = player.BP_Components_Health:GetMaxHealth()
            player.BP_Components_Health:SetHealth(max)
        end)

    elseif class_name == "berserker" then
        -- Weapon upgrade (next tier)
        local pd_tier = 1
        pcall(function()
            local Match = require("match")
            local pd = Match.player_data[player_id]
            if pd then pd_tier = pd.weapon_tier or 1 end
        end)
        local next_tier = math.min(pd_tier + 1, 4)
        local weapons = Config.CLASS_WEAP["berserker"][next_tier]
        if weapons then
            ExecuteInGameThread(function()
                pcall(function() ctrl.BP_Components_Inventory:ClearInventory() end)
                ExecuteWithDelay(500, function()
                    ExecuteInGameThread(function()
                        for _, w in ipairs(weapons) do
                            pcall(function()
                                local data = StaticFindObject(w)
                                if data then ctrl.BP_Components_Inventory:AddItemByData(data, 1, 1.0, {}) end
                            end)
                        end
                    end)
                end)
            end)
        end

    elseif class_name == "fire_mage" or class_name == "air_mage" then
        -- +30 max HP
        pcall(function()
            player.BP_Components_Health:ModifyMaxHealth(30)
            local max = player.BP_Components_Health:GetMaxHealth()
            player.BP_Components_Health:SetHealth(max)
        end)
    end

    -- VFX loop (green glitter while buffed)
    local buff_end = os.time() + Config.POWERUP_BUFF_DURATION
    LoopAsync(3000, function()
        if not is_world_valid() then return true end
        if os.time() >= buff_end then
            -- Remove buff
            Powerups.remove_buff(player, player_id, class_name)
            return true
        end
        pcall(function()
            if player and player:IsValid() then
                player:OnHealthPotionConsume()
            end
        end)
        return false
    end)
end

-- =============================================================================
-- Remove buff on expiry
-- =============================================================================
function Powerups.remove_buff(player, player_id, class_name)
    Powerups.buffs[player_id] = nil

    if class_name == "guardian" then
        pcall(function() player.BP_Components_Health:ModifyMaxHealth(-50) end)
    elseif class_name == "fire_mage" or class_name == "air_mage" then
        pcall(function() player.BP_Components_Health:ModifyMaxHealth(-30) end)
    end
end

-- =============================================================================
-- Proximity loop (runs during active match, checks pickup + respawn)
-- =============================================================================
function Powerups.start_proximity_loop(get_player_team_fn, player_data)
    LoopAsync(1000, function()
        if not is_world_valid() then return true end

        local ok_phase, phase = pcall(function()
            local Match = require("match")
            return Match.state.phase
        end)
        if not ok_phase or phase ~= "active" then return not ok_phase end

        local now = os.time()

        -- Respawn expired powerups (one at a time to avoid spam)
        for i, spawn in ipairs(Powerups.spawns) do
            if not spawn.active and now >= spawn.respawn_at then
                ExecuteInGameThread(function()
                    pcall(function()
                        local actor = spawn_anima(spawn.pos)
                        if actor then
                            spawn.actor = actor
                            spawn.active = true
                        end
                    end)
                end)
                break -- only respawn one per tick
            end
        end

        -- Check player proximity to active powerups
        local players = FindAllOf("BP_PlayerCharacter_C")
        if not players then return false end

        for _, player in pairs(players) do
            pcall(function()
                local ctrl = player:GetInstigatorController()
                if not ctrl or not ctrl:IsValid() then return end
                local pid = ctrl.PlayerState.PlayerId

                local loc = player:K2_GetActorLocation()
                if not loc then return end

                for i, spawn in ipairs(Powerups.spawns) do
                    if spawn.active then
                        local dx = loc.X - spawn.pos.X
                        local dy = loc.Y - spawn.pos.Y
                        local dist = math.sqrt(dx * dx + dy * dy)
                        if dist < Config.POWERUP_PICKUP_RADIUS then
                            -- Pickup! (allow multiple — refreshes timer)
                            spawn.active = false
                            spawn.respawn_at = now + Config.POWERUP_RESPAWN_TIME
                            -- Destroy anima pickup piece
                            if spawn.actor and spawn.actor:IsValid() then
                                pcall(function() spawn.actor:K2_DestroyActor() end)
                                spawn.actor = nil
                            end
                            -- Destroy orbs (keep vent beam)
                            if spawn.orbs then
                                for _, orb in ipairs(spawn.orbs) do
                                    pcall(function() orb:Deactivate() end)
                                end
                                spawn.orbs = {}
                            end
                            if spawn.orb then
                                pcall(function() spawn.orb:Deactivate() end)
                                spawn.orb = nil
                            end

                            -- Apply buff (refreshes if already buffed)
                            local pd = player_data[pid]
                            if pd and pd.class then
                                -- Clear previous buff timer by updating expire
                                Powerups.buffs[pid] = nil
                                apply_buff(player, ctrl, pid, pd.class)
                            end
                            break
                        end
                    end
                end
            end)
        end

        return false
    end)
end

-- =============================================================================
-- Cleanup
-- =============================================================================
function Powerups.cleanup()
    for _, spawn in ipairs(Powerups.spawns) do
        if spawn.actor and spawn.actor:IsValid() then
            pcall(function() spawn.actor:K2_DestroyActor() end)
        end
        if spawn.vent and spawn.vent:IsValid() then
            pcall(function() spawn.vent:K2_DestroyActor() end)
        end
        if spawn.orbs then
            for _, orb in ipairs(spawn.orbs) do
                pcall(function() orb:Deactivate() end)
            end
        end
    end
    Powerups.spawns = {}
    Powerups.buffs = {}
end

return Powerups
