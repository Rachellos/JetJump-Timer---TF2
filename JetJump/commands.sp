void RegisterAllJetJumpCommands()
{
    RegisterJetJumpCommand( "sm_nominate", Command_Nominate, "Nominate maps to be on the end of map vote" );
    AddAliasForCommand( "sm_nominate", "sm_nom");

    RegisterJetJumpCommand( "sm_unnominate", Command_UnNominate, "Removes nominations" );
    AddAliasForCommand( "sm_unnominate", "sm_unnom");

    RegisterJetJumpCommand( "sm_rtv", Command_RockTheVote, "Rock The Vote" );

    RegisterJetJumpCommand( "sm_unrtv", Command_UnRockTheVote, "un-Rock The Vote" );

    RegisterJetJumpCommand("sm_ve", Command_VE, "Vote For Extend Map");
    AddAliasForCommand("sm_ve", "sm_voteextend");

    RegisterJetJumpCommand("sm_revote", Command_Revote, "Revote map choise");	

    RegisterJetJumpCommand("sm_restart", Command_Restart, "Spawn to the map start");
    AddAliasForCommand("sm_restart", "sm_r");
    AddAliasForCommand("sm_restart", "sm_reset");
    AddAliasForCommand("sm_restart", "sm_start");

    RegisterJetJumpCommand("sm_timer", Command_TimerSwitch, "Toggle The timer mode");
    AddAliasForCommand("sm_timer", "sm_enabletimer");
    AddAliasForCommand("sm_timer", "sm_disabletimer");

    RegisterJetJumpCommand("sm_setstart", Command_SetStartPosition, "Set start position");
    AddAliasForCommand("sm_setstart", "sm_set");

    RegisterJetJumpCommand("sm_clearstart", Command_ClearStartPosition, "Clear start position");
    AddAliasForCommand("sm_clearstart", "sm_clear");

    RegisterJetJumpCommand("sm_stage", Command_TeleportToStage, "Teleport to Stage (number)");
    AddAliasForCommand("sm_stage", "sm_c");
    AddAliasForCommand("sm_stage", "sm_st");

    RegisterJetJumpCommand("sm_bonus", Command_TeleportToBonus, "Teleport to Bonus (number)");
    AddAliasForCommand("sm_bonus", "sm_b");

    RegisterJetJumpCommand("sm_drawzone", Command_DrawCurrentZone, "Draw the current zone you stay");
    AddAliasForCommand("sm_drawzone", "sm_dz");

    RegisterJetJumpCommand("sm_top", Command_TopTimes, "Show top times of map");
    AddAliasForCommand("sm_top", "sm_toptimes");

    RegisterJetJumpCommand("sm_connect", Command_ConnectToLobby, "Connect to the lobby");
}

void RegisterJetJumpCommand(const char[] command,
                        ConCmd callback,
                        const char[] description,
                        int flag = 0)
{
    int newCommand = GetFreeCommandListIndex();

    g_commands[newCommand].exists = true;

    g_commands[newCommand].isMainCommand = true;
    g_commands[newCommand].callback = callback;
    g_commands[newCommand].AdminFlag = flag;

    strcopy(g_commands[newCommand].commandName, sizeof(Commands::commandName), command);
    strcopy(g_commands[newCommand].description, sizeof(Commands::description), description);

    RegConsoleCmd(command, callback, description, flag);
}

void AddAliasForCommand(const char[] command, const char[] alias)
{
    int mainCommand = FindCommandByName(command);

    if ( mainCommand == -1 ) return;

    int newCommand = GetFreeCommandListIndex();

    g_commands[newCommand] = g_commands[mainCommand];

    strcopy(g_commands[newCommand].commandName, sizeof(Commands::commandName), alias);
    g_commands[newCommand].isMainCommand = false;

    RegConsoleCmd(alias, g_commands[newCommand].callback, g_commands[newCommand].description, g_commands[newCommand].AdminFlag);
}

