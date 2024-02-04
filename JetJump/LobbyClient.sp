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
			g_player[client].currentLobby.serverSocket.Disconnect();
			g_player[client].currentLobby.exists = false;
		}

		char ipBuff[64], ip[2][32], password[256];
		int port;

		results.FetchString(0, ipBuff, sizeof(ipBuff));
		ExplodeString( ipBuff, ":", ip, sizeof( ip ), sizeof( ip[] ) );

		port = results.FetchInt(1);

		results.FetchString(2, password, sizeof(password));

		g_player[client].currentLobby.serverSocket = new Socket(_, OnServerSocketError);

		g_player[client].currentLobby.id = results.FetchInt(3);

		JetJump_PrintToChat(client, "Connecting to {accent}Lobby...");
		g_player[client].currentLobby.serverSocket.SetArg(client);
		g_player[client].currentLobby.serverSocket.Connect(OnServerSocketConnected, OnServerSocketReceive, OnSocketDisconnected, ip[0], port);
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
public void OnServerSocketReceive(Socket socket, char[] receiveData, const int dataSize, any pack)
{
	static int laser;
	laser = PrecacheModel("sprites/laserbeam.vmt")

	char pos[3][30];
	float startPosition[3], endPosition[3];

	ExplodeString(receiveData, " ", pos, sizeof(pos), sizeof(pos[]));

	for (int cur; cur < 3; cur++)
		startPosition[cur] = StringToFloat(pos[cur]);

	endPosition = startPosition;
	endPosition[2] += 100;

	TE_SetupBeamPoints(startPosition, endPosition, laser, 0, 0, 0, 0.1, 2.0, 2.0, 0, 0.0, {255, 215, 0, 255}, 0);

	for (int i = 1; i <= MaxClients; i++)
		if ( g_player[i].ServerSocket == socket && IsClientInGame(i))
			TE_SendToClient(i);
}

public void OnGameFrame()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_player[i].currentLobby.exists && IsClientInGame(i) && IsPlayerAlive(i))
		{
			float pos[3];
			GetClientAbsOrigin(i, pos);

			char szPos[100];
			FormatEx(szPos, sizeof(szPos), "%.2f %.2f %.2f", pos[0], pos[1], pos[2]);

			if ( g_player[i].currentLobby.serverSocket != INVALID_HANDLE )
			{
				if ( g_player[i].currentLobby.serverSocket.Connected )
				{
					g_player[i].currentLobby.serverSocket.Send(szPos);
				}
			}
		}
	}
}