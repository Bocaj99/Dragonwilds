--[[
    Harena v1 — Combat System
    Death detection, respawn (Multicast_Respawn), friendly fire prevention, kill tracking.
]]

local Config = require("config")
local Events = require("events")
local UI = require("ui")
local Combat = {}

if not _G.harena_hooks then _G.harena_hooks = {} end
Combat.respawn_hook_registered = _G.harena_hooks.respawn or false
Combat.death_hook_registered = _G.harena_hooks.death or false
Combat.ff_hook_registered = _G.harena_hooks.ff or false
Combat.spawn_indices = {red = 0, blue = 0}

-- =============================================================================
-- World validity guard
-- =============================================================================
function is_world_valid()
    local ok, player = pcall(function() return FindFirstOf("BP_PlayerCharacter_C") end)
    if not ok or not player or not player:IsValid() then return false end
    local ok2, world = pcall(function() return player:GetWorld() end)
    if not ok2 or not world or not world:IsValid() then return false end
    return true
end

-- =============================================================================
-- Set death timer on all players
-- =============================================================================
function Combat.set_respawn_delay(delay)
    local comps = FindAllOf("PlayerRespawnComponent")
    if not comps then return end
    for _, rc in pairs(comps) do
        pcall(function() rc.SelfReviveDelay = delay end)
    end
end

