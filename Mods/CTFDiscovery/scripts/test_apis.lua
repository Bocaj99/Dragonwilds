--[[
    CTF Full Flow Test
    F3 = Spawn lodestones
    F6 = Start lobby (60s select → 10s countdown → teleport)
    F7 = Start next PvE event (Dragon Wolves → Rotsworn → Dragon)
    F8 = Kill all nearby enemies (triggers event completion + tier upgrade)
    F9 = Award trinkets
    F10 = Scan nearest NATURAL mob (deep property dump)
    F4 = Coords | 0 = Full reset
    Numpad 2 = Probe last spawned mob HP/damage/data
    Numpad 3-9 = Spawn mob tiers
]]

------------------------------------------------------------
-- UTILS
------------------------------------------------------------
-- Custom log file with immediate flush
local CTF_LOG_PATH = "C:/Users/Jacob/ctf_debug.log"
local function ctf_log(msg)
    print("[CTF] " .. msg .. "\n")
    pcall(function()
        local f = io.open(CTF_LOG_PATH, "a")
        if f then
            f:write(os.date("[%H:%M:%S] ") .. msg .. "\n")
            f:flush()
            f:close()
        end
    end)
end

local function send_chat(msg)
    local c = FindFirstOf("BP_PlayerController_C")
    if not c then return end
    pcall(function()
        c.PlayerChat:Client_ReceiveChatMessage({
            PlayerId=0, Color={R=1,G=1,B=1,A=1}, PlayerName="", MessageBody=msg,
        })
    end)
end

local function send_color(msg, r, g, b)
    local c = FindFirstOf("BP_PlayerController_C")
    if not c then return end
    pcall(function()
        c.PlayerChat:Client_ReceiveChatMessage({
            PlayerId=0, Color={R=r,G=g,B=b,A=1}, PlayerName="", MessageBody=msg,
        })
    end)
end

local function unlock_inv()
    local c = FindFirstOf("BP_PlayerController_C")
    if not c then return end
    pcall(function() c.BP_Components_Inventory.bAllowRemoves = true end)
    pcall(function() c.BP_Components_Loadout.bAllowRemoves = true end)
    pcall(function() c.BP_Components_Inventory.bAllowAdds = true end)
    pcall(function() c.BP_Components_Loadout.bAllowAdds = true end)
end

local function clear_all()
    unlock_inv()
    local c = FindFirstOf("BP_PlayerController_C")
    if not c then return end
    pcall(function() c.BP_Components_Inventory:ClearInventory() end)
    pcall(function() c.BP_Components_Loadout:ClearInventory() end)
end

local function add_item(path, count)
    count = count or 1
    local data = StaticFindObject(path)
    if not data or not data:IsValid() then return false end
    local c = FindFirstOf("BP_PlayerController_C")
    if not c then return false end
    pcall(function() c.BP_Components_Inventory:AddItemByData(data, count, 1.0, {}) end)
    return true
end

local function add_to_loadout(path)
    local data = StaticFindObject(path)
    if not data or not data:IsValid() then return false end
    local c = FindFirstOf("BP_PlayerController_C")
    if not c then return false end
    pcall(function() c.BP_Components_Loadout:AddItemByData(data, 1, 1.0, {}) end)
    return true
end

-- Player-specific versions (for multiplayer — take a controller ref)
local function get_controller_for(player_ref)
    local ctrl = nil
    pcall(function()
        ctrl = player_ref:GetInstigatorController()
    end)
    return ctrl
end

local function unlock_inv_for(ctrl)
    if not ctrl or not ctrl:IsValid() then return end
    pcall(function() ctrl.BP_Components_Inventory.bAllowRemoves = true end)
    pcall(function() ctrl.BP_Components_Loadout.bAllowRemoves = true end)
    pcall(function() ctrl.BP_Components_Inventory.bAllowAdds = true end)
    pcall(function() ctrl.BP_Components_Loadout.bAllowAdds = true end)
end

local function clear_all_for(ctrl)
    unlock_inv_for(ctrl)
    pcall(function() ctrl.BP_Components_Inventory:ClearInventory() end)
    pcall(function() ctrl.BP_Components_Loadout:ClearInventory() end)
end

local function add_item_for(ctrl, path, count)
    count = count or 1
    local data = StaticFindObject(path)
    if not data or not data:IsValid() then return false end
    pcall(function() ctrl.BP_Components_Inventory:AddItemByData(data, count, 1.0, {}) end)
    return true
end

local function add_to_loadout_for(ctrl, path)
    local data = StaticFindObject(path)
    if not data or not data:IsValid() then return false end
    pcall(function() ctrl.BP_Components_Loadout:AddItemByData(data, 1, 1.0, {}) end)
    return true
end

-- Equip base kit on a specific player (T2 armor + base weapons + team cape)
-- equip_base_kit_for defined after BASE_WEAP (see below asset paths section)

-- World validity guard — return true from LoopAsync to stop the loop when world is gone
function is_world_valid()
    local ok, player = pcall(function() return FindFirstOf("BP_PlayerCharacter_C") end)
    if not ok or not player or not player:IsValid() then return false end
    local ok2, world = pcall(function() return player:GetWorld() end)
    if not ok2 or not world or not world:IsValid() then return false end
    return true
end

local function get_player_pos()
    local player = FindFirstOf("BP_PlayerCharacter_C")
    if not player or not player:IsValid() then return nil end
    local pos = player:K2_GetActorLocation()
    return {X = pos.X, Y = pos.Y, Z = pos.Z}
end

local function distance2d(a, b)
    return math.sqrt((a.X - b.X)^2 + (a.Y - b.Y)^2)
end

-- === EARLY DAMAGE HOOK REGISTRATION (must run before any kills) ===
if not _G.mob_last_attacker then _G.mob_last_attacker = {} end
local _dmg_hooks_registered = false
local function register_damage_hooks()
    if _dmg_hooks_registered then return end
    _dmg_hooks_registered = true
    ctf_log("=== REGISTERING DAMAGE HOOKS ===")

    local function try_get_pid(param)
        if not param then return nil end
        local pid = nil
        pcall(function()
            local obj = param:get()
            if not obj then return end
            pcall(function() if obj.PlayerState then pid = obj.PlayerState.PlayerId end end)
            if not pid then
                pcall(function()
                    local ctrl = obj:GetInstigatorController()
                    if ctrl then pid = ctrl.PlayerState.PlayerId end
                end)
            end
            if not pid then
                pcall(function()
                    local ins = obj.Instigator
                    if ins then
                        local ctrl = ins:GetInstigatorController()
                        if ctrl then pid = ctrl.PlayerState.PlayerId end
                    end
                end)
            end
        end)
        return pid
    end

    local hooks = {
        -- Kill attribution is handled by LastDamageEvent in the death hook
        -- These hooks are kept as backup for edge cases only
        "/Script/Dominion.AiHitReactionsComponent:Multicast_Stumble_PointDamage",
    }
    for _, path in ipairs(hooks) do
        local short = path:match(":(.+)$") or path
        local ok, err = pcall(function()
            RegisterHook(path, function(self, p1, p2, p3, p4, p5)
                -- Skip verbose logging for performance (only log fatal/player hits)

                -- Deep probe for Multicast_ApplyDamageFromGameplayEffect
                if short == "Multicast_ApplyDamageFromGameplayEffect" or short == "Multicast_ApplyPointDamageFromGameplayEffect" or
                   short == "Multicast_Stumble_PointDamage" or short == "Multicast_Stumble" then
                    pcall(function()
                        -- Get the mob (owner of the damage component)
                        local comp = self:get()
                        local owner = comp:GetOwner()
                        local mob_addr = tostring(owner:GetAddress())

                        -- Struct probe disabled for performance (kill attribution works via LDE)
                        if false and p1 then
                            pcall(function()
                                local obj1 = p1:get()
                                if obj1 then
                                    local name1 = "?"
                                    pcall(function() name1 = obj1:GetFullName() end)
                                    ctf_log("DMG p1: " .. name1)

                                    -- Try EVERY possible field name for attacker
                                    local attacker_fields = {
                                        "Instigator", "DamageCauser", "InstigatorController",
                                        "InstigatorPawn", "SourceActor", "SourceController",
                                        "Causer", "Attacker", "DamageDealer", "Origin",
                                        "HitInstigator", "EffectCauser", "AbilityOwner",
                                        "DamageSource", "EventInstigator", "OwnerActor",
                                    }
                                    for _, fname in ipairs(attacker_fields) do
                                        pcall(function()
                                            local v = obj1[fname]
                                            if v ~= nil then
                                                local vstr = tostring(v)
                                                -- Try to get more info
                                                pcall(function() vstr = v:GetFullName() end)
                                                ctf_log("  p1." .. fname .. " = " .. vstr)
                                                -- Try PlayerState
                                                pcall(function()
                                                    local pid = v.PlayerState.PlayerId
                                                    ctf_log("  >> PLAYER: P" .. pid .. " via p1." .. fname)
                                                    _G.mob_last_attacker[mob_addr] = pid
                                                end)
                                                pcall(function()
                                                    local pid = v:GetInstigatorController().PlayerState.PlayerId
                                                    ctf_log("  >> PLAYER: P" .. pid .. " via p1." .. fname .. "->ctrl")
                                                    _G.mob_last_attacker[mob_addr] = pid
                                                end)
                                            end
                                        end)
                                    end

                                    -- Try struct property enumeration via StaticFindObject
                                    pcall(function()
                                        local struct_def = StaticFindObject("/Script/Dominion.DominionDamageEvent")
                                        if struct_def and struct_def:IsValid() then
                                            ctf_log("DominionDamageEvent struct found!")
                                            struct_def:ForEachProperty(function(prop)
                                                pcall(function()
                                                    local pn = prop:GetFName():ToString()
                                                    local pt = prop:GetClass():GetFName():ToString()
                                                    ctf_log("  struct." .. pn .. " [" .. pt .. "]")
                                                    -- Try reading the field from obj1
                                                    pcall(function()
                                                        local v = obj1[pn]
                                                        if v ~= nil then
                                                            ctf_log("    = " .. tostring(v))
                                                        end
                                                    end)
                                                end)
                                            end)
                                        end
                                    end)
                                end
                            end)
                        end

                        -- Extract player from DominionDamageEvent struct
                        if p1 then
                            pcall(function()
                                local obj1 = p1:get()
                                if not obj1 then return end

                                -- Check bIsFatalHit
                                local is_fatal = false
                                pcall(function() is_fatal = obj1.bIsFatalHit end)

                                -- Get Instigator
                                local instigator = nil
                                pcall(function() instigator = obj1.Instigator end)

                                if instigator then
                                    local pid = nil
                                    -- Check if Instigator is a player
                                    pcall(function()
                                        local ctrl = instigator:GetInstigatorController()
                                        if ctrl and ctrl:IsValid() then
                                            pid = ctrl.PlayerState.PlayerId
                                        end
                                    end)

                                    if pid then
                                        _G.mob_last_attacker[mob_addr] = pid
                                        if is_fatal then
                                            _G.mob_fatal_attacker = {mob_addr = mob_addr, pid = pid}
                                            ctf_log("FATAL HIT: P" .. pid .. " killed " .. mob_addr)
                                        else
                                            ctf_log("DMG HIT: P" .. pid .. " -> " .. mob_addr)
                                        end
                                    end
                                end
                            end)
                        end

                        -- Probe p2 (RemoteUnrealParam)
                        if p2 and not _G.mob_last_attacker[mob_addr] then
                            pcall(function()
                                local obj2 = p2:get()
                                if obj2 then
                                    local name2 = "?"
                                    pcall(function() name2 = obj2:GetFullName() end)
                                    ctf_log("DMG p2: " .. name2)

                                    local pid = nil
                                    pcall(function() pid = obj2.PlayerState.PlayerId end)
                                    if not pid then pcall(function() pid = obj2:GetInstigatorController().PlayerState.PlayerId end) end
                                    if not pid then pcall(function() pid = obj2.Instigator:GetInstigatorController().PlayerState.PlayerId end) end

                                    if pid then
                                        _G.mob_last_attacker[mob_addr] = pid
                                        ctf_log("DMG ATTACKER (p2): P" .. pid .. " -> " .. mob_addr)
                                    end

                                    if not pid then
                                        pcall(function()
                                            local cls = obj2:GetClass()
                                            if cls then
                                                ctf_log("DMG p2 class: " .. cls:GetFullName())
                                                cls:ForEachProperty(function(prop)
                                                    pcall(function()
                                                        local pn = prop:GetFName():ToString()
                                                        local pt = prop:GetClass():GetFName():ToString()
                                                        local v = obj2[pn]
                                                        ctf_log("  p2." .. pn .. " = " .. tostring(v) .. " [" .. pt .. "]")
                                                    end)
                                                end)
                                            end
                                        end)
                                    end
                                end
                            end)
                        end
                    end)
                    return  -- skip generic logging for this hook
                end

                -- Silent — kill attribution handled by LDE in death hook
            end)
        end)
        if ok then
            ctf_log("DMG HOOK OK: " .. path)
        else
            ctf_log("DMG HOOK FAIL: " .. path .. " | " .. tostring(err))
        end
    end
    -- Dump DominionDamageEvent struct definition
    pcall(function()
        local struct = StaticFindObject("/Script/Dominion.DominionDamageEvent")
        if struct and struct:IsValid() then
            ctf_log("=== DominionDamageEvent STRUCT FIELDS ===")
            struct:ForEachProperty(function(prop)
                pcall(function()
                    local pn = prop:GetFName():ToString()
                    local pt = prop:GetClass():GetFName():ToString()
                    ctf_log("  " .. pn .. " [" .. pt .. "]")
                end)
            end)
        else
            ctf_log("DominionDamageEvent struct NOT FOUND via StaticFindObject")
        end
    end)

    -- Also dump FatalDamageInfo struct
    pcall(function()
        local struct = StaticFindObject("/Script/Dominion.FatalDamageInfo")
        if struct and struct:IsValid() then
            ctf_log("=== FatalDamageInfo STRUCT FIELDS ===")
            struct:ForEachProperty(function(prop)
                pcall(function()
                    local pn = prop:GetFName():ToString()
                    local pt = prop:GetClass():GetFName():ToString()
                    ctf_log("  " .. pn .. " [" .. pt .. "]")
                end)
            end)
        end
    end)

    -- Dump ALL AiHitReactionsComponent functions
    pcall(function()
        local cls = StaticFindObject("/Script/Dominion.AiHitReactionsComponent")
        if cls then
            ctf_log("=== ALL AiHitReactionsComponent functions ===")
            cls:ForEachFunction(function(func)
                pcall(function()
                    ctf_log("  HitReact: " .. func:GetFName():ToString())
                end)
            end)
        end
    end)
    ctf_log("=== DAMAGE HOOKS DONE ===")
end

-- Register immediately
register_damage_hooks()

-- === COMBAT TARGET POLLING (both player and mob side) ===
if not _G.mob_last_attacker then _G.mob_last_attacker = {} end
local _target_poll_log_count = 0  -- limit debug logging

LoopAsync(500, function()
    if not is_world_valid() then return true end
    pcall(function()
        -- Build player lookup: address -> player_id
        local player_lookup = {}  -- player_character_addr -> pid
        local all_players = FindAllOf("BP_PlayerCharacter_C")
        if not all_players then return end
        for _, player in ipairs(all_players) do
            pcall(function()
                if player and player:IsValid() then
                    local pid = nil
                    pcall(function()
                        pid = player:GetInstigatorController().PlayerState.PlayerId
                    end)
                    if pid then
                        player_lookup[tostring(player:GetAddress())] = pid
                    end
                end
            end)
        end

        -- Poll each PvE mob's combat-related properties while ALIVE
        for _, m in ipairs(pve_active_mobs or {}) do
            pcall(function()
                if not m.ref or not m.ref:IsValid() then return end
                local mob_addr = tostring(m.ref:GetAddress())

                -- Try to find who the mob is targeting/fighting
                local target_props = {
                    "CombatTarget", "AggroTarget", "Target", "CurrentTarget",
                    "LastAttacker", "LastDamageInstigator", "LastHitBy",
                }
                for _, tprop in ipairs(target_props) do
                    pcall(function()
                        local val = m.ref[tprop]
                        if val and type(val) == "userdata" then
                            local valid = false
                            pcall(function() valid = val:IsValid() end)
                            if valid then
                                local target_addr = tostring(val:GetAddress())
                                local pid = player_lookup[target_addr]
                                if pid then
                                    _G.mob_last_attacker[mob_addr] = pid
                                    if _target_poll_log_count < 20 then
                                        _target_poll_log_count = _target_poll_log_count + 1
                                        ctf_log("TARGET POLL: " .. tprop .. " -> P" .. pid .. " on " .. mob_addr)
                                    end
                                end
                            end
                        end
                    end)
                end

                -- Also check combat mode initiator component
                pcall(function()
                    local cmi_names = {
                        "BP_Wolf_AiCombatModeInitiator",
                        "BP_AiCombatModeInitiator",
                        "CombatModeInitiator",
                    }
                    for _, cmi_name in ipairs(cmi_names) do
                        pcall(function()
                            local cmi = m.ref[cmi_name]
                            if cmi and cmi:IsValid() then
                                for _, tp in ipairs({"Target", "CurrentTarget", "CombatTarget"}) do
                                    pcall(function()
                                        local t = cmi[tp]
                                        if t and type(t) == "userdata" then
                                            local valid = false
                                            pcall(function() valid = t:IsValid() end)
                                            if valid then
                                                local pid = player_lookup[tostring(t:GetAddress())]
                                                if pid then
                                                    _G.mob_last_attacker[mob_addr] = pid
                                                    if _target_poll_log_count < 20 then
                                                        _target_poll_log_count = _target_poll_log_count + 1
                                                        ctf_log("CMI POLL: P" .. pid .. " on " .. mob_addr)
                                                    end
                                                end
                                            end
                                        end
                                    end)
                                end
                            end
                        end)
                    end
                end)
            end)
        end
    end)
    return false
end)

-- === PVP STATE PROBE ===
-- Captures bIsPvpEnabled changes and related damage component state
pcall(function()
    RegisterHook("/Script/Dominion.PlayerDamageComponent:OnRep_bIsPvpEnabled", function(self)
        pcall(function()
            local comp = self:get()
            if not comp or not comp:IsValid() then return end
            local pvp_state = "?"
            pcall(function() pvp_state = tostring(comp.bIsPvpEnabled) end)
            local can_take = "?"
            pcall(function() can_take = tostring(comp.bCanTakeDamage) end)
            local owner_name = "?"
            pcall(function() owner_name = comp:GetOwner():GetFullName() end)
            ctf_log("PVP STATE CHANGE: bIsPvpEnabled=" .. pvp_state .. " bCanTakeDamage=" .. can_take .. " on " .. owner_name)
        end)
    end)
    ctf_log("PvP state hook registered")
end)

-- === FRIENDLY FIRE PREVENTION via OnDamageReceived ===
-- Fires on every PvP hit — heal back same-team damage instantly
pcall(function()
    RegisterHook("/Game/Gameplay/Character/Player/BP_PlayerCharacter.BP_PlayerCharacter_C:OnDamageReceivedDynamic_Event", function(self, p1, p2)
        pcall(function()
            local victim = self:get()
            if not victim or not victim:IsValid() then return end

            -- TEST: heal ALL PvP damage (remove team check for testing)
            pcall(function()
                local hp = victim.BP_Components_Health
                if hp and hp:IsValid() then
                    local max = hp:GetMaxHealth()
                    hp:SetHealth(max)
                    ctf_log("FF HEAL: SetHealth(" .. tostring(max) .. ")")
                end
            end)
        end)
    end)
    ctf_log("Friendly fire prevention hook registered")
end)

-- Numpad 8 FF moved after variable definitions (see below F11)

-- F12: Probe + toggle PvP state on all players
RegisterKeyBind(Key.F12, function()
    ctf_log("=== PVP STATE PROBE ===")
    pcall(function()
        local all = FindAllOf("BP_PlayerCharacter_C")
        if not all then return end
        for i, player in ipairs(all) do
            pcall(function()
                if not player or not player:IsValid() then return end
                local pid = "?"
                pcall(function() pid = tostring(player:GetInstigatorController().PlayerState.PlayerId) end)

                local dmg = player.BP_Components_PlayerDamage
                if dmg and dmg:IsValid() then
                    -- Read current state
                    local pvp = "?"
                    pcall(function() pvp = tostring(dmg.bIsPvpEnabled) end)
                    local can_take = "?"
                    pcall(function() can_take = tostring(dmg.bCanTakeDamage) end)
                    local can_show = "?"
                    pcall(function() can_show = tostring(dmg.bShowDamageFloaties) end)

                    ctf_log("P" .. pid .. ": bIsPvpEnabled=" .. pvp .. " bCanTakeDamage=" .. can_take .. " bShowDamageFloaties=" .. can_show)

                    -- Dump ALL bool properties on damage component
                    pcall(function()
                        local cls = dmg:GetClass()
                        -- Walk up hierarchy
                        local depth = 0
                        while cls and depth < 5 do
                            cls:ForEachProperty(function(prop)
                                pcall(function()
                                    local pn = prop:GetFName():ToString()
                                    local pt = prop:GetClass():GetFName():ToString()
                                    if pt == "BoolProperty" then
                                        local val = "?"
                                        pcall(function() val = tostring(dmg[pn]) end)
                                        ctf_log("  " .. pn .. " = " .. val)
                                    end
                                end)
                            end)
                            local super = nil
                            pcall(function() super = cls:GetSuperStruct() end)
                            if super and super:IsValid() and super:GetFullName() ~= cls:GetFullName() then
                                cls = super
                            else
                                break
                            end
                            depth = depth + 1
                        end
                    end)
                end
            end)
        end
    end)
    ctf_log("=== PVP PROBE DONE ===")
end)

-- Boss mobs that need Z offset to avoid ground-clip death
local BOSS_MOBS = {zogre=true, abyssal_demon=true, dragon_green=true, dragon_blue=true}

local function play_vfx()
    local player = FindFirstOf("BP_PlayerCharacter_C")
    if not player or not player:IsValid() then return end
    pcall(function() player:DissolveTeleport() end)
    ExecuteWithDelay(500, function()
        pcall(function() player:PlayRespawnVFX() end)
    end)
end

------------------------------------------------------------
-- TEAM & GAME STATE (forward-declared for flag system access)
------------------------------------------------------------
local send_to_all
local send_team_msg
local send_to_team
local equip_class_for
local equip_base_kit_for
local cleanup_flags
local cleanup_powerups
local BED_LOBBY = {X=37473, Y=175582, Z=-3760}
local game_state = {
    phase = "idle",
    match_time = 0,
    pve_event = 0,
}
local player_data = {}
local match_active = false
local lobby_active = false

-- Team data
local teams = {
    red = {
        players = {},  -- array of {id=PlayerId, ref=playerRef}
        pve_kills = {wolf=0, archer=0, mage=0, tank=0, boss=0},
        pvp_kills = 0,
        captures = 0,
        individual_kills = {},  -- keyed by player id
        armor_tier = 2,  -- starts at T2 (base kit)
        color = {R=1, G=0.2, B=0.2, A=1},
    },
    blue = {
        players = {},
        pve_kills = {wolf=0, archer=0, mage=0, tank=0, boss=0},
        pvp_kills = 0,
        captures = 0,
        individual_kills = {},
        armor_tier = 2,
        color = {R=0.2, G=0.4, B=1, A=1},
    },
}

-- Torch lead system: tracks consecutive lead, 3 = instant win
-- Positive = red leads, negative = blue leads
local torch_lead = 0  -- -3 to +3
local TORCH_WIN_LEAD = 3
local MATCH_DURATION = 1080  -- 18 minutes

local function get_torch_display(team)
    -- Returns torch display string for HUD: lit torches based on lead
    local lead = torch_lead
    if team == "blue" then lead = -lead end
    local lit = math.max(0, lead)
    local display = ""
    for i = 1, 3 do
        display = display .. (i <= lit and "|" or ".")
    end
    return display
end

local function update_torch_lead_after_capture(capturing_team)
    if capturing_team == "red" then
        torch_lead = torch_lead + 1
    else
        torch_lead = torch_lead - 1
    end
    -- Clamp to -3..3
    torch_lead = math.max(-TORCH_WIN_LEAD, math.min(TORCH_WIN_LEAD, torch_lead))
    -- Returns true if instant win threshold reached
    return math.abs(torch_lead) >= TORCH_WIN_LEAD
end

------------------------------------------------------------
-- FLAG SYSTEM (torch-based CTF)
------------------------------------------------------------
-- Flag positions: SET THESE to your arena torch coordinates (F4 to capture)
local FLAG_POSITIONS = {
    red  = {X=38353, Y=168901, Z=-3279},
    blue = {X=28906, Y=178347, Z=-3279},
}
local FLAG_PICKUP_RADIUS = 500
local FLAG_CAPTURE_RADIUS = 500
local TORCH_ITEM_PATH = "/Game/Gameplay/Character/Player/Equipment/Held/Torch/ITEM_Torch.ITEM_Torch"

local flag_state = {
    red  = {status = "at_base", carrier = nil, torch_actor = nil},
    blue = {status = "at_base", carrier = nil, torch_actor = nil},
}

local function is_carrying_flag(player_id)
    for _, ft in ipairs({"red", "blue"}) do
        if flag_state[ft].carrier == player_id then return true end
    end
    return false
end

local function spawn_flag_torch(pos, team)
    local player = FindFirstOf("BP_PlayerCharacter_C")
    if not player then return nil end
    local world = player:GetWorld()
    if not world then return nil end
    local torch_class_name = team == "red" and "BP_BaseBuilding_TorchStanding_Red_C" or "BP_BaseBuilding_TorchStanding_Blue_C"
    local existing = FindFirstOf(torch_class_name)
    if not existing or not existing:IsValid() then
        ctf_log("No " .. torch_class_name .. " template! Place a colored torch in the arena first.")
        return nil
    end
    local bpClass = existing:GetClass()
    local ok, actor = pcall(function() return world:SpawnActor(bpClass, pos, {}) end)
    if ok and actor and actor:IsValid() then
        pcall(function() actor:K2_SetActorLocation(pos, false, {}, true) end)
        return actor
    end
    return nil
end

local function destroy_flag_torch(team)
    local f = flag_state[team]
    if f.torch_actor and f.torch_actor:IsValid() then
        pcall(function() f.torch_actor:K2_DestroyActor() end)
        f.torch_actor = nil
    end
end

local function reset_flag(team)
    destroy_flag_torch(team)
    flag_state[team].status = "at_base"
    flag_state[team].carrier = nil
    flag_state[team].torch_actor = spawn_flag_torch(FLAG_POSITIONS[team], team)
end

local function setup_flags()
    -- First, destroy any existing torches near flag positions (manually placed ones)
    for _, torch_cls in ipairs({"BP_BaseBuilding_TorchStanding_Red_C", "BP_BaseBuilding_TorchStanding_Blue_C", "BP_BaseBuilding_TorchStanding_C"}) do
        pcall(function()
            local all_torches = FindAllOf(torch_cls)
            if all_torches then
                for _, torch in ipairs(all_torches) do
                    pcall(function()
                        if torch and torch:IsValid() then
                            local loc = torch:K2_GetActorLocation()
                            for _, team in ipairs({"red", "blue"}) do
                                local fpos = FLAG_POSITIONS[team]
                                if fpos and fpos.X ~= 0 then
                                    local dist = distance2d(loc, fpos)
                                    if dist < 150 then
                                        ctf_log("Destroying existing torch near " .. team .. " flag (dist=" .. math.floor(dist) .. ")")
                                        torch:K2_DestroyActor()
                                    end
                                end
                            end
                        end
                    end)
                end
            end
        end)
    end

    -- Now spawn managed flag torches
    reset_flag("red")
    reset_flag("blue")
    ctf_log("Flags spawned at base positions")
end

cleanup_flags = function()
    destroy_flag_torch("red")
    destroy_flag_torch("blue")
    flag_state.red.carrier = nil
    flag_state.blue.carrier = nil
    flag_state.red.status = "at_base"
    flag_state.blue.status = "at_base"

    -- Brute-force: destroy ALL colored torches near flag positions
    for _, torch_cls in ipairs({"BP_BaseBuilding_TorchStanding_Red_C", "BP_BaseBuilding_TorchStanding_Blue_C", "BP_BaseBuilding_TorchStanding_C"}) do
        pcall(function()
            local all_torches = FindAllOf(torch_cls)
            if all_torches then
                for _, torch in ipairs(all_torches) do
                    pcall(function()
                        if torch and torch:IsValid() then
                            local loc = torch:K2_GetActorLocation()
                            for _, team in ipairs({"red", "blue"}) do
                                local fpos = FLAG_POSITIONS[team]
                                if fpos and fpos.X ~= 0 then
                                    local dist = distance2d(loc, fpos)
                                    if dist < 150 then
                                        torch:K2_DestroyActor()
                                    end
                                end
                            end
                        end
                    end)
                end
            end
        end)
    end
end

local function flag_pickup(flag_team, player_id, player_ref)
    destroy_flag_torch(flag_team)
    flag_state[flag_team].status = "carried"
    flag_state[flag_team].carrier = player_id

    -- Give carrier a torch item, then lock inventory
    pcall(function()
        if player_ref and player_ref:IsValid() then
            local ctrl = player_ref:GetInstigatorController()
            if ctrl and ctrl:IsValid() then
                local torch_data = StaticFindObject(TORCH_ITEM_PATH)
                if torch_data and torch_data:IsValid() then
                    ExecuteInGameThread(function()
                        pcall(function() ctrl.BP_Components_Inventory.bAllowRemoves = true end)
                        pcall(function() ctrl.BP_Components_Inventory.bAllowAdds = true end)
                        pcall(function() ctrl.BP_Components_Loadout.bAllowRemoves = true end)
                        pcall(function() ctrl.BP_Components_Loadout.bAllowAdds = true end)
                        pcall(function() ctrl.BP_Components_Loadout:ClearInventory() end)
                        pcall(function() ctrl.BP_Components_Inventory:ClearInventory() end)
                    end)
                    ExecuteWithDelay(500, function()
                        ExecuteInGameThread(function()
                            pcall(function()
                                ctrl.BP_Components_Inventory:AddItemByData(torch_data, 1, 1.0, {})
                                -- Auto-equip torch
                                local inv = ctrl.BP_Components_Inventory
                                local invCtrl = ctrl.BP_Components_InventoryController
                                if invCtrl then
                                    for idx = 0, 15 do
                                        local ok2, item = pcall(function() return inv:GetItemFromSlot(idx) end)
                                        if ok2 and item and item:IsValid() then
                                            pcall(function() invCtrl:UseItemFromInventory(inv, idx) end)
                                            break
                                        end
                                    end
                                end
                            end)
                            -- Lock inventory AFTER torch is equipped
                            ExecuteWithDelay(300, function()
                                ExecuteInGameThread(function()
                                    pcall(function() ctrl.BP_Components_Inventory.bAllowRemoves = false end)
                                    pcall(function() ctrl.BP_Components_Inventory.bAllowAdds = false end)
                                    pcall(function() ctrl.BP_Components_Loadout.bAllowRemoves = false end)
                                    pcall(function() ctrl.BP_Components_Loadout.bAllowAdds = false end)
                                end)
                            end)
                        end)
                    end)
                end
            end
        end
    end)

    -- Block sprint (set stamina to 0)
    pcall(function()
        if player_ref and player_ref:IsValid() then
            local stamina = player_ref.BP_Components_Stamina
            if stamina and stamina:IsValid() then
                pcall(function() stamina:SetStamina(0) end)
                pcall(function() stamina:SetMaxStamina(0) end)
            end
        end
    end)

    send_to_all(flag_team:upper() .. " FLAG TAKEN!", 1, 1, 0)
    ctf_log("FLAG: " .. flag_team .. " flag picked up by P" .. player_id)
end

local function flag_capture(flag_team, carrier_id, carrier_team, carrier_ref, carrier_class)
    ctf_log("FLAG_CAPTURE called: flag=" .. tostring(flag_team) .. " carrier=" .. tostring(carrier_id) .. " team=" .. tostring(carrier_team))
    if not carrier_team then
        ctf_log("  ERROR: no carrier_team!")
        return
    end

    -- Increment captures
    teams[carrier_team].captures = teams[carrier_team].captures + 1
    -- Update player flags if player_data accessible
    pcall(function()
        if player_data and player_data[carrier_id] then
            player_data[carrier_id].flags = (player_data[carrier_id].flags or 0) + 1
        end
    end)

    -- Reset flag back to enemy base
    flag_state[flag_team].status = "at_base"
    flag_state[flag_team].carrier = nil
    reset_flag(flag_team)

    -- Restore carrier: stamina + re-equip gear
    pcall(function()
        if carrier_ref and carrier_ref:IsValid() then
            -- Restore stamina
            local stamina = carrier_ref.BP_Components_Stamina
            if stamina and stamina:IsValid() then
                pcall(function() stamina:SetMaxStamina(100) end)
                pcall(function() stamina:SetStamina(100) end)
            end
            -- Re-equip: class gear if specialized, base kit otherwise
            local cpd = player_data[carrier_id]
            if cpd and cpd.specialized and cpd.class then
                local vcls = cpd.class
                local vteam = carrier_team
                local ca_tier = teams[vteam] and teams[vteam].armor_tier or 2
                local cteam_pvp = teams[vteam] and teams[vteam].pvp_kills or 0
                local cw_tier = 1
                if cteam_pvp >= 36 then cw_tier = 4
                elseif cteam_pvp >= 24 then cw_tier = 3
                elseif cteam_pvp >= 12 then cw_tier = 2 end
                ExecuteWithDelay(300, function()
                    equip_class_for(carrier_ref, vteam, vcls, ca_tier, cw_tier)
                end)
            else
                ExecuteWithDelay(300, function()
                    equip_base_kit_for(carrier_ref, carrier_team)
                end)
            end
        end
    end)

    local ok2, err2 = pcall(function()
        local red_caps = teams.red.captures
        local blue_caps = teams.blue.captures
        send_to_all("===== " .. carrier_team:upper() .. " CAPTURES! =====", 1, 1, 0)
        send_to_all("Captures: RED " .. red_caps .. " - BLUE " .. blue_caps, 1, 0.8, 0)

        -- Update torch lead
        local instant_win = update_torch_lead_after_capture(carrier_team)
        local red_torches = get_torch_display("red")
        local blue_torches = get_torch_display("blue")
        send_to_all("Torches: RED [" .. red_torches .. "]  BLUE [" .. blue_torches .. "]", 1, 0.8, 0)
        ctf_log("CAPTURE: " .. carrier_team .. " scores! RED " .. red_caps .. " - BLUE " .. blue_caps .. " | lead=" .. torch_lead)
    end)
    if not ok2 then ctf_log("CAPTURE ERROR: " .. tostring(err2)) end

    ctf_log("TORCH CHECK: lead=" .. tostring(torch_lead) .. " threshold=" .. tostring(TORCH_WIN_LEAD) .. " abs=" .. tostring(math.abs(torch_lead)))
    if math.abs(torch_lead) >= TORCH_WIN_LEAD then
        ctf_log("!!! TORCH WIN TRIGGERED !!!")
        -- Announce winner
        local winner = torch_lead > 0 and "RED" or "BLUE"
        pcall(function() send_to_all("===== " .. winner .. " TEAM WINS! (3 torch lead) =====", 1, 0.8, 0) end)
        pcall(function() send_to_all("Final Captures: RED " .. teams.red.captures .. " - BLUE " .. teams.blue.captures, 1, 0.8, 0) end)
        game_state.phase = "ended"
        match_active = false
        pcall(function() cleanup_flags() end)
        pcall(function() cleanup_powerups() end)

        -- Teleport all back to lobby after 5s
        ExecuteWithDelay(5000, function()
            pcall(function()
                local all = FindAllOf("BP_PlayerCharacter_C")
                if all then
                    local td = 0
                    for _, pl in ipairs(all) do
                        ExecuteWithDelay(td, function()
                            ExecuteInGameThread(function()
                                pcall(function()
                                    if pl and pl:IsValid() then
                                        pl:K2_SetActorLocation(
                                            {X=BED_LOBBY.X, Y=BED_LOBBY.Y, Z=BED_LOBBY.Z},
                                            false, {}, true)
                                        pcall(function() pl:PlayRespawnVFX() end)
                                    end
                                end)
                            end)
                        end)
                        td = td + 500
                    end
                end
            end)
            send_to_all("Returned to lobby!", 1, 1, 0)
            pcall(function()
                local ma = FindFirstOf("ModActor_C")
                if ma and ma:IsValid() then
                    for _, prefix in ipairs({"Red", "Blue"}) do
                        for slot = 1, 3 do
                            ma[prefix .. slot .. "Name"] = ""
                            ma[prefix .. slot .. "Class"] = ""
                            ma[prefix .. slot .. "Kills"] = ""
                            ma[prefix .. slot .. "Deaths"] = ""
                            ma[prefix .. slot .. "Flags"] = ""
                        end
                    end
                    local widget = ma.ScoreboardWidget
                    if widget and widget:IsValid() then
                        widget:SetVisibility(2)
                    end
                end
            end)
            game_state.phase = "idle"
            lobby_active = false
        end)
    end
end

local function flag_carrier_died(victim_pid)
    for _, flag_team in ipairs({"red", "blue"}) do
        if flag_state[flag_team].carrier == victim_pid then
            flag_state[flag_team].carrier = nil
            reset_flag(flag_team)
            send_to_all(flag_team:upper() .. " FLAG RETURNED!", 1, 1, 0)
            ctf_log("FLAG: " .. flag_team .. " flag returned (carrier P" .. victim_pid .. " died)")

            -- Restore stamina
            pcall(function()
                local all_p = get_all_players()
                for _, p in ipairs(all_p) do
                    if p.id == victim_pid and p.ref and p.ref:IsValid() then
                        local stamina = p.ref.BP_Components_Stamina
                        if stamina and stamina:IsValid() then
                            pcall(function() stamina:SetMaxStamina(100) end)
                            pcall(function() stamina:SetStamina(100) end)
                        end
                        -- Unlock inventory
                        local ctrl = p.ref:GetInstigatorController()
                        if ctrl and ctrl:IsValid() then
                            pcall(function() ctrl.BP_Components_Inventory.bAllowRemoves = true end)
                            pcall(function() ctrl.BP_Components_Inventory.bAllowAdds = true end)
                            pcall(function() ctrl.BP_Components_Loadout.bAllowRemoves = true end)
                            pcall(function() ctrl.BP_Components_Loadout.bAllowAdds = true end)
                        end
                        break
                    end
                end
            end)
            return true
        end
    end
    return false
end

------------------------------------------------------------
-- POWERUP SYSTEM (Wild Anima pickups)
------------------------------------------------------------
-- Powerup spawn positions: SET THESE to your arena coordinates
local POWERUP_POSITIONS = {
    {X=31602, Y=171621, Z=-3369},
    {X=33615, Y=173630, Z=-3671},
    {X=35627, Y=175649, Z=-3369},
}
local POWERUP_PICKUP_RADIUS = 250
local POWERUP_BUFF_DURATION = 45  -- seconds
local POWERUP_RESPAWN_TIME = 120  -- seconds
local ANIMA_ASSET = "/Game/Gameplay/BaseBuilding_New/BuildingPieces/Decorations/Materials/BP_BaseBuilding_Decoration_Material_Anima_Wild.BP_BaseBuilding_Decoration_Material_Anima_Wild_C"

