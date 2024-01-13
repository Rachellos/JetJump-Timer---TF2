#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <SteamWorks>
#include <geoip>
#include <morecolors>
#include <sdktools>
#include <sdkhooks>
#include <clients>

#pragma newdecls required

#pragma dynamic 131072

#define MAX_COMMANDS 1000

#define TIME_SIZE_DEF 15
#define FORMAT_2DECI 0
#define FORMAT_3DECI 1

#define RUNS_LIMIT 100
#define ZONES_LIMIT RUNS_LIMIT * 3

#define NULL_VEC {0.0, 0.0, 0.0}

#define RECORDS_LIMIT 10000

#define BRUSH_MODEL "models/props/cs_office/vending_machine.mdl"

Database g_hDatabase;

ServerInfo g_server;

Commands g_commands[MAX_COMMANDS];

MapInfo g_currentMap;

Zone g_zones[ZONES_LIMIT];

Run g_run[MAXPLAYERS+1];

Records g_records[RECORDS_LIMIT];
StageEnterTime g_stageEnterTimes[RECORDS_LIMIT];

Player g_player[MAXPLAYERS+1];


#include <GigaTimer\enums.sp>
#include <GigaTimer\commands.sp>

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    if ( late )
    {
        ConnectDatabase();

        InitMap();

        for (int i = 0; i <= MaxClients; i++)
        {
            AuthPlayer(i);
        }

        RequestFrame( DrawPlayersHud );
    }
    
    return APLRes_Success;
}

public void OnPluginStart()
{
    ConnectDatabase();

    // call InitMap() in this event  to avoid deleting newly created zone entites
    HookEvent("teamplay_round_start", OnRoundStart, EventHookMode_Post);
    HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Post);

    RegisterAllGigaCommands();

    RequestFrame( DrawPlayersHud );
}

void OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
    InitMap();
}

void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if ( !(1 <= client <= MaxClients) ) return;

    g_player[client].currentClass = GetPlayerClass(client);
    g_player[client].state = STATE_INVALID;

    Zone emptyZone;
    g_player[client].currentZone = emptyZone;
    g_player[client].currentZone.arrayId = -1;

    Run emptyRun;
    g_run[client] = emptyRun;
}

public void OnMapStart()
{
    if (!IsModelPrecached( BRUSH_MODEL ))
        PrecacheModel( BRUSH_MODEL, true );
    
    InitMap();
}

public void OnMapEnd()
{
    return;
}

public void OnClientPostAdminCheck(int client)
{
    if (IsClientSourceTV(client)) return;

    AuthPlayer(client);
}

void InitMap()
{
    GetCurrentMap(g_currentMap.name, sizeof(MapInfo::name));

    char query[256];

    FormatEx(query, sizeof(query), "SELECT id FROM map_list WHERE name = '%s'", g_currentMap.name);
    g_hDatabase.Query(Thread_GetMapId, query);
}

public void Thread_GetMapId(Database db, DBResultSet results, const char[] error, any data)
{
    if ( strlen(error) > 1 ) { LogError(error); return; }

    if ( results.FetchRow() )
    {
        g_currentMap.id = results.FetchInt(0);

        char query[256];
        FormatEx(query, sizeof(query), "UPDATE map_list SET launches = launches + 1", g_currentMap.id );
        g_hDatabase.Query(Thread_Empty, query);

        InitZones();
    }
    else
    {
        char query[256];
        FormatEx(query, sizeof(query), "INSERT INTO map_list (name) VALUES('%s')", g_currentMap.name );
        g_hDatabase.Query(Thread_Empty, query);


        // now we can get map id.
        InitMap();
    }

    return;
}

void InitZones()
{
    char query[1024];

    FormatEx(query, sizeof(query), "SELECT zone_type, zone_index, run_type, run_id, min1, min2, min3, max1, max2, max3, name, \
                                    COALESCE((SELECT soldier_tier FROM map_info WHERE map_id = map_zones.map_id AND run_type = map_zones.run_type AND run_id = map_zones.run_id), -1), \
                                    COALESCE((SELECT demoman_tier FROM map_info WHERE map_id = map_zones.map_id AND run_type = map_zones.run_type AND run_id = map_zones.run_id), -1), \
                                    COALESCE((SELECT soldier_completions FROM map_info WHERE map_id = map_zones.map_id AND run_type = map_zones.run_type AND run_id = map_zones.run_id), 0), \
                                    COALESCE((SELECT demoman_completions FROM map_info WHERE map_id = map_zones.map_id AND run_type = map_zones.run_type AND run_id = map_zones.run_id), 0), \
                                    COALESCE((SELECT regen_ammo FROM map_info WHERE map_id = map_zones.map_id AND run_type = map_zones.run_type AND run_id = map_zones.run_id), -1) \
                                    FROM map_zones WHERE map_id = %i", g_currentMap.id );

    g_hDatabase.Query(Thread_GetMapZones, query);
}

public void Thread_GetMapZones(Database db, DBResultSet results, const char[] error, any data)
{
    if ( strlen(error) > 1 ) { LogError(error); return; }
    
    // cloar our zones firstly
    ClearZonesData();

    int i = 0;

    while ( results.FetchRow() )
    {
        g_zones[i].zoneType = view_as<Zones>(results.FetchInt(0));
        g_zones[i].zoneIndex = results.FetchInt(1);

        g_zones[i].runType = view_as<RunType>(results.FetchInt(2));
        g_zones[i].runInfo.index = results.FetchInt(3);

        g_zones[i].cordMin[0] = results.FetchFloat(4);
        g_zones[i].cordMin[1] = results.FetchFloat(5);
        g_zones[i].cordMin[2] = results.FetchFloat(6);

        g_zones[i].cordMax[0] = results.FetchFloat(7);
        g_zones[i].cordMax[1] = results.FetchFloat(8);
        g_zones[i].cordMax[2] = results.FetchFloat(9);

        g_zones[i].runInfo.tier[CLASS_SOLDIER] = results.FetchInt(11);
        g_zones[i].runInfo.tier[CLASS_DEMOMAN] = results.FetchInt(12);

        g_zones[i].runInfo.completions[CLASS_SOLDIER] = results.FetchInt(13);
        g_zones[i].runInfo.completions[CLASS_DEMOMAN] = results.FetchInt(14);

        g_zones[i].regen_ammo = view_as<Class>(results.FetchInt(15));

        if ( results.IsFieldNull(10) )
        {
            char currentRun[NUM_RUNS][] = {
                "Map",
                "Stage",
                "Bonus"
            };
            
            if ( g_zones[i].runType == RUN_MAP )
                FormatEx(g_zones[i].runInfo.runName, sizeof(RunInfo::runName), "%s", currentRun[g_zones[i].runType]);
            else
                FormatEx(g_zones[i].runInfo.runName, sizeof(RunInfo::runName), "%s %i", currentRun[g_zones[i].runType], g_zones[i].runInfo.index);
        }
        else
        {
            results.FetchString( 10, g_zones[i].runInfo.runName, sizeof(RunInfo::runName) );
        }

        g_zones[i].arrayId = i;

        g_zones[i].exists = true;

        CreateZoneEntity( i );

        i++;
    }

    if ( i > 0 )
    {
        PrintToServer("Loaded %i zones! for %s", i, g_currentMap.name);
        MC_PrintToChatAll("Loaded {gold}%i {white}zones!", i);
    }
    else
    {
        PrintToServer("No Zones for %s", g_currentMap.name);
    }

    if ( results.RowCount )
    {
        SetupZoneSpawns();
        InitRecords();
    }
}


