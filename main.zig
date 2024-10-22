const std = @import("std");
const pcd = @import("pcd400.zig");

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
    reserved: [26]u8,
};

const ChannelCondition = extern struct {
    measurement_on_off: i8, // -1: No unit, 0: Not measure, 1: Measure
    mode: u8, // Fixed to 0 for PCD-400 A/B
    range_no: u8,
    strain_mode_no: u8,
    lpf_no: u8,
    hpf_no: u8,
    bal_on_off: u8, // 0: OFF, 1: ON
    reserved: [25]u8,
};

// Measuring condition format structures
const GeneralInformation = extern struct {
    device_id: [20]u8, // "PCD-400A" fixed
    parameter_format_version: u16, // 1 fixed
    reserved1: [2]u8,
    model: [8]u8, // Model 1 to 4
    reserved2: [48]u8,
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
    header: CommandHeader,
    command: [3]u8, // "MES"
    parameter_mode: u8, // 0x00 for Load
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

fn printActiveChannels(channel_bit: u32) void {
    std.debug.print("Active channels: ", .{});
    var i: u5 = 0;
    while (i < 32) : (i += 1) {
        if (channel_bit & (@as(u32, 1) << i) != 0) {
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

    // Set default measuring condition
    conditions.measuring_condition.sampling_frequency = 1000; // 1kHz
    conditions.measuring_condition.number_of_channels = 1; // 1 channel

    conditions.measuring_condition.sampling_frequency = 5000; // 5.kHz
    conditions.measuring_condition.number_of_channels = 4; // 4 channel

    // Set default channel conditions
    for (conditions.channel_conditions) |channel| {
        const channelPtr = &channel; // Get a pointer to the channel
        channelPtr.measurement_on_off = 1; // Measure
        channelPtr.mode = 0; // Fixed for PCD-400 A/B Strain
        channelPtr.range_no = 4; // 4 5000 µm/m 20V
        channelPtr.strain_mode_no = 0; // 0 1G2W
        channelPtr.lpf_no = 0; // 0 FLAT FLAT
        channelPtr.hpf_no = 0; // 0 OFF
        channelPtr.bal_on_off = 0; // OFF
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

pub fn setMeasuringConditions(conditions: MeasuringConditionFormat) !void {
    var cmd = MesSetCommand{
        .header = CommandHeader{},
        .command = "MES".*,
        .parameter_mode = 0x01,
        .measuring_conditions = conditions,
    };

    // Initialize header
    @memset(&cmd.header.model, 0);
    @memset(&cmd.header.reserved, 0);
    _ = try std.fmt.bufPrint(&cmd.header.model, "PCD-400A", .{});
    cmd.header.transfer_bytes = 1604; // 3 + 1 + 1600 bytes

    // Send command
    try pcd.usbSendCmd(std.mem.asBytes(&cmd));

    // Receive response
    var response: MesSetResponse = undefined;
    const retSetMesResponseSize = pcd.usbReceiveCmd(std.mem.asBytes(&response));

    std.debug.print("set meas command response size {any}", .{retSetMesResponseSize});

    // Check response
    if (response.header.pcd_error_status != 0) {
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

pub fn startAdConversion() !u8 {
    var cmd = StartAdConversionCommand{
        .header = CommandHeader{},
        .command = "STA".*,
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

    std.debug.print("start ad conversion response size {any}", .{retAdConversionCommand});

    // Check for errors
    if (response.header.pcd_error_status != 0) {
        return error.PcdError;
    } else {
        std.debug.print("received start ad command {}", .{response.status});
    }

    return response.status; // Return the status of the conversion
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

fn printBuffer(label: []const u8, buffer: []const u8) void {
    std.debug.print("{s}: ", .{label});
    for (buffer) |byte| {
        std.debug.print("0x{X:0>2} ", .{byte}); // Print each byte as a decimal first

    }
    std.debug.print("\n", .{});
}

pub fn main() !void {
    std.debug.print("Opening USB connection...\n", .{});

    try pcd.usbOpen();
    defer pcd.usbClose() catch |err| {
        std.debug.print("Error closing USB: {}\n", .{err});
    };

    std.debug.print("Checking connection...\n", .{});
    const connected = try pcd.usbConnectCheck();
    std.debug.print("Connected: {}\n", .{connected});

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

    // First, load current conditions
    std.debug.print("\nLoading current measuring conditions...\n", .{});
    const current_conditions = try loadMeasuringConditions();

    // Print current conditions
    std.debug.print("\nCurrent sampling frequency: {} Hz\n", .{current_conditions.measuring_condition.sampling_frequency});
    std.debug.print("Current number of channels: {}\n", .{current_conditions.measuring_condition.number_of_channels});

    // // Create and set new conditions
    // std.debug.print("\nSetting new measuring conditions...\n", .{});
    // var new_conditions = createDefaultMeasuringConditions();
    // new_conditions.measuring_condition.sampling_frequency = 2000; // 2kHz
    // new_conditions.measuring_condition.number_of_channels = 2; // 2 channels
    // new_conditions.channel_conditions[0].measurement_on_off = 1; // Enable channel 1
    // new_conditions.channel_conditions[1].measurement_on_off = 1; // Enable channel 2

    // try setMeasuringConditions(new_conditions);
    // std.debug.print("New measuring conditions set successfully!\n", .{});

    // Start AD conversion
    std.debug.print("Starting AD conversion...\n", .{});
    const start_status = try startAdConversion();
    std.debug.print("AD Conversion started with status: {}\n", .{start_status});

    // Your logic for working with the AD conversion...

    // Stop AD conversion
    std.debug.print("Stopping AD conversion...\n", .{});
    const stop_status = try stopAdConversion();
    std.debug.print("AD Conversion stopped with status: {}\n", .{stop_status});

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

    printBuffer("sys command", std.mem.asBytes(&sys_cmd));

    // Send command
    try pcd.usbSendCmd(std.mem.asBytes(&sys_cmd));

    // Receive complete response (header + data) in one operation
    var response: SysResponse = undefined;
    const retSysResponseSize = pcd.usbReceiveCmd(std.mem.asBytes(&response));

    std.debug.print("receive sys command response size {any}", .{retSysResponseSize});

    printBuffer("sys command receive", std.mem.asBytes(&response));

    // var modelVar: [32]u8 = undefined;
    // const retModelSize = pcd.usbReceiveCmd(std.mem.asBytes(&modelVar));

    // std.debug.print("receive model response size {any}", .{retModelSize});

    // printBuffer("sys command receive", std.mem.asBytes(&modelVar));

    for (response.data) |data| {
        // _ = pcd;
        std.debug.print("Model: {s}\n", .{std.mem.sliceTo(&data.model, 0)});
        std.debug.print("Firmware version: {s}\n", .{std.mem.sliceTo(&data.firmware_version, 0)});
    }

    // Print header information
    std.debug.print("\nResponse Header Information:\n", .{});
    std.debug.print("Device Model: {s}\n", .{std.mem.sliceTo(&response.header.model, 0)});
    std.debug.print("Response Data Size: {} bytes\n", .{response.header.response_data_bytes});
    std.debug.print("PCD Status: 0x{X:0>8}\n", .{response.header.pcd_status});
    std.debug.print("Error Status: 0x{X:0>8}\n", .{response.header.pcd_error_status});
    std.debug.print("Sampling Frequency: {} Hz\n", .{response.header.sampling_frequency});
    std.debug.print("Measuring channel bit: {} Hz\n", .{response.header.measuring_channel_bit});
    // printActiveChannels(response.header.measuring_channel_bit);
    std.debug.print("Number of Channels: {}\n", .{response.header.number_of_channels});
    std.debug.print("Number of Stacking PCDs: {}\n", .{response.header.number_of_stacking_pcd});

    // Check for errors in header
    // if (response.header.pcd_error_status != 0) {
    //     std.debug.print("Error: PCD reported error status: 0x{X:0>8}\n", .{response.header.pcd_error_status});
    //     return error.PcdError;
    // }

    // // Verify response size matches expected
    // if (response.header.response_data_bytes != @sizeOf(SysResponseData)) {
    //     std.debug.print("Unexpected response size: {} (expected {})\n", .{ response.header.response_data_bytes, @sizeOf(SysResponseData) });
    //     return error.UnexpectedResponseSize;
    // }

    // Print system information
    // std.debug.print("\nSystem Information:\n", .{});
    // std.debug.print("Model: {s}\n", .{std.mem.sliceTo(&response.data.model, 0)});
    // std.debug.print("Firmware Version: {s}\n", .{std.mem.sliceTo(&response.data.firmware_version, 0)});
    // std.debug.print("FPGA Version: {s}\n", .{std.mem.sliceTo(&response.data.fpga_version, 0)});
    // std.debug.print("USB Driver Version: {s}\n", .{std.mem.sliceTo(&response.data.usb_driver_version, 0)});
    // std.debug.print("Serial Number: {s}\n", .{std.mem.sliceTo(&response.data.serial_no, 0)});
    // std.debug.print("Model Byte: 0x{X:0>2}\n", .{response.data.model_byte});
}
