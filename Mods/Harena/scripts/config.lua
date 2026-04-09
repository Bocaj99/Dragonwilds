--[[
    Harena v1 — Configuration
    All coordinates, asset paths, timings, and class definitions.
    Offset from original arena: X+34349, Y-3346, Z+20123
]]

local Config = {}

-- =============================================================================
-- OFFSET (applied to all original coordinates)
-- =============================================================================
local OX, OY, OZ = 34349, -3346, 20123

local function o(x, y, z)
    return {X = x + OX, Y = y + OY, Z = z + OZ}
end

-- =============================================================================
-- MATCH SETTINGS
-- =============================================================================
Config.MATCH_DURATION = 1080          -- 18 minutes
Config.TORCH_WIN_LEAD = 3            -- ±3 captures = instant win
Config.RESPAWN_DELAY = 15.0          -- SelfReviveDelay (death screen duration)
Config.LOBBY_DURATION = 60           -- seconds for team/class select
Config.COUNTDOWN_DURATION = 10       -- seconds countdown before match

-- =============================================================================
-- RADII
-- =============================================================================
Config.FLAG_PICKUP_RADIUS = 500
Config.FLAG_CAPTURE_RADIUS = 500
Config.POWERUP_PICKUP_RADIUS = 250
Config.LODESTONE_RADIUS = 190
Config.BED_LOBBY_RADIUS = 3000

-- =============================================================================
-- PVE SETTINGS
-- =============================================================================
Config.PVE_EVENT_INTERVAL = 270      -- 4:30 between events
Config.PVE_EVENTS_START = 270        -- first event at 4:30
Config.PVE_KILL_REQ = {wolf = 10, archer = 4, mage = 4, tank = 2, boss = 1}
Config.PVE_RESPAWN_START = 15        -- seconds before mob respawning begins
Config.PVE_RESPAWN_INTERVALS = {wolf = 5, archer = 10, mage = 10, tank = 20, boss = 30}

-- =============================================================================
-- POWERUP SETTINGS
-- =============================================================================
Config.POWERUP_BUFF_DURATION = 45    -- seconds
Config.POWERUP_RESPAWN_TIME = 120    -- seconds

-- =============================================================================
-- STAGGER TIMINGS (crash prevention)
-- =============================================================================
Config.EQUIP_DELAY = 500             -- ms between clear and add
Config.EQUIP_STAGGER = 1500          -- ms between players during equip
Config.TELEPORT_STAGGER = 500        -- ms between players during teleport
Config.MOB_SPAWN_STAGGER = 250       -- ms between mob spawns
Config.MOB_GROUP_STAGGER = 4000      -- ms between role groups
Config.MOB_DESTROY_STAGGER = 250     -- ms between mob destroys

-- =============================================================================
-- ARENA COORDINATES (all offset-adjusted)
-- =============================================================================
Config.ARENA_CENTER = o(33630, 173624, -3700)

Config.FLAG_POSITIONS = {
    red  = o(38353, 168901, -3279),
    blue = o(28906, 178347, -3279),
}

Config.POWERUP_POSITIONS = {
    o(31602, 171621, -3369),
    o(33615, 173630, -3721),   -- center lowered 50u
    o(35627, 175649, -3369),
}

Config.BED_LOBBY = o(37473, 175582, -3760)

Config.BED_POSITIONS = {
    o(37177, 176852, -3668),
    o(36856, 177173, -3668),
    o(36538, 177489, -3653),
    o(36221, 177811, -3668),
    o(36150, 175834, -3668),
    o(35835, 176156, -3668),
}

-- =============================================================================
-- TEAM SELECTION LODESTONES
-- =============================================================================
Config.TEAM_SELECT = {
    red    = o(34501, 177490, -3394),
    blue   = o(35523, 178519, -3394),
    random = o(34586, 178363, -3471),
}

-- =============================================================================
-- CLASS LODESTONES (per team)
-- =============================================================================
Config.CLASS_LODESTONES = {
    red = {
        archer    = o(37568, 167182, -3490),
        assassin  = o(38285, 166856, -3489),
        guardian  = o(39021, 166970, -3489),
        berserker = o(40400, 168340, -3489),
        fire_mage = o(40513, 169066, -3489),
        air_mage  = o(40206, 169808, -3489),
    },
    blue = {
        archer    = o(29667, 180097, -3789),
        assassin  = o(28952, 180426, -3789),
        guardian  = o(28218, 180307, -3790),
        berserker = o(26933, 179041, -3804),
        fire_mage = o(26732, 178203, -3805),
        air_mage  = o(27043, 177449, -3804),
    },
}