void InitRecords()
{
    char query[512];
    FormatEx(query, sizeof(query), "SELECT record_id, player_id, players.name, class, run_type, run_id, time \
                                    FROM records JOIN players ON records.player_id = players.id \
                                    WHERE map_id = %i", g_currentMap.id );
    
    g_hDatabase.Query(Thread_GetMapRecords, query);
}

void Thread_GetMapRecords(Database db, DBResultSet results, const char[] error, any data)
{
    if ( strlen(error) > 1 ) { LogError(error); return; }

    // clear records if we want to refresh them
    ClearRecordsData();

    int i = 0;

    while ( results.FetchRow() )
    {
        g_records[i].record_id = results.FetchInt(0);
        g_records[i].player_id = results.FetchInt(1);

        results.FetchString(2, g_records[i].player_name, sizeof(Records::player_name));

        g_records[i].class = view_as<Class>(results.FetchInt(3));
        g_records[i].runType = view_as<RunType>(results.FetchInt(4));
        g_records[i].runIndex = results.FetchInt(5);

        g_records[i].time = results.FetchFloat(6);

        i++;
    }

    if ( i > 0 )
    {
        PrintToServer("Loaded %i Records! For %s", i, g_currentMap.name);
        MC_PrintToChatAll("Loaded {gold}%i {white}records!", i);
    }
    else
    {
        PrintToServer("No Records Found For %s", g_currentMap.name);
    }

    if ( results.RowCount )
    {
        char query[512];
        FormatEx(query, sizeof(query), "SELECT record_id, player_id, class, stage_id, time FROM enter_stage_times WHERE map_id = %i", g_currentMap.id );
        g_hDatabase.Query(Thread_GetEnterStageTimes, query);
    }
}

void Thread_GetEnterStageTimes(Database db, DBResultSet results, const char[] error, any data)
{
    if ( strlen(error) > 1 ) { LogError(error); return; }

    int i = 0;

    while ( results.FetchRow() )
    {
        g_stageEnterTimes[i].record_id = results.FetchInt(0);
        g_stageEnterTimes[i].player_id = results.FetchInt(1);

        g_stageEnterTimes[i].class = view_as<Class>(results.FetchInt(2));
        g_stageEnterTimes[i].stage_id = results.FetchInt(3);

        g_stageEnterTimes[i].time = results.FetchFloat(4);

        i++;
    }

    if ( i > 0 )
    {
        PrintToServer("Loaded %i Records! For %s", i, g_currentMap.name);
        MC_PrintToChatAll("Loaded {gold}%i {white}records!", i);
    }
    else
    {
        PrintToServer("No Records Found For %s", g_currentMap.name);
    }

    if ( results.RowCount )
    {
        char query[512];
        FormatEx(query, sizeof(query), "SELECT record_id, player_id, class, stage_id, time FROM enter_stage_times WHERE map_id = %i", g_currentMap.id );
        g_hDatabase.Query(Thread_GetEnterStageTimes, query);
    }
}

stock void CreateZoneEntity( int index )
{
    int ent = CreateTrigger( g_zones[index].cordMin, g_zones[index].cordMax );

    if ( !ent )
    {
        PrintToServer("ERROR | Can not create trigger for %s %s", g_zones[index].runInfo.runName, g_zones[index].runInfo.index);
        return;
    }

    SetTriggerIndex( ent, index );

    SDKHook( ent, SDKHook_TouchPost, Event_Touch_Zone );
    SDKHook( ent, SDKHook_EndTouch, Event_EndTouch_Zone );

    g_zones[index].ent = ent;

    return;
}

int FindZoneArrayId(RunType run, Zones zone_type, int runId = 1)
{
    for ( int i; i < ZONES_LIMIT; i++ )
        if ( g_zones[i].runType == run && g_zones[i].zoneType == zone_type && g_zones[i].runInfo.index == runId && g_zones[i].exists )
            return i;
    
    return -1;
}

