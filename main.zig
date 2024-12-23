const std = @import("std");
const pcd = @import("pcd400.zig");
const AdDataServer = @import("server.zig").AdDataServer;

// Constants
pub const MAX_CHANNELS: usize = 4;

// Command packet structures
const CommandHeader = extern struct {
    model: [20]u8 = undefined, // "PCD-400A"
    transfer_bytes: u32 = 0, // Command identifier + parameter bytes
    reserved: [40]u8 = undefined, // Reserved space
};

const IniCommand = extern struct {
    header: CommandHeader,
    command: [3]u8, // INI
    parameter_mode: u8, // 0x01 Master unit only
};

const IniResponse = extern struct {
    header: ResponseHeader,
    standart_resp: u8,
};

const SysCommand = extern struct {
    header: CommandHeader,
    command: [3]u8, // "SYS"
};

const MeasuringCondition = extern struct {
    sampling_frequency: u32, // 1 to 10000
    number_of_channels: u16, // 0 to 16
    reserved: [26]u8, // Reserved
};

const ChannelCondition = extern struct {
    measurement_on_off: i8, // -1: No unit, 0: Not measure, 1: Measure
    mode: u8, // Fixed to 0 for PCD-400 A/B
    range_no: u8,
    strain_mode_no: u8,
    lpf_no: u8,
    hpf_no: u8,
    bal_on_off: u8, // 0: OFF, 1: ON
    reserved: [25]u8, // Reserved
};

// Measuring condition format structures
const GeneralInformation = extern struct {
    device_id: [20]u8, // "PCD-400A" fixed
    parameter_format_version: u16, // 1 fixed
    reserved1: [2]u8, // Reserved
    model: [8]u8, // Model 2 for PCD-400A/B
    reserved2: [48]u8, // Reserved
};

const MeasuringConditionFormat = extern struct {
    general_info: GeneralInformation, // 80 bytes
    measuring_condition: MeasuringCondition, // 32 bytes
    channel_conditions: [16]ChannelCondition, // 32 bytes × 16 channels = 512 bytes
    system_reserved: [976]u8, // 976 bytes
};

const MesSetCommand = extern struct {
    header: CommandHeader,
    command: [3]u8, // "MES"
    parameter_mode: u8, // 0x01 for Set
    measuring_conditions: MeasuringConditionFormat,
};

const MesLoadCommand = extern struct {
    header: CommandHeader align(1),
    command: [3]u8 align(1), // "MES"
    parameter_mode: u8 align(1), // 0x00 for Load
};

const MesSetResponse = extern struct {
    header: ResponseHeader,
    condition_check_result: u32,
};

const MesLoadResponse = extern struct {
    header: ResponseHeader,
    measuring_conditions: MeasuringConditionFormat,
};

// Standard Response Header (64 bytes)
const ResponseHeader = extern struct {
    model: [20]u8, // "PCD-400A"
    response_data_bytes: u32, // Size of response data section
    pcd_status: u32, // PCD status
    pcd_error_status: u32, // PCD error status
    sampling_frequency: u32, // 1 to 10000 Hz
    measuring_channel_bit: u32, // Binary digit (0: Not measure, 1: Measure)
    number_of_channels: u16, // 1 to 16
    reserved1: u8, // Reserved
    number_of_stacking_pcd: u8, // Number of stacking PCD units
    reserved2: [20]u8, // Reserved
};

// SYS command specific response data
const SysResponseData = extern struct {
    model: [32]u8, // Response data 1: Model
    firmware_version: [32]u8, // Response data 2: Firmware version
    fpga_version: [32]u8, // Response data 3: FPGA version
    usb_driver_version: [32]u8, // Response data 4: USB device driver version
    serial_no: [32]u8, // Response data 5: SERIAL No.
    reserved1: [32]u8, // Response data 6: Reserved
    model_byte: u8, // Response data 7: Model
    reserved2: [7]u8, // Response data 8: Reserved

};

// Combined response structure
const SysResponse = extern struct {
    header: ResponseHeader,
    data: [4]SysResponseData,
    reserved3: [800]u8, // Response data 9: Reserved
};

const StartAdConversionCommand = extern struct {
    header: CommandHeader,
    command: [3]u8, // "STA"
};

const StopAdConversionCommand = extern struct {
    header: CommandHeader,
    command: [3]u8, // "STP"
};

const AdConversionResponse = extern struct {
    header: ResponseHeader,
    status: u8, // Status of the conversion (1 byte)
};

fn printHexView(label: []const u8, buffer: []const u8) void {
    std.debug.print("{s}:\n", .{label});
    for (buffer, 0..) |byte, i| {
        if (i % 16 == 0) {
            if (i > 0) std.debug.print("\n", .{});
            std.debug.print("{d:0>4}: ", .{i});
        }
        std.debug.print("{x:0>2} ", .{byte});
    }
    std.debug.print("\n\n", .{});
}

fn printHexViewDetailed(label: []const u8, buffer: []const u8, print_ascii: bool) void {
    std.debug.print("\n{s}:\n", .{label});
    var i: usize = 0;
    while (i < buffer.len) {
        // Print offset
        std.debug.print("{x:0>4}: ", .{i});

        // Print hex values (16 bytes per line)
        var j: usize = 0;
        while (j < 16) : (j += 1) {
            if (i + j < buffer.len) {
                std.debug.print("{x:0>2} ", .{buffer[i + j]});
            } else {
                std.debug.print("   ", .{}); // Padding for incomplete line
            }
        }

        // Print ASCII representation if requested
        if (print_ascii) {
            std.debug.print("  ", .{});
            j = 0;
            while (j < 16) : (j += 1) {
                if (i + j < buffer.len) {
                    const c = buffer[i + j];
                    if (c >= 32 and c <= 126) {
                        std.debug.print("{c}", .{c});
                    } else {
                        std.debug.print(".", .{});
                    }
                }
            }
        }

        std.debug.print("\n", .{});
        i += 16;
    }
    std.debug.print("\n", .{});
}

// Helper function to print active channels
fn printActiveChannels(channel_bit: u32) void {
    std.debug.print("Active channels: ", .{});
    var i: u32 = 0;
    while (i < 16) : (i += 1) { // Only check up to 16 channels as per documentation
        if (channel_bit & (@as(u32, 1) << @intCast(i)) != 0) {
            std.debug.print("CH{} ", .{i + 1});
        }
    }
    std.debug.print("\n", .{});
}

fn createDefaultMeasuringConditions() MeasuringConditionFormat {
    var conditions: MeasuringConditionFormat = undefined;

    // Initialize all memory to 0
    @memset(@as([*]u8, @ptrCast(&conditions))[0..@sizeOf(MeasuringConditionFormat)], 0);

    // Set general information
    _ = std.fmt.bufPrint(&conditions.general_info.device_id, "PCD-400A", .{}) catch unreachable;
    conditions.general_info.parameter_format_version = 1;
    conditions.general_info.model = "PCD-400A".*;

    // Set default measuring condition
    // conditions.measuring_condition.sampling_frequency = 1000; // 1kHz
    // conditions.measuring_condition.number_of_channels = 1; // 1 channel

    conditions.measuring_condition.sampling_frequency = 5000; // 5.kHz
    conditions.measuring_condition.number_of_channels = 4; // 4 channel

    // Set default channel conditions
    for (&conditions.channel_conditions) |*channel| {
        channel.measurement_on_off = 1; // Measure
        channel.mode = 0; // Fixed for PCD-400 A/B Strain
        channel.range_no = 4; // 4 5000 µm/m 20V
        channel.strain_mode_no = 0; // 0 1G2W
        channel.lpf_no = 0; // 0 FLAT FLAT
        channel.hpf_no = 0; // 0 OFF
        channel.bal_on_off = 0; // OFF
    }

    return conditions;
}