int FindCommandByName(const char[] name)
{
    for (int i = 0; i < MAX_COMMANDS; i++)
    {
        if ( StrEqual( g_commands[i].commandName, name ) )
            return i
    }

    return -1;
}

int GetFreeCommandListIndex()
{
    for (int i; i < MAX_COMMANDS; i++)
        if ( !g_commands[i].exists )
            return i;
    
    return 0;
}

public Action Command_ConnectToLobby(int client, int args)
{
    if ( !(1 <= client <= MaxClients) ) return Plugin_Handled;

    if ( args > 0 )
    {
        char arg[3];
        GetCmdArg(1, arg, sizeof(arg));

        for (int arg_char; arg_char < strlen(arg); arg_char++)
        {
            if ( !IsCharNumeric(arg[arg_char]) )
            {
                JetJump_PrintToChat(client, "Usage {accent}!connect {white}(number)");
                return Plugin_Handled;
            }
        }

        int num = StringToInt(arg);

        ConnectToLobby(client, num)
    }
    else
    {
        JetJump_PrintToChat(client, "Usage {accent}!connect {white}(number)");
    }

    return Plugin_Handled;
}

public Action Command_Restart(int client, int args)
{
    if ( !(1 <= client <= MaxClients) ) return Plugin_Handled;

    int zoneid = -1;

    g_player[client].currentZone.arrayId = -1;
    g_player[client].state = STATE_INVALID;

    g_run[client].type = RUN_INVALID;
    g_run[client].linearMode = false;

    if ( g_player[client].setStartExists )
    {
        TeleportEntity(client, g_player[client].setStartPos, g_player[client].setStartAng, NULL_VEC);
    }
    else if ( ( zoneid = FindZoneArrayId(RUN_MAP, ZONE_START) ) != -1 )
    {
        TeleportEntity(client, g_zones[zoneid].spawnPos, g_zones[zoneid].spawnAng, NULL_VEC);
    }
    else if ( ( zoneid = FindZoneArrayId(RUN_STAGE, ZONE_START) ) != -1 )
    {
        TeleportEntity(client, g_zones[zoneid].spawnPos, g_zones[zoneid].spawnAng, NULL_VEC);
    }
    else
    {
        JetJump_PrintToChat(client, "{accent}No zones for this map, can not respawn");
        return Plugin_Handled;
    }

    TF2_RegeneratePlayer(client);
    
    return Plugin_Handled;
}

public Action Command_TimerSwitch(int client, int args)
{
    if ( !(1 <= client <= MaxClients) ) return Plugin_Handled;

    g_player[client].isTimerOn = !g_player[client].isTimerOn;

    if ( g_player[client].isTimerOn )
    {
        JetJump_PrintToChat(client, "Timer {accent}Enabled");
        FakeClientCommand(client, "sm_restart");
    }
    else
    {
        JetJump_PrintToChat(client, "Timer {red}Disabled");
    }

    return Plugin_Handled;
}

public Action Command_SetStartPosition(int client, int args)
{
    if ( !(1 <= client <= MaxClients) ) return Plugin_Handled;

    GetClientAbsOrigin(client, g_player[client].setStartPos);
    GetClientEyeAngles(client, g_player[client].setStartAng);

    g_player[client].setStartExists = true;

    JetJump_PrintToChat(client, "Start positions has been {maincolor}Created{white}!\nType {accent}!clearstart {white} to return default Start position!");

    return Plugin_Handled;
}

public Action Command_ClearStartPosition(int client, int args)
{
    if ( !(1 <= client <= MaxClients) ) return Plugin_Handled;

    g_player[client].setStartPos = NULL_VEC;
    g_player[client].setStartAng = NULL_VEC;

    g_player[client].setStartExists = false;

    JetJump_PrintToChat(client, "Start positions has been {maincolor}Cleared{white}!");

    return Plugin_Handled;
}