public void Event_Touch_Zone( int trigger, int client )
{
    if ( client < 1 || client > MaxClients || !IsClientInGame(client) || !IsClientConnected(client) ) return;

    int id = GetTriggerIndex( trigger );

    if ( g_player[client].currentZone.arrayId == g_zones[id].arrayId ) return;
    
    if ( g_zones[id].zoneType == ZONE_START )
    {
        if ( g_zones[id].runType == RUN_MAP
        || g_zones[id].runType == RUN_BONUS
        || (g_zones[id].runType == RUN_STAGE && g_zones[id].runInfo.index == 1) )
        {
            Run emptyRun;
            g_run[client] = emptyRun;

            g_run[client].linearMode = true;
        }
        else if (g_zones[id].runType == RUN_STAGE)
        {
            if ( g_zones[id].runInfo.index == g_run[client].info.index + 1 && g_player[client].state == STATE_END && g_run[client].linearMode )
            {
                float currentTime = GetEngineTime() - g_run[client].startTime;
                char currentTimeText[TIME_SIZE_DEF];

                char comparisonText[64];
                
                FormatSeconds( GetEngineTime() - g_run[client].startTime, currentTimeText, FORMAT_2DECI );
                
                //int stageEnterPrIndex = GetStageEnterPersonalRecordIndex(client, g_player[client].currentClass, g_zones[id].runInfo.index);
                int stageEnterWrIndex = GetStageEnterWorldRecordIndex(g_player[client].currentClass, g_zones[id].runInfo.index);

                StageEnterTime emptyStageEnter;
                g_run[client].stageEnterWorldRecord = stageEnterWrIndex != -1 ? g_stageEnterTimes[stageEnterWrIndex] : emptyStageEnter;

                if ( stageEnterWrIndex != -1 )
                {
                    char comparisonTimeText[TIME_SIZE_DEF];
                    float bestTime = g_stageEnterTimes[stageEnterWrIndex].time;
                    int prefix = currentTime > bestTime ? '+' : '-';
                    
                    FormatSeconds(currentTime > bestTime ? currentTime - bestTime : bestTime - currentTime, comparisonTimeText);
                    FormatEx(comparisonText, sizeof(comparisonText), "{white}({lightskyblue}WR %c%s{white})", prefix, comparisonTimeText);
                }
                MC_PrintToChat(client, "Entered {blue}%s {white}with time: {green}%s %s", g_zones[id].runInfo.runName, currentTimeText, comparisonText);

                g_run[client].stageEnterTime[g_zones[id].runInfo.index] = currentTime;
                g_run[client].linearMode = true;
            }
            // player try to cheat stages run, stop him.
            else if ( ( (g_zones[id].runInfo.index - g_run[client].info.index) > 1
                    || ( g_run[client].info.index == g_zones[id].runInfo.index - 1 && g_player[client].state != STATE_END) )
                    && g_run[client].linearMode )
            {
                MC_PrintToChat(client, "{red}ERROR {white}| Your run was {red}closed{white}, becouse you not finished:")
                
                int lastUnfinishedRun = ( g_player[client].state == STATE_RUNNING ) ? g_run[client].info.index : g_run[client].info.index + 1;

                for (int i = g_zones[id].runInfo.index - 1; i >= lastUnfinishedRun; i--)
                {
                    MC_PrintToChat(client, "{gold}Stage{white} %i", i);
                }

                g_run[client].linearMode = false;
            }
            else if( g_run[client].linearMode && g_run[client].type == RUN_STAGE && g_run[client].info.index > g_zones[id].runInfo.index)
            {
                // dont do nothing....
            }
            else if ( g_zones[id].runInfo.index != g_run[client].info.index
                    || g_zones[id].runType != g_run[client].type
                    || ( g_player[client].state == STATE_END && g_zones[id].runType != g_run[client].type ) )
            {
                g_run[client].linearMode = false;
            }
        }

        int prIndex = GetPersonalRecordRunIndex(client, g_player[client].currentClass, g_zones[id].runType, g_zones[id].runInfo.index);
        int wrIndex = GetWorldRecordRunIndex(g_player[client].currentClass, g_zones[id].runType, g_zones[id].runInfo.index); 

        Records emptyRecord;
        g_run[client].personalRecord = ( prIndex != -1 ) ? g_records[prIndex] : emptyRecord;
        g_run[client].worldRecord = ( wrIndex != -1 ) ? g_records[wrIndex] : emptyRecord;

        g_run[client].type = g_zones[id].runType;
        g_run[client].info = g_zones[id].runInfo;

        g_player[client].currentZone = g_zones[id];
        g_player[client].state = STATE_START;
        
    }
    else if ( g_zones[id].zoneType == ZONE_END && g_player[client].state == STATE_RUNNING)
    {
        if ( g_zones[id].runType != g_run[client].type || g_zones[id].runInfo.index != g_run[client].info.index ) return;

        if ( !g_player[client].isTimerOn ) return;

        g_player[client].currentZone = g_zones[id];

        g_player[client].state = STATE_END;

        NotifyRecordInChat(client, g_run[client]);
    }
    else if ( g_zones[id].zoneType == ZONE_CHECKPOINT )
    {
        if ( g_zones[id].runType != g_run[client].type || g_zones[id].runInfo.index != g_run[client].info.index ) return;

        if ( !g_player[client].isTimerOn ) return;
    }
}

public void Event_EndTouch_Zone( int trigger, int client )
{
    if ( client < 1 || client > MaxClients || !IsClientInGame(client) || !IsClientConnected(client) ) return;

    int id = GetTriggerIndex( trigger );

    if ( g_zones[id].zoneType == ZONE_CHECKPOINT || g_zones[id].zoneType == ZONE_END ) return;

    Zone emptyZone;
    emptyZone.zoneType = ZONE_INVALID;

    g_player[client].currentZone = emptyZone;

    if ( g_zones[id].runType == RUN_STAGE )
    {
        if ( g_zones[id].runInfo.index == 1 )
            g_run[client].startTime = GetEngineTime();
        
        g_run[client].stageStartTime = GetEngineTime();
    }
    else
    {
        g_run[client].startTime = GetEngineTime();
    }

    g_player[client].state = STATE_RUNNING;
    
    return;
}

void NotifyRecordInChat(int client, Run run)
{
    char time[TIME_SIZE_DEF];
    
    if ( run.type == RUN_MAP || run.type == RUN_BONUS )
    {
        run.finishTime = GetEngineTime() - run.startTime;

        FormatSeconds(run.finishTime, time);
        MC_PrintToChatAll( "{yellow}%N {white}finished the {haunted}%s{white}: ({hotpink}%s{white})", client, run.info.runName, time );

        SaveRecord(g_player[client], run);
    }
    else if ( run.type == RUN_STAGE )
    {
        run.stageFinishTime = GetEngineTime() - run.stageStartTime;
        
        FormatSeconds(run.stageFinishTime, time);
        MC_PrintToChatAll( "{gold}%N {white}finished the {haunted}%s{white}: ({hotpink}%s{white})", client, run.info.runName, time );

        SaveRecord(g_player[client], run);

        if ( !IsZoneExists(ZONE_START, RUN_STAGE, g_player[client].currentZone.runInfo.index + 1 ) && run.linearMode)
        {
            run.type = RUN_MAP;

            NotifyRecordInChat(client, run);
        }
    }
}