-- =============================================================================
-- TEAM LOBBY SPAWNS (after team selection, before match)
-- =============================================================================
Config.TEAM_LOBBY_SPAWNS = {
    red = {
        o(39337, 168682, -3611),
        o(39198, 168510, -3611),
        o(38865, 168155, -3611),
        o(38661, 167952, -3611),
    },
    blue = {
        o(27922, 178566, -3611),
        o(28061, 178738, -3611),
        o(28394, 179093, -3611),
        o(28598, 179296, -3611),
    },
}

-- =============================================================================
-- ARENA SPAWNS (match start — fixed initial positions)
-- =============================================================================
Config.TEAM_SPAWN_INITIAL = {
    red = {
        o(37605, 168177, -3284),
        o(38323, 168895, -3284),
        o(36887, 167459, -3284),
        o(38000, 167536, -3284),
        o(36564, 168818, -3284),
        o(39041, 169613, -3284),
        o(36169, 167100, -3284),
    },
    blue = {
        o(29654, 179071, -3284),
        o(28936, 178353, -3284),
        o(30372, 179789, -3284),
        o(29259, 179712, -3284),
        o(30695, 178430, -3284),
        o(28218, 177635, -3284),
        o(31090, 180148, -3284),
    },
}

Config.TEAM_SPAWN_YAW = {red = 135, blue = -45}

-- =============================================================================
-- RANDOM RESPAWN POSITIONS (after death during match)
-- =============================================================================
Config.TEAM_SPAWN_RANDOM = {
    red = {
        o(37605, 168177, -3284),
        o(38323, 168895, -3284),
        o(36887, 167459, -3284),
        o(38000, 167536, -3284),
        o(36564, 168818, -3284),
        o(39041, 169613, -3284),
        o(36169, 167100, -3284),
        o(37282, 169254, -3284),
        o(35810, 168459, -3284),
        o(38682, 168536, -3284),
    },
    blue = {
        o(29654, 179071, -3284),
        o(28936, 178353, -3284),
        o(30372, 179789, -3284),
        o(29259, 179712, -3284),
        o(30695, 178430, -3284),
        o(28218, 177635, -3284),
        o(31090, 180148, -3284),
        o(29977, 177994, -3284),
        o(31449, 178789, -3284),
        o(28577, 178712, -3284),
    },
}

-- =============================================================================
-- PVE SPAWN AREAS (per team, rectangle bounds)
-- =============================================================================
Config.PVE_SPAWN_AREAS = {
    red = {
        min_x = 33025 + OX, max_x = 37381 + OX,
        min_y = 169897 + OY, max_y = 174228 + OY,
        z = -3900 + OZ,
    },
    blue = {
        min_x = 29862 + OX, max_x = 34181 + OX,
        min_y = 173055 + OY, max_y = 177388 + OY,
        z = -3900 + OZ,
    },
}

-- =============================================================================
-- TEAM COLORS
-- =============================================================================
Config.TEAM_COLORS = {
    red  = {R = 1, G = 0.2, B = 0.2, A = 1},
    blue = {R = 0.2, G = 0.4, B = 1, A = 1},
}

-- =============================================================================
-- CLASS DISPLAY NAMES
-- =============================================================================
Config.CLASS_DISPLAY = {
    archer = "ARCHER", assassin = "ASSASSIN", guardian = "GUARDIAN",
    berserker = "BERSERKER", fire_mage = "FIRE MAGE", air_mage = "AIR MAGE",
}

Config.CLASS_LIST = {"archer", "assassin", "guardian", "berserker", "fire_mage", "air_mage"}

-- =============================================================================
-- ASSET PATHS — BASE KIT
-- =============================================================================
Config.BASE_ARMOR = {
    head = "/Game/Gameplay/Character/Player/Equipment/Head/ITEM_Armour_T2_Head_Reinforced.ITEM_Armour_T2_Head_Reinforced",
    body = "/Game/Gameplay/Character/Player/Equipment/Body/ITEM_Armour_T2_Body_Reinforced.ITEM_Armour_T2_Body_Reinforced",
    legs = "/Game/Gameplay/Character/Player/Equipment/Legs/ITEM_Armour_T2_Legs_Reinforced.ITEM_Armour_T2_Legs_Reinforced",
}

