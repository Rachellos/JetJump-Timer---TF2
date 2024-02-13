import socket
from events.custom import CustomEvent
from events.variable import StringVariable
from events.variable import ShortVariable
from events.resource import ResourceFile
from events import Event
from socket import socket as sock
from threading import Thread


def load():
    print('Plugin has been loaded successfully!')


def unload():
    print('Plugin has been unloaded successfully!')


class On_Server_Got_Data(CustomEvent):
    data = StringVariable("Receive Data Gotten for server socket")
    lobby_index = ShortVariable("Lobby array id for management")


class On_Client_Got_Data(CustomEvent):
    data = StringVariable("Receive Data Gotten for client socket")
    lobby_index = ShortVariable("Lobby array id for management")


resource_file = ResourceFile('my_custom_events', On_Server_Got_Data)
resource_file.write()
resource_file.load_events()

resource_file2 = ResourceFile('my_custom_events', On_Client_Got_Data)
resource_file2.write()
resource_file2.load_events()


def fire_got_sever_data_event(msg, lobby):
    event = On_Server_Got_Data(data=msg, lobby_index=lobby)
    event.fire()

    print("FIRED SERVER DATA GOTTEN")


def fire_got_client_data_event(msg):
    event = On_Client_Got_Data(data=msg)
    event.fire()
    print("FIRED CLIENT DATA GOTTEN")


def server_socket_thread(arg):
    while True:
        data = arg['con'].recv(1024).decode()

        print(f"GOTTEN: {data}")

        fire_got_sever_data_event(data, arg['lobby_id'])


def client_socket_thread(arg):
    while True:
        data = arg['con'].recv(1024).decode()

        print(f"GOTTEN client: {data}")

        fire_got_client_data_event(data)


@Event('jetjump_server_socket_created')
def on_server_socket_create(sm_event):
    port = sm_event['port']
    lobby = sm_event['lobby_id']
    server = sock(socket.AF_INET, socket.SOCK_DGRAM)
    server.bind(('0.0.0.0', port))

    arg = {"con": server, "lobby_id": lobby}

    thread = Thread(target=server_socket_thread, args=((arg,)))
    thread.start()

    print("On_Server_Socket_Created CALLED")


@Event('jetjump_client_socket_created')
def on_client_socket_create(sm_event):
    port = sm_event['port']
    server = sock(socket.AF_INET, socket.SOCK_DGRAM)
    server.bind(('0.0.0.0', port))

    thread = Thread(target=client_socket_thread, args=((server,)))
    thread.start()

    print("On_Client_Socket_Created CALLED")

