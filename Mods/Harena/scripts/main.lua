--[[
    Harena v1 — Main Entry Point
    3v3 Capture the Flag for RuneScape: Dragonwilds
    Architecture 2.0: Event-driven, modular, persistent buildings.
]]

local MOD_NAME = "Harena"

print(string.format("[%s] Loading...\n", MOD_NAME))

-- =============================================================================
-- Load modules
-- =============================================================================
local Config      = require("config")
local Events      = require("events")
local UI          = require("ui")
local Buildings   = require("buildings")
local Combat      = require("combat")
local Teams       = require("teams")
local Classes     = require("classes")
local Flags       = require("flags")
local Match       = require("match")
local Scoreboard  = require("scoreboard")
local Progression = require("progression")
local PvE         = require("pve")
local Powerups    = require("powerups")
local Admin       = require("admin")

-- =============================================================================
-- World validity guard (global, used by all LoopAsync loops)
-- =============================================================================
function is_world_valid()
    local ok, player = pcall(function() return FindFirstOf("BP_PlayerCharacter_C") end)
    if not ok or not player or not player:IsValid() then return false end
    local ok2, world = pcall(function() return player:GetWorld() end)
    if not ok2 or not world or not world:IsValid() then return false end
    return true
end

-- =============================================================================
-- Startup sequence (wait for player to load in)
-- =============================================================================
local function on_player_ready()
    print(string.format("[%s] Player in world, initializing...\n", MOD_NAME))

    -- 1. Building protection + stability disable
    ExecuteWithDelay(2000, function()
        ExecuteInGameThread(function()
            Buildings.init()
        end)
    end)

    -- 2. Register combat hooks + progression + PvE
    ExecuteWithDelay(3000, function()
        ExecuteInGameThread(function()
            Combat.init()
            Progression.init()
            PvE.init()
        end)
    end)

    -- 3. Auto-teleport to bed lobby
    ExecuteWithDelay(5000, function()
        ExecuteInGameThread(function()
            pcall(function()
                local player = FindFirstOf("BP_PlayerCharacter_C")
                if player and player:IsValid() then
                    player:K2_SetActorLocation(Config.BED_LOBBY, false, {}, true)
                    UI.send(player, "[HARENA] Welcome! Teleported to lobby.", 1, 0.8, 0)
                end
            end)
        end)
    end)

    -- 4. Register admin keybinds
    Admin.register_keybinds()

    -- 5. Player join detector — auto-teleport new players to bed lobby
    local known_players = {}
    LoopAsync(3000, function()
        if not is_world_valid() then return true end
        local players = FindAllOf("BP_PlayerCharacter_C")
        if not players then return false end
        for _, p in pairs(players) do
            pcall(function()
                local ctrl = p:GetInstigatorController()
                if ctrl and ctrl:IsValid() then
                    local pid = ctrl.PlayerState.PlayerId
                    if not known_players[pid] then
                        known_players[pid] = true
                        -- New player detected — teleport to lobby
                        ExecuteInGameThread(function()
                            pcall(function()
                                p:K2_SetActorLocation(Config.BED_LOBBY, false, {}, true)
                                p:PlayRespawnVFX()
                                UI.send(ctrl, "[HARENA] Welcome! Teleported to lobby.", 1, 0.8, 0)
                                print(string.format("[Harena] New player P%d teleported to lobby\n", pid))
                            end)
                        end)
                    end
                end
            end)
        end
        return false
    end)

    print(string.format("[%s] Initialization complete.\n", MOD_NAME))
end

-- Wait for player to enter world
LoopAsync(2000, function()
    local player = FindFirstOf("BP_PlayerCharacter_C")
    if player and player:IsValid() then
        on_player_ready()
        return true -- stop polling
    end
    return false
end)

-- =============================================================================
-- Event listeners
-- =============================================================================

-- Flag carrier death: return flag to base
Events.on("player_died", function(data)
    if Match.state.phase ~= "active" then return end
    local carrying = Flags.is_carrying(data.player_id)
    if carrying then
        Flags.return_to_base(carrying)
        -- Restore carrier gear
        local pd = Match.player_data[data.player_id]
        if pd then
            pcall(function()
                local players = FindAllOf("BP_PlayerCharacter_C")
                if not players then return end
                for _, p in pairs(players) do
                    local ctrl = p:GetInstigatorController()
                    if ctrl and ctrl.PlayerState.PlayerId == data.player_id then
                        -- Unlock inventory for respawn re-equip
                        pcall(function()
                            ctrl.BP_Components_Inventory.bAllowRemoves = true
                            ctrl.BP_Components_Inventory.bAllowAdds = true
                        end)
                        break
                    end
                end
            end)
        end
    end
end)

-- Match win via torch lead
Events.on("match_win", function(data)
    Match.end_match("torch_lead")
end)

-- Flag captured: update player data + restore carrier
Events.on("flag_captured", function(data)
    local pd = Match.player_data[data.carrier_id]
    if pd then
        pd.flags = (pd.flags or 0) + 1
    end

    -- Restore carrier gear
    pcall(function()
        local players = FindAllOf("BP_PlayerCharacter_C")
        if not players then return end
        for _, p in pairs(players) do
            local ctrl = p:GetInstigatorController()
            if ctrl and ctrl.PlayerState.PlayerId == data.carrier_id then
                -- Unlock inventory
                ctrl.BP_Components_Inventory.bAllowRemoves = true
                ctrl.BP_Components_Inventory.bAllowAdds = true
                ctrl.BP_Components_Loadout.bAllowRemoves = true
                ctrl.BP_Components_Loadout.bAllowAdds = true
                -- Restore stamina
                pcall(function() p.BP_Components_Stamina:SetMaxStamina(100) end)
                -- Re-equip
                if pd and pd.specialized then
                    Classes.equip_class_gear(ctrl, pd.team, pd.class, pd.armor_tier, pd.weapon_tier)
                else
                    Classes.equip_base_kit(ctrl, pd.team)
                end
                break
            end
        end
    end)
end)

