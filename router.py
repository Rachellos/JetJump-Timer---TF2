import socket
from events.custom import CustomEvent
from events.variable import StringVariable
from events.variable import ShortVariable
from events.resource import ResourceFile
from events import Event
from socket import socket as sock
from listeners import OnTick
from threading import Thread


class on_servergotdata(CustomEvent):
    data = StringVariable("Receive Data Gotten for server socket")


class on_clientgotdata(CustomEvent):
    data = StringVariable("Receive Data Gotten for client socket")


resource_file1 = ResourceFile('my_custom_events', on_servergotdata, on_clientgotdata)
resource_file1.write()
resource_file1.load_events()


FireServer = {"need": False, "data": ""}
FireClient = {"need": False, "data": ""}

@OnTick
def checkData():
    if FireServer['need']:
        event = on_servergotdata()
        event.data = FireServer['data']
        event.fire()
        FireServer['need'] = False
    
    if FireClient['need']:
        event = on_clientgotdata()
        event.data = FireClient['data']
        event.fire()
        FireClient['need'] = False


def load():
    thread1 = Thread(target=server_socket_thread)
    thread1.start()

    thread2 = Thread(target=client_socket_thread)
    thread2.start()

    print('[SP] Router has been loaded!')


def unload():
    print('[SP] Router has been unloaded')


def server_socket_thread():
    server = sock(socket.AF_INET, socket.SOCK_DGRAM)
    server.bind(('0.0.0.0', 30001))

    while True:
        try:
            data = server.recv(1024).decode()
            FireServer['data'] = data
            FireServer['need'] = True
            print(data)
        
        except socket.error as e:
            print(f"Error occurred: {e}")


def client_socket_thread():
    server = sock(socket.AF_INET, socket.SOCK_DGRAM)
    server.bind(('0.0.0.0', 31001))

    while True:
        try:
            data = server.recv(1024).decode()
            FireClient['data'] = data
            FireClient['need'] = True
            print(data)
    
        except socket.error as e:
            print(f"Error occurred: {e}")