--[[
    Harena v1 — Match State Machine
    Phases: idle → team_select → class_select → preparation → active → ended

    Flow:
    1. Players load in → auto-TP to bed lobby
    2. F5 or 6 players detected → "Match commencing!" → team_select
    3. Team Selection (60s): walk to lodestone, bed auto-claimed, TP to class lobby
    4. Class Selection (60s): walk to class lodestone in team lobby
    5. Preparation (20s): flags spawn staggered, base kit equip, countdown
    6. Active (18 min): arena teleport, match begins
    7. Ended: winner announced, TP to lobby
]]

local Config = require("config")
local Events = require("events")
local UI = require("ui")
local Teams = require("teams")
local Classes = require("classes")
local Flags = require("flags")
local Scoreboard = require("scoreboard")
local Buildings = require("buildings")
local Match = {}

Match.state = {
    phase = "idle",
    match_time = 0,
    pve_event = 0,
    start_time = nil,
    timer_display = "0:00",
}

Match.player_data = {}
Match._flag_tp_toggle = false
Match._last_countdown = nil
Match._class_select_loop = false

-- =============================================================================
-- Phase transitions
-- =============================================================================
function Match.set_phase(phase)
    local old = Match.state.phase
    Match.state.phase = phase
    Events.fire("phase_changed", {from = old, to = phase})
    print(string.format("[Harena] Phase: %s → %s\n", old, phase))
end

-- =============================================================================
-- START MATCH (F5 or auto when 6 players)
-- =============================================================================
function Match.start()
    if Match.state.phase ~= "idle" then
        UI.announce("Match already in progress!")
        return
    end

    Teams.reset()
    Match.player_data = {}
    Match.state.pve_event = 0

    UI.announce("Match commencing soon!")
    UI.announce("Walk to a team lodestone: RED | BLUE | RANDOM")

    Match.set_phase("team_select")
    Match.start_team_select()
end

