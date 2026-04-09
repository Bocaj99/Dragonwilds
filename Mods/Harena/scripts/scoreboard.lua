--[[
    Harena v1 — Scoreboard System
    Updates ModActor variables for the .pak HUD widget.
]]

local Config = require("config")
local Events = require("events")
local Scoreboard = {}

Scoreboard.visible = false

-- =============================================================================
-- Torch display (tug-of-war style)
-- =============================================================================
function Scoreboard.get_torch_display(team, torch_lead)
    local count = 0
    if team == "red" then
        count = torch_lead > 0 and torch_lead or 0
    else
        count = torch_lead < 0 and math.abs(torch_lead) or 0
    end
    count = math.min(count, 3)
    local lit = string.rep("|", count)
    local unlit = string.rep(".", 3 - count)
    return lit .. unlit
end

-- =============================================================================
-- Show/hide widget
-- =============================================================================
function Scoreboard.show()
    pcall(function()
        local mod_actor = FindFirstOf("ModActor_C")
        if mod_actor then
            pcall(function() mod_actor.ScoreboardWidget:SetVisibility(0) end)
            print("[Harena] Scoreboard widget visible\n")
        end
    end)
end

function Scoreboard.hide()
    pcall(function()
        local mod_actor = FindFirstOf("ModActor_C")
        if mod_actor then
            pcall(function() mod_actor.ScoreboardWidget:SetVisibility(2) end)
        end
    end)
end

-- =============================================================================
-- Toggle visibility (Caps Lock)
-- =============================================================================
function Scoreboard.toggle()
    Scoreboard.visible = not Scoreboard.visible
    pcall(function()
        local mod_actor = FindFirstOf("ModActor_C")
        if mod_actor then
            local widget = mod_actor.ScoreboardWidget
            if widget then
                widget.StatsPanel:SetVisibility(Scoreboard.visible and 0 or 2)
            end
        end
    end)
end

-- =============================================================================
-- Update loop (1000ms)
-- =============================================================================
function Scoreboard.start_update_loop(teams_data, player_data, match_state, flags_module)
    Scoreboard.show()

    LoopAsync(1000, function()
        if not is_world_valid() then return true end

        local mod_actor = FindFirstOf("ModActor_C")
        if not mod_actor or not mod_actor:IsValid() then return false end

        ExecuteInGameThread(function()
            pcall(function()
                -- Torch display
                mod_actor.RedScore = Scoreboard.get_torch_display("red", flags_module.torch_lead)
                mod_actor.BlueScore = Scoreboard.get_torch_display("blue", flags_module.torch_lead)

                -- Timer
                if match_state.timer_display then
                    mod_actor.MatchTimer = match_state.timer_display
                else
                    mod_actor.MatchTimer = "0:00"
                end

                -- Per-player stats (3 per team)
                for _, team_name in ipairs({"red", "blue"}) do
                    local t = teams_data[team_name]
                    local prefix = team_name == "red" and "Red" or "Blue"

                    for slot = 1, 3 do
                        local p = t.players[slot]
                        if p then
                            local pd = player_data[p.id]

                            -- Resolve display name
                            local name = "P" .. p.id
                            pcall(function()
                                if p.ref and p.ref:IsValid() then
                                    local n = p.ref:GetInstigatorController().PlayerState:GetPlayerName():ToString()
                                    if n and n ~= "" then name = n end
                                end
                            end)

                            mod_actor[prefix .. slot .. "Name"]   = name
                            mod_actor[prefix .. slot .. "Class"]  = pd and pd.class and Config.CLASS_DISPLAY[pd.class] or "---"
                            mod_actor[prefix .. slot .. "Kills"]  = tostring(pd and pd.kills or 0)
                            mod_actor[prefix .. slot .. "Deaths"] = tostring(pd and pd.deaths or 0)
                            mod_actor[prefix .. slot .. "Flags"]  = tostring(pd and pd.flags or 0)
                        else
                            mod_actor[prefix .. slot .. "Name"]   = ""
                            mod_actor[prefix .. slot .. "Class"]  = ""
                            mod_actor[prefix .. slot .. "Kills"]  = ""
                            mod_actor[prefix .. slot .. "Deaths"] = ""
                            mod_actor[prefix .. slot .. "Flags"]  = ""
                        end
                    end
                end
            end)
        end)

        return false
    end)
end

return Scoreboard
