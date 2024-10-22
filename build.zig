const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "pcd400_test",
        .root_source_file = .{ .path = "main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Add C library
    exe.linkLibC();

    // Add the PCD400 library
    exe.addLibraryPath(.{ .path = "." }); // Look for libraries in current directory
    exe.addIncludePath(.{ .path = "." }); // Look for headers in current directory

    // Link with pcd400.lib
    exe.addObjectFile(.{ .path = "Pcd400.lib" });

    // Install the artifact
    b.installArtifact(exe);

    // Add run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
