void RegisterAllGigaCommands()
{
    RegisterGigaCommand("sm_restart", Command_Restart, "Spawn to the map start");
    AddAliasForCommand("sm_restart", "sm_r");
    AddAliasForCommand("sm_restart", "sm_reset");
    AddAliasForCommand("sm_restart", "sm_start");

    RegisterGigaCommand("sm_timer", Command_TimerSwitch, "Toggle The timer mode");
    AddAliasForCommand("sm_timer", "sm_enabletimer");
    AddAliasForCommand("sm_timer", "sm_disabletimer");

    RegisterGigaCommand("sm_setstart", Command_SetStartPosition, "Set start position");
    AddAliasForCommand("sm_setstart", "sm_set");

    RegisterGigaCommand("sm_clearstart", Command_ClearStartPosition, "Clear start position");
    AddAliasForCommand("sm_clearstart", "sm_clear");
}

void RegisterGigaCommand(const char[] command,
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
        MC_PrintToChat(client, "No zones for this map, can not respawn");
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
        MC_PrintToChat(client, "Timer {green}Enabled");
        FakeClientCommand(client, "sm_restart");
    }
    else
    {
        MC_PrintToChat(client, "Timer {red}Disabled");
    }

    return Plugin_Handled;
}

public Action Command_SetStartPosition(int client, int args)
{
    if ( !(1 <= client <= MaxClients) ) return Plugin_Handled;

    GetClientAbsOrigin(client, g_player[client].setStartPos);
    GetClientEyeAngles(client, g_player[client].setStartAng);

    g_player[client].setStartExists = true;

    MC_PrintToChat(client, "Start positions has been {gold}Created{white}!\nType {cyan}!clearstart {white} to return default Start position!");

    return Plugin_Handled;
}

public Action Command_ClearStartPosition(int client, int args)
{
    if ( !(1 <= client <= MaxClients) ) return Plugin_Handled;

    g_player[client].setStartPos = NULL_VEC;
    g_player[client].setStartAng = NULL_VEC;

    g_player[client].setStartExists = false;

    MC_PrintToChat(client, "Start positions has been {gold}Cleared{white}!");

    return Plugin_Handled;
}