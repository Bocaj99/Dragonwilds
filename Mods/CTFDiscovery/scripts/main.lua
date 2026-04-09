--[[
    CTF Mod — Phase 1 Discovery Script (v2)
    =========================================
    Press F1 = Fast targeted discovery (player, inventory, combat, etc.)
    Press F2 = Deep scan (all BP classes, items, death funcs — slow but thorough)

    All output writes to file in real-time — no data loss on crash.
    Output: ue4ss/Mods/CTFDiscovery/scripts/discovery_dump.txt
]]

local MOD_NAME = "CTFDiscovery"
local dump_file = nil
local dump_path = "Mods\\CTFDiscovery\\scripts\\discovery_dump.txt"

-- ============================================================================
-- File logging — writes immediately, no buffering
-- ============================================================================

local function open_dump(suffix)
    local path = dump_path
    if suffix then
        path = path:gsub("%.txt$", "_" .. suffix .. ".txt")
    end
    dump_file = io.open(path, "w")
    if not dump_file then
        path = "discovery_dump.txt"
        dump_file = io.open(path, "w")
    end
    if dump_file then
        print(string.format("[%s] Dump file opened: %s\n", MOD_NAME, path))
    else
        print(string.format("[%s] ERROR: Could not open dump file!\n", MOD_NAME))
    end
end

local function log(msg)
    local line = string.format("[%s] %s", MOD_NAME, msg)
    print(line .. "\n")
    if dump_file then
        dump_file:write(line .. "\n")
        dump_file:flush()
    end
end

local function close_dump()
    if dump_file then
        dump_file:close()
        dump_file = nil
        print(string.format("[%s] Dump file saved and closed.\n", MOD_NAME))
    end
end

-- ============================================================================
-- Dump properties and functions for a UObject's class
-- ============================================================================

local function dump_class_info(obj, label)
    log("========================================")
    log("CLASS DUMP: " .. label)
    log("  FullName: " .. obj:GetFullName())
    log("  Class: " .. obj:GetClass():GetFullName())
    log("========================================")

    log("  --- Properties ---")
    obj:GetClass():ForEachProperty(function(prop)
        log("    PROP: " .. prop:GetFullName())
    end)

    log("  --- Functions ---")
    obj:GetClass():ForEachFunction(function(func)
        log("    FUNC: " .. func:GetFullName())
    end)

    -- Walk superclass chain (limited to 5 levels)
    local super = obj:GetClass():GetSuperStruct()
    local depth = 0
    while super and super:IsValid() and depth < 5 do
        log("  --- Super[" .. depth .. "]: " .. super:GetFullName() .. " ---")
        super:ForEachProperty(function(prop)
            log("    SUPER_PROP: " .. prop:GetFullName())
        end)
        super:ForEachFunction(function(func)
            log("    SUPER_FUNC: " .. func:GetFullName())
        end)
        super = super:GetSuperStruct()
        depth = depth + 1
    end
    log("")
end

-- ============================================================================
-- Targeted search helper
-- ============================================================================

local function try_find(search_names, category)
    for _, name in ipairs(search_names) do
        local obj = FindFirstOf(name)
        if obj and obj:IsValid() then
            log("FOUND " .. category .. ": " .. name)
            dump_class_info(obj, category .. " (" .. name .. ")")
            return obj
        end
    end

    local all = FindAllOf(search_names[1])
    if all then
        for i, o in pairs(all) do
            log("  " .. category .. " fallback[" .. i .. "]: " .. o:GetFullName())
        end
    end
    return nil
end

-- ============================================================================
-- F1 — Fast targeted discovery
-- ============================================================================