void SaveRecord(Player player, Run run)
{
    char query[2048];

    Transaction transaction = new Transaction();

    // Add/Update record to the database here
    FormatEx(query, sizeof(query), "INSERT INTO records (map_id, player_id, class, run_type, run_id, time, server_id) VALUES(%i, %i, %i, %i, %i, %f, %i) \
                                    ON DUPLICATE KEY UPDATE time = %f, server_id = %i",
            g_currentMap.id, player.id, player.currentClass, run.type, run.type != RUN_MAP ? run.info.index : 1, run.type == RUN_STAGE ? run.stageFinishTime : run.finishTime, g_server.id,
            run.type == RUN_STAGE ? run.stageFinishTime : run.finishTime, g_server.id);

    transaction.AddQuery(query);

    FormatEx(query, sizeof(query), "UPDATE map_info SET %s = (SELECT COUNT(*) FROM records \
                                    WHERE records.map_id = map_info.map_id AND run_type = %i AND run_id = %i AND class = %i) \
                                    WHERE map_id = %i AND run_type = %i AND run_id = %i",
                                    player.currentClass == CLASS_SOLDIER ? "soldier_completions" : "demoman_completions",
                                    run.type, run.type != RUN_MAP ? run.info.index : 1, player.currentClass,
                                    g_currentMap.id, run.type, run.info.index);

    transaction.AddQuery(query);

    // that means player just finish stages map correctly
    if ( run.type == RUN_MAP && run.info.index > 1 && run.linearMode )
    {
        for (int stage_id = 1; stage_id <= run.info.index; stage_id++)
        {
            FormatEx(query, sizeof(query), "INSERT INTO enter_stage_times (record_id, map_id, player_id, class, stage_id, time) \
                                            VALUES \
                                            ( \
                                                (SELECT record_id FROM records WHERE map_id = %i AND player_id = %i AND class = %i AND run_type = %i), \
                                                %i, %i, %i, %i, %f \
                                            ) \
                                            ON DUPLICATE KEY UPDATE time = %f",
            g_currentMap.id, player.id, player.currentClass, RUN_MAP,
            g_currentMap.id, player.id, player.currentClass, stage_id, run.stageEnterTime[stage_id],
            run.stageEnterTime[stage_id]);
            
            transaction.AddQuery(query);
        }
    }

    if ( run.info.tier[player.currentClass] != -1 )
    {
        g_hDatabase.Execute(transaction, _, Thread_Empty_TransactionFail);
        RecalculatePoints(run.type, run.info.index, player.currentClass);
    }
    else
    {
        for(int i = 0; i <= MaxClients; i++)
        {
            if (g_player[i].id == player.id)
            {
                MC_PrintToChat(i, "Your run dont {red}saved{white}! No tiers to calculate points.");
                return;
            }
        }
    }

    
}

void DrawPlayersHud()
{
    int player;

    State state;
    Run run;

    float currentTime;
    char currentTimeText[TIME_SIZE_DEF];

    char type[32];
    char hud[256];

    float engineTime = GetEngineTime();

    static float whenDrawHud[MAXPLAYERS+1];
    static bool shouldDrawHud[MAXPLAYERS+1];

    for ( int client = 1; client <= MaxClients; client++)
    {
        if ( !IsClientInGame(client) || !IsClientConnected(client) || IsClientSourceTV(client) ) continue;

        player = client;

        // If client is observer, then draw target hud.
        if ( IsClientObserver(client) )
        {
            player = GetCurrentSpectatingClient(client);
            
            // oh no, you dont spectate at any players
            if ( player == -1 ) continue;
        }

        run = g_run[player];
        state = g_player[player].state;

        switch (run.type)
        {
            case RUN_MAP:
                FormatEx(type, sizeof(type), "Linear Run");
            case RUN_BONUS:
                FormatEx(type, sizeof(type), "Bonus Run");
            case RUN_STAGE:
            {
                if ( run.linearMode )
                    FormatEx(type, sizeof(type), "Linear Run");
                else
                    FormatEx(type, sizeof(type), "Stage Run");
            }
            default:
                FormatEx(type, sizeof(type), "-------");
        }

        if ( state == STATE_START || state == STATE_END )
        {
            FormatSeconds(run.linearMode ? run.finishTime : run.stageFinishTime, currentTimeText, FORMAT_2DECI);

            FormatEx(hud, sizeof(hud), "%s\n \n(%s %s)\n \n%s",
            state == STATE_START ? g_currentMap.name : currentTimeText,
            run.info.runName,
            state == STATE_START ? "Start" : "Finish",
            type);

            if (whenDrawHud[client] < engineTime)
            {
                shouldDrawHud[client] = true;
                whenDrawHud[client] = engineTime + 0.5;
            }
            else
            {
                shouldDrawHud[client] = false;
            }

            if ( run.type == RUN_STAGE )
            {
                if ( run.linearMode &&
                ( run.info.index > 1
                || ( state == STATE_END
                && IsZoneExists( ZONE_START, RUN_STAGE, run.info.index + 1 ) ) ) )
                {
                    currentTime = engineTime - run.startTime;
                    FormatSeconds(currentTime, currentTimeText, FORMAT_2DECI);

                    FormatEx(hud, sizeof(hud), "%s\n \n(%s %s)\n \n%s",
                    currentTimeText,
                    run.info.runName,
                    state == STATE_START ? "Start" : "Finish",
                    type);

                    shouldDrawHud[client] = true;
                }
            }
        }
        else if ( state == STATE_RUNNING )
        {
            if ( g_run[player].linearMode )
                currentTime = engineTime - run.startTime;
            else
                currentTime = engineTime - run.stageStartTime;
            
            FormatSeconds(currentTime, currentTimeText, FORMAT_2DECI);

            FormatEx(hud, sizeof(hud), "%s\n \n(%s)\n \n%s (tier %i)", currentTimeText, run.info.runName, type, run.info.tier[g_player[player].currentClass]);

            shouldDrawHud[client] = true;
        }


        if (shouldDrawHud[client])
        {
            PrintHintText( client, hud);
            shouldDrawHud[client] = false;
        }
    }

    // fuck yea
    RequestFrame( DrawPlayersHud );
}

stock int GetCurrentSpectatingClient(int client)
{
    int target;
    // 4 is IN EYE >:), 5 is follow a player in third person view
    if ( GetEntProp(client, Prop_Send, "m_iObserverMode") == 4
        || GetEntProp(client, Prop_Send, "m_iObserverMode") == 5 )
    {
        target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget")

        if ( 1 <= target <= MaxClients && IsClientInGame(target) && IsClientConnected(target) && !IsClientSourceTV(target) )
            return target;
    }
    // Not found :(.
    return -1;
}