fn checkConditionResult(result: u32) !void {
    if (result == 0) return;

    if (result & 0x00000001 != 0) std.debug.print("Error: Channel condition error\n", .{});
    if (result & 0x00000200 != 0) std.debug.print("Error: Sampling frequency error\n", .{});
    if (result & 0x00008000 != 0) std.debug.print("Error: No channel to be measured\n", .{});
    if (result & 0x00040000 != 0) std.debug.print("Error: General information error\n", .{});
    if (result & 0x00080000 != 0) std.debug.print("Error: Measuring condition error\n", .{});
    if (result & 0x10000000 != 0) std.debug.print("Error: Balance adjustment conditions error\n", .{});

    return error.MeasuringConditionError;
}

fn setMeasuringConditions(conditions: MeasuringConditionFormat) !void {
    var cmd = MesSetCommand{
        .header = CommandHeader{},
        .command = "MES".*,
        .parameter_mode = 0x01,
        .measuring_conditions = undefined,
    };

    // _ = conditions;

    // Initialize header
    @memset(&cmd.header.model, 0);
    _ = try std.fmt.bufPrint(&cmd.header.model, "PCD-400A", .{});
    cmd.header.transfer_bytes = 1604; // 3 + 1 + 1600
    @memset(&cmd.header.reserved, 0);

    // Initialize measuring conditions
    var measuring_conditions: MeasuringConditionFormat = undefined;
    @memset(@as([*]u8, @ptrCast(&measuring_conditions))[0..@sizeOf(MeasuringConditionFormat)], 0);

    // Set general information - this part was missing the device ID
    @memset(&measuring_conditions.general_info.device_id, 0);
    _ = try std.fmt.bufPrint(&measuring_conditions.general_info.device_id, "PCD-400A", .{});
    measuring_conditions.general_info.parameter_format_version = 1;
    measuring_conditions.general_info.model[0] = 2;

    // Set measuring condition
    measuring_conditions.measuring_condition.sampling_frequency = 5000;
    measuring_conditions.measuring_condition.number_of_channels = 4;

    // Set channel conditions
    for (&measuring_conditions.channel_conditions, 0..) |*channel, i| {
        if (i < 4) { // First 4 channels ON
            channel.* = .{
                .measurement_on_off = 1, // ON
                .mode = 0, // Fixed for PCD-400A/B
                .range_no = 4, // 5000 μm/m
                .strain_mode_no = 0, // 1G2W
                .lpf_no = 0, // FLAT
                .hpf_no = 0, // OFF
                .bal_on_off = 0, // OFF
                .reserved = [_]u8{0} ** 25,
            };
        } else { // Remaining channels OFF
            channel.* = .{
                .measurement_on_off = -1, // No unit
                .mode = 0,
                .range_no = 0, // Keep same range for consistency
                .strain_mode_no = 0,
                .lpf_no = 0,
                .hpf_no = 0,
                .bal_on_off = 0,
                .reserved = [_]u8{0} ** 25,
            };
        }
    }

    // Zero the system reserved area
    @memset(&measuring_conditions.system_reserved, 0);

    // Copy to command structure
    cmd.measuring_conditions = conditions;

    // Debug print each section to verify
    const cmd_bytes = std.mem.asBytes(&cmd);

    // Print size info first
    std.debug.print("\nStructure Sizes:\n", .{});
    std.debug.print("CommandHeader: {d}\n", .{@sizeOf(CommandHeader)});
    std.debug.print("GeneralInformation: {d}\n", .{@sizeOf(GeneralInformation)});
    std.debug.print("MeasuringCondition: {d}\n", .{@sizeOf(MeasuringCondition)});
    std.debug.print("ChannelCondition: {d}\n", .{@sizeOf(ChannelCondition)});
    std.debug.print("MeasuringConditionFormat: {d}\n", .{@sizeOf(MeasuringConditionFormat)});

    // Print command sections
    printHexView("\nFull Command Packet", cmd_bytes);
    printHexView("\nCommand Header", cmd_bytes[0..64]);
    printHexView("\nCommand and Mode", cmd_bytes[64..68]);
    printHexView("\nGeneral Info", cmd_bytes[68..148]);
    printHexView("\nMeasuring Condition", cmd_bytes[148..180]);

    var label_buf: [32]u8 = undefined;
    for (0..4) |i| {
        const start = 180 + (i * 32);
        const end = start + 32;
        const label = std.fmt.bufPrint(&label_buf, "\nChannel {d}", .{i + 1}) catch unreachable;
        printHexView(label, cmd_bytes[start..end]);
    }

    std.debug.print("\nPacket size: {d} bytes\n", .{cmd_bytes.len});

    // Send command
    try pcd.usbSendCmd(cmd_bytes);

    // Receive and process response
    var response: MesSetResponse = undefined;
    const receive_size: usize = @intCast(try pcd.usbReceiveCmd(std.mem.asBytes(&response)));
    printHexView("\nResponse Buffer", std.mem.asBytes(&response)[0..receive_size]);

    if (response.header.pcd_error_status != 0) {
        std.debug.print("PCD Error Status: 0x{X:0>8}\n", .{response.header.pcd_error_status});
        return error.PcdError;
    }

    try checkConditionResult(response.condition_check_result);
}

pub fn loadMeasuringConditions() !MeasuringConditionFormat {
    var cmd = MesLoadCommand{
        .header = CommandHeader{},
        .command = "MES".*,
        .parameter_mode = 0x00,
    };

    // Initialize header
    @memset(&cmd.header.model, 0);
    @memset(&cmd.header.reserved, 0);
    _ = try std.fmt.bufPrint(&cmd.header.model, "PCD-400A", .{});
    cmd.header.transfer_bytes = 4; // 3 + 1 bytes

    // Send command
    try pcd.usbSendCmd(std.mem.asBytes(&cmd));

    // Receive response
    var response: MesLoadResponse = undefined;
    const retMesLoadResponse = pcd.usbReceiveCmd(std.mem.asBytes(&response));

    std.debug.print("received mes response size {any}", .{retMesLoadResponse});

    // Check response
    if (response.header.pcd_error_status != 0) {
        return error.PcdError;
    }

    return response.measuring_conditions;
}

// Helper function to parse strain mode string to number
fn parseStrainMode(strain_mode: []const u8) u8 {
    if (std.mem.eql(u8, strain_mode, "1G2W")) return 0;
    if (std.mem.eql(u8, strain_mode, "1G3W")) return 1;
    if (std.mem.eql(u8, strain_mode, "2G")) return 2;
    if (std.mem.eql(u8, strain_mode, "4G")) return 3;
    std.debug.print("Unknown strain mode: {s}\n", .{strain_mode});
    return 0; // Default to 1G2W
}

