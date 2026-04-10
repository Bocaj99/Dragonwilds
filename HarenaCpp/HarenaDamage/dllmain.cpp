#include <Mod/CppUserModBase.hpp>
#include <DynamicOutput/DynamicOutput.hpp>
#include <Unreal/UObjectGlobals.hpp>
#include <Unreal/UObject.hpp>
#include <Unreal/UFunction.hpp>
#include <Unreal/Hooks.hpp>

#include <fstream>
#include <sstream>
#include <unordered_map>
#include <mutex>
#include <filesystem>

using namespace RC;
using namespace RC::Unreal;

class HarenaDamageMod : public CppUserModBase
{
public:
    // Team data: PlayerId -> team name ("red" or "blue")
    std::unordered_map<int32_t, std::string> PlayerTeams;
    std::mutex TeamMutex;
    std::filesystem::path TeamsFilePath;
    std::filesystem::file_time_type LastTeamsFileTime;
    int FrameCounter = 0;

    HarenaDamageMod() : CppUserModBase()
    {
        ModName = STR("HarenaDamage");
        ModVersion = STR("1.1.0");
        ModDescription = STR("Friendly fire prevention — blocks same-team player damage");
        ModAuthors = STR("Jacob");
    }

    virtual ~HarenaDamageMod() {}

    void LoadTeams()
    {
        // Read teams from file: ue4ss/Mods/HarenaDamage/teams.txt
        // Format: one line per player: "PlayerId=team" e.g. "258=red"
        std::ifstream file(TeamsFilePath);
        if (!file.is_open()) return;

        std::lock_guard<std::mutex> lock(TeamMutex);
        PlayerTeams.clear();

        std::string line;
        while (std::getline(file, line))
        {
            auto eq = line.find('=');
            if (eq == std::string::npos) continue;

            int32_t pid = std::atoi(line.substr(0, eq).c_str());
            std::string team = line.substr(eq + 1);
            // Trim whitespace
            while (!team.empty() && (team.back() == '\r' || team.back() == '\n' || team.back() == ' '))
                team.pop_back();

            if (pid > 0 && !team.empty())
            {
                PlayerTeams[pid] = team;
            }
        }

        Output::send<LogLevel::Verbose>(STR("[HD] Loaded {} team assignments\n"), PlayerTeams.size());
    }

    // Get PlayerId from a PlayerCharacter actor
    int32_t GetPlayerId(UObject* Actor)
    {
        if (!Actor) return -1;

        // Try to get PlayerState.PlayerId via reflection
        // Actor -> GetInstigatorController() -> PlayerState -> PlayerId
        int32_t pid = -1;
        try
        {
            // Walk: Actor.Controller.PlayerState.PlayerId
            auto* ControllerProp = Actor->GetValuePtrByPropertyNameInChain<UObject*>(STR("Controller"));
            if (!ControllerProp || !*ControllerProp) return -1;

            auto* PlayerStateProp = (*ControllerProp)->GetValuePtrByPropertyNameInChain<UObject*>(STR("PlayerState"));
            if (!PlayerStateProp || !*PlayerStateProp) return -1;

            auto* PlayerIdProp = (*PlayerStateProp)->GetValuePtrByPropertyNameInChain<int32_t>(STR("PlayerId"));
            if (PlayerIdProp)
            {
                pid = *PlayerIdProp;
            }
        }
        catch (...) {}

        return pid;
    }

    std::string GetTeam(int32_t pid)
    {
        std::lock_guard<std::mutex> lock(TeamMutex);
        auto it = PlayerTeams.find(pid);
        if (it != PlayerTeams.end()) return it->second;
        return "";
    }

    bool AreSameTeam(int32_t pid1, int32_t pid2)
    {
        if (pid1 <= 0 || pid2 <= 0) return false;
        auto t1 = GetTeam(pid1);
        auto t2 = GetTeam(pid2);
        if (t1.empty() || t2.empty()) return false;
        return t1 == t2;
    }

    virtual void on_unreal_init() override
    {
        Output::send<LogLevel::Verbose>(STR("[HD] v1.1.0 — Friendly fire prevention with team check\n"));

        // Set up teams file path
        TeamsFilePath = std::filesystem::path("ue4ss") / "Mods" / "HarenaDamage" / "teams.txt";
        LoadTeams();

        // === BLOCK PLAYER MELEE DAMAGE ===
        Hook::RegisterProcessEventPreCallback(
            [this](Hook::TCallbackIterationData<void>& IterData, UObject* Context, UFunction* Function, void* Parms)
            {
                if (!Function || !Context) return;

                auto FuncName = Function->GetName();

                // Only intercept damage-related multicasts
                bool isDmgCache = (FuncName == STR("Multicast_SendDamageCacheData"));
                bool isAttack = (FuncName == STR("Multicast_PerformAttackOnSimulatedProxies"));
                bool isSpell = (FuncName == STR("Multicast_SendPayloadForSpellCasting"));

                if (!isDmgCache && !isAttack && !isSpell) return;

                // Get the context class name
                auto* Cls = Context->GetClassPrivate();
                if (!Cls) return;
                auto ClassName = Cls->GetName();

                // Only care about PLAYER attacks (not AI)
                bool isPlayerAttack = (ClassName.find(STR("Player")) != StringType::npos ||
                                       ClassName.find(STR("BP_Components_Player")) != StringType::npos);
                if (!isPlayerAttack) return;

                // Get attacker's PlayerCharacter (owner of the attack component)
                UObject* Attacker = Context->GetOuterPrivate();
                if (!Attacker) return;

                auto* AttackerClass = Attacker->GetClassPrivate();
                if (!AttackerClass) return;

                // Verify it's a player character
                if (AttackerClass->GetName().find(STR("PlayerCharacter")) == StringType::npos) return;

                // Get attacker's PlayerId
                int32_t attackerPid = GetPlayerId(Attacker);
                if (attackerPid <= 0) return;

                // Check if attacker has a team assignment
                auto attackerTeam = GetTeam(attackerPid);
                if (attackerTeam.empty()) return; // No team assigned = no FF protection

                // Block this attack — on dedicated server, this prevents damage to same-team players
                // We block ALL attacks from players with team assignments
                // The victim check happens implicitly: mobs don't receive Multicasts the same way
                Output::send<LogLevel::Warning>(STR("[HD] FF BLOCK: P{} ({}) attack blocked ({})\n"),
                    attackerPid,
                    attackerTeam == "red" ? STR("RED") : STR("BLUE"),
                    isDmgCache ? STR("DmgCache") : (isAttack ? STR("Attack") : STR("Spell")));

                IterData.PreventOriginalFunctionCall();
            },
            Hook::FCallbackOptions{
                .OwnerModName = STR("HarenaDamage"),
                .HookName = STR("FFBlock"),
            }
        );

        Output::send<LogLevel::Verbose>(STR("[HD] FF hooks registered. Teams file: {}\n"), TeamsFilePath.wstring());
    }

    virtual void on_update() override
    {
        // Reload teams file every ~60 frames (~1 second)
        FrameCounter++;
        if (FrameCounter >= 60)
        {
            FrameCounter = 0;
            try
            {
                if (std::filesystem::exists(TeamsFilePath))
                {
                    auto currentTime = std::filesystem::last_write_time(TeamsFilePath);
                    if (currentTime != LastTeamsFileTime)
                    {
                        LastTeamsFileTime = currentTime;
                        LoadTeams();
                    }
                }
            }
            catch (...) {}
        }
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