Config.BASE_WEAP = {
    SwingSlash = "/Game/Gameplay/Character/Player/Equipment/Held/Mace/ITEM_Club_SwingSlash.ITEM_Club_SwingSlash",
    AshBow     = "/Game/Gameplay/Character/Player/Equipment/Held/Bow/ITEM_Shortbow_Wood.ITEM_Shortbow_Wood",
    BoneArrows = "/Game/Gameplay/Character/Player/Equipment/Ammo/ITEM_Ammo_Arrows_Bone_Bodkin.ITEM_Ammo_Arrows_Bone_Bodkin",
}

-- =============================================================================
-- ASSET PATHS — CAPES
-- =============================================================================
Config.CAPE = {
    RedAdv   = "/Game/Gameplay/Character/Player/Equipment/Cape/ITEM_Cape_Adventurers_Red.ITEM_Cape_Adventurers_Red",
    BlueAdv  = "/Game/Gameplay/Character/Player/Equipment/Cape/ITEM_Cape_Adventurers_Blue.ITEM_Cape_Adventurers_Blue",
    RedDyad  = "/DowdunReach/Gameplay/Character/Player/Equipment/Cape/ITEM_Cape_RedDyad.ITEM_Cape_RedDyad",
    BlueDyad = "/DowdunReach/Gameplay/Character/Player/Equipment/Cape/ITEM_Cape_BlueDyad.ITEM_Cape_BlueDyad",
    RedHex   = "/DowdunReach/Gameplay/Character/Player/Equipment/Cape/ITEM_Cape_RedHex.ITEM_Cape_RedHex",
    BlueHex  = "/DowdunReach/Gameplay/Character/Player/Equipment/Cape/ITEM_Cape_BlueHex.ITEM_Cape_BlueHex",
    Attack   = "/Game/Gameplay/Character/Player/Equipment/Cape/ITEM_Cape_Trimmed_Skillcape_Attack.ITEM_Cape_Trimmed_Skillcape_Attack",
    Magic    = "/Game/Gameplay/Character/Player/Equipment/Cape/ITEM_Cape_Trimmed_Skillcape_Magic.ITEM_Cape_Trimmed_Skillcape_Magic",
}

-- =============================================================================
-- ASSET PATHS — RUNES
-- =============================================================================
Config.RUNE = {
    Air    = "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Air.ITEM_Rune_Air",
    Fire   = "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Fire.ITEM_Rune_Fire",
    Nature = "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Nature.ITEM_Rune_Nature",
    Law    = "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Law.ITEM_Rune_Law",
    Astral = "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Astral.ITEM_Rune_Astral",
}

-- =============================================================================
-- ASSET PATHS — CLASS RUNES (given at specialization)
-- =============================================================================
Config.CLASS_RUNES = {
    archer    = {{Config.RUNE.Astral, 75}, {Config.RUNE.Nature, 50}},
    assassin  = {{Config.RUNE.Air, 75}, {Config.RUNE.Astral, 25}},
    guardian  = {{Config.RUNE.Air, 75}},
    berserker = {{Config.RUNE.Fire, 75}, {Config.RUNE.Astral, 25}},
    fire_mage = {{Config.RUNE.Fire, 2000}, {Config.RUNE.Astral, 50}, {Config.RUNE.Law, 50}},
    air_mage  = {{Config.RUNE.Air, 2000}, {Config.RUNE.Astral, 50}, {Config.RUNE.Law, 50}},
}

