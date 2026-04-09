--[[
    Harena v1 — Class System + Equip Pipeline
    6 classes, tiered armor/weapons, safe staggered equipping.
]]

local Config = require("config")
local Events = require("events")
local Classes = {}

Classes.equip_busy = false

-- =============================================================================
-- Utility: find item data from path
-- =============================================================================
local function find_item(path)
    return StaticFindObject(path)
end

-- =============================================================================
-- Utility: unlock inventory for a controller
-- =============================================================================
local function unlock_inv(ctrl)
    pcall(function()
        ctrl.BP_Components_Inventory.bAllowRemoves = true
        ctrl.BP_Components_Inventory.bAllowAdds = true
        ctrl.BP_Components_Loadout.bAllowRemoves = true
        ctrl.BP_Components_Loadout.bAllowAdds = true
    end)
end

-- =============================================================================
-- Utility: clear all equipment
-- =============================================================================
local function clear_all(ctrl)
    pcall(function() ctrl.BP_Components_Inventory:ClearInventory() end)
    pcall(function() ctrl.BP_Components_Loadout:ClearInventory() end)
end

-- =============================================================================
-- Utility: add item to loadout (armor auto-equips)
-- =============================================================================
local function add_to_loadout(ctrl, path)
    pcall(function()
        local data = find_item(path)
        if data then
            ctrl.BP_Components_Loadout:AddItemByData(data, 1, 1.0, {})
        end
    end)
end

-- =============================================================================
-- Utility: add item to inventory (weapons, ammo, runes)
-- =============================================================================
local function add_item(ctrl, path, count)
    count = count or 1
    pcall(function()
        local data = find_item(path)
        if data then
            ctrl.BP_Components_Inventory:AddItemByData(data, count, 1.0, {})
        end
    end)
end

-- =============================================================================
-- Get cape for team + tier
-- =============================================================================
function Classes.get_cape(team, tier)
    if tier >= 4 then
        return team == "red" and Config.CAPE.Attack or Config.CAPE.Magic
    elseif tier == 3 then
        return team == "red" and Config.CAPE.RedHex or Config.CAPE.BlueHex
    elseif tier == 2 then
        return team == "red" and Config.CAPE.RedDyad or Config.CAPE.BlueDyad
    else
        return team == "red" and Config.CAPE.RedAdv or Config.CAPE.BlueAdv
    end
end

-- =============================================================================
-- Equip base kit for a player
-- =============================================================================
function Classes.equip_base_kit(ctrl, team)
    unlock_inv(ctrl)
    ExecuteInGameThread(function()
        clear_all(ctrl)
        ExecuteWithDelay(Config.EQUIP_DELAY, function()
            ExecuteInGameThread(function()
                -- Armor
                add_to_loadout(ctrl, Config.BASE_ARMOR.head)
                add_to_loadout(ctrl, Config.BASE_ARMOR.body)
                add_to_loadout(ctrl, Config.BASE_ARMOR.legs)
                -- Cape
                add_to_loadout(ctrl, Classes.get_cape(team, 0))
                -- Weapons
                add_item(ctrl, Config.BASE_WEAP.SwingSlash)
                add_item(ctrl, Config.BASE_WEAP.AshBow)
                add_item(ctrl, Config.BASE_WEAP.BoneArrows, 50)
            end)
        end)
    end)
end

-- =============================================================================
-- Equip class gear for a player
-- =============================================================================
function Classes.equip_class_gear(ctrl, team, class_name, armor_tier_idx, weapon_tier_idx)
    -- armor_tier_idx: 1=T3, 2=T4, 3=T5, 4=T6
    -- weapon_tier_idx: 1=T3, 2=T4, 3=T5, 4=T6
    armor_tier_idx = math.max(1, math.min(4, armor_tier_idx or 1))
    weapon_tier_idx = math.max(1, math.min(4, weapon_tier_idx or 1))

    unlock_inv(ctrl)
    ExecuteInGameThread(function()
        clear_all(ctrl)
        ExecuteWithDelay(Config.EQUIP_DELAY, function()
            ExecuteInGameThread(function()
                -- Armor
                local armor = Config.CLASS_ARMOR[class_name]
                if armor and armor[armor_tier_idx] then
                    add_to_loadout(ctrl, armor[armor_tier_idx].head)
                    add_to_loadout(ctrl, armor[armor_tier_idx].body)
                    add_to_loadout(ctrl, armor[armor_tier_idx].legs)
                end

                -- Cape
                local cape_tier = armor_tier_idx + 1  -- armor idx 1=T3 → cape tier 2 (Dyad)
                add_to_loadout(ctrl, Classes.get_cape(team, cape_tier))

                -- Weapons
                local weapons = Config.CLASS_WEAP[class_name]
                if weapons and weapons[weapon_tier_idx] then
                    for _, w in ipairs(weapons[weapon_tier_idx]) do
                        add_item(ctrl, w)
                    end
                end

                -- Ammo for archer
                if class_name == "archer" then
                    local ammo = Config.ARCHER_AMMO[weapon_tier_idx]
                    if ammo then add_item(ctrl, ammo, 50) end
                end
            end)
        end)
    end)
end

-- =============================================================================
-- Give class runes (at specialization)
-- =============================================================================
function Classes.give_runes(ctrl, class_name)
    local runes = Config.CLASS_RUNES[class_name]
    if not runes then return end
    ExecuteInGameThread(function()
        for _, rune_def in ipairs(runes) do
            add_item(ctrl, rune_def[1], rune_def[2])
        end
    end)
end

-- =============================================================================
-- Give trinket
-- =============================================================================
function Classes.give_trinket(ctrl, class_name)
    local path = Config.TRINKETS[class_name]
    if path then
        ExecuteInGameThread(function()
            add_to_loadout(ctrl, path)
        end)
    end
end

-- =============================================================================
-- Equip weapons only (for tier upgrades, no armor swap)
-- =============================================================================
function Classes.equip_weapons_only(ctrl, class_name, weapon_tier_idx, team)
    unlock_inv(ctrl)
    ExecuteInGameThread(function()
        pcall(function() ctrl.BP_Components_Inventory:ClearInventory() end)
        ExecuteWithDelay(Config.EQUIP_DELAY, function()
            ExecuteInGameThread(function()
                local weapons = Config.CLASS_WEAP[class_name]
                if weapons and weapons[weapon_tier_idx] then
                    for _, w in ipairs(weapons[weapon_tier_idx]) do
                        add_item(ctrl, w)
                    end
                end
                -- Ammo for archer
                if class_name == "archer" then
                    local ammo = Config.ARCHER_AMMO[weapon_tier_idx]
                    if ammo then add_item(ctrl, ammo, 50) end
                end
                -- Re-give runes (ClearInventory wipes them)
                ExecuteWithDelay(500, function()
                    Classes.give_runes(ctrl, class_name)
                end)
            end)
        end)
    end)
end

-- =============================================================================
-- Block/unblock Windstep
-- =============================================================================
function Classes.block_windstep()
    pcall(function()
        local usd = StaticFindObject(Config.WINDSTEP_PATH)
        if usd then usd.CooldownDuration = Config.WINDSTEP_BLOCKED_CD end
    end)
end

function Classes.unblock_windstep()
    pcall(function()
        local usd = StaticFindObject(Config.WINDSTEP_PATH)
        if usd then usd.CooldownDuration = Config.WINDSTEP_NORMAL_CD end
    end)
end

return Classes
