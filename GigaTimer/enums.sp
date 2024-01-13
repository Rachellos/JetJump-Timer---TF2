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

    bool exists;
}

enum struct StageEnterTime
{
    int record_id;
    
    int player_id;

    Class class;

    int stage_id;

    float time;
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
    Class regenAmmo[NUM_RUNS];

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

enum struct Player
{
    int id;
    int soldierRank;
    int demomanRank;

    // player settings (hud, sounds etc)
    int settingsFlags;

    char name[32];
    char steamid[255];
    char ip[32];
    char country[64];

    bool isTimerOn;
    bool isAdmin;

    float overallPoints;
    float soldierPoints;
    float demomanPoints;

    Zone currentZone;

    State state;

    Class currentClass;
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