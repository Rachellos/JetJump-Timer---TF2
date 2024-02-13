#define MAX_COMMANDS 1000

#define TIME_SIZE_DEF 15
#define FORMAT_2DECI 0
#define FORMAT_3DECI 1

#define RUNS_LIMIT 100
#define ZONES_LIMIT RUNS_LIMIT * 3

#define NULL_VEC {0.0, 0.0, 0.0}

#define RECORDS_LIMIT 10000

#define BRUSH_MODEL "models/props/cs_office/vending_machine.mdl"

enum struct ServerInfo
{
    int id;
    char ip[32];
    int port;

    char name[128];
    char currentMap[128];

    int players;
    int maxPlayers;

    bool isOnline;
}

enum State
{
    STATE_INVALID = -1,

    STATE_START,
    STATE_RUNNING,
    STATE_END,

    NUM_STATE
}

enum Class
{
    CLASS_INVALID = -1,

    CLASS_SOLDIER,
    CLASS_DEMOMAN,
    CLASS_BOTH,

    NUM_CLASS
}

enum RunType
{
    RUN_INVALID = -1,

    RUN_MAP,
    RUN_STAGE,
    RUN_BONUS,

    NUM_RUNS
}

enum struct RunInfo
{
    int index;
    
    int completions[NUM_CLASS];
    int tier[NUM_CLASS];

    char runName[64];
}

enum struct Records
{
    int record_id;

    int player_id;

    char player_name[32];

    Class class;

    RunType runType;

    int runIndex;

    float time;
    float points;
    int rank;

    bool exists;
}

enum struct StageEnterTime
{
    int record_id;
    
    int player_id;

    Class class;

    int stage_id;

    float time;

    bool exists;
}

enum struct Checkpoint
{
    int num;
}

enum struct Run
{
    RunType type;

    RunInfo info;

    Records personalRecord;
    Records worldRecord;

    float stageEnterTime[RECORDS_LIMIT];
    StageEnterTime stageEnterPersonalRecord;
    StageEnterTime stageEnterWorldRecord;

    Checkpoint checkpoint;

    float startTime;
    float finishTime;

    float stageStartTime;
    float stageFinishTime;

    // if CLASS_SOLDIER -> enable ammo regen for soldier and etc.
    // if -1 then disable regen for both classes
    Class regenAmmo;

    bool linearMode;
}

enum struct MapInfo
{
    int id;
    char name[64];
}

enum Zones
{
    ZONE_INVALID = -1,

    ZONE_START,
    ZONE_END,
    ZONE_CHECKPOINT
}

enum struct Zone
{
    RunType runType;

    RunInfo runInfo;

    Zones zoneType;

    int zoneIndex;

    int arrayId;

    int ent;

    Class regen_ammo;
    
    float cordMin[3];
    float cordMax[3];
    float spawnPos[3];
    float spawnAng[3];

    bool exists;
}

enum struct Lobby
{
    int id;

    int serverHost_id;

    char ip[64];
    int port;

    Socket serverSocket;
    ArrayList lobbyConnectionsData;
    
    int creator_id;

    char password[32];
    char lobbyName[32];

    bool exists;
}

enum struct Player
{
    int id;
    int clientIndex;
    int soldierRank;
    int demomanRank;

    // player settings (hud, sounds etc)
    int settingsFlags;

    char name[32];
    char steamid[255];
    char steamid64[255];
    char ip[32];
    char country[64];

    bool isTimerOn;
    bool isIdle;
    bool isAdmin;

    float overallPoints;
    float soldierPoints;
    float demomanPoints;

    Zone currentZone;

    State state;

    Class currentClass;

    Socket ServerSocket;
    Lobby currentLobby;

    float setStartPos[3];
    float setStartAng[3];
    bool setStartExists;

    Menu previousMenu[100];

    int GetNewPrevMenuIndex()
    {
        for (int i=0; i < 100; i++)
        {
            if (this.previousMenu[i] == null || this.previousMenu[i] == INVALID_HANDLE)
                return i;
        }
        return 99;
    }