public Action Command_TeleportToStage(int client, int args)
{
    if ( !(1 <= client <= MaxClients) ) return Plugin_Handled;
    if ( !IsPlayerAlive(client) ) return Plugin_Handled;

    int avaliableStages;

    if ( args > 0 )
    {
        char arg[3];
        GetCmdArg(1, arg, sizeof(arg));

        for (int arg_char; arg_char < strlen(arg); arg_char++)
        {
            if ( !IsCharNumeric(arg[arg_char]) )
            {
                JetJump_PrintToChat(client, "Usage {accent}!stage {white}(number)");
                return Plugin_Handled;
            }
        }

        int num = StringToInt(arg);

        for (int i; i < ZONES_LIMIT; i++)
        {
            if ( g_zones[i].runType == RUN_STAGE
                && g_zones[i].zoneType == ZONE_START
                && g_zones[i].runInfo.index == num
                && g_zones[i].zoneIndex == 0
                && g_zones[i].exists )
            {
                g_run[client].linearMode = false;
                TeleportEntity(client, g_zones[i].spawnPos, g_zones[i].spawnAng, NULL_VEC);
                return Plugin_Handled;
            }
        }

        for (int i; i < ZONES_LIMIT; i++)
        {
            if ( g_zones[i].runType == RUN_STAGE
                && g_zones[i].zoneType == ZONE_START
                && g_zones[i].zoneIndex == 0
                && g_zones[i].exists )
            {
                avaliableStages++
            }
        }

        if (avaliableStages > 0)
            JetJump_PrintToChat(client, "This map have only {accent}%i {white}stages.", avaliableStages);
        else
            JetJump_PrintToChat(client, "No {red}stages {white}found on this map.");
        
        return Plugin_Handled;
    }

    char strBonusArrayId[10];
    Menu menu = new Menu(MenuHander_TeleportToRunMenu);
    
    for (int i; i < ZONES_LIMIT; i++)
    {
        if ( g_zones[i].runType == RUN_STAGE
            && g_zones[i].zoneType == ZONE_START
            && g_zones[i].zoneIndex == 0
            && g_zones[i].exists )
        {
            IntToString(g_zones[i].arrayId, strBonusArrayId, sizeof(strBonusArrayId));
            menu.AddItem(strBonusArrayId, g_zones[i].runInfo.runName)
            avaliableStages++
        }
    }

    if (avaliableStages == 0)
    {
        JetJump_PrintToChat(client, "No {red}stages {white}found on this map.");
        return Plugin_Handled;
    }
    
    menu.SetTitle("Avaliable Stages (%i):\n \n", avaliableStages);
    menu.Display(client, MENU_TIME_FOREVER);

    return Plugin_Handled;
}

