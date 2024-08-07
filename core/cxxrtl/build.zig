const std = @import("std");

pub fn build(b: *std.Build) void {
    const yosys_data_dir = b.option([]const u8, "yosys_data_dir", "yosys data dir (per yosys-config --datdir)") orelse @import("zxxrtl").guessYosysDataDir(b);
    const cxxrtl_o_paths = b.option([][]const u8, "cxxrtl_o_path", "path to .o file to link against") orelse
        &[_][]const u8{"../build/cxxrtl/avacore.o"};
    const clock_hz = b.option(usize, "clock_hz", "clock speed the gateware is elaborated at in Hz") orelse 1_000_000;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "cxxrtl",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibCpp();

    const zxxrtl_mod = b.dependency("zxxrtl", .{
        .target = target,
        .optimize = optimize,
        .yosys_data_dir = yosys_data_dir,
    }).module("zxxrtl");
    exe.root_module.addImport("zxxrtl", zxxrtl_mod);

    for (cxxrtl_o_paths) |cxxrtl_o_path| {
        exe.addObjectFile(b.path(cxxrtl_o_path));
    }

    const options = b.addOptions();
    options.addOption(usize, "clock_hz", clock_hz);
    exe.root_module.addOptions("options", options);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