// Helper function to parse LPF string to number
fn parseLpf(lpf: []const u8) u8 {
    if (std.mem.eql(u8, lpf, "FLAT")) return 0;
    if (std.mem.eql(u8, lpf, "100Hz")) return 1;
    if (std.mem.eql(u8, lpf, "30Hz")) return 2;
    if (std.mem.eql(u8, lpf, "10Hz")) return 3;
    std.debug.print("Unknown LPF: {s}\n", .{lpf});
    return 0; // Default to FLAT
}

// Add helper function to convert numeric values back to strings for debug printing
fn strainModeToString(mode: u8) []const u8 {
    return switch (mode) {
        0 => "1G2W",
        1 => "1G3W",
        2 => "2G",
        3 => "4G",
        else => "Unknown",
    };
}

fn lpfToString(lpf: u8) []const u8 {
    return switch (lpf) {
        0 => "FLAT",
        1 => "100Hz",
        2 => "30Hz",
        3 => "10Hz",
        else => "Unknown",
    };
}

fn rangeToString(range: u8) []const u8 {
    return switch (range) {
        0 => "200μm/m",
        1 => "500μm/m",
        2 => "1000μm/m",
        3 => "2000μm/m",
        4 => "5000μm/m",
        5 => "10000μm/m",
        6 => "20000μm/m",
        else => "Unknown",
    };
}

pub fn printChannelConfig(config: *const MeasuringConditionFormat) void {
    std.debug.print("\n=== PCD Configuration Summary ===\n", .{});
    std.debug.print("Device ID: {s}\n", .{config.general_info.device_id});
    std.debug.print("Parameter Version: {d}\n", .{config.general_info.parameter_format_version});
    std.debug.print("Sampling Frequency: {d} Hz\n", .{config.measuring_condition.sampling_frequency});
    std.debug.print("Number of Active Channels: {d}\n", .{config.measuring_condition.number_of_channels});

    std.debug.print("\n--- Channel Configurations ---\n", .{});
    // Only print up to MAX_CHANNELS
    for (config.channel_conditions[0..MAX_CHANNELS], 0..) |channel, i| {
        std.debug.print("\nChannel {d}:\n", .{i + 1});
        std.debug.print("  Status: {s}\n", .{if (channel.measurement_on_off == 1) "ON" else if (channel.measurement_on_off == 0) "OFF" else "No Unit"});
        std.debug.print("  Mode: {d}\n", .{channel.mode});
        std.debug.print("  Range: {s}\n", .{rangeToString(channel.range_no)});
        std.debug.print("  Strain Mode: {s}\n", .{strainModeToString(channel.strain_mode_no)});
        std.debug.print("  LPF: {s}\n", .{lpfToString(channel.lpf_no)});
        std.debug.print("  HPF: {d}\n", .{channel.hpf_no});
        std.debug.print("  Balance: {s}\n", .{if (channel.bal_on_off == 1) "ON" else "OFF"});
    }
    std.debug.print("\n==============================\n", .{});
}

fn parseChannelConfig(config_contents: []const u8) !MeasuringConditionFormat {
    var config: MeasuringConditionFormat = undefined;
    @memset(@as([*]u8, @ptrCast(&config))[0..@sizeOf(MeasuringConditionFormat)], 0);

    // Set general information
    _ = std.fmt.bufPrint(&config.general_info.device_id, "PCD-400A", .{}) catch unreachable;
    config.general_info.parameter_format_version = 1;

    // Set model to 2 for PCD-400A/B
    config.general_info.model[0] = 2;

    // Set measuring condition defaults
    config.measuring_condition = .{
        .sampling_frequency = 5000, // 5kHz
        .number_of_channels = 0, // Will be updated as we count active channels
        .reserved = [_]u8{0} ** 26,
    };

    // Initialize all channels to OFF state
    for (&config.channel_conditions) |*ch| {
        ch.* = .{
            .measurement_on_off = -1, // No unit by default
            .mode = 0, // Fixed to 0 for PCD-400A/B
            .range_no = 4, // 5k μm/m
            .strain_mode_no = 0, // 1G2W
            .lpf_no = 0, // FLAT
            .hpf_no = 0, // OFF
            .bal_on_off = 0, // OFF
            .reserved = [_]u8{0} ** 25,
        };
    }

    var lines = std.mem.split(u8, config_contents, "\n");
    // Skip header
    _ = lines.next();

    var active_channels: u16 = 0;

    // Process each line
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r\n");
        if (trimmed.len == 0) continue;

        var columns = std.mem.split(u8, trimmed, ",");

        // Parse channel number (first column)
        const ch_num = std.fmt.parseInt(usize, std.mem.trim(u8, columns.next() orelse continue, " "), 10) catch continue;

        if (ch_num < 1 or ch_num > MAX_CHANNELS) continue;

        // Skip Model column
        _ = columns.next();

        // Measurement ON/OFF
        const meas = columns.next() orelse continue;
        if (std.mem.eql(u8, std.mem.trim(u8, meas, " "), "ON")) {
            config.channel_conditions[ch_num - 1].measurement_on_off = 1;
            active_channels += 1;
        }

        // Skip Mode column (should be Strain)
        _ = columns.next();

        // Strain Mode
        if (columns.next()) |strain_mode| {
            const trimmed_mode = std.mem.trim(u8, strain_mode, " ");
            config.channel_conditions[ch_num - 1].strain_mode_no = parseStrainMode(trimmed_mode);
        }

        // Skip Gage Factor
        _ = columns.next();

        // Range
        if (columns.next()) |range| {
            const trimmed_range = std.mem.trim(u8, range, " ");
            if (std.mem.eql(u8, trimmed_range, "5k")) {
                config.channel_conditions[ch_num - 1].range_no = 4; // 5000 μm/m
            }
        }

        // LPF
        if (columns.next()) |lpf| {
            const trimmed_lpf = std.mem.trim(u8, lpf, " ");
            config.channel_conditions[ch_num - 1].lpf_no = parseLpf(trimmed_lpf);
        }

        // Balance
        if (columns.next()) |bal| {
            const trimmed_bal = std.mem.trim(u8, bal, " ");
            config.channel_conditions[ch_num - 1].bal_on_off =
                if (std.mem.eql(u8, trimmed_bal, "ON")) 1 else 0;
        }
    }

    // Set number of active channels
    config.measuring_condition.number_of_channels = active_channels;
    std.debug.print("Total active channels: {d}\n", .{active_channels});

    return config;
}

pub fn loadChannelConfig(config_path: []const u8) !MeasuringConditionFormat {
    // Read entire file contents
    const config_contents = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, config_path, 1024 // Max file size
    );
    defer std.heap.page_allocator.free(config_contents);

    return parseChannelConfig(config_contents);
}