// Format seconds and make them look nice.
stock void FormatSeconds( float flSeconds, char szTarget[TIME_SIZE_DEF], int fFlags = 0 )
{
    int iMins;
    int iHours;
    int iDay;

    char szSec[7];

    while ( flSeconds >= 60.0 )
	{
		iMins++;
		flSeconds -= 60.0;
	}
	
    while ( iMins >= 60 )
	{
		iHours++;
		iMins -= 60;
	}
	
    while ( iHours >= 24 )
	{
		iDay++;
		iHours -= 24;
	}
	
    switch ( fFlags )
    {
        case FORMAT_3DECI :
        {
			FormatEx( szSec, sizeof( szSec ), "%06.3f", flSeconds );
		}
		case FORMAT_2DECI :
		{
			FormatEx( szSec, sizeof( szSec ), "%05.2f", flSeconds );
		}
		default :
		{
			FormatEx( szSec, sizeof( szSec ), "%05.2f", flSeconds );
		}
	}
	
	// "XX:XX:XX" to "XX:XX.XX"
    szSec[sizeof( szSec ) - 5] = '.';
	
    if ( iHours != 0 )
	{
	    FormatEx( szTarget, TIME_SIZE_DEF, "%i:%02i:%s", iHours, iMins, szSec );
    }
    else
	{
	    FormatEx( szTarget, TIME_SIZE_DEF, "%02i:%s", iMins, szSec );
	}

    if ( iDay != 0 )
	{
	    FormatEx( szTarget, TIME_SIZE_DEF, "%id:%i:%02i:%s", iDay, iHours, iMins, szSec );
    }

    return;
}

void ClearPlayerData(int client)
{
    if ( !(1 <= client <= MaxClients) ) return

    Player emptyPlayer

    g_player[client] = emptyPlayer
}

void ClearZonesData()
{
    Zone emptyZone

    for ( int i; i < ZONES_LIMIT; i++ )
    {
        SDKUnhook(g_zones[i].ent, SDKHook_Touch, Event_Touch_Zone);
        SDKUnhook(g_zones[i].ent, SDKHook_EndTouch, Event_Touch_Zone);
        g_zones[i] = emptyZone;
    }
}

void ClearRecordsData()
{
    Records emptyRecord;

    for ( int i; i < RECORDS_LIMIT; i++ )
        g_records[i] = emptyRecord;
}

stock bool IsZoneExists(Zones zone, RunType runtype, int num)
{
    for (int i; i < ZONES_LIMIT; i++)
    {
        if (g_zones[i].zoneType == zone && g_zones[i].runType == runtype && g_zones[i].runInfo.index == num && g_zones[i].exists)
            return true;
    }

    return false;
}

stock int GetPersonalRecordRunIndex(int client, Class class, RunType runType, int run_id)
{
    for (int i = 0; i < RECORDS_LIMIT; i++)
    {
        if ( g_records[i].player_id == g_player[client].id && g_records[i].class == class && g_records[i].runType == runType && g_records[i].runIndex == run_id )
            return i;
    }

    return -1;
}

stock int GetWorldRecordRunIndex(Class class, RunType runType, int run_id)
{
    int index = -1;
    float bestTime = -1.0;

    for (int i = 0; i < RECORDS_LIMIT; i++)
    {
        if ( g_records[i].class == class && g_records[i].runType == runType && g_records[i].runIndex == run_id )
        {
            if ( bestTime == -1.0 )
            {
                index = i;
                bestTime = g_records[i].time;
            }
            else if (bestTime > g_records[i].time)
            {
                index = i;
                bestTime = g_records[i].time;
            }
        }
    }

    return index;
}

stock int GetStageEnterWorldRecordIndex(Class class, int stage_id)
{
    int wrIndex = GetWorldRecordRunIndex(class, RUN_STAGE, stage_id);

    if ( wrIndex == -1 )
        return -1;

    for (int i = 0; i < RECORDS_LIMIT; i++)
        if ( g_stageEnterTimes[i].record_id == g_records[wrIndex].record_id )
            return i;

    return -1;
}

stock int GetStageEnterPersonalRecordIndex(int client, Class class, int stage_id)
{
    int prIndex = GetPersonalRecordRunIndex(client, class, RUN_STAGE, stage_id);

    if ( prIndex == -1 )
        return -1;

    for (int i = 0; i < RECORDS_LIMIT; i++)
        if ( g_stageEnterTimes[i].record_id == g_records[prIndex].record_id )
            return i;

    return -1;
}

stock int GetTriggerIndex( int ent )
{
	return GetEntProp( ent, Prop_Data, "m_iHealth" );
}

stock void SetTriggerIndex( int ent, int index )
{
    SetEntProp( ent, Prop_Data, "m_iHealth", index );
    return;
}

public Class GetPlayerClass(int client)
{
	Class class;
	if (IsClientInGame(client) && IsPlayerAlive(client))
	{

		TFClassType playerClass = TF2_GetPlayerClass(client);

		switch(playerClass)
		{
			case TFClass_Soldier  : return CLASS_SOLDIER;
			case TFClass_DemoMan  : return CLASS_DEMOMAN;
			default: return CLASS_INVALID;
		}
	}
	return class;
}

stock int CreateTrigger( float vecMins[3], float vecMaxs[3] )
{
    int ent = CreateEntityByName( "trigger_multiple" );

    if ( ent < 1 )
    {
    	LogError( "Couldn't create block entity!" );
    	return 0;
    }

    DispatchKeyValue( ent, "wait", "0" );
    DispatchKeyValue( ent, "StartDisabled", "0" );
    DispatchKeyValue( ent, "spawnflags", "1");
	
    if ( !DispatchSpawn( ent ) )
    {
        LogError("Couldn't spawn block entity!" );
        return 0;
	}
	
    ActivateEntity( ent );
	
    SetEntityModel( ent, BRUSH_MODEL );
	
    SetEntProp( ent, Prop_Send, "m_fEffects", 32 ); // NODRAW
	
    float vecPos[3];
    float vecNewMaxs[3];

	// Determine the entity's origin.
	// This means the bounds will be just opposite numbers of each other.
    vecNewMaxs[0] = ( vecMaxs[0] - vecMins[0] ) / 2;
    vecPos[0] = vecMins[0] + vecNewMaxs[0];

    vecNewMaxs[1] = ( vecMaxs[1] - vecMins[1] ) / 2;
    vecPos[1] = vecMins[1] + vecNewMaxs[1];

    vecNewMaxs[2] = ( vecMaxs[2] - vecMins[2] ) / 2;
    vecPos[2] = vecMins[2] + vecNewMaxs[2];
	
    TeleportEntity( ent, vecPos, NULL_VECTOR, NULL_VECTOR );
	
	// We then set the mins and maxs of the zone according to the center.
    float vecNewMins[3];
	
    vecNewMins[0] = -1 * vecNewMaxs[0];
    vecNewMins[1] = -1 * vecNewMaxs[1];
    vecNewMins[2] = -1 * vecNewMaxs[2];
	
    SetEntPropVector( ent, Prop_Send, "m_vecMins", vecNewMins );
    SetEntPropVector( ent, Prop_Send, "m_vecMaxs", vecNewMaxs );
    SetEntProp( ent, Prop_Send, "m_nSolidType", 2 ); // Essential! Use bounding box instead of model's bsp(?) for input.
	
    return ent;
}

