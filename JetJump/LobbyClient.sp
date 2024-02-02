void ConnectToLobby(int client, int lobby_id, const char[] password = "")
{
	int port = GetFreeLobbyPort();

	g_player[client].clientSocket = SocketCreate(SOCKET_TCP, OnClientSocketError);

	if ( !g_player[client].clientSocket.Bind("0.0.0.0", port) )
	{
		MC_PrintToChat(client, "{red}ERROR | {white}Can not create incoming connection for this {accent}Lobby{white}. Try again");
		CloseHandle(g_player[client].clientSocket);
		return;
	}

	g_player[client].clientSocket.Listen(OnPlayersIncoming);
	g_player[client].clientListenPort = port;
	PrintToChatAll("client listen port: %i", port);

	char query[256];

	FormatEx(query, sizeof(query), "SELECT ip, port, password FROM lobby JOIN servers ON servers.id = lobby.server_id WHERE lobby.id = %i", lobby_id);
	g_hDatabase.Query(Thread_ConnectToLobby, query, client);
}

public void Thread_ConnectToLobby(Database db, DBResultSet results, const char[] error, any client)
{
    if ( strlen(error) > 1 ) { LogError(error); return; }

    if ( results.FetchRow() )
    {
		char ipBuff[64], ip[2][32], password[256];
		int port;

		results.FetchString(0, ipBuff, sizeof(ipBuff));
		ExplodeString( ipBuff, ":", ip, sizeof( ip ), sizeof( ip[] ) );

		port = results.FetchInt(1);

		results.FetchString(2, password, sizeof(password));

		g_player[client].ServerSocket = new Socket(_, OnServerSocketError);

		g_player[client].ServerSocket.SetArg(g_player[client].clientListenPort);
		PrintToChatAll("Connecting to host");
		g_player[client].ServerSocket.Connect(OnServerSocketConnected, OnServerSocketReceive, OnSocketDisconnected, ip[0], port);
	}
	else
	{
		MC_PrintToChat(client, "{red}ERROR | {white}Can not get info about this {accent}Lobby{white}. Try again");
		CloseHandle(g_player[client].clientSocket);
	}
}

public void OnServerSocketConnected(Socket socketServer, any clientPort)
{
	PrintToServer("Host server connected!");

	char info[100];
	FormatEx(info, sizeof(info), "%s:%i", g_server.ip, clientPort);

	socketServer.Send(info);
}

public void OnSocketDisconnected(Socket socket, any hFile)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if ( g_player[i].ServerSocket == socket )
		{
			if (g_player[i].ServerSocket.Connected)
				g_player[i].ServerSocket.Disconnect();

			if (g_player[i].clientSocket.Connected)
				g_player[i].clientSocket.Disconnect();
			
			Lobby emptyLobby;

			g_player[i].currentLobby = emptyLobby;
		}
	}

	PrintToChatAll("Disconnected from host");
}

//When a client sent a message to the MCS OR the MCS sent a message to the client, and the MCS have to handle it :
public void OnServerSocketReceive(Socket socket, char[] receiveData, const int dataSize, any pack)
{
	char connectionData[2][50];
	ExplodeString(receiveData, ":", connectionData, sizeof(connectionData), sizeof(connectionData[]));

	PrintToChatAll("data from other player: %s", receiveData);
	PrintToChatAll("%s:%s", connectionData[0], connectionData[1]);

	for (int i = 1; i <= MaxClients; i++)
	{
		if ( g_player[i].ServerSocket == socket )
		{
			if ( g_player[i].currentLobby.lobbyConnectionsSocket == INVALID_HANDLE )
				g_player[i].currentLobby.lobbyConnectionsSocket = new ArrayList();
			
			Socket newConnection = new Socket(_, OnClientSocketError);
			newConnection.Connect(OnConnectToPlayer, OnInfoFromPlayersGiven, OnPlayerDisconnected, connectionData[0], StringToInt(connectionData[1]));
			
			g_player[i].currentLobby.lobbyConnectionsSocket.Push(newConnection);
		}
	}
}

