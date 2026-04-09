--[[
    Harena v1 — UI / Chat Messaging
    All player-facing text output via Client_ReceiveChatMessage.
]]

local Config = require("config")
local UI = {}

function UI.send(player_or_ctrl, message, r, g, b)
    r = r or 1; g = g or 1; b = b or 1
    pcall(function()
        local ctrl = player_or_ctrl
        if not ctrl.PlayerChat then
            ctrl = player_or_ctrl:GetInstigatorController()
        end
        ctrl.PlayerChat:Client_ReceiveChatMessage({
            PlayerId = 0,
            Color = {R = r, G = g, B = b, A = 1},
            PlayerName = "",
            MessageBody = message,
        })
    end)
end

function UI.broadcast(message, r, g, b)
    r = r or 1; g = g or 1; b = b or 1
    local players = FindAllOf("BP_PlayerCharacter_C")
    if not players then return end
    for _, p in pairs(players) do
        pcall(function()
            local ctrl = p:GetInstigatorController()
            if ctrl and ctrl:IsValid() then
                UI.send(ctrl, message, r, g, b)
            end
        end)
    end
end

function UI.team_msg(team, message)
    local color = Config.TEAM_COLORS[team] or {R = 1, G = 1, B = 1, A = 1}
    UI.broadcast(message, color.R, color.G, color.B)
end

function UI.announce(message)
    UI.broadcast("[HARENA] " .. message, 1, 0.8, 0)
end

function UI.error(message)
    UI.broadcast("[HARENA] " .. message, 1, 0.2, 0.2)
end

return UI
