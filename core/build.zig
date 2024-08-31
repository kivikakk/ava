const std = @import("std");

pub fn build(b: *std.Build) void {
    const host_target = b.standardTargetOptions(.{});
    const host_optimize = b.standardOptimizeOption(.{});

    const optimize: std.builtin.OptimizeMode =
        if (b.option(bool, "target-debug", "Include safety checks on target") orelse false)
        .ReleaseSafe
    else
        .ReleaseSmall;

    const test_step = b.step("test", "Run unit tests");

    _ = b.addModule("avacore", .{
        .root_source_file = b.path("src/mod.zig"),
        .target = host_target,
        .optimize = host_optimize,
    });
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/mod.zig"),
        .target = host_target,
        .optimize = host_optimize,
    });
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);

    const target = b.resolveTargetQuery(.{
        .cpu_arch = .riscv32,
        .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 },
        .os_tag = .freestanding,
        .cpu_features_add = std.Target.riscv.featureSet(&.{
            .c,
            .m,
            .zicsr,
        }),
    });
    const core = b.addExecutable(.{
        .name = "avacore",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    core.addAssemblyFile(b.path("src/crt0.S"));
    core.setLinkerScript(b.path("src/core.ld"));
    core.root_module.code_model = .medium;
    core.root_module.single_threaded = true;
    core.entry = .disabled;
    const core_inst = b.addInstallArtifact(core, .{ .dest_dir = .{ .override = .bin } });

    const avabasic_mod = b.dependency("avabasic", .{
        .target = target,
        .optimize = optimize,
    }).module("avabasic");
    core.root_module.addImport("avabasic", avabasic_mod);

    const imem_bin = b.addSystemCommand(&.{
        "llvm-objcopy",
        "--output-target=binary",
        "-j",
        ".text",
        b.fmt("{s}/bin/avacore", .{b.install_prefix}),
        b.fmt("{s}/bin/avacore.imem.bin", .{b.install_prefix}),
    });
    imem_bin.step.dependOn(&core_inst.step);
    b.getInstallStep().dependOn(&imem_bin.step);

    // TODO: look into b.addObjCopy.
    const dmem_bin = b.addSystemCommand(&.{
        "llvm-objcopy",
        "--output-target=binary",
        "-j",
        ".data",
        b.fmt("{s}/bin/avacore", .{b.install_prefix}),
        b.fmt("{s}/bin/avacore.dmem.bin", .{b.install_prefix}),
    });
    dmem_bin.step.dependOn(&core_inst.step);
    b.getInstallStep().dependOn(&dmem_bin.step);
}
