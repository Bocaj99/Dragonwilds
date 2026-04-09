--[[
    Harena v1 — Flag System
    Torch-based CTF: spawn, pickup, capture, return on death.
]]

local Config = require("config")
local Events = require("events")
local UI = require("ui")
local Flags = {}

Flags.state = {
    red  = {status = "at_base", carrier = nil, torch_actor = nil},
    blue = {status = "at_base", carrier = nil, torch_actor = nil},
}

Flags.torch_lead = 0  -- -3 to +3 (negative = blue leads)

-- =============================================================================
-- Torch spawn/destroy
-- =============================================================================
function Flags.spawn_torch(team)
    local pos = Config.FLAG_POSITIONS[team]
    local player = FindFirstOf("BP_PlayerCharacter_C")
    if not player then return nil end
    local world = player:GetWorld()
    if not world then return nil end

    local color = (team == "red") and "Red" or "Blue"
    local existing = FindFirstOf("BP_BaseBuilding_TorchStanding_" .. color .. "_C")
    if not existing or not existing:IsValid() then
        existing = FindFirstOf("BP_BaseBuilding_TorchStanding_C")
    end
    if not existing or not existing:IsValid() then return nil end

    local bpClass = existing:GetClass()
    local ok, actor = pcall(function() return world:SpawnActor(bpClass, pos, {}) end)
    if ok and actor and actor:IsValid() then
        pcall(function() actor:K2_SetActorLocation(pos, false, {}, true) end)
        Flags.state[team].torch_actor = actor
        return actor
    end
    return nil
end

function Flags.destroy_torch(team)
    local flag = Flags.state[team]
    if flag.torch_actor and flag.torch_actor:IsValid() then
        pcall(function() flag.torch_actor:K2_DestroyActor() end)
        flag.torch_actor = nil
    end
end

-- =============================================================================
-- Flag lifecycle
-- =============================================================================
function Flags.setup()
    Flags.spawn_torch("red")
    Flags.spawn_torch("blue")
    Flags.torch_lead = 0
end

function Flags.pickup(flag_team, carrier_id, carrier_ref, carrier_ctrl)
    local flag = Flags.state[flag_team]
    Flags.destroy_torch(flag_team)
    flag.status = "carried"
    flag.carrier = carrier_id

    -- Give carrier a torch item (v3 mechanic: clear → 500ms → add torch → equip → lock)
    pcall(function()
        if carrier_ref and carrier_ref:IsValid() and carrier_ctrl and carrier_ctrl:IsValid() then
            local torch_data = StaticFindObject(Config.TORCH_ITEM)
            if torch_data and torch_data:IsValid() then
                -- Step 1: Unlock + clear everything
                ExecuteInGameThread(function()
                    pcall(function() carrier_ctrl.BP_Components_Inventory.bAllowRemoves = true end)
                    pcall(function() carrier_ctrl.BP_Components_Inventory.bAllowAdds = true end)
                    pcall(function() carrier_ctrl.BP_Components_Loadout.bAllowRemoves = true end)
                    pcall(function() carrier_ctrl.BP_Components_Loadout.bAllowAdds = true end)
                    pcall(function() carrier_ctrl.BP_Components_Loadout:ClearInventory() end)
                    pcall(function() carrier_ctrl.BP_Components_Inventory:ClearInventory() end)
                end)
                -- Step 2: Add torch + auto-equip after 500ms
                ExecuteWithDelay(500, function()
                    ExecuteInGameThread(function()
                        pcall(function()
                            carrier_ctrl.BP_Components_Inventory:AddItemByData(torch_data, 1, 1.0, {})
                            -- Auto-equip torch by scanning slots
                            local inv = carrier_ctrl.BP_Components_Inventory
                            local invCtrl = carrier_ctrl.BP_Components_InventoryController
                            if invCtrl then
                                for idx = 0, 15 do
                                    local ok2, item = pcall(function() return inv:GetItemFromSlot(idx) end)
                                    if ok2 and item and item:IsValid() then
                                        pcall(function() invCtrl:UseItemFromInventory(inv, idx) end)
                                        break
                                    end
                                end
                            end
                        end)
                        -- Step 3: Lock inventory 300ms after equip
                        ExecuteWithDelay(300, function()
                            ExecuteInGameThread(function()
                                pcall(function() carrier_ctrl.BP_Components_Inventory.bAllowRemoves = false end)
                                pcall(function() carrier_ctrl.BP_Components_Inventory.bAllowAdds = false end)
                                pcall(function() carrier_ctrl.BP_Components_Loadout.bAllowRemoves = false end)
                                pcall(function() carrier_ctrl.BP_Components_Loadout.bAllowAdds = false end)
                            end)
                        end)
                    end)
                end)
            end
        end
    end)

    -- Block sprint (set max stamina to 0)
    pcall(function()
        if carrier_ref and carrier_ref:IsValid() then
            local stamina = carrier_ref.BP_Components_Stamina
            if stamina and stamina:IsValid() then
                pcall(function() stamina:SetStamina(0) end)
                pcall(function() stamina:SetMaxStamina(0) end)
            end
        end
    end)

    UI.broadcast(string.format("[HARENA] %s FLAG TAKEN!", string.upper(flag_team)), 1, 1, 0)
    Events.fire("flag_pickup", {team = flag_team, carrier_id = carrier_id})