pub fn startAdConversion() !u8 {
    // Detailed status check before starting
    var status_cmd = CommandHeader{};
    @memset(&status_cmd.model, 0);
    @memset(&status_cmd.reserved, 0);
    _ = try std.fmt.bufPrint(&status_cmd.model, "PCD-400A", .{});
    status_cmd.transfer_bytes = 0;

    try pcd.usbSendCmd(std.mem.asBytes(&status_cmd));

    var status_response: ResponseHeader = undefined;
    _ = try pcd.usbReceiveCmd(std.mem.asBytes(&status_response));

    std.debug.print("Pre-Start Status: 0x{X:0>8}\n", .{status_response.pcd_status});
    std.debug.print("Pre-Start Error Status: 0x{X:0>8}\n", .{status_response.pcd_error_status});

    // Check if AD conversion start is available (bit 0x00000001)
    if (status_response.pcd_status & 0x00000001 == 0) {
        std.debug.print("AD conversion not available. PCD Status: 0x{X:0>8}\n", .{status_response.pcd_status});
        return error.AdConversionNotAvailable;
    }

    // Prepare STA command
    var cmd = StartAdConversionCommand{
        .header = CommandHeader{},
        .command = "STA".*,
    };

    @memset(&cmd.header.model, 0);
    @memset(&cmd.header.reserved, 0);
    _ = try std.fmt.bufPrint(&cmd.header.model, "PCD-400A", .{});
    cmd.header.transfer_bytes = 3;

    // Send command
    try pcd.usbSendCmd(std.mem.asBytes(&cmd));

    // Receive response
    var response: AdConversionResponse = undefined;
    const receive_size = try pcd.usbReceiveCmd(std.mem.asBytes(&response));

    // Additional detailed logging
    std.debug.print("Start Conversion Response Size: {}\n", .{receive_size});
    std.debug.print("Start Conversion Status: 0x{X:0>8}\n", .{response.header.pcd_status});
    std.debug.print("Start Conversion Error Status: 0x{X:0>8}\n", .{response.header.pcd_error_status});

    // Verify status is now 0x00000003 (AD conversion in progress)
    if (response.header.pcd_status & 0x00000003 != 0x00000003) {
        std.debug.print("AD conversion not started correctly\n", .{});
        return error.AdConversionStartFailed;
    }

    // Check for errors
    if (response.header.pcd_error_status != 0) {
        std.debug.print("PCD Error Status: 0x{X:0>8}\n", .{response.header.pcd_error_status});
        return error.PcdError;
    }

    return response.status;
}

pub fn stopAdConversion() !u8 {
    var cmd = StopAdConversionCommand{
        .header = CommandHeader{},
        .command = "STP".*,
    };

    // Initialize header
    @memset(&cmd.header.model, 0);
    @memset(&cmd.header.reserved, 0);
    _ = try std.fmt.bufPrint(&cmd.header.model, "PCD-400A", .{});

    // Send command
    try pcd.usbSendCmd(std.mem.asBytes(&cmd));

    // Receive response
    var response: AdConversionResponse = undefined;
    const retAdConversionCommand = pcd.usbReceiveCmd(std.mem.asBytes(&response));

    std.debug.print("stop ad conversion response size {any}", .{retAdConversionCommand});

    // Check for errors
    if (response.header.pcd_error_status != 0) {
        return error.PcdError;
    }

    return response.status; // Return the status of the conversion
}

// Maximum number of samples to store
const MAX_SAMPLES = 10000;

// Conversion constants
const AD_MAX_VALUE: f32 = 8200000.0; // Maximum AD value for full scale
const DEFAULT_GAGE_FACTOR: f32 = 2.00; // Default gage factor used by PCD

fn compensateNonlinearity(strain: f32) f32 {
    // ε1 = ε0 - (ε0 × |ε0| × 10^-6)
    // where ε0 is measured strain and ε1 is compensated strain
    const abs_strain = @abs(strain);
    return strain - (strain * abs_strain * 1e-6);
}

fn compensateGageFactor(strain: f32, gage_factor: f32) f32 {
    // ε2 = ε1 × (2.00 / Ks)
    // where ε1 is nonlinearity compensated strain,
    // Ks is actual gage factor, and ε2 is true strain
    return strain * (DEFAULT_GAGE_FACTOR / gage_factor);
}

fn convertAdValueToRange(ad_value: i32, range_index: u8, strain_mode: u8, gage_factor: f32) f32 {
    const ranges = [_]f32{
        200.0, // 200 μm/m
        500.0, // 500 μm/m
        1000.0, // 1000 μm/m
        2000.0, // 2000 μm/m
        5000.0, // 5000 μm/m
        10000.0, // 10000 μm/m
        20000.0, // 20000 μm/m
    };

    // Select range value, default to 5000 if index is out of bounds
    const range = if (range_index < ranges.len) ranges[range_index] else 5000.0;

    // Convert AD value to initial strain value
    var strain = (range / AD_MAX_VALUE) * @as(f32, @floatFromInt(ad_value));

    // Apply compensations for 1G2W or 1G3W strain modes
    if (strain_mode == 0 or strain_mode == 1) { // 1G2W or 1G3W
        // First apply nonlinearity compensation
        strain = compensateNonlinearity(strain);

        // Then apply gage factor compensation
        strain = compensateGageFactor(strain, gage_factor);
    }

    return strain;
}

// Updated AdDataSample struct to include gage factor
pub const AdDataSample = struct {
    timestamp: i128,
    channel_data: [16]f32, // Converted engineering units
    raw_ad_data: [16]i32, // Original AD values
    gage_factors: [16]f32, // Gage factors for each channel
};

pub const DataAcquisitionConfig = struct {
    sample_interval_ns: u64, // Nanoseconds between GMD command calls
    buffer_size: usize, // Size of circular buffer to store samples
    max_retries: u8, // Maximum retries on communication error
};

pub const DataAcquisitionStats = struct {
    total_samples: usize = 0,
    buffer_overruns: usize = 0,
    comm_errors: usize = 0,
    last_error: ?anyerror = null,
};

// fn convertAdValueToRange(ad_value: i32, range_index: u8) f32 {
//     const ranges = [_]f32{
//         200.0, // 200 μm/m
//         500.0, // 500 μm/m
//         1000.0, // 1000 μm/m
//         2000.0, // 2000 μm/m
//         5000.0, // 5000 μm/m
//         10000.0, // 10000 μm/m
//         20000.0, // 20000 μm/m
//     };

//     const selected_range = if (range_index < ranges.len) ranges[range_index] else 5000.0;
//     return (selected_range / 8200000.0) * @as(f32, @floatFromInt(ad_value));
// }