-- =============================================================================
-- PHASE 1: TEAM SELECTION (60s)
-- =============================================================================
function Match.start_team_select()
    local selection_start = os.time()
    local duration = Config.LOBBY_DURATION

    LoopAsync(500, function()
        if not is_world_valid() then return true end
        if Match.state.phase ~= "team_select" then return true end

        local elapsed = os.time() - selection_start
        local remaining = duration - elapsed

        -- Time's up: auto-assign unassigned players
        if remaining <= 0 then
            Match.auto_assign_remaining()
            Match.start_class_select()
            return true
        end

        -- Check all players against team lodestones
        local players = FindAllOf("BP_PlayerCharacter_C")
        if not players then return false end

        for _, player in pairs(players) do
            pcall(function()
                local ctrl = player:GetInstigatorController()
                if not ctrl or not ctrl:IsValid() then return end
                local pid = ctrl.PlayerState.PlayerId
                if Teams.get_team(pid) then return end -- already assigned

                local loc = player:K2_GetActorLocation()
                if not loc then return end

                for team_name, team_pos in pairs(Config.TEAM_SELECT) do
                    local dx = loc.X - team_pos.X
                    local dy = loc.Y - team_pos.Y
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist < Config.LODESTONE_RADIUS then
                        local assigned_team = team_name
                        if team_name == "random" then
                            assigned_team = Teams.assign_random(pid, player)
                        else
                            if Teams.count(team_name) < 3 then
                                Teams.add_player(team_name, pid, player)
                                assigned_team = team_name
                            else
                                UI.send(ctrl, string.upper(team_name) .. " team is full!", 1, 0.2, 0.2)
                                return
                            end
                        end

                        UI.send(ctrl, "Joined " .. string.upper(assigned_team) .. " team!", 1, 0.8, 0)

                        -- Auto-claim bed
                        Buildings.claim_beds_for_team(assigned_team, Teams.get_player_refs(assigned_team))

                        -- Teleport to class lobby
                        local lobbies = Config.TEAM_LOBBY_SPAWNS[assigned_team]
                        if lobbies and #lobbies > 0 then
                            local slot = Teams.count(assigned_team)
                            local lobby_pos = lobbies[((slot - 1) % #lobbies) + 1]
                            ExecuteInGameThread(function()
                                pcall(function()
                                    player:K2_SetActorLocation(lobby_pos, false, {}, true)
                                    player:PlayRespawnVFX()
                                end)
                            end)
                        end

                        -- Check if all players assigned (early transition)
                        local total = Teams.count("red") + Teams.count("blue")
                        if total >= 6 then
                            UI.announce("All players assigned! Moving to class selection.")
                            Match.start_class_select()
                            return
                        end

                        break
                    end
                end
            end)
        end

        -- Display remaining time every 15 seconds
        if remaining % 15 == 0 and remaining > 0 then
            UI.broadcast(string.format("Team selection: %ds remaining", remaining), 1, 0.8, 0)
        end

        return false
    end)
end

-- =============================================================================
-- Auto-assign unassigned players to random teams
-- =============================================================================
function Match.auto_assign_remaining()
    local players = FindAllOf("BP_PlayerCharacter_C")
    if not players then return end
    for _, p in pairs(players) do
        pcall(function()
            local ctrl = p:GetInstigatorController()
            if ctrl and ctrl:IsValid() then
                local pid = ctrl.PlayerState.PlayerId
                if not Teams.get_team(pid) then
                    local team = Teams.assign_random(pid, p)
                    UI.send(ctrl, "Auto-assigned to " .. string.upper(team) .. " team!", 1, 0.5, 0)
                    Buildings.claim_beds_for_team(team, Teams.get_player_refs(team))
                    -- Teleport to class lobby
                    local lobbies = Config.TEAM_LOBBY_SPAWNS[team]
                    if lobbies and #lobbies > 0 then
                        local slot = Teams.count(team)
                        local lobby_pos = lobbies[((slot - 1) % #lobbies) + 1]
                        ExecuteInGameThread(function()
                            pcall(function()
                                p:K2_SetActorLocation(lobby_pos, false, {}, true)
                            end)
                        end)
                    end
                end
            end
        end)
    end
end

-- =============================================================================
-- PHASE 2: CLASS SELECTION (60s)
-- =============================================================================
function Match.start_class_select()
    if Match.state.phase == "class_select" then return end -- prevent double trigger
    Match.set_phase("class_select")

    UI.announce("Choose your class! Walk to a class lodestone.")
    UI.broadcast("ARCHER | ASSASSIN | GUARDIAN | BERSERKER | FIRE MAGE | AIR MAGE", 1, 0.8, 0)

    local selection_start = os.time()
    local duration = Config.LOBBY_DURATION

    LoopAsync(500, function()
        if not is_world_valid() then return true end
        if Match.state.phase ~= "class_select" then return true end

        local elapsed = os.time() - selection_start
        local remaining = duration - elapsed

        if remaining <= 0 then
            Match.start_preparation()
            return true
        end

        -- Check players against class lodestones
        local players = FindAllOf("BP_PlayerCharacter_C")
        if not players then return false end

        for _, player in pairs(players) do
            pcall(function()
                local ctrl = player:GetInstigatorController()
                if not ctrl or not ctrl:IsValid() then return end
                local pid = ctrl.PlayerState.PlayerId
                local team = Teams.get_team(pid)
                if not team then return end

                local loc = player:K2_GetActorLocation()
                if not loc then return end

                -- Check class lodestones for this player's team
                local class_stones = Config.CLASS_LODESTONES[team]
                if not class_stones then return end

                for class_name, stone_pos in pairs(class_stones) do
                    local dx = loc.X - stone_pos.X
                    local dy = loc.Y - stone_pos.Y
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist < Config.LODESTONE_RADIUS then
                        -- Initialize player data if needed
                        if not Match.player_data[pid] then
                            Match.player_data[pid] = {
                                team = team, class = nil, kills = 0, deaths = 0,
                                flags = 0, specialized = false, weapon_tier = 0,
                                armor_tier = 0, trinket_earned = false, name = "Player",
                            }
                        end

                        -- Skip if same class already selected (avoid re-equip spam)
                        if Match.player_data[pid].class == class_name then break end

                        Match.player_data[pid].class = class_name
                        UI.send(ctrl, "Selected " .. Config.CLASS_DISPLAY[class_name] .. "!", 0, 1, 0)
                        print(string.format("[Harena] P%d selected class: %s\n", pid, class_name))

                        -- T6 armor preview disabled on dedicated server (causes disconnects)
                        -- Equip happens during preparation phase instead
                        break
                    end
                end
            end)
        end

        -- Display time remaining every 15s
        if remaining % 15 == 0 and remaining > 0 then
            UI.broadcast(string.format("Class selection: %ds remaining", remaining), 1, 0.8, 0)
        end

        return false
    end)
end

-- =============================================================================
-- PHASE 3: PREPARATION (20s — flags spawn, base kit equip, countdown)
-- =============================================================================
function Match.start_preparation()
    Match.set_phase("preparation")

    -- Init player data for anyone without a class (default to archer)
    for _, team_name in ipairs({"red", "blue"}) do
        for _, p in ipairs(Teams.data[team_name].players) do
            if not Match.player_data[p.id] then
                Match.player_data[p.id] = {
                    team = team_name, class = "archer", kills = 0, deaths = 0,
                    flags = 0, specialized = false, weapon_tier = 0,
                    armor_tier = 0, trinket_earned = false, name = "Player",
                }
            elseif not Match.player_data[p.id].class then
                Match.player_data[p.id].class = "archer"
                UI.send(p.ref and p.ref:GetInstigatorController(), "Auto-assigned class: ARCHER", 1, 0.5, 0)
            end
        end
    end

    -- Block windstep
    Classes.block_windstep()

    UI.announce("Preparing arena...")

    -- Spawn flags staggered (5s apart, at 0s and 5s into preparation)
    ExecuteWithDelay(0, function()
        ExecuteInGameThread(function()
            pcall(function()
                Flags.spawn_torch("red")
                print("[Harena] Red flag spawned\n")
            end)
        end)
    end)

    ExecuteWithDelay(5000, function()
        ExecuteInGameThread(function()
            pcall(function()
                Flags.spawn_torch("blue")
                print("[Harena] Blue flag spawned\n")
            end)
        end)
    end)

    -- Spawn arena trees at 2s (staggered, skip if already spawned)
    ExecuteWithDelay(2000, function()
        ExecuteInGameThread(function()
            local player = FindFirstOf("BP_PlayerCharacter_C")
            if not player then return end
            local world = player:GetWorld()
            if not world then return end

            -- Check if trees already exist (from previous match or T key)
            if Match._trees_spawned then
                print("[Harena] Arena trees already spawned, skipping\n")
                return
            end
            Match._trees_spawned = true

            local count = 0
            local delay = 0
            for _, tree_def in ipairs(Config.ARENA_TREES or {}) do
                ExecuteWithDelay(delay, function()
                    ExecuteInGameThread(function()
                        pcall(function()
                            local existing = FindFirstOf(tree_def.class)
                            if existing and existing:IsValid() then
                                local cls = existing:GetClass()
                                local t = world:SpawnActor(cls, tree_def.pos, {})
                                if t and t:IsValid() then
                                    local yaw = tree_def.yaw or 0
                                    t:K2_SetActorLocationAndRotation(
                                        tree_def.pos,
                                        {Pitch = 0, Yaw = yaw, Roll = 0},
                                        false, {}, true
                                    )
                                end
                            end
                        end)
                    end)
                end)
                delay = delay + 200
            end
            print(string.format("[Harena] Arena trees spawning (%d queued)\n", #(Config.ARENA_TREES or {})))
        end)
    end)

    -- Spawn powerups at 7s into preparation
    ExecuteWithDelay(7000, function()
        ExecuteInGameThread(function()
            local Powerups = require("powerups")
            Powerups.setup()
            print("[Harena] Powerups spawned during preparation\n")
        end)
    end)

    -- Equip base kit at 10s (10s before GO)
    ExecuteWithDelay(10000, function()
        UI.announce("Equipping base kit...")
        local delay = 0
        for _, team_name in ipairs({"red", "blue"}) do
            for _, p in ipairs(Teams.data[team_name].players) do
                ExecuteWithDelay(delay, function()
                    ExecuteInGameThread(function()
                        pcall(function()
                            if p.ref and p.ref:IsValid() then
                                local ctrl = p.ref:GetInstigatorController()
                                if ctrl then
                                    Classes.equip_base_kit(ctrl, team_name)
                                end
                            end
                        end)
                    end)
                end)
                delay = delay + Config.EQUIP_STAGGER
            end
        end
    end)

    -- Countdown starts at 10s remaining (10s into preparation)
    ExecuteWithDelay(10000, function()
        local countdown_start = os.time()
        LoopAsync(200, function()
            if not is_world_valid() then return true end
            local elapsed = os.time() - countdown_start
            local remaining = 10 - elapsed
            if remaining <= 0 then
                Match.go()
                return true
            end
            if remaining ~= Match._last_countdown then
                Match._last_countdown = remaining
                UI.broadcast(string.format("Starting in %d...", remaining), 1, 0.8, 0)
            end
            return false
        end)
    end)
end

-- =============================================================================
-- GO! (match active)
-- =============================================================================
function Match.go()
    Match.set_phase("active")
    Match.state.start_time = os.time()

    UI.announce("=============================")
    UI.announce("MATCH STARTED!")
    UI.announce("=============================")

    -- Set respawn delay + enable PvP
    local Combat = require("combat")
    Combat.set_respawn_delay(Config.RESPAWN_DELAY)
    Combat.set_pvp_all(true)

    -- Teleport players to arena spawns (staggered)
    local delay = 0
    for _, team_name in ipairs({"red", "blue"}) do
        local spawns = Config.TEAM_SPAWN_INITIAL[team_name]
        local yaw = Config.TEAM_SPAWN_YAW[team_name]
        for i, p in ipairs(Teams.data[team_name].players) do
            local spawn = spawns[((i - 1) % #spawns) + 1]
            ExecuteWithDelay(delay, function()
                ExecuteInGameThread(function()
                    pcall(function()
                        if p.ref and p.ref:IsValid() then
                            p.ref:K2_SetActorLocationAndRotation(
                                spawn,
                                {Pitch = 0, Yaw = yaw, Roll = 0},
                                false, {}, true
                            )
                            p.ref:PlayRespawnVFX()
                        end
                    end)
                end)
            end)
            delay = delay + Config.TELEPORT_STAGGER
        end
    end

    -- Start systems staggered to avoid crash
    -- 3s: flag proximity loop
    ExecuteWithDelay(3000, function()
        Flags.start_proximity_loop(Teams.get_team, Match.player_data)
        print("[Harena] Flag proximity loop started\n")
    end)

    -- 5s: powerup proximity loop (powerups already spawned in preparation)
    ExecuteWithDelay(5000, function()
        local Powerups = require("powerups")
        Powerups.start_proximity_loop(Teams.get_team, Match.player_data)
        print("[Harena] Powerup proximity loop started\n")
    end)

    -- 2s: scoreboard + timer
    ExecuteWithDelay(2000, function()
        Match.start_timer()
        Scoreboard.start_update_loop(Teams.data, Match.player_data, Match.state, Flags)
        print("[Harena] Timer + scoreboard started\n")
    end)
end

-- =============================================================================
-- Match timer (1000ms)
-- =============================================================================
function Match.start_timer()
    LoopAsync(1000, function()
        if not is_world_valid() then return true end
        if Match.state.phase ~= "active" then return true end

        local elapsed = os.time() - Match.state.start_time
        local remaining = Config.MATCH_DURATION - elapsed
        if remaining <= 0 then
            Match.end_match("time")
            return true
        end

        local mins = math.floor(remaining / 60)
        local secs = remaining % 60
        Match.state.timer_display = string.format("%d:%02d", mins, secs)
        Match.state.match_time = elapsed

        -- PvE event triggers
        local pve_interval = Config.PVE_EVENT_INTERVAL
        local next_event = Match.state.pve_event + 1
        if next_event <= 3 and elapsed >= (next_event * pve_interval) then
            Match.state.pve_event = next_event
            Events.fire("pve_start", {event_num = next_event})
        end

        -- Time warnings
        if remaining == 60 then UI.announce("1 MINUTE REMAINING!") end
        if remaining == 30 then UI.announce("30 SECONDS!") end
        if remaining <= 10 and remaining > 0 then
            UI.broadcast(tostring(remaining) .. "...", 1, 0.3, 0.3)
        end

        return false
    end)
end

-- =============================================================================
-- END MATCH
-- =============================================================================
function Match.end_match(reason)
    Match.set_phase("ended")

    local red_caps = Teams.data.red.captures
    local blue_caps = Teams.data.blue.captures
    local winner = "draw"
    if red_caps > blue_caps then winner = "red"
    elseif blue_caps > red_caps then winner = "blue" end

    if reason == "torch_lead" then
        winner = Flags.torch_lead > 0 and "red" or "blue"
    end

    UI.announce("=============================")
    if winner == "draw" then
        UI.announce("MATCH ENDED — DRAW!")
    else
        UI.announce(string.upper(winner) .. " TEAM WINS!")
    end
    UI.announce(string.format("Final Score: RED %d - BLUE %d", red_caps, blue_caps))
    UI.announce("=============================")

    -- Cleanup
    local Combat = require("combat")
    Combat.set_pvp_all(false)
    Flags.cleanup()
    Classes.unblock_windstep()
    local Powerups = require("powerups")
    Powerups.cleanup()
    local PvE = require("pve")
    PvE.cleanup()

    -- Teleport to lobby after 5s
    ExecuteWithDelay(5000, function()
        ExecuteInGameThread(function()
            local players = FindAllOf("BP_PlayerCharacter_C")
            if players then
                local delay = 0
                for _, p in pairs(players) do
                    ExecuteWithDelay(delay, function()
                        ExecuteInGameThread(function()
                            pcall(function()
                                p:K2_SetActorLocation(Config.BED_LOBBY, false, {}, true)
                            end)
                        end)
                    end)
                    delay = delay + Config.TELEPORT_STAGGER
                end
            end
        end)
        Match.set_phase("idle")
    end)
end

-- =============================================================================
-- FULL RESET
-- =============================================================================
function Match.reset()
    Match.set_phase("idle")
    Match.state.match_time = 0
    Match.state.pve_event = 0
    Match.state.start_time = nil
    Match.state.timer_display = "0:00"
    Match.player_data = {}
    Teams.reset()
    Flags.cleanup()
    Classes.unblock_windstep()
    UI.announce("Match reset.")
end

return Match
