void SendToClients(client, const char[] data = "Empty", bool onlyOtherServers = false)
{
	if (!client) return;

	if (g_Socket == INVALID_HANDLE) return;

	if (!g_player[client].currentLobby.exists) return;

	char ip[64];

	for (int i; i < g_player[client].currentLobby.lobbyConnections.Length; i++)
	{
		g_player[client].currentLobby.lobbyConnections.GetString(i, ip, sizeof(ip));

		if (onlyOtherServers)
			if (StrEqual(ip, g_server.ip))
				continue;

		g_Socket.SendTo(data, _, ip, 31001);
	}
}

void ConnectToLobby(int client, int lobby_id, const char[] password = "")
{
	char query[256];
	Transaction t = new Transaction();

	FormatEx(query, sizeof(query), "SELECT ip, password, lobby.id, servers.id, creator_id FROM lobby JOIN servers ON servers.id = lobby.server_id WHERE lobby.id = %i", lobby_id);
	t.AddQuery(query);

	FormatEx(query, sizeof(query), "SELECT ip, password, lobby.id, servers.id, creator_id FROM lobby JOIN servers ON servers.id = lobby.server_id WHERE lobby.id = %i", lobby_id);
	t.AddQuery(query);
	g_hDatabase.Query(Thread_ConnectToLobby, query, client);
}

void DisconnectLobby(int client)
{
	if ( !g_player[client].currentLobby.exists )
	{
		MC_PrintToChat(client, "{red}ERROR | {white}You are not in any {accent}lobby{white}, can not disconnect.");
		return;
	}

	char send[256];
	bool mustErase = true;

	for (int i = 1; i <= MaxClients; i++)
		if ( i != client && g_player[i].currentLobby.id == g_player[client].currentLobby.id )
			mustErase = false;

	PrintToChatAll("%s", (mustErase) ? "true" : "false");

	FormatEx(send, sizeof(send), "::DisconnectMe:: %s^%i %i %i %s", g_server.ip, g_player[client].currentLobby.id, mustErase,g_player[client].id, g_player[client].name);
	g_Socket.SendTo(send, _, g_player[client].currentLobby.serverHost_ip, 30001);

	char query[256];
	FormatEx(query, sizeof(query), "UPDATE players SET current_lobby = NULL WHERE id = %i", g_player[client].id);
	g_hDatabase.Query(Thread_Empty, query, client);
}

public void Thread_ConnectToLobby(Database db, DBResultSet results, const char[] error, any client)
{
	if ( strlen(error) > 1 ) { LogError(error); return; }

	char send[256];

	if ( results.FetchRow() )
    {
		if ( g_player[client].currentLobby.exists )
		{
			DisconnectLobby(client);
		}

		char ipBuff[64], ip[2][64], password[256];

		results.FetchString(0, ipBuff, sizeof(ipBuff));
		ExplodeString( ipBuff, ":", ip, sizeof( ip ), sizeof( ip[] ) );

		results.FetchString(1, password, sizeof(password));

		g_player[client].currentLobby.id = results.FetchInt(2);

		g_player[client].currentLobby.serverHost_id = results.FetchInt(3);

		g_player[client].currentLobby.creator_id = results.FetchInt(4);

		g_player[client].currentLobby.lobbyConnections = new ArrayList(ByteCountToCells(128));
		
		FormatEx(g_player[client].currentLobby.serverHost_ip, sizeof(Lobby::serverHost_ip), ip[0]);

		JetJump_PrintToChat(client, "Connecting to {accent}Lobby... %s", g_player[client].currentLobby.serverHost_ip);

		FormatEx(send, sizeof(send), "::NewConnection:: %s^%i %s", g_server.ip, g_player[client].currentLobby.id, g_player[client].name);
		g_Socket.SendTo(send, _, g_player[client].currentLobby.serverHost_ip, 30001);
		
		CreateTimer(5.0, Timer_TimeOutConnectionLobby, client);
	}
	else
	{
		MC_PrintToChat(client, "{red}ERROR | {white}This {accent}Lobby{white} not exists.");
	}
}

Action Timer_TimeOutConnectionLobby(Handle timer, int client)
{
	if (!g_player[client].currentLobby.exists)
	{
		MC_PrintToChat(client, "{red}ERROR | {white}Some Сonnection Error. Try again.");

		char query[256];
		FormatEx(query, sizeof(query), "UPDATE players SET current_lobby = NULL WHERE id = %i", g_player[client].id);
		g_hDatabase.Query(Thread_Empty, query, client);

		Lobby empty;
		g_player[client].currentLobby = empty;
	}

	return Plugin_Handled;
}