// Find an angle for the starting zones.
stock void SetupZoneSpawns()
{
	// Give each starting zone a spawn position.
    for (int i = 0; i < ZONES_LIMIT; i++ )
    {
        if ( g_zones[i].exists && g_zones[i].zoneType == ZONE_START )
        {
            g_zones[i].spawnPos[0] = g_zones[i].cordMin[0] + ( g_zones[i].cordMax[0] - g_zones[i].cordMin[0] ) / 2;
            g_zones[i].spawnPos[1] = g_zones[i].cordMin[1] + ( g_zones[i].cordMax[1] - g_zones[i].cordMin[1] ) / 2;
            g_zones[i].spawnPos[2] = g_zones[i].cordMin[2] + 16.0;
        }
    }

    // so if is there start position by map creator, then lets use it
    int ent = -1;
    while ( (ent = FindEntityByClassname( ent, "info_teleport_destination" )) != -1 )
    {
		for (int i = 0; i < ZONES_LIMIT; i++ )
		{
			if ( g_zones[i].exists && g_zones[i].zoneType == ZONE_START && IsInsideBounds( ent, g_zones[i].cordMin, g_zones[i].cordMax ) )
			{
                GetEntPropVector( ent, Prop_Data, "m_vecOrigin", g_zones[i].spawnPos );
                GetEntPropVector( ent, Prop_Data, "m_angRotation", g_zones[i].spawnAng );
			}
		}
	}
    return;
}

stock void ArrayCopy( const any[] oldArray, any[] newArray, int size = 1 )
{
	for ( int i = 0; i < size; i++ ) newArray[i] = oldArray[i];
}

// uses only for entites 
stock bool IsInsideBounds( int ent, float vecMins[3], float vecMaxs[3] )
{
	static float vecPos[3];
	GetEntPropVector( ent, Prop_Send, "m_vecOrigin", vecPos );
	
	if ( (vecMins[0] <= vecPos[0] <= vecMaxs[0] ) && ( vecMins[1] <= vecPos[1] <= vecMaxs[1] ) && ( vecMins[2] <= vecPos[2] <= vecMaxs[2] ) )
		return true;
	else
		return false;
}

void RecalculatePoints(RunType runtype, int run_id, Class class)
{
    Transaction transaction = new Transaction();
    char query[256];
    
    FormatEx(query, sizeof(query), "CALL UpdateMapPoints(%i, %i, %i, %i);", g_currentMap.id, runtype, run_id, class);

    transaction.AddQuery(query);

    g_hDatabase.Execute(transaction, _, Thread_Empty_TransactionFail);
}

ServerInfo AuthServer()
{
    ServerInfo srv;
    int iPublicIP[4];

    // if we cant get public ip --> stop plugin
    if (SteamWorks_GetPublicIP(iPublicIP) == false)
        SetFailState("Appears like we had an error on getting the Public Server IP address.");

    Format(srv.ip, sizeof(ServerInfo::ip), "%d.%d.%d.%d", iPublicIP[0], iPublicIP[1], iPublicIP[2], iPublicIP[3]);
    srv.port = GetConVarInt(FindConVar("hostport"));
    srv.maxPlayers = 10;
    GetConVarString(FindConVar("hostname"), srv.name, sizeof(ServerInfo::name));
    srv.isOnline = true;

    char query[256];
    FormatEx(query, sizeof(query), "INSERT INTO servers (name, ip, max_players, isOnline) VALUES('%s', '%s:%i', %i, 1) \
                                    ON DUPLICATE KEY UPDATE name = '%s', max_players = %i, isOnline = 1",
                                    srv.name,
                                    srv.ip, srv.port,
                                    srv.maxPlayers,
                                    srv.name,
                                    srv.maxPlayers);

    g_hDatabase.Query(Thread_Empty, query);

    FormatEx(query, sizeof(query), "SELECT id FROM servers WHERE ip = '%s:%i'", srv.ip, srv.port);

    g_hDatabase.Query(Thread_GetServerId, query);

    return srv;
}

public void Thread_GetServerId(Database db, DBResultSet results, const char[] error, any data)
{
    if ( strlen(error) > 1 ) { LogError(error); return; }

    if ( results.FetchRow() )
    {
        g_server.id = results.FetchInt(0);
    }
    else
    {
        SetFailState("Can not get server id! Plugin disabled.");
    }

    return;
}

void AuthPlayer(int client)
{
    if ( !(1 <= client <= MaxClients) ) return;
    if ( !IsClientInGame(client) && IsClientSourceTV(client) ) return;

    ClearPlayerData(client);

    char query[256];

    GetClientAuthId(client, AuthId_SteamID64, g_player[client].steamid, Player::steamid);

    g_player[client].state = STATE_INVALID;
    g_player[client].isTimerOn = true;
    g_player[client].currentZone.arrayId = -1;

    FormatEx( query, sizeof(query), "SELECT id, settingsFlag, soldier_points, demoman_points, soldier_rank, demoman_rank, isAdmin FROM players WHERE steamid = '%s'", g_player[client].steamid );
    g_hDatabase.Query(Thread_GetPlayerInfo, query, client);

    return;
}

void JoinRankNotify(int client)
{
    char info[64];

    int srank = g_player[client].soldierRank;
    int drank = g_player[client].demomanRank;

    if ( srank != -1 || drank != -1 )
    {
        if ( srank == -1 )
            FormatEx(info, sizeof(info), "Demoman %i Rank", drank);
        else if(drank == -1)
            FormatEx(info, sizeof(info), "Soldier %i Rank", srank);
        else if ( srank <= drank )
            FormatEx(info, sizeof(info), "Soldier %i Rank", srank);
        else if ( drank < srank )
            FormatEx(info, sizeof(info), "Demoman %i Rank", drank);
    }
    else
    {
        FormatEx(info, sizeof(info), "Unranked");
    }

    MC_PrintToChatAll("{orange}%s {blue}(%s) {white}connected from {green}%s", g_player[client].name, info, g_player[client].country);
}