-- =============================================================================
-- ASSET PATHS — TRINKETS (earned at 12 kills)
-- =============================================================================
Config.TRINKETS = {
    archer    = "/Game/Gameplay/Character/Player/Equipment/Jewellery/ITEM_Trinket_Iconic_Amulet_of_Accuracy.ITEM_Trinket_Iconic_Amulet_of_Accuracy",
    assassin  = "/DowdunReach/Gameplay/Character/Player/Equipment/Jewellery/ITEM_Trinket_Unholy_Symbol.ITEM_Trinket_Unholy_Symbol",
    guardian  = "/Game/Gameplay/Character/Player/Equipment/Jewellery/ITEM_Trinket_Iconic_Ring_of_Recoil.ITEM_Trinket_Iconic_Ring_of_Recoil",
    berserker = "/Game/Gameplay/Character/Player/Equipment/Jewellery/ITEM_Trinket_Iconic_Amulet_of_Strength.ITEM_Trinket_Iconic_Amulet_of_Strength",
    fire_mage = "/Game/Gameplay/Character/Player/Equipment/Jewellery/ITEM_Trinket_Iconic_Amulet_of_Magic.ITEM_Trinket_Iconic_Amulet_of_Magic",
    air_mage  = "/Game/Gameplay/Character/Player/Equipment/Jewellery/ITEM_Trinket_Iconic_Amulet_of_Magic.ITEM_Trinket_Iconic_Amulet_of_Magic",
}

-- =============================================================================
-- ASSET PATHS — TORCH (flag carrier)
-- =============================================================================
Config.TORCH_ITEM = "/Game/Gameplay/Character/Player/Equipment/Held/Torch/ITEM_Torch.ITEM_Torch"
Config.ANIMA_ASSET = "/Game/Gameplay/BaseBuilding_New/BuildingPieces/Decorations/Materials/Basic/BP_BaseBuilding_Decoration_Material_Anima_Wild.BP_BaseBuilding_Decoration_Material_Anima_Wild_C"

-- =============================================================================
-- ASSET PATHS — CLASS ARMOR (indexed [1]=T3, [2]=T4, [3]=T5, [4]=T6)
-- =============================================================================
local G = "/Game/Gameplay/Character/Player/Equipment"
local D = "/DowdunReach/Gameplay/Character/Player/Equipment"

local function armor(tier, set)
    local prefix = tier <= 5 and G or D
    return {
        head = prefix .. "/Head/ITEM_Armour_T" .. tier .. "_Head_" .. set .. ".ITEM_Armour_T" .. tier .. "_Head_" .. set,
        body = prefix .. "/Body/ITEM_Armour_T" .. tier .. "_Body_" .. set .. ".ITEM_Armour_T" .. tier .. "_Body_" .. set,
        legs = prefix .. "/Legs/ITEM_Armour_T" .. tier .. "_Legs_" .. set .. ".ITEM_Armour_T" .. tier .. "_Legs_" .. set,
    }
end

Config.CLASS_ARMOR = {
    archer    = {armor(3, "HardLeather"),   armor(4, "WildArcher"),      armor(5, "Ranger"),       armor(6, "BlackRanger")},
    assassin  = {armor(3, "HardLeather"),   armor(4, "StuddedLeather"),  armor(5, "GreenDragonHide"),
        {head = D .. "/Head/ITEM_Armour_T6_Head_BlueDragonhide.ITEM_Armour_T6_Head_BlueDragonhide",
         body = D .. "/Body/ITEM_Armour_T6_Body_BlueDragonHide.ITEM_Armour_T6_Body_BlueDragonHide",
         legs = D .. "/Legs/ITEM_Armour_T6_Legs_BlueDragonhide.ITEM_Armour_T6_Legs_BlueDragonhide"}},
    guardian  = {armor(3, "Bronze"),         armor(4, "Paladin"),         armor(5, "White"),        armor(6, "Mithril")},
    berserker = {armor(3, "Bronze"),         armor(4, "Iron"),            armor(5, "Skeleton"),     armor(6, "Black")},
    fire_mage = {armor(3, "Wizard"),         armor(4, "DragonkinMage"),   armor(5, "Necromancer"),  armor(6, "Zamorak")},
    air_mage  = {armor(3, "Wizard"),         armor(4, "DarkMage"),        armor(5, "Splitbark"),    armor(6, "Mystic")},
}

-- =============================================================================
-- ASSET PATHS — CLASS WEAPONS (indexed [1]=T3, [2]=T4, [3]=T5, [4]=T6)
-- Weapons are arrays (some classes have 2: weapon + shield, or shortbow + longbow)
-- =============================================================================
local H = G .. "/Held"

local DH = D .. "/Held"  -- DowdunReach held equipment path

