import socket
import struct
import time
import threading

class AdDataClient:
    def __init__(self, host='localhost', port=8000, channels=4):
        self.host = host
        self.port = port
        self.channels = channels
        self.running = False
        self.socket = None
        self.current_values = [0.0] * channels

    def connect(self):
        """Establish connection to the server"""
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.socket.connect((self.host, self.port))
        print(f"Connected to {self.host}:{self.port}")

    def receive_data(self):
        """Receive and process data from the server"""
        # Calculate packet size: timestamp (16 bytes) + channels * float (4 bytes each)
        packet_size = 16 + (self.channels * 4)
        
        while self.running:
            try:
                # Receive one complete packet
                data = self.socket.recv(packet_size)
                if not data:
                    break
                
                if len(data) == packet_size:
                    # Unpack timestamp (i128/16 bytes) and channel data (array of f32)
                    # Use 'q' (signed long long) twice to represent i128
                    timestamp_low, timestamp_high = struct.unpack('qq', data[:16])
                    timestamp = (timestamp_high << 64) | timestamp_low
                    
                    # Unpack channel values
                    values = struct.unpack(f'{self.channels}f', data[16:])
                    
                    # Update current values
                    self.current_values = values
                    
                    # Clear line and print current values
                    print('\r', end='')
                    for i, value in enumerate(values):
                        print(f"CH{i+1}: {value:8.2f} μm/m  ", end='')
                    print('', end='', flush=True)
                
            except struct.error as e:
                print(f"\nStruct unpack error: {e}")
                print(f"Received data length: {len(data)}")
                print(f"Received data: {data.hex()}")
                break
            except Exception as e:
                print(f"\nError receiving data: {e}")
                break

    def start(self):
        """Start receiving data"""
        self.running = True
        
        # Start receive thread
        self.receive_thread = threading.Thread(target=self.receive_data)
        self.receive_thread.start()

    def stop(self):
        """Stop the client"""
        self.running = False
        if self.socket:
            self.socket.close()
        self.receive_thread.join()

if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description='AD Data Client')
    parser.add_argument('--host', default='localhost', help='Server host (default: localhost)')
    parser.add_argument('--port', type=int, default=8000, help='Server port (default: 8000)')
    parser.add_argument('--channels', type=int, default=4, help='Number of channels (default: 4)')
    
    args = parser.parse_args()

    # Create and start client
    client = AdDataClient(
        host=args.host,
        port=args.port,
        channels=args.channels
    )

    try:
        client.connect()
        client.start()
        
        # Keep main thread running
        while True:
            time.sleep(0.1)
            
    except KeyboardInterrupt:
        print("\nStopping client...")
        client.stop()
    except Exception as e:
        print(f"Error: {e}")
        client.stop()