public void Thread_GetPlayerInfo(Database db, DBResultSet results, const char[] error, any client)
{
    if ( !client ) return;

    if ( strlen(error) > 1 )
    {
        LogError(error);
        return;
    }

    if ( !GetClientName(client, g_player[client].name, sizeof(Player::name)) )
        FormatEx(g_player[client].name, sizeof(Player::name), "None");

    //Escape player name to kill SQL injections
    g_hDatabase.Escape(g_player[client].name, g_player[client].name, 2*strlen(g_player[client].name)+1);

    GetClientIP(client, g_player[client].ip, sizeof(Player::ip));

    if ( !GeoipCountry(g_player[client].ip, g_player[client].country, Player::country) )
        FormatEx(g_player[client].country, sizeof(Player::country), "None");
    
    if ( results.FetchRow() )
    {
        g_player[client].id = results.FetchInt(0);
        g_player[client].settingsFlags = results.FetchInt(1);

        g_player[client].soldierPoints = results.FetchFloat(2);
        g_player[client].demomanPoints = results.FetchFloat(3);

        g_player[client].soldierRank = results.FetchInt(4);
        g_player[client].demomanRank = results.FetchInt(5);

        g_player[client].isAdmin = view_as<bool>(results.FetchInt(6));

        Transaction transaction = new Transaction();

        char query[128];
        FormatEx(query, sizeof(query), "UPDATE players SET online_on_server_id = %i, last_connection = NOW() WHERE id = %i", g_server.id, g_player[client].id);
        transaction.AddQuery(query);

        FormatEx(query, sizeof(query), "UPDATE servers SET players = %i, total_joins = total_joins + 1 WHERE id = %i", GetClientCount(), g_server.id);
        transaction.AddQuery(query);

        g_hDatabase.Execute(transaction, _, Thread_Empty_TransactionFail);

        JoinRankNotify(client);
    }
    else
    {
        // so if player connected first time, lets insert data about him and draw welcome menu.
        char query[256];
        FormatEx(query, sizeof(query), "INSERT INTO players (name, steamid, ip, first_connection) VALUES('%s', '%s', '%s', NOW())", 
                                        g_player[client].name,
                                        g_player[client].steamid,
                                        g_player[client].ip );

        g_hDatabase.Query(Thread_Empty, query);

        // Auth this player again to get default data
        AuthPlayer(client);
    }

    return;
}

// empty thread callback for non-select queries.
public void Thread_Empty(Database db, DBResultSet results, const char[] error, any data)
{
    if ( error[0] != '\0' )
	{
        PrintToServer("ERROR | %s", error);
        LogError( error );
	}
    delete db;

    return;
}

// empty thread transaction callback for non-select queries (ON FAIL).
public void Thread_Empty_TransactionFail(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    PrintToServer("ERROR | %s", error);
    LogError( error );
}

void ConnectDatabase()
{
    char error[256];

    g_hDatabase = SQL_Connect("GigaTimer", true, error, sizeof(error));

    if ( g_hDatabase == INVALID_HANDLE )
        SetFailState("ERROR | GigaTimer can't connect to database; Check databases.cfg settings;")
    
    g_hDatabase.SetCharset("utf8");

    PrintToServer("SUCEFULL | GigaTimer Database Connected!");

    BuildDatabaseTables();

    return;
}

