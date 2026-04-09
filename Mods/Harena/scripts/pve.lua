--[[
    Harena v1 — PvE Event System
    3 tiers of mob events, per-team tracking, role-based spawning.
]]

local Config = require("config")
local Events = require("events")
local UI = require("ui")
local PvE = {}

PvE.active = false
PvE.current_event = nil
PvE.spawned_mobs = {red = {}, blue = {}}
PvE.mob_class_cache = {}

-- =============================================================================
-- Get mob class ref (cached)
-- =============================================================================
local function get_mob_class(mob_key)
    if PvE.mob_class_cache[mob_key] then return PvE.mob_class_cache[mob_key] end

    local path = Config.MOB_CLASSES[mob_key]
    if not path then return nil end

    local ok, cls = pcall(function() return StaticFindObject(path) end)
    if ok and cls and cls:IsValid() then
        PvE.mob_class_cache[mob_key] = cls
        return cls
    end
    return nil
end

-- =============================================================================
-- Spawn a single mob at position with power level
-- =============================================================================
local function spawn_mob(mob_key, pos, power_level)
    local player = FindFirstOf("BP_PlayerCharacter_C")
    if not player then return nil end
    local world = player:GetWorld()
    if not world then return nil end

    local cls = get_mob_class(mob_key)
    if not cls then return nil end

    -- Boss gets Z+200 offset to avoid ground clip
    local spawn_pos = {X = pos.X, Y = pos.Y, Z = pos.Z}
    if mob_key:find("boss") or mob_key:find("dragon") or mob_key:find("abyssal") or mob_key:find("zogre") then
        spawn_pos.Z = spawn_pos.Z + 200
    end

    local ok, mob = pcall(function() return world:SpawnActor(cls, spawn_pos, {}) end)
    if ok and mob and mob:IsValid() then
        pcall(function() mob.PowerLevel = power_level end)
        return mob
    end
    return nil
end

-- =============================================================================
-- Get spawn position within team's PvE area
-- =============================================================================
local function get_pve_spawn_pos(team, role_idx)
    local area = Config.PVE_SPAWN_AREAS[team]
    if not area then return nil end

    -- Distribute positions within the rectangle
    local x = area.min_x + math.random() * (area.max_x - area.min_x)
    local y = area.min_y + math.random() * (area.max_y - area.min_y)
    return {X = x, Y = y, Z = area.z}
end

-- =============================================================================
-- Start a PvE event
-- =============================================================================
function PvE.start_event(event_num, teams_data, player_data)
    if PvE.active then return end
    if not Config.PVE_EVENTS[event_num] then return end

    PvE.active = true
    PvE.current_event = Config.PVE_EVENTS[event_num]
    PvE.spawned_mobs = {red = {}, blue = {}}

    local event = PvE.current_event
    UI.announce(string.format("=== PVE EVENT %d: %s (PL%d) ===",
        event_num, event.name, event.power_level))

    -- Spawn mobs for each team
    local roles = {"wolf", "archer", "mage", "tank", "boss"}
    local role_counts = {
        wolf = Config.PVE_KILL_REQ.wolf,
        archer = Config.PVE_KILL_REQ.archer,
        mage = Config.PVE_KILL_REQ.mage,
        tank = Config.PVE_KILL_REQ.tank,
        boss = Config.PVE_KILL_REQ.boss,
    }

    local group_delay = 0
    for _, role in ipairs(roles) do
        local mob_key = event.mobs[role]
        if not mob_key then goto continue end

        local count = role_counts[role]

        for _, team_name in ipairs({"red", "blue"}) do
            local delay = group_delay
            for i = 1, count do
                ExecuteWithDelay(delay, function()
                    ExecuteInGameThread(function()
                        if not PvE.active then return end
                        local pos = get_pve_spawn_pos(team_name, i)
                        if not pos then return end
                        local mob = spawn_mob(mob_key, pos, event.power_level)
                        if mob then
                            table.insert(PvE.spawned_mobs[team_name], {
                                ref = mob,
                                role = role,
                                mob_key = mob_key,
                            })
                        end
                    end)
                end)
                delay = delay + Config.MOB_SPAWN_STAGGER
            end
        end

        group_delay = group_delay + Config.MOB_GROUP_STAGGER
        ::continue::
    end

    -- Start respawn loop
    PvE.start_respawn_loop(event_num, teams_data)
end

