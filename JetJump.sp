#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <SteamWorks>
#include <geoip>
#include <morecolors>
#include <sdktools>
#include <sdkhooks>
#include <clients>
#include <basecomm>
#include <socket>
#include <JetJump>

Database g_hDatabase;

ServerInfo g_server;

Commands g_commands[MAX_COMMANDS];

MapInfo g_currentMap;

Zone g_zones[ZONES_LIMIT];

Run g_run[MAXPLAYERS+1];

Records g_records[RECORDS_LIMIT];
StageEnterTime g_stageEnterTimes[RECORDS_LIMIT];

Player g_player[MAXPLAYERS+1];

Lobby g_lobby[10];

Socket g_Socket;

#include <JetJump\commands.sp>
#include <JetJump\mapchooser.sp>
#include <JetJump\LobbyServer.sp>
#include <JetJump\LobbyClient.sp>

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    if ( late )
    {
        RequestFrame(ConnectDatabase);

        RequestFrame(InitMap);

        for (int i = 0; i <= MaxClients; i++)
        {
            RequestFrame(AuthPlayer, i);
        }
    }
    
    return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
    MC_AddColor("maincolor", 0x62DA9A);
    MC_AddColor("accent", 0xB4F200);
    MC_AddColor("background", 0xF36D91);

    // call InitMap() in this event  to avoid deleting newly created zone entites
    HookEvent("teamplay_round_start", OnRoundStart, EventHookMode_Post);
    HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Post);
    HookEvent("player_connect_client", Event_Player_Connect, EventHookMode_Pre);
    HookEvent("player_disconnect", Event_Player_Disconnect, EventHookMode_Pre);

    g_aMapList = new ArrayList( ByteCountToCells(PLATFORM_MAX_PATH) );
    g_aMapTiersSolly = new ArrayList();
    g_aMapTiersDemo = new ArrayList();
    g_aNominateList = new ArrayList( ByteCountToCells(PLATFORM_MAX_PATH) );
    g_aOldMaps = new ArrayList( ByteCountToCells(PLATFORM_MAX_PATH) );

    ConnectDatabase();
    // load maplist array
    LoadMapList();
    // cache the nominate menu so that it isn't being built every time player opens it
    CreateNominateMenu();

    RegisterAllJetJumpCommands();

    DrawPlayersHud();

    g_Socket = new Socket(SOCKET_UDP, OnServerSocketError);
    
    HookEvent("On_Server_Got_Data", OnServerChildSocketReceive);
    HookEvent("On_Client_Got_Data", OnServerSocketReceive);
}

void OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
    for (int i; i < ZONES_LIMIT; i++)
        if ( g_zones[i].exists )
            CreateZoneEntity( i ); // Creating zone entity and touch/leave hook of them
}

stock void JetJump_PrintToChat(int client, const char[] message, any ...)
{
    MC_CheckTrie();

    char prefix[] = "{background}[JetTimer] {white}";
    char finalMessage[256];

    FormatEx(finalMessage, sizeof(finalMessage), "%s%s", prefix, message );

    char buffer[MAX_BUFFER_LENGTH];
    char buffer2[MAX_BUFFER_LENGTH];

    SetGlobalTransTarget(client);
    Format(buffer, sizeof(buffer), "%s", finalMessage);
    VFormat(buffer2, sizeof(buffer2), buffer, 3);

    MC_ReplaceColorCodes(buffer2);
    MC_SendMessage(client, buffer2);
}

stock void JetJump_PrintToChatAll(const char[] message, any ...)
{
    char prefix[] = "{background}[JetTimer] {white}";
    char finalMessage[256];
    FormatEx(finalMessage, sizeof(finalMessage), "%s%s", prefix, message );

    MC_CheckTrie();

    char buffer[MAX_BUFFER_LENGTH], buffer2[MAX_BUFFER_LENGTH];

    for (int i = 1; i <= MaxClients; ++i) {
        if (!IsClientInGame(i)) {
            continue;
        }

        SetGlobalTransTarget(i);
        Format(buffer, sizeof(buffer), "%s", finalMessage);
        VFormat(buffer2, sizeof(buffer2), buffer, 2);

        MC_ReplaceColorCodes(buffer2);
        MC_SendMessage(i, buffer2);
	}
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

    CreateTimer(2.0, RegeneratePlayersAmmo, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer( 1.0, Timer_OnSecond, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE );
}

public void OnMapEnd()
{
    // cloar our zones firstly
    ClearZonesData();
}

public Action Event_Player_Disconnect(Event event, const char[] name, bool dontBroadcast)
{
    char strName[MAX_NAME_LENGTH];
    event.GetString("name", strName, sizeof(strName));

    MC_PrintToChatAll("{gold}%s {white}has been disconnected", strName);

    event.BroadcastDisabled = true;

    return Plugin_Continue;
}

public Action Event_Player_Connect(Event event, const char[] name, bool dontBroadcast)
{
    char strName[MAX_NAME_LENGTH];
    event.GetString("name", strName, sizeof(strName));

    MC_PrintToChatAll("{gold}%s {white}joins the server", strName);

    event.BroadcastDisabled = true;

    return Plugin_Continue;
}

public Action OnGetMaxHealth(int client, int &maxhealth)
{
    if (client > 0 && client <= MaxClients)
    {
        if (TF2_GetPlayerClass(client) == TFClass_Soldier)
        {
            maxhealth = 900;
        }
        return Plugin_Changed;
    }
    return Plugin_Continue;
}

public Action OnTakeDamage(int client, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (TF2_GetPlayerClass(client) == TFClass_Soldier && damagetype & DMG_FALL)
        return Plugin_Handled;

    return Plugin_Continue;
}

public void OnClientPostAdminCheck(int client)
{
    if (IsClientSourceTV(client)) return;

    AuthPlayer(client);
}

Action RegeneratePlayersAmmo(Handle timer)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if ( !IsClientInGame(client)
            || !IsClientConnected(client)
            || IsClientSourceTV(client)
            || !IsPlayerAlive(client)
            || g_player[client].currentClass == CLASS_INVALID ) continue;

        if ( g_run[client].regenAmmo == g_player[client].currentClass || g_run[client].regenAmmo == CLASS_BOTH )
            TF2_RegeneratePlayer(client);
    }
    
    return Plugin_Continue;
}