void BuildDatabaseTables()
{
    Transaction t = new Transaction();

    t.AddQuery( "CREATE TABLE IF NOT EXISTS servers \
                (\
                    id INT NOT NULL PRIMARY KEY AUTO_INCREMENT, \
                    ip VARCHAR(128) NOT NULL UNIQUE, \
                    name VARCHAR(128) NOT NULL DEFAULT 'None', \
                    players INT NOT NULL DEFAULT 0, \
                    max_players INT NOT NULL DEFAULT 0, \
                    isOnline INT NOT NULL DEFAULT 0, \
                    total_joins INT NOT NULL DEFAULT 0, \
                    added_date DATETIME NOT NULL DEFAULT NOW() \
                );");

    t.AddQuery( "CREATE TABLE IF NOT EXISTS map_list \
                (\
                    id INT NOT NULL PRIMARY KEY AUTO_INCREMENT, \
                    name VARCHAR(128) NOT NULL DEFAULT 'None', \
                    enabled INT NOT NULL DEFAULT 0, \
                    launches INT NOT NULL DEFAULT 0, \
                    added_date DATETIME NOT NULL DEFAULT NOW(), \
                    UNIQUE KEY map_list_index (name) \
                );");

    t.AddQuery( "CREATE TABLE IF NOT EXISTS players \
                (\
                    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, \
                    name VARCHAR(64) NOT NULL DEFAULT 'SEX MACHINE', \
                    steamid VARCHAR(128), \
                    settingsFlag BIGINT NOT NULL DEFAULT 0, \
                    soldier_points DOUBLE NOT NULL DEFAULT 0.0, \
                    demoman_points DOUBLE NOT NULL DEFAULT 0.0, \
                    soldier_rank INT NOT NULL DEFAULT -1, \
                    demoman_rank INT NOT NULL DEFAULT -1, \
                    online_on_server_id INT, \
                    isAdmin INT NOT NULL DEFAULT 0, \
                    ip VARCHAR(32) NOT NULL DEFAULT 'None', \
                    first_connection DATETIME NOT NULL DEFAULT NOW(), \
                    last_connection DATETIME NOT NULL DEFAULT NOW(), \
                    FOREIGN KEY (online_on_server_id) REFERENCES servers (id) \
                    ON DELETE SET DEFAULT \
                );");

    t.AddQuery( "CREATE TABLE IF NOT EXISTS map_info \
                (\
                    map_id INT NOT NULL REFERENCES map_list (id) ON DELETE CASCADE, \
                    run_type INT NOT NULL, \
                    run_id INT NOT NULL, \
                    \
                    soldier_tier INT NOT NULL DEFAULT -1, \
                    demoman_tier INT NOT NULL DEFAULT -1, \
                    soldier_completions INT NOT NULL DEFAULT 0, \
                    demoman_completions INT NOT NULL DEFAULT 0, \
                    regen_ammo INT NOT NULL DEFAULT -1, \
                    \
                    UNIQUE KEY map_info_index (map_id, run_type, run_id) \
                );");

    t.AddQuery( "CREATE TABLE IF NOT EXISTS map_zones \
                (\
                    map_id INT NOT NULL, \
                    zone_type INT NOT NULL, \
                    zone_index INT NOT NULL, \
                    run_type INT NOT NULL, \
                    run_id INT NOT NULL, \
                    \
                    min1 DOUBLE NOT NULL DEFAULT 0.0, \
                    min2 DOUBLE NOT NULL DEFAULT 0.0, \
                    min3 DOUBLE NOT NULL DEFAULT 0.0, \
                    max1 DOUBLE NOT NULL DEFAULT 0.0, \
                    max2 DOUBLE NOT NULL DEFAULT 0.0, \
                    max3 DOUBLE NOT NULL DEFAULT 0.0, \
                    \
                    name VARCHAR(64), \
                    UNIQUE KEY map_zones_index (map_id, zone_type, zone_index, run_type, run_id), \
                    FOREIGN KEY (map_id) REFERENCES map_list (id) \
                );");
    
    t.AddQuery( "CREATE TABLE IF NOT EXISTS records \
                ( \
                    record_id INT NOT NULL PRIMARY KEY AUTO_INCREMENT, \
                    map_id INT NOT NULL REFERENCES map_list (id) ON DELETE CASCADE, \
                    player_id INT NOT NULL REFERENCES players (id) ON DELETE CASCADE, \
                    class INT NOT NULL, \
                    run_type INT NOT NULL, \
                    run_id INT NOT NULL, \
                    time DOUBLE NOT NULL, \
                    `rank` INT DEFAULT NULL, \
                    points DOUBLE DEFAULT NULL, \
                    server_id INT NOT NULL REFERENCES servers (id), \
                    date DATETIME NOT NULL DEFAULT NOW(), \
                    UNIQUE KEY records_indexes (map_id, player_id, class, run_type, run_id) \
                );");

    t.AddQuery( "CREATE TABLE IF NOT EXISTS enter_stage_times \
                ( \
                    record_id INT NOT NULL PRIMARY KEY REFERENCES records (record_id) ON DELETE CASCADE, \
                    map_id INT NOT NULL REFERENCES map_list (id) ON DELETE CASCADE, \
                    player_id INT NOT NULL REFERENCES players (id) ON DELETE CASCADE, \
                    class INT NOT NULL, \
                    stage_id INT NOT NULL, \
                    time DOUBLE NOT NULL, \
                    UNIQUE KEY stages_enter_index (map_id, player_id, class, stage_id) \
                );");

    t.AddQuery( "CREATE TABLE IF NOT EXISTS points \
                ( \
                    tier INT NOT NULL PRIMARY KEY, \
                    pts DOUBLE NOT NULL \
                );");

    t.AddQuery( "REPLACE INTO points VALUES \
                (1, 10.0), \
                (2, 20.0), \
                (3, 40.0), \
                (4, 100.0), \
                (5, 200.0), \
                (6, 530.0), \
                (7, 530.0), \
                (8, 740.0), \
                (9, 940.0), \
                (10, 1200.0);");

    g_hDatabase.Execute(t, _, Thread_Empty_TransactionFail);


    Transaction t2 = new Transaction();

    t2.AddQuery("CREATE PROCEDURE IF NOT EXISTS `UpdateMapPoints`(IN `in_map_id` INT, IN `in_run_type` INT, IN `in_run_id` INT, IN `in_class` INT) NOT DETERMINISTIC CONTAINS SQL SQL SECURITY INVOKER BEGIN");
    t2.AddQuery("DECLARE v_rec_id, v_player_id, completions, v_tier INT;");
    t2.AddQuery("DECLARE v_rank INT DEFAULT 0;");
    t2.AddQuery("DECLARE calculated_points, default_points, wr, pr DOUBLE;");
    t2.AddQuery("DECLARE done INT DEFAULT FALSE;");
    t2.AddQuery("DECLARE cur CURSOR FOR SELECT record_id, player_id, time FROM records WHERE map_id = in_map_id AND run_type = in_run_type AND run_id = in_run_id AND class = in_class ORDER BY time ASC;");
    t2.AddQuery("DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;");
    t2.AddQuery("OPEN cur;");
    t2.AddQuery("SELECT COUNT(*) INTO completions FROM records WHERE map_id = in_map_id AND run_type = in_run_type AND run_id = in_run_id AND class = in_class;");
    t2.AddQuery("IF in_class = 0");
    t2.AddQuery("THEN");
    t2.AddQuery("SELECT soldier_tier INTO v_tier FROM map_info WHERE map_id = in_map_id AND run_type = in_run_type AND run_id = in_run_id;");
    t2.AddQuery("ELSEIF in_class = 1");
    t2.AddQuery("THEN");
    t2.AddQuery("SELECT demoman_tier INTO v_tier FROM map_info WHERE map_id = in_map_id AND run_type = in_run_type AND run_id = in_run_id;");
    t2.AddQuery("END IF;");
    t2.AddQuery("SELECT pts INTO default_points FROM points WHERE tier = v_tier;");
    t2.AddQuery("loop_through_rows:LOOP");
    t2.AddQuery("FETCH cur INTO v_rec_id, v_player_id, pr;");
    t2.AddQuery("IF done THEN");
    t2.AddQuery("LEAVE loop_through_rows;");
    t2.AddQuery("END IF;");
    t2.AddQuery("SET v_rank = v_rank + 1;");
    t2.AddQuery("IF v_rank = 1");
    t2.AddQuery("THEN");
    t2.AddQuery("SET wr = pr;");
    t2.AddQuery("SET calculated_points = default_points + ((default_points * ((wr / pr) * 1.5)) * 1.3) + completions;");
    t2.AddQuery("ELSE");
    t2.AddQuery("SET calculated_points = default_points + ((default_points * ((wr / pr) * 1.5)) / 1.3) + completions * 0.75;");
    t2.AddQuery("END IF;");
    t2.AddQuery("UPDATE records SET `records`.`rank` = (SELECT v_rank), `records`.`points` = (SELECT calculated_points) WHERE record_id = v_rec_id;");
    t2.AddQuery("IF in_class = 0");
    t2.AddQuery("THEN");
    t2.AddQuery("UPDATE players SET soldier_points = (SELECT SUM(points) FROM records WHERE player_id = v_player_id AND class = in_class) WHERE id = v_player_id;");
    t2.AddQuery("UPDATE players SET soldier_rank = (SELECT COUNT(*) + 1 FROM records WHERE (SELECT soldier_points WHERE id = v_player_id) > soldier_points) WHERE id = v_player_id;");
    t2.AddQuery("ELSEIF in_class = 1");
    t2.AddQuery("THEN");
    t2.AddQuery("UPDATE players SET demoman_points = (SELECT SUM(points) FROM records WHERE player_id = v_player_id AND class = in_class) WHERE id = v_player_id;");
    t2.AddQuery("UPDATE players SET demoman_rank = (SELECT COUNT(*) + 1 FROM records WHERE (SELECT demoman_points WHERE id = v_player_id) > demoman_points) WHERE id = v_player_id;");
    t2.AddQuery("END IF;");
    t2.AddQuery("END LOOP;");
    t2.AddQuery("CLOSE cur;");
    t2.AddQuery("END;");

    g_hDatabase.Execute(t2, _, Thread_Empty_TransactionFail);

    g_server = AuthServer();

    return;
}