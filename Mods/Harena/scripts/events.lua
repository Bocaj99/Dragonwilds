--[[
    Harena v1 — Event Bus
    Central pub/sub system for decoupled module communication.
]]

local Events = {}
Events._listeners = {}

function Events.on(event, callback)
    if not Events._listeners[event] then
        Events._listeners[event] = {}
    end
    table.insert(Events._listeners[event], callback)
end

function Events.fire(event, data)
    if not Events._listeners[event] then return end
    for _, callback in ipairs(Events._listeners[event]) do
        pcall(callback, data)
    end
end

function Events.clear(event)
    Events._listeners[event] = nil
end

function Events.clear_all()
    Events._listeners = {}
end

return Events