//When a client sent a message to the MCS OR the MCS sent a message to the client, and the MCS have to handle it :
void OnServerSocketReceive(Event event, const char[] name, bool dontBroadcast)
{
	char text[MC_MAX_MESSAGE_LENGTH];

	event.GetString("data", text, sizeof(text));

	if ( StrContains(text, "::NotifyConnection::") != -1 )
	{
		ReplaceString(text, sizeof(text), "::NotifyConnection:: ", "");

		char data[3][MC_MAX_MESSAGE_LENGTH];
		int lobbyId;

		ExplodeString(text, " ", data, sizeof(data), sizeof(data[]), true);
		
		lobbyId = StringToInt(data[0]);

		for (int i = 1; i <= MaxClients; i++)
		{
			if ( IsClientInGame(i) && g_player[i].currentLobby.id == lobbyId )
			{
				if ( g_player[i].currentLobby.lobbyConnections.FindString(data[1]) == -1 ) 
					g_player[i].currentLobby.lobbyConnections.PushString(data[1]);

				if ( !g_player[i].currentLobby.exists )
				{
					char query[256];

					FormatEx(query, sizeof(query), "UPDATE players SET current_lobby = %i WHERE id = %i", lobbyId, g_player[i].id);
					g_hDatabase.Query(Thread_Empty, query, i);
					g_player[i].currentLobby.exists = true;

					MC_PrintToChat(i, "{green}[LOBBY] {white}Connection {accent}Established");
				}

				MC_PrintToChat(i, "{green}[LOBBY] {maincolor}%s {white}just join the lobby!", data[2]);
			}
		}
	}
	else if ( StrContains(text, "::NotifyDisconnect::") != -1 )
	{
		ReplaceString(text, sizeof(text), "::NotifyDisconnect:: ", "");

		char data[5][MC_MAX_MESSAGE_LENGTH];

		ExplodeString(text, " ", data, sizeof(data), sizeof(data[]), true);
		
		int lobbyId = StringToInt(data[0]);
		bool mustEraseIp = view_as<bool>(StringToInt(data[1]));

		int playerId = StringToInt(data[2]);

		for (int i = 1; i <= MaxClients; i++)
		{
			if ( IsClientInGame(i) && g_player[i].currentLobby.id == lobbyId )
			{
				MC_PrintToChat(i, "{green}[LOBBY] {maincolor}%s {white}has leave the lobby", data[4]);

				if ( g_player[i].id == playerId )
				{
					MC_PrintToChat(i, "{green}[LOBBY] {white}Disconnected from {accent}Lobby #%i", g_player[i].currentLobby.id);
					
					Lobby empty;
					g_player[i].currentLobby = empty;

					continue;
				}

				if ( mustEraseIp )
					if ( g_player[i].currentLobby.lobbyConnections.FindString(data[3]) != -1 ) 
						g_player[i].currentLobby.lobbyConnections.Erase(g_player[i].currentLobby.lobbyConnections.FindString(data[3]));
			}
		}
	}
	else if ( StrContains(text, "::LobbyClosed::") != -1 )
	{
		ReplaceString(text, sizeof(text), "::LobbyClosed:: ", "");

		char data[2][MC_MAX_MESSAGE_LENGTH];

		ExplodeString(text, " ", data, sizeof(data), sizeof(data[]), true);
		
		int lobbyId = StringToInt(data[0]);

		for (int i = 1; i <= MaxClients; i++)
		{
			if ( IsClientInGame(i) && g_player[i].currentLobby.id == lobbyId )
			{
				MC_PrintToChat(i, "{green}[LOBBY] Lobby Has Been Closed By {maincolor}%s. Disconnected!", data[1]);

				char query[256];
				FormatEx(query, sizeof(query), "UPDATE players SET current_lobby = NULL WHERE id = %i", g_player[i].id);
				g_hDatabase.Query(Thread_Empty, query, i);

				Lobby empty;
				g_player[i].currentLobby = empty;
			}
		}
	}
	else if ( StrContains(text, "::Lobby-Msg::") != -1 )
	{
		ReplaceString(text, sizeof(text), "::Lobby-Msg:: ", "");

		char msg[2][MC_MAX_MESSAGE_LENGTH];
		ExplodeString(text, " ", msg, sizeof(msg), sizeof(msg[]), true);

		int lobbyId = StringToInt(msg[0]);

		for (int i = 1; i <= MaxClients; i++)
		{
			if ( IsClientInGame(i) && g_player[i].currentLobby.id == lobbyId )
			{
				MC_PrintToChat(i, msg[1]);
			}
		}
	}
	else if ( StrContains(text, "::Movement-Data::") != -1 )
	{
		ReplaceString(text, sizeof(text), "::Movement-Data:: ", "")

		static int laser;

		laser = PrecacheModel("sprites/laserbeam.vmt")

		char data[4][MC_MAX_MESSAGE_LENGTH];
		ExplodeString(text, " ", data, sizeof(data), sizeof(data[]));

		int lobbyId = StringToInt(data[0]);

		float startPosition[3], endPosition[3];

		for (int cur = 0; cur < 3; cur++)
			startPosition[cur] = StringToFloat(data[cur+1]);

		endPosition = startPosition;
		endPosition[2] += 100;

		for (int i = 1; i <= MaxClients; i++)
		{
			if ( IsClientInGame(i) && g_player[i].currentLobby.id == lobbyId )
			{
				TE_SetupBeamPoints(startPosition, endPosition, laser, 0, 0, 0, 0.15, 32.0, 32.0, 0, 0.0, {255, 215, 0, 255}, 0);
				TE_SendToClient(i);
			}
		}
	}
	else if ( StrContains(text, "::Normal-IRC-Msg::") != -1 )
	{
		ReplaceString(text, sizeof(text), "::Normal-IRC-Msg:: ", "")
		MC_PrintToChatAll(text);
	}
}

float delay;

stock bool IsDelayed()
{
	if ( delay > GetEngineTime() )
	{
		return true;
	}

	delay = GetEngineTime() + 0.1;

	return false;
}

public void OnGameFrame()
{
	if ( IsDelayed() ) return;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_player[i].currentLobby.exists && IsClientInGame(i) && IsPlayerAlive(i))
		{
			float pos[3];
			GetClientAbsOrigin(i, pos);

			char szPos[128];
			FormatEx(szPos, sizeof(szPos), "::Movement-Data:: %i %.2f %.2f %.2f", g_player[i].currentLobby.id, pos[0], pos[1], pos[2]);

			SendToClients(i, szPos);
		}
	}
}