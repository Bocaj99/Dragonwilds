--[[
    Harena v1 — Admin / Debug Commands
    F3 (lodestones), F6 (PvE), F7 (runes), Num3-5 (mob spawns)
]]

local Config = require("config")
local Events = require("events")
local UI = require("ui")
local PvE = require("pve")
local Classes = require("classes")
local Teams = require("teams")
local Admin = {}

-- =============================================================================
-- Spawn lodestones at team select + class lobby positions
-- =============================================================================
function Admin.spawn_lodestones()
    local player = FindFirstOf("BP_PlayerCharacter_C")
    if not player then return end
    local world = player:GetWorld()
    if not world then return end

    local existing = FindFirstOf("BP_Lodestone_C")
    if not existing then
        UI.error("No lodestone template in world!")
        return
    end

    local bpClass = existing:GetClass()
    local count = 0

    -- Team selection lodestones
    for name, pos in pairs(Config.TEAM_SELECT) do
        ExecuteInGameThread(function()
            pcall(function()
                local actor = world:SpawnActor(bpClass, pos, {})
                if actor then
                    actor:K2_SetActorLocation(pos, false, {}, true)
                    count = count + 1
                end
            end)
        end)
    end

    -- Class lodestones per team
    for team_name, classes in pairs(Config.CLASS_LODESTONES) do
        for class_name, pos in pairs(classes) do
            ExecuteInGameThread(function()
                pcall(function()
                    local actor = world:SpawnActor(bpClass, pos, {})
                    if actor then
                        actor:K2_SetActorLocation(pos, false, {}, true)
                        count = count + 1
                    end
                end)
            end)
        end
    end

    UI.announce("Lodestones spawned: " .. count)
end

-- =============================================================================
-- Spawn debug mob near player
-- =============================================================================
function Admin.spawn_mob_by_key(mob_key, power_level)
    local player = FindFirstOf("BP_PlayerCharacter_C")
    if not player then return end
    local world = player:GetWorld()
    if not world then return end
    local loc = player:K2_GetActorLocation()
    local spawn_pos = {X = loc.X + 500, Y = loc.Y, Z = loc.Z + 300}

    local path = Config.MOB_CLASSES[mob_key]
    if not path then
        UI.error("Unknown mob: " .. mob_key)
        return
    end

    local cls = nil
    pcall(function() cls = StaticFindObject(path) end)
    if not cls or not cls:IsValid() then
        UI.error("NOT LOADED: " .. mob_key)
        print(string.format("[Harena] NOT LOADED: %s\n", mob_key))
        return
    end

    local ok, mob = pcall(function() return world:SpawnActor(cls, spawn_pos, {}) end)
    if ok and mob and mob:IsValid() then
        pcall(function() mob.PowerLevel = power_level end)
        UI.announce(string.format("Spawned %s (PL%d)", mob_key, power_level))
        print(string.format("[Harena] SPAWNED: %s (PL%d)\n", mob_key, power_level))
    else
        UI.error("Spawn failed: " .. mob_key)
    end
end

function Admin.spawn_mob_tier(tier)
    local player = FindFirstOf("BP_PlayerCharacter_C")
    if not player then return end
    local world = player:GetWorld()
    if not world then return end
    local loc = player:K2_GetActorLocation()
    if not loc then return end

    local spawn_pos = {X = loc.X + 500, Y = loc.Y, Z = loc.Z + 300}

    local tier_mobs = {
        [1] = {"wolf", 3},
        [2] = {"dragonwolf", 5},
        [3] = {"blackknight_2h", 6},
    }

    local mob_info = tier_mobs[tier]
    if not mob_info then return end

    local mob_key = mob_info[1]
    local power_level = mob_info[2]
    local path = Config.MOB_CLASSES[mob_key]
    if not path then
        UI.error("Mob class not found: " .. mob_key)
        return
    end

    ExecuteInGameThread(function()
        pcall(function()
            local cls = StaticFindObject(path)
            if not cls then
                UI.error("Class not loaded: " .. mob_key)
                return
            end
            local mob = world:SpawnActor(cls, spawn_pos, {})
            if mob and mob:IsValid() then
                mob.PowerLevel = power_level
                UI.announce(string.format("Spawned %s (PL%d)", mob_key, power_level))
            end
        end)
    end)
