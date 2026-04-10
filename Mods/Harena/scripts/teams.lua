--[[
    Harena v1 — Team System
    Team assignment, lodestone proximity, auto-balance.
]]

local Config = require("config")
local Events = require("events")
local UI = require("ui")
local Teams = {}

Teams.data = {
    red = {
        players = {},
        pvp_kills = 0,
        captures = 0,
        armor_tier = 2,
        color = Config.TEAM_COLORS.red,
        pve_kills = {wolf = 0, archer = 0, mage = 0, tank = 0, boss = 0},
    },
    blue = {
        players = {},
        pvp_kills = 0,
        captures = 0,
        armor_tier = 2,
        color = Config.TEAM_COLORS.blue,
        pve_kills = {wolf = 0, archer = 0, mage = 0, tank = 0, boss = 0},
    },
}

function Teams.get_team(player_id)
    for team_name, team in pairs(Teams.data) do
        for _, p in ipairs(team.players) do
            if p.id == player_id then return team_name end
        end
    end
    return nil
end

function Teams.get_player_refs(team)
    local refs = {}
    for _, p in ipairs(Teams.data[team].players) do
        if p.ref and p.ref:IsValid() then
            table.insert(refs, p.ref)
        end
    end
    return refs
end

function Teams.count(team)
    return #Teams.data[team].players
end

function Teams.add_player(team, player_id, player_ref)
    -- Remove from any existing team first
    Teams.remove_player(player_id)
    table.insert(Teams.data[team].players, {id = player_id, ref = player_ref})
    Events.fire("team_assigned", {player_id = player_id, team = team})
    Teams.write_teams_file()
end

function Teams.remove_player(player_id)
    for team_name, team in pairs(Teams.data) do
        for i, p in ipairs(team.players) do
            if p.id == player_id then
                table.remove(team.players, i)
                Teams.write_teams_file()
                return team_name
            end
        end
    end
    return nil
end

function Teams.assign_random(player_id, player_ref)
    local red_count = Teams.count("red")
    local blue_count = Teams.count("blue")
    local team = red_count <= blue_count and "red" or "blue"
    Teams.add_player(team, player_id, player_ref)
    return team
end

function Teams.start_selection_loop(on_complete)
    local selection_start = os.time()
    local duration = Config.LOBBY_DURATION

    LoopAsync(500, function()
        if not is_world_valid() then return true end

        local elapsed = os.time() - selection_start
        if elapsed >= duration then
            on_complete()
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

                -- Check team lodestones
                for team_name, team_pos in pairs(Config.TEAM_SELECT) do
                    local dx = loc.X - team_pos.X
                    local dy = loc.Y - team_pos.Y
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist < Config.LODESTONE_RADIUS then
                        if team_name == "random" then
                            local assigned = Teams.assign_random(pid, player)
                            UI.send(ctrl, "Assigned to " .. string.upper(assigned) .. " team!", 1, 0.8, 0)
                        else
                            if Teams.count(team_name) < 3 then
                                Teams.add_player(team_name, pid, player)
                                UI.send(ctrl, "Joined " .. string.upper(team_name) .. " team!", 1, 0.8, 0)
                            else
                                UI.send(ctrl, string.upper(team_name) .. " team is full!", 1, 0.2, 0.2)
                            end
                        end
                        -- Teleport to team lobby
                        local lobbies = Config.TEAM_LOBBY_SPAWNS[Teams.get_team(pid)]
                        if lobbies and #lobbies > 0 then
                            local slot = #Teams.data[Teams.get_team(pid)].players
                            local lobby_pos = lobbies[((slot - 1) % #lobbies) + 1]
                            ExecuteInGameThread(function()
                                pcall(function()
                                    player:K2_SetActorLocation(lobby_pos, false, {}, true)
                                end)
                            end)
                        end
                        break
                    end
                end
            end)
        end

        -- Display remaining time every 15 seconds
        local remaining = duration - elapsed
        if remaining % 15 == 0 and remaining > 0 then
            UI.broadcast(string.format("Team selection: %d seconds remaining", remaining), 1, 0.8, 0)
        end

        return false
    end)
end

function Teams.reset()
    Teams.data.red.players = {}
    Teams.data.red.pvp_kills = 0
    Teams.data.red.captures = 0
    Teams.data.red.armor_tier = 2
    Teams.data.red.pve_kills = {wolf = 0, archer = 0, mage = 0, tank = 0, boss = 0}

    Teams.data.blue.players = {}
    Teams.data.blue.pvp_kills = 0
    Teams.data.blue.captures = 0
    Teams.data.blue.armor_tier = 2
    Teams.data.blue.pve_kills = {wolf = 0, archer = 0, mage = 0, tank = 0, boss = 0}

    Teams.write_teams_file()
end

-- Write team assignments to file for C++ HarenaDamage mod
function Teams.write_teams_file()
    pcall(function()
        local path = "ue4ss/Mods/HarenaDamage/teams.txt"
        local f = io.open(path, "w")
        if not f then return end
        for team_name, team in pairs(Teams.data) do
            if team_name == "red" or team_name == "blue" then
                for _, p in ipairs(team.players) do
                    f:write(tostring(p.id) .. "=" .. team_name .. "\n")
                end
            end
        end
        f:close()
    end)
end

return Teams
