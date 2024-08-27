const std = @import("std");

pub fn build(b: *std.Build) void {
    var ab = AvaBasicBuild.init(b);
    ab.avabasic();
    ab.avacore();
}

const AvaBasicBuild = struct {
    const Self = @This();

    b: *std.Build,
    host_target: std.Build.ResolvedTarget,
    host_optimize: std.builtin.OptimizeMode,
    test_step: *std.Build.Step,

    fn init(b: *std.Build) Self {
        const host_target = b.standardTargetOptions(.{});
        const host_optimize = b.standardOptimizeOption(.{});

        const test_step = b.step("test", "Run unit tests");

        return .{
            .b = b,
            .host_target = host_target,
            .host_optimize = host_optimize,
            .test_step = test_step,
        };
    }

    fn avabasic(self: Self) void {
        const lib = self.b.addStaticLibrary(.{
            .name = "avabasic",
            .root_source_file = self.b.path("src/root.zig"),
            .target = self.host_target,
            .optimize = self.host_optimize,
        });
        self.b.installArtifact(lib);

        const zigargs = self.b.dependency("zig-args", .{
            .target = self.host_target,
            .optimize = self.host_optimize,
        });

        const exe = self.b.addExecutable(.{
            .name = "avabasic",
            .root_source_file = self.b.path("src/main.zig"),
            .target = self.host_target,
            .optimize = self.host_optimize,
        });
        exe.root_module.addImport("args", zigargs.module("args"));
        self.b.installArtifact(exe);

        const run_cmd = self.b.addRunArtifact(exe);
        run_cmd.step.dependOn(self.b.getInstallStep());
        if (self.b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = self.b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);

        const lib_unit_tests = self.b.addTest(.{
            .root_source_file = self.b.path("src/root.zig"),
            .target = self.host_target,
            .optimize = self.host_optimize,
        });
        self.test_step.dependOn(&self.b.addRunArtifact(lib_unit_tests).step);

        const exe_unit_tests = self.b.addTest(.{
            .root_source_file = self.b.path("src/main.zig"),
            .target = self.host_target,
            .optimize = self.host_optimize,
        });
        self.test_step.dependOn(&self.b.addRunArtifact(exe_unit_tests).step);
    }

    fn avacore(self: Self) void {
        const core_target = self.b.resolveTargetQuery(.{
            .cpu_arch = .riscv32,
            .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 },
            .os_tag = .freestanding,
        });
        const core = self.b.addExecutable(.{
            .name = "avacore",
            .root_source_file = self.b.path("src/core/main.zig"),
            .target = core_target,
            .optimize = .ReleaseSafe,
            // .optimize = .ReleaseSmall,
        });
        core.root_module.code_model = .medium;
        core.setLinkerScript(self.b.path("src/core/core.ld"));
        core.setVerboseLink(true);
        core.entry = .disabled;
        core.addAssemblyFile(self.b.path("src/core/crt0.S"));
        const core_inst = self.b.addInstallArtifact(core, .{ .dest_dir = .{ .override = .bin } });

        const core_imem_bin = self.b.addSystemCommand(&.{
            "llvm-objcopy",
            "--output-target=binary",
            "-j",
            ".text",
            "zig-out/bin/avacore",
            "zig-out/bin/avacore.imem.bin",
        });
        core_imem_bin.step.dependOn(&core_inst.step);
        self.b.getInstallStep().dependOn(&core_imem_bin.step);

        const core_dmem_bin = self.b.addSystemCommand(&.{
            "llvm-objcopy",
            "--output-target=binary",
            "-j",
            ".data",
            "zig-out/bin/avacore",
            "zig-out/bin/avacore.dmem.bin",
        });
        core_dmem_bin.step.dependOn(&core_inst.step);
        self.b.getInstallStep().dependOn(&core_dmem_bin.step);

        const core_unit_tests = self.b.addTest(.{
            .root_source_file = self.b.path("src/core.zig"),
            .target = self.host_target,
            .optimize = self.host_optimize,
        });
        self.test_step.dependOn(&self.b.addRunArtifact(core_unit_tests).step);
    }
};
