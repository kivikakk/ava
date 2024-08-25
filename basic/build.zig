const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "avabasic",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "avabasic",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);
    const zigargs = b.dependency("zig-args", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("args", zigargs.module("args"));

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const coreQuery = std.Target.Query{
        .cpu_arch = .riscv32,
        .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 },
        .os_tag = .freestanding,
    };
    const core = b.addObject(.{
        .name = "avacore",
        .root_source_file = b.path("src/core.zig"),
        .target = b.resolveTargetQuery(coreQuery),
        .optimize = .ReleaseSmall,
    });
    core.root_module.code_model = .small; // ?
    core.setLinkerScript(b.path("src/core.ld"));
    core.setVerboseLink(true);
    const coreInst = b.addInstallArtifact(core, .{ .dest_dir = .{ .override = .bin } });

    const coreBin = b.addSystemCommand(&.{
        "llvm-objcopy",
        "-j",
        ".text",
        "--output-target=binary",
        "zig-out/bin/avacore.o",
        "zig-out/bin/avacore.bin",
    });
    coreBin.step.dependOn(&coreInst.step);

    b.getInstallStep().dependOn(&coreBin.step);

    const core_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/core.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_core_unit_tests = b.addRunArtifact(core_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
    test_step.dependOn(&run_core_unit_tests.step);
}
