stock void CreateLobbyServer(Player creator, char[] password = "", char[] lobbyName = "")
{
	if ( creator.currentLobby.exists )
	{
		MC_PrintToChat(creator.clientIndex, "{red}ERROR {white}| You have already created a lobby!");
		return;
	}

	int lobbyIndex = GetFreeLobbyIndex();

	if ( lobbyIndex == -1 )
	{
		MC_PrintToChat(creator.clientIndex, "{red}ERROR {white}| Lobbies limit {accent}exceeded{white}!");
		return;
	}

	g_lobby[lobbyIndex].creator_id = creator.id;

	g_lobby[lobbyIndex].serverSocket = SocketCreate(SOCKET_TCP, OnServerSocketError);
	g_lobby[lobbyIndex].serverSocket.SetArg(lobbyIndex);

	int port = GetFreeLobbyPort();

	if ( !g_lobby[lobbyIndex].serverSocket.Bind("0.0.0.0", port) )
	{
		PrintToChat(creator.clientIndex, "cant create server");
		CreateLobbyServer(creator, password, lobbyName);
		return;
	}
	
	g_lobby[lobbyIndex].serverSocket.Listen(OnLobbyIncoming);

	g_lobby[lobbyIndex].lobbyConnectionsSocket = new ArrayList();

	char query[255];

	SQL_LockDatabase(g_hDatabase);

	FormatEx(query, sizeof(query), "INSERT INTO lobby (creator_id, server_id, password, lobby_name, port) VALUES(%i, %i, '%s', '%s', %i)", creator.id, g_server.id, password, lobbyName, port);

	if ( !SQL_FastQuery(g_hDatabase, query) )
	{
		MC_PrintToChat(creator.clientIndex, "{red}ERROR {white}| Lobby was not {accent}created{white}!");

		SQL_UnlockDatabase(g_hDatabase);
		CloseHandle(g_lobby[lobbyIndex].serverSocket);
		return;
	}

	SQL_UnlockDatabase(g_hDatabase);

	FormatEx(query, sizeof(query), "SELECT id FROM lobby WHERE creator_id = %i", creator.id);
	
	g_hDatabase.Query(Thread_GetLobbyId, query, lobbyIndex);

	g_lobby[lobbyIndex].serverHost_id = g_server.id;
	g_lobby[lobbyIndex].port = port;

	strcopy(g_lobby[lobbyIndex].password, Lobby::password, password);
	strcopy(g_lobby[lobbyIndex].lobbyName, Lobby::lobbyName, lobbyName);

	g_lobby[lobbyIndex].exists = true;
}

public void Thread_GetLobbyId(Database db, DBResultSet results, const char[] error, any lobbyId)
{
    if ( strlen(error) > 1 ) { LogError(error); return; }

    if ( results.FetchRow() )
    {
		g_lobby[lobbyId].id = results.FetchInt(0);

		for (int i = 1; i <= MaxClients; i++)
			if ( g_player[i].id == g_lobby[lobbyId].creator_id )
			{
				MC_PrintToChat(i, "Lobby was {accent}Created{white}! ID: %i", g_lobby[lobbyId].id);
				ConnectToLobby(i, g_lobby[lobbyId].id);
			}
	}
}

public void OnLobbyIncoming(Socket socket, Socket newSocket, char[] remoteIP, int remotePort, any index)
{
	PrintToServer("Another player connected to the lobby server ! from (%s)", remoteIP);
	newSocket.SetArg(index);
	newSocket.SetReceiveCallback( OnServerChildSocketReceive );
	newSocket.SetDisconnectCallback( OnServerChildSocketDisconnected );
	newSocket.SetErrorCallback( OnChildSocketError );
	

	g_lobby[index].lobbyConnectionsSocket.Push(newSocket);
}

//When a client sent a message to the server OR the server sent a message to the client :
public void OnServerChildSocketReceive(Socket socket, char[] receiveData, const int dataSize, any index)
{
	if ( g_lobby[index].lobbyConnectionsSocket == INVALID_HANDLE ) return;

	for (int i = 0; i < g_lobby[index].lobbyConnectionsSocket.Length; i++)
	{
		//Get client :
		Socket client = g_lobby[index].lobbyConnectionsSocket.Get(i);
		
		//If the handle to the client socket and the socket is connected, send the message :
		if(client && client.Connected)
		{
			client.Send( receiveData );
		}
	}
}

//When a client disconnect
public void OnServerChildSocketDisconnected(Socket socket, any index)
{
	int arr_id = g_lobby[index].lobbyConnectionsSocket.FindValue(socket);

	if ( arr_id != -1 )
	{
		g_lobby[index].lobbyConnectionsSocket.Erase(arr_id);
	}

	PrintToChatAll("player disconnected from host");

	CloseHandle(socket);
}

//When a client crash :
public void OnChildSocketError(Socket socket, const int errorType, const int errorNum, any index)
{
	PrintToServer("child socket error %d (errno %d)", errorType, errorNum);

	int arr_id = -1;
	
	arr_id = g_lobby[index].lobbyConnectionsSocket.FindValue(socket);

	if ( arr_id != -1 )
	{
		g_lobby[index].lobbyConnectionsSocket.Erase(arr_id);
	}

	PrintToChatAll("player disconnected from host (error)");

	CloseHandle(socket);
}

public void OnServerSocketError(Socket socket, const int errorType, const int errorNum, any index)
{
	if (g_lobby[index].serverSocket != INVALID_HANDLE)
		CloseHandle(g_lobby[index].serverSocket);

	for (int i = 1; i <= MaxClients; i++)
		if ( g_player[i].id == g_lobby[index].creator_id && IsClientInGame(i) )
			MC_PrintToChat(i, "{red}ERROR | {white}Lobby was {accent}Closed{white}. Some network error");

	PrintToChatAll("Error host creation: %i: num %i", errorType, errorNum);
}

int GetFreeLobbyIndex()
{
	for (int i; i < 10; i++)
		if ( !g_lobby[i].exists )
			return i;
	
	return -1;
}

int GetFreeLobbyPort()
{
	int port = GetRandomInt(27050, 28050);

	for (int i; i < 10; i++)
	{
		if ( g_lobby[i].port == port )
		{
			port = GetFreeLobbyPort();
		}
	}
	
	return port;
}

stock void CloseLobbyServer(Lobby lobby)
{
	Lobby emptyLobby;
	
	SQL_LockDatabase(g_hDatabase);

	char query[128];
	FormatEx(query, sizeof(query), "DELETE FROM lobby WHERE id = %i", lobby.id);
	SQL_FastQuery(g_hDatabase, query);

	SQL_UnlockDatabase(g_hDatabase);

	for (int i; i <= MaxClients; i++)
	{
		if ( g_player[i].currentLobby.id == lobby.id )
		{
			JetJump_PrintToChat(g_player[i].clientIndex, "Lobby #%i was {accent}closed{white}! You are no longer in it.", lobby.id);
			g_player[i].currentLobby = emptyLobby;
		}
	}

	if ( lobby.serverSocket && lobby.serverSocket.Connected )
		lobby.serverSocket.Disconnect();

	// clear the lobby here
	lobby = emptyLobby;
}