void InitMap()
{
    g_bMapVoteFinished = false;
    g_bMapVoteStarted = false;
	
    g_aNominateList.Clear();

    for ( int i = 1; i <= MaxClients; i++ )
    {
        g_cNominatedMap[i][0] = '\0';
    }

    ClearRTV();

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
        FormatEx(query, sizeof(query), "UPDATE map_list SET launches = launches + 1 WHERE id = %i", g_currentMap.id );
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
                                    FROM map_zones WHERE map_id = %i ORDER BY run_id ASC", g_currentMap.id );

    g_hDatabase.Query(Thread_GetMapZones, query);
}

public void Thread_GetMapZones(Database db, DBResultSet results, const char[] error, any data)
{
    if ( strlen(error) > 1 ) { LogError(error); return; }

    int zones_count = 0;

    for (int i = 1; results.FetchRow(); i++ )
    {
        g_zones[i].zoneType = view_as<Zones>(results.FetchInt(0));
        g_zones[i].zoneIndex = results.FetchInt(1);

        g_zones[i].runType = view_as<RunType>(results.FetchInt(2));
        g_zones[i].runInfo.index = results.FetchInt(3);

        if (g_zones[i].runType == RUN_STAGE)
        {
            g_zones[0].runType = RUN_MAP;
            FormatEx( g_zones[0].runInfo.runName, sizeof(RunInfo::runName), "Map" );
            g_zones[0].runInfo.index = 1;
            g_zones[0].zoneType = ZONE_START;
            g_zones[0].zoneIndex = 0;
        }

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

        CreateZoneEntity( i ); // Creating touch/leave hook 

        zones_count++;
    }

    if ( zones_count > 0 )
    {
        PrintToServer("Loaded %i zones! for %s", zones_count, g_currentMap.name);
        JetJump_PrintToChatAll("Loaded {maincolor}%i {white}zones!", zones_count);
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
    FormatEx(query, sizeof(query), "SELECT record_id, player_id, players.name, class, run_type, run_id, time, points, `rank` \
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
        g_records[i].points = results.FetchFloat(7);
        g_records[i].rank = results.FetchInt(8);

        g_records[i].exists = true;

        for (int client = 1; client <= MaxClients; client++)
        {
            if ( g_run[client].type == g_records[i].runType && g_run[client].info.index == g_records[i].runIndex && g_player[client].currentClass == g_records[i].class )
            {
                g_run[client].worldRecord = g_records[ GetWorldRecordRunIndex(g_records[i].class, g_records[i].runType, g_records[i].runIndex) ];

                if ( GetPersonalRecordRunIndex(g_player[client].id, g_records[i].class, g_records[i].runType, g_records[i].runIndex) != -1 )
                    g_run[client].personalRecord = g_records[ GetPersonalRecordRunIndex(g_player[client].id, g_records[i].class, g_records[i].runType, g_records[i].runIndex) ];
            }
        }

        i++;
    }

    if ( i == 0 ) 
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

        g_stageEnterTimes[i].exists = true;

        i++;
    }

    if ( i > 0 )
    {
        PrintToServer("Reloaded %i Stage Enter Records! For %s", i, g_currentMap.name);
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
            if ( g_zones[id].runInfo.index == g_run[client].info.index + 1 && g_player[client].state == STATE_END && g_run[client].type == RUN_STAGE && g_run[client].linearMode && g_player[client].isTimerOn )
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
                    int prefix = currentTime >= bestTime ? '+' : '-';
                    
                    FormatSeconds(currentTime > bestTime ? currentTime - bestTime : bestTime - currentTime, comparisonTimeText);
                    FormatEx(comparisonText, sizeof(comparisonText), "{white}({%s}WR %c%s{white})", prefix == '+' ? "maincolor" : "red", prefix, comparisonTimeText);
                }
                JetJump_PrintToChat(client, "Entered {maincolor}%s {white}with time: {accent}%s %s", g_zones[id].runInfo.runName, currentTimeText, comparisonText);

                g_run[client].stageEnterTime[g_zones[id].runInfo.index] = currentTime;
                g_run[client].linearMode = true;
            }
            // player try to cheat stages run, stop him.
            else if ( ( (g_zones[id].runInfo.index - g_run[client].info.index) > 1
                    || ( g_run[client].info.index == g_zones[id].runInfo.index - 1 && g_player[client].state != STATE_END) )
                    && g_run[client].type == RUN_STAGE
                    && g_run[client].linearMode )
            {
                MC_PrintToChat(client, "{red}ERROR {white}| Your run was {accent}CLOSED{white}, becouse you not finished:")
                
                int lastUnfinishedRun = ( g_player[client].state == STATE_RUNNING ) ? g_run[client].info.index : g_run[client].info.index + 1;

                for (int i = g_zones[id].runInfo.index - 1; i >= lastUnfinishedRun; i--)
                {
                    JetJump_PrintToChat(client, "Stage {maincolor}%i", i);
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

        int prIndex = GetPersonalRecordRunIndex(g_player[client].id, g_player[client].currentClass, g_zones[id].runType, g_zones[id].runInfo.index);
        int wrIndex = GetWorldRecordRunIndex(g_player[client].currentClass, g_zones[id].runType, g_zones[id].runInfo.index); 

        Records emptyRecord;
        g_run[client].personalRecord = ( prIndex != -1 ) ? g_records[prIndex] : emptyRecord;
        g_run[client].worldRecord = ( wrIndex != -1 ) ? g_records[wrIndex] : emptyRecord;

        g_run[client].type = g_zones[id].runType;
        g_run[client].info = g_zones[id].runInfo;
        g_run[client].regenAmmo = g_zones[id].regen_ammo;

        g_player[client].currentZone = g_zones[id];
        g_player[client].state = STATE_START;
    }
    else if ( g_zones[id].zoneType == ZONE_END && g_player[client].state == STATE_RUNNING)
    {
        if ( g_zones[id].runType != g_run[client].type || g_zones[id].runInfo.index != g_run[client].info.index ) return;

        g_player[client].currentZone = g_zones[id];

        g_player[client].state = STATE_END;

        if ( g_player[client].isTimerOn )
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
    if ( client < 1 || client > MaxClients || !IsClientInGame(client) || !IsClientConnected(client) || g_player[client].state == STATE_INVALID ) return;

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
    if ( g_player[client].currentClass == CLASS_INVALID ) return;

    char time[TIME_SIZE_DEF];
    char comparisonText[128], comparisonTimeText[TIME_SIZE_DEF];
    
    int prIndex = GetPersonalRecordRunIndex(g_player[client].id, g_player[client].currentClass, run.type, run.info.index);
    int wrIndex = GetWorldRecordRunIndex(g_player[client].currentClass, run.type, run.info.index);

    if ( run.type == RUN_MAP || run.type == RUN_BONUS )
    {
        run.finishTime = GetEngineTime() - run.startTime;

        if ( prIndex != -1 )
        {
            g_run[client].personalRecord = g_records[prIndex];
            run.personalRecord = g_run[client].personalRecord;
        }

        if (wrIndex != -1)
        {
            g_run[client].worldRecord = g_records[wrIndex];
            run.worldRecord = g_run[client].worldRecord;
        }

        if ( run.worldRecord.exists )
        {
            int prefix = run.finishTime >= run.worldRecord.time ? '+' : '-';
                        
            FormatSeconds(run.finishTime >= run.worldRecord.time ? run.finishTime - run.worldRecord.time : run.worldRecord.time - run.finishTime, comparisonTimeText);
            FormatEx(comparisonText, sizeof(comparisonText), "{white}({%s}WR %c%s{white})", prefix == '+' ? "maincolor" : "red", prefix, comparisonTimeText);

            if ( prIndex != -1 && g_run[client].personalRecord.time > run.finishTime )
            {
                FormatSeconds(run.personalRecord.time - run.finishTime, comparisonTimeText);
                FormatEx(comparisonText, sizeof(comparisonText), "%s | improved by {accent}%s", comparisonText, comparisonTimeText);
            }
        }

        FormatSeconds(run.finishTime, time);
        JetJump_PrintToChatAll( "{gold}%N {white}finished the {maincolor}%s{white}: {accent}%s %s", client, run.info.runName, time, comparisonText );

        if ( prIndex == -1 || run.finishTime < g_records[prIndex].time )
            SaveRecord(g_player[client], run);
    }
    else if ( run.type == RUN_STAGE )
    {
        run.stageFinishTime = GetEngineTime() - run.stageStartTime;
        
        if ( run.worldRecord.exists )
        {
            int prefix = run.stageFinishTime >= run.worldRecord.time ? '+' : '-';
                        
            FormatSeconds(run.stageFinishTime >= run.worldRecord.time ? run.stageFinishTime - run.worldRecord.time : run.worldRecord.time - run.stageFinishTime, comparisonTimeText);
            FormatEx(comparisonText, sizeof(comparisonText), "{white}({%s}WR %c%s{white})", prefix == '+' ? "maincolor" : "red", prefix, comparisonTimeText);

            if ( prIndex != -1 && g_run[client].personalRecord.time > run.stageFinishTime )
            {
                FormatSeconds(run.personalRecord.time - run.stageFinishTime, comparisonTimeText);
                FormatEx(comparisonText, sizeof(comparisonText), "%s | improved by {accent}%s", comparisonText, comparisonTimeText);
            }
        }

        FormatSeconds(run.stageFinishTime, time);
        JetJump_PrintToChatAll( "{gold}%N {white}finished the {maincolor}%s{white}: {accent}%s %s", client, run.info.runName, time, comparisonText );
        
        if ( prIndex == -1 || run.stageFinishTime < g_records[prIndex].time )
            SaveRecord(g_player[client], run);

        if ( !IsZoneExists(ZONE_START, RUN_STAGE, g_player[client].currentZone.runInfo.index + 1 ) && run.linearMode)
        {
            run.type = g_zones[0].runType;
            run.info = g_zones[0].runInfo;

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
                                    ON DUPLICATE KEY UPDATE time = %f, date = NOW(), server_id = %i;",
                                    g_currentMap.id, player.id, player.currentClass, run.type, run.type != RUN_MAP ? run.info.index : 1, run.type == RUN_STAGE ? run.stageFinishTime : run.finishTime, g_server.id,
                                    run.type == RUN_STAGE ? run.stageFinishTime : run.finishTime, g_server.id);

    transaction.AddQuery(query);

    FormatEx(query, sizeof(query), "UPDATE map_info SET %s = (SELECT COUNT(*) FROM records \
                                    WHERE records.map_id = map_info.map_id AND run_type = %i AND run_id = %i AND class = %i) \
                                    WHERE map_id = %i AND run_type = %i AND run_id = %i;",
                                    player.currentClass == CLASS_SOLDIER ? "soldier_completions" : "demoman_completions",
                                    run.type, run.info.index, player.currentClass,
                                    g_currentMap.id, run.type, run.info.index);

    transaction.AddQuery(query);

    // that means player just finish stages map correctly
    int lastStage;

    for (int i = 1; i < ZONES_LIMIT; i++)
    {
        if ( FindZoneArrayId(RUN_STAGE, ZONE_START, i) != -1)
            lastStage++;
    }

    if ( run.type == RUN_MAP && lastStage > 1 && run.linearMode )
    {
        // we start by stage 2 obviously
        for (int stage_id = 2; stage_id <= lastStage; stage_id++)
        {
            FormatEx(query, sizeof(query), "INSERT INTO enter_stage_times (record_id, map_id, player_id, class, stage_id, time) \
                                            VALUES \
                                            ( \
                                                (SELECT record_id FROM records WHERE map_id = %i AND player_id = %i AND class = %i AND run_type = 0 AND run_id = 1), \
                                                %i, %i, %i, %i, %f \
                                            ) \
                                            ON DUPLICATE KEY UPDATE time = %f;",
                                            g_currentMap.id, player.id, player.currentClass,
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
                JetJump_PrintToChat(i, "Your run dont {red}SAVED{white}! No tiers to calculate points.");
                return;
            }
        }
    }
}

void DrawPlayersHud()
{
    static int player;

    static State state;
    static Run run;

    static float currentTime;
    static char currentTimeText[TIME_SIZE_DEF];

    static char type[32];
    static char hud[256];

    static float engineTime;
    engineTime = GetEngineTime();

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
            if ( player == -1 ) player = client;
        }

        if ( g_player[player].currentClass == CLASS_INVALID ) continue;

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

            if ( run.type == RUN_STAGE )
            {
                if ( run.linearMode &&
                ( run.info.index > 1
                || ( state == STATE_END
                && IsZoneExists( ZONE_START, RUN_STAGE, run.info.index + 1 ) ) ) )
                {
                    currentTime = engineTime - run.startTime;
                    FormatSeconds(currentTime, currentTimeText, FORMAT_2DECI);

                    if (!g_player[player].isTimerOn)
                        FormatEx(currentTimeText, sizeof(currentTimeText), "[Timer OFF]");

                    FormatEx(hud, sizeof(hud), "%s\n \n(%s %s)\n \n%s",
                    currentTimeText,
                    run.info.runName,
                    state == STATE_START ? "Start" : "Finish",
                    type);
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

            if (!g_player[player].isTimerOn)
                FormatEx(currentTimeText, sizeof(currentTimeText), "[Timer OFF]");

            FormatEx(hud, sizeof(hud), "%s\n \n(%s)\n \n%s", currentTimeText, run.info.runName, type);
        }
        else if ( state == STATE_INVALID )
        {
            FormatEx(hud, sizeof(hud), "[Enter the Start Zone]");
        }

        if (shouldDrawHud[client])
        {
            PrintHintTextCenter( client, hud );

            if ( state != STATE_INVALID )
            {
                PrintHintTextRightSide(client, player);
            }
        }

        if ( state == STATE_RUNNING
            || ((state == STATE_START || state == STATE_END) && run.type == RUN_STAGE && run.info.index > 1 && run.linearMode ) )
        {
            shouldDrawHud[client] = true;
        }
        else
        {
            if (whenDrawHud[client] < engineTime)
            {
                shouldDrawHud[client] = true;
                whenDrawHud[client] = engineTime + 0.5;
            }
            else
            {
                shouldDrawHud[client] = false;
            }
        }
    }

    // fuck yea
    RequestFrame( DrawPlayersHud );
}

stock void PrintHintTextCenter(int client, const char[] buffer)
{
    Handle msg = StartMessageOne("HintText", client, USERMSG_BLOCKHOOKS);

    if (msg != INVALID_HANDLE)
	{
        BfWriteString(msg, buffer);
        EndMessage();
	}
}

stock void PrintHintTextRightSide(int client, int target_player)
{
    if ( IsClientObserver(client) && GetEntPropEnt(client, Prop_Send, "m_hObserverTarget") == -1 ) return;

    char hud[254];

    char remaining[64];
    char TimeText[TIME_SIZE_DEF];

    int timeleft; GetMapTimeLeft(timeleft);

    if ( timeleft >= 60 )
	{
		int mins = timeleft / 60;
		FormatEx(remaining, sizeof(remaining), "%i minutes left", mins);
	}
	else if ( timeleft < 60 && timeleft > 0 )
	{
		FormatEx(remaining, sizeof(remaining), "%i seconds left", timeleft);
	}
	else if ( timeleft <= 0 )
	{
		FormatEx(remaining, sizeof(remaining), "Map ending...");
	}

    FormatEx(hud, sizeof(hud), "%s\n\n", remaining);
    
    if ( g_run[target_player].personalRecord.exists )
    {
        FormatSeconds(g_run[target_player].personalRecord.time, TimeText, FORMAT_2DECI);

        if ( g_run[target_player].personalRecord.player_id == g_run[target_player].worldRecord.player_id )
        {
            FormatEx(hud, sizeof(hud), "%sPersonal Record:\n%s\n\n", hud, TimeText);
        }
        else
        {
            char PrWrCompare[TIME_SIZE_DEF];
            FormatSeconds(g_run[target_player].personalRecord.time - g_run[target_player].worldRecord.time, PrWrCompare, FORMAT_2DECI);
            FormatEx(hud, sizeof(hud), "%sPersonal Record:\n%s (+%s)\n\n", hud, TimeText, PrWrCompare);
        }
    }
    else
    {
        FormatEx(hud, sizeof(hud), "%sPersonal Record:\n-\n\n", hud);
    }


    if ( g_run[target_player].worldRecord.exists )
    {
        FormatSeconds(g_run[target_player].worldRecord.time, TimeText, FORMAT_2DECI);
        FormatEx(hud, sizeof(hud), "%sWorld Record:\n%s (%s)\n\n", hud, TimeText, g_run[target_player].worldRecord.player_name);
    }
    else
    {
        FormatEx(hud, sizeof(hud), "%sWorld Record:\n-\n\n", hud);
    }

    char strSpectatorsName[256];
    int Spec_Count;
    for (int i = 1; i <= MaxClients; i++)
    {
		if (!IsClientInGame(i) || !IsClientObserver(i))
				continue;
				
		int iSpecMode = GetEntProp(i, Prop_Send, "m_iObserverMode");
			
			// The client isn't spectating any one person, so ignore them.
		if (iSpecMode != 4 && iSpecMode != 5)
				continue;
			
			// Find out who the client is spectating.
		int iTarget = GetEntPropEnt(i, Prop_Send, "m_hObserverTarget");
			
			// Are they spectating our player?
		if (iTarget == target_player)
		{
            char name[32];
            GetClientName(i, name, sizeof(name));

            Spec_Count++;
            if (Spec_Count <= 5)
                FormatEx(strSpectatorsName, sizeof(strSpectatorsName), "%s\n%s", strSpectatorsName, name);
		}
	}

    if ( Spec_Count <= 5 )
        FormatEx(hud, sizeof(hud), "%sSpectators (%i)%s", hud, Spec_Count, strSpectatorsName);
    else
        FormatEx(hud, sizeof(hud), "%sSpectators (%i)%s\n(+%i)", hud, Spec_Count, strSpectatorsName, Spec_Count - 5);

    StrCat(hud, sizeof(hud), "\n\n");

    Handle userMessage = StartMessageOne("KeyHintText", client);

    if (userMessage != INVALID_HANDLE)
    {
        BfWriteByte(userMessage, 1);
        BfWriteString(userMessage, hud);

        EndMessage();
    }
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

public Action OnClientSayCommand( int client, const char[] szCommand, const char[] text )
{
    if ( !client || BaseComm_IsClientGagged( client ) ) return Plugin_Continue;

    char sCodes[8][] = {"\x01", "\x02", "\x03", "\x04", "\x05", "\x06", "\x07", "\x08"};

    char live[10];
    char msg[200];
    char alltext[300];
    int rank;
    char class[1];

    FormatEx(msg, sizeof(msg), "%s", text);
    TrimString(msg);

    for ( int i = 0; i < 8; i++)
        ReplaceString(msg, sizeof(msg), sCodes[i], "");

    if ( !IsPlayerAlive(client) )
        FormatEx(live, sizeof(live), "* ");
    else
        FormatEx(live, sizeof(live), "");

    if (g_player[client].soldierRank <= 0)
    {
        class[0] = 'D';
        rank = g_player[client].demomanRank;
    }
    else if (g_player[client].demomanRank <= 0)
    {
        class[0] = 'S';
        rank = g_player[client].soldierRank;
    }
    else
    {
        if (g_player[client].soldierRank <= g_player[client].demomanRank)
        {
            class[0] = 'S';
            rank = g_player[client].soldierRank;
        }
        else
        {
            class[0] = 'D';
            rank = g_player[client].demomanRank;
        }
    }

    if ( rank > 0 )
        FormatEx( alltext, sizeof(alltext), "%s{red}[{white}%s{red}|{orange}Rank %i{red}] {cyan}%s{white}: %s", live, class, rank, g_player[client].name, msg );
    else
        FormatEx( alltext, sizeof(alltext), "%s{red}[{grey}Unranked{red}] {grey}%s{white}: %s", live, g_player[client].name, msg );

    for (int i = 1; i <= MaxClients; i++)
        if (IsClientConnected(i) && IsClientInGame(i))
            MC_PrintToChat(i, alltext);
    
    if ( g_player[client].currentLobby.serverSocket )
    {
        char lobbyMsg[MC_MAX_MESSAGE_LENGTH];
        FormatEx(lobbyMsg, sizeof(lobbyMsg), "::Lobby-Msg:: %i {green}| %s{endmsg}", g_player[client].id, alltext);
        
        g_player[client].currentLobby.serverSocket.Send(lobbyMsg);
    }
    
    return Plugin_Handled;
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

stock void DrawZone(int client, Zone zoneToDraw)
{
    enum
    {
        BEAM_POS_BOTTOM1,
        BEAM_POS_BOTTOM2,
        BEAM_POS_BOTTOM3,
        BEAM_POS_BOTTOM4,
        BEAM_POS_TOP1,
        BEAM_POS_TOP2,
        BEAM_POS_TOP3,
        BEAM_POS_TOP4,
        
        BEAM_POINTS
    }

    #define ZONE_WIDTH 1.5
    #define ZONE_BEAM_ALIVE 25.0

    int color[4] = {255, 215, 0, 255};

    int laser = PrecacheModel("sprites/laserbeam.vmt");

    float point[BEAM_POINTS][3];
    float ZoneBottomPoint[4][3];
    float ZoneTopPoint[4][3];

    float vecTemp[3];

    int zones_drawed;

    Zone zone;

    for (int i; i < ZONES_LIMIT; i++)
    {
        if ( !g_zones[i].exists ) continue;

        if ( g_zones[i].zoneType != zoneToDraw.zoneType
            || g_zones[i].runType != zoneToDraw.runType
            || g_zones[i].runInfo.index != zoneToDraw.runInfo.index ) continue;

        zone = g_zones[i];

        vecTemp[0] = zone.cordMin[0] + ZONE_WIDTH;
        vecTemp[1] = zone.cordMin[1] + ZONE_WIDTH;
        vecTemp[2] = zone.cordMin[2] + ZONE_WIDTH;
        ArrayCopy( vecTemp, point[BEAM_POS_BOTTOM1], 3 );

        vecTemp[0] = zone.cordMax[0] - ZONE_WIDTH;
        vecTemp[1] = zone.cordMin[1] + ZONE_WIDTH;
        vecTemp[2] = zone.cordMin[2] + ZONE_WIDTH;
        ArrayCopy( vecTemp, point[BEAM_POS_BOTTOM2], 3 );

        vecTemp[0] = zone.cordMax[0] - ZONE_WIDTH;
        vecTemp[1] = zone.cordMax[1] - ZONE_WIDTH;
        vecTemp[2] = zone.cordMin[2] + ZONE_WIDTH;
        ArrayCopy( vecTemp, point[BEAM_POS_BOTTOM3], 3 );

        vecTemp[0] = zone.cordMin[0] + ZONE_WIDTH;
        vecTemp[1] = zone.cordMax[1] - ZONE_WIDTH;
        vecTemp[2] = zone.cordMin[2] + ZONE_WIDTH;
        ArrayCopy( vecTemp, point[BEAM_POS_BOTTOM4], 3 );

        // Top
        vecTemp[0] = zone.cordMin[0] + ZONE_WIDTH;
        vecTemp[1] = zone.cordMin[1] + ZONE_WIDTH;
        vecTemp[2] = zone.cordMax[2] - ZONE_WIDTH;
        ArrayCopy( vecTemp, point[BEAM_POS_TOP1], 3 );

        vecTemp[0] = zone.cordMax[0] - ZONE_WIDTH;
        vecTemp[1] = zone.cordMin[1] + ZONE_WIDTH;
        vecTemp[2] = zone.cordMax[2] - ZONE_WIDTH;
        ArrayCopy( vecTemp, point[BEAM_POS_TOP2], 3 );

        vecTemp[0] = zone.cordMax[0] - ZONE_WIDTH;
        vecTemp[1] = zone.cordMax[1] - ZONE_WIDTH;
        vecTemp[2] = zone.cordMax[2] - ZONE_WIDTH;
        ArrayCopy( vecTemp, point[BEAM_POS_TOP3], 3 );

        vecTemp[0] = zone.cordMin[0] + ZONE_WIDTH;
        vecTemp[1] = zone.cordMax[1] - ZONE_WIDTH;
        vecTemp[2] = zone.cordMax[2] - ZONE_WIDTH;
        ArrayCopy( vecTemp, point[BEAM_POS_TOP4], 3 );

        // Bottom
        ArrayCopy( point[BEAM_POS_BOTTOM1], ZoneBottomPoint[0], 3 );
        ArrayCopy( point[BEAM_POS_BOTTOM2], ZoneBottomPoint[1], 3 );
        ArrayCopy( point[BEAM_POS_BOTTOM3], ZoneBottomPoint[2], 3 );
        ArrayCopy( point[BEAM_POS_BOTTOM4], ZoneBottomPoint[3], 3 );
        
        // Top
        ArrayCopy( point[BEAM_POS_TOP1], ZoneTopPoint[0], 3 );
        ArrayCopy( point[BEAM_POS_TOP2], ZoneTopPoint[1], 3 );
        ArrayCopy( point[BEAM_POS_TOP3], ZoneTopPoint[2], 3 );
        ArrayCopy( point[BEAM_POS_TOP4], ZoneTopPoint[3], 3 );

        for (int z = 0; z < 4; z++)
        {
            // Bottom
            TE_SetupBeamPoints( ZoneBottomPoint[z], ZoneBottomPoint[(z == 3) ? 0 : z+1], laser, 0, 0, 0, ZONE_BEAM_ALIVE, ZONE_WIDTH, ZONE_WIDTH, 0, 0.0, color, 0 );
            TE_SendToClient(client);

            // Top
            TE_SetupBeamPoints( ZoneTopPoint[z], ZoneTopPoint[(z == 3) ? 0 : z+1], laser, 0, 0, 0, ZONE_BEAM_ALIVE, ZONE_WIDTH, ZONE_WIDTH, 0, 0.0, color, 0 );
            TE_SendToClient(client);

            // From bottom to top.
            TE_SetupBeamPoints( ZoneBottomPoint[z], ZoneTopPoint[z], laser, 0, 0, 0, 25.0, ZONE_WIDTH, ZONE_WIDTH, 0, 0.0, color, 0 );
            TE_SendToClient(client);
        }
        zones_drawed++;
    }

    if ( zones_drawed > 0 )
        JetJump_PrintToChat(client, "Drawed {gold}%i {white}zone(s) for {cyan}%s%s", zones_drawed, zoneToDraw.runInfo.runName, zoneToDraw.zoneType == ZONE_START ? " Start" : " End" );
}

void ClearPlayerData(int client)
{
    if ( !(1 <= client <= MaxClients) ) return

    Player emptyPlayer

    g_player[client] = emptyPlayer
    g_player[client].state = STATE_INVALID;
    g_player[client].isTimerOn = true;
    g_player[client].currentZone.arrayId = -1;
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
    StageEnterTime emptyStageEnter;

    for ( int i; i < RECORDS_LIMIT; i++ )
    {
        g_records[i] = emptyRecord;
        g_stageEnterTimes[i] = emptyStageEnter;
    }
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

stock int GetPersonalRecordRunIndex(int player_id, Class class, RunType runType, int run_id)
{
    for (int i = 0; i < RECORDS_LIMIT; i++)
    {
        if ( g_records[i].player_id == player_id && g_records[i].class == class && g_records[i].runType == runType && g_records[i].runIndex == run_id && g_records[i].exists )
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
        if ( g_records[i].class == class && g_records[i].runType == runType && g_records[i].runIndex == run_id && g_records[i].exists )
        {
            if ( index == -1 )
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
    int wrIndex = GetWorldRecordRunIndex(class, RUN_MAP, 1);

    if ( wrIndex == -1 )
        return -1;

    for (int i = 0; i < RECORDS_LIMIT; i++)
        if ( g_stageEnterTimes[i].record_id == g_records[wrIndex].record_id
            && g_stageEnterTimes[i].stage_id == stage_id
            && g_stageEnterTimes[i].class == class )
            return i;

    return -1;
}

stock int GetStageEnterPersonalRecordIndex(int client, Class class, int stage_id)
{
    int prIndex = GetPersonalRecordRunIndex(g_player[client].id, class, RUN_MAP, 1);

    if ( prIndex == -1 )
        return -1;

    for (int i = 0; i < RECORDS_LIMIT; i++)
        if ( g_stageEnterTimes[i].record_id == g_records[prIndex].record_id
            && g_stageEnterTimes[i].stage_id == stage_id
            && g_stageEnterTimes[i].class == class )
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
			default:
                return CLASS_INVALID;
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
    char query[1024];
    
    FormatEx(query, sizeof(query), "CALL UpdateMapPoints(%i, %i, %i, %i);", g_currentMap.id, runtype, run_id, class);

    transaction.AddQuery(query);

    FormatEx(query, sizeof(query), "SELECT player_id, records.run_type, records.run_id, records.class, records.points, records.`rank`, map_info.%s \
                                    FROM records JOIN map_info ON map_info.map_id = records.map_id AND map_info.run_type = records.run_type AND map_info.run_id = records.run_id \
                                    WHERE records.map_id = %i AND records.run_type = %i AND records.run_id = %i AND records.class = %i;", class == CLASS_SOLDIER ? "soldier_completions" : "demoman_completions", g_currentMap.id, runtype, run_id, class);

    transaction.AddQuery(query);

    g_hDatabase.Execute(transaction, Thread_GetUpdatedPoints, Thread_Empty_TransactionFail);
}

public void Thread_GetUpdatedPoints (Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
    int player_id;

    RunType run_type;

    int run_id;

    Class class;

    float points;

    int prIndex;
    float prevPoints;

    int rank, prevRank, completions;

    Transaction t = new Transaction();
    char query[255];

    bool mustRequeryRankSurely;

    while ( results[1].FetchRow() )
    {
        player_id = results[1].FetchInt(0);
        run_type = view_as<RunType>(results[1].FetchInt(1));
        run_id = results[1].FetchInt(2);

        class = view_as<Class>(results[1].FetchInt(3));

        points = results[1].FetchFloat(4);
        rank = results[1].FetchInt(5);
        completions = results[1].FetchInt(6);

        prIndex = GetPersonalRecordRunIndex(player_id, class, run_type, run_id);

        prevPoints = prIndex != -1 ? g_records[prIndex].points : 0.0;

        prevRank = prIndex != -1 ? g_records[prIndex].rank : 0;

        bool mustRequeryRank;

        for (int i = 1; i <= MaxClients; i++)
        {
            if ( g_player[i].id == player_id && IsClientInGame(i) )
            {
                if ( points != prevPoints )
                {
                    JetJump_PrintToChat(i, "You gain %s%.1f {white}%s points for {maincolor}%s", (points - prevPoints) > 0.0 ? "{accent}" : "{red}", points - prevPoints, class == CLASS_SOLDIER ? "Soldier" : "Demoman",
                                    FindZoneArrayId(run_type, ZONE_START, run_id) != -1 ? g_zones[FindZoneArrayId(run_type, ZONE_START, run_id)].runInfo.runName : "Map" );
                    mustRequeryRank = true;
                }
                if ( rank != prevRank )
                {
                    if ( prevRank == 0 )
                    {
                        JetJump_PrintToChat(i, "Now rank: {accent}%i/%i {white}on {maincolor}%s {white}(%s)", rank, completions, class == CLASS_SOLDIER ? "Soldier" : "Demoman",
                                        FindZoneArrayId(run_type, ZONE_START, run_id) != -1 ? g_zones[FindZoneArrayId(run_type, ZONE_START, run_id)].runInfo.runName : "Map" );
                    }
                    else
                    {
                        JetJump_PrintToChat(i, "Now rank: {accent}%i/%i {white}(%s%i{white}) on {maincolor}%s {white}(%s)", rank, completions, rank < prevRank ? "{accent}" : "{red}+", rank - prevRank, class == CLASS_SOLDIER ? "Soldier" : "Demoman",
                                        FindZoneArrayId(run_type, ZONE_START, run_id) != -1 ? g_zones[FindZoneArrayId(run_type, ZONE_START, run_id)].runInfo.runName : "Map" );
                    }
                    mustRequeryRank = true;
                }

                if ( mustRequeryRank )
                {
                    FormatEx( query, sizeof(query), "SELECT soldier_rank, demoman_rank FROM players WHERE id = %i", g_player[i].id );
                    t.AddQuery(query, i);

                    mustRequeryRankSurely = true;
                }
            }
        }
    }
    
    InitRecords();

    if ( mustRequeryRankSurely )
        g_hDatabase.Execute(t, Thread_GetPlayersRanks);
}

void Thread_GetPlayersRanks(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
    for (int i; i < numQueries; i++)
    {
        if (results[i].FetchRow())
        {
            g_player[queryData[i]].soldierRank = results[i].FetchInt(0);
            g_player[queryData[i]].demomanRank = results[i].FetchInt(1);
        }
    }
}


void AuthServer()
{
    int iPublicIP[4];

    // if we cant get public ip --> try until we get
    if (!SteamWorks_IsConnected() || !SteamWorks_GetPublicIP(iPublicIP))
    {
        RequestFrame(AuthServer);
        return;
    }

    if (iPublicIP[0] == 0)
    {
        RequestFrame(AuthServer);
        return;
    }

    Format(g_server.ip, sizeof(ServerInfo::ip), "%d.%d.%d.%d", iPublicIP[0], iPublicIP[1], iPublicIP[2], iPublicIP[3]);
    g_server.port = GetConVarInt(FindConVar("hostport"));
    g_server.maxPlayers = 10;
    GetConVarString(FindConVar("hostname"), g_server.name, sizeof(ServerInfo::name));
    g_server.isOnline = true;

    char query[256];
    FormatEx(query, sizeof(query), "INSERT INTO servers (name, ip, max_players, isOnline) VALUES('%s', '%s:%i', %i, 1) \
                                    ON DUPLICATE KEY UPDATE name = '%s', max_players = %i, isOnline = 1",
                                    g_server.name,
                                    g_server.ip, g_server.port,
                                    g_server.maxPlayers,
                                    g_server.name,
                                    g_server.maxPlayers);

    g_hDatabase.Query(Thread_Empty, query);

    FormatEx(query, sizeof(query), "SELECT id FROM servers WHERE ip = '%s:%i'", g_server.ip, g_server.port);

    g_hDatabase.Query(Thread_GetServerId, query);
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
}

void AuthPlayer(int client)
{
    if ( !(1 <= client <= MaxClients) ) return;
    if ( !IsClientInGame(client) || IsClientSourceTV(client) ) return;
    
    char query[300];

    SDKHook(client, SDKHook_GetMaxHealth, OnGetMaxHealth);
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);

    ClearPlayerData(client);

    g_player[client].clientIndex = client;
    GetClientAuthId(client, AuthId_Steam2, g_player[client].steamid, sizeof(Player::steamid));
    GetClientAuthId(client, AuthId_SteamID64, g_player[client].steamid64, sizeof(Player::steamid64));

    FormatEx( query, sizeof(query), "SELECT id, settingsFlag, soldier_points, demoman_points, soldier_rank, demoman_rank, isAdmin FROM players WHERE steamid = '%s'", g_player[client].steamid );
    g_hDatabase.Query(Thread_GetPlayerInfo, query, client);
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

    MC_PrintToChatAll("{gold}%s {white}({maincolor}%s{white}) {white}connected from {accent}%s", g_player[client].name, info, g_player[client].country);
}

void Thread_GetPlayerInfo(Database db, DBResultSet results, const char[] error, any client)
{
    if ( strlen(error) > 1 )
    {
        LogError(error);
        return;
    }

    ShowWelcomeMenu(client);

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

        char query[256];
        FormatEx(query, sizeof(query), "UPDATE players SET online_on_server_id = %i, last_connection = NOW() WHERE id = %i;", g_server.id, g_player[client].id);
        transaction.AddQuery(query);

        FormatEx(query, sizeof(query), "UPDATE servers SET players = %i, total_joins = total_joins + 1 WHERE id = %i", GetClientCount() - 1, g_server.id);
        transaction.AddQuery(query);

        g_hDatabase.Execute(transaction, _, Thread_Empty_TransactionFail);

        JoinRankNotify(client);
    }
    else
    {
        // so if player connected first time, lets insert data about him and draw welcome menu.
        char query[300];
        FormatEx(query, sizeof(query), "INSERT INTO players (name, steamid, steamid64, ip, first_connection) VALUES('%s', '%s', '%s', '%s', NOW())", 
                                        g_player[client].name,
                                        g_player[client].steamid,
                                        g_player[client].steamid64,
                                        g_player[client].ip );

        g_hDatabase.Query(Thread_Empty, query);

        // Auth this player again to get default data
        AuthPlayer(client);

        ShowWelcomeMenu(client);
    }

    return;
}

void ShowWelcomeMenu(int client)
{
    Panel panel = new Panel();

    panel.SetTitle("Welcome to the JetJump (We need to think about the name)\n \n ");

    panel.DrawText("The plugin is currently in alpha version,\nbut basic things have been implemented, such as:\n ");
    panel.DrawText("Timer;\nNew 'fair' points system;\nA few commands that you can see in /commands;\n ");
    panel.DrawText("Work is underway on innovative features for this mode.\n ");
    panel.DrawText("In the future, servers will be launched all over the world,\nimmediately after the project is fully ready.\n \n \n ");

    panel.CurrentKey = 10;
    panel.DrawItem("[Understandable]", ITEMDRAW_CONTROL);

    panel.Send(client, Welcome_MenuHandler, MENU_TIME_FOREVER);
}

int Welcome_MenuHandler(Menu panel, MenuAction action, int client, int item)
{
    if ( action == MenuAction_End )
        delete panel;
    
    if ( action == MenuAction_Select )
    {
        if ( item == 10 )
            delete panel;
    }

    return 0;
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
}

// empty thread transaction callback for non-select queries (ON FAIL).
public void Thread_Empty_TransactionFail(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    PrintToServer("ERROR | %s", error);
    PrintToServer("ERROR query index | %i", failIndex);
    LogError( error );
}

void ConnectDatabase()
{
    char error[256];

    g_hDatabase = SQL_Connect("JetJump", true, error, sizeof(error));

    if ( g_hDatabase == INVALID_HANDLE )
        SetFailState("ERROR | JetJump can't connect to database; Check databases.cfg settings;")
    
    g_hDatabase.SetCharset("utf8");

    PrintToServer("SUCEFULL | JetJump Database Connected!");

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
                    steamid64 VARCHAR(128), \
                    settingsFlag BIGINT NOT NULL DEFAULT 0, \
                    soldier_points DOUBLE NOT NULL DEFAULT 0.0, \
                    demoman_points DOUBLE NOT NULL DEFAULT 0.0, \
                    soldier_rank INT NOT NULL DEFAULT -1, \
                    demoman_rank INT NOT NULL DEFAULT -1, \
                    online_on_server_id INT, \
                    in_lobby INT NOT NULL DEFAULT -1, \
                    isAdmin INT NOT NULL DEFAULT 0, \
                    ip VARCHAR(32) NOT NULL DEFAULT 'None', \
                    first_connection DATETIME NOT NULL DEFAULT NOW(), \
                    last_connection DATETIME NOT NULL DEFAULT NOW(), \
                    FOREIGN KEY (online_on_server_id) REFERENCES servers (id) \
                    ON DELETE SET DEFAULT \
                );");

    t.AddQuery( "CREATE TABLE IF NOT EXISTS map_info \
                (\
                    map_id INT NOT NULL, \
                    run_type INT NOT NULL, \
                    run_id INT NOT NULL, \
                    \
                    soldier_tier INT NOT NULL DEFAULT -1, \
                    demoman_tier INT NOT NULL DEFAULT -1, \
                    soldier_completions INT NOT NULL DEFAULT 0, \
                    demoman_completions INT NOT NULL DEFAULT 0, \
                    regen_ammo INT NOT NULL DEFAULT -1, \
                    FOREIGN KEY (map_id) REFERENCES map_list (id) \
                    ON DELETE CASCADE \
                    ON UPDATE CASCADE, \
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
                    map_id INT NOT NULL, \
                    player_id INT NOT NULL, \
                    class INT NOT NULL, \
                    run_type INT NOT NULL, \
                    run_id INT NOT NULL, \
                    time DOUBLE NOT NULL, \
                    `rank` INT DEFAULT NULL, \
                    points DOUBLE DEFAULT NULL, \
                    server_id INT NOT NULL REFERENCES servers (id), \
                    date DATETIME NOT NULL DEFAULT NOW(), \
                    FOREIGN KEY (map_id) REFERENCES map_list (id) \
                    ON DELETE CASCADE \
                    ON UPDATE CASCADE, \
                    FOREIGN KEY (player_id) REFERENCES players (id) \
                    ON DELETE CASCADE \
                    ON UPDATE CASCADE, \
                    UNIQUE KEY records_indexes (map_id, player_id, class, run_type, run_id) \
                );");

    t.AddQuery( "CREATE TABLE IF NOT EXISTS enter_stage_times \
                ( \
                    record_id INT NOT NULL, \
                    map_id INT NOT NULL, \
                    player_id INT NOT NULL, \
                    class INT NOT NULL, \
                    stage_id INT NOT NULL, \
                    time DOUBLE NOT NULL, \
                    FOREIGN KEY (record_id) REFERENCES records (record_id) \
                    ON DELETE CASCADE \
                    ON UPDATE CASCADE, \
                    FOREIGN KEY (map_id) REFERENCES map_list (id) \
                    ON DELETE CASCADE \
                    ON UPDATE CASCADE, \
                    FOREIGN KEY (player_id) REFERENCES players (id) \
                    ON DELETE CASCADE \
                    ON UPDATE CASCADE, \
                    UNIQUE KEY stages_enter_index (map_id, player_id, class, stage_id) \
                );");

    t.AddQuery( "CREATE TABLE IF NOT EXISTS lobby \
                ( \
                    id INT NOT NULL PRIMARY KEY AUTO_INCREMENT, \
                    creator_id INT NOT NULL, \
                    server_id INT NOT NULL, \
                    password VARCHAR(32), \
                    lobby_name VARCHAR(32), \
                    port INT NOT NULL, \
                    FOREIGN KEY (server_id) REFERENCES servers (id) \
                    ON DELETE CASCADE \
                    ON UPDATE CASCADE, \
                    FOREIGN KEY (creator_id) REFERENCES players (id) \
                    ON DELETE CASCADE \
                    ON UPDATE CASCADE, \
                    UNIQUE KEY lobby_index (creator_id) \
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
                (6, 350.0), \
                (7, 530.0), \
                (8, 740.0), \
                (9, 940.0), \
                (10, 1200.0);");

    g_hDatabase.Execute(t, _, Thread_Empty_TransactionFail);

    AuthServer();

    return;
}