local function run_fast_discovery()
    open_dump("fast")
    log("############################################")
    log("# CTF FAST DISCOVERY — STARTING            #")
    log("############################################")
    log("")

    -- 1. Player Character
    log("==== PLAYER CHARACTER ====")
    local player = try_find({
        "BP_PlayerCharacter_C",
        "PlayerCharacter_C",
        "BP_Character_C",
        "BP_Player_C",
        "BP_SurvivalCharacter_C",
        "BP_MainCharacter_C",
    }, "PlayerCharacter")

    if not player then
        log("Trying base classes...")
        player = try_find({"Character", "Pawn"}, "PlayerCharacter")
    end

    -- 2. Player Controller
    log("==== PLAYER CONTROLLER ====")
    try_find({
        "BP_PlayerController_C",
        "PlayerController_C",
        "BP_SurvivalPlayerController_C",
        "PlayerController",
    }, "PlayerController")

    -- 3. Game Mode / Game State
    log("==== GAME MODE / GAME STATE ====")
    local gm_names = {
        "BP_GameMode_C",
        "BP_SurvivalGameMode_C",
        "BP_GameState_C",
        "BP_SurvivalGameState_C",
        "GameModeBase",
        "GameStateBase",
    }
    for _, name in ipairs(gm_names) do
        local obj = FindFirstOf(name)
        if obj and obj:IsValid() then
            log("FOUND: " .. name)
            dump_class_info(obj, name)
        end
    end

    -- 4. Inventory / Equipment
    log("==== INVENTORY / EQUIPMENT ====")
    local inv_names = {
        "BP_InventoryComponent_C",
        "InventoryComponent_C",
        "BP_EquipmentComponent_C",
        "BP_Inventory_C",
        "BP_ItemManager_C",
        "InventoryManagerComponent",
        "BP_ActionBar_C",
    }
    for _, name in ipairs(inv_names) do
        local obj = FindFirstOf(name)
        if obj and obj:IsValid() then
            log("FOUND inventory: " .. name)
            dump_class_info(obj, name)
        end
    end

    -- 5. Health / Stats / Combat
    log("==== HEALTH / STATS / COMBAT ====")
    local combat_names = {
        "BP_HealthComponent_C",
        "BP_StatsComponent_C",
        "BP_CombatComponent_C",
        "BP_AttributeComponent_C",
        "BP_DamageComponent_C",
        "AbilitySystemComponent",
    }
    for _, name in ipairs(combat_names) do
        local obj = FindFirstOf(name)
        if obj and obj:IsValid() then
            log("FOUND combat: " .. name)
            dump_class_info(obj, name)
        end
    end

    -- 6. HUD / UI
    log("==== HUD / UI ====")
    local hud_names = {
        "BP_HUD_C",
        "HUD",
        "BP_PlayerHUD_C",
    }
    for _, name in ipairs(hud_names) do
        local obj = FindFirstOf(name)
        if obj and obj:IsValid() then
            log("FOUND HUD: " .. name)
            dump_class_info(obj, name)
        end
    end

    -- 7. Coordinates
    log("==== COORDINATES ====")
    if player and player:IsValid() then
        local ok, loc = pcall(function() return player:K2_GetActorLocation() end)
        if ok and loc then
            log(string.format("  Player Location: X=%.2f Y=%.2f Z=%.2f", loc.X, loc.Y, loc.Z))
        else
            log("  K2_GetActorLocation failed or unavailable")
        end
    else
        log("  No player found for coordinate check")
    end

    log("")
    log("############################################")
    log("# CTF FAST DISCOVERY — COMPLETE            #")
    log("# Press F2 for deep scan (slow)            #")
    log("############################################")
    close_dump()
end

-- ============================================================================
-- F2 — Deep scan (all BP classes, items, death events)
-- Writes to file only (skips console print) for speed
-- ============================================================================

