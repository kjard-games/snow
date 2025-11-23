const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "snow",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibrary(raylib_dep.artifact("raylib"));
    exe.root_module.addImport("raylib", raylib_dep.module("raylib"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Headless battle simulation test
    const sim_test = b.addExecutable(.{
        .name = "test-simulation",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_simulation.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    sim_test.linkLibrary(raylib_dep.artifact("raylib"));
    sim_test.root_module.addImport("raylib", raylib_dep.module("raylib"));

    b.installArtifact(sim_test);

    const test_cmd = b.addRunArtifact(sim_test);
    test_cmd.step.dependOn(b.getInstallStep());

    const test_step = b.step("test-sim", "Run headless AI vs AI battle simulation");
    test_step.dependOn(&test_cmd.step);
}