public Action Command_TeleportToBonus(int client, int args)
{
    if ( !(1 <= client <= MaxClients) ) return Plugin_Handled;
    if ( !IsPlayerAlive(client) ) return Plugin_Handled;

    int avaliableBonuses;

    if ( args > 0 )
    {
        char arg[3];
        GetCmdArg(1, arg, sizeof(arg));

        for (int arg_char; arg_char < strlen(arg); arg_char++)
        {
            if ( !IsCharNumeric(arg[arg_char]) )
            {
                JetJump_PrintToChat(client, "Usage {accent}!bonus {white}(number)");
                return Plugin_Handled;
            }
        }

        int num = StringToInt(arg);

        for (int i; i < ZONES_LIMIT; i++)
        {
            if ( g_zones[i].runType == RUN_BONUS
                && g_zones[i].zoneType == ZONE_START
                && g_zones[i].runInfo.index == num
                && g_zones[i].zoneIndex == 0
                && g_zones[i].exists )
            {
                TeleportEntity(client, g_zones[i].spawnPos, g_zones[i].spawnAng, NULL_VEC);
                return Plugin_Handled;
            }
        }

        for (int i; i < ZONES_LIMIT; i++)
        {
            if ( g_zones[i].runType == RUN_BONUS
                && g_zones[i].zoneType == ZONE_START
                && g_zones[i].zoneIndex == 0
                && g_zones[i].exists )
            {
                avaliableBonuses++
            }
        }

        if (avaliableBonuses > 0)
            JetJump_PrintToChat(client, "This map have only {accent}%i {white}bonuses.", avaliableBonuses);
        else
            JetJump_PrintToChat(client, "No {red}bonuses {white}found on this map.");
        
        return Plugin_Handled;
    }

    char strBonusArrayId[10];
    Menu menu = new Menu(MenuHander_TeleportToRunMenu);
    
    for (int i; i < ZONES_LIMIT; i++)
    {
        if ( g_zones[i].runType == RUN_BONUS
            && g_zones[i].zoneType == ZONE_START
            && g_zones[i].zoneIndex == 0
            && g_zones[i].exists )
        {
            IntToString(g_zones[i].arrayId, strBonusArrayId, sizeof(strBonusArrayId));
            menu.AddItem(strBonusArrayId, g_zones[i].runInfo.runName)
            avaliableBonuses++
        }
    }

    if (avaliableBonuses == 0)
    {
        JetJump_PrintToChat(client, "No {red}bonuses {white}found on this map.");
        return Plugin_Handled;
    }
    
    menu.SetTitle("Avaliable Bonuses (%i):\n \n", avaliableBonuses);
    menu.Display(client, MENU_TIME_FOREVER);

    return Plugin_Handled;
}

int MenuHander_TeleportToRunMenu(Menu menu, MenuAction action, int client, int item)
{
    if ( action == MenuAction_Select )
    {
        char strBonusArrayId[10];

        menu.GetItem(item, strBonusArrayId, sizeof(strBonusArrayId));

        for (int i; i < ZONES_LIMIT; i++)
        {
            if ( g_zones[i].arrayId == StringToInt(strBonusArrayId) )
            {
                if ( g_zones[i].runType == RUN_STAGE )
                    g_run[client].linearMode = false;

                TeleportEntity(client, g_zones[i].spawnPos, g_zones[i].spawnAng, NULL_VEC);
                break;
            }
        }
        menu.DisplayAt(client, menu.Selection, MENU_TIME_FOREVER);
    }
    return 0;
}

public Action Command_DrawCurrentZone(int client, int args)
{
    if ( !(1 <= client <= MaxClients) ) return Plugin_Handled;
    if ( !IsPlayerAlive(client) ) return Plugin_Handled;

    DrawZone(client, g_player[client].currentZone);

    CreateLobbyServer(g_player[client]);

    return Plugin_Handled;
}

public Action Command_TopTimes(int client, int args)
{
    if ( !(1 <= client <= MaxClients) ) return Plugin_Handled;

    CloseLobbyServer(g_player[client].currentLobby);
    char query[255];

    char szTarget[32];
    char displayName[100];

    GetCmdArg(1, szTarget, sizeof( szTarget ) );

    if ( args )
    {
        if ( !GetMapDisplayName(szTarget, displayName, sizeof(displayName)) )
        {
            JetJump_PrintToChat(client, "Map not found");
            return Plugin_Handled;
        }
        else
        {
            FormatEx(query, sizeof(query), "SELECT name, map_id, run_type, run_id FROM map_info JOIN map_list ON id = map_id WHERE name = '%s' ORDER BY run_type, run_id ASC", displayName);
        }
	}
    else
    {
        FormatEx(query, sizeof(query), "SELECT name, map_id, run_type, run_id FROM map_info JOIN map_list ON id = map_id WHERE name = '%s' ORDER BY run_type, run_id ASC", g_currentMap.name);
    }

    DrawLoadingMenu(client);

    g_hDatabase.Query(Thread_TopTimes_TypeChoise, query, client);

    return Plugin_Handled;
}