    int GetLastPrevMenuIndex()
    {
        for (int i=99; i >= 0; i--)
        {
            if (this.previousMenu[i] != null && this.previousMenu[i] != INVALID_HANDLE)
                return i;
        }
        return -1;
    }

    void SetNewPrevMenu(Menu menu)
    {
        this.previousMenu[this.GetNewPrevMenuIndex()] = menu;
    }

    void RemoveLastPrevMenu()
    {
        if (this.GetLastPrevMenuIndex() != -1)
        {
            if (this.previousMenu[this.GetLastPrevMenuIndex()] != null 
                && this.previousMenu[this.GetLastPrevMenuIndex()] != INVALID_HANDLE)
            {
                this.previousMenu[this.GetLastPrevMenuIndex()] = null;
            }
        }
    }

    void RemoveAllPrevMenus()
    {
        for (int i = 0; i < 10; i++)
        {
            if (this.previousMenu[i] != null && this.previousMenu[i] != INVALID_HANDLE)
            {
                this.previousMenu[i] = null;
            }
        }
    }

    void CallPrevMenu()
    {
        if (this.GetLastPrevMenuIndex() != -1)
        {
            if (this.previousMenu[this.GetLastPrevMenuIndex()] != null 
                && this.previousMenu[this.GetLastPrevMenuIndex()] != INVALID_HANDLE)
            {
                this.previousMenu[this.GetLastPrevMenuIndex()].Display(this.clientIndex, MENU_TIME_FOREVER);
            }
        }
    }
}

enum struct ChatTitles
{
    char TitleName[64];
    char titleColor[32];
    char bracketsColor[32];
    char messageColor[32];

    bool isSpectating;
}

enum struct Commands
{
    char commandName[128];
    char description[256];

    ConCmd callback;

    int AdminFlag;

    bool isMainCommand;
    bool exists;
}

/**
 * Called when a client touch some zone
 *
 * @param client        Client index
 * @param run_type        Run Type (map, stage, bonus)
 * @param zone_type        Zone Type (start, end, checkpoint) *If touch checkpoint, then run_type will be RUN_INVALID
 * @param run_id        Run Number ( (stage || bonus || checkpoint) Number) *Map runs always return 1
 */
forward void JetJump_OnZoneEntered(int client, RunType run_type, Zones zone_type, int run_id);

/**
 * Called when a client finish run
 *
 * @param client        Client index
 * @param run_type        Run Type (map, stage, bonus)
 * @param run_id        Run Number ( (stage || bonus) Number) *Map runs always return 1
 * @param shouldSave    default is False. True if the player improves their personal best record or completes the map for the first time.
 */
forward void JetJump_OnRunFinished(int client, RunType run_type, int run_id, bool shouldSave = false);

/**
 * Returns the current client Run Type
 *
 * @param client        Client index
 * @return              RunType enum value.
 * @error               If the client not running.
 */
native RunType JetJump_GetRunType(int client);

/**
 * Returns the current Zone Type
 *
 * @param client        Client index
 * @return              Zones enum value.
 * @error               ZONE_INVALID If the client not state at the some zones from Zones enum.
 */
native Zones JetJump_GetZoneType(int client);

/**
 * Returns the current Run Id
 *
 * @param client        Client index
 * @return              Run number int value. *If Map, then return 1
 * @error               -1 If the client not running anything.
 */
native int JetJump_GetRunId(int client);

/**
 * Returns the current Run Id
 *
 * @param client        Client index
 * @return              True if timer enabled, else False
 */
native bool JetJump_IsTimerEnabled(int client);

public SharedPlugin __pl_JetJump = {
	name = "JetJump",
	file = "JetJump.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_JetJump_SetNTVOptional() {
	MarkNativeAsOptional("JetJump_GetRunType");
	MarkNativeAsOptional("JetJump_GetZoneType");
    MarkNativeAsOptional("JetJump_GetRunId");
    MarkNativeAsOptional("JetJump_IsTimerEnabled");
}
#endif