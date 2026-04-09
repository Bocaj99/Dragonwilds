--[[
    Harena v1 — Progression System
    Specialization (3 kills), weapon tiers (12/24/36 team), trinkets (12 personal).
    Listens to player_killed events from combat module.
]]

local Config = require("config")
local Events = require("events")
local UI = require("ui")
local Classes = require("classes")
local Flags = require("flags")
local Progression = {}

-- =============================================================================
-- Process a PvP kill (called from event listener)
-- =============================================================================
function Progression.on_pvp_kill(data, player_data, teams_data)
    local killer_id = data.killer_id
    local killer_team = data.killer_team
    if not killer_id or not killer_team then return end

    local pd = player_data[killer_id]
    if not pd or not pd.class then return end

    local team = teams_data[killer_team]
    if not team then return end

    -- Increment team PvP kills
    team.pvp_kills = team.pvp_kills + 1

    -- Find killer controller
    local killer_ctrl = nil
    local killer_ref = nil
    pcall(function()
        local players = FindAllOf("BP_PlayerCharacter_C")
        if not players then return end
        for _, p in pairs(players) do
            local ctrl = p:GetInstigatorController()
            if ctrl and ctrl.PlayerState.PlayerId == killer_id then
                killer_ctrl = ctrl
                killer_ref = p
                break
            end
        end
    end)
    if not killer_ctrl then return end

    -- Skip if carrying flag (defer upgrades)
    if Flags.is_carrying(killer_id) then return end

    local kills = pd.kills

    -- === SPECIALIZATION (3 personal kills) ===
    if kills == 3 and not pd.specialized then
        pd.specialized = true
        pd.weapon_tier = 1
        pd.armor_tier = math.max(pd.armor_tier, 1)

        UI.broadcast(string.format("[HARENA] %s SPECIALIZED as %s!",
            pd.name, Config.CLASS_DISPLAY[pd.class]), 0, 1, 0)

        Classes.equip_class_gear(killer_ctrl, killer_team, pd.class, pd.armor_tier, pd.weapon_tier)
        ExecuteWithDelay(1000, function()
            Classes.give_runes(killer_ctrl, pd.class)
        end)

        pcall(function() killer_ref:PlayRespawnVFX() end)
        pcall(function() killer_ref:DissolveTeleport() end)
        return
    end

    -- === TRINKET (12 personal kills) ===
    if kills == 12 and not pd.trinket_earned then
        pd.trinket_earned = true
        UI.broadcast(string.format("[HARENA] %s earned a TRINKET! (12 kills)", pd.name), 1, 0.8, 0)
        Classes.give_trinket(killer_ctrl, pd.class)
        pcall(function() killer_ref:PlayRespawnVFX() end)
    end

    -- === TEAM WEAPON TIERS (12/24/36 team kills) ===
    local team_kills = team.pvp_kills
    local new_weapon_tier = nil

    if team_kills == 12 and pd.weapon_tier < 2 then
        new_weapon_tier = 2
        UI.broadcast(string.format("[HARENA] %s TEAM: 12 kills! Weapons → T4!",
            string.upper(killer_team)), 0, 1, 1)
    elseif team_kills == 24 and pd.weapon_tier < 3 then
        new_weapon_tier = 3
        UI.broadcast(string.format("[HARENA] %s TEAM: 24 kills! Weapons → T5!",
            string.upper(killer_team)), 0, 1, 1)
    elseif team_kills == 36 and pd.weapon_tier < 4 then
        new_weapon_tier = 4
        UI.broadcast(string.format("[HARENA] %s TEAM: 36 kills! Weapons → T6 (MAX)!",
            string.upper(killer_team)), 1, 0.8, 0)
    end

    if new_weapon_tier then
        -- Upgrade ALL team members' weapons
        local delay = 0
        for _, tp in ipairs(team.players) do
            local tpd = player_data[tp.id]
            if tpd and tpd.class then
                -- Auto-promote unspecialized at 12 team kills
                if not tpd.specialized and team_kills >= 12 then
                    tpd.specialized = true
                    tpd.kills = math.max(tpd.kills, 3)
                    tpd.armor_tier = math.max(tpd.armor_tier, 1)
                    UI.broadcast(string.format("[HARENA] %s AUTO-PROMOTED! (team hit %d kills)",
                        tpd.name, team_kills), 1, 0.8, 0)
                end

                tpd.weapon_tier = new_weapon_tier

                ExecuteWithDelay(delay, function()
                    ExecuteInGameThread(function()
                        pcall(function()
                            if tp.ref and tp.ref:IsValid() then
                                local ctrl = tp.ref:GetInstigatorController()
                                if ctrl and not Flags.is_carrying(tp.id) then
                                    Classes.equip_weapons_only(ctrl, tpd.class, new_weapon_tier, killer_team)
                                    tp.ref:PlayRespawnVFX()
                                end
                            end
                        end)
                    end)
                end)
                delay = delay + Config.EQUIP_STAGGER
            end
        end
    end
end

-- =============================================================================
-- Process PvE event completion (armor tier upgrade for whole team)
-- =============================================================================
function Progression.on_pve_complete(team_name, event_num, player_data, teams_data)
    local team = teams_data[team_name]
    if not team then return end

    local reward_tier = Config.PVE_EVENTS[event_num].reward_tier
    team.armor_tier = reward_tier

    -- Armor index: reward_tier 4 = idx 2 (T4), 5 = idx 3 (T5), 6 = idx 4 (T6)
    local armor_idx = reward_tier - 2

    UI.team_msg(team_name, string.format("[HARENA] %s completed PvE Event %d! Armor → T%d!",
        string.upper(team_name), event_num, reward_tier))

    -- Upgrade ALL team members' armor
    local delay = 0
    for _, tp in ipairs(team.players) do
        local tpd = player_data[tp.id]
        if tpd and tpd.class and tpd.specialized then
            tpd.armor_tier = armor_idx

            ExecuteWithDelay(delay, function()
                ExecuteInGameThread(function()
                    pcall(function()
                        if tp.ref and tp.ref:IsValid() then
                            local ctrl = tp.ref:GetInstigatorController()
                            if ctrl and not Flags.is_carrying(tp.id) then
                                Classes.equip_class_gear(ctrl, team_name, tpd.class, tpd.armor_tier, tpd.weapon_tier)
                                tp.ref:PlayRespawnVFX()
                            end
                        end
                    end)
                end)
            end)
            delay = delay + Config.EQUIP_STAGGER
        end
    end
end

-- =============================================================================
-- Init (register event listener)
-- =============================================================================
function Progression.init()
    Events.on("player_killed", function(data)
        -- Always read fresh from Match to avoid stale references
        local Match = require("match")
        local Teams = require("teams")
        Progression.on_pvp_kill(data, Match.player_data, Teams.data)
    end)

    Events.on("pve_complete", function(data)
        local Match = require("match")
        local Teams = require("teams")
        Progression.on_pve_complete(data.team, data.event_num, Match.player_data, Teams.data)
    end)
end

return Progression