void Thread_TopTimes_TypeChoise(Database db, DBResultSet results, const char[] error, any client)
{
    if ( strlen(error) > 1 )
    {
        LogError(error);
        return;
    }

    if (!results.RowCount)
    {
        JetJump_PrintToChat(client, "Map not found");
        return;
    }

    Menu menu = new Menu(TopTimes_TypeChoise_MenuHandler);

    int prevRunType;

    int map_id, runType, runId;

    char itemInfo[32], itemName[32];

    char mapName[64];
    char runName[][] = {"Map", "Stage", "Bonus"}; 

    while (results.FetchRow())
    {
        results.FetchString(0, mapName, sizeof(mapName));

        map_id = results.FetchInt(1);

        runType = results.FetchInt(2);
        runId = results.FetchInt(3);

        FormatEx(itemInfo, sizeof(itemInfo), "%i/%i/%i", map_id, runType, runId);

        if ( runType > 0 )
            FormatEx(itemName, sizeof(itemName), "%s %i", runName[runType], runId);
        else
            FormatEx(itemName, sizeof(itemName), "Map Run");

        if ( prevRunType != runType )
            menu.AddItem( "", "\n", ITEMDRAW_RAWLINE );

        prevRunType = runType;
        
        menu.AddItem(itemInfo, itemName);
    }

    menu.SetTitle("Select Run Zone\nMap: %s\n \n", mapName);
    menu.Display(client, MENU_TIME_FOREVER);

    g_player[client].SetNewPrevMenu(menu);
}

int TopTimes_TypeChoise_MenuHandler(Menu menu, MenuAction action, int client, int item)
{
    if ( action == MenuAction_End ) { return 0; }

    if ( action == MenuAction_Select )
    {
        char itemData[3][10];
        char strItemData[32];

        menu.GetItem(item, strItemData, sizeof(strItemData));

        ExplodeString( strItemData, "/", itemData, sizeof( itemData ), sizeof( itemData[] ) );

        int map_id = StringToInt(itemData[0]);
        int run_type = StringToInt(itemData[1]);
        int run_id = StringToInt(itemData[2]);
        
        g_player[client].SetNewPrevMenu(menu);

        DrawTopTimes(client, map_id, run_type, run_id, g_player[client].currentClass != CLASS_INVALID ? g_player[client].currentClass : CLASS_SOLDIER);
    }

    return 0;
}

void DrawTopTimes(int client, int map_id, int run_type, int run_id, Class class)
{
    DrawLoadingMenu(client);

    char query[1024];

    Transaction t = new Transaction();

    FormatEx(query, sizeof(query), "SELECT id, name, %i, %i, %i FROM map_list \
                                    WHERE id = %i;", run_type, run_id, class, map_id);

    t.AddQuery(query);

    FormatEx(query, sizeof(query), "SELECT record_id, players.name, time, points FROM records \
                                    JOIN players ON players.id = records.player_id \
                                    WHERE map_id = %i AND run_type = %i AND run_id = %i AND class = %i ORDER BY time LIMIT 100;", map_id, run_type, run_id, class);

    t.AddQuery(query);
    
    g_hDatabase.Execute(t, Thread_DrawTopTimes, _, client);
}


