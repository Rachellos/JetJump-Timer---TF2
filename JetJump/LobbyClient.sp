void ConnectToLobby(int client, int lobby_id, const char[] password = "")
{
	char query[256];

	FormatEx(query, sizeof(query), "SELECT ip, port, password, lobby.id FROM lobby JOIN servers ON servers.id = lobby.server_id WHERE lobby.id = %i", lobby_id);
	g_hDatabase.Query(Thread_ConnectToLobby, query, client);
}

public void Thread_ConnectToLobby(Database db, DBResultSet results, const char[] error, any client)
{
    if ( strlen(error) > 1 ) { LogError(error); return; }

    if ( results.FetchRow() )
    {
		if ( g_player[client].currentLobby.serverSocket && g_player[client].currentLobby.serverSocket.Connected )
		{
			char lobbyMsg[MC_MAX_MESSAGE_LENGTH];
			FormatEx(lobbyMsg, sizeof(lobbyMsg), "::Lobby-Msg:: %i {green}[LOBBY] {maincolor}%s {white}has left the lobby!{endmsg}", g_player[client].id, g_player[client].name);

			g_player[client].currentLobby.serverSocket.Send(lobbyMsg);
			g_player[client].currentLobby.serverSocket.Disconnect();
			g_player[client].currentLobby.exists = false;
		}

		char ipBuff[64], ip[2][64], password[256];
		int port;

		results.FetchString(0, ipBuff, sizeof(ipBuff));
		ExplodeString( ipBuff, ":", ip, sizeof( ip ), sizeof( ip[] ) );

		port = results.FetchInt(1);

		results.FetchString(2, password, sizeof(password));

		g_player[client].currentLobby.id = results.FetchInt(3);

		g_player[client].currentLobby.ip = ip[0];
		g_player[client].currentLobby.port = port;

		JetJump_PrintToChat(client, "Connecting to {accent}Lobby...");
		char send[128];

		Event OnClientSockCreate = CreateEvent("jetjump_client_socket_created", true);
		OnClientSockCreate.SetInt("port", port);

		OnClientSockCreate.Fire();

		FormatEx(send, sizeof(send), "::NewConnection:: %s", g_player[client].name);
		g_Socket.SendTo(send, _, ip[0], port);
	}
	else
	{
		MC_PrintToChat(client, "{red}ERROR | {white}Can not get info about this {accent}Lobby{white}. Try again");
	}
}

public void OnServerSocketConnected(Socket socketServer, any client)
{
	JetJump_PrintToChat(client, "Connected to {accent}Lobby!");

	g_player[client].currentLobby.serverSocket = socketServer;
	g_player[client].currentLobby.exists = true;

	char lobbyMsg[MC_MAX_MESSAGE_LENGTH];
	FormatEx(lobbyMsg, sizeof(lobbyMsg), "::Lobby-Msg:: %i {green}[LOBBY] {maincolor}%s {white}joined the lobby!{endmsg}", g_player[client].id, g_player[client].name);

	socketServer.Send(lobbyMsg);
}

public void OnSocketDisconnected(Socket socket, any hFile)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if ( g_player[i].currentLobby.serverSocket == socket )
		{
			if (g_player[i].currentLobby.serverSocket.Connected)
				g_player[i].currentLobby.serverSocket.Disconnect();
			
			Lobby emptyLobby;

			g_player[i].currentLobby = emptyLobby;

			JetJump_PrintToChat(i, "Disconnected from lobby (host have been disconnected)")
		}
	}

	PrintToChatAll("Disconnected from host");
}

//When a client sent a message to the MCS OR the MCS sent a message to the client, and the MCS have to handle it :
public void OnServerSocketReceive(Event event, const char[] name, bool dontBroadcast)
{
	char text[MC_MAX_MESSAGE_LENGTH];

	event.GetString("data", text, sizeof(text));

	if ( StrContains(text, "::NotifyConnection::") != -1 )
	{
		ReplaceString(text, sizeof(text), "::NotifyConnection:: ", "");

		for (int i = 1; i <= MaxClients; i++)
		{
			if ( IsClientInGame(i) )
			{
				MC_PrintToChat(i, "{green}[LOBBY] {maincolor}%s {white}just join the lobby!");
			}
		}
	}

	if ( StrContains(text, "::Lobby-Msg::") != -1 )
	{
		ReplaceString(text, sizeof(text), "::Lobby-Msg:: ", "");

		char msg[2][MC_MAX_MESSAGE_LENGTH];
		ExplodeString(text, " ", msg, sizeof(msg), sizeof(msg[]), true);

		int playerId = StringToInt(msg[0]);

		// so if message sender on the same server we are, then dont print his message
		for (int i = 1; i <= MaxClients; i++)
			if ( g_player[i].id == playerId )
				return;

		for (int i = 1; i <= MaxClients; i++)
		{
			if ( IsClientInGame(i) )
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

		int playerId = StringToInt(data[0]);
		float startPosition[3], endPosition[3];

		for (int cur = 1; cur < 4; cur++)
			startPosition[cur-1] = StringToFloat(data[cur]);

		endPosition = startPosition;
		endPosition[2] += 100;

		TE_SetupBeamPoints(startPosition, endPosition, laser, 0, 0, 0, 0.25, 32.0, 32.0, 0, 0.0, {255, 215, 0, 255}, 0);

		for (int i = 1; i <= MaxClients; i++)
			if ( IsClientInGame(i) )
				TE_SendToClient(i);
	}
	else if ( StrContains(text, "::Normal-IRC-Msg::") != -1 )
	{
		ReplaceString(text, sizeof(text), "::Normal-IRC-Msg:: ", "")
		MC_PrintToChatAll(text);
	}
}

float delay;

stock bool IsSpamming()
{
	if ( delay > GetEngineTime() )
	{
		return true;
	}

	delay = GetEngineTime() + 0.2;

	return false;
}

public void OnGameFrame()
{
	if ( IsSpamming() ) return;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_player[i].currentLobby.exists && IsClientInGame(i) && IsPlayerAlive(i))
		{
			float pos[3];
			GetClientAbsOrigin(i, pos);

			char szPos[128];
			FormatEx(szPos, sizeof(szPos), "::Movement-Data:: %i %.2f %.2f %.2f{endmsg}", g_player[i].id, pos[0], pos[1], pos[2]);

			if ( g_player[i].currentLobby.serverSocket != INVALID_HANDLE )
			{
				g_player[i].currentLobby.serverSocket.Send(szPos);
			}
		}
	}
}