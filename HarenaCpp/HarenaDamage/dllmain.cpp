#include <Mod/CppUserModBase.hpp>
#include <DynamicOutput/DynamicOutput.hpp>
#include <Unreal/UObjectGlobals.hpp>
#include <Unreal/UObject.hpp>
#include <Unreal/UFunction.hpp>
#include <Unreal/Hooks.hpp>

using namespace RC;
using namespace RC::Unreal;

// Stored original function pointers
static UnrealScriptFunction OrigMeleeDmgCache = nullptr;
static UnrealScriptFunction OrigMeleeAttack = nullptr;
static UnrealScriptFunction OrigSpellPayload = nullptr;

// Team data
static bool ff_enabled = false;

// Replacement functions that log and skip the original
static void BlockedMeleeDmgCache(UObject* Context, FFrame& Stack, void* RESULT_DECL)
{
    Output::send<LogLevel::Warning>(STR("[HD] BLOCKED melee DmgCache\n"));
    // Don't call original — damage cache not sent
}

static void BlockedMeleeAttack(UObject* Context, FFrame& Stack, void* RESULT_DECL)
{
    Output::send<LogLevel::Warning>(STR("[HD] BLOCKED melee Attack\n"));
    // Don't call original
}

static void BlockedSpellPayload(UObject* Context, FFrame& Stack, void* RESULT_DECL)
{
    Output::send<LogLevel::Warning>(STR("[HD] BLOCKED spell payload\n"));
    // Don't call original
}

class HarenaDamageMod : public CppUserModBase
{
public:
    HarenaDamageMod() : CppUserModBase()
    {
        ModName = STR("HarenaDamage");
        ModVersion = STR("2.0.0");
        ModDescription = STR("FF prevention via SetFuncPtr — blocks all player attack multicasts");
        ModAuthors = STR("Jacob");
    }

    virtual ~HarenaDamageMod() {}

    virtual void on_unreal_init() override
    {
        Output::send<LogLevel::Verbose>(STR("[HD] v2.0.0 — SetFuncPtr block test\n"));

        // Hook melee damage cache
        UFunction* MeleeDmgCache = UObjectGlobals::StaticFindObject<UFunction*>(
            nullptr, nullptr, STR("/Script/Dominion.PlayerMeleeAttackComponent:Multicast_SendDamageCacheData")
        );
        if (MeleeDmgCache)
        {
            OrigMeleeDmgCache = MeleeDmgCache->GetFuncPtr();
            MeleeDmgCache->SetFuncPtr(BlockedMeleeDmgCache);
            Output::send<LogLevel::Verbose>(STR("[HD] Replaced MeleeDmgCache func ptr\n"));
        }
        else
        {
            Output::send<LogLevel::Error>(STR("[HD] MISS: MeleeDmgCache\n"));
        }

        // Hook melee attack multicast
        UFunction* MeleeAttack = UObjectGlobals::StaticFindObject<UFunction*>(
            nullptr, nullptr, STR("/Script/Dominion.PlayerAttackComponent:Multicast_PerformAttackOnSimulatedProxies")
        );
        if (MeleeAttack)
        {
            OrigMeleeAttack = MeleeAttack->GetFuncPtr();
            MeleeAttack->SetFuncPtr(BlockedMeleeAttack);
            Output::send<LogLevel::Verbose>(STR("[HD] Replaced MeleeAttack func ptr\n"));
        }
        else
        {
            Output::send<LogLevel::Error>(STR("[HD] MISS: MeleeAttack\n"));
        }

        // Hook spell payload
        UFunction* SpellPayload = UObjectGlobals::StaticFindObject<UFunction*>(
            nullptr, nullptr, STR("/Script/Dominion.PlayerMagicComponent:Multicast_SendPayloadForSpellCasting")
        );
        if (SpellPayload)
        {
            OrigSpellPayload = SpellPayload->GetFuncPtr();
            SpellPayload->SetFuncPtr(BlockedSpellPayload);
            Output::send<LogLevel::Verbose>(STR("[HD] Replaced SpellPayload func ptr\n"));
        }
        else
        {
            Output::send<LogLevel::Error>(STR("[HD] MISS: SpellPayload\n"));
        }

        Output::send<LogLevel::Verbose>(STR("[HD] All player attack functions replaced with no-ops.\n"));
        Output::send<LogLevel::Verbose>(STR("[HD] WARNING: This blocks ALL player damage (including to mobs from players).\n"));
        Output::send<LogLevel::Verbose>(STR("[HD] Players should not be able to damage each other.\n"));
    }

    virtual void on_update() override
    {
    }
};

extern "C"
{
    __declspec(dllexport) CppUserModBase* start_mod()
    {
        return new HarenaDamageMod();
    }

    __declspec(dllexport) void uninstall_mod(CppUserModBase* mod)
    {
        delete mod;
    }
}
