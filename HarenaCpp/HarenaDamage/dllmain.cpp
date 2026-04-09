#include <Mod/CppUserModBase.hpp>
#include <DynamicOutput/DynamicOutput.hpp>

using namespace RC;

class HarenaDamageMod : public CppUserModBase
{
public:
    HarenaDamageMod() : CppUserModBase()
    {
        ModName = STR("HarenaDamage");
        ModVersion = STR("1.0.0");
        ModDescription = STR("Pre-damage friendly fire prevention for Harena CTF");
        ModAuthors = STR("Jacob");
    }

    virtual ~HarenaDamageMod() {}

    virtual void on_unreal_init() override
    {
        Output::send<LogLevel::Verbose>(STR("[HarenaDamage] Mod initialized — ready to register hooks\n"));
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