end

function Flags.capture(flag_team, carrier_team, carrier_id)
    local flag = Flags.state[flag_team]
    flag.status = "at_base"
    flag.carrier = nil

    -- Update scores
    local teams_module = require("teams")
    teams_module.data[carrier_team].captures = teams_module.data[carrier_team].captures + 1

    -- Update torch lead
    if carrier_team == "red" then
        Flags.torch_lead = math.min(Flags.torch_lead + 1, Config.TORCH_WIN_LEAD)
    else
        Flags.torch_lead = math.max(Flags.torch_lead - 1, -Config.TORCH_WIN_LEAD)
    end

    -- Respawn flag torch at enemy base
    Flags.spawn_torch(flag_team)

    -- Restore carrier
    Events.fire("flag_captured", {
        flag_team = flag_team,
        carrier_team = carrier_team,
        carrier_id = carrier_id,
        torch_lead = Flags.torch_lead,
    })

    UI.broadcast(string.format("[HARENA] ===== %s CAPTURES! =====", string.upper(carrier_team)), 1, 0.8, 0)

    -- Check win condition
    if math.abs(Flags.torch_lead) >= Config.TORCH_WIN_LEAD then
        local winner = Flags.torch_lead > 0 and "red" or "blue"
        Events.fire("match_win", {winner = winner, reason = "torch_lead"})
    end
end

function Flags.return_to_base(flag_team)
    local flag = Flags.state[flag_team]
    flag.status = "at_base"
    flag.carrier = nil
    Flags.spawn_torch(flag_team)
    UI.broadcast(string.format("[HARENA] %s flag returned to base!", string.upper(flag_team)), 1, 0.5, 0)
end

function Flags.is_carrying(player_id)
    for team, flag in pairs(Flags.state) do
        if flag.carrier == player_id then return team end
    end
    return nil
end

function Flags.get_carrier(team)
    return Flags.state[team].carrier
end

-- =============================================================================
-- Proximity polling (500ms during active match)
-- =============================================================================
function Flags.start_proximity_loop(get_player_team_fn, player_data)
    LoopAsync(500, function()
        if not is_world_valid() then return true end

        local ok_phase, phase = pcall(function()
            local match = require("match")
            return match.state.phase
        end)
        if not ok_phase or phase ~= "active" then return not ok_phase end

        local players = FindAllOf("BP_PlayerCharacter_C")
        if not players then return false end

        for _, player in pairs(players) do
            pcall(function()
                local ctrl = player:GetInstigatorController()
                if not ctrl or not ctrl:IsValid() then return end
                local pid = ctrl.PlayerState.PlayerId
                local team = get_player_team_fn(pid)
                if not team then return end

                local loc = player:K2_GetActorLocation()
                if not loc then return end

                -- Check flag pickup (enemy flag)
                local enemy_team = team == "red" and "blue" or "red"
                local enemy_flag = Flags.state[enemy_team]
                if enemy_flag.status == "at_base" then
                    local flag_pos = Config.FLAG_POSITIONS[enemy_team]
                    local dx = loc.X - flag_pos.X
                    local dy = loc.Y - flag_pos.Y
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist < Config.FLAG_PICKUP_RADIUS then
                        Flags.pickup(enemy_team, pid, player, ctrl)
                    end
                end

                -- Check flag capture (own base while carrying enemy flag)
                local carrying = Flags.is_carrying(pid)
                if carrying then
                    local own_pos = Config.FLAG_POSITIONS[team]
                    local dx = loc.X - own_pos.X
                    local dy = loc.Y - own_pos.Y
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist < Config.FLAG_CAPTURE_RADIUS then
                        Flags.capture(carrying, team, pid)
                    end
                end
            end)
        end
        return false
    end)
end

function Flags.cleanup()
    Flags.destroy_torch("red")
    Flags.destroy_torch("blue")
    Flags.state.red = {status = "at_base", carrier = nil, torch_actor = nil}
    Flags.state.blue = {status = "at_base", carrier = nil, torch_actor = nil}
    Flags.torch_lead = 0
end

return Flags
