stock void CreateLobbyServer(Player creator, char[] password = "", char[] lobbyName = "")
{
	if ( creator.currentLobby.exists )
	{
		MC_PrintToChat(creator.clientIndex, "{red}ERROR {white}| You have already created a lobby!");
		return;
	}

	int port = 30001; // = GetFreeLobbyPort();

	char query[255];

	SQL_LockDatabase(g_hDatabase);

	FormatEx(query, sizeof(query), "INSERT INTO lobby (creator_id, server_id, password, lobby_name, port) VALUES(%i, %i, '%s', '%s', %i)", creator.id, g_server.id, password, lobbyName, port);

	if ( !SQL_FastQuery(g_hDatabase, query) )
	{
		MC_PrintToChat(creator.clientIndex, "{red}ERROR {white}| Lobby was not {accent}created{white}! You must close the previous lobby ({accent}/close{white})");

		SQL_UnlockDatabase(g_hDatabase);
		return;
	}

	SQL_UnlockDatabase(g_hDatabase);

	FormatEx(query, sizeof(query), "SELECT id FROM lobby WHERE creator_id = %i", creator.id);
	
	g_hDatabase.Query(Thread_GetLobbyId, query, creator.clientIndex);
}

public void Thread_GetLobbyId(Database db, DBResultSet results, const char[] error, any client)
{
    if ( strlen(error) > 1 ) { LogError(error); return; }

    if ( results.FetchRow() )
    {
		int id = results.FetchInt(0);

		for (int i = 1; i <= MaxClients; i++)
		{
			if ( g_player[i].id == g_player[client].id )
			{
				MC_PrintToChat(i, "Lobby was {accent}Created{white}! ID: %i", id);
				ConnectToLobby(i, id);
			}
		}
	}
}

//When a client sent a message to the server OR the server sent a message to the client :
void OnServerChildSocketReceive(Event event, const char[] name, bool dontBroadcast)
{
	PrintToServer("CALLED CALLBACK IN SOURCEMOD!!");
	char data[1024];
	event.GetString("data", data, sizeof(data));

	if (StrContains(data, "::NewConnection::") != -1)
	{
		ReplaceString(data, sizeof(data), "::NewConnection:: ", "");

		char split[2][256]; // 0 = ip@id  1 = player name
		ExplodeString(data, " ", split, sizeof(split), sizeof(split[]), true);

		if (g_lobby.lobbyConnections.FindString(split[0]) == -1)
			g_lobby.lobbyConnections.PushString(split[0]);

		int lobbyId = GetAndRemoveLobbyId(split[0]);
		FormatEx(data, sizeof(data), "::NotifyConnection:: %i %s %s", lobbyId, split[0], split[1]);
	}
	else if ( StrContains(data, "::DisconnectMe::") != -1 )
	{
		ReplaceString(data, sizeof(data), "::DisconnectMe:: ", "");

		char split[4][256];

		ExplodeString(data, " ", split, sizeof(split), sizeof(split[]), true);
		
		int playerId = StringToInt(split[2]);
		bool mustEraseIp = view_as<bool>(StringToInt(split[1]));

		if ( mustEraseIp )
			if ( g_lobby.lobbyConnections.FindString(split[0]) != -1 ) 
				g_lobby.lobbyConnections.Erase(g_lobby.lobbyConnections.FindString(split[0]));

		int lobbyId = GetAndRemoveLobbyId(split[0]);

		FormatEx(data, sizeof(data), "::NotifyDisconnect:: %i %i %i %s %s", lobbyId, mustEraseIp, playerId, split[0], split[3]);
	}

	if ( g_lobby.lobbyConnections == INVALID_HANDLE ) return;

	for (int i = 0; i < g_lobby.lobbyConnections.Length; i++)
	{
		char buff[2][64];
		char arrData[256];

		g_lobby.lobbyConnections.GetString(i, arrData, sizeof(arrData));

		ExplodeString(data, " ", buff, sizeof(buff), sizeof(buff[]));

		int lobby1 = StringToInt(buff[1]);
		int lobby2 = GetAndRemoveLobbyId(arrData);

		if ( lobby1 == lobby2 )
			g_Socket.SendTo( data, _, arrData, 31001 );
	}

	if ( StrContains(data, "::LobbyClosed::") != -1 )
	{
		ReplaceString(data, sizeof(data), "::LobbyClosed:: ", "");

		char split[2][128];

		ExplodeString(data, " ", split, sizeof(split), sizeof(split[]), true);


		for(int i; i < g_lobby.lobbyConnections.Length; i++)
		{
			char buff[256];
			g_lobby.lobbyConnections.GetString(i, buff, sizeof(buff));

			int lobbyId = GetAndRemoveLobbyId(buff);

			if ( lobbyId == StringToInt(split[0]) )
				g_lobby.lobbyConnections.Erase(i);
		}
	}
}

public void OnServerSocketError(Socket socket, const int errorType, const int errorNum, any index)
{
	PrintToServer("Error host creation: %i: num %i", errorType, errorNum);
}

int GetAndRemoveLobbyId(char str[256])
{
	char buff[2][64];

	ExplodeString(str, "^", buff, sizeof(buff), sizeof(buff[]));

	strcopy(str, sizeof(str), buff[0]);

	return StringToInt(buff[1]);
}

/*int GetFreeLobbyPort()
{
	int port = GetRandomInt(30000, 32000);

	for (int i; i < 10; i++)
	{
		if ( g_lobby[i].port == port )
		{
			port = GetFreeLobbyPort();
		}
	}
	
	return port;
}*/

stock void CloseLobbyServer(int client)
{
	char query[256];

	FormatEx(query, sizeof(query), "SELECT ip, lobby.id FROM lobby JOIN servers ON lobby.server_id = servers.id WHERE creator_id = %i", g_player[client].id);
	g_hDatabase.Query(Thread_CloseLobby, query, client);
}

public void Thread_CloseLobby(Database db, DBResultSet results, const char[] error, any client)
{
	if ( strlen(error) > 1 ) { LogError(error); return; }

	char send[256];

	if ( !results.FetchRow() )
    {
		MC_PrintToChat(client, "{red}ERROR | {white}No active own lobbies to delete.");
		return;
	}

	char buff[2][64];
	char ip[64];
	int lobbyId;

	results.FetchString(0, ip, sizeof(ip));
	lobbyId = results.FetchInt(1);

	ExplodeString(ip, ":", buff, sizeof(buff), sizeof(buff[]));

	ip = buff[0];

	FormatEx(send, sizeof(send), "::LobbyClosed:: %i %s", lobbyId, g_player[client].name);
	g_Socket.SendTo(send, _, ip, 30001);

	SQL_LockDatabase(g_hDatabase);

	char query[128];
	FormatEx(query, sizeof(query), "DELETE FROM lobby WHERE id = %i", lobbyId);
	SQL_FastQuery(g_hDatabase, query);

	SQL_UnlockDatabase(g_hDatabase);

	MC_PrintToChat(client, "{green}[LOBBY] {white}Lobby {accent}#%i {white}has been closed.", lobbyId);
}