pub const ContinuousDataAcquisition = struct {
    config: DataAcquisitionConfig,
    measuring_conditions: MeasuringConditionFormat,
    stats: DataAcquisitionStats,
    allocator: std.mem.Allocator,
    is_running: std.atomic.Value(bool),
    data_mutex: std.Thread.Mutex,
    circular_buffer: CircularBuffer,
    acquisition_thread: ?std.Thread = null,

    const CircularBuffer = struct {
        buffer: []AdDataSample,
        head: usize,
        tail: usize,
        count: usize,

        pub fn init(allocator: std.mem.Allocator, size: usize) !CircularBuffer {
            return CircularBuffer{
                .buffer = try allocator.alloc(AdDataSample, size),
                .head = 0,
                .tail = 0,
                .count = 0,
            };
        }

        pub fn deinit(self: *CircularBuffer, allocator: std.mem.Allocator) void {
            allocator.free(self.buffer);
        }

        pub fn push(self: *CircularBuffer, sample: AdDataSample) bool {
            if (self.count == self.buffer.len) {
                return false; // Buffer full
            }
            self.buffer[self.tail] = sample;
            self.tail = (self.tail + 1) % self.buffer.len;
            self.count += 1;
            return true;
        }

        pub fn pop(self: *CircularBuffer) ?AdDataSample {
            if (self.count == 0) return null;
            const sample = self.buffer[self.head];
            self.head = (self.head + 1) % self.buffer.len;
            self.count -= 1;
            return sample;
        }
    };

    pub fn init(allocator: std.mem.Allocator, config: DataAcquisitionConfig, conditions: MeasuringConditionFormat) !*ContinuousDataAcquisition {
        const self = try allocator.create(ContinuousDataAcquisition);
        self.* = .{
            .config = config,
            .measuring_conditions = conditions,
            .stats = .{},
            .allocator = allocator,
            .is_running = std.atomic.Value(bool).init(false),
            .data_mutex = .{},
            .circular_buffer = try CircularBuffer.init(allocator, config.buffer_size),
        };
        return self;
    }

    pub fn deinit(self: *ContinuousDataAcquisition) void {
        if (self.is_running.load(.monotonic)) {
            self.stop();
        }
        self.circular_buffer.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn start(self: *ContinuousDataAcquisition) !void {
        if (self.is_running.load(.monotonic)) return error.AlreadyRunning;

        // Check device connection first
        const connected = try pcd.usbConnectCheck();
        if (!connected) return error.DeviceNotConnected;

        // Start AD conversion
        const start_status = try startAdConversion();
        if (start_status != 0) return error.StartConversionFailed;

        // According to 6-3-7, to get status we send only the header with transfer_bytes = 0
        var status_cmd = CommandHeader{
            .model = undefined,
            .transfer_bytes = 0, // No additional data
            .reserved = undefined,
        };

        // Initialize header fields
        @memset(std.mem.asBytes(&status_cmd), 0);
        _ = try std.fmt.bufPrint(&status_cmd.model, "PCD-400A", .{});

        // Send status command
        try pcd.usbSendCmd(std.mem.asBytes(&status_cmd));

        // Receive response
        var status_response: ResponseHeader = undefined;
        _ = try pcd.usbReceiveCmd(std.mem.asBytes(&status_response));

        // Check AD conversion status bits per manual section 4-3:
        // 0x00000001 - AD conversion start available
        // 0x00000002 - During AD conversion (measurements)
        // Expected combined state is 0x00000003 when running
        if (status_response.pcd_status & 0x00000003 != 0x00000003) {
            std.debug.print("Invalid AD conversion state. PCD Status: 0x{X:0>8}\n", .{status_response.pcd_status});
            if (status_response.pcd_status & 0x00000001 == 0) {
                std.debug.print("AD conversion start not available\n", .{});
            }
            if (status_response.pcd_status & 0x00000002 == 0) {
                std.debug.print("AD conversion not running\n", .{});
            }
            return error.AdConversionInvalidState;
        }

        // Check for error status bits per section 4-4
        if (status_response.pcd_error_status != 0) {
            std.debug.print("PCD Error Status: 0x{X:0>8}\n", .{status_response.pcd_error_status});
            // Check specific error bits
            if (status_response.pcd_error_status & 0x00000001 != 0) std.debug.print("Hardware Error\n", .{});
            if (status_response.pcd_error_status & 0x00000002 != 0) std.debug.print("EEPROM Error\n", .{});
            if (status_response.pcd_error_status & 0x00000004 != 0) std.debug.print("External SRAM Error\n", .{});
            if (status_response.pcd_error_status & 0x00000008 != 0) std.debug.print("FPGA Error\n", .{});
            if (status_response.pcd_error_status & 0x00000100 != 0) std.debug.print("Number of stacking PCD units Error\n", .{});
            if (status_response.pcd_error_status & 0x00000200 != 0) std.debug.print("Slave units are OFF\n", .{});
            return error.PcdError;
        }

        // Additional checks from the response header
        std.debug.print("\nStatus Check Results:\n", .{});
        std.debug.print("Sampling Frequency: {} Hz\n", .{status_response.sampling_frequency});
        std.debug.print("Number of Channels: {}\n", .{status_response.number_of_channels});
        std.debug.print("Number of Stacking PCDs: {}\n", .{status_response.number_of_stacking_pcd});

        // Print active channels based on measuring_channel_bit
        printActiveChannels(status_response.measuring_channel_bit);

        self.is_running.store(true, .monotonic);
        self.acquisition_thread = try std.Thread.spawn(.{}, acquisitionLoop, .{self});
    }

    pub fn stop(self: *ContinuousDataAcquisition) void {
        self.is_running.store(false, .monotonic);
        if (self.acquisition_thread) |thread| {
            thread.join();
            self.acquisition_thread = null;
        }
        _ = stopAdConversion() catch |err| {
            std.debug.print("Error stopping AD conversion: {}\n", .{err});
        };
    }

    fn parseGmdResponse(buffer: []const u8, conditions: *const MeasuringConditionFormat) ![]const i32 {
        _ = conditions;
        // Add more robust validation
        if (buffer.len < @sizeOf(ResponseHeader)) {
            std.debug.print("Buffer too small for header: got {}, need {}\n", .{ buffer.len, @sizeOf(ResponseHeader) });
            return error.BufferTooSmall;
        }

        const header = @as(*const ResponseHeader, @ptrCast(@alignCast(buffer.ptr)));

        // Validate expected data size
        const expected_data_size = header.number_of_channels * @sizeOf(i32);
        const expected_total_size = @sizeOf(ResponseHeader) + expected_data_size;

        if (buffer.len != expected_total_size) {
            std.debug.print("Unexpected buffer size: got {}, expected {}\n", .{ buffer.len, expected_total_size });
            return error.UnexpectedBufferSize;
        }

        // Extract AD data with bounds checking
        const data_start = @sizeOf(ResponseHeader);
        const data_slice = buffer[data_start..];
        const ad_data = @as([*]const i32, @ptrCast(@alignCast(data_slice.ptr)))[0..header.number_of_channels];

        return ad_data;
    }

    fn processGmdData(self: *ContinuousDataAcquisition, raw_data: []const i32, timestamp: i128) !void {
        var sample = AdDataSample{
            .timestamp = timestamp,
            .channel_data = undefined,
            .raw_ad_data = undefined,
            .gage_factors = undefined,
        };

        // Initialize gage factors (could be loaded from configuration)
        @memset(&sample.gage_factors, DEFAULT_GAGE_FACTOR);

        // Process each channel
        for (0..@min(raw_data.len, MAX_CHANNELS)) |i| {
            sample.raw_ad_data[i] = raw_data[i];
            sample.channel_data[i] = convertAdValueToRange(raw_data[i], self.measuring_conditions.channel_conditions[i].range_no, self.measuring_conditions.channel_conditions[i].strain_mode_no, sample.gage_factors[i]);
        }

        // Store the sample in the circular buffer
        self.data_mutex.lock();
        defer self.data_mutex.unlock();

        if (!self.circular_buffer.push(sample)) {
            self.stats.buffer_overruns += 1;
        }
        self.stats.total_samples += 1;
    }

    fn acquisitionLoop(self: *ContinuousDataAcquisition) !void {
        // Status command
        var status_cmd = CommandHeader{};
        @memset(std.mem.asBytes(&status_cmd), 0);
        _ = try std.fmt.bufPrint(&status_cmd.model, "PCD-400A", .{});
        status_cmd.transfer_bytes = 0;
        try pcd.usbSendCmd(std.mem.asBytes(&status_cmd));
        var status_response: ResponseHeader = undefined;
        _ = try pcd.usbReceiveCmd(std.mem.asBytes(&status_response));

        std.debug.print("PCD Status: 0x{X:0>8}\n", .{status_response.pcd_status});
        std.debug.print("Error Status: 0x{X:0>8}\n", .{status_response.pcd_error_status});

        var cmd = GmdCommand{
            .header = CommandHeader{},
            .command = "GMD".*,
        };

        @memset(std.mem.asBytes(&cmd.header), 0);
        _ = try std.fmt.bufPrint(&cmd.header.model, "PCD-400A", .{});
        cmd.header.transfer_bytes = 3;

        // const active_channels = self.measuring_conditions.measuring_condition.number_of_channels;
        // const response_size = @sizeOf(ResponseHeader) + (active_channels * @sizeOf(i32));

        // // According to memo, we need periodic command calls between 100ms to 1sec
        // const command_interval_ns = 100 * std.time.ns_per_ms; // 100ms interval
        // var last_command_time = std.time.nanoTimestamp();

        while (self.is_running.load(.monotonic)) {
            // std.debug.print("AD Conversion started\n", .{});

            @memset(std.mem.asBytes(&cmd.header), 0);
            _ = try std.fmt.bufPrint(&cmd.header.model, "PCD-400A", .{});
            cmd.header.transfer_bytes = 3;

            // Buffer for 4 channels
            //const buffer_size = @sizeOf(ResponseHeader) + (1024 * @sizeOf(i32));

            // Run for 10 seconds
            const end_time = std.time.timestamp() + 10;
            var count: usize = 0;

            while (std.time.timestamp() < end_time) {
                // var response_buffer: [1024 * 8]u8 = undefined;
                // std.debug.print("\n=== GMD Command #{d} ===\n", .{count});

                // // Send GMD command
                // try pcd.usbSendCmd(std.mem.asBytes(&cmd));
                // std.debug.print("GMD command sent\n", .{});

                // // Receive response
                // const receive_size = try pcd.usbReceiveCmd(&response_buffer);
                // std.debug.print("Received {d} bytes\n", .{receive_size});

                var response_buffer: [1024 * 16]u8 = undefined;

                try pcd.usbSendCmd(std.mem.asBytes(&cmd));
                const receive_size = try pcd.usbReceiveCmd(&response_buffer);

                if (receive_size >= @sizeOf(ResponseHeader)) {
                    const header = @as(*const ResponseHeader, @ptrCast(@alignCast(&response_buffer)));
                    const data_start = @sizeOf(ResponseHeader);
                    const data_slice = response_buffer[data_start..@intCast(receive_size)];
                    const ad_data = @as([*]const i32, @ptrCast(@alignCast(data_slice.ptr)))[0..header.number_of_channels];

                    try self.processGmdData(ad_data, std.time.nanoTimestamp());
                }

                // Print response as hex for debugging
                //printHexView("Response", response_buffer[0..@intCast(receive_size)]);
                // std.time.sleep(100 * std.time.ns_per_ms); // 100ms interval
                count += 1;
            }

            // Stop AD conversion
            // try stopAdConversion();
            std.debug.print("AD Conversion stopped\n", .{});
        }
    }

    pub fn getSamples(self: *ContinuousDataAcquisition, buffer: []AdDataSample) usize {
        self.data_mutex.lock();
        defer self.data_mutex.unlock();

        var count: usize = 0;
        while (count < buffer.len) {
            if (self.circular_buffer.pop()) |sample| {
                buffer[count] = sample;
                count += 1;
            } else {
                break;
            }
        }
        return count;
    }

    pub fn getStats(self: *ContinuousDataAcquisition) DataAcquisitionStats {
        return self.stats;
    }
};

// GMD Command structures (similar to other command structures in your existing code)
const GmdCommand = extern struct {
    header: CommandHeader, // 64 bytes
    command: [3]u8, // 3 bytes for "GMD"
};

const GmdResponse = extern struct {
    header: ResponseHeader,
    data: [16]i32, // Assuming 16 possible channels
};

fn printBuffer(label: []const u8, buffer: []const u8) void {
    std.debug.print("{s}: ", .{label});
    for (buffer) |byte| {
        std.debug.print("0x{X:0>2} ", .{byte}); // Print each byte as a decimal first

    }
    std.debug.print("\n", .{});
}

fn printSysInformations() !u8 {

    // Prepare SYS command
    var sys_cmd = SysCommand{
        .header = CommandHeader{},
        .command = "SYS".*,
    };

    // Initialize header
    @memset(&sys_cmd.header.model, 0);
    @memset(&sys_cmd.header.reserved, 0);
    _ = try std.fmt.bufPrint(&sys_cmd.header.model, "PCD-400A", .{});
    sys_cmd.header.transfer_bytes = 3; // Command length (SYS)

    // printBuffer("sys command", std.mem.asBytes(&sys_cmd));

    // Send command
    try pcd.usbSendCmd(std.mem.asBytes(&sys_cmd));

    // Receive complete response (header + data) in one operation
    var response: SysResponse = undefined;
    const retSysResponseSize: i32 = try pcd.usbReceiveCmd(std.mem.asBytes(&response));

    std.debug.print("receive sys command response size {any}\n", .{retSysResponseSize});

    // Check for errors in header
    if (response.header.pcd_error_status != 0) {
        std.debug.print("Error: PCD reported error status: 0x{X:0>8}\n", .{response.header.pcd_error_status});
        return error.PcdError;
    }

    // Verify response size matches expected
    if (retSysResponseSize != @sizeOf(SysResponse)) {
        std.debug.print("Unexpected response size: {} (expected {})\n", .{ retSysResponseSize, @sizeOf(SysResponse) });
        return error.UnexpectedResponseSize;
    }

    // printBuffer("sys command receive", std.mem.asBytes(&response));
    for (response.data) |data| {
        std.debug.print("Model: {s}\n", .{std.mem.sliceTo(&data.model, 0)});
        std.debug.print("Firmware version: {s}\n", .{std.mem.sliceTo(&data.firmware_version, 0)});
        std.debug.print("FPGA version: {s}\n", .{std.mem.sliceTo(&data.fpga_version, 0)});
        std.debug.print("USB Driver version: {s}\n", .{std.mem.sliceTo(&data.usb_driver_version, 0)});
        std.debug.print("Serial no: {s}\n", .{std.mem.sliceTo(&data.serial_no, 0)});
        std.debug.print("Reserved 1: {s}\n", .{std.mem.sliceTo(&data.reserved1, 0)});
        // std.debug.print("Model: {s}\n", .{std.mem.sliceTo(&data.model_byte, 0)});
        std.debug.print("Reserved 2: {s}\n", .{std.mem.sliceTo(&data.reserved2, 0)});
    }

    // Print header information
    std.debug.print("\nResponse Header Information:\n", .{});
    std.debug.print("Device Model: {s}\n", .{std.mem.sliceTo(&response.header.model, 0)});
    std.debug.print("Response Data Size: {} bytes\n", .{response.header.response_data_bytes});
    std.debug.print("PCD Status: 0x{X:0>8}\n", .{response.header.pcd_status});
    std.debug.print("Error Status: 0x{X:0>8}\n", .{response.header.pcd_error_status});
    std.debug.print("Sampling Frequency: {} Hz\n", .{response.header.sampling_frequency});
    std.debug.print("Measuring channel bit: {} Hz\n", .{response.header.measuring_channel_bit});
    std.debug.print("Number of Channels: {}\n", .{response.header.number_of_channels});
    std.debug.print("Number of Stacking PCDs: {}\n", .{response.header.number_of_stacking_pcd});

    return 0;
}

// Balance Adjustment Command Structures
const BalCommand = extern struct {
    header: CommandHeader,
    command: [3]u8, // "BAL"
    parameter_mode: u8, // 0x01 for Execute
};

const BalResponse = extern struct {
    header: ResponseHeader,
    status: u8, // Standard response
};

const BalResultResponse = extern struct {
    header: ResponseHeader,
    results: [16]i8, // Balance adjustment results for 16 channels
    reserved: [16]u8,
};

pub fn executeBalanceAdjustment() !void {
    std.debug.print("Executing Balance Adjustment for all channels...\n", .{});

    // Prepare Balance Adjustment Command
    var bal_cmd = BalCommand{
        .header = CommandHeader{},
        .command = "BAL".*,
        .parameter_mode = 0x01, // Execute balance adjustment
    };

    // Initialize header
    @memset(&bal_cmd.header.model, 0);
    @memset(&bal_cmd.header.reserved, 0);
    _ = try std.fmt.bufPrint(&bal_cmd.header.model, "PCD-400A", .{});
    bal_cmd.header.transfer_bytes = 4; // Command length

    // Send balance adjustment command
    try pcd.usbSendCmd(std.mem.asBytes(&bal_cmd));

    // Receive initial response
    var initial_response: BalResponse = undefined;
    _ = try pcd.usbReceiveCmd(std.mem.asBytes(&initial_response));

    // Check for errors in initial response
    if (initial_response.header.pcd_error_status != 0) {
        std.debug.print("Error during balance adjustment initiation. Error status: 0x{X:0>8}\n", .{initial_response.header.pcd_error_status});
        return error.BalanceAdjustmentError;
    }

    // Wait for command execution to complete
    var wait_attempts: u8 = 0;
    const max_attempts = 50; // Adjust as needed
    while (wait_attempts < max_attempts) : (wait_attempts += 1) {
        // Send a command to check status (you can use any command that returns status)
        var status_cmd = SysCommand{
            .header = CommandHeader{},
            .command = "SYS".*,
        };

        // Initialize header
        @memset(&status_cmd.header.model, 0);
        @memset(&status_cmd.header.reserved, 0);
        _ = try std.fmt.bufPrint(&status_cmd.header.model, "PCD-400A", .{});
        status_cmd.header.transfer_bytes = 3; // Command length

        // Send command
        try pcd.usbSendCmd(std.mem.asBytes(&status_cmd));

        // Receive status response
        var status_response: SysResponse = undefined;
        _ = try pcd.usbReceiveCmd(std.mem.asBytes(&status_response));

        // Check if command execution is complete
        // 0x00010000 is the bit indicating "Executing the command"
        if (status_response.header.pcd_status & 0x00010000 == 0) {
            break;
        }

        // Wait a short time before next status check
        std.time.sleep(100 * std.time.ns_per_ms); // 100ms delay
    }

    if (wait_attempts >= max_attempts) {
        std.debug.print("Timeout waiting for balance adjustment to complete\n", .{});
        return error.BalanceAdjustmentTimeout;
    }

    // Now load balance adjustment results
    var bal_load_cmd = BalCommand{
        .header = CommandHeader{},
        .command = "BAL".*,
        .parameter_mode = 0x00, // Load balance adjustment results
    };

    // Initialize header for load command
    @memset(&bal_load_cmd.header.model, 0);
    @memset(&bal_load_cmd.header.reserved, 0);
    _ = try std.fmt.bufPrint(&bal_load_cmd.header.model, "PCD-400A", .{});
    bal_load_cmd.header.transfer_bytes = 4; // Command length

    // Send load results command
    try pcd.usbSendCmd(std.mem.asBytes(&bal_load_cmd));

    // Receive balance adjustment results
    var results_response: BalResultResponse = undefined;
    _ = try pcd.usbReceiveCmd(std.mem.asBytes(&results_response));

    // Check for errors in results
    if (results_response.header.pcd_error_status != 0) {
        std.debug.print("Error loading balance adjustment results. Error status: 0x{X:0>8}\n", .{results_response.header.pcd_error_status});
        return error.BalanceAdjustmentError;
    }

    // Print balance adjustment results
    std.debug.print("\n=== Balance Adjustment Results ===\n", .{});
    for (results_response.results, 0..) |result, i| {
        const result_str = switch (result) {
            -1 => "No unit/No function/No target channel",
            0 => "Passed",
            1 => "Error",
            2 => "OFF",
            3 => "Connection error",
            else => "Unknown status",
        };
        std.debug.print("Channel {}: {s} ({})\n", .{ i + 1, result_str, result });
    }
    printHexView("\n=== Balance Adjustment Results as HEX ===\n", std.mem.asBytes(&results_response));
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // std.debug.print("Performing USB Target Reset...\n", .{});
    // try pcd.usbTargetReset(); // Add target reset at the beginning

    std.debug.print("Opening USB connection...\n", .{});

    try pcd.usbOpen();
    defer pcd.usbClose() catch |err| {
        std.debug.print("Error closing USB: {}\n", .{err});
    };

    std.debug.print("Checking connection...\n", .{});
    const connected = try pcd.usbConnectCheck();
    std.debug.print("Connected: {}\n", .{connected});

    const sysinfo_status = try printSysInformations();
    std.debug.print("Printing System Informations: {}\n", .{sysinfo_status});

    const config = try loadChannelConfig("channel_config.csv");

    // const sampling_frequency = config.measuring_condition.sampling_frequency;
    const active_channels = config.measuring_condition.number_of_channels;

    // Print the loaded configuration for verification
    printChannelConfig(&config);
    // First initialize pcd as master

    var ini_cmd = IniCommand{
        .header = CommandHeader{},
        .command = "INI".*,
        .parameter_mode = 0xFF,
    };

    // Initialize header
    @memset(&ini_cmd.header.model, 0);
    @memset(&ini_cmd.header.reserved, 0);
    _ = try std.fmt.bufPrint(&ini_cmd.header.model, "PCD-400A", .{});
    ini_cmd.header.transfer_bytes = 4; // Command length (SYS)

    // Send command
    try pcd.usbSendCmd(std.mem.asBytes(&ini_cmd));

    // // Receive complete response (header + data) in one operation
    var iniResp: IniResponse = undefined;
    const retIniResponseSize = pcd.usbReceiveCmd(std.mem.asBytes(&iniResp));

    std.debug.print("\nResponse Header Information:\n", .{});
    std.debug.print("Device Model: {s}\n", .{std.mem.sliceTo(&iniResp.header.model, 0)});
    std.debug.print("Response Data Size: {} bytes\n", .{iniResp.header.response_data_bytes});
    std.debug.print("PCD Status: 0x{X:0>8}\n", .{iniResp.header.pcd_status});
    std.debug.print("Error Status: 0x{X:0>8}\n", .{iniResp.header.pcd_error_status});
    std.debug.print("Sampling Frequency: {} Hz\n", .{iniResp.header.sampling_frequency});

    std.debug.print("receive ini command response size {any}", .{retIniResponseSize});

    printBuffer("ini command", std.mem.asBytes(&iniResp));

    // First, load current conditions to see current state
    // Load new conditions from file

    // // Print current conditions
    // std.debug.print("\nCurrent sampling frequency: {} Hz\n", .{current_conditions.measuring_condition.sampling_frequency});
    // std.debug.print("Current number of channels: {}\n", .{current_conditions.measuring_condition.number_of_channels});

    // // Create and set new conditions
    // std.debug.print("\nSetting new measuring conditions...\n", .{});
    // var new_conditions = createDefaultMeasuringConditions();
    // new_conditions.measuring_condition.sampling_frequency = 2000; // 2kHz
    // new_conditions.measuring_condition.number_of_channels = 2; // 2 channels
    // for (&new_conditions.channel_conditions) |*channel| {
    //     channel.measurement_on_off = 1;
    //     channel.mode = 0;
    //     channel.range_no = 4;
    //     channel.strain_mode_no = 0;
    //     channel.lpf_no = 0;
    //     channel.hpf_no = 0;
    //     channel.bal_on_off = 1;
    // }

    // Load and set new conditions from file
    // std.debug.print("\nLoading and setting new conditions from file...\n", .{});
    // const new_conditions = try loadChannelConfig("channel_config.csv");
    // Load the current measuring conditions

    // Set measuring conditions with more robust error handling
    setMeasuringConditions(config) catch |err| {
        std.debug.print("Failed to set measuring conditions: {any}\n", .{err});
        return err;
    };

    std.debug.print("New measuring conditions set successfully!\n", .{});

    const current_conditions = try loadMeasuringConditions();

    // Print the loaded conditions
    printChannelConfig(&current_conditions);

    printHexView("Current Measuring Conditions", std.mem.asBytes(&current_conditions));

    // Execute balance adjustment before starting data acquisition
    try executeBalanceAdjustment();

    std.time.sleep(1 * std.time.ns_per_s); // Wait for balance adjustment to complete

    // Set up data acquisition
    const acq_config = DataAcquisitionConfig{
        .sample_interval_ns = @divFloor(std.time.ns_per_s, 5000),
        .buffer_size = 10000,
        .max_retries = 5,
    };

    // Initialize data acquisition with configuration
    var acquisition = try ContinuousDataAcquisition.init(allocator, acq_config, config // Pass the loaded configuration
    );
    defer acquisition.deinit();

    // Create CSV file for data recording
    var csv_file = try std.fs.cwd().createFile("measurement_data.csv", .{});
    defer csv_file.close();

    // Write CSV header with strain units
    try csv_file.writer().print("Timestamp", .{});
    for (0..active_channels) |i| {
        try csv_file.writer().print(",CH{}_Strain(μm/m)", .{i + 1});
    }
    try csv_file.writer().print("\n", .{});

    // Initialize TCP server
    var tcp_server = try AdDataServer.init(allocator, acquisition);
    defer tcp_server.deinit();

    // Start data acquisition
    try acquisition.start();
    std.debug.print("Data acquisition started...\n", .{});

    // Set measurement duration
    const start_time = std.time.timestamp();
    const measurement_duration_s: i64 = 10; // 60 seconds measurement

    // Sample buffer
    var sample_buffer: [1000]AdDataSample = undefined;

    // Main data collection loop
    while (true) {
        const current_time = std.time.timestamp();
        if (current_time - start_time >= measurement_duration_s) break;

        // Retrieve samples
        const samples_read = acquisition.getSamples(&sample_buffer);
        if (samples_read > 0) {
            // Process and save samples
            for (sample_buffer[0..samples_read]) |sample| {
                // Write timestamp
                try csv_file.writer().print("{}", .{sample.timestamp});

                // Write converted strain values for each channel
                for (0..active_channels) |ch| {
                    const strain_value = sample.channel_data[ch];
                    try csv_file.writer().print(",{d:.3}", .{strain_value});
                }
                try csv_file.writer().print("\n", .{});
            }

            // Print stats every 1000 samples
            if (acquisition.getStats().total_samples % 1000 == 0) {
                const stats = acquisition.getStats();
                std.debug.print("\rSamples: {d}, Overruns: {d}, Errors: {d}", .{
                    stats.total_samples,
                    stats.buffer_overruns,
                    stats.comm_errors,
                });
            }
        }

        // Small delay to prevent tight loop
        std.time.sleep(10 * std.time.ns_per_ms);
    }

    // Start TCP server in a separate thread
    _ = try std.Thread.spawn(.{}, AdDataServer.start, .{ tcp_server, 8000 });

    // Set measurement duration
    // const start_time = std.time.timestamp();
    const measurement_duration_serv: i64 = 3600; // Run for 1 hour
    var last_stats_time = start_time;

    while (true) {
        const current_time = std.time.timestamp();
        if (current_time - start_time >= measurement_duration_serv) break;

        // Print stats every 5 seconds
        if (current_time - last_stats_time >= 5) {
            const stats = acquisition.getStats();
            std.debug.print("\rSamples: {d}, Overruns: {d}, Errors: {d}", .{
                stats.total_samples,
                stats.buffer_overruns,
                stats.comm_errors,
            });
            last_stats_time = current_time;
        }

        std.time.sleep(100 * std.time.ns_per_ms); // Sleep for 100ms
    }

    // Stop acquisition and print final statistics
    std.debug.print("\nStopping data acquisition...\n", .{});
    acquisition.stop();

    // Stop acquisition and print final statistics
    std.debug.print("\nStopping data acquisition...\n", .{});
    acquisition.stop();

    const final_stats = acquisition.getStats();
    std.debug.print("\nFinal Statistics:\n", .{});
    std.debug.print("Total Samples: {d}\n", .{final_stats.total_samples});
    std.debug.print("Buffer Overruns: {d}\n", .{final_stats.buffer_overruns});
    std.debug.print("Communication Errors: {d}\n", .{final_stats.comm_errors});
    if (final_stats.last_error) |err| {
        std.debug.print("Last Error: {}\n", .{err});
    }

    try pcd.usbClose();
}