Config.CLASS_WEAP = {
    archer = {
        {H .. "/Bow/ITEM_Shortbow_Oak.ITEM_Shortbow_Oak", H .. "/Bow/ITEM_Longbow_Oak.ITEM_Longbow_Oak"},
        {H .. "/Bow/ITEM_Shortbow_Hunter.ITEM_Shortbow_Hunter", H .. "/Bow/ITEM_Longbow_Hunter.ITEM_Longbow_Hunter"},
        {H .. "/Bow/ITEM_Shortbow_Willow.ITEM_Shortbow_Willow", H .. "/Bow/ITEM_Longbow_Willow.ITEM_Longbow_Willow"},
        {DH .. "/Bow/ITEM_Shortbow_Maple.ITEM_Shortbow_Maple", DH .. "/Bow/ITEM_Longbow_Maple.ITEM_Longbow_Maple"},
    },
    assassin = {
        {H .. "/Dagger/ITEM_Dagger_Bronze.ITEM_Dagger_Bronze"},
        {H .. "/Dagger/ITEM_Dagger_Iron.ITEM_Dagger_Iron"},
        {H .. "/Dagger/ITEM_Dagger_Steel.ITEM_Dagger_Steel"},
        {DH .. "/Dagger/ITEM_Dagger_Mithril.ITEM_Dagger_Mithril"},
    },
    guardian = {
        {H .. "/Sword/ITEM_Sword_Bronze.ITEM_Sword_Bronze", H .. "/Shield/ITEM_Shield_Bronze.ITEM_Shield_Bronze"},
        {H .. "/Sword/ITEM_Sword_Iron.ITEM_Sword_Iron", H .. "/Shield/ITEM_Shield_Iron.ITEM_Shield_Iron"},
        {H .. "/Sword/ITEM_Sword_Steel.ITEM_Sword_Steel", H .. "/Shield/ITEM_Shield_Steel.ITEM_Shield_Steel"},
        {DH .. "/Sword/ITEM_Sword_Mithril.ITEM_Sword_Mithril", DH .. "/Shield/ITEM_Shield_Mithril.ITEM_Shield_Mithril"},
    },
    berserker = {
        {H .. "/GreatSword/ITEM_GreatSword_Bronze.ITEM_GreatSword_Bronze"},
        {H .. "/GreatSword/ITEM_GreatSword_Iron.ITEM_GreatSword_Iron"},
        {H .. "/GreatSword/ITEM_GreatSword_Steel.ITEM_GreatSword_Steel"},
        {DH .. "/GreatSword/ITEM_GreatSword_Mithril.ITEM_GreatSword_Mithril"},
    },
    fire_mage = {
        {H .. "/Staff/ITEM_Staff_Garou.ITEM_Staff_Garou"},
        {H .. "/Staff/ITEM_Staff_Battlestaff.ITEM_Staff_Battlestaff"},
        {H .. "/Staff/ITEM_Staff_Splitbark.ITEM_Staff_Splitbark"},
        {DH .. "/Staff/ITEM_Staff_Maple.ITEM_Staff_Maple"},
    },
    air_mage = {
        {H .. "/Staff/ITEM_Staff_Oak.ITEM_Staff_Oak"},
        {H .. "/Staff/ITEM_Staff_Battlestaff.ITEM_Staff_Battlestaff"},
        {H .. "/Staff/ITEM_Staff_Splitbark.ITEM_Staff_Splitbark"},
        {DH .. "/Staff/ITEM_Staff_Maple.ITEM_Staff_Maple"},
    },
}

-- =============================================================================
-- ARCHER AMMO (tiered, indexed [1]=T3, [2]=T4, [3]=T5, [4]=T6)
-- =============================================================================
Config.ARCHER_AMMO = {
    [1] = G .. "/Ammo/ITEM_Ammo_Arrows_Bronze_Bodkin.ITEM_Ammo_Arrows_Bronze_Bodkin",
    [2] = G .. "/Ammo/ITEM_Ammo_Arrows_Iron_Bodkin.ITEM_Ammo_Arrows_Iron_Bodkin",
    [3] = G .. "/Ammo/ITEM_Ammo_Arrows_Steel_Bodkin.ITEM_Ammo_Arrows_Steel_Bodkin",
    [4] = D .. "/Ammo/ITEM_Ammo_Arrows_Mithril_Bodkin.ITEM_Ammo_Arrows_Mithril_Bodkin",
}