public void OnConnectToPlayer(Socket socket, any arg)
{
	char host[100];
	Socket.GetHostName(host, sizeof(host));

	PrintToChatAll("connected to %s", host);
}

public void OnPlayersIncoming(Socket socket, Socket newSocket, char[] remoteIP, int remotePort, any arg)
{
	PrintToChatAll("Player connected to player");
	newSocket.SetReceiveCallback( OnInfoFromPlayersGiven );
}

public void OnInfoFromPlayersGiven(Socket socket, char[] receiveData, const int dataSize, any hFile)
{
	PrintToServer("IRC MSG: %s", receiveData); //In any case, always print the message

	static int laser;
	laser = PrecacheModel("sprites/laserbeam.vmt")

	char pos[3][30];
	float startPosition[3], endPosition[3];

	ExplodeString(receiveData, " ", pos, sizeof(pos), sizeof(pos[]));

	for (int cur; cur < 3; cur++)
		startPosition[cur] = StringToFloat(pos[cur]);

	endPosition = startPosition;
	endPosition[1] += 100;

	TE_SetupBeamPoints(startPosition, endPosition, laser, 0, 0, 0, 5.0, 2.0, 2.0, 0, 0.0, {255, 215, 0, 255}, 0);
	TE_SendToAll();
}

public void OnGameFrame()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_player[i].currentLobby.exists)
		{
			if ( g_player[i].currentLobby.lobbyConnectionsSocket == INVALID_HANDLE )
				g_player[i].currentLobby.lobbyConnectionsSocket = new ArrayList();

			float pos[3];
			GetClientAbsOrigin(i, pos);
			for (int sockets; sockets < g_player[i].currentLobby.lobbyConnectionsSocket.Length; sockets++)
			{
				char szPos[100];
				FormatEx(szPos, sizeof(szPos), "%.2f %.2f %.2f", pos[0], pos[1], pos[2]);

				Socket player = g_player[i].currentLobby.lobbyConnectionsSocket.Get(sockets);
				if ( player != INVALID_HANDLE )
				{
					if ( player.Connected )
					{
						PrintToChatAll(szPos);
						player.Send(szPos);
					}
				}
			}
		}
	}
}

//When a client disconnect from our client
public void OnPlayerDisconnected(Socket socket, any hFile)
{
	int arr_id = -1;

	for (int client = 1; client <= MaxClients; client++)
	{
		if ( (arr_id = g_player[client].currentLobby.lobbyConnectionsSocket.FindValue(socket)) != -1 )
		{
			g_player[client].currentLobby.lobbyConnectionsSocket.Erase(arr_id);
		}
	}

	PrintToChatAll("disconnected from our client");
	CloseHandle(socket);
}

public void OnClientSocketError(Socket socket, const int errorType, const int errorNum, any arg)
{
	int client;

	PrintToChatAll("type: %i - errorNum: %i", errorType, errorNum);

	for (int idx = 1; idx <= MaxClients; idx++)
	{
		if ( g_player[idx].currentLobby.lobbyConnectionsSocket == INVALID_HANDLE )
			g_player[idx].currentLobby.lobbyConnectionsSocket = new ArrayList();
		
		if ( g_player[idx].currentLobby.lobbyConnectionsSocket.FindValue(socket) != -1 )
		{
			client = idx;
		}
	}

	if (g_player[client].clientSocket != INVALID_HANDLE)
		CloseHandle(g_player[client].clientSocket);
	
	if (g_player[client].ServerSocket != INVALID_HANDLE)
		CloseHandle(g_player[client].ServerSocket);

	MC_PrintToChat(client, "{red}ERROR | {white}You was kicked from {accent}Lobby #%i{white}. Some network error", g_player[client].currentLobby.id);

	Lobby emptyLobby;

	g_player[client].currentLobby = emptyLobby;
}