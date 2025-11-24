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

    // 3-team arena simulation
    const sim_3team = b.addExecutable(.{
        .name = "sim-3team-arena",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/sim_3team_arena.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    sim_3team.linkLibrary(raylib_dep.artifact("raylib"));
    sim_3team.root_module.addImport("raylib", raylib_dep.module("raylib"));

    b.installArtifact(sim_3team);

    const sim_3team_cmd = b.addRunArtifact(sim_3team);
    sim_3team_cmd.step.dependOn(b.getInstallStep());

    const sim_3team_step = b.step("sim-3team", "Run 3-team arena battle simulation");
    sim_3team_step.dependOn(&sim_3team_cmd.step);

    // SimulationFactory test suite
    const test_factory = b.addExecutable(.{
        .name = "test-simulation-factory",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_simulation_factory.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    test_factory.linkLibrary(raylib_dep.artifact("raylib"));
    test_factory.root_module.addImport("raylib", raylib_dep.module("raylib"));

    b.installArtifact(test_factory);

    const test_factory_cmd = b.addRunArtifact(test_factory);
    test_factory_cmd.step.dependOn(b.getInstallStep());

    const test_factory_step = b.step("test-factory", "Run SimulationFactory test suite with multiple scenarios");
    test_factory_step.dependOn(&test_factory_cmd.step);

    // Balance iteration test
    const balance_test = b.addExecutable(.{
        .name = "balance-test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/balance_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    balance_test.linkLibrary(raylib_dep.artifact("raylib"));
    balance_test.root_module.addImport("raylib", raylib_dep.module("raylib"));

    b.installArtifact(balance_test);

    const balance_test_cmd = b.addRunArtifact(balance_test);
    balance_test_cmd.step.dependOn(b.getInstallStep());

    const balance_test_step = b.step("balance-test", "Run balance iteration tests comparing team compositions");
    balance_test_step.dependOn(&balance_test_cmd.step);

    // Batch testing framework
    const batch_test = b.addExecutable(.{
        .name = "batch-test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/batch_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    batch_test.linkLibrary(raylib_dep.artifact("raylib"));
    batch_test.root_module.addImport("raylib", raylib_dep.module("raylib"));

    b.installArtifact(batch_test);

    const batch_test_cmd = b.addRunArtifact(batch_test);
    batch_test_cmd.step.dependOn(b.getInstallStep());

    const batch_test_step = b.step("batch-test", "Run batch simulations and collect aggregate statistics");
    batch_test_step.dependOn(&batch_test_cmd.step);
}
