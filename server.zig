const std = @import("std");
const windows = std.os.windows;
const ws2_32 = windows.ws2_32;

const ContinuousDataAcquisition = @import("main.zig").ContinuousDataAcquisition;
const AdDataSample = @import("main.zig").AdDataSample;
const MAX_CHANNELS = @import("main.zig").MAX_CHANNELS;

pub const NetworkError = error{
    WSAStartupFailed,
    SocketCreationFailed,
    SetSockOptFailed,
    BindFailed,
    ListenFailed,
    AcceptFailed,
    SendFailed,
};

// Address family and socket constants
const AF_INET = 2; // Address family for IPv4
const SOCK_STREAM = 1; // TCP socket type
const IPPROTO_TCP = 6; // TCP protocol
const SOL_SOCKET = 0xFFFF;
const SO_REUSEADDR = 0x0004;

pub const AdDataServer = struct {
    listener: std.net.Stream,
    listen_address: std.net.Address,
    client_set: std.AutoHashMap(*Connection, void),
    allocator: std.mem.Allocator,
    acquisition: *ContinuousDataAcquisition,

    const Connection = struct {
        socket: ws2_32.SOCKET,
        server: *AdDataServer,

        fn init(server: *AdDataServer, socket: ws2_32.SOCKET) Connection {
            return .{
                .socket = socket,
                .server = server,
            };
        }

        fn handle(self: *Connection) !void {
            defer {
                _ = ws2_32.closesocket(self.socket);
                _ = self.server.client_set.remove(self);
                self.server.allocator.destroy(self);
            }

            var sample_buffer: [100]AdDataSample = undefined;

            while (true) {
                const samples_read = self.server.acquisition.getSamples(&sample_buffer);
                if (samples_read > 0) {
                    const DataPacket = struct {
                        timestamp: i128,
                        values: [MAX_CHANNELS]f32,
                    };

                    for (sample_buffer[0..samples_read]) |sample| {
                        var packet = DataPacket{
                            .timestamp = sample.timestamp,
                            .values = sample.channel_data[0..MAX_CHANNELS].*,
                        };

                        const bytes = std.mem.asBytes(&packet);

                        // Use ws2_32.send instead of stream.write
                        const send_result = ws2_32.send(self.socket, bytes.ptr, @intCast(bytes.len), 0);

                        if (send_result == -1) {
                            const err = ws2_32.WSAGetLastError();
                            std.debug.print("Send failed with error: {}\n", .{err});
                            return NetworkError.SendFailed;
                        }
                    }
                }

                std.time.sleep(10 * std.time.ns_per_ms);
            }
        }
    };

    pub fn init(allocator: std.mem.Allocator, acquisition: *ContinuousDataAcquisition) !*AdDataServer {
        // Initialize WSA
        var wsa_data: ws2_32.WSADATA = undefined;
        const startup_result = ws2_32.WSAStartup(0x0202, &wsa_data);
        if (startup_result != 0) {
            return NetworkError.WSAStartupFailed;
        }

        const self = try allocator.create(AdDataServer);
        errdefer allocator.destroy(self);

        // Create socket
        const sock = ws2_32.socket(AF_INET, // IPv4
            SOCK_STREAM, // TCP
            IPPROTO_TCP // TCP Protocol
        );

        // Check if socket handle is valid
        const socket_int = @intFromPtr(sock);
        if (socket_int == -1) {
            const err = ws2_32.WSAGetLastError();
            std.debug.print("Socket creation failed with error: {}\n", .{err});
            return NetworkError.SocketCreationFailed;
        }

        // Enable address reuse
        var enable: u32 = 1;
        const sockopt_result = ws2_32.setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, @ptrCast(&enable), @sizeOf(@TypeOf(enable)));
        if (sockopt_result != 0) {
            const err = ws2_32.WSAGetLastError();
            std.debug.print("Setsockopt failed with error: {}\n", .{err});
            return NetworkError.SetSockOptFailed;
        }

        // Create address and bind
        const address = try std.net.Address.parseIp4("0.0.0.0", 8000);
        const bind_result = ws2_32.bind(sock, @ptrCast(&address.any), @intCast(address.getOsSockLen()));
        if (bind_result != 0) {
            const err = ws2_32.WSAGetLastError();
            std.debug.print("Bind failed with error: {}\n", .{err});
            return NetworkError.BindFailed;
        }

        self.* = .{
            .listener = .{ .handle = sock },
            .listen_address = address,
            .client_set = std.AutoHashMap(*Connection, void).init(allocator),
            .allocator = allocator,
            .acquisition = acquisition,
        };

        return self;
    }

    pub fn deinit(self: *AdDataServer) void {
        var it = self.client_set.keyIterator();
        while (it.next()) |conn| {
            _ = ws2_32.closesocket(conn.*.socket);
            self.allocator.destroy(conn.*);
        }
        self.client_set.deinit();
        self.listener.close();
        self.allocator.destroy(self);
        _ = ws2_32.WSACleanup();
    }

    pub fn start(self: *AdDataServer, port: u16) !void {
        _ = port; // port is already set in init

        // Start listening
        const listen_result = ws2_32.listen(self.listener.handle, 128);
        if (listen_result != 0) {
            const err = ws2_32.WSAGetLastError();
            std.debug.print("Listen failed with error: {}\n", .{err});
            return NetworkError.ListenFailed;
        }

        std.debug.print("TCP Server listening on port {d}...\n", .{self.listen_address.getPort()});

        while (true) {
            var addr: std.net.Address = undefined;
            var addr_len: i32 = @intCast(@sizeOf(std.net.Address));

            const client_socket = ws2_32.accept(self.listener.handle, @ptrCast(&addr.any), &addr_len);

            const client_int = @intFromPtr(client_socket);
            if (client_int == -1) {
                const err = ws2_32.WSAGetLastError();
                std.debug.print("Accept failed with error: {}\n", .{err});
                continue;
            }

            const conn = try self.allocator.create(Connection);
            conn.* = Connection.init(self, client_socket);
            try self.client_set.put(conn, {});

            // Spawn a thread to handle this connection
            const thread = try std.Thread.spawn(.{}, Connection.handle, .{conn});
            thread.detach();
        }
    }
};