public void Thread_DrawTopTimes (Database db, any client, int numQueries, DBResultSet[] results, any[] queryData)
{

    Menu menu = new Menu(DrawTopTimes_MenuHandler);

    int mapId, runId;

    RunType runType;

    int rank, itemNum;

    float time, worldRecordTime;

    char strTimeFormated[TIME_SIZE_DEF];
    char strTimeComparisonFormated[TIME_SIZE_DEF];

    Class class;

    char strRecordId[10], itemName[64], playerName[32];

    char controlItemInfo[32];

    char mapName[64];
    char runName[][] = {"Map", "Stage", "Bonus"}; 

    if ( results[0].FetchRow() )
    {
        mapId = results[0].FetchInt(0);
        results[0].FetchString(1, mapName, sizeof(mapName));
        runType = view_as<RunType>(results[0].FetchInt(2));
        runId = results[0].FetchInt(3);
        class = view_as<Class>(results[0].FetchInt(4));

        FormatEx(controlItemInfo, sizeof(controlItemInfo), "%i/%i/%i/%i", mapId, runType, runId, class);
    }

    if ( results[1].RowCount )
    {
        while (results[1].FetchRow())
        {
            itemNum++;

            if ( itemNum == 7)
            {
                if ( class == CLASS_SOLDIER )
                    menu.AddItem(controlItemInfo, "[*SOLDIER*]");
                else if ( class == CLASS_DEMOMAN )
                    menu.AddItem(controlItemInfo, "[*DEMOMAN*]");
                
                itemNum = 0;
            }
            else
            {
                rank++

                IntToString(results[1].FetchInt(0), strRecordId, sizeof(strRecordId));
                results[1].FetchString(1, playerName, sizeof(playerName));

                time = results[1].FetchFloat(2);

                if ( rank == 1 )
                    worldRecordTime = time;

                FormatSeconds(time, strTimeFormated, sizeof(strTimeFormated));
                FormatSeconds(time - worldRecordTime, strTimeComparisonFormated, sizeof(strTimeComparisonFormated));
                FormatEx(itemName, sizeof(itemName), "[#%i] %s +%s | %s%s", rank, strTimeFormated, strTimeComparisonFormated, playerName, itemNum == 6 ? "\n " : "");

                menu.AddItem(strRecordId, itemName, ITEMDRAW_DISABLED);
            }
        }
    }
    else
    {
        itemNum = 1;
        menu.AddItem("", "[No Records Found]", ITEMDRAW_DISABLED)
    }

    if ( 0 < itemNum < 7 )
    {
        for (int i = itemNum; i < 6; i++)
        {
            menu.AddItem("", "", ITEMDRAW_SPACER);
        }

        if ( class == CLASS_SOLDIER )
            menu.AddItem(controlItemInfo, "[*SOLDIER*]");
        else if ( class == CLASS_DEMOMAN )
            menu.AddItem(controlItemInfo, "[*DEMOMAN*]");
    }
    
    if ( runType == RUN_MAP )
        menu.SetTitle("Top Times | Map Run\nMap: %s\n \n", mapName);
    else
        menu.SetTitle("Top Times | %s %i\nMap: %s\n \n", runName[runType], runId, mapName);

    if ( g_player[client].GetLastPrevMenuIndex() != -1 )
        menu.ExitBackButton = true;

    menu.Display(client, MENU_TIME_FOREVER);
}

int DrawTopTimes_MenuHandler(Menu menu, MenuAction action, int client, int item)
{
    if ( action == MenuAction_End ) { return 0; }
    if ( action == MenuAction_Cancel && item == MenuCancel_ExitBack )
    {
        g_player[client].CallPrevMenu();
        return 0;
    }

    if ( action == MenuAction_Select )
    {
        char itemData[4][10];
        char strItemData[32];

        menu.GetItem(item, strItemData, sizeof(strItemData));

        if ( item == 6 )
        {
            ExplodeString( strItemData, "/", itemData, sizeof( itemData ), sizeof( itemData[] ) );

            int map_id = StringToInt(itemData[0]);
            int run_type = StringToInt(itemData[1]);
            int run_id = StringToInt(itemData[2]);
            Class class = view_as<Class>(StringToInt(itemData[3]));

            DrawTopTimes(client, map_id, run_type, run_id, class == CLASS_SOLDIER ? CLASS_DEMOMAN : CLASS_SOLDIER);
        }
    }

    return 0;
}

void DrawLoadingMenu(int client)
{
    Panel hPanel = new Panel();
    hPanel.DrawText( "Loading..." );
    
    hPanel.Send( client, Empty_MenuHandle, 20 );
}

int Empty_MenuHandle(Menu menu, MenuAction action, int client, int item)
{
    return 0;
}