end

-- =============================================================================
-- Register admin keybinds
-- =============================================================================
function Admin.register_keybinds()
    -- F3: Spawn lodestones
    RegisterKeyBind(Key.F3, function()
        ExecuteInGameThread(function() Admin.spawn_lodestones() end)
    end)

    -- F6: Start next PvE event manually
    RegisterKeyBind(Key.F6, function()
        ExecuteInGameThread(function()
            local Match = require("match")
            local next_event = Match.state.pve_event + 1
            if next_event > 3 then
                UI.announce("All PvE events complete!")
                return
            end
            Match.state.pve_event = next_event
            Events.fire("pve_start", {event_num = next_event})
        end)
    end)

    -- F7: Test Water Niagara VFX + AnimaVent at -5000u
    RegisterKeyBind(Key.F7, function()
        ExecuteInGameThread(function()
            local player = FindFirstOf("BP_PlayerCharacter_C")
            if not player or not player:IsValid() then return end
            local world = player:GetWorld()
            if not world then return end
            local loc = player:K2_GetActorLocation()
            if not loc then return end
            local pos = {X = loc.X + 300, Y = loc.Y, Z = loc.Z}

            local niagaraLib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
            local vent = FindFirstOf("BP_AnimaVent_C")
            local vent_cls = nil
            if vent and vent:IsValid() then vent_cls = vent:GetClass() end

            -- 1. Fire orb + AnimaVent at pos
            pcall(function()
                local fire_sys = StaticFindObject("/Game/Art/VFX/Library/Env/AnimaVent/Fire/NS_Anima_Loop_Fire.NS_Anima_Loop_Fire")
                if niagaraLib and fire_sys and fire_sys:IsValid() then
                    niagaraLib:SpawnSystemAtLocation(player, fire_sys, pos, {Pitch=0,Yaw=0,Roll=0}, {X=1,Y=1,Z=1}, false, true, 0, false)
                    UI.announce("Fire orb spawned!")
                end
                if vent_cls then
                    local a = world:SpawnActor(vent_cls, {X=pos.X, Y=pos.Y, Z=pos.Z-670}, {})
                    if a then pcall(function() a:SetActorEnableCollision(false) end) end
                    UI.announce("Fire vent spawned")
                end
            end)

            -- 2. Air orb + AnimaVent at pos+800
            local pos2 = {X = pos.X + 800, Y = pos.Y, Z = pos.Z}
            pcall(function()
                local air_sys = StaticFindObject("/Game/Art/VFX/Library/Env/AnimaVent/Air/NS_Anima_Loop_Air.NS_Anima_Loop_Air")
                if niagaraLib and air_sys and air_sys:IsValid() then
                    niagaraLib:SpawnSystemAtLocation(player, air_sys, pos2, {Pitch=0,Yaw=0,Roll=0}, {X=1,Y=1,Z=1}, false, true, 0, false)
                    UI.announce("Air orb spawned!")
                end
                if vent_cls then
                    local a = world:SpawnActor(vent_cls, {X=pos2.X, Y=pos2.Y, Z=pos2.Z-670}, {})
                    if a then pcall(function() a:SetActorEnableCollision(false) end) end
                    UI.announce("Air vent spawned")
                end
            end)
        end)
    end)

    -- F8: Simulate PvP kill (for testing progression)
    RegisterKeyBind(Key.F8, function()
        ExecuteInGameThread(function()
            local player = FindFirstOf("BP_PlayerCharacter_C")
            if not player then return end
            local ctrl = player:GetInstigatorController()
            if not ctrl then return end
            local pid = ctrl.PlayerState.PlayerId

            local Match = require("match")
            local pd = Match.player_data[pid]
            if not pd then
                UI.error("No player data — start a match first!")
                return
            end

            pd.kills = (pd.kills or 0) + 1
            local team = pd.team
            if team then
                Teams.data[team].pvp_kills = (Teams.data[team].pvp_kills or 0) + 1
            end

            UI.send(ctrl, string.format("SIMULATED KILL #%d (Team: %d)", pd.kills, team and Teams.data[team].pvp_kills or 0), 1, 0.8, 0)

            -- Fire the event to trigger progression
            local Events = require("events")
            Events.fire("player_killed", {
                victim_id = -1,
                victim_team = team == "red" and "blue" or "red",
                killer_id = pid,
                killer_team = team,
            })
        end)
    end)

    -- F9: Toggle building regen on/off + retake snapshot
    Admin._regen_paused = false
    RegisterKeyBind(Key.F9, function()
        ExecuteInGameThread(function()
            local Buildings = require("buildings")
            Admin._regen_paused = not Admin._regen_paused
            Buildings._regen_paused = Admin._regen_paused
            if Admin._regen_paused then
                -- Unlock mannequins
                local mannequins = FindAllOf("BP_BaseBuilding_ArmourMannequin_C")
                if mannequins then
                    for _, m in pairs(mannequins) do
                        pcall(function()
                            local inv = m.BP_Components_WorldItemInventory
                            if inv then
                                inv.bAllowRemoves = true
                                inv.bAllowAdds = true
                            end
                        end)
                    end
                end
                UI.announce("Build mode: EDIT (regen paused, mannequins unlocked)")
            else
                -- Re-lock mannequins
                Buildings.lock_mannequins()
                Buildings.snapshot_pieces()
                UI.announce("Build mode: PROTECTED (regen on, mannequins locked) — " .. Buildings.expected_count .. " pieces")
            end
        end)
    end)

    -- Num3: Simulate PvP kill (same as F8)
    RegisterKeyBind(Key.NUM_THREE, function()
        ExecuteInGameThread(function()
            local player = FindFirstOf("BP_PlayerCharacter_C")
            if not player then return end
            local ctrl = player:GetInstigatorController()
            if not ctrl then return end
            local pid = ctrl.PlayerState.PlayerId

            local Match = require("match")
            local pd = Match.player_data[pid]
            if not pd then
                UI.error("No player data — start a match first!")
                return
            end

            pd.kills = (pd.kills or 0) + 1
            local team = pd.team
            if team then
                Teams.data[team].pvp_kills = (Teams.data[team].pvp_kills or 0) + 1
            end

            UI.send(ctrl, string.format("KILL #%d (Team: %d)", pd.kills, team and Teams.data[team].pvp_kills or 0), 1, 0.8, 0)

            local Events = require("events")
            Events.fire("player_killed", {
                victim_id = -1,
                victim_team = team == "red" and "blue" or "red",
                killer_id = pid,
                killer_team = team,
            })
        end)
    end)

    -- Num6: Cycle through mob biome locations (to preload mob classes)
    Admin._biome_idx = 0
    Admin._biome_locations = {
        {name = "Garou",          pos = {X = 69305, Y = 107833, Z = 872}},
        {name = "Abyssal",        pos = {X = 128377, Y = 142256, Z = -2106}},
        {name = "Dragon/Dowdun",  pos = {X = 194355, Y = 63035, Z = 4879}},
        {name = "Mob Spot 5",     pos = {X = 227992, Y = 32440, Z = -4376}},
        {name = "Fellhollow",     pos = {X = 237307, Y = -35328, Z = 6223}},
        {name = "Mob Spot 6",     pos = {X = 78109, Y = -42975, Z = -6531}},
        {name = "ARENA",          pos = {X = 68469, Y = 176517, Z = -442}},
    }

    RegisterKeyBind(Key.NUM_SIX, function()
        ExecuteInGameThread(function()
            local player = FindFirstOf("BP_PlayerCharacter_C")
            if not player then return end

            Admin._biome_idx = (Admin._biome_idx % #Admin._biome_locations) + 1
            local biome = Admin._biome_locations[Admin._biome_idx]

            pcall(function()
                player:K2_SetActorLocation(biome.pos, false, {}, true)
                player:PlayRespawnVFX()
            end)
            UI.send(player, string.format("TP: %s (%d/%d)", biome.name, Admin._biome_idx, #Admin._biome_locations), 1, 0.8, 0)
            print(string.format("[Harena] Biome TP: %s\n", biome.name))
        end)
    end)
    -- Num9: Spawn height fog at arena
    RegisterKeyBind(Key.NUM_NINE, function()
        ExecuteInGameThread(function()
            local player = FindFirstOf("BP_PlayerCharacter_C")
            if not player then return end
            local world = player:GetWorld()
            if not world then return end
            local loc = player:K2_GetActorLocation()

            -- Try finding existing height fog actors
            local fog_names = {"BP_HeightFog_C", "BP_HeightFog_FH_C", "BP_HeightFog_Imaru_C", "BP_HeightFog_UMS_C"}
            for _, name in ipairs(fog_names) do
                pcall(function()
                    local existing = FindFirstOf(name)
                    if existing and existing:IsValid() then
                        local cls = existing:GetClass()
                        local fog = world:SpawnActor(cls, loc, {})
                        if fog and fog:IsValid() then
                            fog:K2_SetActorLocation(loc, false, {}, true)
                            -- Try adjusting fog properties
                            pcall(function()
                                local fogComp = fog.ExponentialHeightFog
                                if fogComp then
                                    fogComp.FogDensity = 0.3
                                    fogComp.FogHeightFalloff = 0.00001
                                    fogComp.FogMaxOpacity = 1.0
                                    fogComp.StartDistance = 0
                                    fogComp.FogCutoffDistance = 0
                                    fogComp.bEnableVolumetricFog = true
                                    fogComp.VolumetricFogDistance = 50000
                                    fogComp.VolumetricFogExtinctionScale = 5.0
                                    fogComp.VolumetricFogStartDistance = 0
                                    print("[Harena] Fog properties set: density=0.5, falloff=0.0001, volumetric=ON (max)\n")
                                end
                            end)
                            -- Set weather to cloudy + pause
                            pcall(function()
                                local cm = FindFirstOf("DominionCheatManager")
                                if cm then
                                    cm:domSetWeather("Cloudy")
                                    cm:domTogglePauseWeather()
                                    print("[Harena] Weather set to Cloudy (paused)\n")
                                end
                            end)
                            UI.announce("Fog + Cloudy weather set!")
                            print(string.format("[Harena] Fog spawned: %s\n", name))
                            return
                        end
                    end
                end)
            end

            -- If no fog Blueprint found, try modifying existing world fog
            pcall(function()
                local existing_fog = FindFirstOf("ExponentialHeightFog")
                if existing_fog and existing_fog:IsValid() then
                    local floc = existing_fog:K2_GetActorLocation()
                    print(string.format("[Harena] Existing world fog at Z=%.0f\n", floc.Z))
                    -- Move it up to arena height
                    existing_fog:K2_SetActorLocation({X = floc.X, Y = floc.Y, Z = loc.Z}, false, {}, true)
                    UI.announce("World fog raised to arena height!")
                    print(string.format("[Harena] Fog moved to Z=%.0f\n", loc.Z))
                else
                    UI.error("No fog actor found in world")
                end
            end)
        end)
    end)

    -- Num8: Scan for all tree classes in memory
    -- (Num8 removed — now used for FF test in CTFBuildingTool)

    -- T: Spawn arena trees from config
    RegisterKeyBind(Key.T, function()
        ExecuteInGameThread(function()
            local player = FindFirstOf("BP_PlayerCharacter_C")
            if not player then return end
            local world = player:GetWorld()
            if not world then return end

            local count = 0
            for _, tree_def in ipairs(Config.ARENA_TREES or {}) do
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
                            count = count + 1
                        end
                    else
                        UI.error("Not loaded: " .. tree_def.class)
                    end
                end)
            end
            UI.announce(string.format("Arena trees: %d/%d spawned", count, #(Config.ARENA_TREES or {})))
        end)
    end)

    -- F12: Destroy all nearby trees (5000u radius)
    -- Num4: Cycle through all class loadouts (preload assets on mannequins)
    Admin._loadout_idx = 0
    Admin._loadout_list = {}
    for _, class_name in ipairs(Config.CLASS_LIST) do
        for tier = 1, 4 do
            table.insert(Admin._loadout_list, {class = class_name, tier = tier})
        end
    end

    -- Num4: Give ALL weapons (all classes, all tiers) to inventory
    RegisterKeyBind(Key.NUM_FOUR, function()
        ExecuteInGameThread(function()
            local player = FindFirstOf("BP_PlayerCharacter_C")
            if not player then return end
            local ctrl = player:GetInstigatorController()
            if not ctrl then return end
            local inv = ctrl.BP_Components_Inventory
            pcall(function() inv.bAllowAdds = true end)

            local count = 0
            for _, class_name in ipairs(Config.CLASS_LIST) do
                for tier = 1, 4 do
                    local weapons = Config.CLASS_WEAP[class_name]
                    if weapons and weapons[tier] then
                        for _, w in ipairs(weapons[tier]) do
                            pcall(function()
                                local d = StaticFindObject(w)
                                if d then
                                    inv:AddItemByData(d, 1, 1.0, {})
                                    count = count + 1
                                end
                            end)
                        end
                    end
                    -- Ammo for archer
                    if class_name == "archer" then
                        local ammo = Config.ARCHER_AMMO[tier]
                        if ammo then
                            pcall(function()
                                local d = StaticFindObject(ammo)
                                if d then inv:AddItemByData(d, 50, 1.0, {}) end
                            end)
                        end
                    end
                end
            end
            -- Also add base weapons
            pcall(function()
                local d = StaticFindObject(Config.BASE_WEAP.SwingSlash)
                if d then inv:AddItemByData(d, 1, 1.0, {}) end
            end)
            pcall(function()
                local d = StaticFindObject(Config.BASE_WEAP.AshBow)
                if d then inv:AddItemByData(d, 1, 1.0, {}) end
            end)
            pcall(function()
                local d = StaticFindObject(Config.BASE_WEAP.BoneArrows)
                if d then inv:AddItemByData(d, 50, 1.0, {}) end
            end)
            UI.announce(count .. " weapons added to inventory!")
        end)
    end)

    -- Num5: Give T6 armor (all 6 classes) to inventory
    RegisterKeyBind(Key.NUM_FIVE, function()
        ExecuteInGameThread(function()
            local player = FindFirstOf("BP_PlayerCharacter_C")
            if not player then return end
            local ctrl = player:GetInstigatorController()
            if not ctrl then return end
            local inv = ctrl.BP_Components_Inventory
            pcall(function() inv.bAllowAdds = true end)

            local count = 0
            for _, class_name in ipairs(Config.CLASS_LIST) do
                local armor = Config.CLASS_ARMOR[class_name]
                if armor and armor[4] then  -- index 4 = T6
                    pcall(function()
                        local h = StaticFindObject(armor[4].head)
                        local b = StaticFindObject(armor[4].body)
                        local l = StaticFindObject(armor[4].legs)
                        if h then inv:AddItemByData(h, 1, 1.0, {}) count = count + 1 end
                        if b then inv:AddItemByData(b, 1, 1.0, {}) count = count + 1 end
                        if l then inv:AddItemByData(l, 1, 1.0, {}) count = count + 1 end
                    end)
                end
            end
            UI.announce(count .. " T6 armor pieces added!")
        end)
    end)

    -- F12: Destroy all nearby trees
    RegisterKeyBind(Key.F12, function()
        ExecuteInGameThread(function()
            local player = FindFirstOf("BP_PlayerCharacter_C")
            if not player then return end
            local ploc = player:K2_GetActorLocation()

            local tree_classes = {"BP_BM_Tree_Ash_03_C", "BP_BM_Tree_Ash_02_C", "BP_BM_Tree_Ash_01_C",
                "BP_BM_Tree_Oak_01_C", "BP_BM_Tree_Oak_02_C", "BP_Tree_Oak_01_C", "BP_Tree_Oak_02_C",
                "BP_FH_Tree_Oak_01_C", "BP_FH_Tree_Oak_02_C", "BP_DR_Tree_Maple_01_C", "BP_DR_Tree_Maple_02_C",
                "FH_HeroTree_01_C", "BP_FH_Tree_Ash_01_C", "BP_FH_Tree_Ash_02_C", "BP_FH_Tree_Ash_03_C",
                "BP_FH_Tree_Willow_01_C", "BP_FH_Tree_Willow_02_C", "BP_FH_Tree_Willow_03_C"}

            local count = 0
            for _, name in ipairs(tree_classes) do
                pcall(function()
                    local trees = FindAllOf(name)
                    if trees then
                        for _, t in pairs(trees) do
                            pcall(function()
                                local tloc = t:K2_GetActorLocation()
                                if tloc then
                                    local dx = tloc.X - ploc.X
                                    local dy = tloc.Y - ploc.Y
                                    local dist = math.sqrt(dx*dx + dy*dy)
                                    if dist < 1000 then
                                        t:K2_DestroyActor()
                                        count = count + 1
                                    end
                                end
                            end)
                        end
                    end
                end)
            end
            UI.announce(count .. " trees destroyed!")
        end)
    end)

    -- F11: Toggle flight
    RegisterKeyBind(Key.F11, function()
        ExecuteInGameThread(function()
            pcall(function()
                local cm = FindFirstOf("DominionCheatManager")
                if cm then
                    cm:domSetCanFly(true)
                    UI.announce("Flight enabled!")
                    print("[Harena] domSetCanFly(true) called\n")
                end
            end)
        end)
    end)

    -- Num7: Spawn tree at player position (cycles through tree types)
    Admin._tree_idx = 0
    Admin._tree_types = {
        -- Fellhollow Oak
        "BP_FH_Tree_Oak_01_C",
        "BP_FH_Tree_Oak_02_C",
        -- Fellhollow Willow
        "BP_FH_Tree_Willow_01_C",
        "BP_FH_Tree_Willow_02_C",
        "BP_FH_Tree_Willow_03_C",
        -- Fellhollow Ash
        "BP_FH_Tree_Ash_01_C",
        "BP_FH_Tree_Ash_02_C",
        "BP_FH_Tree_Ash_03_C",
        -- Fellhollow Bare
        "BP_FH_Tree_Ash_Bare_01_C",
        "BP_FH_Tree_Ash_Bare_02_C",
        "BP_FH_Tree_Ash_Bare_03_C",
        -- Brynmoor Oak
        "BP_BM_Tree_Oak_01_C",
        "BP_BM_Tree_Oak_02_C",
        -- Base Oak
        "BP_Tree_Oak_01_C",
        "BP_Tree_Oak_02_C",
        -- Brynmoor Ash
        "BP_BM_Tree_Ash_01_C",
        "BP_BM_Tree_Ash_02_C",
        "BP_BM_Tree_Ash_03_C",
        -- Dowdun Reach Maple
        "BP_DR_Tree_Maple_01_C",
        "BP_DR_Tree_Maple_02_C",
        -- Special
        "FH_HeroTree_01_C",
        "BP_BlightwoodRoot_C",
    }

    -- Num7: Give ALL capes to inventory
    RegisterKeyBind(Key.NUM_SEVEN, function()
        ExecuteInGameThread(function()
            local player = FindFirstOf("BP_PlayerCharacter_C")
            if not player then return end
            local ctrl = player:GetInstigatorController()
            if not ctrl then return end
            local inv = ctrl.BP_Components_Inventory
            pcall(function() inv.bAllowAdds = true end)

            local count = 0
            for _, path in pairs(Config.CAPE) do
                pcall(function()
                    local d = StaticFindObject(path)
                    if d then
                        inv:AddItemByData(d, 1, 1.0, {})
                        count = count + 1
                    end
                end)
            end
            UI.announce(count .. " capes added to inventory!")
        end)
    end)

end

return Admin