-- =============================================================================
-- KEYBINDS
-- =============================================================================

-- MATCH
RegisterKeyBind(Key.F5, function()
    ExecuteInGameThread(function()
        local phase = Match.state.phase
        if phase == "idle" then
            Match.start()
        elseif phase == "team_select" then
            -- Fast track: auto-assign remaining, skip to class select
            UI.announce("Fast tracking to class selection!")
            Match.auto_assign_remaining()
            Match.start_class_select()
        elseif phase == "class_select" then
            -- Fast track: default unselected to archer, skip to preparation
            UI.announce("Fast tracking to preparation!")
            Match.start_preparation()
        elseif phase == "preparation" then
            UI.announce("Already preparing!")
        elseif phase == "active" then
            UI.announce("Match in progress!")
        end
    end)
end)

RegisterKeyBind(Key.ZERO, function()
    ExecuteInGameThread(function()
        Match.reset()
        -- Also clear all player loadouts
        local players = FindAllOf("BP_PlayerCharacter_C")
        if players then
            for _, p in pairs(players) do
                pcall(function()
                    local ctrl = p:GetInstigatorController()
                    if ctrl and ctrl:IsValid() then
                        pcall(function() ctrl.BP_Components_Inventory.bAllowRemoves = true end)
                        pcall(function() ctrl.BP_Components_Inventory.bAllowAdds = true end)
                        pcall(function() ctrl.BP_Components_Loadout.bAllowRemoves = true end)
                        pcall(function() ctrl.BP_Components_Loadout.bAllowAdds = true end)
                        pcall(function() ctrl.BP_Components_Inventory:ClearInventory() end)
                        pcall(function() ctrl.BP_Components_Loadout:ClearInventory() end)
                    end
                end)
            end
        end
        UI.announce("Match + loadouts reset!")
    end)
end)

RegisterKeyBind(Key.CAPS_LOCK, function()
    Scoreboard.toggle()
end)

-- ADMIN
RegisterKeyBind(Key.F1, function()
    -- Teleport all to host
    ExecuteInGameThread(function()
        local host = FindFirstOf("BP_PlayerCharacter_C")
        if not host then return end
        local host_loc = host:K2_GetActorLocation()
        local players = FindAllOf("BP_PlayerCharacter_C")
        if not players then return end
        local delay = 0
        for _, p in pairs(players) do
            ExecuteWithDelay(delay, function()
                ExecuteInGameThread(function()
                    pcall(function() p:K2_SetActorLocation(host_loc, false, {}, true) end)
                end)
            end)
            delay = delay + Config.TELEPORT_STAGGER
        end
        UI.announce("All players teleported to host.")
    end)
end)

RegisterKeyBind(Key.F2, function()
    -- Kill mobs within 5000 units of player
    ExecuteInGameThread(function()
        local player = FindFirstOf("BP_PlayerCharacter_C")
        if not player then return end
        local ploc = player:K2_GetActorLocation()
        if not ploc then return end

        local mobs = FindAllOf("BP_DominionAICharacter_C")
        if not mobs then UI.announce("No mobs found.") return end
        local count = 0
        local delay = 0
        for _, mob in pairs(mobs) do
            pcall(function()
                local mloc = mob:K2_GetActorLocation()
                if mloc then
                    local dx = mloc.X - ploc.X
                    local dy = mloc.Y - ploc.Y
                    local dist = math.sqrt(dx*dx + dy*dy)
                    if dist < 5000 then
                        ExecuteWithDelay(delay, function()
                            ExecuteInGameThread(function()
                                pcall(function() mob:K2_DestroyActor() end)
                            end)
                        end)
                        delay = delay + Config.MOB_DESTROY_STAGGER
                        count = count + 1
                    end
                end
            end)
        end
        UI.announce(count .. " nearby mobs destroyed.")
    end)
end)

RegisterKeyBind(Key.F4, function()
    -- Show coordinates
    ExecuteInGameThread(function()
        local player = FindFirstOf("BP_PlayerCharacter_C")
        if not player then return end
        local loc = player:K2_GetActorLocation()
        if loc then
            local msg = string.format("[POS] X=%.0f Y=%.0f Z=%.0f", loc.X, loc.Y, loc.Z)
            print("[Harena] " .. msg .. "\n")
            UI.send(player, msg, 0.5, 1, 0.5)
        end
    end)
end)

-- DEBUG
RegisterKeyBind(Key.I, function()
    -- Toggle TP between flag areas
    ExecuteInGameThread(function()
        local player = FindFirstOf("BP_PlayerCharacter_C")
        if not player then return end
        Match._flag_tp_toggle = not Match._flag_tp_toggle
        local pos, label
        if Match._flag_tp_toggle then
            pos = Config.FLAG_POSITIONS.red
            label = "RED FLAG AREA"
        else
            pos = Config.FLAG_POSITIONS.blue
            label = "BLUE FLAG AREA"
        end
        pcall(function()
            player:K2_SetActorLocation(pos, false, {}, true)
            player:PlayRespawnVFX()
        end)
        UI.send(player, "TP: " .. label, 1, 1, 0)
    end)
end)

Match._flag_tp_toggle = false

-- =============================================================================
-- Done
-- =============================================================================
print(string.format("[%s] Loaded! F5=Start Match | 0=Reset | Caps=Scoreboard\n", MOD_NAME))