local function run_deep_discovery()
    open_dump("deep")
    log("############################################")
    log("# CTF DEEP DISCOVERY — STARTING            #")
    log("# This will take several minutes...        #")
    log("############################################")
    log("")

    -- All Blueprint classes
    log("==== ALL BLUEPRINT CLASSES ====")
    local seen_classes = {}
    local class_count = 0
    ForEachUObject(function(Object, ChunkIndex, ObjectIndex)
        local ok, class = pcall(function() return Object:GetClass() end)
        if ok and class and class:IsValid() then
            local ok2, className = pcall(function() return class:GetFullName() end)
            if ok2 and className and not seen_classes[className] then
                if className:find("_C ") or className:find("_C$") or className:find("BP_") then
                    seen_classes[className] = true
                    class_count = class_count + 1
                    if dump_file then
                        dump_file:write(string.format("[%s]   BP_CLASS: %s\n", MOD_NAME, className))
                        if class_count % 50 == 0 then
                            dump_file:flush()
                            print(string.format("[%s] ... scanned %d BP classes so far\n", MOD_NAME, class_count))
                        end
                    end
                end
            end
        end
    end)
    log(string.format("Total BP classes found: %d", class_count))

    -- Weapon / Item scan
    log("==== WEAPON / ITEM ASSETS ====")
    local item_keywords = {"Sword", "Shield", "Bow", "Staff", "Mace", "Rune", "Dragon", "Magic",
                           "Plate", "Leather", "Robes", "Monk", "Weapon", "Armor", "Armour", "Item"}
    local seen_items = {}
    local item_count = 0
    ForEachUObject(function(Object, ChunkIndex, ObjectIndex)
        local ok, fullName = pcall(function() return Object:GetFullName() end)
        if ok and fullName then
            for _, keyword in ipairs(item_keywords) do
                if fullName:find(keyword) and not seen_items[fullName] then
                    seen_items[fullName] = true
                    item_count = item_count + 1
                    if dump_file then
                        dump_file:write(string.format("[%s]   ITEM [%s]: %s\n", MOD_NAME, keyword, fullName))
                        if item_count % 50 == 0 then
                            dump_file:flush()
                        end
                    end
                    break
                end
            end
        end
    end)
    log(string.format("Total item matches found: %d", item_count))

    -- Death / Respawn events
    log("==== DEATH / RESPAWN EVENTS ====")
    local death_keywords = {"Die", "Death", "Kill", "Respawn", "Revive", "Down", "Knock", "Faint", "Damage"}
    local seen_funcs = {}
    local func_count = 0
    ForEachUObject(function(Object, ChunkIndex, ObjectIndex)
        local ok, isClass = pcall(function() return Object:IsClass() end)
        if ok and isClass then
            pcall(function()
                Object:ForEachFunction(function(func)
                    local funcName = func:GetFullName()
                    for _, keyword in ipairs(death_keywords) do
                        if funcName:find(keyword) and not seen_funcs[funcName] then
                            seen_funcs[funcName] = true
                            func_count = func_count + 1
                            if dump_file then
                                dump_file:write(string.format("[%s]   DEATH_FUNC [%s]: %s\n", MOD_NAME, keyword, funcName))
                                if func_count % 50 == 0 then
                                    dump_file:flush()
                                end
                            end
                            break
                        end
                    end
                end)
            end)
        end
    end)
    log(string.format("Total death/damage funcs found: %d", func_count))

    log("")
    log("############################################")
    log("# CTF DEEP DISCOVERY — COMPLETE            #")
    log("############################################")
    close_dump()
end

-- ============================================================================
-- Keybinds
-- ============================================================================

print(string.format("[%s] Discovery script v2 loaded!\n", MOD_NAME))
print(string.format("[%s] Press F1 = Fast discovery (recommended first)\n", MOD_NAME))
print(string.format("[%s] Press F2 = Deep scan (slow, thorough)\n", MOD_NAME))
print(string.format("[%s] Load into a world first, then press the key.\n", MOD_NAME))

RegisterKeyBind(Key.F1, function()
    ExecuteInGameThread(function()
        run_fast_discovery()
    end)
end)

RegisterKeyBind(Key.F2, function()
    ExecuteInGameThread(function()
        run_deep_discovery()
    end)
end)

-- Quick auto-check after 5 seconds
ExecuteWithDelay(5000, function()
    ExecuteInGameThread(function()
        print(string.format("[%s] --- Quick Check ---\n", MOD_NAME))
        local player = FindFirstOf("Character")
        if player and player:IsValid() then
            print(string.format("[%s] Character found: %s\n", MOD_NAME, player:GetFullName()))
        else
            print(string.format("[%s] No Character yet. Load a world, then press F1.\n", MOD_NAME))
        end
    end)
end)

-- Load CTF full flow test
require("test_apis")