-- =============================================================================
-- PVE MOB DEFINITIONS (3 events)
-- =============================================================================
Config.PVE_EVENTS = {
    [1] = {
        name = "GAROU ASSAULT",
        power_level = 4,
        reward_tier = 4,
        mobs = {
            wolf    = "wolf",
            archer  = "garou_hunter",
            mage    = "garou_druid",
            tank    = "garou_berserker",
            boss    = "abyssal_demon",
        },
    },
    [2] = {
        name = "ROTSWORN INVASION",
        power_level = 5,
        reward_tier = 5,
        mobs = {
            wolf    = "dragonwolf",
            archer  = "skeletal_archer",
            mage    = "rotsworn_necromancer",
            tank    = "rotsworn_marauder",
            boss    = "zogre",
        },
    },
    [3] = {
        name = "DARK SIEGE",
        power_level = 6,
        reward_tier = 6,
        mobs = {
            wolf    = "hellhound_fido",
            archer  = "blackknight_ranged",
            mage    = "mage_of_zamorak",
            tank    = "blackknight_2h",
            boss    = "dragon_blue",
        },
    },
}

-- =============================================================================
-- MOB ASSET PATHS
-- =============================================================================
Config.MOB_CLASSES = {
    wolf                 = "/Game/Gameplay/AI/Wolf/BP_AI_Wolf_Character.BP_AI_Wolf_Character_C",
    garou_hunter         = "/Game/Gameplay/AI/BeastFaction/RangedBeast/BP_AI_RangedBeast_Character.BP_AI_RangedBeast_Character_C",
    garou_druid          = "/Game/Gameplay/AI/BeastFaction/MagicBeast/BP_AI_MagicBeast_Character.BP_AI_MagicBeast_Character_C",
    garou_berserker      = "/Game/Gameplay/AI/BeastFaction/MediumBeast/BP_AI_MediumBeast_Character.BP_AI_MediumBeast_Character_C",
    abyssal_demon        = "/Game/Gameplay/AI/AbyssalDemon/BP_AI_AbyssalDemon_Character.BP_AI_AbyssalDemon_Character_C",
    dragonwolf           = "/FutureMajorVersion/Gameplay/AI/Wolf/DragonWolf/BP_AI_DragonWolf_Character.BP_AI_DragonWolf_Character_C",
    skeletal_archer      = "/FutureMajorVersion/Gameplay/AI/SkeletonFaction/RangedSkeleton/BP_AI_SkeletalArcher_Character.BP_AI_SkeletalArcher_Character_C",
    rotsworn_necromancer = "/FutureMajorVersion/Gameplay/AI/SkeletonFaction/MagicSkeleton/BP_AI_RotswornNecromancer_Character.BP_AI_RotswornNecromancer_Character_C",
    rotsworn_marauder    = "/FutureMajorVersion/Gameplay/AI/SkeletonFaction/MeleeSkeleton/TwoHandSwordVariant/WitheredVariant/BP_AI_RotswornMarauder_Character.BP_AI_RotswornMarauder_Character_C",
    zogre                = "/FutureMajorVersion/Gameplay/AI/ZombieFaction/Zogre/BP_AI_Zogre_Character.BP_AI_Zogre_Character_C",
    hellhound_fido       = "/DowdunReach/Gameplay/AI/Wildlife/Hellhound/MiniBossVariant/BP_AI_HellHound_Minion_Fido_Character.BP_AI_HellHound_Minion_Fido_Character_C",
    blackknight_ranged   = "/DowdunReach/Gameplay/AI/BlackKnightFaction/RangedBlackKnight/BP_AI_BlackKnightRanged_Character.BP_AI_BlackKnightRanged_Character_C",
    mage_of_zamorak      = "/DowdunReach/Gameplay/AI/ZamorakianMageFaction/ZamorakianMage/BP_AI_MageOfZamorak_Character.BP_AI_MageOfZamorak_Character_C",
    blackknight_2h       = "/DowdunReach/Gameplay/AI/BlackKnightFaction/2HMeleeBlackKnight/BP_AI_Melee2HBlackKnight_Character.BP_AI_Melee2HBlackKnight_Character_C",
    dragon_blue          = "/DowdunReach/Gameplay/AI/Bosses/LesserBlueDragon/BP_AI_DragonLesserBlue_Character.BP_AI_DragonLesserBlue_Character_C",
}