-- =============================================================================
-- Get random spawn for team
-- =============================================================================
function Combat.get_random_spawn(team)
    local spawns = Config.TEAM_SPAWN_RANDOM[team]
    if not spawns or #spawns == 0 then return nil end
    Combat.spawn_indices[team] = (Combat.spawn_indices[team] % #spawns) + 1
    return spawns[Combat.spawn_indices[team]]
end

-- =============================================================================
-- Register Multicast_Respawn hook (arena teleport on respawn)
-- =============================================================================
function Combat.register_respawn_hook(get_player_team_fn)
    if Combat.respawn_hook_registered then return end

    pcall(function()
        RegisterHook("/Script/Dominion.PlayerRespawnComponent:Multicast_Respawn", function(self, loc, rot)
            ExecuteWithDelay(500, function()
                ExecuteInGameThread(function()
                    pcall(function()
                        local player = FindFirstOf("BP_PlayerCharacter_C")
                        if not player or not player:IsValid() then return end

                        local ctrl = player:GetInstigatorController()
                        if not ctrl then return end
                        local pid = ctrl.PlayerState.PlayerId

                        local team = get_player_team_fn(pid)
                        if not team then return end

                        local spawn = Combat.get_random_spawn(team)
                        if not spawn then return end

                        local yaw = Config.TEAM_SPAWN_YAW[team] or 0
                        player:K2_SetActorLocationAndRotation(
                            spawn,
                            {Pitch = 0, Yaw = yaw, Roll = 0},
                            false, {}, true
                        )
                        player:PlayRespawnVFX()

                        Events.fire("player_respawned", {
                            player_id = pid,
                            team = team,
                            location = spawn,
                        })
                    end)
                end)
            end)
        end)
        Combat.respawn_hook_registered = true
        _G.harena_hooks.respawn = true
        print("[Harena] Multicast_Respawn hook registered\n")
    end)
end

-- =============================================================================
-- Register death hook (player death detection + kill tracking)
-- =============================================================================
function Combat.register_death_hook(get_player_team_fn)
    if Combat.death_hook_registered then return end

    pcall(function()
        RegisterHook("/Game/Gameplay/Character/Player/BP_PlayerCharacter.BP_PlayerCharacter_C:OnPlayerDeath", function(self)
            pcall(function()
                local victim = self:get()
                if not victim or not victim:IsValid() then return end
                local victim_ctrl = victim:GetInstigatorController()
                if not victim_ctrl then return end
                local victim_id = victim_ctrl.PlayerState.PlayerId
                -- FRESH reference every call (fixes stale closure bug)
                local Teams = require("teams")
                local victim_team = Teams.get_team(victim_id)

                -- Find killer from damage component
                local killer_id = nil
                local killer_team = nil
                pcall(function()
                    local dmg = victim.BP_Components_PlayerDamage
                    if dmg then
                        local lde = dmg.LastDamageEvent
                        if lde and lde.Instigator and lde.Instigator:IsValid() then
                            local killer = lde.Instigator
                            local killer_ctrl = killer:GetInstigatorController()
                            if killer_ctrl and killer_ctrl:IsValid() then
                                killer_id = killer_ctrl.PlayerState.PlayerId
                                killer_team = Teams.get_team(killer_id)
                            end
                        end
                    end
                end)

                -- Friendly fire check
                if killer_id and killer_team and victim_team and killer_team == victim_team then
                    -- Same team kill — heal victim back
                    pcall(function()
                        local max = victim.BP_Components_Health:GetMaxHealth()
                        victim.BP_Components_Health:SetHealth(max)
                        victim:PlayRespawnVFX()
                    end)
                    UI.send(victim_ctrl, "Friendly fire! Teammates can't hurt you.", 1, 0.5, 0)
                    return
                end

                -- Valid PvP kill
                Events.fire("player_killed", {
                    victim_id = victim_id,
                    victim_team = victim_team,
                    killer_id = killer_id,
                    killer_team = killer_team,
                })

                -- Track deaths/kills via fresh Match reference
                local Match = require("match")
                local pd = Match.player_data
                if pd[victim_id] then
                    pd[victim_id].deaths = (pd[victim_id].deaths or 0) + 1
                end
                if killer_id and pd[killer_id] then
                    pd[killer_id].kills = (pd[killer_id].kills or 0) + 1
                end

                -- Flag carrier death
                Events.fire("player_died", {
                    player_id = victim_id,
                    team = victim_team,
                    killer_id = killer_id,
                })
            end)
        end)
        Combat.death_hook_registered = true
        _G.harena_hooks.death = true
        print("[Harena] OnPlayerDeath hook registered\n")
    end)
end

-- =============================================================================
-- Register friendly fire prevention (OnDamageReceivedDynamic_Event)
-- =============================================================================
function Combat.register_ff_hook(get_player_team_fn)
    if Combat.ff_hook_registered then return end

    pcall(function()
        RegisterHook("/Game/Gameplay/Character/Player/BP_PlayerCharacter.BP_PlayerCharacter_C:OnDamageReceivedDynamic_Event", function(self, damageEvent)
            pcall(function()
                local victim = self:get()
                if not victim or not victim:IsValid() then return end
                local victim_ctrl = victim:GetInstigatorController()
                if not victim_ctrl then return end
                local victim_id = victim_ctrl.PlayerState.PlayerId

                -- Get attacker from damage event
                local de = damageEvent:get()
                if not de then return end

                local attacker_id = nil
                local is_player_attacker = false
                pcall(function()
                    -- Use LastDamageInstigatorServer on the victim's DamageComponent
                    local dmg_comp = victim.BP_Components_PlayerDamage
                    if not dmg_comp then return end
                    local last_ins = dmg_comp.LastDamageInstigatorServer
                    if last_ins and last_ins:IsValid() then
                        local ins_name = last_ins:GetFullName()
                        if ins_name:find("PlayerCharacter") then
                            is_player_attacker = true
                            local attacker_ctrl = last_ins:GetInstigatorController()
                            if attacker_ctrl and attacker_ctrl:IsValid() then
                                attacker_id = attacker_ctrl.PlayerState.PlayerId
                            end
                        end
                        print(string.format("[Harena] FF: attacker=P%s victim=P%d (from LastDamageInstigatorServer)\n",
                            tostring(attacker_id), victim_id))
                    else
                        print(string.format("[Harena] FF: LastDamageInstigatorServer nil for P%d\n", victim_id))
                    end
                end)

                -- Only process player-on-player damage
                if not is_player_attacker or not attacker_id then return end

                -- Get teams (fresh every call)
                local Teams = require("teams")
                local victim_team = Teams.get_team(victim_id)
                local attacker_team = Teams.get_team(attacker_id)

                -- Same team = heal back (FF protection)
                if victim_team and attacker_team and victim_team == attacker_team then
                    pcall(function()
                        local hp = victim.BP_Components_Health
                        local max = hp:GetMaxHealth()
                        hp:SetHealth(max, "FFHeal")

                        -- Also restore shield if possible
                        pcall(function()
                            local shield = victim.BP_Components_VitalShield
                            if shield then
                                local max_shield = shield.MaxShield
                                if max_shield and max_shield > 0 then
                                    shield.CurrentShield = max_shield
                                end
                            end
                        end)
                    end)
                    print(string.format("[Harena] FF BLOCKED: P%d(%s) -> P%d(%s) healed\n",
                        attacker_id, tostring(attacker_team), victim_id, tostring(victim_team)))
                else
                    -- Different team or no team = allow damage
                    print(string.format("[Harena] PvP HIT: P%d(%s) -> P%d(%s)\n",
                        attacker_id, tostring(attacker_team), victim_id, tostring(victim_team)))
                end
            end)
        end)
        Combat.ff_hook_registered = true
        _G.harena_hooks.ff = true
        print("[Harena] Friendly fire hook registered\n")
    end)
end

-- =============================================================================
-- Register AI death hook (PvE kill tracking)
-- =============================================================================
function Combat.register_ai_death_hook()
    if _G.harena_hooks.ai_death then return end
    pcall(function()
        RegisterHook("/Game/Gameplay/AI/BP_DominionAICharacter.BP_DominionAICharacter_C:BP_OnDeath", function(self)
            pcall(function()
                local mob = self:get()
                if not mob or not mob:IsValid() then return end

                local killer_id = nil
                pcall(function()
                    local dmg = mob.BP_AiDamageComponent
                    local lde = dmg.LastDamageEvent
                    if lde and lde.Instigator and lde.Instigator:IsValid() then
                        local killer = lde.Instigator
                        local killer_ctrl = killer:GetInstigatorController()
                        if killer_ctrl then
                            killer_id = killer_ctrl.PlayerState.PlayerId
                        end
                    end
                end)

                local mob_class = mob:GetClass():GetFullName()
                Events.fire("ai_killed", {
                    mob_class = mob_class,
                    killer_id = killer_id,
                })
            end)
        end)
        _G.harena_hooks.ai_death = true
        print("[Harena] AI death hook registered\n")
    end)
end

-- =============================================================================
-- Init
-- =============================================================================
-- =============================================================================
-- PvP toggle via bIsPvpEnabled on PlayerDamageComponent (per-player)
-- =============================================================================
function Combat.set_pvp_all(enabled)
    local players = FindAllOf("BP_PlayerCharacter_C")
    if not players then return end
    for _, player in pairs(players) do
        pcall(function()
            local dmgComp = player.BP_Components_PlayerDamage
            if dmgComp and dmgComp:IsValid() then
                dmgComp.bIsPvpEnabled = enabled
                pcall(function() dmgComp:OnRep_bIsPvpEnabled() end)
            end
        end)
    end
    print(string.format("[Harena] PvP %s for all players\n", enabled and "ENABLED" or "DISABLED"))
end

function Combat.init()
    local Teams = require("teams")
    local get_team = Teams.get_team

    Combat.set_respawn_delay(Config.RESPAWN_DELAY)
    Combat.register_respawn_hook(get_team)
    Combat.register_death_hook(get_team)
    Combat.register_ff_hook(get_team)
    Combat.register_ai_death_hook()
    -- Disable PvP by default (enabled when match starts)
    Combat.set_pvp_all(false)
end

return Combat
