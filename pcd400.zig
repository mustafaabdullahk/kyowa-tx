// pcd400.zig

const std = @import("std");
const windows = std.os.windows;

// Constants
pub const Error = enum(i32) {
    NONE = 0,
    NOT_OPEN = -1,
    PARAM = -2,
    LOCKED = -3,
    NO_TARGET = -100,
    TRANS = -101,
    EXCEPTION = -102,

    pub fn fromI32(value: i32) Error {
        return switch (value) {
            0 => .NONE,
            -1 => .NOT_OPEN,
            -2 => .PARAM,
            -3 => .LOCKED,
            -100 => .NO_TARGET,
            -101 => .TRANS,
            -102 => .EXCEPTION,
            else => unreachable,
        };
    }
};

pub const TMO_MAX: u32 = 60;

// External function declarations
pub extern "pcd400" fn PCD400_UsbOpen() callconv(.C) i32;
pub extern "pcd400" fn PCD400_UsbClose() callconv(.C) i32;
pub extern "pcd400" fn PCD400_UsbSetTimeOut(timeout: u16) callconv(.C) i32;
pub extern "pcd400" fn PCD400_UsbConnectCheck(connection: *u16) callconv(.C) i32;
pub extern "pcd400" fn PCD400_UsbSendCmd(sendByte: u32, sendCmd: *const anyopaque) callconv(.C) i32;
pub extern "pcd400" fn PCD400_UsbReceiveCmd(receiveCmd: *anyopaque, receiveSize: u32) callconv(.C) i32;
pub extern "pcd400" fn PCD400_UsbTargetReset() callconv(.C) i32;

// Wrapper functions with error handling
pub fn usbOpen() !void {
    const result = PCD400_UsbOpen();
    if (result != 0) {
        return error.UsbOpenFailed;
    }
}

pub fn usbClose() !void {
    const result = PCD400_UsbClose();
    if (result != 0) {
        return error.UsbCloseFailed;
    }
}

pub fn usbSetTimeOut(timeout: u16) !void {
    const result = PCD400_UsbSetTimeOut(timeout);
    if (result != 0) {
        return error.SetTimeOutFailed;
    }
}

pub fn usbConnectCheck() !bool {
    var connection: u16 = 0;
    const result = PCD400_UsbConnectCheck(&connection);
    if (result != 0) {
        return error.ConnectCheckFailed;
    }
    return connection != 0;
}

pub fn usbSendCmd(data: []const u8) !void {
    const result = PCD400_UsbSendCmd(@intCast(data.len), data.ptr);

    std.debug.print("\nSent Packet Size:{d}\n", .{data.len});

    if (result != 0) {
        return error.SendCmdFailed;
    }
}

pub fn usbReceiveCmd(buffer: []u8) !i32 {
    const result = PCD400_UsbReceiveCmd(buffer.ptr, @intCast(buffer.len));

    std.debug.print("\nReceived Packet Size:{d}, buffer len={d}\n", .{ result, buffer.len });

    if (result < 0) {
        std.debug.print("UsbReceiveCmd failed with ={d}", .{result});
        return error.ReceiveCmdFailed;
    }

    return result;
}

pub fn usbTargetReset() !void {
    const result = PCD400_UsbTargetReset();
    if (result != 0) {
        return error.TargetResetFailed;
    }
}