-- =============================================================================
-- SPELL BLOCKING
-- =============================================================================
Config.WINDSTEP_PATH = "/Game/Gameplay/UtilityMagic/PerkSpells/Windstep/USD_Windstep.USD_Windstep"
Config.WINDSTEP_BLOCKED_CD = 9999.0
Config.WINDSTEP_NORMAL_CD = 3.0

-- =============================================================================
-- DECORATIVE TREES (auto-spawn on startup, session-only)
-- =============================================================================
Config.ARENA_TREES = {
    -- Oak trees (4 corners)
    {class = "BP_BM_Tree_Oak_02_C", pos = {X = 71152, Y = 165201, Z = 17789}, yaw = 0},
    {class = "BP_BM_Tree_Oak_02_C", pos = {X = 73060, Y = 167108, Z = 17789}, yaw = 0},
    {class = "BP_BM_Tree_Oak_02_C", pos = {X = 64774, Y = 175401, Z = 17788}, yaw = 180},
    {class = "BP_BM_Tree_Oak_02_C", pos = {X = 62847, Y = 173499, Z = 17788}, yaw = 180},
    -- Ash trees (side 1 — blue edge)
    {class = "BP_BM_Tree_Ash_03_C", pos = {X = 66545, Y = 175309, Z = 17789}, yaw = 0},
    {class = "BP_BM_Tree_Ash_03_C", pos = {X = 67193, Y = 174674, Z = 17788}, yaw = 0},
    {class = "BP_BM_Tree_Ash_03_C", pos = {X = 67821, Y = 174039, Z = 17788}, yaw = 0},
    {class = "BP_BM_Tree_Ash_03_C", pos = {X = 68460, Y = 173395, Z = 17788}, yaw = 0},
    {class = "BP_BM_Tree_Ash_03_C", pos = {X = 69098, Y = 172763, Z = 17788}, yaw = 0},
    {class = "BP_BM_Tree_Ash_03_C", pos = {X = 69737, Y = 172127, Z = 17788}, yaw = 0},
    {class = "BP_BM_Tree_Ash_03_C", pos = {X = 70371, Y = 171488, Z = 17788}, yaw = 0},
    {class = "BP_BM_Tree_Ash_03_C", pos = {X = 71008, Y = 170850, Z = 17788}, yaw = 0},
    {class = "BP_BM_Tree_Ash_03_C", pos = {X = 71641, Y = 170218, Z = 17788}, yaw = 0},
    {class = "BP_BM_Tree_Ash_03_C", pos = {X = 72280, Y = 169582, Z = 17788}, yaw = 0},
    {class = "BP_BM_Tree_Ash_03_C", pos = {X = 72932, Y = 168934, Z = 17788}, yaw = 0},
    -- Ash trees (side 2 — red edge)
    {class = "BP_BM_Tree_Ash_03_C", pos = {X = 69419, Y = 165237, Z = 17788}, yaw = 180},
    {class = "BP_BM_Tree_Ash_03_C", pos = {X = 68744, Y = 165909, Z = 17789}, yaw = 180},
    {class = "BP_BM_Tree_Ash_03_C", pos = {X = 68104, Y = 166544, Z = 17789}, yaw = 180},
    {class = "BP_BM_Tree_Ash_03_C", pos = {X = 67472, Y = 167179, Z = 17788}, yaw = 180},
    {class = "BP_BM_Tree_Ash_03_C", pos = {X = 66836, Y = 167817, Z = 17788}, yaw = 180},
    {class = "BP_BM_Tree_Ash_03_C", pos = {X = 66197, Y = 168454, Z = 17788}, yaw = 180},
    {class = "BP_BM_Tree_Ash_03_C", pos = {X = 65559, Y = 169095, Z = 17788}, yaw = 180},
    {class = "BP_BM_Tree_Ash_03_C", pos = {X = 64929, Y = 169733, Z = 17788}, yaw = 180},
    {class = "BP_BM_Tree_Ash_03_C", pos = {X = 64290, Y = 170369, Z = 17788}, yaw = 180},
    {class = "BP_BM_Tree_Ash_03_C", pos = {X = 63654, Y = 171000, Z = 17788}, yaw = 180},
    {class = "BP_BM_Tree_Ash_03_C", pos = {X = 62856, Y = 171793, Z = 17788}, yaw = 180},
}

return Config