local powerup_spawns = {}  -- {pos, active, last_pickup, anima_actor}
local powerup_buffs = {}   -- {[player_id] = {class, expires, player_ref}

-- Class-specific powerup effects (from CLAUDE.md spec)
-- Archer: Poison Arrows (until death) — swap to poisoned ammo
-- Assassin: Invisibility (45s) — PlayDespawnVFX, then PlayRespawnVFX on expire
-- Guardian: Armor bonus (until death) — boost max HP
-- Berserker: Whetstone/damage boost (until death) — upgrade weapon tier
-- Fire Mage: Magic potion (45s) — boost max HP temporarily
-- Air Mage: Magical focus (45s) — boost max HP temporarily

-- Forward-declared, defined after CLASS_WEAP
local apply_powerup_buff
local remove_powerup_buff

local function spawn_anima(pos)
    local player = FindFirstOf("BP_PlayerCharacter_C")
    if not player then return nil end
    local world = player:GetWorld()
    if not world or not world:IsValid() then return nil end
    local freshClass = StaticFindObject(ANIMA_ASSET)
    if not freshClass or not freshClass:IsValid() then
        local existing = FindFirstOf("BP_BaseBuilding_Decoration_Material_Anima_Wild_C")
        if existing and existing:IsValid() then
            freshClass = existing:GetClass()
        else
            return nil
        end
    end
    local ok, actor = pcall(function() return world:SpawnActor(freshClass, pos, {}) end)
    if ok and actor and actor:IsValid() then
        pcall(function() actor:K2_SetActorLocation(pos, false, {}, true) end)
        return actor
    end
    return nil
end

local function setup_powerups()
    -- Always cleanup first to prevent stacking
    cleanup_powerups()
    powerup_spawns = {}
    powerup_buffs = {}
    for _, pos in ipairs(POWERUP_POSITIONS) do
        local spawn = {
            pos = pos,
            active = true,
            last_pickup = 0,
            anima_actor = spawn_anima(pos),
        }
        table.insert(powerup_spawns, spawn)
    end
    ctf_log("Powerups spawned: " .. #powerup_spawns)
end

------------------------------------------------------------
-- BED MANAGEMENT (destroy + respawn fresh between matches)
------------------------------------------------------------
-- BED_LOBBY forward-declared at top
local BED_POSITIONS = {
    {X=37177, Y=176852, Z=-3668},
    {X=36856, Y=177173, Z=-3668},
    {X=36538, Y=177489, Z=-3653},
    {X=36221, Y=177811, Z=-3668},
    {X=36150, Y=175834, Z=-3668},
    {X=35835, Y=176156, Z=-3668},
    {X=35510, Y=176474, Z=-3668},
    {X=35199, Y=176794, Z=-3668},
}
local BED_LOBBY_RADIUS = 3000  -- all beds are within this radius of lobby center

local function destroy_lobby_beds()
    pcall(function()
        local beds = FindAllOf("BP_BaseBuilding_Bed_C")
        if not beds then return end
        local lobby = BED_LOBBY  -- {X=37473, Y=175582, Z=-3760}
        for _, bed in ipairs(beds) do
            pcall(function()
                if bed and bed:IsValid() then
                    local loc = bed:K2_GetActorLocation()
                    local dist = distance2d(loc, lobby)
                    if dist < BED_LOBBY_RADIUS then
                        bed:K2_DestroyActor()
                    end
                end
            end)
        end
        ctf_log("Lobby beds destroyed")
    end)
end

local function spawn_lobby_beds()
    pcall(function()
        -- Get class reference from any existing bed in the world
        local existing = FindFirstOf("BP_BaseBuilding_Bed_C")
        if not existing or not existing:IsValid() then
            ctf_log("No bed template found — can't respawn beds")
            return
        end
        local bpClass = existing:GetClass()
        local player = FindFirstOf("BP_PlayerCharacter_C")
        if not player then return end
        local world = player:GetWorld()
        if not world then return end

        local delay = 0
        for _, pos in ipairs(BED_POSITIONS) do
            ExecuteWithDelay(delay, function()
                ExecuteInGameThread(function()
                    pcall(function()
                        local bed = world:SpawnActor(bpClass, pos, {})
                        if bed and bed:IsValid() then
                            bed:K2_SetActorLocation(pos, false, {}, true)
                        end
                    end)
                end)
            end)
            delay = delay + 300
        end
        ctf_log("Lobby beds respawned (" .. #BED_POSITIONS .. ")")
    end)
end

local function refresh_beds()
    destroy_lobby_beds()
    ExecuteWithDelay(2000, function()
        spawn_lobby_beds()
    end)
end

cleanup_powerups = function()
    for _, spawn in ipairs(powerup_spawns) do
        if spawn.anima_actor and spawn.anima_actor:IsValid() then
            pcall(function() spawn.anima_actor:K2_DestroyActor() end)
        end
    end
    powerup_spawns = {}
    powerup_buffs = {}
end

-- player_data[id] = {team="red"|"blue", class=nil, kills=0, deaths=0, specialized=false}
-- (player_data declared earlier in forward declarations)

-- PvE kill requirements per role
local PVE_KILL_REQ = {wolf=10, archer=4, mage=4, tank=2, boss=1}

-- Get all players as a list of {id, ref, pos}
local function get_all_players()
    local result = {}
    pcall(function()
        local all = FindAllOf("BP_PlayerCharacter_C")
        if all then
            for _, p in ipairs(all) do
                pcall(function()
                    if p and p:IsValid() then
                        local ctrl = p:GetInstigatorController()
                        local id = 0
                        if ctrl and ctrl:IsValid() then
                            pcall(function() id = ctrl.PlayerState.PlayerId end)
                        end
                        local pos = p:K2_GetActorLocation()
                        table.insert(result, {id=id, ref=p, pos={X=pos.X, Y=pos.Y, Z=pos.Z}})
                    end
                end)
            end
        end
    end)
    return result
end

-- Find which team a player belongs to
local function get_player_team(player_id)
    if player_data[player_id] then return player_data[player_id].team end
    return nil
end

-- Send colored message to a specific player (via their controller)
send_team_msg = function(player_ref, msg, r, g, b)
    pcall(function()
        local ctrl = player_ref:GetInstigatorController()
        if ctrl and ctrl:IsValid() then
            ctrl.PlayerChat:Client_ReceiveChatMessage({
                PlayerId = 0,
                Color = {R=r or 1, G=g or 1, B=b or 1, A=1},
                PlayerName = "",
                MessageBody = msg,
            })
        end
    end)
end

-- Send message to all players on a team
send_to_team = function(team_name, msg)
    local t = teams[team_name]
    if not t then return end
    local c = t.color
    for _, p in ipairs(t.players) do
        pcall(function()
            if p.ref and p.ref:IsValid() then
                send_team_msg(p.ref, "[" .. team_name:upper() .. "] " .. msg, c.R, c.G, c.B)
            end
        end)
    end
end

-- Send message to ALL players
send_to_all = function(msg, r, g, b)
    pcall(function()
        local all = FindAllOf("BP_PlayerCharacter_C")
        if all then
            for _, p in ipairs(all) do
                send_team_msg(p, msg, r, g, b)
            end
        end
    end)
end

-- Auto-assign players to teams (first 3 = red, next 3 = blue)
local function assign_teams()
    local players = get_all_players()
    teams.red.players = {}
    teams.blue.players = {}
    player_data = {}

    ctf_log("=== TEAM ASSIGNMENT ===")
    ctf_log("Players found: " .. #players)

    local half = math.ceil(#players / 2)  -- split evenly (2 players: 1 red, 1 blue)
    for i, p in ipairs(players) do
        local team_name = (i <= half) and "red" or "blue"
        table.insert(teams[team_name].players, {id=p.id, ref=p.ref})
        player_data[p.id] = {
            team = team_name,
            class = nil,
            kills = 0,
            deaths = 0,
            specialized = false,
        }
        teams[team_name].individual_kills[p.id] = 0
        ctf_log("P" .. i .. " (ID=" .. p.id .. ") -> " .. team_name:upper())
        send_team_msg(p.ref, "You are on " .. team_name:upper() .. " team!",
            teams[team_name].color.R, teams[team_name].color.G, teams[team_name].color.B)

        -- Equip base kit with team cape (stagger per player to avoid crashes)
        ExecuteWithDelay(i * 1500, function()
            pcall(function()
                equip_base_kit_for(p.ref, team_name)
            end)
        end)
    end

    ctf_log("Red: " .. #teams.red.players .. " | Blue: " .. #teams.blue.players)
    send_to_all("Teams assigned! Red: " .. #teams.red.players .. " | Blue: " .. #teams.blue.players, 1, 1, 0)
    ctf_log("=== TEAMS READY ===")
end

-- Reset all game state
local function reset_game_state()
    game_state.phase = "idle"
    game_state.match_time = 0
    game_state.pve_event = 0
    for _, team_name in ipairs({"red", "blue"}) do
        local t = teams[team_name]
        t.pve_kills = {wolf=0, archer=0, mage=0, tank=0, boss=0}
        t.pvp_kills = 0
        t.captures = 0
        t.armor_tier = 2
        t.individual_kills = {}
    end
    player_data = {}
    cleanup_flags()
    cleanup_powerups()
    refresh_beds()
    ctf_log("Game state reset")
end

-- Check if a team has completed PvE kill requirements
local function check_pve_completion(team_name)
    local t = teams[team_name]
    local missing = {}
    for role, req in pairs(PVE_KILL_REQ) do
        local cur = t.pve_kills[role] or 0
        if cur < req then
            table.insert(missing, role .. ":" .. cur .. "/" .. req)
        end
    end
    if #missing > 0 then
        ctf_log(team_name:upper() .. " PvE incomplete: " .. table.concat(missing, ", "))
        return false
    end
    ctf_log(team_name:upper() .. " PvE ALL REQUIREMENTS MET!")
    return true
end

-- Get PvE progress string for a team
local function pve_progress_str(team_name)
    local t = teams[team_name]
    local parts = {}
    for _, role in ipairs({"wolf", "archer", "mage", "tank", "boss"}) do
        local cur = t.pve_kills[role] or 0
        local req = PVE_KILL_REQ[role]
        table.insert(parts, role .. ":" .. cur .. "/" .. req)
    end
    return table.concat(parts, " | ")
end

------------------------------------------------------------
-- ASSET PATHS
------------------------------------------------------------
local CAPE = {
    RedAdv   = "/Game/Gameplay/Character/Player/Equipment/Cape/ITEM_Cape_Adventurers_Red.ITEM_Cape_Adventurers_Red",
    BlueAdv  = "/Game/Gameplay/Character/Player/Equipment/Cape/ITEM_Cape_Adventurers_Blue.ITEM_Cape_Adventurers_Blue",
    RedDyad  = "/DowdunReach/Gameplay/Character/Player/Equipment/Cape/ITEM_Cape_RedDyad.ITEM_Cape_RedDyad",
    BlueDyad = "/DowdunReach/Gameplay/Character/Player/Equipment/Cape/ITEM_Cape_BlueDyad.ITEM_Cape_BlueDyad",
    RedHex   = "/DowdunReach/Gameplay/Character/Player/Equipment/Cape/ITEM_Cape_RedHex.ITEM_Cape_RedHex",
    BlueHex  = "/DowdunReach/Gameplay/Character/Player/Equipment/Cape/ITEM_Cape_BlueHex.ITEM_Cape_BlueHex",
    Attack   = "/Game/Gameplay/Character/Player/Equipment/Cape/ITEM_Cape_Trimmed_Skillcape_Attack.ITEM_Cape_Trimmed_Skillcape_Attack",
    Magic    = "/Game/Gameplay/Character/Player/Equipment/Cape/ITEM_Cape_Trimmed_Skillcape_Magic.ITEM_Cape_Trimmed_Skillcape_Magic",
}

local BASE_WEAP = {
    SwingSlash = "/Game/Gameplay/Character/Player/Equipment/Held/Mace/ITEM_Club_SwingSlash.ITEM_Club_SwingSlash",
    AshBow     = "/Game/Gameplay/Character/Player/Equipment/Held/Bow/ITEM_Shortbow_Wood.ITEM_Shortbow_Wood",
    BoneArrows = "/Game/Gameplay/Character/Player/Equipment/Ammo/ITEM_Ammo_Arrows_Bone_Bodkin.ITEM_Ammo_Arrows_Bone_Bodkin",
}

local BASE_ARMOR = {
    head = "/Game/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T2_Head_Reinforced.ITEM_Armour_T2_Head_Reinforced",
    body = "/Game/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T2_Body_Reinforced.ITEM_Armour_T2_Body_Reinforced",
    legs = "/Game/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T2_Legs_Reinforced.ITEM_Armour_T2_Legs_Reinforced",
}

-- Armor per class per tier index (1=T3, 2=T4, 3=T5, 4=T6)
local CLASS_ARMOR = {
    archer = {
        {head="/Game/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T3_Head_HardLeather.ITEM_Armour_T3_Head_HardLeather", body="/Game/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T3_Body_HardLeather.ITEM_Armour_T3_Body_HardLeather", legs="/Game/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T3_Legs_HardLeather.ITEM_Armour_T3_Legs_HardLeather"},
        {head="/Game/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T4_Head_WildArcher.ITEM_Armour_T4_Head_WildArcher", body="/Game/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T4_Body_WildArcher.ITEM_Armour_T4_Body_WildArcher", legs="/Game/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T4_Legs_WildArcher.ITEM_Armour_T4_Legs_WildArcher"},
        {head="/Game/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T5_Head_Ranger.ITEM_Armour_T5_Head_Ranger", body="/Game/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T5_Body_Ranger.ITEM_Armour_T5_Body_Ranger", legs="/Game/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T5_Legs_Ranger.ITEM_Armour_T5_Legs_Ranger"},
        {head="/DowdunReach/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T6_Head_BlackRanger.ITEM_Armour_T6_Head_BlackRanger", body="/DowdunReach/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T6_Body_BlackRanger.ITEM_Armour_T6_Body_BlackRanger", legs="/DowdunReach/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T6_Legs_BlackRanger.ITEM_Armour_T6_Legs_BlackRanger"},
    },
    assassin = {
        {head="/Game/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T3_Head_HardLeather.ITEM_Armour_T3_Head_HardLeather", body="/Game/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T3_Body_HardLeather.ITEM_Armour_T3_Body_HardLeather", legs="/Game/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T3_Legs_HardLeather.ITEM_Armour_T3_Legs_HardLeather"},
        {head="/Game/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T4_Head_StuddedLeather.ITEM_Armour_T4_Head_StuddedLeather", body="/Game/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T4_Body_StuddedLeather.ITEM_Armour_T4_Body_StuddedLeather", legs="/Game/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T4_Legs_StuddedLeather.ITEM_Armour_T4_Legs_StuddedLeather"},
        {head="/Game/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T5_Head_GreenDragonHide.ITEM_Armour_T5_Head_GreenDragonHide", body="/Game/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T5_Body_GreenDragonHide.ITEM_Armour_T5_Body_GreenDragonHide", legs="/Game/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T5_Legs_GreenDragonHide.ITEM_Armour_T5_Legs_GreenDragonHide"},
        {head="/DowdunReach/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T6_Head_BlueDragonhide.ITEM_Armour_T6_Head_BlueDragonhide", body="/DowdunReach/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T6_Body_BlueDragonHide.ITEM_Armour_T6_Body_BlueDragonHide", legs="/DowdunReach/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T6_Legs_BlueDragonhide.ITEM_Armour_T6_Legs_BlueDragonhide"},
    },
    guardian = {
        {head="/Game/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T3_Head_Bronze.ITEM_Armour_T3_Head_Bronze", body="/Game/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T3_Body_Bronze.ITEM_Armour_T3_Body_Bronze", legs="/Game/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T3_Legs_Bronze.ITEM_Armour_T3_Legs_Bronze"},
        {head="/Game/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T4_Head_Paladin.ITEM_Armour_T4_Head_Paladin", body="/Game/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T4_Body_Paladin.ITEM_Armour_T4_Body_Paladin", legs="/Game/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T4_Legs_Paladin.ITEM_Armour_T4_Legs_Paladin"},
        {head="/Game/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T5_Head_White.ITEM_Armour_T5_Head_White", body="/Game/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T5_Body_White.ITEM_Armour_T5_Body_White", legs="/Game/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T5_Legs_White.ITEM_Armour_T5_Legs_White"},
        {head="/DowdunReach/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T6_Head_Mithril.ITEM_Armour_T6_Head_Mithril", body="/DowdunReach/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T6_Body_Mithril.ITEM_Armour_T6_Body_Mithril", legs="/DowdunReach/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T6_Legs_Mithril.ITEM_Armour_T6_Legs_Mithril"},
    },
    berserker = {
        {head="/Game/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T3_Head_Bronze.ITEM_Armour_T3_Head_Bronze", body="/Game/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T3_Body_Bronze.ITEM_Armour_T3_Body_Bronze", legs="/Game/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T3_Legs_Bronze.ITEM_Armour_T3_Legs_Bronze"},
        {head="/Game/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T4_Head_Iron.ITEM_Armour_T4_Head_Iron", body="/Game/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T4_Body_Iron.ITEM_Armour_T4_Body_Iron", legs="/Game/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T4_Legs_Iron.ITEM_Armour_T4_Legs_Iron"},
        {head="/Game/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T5_Head_Skeleton.ITEM_Armour_T5_Head_Skeleton", body="/Game/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T5_Body_Skeleton.ITEM_Armour_T5_Body_Skeleton", legs="/Game/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T5_Legs_Skeleton.ITEM_Armour_T5_Legs_Skeleton"},
        {head="/DowdunReach/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T6_Head_Black.ITEM_Armour_T6_Head_Black", body="/DowdunReach/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T6_Body_Black.ITEM_Armour_T6_Body_Black", legs="/DowdunReach/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T6_Legs_Black.ITEM_Armour_T6_Legs_Black"},
    },
    fire_mage = {
        {head="/Game/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T3_Head_Wizard.ITEM_Armour_T3_Head_Wizard", body="/Game/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T3_Body_Wizard.ITEM_Armour_T3_Body_Wizard", legs="/Game/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T3_Legs_Wizard.ITEM_Armour_T3_Legs_Wizard"},
        {head="/Game/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T4_Head_DragonkinMage.ITEM_Armour_T4_Head_DragonkinMage", body="/Game/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T4_Body_DragonkinMage.ITEM_Armour_T4_Body_DragonkinMage", legs="/Game/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T4_Legs_DragonkinMage.ITEM_Armour_T4_Legs_DragonkinMage"},
        {head="/Game/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T5_Head_Necromancer.ITEM_Armour_T5_Head_Necromancer", body="/Game/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T5_Body_Necromancer.ITEM_Armour_T5_Body_Necromancer", legs="/Game/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T5_Legs_Necromancer.ITEM_Armour_T5_Legs_Necromancer"},
        {head="/DowdunReach/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T6_Head_Zamorak.ITEM_Armour_T6_Head_Zamorak", body="/DowdunReach/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T6_Body_Zamorak.ITEM_Armour_T6_Body_Zamorak", legs="/DowdunReach/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T6_Legs_Zamorak.ITEM_Armour_T6_Legs_Zamorak"},
    },
    air_mage = {
        {head="/Game/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T3_Head_Wizard.ITEM_Armour_T3_Head_Wizard", body="/Game/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T3_Body_Wizard.ITEM_Armour_T3_Body_Wizard", legs="/Game/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T3_Legs_Wizard.ITEM_Armour_T3_Legs_Wizard"},
        {head="/Game/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T4_Head_DarkMage.ITEM_Armour_T4_Head_DarkMage", body="/Game/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T4_Body_DarkMage.ITEM_Armour_T4_Body_DarkMage", legs="/Game/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T4_Legs_DarkMage.ITEM_Armour_T4_Legs_DarkMage"},
        {head="/Game/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T5_Head_Splitbark.ITEM_Armour_T5_Head_Splitbark", body="/Game/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T5_Body_Splitbark.ITEM_Armour_T5_Body_Splitbark", legs="/Game/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T5_Legs_Splitbark.ITEM_Armour_T5_Legs_Splitbark"},
        {head="/DowdunReach/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T6_Head_Mystic.ITEM_Armour_T6_Head_Mystic", body="/DowdunReach/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T6_Body_Mystic.ITEM_Armour_T6_Body_Mystic", legs="/DowdunReach/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T6_Legs_Mystic.ITEM_Armour_T6_Legs_Mystic"},
    },
}

-- Weapons per class per tier (1=T3 spec, 2=T4, 3=T5, 4=T6)
local CLASS_WEAP = {
    archer = {
        {"/Game/Gameplay/Character/Player/Equipment/Held/Bow/ITEM_Shortbow_Oak.ITEM_Shortbow_Oak", "/Game/Gameplay/Character/Player/Equipment/Held/Bow/ITEM_Longbow_Oak.ITEM_Longbow_Oak"},
        {"/Game/Gameplay/Character/Player/Equipment/Held/Bow/ITEM_Shortbow_Hunter.ITEM_Shortbow_Hunter", "/Game/Gameplay/Character/Player/Equipment/Held/Bow/ITEM_Longbow_Hunter.ITEM_Longbow_Hunter"},
        {"/Game/Gameplay/Character/Player/Equipment/Held/Bow/ITEM_Shortbow_Willow.ITEM_Shortbow_Willow", "/Game/Gameplay/Character/Player/Equipment/Held/Bow/ITEM_Longbow_Willow.ITEM_Longbow_Willow"},
        {"/DowdunReach/Gameplay/Character/Player/Equipment/Held/Bow/ITEM_Shortbow_Maple.ITEM_Shortbow_Maple", "/DowdunReach/Gameplay/Character/Player/Equipment/Held/Bow/ITEM_Longbow_Maple.ITEM_Longbow_Maple"},
    },
    assassin = {
        {"/Game/Gameplay/Character/Player/Equipment/Held/Dagger/ITEM_Dagger_Bronze.ITEM_Dagger_Bronze"},
        {"/Game/Gameplay/Character/Player/Equipment/Held/Dagger/ITEM_Dagger_Iron.ITEM_Dagger_Iron"},
        {"/Game/Gameplay/Character/Player/Equipment/Held/Dagger/ITEM_Dagger_Steel.ITEM_Dagger_Steel"},
        {"/DowdunReach/Gameplay/Character/Player/Equipment/Held/Dagger/ITEM_Dagger_Mithril.ITEM_Dagger_Mithril"},
    },
    guardian = {
        {"/Game/Gameplay/Character/Player/Equipment/Held/Sword/ITEM_Sword_Bronze.ITEM_Sword_Bronze", "/Game/Gameplay/Character/Player/Equipment/Held/Shield/ITEM_Shield_Bronze.ITEM_Shield_Bronze"},
        {"/Game/Gameplay/Character/Player/Equipment/Held/Sword/ITEM_Sword_Iron.ITEM_Sword_Iron", "/Game/Gameplay/Character/Player/Equipment/Held/Shield/ITEM_Shield_Iron.ITEM_Shield_Iron"},
        {"/Game/Gameplay/Character/Player/Equipment/Held/Sword/ITEM_Sword_Steel.ITEM_Sword_Steel", "/Game/Gameplay/Character/Player/Equipment/Held/Shield/ITEM_Shield_Steel.ITEM_Shield_Steel"},
        {"/DowdunReach/Gameplay/Character/Player/Equipment/Held/Sword/ITEM_Sword_Mithril.ITEM_Sword_Mithril", "/DowdunReach/Gameplay/Character/Player/Equipment/Held/Shield/ITEM_Shield_Mithril.ITEM_Shield_Mithril"},
    },
    berserker = {
        {"/Game/Gameplay/Character/Player/Equipment/Held/GreatSword/ITEM_GreatSword_Bronze.ITEM_GreatSword_Bronze"},
        {"/Game/Gameplay/Character/Player/Equipment/Held/GreatSword/ITEM_GreatSword_Iron.ITEM_GreatSword_Iron"},
        {"/Game/Gameplay/Character/Player/Equipment/Held/GreatSword/ITEM_GreatSword_Steel.ITEM_GreatSword_Steel"},
        {"/DowdunReach/Gameplay/Character/Player/Equipment/Held/GreatSword/ITEM_GreatSword_Mithril.ITEM_GreatSword_Mithril"},
    },
    fire_mage = {
        {"/Game/Gameplay/Character/Player/Equipment/Held/Staff/ITEM_Staff_Garou.ITEM_Staff_Garou"},
        {"/Game/Gameplay/Character/Player/Equipment/Held/Staff/ITEM_Staff_Battlestaff.ITEM_Staff_Battlestaff"},
        {"/Game/Gameplay/Character/Player/Equipment/Held/Staff/ITEM_Staff_Splitbark.ITEM_Staff_Splitbark"},
        {"/DowdunReach/Gameplay/Character/Player/Equipment/Held/Staff/ITEM_Staff_Maple.ITEM_Staff_Maple"},
    },
    air_mage = {
        {"/Game/Gameplay/Character/Player/Equipment/Held/Staff/ITEM_Staff_Oak.ITEM_Staff_Oak"},
        {"/Game/Gameplay/Character/Player/Equipment/Held/Staff/ITEM_Staff_Battlestaff.ITEM_Staff_Battlestaff"},
        {"/Game/Gameplay/Character/Player/Equipment/Held/Staff/ITEM_Staff_Splitbark.ITEM_Staff_Splitbark"},
        {"/DowdunReach/Gameplay/Character/Player/Equipment/Held/Staff/ITEM_Staff_Maple.ITEM_Staff_Maple"},
    },
}

-- Ammo per tier (1=T3, 2=T4, 3=T5, 4=T6)
local ARCHER_AMMO = {
    "/Game/Gameplay/Character/Player/Equipment/Ammo/ITEM_Ammo_Arrows_Bronze_Bodkin.ITEM_Ammo_Arrows_Bronze_Bodkin",
    "/Game/Gameplay/Character/Player/Equipment/Ammo/ITEM_Ammo_Arrows_Iron_Bodkin.ITEM_Ammo_Arrows_Iron_Bodkin",
    "/Game/Gameplay/Character/Player/Equipment/Ammo/ITEM_Ammo_Arrows_Steel_Bodkin.ITEM_Ammo_Arrows_Steel_Bodkin",
    "/DowdunReach/Gameplay/Character/Player/Equipment/Ammo/ITEM_Ammo_Arrows_Mithril_Bodkin.ITEM_Ammo_Arrows_Mithril_Bodkin",
}
local CLASS_AMMO = { archer = "/Game/Gameplay/Character/Player/Equipment/Ammo/ITEM_Ammo_Arrows_Bone_Bodkin.ITEM_Ammo_Arrows_Bone_Bodkin" }

local RUNE = {
    Air    = "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Air.ITEM_Rune_Air",
    Fire   = "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Fire.ITEM_Rune_Fire",
    Nature = "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Nature.ITEM_Rune_Nature",
    Law    = "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Law.ITEM_Rune_Law",
    Astral = "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Astral.ITEM_Rune_Astral",
}

-- Class runes: spell runes (×5 casts) + combat ammo for mages
local CLASS_RUNES = {
    archer    = {{RUNE.Astral, 75}, {RUNE.Nature, 50}},                    -- Snare: 15 astral + 10 nature ×5
    assassin  = {{RUNE.Air, 75}, {RUNE.Astral, 25}},                      -- Enchant Air: 15 air + 5 astral ×5
    guardian  = {{RUNE.Air, 75}},                                           -- Tempest Shield: 15 air ×5
    berserker = {{RUNE.Fire, 75}, {RUNE.Astral, 25}},                     -- Enchant Fire: 15 fire + 5 astral ×5
    fire_mage = {{RUNE.Fire, 2000}, {RUNE.Astral, 50}, {RUNE.Law, 50}},  -- Fire ammo (2000) + Surge: 10 astral + 10 law ×5
    air_mage  = {{RUNE.Air, 2000}, {RUNE.Astral, 50}, {RUNE.Law, 50}},   -- Air ammo (2000) + Surge: 10 astral + 10 law ×5
}

local TRINKETS = {
    archer    = "/Game/Gameplay/Character/Player/Equipment/Jewellery/ITEM_Trinket_Iconic_Amulet_of_Accuracy.ITEM_Trinket_Iconic_Amulet_of_Accuracy",
    assassin  = "/DowdunReach/Gameplay/Character/Player/Equipment/Jewellery/ITEM_Trinket_Unholy_Symbol.ITEM_Trinket_Unholy_Symbol",
    guardian  = "/Game/Gameplay/Character/Player/Equipment/Jewellery/ITEM_Trinket_Iconic_Ring_of_Recoil.ITEM_Trinket_Iconic_Ring_of_Recoil",
    berserker = "/Game/Gameplay/Character/Player/Equipment/Jewellery/ITEM_Trinket_Iconic_Amulet_of_Strength.ITEM_Trinket_Iconic_Amulet_of_Strength",
    fire_mage = "/Game/Gameplay/Character/Player/Equipment/Jewellery/ITEM_Trinket_Iconic_Amulet_of_Magic.ITEM_Trinket_Iconic_Amulet_of_Magic",
    air_mage  = "/Game/Gameplay/Character/Player/Equipment/Jewellery/ITEM_Trinket_Iconic_Amulet_of_Magic.ITEM_Trinket_Iconic_Amulet_of_Magic",
}

------------------------------------------------------------
-- EQUIP BASE KIT (multiplayer — must be after BASE_WEAP defined)
------------------------------------------------------------
equip_base_kit_for = function(player_ref, team_name)
    local ctrl = get_controller_for(player_ref)
    if not ctrl or not ctrl:IsValid() then
        ctf_log("equip_base_kit_for: no controller")
        return
    end

    local cape_path = (team_name == "red") and CAPE.RedAdv or CAPE.BlueAdv

    -- T2 Reinforced armor
    local t2 = {
        head = "/Game/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T2_Head_Reinforced.ITEM_Armour_T2_Head_Reinforced",
        body = "/Game/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T2_Body_Reinforced.ITEM_Armour_T2_Body_Reinforced",
        legs = "/Game/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T2_Legs_Reinforced.ITEM_Armour_T2_Legs_Reinforced",
    }

    ExecuteInGameThread(function()
        unlock_inv_for(ctrl)
        clear_all_for(ctrl)

        ExecuteWithDelay(500, function()
            ExecuteInGameThread(function()
                add_to_loadout_for(ctrl, t2.head)
                add_to_loadout_for(ctrl, t2.body)
                add_to_loadout_for(ctrl, t2.legs)
                add_to_loadout_for(ctrl, cape_path)
                add_item_for(ctrl, BASE_WEAP.SwingSlash, 1)
                add_item_for(ctrl, BASE_WEAP.AshBow, 1)
                add_item_for(ctrl, BASE_WEAP.BoneArrows, 50)
                ctf_log("Equipped base kit for " .. team_name .. " player")
            end)
        end)
    end)
end

-- equip_class_for and equip_base_kit_for forward-declared at top (line ~612)

------------------------------------------------------------
-- STATE
------------------------------------------------------------
-- lobby_active, match_active declared earlier in forward declarations
local locked = false
local selected_class = nil
local selected_team = nil
local spawned_lodestones = {}
local equip_busy = false
local armor_tier = 0   -- 0=base(T2), 1=T3(spec), 2=T4, 3=T5, 4=T6
local weapon_tier = 0  -- 0=base, 1=T3(spec), 2=T4, 3=T5, 4=T6
local pve_event = 0    -- 0=none, 1=wolves done, 2=rotsworn done, 3=dragon done
local trinket_earned = false
local runes_given = false
local spawned_mobs = {}

local LOBBY_RADIUS = 190
local TEAM_RADIUS = 190
local last_equip_time = 0  -- shared cooldown for ANY equip (team or class switch)
local debug_equip_mode = 0  -- 0=all, 1=armor, 2=weapons, 3=cape, 4=armor+cape, 5=armor+weapons, 6=cape+weapons

local lodestone_positions = {
    team_red    = {X=34501, Y=177490, Z=-3394},
    team_blue   = {X=35523, Y=178519, Z=-3394},
    team_random = {X=34586, Y=178363, Z=-3471},
    -- Red class lobby
    red_archer    = {X=37568, Y=167182, Z=-3490},
    red_assassin  = {X=38285, Y=166856, Z=-3489},
    red_guardian  = {X=39021, Y=166970, Z=-3489},
    red_berserker = {X=40400, Y=168340, Z=-3489},
    red_fire_mage = {X=40513, Y=169066, Z=-3489},
    red_air_mage  = {X=40206, Y=169808, Z=-3489},
    -- Blue class lobby
    blue_archer    = {X=29667, Y=180097, Z=-3789},
    blue_assassin  = {X=28952, Y=180426, Z=-3789},
    blue_guardian  = {X=28218, Y=180307, Z=-3790},
    blue_berserker = {X=26933, Y=179041, Z=-3804},
    blue_fire_mage = {X=26732, Y=178203, Z=-3805},
    blue_air_mage  = {X=27043, Y=177449, Z=-3804},
}

-- Teleport destinations: team selection → class lobby
local team_lobby_spawns = {
    red = {
        {X=39337, Y=168682, Z=-3611},
        {X=39198, Y=168510, Z=-3611},
        {X=38865, Y=168155, Z=-3611},
        {X=38661, Y=167952, Z=-3611},
    },
    blue = {  -- mirrored from red: Blue = 67259-RedX, 347248-RedY
        {X=27922, Y=178566, Z=-3611},
        {X=28061, Y=178738, Z=-3611},
        {X=28394, Y=179093, Z=-3611},
        {X=28598, Y=179296, Z=-3611},
    },
}

-- Fixed spawn: per-player positions at match start (GO!)
-- Facing direction (Yaw) — rotates both character model and camera
local team_spawn_yaw = {
    red  = 135,   -- faces towards blue side
    blue = -45,   -- faces towards red side (180° opposite)
}

local function snap_camera(player_ref, yaw)
    pcall(function()
        local ctrl = player_ref:GetInstigatorController()
        if ctrl and ctrl:IsValid() then
            ctrl:SetControlRotation({Pitch=0, Yaw=yaw, Roll=0})
        end
    end)
end

local team_spawn_initial = {
    red = {
        {X=38082, Y=169179, Z=-3284},  -- player 1
        {X=37862, Y=168971, Z=-3284},  -- player 2
        {X=38291, Y=169404, Z=-3284},  -- player 3
        {X=38342, Y=169450, Z=-3284},  -- player 4 (future expansion)
        {X=38181, Y=169291, Z=-3284},  -- player 5
        {X=37966, Y=169077, Z=-3284},  -- player 6
        {X=37813, Y=168909, Z=-3284},  -- player 7
    },
    blue = {
        {X=29177, Y=178069, Z=-3284},  -- player 1 (mirrored from red)
        {X=29397, Y=178277, Z=-3284},  -- player 2
        {X=28968, Y=177844, Z=-3284},  -- player 3
        {X=28917, Y=177798, Z=-3284},  -- player 4 (future expansion)
        {X=29078, Y=177957, Z=-3284},  -- player 5
        {X=29293, Y=178171, Z=-3284},  -- player 6
        {X=29446, Y=178339, Z=-3284},  -- player 7
    },
}

-- Random spawns: used for respawns after death during match
local team_spawn_random = {
    red = {
        {X=39065, Y=169528, Z=-3611},
        {X=39479, Y=169998, Z=-3611},
        {X=39822, Y=170287, Z=-3611},
        {X=40308, Y=170847, Z=-3611},
        {X=39273, Y=170194, Z=-3611},
        {X=39573, Y=170540, Z=-3611},
        {X=39956, Y=171099, Z=-3611},
        {X=37605, Y=168177, Z=-3611},
        {X=37226, Y=167816, Z=-3611},
        {X=36893, Y=167516, Z=-3611},
        {X=36421, Y=166869, Z=-3611},
        {X=36035, Y=167331, Z=-3611},
        {X=36551, Y=167805, Z=-3611},
        {X=36876, Y=168125, Z=-3611},
        {X=37247, Y=168538, Z=-3611},
        {X=37305, Y=169369, Z=-3611},
        {X=37581, Y=169607, Z=-3611},
        {X=37979, Y=170095, Z=-3611},
    },
    blue = {
        {X=28194, Y=177720, Z=-3611},
        {X=27780, Y=177250, Z=-3611},
        {X=27437, Y=176961, Z=-3611},
        {X=26951, Y=176401, Z=-3611},
        {X=27986, Y=177054, Z=-3611},
        {X=27686, Y=176708, Z=-3611},
        -- removed: 27303,176149 (against wall)
        {X=29654, Y=179071, Z=-3611},
        {X=30033, Y=179432, Z=-3611},
        {X=30366, Y=179732, Z=-3611},
        {X=30838, Y=180379, Z=-3611},
        {X=31224, Y=179917, Z=-3611},
        {X=30708, Y=179443, Z=-3611},
        {X=30383, Y=179123, Z=-3611},
        {X=30012, Y=178710, Z=-3611},
        {X=29954, Y=177879, Z=-3611},
        {X=29678, Y=177641, Z=-3611},
        {X=29280, Y=177153, Z=-3611},
    },
}

local function get_random_spawn(team)
    local spawns = team_spawn_random[team]
    if not spawns or #spawns == 0 then return {X=0, Y=0, Z=0} end
    return spawns[math.random(1, #spawns)]
end

local CLASS_DISPLAY = {
    archer = "ARCHER", assassin = "ASSASSIN", guardian = "GUARDIAN",
    berserker = "BERSERKER", fire_mage = "FIRE MAGE", air_mage = "AIR MAGE"
}

------------------------------------------------------------
-- F11: Quick team selection (walk to lodestones, no class/lobby)
------------------------------------------------------------
RegisterKeyBind(Key.F11, function()
    send_color("Team selection OPEN — walk to RED or BLUE lodestone", 1, 1, 0)
    ctf_log("=== QUICK TEAM SELECT ===")

    -- Register all players
    pcall(function()
        local all = FindAllOf("BP_PlayerCharacter_C")
        if all then
            for _, p in ipairs(all) do
                pcall(function()
                    if p and p:IsValid() then
                        local pid = p:GetInstigatorController().PlayerState.PlayerId
                        if not player_data[pid] then
                            player_data[pid] = {team=nil, class=nil, kills=0, deaths=0, specialized=false}
                        end
                    end
                end)
            end
        end
    end)

    -- Poll for team lodestone proximity
    LoopAsync(500, function()
        if not is_world_valid() then return true end
        pcall(function()
            local all = FindAllOf("BP_PlayerCharacter_C")
            if not all then return end
            for _, p in ipairs(all) do
                pcall(function()
                    if not p or not p:IsValid() then return end
                    local pid = p:GetInstigatorController().PlayerState.PlayerId
                    local pd = player_data[pid]
                    if not pd then
                        player_data[pid] = {team=nil, class=nil, kills=0, deaths=0, specialized=false}
                        pd = player_data[pid]
                    end

                    local pos = p:K2_GetActorLocation()
                    local ppos = {X=pos.X, Y=pos.Y, Z=pos.Z}

                    for _, tk in ipairs({"team_red", "team_blue"}) do
                        local spos = lodestone_positions[tk]
                        if spos and distance2d(ppos, spos) < TEAM_RADIUS then
                            local new_team = (tk == "team_red") and "red" or "blue"
                            if pd.team ~= new_team then
                                if pd.team then
                                    local old = teams[pd.team]
                                    for j = #old.players, 1, -1 do
                                        if old.players[j].id == pid then
                                            table.remove(old.players, j)
                                        end
                                    end
                                end
                                pd.team = new_team
                                table.insert(teams[new_team].players, {id=pid, ref=p})
                                teams[new_team].individual_kills[pid] = 0
                                send_color("P" .. pid .. " joined " .. new_team:upper(), teams[new_team].color.R, teams[new_team].color.G, teams[new_team].color.B)
                                ctf_log("P" .. pid .. " joined " .. new_team:upper())
                            end
                            break
                        end
                    end
                end)
            end
        end)
        return false
    end)
end)

------------------------------------------------------------
-- Numpad 8: Friendly fire prevention (must be after player_data/teams defined)
------------------------------------------------------------
RegisterKeyBind(Key.NUM_EIGHT, function()
    send_color("Friendly fire prevention ACTIVE", 0, 1, 0)
    ctf_log("=== FF ACTIVATED ===")

    pcall(function()
        RegisterHook("/Game/Gameplay/Character/Player/BP_PlayerCharacter.BP_PlayerCharacter_C:OnDamageReceivedDynamic_Event", function(self, p1, p2)
            pcall(function()
                local victim = self:get()
                if not victim or not victim:IsValid() then return end

                local dmg_event = nil
                local attacker_pid = nil
                local dmg_amount = 0
                pcall(function()
                    dmg_event = p2:get()
                    if dmg_event then
                        dmg_amount = dmg_event.Amount or 0
                        local ins = dmg_event.Instigator
                        if ins and ins:IsValid() and ins:GetFullName():find("PlayerCharacter") then
                            attacker_pid = ins:GetInstigatorController().PlayerState.PlayerId
                        end
                    end
                end)

                if not attacker_pid then return end

                local victim_pid = nil
                pcall(function() victim_pid = victim:GetInstigatorController().PlayerState.PlayerId end)

                local attacker_team = player_data[attacker_pid] and player_data[attacker_pid].team or nil
                local victim_team = player_data[victim_pid] and player_data[victim_pid].team or nil

                if attacker_team and victim_team and attacker_team == victim_team then
                    -- Read shield absorbed amount
                    local shield_absorbed = 0
                    pcall(function() shield_absorbed = dmg_event.AmountAbsorbedByShield or 0 end)

                    ExecuteInGameThread(function()
                        pcall(function()
                            -- Restore HP
                            local hp = victim.BP_Components_Health
                            if hp and hp:IsValid() then
                                local cur = hp:GetAuthoritativeHealth()
                                local restored = math.min(cur + dmg_amount, hp:GetMaxHealth())
                                hp:SetHealth(restored, "Heal")
                            end

                            -- Shield/armor restoration not possible from Lua (writes get overridden)
                        end)
                    end)
                end
            end)
        end)
        ctf_log("FF hook registered")
    end)
end)

-- SCOREBOARD UPDATE (team scores + timer + 30 per-player variables)
LoopAsync(1000, function()
    if not is_world_valid() then return true end
    local ok, err = pcall(function()
        local mod_actor = FindFirstOf("ModActor_C")
        if not mod_actor or not mod_actor:IsValid() then return end

        ExecuteInGameThread(function()
            pcall(function()
                mod_actor.RedScore = get_torch_display("red")
                mod_actor.BlueScore = get_torch_display("blue")

                -- Timer
                if game_state.timer_display then
                    mod_actor.MatchTimer = game_state.timer_display
                else
                    mod_actor.MatchTimer = "0:00"
                end

                -- Per-player stats: 6 players x 5 columns = 30 variables
                for _, team_name in ipairs({"red", "blue"}) do
                    local t = teams[team_name]
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
                            mod_actor[prefix .. slot .. "Class"]  = pd and pd.class and CLASS_DISPLAY[pd.class] or "---"
                            mod_actor[prefix .. slot .. "Kills"]  = tostring(pd and pd.kills or 0)
                            mod_actor[prefix .. slot .. "Deaths"] = tostring(pd and pd.deaths or 0)
                            mod_actor[prefix .. slot .. "Flags"]  = tostring(pd and pd.flags or 0)
                        else
                            -- Empty slot
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
    end)
    if not ok then print("[CTF] SCOREBOARD ERR: " .. tostring(err) .. "\n") end
    return false
end)

------------------------------------------------------------
-- CAPS LOCK: Toggle stats panel visibility
------------------------------------------------------------
local stats_panel_visible = false
RegisterKeyBind(Key.CAPS_LOCK, function()
    pcall(function()
        local mod_actor = FindFirstOf("ModActor_C")
        if not mod_actor or not mod_actor:IsValid() then return end
        local widget = mod_actor.ScoreboardWidget
        if not widget or not widget:IsValid() then return end

        ExecuteInGameThread(function()
            pcall(function()
                local panel = widget.StatsPanel
                if panel and panel:IsValid() then
                    stats_panel_visible = not stats_panel_visible
                    panel:SetVisibility(stats_panel_visible and 0 or 2)
                    -- 0 = Visible, 2 = Hidden
                end
            end)
        end)
    end)
end)

-- CAPE HELPER
------------------------------------------------------------
local function get_cape(team, tier)
    if tier <= 1 then return team == "red" and CAPE.RedAdv or CAPE.BlueAdv
    elseif tier == 2 then return team == "red" and CAPE.RedDyad or CAPE.BlueDyad
    elseif tier == 3 then return team == "red" and CAPE.RedHex or CAPE.BlueHex
    else return team == "red" and CAPE.Attack or CAPE.Magic end
end

------------------------------------------------------------
-- EQUIP CLASS FOR (re-equip after flag capture/death)
------------------------------------------------------------
equip_class_for = function(player_ref, team_name, class_name, a_tier, w_tier)
    local ctrl = get_controller_for(player_ref)
    if not ctrl or not ctrl:IsValid() then
        ctf_log("equip_class_for: no controller")
        return
    end

    local tier_idx = math.max(1, (a_tier or 2) - 2)
    local w_idx = math.max(1, w_tier or 0)
    local armor = CLASS_ARMOR[class_name] and CLASS_ARMOR[class_name][tier_idx] or nil
    local cape_path = get_cape(team_name, tier_idx)
    local weapons = CLASS_WEAP[class_name] and CLASS_WEAP[class_name][w_idx] or {}
    local ammo = CLASS_AMMO[class_name] or nil
    local runes = CLASS_RUNES[class_name] or nil

    ctf_log("equip_class_for: " .. team_name .. " " .. class_name .. " armor_tier=" .. tier_idx .. " weap_tier=" .. w_idx .. " weapons=" .. #weapons)

    -- Exact same pattern as equip_base_kit_for (proven working)
    ExecuteInGameThread(function()
        unlock_inv_for(ctrl)
        clear_all_for(ctrl)

        ExecuteWithDelay(500, function()
            ExecuteInGameThread(function()
                -- Armor
                if armor then
                    add_to_loadout_for(ctrl, armor.head)
                    add_to_loadout_for(ctrl, armor.body)
                    add_to_loadout_for(ctrl, armor.legs)
                end
                if cape_path then add_to_loadout_for(ctrl, cape_path) end
                -- Weapons
                for _, w in ipairs(weapons) do
                    add_item_for(ctrl, w, 1)
                end
                -- Ammo
                if ammo then add_item_for(ctrl, ammo, 50) end
                -- Runes
                if runes then
                    for _, r in ipairs(runes) do
                        add_item_for(ctrl, r[1], r[2])
                    end
                end
                -- Trinket (if player has 12+ kills)
                if player_data and player_data[ctrl.PlayerState.PlayerId] then
                    local pkills = player_data[ctrl.PlayerState.PlayerId].kills or 0
                    if pkills >= 12 and TRINKETS[class_name] then
                        add_to_loadout_for(ctrl, TRINKETS[class_name])
                    end
                end
                ctf_log("equip_class_for: done for " .. team_name .. " " .. class_name)
            end)
        end)
    end)
end

------------------------------------------------------------
-- POWERUP BUFF IMPLEMENTATION
------------------------------------------------------------
apply_powerup_buff = function(player_ref, player_id, class_name)
    if not player_ref or not player_ref:IsValid() then return end
    ctf_log("POWERUP: applying buff for " .. tostring(class_name) .. " P" .. tostring(player_id))

    if class_name == "assassin" then
        -- Invisibility: PlayDespawnVFX makes player invisible
        ExecuteInGameThread(function()
            pcall(function() player_ref:PlayDespawnVFX() end)
        end)
        send_color("INVISIBILITY ACTIVE! (45s)", 0.5, 0, 1)

    elseif class_name == "guardian" then
        -- Armor bonus: boost max HP by 50
        ExecuteInGameThread(function()
            pcall(function()
                local hp = player_ref.BP_Components_Health
                if hp and hp:IsValid() then
                    hp:ModifyMaxHealth(50)
                    hp:SetHealth(hp:GetMaxHealth(), "Heal")
                end
            end)
        end)
        send_color("ARMOR BONUS! +50 HP", 0, 1, 0.5)

    elseif class_name == "berserker" then
        -- Whetstone: upgrade weapon one tier (based on team PvP kills)
        local ctrl = get_controller_for(player_ref)
        if ctrl and ctrl:IsValid() then
            -- Determine current weapon tier from team pvp kills
            local pd = player_data and player_data[player_id] or nil
            local team = pd and pd.team or nil
            local team_pvp = team and teams[team].pvp_kills or 0
            local cur_wt = 1  -- default T3
            if team_pvp >= 36 then cur_wt = 4
            elseif team_pvp >= 24 then cur_wt = 3
            elseif team_pvp >= 12 then cur_wt = 2 end
            local w_idx = math.min(cur_wt + 1, 4)  -- upgrade one tier
            local weapons = CLASS_WEAP[class_name] and CLASS_WEAP[class_name][w_idx] or {}
            ExecuteInGameThread(function()
                pcall(function() ctrl.BP_Components_Inventory.bAllowRemoves = true end)
                pcall(function() ctrl.BP_Components_Inventory:ClearInventory() end)
                ExecuteWithDelay(500, function()
                    ExecuteInGameThread(function()
                        for _, w in ipairs(weapons) do
                            pcall(function() add_to_loadout_for(ctrl, w) end)
                        end
                    end)
                end)
            end)
        end
        send_color("WHETSTONE! Weapon upgraded!", 1, 0.5, 0)

    elseif class_name == "archer" then
        -- Poison arrows: swap ammo to higher tier (based on team PvP kills)
        local ctrl = get_controller_for(player_ref)
        if ctrl and ctrl:IsValid() then
            local pd = player_data and player_data[player_id] or nil
            local team = pd and pd.team or nil
            local team_pvp = team and teams[team].pvp_kills or 0
            local cur_wt = 1
            if team_pvp >= 36 then cur_wt = 4
            elseif team_pvp >= 24 then cur_wt = 3
            elseif team_pvp >= 12 then cur_wt = 2 end
            local w_idx = math.min(cur_wt + 1, 4)
            local ammo = ARCHER_AMMO and ARCHER_AMMO[w_idx] or nil
            if ammo then
                ExecuteInGameThread(function()
                    pcall(function() add_item_for(ctrl, ammo, 100) end)
                end)
            end
        end
        send_color("POISON ARROWS! Enhanced ammo!", 0, 1, 0)

    elseif class_name == "fire_mage" or class_name == "air_mage" then
        -- Magic potion: boost max HP by 30
        ExecuteInGameThread(function()
            pcall(function()
                local hp = player_ref.BP_Components_Health
                if hp and hp:IsValid() then
                    hp:ModifyMaxHealth(30)
                    hp:SetHealth(hp:GetMaxHealth(), "Heal")
                end
            end)
        end)
        send_color("MAGIC POTION! +30 HP", 0, 0.5, 1)
    end

    -- Green glitter VFX loop while buffed
    local buff_end = os.time() + POWERUP_BUFF_DURATION
    LoopAsync(3000, function()
        if not is_world_valid() then return true end
        if os.time() >= buff_end - 3 then return true end
        if not powerup_buffs[player_id] then return true end
        ExecuteInGameThread(function()
            pcall(function()
                if player_ref and player_ref:IsValid() then
                    player_ref:OnHealthPotionConsume()
                end
            end)
        end)
        return false
    end)
end

remove_powerup_buff = function(player_ref, player_id, class_name)
    if not player_ref or not player_ref:IsValid() then return end
    ctf_log("POWERUP: removing buff for " .. tostring(class_name) .. " P" .. tostring(player_id))

    if class_name == "assassin" then
        -- End invisibility
        ExecuteInGameThread(function()
            pcall(function() player_ref:PlayRespawnVFX() end)
        end)
        send_color("Invisibility expired!", 1, 1, 0)

    elseif class_name == "guardian" then
        -- Remove HP bonus
        ExecuteInGameThread(function()
            pcall(function()
                local hp = player_ref.BP_Components_Health
                if hp and hp:IsValid() then
                    hp:ModifyMaxHealth(-50)
                end
            end)
        end)

    elseif class_name == "fire_mage" or class_name == "air_mage" then
        -- Remove HP bonus
        ExecuteInGameThread(function()
            pcall(function()
                local hp = player_ref.BP_Components_Health
                if hp and hp:IsValid() then
                    hp:ModifyMaxHealth(-30)
                end
            end)
        end)
    end
    -- Berserker/archer: "until death" — no removal needed (reset on respawn)
end

------------------------------------------------------------
-- EQUIP FUNCTION (safe pipeline)
------------------------------------------------------------
local function equip_loadout(armor_set, weapons, ammo, cape)
    if equip_busy then return end
    equip_busy = true
    unlock_inv()

    -- Step 1: Clear on game thread
    ExecuteInGameThread(function()
        clear_all()
    end)

    -- Step 2: Add items on game thread after 500ms
    ExecuteWithDelay(500, function()
        ExecuteInGameThread(function()
            if armor_set then
                pcall(function() add_to_loadout(armor_set.head) end)
                pcall(function() add_to_loadout(armor_set.body) end)
                pcall(function() add_to_loadout(armor_set.legs) end)
            end
            if cape then pcall(function() add_to_loadout(cape) end) end
        end)

        -- Step 3: Weapons after another 200ms
        ExecuteWithDelay(200, function()
            ExecuteInGameThread(function()
                for _, w in ipairs(weapons) do add_item(w) end
                if ammo then add_item(ammo, 50) end
                equip_busy = false
            end)
        end)
    end)
end

local function equip_current_gear()
    if not selected_class or not selected_team then return end
    local a_idx = math.max(armor_tier, 1)
    local w_idx = math.max(weapon_tier, 1)
    local armor = CLASS_ARMOR[selected_class][a_idx]
    local weapons = CLASS_WEAP[selected_class][w_idx]
    local cape = get_cape(selected_team, armor_tier)

    -- Tiered ammo for archer
    local ammo = nil
    if selected_class == "archer" then
        ammo = ARCHER_AMMO[w_idx] or CLASS_AMMO.archer
    end

    -- Include trinket if earned
    local trinket = nil
    if trinket_earned then
        trinket = TRINKETS[selected_class]
    end

    if equip_busy then return end
    equip_busy = true
    unlock_inv()

    -- Step 1: Clear on game thread
    ExecuteInGameThread(function()
        clear_all()
    end)

    -- Step 2: Add armor/cape/trinket on game thread after 500ms
    ExecuteWithDelay(500, function()
        ExecuteInGameThread(function()
            pcall(function() add_to_loadout(armor.head) end)
            pcall(function() add_to_loadout(armor.body) end)
            pcall(function() add_to_loadout(armor.legs) end)
            if cape then pcall(function() add_to_loadout(cape) end) end
            if trinket then pcall(function() add_to_loadout(trinket) end) end
        end)

        -- Step 3: Weapons after another 200ms
        ExecuteWithDelay(200, function()
            ExecuteInGameThread(function()
                for _, w in ipairs(weapons) do add_item(w) end
                if ammo then
                    add_item(ammo, 50)
                    -- Auto-equip arrows only
                    local arrow_slot = #weapons
                    ExecuteWithDelay(200, function()
                        ExecuteInGameThread(function()
                            local ctrl = FindFirstOf("BP_PlayerController_C")
                            if ctrl then
                                pcall(function()
                                    ctrl.BP_Components_InventoryController:UseItemFromInventory(
                                        ctrl.BP_Components_Inventory, arrow_slot)
                                end)
                            end
                        end)
                    end)
                end
                equip_busy = false
            end)
        end)
    end)
end

------------------------------------------------------------
-- GIVE CLASS RUNES (at specialization)
------------------------------------------------------------
local function give_class_runes(silent)
    if not selected_class then return end
    unlock_inv()
    local runes = CLASS_RUNES[selected_class]
    if runes then
        ExecuteInGameThread(function()
            for _, r in ipairs(runes) do
                add_item(r[1], r[2])
            end
        end)
        if not silent then
            send_color("Runes for " .. CLASS_DISPLAY[selected_class] .. " granted!", 0, 1, 1)
        end
        runes_given = true
    end
end

------------------------------------------------------------
-- SPELL BLOCKING (Windstep)
------------------------------------------------------------
local WINDSTEP_ORIGINAL_CD = 3.0

local function block_windstep()
    pcall(function()
        local usd = StaticFindObject("/Game/Gameplay/UtilityMagic/PerkSpells/Windstep/USD_Windstep.USD_Windstep")
        if usd and usd:IsValid() then
            WINDSTEP_ORIGINAL_CD = usd.CooldownDuration or 3.0
            usd.CooldownDuration = 9999.0
            ctf_log("Windstep BLOCKED (CD=9999)\n")
            send_color("Windstep BLOCKED for match", 1, 0.5, 0)
        end
    end)
end

local function unblock_windstep()
    pcall(function()
        local usd = StaticFindObject("/Game/Gameplay/UtilityMagic/PerkSpells/Windstep/USD_Windstep.USD_Windstep")
        if usd and usd:IsValid() then
            usd.CooldownDuration = WINDSTEP_ORIGINAL_CD
            ctf_log("Windstep UNBLOCKED (CD=" .. WINDSTEP_ORIGINAL_CD .. ")\n")
        end
    end)
end

------------------------------------------------------------
-- LODESTONE SPAWNING
------------------------------------------------------------
local function spawn_lodestone(pos, label)
    local cls = StaticFindObject("/Game/Gameplay/BaseBuilding/Actors/Props/BP_BaseBuilding_Lodestone.BP_BaseBuilding_Lodestone_C")
    if not cls or not cls:IsValid() then return nil end
    local world = FindFirstOf("World")
    if not world then return nil end
    local actor = nil
    pcall(function() actor = world:SpawnActor(cls, pos, {}) end)
    if actor and actor:IsValid() then
        table.insert(spawned_lodestones, actor)
        return actor
    end
    return nil
end

local function destroy_lodestones()
    for _, s in ipairs(spawned_lodestones) do
        pcall(function() if s and s:IsValid() then s:K2_DestroyActor() end end)
    end
    spawned_lodestones = {}
end

------------------------------------------------------------
-- MOB CLASS PATHS (for direct spawning without template)
------------------------------------------------------------
local MOB_CLASSES = {
    wolf             = "/Game/Gameplay/AI/Wolf/BP_AI_Wolf_Character.BP_AI_Wolf_Character_C",
    wolf_elite       = "/Game/Gameplay/AI/Wolf/WolfEliteVariant/BP_AI_WolfElite_Character.BP_AI_WolfElite_Character_C",
    rotsworn_warrior = "/FutureMajorVersion/Gameplay/AI/SkeletonFaction/MeleeSkeleton/OneHandSwordVariant/WitheredVariant/BP_AI_RotswornWarrior_Character.BP_AI_RotswornWarrior_Character_C",
    rotsworn_marauder = "/FutureMajorVersion/Gameplay/AI/SkeletonFaction/MeleeSkeleton/TwoHandSwordVariant/WitheredVariant/BP_AI_RotswornMarauder_Character.BP_AI_RotswornMarauder_Character_C",
    rotsworn_zombie  = "/FutureMajorVersion/Gameplay/AI/ZombieFaction/RotswornZombie/BP_AI_RotswornZombie_Character.BP_AI_RotswornZombie_Character_C",
    rotsworn_necromancer = "/FutureMajorVersion/Gameplay/AI/SkeletonFaction/MagicSkeleton/BP_AI_RotswornNecromancer_Character.BP_AI_RotswornNecromancer_Character_C",
    dragon_green     = "/Game/Gameplay/AI/DragonLesser/BP_AI_DragonLesserGreen_Character.BP_AI_DragonLesserGreen_Character_C",
    hellhound_fido    = "/DowdunReach/Gameplay/AI/Wildlife/Hellhound/MiniBossVariant/BP_AI_HellHound_Minion_Fido_Character.BP_AI_HellHound_Minion_Fido_Character_C",
    hellhound_gnasher = "/DowdunReach/Gameplay/AI/Wildlife/Hellhound/MiniBossVariant/BP_AI_HellHound_Minion_Gnasher_Character.BP_AI_HellHound_Minion_Gnasher_Character_C",
    zogre             = "/FutureMajorVersion/Gameplay/AI/ZombieFaction/Zogre/BP_AI_Zogre_Character.BP_AI_Zogre_Character_C",
    zogre_dowdun      = "/DowdunReach/Gameplay/AI/FellhollowVariants/ZogreDowdun/BP_AI_Zogre_Dowdun_Character.BP_AI_Zogre_Dowdun_Character_C",
    dragon_blue       = "/DowdunReach/Gameplay/AI/Bosses/LesserBlueDragon/BP_AI_DragonLesserBlue_Character.BP_AI_DragonLesserBlue_Character_C",
    blackknight_1h    = "/DowdunReach/Gameplay/AI/BlackKnightFaction/1HMeleeBlackKnight/BP_AI_1HMeleeBlackKnight_Character.BP_AI_1HMeleeBlackKnight_Character_C",
    blackknight_2h    = "/DowdunReach/Gameplay/AI/BlackKnightFaction/2HMeleeBlackKnight/BP_AI_Melee2HBlackKnight_Character.BP_AI_Melee2HBlackKnight_Character_C",
    blackknight_ranged = "/DowdunReach/Gameplay/AI/BlackKnightFaction/RangedBlackKnight/BP_AI_BlackKnightRanged_Character.BP_AI_BlackKnightRanged_Character_C",
    zamorak_acolyte   = "/DowdunReach/Gameplay/AI/ZamorakianMageFaction/ZamorakAcolyte/BP_AI_ZamorakAcolyte_Character.BP_AI_ZamorakAcolyte_Character_C",
    mage_of_zamorak   = "/DowdunReach/Gameplay/AI/ZamorakianMageFaction/ZamorakianMage/BP_AI_MageOfZamorak_Character.BP_AI_MageOfZamorak_Character_C",
    demon_master      = "/DowdunReach/Gameplay/AI/ZamorakianMageFaction/ZamorakianMage/MiniBossVariant/DemonMaster/BP_AI_DemonMaster_Character.BP_AI_DemonMaster_Character_C",
    abyssal_demon     = "/Game/Gameplay/AI/AbyssalDemon/BP_AI_AbyssalDemon_Character.BP_AI_AbyssalDemon_Character_C",
    dragonwolf          = "/FutureMajorVersion/Gameplay/AI/Wolf/DragonWolf/BP_AI_DragonWolf_Character.BP_AI_DragonWolf_Character_C",
    spectral_dragonwolf = "/FutureMajorVersion/Gameplay/AI/Wolf/SpectralDragonWolf/BP_AI_SpectralDragonWolf_Character.BP_AI_SpectralDragonWolf_Character_C",
    skeletal_archer     = "/FutureMajorVersion/Gameplay/AI/SkeletonFaction/RangedSkeleton/BP_AI_SkeletalArcher_Character.BP_AI_SkeletalArcher_Character_C",
    skeletal_hoplite    = "/FutureMajorVersion/Gameplay/AI/SkeletonFaction/ShieldSkeleton/BP_AI_SkeletalHoplite_Character.BP_AI_SkeletalHoplite_Character_C",
    spectral_hoplite    = "/FutureMajorVersion/Gameplay/AI/SkeletonFaction/SpectralSkeletalHoplite/BP_AI_SpectralSkeletalHoplite_Character.BP_AI_SpectralSkeletalHoplite_Character_C",
    garou_berserker   = "/Game/Gameplay/AI/BeastFaction/MediumBeast/BP_AI_MediumBeast_Character.BP_AI_MediumBeast_Character_C",
    garou_druid       = "/Game/Gameplay/AI/BeastFaction/MagicBeast/BP_AI_MagicBeast_Character.BP_AI_MagicBeast_Character_C",
    garou_hunter      = "/Game/Gameplay/AI/BeastFaction/RangedBeast/BP_AI_RangedBeast_Character.BP_AI_RangedBeast_Character_C",
}

-- Cache for mob classes that need runtime loading
local cached_mob_classes = {}
local last_spawned_mob = nil  -- reference to most recently spawned mob

-- Try to cache a mob class from StaticFindObject or FindFirstOf
local function cache_mob_class(mob_key)
    if cached_mob_classes[mob_key] then return cached_mob_classes[mob_key] end

    local path = MOB_CLASSES[mob_key]
    if not path then return nil end

    -- Try StaticFindObject first
    local cls = StaticFindObject(path)
    if cls and cls:IsValid() then
        cached_mob_classes[mob_key] = cls
        return cls
    end

    -- Try FindFirstOf with the class name
    local class_name = path:match("([^/]+)$") -- BP_AI_Wolf_Character_C
    pcall(function()
        local instance = FindFirstOf(class_name)
        if instance and instance:IsValid() then
            cls = instance:GetClass()
            if cls and cls:IsValid() then
                cached_mob_classes[mob_key] = cls
            end
        end
    end)

    return cached_mob_classes[mob_key]
end

-- Get mob class: prioritize live instance (inherits HP/stats) → cache → StaticFindObject → LoadAsset
local function get_mob_class(mob_key)
    local path = MOB_CLASSES[mob_key]
    if not path then return nil end

    -- Extract class name for FindFirstOf (e.g. "BP_AI_DragonWolf_Character_C")
    local class_name = path:match("([^/%.]+)$")

    -- 1. Try FindFirstOf live instance (inherits HP/stats from natural mobs)
    pcall(function()
        local instance = FindFirstOf(class_name)
        if instance and instance:IsValid() then
            local cls = instance:GetClass()
            if cls and cls:IsValid() then
                cached_mob_classes[mob_key] = cls
            end
        end
    end)
    if cached_mob_classes[mob_key] then return cached_mob_classes[mob_key] end

    -- 2. Try StaticFindObject
    local cls = StaticFindObject(path)
    if cls and cls:IsValid() then
        cached_mob_classes[mob_key] = cls
        return cls
    end

    -- 3. Try LoadAsset as last resort (wrapped in ExecuteInGameThread for safety)
    ctf_log("get_mob_class: " .. mob_key .. " not cached, trying LoadAsset...")
    local package = path:match("(.+)%.")
    if package then
        pcall(function()
            ExecuteInGameThread(function()
                pcall(function() LoadAsset(package) end)
            end)
        end)
        -- Check again after LoadAsset (synchronous within game thread)
        local cls2 = StaticFindObject(path)
        if cls2 and cls2:IsValid() then
            cached_mob_classes[mob_key] = cls2
            ctf_log("get_mob_class: " .. mob_key .. " loaded via LoadAsset!")
            return cls2
        end
    end
    ctf_log("get_mob_class: " .. mob_key .. " not available")
    return nil
end

local function spawn_mob_direct(mob_key, pos)
    local path = MOB_CLASSES[mob_key]
    if not path then return nil end
    local cls = StaticFindObject(path)
    if not cls or not cls:IsValid() then return nil end
    local world = FindFirstOf("World")
    if not world then return nil end
    local mob = nil
    ExecuteInGameThread(function()
        pcall(function()
            mob = world:SpawnActor(cls, pos, {})
        end)
    end)
    return mob
end

------------------------------------------------------------
-- MOB SPAWNING + KILLING
------------------------------------------------------------
local function spawn_mobs_near(count, target_mob_classes, spacing)
    local pos = get_player_pos()
    if not pos then return end
    spacing = spacing or 500

    -- Find a template mob matching the target classes
    local template = nil
    local found_name = "unknown"
    for _, cls_name in ipairs(target_mob_classes) do
        pcall(function()
            local found = FindFirstOf(cls_name)
            if found and found:IsValid() then
                template = found
                found_name = cls_name
            end
        end)
        if template then break end
    end

    -- Fallback: use ANY nearby AI mob
    if not template then
        send_color("Target mob not found, trying fallback...", 1, 0.5, 0)
        local fallback_classes = {"BP_AI_RotswornWarrior_Character_C", "BP_AI_RotswornMarauder_Character_C",
                                  "BP_AI_RotswornZombie_Character_C", "BP_AI_Wolf_Character_C",
                                  "BP_AI_GiantRatWithered_Character_C", "BP_AI_DragonLesserGreen_Character_C"}
        for _, cls_name in ipairs(fallback_classes) do
            pcall(function()
                local found = FindFirstOf(cls_name)
                if found and found:IsValid() then
                    template = found
                    found_name = cls_name
                end
            end)
            if template then break end
        end
    end

    if not template then
        send_color("No mobs found nearby to clone!", 1, 0, 0)
        return
    end

    local mob_class = nil
    pcall(function() mob_class = template:GetClass() end)
    if not mob_class then return end

    local world = FindFirstOf("World")
    if not world then return end

    send_color("Spawning " .. count .. " mobs (1 every 2s)...", 1, 0.8, 0)
    local spawned = 0
    LoopAsync(1500, function()
        if not is_world_valid() then return true end
        if spawned >= count then
            send_color(count .. " mobs spawned! Press F8 to kill all.", 0, 1, 0)
            return true
        end
        ExecuteInGameThread(function()
            pcall(function()
                local sx = pos.X + 800 + (spawned % 4) * spacing
                local sy = pos.Y - 600 + math.floor(spawned / 4) * spacing
                local mob = world:SpawnActor(mob_class, {X=sx, Y=sy, Z=pos.Z}, {})
                if mob and mob:IsValid() then
                    table.insert(spawned_mobs, mob)
                end
            end)
        end)
        spawned = spawned + 1
        return false
    end)
end

local function kill_all_mobs()
    local killed = 0
    -- Kill spawned mobs on game thread
    ExecuteInGameThread(function()
        for _, mob in ipairs(spawned_mobs) do
            pcall(function()
                if mob and mob:IsValid() then
                    mob:K2_DestroyActor()
                    killed = killed + 1
                end
            end)
        end
    end)
    spawned_mobs = {}
    spawned_mobs_max_idx = 0

    -- Also kill any nearby AI
    pcall(function()
        local all_ai = FindAllOf("DominionAICharacter")
        if all_ai then
            local ppos = get_player_pos()
            for _, ai in ipairs(all_ai) do
                pcall(function()
                    if ai and ai:IsValid() then
                        local apos = ai:K2_GetActorLocation()
                        if ppos and distance2d(ppos, {X=apos.X, Y=apos.Y}) < 3000 then
                            ai:K2_DestroyActor()
                            killed = killed + 1
                        end
                    end
                end)
            end
        end
    end)

    return killed
end

------------------------------------------------------------
-- F3: Start team selection (manual trigger — replaces bed claim detection for testing)
------------------------------------------------------------
RegisterKeyBind(Key.F3, function()
    send_to_all("===== TEAM SELECTION OPEN =====", 1, 0.8, 0)
    send_to_all("Walk to the selection zone to be assigned a team!", 1, 1, 0)
    ctf_log("=== TEAM SELECTION STARTED (F3) ===")

    -- Register all connected players with no team
    local players = get_all_players()
    for _, p in ipairs(players) do
        if not player_data[p.id] then
            player_data[p.id] = {
                team = nil,
                class = nil,
                kills = 0,
                deaths = 0,
                specialized = false,
            }
        end
    end

    -- Reset teams
    teams.red.players = {}
    teams.blue.players = {}
    teams.red.captures = 0
    teams.blue.captures = 0
    torch_lead = 0

    game_state.phase = "class_select"
    lobby_active = true
    game_state.lobby_end_time = os.time() + 60
    game_state.timer_display = "60"

    -- Show scoreboard
    pcall(function()
        local ma = FindFirstOf("ModActor_C")
        if ma and ma:IsValid() then
            ma.RedScore = "0"
            ma.BlueScore = "0"
            ma.MatchTimer = "60"
            local widget = ma.ScoreboardWidget
            if widget and widget:IsValid() then
                widget:SetVisibility(0)
            end
        end
    end)

    send_to_all("60 seconds to select team + class!", 1, 1, 0)

    -- Proximity loop for team + class selection
    local class_names = {"archer", "assassin", "guardian", "berserker", "fire_mage", "air_mage"}
    local player_equip_cooldown = {}

    LoopAsync(500, function()
        if not is_world_valid() then return true end
        if game_state.phase ~= "class_select" then return true end
        local now = os.clock()
        local all_p = get_all_players()
        for _, p in ipairs(all_p) do
            local pd = player_data[p.id]
            if not pd then goto cont end
            if player_equip_cooldown[p.id] and (now - player_equip_cooldown[p.id]) < 4.0 then goto cont end

            -- TEAM selection (3 zones)
            if pd.team == nil then
                local red_count = #teams.red.players
                local blue_count = #teams.blue.players
                local new_team = nil

                local red_pos = lodestone_positions.team_red
                if red_pos and distance2d(p.pos, red_pos) < TEAM_RADIUS then
                    if red_count >= 3 then
                        send_team_msg(p.ref, "RED team is full! (3 max)", 1, 0.3, 0.3)
                    else
                        new_team = "red"
                    end
                end

                if not new_team then
                    local blue_pos = lodestone_positions.team_blue
                    if blue_pos and distance2d(p.pos, blue_pos) < TEAM_RADIUS then
                        if blue_count >= 3 then
                            send_team_msg(p.ref, "BLUE team is full! (3 max)", 1, 0.3, 0.3)
                        else
                            new_team = "blue"
                        end
                    end
                end

                if not new_team then
                    local rpos = lodestone_positions.team_random
                    if rpos and distance2d(p.pos, rpos) < TEAM_RADIUS then
                        if red_count >= 3 and blue_count >= 3 then
                            send_team_msg(p.ref, "Both teams are full!", 1, 0.3, 0.3)
                        elseif red_count < blue_count then
                            new_team = "red"
                        elseif blue_count < red_count then
                            new_team = "blue"
                        else
                            new_team = math.random(2) == 1 and "red" or "blue"
                        end
                    end
                end

                if new_team then
                    pd.team = new_team
                    table.insert(teams[new_team].players, {id=p.id, ref=p.ref})
                    teams[new_team].individual_kills[p.id] = 0
                    player_equip_cooldown[p.id] = now

                    local count = #teams[new_team].players
                    local c = teams[new_team].color
                    -- Check if random or chosen
                    local rpos = lodestone_positions.team_random
                    local was_random = rpos and distance2d(p.pos, rpos) < TEAM_RADIUS
                    if was_random then
                        send_team_msg(p.ref, ">> TEAM " .. new_team:upper() .. " randomed! (" .. count .. "/3)", c.R, c.G, c.B)
                    else
                        send_team_msg(p.ref, ">> TEAM " .. new_team:upper() .. " selected! (" .. count .. "/3)", c.R, c.G, c.B)
                    end
                    send_to_all(new_team:upper() .. " team: " .. count .. "/3", c.R, c.G, c.B)
                    ctf_log("P" .. p.id .. " joined " .. new_team:upper() .. " (" .. count .. "/3)")

                    -- Teleport to team class lobby
                    pcall(function()
                        local lobby_spawns = team_lobby_spawns[new_team]
                        if lobby_spawns and #lobby_spawns > 0 then
                            local spawn = lobby_spawns[math.random(1, #lobby_spawns)]
                            local yaw = team_spawn_yaw[new_team] or 0
                            ExecuteInGameThread(function()
                                pcall(function()
                                    p.ref:K2_SetActorLocationAndRotation(
                                        {X=spawn.X, Y=spawn.Y, Z=spawn.Z},
                                        {Pitch=0, Yaw=yaw, Roll=0},
                                        false, {}, true)
                                    snap_camera(p.ref, yaw)
                                    pcall(function() p.ref:PlayRespawnVFX() end)
                                end)
                            end)
                        end
                    end)
                end
            end

            -- CLASS selection (team-specific lodestones)
            if pd.team then
                for _, cls in ipairs(class_names) do
                    local lkey = pd.team .. "_" .. cls
                    local spos = lodestone_positions[lkey]
                    if spos and distance2d(p.pos, spos) < LOBBY_RADIUS then
                        if pd.class ~= cls then
                            pd.class = cls
                            player_equip_cooldown[p.id] = now
                            send_team_msg(p.ref, ">> Class: " .. CLASS_DISPLAY[cls], 0, 1, 0.5)
                            ctf_log("P" .. p.id .. " selected " .. cls)

                            -- Preview equip
                            pcall(function()
                                local ctrl = get_controller_for(p.ref)
                                if ctrl and ctrl:IsValid() then
                                    local cape = get_cape(pd.team, 0)
                                    ExecuteInGameThread(function()
                                        clear_all_for(ctrl)
                                        ExecuteWithDelay(500, function()
                                            ExecuteInGameThread(function()
                                                local armor = CLASS_ARMOR[cls] and CLASS_ARMOR[cls][4] or nil
                                                if armor then
                                                    add_to_loadout_for(ctrl, armor.head)
                                                    add_to_loadout_for(ctrl, armor.body)
                                                    add_to_loadout_for(ctrl, armor.legs)
                                                end
                                                if cape then add_to_loadout_for(ctrl, cape) end
                                                local weapons = CLASS_WEAP[cls] and CLASS_WEAP[cls][4] or {}
                                                for _, w in ipairs(weapons) do
                                                    add_item_for(ctrl, w, 1)
                                                end
                                                if CLASS_AMMO[cls] then
                                                    add_item_for(ctrl, CLASS_AMMO[cls], 50)
                                                end
                                            end)
                                        end)
                                    end)
                                end
                            end)
                        end
                        break
                    end
                end
            end

            ::cont::
        end
        return false
    end)

    -- Lobby countdown
    LoopAsync(1000, function()
        if not is_world_valid() then return true end
        if game_state.phase ~= "class_select" then return true end
        local remaining = math.max(0, game_state.lobby_end_time - os.time())
        game_state.timer_display = tostring(remaining)
        pcall(function()
            local ma = FindFirstOf("ModActor_C")
            if ma and ma:IsValid() then ma.MatchTimer = tostring(remaining) end
        end)

        if remaining <= 0 then
            game_state.phase = "countdown"
            lobby_active = false
            send_to_all("===== LOBBY CLOSED =====", 1, 0.8, 0)

            -- Equip base kit for all players (inline, staggered)
            send_to_all("Equipping base kit...", 1, 1, 0)
            local equip_delay = 500
            for _, team_name in ipairs({"red", "blue"}) do
                local cape_path = (team_name == "red") and CAPE.RedAdv or CAPE.BlueAdv
                for _, tp in ipairs(teams[team_name].players) do
                    local pid = tp.id
                    local cape = cape_path
                    ExecuteWithDelay(equip_delay, function()
                        ExecuteInGameThread(function()
                            pcall(function()
                                local all = FindAllOf("BP_PlayerCharacter_C")
                                if not all then return end
                                for _, pl in ipairs(all) do
                                    pcall(function()
                                        if pl and pl:IsValid() then
                                            local ppid = pl:GetInstigatorController().PlayerState.PlayerId
                                            if ppid == pid then
                                                local ctrl = pl:GetInstigatorController()
                                                if ctrl and ctrl:IsValid() then
                                                    unlock_inv_for(ctrl)
                                                    clear_all_for(ctrl)
                                                    ctf_log("Base kit: cleared P" .. pid)
                                                end
                                            end
                                        end
                                    end)
                                end
                            end)
                        end)
                        -- Add items after clear
                        ExecuteWithDelay(600, function()
                            ExecuteInGameThread(function()
                                pcall(function()
                                    local all = FindAllOf("BP_PlayerCharacter_C")
                                    if not all then return end
                                    for _, pl in ipairs(all) do
                                        pcall(function()
                                            if pl and pl:IsValid() then
                                                local ppid = pl:GetInstigatorController().PlayerState.PlayerId
                                                if ppid == pid then
                                                    local ctrl = pl:GetInstigatorController()
                                                    add_to_loadout_for(ctrl, "/Game/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T2_Head_Reinforced.ITEM_Armour_T2_Head_Reinforced")
                                                    add_to_loadout_for(ctrl, "/Game/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T2_Body_Reinforced.ITEM_Armour_T2_Body_Reinforced")
                                                    add_to_loadout_for(ctrl, "/Game/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T2_Legs_Reinforced.ITEM_Armour_T2_Legs_Reinforced")
                                                    add_to_loadout_for(ctrl, cape)
                                                    add_item_for(ctrl, BASE_WEAP.SwingSlash, 1)
                                                    add_item_for(ctrl, BASE_WEAP.AshBow, 1)
                                                    add_item_for(ctrl, BASE_WEAP.BoneArrows, 50)
                                                    ctf_log("Base kit: equipped P" .. pid)
                                                end
                                            end
                                        end)
                                    end
                                end)
                            end)
                        end)
                    end)
                    equip_delay = equip_delay + 2000
                end
            end

            -- 10 second countdown (os.time based for accuracy)
            ExecuteWithDelay(equip_delay + 2000, function()
                local countdown_start = os.time()
                local last_shown = 11
                LoopAsync(200, function()
                    if not is_world_valid() then return true end
                    local elapsed = os.time() - countdown_start
                    local remaining = 10 - elapsed
                    if remaining >= 0 and remaining < last_shown then
                        last_shown = remaining
                        send_to_all(">> " .. remaining .. " <<", 1, 0.3, 0)
                        pcall(function()
                            local ma = FindFirstOf("ModActor_C")
                            if ma and ma:IsValid() then ma.MatchTimer = tostring(remaining) end
                        end)
                    end
                    if remaining > 0 then
                        return false
                    else
                        -- === GO! ===
                        game_state.phase = "active"
                        game_state.start_time = os.time()
                        game_state.match_duration = MATCH_DURATION  -- 18 minutes
                        match_active = true

                        send_to_all("===== GO! =====", 0, 1, 0)

                        -- Spawn flags + powerups
                        ExecuteWithDelay(2000, function()
                            ExecuteInGameThread(function()
                                pcall(function() setup_flags() end)
                                pcall(function() setup_powerups() end)
                            end)
                        end)

                        -- Auto-start PvE events at 3:30 intervals
                        -- Event 1 at 3:30, Event 2 at 7:00, Event 3 at 10:30
                        local pve_event_names = {"GAROU ASSAULT", "ROTSWORN INVASION", "DARK SIEGE"}
                        for evt = 1, 3 do
                            local evt_delay = evt * 210000  -- 3:30 = 210 seconds
                            local evt_num = evt
                            local evt_name = pve_event_names[evt]
                            -- 15 second warning
                            ExecuteWithDelay(evt_delay - 15000, function()
                                if game_state.phase ~= "active" then return end
                                send_to_all(">>> PVE EVENT: " .. evt_name .. " in 15 seconds! <<<", 1, 0.5, 0)
                            end)
                            -- Start event
                            ExecuteWithDelay(evt_delay, function()
                                if game_state.phase ~= "active" then return end
                                send_to_all("===== PVE EVENT: " .. evt_name .. " =====", 1, 0.8, 0)
                                start_pve_event(evt_num)
                            end)
                        end

                        -- Teleport each team to initial spawns
                        for _, team_name in ipairs({"red", "blue"}) do
                            local tp_delay = 0
                            local spawns = team_spawn_initial[team_name]
                            local yaw = team_spawn_yaw[team_name] or 0
                            for i, tp in ipairs(teams[team_name].players) do
                                local spawn = spawns[i] or spawns[1]
                                if spawn then
                                    ExecuteWithDelay(tp_delay, function()
                                        ExecuteInGameThread(function()
                                            pcall(function()
                                                if tp.ref and tp.ref:IsValid() then
                                                    tp.ref:K2_SetActorLocationAndRotation(
                                                        {X=spawn.X, Y=spawn.Y, Z=spawn.Z},
                                                        {Pitch=0, Yaw=yaw, Roll=0},
                                                        false, {}, true)
                                                    snap_camera(tp.ref, yaw)
                                                    pcall(function() tp.ref:DissolveTeleport() end)
                                                    ExecuteWithDelay(500, function()
                                                        pcall(function() tp.ref:PlayRespawnVFX() end)
                                                    end)
                                                end
                                            end)
                                        end)
                                    end)
                                    tp_delay = tp_delay + 500
                                end
                            end
                        end

                        -- Announce classes
                        for _, team_name in ipairs({"red", "blue"}) do
                            for _, tp in ipairs(teams[team_name].players) do
                                local tpd = player_data[tp.id]
                                if tpd and tpd.class then
                                    send_team_msg(tp.ref, "Get 3 kills to specialize as " .. CLASS_DISPLAY[tpd.class] .. "!", 1, 1, 0)
                                end
                            end
                        end

                        -- Match timer
                        LoopAsync(1000, function()
                            if not is_world_valid() then return true end
                            if game_state.phase ~= "active" then return true end
                            local elapsed = os.time() - game_state.start_time
                            local rem = math.max(0, game_state.match_duration - elapsed)
                            local time_str = string.format("%d:%02d", math.floor(rem / 60), math.floor(rem % 60))
                            game_state.timer_display = time_str
                            pcall(function()
                                local ma = FindFirstOf("ModActor_C")
                                if ma and ma:IsValid() then ma.MatchTimer = time_str end
                            end)
                            if rem <= 0 then
                                game_state.phase = "ended"
                                match_active = false
                                send_to_all("===== MATCH OVER =====", 1, 1, 0)
                                local red_caps = teams.red.captures
                                local blue_caps = teams.blue.captures
                                if red_caps > blue_caps then
                                    send_to_all("===== RED TEAM WINS! =====", 1, 0.2, 0.2)
                                elseif blue_caps > red_caps then
                                    send_to_all("===== BLUE TEAM WINS! =====", 0.2, 0.4, 1)
                                else
                                    send_to_all("===== DRAW! =====", 1, 1, 0)
                                end
                                send_to_all("Final Score: RED " .. red_caps .. " - BLUE " .. blue_caps, 1, 0.8, 0)
                                cleanup_flags()
                                cleanup_powerups()
                                ExecuteWithDelay(5000, function()
                                    pcall(function()
                                        local all = FindAllOf("BP_PlayerCharacter_C")
                                        if all then
                                            local td = 0
                                            for _, pl in ipairs(all) do
                                                ExecuteWithDelay(td, function()
                                                    ExecuteInGameThread(function()
                                                        pcall(function()
                                                            if pl and pl:IsValid() then
                                                                pl:K2_SetActorLocation(
                                                                    {X=BED_LOBBY.X, Y=BED_LOBBY.Y, Z=BED_LOBBY.Z},
                                                                    false, {}, true)
                                                                pcall(function() pl:PlayRespawnVFX() end)
                                                            end
                                                        end)
                                                    end)
                                                end)
                                                td = td + 500
                                            end
                                        end
                                    end)
                                    send_to_all("Returned to lobby!", 1, 1, 0)

                                    -- Hide HUD + reset scoreboard
                                    pcall(function()
                                        local ma = FindFirstOf("ModActor_C")
                                        if ma and ma:IsValid() then
                                            ma.RedScore = "0"
                                            ma.BlueScore = "0"
                                            ma.MatchTimer = "0:00"
                                            -- Clear all player stats
                                            for _, prefix in ipairs({"Red", "Blue"}) do
                                                for slot = 1, 3 do
                                                    ma[prefix .. slot .. "Name"] = ""
                                                    ma[prefix .. slot .. "Class"] = ""
                                                    ma[prefix .. slot .. "Kills"] = ""
                                                    ma[prefix .. slot .. "Deaths"] = ""
                                                    ma[prefix .. slot .. "Flags"] = ""
                                                end
                                            end
                                            -- Hide widget
                                            local widget = ma.ScoreboardWidget
                                            if widget and widget:IsValid() then
                                                widget:SetVisibility(2)  -- Hidden
                                            end
                                        end
                                    end)

                                    -- Reset game state for next match
                                    game_state.phase = "idle"
                                    match_active = false
                                    lobby_active = false
                                end)
                                return true
                            end
                            return false
                        end)

                        -- Flag + powerup proximity loop
                        LoopAsync(500, function()
                            if not is_world_valid() then return true end
                            if game_state.phase ~= "active" then return true end
                            pcall(function()
                                local all_p = get_all_players()
                                for _, p in ipairs(all_p) do
                                    if not p.ref or not p.ref:IsValid() or not p.pos then goto np end
                                    local pd = player_data[p.id]
                                    if not pd or not pd.team then goto np end

                                    local enemy_team = pd.team == "red" and "blue" or "red"

                                    -- Flag pickup
                                    if flag_state[enemy_team].status == "at_base" and flag_state[enemy_team].carrier == nil then
                                        local fpos = FLAG_POSITIONS[enemy_team]
                                        if fpos and fpos.X ~= 0 then
                                            if distance2d(p.pos, fpos) < FLAG_PICKUP_RADIUS then
                                                flag_pickup(enemy_team, p.id, p.ref)
                                            end
                                        end
                                    end

                                    -- Flag capture
                                    for _, ft in ipairs({"red", "blue"}) do
                                        if flag_state[ft].carrier == p.id then
                                            local own_base = FLAG_POSITIONS[pd.team]
                                            if own_base and own_base.X ~= 0 then
                                                if distance2d(p.pos, own_base) < FLAG_CAPTURE_RADIUS then
                                                    pd.flags = (pd.flags or 0) + 1
                                                    flag_capture(ft, p.id, pd.team, p.ref, pd.class)
                                                end
                                            end
                                        end
                                    end

                                    -- Powerup pickup
                                    for _, spawn in ipairs(powerup_spawns) do
                                        if spawn.active and distance2d(p.pos, spawn.pos) < POWERUP_PICKUP_RADIUS then
                                            if not powerup_buffs[p.id] then
                                                spawn.active = false
                                                spawn.last_pickup = os.time()
                                                if spawn.anima_actor and spawn.anima_actor:IsValid() then
                                                    ExecuteInGameThread(function()
                                                        pcall(function() spawn.anima_actor:K2_DestroyActor() end)
                                                    end)
                                                    spawn.anima_actor = nil
                                                end
                                                local pclass = pd.class or "berserker"
                                                powerup_buffs[p.id] = {expires = os.time() + POWERUP_BUFF_DURATION, class = pclass, player_ref = p.ref}
                                                send_to_all(pd.team:upper() .. " picked up Wild Anima!", 0, 1, 0.5)
                                                apply_powerup_buff(p.ref, p.id, pclass)
                                            end
                                        end
                                    end

                                    ::np::
                                end

                                -- Respawn powerups
                                local now = os.time()
                                for _, spawn in ipairs(powerup_spawns) do
                                    if not spawn.active and (now - spawn.last_pickup) >= POWERUP_RESPAWN_TIME then
                                        spawn.active = true
                                        ExecuteInGameThread(function()
                                            spawn.anima_actor = spawn_anima(spawn.pos)
                                        end)
                                    end
                                end

                                -- Expire buffs
                                for pid, buff in pairs(powerup_buffs) do
                                    if now >= buff.expires then
                                        remove_powerup_buff(buff.player_ref, pid, buff.class)
                                        powerup_buffs[pid] = nil
                                    end
                                end
                            end)
                            return false
                        end)

                        return true  -- stop countdown loop
                    end
                end)
            end)

            return true  -- stop lobby countdown
        end

        if remaining == 30 then send_to_all("30 seconds remaining!", 1, 1, 0) end
        if remaining == 10 then send_to_all("10 seconds!", 1, 0.5, 0) end
        if remaining <= 5 and remaining > 0 then send_to_all(remaining .. "...", 1, 0.3, 0) end
        return false
    end)
end)

------------------------------------------------------------
-- F6: Start lobby (60s select → 10s countdown → teleport)
------------------------------------------------------------
RegisterKeyBind(Key.F6, function()
    if lobby_active then
        lobby_active = false
        send_color("Lobby CLOSED", 1, 0, 0)
        return
    end

    lobby_active = true
    locked = false
    match_active = false
    selected_class = nil
    selected_team = nil
    armor_tier = 0
    weapon_tier = 0
    pve_event = 0
    equip_busy = false
    ExecuteInGameThread(function()
        clear_all()
    end)

    send_color("===== LOBBY OPEN (60 seconds) =====", 0, 1, 0)
    send_color("Walk to RED or BLUE lodestone for team", 1, 1, 0)
    send_color("Stand on a CLASS lodestone to preview", 1, 1, 0)

    -- 60s lobby timer
    local lobby_time = 60

    -- Lobby countdown display
    LoopAsync(1000, function()
        if not is_world_valid() then return true end
        if not lobby_active or locked then return true end
        lobby_time = lobby_time - 1

        if lobby_time == 30 then send_color("30 seconds remaining!", 1, 1, 0) end
        if lobby_time == 10 then send_color("10 seconds remaining!", 1, 0.5, 0) end
        if lobby_time <= 5 and lobby_time > 0 then send_color(">> " .. lobby_time .. " <<", 1, 0.3, 0) end

        if lobby_time <= 0 then
            -- Auto-lock and start match countdown
            if not selected_class or not selected_team then
                send_color("No class/team selected! Lobby extended 30s.", 1, 0, 0)
                lobby_time = 30
                return false
            end

            locked = true
            lobby_active = false
            send_color("===== LOCKED: " .. string.upper(selected_team) .. " " .. CLASS_DISPLAY[selected_class] .. " =====", 1, 0.8, 0)
            send_color("Equipping base kit...", 1, 1, 0)

            -- Wait for any pending equip to finish, then equip base kit
            -- No pre-load — mannequins + base kit already cached
            ExecuteWithDelay(1500, function()
                equip_busy = false
                equip_loadout(BASE_ARMOR, {BASE_WEAP.SwingSlash, BASE_WEAP.AshBow}, BASE_WEAP.BoneArrows, get_cape(selected_team, 0))
            end)

            -- 10s match countdown (starts after 3s to let equip finish)
            local match_count = 10
            local countdown_started = false
            ExecuteWithDelay(3000, function() countdown_started = true end)
            LoopAsync(1000, function()
                if not is_world_valid() then return true end
                if not countdown_started then return false end
                if match_count > 0 then
                    if match_count <= 5 then send_color(">> " .. match_count .. " <<", 1, 0.3, 0) end
                    match_count = match_count - 1
                    return false
                else
                    match_active = true
                    -- windstep already blocked on script load
                    send_color("===== GO! =====", 0, 1, 0)

                    local spawn = team_spawns[selected_team]
                    local player = FindFirstOf("BP_PlayerCharacter_C")
                    if player and player:IsValid() and spawn then
                        player:K2_SetActorLocation(spawn, false, {}, true)
                        play_vfx()
                    end
                    send_color("Get 3 kills to specialize as " .. CLASS_DISPLAY[selected_class] .. "!", 1, 1, 0)
                    return true
                end
            end)
            return true
        end
        return false
    end)

    -- Proximity polling
    LoopAsync(500, function()
        if not is_world_valid() then return true end
        if not lobby_active or locked or equip_busy then return not lobby_active end

        local ppos = get_player_pos()
        if not ppos then return false end
        local now = os.clock()

        -- Team lodestones (3s cooldown)
        if not equip_busy and (now - (last_equip_time or 0)) > 3.5 then
            for _, tk in ipairs({"team_red", "team_blue"}) do
                local spos = lodestone_positions[tk]
                if spos and distance2d(ppos, spos) < TEAM_RADIUS then
                    local nt = tk == "team_red" and "red" or "blue"
                    if selected_team ~= nt then
                        last_equip_time = now
                        selected_team = nt
                        if nt == "red" then send_color(">> TEAM RED", 1, 0.3, 0.3)
                        else send_color(">> TEAM BLUE", 0.3, 0.5, 1) end
                        local cape = get_cape(nt, 0)
                        if selected_class then
                            last_equip_time = now
                            equip_loadout(CLASS_ARMOR[selected_class][4], CLASS_WEAP[selected_class][4],
                                CLASS_AMMO[selected_class], cape)
                        else
                            -- Cape swap: remove old cape (slot 3), then add new
                            ExecuteInGameThread(function()
                                pcall(function()
                                    local c = FindFirstOf("BP_PlayerController_C")
                                    if c then
                                        c.BP_Components_Loadout:RemoveFromSlot(3, 1, c)
                                    end
                                end)
                            end)
                            ExecuteWithDelay(300, function()
                                ExecuteInGameThread(function()
                                    pcall(function() add_to_loadout(cape) end)
                                end)
                            end)
                        end
                        break  -- only process one team per poll cycle
                    end
                end
            end
        end

        -- Class lodestones (3s cooldown, break after first match)
        -- debug_mode: 1=armor only, 2=weapons only, 3=cape only, 0=all (normal)
        if not equip_busy and (now - (last_equip_time or 0)) > 3.5 then
            for _, cls in ipairs({"archer","assassin","guardian","berserker","fire_mage","air_mage"}) do
                local spos = lodestone_positions[cls]
                if spos and distance2d(ppos, spos) < LOBBY_RADIUS then
                    if selected_class ~= cls then
                        last_equip_time = now
                        selected_class = cls
                        local team = selected_team
                        local cape = team and get_cape(team, 0) or nil

                        local mode_names = {[0]="ALL", [1]="ARMOR", [2]="WEAPONS", [3]="CAPE", [4]="ARMOR+CAPE", [5]="ARMOR+WEAPONS", [6]="CAPE+WEAPONS"}
                        send_color(">> " .. CLASS_DISPLAY[cls] .. " [" .. mode_names[debug_equip_mode] .. "]", 0, 1, 0.5)

                        local do_armor = debug_equip_mode == 0 or debug_equip_mode == 1 or debug_equip_mode == 4 or debug_equip_mode == 5
                        local do_weapons = debug_equip_mode == 0 or debug_equip_mode == 2 or debug_equip_mode == 5 or debug_equip_mode == 6
                        local do_cape = debug_equip_mode == 0 or debug_equip_mode == 3 or debug_equip_mode == 4 or debug_equip_mode == 6

                        local armor = do_armor and CLASS_ARMOR[cls][4] or nil
                        local weapons = do_weapons and CLASS_WEAP[cls][4] or {}
                        local ammo = do_weapons and CLASS_AMMO[cls] or nil
                        local eq_cape = do_cape and cape or nil

                        if do_armor then
                            -- Use full equip pipeline
                            equip_loadout(armor, weapons, ammo, eq_cape)
                        elseif do_weapons then
                            -- Weapons only (no loadout touch)
                            unlock_inv()
                            local c = FindFirstOf("BP_PlayerController_C")
                            if c then pcall(function() c.BP_Components_Inventory:ClearInventory() end) end
                            ExecuteWithDelay(200, function()
                                for _, w in ipairs(weapons) do add_item(w) end
                                if ammo then add_item(ammo, 50) end
                                if do_cape then pcall(function() add_to_loadout(eq_cape) end) end
                            end)
                        elseif do_cape then
                            -- Cape only
                            pcall(function() add_to_loadout(cape) end)
                        end
                        play_vfx()
                        break
                    end
                end
            end
        end

        return false
    end)
end)

------------------------------------------------------------
-- NEW PVE EVENT SYSTEM (role-based, multiplayer)
------------------------------------------------------------
local PVE_EVENT_DEFS = {
    [1] = {
        name = "GAROU ASSAULT",
        power_level = 4,
        roles = {
            {role="wolf",   mob_key="wolf",            count=10, respawn=5000},
            {role="archer", mob_key="garou_hunter",     count=4,  respawn=10000},
            {role="mage",   mob_key="garou_druid",      count=4,  respawn=10000},
            {role="tank",   mob_key="garou_berserker",  count=2,  respawn=20000},
            {role="boss",   mob_key="abyssal_demon",    count=1,  respawn=30000},
        },
        initial_delays = {0, 4000, 8000, 12000, 16000},  -- stagger per role group
        reward_tier = 4,  -- T4 armor
    },
    [2] = {
        name = "ROTSWORN INVASION",
        power_level = 5,
        roles = {
            {role="wolf",   mob_key="dragonwolf",           count=10, respawn=5000},
            {role="archer", mob_key="skeletal_archer",      count=4,  respawn=10000},
            {role="mage",   mob_key="rotsworn_necromancer", count=4,  respawn=10000},
            {role="tank",   mob_key="rotsworn_marauder",    count=2,  respawn=20000},
            {role="boss",   mob_key="zogre",                count=1,  respawn=30000},
        },
        initial_delays = {0, 4000, 8000, 12000, 16000},
        reward_tier = 5,
    },
    [3] = {
        name = "DARK SIEGE",
        power_level = 6,
        roles = {
            {role="wolf",   mob_key="hellhound_fido",      count=10, respawn=5000},
            {role="archer", mob_key="blackknight_ranged",  count=4,  respawn=10000},
            {role="mage",   mob_key="mage_of_zamorak",    count=4,  respawn=10000},
            {role="tank",   mob_key="blackknight_2h",      count=2,  respawn=20000},
            {role="boss",   mob_key="dragon_blue",         count=1,  respawn=30000},
        },
        initial_delays = {0, 4000, 8000, 12000, 16000},
        reward_tier = 6,
    },
}

local pve_active_mobs = {}   -- tracked spawned mobs {ref=, role=, mob_key=}
local pve_respawn_timers = {} -- active respawn loops
local current_pve_event = nil

-- PvE spawn areas per team (rectangle perimeters)
-- Mobs spawn at random positions within each team's rectangle
local PVE_SPAWN_AREAS = {
    red = {
        min_x = 33025, max_x = 37381,
        min_y = 169897, max_y = 174228,
        z = -3900,
    },
    blue = {
        min_x = 29862, max_x = 34181,
        min_y = 173055, max_y = 177388,
        z = -3900,
    },
}

-- Fixed spawn points per role per team (no stacking, tactical layout)
-- Boss=center, Archers=back, Mages=mid, Tanks=front, Wolves=edges
local PVE_SPAWN_POINTS = {
    red = {
        boss   = {{X=35203, Y=172063, Z=-3900}},
        tank   = {
            {X=34416, Y=169007, Z=-3386},   -- right alley (flag end)
            {X=38151, Y=172933, Z=-3386},   -- left alley (flag end)
        },
        archer = {
            {X=32607, Y=170809, Z=-3386},   -- right alley (arena end)
            {X=36427, Y=174630, Z=-3386},   -- left alley (arena end)
            {X=35910, Y=172770, Z=-3900},   -- middle (perp right of boss, 1000u)
            {X=34496, Y=171356, Z=-3900},   -- middle (perp left of boss, 1000u)
        },
        mage   = {
            {X=33511, Y=169908, Z=-3386},   -- right alley (center)
            {X=37289, Y=173781, Z=-3386},   -- left alley (center)
            {X=35627, Y=172487, Z=-3900},   -- middle (perp right of boss, 600u)
            {X=34778, Y=171638, Z=-3900},   -- middle (perp left of boss, 600u)
        },
        wolf   = {
            -- Evenly spaced around perimeter
            {X=33459, Y=172370, Z=-3900}, {X=34328, Y=173238, Z=-3900}, {X=35198, Y=174106, Z=-3900},
            {X=36066, Y=173480, Z=-3900}, {X=36934, Y=172611, Z=-3900}, {X=36956, Y=171745, Z=-3900},
            {X=36082, Y=170881, Z=-3900}, {X=35208, Y=170018, Z=-3900}, {X=34335, Y=170639, Z=-3900},
            {X=33461, Y=171503, Z=-3900},
        },
    },
    blue = {
        boss   = {{X=32056, Y=175185, Z=-3900}},
        tank   = {
            {X=34637, Y=176436, Z=-3386},   -- right alley (flag end)
            {X=29110, Y=174323, Z=-3386},   -- left alley (flag end)
        },
        archer = {
            {X=32930, Y=178136, Z=-3386},   -- right alley (arena end)
            {X=30796, Y=172641, Z=-3386},   -- left alley (arena end)
            {X=32763, Y=175892, Z=-3900},   -- middle (perp right of boss, 1000u)
            {X=31349, Y=174478, Z=-3900},   -- middle (perp left of boss, 1000u)
        },
        mage   = {
            {X=33783, Y=177286, Z=-3386},   -- right alley (center)
            {X=29970, Y=173482, Z=-3386},   -- left alley (center)
            {X=32480, Y=175609, Z=-3900},   -- middle (perp right of boss, 600u)
            {X=31631, Y=174760, Z=-3900},   -- middle (perp left of boss, 600u)
        },
        wolf   = {
            -- Evenly spaced around perimeter
            {X=33800, Y=174878, Z=-3900}, {X=32931, Y=174010, Z=-3900}, {X=32061, Y=173142, Z=-3900},
            {X=31193, Y=173768, Z=-3900}, {X=30325, Y=174637, Z=-3900}, {X=30303, Y=175503, Z=-3900},
            {X=31177, Y=176367, Z=-3900}, {X=32051, Y=177230, Z=-3900}, {X=32924, Y=176609, Z=-3900},
            {X=33798, Y=175745, Z=-3900},
        },
    },
}

-- Counters for cycling through fixed points (reset per event)
local pve_spawn_counters = {}

local function get_pve_spawn_pos(team, role)
    local points = PVE_SPAWN_POINTS[team or "red"]
    if not points or not points[role] then
        return {X=35203, Y=172063, Z=-3900}  -- fallback to red center
    end

    local key = (team or "red") .. "_" .. (role or "wolf")
    pve_spawn_counters[key] = (pve_spawn_counters[key] or 0) + 1
    local idx = ((pve_spawn_counters[key] - 1) % #points[role]) + 1

    return points[role][idx]
end

local function spawn_pve_mob(mob_key, power_level, role, team)
    local cls = get_mob_class(mob_key)
    if not cls then
        ctf_log("PvE spawn failed: " .. mob_key .. " not available")
        return nil
    end

    local pos = get_pve_spawn_pos(team, role)
    -- Boss mobs need Z offset
    if BOSS_MOBS[mob_key] then pos.Z = pos.Z + 200 end  -- offset to avoid ground clip

    local spawned_mob = nil
    ExecuteInGameThread(function()
        pcall(function()
            local world = FindFirstOf("World")
            if world then
                -- Mobs face towards their team's flag
                local mob_yaw = (team == "red") and -45 or 135
                local mob = world:SpawnActor(cls, pos, {})
                if mob and mob:IsValid() then
                    mob.PowerLevel = power_level
                    pcall(function() mob:K2_SetActorRotation({Pitch=0, Yaw=mob_yaw, Roll=0}, false) end)
                    spawned_mob = mob
                    table.insert(pve_active_mobs, {ref=mob, role=role, mob_key=mob_key})
                    table.insert(spawned_mobs, mob)
                end
            end
        end)
    end)
    return spawned_mob
end

local function count_alive_by_role(role)
    local count = 0
    for i = #pve_active_mobs, 1, -1 do
        local m = pve_active_mobs[i]
        local alive = false
        pcall(function() alive = m.ref and m.ref:IsValid() and not m.ref.HealthComponent:IsDead() end)
        if alive and m.role == role then
            count = count + 1
        elseif not alive then
            table.remove(pve_active_mobs, i)
        end
    end
    return count
end

function start_pve_event(event_num)
    local event = PVE_EVENT_DEFS[event_num]
    if not event then
        ctf_log("Invalid PvE event: " .. tostring(event_num))
        return
    end

    current_pve_event = event_num
    game_state.pve_event = event_num
    pve_spawn_counters = {}  -- reset spawn point cycling
    ctf_log("=== PVE EVENT " .. event_num .. ": " .. event.name .. " (PL" .. event.power_level .. ") ===")
    send_to_all("===== PVE EVENT: " .. event.name .. " =====", 1, 0.8, 0)
    send_to_all("Kill targets: wolf:10 archer:4 mage:4 tank:2 boss:1", 1, 1, 0)

    -- Initial spawn — interleaved (red+blue alternate per mob to spread load evenly)
    local spawn_delay = 0
    for role_idx, role_def in ipairs(event.roles) do
        local base_delay = event.initial_delays[role_idx] or 0
        for i = 1, role_def.count do
            for _, tname in ipairs({"red", "blue"}) do
                local d = base_delay + spawn_delay
                local team = tname
                local mk = role_def.mob_key
                local pl = event.power_level
                local rl = role_def.role
                ExecuteWithDelay(d, function()
                    spawn_pve_mob(mk, pl, rl, team)
                end)
                spawn_delay = spawn_delay + 250
            end
        end
        ctf_log("Queued " .. role_def.count .. "x " .. role_def.mob_key .. " (" .. role_def.role .. ") for BOTH teams")
    end

    -- Per-team respawn: mob stops spawning on a team's side when THAT team kills it
    -- Delay start by 15s to let initial spawn complete
    local respawn_start_time = os.clock() + 15
    local last_respawn_time = {}
    for _, role_def in ipairs(event.roles) do
        for _, tn in ipairs({"red", "blue"}) do
            last_respawn_time[tn .. "_" .. role_def.role] = os.clock() + 15
        end
    end

    LoopAsync(3000, function()
        if not is_world_valid() then return true end
        if os.clock() < respawn_start_time then return false end  -- wait for initial spawn
        if game_state.phase ~= "active" then return true end
        -- Stop this event's respawn when both teams have completed it
        local red_done = teams.red.armor_tier >= (event_num + 3)
        local blue_done = teams.blue.armor_tier >= (event_num + 3)
        if red_done and blue_done then return true end

        local now = os.clock()
        for _, team_name in ipairs({"red", "blue"}) do
            local t = teams[team_name]
            for _, role_def in ipairs(event.roles) do
                local role = role_def.role
                local req = PVE_KILL_REQ[role] or role_def.count
                local team_kills_for_role = t.pve_kills[role] or 0

                -- Only respawn if:
                -- 1. Team hasn't met kill quota for this role
                -- 2. Alive count for this role is below target (prevents stacking)
                if team_kills_for_role < req then
                    local alive = count_alive_by_role(role)
                    -- Both teams: max alive = count * 2 (10 per side = 20 total)
                    -- But don't respawn during initial spawn (wait for first death)
                    if alive < role_def.count * 2 then
                        local key = team_name .. "_" .. role
                        local elapsed = (now - (last_respawn_time[key] or 0)) * 1000
                        if elapsed >= role_def.respawn then
                            spawn_pve_mob(role_def.mob_key, event.power_level, role, team_name)
                            last_respawn_time[key] = now
                            ctf_log("Respawn: " .. role_def.mob_key .. " for " .. team_name:upper() .. " (kills:" .. team_kills_for_role .. "/" .. req .. " alive:" .. alive .. "/" .. role_def.count .. ")")
                        end
                    end
                end
            end
        end
        return false
    end)
end

------------------------------------------------------------
-- OLD PVE EVENT SYSTEM (F7 — kept for backward compat)
------------------------------------------------------------
local PVE_EVENTS = {
    {name = "DRAGON WOLVES", initial_count = 16, kill_threshold = 10, tier_name = "T4",
     mob_classes = {"BP_AI_Wolf_Character_C", "BP_AI_WolfElite_Character_C"},
     auto_spawn_after = 12, respawn_interval = 20000},  -- 20s respawn
    {name = "ROTSWORN WARRIORS", initial_count = 16, kill_threshold = 10, tier_name = "T5",
     mob_classes = {"BP_AI_RotswornWarrior_Character_C", "BP_AI_RotswornMarauder_Character_C", "BP_AI_RotswornZombie_Character_C"},
     auto_spawn_after = 12, respawn_interval = 20000},
    {name = "DRAGON", initial_count = 3, kill_threshold = 3, tier_name = "T6",
     mob_classes = {"BP_AI_DragonLesserGreen_Character_C"},
     auto_spawn_after = 3, respawn_interval = 30000},  -- 30s respawn for dragons
}

local pve_kills = {red = 0, blue = 0}  -- per-team kill count
local pve_total_killed = 0              -- total killed from initial pool
local pve_event_active = false
local pve_auto_spawning = false
local pve_current_event = nil
local pve_mob_class_ref = nil           -- cached mob class for respawning
local pve_spawn_pos = nil               -- cached spawn position
local spawned_mobs_max_idx = 0          -- highest index in spawned_mobs
local pve_last_dead_count = 0           -- last polled dead count (to detect new deaths)

local function check_pve_completion_old()
    if not pve_current_event then return end
    local event = pve_current_event
    local my_team = selected_team or "red"

    -- Check if player's team reached threshold
    if pve_kills[my_team] >= event.kill_threshold then
        -- Team completed!
        pve_event_active = false
        pve_auto_spawning = false
        pve_event = pve_event + 1
        armor_tier = pve_event + 1  -- 2=T4, 3=T5, 4=T6

        send_color("===== " .. event.name .. " COMPLETE! =====", 0, 1, 0)
        send_color("Armor upgraded to " .. event.tier_name .. "! (" .. pve_kills[my_team] .. " kills)", 0, 1, 1)

        -- First PvE event also triggers specialization if not yet specialized
        if pve_event == 1 and weapon_tier == 0 then
            weapon_tier = 1
            individual_kills = math.max(individual_kills, 3)
            send_color(">> AUTO-PROMOTED via PvE!", 1, 0.8, 0)
        end

        -- Upgrade armor
        equip_current_gear()
        ExecuteWithDelay(1000, function() give_class_runes(runes_given) end)
        play_vfx()

        -- Clean up remaining mobs
        ExecuteWithDelay(2000, function()
            kill_all_mobs()
        end)

        pve_current_event = nil
    end
end

local pve_death_hook_registered = false

local function start_pve_kill_tracking()
    -- Hook BP_OnDeath for instant kill detection
    if not pve_death_hook_registered then
        pcall(function()
            RegisterHook("/Game/Gameplay/AI/BP_DominionAICharacter.BP_DominionAICharacter_C:BP_OnDeath", function(self)
                -- Extract killer from LastDamageEvent before properties are cleared
                pcall(function()
                    local mob = self:get()
                    if not mob or not mob:IsValid() then return end
                    local dmg = mob.BP_AiDamageComponent
                    if not dmg or not dmg:IsValid() then return end

                    local lde_mob_addr = tostring(mob:GetAddress())
                    local lde = dmg.LastDamageEvent
                    if not lde then return end
                    local ins = lde.Instigator
                    if not ins then return end
                    local valid = false
                    pcall(function() valid = ins:IsValid() end)
                    if not valid then return end

                    pcall(function()
                        local ctrl = ins:GetInstigatorController()
                        if ctrl and ctrl:IsValid() then
                            local pid = ctrl.PlayerState.PlayerId
                            if pid then
                                _G.mob_fatal_attacker = {mob_addr = lde_mob_addr, pid = pid}
                                _G.mob_last_attacker[lde_mob_addr] = pid
                                ctf_log("KILL BY: P" .. pid)
                            end
                        end
                    end)
                end)
                pcall(function()
                    if #teams.red.players == 0 and #teams.blue.players == 0 then
                        ctf_log("No teams assigned, skipping kill tracking")
                        return
                    end

                    local mob = self:get()
                    if not mob or not mob:IsValid() then
                        ctf_log("Mob invalid in death hook")
                        return
                    end

                    -- Determine mob role from class name
                    local mob_class = ""
                    pcall(function() mob_class = mob:GetClass():GetFullName() end)

                    local role = "wolf"
                    local mob_display = "Wolf"
                    local is_summon = false
                    if mob_class:find("Archer") or (mob_class:find("Ranged") and not mob_class:find("BlackKnight")) then
                        role = "archer"
                        if mob_class:find("Skeletal") then mob_display = "Skeletal Archer"
                        elseif mob_class:find("RangedBeast") then mob_display = "Garou Hunter"
                        elseif mob_class:find("BlackKnight") then mob_display = "Black Knight"
                        else mob_display = "Archer" end
                    elseif mob_class:find("Necromancer") or mob_class:find("MagicBeast") or mob_class:find("Zamorak") then
                        role = "mage"
                        if mob_class:find("Necromancer") then mob_display = "Necromancer"
                        elseif mob_class:find("MagicBeast") then mob_display = "Garou Druid"
                        elseif mob_class:find("Zamorak") then mob_display = "Mage of Zamorak"
                        else mob_display = "Mage" end
                    elseif mob_class:find("Marauder") or mob_class:find("MediumBeast") or mob_class:find("BlackKnight") or mob_class:find("Hoplite") then
                        role = "tank"
                        if mob_class:find("Marauder") then mob_display = "Rotsworn Marauder"
                        elseif mob_class:find("MediumBeast") then mob_display = "Garou Berserker"
                        elseif mob_class:find("2H") then mob_display = "Black Knight"
                        else mob_display = "Tank" end
                    elseif mob_class:find("Zogre") or mob_class:find("Abyssal") or mob_class:find("Dragon") then
                        role = "boss"
                        if mob_class:find("Zogre") then mob_display = "Zogre"
                        elseif mob_class:find("Abyssal") then mob_display = "Abyssal Demon"
                        elseif mob_class:find("Blue") then mob_display = "Blue Dragon"
                        elseif mob_class:find("Green") then mob_display = "Green Dragon"
                        else mob_display = "Boss" end
                    elseif mob_class:find("RotswornWarrior") or mob_class:find("RotswornZombie") then
                        -- Summoned mobs (spawned by Necromancer) — don't count towards PvE
                        is_summon = true
                        mob_display = "Rotsworn Warrior"
                    else
                        if mob_class:find("DragonWolf") then mob_display = "Dragonwolf"
                        elseif mob_class:find("HellHound") then mob_display = "Hellhound"
                        end
                    end

                    -- Skip summoned mobs (don't count towards PvE kills)
                    if is_summon then return end

                    -- Find killer: check fatal hit > damage tracker > proximity
                    local mob_addr = tostring(mob:GetAddress())
                    local nearest_team = nil
                    local nearest_id = nil
                    local nearest_ref = nil

                    -- 1. Check fatal hit tracker (exact killing blow)
                    if _G.mob_fatal_attacker and _G.mob_fatal_attacker.mob_addr == mob_addr then
                        nearest_id = _G.mob_fatal_attacker.pid
                        nearest_team = get_player_team(nearest_id)
                        pcall(function()
                            local players = get_all_players()
                            for _, p in ipairs(players) do
                                if p.id == nearest_id then nearest_ref = p.ref break end
                            end
                        end)
                        _G.mob_fatal_attacker = nil
                        ctf_log("Kill attributed via FATAL HIT: P" .. nearest_id)
                    end

                    -- 2. Check damage tracker (last player to damage this mob)
                    if not nearest_team and _G.mob_last_attacker and _G.mob_last_attacker[mob_addr] then
                        nearest_id = _G.mob_last_attacker[mob_addr]
                        nearest_team = get_player_team(nearest_id)
                        pcall(function()
                            local players = get_all_players()
                            for _, p in ipairs(players) do
                                if p.id == nearest_id then nearest_ref = p.ref break end
                            end
                        end)
                        _G.mob_last_attacker[mob_addr] = nil
                        ctf_log("Kill attributed via damage tracker: P" .. nearest_id)
                    end

                    -- 3. Fallback to proximity
                    if not nearest_team then
                        local mob_pos = nil
                        pcall(function()
                            local mp = mob:K2_GetActorLocation()
                            mob_pos = {X=mp.X, Y=mp.Y, Z=mp.Z}
                        end)
                        if mob_pos then
                            local nearest_dist = 999999
                            local players = get_all_players()
                            for _, p in ipairs(players) do
                                local d = distance2d(mob_pos, p.pos)
                                if d < nearest_dist then
                                    nearest_dist = d
                                    nearest_id = p.id
                                    nearest_team = get_player_team(p.id)
                                    nearest_ref = p.ref
                                end
                            end
                            ctf_log("Kill attributed via proximity (fallback): P" .. tostring(nearest_id))
                        end
                    end

                    -- Auto-assign to red if player has no team (testing convenience)
                    if nearest_id and not nearest_team then
                        if player_data[nearest_id] then
                            player_data[nearest_id].team = "red"
                        else
                            player_data[nearest_id] = {team="red", class=nil, kills=0, deaths=0, specialized=false}
                        end
                        table.insert(teams.red.players, {id=nearest_id, ref=nearest_ref})
                        teams.red.individual_kills[nearest_id] = 0
                        nearest_team = "red"
                        ctf_log("Auto-assigned P" .. nearest_id .. " to RED (no team set)")
                    end

                    if nearest_team then
                        local t = teams[nearest_team]
                        local req = PVE_KILL_REQ[role]
                        local cur = t.pve_kills[role] or 0

                        -- Skip if this team is already at max tier (T6)
                        if t.armor_tier >= 6 then return end

                        -- Only count PvE role kills if not already capped
                        if cur < req then
                            t.pve_kills[role] = cur + 1
                            cur = cur + 1

                            ctf_log(nearest_team:upper() .. " kill: " .. mob_display .. " [" .. role .. "] (" .. cur .. "/" .. req .. ") by P" .. nearest_id)

                            -- Notify the killer
                            if nearest_ref then
                                if cur == req then
                                    send_team_msg(nearest_ref, mob_display .. " COMPLETE! (" .. cur .. "/" .. req .. ")", 0, 1, 0)
                                else
                                    send_team_msg(nearest_ref, mob_display .. " killed! (" .. cur .. "/" .. req .. ")",
                                        t.color.R, t.color.G, t.color.B)
                                end
                            end
                        end

                        -- Check if team completed all PvE requirements
                        -- PvE rewards: Event1→T4, Event2→T5, Event3→T6
                        -- armor_tier: 2=base, 4=after E1, 5=after E2, 6=after E3
                        local new_tier
                        if t.armor_tier <= 3 then new_tier = 4      -- Event 1 → T4
                        elseif t.armor_tier == 4 then new_tier = 5  -- Event 2 → T5
                        elseif t.armor_tier == 5 then new_tier = 6  -- Event 3 → T6
                        else new_tier = t.armor_tier end
                        local event_num = new_tier - 3
                        if new_tier > t.armor_tier and check_pve_completion(nearest_team) then
                            t.armor_tier = new_tier

                            send_to_all(nearest_team:upper() .. " TEAM completed PvE! Armor upgrade to T" .. new_tier .. "!", 1, 1, 0)
                            ctf_log(nearest_team:upper() .. " completed PvE event " .. event_num .. "! New tier: T" .. new_tier)

                            -- Reset kill counters for next event
                            t.pve_kills = {wolf=0, archer=0, mage=0, tank=0, boss=0}

                            -- Equip new armor for all team members (staggered)
                            local equip_delay = 0
                            for _, tp in ipairs(t.players) do
                                ExecuteWithDelay(equip_delay, function()
                                    pcall(function()
                                        local pd = player_data[tp.id]
                                        if not pd or not tp.ref or not tp.ref:IsValid() then return end

                                        -- Auto-promote unspecialized players
                                        if not pd.specialized and pd.class then
                                            pd.specialized = true
                                            send_team_msg(tp.ref, ">> AUTO-PROMOTED via PvE! Specialized as " .. CLASS_DISPLAY[pd.class], 1, 0.8, 0)
                                            ctf_log("Auto-promoted P" .. tp.id .. " as " .. pd.class)
                                        end

                                        if pd.class then
                                            local ctrl = get_controller_for(tp.ref)
                                            if ctrl and ctrl:IsValid() then
                                                local tier_idx = new_tier - 2  -- T3=1, T4=2, T5=3, T6=4
                                                local armor = CLASS_ARMOR[pd.class] and CLASS_ARMOR[pd.class][tier_idx] or nil
                                                local cape = get_cape(nearest_team, tier_idx)
                                                if armor then
                                                    ExecuteInGameThread(function()
                                                        unlock_inv_for(ctrl)
                                                        pcall(function() ctrl.BP_Components_Inventory:ClearInventory() end)
                                                        pcall(function() ctrl.BP_Components_Loadout:ClearInventory() end)
                                                        ExecuteWithDelay(500, function()
                                                            ExecuteInGameThread(function()
                                                                add_to_loadout_for(ctrl, armor.head)
                                                                add_to_loadout_for(ctrl, armor.body)
                                                                add_to_loadout_for(ctrl, armor.legs)
                                                                if cape then add_to_loadout_for(ctrl, cape) end
                                                                -- Re-add weapons (cleared with loadout)
                                                                local weap_idx = math.min(tier_idx, 4)
                                                                local weapons = CLASS_WEAP[pd.class] and CLASS_WEAP[pd.class][weap_idx] or {}
                                                                for _, w in ipairs(weapons) do
                                                                    add_item_for(ctrl, w, 1)
                                                                end
                                                                if CLASS_AMMO[pd.class] then
                                                                    add_item_for(ctrl, CLASS_AMMO[pd.class], 50)
                                                                end
                                                                -- Runes if first time specializing
                                                                local runes = CLASS_RUNES[pd.class]
                                                                if runes then
                                                                    for _, r in ipairs(runes) do
                                                                        add_item_for(ctrl, r[1], r[2])
                                                                    end
                                                                end
                                                                -- Re-add trinket if earned (12+ personal kills)
                                                                if pd.kills >= 12 and TRINKETS[pd.class] then
                                                                    add_to_loadout_for(ctrl, TRINKETS[pd.class])
                                                                end
                                                                ctf_log("Upgraded " .. nearest_team .. " P" .. tp.id .. " to T" .. new_tier)
                                                            end)
                                                        end)
                                                    end)
                                                end
                                            end
                                        end
                                    end)
                                end)
                                equip_delay = equip_delay + 1500
                            end

                            -- Reset PvE kills for next event
                            t.pve_kills = {wolf=0, archer=0, mage=0, tank=0, boss=0}

                            -- Check if BOTH teams completed — if so, just announce (don't kill mobs, next event may have spawned)
                            local both_done = true
                            for _, tn in ipairs({"red", "blue"}) do
                                if #teams[tn].players > 0 and teams[tn].armor_tier < new_tier then
                                    both_done = false
                                end
                            end
                            if both_done then
                                send_to_all("PvE Event " .. event_num .. " complete for both teams!", 1, 1, 0)
                                ctf_log("Both teams completed PvE event " .. event_num)
                                -- Don't kill mobs or clear pve_event — next event may already be running
                            end
                        end
                        -- (skip_pve_tracking label removed — using return instead)
                    end
                end)

                -- === OLD PVE EVENT TRACKING (F7 system) ===
                if not pve_event_active then return end
                local my_team = selected_team or "red"
                pve_kills[my_team] = pve_kills[my_team] + 1
                pve_total_killed = pve_total_killed + 1
                send_color("Kills: " .. pve_kills[my_team] .. "/" .. pve_current_event.kill_threshold, 1, 0.5, 0)

                -- Auto-spawner
                if not pve_auto_spawning and pve_total_killed >= pve_current_event.auto_spawn_after then
                    pve_auto_spawning = true
                    send_color("Auto-spawner activated!", 1, 0.8, 0)
                    LoopAsync(pve_current_event.respawn_interval, function()
                        if not is_world_valid() then return true end
                        if not pve_event_active then return true end
                        ExecuteInGameThread(function()
                            if pve_mob_class_ref and pve_spawn_pos then
                                local world = FindFirstOf("World")
                                if world then
                                    pcall(function()
                                        local sx = pve_spawn_pos.X + math.random(-500, 500)
                                        local sy = pve_spawn_pos.Y + math.random(-500, 500)
                                        local mob = world:SpawnActor(pve_mob_class_ref, {X=sx, Y=sy, Z=pve_spawn_pos.Z}, {})
                                        if mob and mob:IsValid() then
                                            table.insert(spawned_mobs, mob)
                                        end
                                    end)
                                end
                            end
                        end)
                        return false
                    end)
                end

                check_pve_completion()
            end)
            pve_death_hook_registered = true
        end)
    end

    if pve_death_hook_registered then return end

    -- Fallback: polling (shouldn't reach here)
    local last_alive_nearby = -1

    LoopAsync(100, function()
        if not is_world_valid() then return true end
        if not pve_event_active then return true end

        -- Count ALL alive AI within 5000 units of spawn point
        local alive_now = 0
        pcall(function()
            local all_ai = FindAllOf("DominionAICharacter")
            if all_ai and pve_spawn_pos then
                for _, ai in ipairs(all_ai) do
                    pcall(function()
                        if ai and ai:IsValid() then
                            local apos = ai:K2_GetActorLocation()
                            local dx = apos.X - pve_spawn_pos.X
                            local dy = apos.Y - pve_spawn_pos.Y
                            if math.sqrt(dx*dx + dy*dy) < 5000 then
                                alive_now = alive_now + 1
                            end
                        end
                    end)
                end
            end
        end)

        -- First poll or mobs still spawning — just update baseline
        if last_alive_nearby == -1 or alive_now > last_alive_nearby then
            last_alive_nearby = alive_now
            return false
        end

        -- Alive count dropped = kills happened
        local new_kills = last_alive_nearby - alive_now
        last_alive_nearby = alive_now

        if new_kills > 0 then
            local my_team = selected_team or "red"
            pve_kills[my_team] = pve_kills[my_team] + new_kills
            pve_total_killed = pve_total_killed + new_kills
            send_color("Kills: " .. pve_kills[my_team] .. "/" .. pve_current_event.kill_threshold .. " | Alive: " .. alive_now, 1, 0.5, 0)

            -- Auto-spawner
            if not pve_auto_spawning and pve_total_killed >= pve_current_event.auto_spawn_after then
                pve_auto_spawning = true
                send_color("Auto-spawner activated!", 1, 0.8, 0)
                LoopAsync(pve_current_event.respawn_interval, function()
                    if not is_world_valid() then return true end
                    if not pve_event_active then return true end
                    ExecuteInGameThread(function()
                        if pve_mob_class_ref and pve_spawn_pos then
                            local world = FindFirstOf("World")
                            if world then
                                pcall(function()
                                    local sx = pve_spawn_pos.X + math.random(-500, 500)
                                    local sy = pve_spawn_pos.Y + math.random(-500, 500)
                                    local mob = world:SpawnActor(pve_mob_class_ref, {X=sx, Y=sy, Z=pve_spawn_pos.Z}, {})
                                    if mob and mob:IsValid() then
                                        table.insert(spawned_mobs, mob)
                                    end
                                end)
                            end
                        end
                    end)
                    return false
                end)
            end

            check_pve_completion()
        end

        return false
    end)
end

-- F7: Start next PvE event (NEW role-based system)
RegisterKeyBind(Key.F7, function()
    local next_event = (current_pve_event or 0) + 1
    if next_event > 3 then
        send_color("All PvE events completed!", 0, 1, 0)
        return
    end
    start_pve_event(next_event)
end)

--[[ OLD F7: Start next PvE event (disabled)
RegisterKeyBind(Key.F7_OLD, function()
    local ok, err = pcall(function()
    if pve_event_active then
        send_color("PvE event already in progress!", 1, 0, 0)
        return
    end

    if not match_active then
        match_active = true
        if not selected_class then selected_class = "archer" end
        if not selected_team then selected_team = "red" end
        armor_tier = 1
        weapon_tier = 1
    end

    local next_event = pve_event + 1
    if next_event > 3 then
        send_color("All PvE events completed!", 1, 1, 0)
        return
    end

    local event = PVE_EVENTS[next_event]
    pve_current_event = event
    pve_event_active = true
    pve_auto_spawning = false
    pve_kills = {red = 0, blue = 0}
    pve_total_killed = 0

    send_color("===== PVE EVENT: " .. event.name .. " =====", 1, 0.8, 0)
    send_color("Kill " .. event.kill_threshold .. " to earn " .. event.tier_name .. " armor!", 0, 1, 1)

    pve_spawn_pos = get_player_pos()
    spawn_mobs_near(event.initial_count, event.mob_classes)

    -- Cache the mob class for auto-respawner (find after initial spawn)
    ExecuteWithDelay(3000, function()
        for _, mob in ipairs(spawned_mobs) do
            if mob then
                pcall(function()
                    if mob:IsValid() then
                        pve_mob_class_ref = mob:GetClass()
                    end
                end)
                if pve_mob_class_ref then break end
            end
        end
    end)

    -- Start kill tracking immediately — MaxHP=0 check skips uninitialized mobs
    start_pve_kill_tracking()
    end) -- end pcall
    if not ok then
        ctf_log("F7 ERROR: " .. tostring(err) .. "\n")
        send_color("F7 ERROR: " .. tostring(err), 1, 0, 0)
    end
end)
]]

-- F8: Kill all nearby enemies (debug — counts toward event)
RegisterKeyBind(Key.F8, function()
    kill_all_mobs()
    send_color("All nearby enemies destroyed!", 1, 0.3, 0)
end)

-- Numpad 2 REMOVED (was mob HP probe)
--[[ REMOVED
RegisterKeyBind(Key.NUM_TWO, function()
    send_color("Probing mob HP/damage...", 1, 0.8, 0)
    ctf_log("=== MOB HP/DAMAGE PROBE ===\n")

    -- Probe the last spawned mob (from Numpad 3/4/5)
    local mob = last_spawned_mob
    if not mob then
        send_color("Spawn a mob first (Numpad 3/4/5), then probe with Numpad 2", 1, 0, 0)
        return
    end
    local valid = false
    pcall(function() valid = mob:IsValid() end)
    if not valid then
        send_color("Last spawned mob is dead/gone!", 1, 0, 0)
        return
    end

    if not mob then
        send_color("No mob found to probe!", 1, 0, 0)
        return
    end

    local mob_name = "unknown"
    pcall(function() mob_name = mob:GetClass():GetName() end)
    ctf_log("=== PROBING: " .. mob_name .. " ===\n")
    send_color("Probing: " .. mob_name, 1, 0.8, 0)

    -- Health
    pcall(function()
        local hp = mob.HealthComponent
        if hp and hp:IsValid() then
            local maxHP = hp:GetMaxHealth()
            local curHP = hp:GetAuthoritativeHealth()
            ctf_log("HP: " .. tostring(curHP) .. "/" .. tostring(maxHP) .. "\n")
            send_color("HP: " .. tostring(curHP) .. "/" .. tostring(maxHP), 0, 1, 0)

            -- Try EVERY possible way to modify HP
            local methods = {
                {"SetHealth(500)", function() hp:SetHealth(500) end},
                {"ModifyMaxHealth(500)", function() hp:ModifyMaxHealth(500) end},
                {"AuthoritativeHealth=500", function() hp.AuthoritativeHealth = 500 end},
                {"MaxHealth=500", function() hp.MaxHealth = 500 end},
                {"BaseMaxHealth=500", function() hp.BaseMaxHealth = 500 end},
                {"CurrentHealth=500", function() hp.CurrentHealth = 500 end},
                {"Health=500", function() hp.Health = 500 end},
            }
            for _, m in ipairs(methods) do
                pcall(m[2])
            end
            local newMax = hp:GetMaxHealth()
            local newCur = hp:GetAuthoritativeHealth()
            ctf_log("After ALL modify attempts: " .. tostring(newCur) .. "/" .. tostring(newMax) .. "\n")
            send_color("After: " .. tostring(newCur) .. "/" .. tostring(newMax), 1, 1, 0)

            -- Also scan health component for ALL numeric properties
            pcall(function()
                local hp_cls = hp:GetClass()
                if hp_cls then
                    hp_cls:ForEachProperty(function(prop)
                        pcall(function()
                            local pname = prop:GetFName():ToString()
                            local val = hp[pname]
                            if val ~= nil and tonumber(tostring(val)) then
                                ctf_log("HC." .. pname .. " = " .. tostring(val) .. "\n")
                                send_color("HC." .. pname .. " = " .. tostring(val), 0.5, 1, 0.5)
                            end
                        end)
                    end)
                end
            end)
        else
            send_color("No HealthComponent!", 1, 0, 0)
        end
    end)

    -- Damage component properties
    pcall(function()
        local dmg = mob.BP_AiDamageComponent
        if dmg and dmg:IsValid() then
            local dmg_cls = dmg:GetClass()
            dmg_cls:ForEachProperty(function(prop)
                pcall(function()
                    local pname = prop:GetFName():ToString()
                    local val = dmg[pname]
                    if val ~= nil and tonumber(tostring(val)) then
                        ctf_log("Dmg." .. pname .. " = " .. tostring(val) .. "\n")
                        send_color("Dmg." .. pname .. " = " .. tostring(val), 1, 0.5, 0)
                    end
                end)
            end)
        end
    end)

    -- Mob numeric properties
    local props = {"PowerLevel", "Level", "BaseDamage", "AttackDamage", "DamageMultiplier", "Armor", "Defence"}
    for _, pname in ipairs(props) do
        pcall(function()
            local val = mob[pname]
            if val ~= nil and tonumber(tostring(val)) then
                ctf_log("" .. pname .. " = " .. tostring(val) .. "\n")
                send_color(pname .. " = " .. tostring(val), 1, 1, 0)
            end
        end)
    end

    -- Probe the AI Data asset for this mob type
    ctf_log("=== PROBING AI DATA ASSETS ===")

    -- Try to get the data asset directly from the mob via AIDataAsset property
    pcall(function()
        local data_ref = mob.AIDataAsset
        if data_ref and data_ref:IsValid() then
            ctf_log("MOB HAS AIDataAsset: " .. data_ref:GetFullName())
            send_color("AIDataAsset found on mob!", 0, 1, 1)
            local dcls = data_ref:GetClass()
            if dcls then
                dcls:ForEachProperty(function(prop)
                    pcall(function()
                        local pname = prop:GetFName():ToString()
                        local ptype = prop:GetClass():GetFName():ToString()
                        local val = data_ref[pname]
                        local str = tostring(val or "nil")
                        ctf_log("  DA." .. pname .. " = " .. str .. " [" .. ptype .. "]")
                        send_color("  DA." .. pname .. " = " .. str, 1, 1, 0)
                    end)
                end)
            end
        else
            ctf_log("Mob has NO AIDataAsset property")
        end
    end)

    -- Also try common data-holding property names
    local data_props = {"DataAsset", "AIData", "AiData", "CharacterData", "MobData", "CombatData", "StatsData", "CreatureData", "NPCData"}
    for _, dp in ipairs(data_props) do
        pcall(function()
            local val = mob[dp]
            if val and type(val) ~= "number" and type(val) ~= "string" and type(val) ~= "boolean" then
                local valid = false
                pcall(function() valid = val:IsValid() end)
                if valid then
                    ctf_log("FOUND data prop: " .. dp .. " = " .. val:GetFullName())
                    send_color("DATA: " .. dp, 0, 1, 1)
                    local dcls = val:GetClass()
                    if dcls then
                        dcls:ForEachProperty(function(prop)
                            pcall(function()
                                local pname = prop:GetFName():ToString()
                                local ptype = prop:GetClass():GetFName():ToString()
                                local v = val[pname]
                                ctf_log("  " .. dp .. "." .. pname .. " = " .. tostring(v or "nil") .. " [" .. ptype .. "]")
                            end)
                        end)
                    end
                end
            end
        end)
    end

    -- Enumerate ALL mob properties (not just numeric) to find anything data/config related
    ctf_log("=== ALL MOB PROPERTIES ===")
    pcall(function()
        local mob_cls = mob:GetClass()
        if mob_cls then
            local pcount = 0
            mob_cls:ForEachProperty(function(prop)
                pcount = pcount + 1
                pcall(function()
                    local pname = prop:GetFName():ToString()
                    local ptype = prop:GetClass():GetFName():ToString()
                    local val = mob[pname]
                    local str = tostring(val or "nil")
                    -- Log everything, truncate long values
                    if #str > 80 then str = str:sub(1, 80) .. "..." end
                    ctf_log("  " .. pname .. " = " .. str .. " [" .. ptype .. "]")
                end)
            end)
            ctf_log("Total properties: " .. tostring(pcount))
        end
    end)

    -- Static data asset paths as fallback
    local data_paths = {
        "/Game/Gameplay/AI/Wolf/BP_AI_Wolf_Data.BP_AI_Wolf_Data",
        "/FutureMajorVersion/Gameplay/AI/Wolf/DragonWolf/BP_AI_DragonWolf_Data.BP_AI_DragonWolf_Data",
        "/Game/Gameplay/AI/Wolf/WolfEliteVariant/BP_AI_WolfElite_Data.BP_AI_WolfElite_Data",
        "/Game/Gameplay/AI/BeastFaction/MediumBeast/BP_AI_MediumBeast_Data.BP_AI_MediumBeast_Data",
        "/Game/Gameplay/AI/BeastFaction/RangedBeast/BP_AI_RangedBeast_Data.BP_AI_RangedBeast_Data",
    }
    for _, dpath in ipairs(data_paths) do
        pcall(function()
            local data = StaticFindObject(dpath)
            if data and data:IsValid() then
                local dname = dpath:match("([^/]+)$")
                ctf_log("StaticFind OK: " .. dname)
                send_color("DATA: " .. dname, 0, 1, 1)
                local data_cls = data:GetClass()
                if data_cls then
                    data_cls:ForEachProperty(function(prop)
                        pcall(function()
                            local pname = prop:GetFName():ToString()
                            local ptype = prop:GetClass():GetFName():ToString()
                            local val = data[pname]
                            ctf_log("  " .. dname .. "." .. pname .. " = " .. tostring(val or "nil") .. " [" .. ptype .. "]")
                            send_color("  " .. pname .. " = " .. tostring(val or "nil"), 1, 1, 0)
                        end)
                    end)
                end
            else
                ctf_log("NOT FOUND: " .. dpath)
            end
        end)
    end

    ctf_log("=== PROBE DONE ===")
    return
end)

------------------------------------------------------------
-- F10: Scan nearest NATURAL mob (not spawned by us)
-- Deep property dump to compare vs our spawned mobs
------------------------------------------------------------
RegisterKeyBind(Key.F10, function()
    send_color("Scanning nearest natural mob...", 0, 1, 1)
    ctf_log("=== NATURAL MOB SCAN (F10) ===")

    local search_classes = {
        "BP_AI_Wolf_Character_C", "BP_AI_WolfElite_Character_C",
        "BP_AI_DragonWolf_Character_C", "BP_AI_SpectralDragonWolf_Character_C",
        "BP_AI_MediumBeast_Character_C", "BP_AI_RangedBeast_Character_C", "BP_AI_MagicBeast_Character_C",
        "BP_AI_RotswornZombie_Character_C", "BP_AI_RotswornWarrior_Character_C", "BP_AI_RotswornMarauder_Character_C",
        "BP_AI_SkeletalArcher_Character_C", "BP_AI_SkeletalHoplite_Character_C", "BP_AI_SpectralSkeletalHoplite_Character_C",
        "BP_AI_1HMeleeBlackKnight_Character_C", "BP_AI_Melee2HBlackKnight_Character_C", "BP_AI_BlackKnightRanged_Character_C",
        "BP_AI_Zogre_Character_C", "BP_AI_Zogre_Character_C", "BP_AI_Ogre_Character_C",
        "BP_AI_Zogre_Fellhollow_Character_C", "BP_AI_ZogreFellhollow_Character_C",
        "BP_AI_DragonLesserGreen_Character_C", "BP_AI_DragonLesserBlue_Character_C",
        "BP_AI_AbyssalDemon_Character_C",
        "BP_AI_ZamorakAcolyte_Character_C", "BP_AI_MageOfZamorak_Character_C",
        "BP_AI_HellHound_Minion_Fido_Character_C", "BP_AI_HellHound_Minion_Gnasher_Character_C",
    }

    -- Broad scan — log ALL loaded AI mob classes using GetFullName (GetName fails in pcall)
    ctf_log("=== ALL LOADED AI CLASSES ===")
    pcall(function()
        local seen = {}
        local all_ai = FindAllOf("BP_DominionAICharacter_C")
        if all_ai then
            ctf_log("FindAllOf returned " .. #all_ai .. " AI mobs")
            for _, ai in ipairs(all_ai) do
                pcall(function()
                    if ai and ai:IsValid() then
                        local full = ai:GetClass():GetFullName()
                        if not seen[full] then
                            seen[full] = true
                            ctf_log("MOB: " .. full)
                            send_color(full:match("([^/]+)$") or full, 0, 1, 1)
                        end
                    end
                end)
            end
        else
            ctf_log("FindAllOf returned nil")
        end
    end)

    local found_mob = nil
    local found_name = ""

    for _, cls_name in ipairs(search_classes) do
        if found_mob then break end
        pcall(function()
            local mob = FindFirstOf(cls_name)
            if mob and mob:IsValid() then
                found_mob = mob
                found_name = mob:GetClass():GetName()
            end
        end)
    end

    if not found_mob then
        send_color("No natural mobs found nearby!", 1, 0, 0)
        ctf_log("No natural mobs found")
        return
    end

    ctf_log("=== NATURAL MOB: " .. found_name .. " ===")
    send_color("Natural: " .. found_name, 0, 1, 0)

    -- Full class path
    pcall(function()
        ctf_log("Class: " .. found_mob:GetClass():GetFullName())
    end)

    -- Health
    pcall(function()
        local hp = found_mob.HealthComponent
        if hp and hp:IsValid() then
            local maxHP = hp:GetMaxHealth()
            local curHP = hp:GetAuthoritativeHealth()
            ctf_log("HP: " .. tostring(curHP) .. "/" .. tostring(maxHP))
            send_color("HP: " .. tostring(curHP) .. "/" .. tostring(maxHP), 0, 1, 0)

            -- Enumerate health component properties
            pcall(function()
                local hp_cls = hp:GetClass()
                if hp_cls then
                    ctf_log("HealthComp class: " .. hp_cls:GetFullName())
                    hp_cls:ForEachProperty(function(prop)
                        pcall(function()
                            local pname = prop:GetFName():ToString()
                            local ptype = prop:GetClass():GetFName():ToString()
                            local val = hp[pname]
                            ctf_log("  HC." .. pname .. " = " .. tostring(val or "nil") .. " [" .. ptype .. "]")
                        end)
                    end)
                end
            end)
        else
            ctf_log("No HealthComponent")
            send_color("No HealthComponent!", 1, 0, 0)
        end
    end)

    -- Damage component — properties AND functions
    pcall(function()
        local dmg = found_mob.BP_AiDamageComponent
        if dmg and dmg:IsValid() then
            ctf_log("Has BP_AiDamageComponent")
            local dmg_cls = dmg:GetClass()
            if dmg_cls then
                ctf_log("DmgComp class: " .. dmg_cls:GetFullName())
                -- Properties
                dmg_cls:ForEachProperty(function(prop)
                    pcall(function()
                        local pname = prop:GetFName():ToString()
                        local ptype = prop:GetClass():GetFName():ToString()
                        local val = dmg[pname]
                        ctf_log("  Dmg." .. pname .. " = " .. tostring(val or "nil") .. " [" .. ptype .. "]")
                    end)
                end)
                -- Functions (hookable)
                ctf_log("=== DMG FUNCTIONS ===")
                dmg_cls:ForEachFunction(function(func)
                    pcall(function()
                        local fname = func:GetFName():ToString()
                        ctf_log("  Dmg::" .. fname .. "()")
                    end)
                end)
            end
        end
    end)

    -- Also check the mob's own functions for damage hooks
    pcall(function()
        local mob_cls = found_mob:GetClass()
        if mob_cls then
            ctf_log("=== MOB FUNCTIONS ===")
            mob_cls:ForEachFunction(function(func)
                pcall(function()
                    local fname = func:GetFName():ToString()
                    if fname:find("Damage") or fname:find("Hit") or fname:find("Attack")
                       or fname:find("Hurt") or fname:find("Death") or fname:find("Combat")
                       or fname:find("Take") or fname:find("Receive") or fname:find("Apply") then
                        ctf_log("  Mob::" .. fname .. "()")
                    end
                end)
            end)
        end
    end)

    -- Check the AI base class functions too
    pcall(function()
        local base = StaticFindObject("/Game/Gameplay/AI/BP_DominionAICharacter.BP_DominionAICharacter_C")
        if base and base:IsValid() then
            ctf_log("=== AI BASE FUNCTIONS ===")
            base:ForEachFunction(function(func)
                pcall(function()
                    local fname = func:GetFName():ToString()
                    if fname:find("Damage") or fname:find("Hit") or fname:find("Attack")
                       or fname:find("Hurt") or fname:find("Death") or fname:find("Combat")
                       or fname:find("Take") or fname:find("Receive") or fname:find("Apply") then
                        ctf_log("  AIBase::" .. fname .. "()")
                    end
                end)
            end)
        end
    end)

    -- === C++ CLASS HIERARCHY PROBE (looking for damage hooks) ===
    -- Walk up the class hierarchy of damage components to find C++ functions
    local function probe_class_hierarchy(obj, label)
        pcall(function()
            local cls = obj:GetClass()
            local depth = 0
            while cls and depth < 10 do
                local name = cls:GetFullName()
                ctf_log(label .. " L" .. depth .. ": " .. name)

                local fcount = 0
                cls:ForEachFunction(function(func)
                    pcall(function()
                        local fname = func:GetFName():ToString()
                        fcount = fcount + 1
                        if fname:find("Damage") or fname:find("Hit") or fname:find("Take")
                           or fname:find("Health") or fname:find("Receive") or fname:find("Apply")
                           or fname:find("Hurt") or fname:find("Attack") or fname:find("OnHit")
                           or fname:find("Impact") or fname:find("Instigat") then
                            ctf_log("  >> " .. fname .. "()")
                        end
                    end)
                end)
                ctf_log("  (" .. fcount .. " total functions)")

                -- Go to parent class
                local super = nil
                pcall(function() super = cls:GetSuperStruct() end)
                if super and super:IsValid() and super:GetFullName() ~= name then
                    cls = super
                else
                    break
                end
                depth = depth + 1
            end
        end)
    end

    pcall(function()
        local mob = found_mob
        ctf_log("=== DAMAGE COMPONENT HIERARCHY ===")
        pcall(function() probe_class_hierarchy(mob.BP_AiDamageComponent, "DmgComp") end)

        ctf_log("=== HEALTH COMPONENT HIERARCHY ===")
        pcall(function() probe_class_hierarchy(mob.HealthComponent, "HealthComp") end)

        ctf_log("=== HIT REACTIONS HIERARCHY ===")
        pcall(function() probe_class_hierarchy(mob.BP_AiHitReactionsComponent, "HitReact") end)

        ctf_log("=== HIT POINTS HIERARCHY ===")
        pcall(function() probe_class_hierarchy(mob.BP_AiHitPointsComponent, "HitPoints") end)
    end)

    -- === SEARCH FOR PROJECTILE/ARROW CLASSES ===
    ctf_log("=== PROJECTILE SEARCH ===")
    local projectile_classes = {
        "Projectile", "BP_Projectile_C", "BP_Arrow_C", "BP_Projectile_Arrow_C",
        "BP_RangedProjectile_C", "DominionProjectile", "BP_DominionProjectile_C",
    }
    for _, pc in ipairs(projectile_classes) do
        pcall(function()
            local proj = FindFirstOf(pc)
            if proj and proj:IsValid() then
                ctf_log("FOUND PROJECTILE: " .. pc .. " = " .. proj:GetClass():GetFullName())
                -- Probe its functions
                local pcls = proj:GetClass()
                pcls:ForEachFunction(function(func)
                    pcall(function()
                        ctf_log("  " .. pc .. "::" .. func:GetFName():ToString() .. "()")
                    end)
                end)
            end
        end)
    end

    -- === PLAYER DAMAGE COMPONENT HIERARCHY ===
    pcall(function()
        local player = FindFirstOf("BP_PlayerCharacter_C")
        if player and player:IsValid() then
            ctf_log("=== PLAYER DAMAGE HIERARCHY ===")
            pcall(function() probe_class_hierarchy(player.BP_Components_PlayerDamage, "PlayerDmg") end)

            ctf_log("=== PLAYER MELEE HIERARCHY ===")
            pcall(function() probe_class_hierarchy(player.BP_Components_PlayerMeleeAttack, "MeleeAtk") end)

            ctf_log("=== PLAYER RANGED HIERARCHY ===")
            pcall(function() probe_class_hierarchy(player.BP_Components_PlayerRangedAttack, "RangedAtk") end)
        end
    end)

    -- === PLAYER CHARACTER FUNCTIONS (for damage-dealing hooks) ===
    pcall(function()
        local player = FindFirstOf("BP_PlayerCharacter_C")
        if player and player:IsValid() then
            local pcls = player:GetClass()
            ctf_log("=== PLAYER FUNCTIONS (all) ===")
            pcls:ForEachFunction(function(func)
                pcall(function()
                    local fname = func:GetFName():ToString()
                    ctf_log("  Player::" .. fname .. "()")
                end)
            end)

            -- Also check player components for damage/combat
            ctf_log("=== PLAYER COMPONENTS ===")
            pcls:ForEachProperty(function(prop)
                pcall(function()
                    local pname = prop:GetFName():ToString()
                    local ptype = prop:GetClass():GetFName():ToString()
                    if ptype == "ObjectProperty" then
                        ctf_log("  " .. pname .. " [" .. ptype .. "]")
                        -- Probe component functions if it looks combat-related
                        if pname:find("Combat") or pname:find("Attack") or pname:find("Damage")
                           or pname:find("Weapon") or pname:find("Hit") or pname:find("Perk")
                           or pname:find("Spell") or pname:find("Ability") then
                            pcall(function()
                                local comp = player[pname]
                                if comp and comp:IsValid() then
                                    local ccls = comp:GetClass()
                                    ctf_log("    Class: " .. ccls:GetFullName())
                                    ccls:ForEachFunction(function(f)
                                        pcall(function()
                                            ctf_log("    " .. pname .. "::" .. f:GetFName():ToString() .. "()")
                                        end)
                                    end)
                                end
                            end)
                        end
                    end
                end)
            end)
        end
    end)

    -- Key named properties — with explicit error logging for UObject drilling
    local key_props = {
        "PowerLevel", "Level", "BaseDamage", "AttackDamage", "DamageMultiplier",
        "Armor", "Defence", "AIDataAsset", "DataAsset", "AIData", "CombatData",
        "CharacterData", "SpawnData", "MobData",
    }
    for _, pname in ipairs(key_props) do
        local ok, err = pcall(function()
            local val = found_mob[pname]
            if val ~= nil then
                local str = tostring(val)
                ctf_log(pname .. " = " .. str)
                send_color(pname .. " = " .. str, 1, 1, 0)
                -- If it's a UObject, try to drill into it
                if type(val) == "userdata" then
                    local ok2, err2 = pcall(function()
                        local valid = val:IsValid()
                        ctf_log("  " .. pname .. ":IsValid() = " .. tostring(valid))
                        if valid then
                            ctf_log("  " .. pname .. ":GetFullName() = " .. val:GetFullName())
                            local vcls = val:GetClass()
                            if vcls then
                                ctf_log("  " .. pname .. " class: " .. vcls:GetFullName())
                                vcls:ForEachProperty(function(prop)
                                    pcall(function()
                                        local pp = prop:GetFName():ToString()
                                        local pt = prop:GetClass():GetFName():ToString()
                                        local pv = val[pp]
                                        ctf_log("    " .. pp .. " = " .. tostring(pv or "nil") .. " [" .. pt .. "]")
                                    end)
                                end)
                            end
                        end
                    end)
                    if not ok2 then
                        ctf_log("  " .. pname .. " drill ERROR: " .. tostring(err2))
                    end
                end
            end
        end)
        if not ok then
            ctf_log(pname .. " access ERROR: " .. tostring(err))
        end
    end

    -- ALL mob properties (full dump)
    ctf_log("=== ALL NATURAL MOB PROPERTIES ===")
    pcall(function()
        local mob_cls = found_mob:GetClass()
        if mob_cls then
            local pcount = 0
            mob_cls:ForEachProperty(function(prop)
                pcount = pcount + 1
                pcall(function()
                    local pname = prop:GetFName():ToString()
                    local ptype = prop:GetClass():GetFName():ToString()
                    local val = found_mob[pname]
                    local str = tostring(val or "nil")
                    if #str > 80 then str = str:sub(1, 80) .. "..." end
                    ctf_log("  " .. pname .. " = " .. str .. " [" .. ptype .. "]")
                end)
            end)
            ctf_log("Total properties: " .. tostring(pcount))
        end
    end)

    ctf_log("=== NATURAL MOB SCAN DONE ===")
    send_color("Scan complete — check ctf_debug.log", 0, 1, 1)
end)
--]] -- END REMOVED NUM_TWO

--[[ OLD F11 SCAN (replaced by Numpad 2 above)
RegisterKeyBind(Key.NUM_TWO_OLD, function()
    send_color("Scanning nearby AI mobs...", 1, 0.8, 0)
    ctf_log("=== NEARBY AI SCAN ===\n")

    local ppos = get_player_pos()
    if not ppos then return end

    local found_types = {}
    local search_classes = {
        "BP_AI_Wolf_Character_C", "BP_AI_WolfElite_Character_C",
        "BP_AI_MediumBeast_Character_C", "BP_AI_RangedBeast_Character_C", "BP_AI_MagicBeast_Character_C",
        "BP_AI_RotswornZombie_Character_C", "BP_AI_RotswornWarrior_Character_C",
        "BP_AI_1HMeleeBlackKnight_Character_C", "BP_AI_Zogre_Character_C",
        "BP_AI_DragonLesserGreen_Character_C", "BP_AI_AbyssalDemon_Character_C",
        "BP_AI_ZamorakAcolyte_Character_C", "BP_AI_MageOfZamorak_Character_C",
        "BP_AI_HellHound_Character_C", "BP_AI_HellRat_Character_C",
        "BP_AI_GiantRat_Character_C", "BP_AI_GiantRatWithered_Character_C",
        "BP_AI_Zombie_Character_C", "BP_AI_ThaneBeast_Character_C",
        "BP_AI_Deer_Character_C", "BP_AI_Sheep_Character_C",
        "BP_AI_SkeletalArcher_Character_C", "BP_AI_SkeletalHoplite_Character_C",
    }

    for _, cls_name in ipairs(search_classes) do
        pcall(function()
            local found = FindFirstOf(cls_name)
            if found and found:IsValid() then
                local actual_class = found:GetClass():GetName()
                if not found_types[actual_class] then
                    found_types[actual_class] = true
                    local full = found:GetClass():GetFullName()
                    ctf_log("FOUND: " .. actual_class .. " (searched: " .. cls_name .. ") | " .. full .. "\n")
                    send_color("[FOUND] " .. actual_class .. " ← " .. cls_name, 0, 1, 1)
                end
            end
        end)
    end

    if not next(found_types) then
        send_color("No AI mobs found!", 1, 0, 0)
    end

    -- Probe the first AI mob found — check HP, damage, and all combat properties
    pcall(function()
        local mob = FindFirstOf("DominionAICharacter")
        if mob and mob:IsValid() then
            local mob_name = mob:GetClass():GetName()
            ctf_log("=== PROBING: " .. mob_name .. " ===\n")
            send_color("Probing: " .. mob_name, 1, 0.8, 0)

            -- Health component
            pcall(function()
                local hp = mob.HealthComponent
                if hp and hp:IsValid() then
                    local maxHP = hp:GetMaxHealth()
                    local curHP = hp:GetAuthoritativeHealth()
                    ctf_log("HP: " .. tostring(curHP) .. "/" .. tostring(maxHP) .. "\n")
                    send_color("HP: " .. tostring(curHP) .. "/" .. tostring(maxHP), 0, 1, 0)

                    -- Try to SET health
                    pcall(function() hp:SetHealth(500) end)
                    pcall(function() hp:ModifyMaxHealth(500) end)
                    local newMax = hp:GetMaxHealth()
                    local newCur = hp:GetAuthoritativeHealth()
                    ctf_log("After SetHealth(500): " .. tostring(newCur) .. "/" .. tostring(newMax) .. "\n")
                    send_color("After set: " .. tostring(newCur) .. "/" .. tostring(newMax), 1, 1, 0)
                end
            end)

            -- Damage component
            pcall(function()
                local dmg = mob.BP_AiDamageComponent
                if dmg and dmg:IsValid() then
                    ctf_log("Has BP_AiDamageComponent\n")
                    local dmg_cls = dmg:GetClass()
                    dmg_cls:ForEachProperty(function(prop)
                        pcall(function()
                            local pname = prop:GetFName():ToString()
                            local val = dmg[pname]
                            if val ~= nil then
                                local str = tostring(val)
                                if tonumber(str) then
                                    ctf_log("Dmg." .. pname .. " = " .. str .. "\n")
                                    send_color("Dmg." .. pname .. " = " .. str, 1, 0.5, 0)
                                end
                            end
                        end)
                    end)
                end
            end)

            -- General numeric properties on the mob
            local combat_props = {"PowerLevel", "Level", "BaseDamage", "AttackDamage",
                                  "DamageMultiplier", "DamageMult", "AttackPower",
                                  "Armor", "Defence", "Defense", "Resistance"}
            for _, pname in ipairs(combat_props) do
                pcall(function()
                    local val = mob[pname]
                    if val ~= nil and tonumber(tostring(val)) then
                        ctf_log("Mob." .. pname .. " = " .. tostring(val) .. "\n")
                        send_color("Mob." .. pname .. " = " .. tostring(val), 1, 1, 0)
                    end
                end)
            end
        end
    end)
    ctf_log("=== SCAN DONE ===\n")
end)
--]]

-- Numpad 7: Force complete current PvE event
RegisterKeyBind(Key.NUM_SEVEN, function()
    if not pve_event_active or not pve_current_event then
        send_color("No PvE event active!", 1, 0, 0)
        return
    end
    local my_team = selected_team or "red"
    pve_kills[my_team] = pve_current_event.kill_threshold
    send_color("Force completing event...", 1, 0.8, 0)
    check_pve_completion()
end)

------------------------------------------------------------
-- Numpad 0: Simulate PvP kill (+1 individual, +1 team)
------------------------------------------------------------
local individual_kills = 0
local team_kills = 0

--[[ NUM_ZERO REMOVED (clashes with CTFBuildingTool import)
RegisterKeyBind(Key.NUM_ZERO, function()
    if resetting then return end
    -- Set selected_class/selected_team from player_data if available
    if not selected_class or not selected_team then
        local my_player = FindFirstOf("BP_PlayerCharacter_C")
        if my_player then
            pcall(function()
                local ctrl = my_player:GetInstigatorController()
                if ctrl and ctrl:IsValid() then
                    local my_id = ctrl.PlayerState.PlayerId
                    local pd = player_data[my_id]
                    if pd then
                        if pd.class then selected_class = pd.class end
                        if pd.team then selected_team = pd.team end
                    end
                end
            end)
        end
    end

    if not match_active then
        -- Quick start for testing — cycle class each time
        match_active = true
        block_windstep()
        if not selected_team then selected_team = "red" end
        local class_cycle = {"archer", "assassin", "guardian", "berserker", "fire_mage", "air_mage"}
        if not selected_class then
            selected_class = class_cycle[1]
        else
            -- Find next class
            for i, cls in ipairs(class_cycle) do
                if cls == selected_class then
                    selected_class = class_cycle[(i % #class_cycle) + 1]
                    break
                end
            end
        end
        armor_tier = 0
        weapon_tier = 0
        individual_kills = 0
        team_kills = 0
        trinket_earned = false
        equip_loadout(BASE_ARMOR, {BASE_WEAP.SwingSlash, BASE_WEAP.AshBow}, BASE_WEAP.BoneArrows, get_cape(selected_team, 0))
        send_color("Match started as " .. string.upper(selected_team) .. " " .. CLASS_DISPLAY[selected_class], 1, 0.8, 0)
        send_color("Press F5 again to cycle class, or keep pressing for kills", 0.5, 0.5, 0.5)
        return
    end

    individual_kills = individual_kills + 1
    team_kills = team_kills + 1

    send_color("KILL! Individual: " .. individual_kills .. " | Team: " .. team_kills, 1, 0.5, 0)

    -- Check individual threshold: 3 kills = specialization (FULL equip: armor + weapons + runes)
    if individual_kills == 3 and weapon_tier == 0 then
        weapon_tier = 1
        armor_tier = math.max(armor_tier, 1)
        send_color("===== SPECIALIZATION UNLOCKED: " .. CLASS_DISPLAY[selected_class] .. " =====", 0, 1, 0)
        equip_busy = false
        equip_current_gear()  -- full swap: T2 → T3 armor + weapons
        -- Give runes AFTER equip pipeline finishes
        ExecuteWithDelay(1000, function() give_class_runes() end)
        play_vfx()
        return
    end

    -- Check individual threshold: 12 kills = trinket (add trinket only, no gear swap)
    if individual_kills == 12 and not trinket_earned then
        trinket_earned = true
        send_color("===== 12 KILLS! TRINKET EARNED =====", 1, 0.8, 0)
        local trinket_path = TRINKETS[selected_class]
        if trinket_path then
            pcall(function() add_to_loadout(trinket_path) end)
        end
        play_vfx()
    end

    -- Check team thresholds: 12/24/36 (WEAPONS ONLY — no armor swap)
    local weapon_changed = false

    if team_kills == 12 and weapon_tier < 2 then
        weapon_tier = 2
        if individual_kills < 3 then
            -- Auto-promote: needs full equip since going from base to class gear
            individual_kills = 3
            armor_tier = math.max(armor_tier, 1)
            send_color(">> AUTO-PROMOTED! (team hit 12 kills)", 1, 0.8, 0)
            equip_busy = false
            equip_current_gear()
            ExecuteWithDelay(1000, function() give_class_runes(runes_given) end)
            play_vfx()
            return
        end
        send_color("===== 12 TEAM KILLS! Weapons → T4 =====", 0, 1, 1)
        weapon_changed = true
    end

    if team_kills == 24 and weapon_tier < 3 then
        weapon_tier = 3
        send_color("===== 24 TEAM KILLS! Weapons → T5 =====", 0, 1, 1)
        weapon_changed = true
    end

    if team_kills == 36 and weapon_tier < 4 then
        weapon_tier = 4
        send_color("===== 36 TEAM KILLS! Weapons → T6 (MAX) =====", 1, 0.8, 0)
        weapon_changed = true
    end

    -- Weapon-only swap: clear action bar, add new weapons + arrows (no armor/loadout touch)
    if weapon_changed then
        unlock_inv()
        local w_idx = math.max(weapon_tier, 1)
        local weapons = CLASS_WEAP[selected_class][w_idx]
        local ammo = nil
        if selected_class == "archer" then
            ammo = ARCHER_AMMO[w_idx] or CLASS_AMMO.archer
        end

        -- Step 1: Clear inventory only (not loadout — armor/cape/trinket stay)
        ExecuteInGameThread(function()
            local c = FindFirstOf("BP_PlayerController_C")
            if c then
                pcall(function() c.BP_Components_Inventory:ClearInventory() end)
            end

            -- Step 2: Add new weapons + arrows after clear completes
            ExecuteWithDelay(500, function()
                ExecuteInGameThread(function()
                    for _, w in ipairs(weapons) do add_item(w) end
                    if ammo then add_item(ammo, 50) end

                    -- Auto-equip arrows only (they land after weapons in action bar)
                    if ammo then
                        local arrow_slot = #weapons  -- 0-indexed: arrows go after weapons
                        ExecuteWithDelay(200, function()
                            ExecuteInGameThread(function()
                                local ctrl = FindFirstOf("BP_PlayerController_C")
                                if ctrl then
                                    local inv = ctrl.BP_Components_Inventory
                                    local invCtrl = ctrl.BP_Components_InventoryController
                                    -- Only equip the arrow slot
                                    pcall(function() invCtrl:UseItemFromInventory(inv, arrow_slot) end)
                                end
                            end)
                        end)
                    end

                    play_vfx()

                    -- Re-give runes (ClearInventory wiped them)
                    ExecuteWithDelay(500, function()
                        give_class_runes(true)  -- silent
                    end)
                end)
            end)
        end)
    end
end)
--]] -- END REMOVED NUM_ZERO

------------------------------------------------------------
-- F9: Give class-specific runes only
------------------------------------------------------------
RegisterKeyBind(Key.F9, function()
    unlock_inv()

    -- Give ALL rune types for testing (50 each)
    local all_runes = {
        "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Air.ITEM_Rune_Air",
        "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Fire.ITEM_Rune_Fire",
        "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Earth.ITEM_Rune_Earth",
        "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Water.ITEM_Rune_Water",
        "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Nature.ITEM_Rune_Nature",
        "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Law.ITEM_Rune_Law",
        "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Astral.ITEM_Rune_Astral",
        "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Essence.ITEM_Rune_Essence",
    }
    for _, r in ipairs(all_runes) do add_item(r, 50) end
    send_color("All runes added (50 each)! Test spells now.", 0, 1, 0)

    local cls = selected_class or "fire_mage"
    local RUNE = {
        Air    = "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Air.ITEM_Rune_Air",
        Fire   = "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Fire.ITEM_Rune_Fire",
        Nature = "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Nature.ITEM_Rune_Nature",
        Law    = "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Law.ITEM_Rune_Law",
        Astral = "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Astral.ITEM_Rune_Astral",
    }

    -- Class-specific runes (exact amounts per cast × 5 casts)
    local class_runes = {
        archer    = {{RUNE.Astral, 75}, {RUNE.Nature, 50}},      -- Snare: 15 astral + 10 nature
        assassin  = {{RUNE.Air, 75}, {RUNE.Astral, 25}},         -- Enchant Air: 15 air + 5 astral
        guardian  = {{RUNE.Air, 75}},                              -- Tempest Shield: 15 air
        berserker = {{RUNE.Fire, 75}, {RUNE.Astral, 25}},        -- Enchant Fire: 15 fire + 5 astral
        fire_mage = {{RUNE.Astral, 50}, {RUNE.Law, 50}},         -- Surge: 10 astral + 10 law
        air_mage  = {{RUNE.Astral, 50}, {RUNE.Law, 50}},         -- Surge: 10 astral + 10 law
    }

    local runes = class_runes[cls]
    if runes then
        for _, r in ipairs(runes) do
            add_item(r[1], r[2])
        end
        send_color("Runes for " .. CLASS_DISPLAY[cls] .. " added! (5 casts)", 0, 1, 0)
    end
end)

------------------------------------------------------------
-- PowerLevel write + CDO pre-spawn approach
------------------------------------------------------------
local TIER_POWER_LEVELS = {4, 5, 6}  -- T1(Num3)=PL4, T2(Num4)=PL5, T3(Num5)=PL6

local function spawn_mob_with_level(mob_key, target_level, tier_label)
    local pos = get_player_pos()
    if not pos then return end
    pos.X = pos.X - 500  -- spawn 500 units away (opposite direction from hill)
    if BOSS_MOBS[mob_key] then pos.Z = pos.Z + 200 end  -- offset to avoid ground clip  -- bosses spawn higher to avoid ground clip
    local cls = get_mob_class(mob_key)
    if not cls then send_color(mob_key .. " not available!", 1, 0, 0) return end

    ctf_log("=== SPAWN " .. tier_label .. ": " .. mob_key .. " (target PL=" .. target_level .. ") ===")

    ExecuteInGameThread(function()
        local world = FindFirstOf("World")
        if not world then return end
        pcall(function()
            local mob = world:SpawnActor(cls, pos, {})
            if not mob or not mob:IsValid() then return end
            last_spawned_mob = mob
            send_color(tier_label .. ": " .. mob_key .. " spawned!", 0, 1, 0)

            -- Read initial state
            local pl0, hp0, max0 = "?", "?", "?"
            pcall(function() pl0 = tostring(mob.PowerLevel) end)
            pcall(function()
                hp0 = tostring(mob.HealthComponent:GetAuthoritativeHealth())
                max0 = tostring(mob.HealthComponent:GetMaxHealth())
            end)
            ctf_log("SPAWN: PL=" .. pl0 .. " HP=" .. hp0 .. "/" .. max0)

            -- APPROACH 2: Write PowerLevel on the instance immediately
            if tonumber(pl0) ~= target_level then
                pcall(function() mob.PowerLevel = target_level end)
                local pl1 = "?"
                pcall(function() pl1 = tostring(mob.PowerLevel) end)
                ctf_log("INSTANCE WRITE: PL=" .. pl1)
            end

            -- Delayed re-read: check if HP updates after engine processes the PL change
            ExecuteWithDelay(250, function()
                pcall(function()
                    if not mob:IsValid() then
                        ctf_log("Mob gone before delayed check")
                        return
                    end
                    local pl2, hp2, max2 = "?", "?", "?"
                    pcall(function() pl2 = tostring(mob.PowerLevel) end)
                    pcall(function()
                        hp2 = tostring(mob.HealthComponent:GetAuthoritativeHealth())
                        max2 = tostring(mob.HealthComponent:GetMaxHealth())
                    end)
                    ctf_log("DELAYED 500ms: PL=" .. pl2 .. " HP=" .. hp2 .. "/" .. max2)
                    send_color("PL=" .. pl2 .. " HP=" .. hp2 .. "/" .. max2, 1, 1, 0)
                end)
            end)

            -- Second delayed check at 2 seconds
            ExecuteWithDelay(2000, function()
                pcall(function()
                    if not mob:IsValid() then return end
                    local pl3, hp3, max3 = "?", "?", "?"
                    pcall(function() pl3 = tostring(mob.PowerLevel) end)
                    pcall(function()
                        hp3 = tostring(mob.HealthComponent:GetAuthoritativeHealth())
                        max3 = tostring(mob.HealthComponent:GetMaxHealth())
                    end)
                    ctf_log("DELAYED 2s: PL=" .. pl3 .. " HP=" .. hp3 .. "/" .. max3)
                end)
            end)
        end)
    end)
end

------------------------------------------------------------
-- F11: Probe Windstep spell data + try to modify rune cost
------------------------------------------------------------
-- Numpad 3: Tier 1 mobs (wolf, garou berserker/druid/hunter, abyssal demon)
local tier1_idx = 0
local tier1_keys = {"wolf", "garou_hunter", "garou_druid", "garou_berserker", "abyssal_demon"}
RegisterKeyBind(Key.NUM_THREE, function()
    tier1_idx = (tier1_idx % #tier1_keys) + 1
    spawn_mob_with_level(tier1_keys[tier1_idx], TIER_POWER_LEVELS[1], "T1")
end)

-- Numpad 4: Tier 2 mobs (zogre, dragonwolf, skeletal archer, skeletal hoplite, spectral hoplite)
local tier2_idx = 0
local tier2_keys = {"dragonwolf", "skeletal_archer", "rotsworn_necromancer", "rotsworn_marauder", "zogre"}
RegisterKeyBind(Key.NUM_FOUR, function()
    tier2_idx = (tier2_idx % #tier2_keys) + 1
    spawn_mob_with_level(tier2_keys[tier2_idx], TIER_POWER_LEVELS[2], "T2")
end)

-- Numpad 5: Tier 3 mobs (blue dragon, black knight 2H, black knight ranged, mage of zamorak, hellhound)
local tier3_idx = 0
local tier3_keys = {"hellhound_fido", "blackknight_ranged", "mage_of_zamorak", "blackknight_2h", "dragon_blue"}
RegisterKeyBind(Key.NUM_FIVE, function()
    tier3_idx = (tier3_idx % #tier3_keys) + 1
    local mob_key = tier3_keys[tier3_idx]
    spawn_mob_with_level(mob_key, TIER_POWER_LEVELS[3], "T3")
end)

-- OLD Numpad 3: Spawn Dragonwolf (replaced by tier system above)
--[[ DISABLED
RegisterKeyBind(Key.NUM_THREE, function()
    local pos = get_player_pos()
    if not pos then return end
    pos.Z = pos.Z + 200
    send_color("Spawning Dragonwolf...", 1, 0.8, 0)

    -- Try to clone from a natural dragonwolf (inherits HP/level data)
    local cls = nil
    pcall(function()
        local instance = FindFirstOf("BP_AI_DragonWolf_Character_C")
        if instance and instance:IsValid() then
            cls = instance:GetClass()
        end
    end)
    if not cls then
        cls = cached_mob_classes["dragonwolf"] or StaticFindObject(MOB_CLASSES["dragonwolf"])
    end
    if not cls or not cls:IsValid() then
        -- Try LoadAsset (FutureMajorVersion plugin)
        pcall(function() LoadAsset("/FutureMajorVersion/Gameplay/AI/Wolf/DragonWolf/BP_AI_DragonWolf_Character") end)
        ExecuteWithDelay(1000, function()
            cls = StaticFindObject(MOB_CLASSES["dragonwolf"])
            if cls and cls:IsValid() then
                ExecuteInGameThread(function()
                    local world = FindFirstOf("World")
                    if world then pcall(function() world:SpawnActor(cls, pos, {}) end) end
                end)
                send_color("Dragonwolf spawned!", 0, 1, 0)
            else
                send_color("Dragonwolf not available!", 1, 0, 0)
            end
        end)
        return
    end

    ExecuteInGameThread(function()
        local world = FindFirstOf("World")
        if world then
            pcall(function()
                local mob = world:SpawnActor(cls, pos, {})
                if mob and mob:IsValid() then
                    -- Try to set power level
                    local level_props = {"PowerLevel", "Level", "AILevel", "CreatureLevel",
                                        "CharacterLevel", "SpawnLevel", "CombatLevel"}
                    for _, pname in ipairs(level_props) do
                        pcall(function()
                            local old = mob[pname]
                            if old and tonumber(tostring(old)) then
                                mob[pname] = 5
                                local new = mob[pname]
                                ctf_log("" .. pname .. ": " .. tostring(old) .. " → " .. tostring(new) .. "\n")
                                send_color(pname .. ": " .. tostring(old) .. "→" .. tostring(new), 1, 1, 0)
                            end
                        end)
                    end
                    send_color("Dragonwolf spawned!", 0, 1, 0)
                end
            end)
        end
    end)
end)
--]]

-- Numpad 6 and 7 now replaced by tier system (Numpad 3/4/5)
-- Keeping Numpad 7 for Abyssal Demon quick spawn

RegisterKeyBind(Key.NUM_SIX, function()
    garou_idx = (garou_idx % #garou_keys) + 1
    local mob_key = garou_keys[garou_idx]
    local pos = get_player_pos()
    if not pos then return end
    pos.Z = pos.Z + 200

    send_color("Spawning " .. garou_names[mob_key] .. "...", 1, 0.8, 0)
    local cls = get_mob_class(mob_key)
    if not cls then
        send_color(garou_names[mob_key] .. " not available!", 1, 0, 0)
        return
    end
    ExecuteInGameThread(function()
        local world = FindFirstOf("World")
        if world then
            pcall(function()
                local mob = world:SpawnActor(cls, pos, {})
                if mob and mob:IsValid() then
                    send_color(garou_names[mob_key] .. " spawned!", 0, 1, 0)
                end
            end)
        end
    end)
end)

-- Numpad 7: Spawn Abyssal Demon at player position + 200 height
RegisterKeyBind(Key.NUM_SEVEN, function()
    local pos = get_player_pos()
    if not pos then return end
    pos.Z = pos.Z + 200
    send_color("Spawning Abyssal Demon...", 1, 0.8, 0)
    local cls = get_mob_class("abyssal_demon")
    if not cls then
        send_color("Abyssal Demon not available!", 1, 0, 0)
        return
    end
    ExecuteInGameThread(function()
        local world = FindFirstOf("World")
        if world then
            pcall(function()
                local mob = world:SpawnActor(cls, pos, {})
                if mob and mob:IsValid() then
                    send_color("Abyssal Demon spawned!", 0, 1, 0)
                end
            end)
        end
    end)
end)

-- Numpad 8: Cache all nearby mob classes (safe — no AssetRegistry)
RegisterKeyBind(Key.NUM_EIGHT, function()
    send_color("Scanning for mob classes...", 1, 0.8, 0)
    local found = 0
    for key, mob_path in pairs(MOB_CLASSES) do
        if not cached_mob_classes[key] then
            local cls = StaticFindObject(mob_path)
            if cls and cls:IsValid() then
                cached_mob_classes[key] = cls
                found = found + 1
                send_color("  Cached: " .. key, 0, 1, 0)
            end
        else
            found = found + 1
        end
    end
    send_color("Cached " .. found .. "/6 mob classes", 0, 1, 0)
end)

-- Numpad 9: Test direct mob spawn (no template needed)
local direct_spawn_idx = 0
local direct_spawn_keys = {
    "wolf", "wolf_elite", "hellhound_fido", "hellhound_gnasher",
    "zogre", "dragon_green",
    "rotsworn_zombie", "rotsworn_warrior", "rotsworn_marauder", "rotsworn_necromancer",
    "blackknight_1h", "blackknight_2h", "blackknight_ranged",
    "zamorak_acolyte", "mage_of_zamorak", "abyssal_demon",
}

-- OLD NUM_NINE (disabled — now used for PvP setup)
--[[
RegisterKeyBind(Key.NUM_NINE_OLD, function()
    direct_spawn_idx = (direct_spawn_idx % #direct_spawn_keys) + 1
    local mob_key = direct_spawn_keys[direct_spawn_idx]
    local pos = get_player_pos()
    if not pos then return end
    -- Spawn 500 units in front
    pos.X = pos.X + 500

    send_color("Spawning: " .. mob_key, 1, 0.8, 0)
    local path = MOB_CLASSES[mob_key]
    if not path then send_color("No path for " .. mob_key, 1, 0, 0) return end

    -- Prioritize live instance (inherits HP/stats from natural mobs)
    local cls = get_mob_class(mob_key)

    if not cls then
        -- Try LoadAsset as last resort
        send_color("Loading " .. mob_key .. "...", 1, 0.8, 0)
        local package_path = path:match("(.+)%.")
        ExecuteInGameThread(function()
            pcall(function() LoadAsset(package_path) end)
        end)
        ExecuteWithDelay(1500, function()
            ExecuteInGameThread(function()
                cls = cache_mob_class(mob_key)
                if not cls then
                    send_color(mob_key .. " not available!", 1, 0, 0)
                    return
                end
                local world = FindFirstOf("World")
                if world then
                    pcall(function()
                        local mob = world:SpawnActor(cls, pos, {})
                        if mob and mob:IsValid() then
                            send_color(mob_key .. " spawned!", 0, 1, 0)
                        end
                    end)
                end
            end)
        end)
        return
    end

    -- Class available — spawn on game thread
    ExecuteInGameThread(function()
        -- Re-verify right before spawn
        local valid = false
        pcall(function() valid = cls:IsValid() end)
        if not valid then
            send_color(mob_key .. " class expired!", 1, 0, 0)
            cached_mob_classes[mob_key] = nil
            return
        end
        local world = FindFirstOf("World")
        if world then
            pcall(function()
                local mob = world:SpawnActor(cls, pos, {})
                if mob and mob:IsValid() then
                    send_color(mob_key .. " spawned!", 0, 1, 0)
                end
            end)
        end
    end)
end)
]]

--[[ OLD WINDSTEP MANUAL BLOCK (now auto-blocked on load)
RegisterKeyBind(Key.F11_OLD, function()
    send_color("Blocking Windstep...", 1, 0.8, 0)
    print("\n[CTF] === BLOCK WINDSTEP ===\n")

    local usd = StaticFindObject("/Game/Gameplay/UtilityMagic/PerkSpells/Windstep/USD_Windstep.USD_Windstep")
    if not usd or not usd:IsValid() then
        send_color("USD_Windstep not found!", 1, 0, 0)
        return
    end

    -- Read current cooldown
    local current = nil
    pcall(function() current = usd.CooldownDuration end)
    ctf_log("Current CooldownDuration: " .. tostring(current) .. "\n")
    send_color("Current cooldown: " .. tostring(current), 1, 1, 0)

    -- Set cooldown to 9999
    pcall(function() usd.CooldownDuration = 9999.0 end)

    -- Also try to set rune cost properties
    local rune_cost_props = {
        "RuneCost", "RuneCosts", "Cost", "SpellCost", "CastCost",
        "RequiredRuneCount", "RuneAmount", "AirRuneCost",
    }
    for _, pname in ipairs(rune_cost_props) do
        pcall(function()
            local val = usd[pname]
            if val ~= nil and tonumber(tostring(val)) then
                local old = tostring(val)
                usd[pname] = 9999
                local new = tostring(usd[pname])
                ctf_log("" .. pname .. ": " .. old .. " → " .. new .. "\n")
                send_color(pname .. ": " .. old .. " → " .. new, 1, 1, 0)
            end
        end)
    end

    -- Verify cooldown changed
    local new_val = nil
    pcall(function() new_val = usd.CooldownDuration end)
    ctf_log("New CooldownDuration: " .. tostring(new_val) .. "\n")

    if new_val and tonumber(tostring(new_val)) == 9999.0 then
        send_color("WINDSTEP BLOCKED! Cooldown set to 9999s", 0, 1, 0)
    else
        send_color("Failed to change cooldown. Value: " .. tostring(new_val), 1, 0, 0)
    end

    -- Also list all spell data we can find
    ctf_log("--- All spells ---\n")
    local spells = {
        {"Windstep", "/Game/Gameplay/UtilityMagic/PerkSpells/Windstep/USD_Windstep.USD_Windstep"},
        {"Surge", "/Game/Gameplay/UtilityMagic/PerkSpells/Surge/USD_Surge.USD_Surge"},
        {"SnareTrap", "/Game/Gameplay/UtilityMagic/PerkSpells/SnareTrap/USD_SnareTrap.USD_SnareTrap"},
        {"TempestShield", "/Game/Gameplay/UtilityMagic/PerkSpells/TempestShield/USD_TempestShield.USD_TempestShield"},
        {"EnchantWeapon_Air", "/Game/Gameplay/UtilityMagic/PerkSpells/EnchantWeapon/USD_EnchantWeapon_Air.USD_EnchantWeapon_Air"},
        {"EnchantWeapon_Fire", "/Game/Gameplay/UtilityMagic/PerkSpells/EnchantWeapon/USD_EnchantWeapon_Fire.USD_EnchantWeapon_Fire"},
    }
    for _, s in ipairs(spells) do
        local obj = StaticFindObject(s[2])
        if obj and obj:IsValid() then
            local cd = nil
            pcall(function() cd = obj.CooldownDuration end)
            ctf_log("" .. s[1] .. ": CD=" .. tostring(cd) .. "\n")
            send_color(s[1] .. " CD=" .. tostring(cd), 0, 1, 0.5)
        else
            send_color(s[1] .. " not found", 1, 0, 0)
        end
    end
end)

------------------------------------------------------------
-- F12: Set all skills to 99
------------------------------------------------------------
-- Numpad debug mode selectors
-- NUM_ZERO now used for PvP kill simulation (see above)
-- Debug equip mode selectors REMOVED (were clashing with Numpad 3/4/5 mob spawners)

--[[ OLD WINDSTEP PROBE (disabled)
RegisterKeyBind(Key.F12_OLD, function()
    send_color("Enumerating ALL USD_Windstep properties...", 1, 0.8, 0)
    print("\n[CTF] === USD PROPERTY ENUMERATION ===\n")

    local usd = StaticFindObject("/Game/Gameplay/UtilityMagic/PerkSpells/Windstep/USD_Windstep.USD_Windstep")
    if not usd or not usd:IsValid() then
        send_color("USD_Windstep not found!", 1, 0, 0)
        return
    end

    -- Use ForEachProperty on the class to enumerate ALL real properties
    local cls = usd:GetClass()
    if not cls or not cls:IsValid() then
        send_color("Can't get class!", 1, 0, 0)
        return
    end

    ctf_log("Class: " .. cls:GetFullName() .. "\n")
    local prop_count = 0

    cls:ForEachProperty(function(prop)
        prop_count = prop_count + 1
        local name = "?"
        local ptype = "?"
        -- Try multiple ways to get the property name
        pcall(function() name = prop:GetFName():ToString() end)
        if name == "?" then pcall(function() name = prop:GetName() end) end
        if name == "?" then pcall(function() name = prop:GetFullName() end) end
        if name == "?" then pcall(function() name = tostring(prop:GetFName()) end) end
        -- Try to get the property type
        pcall(function() ptype = prop:GetClass():GetFName():ToString() end)
        if ptype == "?" then pcall(function() ptype = prop:GetClass():GetName() end) end
        ctf_log("PROP #" .. prop_count .. ": " .. name .. " [" .. ptype .. "]\n")
        send_color("#" .. prop_count .. " " .. name .. " [" .. ptype .. "]", 1, 1, 0)

        -- Try to read the value
        pcall(function()
            local val = usd[name]
            if val ~= nil then
                local str = tostring(val)
                local num = tonumber(str)
                if num then
                    ctf_log("  Value: " .. str .. "\n")
                elseif str == "true" or str == "false" then
                    ctf_log("  Value: " .. str .. "\n")
                elseif string.find(str, "TArray") then
                    local count = 0
                    pcall(function() count = val:GetArrayNum() end)
                    ctf_log("  Value: TArray(" .. count .. ")\n")
                else
                    ctf_log("  Value: " .. str .. "\n")
                end
            end
        end)
    end)

    ctf_log("Total properties: " .. prop_count .. "\n")

    -- Probe the OwningPerk directly
    ctf_log("--- Probing OwningPerk ---\n")
    local perk = nil
    pcall(function() perk = usd.OwningPerk end)

    if not perk then
        -- Try StaticFindObject directly
        perk = StaticFindObject("/Game/Gameplay/Character/Player/PerksV2/Runecrafting/PerkV2_Runecraftng_Windstep.PerkV2_Runecraftng_Windstep")
    end

    if perk and perk:IsValid() then
        pcall(function() ctf_log("Perk: " .. perk:GetFullName() .. "\n") end)
        send_color("Perk found!", 0, 1, 0)

        -- Enumerate perk properties
        pcall(function()
            local perk_cls = perk:GetClass()
            ctf_log("Perk class: " .. perk_cls:GetFullName() .. "\n")

            local count = 0
            perk_cls:ForEachProperty(function(prop)
                count = count + 1
                local name = "?"
                local ptype = "?"
                pcall(function() name = prop:GetFName():ToString() end)
                pcall(function() ptype = prop:GetClass():GetFName():ToString() end)
                ctf_log("Perk #" .. count .. ": " .. name .. " [" .. ptype .. "]\n")

                -- Read value for interesting types
                pcall(function()
                    local val = perk[name]
                    if val ~= nil then
                        local str = tostring(val)
                        local num = tonumber(str)
                        if num or str == "true" or str == "false" or string.find(str, "TArray") then
                            ctf_log("  → " .. str .. "\n")
                            send_color("  " .. name .. " = " .. str, 1, 1, 0)
                        end
                    end
                end)
            end)
            ctf_log("Total perk props: " .. count .. "\n")
            send_color("Perk props: " .. count, 0, 1, 0)
        end)
    else
        send_color("Perk not found!", 1, 0, 0)
    end

    -- Probe PerkModules array
    pcall(function()
        local modules = perk.PerkModules
        if modules then
            local count = 0
            pcall(function() count = modules:GetArrayNum() end)
            ctf_log("PerkModules count: " .. count .. "\n")
            send_color("PerkModules: " .. count .. " entries", 0, 1, 0)

            -- Iterate each module
            for i = 1, count do
                pcall(function()
                    local mod = modules[i]
                    if mod then
                        local mod_name = "?"
                        pcall(function() mod_name = mod:GetFullName() end)
                        ctf_log("Module " .. i .. ": " .. mod_name .. "\n")
                        send_color("[Mod " .. i .. "] " .. mod_name, 1, 1, 0)

                        -- Enumerate module properties
                        pcall(function()
                            local mod_cls = mod:GetClass()
                            mod_cls:ForEachProperty(function(prop)
                                local pname = "?"
                                local ptype = "?"
                                pcall(function() pname = prop:GetFName():ToString() end)
                                pcall(function() ptype = prop:GetClass():GetFName():ToString() end)
                                ctf_log("  " .. pname .. " [" .. ptype .. "]\n")

                                pcall(function()
                                    local val = mod[pname]
                                    if val ~= nil then
                                        local str = tostring(val)
                                        local num = tonumber(str)
                                        if num or str == "true" or str == "false" then
                                            ctf_log("    = " .. str .. "\n")
                                            send_color("    " .. pname .. " = " .. str, 1, 0.8, 0)
                                        elseif string.find(str, "TArray") then
                                            local ac = 0
                                            pcall(function() ac = val:GetArrayNum() end)
                                            ctf_log("    = TArray(" .. ac .. ")\n")
                                            send_color("    " .. pname .. " = TArray(" .. ac .. ")", 1, 0.8, 0)
                                        end
                                    end
                                end)
                            end)
                        end)
                    end
                end)
            end
        end
    end)

    send_color("Done. Check log.", 0, 1, 0)
end)
--]]

------------------------------------------------------------
-- Trinkets (via F9 now combined with runes)
------------------------------------------------------------
RegisterKeyBind(Key.F9, function()
    if not selected_class then send_color("Select a class first!", 1, 0, 0) return end
    unlock_inv()
    add_item(TRINKETS[selected_class])
    ExecuteWithDelay(300, function()
        local c = FindFirstOf("BP_PlayerController_C")
        if c then
            local inv = c.BP_Components_Inventory
            local invCtrl = c.BP_Components_InventoryController
            for i = 0, 12 do pcall(function() invCtrl:UseItemFromInventory(inv, i) end) end
        end
    end)
    send_color(">> TRINKET AWARDED!", 1, 0.8, 0)
end)

------------------------------------------------------------
-- F12: PvP Setup — enable hitsplats, hide nametags/map icons
------------------------------------------------------------
RegisterKeyBind(Key.NUM_NINE, function()
    ctf_log("=== PVP SETUP ===")
    send_color("Setting up PvP...", 1, 0.8, 0)

    pcall(function()
        local all_players = FindAllOf("BP_PlayerCharacter_C")
        if not all_players then return end

        for _, player in ipairs(all_players) do
            pcall(function()
                if not player or not player:IsValid() then return end

                -- Enable damage floaties/hitsplats
                pcall(function()
                    local dmg = player.BP_Components_PlayerDamage
                    if dmg and dmg:IsValid() then
                        pcall(function() dmg:SetCanShowDamageFloaties(true) end)
                        pcall(function() dmg.bShowDamageFloaties = true end)
                        pcall(function() dmg:SetCanTakeDamage(true) end)
                        pcall(function() dmg.bCanTakeDamage = true end)
                        -- Enable PvP
                        pcall(function() dmg.bIsPvpEnabled = true end)
                        -- Enable XP from damage
                        pcall(function() dmg.bAwardsXPThroughPlayerDamageComponent = true end)
                        ctf_log("Damage floaties + PvP enabled for player")
                    end
                end)

                -- Hide nameplate — try both BP and C++ paths
                pcall(function()
                    -- BP path
                    local np = player.BP_Player_Nameplate
                    if np and np:IsValid() then
                        pcall(function() np:SetVisibility(false) end)
                        pcall(function() np:SetHiddenInGame(true) end)
                        pcall(function() np:Deactivate() end)
                        pcall(function() np:SetActive(false) end)
                        pcall(function() np:DestroyComponent() end)
                    end
                    -- C++ path
                    local np2 = player.PlayerNameplateComponent
                    if np2 and np2:IsValid() then
                        pcall(function() np2:SetVisibility(false) end)
                        pcall(function() np2:SetHiddenInGame(true) end)
                        pcall(function() np2:Deactivate() end)
                        pcall(function() np2:DestroyComponent() end)
                        -- Probe properties
                        pcall(function()
                            local cls = np2:GetClass()
                            ctf_log("Nameplate C++ class: " .. cls:GetFullName())
                            cls:ForEachProperty(function(prop)
                                pcall(function()
                                    local pn = prop:GetFName():ToString()
                                    local pt = prop:GetClass():GetFName():ToString()
                                    ctf_log("  NP." .. pn .. " [" .. pt .. "]")
                                end)
                            end)
                        end)
                    end
                    ctf_log("Nameplate hidden")
                end)

                -- Try to find nameplate via class
                pcall(function()
                    local cls = player:GetClass()
                    cls:ForEachProperty(function(prop)
                        pcall(function()
                            local pn = prop:GetFName():ToString()
                            if pn:find("Name") or pn:find("Plate") or pn:find("Label")
                               or pn:find("Map") or pn:find("Compass") or pn:find("Presence")
                               or pn:find("Icon") or pn:find("Marker") or pn:find("Ping") then
                                ctf_log("  FOUND: " .. pn .. " [" .. prop:GetClass():GetFName():ToString() .. "]")
                            end
                        end)
                    end)
                end)

                -- Hide map presence/compass icon — probe and disable
                pcall(function()
                    local presence = player.BP_Components_Presence_MasterCapture
                    if presence and presence:IsValid() then
                        -- Try every disable method
                        pcall(function() presence:Deactivate() end)
                        pcall(function() presence:SetComponentTickEnabled(false) end)
                        pcall(function() presence:SetActive(false) end)
                        pcall(function() presence:SetVisibility(false) end)
                        pcall(function() presence:SetHiddenInGame(true) end)
                        pcall(function() presence:DestroyComponent() end)

                        -- Hide compass by shrinking capture area + clearing materials
                        pcall(function() presence.CaptureAreaSize = 0.0 end)
                        pcall(function() presence.CaptureDelta = 0.0 end)
                        -- Clear the player drawing material
                        pcall(function() presence.DrawPlayersMID = nil end)
                        pcall(function() presence.DrawEntitiesMID = nil end)
                        ctf_log("Presence/map icon disabled")
                    else
                        ctf_log("No Presence component found")
                    end
                end)

                -- Try MapView component
                pcall(function()
                    local mv = player.MapView
                    if mv and mv:IsValid() then
                        pcall(function() mv:SetVisibility(false) end)
                        pcall(function() mv:SetHiddenInGame(true) end)
                        pcall(function() mv:Deactivate() end)
                        ctf_log("MapView hidden")
                    else
                        ctf_log("No MapView found")
                    end
                end)
            end)
        end
    end)

    send_color("PvP setup complete! Hitsplats + hidden nametags/map", 0, 1, 0)
    ctf_log("=== PVP SETUP DONE ===")
end)

------------------------------------------------------------
-- DEATH HOOK
------------------------------------------------------------
local death_hook_registered = false
local function register_death_hook()
    if death_hook_registered then return end
    death_hook_registered = true
    RegisterHook("/Game/Gameplay/Character/Player/BP_PlayerCharacter.BP_PlayerCharacter_C:OnPlayerDeath", function(self)
        local victim = self:get()
        if not victim or not victim:IsValid() then return end

        -- === PVP KILL ATTRIBUTION ===
        -- Read killer from LastDamageEvent (same approach as mob kills)
        local killer_pid = nil
        local victim_pid = nil
        pcall(function()
            victim_pid = victim:GetInstigatorController().PlayerState.PlayerId
        end)

        pcall(function()
            local dmg = victim.BP_Components_PlayerDamage
            if dmg and dmg:IsValid() then
                local lde = dmg.LastDamageEvent
                if lde then
                    local ins = lde.Instigator
                    if ins then
                        local valid = false
                        pcall(function() valid = ins:IsValid() end)
                        if valid then
                            pcall(function()
                                local ctrl = ins:GetInstigatorController()
                                if ctrl and ctrl:IsValid() then
                                    killer_pid = ctrl.PlayerState.PlayerId
                                end
                            end)
                            -- Log the kill
                            local killer_name = "?"
                            pcall(function() killer_name = ins:GetFullName() end)
                            ctf_log("PVP DEATH: P" .. tostring(victim_pid) .. " killed by " .. killer_name)
                            if killer_pid then
                                -- Check friendly fire BEFORE counting kill
                                if killer_name:find("PlayerCharacter") then
                                    local k_team = get_player_team(killer_pid)
                                    local v_team = get_player_team(victim_pid)
                                    if k_team and v_team and k_team == v_team then
                                        ctf_log("FRIENDLY FIRE BLOCKED: P" .. killer_pid .. " -> P" .. tostring(victim_pid) .. " (both " .. k_team .. ")")
                                        -- Heal victim back immediately
                                        ExecuteWithDelay(500, function()
                                            ExecuteInGameThread(function()
                                                pcall(function()
                                                    if victim and victim:IsValid() then
                                                        local hp = victim.BP_Components_Health
                                                        if hp and hp:IsValid() then
                                                            hp:SetHealth(hp:GetMaxHealth())
                                                        end
                                                        local pos = victim:K2_GetActorLocation()
                                                        victim:K2_SetActorLocation({X=pos.X, Y=pos.Y, Z=pos.Z}, false, {}, true)
                                                        pcall(function() victim:PlayRespawnVFX() end)
                                                        send_team_msg(victim, "Friendly fire! Teammates can't kill you.", 1, 1, 0)
                                                    end
                                                end)
                                            end)
                                        end)
                                        return  -- skip ALL kill processing
                                    end
                                end

                                ctf_log("PVP KILL: P" .. killer_pid .. " killed P" .. tostring(victim_pid))
                                -- Check if killer is a player (not a mob)
                                if killer_name:find("PlayerCharacter") then
                                    -- Get player names
                                    local k_name = "Player " .. killer_pid
                                    local v_name = "Player " .. tostring(victim_pid)

                                    -- Get player display names
                                    local function get_player_name(pawn)
                                        local name = nil
                                        pcall(function()
                                            local ctrl = pawn:GetInstigatorController()
                                            if ctrl and ctrl:IsValid() then
                                                local ps = ctrl.PlayerState
                                                if ps then
                                                    -- GetPlayerName returns FString — call :ToString()
                                                    pcall(function()
                                                        local n = ps:GetPlayerName()
                                                        if n then
                                                            local s = n:ToString()
                                                            if s and s ~= "" then name = s end
                                                        end
                                                    end)
                                                    -- Fallback: PlayerNamePrivate
                                                    if not name then
                                                        pcall(function()
                                                            local n = ps.PlayerNamePrivate
                                                            if n then
                                                                local s = n:ToString()
                                                                if s and s ~= "" then name = s end
                                                            end
                                                        end)
                                                    end
                                                end
                                            end
                                        end)
                                        return name
                                    end

                                    pcall(function()
                                        local n = get_player_name(ins)
                                        if n then k_name = n end
                                    end)
                                    pcall(function()
                                        local n = get_player_name(victim)
                                        if n then v_name = n end
                                    end)

                                    -- Send kill feed with team colors
                                    local kd = player_data[killer_pid]
                                    local vd = player_data[victim_pid]
                                    local k_team = kd and kd.team or nil
                                    local v_team = vd and vd.team or nil

                                    -- Send colored messages to all players
                                    pcall(function()
                                        local all = FindAllOf("BP_PlayerCharacter_C")
                                        if all then
                                            for _, p in ipairs(all) do
                                                pcall(function()
                                                    local ctrl = p:GetInstigatorController()
                                                    if ctrl and ctrl:IsValid() then
                                                        -- Killer name in killer's team color
                                                        local kc = k_team and teams[k_team].color or {R=1,G=1,B=1,A=1}
                                                        ctrl.PlayerChat:Client_ReceiveChatMessage({
                                                            PlayerId=0, Color=kc, PlayerName="",
                                                            MessageBody=k_name .. " defeated " .. v_name,
                                                        })
                                                    end
                                                end)
                                            end
                                        end
                                    end)
                                    ctf_log("KILL FEED: " .. k_name .. " defeated " .. v_name)
                                    -- Track PvP kills + progression
                                    if player_data[killer_pid] then
                                        local pd = player_data[killer_pid]
                                        pd.kills = pd.kills + 1
                                        local kills = pd.kills
                                        local killer_team = pd.team
                                        local team_pvp = 0
                                        if killer_team then
                                            teams[killer_team].pvp_kills = teams[killer_team].pvp_kills + 1
                                            team_pvp = teams[killer_team].pvp_kills
                                        end
                                        ctf_log("PVP: P" .. killer_pid .. " kills=" .. kills .. " team_pvp=" .. team_pvp)

                                        -- Find killer's player ref for equip
                                        local killer_ref = nil
                                        pcall(function()
                                            local all_players = FindAllOf("BP_PlayerCharacter_C")
                                            if all_players then
                                                for _, kp in ipairs(all_players) do
                                                    pcall(function()
                                                        if kp and kp:IsValid() then
                                                            local kpid = kp:GetInstigatorController().PlayerState.PlayerId
                                                            if kpid == killer_pid then killer_ref = kp end
                                                        end
                                                    end)
                                                end
                                            end
                                        end)

                                        -- Skip gear upgrades if carrying flag
                                        local defer_upgrade = is_carrying_flag(killer_pid)
                                        if defer_upgrade then
                                            ctf_log("Killer P" .. killer_pid .. " carrying flag — upgrade deferred")
                                        end

                                        -- === SPECIALIZATION: 3 personal kills ===
                                        if kills == 3 and not pd.specialized and pd.class and not defer_upgrade then
                                            pd.specialized = true
                                            send_to_all(k_name .. " SPECIALIZED as " .. CLASS_DISPLAY[pd.class] .. "!", 0, 1, 0)
                                            ctf_log("SPECIALIZED: P" .. killer_pid .. " as " .. pd.class)
                                            if killer_ref and killer_team then
                                                equip_class_for(killer_ref, killer_team, pd.class, teams[killer_team].armor_tier, 1)
                                                -- Give runes after equip
                                                ExecuteWithDelay(2000, function()
                                                    pcall(function()
                                                        if killer_ref and killer_ref:IsValid() then
                                                            local ctrl = killer_ref:GetInstigatorController()
                                                            if ctrl and ctrl:IsValid() and CLASS_RUNES[pd.class] then
                                                                for _, r in ipairs(CLASS_RUNES[pd.class]) do
                                                                    add_item_for(ctrl, r[1], r[2])
                                                                end
                                                            end
                                                        end
                                                    end)
                                                end)
                                            end
                                        end

                                        -- === TRINKET: 12 personal kills ===
                                        if kills == 12 and pd.class and not defer_upgrade then
                                            local trinket_path = TRINKETS[pd.class]
                                            if trinket_path and killer_ref then
                                                send_to_all(k_name .. " earned a TRINKET!", 1, 0.8, 0)
                                                pcall(function()
                                                    local ctrl = killer_ref:GetInstigatorController()
                                                    if ctrl and ctrl:IsValid() then
                                                        add_to_loadout_for(ctrl, trinket_path)
                                                    end
                                                end)
                                            end
                                        end

                                        -- === WEAPON TIERS: 12/24/36 team PvP kills ===
                                        if killer_team and not defer_upgrade then
                                            local new_weapon_tier = nil
                                            if team_pvp == 12 then
                                                new_weapon_tier = 2
                                                send_to_all(killer_team:upper() .. " TEAM: 12 kills! Weapons → T4!", 0, 1, 1)
                                            elseif team_pvp == 24 then
                                                new_weapon_tier = 3
                                                send_to_all(killer_team:upper() .. " TEAM: 24 kills! Weapons → T5!", 0, 1, 1)
                                            elseif team_pvp == 36 then
                                                new_weapon_tier = 4
                                                send_to_all(killer_team:upper() .. " TEAM: 36 kills! Weapons → T6 (MAX)!", 1, 0.8, 0)
                                            end

                                            if new_weapon_tier then
                                                -- Upgrade weapons for ALL players on this team
                                                local delay = 0
                                                for _, tp in ipairs(teams[killer_team].players) do
                                                    local tpd = player_data[tp.id]
                                                    if tpd and tpd.class and tpd.specialized then
                                                        local tpid = tp.id
                                                        local tcls = tpd.class
                                                        local wt = new_weapon_tier
                                                        ExecuteWithDelay(delay, function()
                                                            pcall(function()
                                                                local all_p = FindAllOf("BP_PlayerCharacter_C")
                                                                if all_p then
                                                                    for _, pl in ipairs(all_p) do
                                                                        pcall(function()
                                                                            if pl and pl:IsValid() then
                                                                                local ppid = pl:GetInstigatorController().PlayerState.PlayerId
                                                                                if ppid == tpid then
                                                                                    local ctrl = pl:GetInstigatorController()
                                                                                    if ctrl and ctrl:IsValid() then
                                                                                        -- Clear inventory, give new weapons
                                                                                        ctrl.BP_Components_Inventory.bAllowRemoves = true
                                                                                        ctrl.BP_Components_Inventory.bAllowAdds = true
                                                                                        ctrl.BP_Components_Inventory:ClearInventory()
                                                                                        ExecuteWithDelay(300, function()
                                                                                            ExecuteInGameThread(function()
                                                                                                pcall(function()
                                                                                                    local weapons = CLASS_WEAP[tcls] and CLASS_WEAP[tcls][wt] or {}
                                                                                                    for _, w in ipairs(weapons) do
                                                                                                        add_to_loadout_for(ctrl, w)
                                                                                                    end
                                                                                                    if CLASS_AMMO[tcls] then
                                                                                                        add_item_for(ctrl, ARCHER_AMMO and ARCHER_AMMO[wt] or CLASS_AMMO[tcls], 50)
                                                                                                    end
                                                                                                end)
                                                                                            end)
                                                                                        end)
                                                                                    end
                                                                                end
                                                                            end
                                                                        end)
                                                                    end
                                                                end
                                                            end)
                                                        end)
                                                        delay = delay + 1500
                                                    elseif tpd and tpd.class and not tpd.specialized and team_pvp >= 12 then
                                                        -- Auto-promote unspecialized at 12 team kills
                                                        tpd.specialized = true
                                                        send_to_all("Auto-promoted: " .. (CLASS_DISPLAY[tpd.class] or "?"), 1, 0.8, 0)
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end)

        -- === FRIENDLY FIRE PREVENTION ===
        -- If killer and victim are on the same team, revive instantly
        if killer_pid and victim_pid then
            local k_team = get_player_team(killer_pid)
            local v_team = get_player_team(victim_pid)
            if k_team and v_team and k_team == v_team then
                ctf_log("FRIENDLY FIRE BLOCKED: P" .. killer_pid .. " -> P" .. victim_pid .. " (both " .. k_team .. ")")
                -- Heal victim back to full immediately
                ExecuteWithDelay(500, function()
                    ExecuteInGameThread(function()
                        pcall(function()
                            if victim and victim:IsValid() then
                                local hp = victim.BP_Components_Health
                                if hp and hp:IsValid() then
                                    local max = hp:GetMaxHealth()
                                    hp:SetHealth(max)
                                    ctf_log("Healed friendly fire victim P" .. victim_pid .. " to " .. max)
                                end
                                -- Respawn at current position (not team spawn)
                                local pos = victim:K2_GetActorLocation()
                                victim:K2_SetActorLocation({X=pos.X, Y=pos.Y, Z=pos.Z}, false, {}, true)
                                pcall(function() victim:PlayRespawnVFX() end)
                                send_team_msg(victim, "Friendly fire! Teammates can't kill you.", 1, 1, 0)
                            end
                        end)
                    end)
                end)
                return  -- skip death tracking and respawn timer
            end
        end

        -- Track victim death (only for enemy kills)
        if victim_pid and player_data[victim_pid] then
            player_data[victim_pid].deaths = player_data[victim_pid].deaths + 1
        end

        -- Flag carrier death: return flag to base
        if victim_pid then
            flag_carrier_died(victim_pid)
        end

        -- Respawn logic
        if not match_active then return end
        local victim_team = get_player_team(victim_pid)
        local spawn = get_random_spawn(victim_team or selected_team)
        if not spawn then return end

        -- Send death message + make invulnerable during respawn
        pcall(function()
            if victim and victim:IsValid() then
                send_team_msg(victim, "You died! Respawning in 15 seconds...", 1, 0.3, 0.3)
                -- Make invulnerable at bed
                local dmg = victim.BP_Components_PlayerDamage
                if dmg and dmg:IsValid() then
                    dmg.bCanTakeDamage = false
                end
            end
        end)

        ExecuteWithDelay(10000, function()
            local count = 5
            LoopAsync(1000, function()
                if not is_world_valid() then return true end
                if count > 0 then
                    pcall(function()
                        if victim and victim:IsValid() then
                            send_team_msg(victim, "Respawning in " .. count .. "...", 1, 0.5, 0)
                        end
                    end)
                    count = count - 1
                    return false
                else
                    ExecuteInGameThread(function()
                        if not match_active then return end
                        -- Pick a fresh random spawn at respawn time
                        local rs = get_random_spawn(victim_team or selected_team)
                        local yaw = team_spawn_yaw[victim_team or selected_team] or 0
                        pcall(function()
                            if victim and victim:IsValid() then
                                victim:K2_SetActorLocationAndRotation(
                                    {X=rs.X, Y=rs.Y, Z=rs.Z},
                                    {Pitch=0, Yaw=yaw, Roll=0},
                                    false, {}, true)
                                snap_camera(victim, yaw)
                                pcall(function() victim:PlayRespawnVFX() end)
                                -- Re-enable damage
                                pcall(function()
                                    local dmg = victim.BP_Components_PlayerDamage
                                    if dmg and dmg:IsValid() then
                                        dmg.bCanTakeDamage = true
                                    end
                                end)
                                send_team_msg(victim, "Respawned! Back in the fight!", 0, 1, 0)

                                -- Re-equip gear immediately after respawn
                                local vpd = player_data[victim_pid]
                                if vpd and vpd.team and vpd.class and vpd.specialized then
                                    local vteam = vpd.team
                                    local vcls = vpd.class
                                    local va_tier = teams[vteam] and teams[vteam].armor_tier or 2
                                    local vteam_pvp = teams[vteam] and teams[vteam].pvp_kills or 0
                                    local vw_tier = 1
                                    if vteam_pvp >= 36 then vw_tier = 4
                                    elseif vteam_pvp >= 24 then vw_tier = 3
                                    elseif vteam_pvp >= 12 then vw_tier = 2 end
                                    equip_class_for(victim, vteam, vcls, va_tier, vw_tier)
                                elseif vpd and vpd.team then
                                    equip_base_kit_for(victim, vpd.team)
                                end
                            end
                        end)
                    end)
                    return true
                end
            end)
        end)
    end)
    ctf_log("Death hook registered\n")
    -- Also register AI kill tracking hook
    start_pve_kill_tracking()
    ctf_log("AI kill tracking registered\n")
end

-- OLD DAMAGE TRACKING (moved to top of file for early registration)
--[[ DISABLED
    if not _G.mob_last_attacker then _G.mob_last_attacker = {} end

    local function try_extract_player_id(param, label)
        if not param then return nil end
        local pid = nil
        pcall(function()
            local obj = param:get()
            if obj and obj:IsValid() then
                -- Direct PlayerState check (if it's a controller)
                pcall(function()
                    local ps = obj.PlayerState
                    if ps then pid = ps.PlayerId end
                end)
                -- Try GetInstigatorController (if it's a pawn/projectile)
                if not pid then
                    pcall(function()
                        local ctrl = obj:GetInstigatorController()
                        if ctrl and ctrl:IsValid() then
                            local ps = ctrl.PlayerState
                            if ps then pid = ps.PlayerId end
                        end
                    end)
                end
                -- Try Instigator (actor property)
                if not pid then
                    pcall(function()
                        local ins = obj.Instigator
                        if ins and ins:IsValid() then
                            local ctrl = ins:GetInstigatorController()
                            if ctrl then
                                local ps = ctrl.PlayerState
                                if ps then pid = ps.PlayerId end
                            end
                        end
                    end)
                end
            end
        end)
        return pid
    end

    local dmg_hooks = {
        "/Script/Dominion.DamageComponent:BP_OnDamageReceived",
        "/Script/Dominion.DamageComponent:BP_OnAnyDamageReceived",
        "/Script/Dominion.DamageComponent:BP_OnPointDamageReceived",
        "/Script/Dominion.DamageComponent:HandleOnDamageCached",
        "/Script/Dominion.DamageComponent:BP_OnWillReceiveDamage",
        "/Game/Gameplay/AI/Components/BP_AiDamageComponent.BP_AiDamageComponent_C:BP_OnDamageReceived",
        "/Game/Gameplay/AI/Components/BP_AiDamageComponent.BP_AiDamageComponent_C:BP_OnAnyDamageReceived",
        "/Script/Dominion.PlayerMeleeAttackComponent:Multicast_SendDamageCacheData",
    }
    for _, hook_path in ipairs(dmg_hooks) do
        local ok = pcall(function()
            RegisterHook(hook_path, function(self, p1, p2, p3, p4, p5)
                pcall(function()
                    local comp = self:get()
                    if not comp or not comp:IsValid() then return end

                    -- Get the owning actor (mob or player)
                    local owner = nil
                    pcall(function() owner = comp:GetOwner() end)

                    local mob_addr = nil
                    local pid = nil

                    -- Check all params for player ID
                    for i, param in ipairs({p1, p2, p3, p4, p5}) do
                        if param and not pid then
                            pid = try_extract_player_id(param, "p" .. i)
                        end
                    end

                    -- If this is on a mob's damage component, store the attacker
                    if owner then
                        pcall(function()
                            mob_addr = tostring(owner:GetAddress())
                        end)
                    end

                    if mob_addr and pid then
                        _G.mob_last_attacker[mob_addr] = pid
                    end

                    -- Log first few hits for debugging
                    local short = hook_path:match("([^:]+)$") or hook_path
                    if pid then
                        ctf_log("DMG HIT: " .. short .. " -> P" .. pid .. " on " .. tostring(mob_addr))
                    else
                        -- Log params to see what we get
                        local params = {}
                        for i, p in ipairs({p1, p2, p3, p4, p5}) do
                            if p then
                                local str = tostring(p)
                                pcall(function() str = p:get():GetFullName() end)
                                table.insert(params, "p" .. i .. "=" .. str)
                            end
                        end
                        if #params > 0 then
                            ctf_log("DMG RAW: " .. short .. " | " .. table.concat(params, " | "))
                        end
                    end
                end)
            end)
            ctf_log("DMG HOOK OK: " .. hook_path)
        end)
        if not ok then
            ctf_log("DMG HOOK FAIL: " .. hook_path)
        end
    end
    ctf_log("=== DAMAGE HOOKS DONE ===")
--]]

------------------------------------------------------------
-- TEAM-AWARE AI KILL TRACKING
-- Attributes kills to the nearest player's team
------------------------------------------------------------
------------------------------------------------------------
-- F1: Scan all connected players — IDs, names, positions, HP
------------------------------------------------------------
RegisterKeyBind(Key.F1, function()
    ctf_log("=== PLAYER SCAN ===")
    send_color("Scanning players...", 0, 1, 1)

    pcall(function()
        local all_players = FindAllOf("BP_PlayerCharacter_C")
        if not all_players then
            send_color("No players found!", 1, 0, 0)
            ctf_log("No players found")
            return
        end

        ctf_log("Found " .. #all_players .. " player(s)")
        send_color("Players: " .. #all_players, 0, 1, 0)

        for i, player in ipairs(all_players) do
            pcall(function()
                if not player or not player:IsValid() then return end

                local info = "P" .. i .. ":"
                -- Position
                pcall(function()
                    local pos = player:K2_GetActorLocation()
                    info = info .. string.format(" Pos(%.0f,%.0f,%.0f)", pos.X, pos.Y, pos.Z)
                end)
                -- HP
                pcall(function()
                    local hp = player.BP_Components_Health
                    if hp and hp:IsValid() then
                        local cur = hp:GetAuthoritativeHealth()
                        local max = hp:GetMaxHealth()
                        info = info .. string.format(" HP=%.0f/%.0f", cur, max)
                    end
                end)
                -- Player name / ID
                pcall(function()
                    local ctrl = player:GetInstigatorController()
                    if ctrl and ctrl:IsValid() then
                        -- Try PlayerState for name
                        pcall(function()
                            local ps = ctrl.PlayerState
                            if ps and ps:IsValid() then
                                local name = ps:GetPlayerName()
                                info = info .. " Name=" .. tostring(name)
                            end
                        end)
                        -- Try PlayerId
                        pcall(function()
                            local ps = ctrl.PlayerState
                            if ps then
                                info = info .. " ID=" .. tostring(ps.PlayerId)
                            end
                        end)
                    end
                end)
                -- Full class to confirm it's a player
                pcall(function()
                    info = info .. " | " .. player:GetClass():GetFullName()
                end)

                ctf_log(info)
                send_color(info, 1, 1, 0)
            end)
        end
    end)

    ctf_log("=== PLAYER SCAN DONE ===")
end)

------------------------------------------------------------
-- F4: Coords
------------------------------------------------------------
RegisterKeyBind(Key.F4, function()
    -- Show ALL player positions
    pcall(function()
        local all = FindAllOf("BP_PlayerCharacter_C")
        if all then
            for i, p in ipairs(all) do
                pcall(function()
                    if p and p:IsValid() then
                        local loc = p:K2_GetActorLocation()
                        local pid = "?"
                        pcall(function() pid = tostring(p:GetInstigatorController().PlayerState.PlayerId) end)
                        local msg = string.format("P%s: X=%.0f Y=%.0f Z=%.0f", pid, loc.X, loc.Y, loc.Z)
                        send_chat("[POS] " .. msg)
                        ctf_log("[POS] " .. msg)
                    end
                end)
            end
        end
    end)
end)

------------------------------------------------------------
-- F2: Teleport ALL players to your position (staggered, game thread safe)
------------------------------------------------------------
RegisterKeyBind(Key.F2, function()
    local pos = get_player_pos()
    if not pos then send_color("Can't get your position!", 1, 0, 0) return end
    local my_player = FindFirstOf("BP_PlayerCharacter_C")

    ctf_log("=== TELEPORT ALL PLAYERS ===")
    ctf_log(string.format("Target: X=%.0f Y=%.0f Z=%.0f", pos.X, pos.Y, pos.Z))

    pcall(function()
        local all_players = FindAllOf("BP_PlayerCharacter_C")
        if not all_players then
            send_color("No players found!", 1, 0, 0)
            return
        end

        local delay = 0
        local count = 0
        for i, player in ipairs(all_players) do
            if player and player:IsValid() and player ~= my_player then
                local offset = (i - 1) * 200  -- spread players out
                local tp_pos = {X = pos.X + offset, Y = pos.Y, Z = pos.Z}
                ExecuteWithDelay(delay, function()
                    ExecuteInGameThread(function()
                        pcall(function()
                            if player:IsValid() then
                                player:K2_SetActorLocation(tp_pos, false, {}, true)
                                ctf_log("Teleported player " .. i)
                            end
                        end)
                    end)
                end)
                delay = delay + 1000  -- 1s between each teleport
                count = count + 1
            end
        end
        send_color("Teleporting " .. count .. " players to you!", 0, 1, 0)
    end)
end)

------------------------------------------------------------
-- F5: START MATCH (full multiplayer flow)
-- Phase: assign teams → class select lobby (60s) → countdown (10s) → GO
------------------------------------------------------------
RegisterKeyBind(Key.F5, function()
    -- If match already running, show status instead
    if game_state.phase == "active" then
        ctf_log("=== TEAM STATUS ===")
        for _, team_name in ipairs({"red", "blue"}) do
            local t = teams[team_name]
            local msg = team_name:upper() .. " (" .. #t.players .. "p)"
            msg = msg .. " | PvP:" .. t.pvp_kills
            msg = msg .. " | PvE: " .. pve_progress_str(team_name)
            msg = msg .. " | Armor:T" .. t.armor_tier
            ctf_log(msg)
            send_color(msg, t.color.R, t.color.G, t.color.B)
            for _, p in ipairs(t.players) do
                local pd = player_data[p.id]
                if pd then
                    local pmsg = "  ID=" .. p.id .. " K:" .. pd.kills .. " D:" .. pd.deaths
                    if pd.class then pmsg = pmsg .. " Class:" .. pd.class end
                    if pd.specialized then pmsg = pmsg .. " [SPEC]" end
                    ctf_log(pmsg)
                    send_color(pmsg, t.color.R, t.color.G, t.color.B)
                end
            end
        end
        ctf_log("=== STATUS DONE ===")
        return
    end

    -- === PHASE 1: DETECT PLAYERS, OPEN LOBBY ===
    game_state.phase = "lobby"
    reset_game_state()
    ctf_log("=== MATCH START ===")

    -- Register all connected players (no team yet)
    local players = get_all_players()
    for _, p in ipairs(players) do
        player_data[p.id] = {
            team = nil,
            class = nil,
            kills = 0,
            deaths = 0,
            specialized = false,
            ref = p.ref,
        }
    end
    ctf_log("Lobby opened with " .. #players .. " players")

    -- === PHASE 2: TEAM + CLASS SELECT (60s) ===
    send_to_all("===== LOBBY OPEN (60 seconds) =====", 0, 1, 0)
    send_to_all("Walk to RED or BLUE lodestone for team", 1, 1, 0)
    send_to_all("Walk to a CLASS lodestone to select class", 1, 1, 0)

    local class_names = {"archer", "assassin", "guardian", "berserker", "fire_mage", "air_mage"}
    local lobby_time = 60
    game_state.phase = "class_select"
    game_state.lobby_end_time = os.time() + 60
    game_state.timer_display = "60"
    pcall(function()
        local ma = FindFirstOf("ModActor_C")
        if ma and ma:IsValid() then
            ma.MatchTimer = "60"
            ma.RedScore = "0"
            ma.BlueScore = "0"
            -- Show scoreboard widget
            pcall(function()
                local widget = ma.ScoreboardWidget
                if widget and widget:IsValid() then
                    widget:SetVisibility(0)  -- 0 = Visible
                end
            end)
        end
    end)

    -- Proximity-based team + class selection for ALL players
    local player_equip_cooldown = {}

    LoopAsync(500, function()
        if not is_world_valid() then return true end
        if game_state.phase ~= "class_select" then return true end

        local now = os.clock()
        local all_p = get_all_players()
        for _, p in ipairs(all_p) do
            local pd = player_data[p.id]
            if not pd then goto continue_player end

            -- Skip if on cooldown (4s)
            if player_equip_cooldown[p.id] and (now - player_equip_cooldown[p.id]) < 4.0 then
                goto continue_player
            end

            -- TEAM selection via 3 zones: red, blue, random (3-player cap)
            if pd.team == nil then
                local red_count = #teams.red.players
                local blue_count = #teams.blue.players
                local new_team = nil

                -- Check red zone
                local red_pos = lodestone_positions.team_red
                if red_pos and distance2d(p.pos, red_pos) < TEAM_RADIUS then
                    if red_count >= 3 then
                        send_team_msg(p.ref, "RED team is full! (3 max)", 1, 0.3, 0.3)
                    else
                        new_team = "red"
                    end
                end

                -- Check blue zone
                if not new_team then
                    local blue_pos = lodestone_positions.team_blue
                    if blue_pos and distance2d(p.pos, blue_pos) < TEAM_RADIUS then
                        if blue_count >= 3 then
                            send_team_msg(p.ref, "BLUE team is full! (3 max)", 1, 0.3, 0.3)
                        else
                            new_team = "blue"
                        end
                    end
                end

                -- Check random zone
                if not new_team then
                    local rpos = lodestone_positions.team_random
                    if rpos and distance2d(p.pos, rpos) < TEAM_RADIUS then
                        if red_count >= 3 and blue_count >= 3 then
                            send_team_msg(p.ref, "Both teams are full! (3v3 max)", 1, 0.3, 0.3)
                        elseif red_count < blue_count then
                            new_team = "red"
                        elseif blue_count < red_count then
                            new_team = "blue"
                        else
                            new_team = math.random(2) == 1 and "red" or "blue"
                        end
                    end
                end

                if new_team then
                    pd.team = new_team
                    table.insert(teams[new_team].players, {id=p.id, ref=p.ref})
                    teams[new_team].individual_kills[p.id] = 0
                    player_equip_cooldown[p.id] = now

                    local c = teams[new_team].color
                    send_team_msg(p.ref, ">> TEAM " .. new_team:upper() .. " selected!", c.R, c.G, c.B)
                    ctf_log("P" .. p.id .. " joined " .. new_team:upper())

                    -- Teleport to team's class lobby
                    pcall(function()
                        local lobby_spawns = team_lobby_spawns[new_team]
                        if lobby_spawns and #lobby_spawns > 0 then
                            local spawn = lobby_spawns[math.random(1, #lobby_spawns)]
                            local yaw = team_spawn_yaw[new_team] or 0
                            ExecuteInGameThread(function()
                                pcall(function()
                                    p.ref:K2_SetActorLocationAndRotation(
                                        {X=spawn.X, Y=spawn.Y, Z=spawn.Z},
                                        {Pitch=0, Yaw=yaw, Roll=0},
                                        false, {}, true)
                                    snap_camera(p.ref, yaw)
                                    pcall(function() p.ref:PlayRespawnVFX() end)
                                end)
                            end)
                        end
                    end)

                        -- If class already selected, re-preview with new team cape
                        if pd.class then
                            pcall(function()
                                local ctrl = get_controller_for(p.ref)
                                if ctrl and ctrl:IsValid() then
                                    local cape = get_cape(new_team, 0)
                                    local cls = pd.class
                                    ExecuteInGameThread(function()
                                        clear_all_for(ctrl)
                                        ExecuteWithDelay(500, function()
                                            ExecuteInGameThread(function()
                                                local armor = CLASS_ARMOR[cls] and CLASS_ARMOR[cls][4] or nil
                                                if armor then
                                                    add_to_loadout_for(ctrl, armor.head)
                                                    add_to_loadout_for(ctrl, armor.body)
                                                    add_to_loadout_for(ctrl, armor.legs)
                                                end
                                                if cape then add_to_loadout_for(ctrl, cape) end
                                                local weapons = CLASS_WEAP[cls] and CLASS_WEAP[cls][4] or {}
                                                for _, w in ipairs(weapons) do
                                                    add_item_for(ctrl, w, 1)
                                                end
                                                if CLASS_AMMO[cls] then
                                                    add_item_for(ctrl, CLASS_AMMO[cls], 50)
                                                end
                                            end)
                                        end)
                                    end)
                                end
                            end)
                        else
                            -- No class yet — clear loadout and add just the cape
                            pcall(function()
                                local ctrl = get_controller_for(p.ref)
                                if ctrl and ctrl:IsValid() then
                                    ExecuteInGameThread(function()
                                        clear_all_for(ctrl)
                                        ExecuteWithDelay(500, function()
                                            ExecuteInGameThread(function()
                                                pcall(function()
                                                    add_to_loadout_for(ctrl, get_cape(new_team, 0))
                                                end)
                                            end)
                                        end)
                                    end)
                                end
                            end)
                        end
                    end
                end

            -- CLASS selection via team-specific class lodestones
            if pd.team then
            for _, cls in ipairs(class_names) do
                local lkey = pd.team .. "_" .. cls  -- e.g. "red_archer", "blue_guardian"
                local spos = lodestone_positions[lkey]
                if spos and distance2d(p.pos, spos) < LOBBY_RADIUS then
                    if pd.class ~= cls then
                        pd.class = cls
                        player_equip_cooldown[p.id] = now
                        send_team_msg(p.ref, ">> Class: " .. CLASS_DISPLAY[cls], 0, 1, 0.5)
                        ctf_log("P" .. p.id .. " selected " .. cls)

                        -- Preview equip (armor + weapons + ammo + runes)
                        pcall(function()
                            local ctrl = get_controller_for(p.ref)
                            if ctrl and ctrl:IsValid() then
                                local cape = get_cape(pd.team or "red", 0)
                                ExecuteInGameThread(function()
                                    clear_all_for(ctrl)
                                    ExecuteWithDelay(500, function()
                                        ExecuteInGameThread(function()
                                            -- Armor (T6 preview = index 4)
                                            local armor = CLASS_ARMOR[cls] and CLASS_ARMOR[cls][4] or nil
                                            if armor then
                                                add_to_loadout_for(ctrl, armor.head)
                                                add_to_loadout_for(ctrl, armor.body)
                                                add_to_loadout_for(ctrl, armor.legs)
                                            end
                                            if cape then add_to_loadout_for(ctrl, cape) end
                                            -- Weapons (T6 = index 4)
                                            local weapons = CLASS_WEAP[cls] and CLASS_WEAP[cls][4] or {}
                                            for _, w in ipairs(weapons) do
                                                add_item_for(ctrl, w, 1)
                                            end
                                            -- Ammo
                                            if CLASS_AMMO[cls] then
                                                add_item_for(ctrl, CLASS_AMMO[cls], 50)
                                            end
                                            -- Runes
                                            local runes = CLASS_RUNES[cls]
                                            if runes then
                                                for _, r in ipairs(runes) do
                                                    add_item_for(ctrl, r[1], r[2])
                                                end
                                            end
                                        end)
                                    end)
                                end)
                            end
                        end)
                    end
                    break
                end
            end
            end  -- close if pd.team

            ::continue_player::
        end
        return false
    end)

    -- Lobby countdown
    LoopAsync(1000, function()
        if not is_world_valid() then return true end
        if game_state.phase ~= "class_select" then return true end
        lobby_time = lobby_time - 1
        game_state.timer_display = tostring(lobby_time)
        pcall(function()
            local ma = FindFirstOf("ModActor_C")
            if ma and ma:IsValid() then ma.MatchTimer = tostring(lobby_time) end
        end)

        if lobby_time == 30 then send_to_all("30 seconds remaining!", 1, 1, 0) end
        if lobby_time == 10 then send_to_all("10 seconds remaining!", 1, 0.5, 0) end
        if lobby_time <= 5 and lobby_time > 0 then send_to_all(">> " .. lobby_time .. " <<", 1, 0.3, 0) end

        if lobby_time <= 0 then
            -- Check all players have team + class
            local all_ready = true
            local missing = {}
            for id, pd in pairs(player_data) do
                if not pd.team then
                    all_ready = false
                    table.insert(missing, "P" .. id .. " needs team")
                end
                if not pd.class then
                    all_ready = false
                    table.insert(missing, "P" .. id .. " needs class")
                end
            end

            if not all_ready then
                send_to_all("Not ready! " .. table.concat(missing, ", ") .. " — 30s extension.", 1, 0, 0)
                lobby_time = 30
                return false
            end

            -- === PHASE 3: LOCK & EQUIP ===
            game_state.phase = "countdown"
            send_to_all("===== CLASSES LOCKED =====", 1, 0.8, 0)

            -- Equip base kit for all players (staggered)
            local delay = 0
            for _, team_name in ipairs({"red", "blue"}) do
                for _, p in ipairs(teams[team_name].players) do
                    local pd = player_data[p.id]
                    ExecuteWithDelay(delay, function()
                        pcall(function()
                            equip_base_kit_for(p.ref, team_name)
                        end)
                    end)
                    delay = delay + 1500
                end
            end

            -- === PHASE 4: MATCH COUNTDOWN (10s) ===
            local match_count = 10
            ExecuteWithDelay(delay + 1000, function()
                send_to_all("Match starting in 10 seconds!", 1, 1, 0)
                LoopAsync(1000, function()
                    if not is_world_valid() then return true end
                    if match_count > 0 then
                        if match_count <= 5 then send_to_all(">> " .. match_count .. " <<", 1, 0.3, 0) end
                        game_state.timer_display = tostring(match_count)
                        pcall(function()
                            local ma = FindFirstOf("ModActor_C")
                            if ma and ma:IsValid() then ma.MatchTimer = tostring(match_count) end
                        end)
                        match_count = match_count - 1
                        return false
                    else
                        -- === PHASE 5: GO! ===
                        game_state.phase = "active"
                        game_state.start_time = os.time()
                        game_state.match_duration = MATCH_DURATION  -- 18 minutes  -- 15 minutes
                        match_active = true

                        -- Spawn flags at base positions
                        ExecuteWithDelay(2000, function()
                            ExecuteInGameThread(function()
                                pcall(function() setup_flags() end)
                                pcall(function() setup_powerups() end)
                            end)
                        end)

                        -- Flag & Powerup proximity check loop (500ms)
                        LoopAsync(500, function()
                            if not is_world_valid() then return true end
                            if game_state.phase ~= "active" then return true end
                            pcall(function()
                                local all_p = get_all_players()
                                for _, p in ipairs(all_p) do
                                    if not p.ref or not p.ref:IsValid() or not p.pos then goto next_player end
                                    local pd = player_data[p.id]
                                    if not pd or not pd.team then goto next_player end

                                    -- Check flag pickup: enemy flag at base, player near it
                                    local enemy_team = pd.team == "red" and "blue" or "red"
                                    if flag_state[enemy_team].status == "at_base" and flag_state[enemy_team].carrier == nil then
                                        local fpos = FLAG_POSITIONS[enemy_team]
                                        if fpos and fpos.X ~= 0 then  -- skip if positions not set
                                            local dist = distance2d(p.pos, fpos)
                                            if dist < FLAG_PICKUP_RADIUS then
                                                flag_pickup(enemy_team, p.id, p.ref)
                                            end
                                        end
                                    end

                                    -- Check flag capture
                                    for _, ft in ipairs({"red", "blue"}) do
                                        if flag_state[ft].carrier == p.id then
                                            local own_base = FLAG_POSITIONS[pd.team]
                                            if own_base and own_base.X ~= 0 then
                                                local dist = distance2d(p.pos, own_base)
                                                if dist < FLAG_CAPTURE_RADIUS then
                                                    pd.flags = (pd.flags or 0) + 1
                                                    flag_capture(ft, p.id, pd.team, p.ref, pd.class)
                                                end
                                            end
                                        end
                                    end

                                    -- Check powerup pickup
                                    for _, spawn in ipairs(powerup_spawns) do
                                        if spawn.active then
                                            local dist = distance2d(p.pos, spawn.pos)
                                            if dist < POWERUP_PICKUP_RADIUS then
                                                if not powerup_buffs[p.id] then
                                                    spawn.active = false
                                                    spawn.last_pickup = os.time()
                                                    if spawn.anima_actor and spawn.anima_actor:IsValid() then
                                                        ExecuteInGameThread(function()
                                                            pcall(function() spawn.anima_actor:K2_DestroyActor() end)
                                                        end)
                                                        spawn.anima_actor = nil
                                                    end
                                                    local pclass = pd.class or "berserker"
                                                    powerup_buffs[p.id] = {
                                                        expires = os.time() + POWERUP_BUFF_DURATION,
                                                        class = pclass,
                                                        player_ref = p.ref,
                                                    }
                                                    send_to_all(pd.team:upper() .. " picked up Wild Anima!", 0, 1, 0.5)
                                                    apply_powerup_buff(p.ref, p.id, pclass)
                                                end
                                            end
                                        end
                                    end

                                    ::next_player::
                                end

                                -- Respawn depleted powerups
                                local now = os.time()
                                for _, spawn in ipairs(powerup_spawns) do
                                    if not spawn.active and (now - spawn.last_pickup) >= POWERUP_RESPAWN_TIME then
                                        spawn.active = true
                                        ExecuteInGameThread(function()
                                            spawn.anima_actor = spawn_anima(spawn.pos)
                                        end)
                                    end
                                end

                                -- Expire powerup buffs
                                for pid, buff in pairs(powerup_buffs) do
                                    if now >= buff.expires then
                                        remove_powerup_buff(buff.player_ref, pid, buff.class)
                                        powerup_buffs[pid] = nil
                                    end
                                end
                            end)
                            return false
                        end)

                        -- Match timer loop (synced 1s ticks)
                        LoopAsync(1000, function()
                            if not is_world_valid() then return true end
                            if game_state.phase ~= "active" then return true end
                            local elapsed = os.time() - game_state.start_time
                            local remaining = math.max(0, game_state.match_duration - elapsed)
                            local mins = math.floor(remaining / 60)
                            local secs = math.floor(remaining % 60)
                            local time_str = string.format("%d:%02d", mins, secs)
                            game_state.timer_display = time_str
                            pcall(function()
                                local ma = FindFirstOf("ModActor_C")
                                if ma and ma:IsValid() then ma.MatchTimer = time_str end
                            end)
                            if remaining <= 0 then
                                game_state.phase = "ended"
                                match_active = false
                                send_to_all("===== MATCH OVER =====", 1, 1, 0)

                                -- Win condition: most flag captures
                                local red_caps = teams.red.captures
                                local blue_caps = teams.blue.captures
                                if red_caps > blue_caps then
                                    send_to_all("===== RED TEAM WINS! =====", 1, 0.2, 0.2)
                                elseif blue_caps > red_caps then
                                    send_to_all("===== BLUE TEAM WINS! =====", 0.2, 0.4, 1)
                                else
                                    send_to_all("===== DRAW! =====", 1, 1, 0)
                                end
                                send_to_all("Final Score: RED " .. red_caps .. " - BLUE " .. blue_caps, 1, 0.8, 0)

                                -- Cleanup flags and powerups
                                cleanup_flags()
                                cleanup_powerups()

                                -- Teleport all players back to bed/team lobby after 5s
                                ExecuteWithDelay(5000, function()
                                    pcall(function()
                                        local all = FindAllOf("BP_PlayerCharacter_C")
                                        if all then
                                            local tp_delay = 0
                                            for _, pl in ipairs(all) do
                                                ExecuteWithDelay(tp_delay, function()
                                                    ExecuteInGameThread(function()
                                                        pcall(function()
                                                            if pl and pl:IsValid() then
                                                                pl:K2_SetActorLocation(
                                                                    {X=BED_LOBBY.X, Y=BED_LOBBY.Y, Z=BED_LOBBY.Z},
                                                                    false, {}, true)
                                                                pcall(function() pl:PlayRespawnVFX() end)
                                                            end
                                                        end)
                                                    end)
                                                end)
                                                tp_delay = tp_delay + 500
                                            end
                                        end
                                    end)
                                    send_to_all("Returned to lobby!", 1, 1, 0)

                                    -- Hide HUD + reset scoreboard
                                    pcall(function()
                                        local ma = FindFirstOf("ModActor_C")
                                        if ma and ma:IsValid() then
                                            ma.RedScore = "0"
                                            ma.BlueScore = "0"
                                            ma.MatchTimer = "0:00"
                                            for _, prefix in ipairs({"Red", "Blue"}) do
                                                for slot = 1, 3 do
                                                    ma[prefix .. slot .. "Name"] = ""
                                                    ma[prefix .. slot .. "Class"] = ""
                                                    ma[prefix .. slot .. "Kills"] = ""
                                                    ma[prefix .. slot .. "Deaths"] = ""
                                                    ma[prefix .. slot .. "Flags"] = ""
                                                end
                                            end
                                            local widget = ma.ScoreboardWidget
                                            if widget and widget:IsValid() then
                                                widget:SetVisibility(2)
                                            end
                                        end
                                    end)
                                    game_state.phase = "idle"
                                    match_active = false
                                    lobby_active = false
                                end)
                                return true
                            end
                            return false
                        end)
                        send_to_all("===== GO! =====", 0, 1, 0)

                        -- Teleport each team to their initial spawn (per-player positions)
                        for _, team_name in ipairs({"red", "blue"}) do
                            local tp_delay = 0
                            local spawns = team_spawn_initial[team_name]
                            local yaw = team_spawn_yaw[team_name] or 0
                            for i, p in ipairs(teams[team_name].players) do
                                local spawn = spawns[i] or spawns[1]
                                if spawn then
                                    ExecuteWithDelay(tp_delay, function()
                                        ExecuteInGameThread(function()
                                            pcall(function()
                                                if p.ref and p.ref:IsValid() then
                                                    p.ref:K2_SetActorLocationAndRotation(
                                                        {X=spawn.X, Y=spawn.Y, Z=spawn.Z},
                                                        {Pitch=0, Yaw=yaw, Roll=0},
                                                        false, {}, true)
                                                    snap_camera(p.ref, yaw)
                                                    pcall(function() p.ref:DissolveTeleport() end)
                                                    ExecuteWithDelay(500, function()
                                                        pcall(function() p.ref:PlayRespawnVFX() end)
                                                    end)
                                                end
                                            end)
                                        end)
                                    end)
                                    tp_delay = tp_delay + 500
                                end
                            end
                        end

                        -- Announce classes
                        for _, team_name in ipairs({"red", "blue"}) do
                            for _, p in ipairs(teams[team_name].players) do
                                local pd = player_data[p.id]
                                if pd and pd.class then
                                    send_team_msg(p.ref, "Get 3 kills to specialize as " .. CLASS_DISPLAY[pd.class] .. "!",
                                        1, 1, 0)
                                end
                            end
                        end

                        ctf_log("=== MATCH ACTIVE ===")

                        -- Auto-start PvE Event 1 after 60 seconds
                        ExecuteWithDelay(60000, function()
                            if game_state.phase ~= "active" then return end
                            start_pve_event(1)
                        end)

                        return true
                    end
                end)
            end)

            return true
        end
        return false
    end)
end)

------------------------------------------------------------
-- 0: Full reset
------------------------------------------------------------
-- I: Toggle TP between red and blue flag area
local flag_tp_toggle = false
RegisterKeyBind(Key.I, function()
    local player = FindFirstOf("BP_PlayerCharacter_C")
    if not player or not player:IsValid() then return end

    flag_tp_toggle = not flag_tp_toggle
    local spawn, team, label
    if flag_tp_toggle then
        spawn = {X=71954, Y=164831, Z=16512}
        team = "red"
        label = "RED FLAG AREA"
    else
        spawn = {X=64003, Y=175725, Z=16512}
        team = "blue"
        label = "BLUE FLAG AREA"
    end

    local yaw = team_spawn_yaw[team] or 0
    ExecuteInGameThread(function()
        pcall(function()
            player:K2_SetActorLocationAndRotation(
                {X=spawn.X, Y=spawn.Y, Z=spawn.Z},
                {Pitch=0, Yaw=yaw, Roll=0},
                false, {}, true)
            snap_camera(player, yaw)
            pcall(function() player:PlayRespawnVFX() end)
        end)
    end)
    send_color("TP: " .. label, 1, 1, 0)
end)
-- Keys 5,6,1,R,3,2,7,8,I,9 REMOVED — start


------------------------------------------------------------
-- 8: Simulate PvP kill (for testing progression)
------------------------------------------------------------
RegisterKeyBind(Key.EIGHT, function()
    local player = FindFirstOf("BP_PlayerCharacter_C")
    if not player or not player:IsValid() then return end
    local pid = player:GetInstigatorController().PlayerState.PlayerId
    local pd = player_data[pid]
    if not pd then
        send_color("No player data — press F3 first", 1, 0, 0)
        return
    end
    if not pd.team then
        send_color("No team assigned", 1, 0, 0)
        return
    end

    -- Simulate a kill
    pd.kills = pd.kills + 1
    local kills = pd.kills
    local team = pd.team
    teams[team].pvp_kills = teams[team].pvp_kills + 1
    local team_pvp = teams[team].pvp_kills

    send_color("SIM KILL: Personal=" .. kills .. " Team=" .. team_pvp, 1, 0.5, 0)

    -- Don't apply gear upgrades while carrying flag
    if is_carrying_flag(pid) then
        send_color("Carrying flag — upgrade deferred!", 1, 1, 0)
        return
    end

    -- Specialization at 3
    if kills == 3 and not pd.specialized and pd.class then
        pd.specialized = true
        send_color("===== SPECIALIZED: " .. CLASS_DISPLAY[pd.class] .. " =====", 0, 1, 0)
        play_vfx()
        equip_class_for(player, team, pd.class, teams[team].armor_tier, 1)
    end

    -- Trinket at 12 personal
    if kills == 12 and pd.class then
        local trinket_path = TRINKETS[pd.class]
        if trinket_path then
            send_color("===== TRINKET EARNED =====", 1, 0.8, 0)
            add_to_loadout(trinket_path)
        end
    end

    -- Weapon tiers at 12/24/36 team
    if team_pvp == 12 or team_pvp == 24 or team_pvp == 36 then
        local wt = team_pvp == 12 and 2 or (team_pvp == 24 and 3 or 4)
        send_color("===== WEAPON TIER T" .. (wt+2) .. " =====", 0, 1, 1)
        if pd.class and pd.specialized then
            -- Swap weapons only — clear inventory (not loadout/armor)
            local cls = pd.class
            local weapons = CLASS_WEAP[cls] and CLASS_WEAP[cls][wt] or {}
            local ammo = nil
            if cls == "archer" then
                ammo = ARCHER_AMMO[wt] or CLASS_AMMO.archer
            end
            unlock_inv()
            ExecuteInGameThread(function()
                pcall(function()
                    local ctrl = FindFirstOf("BP_PlayerController_C")
                    if ctrl and ctrl:IsValid() then
                        ctrl.BP_Components_Inventory.bAllowRemoves = true
                        ctrl.BP_Components_Inventory.bAllowAdds = true
                        ctrl.BP_Components_Inventory:ClearInventory()
                    end
                end)
            end)
            ExecuteWithDelay(400, function()
                ExecuteInGameThread(function()
                    for _, w in ipairs(weapons) do
                        add_item(w)
                    end
                    if ammo then add_item(ammo, 50) end
                    -- Re-add runes
                    local runes = CLASS_RUNES[cls]
                    if runes then
                        for _, r in ipairs(runes) do
                            add_item(r[1], r[2])
                        end
                    end
                    send_color("Weapons upgraded!", 0, 1, 0)
                    play_vfx()
                end)
            end)
        end
        -- Auto-promote at 12 if unspecialized
        if team_pvp == 12 and not pd.specialized and pd.class then
            pd.specialized = true
            send_color(">> AUTO-PROMOTED!", 1, 0.8, 0)
        end
    end
end)

local resetting = false

RegisterKeyBind(Key.ZERO, function()
    resetting = true
    lobby_active = false
    match_active = false
    locked = false
    selected_class = nil
    selected_team = nil
    armor_tier = 0
    weapon_tier = 0
    pve_event = 0
    pve_event_active = false  -- disable BEFORE killing mobs (prevents death hook from counting)
    pve_auto_spawning = false
    pve_current_event = nil
    pve_kills = {red = 0, blue = 0}
    pve_total_killed = 0
    equip_busy = false
    individual_kills = 0
    team_kills = 0
    trinket_earned = false
    runes_given = false
    kill_all_mobs()
    destroy_lodestones()

    -- Clear on game thread
    ExecuteInGameThread(function()
        clear_all()
        unblock_windstep()
    end)
    send_chat("[CTF] Full reset")
    cleanup_flags()
    cleanup_powerups()

    ExecuteWithDelay(500, function()
        resetting = false
    end)
end)

------------------------------------------------------------
-- INIT
------------------------------------------------------------

-- Spawn platform → team/bed lobby teleport (always active)
local SPAWN_PLATFORM = {X=8705, Y=185369, Z=-2993}
-- BED_LOBBY defined earlier (near bed management section)
local PLATFORM_RADIUS = 500
local platform_cooldown = {}  -- prevent re-teleporting immediately

ExecuteWithDelay(12000, function()
    LoopAsync(1000, function()
        if not is_world_valid() then return true end
        pcall(function()
            local all = FindAllOf("BP_PlayerCharacter_C")
            if not all then return end
            for _, p in ipairs(all) do
                pcall(function()
                    if p and p:IsValid() then
                        local loc = p:K2_GetActorLocation()
                        local pid = p:GetInstigatorController().PlayerState.PlayerId
                        local dist = math.sqrt((loc.X - SPAWN_PLATFORM.X)^2 + (loc.Y - SPAWN_PLATFORM.Y)^2)
                        if dist < PLATFORM_RADIUS then
                            local now = os.time()
                            if not platform_cooldown[pid] or (now - platform_cooldown[pid]) > 10 then
                                platform_cooldown[pid] = now
                                ExecuteInGameThread(function()
                                    pcall(function()
                                        p:K2_SetActorLocation(
                                            {X=BED_LOBBY.X, Y=BED_LOBBY.Y, Z=BED_LOBBY.Z},
                                            false, {}, true)
                                        pcall(function() p:PlayRespawnVFX() end)
                                    end)
                                end)
                                ctf_log("PLATFORM: P" .. pid .. " teleported to bed lobby")
                            end
                        end
                    end
                end)
            end
        end)
        return false
    end)
    ctf_log("Spawn platform teleport active")

    -- Auto-detect 6 players in lobby → start team selection
    local auto_start_triggered = false
    LoopAsync(3000, function()
        if not is_world_valid() then return true end
        if auto_start_triggered or game_state.phase ~= "idle" then return false end
        pcall(function()
            local all = FindAllOf("BP_PlayerCharacter_C")
            if not all then return end
            local lobby_count = 0
            for _, p in ipairs(all) do
                pcall(function()
                    if p and p:IsValid() then
                        local loc = p:K2_GetActorLocation()
                        if distance2d(loc, BED_LOBBY) < BED_LOBBY_RADIUS then
                            lobby_count = lobby_count + 1
                        end
                    end
                end)
            end
            if lobby_count >= 6 then
                auto_start_triggered = true
                ctf_log("6 players detected in lobby — auto-starting team selection!")
                send_to_all("===== ALL PLAYERS READY =====", 1, 0.8, 0)
                send_to_all("Choose your team: RED, BLUE, or RANDOM!", 1, 1, 0)

                -- Register all players
                for _, p in ipairs(all) do
                    pcall(function()
                        if p and p:IsValid() then
                            local pid = p:GetInstigatorController().PlayerState.PlayerId
                            if not player_data[pid] then
                                player_data[pid] = {team=nil, class=nil, kills=0, deaths=0, specialized=false}
                            end
                        end
                    end)
                end

                game_state.phase = "class_select"
                lobby_active = true
                game_state.lobby_end_time = os.time() + 60
                game_state.timer_display = "60"

                pcall(function()
                    local ma = FindFirstOf("ModActor_C")
                    if ma and ma:IsValid() then
                        ma.RedScore = "0"
                        ma.BlueScore = "0"
                        ma.MatchTimer = "60"
                        local widget = ma.ScoreboardWidget
                        if widget and widget:IsValid() then
                            widget:SetVisibility(0)
                        end
                    end
                end)
            end
        end)
        return false
    end)
end)

-- Lock mannequin inventories so players can't steal display armor
-- Poll until buildings are found, then protect them
local building_protection_done = false
LoopAsync(5000, function()
    if not is_world_valid() then return true end
    if building_protection_done then return true end

    -- Wait until player is in the world (means buildings are loaded too)
    local player = FindFirstOf("BP_PlayerCharacter_C")
    if not player or not player:IsValid() then return false end

    -- Extra delay to ensure all buildings are streamed in
    building_protection_done = true
    ctf_log("Player in world, waiting 10s for buildings to stream in...")
    ExecuteWithDelay(10000, function()
    ctf_log("=== BUILDING PROTECTION INIT ===")
    pcall(function()
        local mannequins = FindAllOf("BP_BaseBuilding_ArmourMannequin_C")
        if mannequins then
            ctf_log("Locking " .. #mannequins .. " mannequins...")
            for _, m in ipairs(mannequins) do
                pcall(function()
                    if m and m:IsValid() then
                        -- Only try the component that actually works
                        local inv = m["BP_Components_WorldItemInventory"]
                        if inv and type(inv) == "userdata" then
                            pcall(function()
                                if inv:IsValid() then
                                    inv.bAllowRemoves = false
                                    inv.bAllowAdds = false
                                end
                            end)
                        end
                    end
                end)
            end
            ctf_log("Mannequins locked: " .. #mannequins)
        else
            ctf_log("No mannequins found")
        end
    end)

    -- Make ALL buildings invulnerable
    pcall(function()
        local building_classes = {
            "BP_BaseBuilding_C",
            "BP_BaseBuildingPiece_C",
            "BP_BuildingHelper_C",
        }
        local total = 0
        for _, cls in ipairs(building_classes) do
            pcall(function()
                local buildings = FindAllOf(cls)
                if buildings then
                    for _, b in ipairs(buildings) do
                        pcall(function()
                            if b and b:IsValid() then
                                -- Try setting health component to invulnerable
                                pcall(function()
                                    local hc = b.HealthComponent
                                    if hc and hc:IsValid() then
                                        hc:SetHealth(999999, "Heal")
                                    end
                                end)
                                -- Try bCanBeDamaged
                                pcall(function() b.bCanBeDamaged = false end)
                                total = total + 1
                            end
                        end)
                    end
                end
            end)
        end
        -- Also protect all actors with "BaseBuilding" in name
        pcall(function()
            local all = FindAllOf("Actor")
            if all then
                for _, a in ipairs(all) do
                    pcall(function()
                        if a and a:IsValid() then
                            local cls_name = a:GetClass():GetFName():ToString()
                            if cls_name:find("BaseBuilding") or cls_name:find("BuildingHelper") then
                                pcall(function() a.bCanBeDamaged = false end)
                                pcall(function()
                                    local hc = a.HealthComponent
                                    if hc and hc:IsValid() then
                                        hc:SetHealth(999999, "Heal")
                                    end
                                end)
                                total = total + 1
                            end
                        end
                    end)
                end
            end
        end)
        ctf_log("Buildings protected: " .. total)
    end)

    -- Continuous heal loop (every 5s) — heal ALL HealthComponents except trees/mobs/players
    LoopAsync(5000, function()
        if not is_world_valid() then return true end -- stop loop on disconnect
        pcall(function()
            local player = FindFirstOf("BP_PlayerCharacter_C")
            if not player or not player:IsValid() then return end
            local hcs = FindAllOf("HealthComponent")
            if not hcs then return end
            for _, hc in ipairs(hcs) do
                pcall(function()
                    if hc and hc:IsValid() then
                        local full = hc:GetFullName()
                        -- Skip trees, mobs, players, wildlife
                        if not full:find("Tree") and not full:find("Sapling")
                           and not full:find("BP_AI_") and not full:find("PlayerCharacter")
                           and not full:find("Deer") and not full:find("Kebbit")
                           and not full:find("Chinchompa") and not full:find("Sheep")
                           and not full:find("Chicken") and not full:find("Cow")
                           and not full:find("Magpie") and not full:find("Rat")
                           and not full:find("Bush") and not full:find("Flax")
                           and not full:find("OreNode") and not full:find("Spawner") then
                            local max = hc:GetMaxHealth()
                            if max and max > 0 then
                                hc:SetHealth(max, "Heal")
                            end
                        end
                    end
                end)
            end
        end)
        return false
    end)
    ctf_log("Building heal loop active")
    end)  -- end ExecuteWithDelay
    return true  -- stop polling loop, protection is set up
end)

-- Delay death hook until player is in world
ExecuteWithDelay(8000, function()
    register_death_hook()
end)

-- Pre-load mob classes at startup
ExecuteWithDelay(10000, function()
    ExecuteInGameThread(function()
        -- Load mob classes directly
        for key, mob_path in pairs(MOB_CLASSES) do
            local package = mob_path:match("(.+)%.")
            pcall(function() LoadAsset(package) end)
        end

        -- Also load HuntedEvent ambush assets (these force-load referenced mob classes)
        local ambush_events = {
            "/Game/Gameplay/Events/BP_HuntedEvent_RotswornSkeletonAmbush_01",
            "/Game/Gameplay/Events/BP_HuntedEvent_RotswornZombieAmbush_01",
            "/Game/Gameplay/Events/BP_HuntedEvent_SkeletonAmbush_01",
            "/Game/Gameplay/Events/BP_HuntedEvent_ZombieAmbush_01",
            "/Game/Gameplay/Events/BP_HuntedEvent_BM_1",
            "/Game/Gameplay/Events/BP_HuntedEvent_GF_1",
            "/Game/Gameplay/Events/BP_AmbushRaid_DowdunReach_BlackKnights_Melee",
            "/Game/Gameplay/Events/BP_AmbushRaid_DowdunReach_BlackKnights_Ranged",
        }
        for _, event_path in ipairs(ambush_events) do
            pcall(function() LoadAsset(event_path) end)
        end
        ctf_log("LoadAsset: mob classes + ambush events\n")
    end)

    ExecuteWithDelay(3000, function()
        -- Check what loaded
        for key, mob_path in pairs(MOB_CLASSES) do
            local cls = StaticFindObject(mob_path)
            if cls and cls:IsValid() then
                cached_mob_classes[key] = cls
                ctf_log("PRE-LOADED: " .. key .. "\n")
            else
                ctf_log("NOT LOADED: " .. key .. "\n")
            end
        end

        -- Scan ALL AI character classes currently loaded in memory
        ctf_log("=== SCANNING ALL LOADED AI MOBS ===\n")
        pcall(function()
            local all_ai = FindAllOf("DominionAICharacter")
            if all_ai then
                local seen = {}
                for _, ai in ipairs(all_ai) do
                    pcall(function()
                        if ai and ai:IsValid() then
                            local cls = ai:GetClass()
                            local name = cls:GetName()
                            if not seen[name] then
                                seen[name] = true
                                ctf_log("LOADED MOB: " .. name .. " | " .. cls:GetFullName() .. "\n")
                            end
                        end
                    end)
                end
            end
        end)

        -- Also check every known mob type from manifest
        local all_mob_checks = {
            -- Skeleton faction
            {"SkeletalHoplite", "/FutureMajorVersion/Gameplay/AI/SkeletonFaction/ShieldSkeleton/BP_AI_SkeletalHoplite_Character.BP_AI_SkeletalHoplite_Character_C"},
            {"SpectralSkeletalHoplite", "/FutureMajorVersion/Gameplay/AI/SkeletonFaction/SpectralSkeletalHoplite/BP_AI_SpectralSkeletalHoplite_Character.BP_AI_SpectralSkeletalHoplite_Character_C"},
            {"SkeletalNecromancer", "/FutureMajorVersion/Gameplay/AI/SkeletonFaction/MagicSkeleton/BP_AI_SkeletalNecromancer_Character.BP_AI_SkeletalNecromancer_Character_C"},
            {"RotswornNecromancer", "/FutureMajorVersion/Gameplay/AI/SkeletonFaction/MagicSkeleton/BP_AI_RotswornNecromancer_Character.BP_AI_RotswornNecromancer_Character_C"},
            {"SkeletalArcher", "/FutureMajorVersion/Gameplay/AI/SkeletonFaction/RangedSkeleton/BP_AI_SkeletalArcher_Character.BP_AI_SkeletalArcher_Character_C"},
            {"SkeletonMagicFire", "/FutureMajorVersion/Gameplay/AI/SkeletonFaction/MagicSkeleton/FireVariant/BP_AI_SkeletonMagicFire_Character.BP_AI_SkeletonMagicFire_Character_C"},
            {"SkeletonMagicShock", "/FutureMajorVersion/Gameplay/AI/SkeletonFaction/MagicSkeleton/ShockVariant/BP_AI_SkeletonMagicShock_Character.BP_AI_SkeletonMagicShock_Character_C"},
            -- Zombie faction
            {"RotswornZombie", "/FutureMajorVersion/Gameplay/AI/ZombieFaction/RotswornZombie/BP_AI_RotswornZombie_Character.BP_AI_RotswornZombie_Character_C"},
            -- Rotsworn melee
            {"RotswornWarrior", "/FutureMajorVersion/Gameplay/AI/SkeletonFaction/MeleeSkeleton/OneHandSwordVariant/WitheredVariant/BP_AI_RotswornWarrior_Character.BP_AI_RotswornWarrior_Character_C"},
            {"RotswornMarauder", "/FutureMajorVersion/Gameplay/AI/SkeletonFaction/MeleeSkeleton/TwoHandSwordVariant/WitheredVariant/BP_AI_RotswornMarauder_Character.BP_AI_RotswornMarauder_Character_C"},
            -- Base game
            {"Wolf", "/Game/Gameplay/AI/Wolf/BP_AI_Wolf_Character.BP_AI_Wolf_Character_C"},
            {"WolfElite", "/Game/Gameplay/AI/Wolf/WolfEliteVariant/BP_AI_WolfElite_Character.BP_AI_WolfElite_Character_C"},
            {"DragonGreen", "/Game/Gameplay/AI/DragonLesser/BP_AI_DragonLesserGreen_Character.BP_AI_DragonLesserGreen_Character_C"},
            -- Other base game mobs
            {"GiantRat", "/Game/Gameplay/AI/BeastFaction/GiantRat/BP_AI_GiantRat_Character.BP_AI_GiantRat_Character_C"},
            {"Zombie", "/Game/Gameplay/AI/ZombieFaction/Zombie/BP_AI_Zombie_Character.BP_AI_Zombie_Character_C"},
            {"RangedBeast", "/Game/Gameplay/AI/BeastFaction/RangedBeast/BP_AI_RangedBeast_Character.BP_AI_RangedBeast_Character_C"},
            -- DowdunReach
            {"BlackKnight1H", "/DowdunReach/Gameplay/AI/BlackKnightFaction/1HMeleeBlackKnight/BP_AI_1HMeleeBlackKnight_Character.BP_AI_1HMeleeBlackKnight_Character_C"},
            {"BlackKnight2H", "/DowdunReach/Gameplay/AI/BlackKnightFaction/2HMeleeBlackKnight/BP_AI_Melee2HBlackKnight_Character.BP_AI_Melee2HBlackKnight_Character_C"},
            {"BlackKnightMelee", "/DowdunReach/Gameplay/AI/BlackKnightFaction/MeleeBlackKnight/BP_AI_MeleeBlackKnight_Character.BP_AI_MeleeBlackKnight_Character_C"},
            {"BlackKnightRanged", "/DowdunReach/Gameplay/AI/BlackKnightFaction/RangedBlackKnight/BP_AI_BlackKnightRanged_Character.BP_AI_BlackKnightRanged_Character_C"},
            {"ZogreDowdun", "/DowdunReach/Gameplay/AI/FellhollowVariants/ZogreDowdun/BP_AI_Zogre_Dowdun_Character.BP_AI_Zogre_Dowdun_Character_C"},
        }
        ctf_log("=== CHECKING ALL KNOWN MOB CLASSES ===\n")
        for _, check in ipairs(all_mob_checks) do
            local cls = StaticFindObject(check[2])
            if cls and cls:IsValid() then
                ctf_log("AVAILABLE: " .. check[1] .. "\n")
            end
        end
        ctf_log("=== INITIAL SCAN COMPLETE ===\n")

        -- Continuous scanner: check specific known mob class names via FindFirstOf
        local discovered_mobs = {}
        local known_mob_classes = {
            -- Base game
            "BP_AI_Wolf_Character_C", "BP_AI_WolfElite_Character_C",
            "BP_AI_GiantRat_Character_C", "BP_AI_GiantRatWithered_Character_C", "BP_AI_GiantRatZombie_Character_C",
            "BP_AI_Zombie_Character_C", "BP_AI_RangedBeast_Character_C",
            "BP_AI_DragonLesserGreen_Character_C", "BP_AI_DragonLesserGreen_Blightscale_Character_C",
            "BP_AI_DragonImaru_Character_C", "BP_AI_DragonVelgar_Character_C",
            "BP_AI_Deer_Character_C", "BP_AI_Sheep_Character_C", "BP_AI_Magpie_Character_C",
            "BP_AI_Kebbit_Character_02_C", "BP_AI_Chinchompa_Character_C",
            "BP_AI_TrainingDummy_Character_C",
            -- FutureMajorVersion (skeletons/rotsworn/zombies)
            "BP_AI_RotswornWarrior_Character_C", "BP_AI_RotswornMarauder_Character_C",
            "BP_AI_RotswornZombie_Character_C", "BP_AI_RotswornNecromancer_Character_C",
            "BP_AI_SkeletalHoplite_Character_C", "BP_AI_SpectralSkeletalHoplite_Character_C",
            "BP_AI_SkeletalNecromancer_Character_C", "BP_AI_SkeletalArcher_Character_C",
            "BP_AI_SkeletonMagicFire_Character_C", "BP_AI_SkeletonMagicShock_Character_C",
            "BP_AI_DragonWolf_Character_C", "BP_AI_SpectralDragonWolf_Character_C",
            -- DowdunReach (black knights/zogres/etc)
            "BP_AI_1HMeleeBlackKnight_Character_C", "BP_AI_Melee2HBlackKnight_Character_C",
            "BP_AI_MeleeBlackKnight_Character_C", "BP_AI_BlackKnightRanged_Character_C",
            "BP_AI_Zogre_Character_C",
            "BP_AI_DragonLesserBlue_Character_C",
            "BP_AI_AbyssalDemon_Character_C",
        }
        ctf_log("Mob scanner active (" .. #known_mob_classes .. " types)...\n")
        LoopAsync(3000, function()
            if not is_world_valid() then return true end
            for _, cls_name in ipairs(known_mob_classes) do
                if not discovered_mobs[cls_name] then
                    pcall(function()
                        local found = FindFirstOf(cls_name)
                        if found and found:IsValid() then
                            discovered_mobs[cls_name] = true
                            local full = found:GetClass():GetFullName()
                            ctf_log("NEW MOB: " .. cls_name .. " | " .. full .. "\n")
                            send_color("[NEW MOB] " .. cls_name, 0, 1, 1)
                            cached_mob_classes[cls_name] = found:GetClass()
                        end
                    end)
                end
            end
            return false
        end)
    end)
end)

ExecuteWithDelay(5000, function()
    pcall(function()
        local bSub = FindFirstOf("BuildingSubsystem")
        if bSub then bSub.bCheatAlwaysAllowBuilding = true end
        local gbm = FindFirstOf("GlobalBuildingManager")
        if gbm then gbm.StabilityComponent:Deactivate() end
    end)
    -- Block windstep early (during load, before any gameplay)
    block_windstep()
end)

------------------------------------------------------------
-- F12: Building Export — scan all building pieces, write to file
------------------------------------------------------------
RegisterKeyBind(Key.F12, function()
    ctf_log("=== BUILDING EXPORT ===")
    send_color("Scanning for building pieces...", 1, 1, 0)

    local export = {}
    local count = 0

    -- Step 1: Discover what building classes exist
    -- Try the GlobalBuildingManager first
    pcall(function()
        local gbm = FindFirstOf("GlobalBuildingManager")
        if gbm and gbm:IsValid() then
            ctf_log("GlobalBuildingManager found: " .. gbm:GetFullName())
            -- Dump its properties to find the building piece list
            for _, prop in ipairs(gbm:type():GetAllProperties()) do
                pcall(function()
                    local name = prop:GetFName():ToString()
                    local ptype = prop:GetClass():GetFName():ToString()
                    ctf_log("  GBM PROP: " .. name .. " [" .. ptype .. "]")
                end)
            end
            for _, fn in ipairs(gbm:type():GetAllFunctions()) do
                pcall(function()
                    ctf_log("  GBM FUNC: " .. fn:GetFName():ToString())
                end)
            end
        end
    end)

    -- Step 2: Search for all BaseBuilding actors
    local building_classes = {
        "BP_BaseBuilding_C",
        "BP_BaseBuildingPiece_C",
        "BaseBuildingPiece_C",
        "BuildingPiece_C",
        "BP_BuildingPiece_C",
        "DominionBuildingPiece_C",
        "BP_DominionBuildingPiece_C",
        "BaseBuildingActor_C",
        "BP_BaseBuildingActor_C",
    }

    for _, cls in ipairs(building_classes) do
        pcall(function()
            local found = FindAllOf(cls)
            if found then
                ctf_log("FOUND building class: " .. cls .. " x" .. #found)
                send_color("FOUND: " .. cls .. " x" .. #found, 0, 1, 0)
                for _, piece in ipairs(found) do
                    pcall(function()
                        if piece and piece:IsValid() then
                            local full = piece:GetFullName()
                            local loc = piece:K2_GetActorLocation()
                            local rot = piece:K2_GetActorRotation()
                            local class_name = piece:GetClass():GetFName():ToString()
                            local class_path = piece:GetClass():GetFullName()

                            local entry = {
                                class = class_name,
                                path = class_path,
                                x = loc.X, y = loc.Y, z = loc.Z,
                                pitch = rot.Pitch, yaw = rot.Yaw, roll = rot.Roll
                            }
                            table.insert(export, entry)
                            count = count + 1
                            ctf_log("  PIECE: " .. class_name .. " @ " .. loc.X .. "," .. loc.Y .. "," .. loc.Z)
                        end
                    end)
                end
            end
        end)
    end

    -- Step 3: Also grab known prop types
    local prop_classes = {
        "BP_BaseBuilding_BedRoll_C", "BP_BaseBuilding_Bed_C",
        "BP_BaseBuilding_Lodestone_C", "BP_BaseBuilding_ArmourMannequin_C",
        "BP_BaseBuilding_Torch_Type2_Purple_C",
    }
    for _, cls in ipairs(prop_classes) do
        pcall(function()
            local found = FindAllOf(cls)
            if found then
                ctf_log("FOUND prop: " .. cls .. " x" .. #found)
                for _, piece in ipairs(found) do
                    pcall(function()
                        if piece and piece:IsValid() then
                            local loc = piece:K2_GetActorLocation()
                            local rot = piece:K2_GetActorRotation()
                            local class_name = piece:GetClass():GetFName():ToString()
                            local class_path = piece:GetClass():GetFullName()

                            local entry = {
                                class = class_name,
                                path = class_path,
                                x = loc.X, y = loc.Y, z = loc.Z,
                                pitch = rot.Pitch, yaw = rot.Yaw, roll = rot.Roll
                            }
                            table.insert(export, entry)
                            count = count + 1
                            ctf_log("  PROP: " .. class_name .. " @ " .. loc.X .. "," .. loc.Y .. "," .. loc.Z)
                        end
                    end)
                end
            end
        end)
    end

    -- Step 4: Broad scan — find ANY actor with "Building" or "Build" in class name
    pcall(function()
        local all_classes_found = {}
        -- Check all actors in world for building-related ones
        local actor_classes_to_scan = {"Actor"}
        local all = FindAllOf("Actor")
        if all then
            ctf_log("Total actors in world: " .. #all)
            send_color("Total actors: " .. #all .. " — scanning for building pieces...", 1, 1, 0)
            for _, actor in ipairs(all) do
                pcall(function()
                    if actor and actor:IsValid() then
                        local class_name = actor:GetClass():GetFName():ToString()
                        local lower = string.lower(class_name)
                        if (string.find(lower, "building") or string.find(lower, "build"))
                           and not string.find(lower, "subsystem")
                           and not string.find(lower, "manager")
                           and not string.find(lower, "spawner") then
                            if not all_classes_found[class_name] then
                                all_classes_found[class_name] = 0
                            end
                            all_classes_found[class_name] = all_classes_found[class_name] + 1

                            local loc = actor:K2_GetActorLocation()
                            local rot = actor:K2_GetActorRotation()
                            local class_path = actor:GetClass():GetFullName()

                            local entry = {
                                class = class_name,
                                path = class_path,
                                x = loc.X, y = loc.Y, z = loc.Z,
                                pitch = rot.Pitch, yaw = rot.Yaw, roll = rot.Roll
                            }
                            table.insert(export, entry)
                            count = count + 1
                        end
                    end
                end)
            end
            ctf_log("--- Building classes found ---")
            for cls, cnt in pairs(all_classes_found) do
                ctf_log("  " .. cls .. " x" .. cnt)
                send_color(cls .. " x" .. cnt, 0, 1, 0)
            end
        end
    end)

    -- Step 5: Write export file
    if count > 0 then
        local file_path = "C:\\Users\\Jacob\\ctf_building_export.lua"
        local f = io.open(file_path, "w")
        if f then
            f:write("-- CTF Building Export\n")
            f:write("-- Exported " .. count .. " pieces\n")
            f:write("-- Date: " .. os.date() .. "\n")
            f:write("return {\n")
            for _, e in ipairs(export) do
                f:write("  {class=\"" .. e.class .. "\", path=\"" .. e.path .. "\", ")
                f:write("x=" .. e.x .. ", y=" .. e.y .. ", z=" .. e.z .. ", ")
                f:write("pitch=" .. e.pitch .. ", yaw=" .. e.yaw .. ", roll=" .. e.roll .. "},\n")
            end
            f:write("}\n")
            f:close()
            ctf_log("EXPORTED " .. count .. " pieces to " .. file_path)
            send_color("EXPORTED " .. count .. " building pieces!", 0, 1, 0)
        else
            ctf_log("ERROR: Could not open file for writing")
            send_color("ERROR: Could not write export file", 1, 0, 0)
        end
    else
        ctf_log("No building pieces found to export")
        send_color("No building pieces found — check console for class discovery", 1, 0.5, 0)
    end

    ctf_log("=== BUILDING EXPORT DONE ===")
end)

ctf_log("FULL FLOW TEST loaded!\n")
ctf_log("F3=Lodestones | F6=Lobby | F7=PvE | F8=Kill | F9=Trinket | F10=ScanNatural | F4=Coords | F12=BuildExport | 0=Reset")