-- =============================================================================
-- Respawn loop (checks if mobs need respawning per team)
-- =============================================================================
function PvE.start_respawn_loop(event_num, teams_data)
    local event = Config.PVE_EVENTS[event_num]
    local respawn_start = os.time() + Config.PVE_RESPAWN_START

    LoopAsync(3000, function()
        if not is_world_valid() then return true end
        if not PvE.active then return true end
        if os.time() < respawn_start then return false end

        -- Check each team
        for _, team_name in ipairs({"red", "blue"}) do
            local team = teams_data[team_name]
            if not team then goto next_team end

            -- Check if team completed this event
            local all_done = true
            for role, req in pairs(Config.PVE_KILL_REQ) do
                if (team.pve_kills[role] or 0) < req then
                    all_done = false
                    break
                end
            end

            if all_done then goto next_team end

            -- Count alive mobs per role
            local alive = {wolf = 0, archer = 0, mage = 0, tank = 0, boss = 0}
            local new_list = {}
            for _, mob_data in ipairs(PvE.spawned_mobs[team_name]) do
                if mob_data.ref and mob_data.ref:IsValid() then
                    alive[mob_data.role] = alive[mob_data.role] + 1
                    table.insert(new_list, mob_data)
                end
            end
            PvE.spawned_mobs[team_name] = new_list

            -- Respawn missing mobs (only if team hasn't met quota for that role)
            for role, req in pairs(Config.PVE_KILL_REQ) do
                local kills = team.pve_kills[role] or 0
                if kills < req and alive[role] < 1 then
                    local mob_key = event.mobs[role]
                    if mob_key then
                        ExecuteInGameThread(function()
                            local pos = get_pve_spawn_pos(team_name, 1)
                            if pos then
                                local mob = spawn_mob(mob_key, pos, event.power_level)
                                if mob then
                                    table.insert(PvE.spawned_mobs[team_name], {
                                        ref = mob, role = role, mob_key = mob_key,
                                    })
                                end
                            end
                        end)
                    end
                end
            end

            ::next_team::
        end

        -- Check if both teams done
        local both_done = true
        for _, team_name in ipairs({"red", "blue"}) do
            local team = teams_data[team_name]
            for role, req in pairs(Config.PVE_KILL_REQ) do
                if (team.pve_kills[role] or 0) < req then
                    both_done = false
                    break
                end
            end
            if not both_done then break end
        end

        if both_done then
            PvE.active = false
            UI.announce("PvE event complete!")
            return true
        end

        return false
    end)
end

-- =============================================================================
-- Track AI kill for PvE (called from event listener)
-- =============================================================================
function PvE.on_ai_killed(data, teams_data, player_data)
    if not PvE.active then return end

    local killer_id = data.killer_id
    if not killer_id then return end

    -- Find killer's team
    local killer_team = nil
    for team_name, team in pairs(teams_data) do
        for _, p in ipairs(team.players) do
            if p.id == killer_id then
                killer_team = team_name
                break
            end
        end
        if killer_team then break end
    end
    if not killer_team then return end

    -- Determine which role was killed by checking mob class
    local mob_class = data.mob_class or ""
    local event = PvE.current_event
    if not event then return end

    for role, mob_key in pairs(event.mobs) do
        local path = Config.MOB_CLASSES[mob_key] or ""
        if mob_class:find(mob_key) or mob_class:find(path:match("([^/]+)_C$") or "") then
            local team = teams_data[killer_team]
            team.pve_kills[role] = (team.pve_kills[role] or 0) + 1

            local req = Config.PVE_KILL_REQ[role]
            local kills = team.pve_kills[role]

            if kills >= req then
                UI.team_msg(killer_team, string.format("[HARENA] %s: %s role complete! (%d/%d)",
                    string.upper(killer_team), role, kills, req))
            end

            -- Check if team completed all roles
            local all_done = true
            for r, rq in pairs(Config.PVE_KILL_REQ) do
                if (team.pve_kills[r] or 0) < rq then
                    all_done = false
                    break
                end
            end

            if all_done then
                local event_num = 0
                for i, ev in ipairs(Config.PVE_EVENTS) do
                    if ev.name == event.name then event_num = i break end
                end
                Events.fire("pve_complete", {
                    team = killer_team,
                    event_num = event_num,
                })
            end
            break
        end
    end
end

-- =============================================================================
-- Destroy all PvE mobs
-- =============================================================================
function PvE.cleanup()
    PvE.active = false
    PvE.current_event = nil
    for _, team_name in ipairs({"red", "blue"}) do
        local delay = 0
        for _, mob_data in ipairs(PvE.spawned_mobs[team_name]) do
            if mob_data.ref and mob_data.ref:IsValid() then
                ExecuteWithDelay(delay, function()
                    ExecuteInGameThread(function()
                        pcall(function() mob_data.ref:K2_DestroyActor() end)
                    end)
                end)
                delay = delay + Config.MOB_DESTROY_STAGGER
            end
        end
        PvE.spawned_mobs[team_name] = {}
    end
end

-- =============================================================================
-- Init (register event listeners)
-- =============================================================================
function PvE.init()
    Events.on("pve_start", function(data)
        local Match = require("match")
        local Teams = require("teams")
        PvE.start_event(data.event_num, Teams.data, Match.player_data)
    end)

    Events.on("ai_killed", function(data)
        local Match = require("match")
        local Teams = require("teams")
        PvE.on_ai_killed(data, Teams.data, Match.player_data)
    end)
end

return PvE
