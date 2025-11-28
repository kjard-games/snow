//! Test program for SimulationFactory - demonstrates different simulation configurations
//! Usage: zig build test-factory
//!
//! This showcases:
//! - Single battle with full scoreboard
//! - Batch testing for balance analysis
//! - Different verbosity levels

const std = @import("std");
const rl = @import("raylib");
const simulation_factory = @import("simulation_factory.zig");
const entity = @import("entity.zig");
const game_state = @import("game_state.zig");
const telemetry = @import("telemetry.zig");

const SimulationFactory = simulation_factory.SimulationFactory;
const SimulationRunner = simulation_factory.SimulationRunner;
const Verbosity = simulation_factory.Verbosity;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize RNG and ID generator
    const seed: u64 = @bitCast(std.time.timestamp());
    var prng = std.Random.DefaultPrng.init(seed);
    var rng = prng.random();
    var id_gen = entity.EntityIdGenerator{};

    std.debug.print("\n\x1b[36m╔════════════════════════════════════════════════════════════╗\x1b[0m\n", .{});
    std.debug.print("\x1b[36m║\x1b[0m \x1b[1m         SNOW BATTLE SIMULATION TEST SUITE              \x1b[0m \x1b[36m║\x1b[0m\n", .{});
    std.debug.print("\x1b[36m╚════════════════════════════════════════════════════════════╝\x1b[0m\n", .{});

    // ==========================================================================
    // TEST 1: Single 4v4 Battle with Full Output
    // ==========================================================================
    std.debug.print("\n\x1b[33m━━━ TEST 1: 4v4 Battle (Normal Verbosity) ━━━\x1b[0m\n", .{});

    {
        var factory = SimulationFactory.init(allocator, &rng, &id_gen);
        defer factory.deinit();

        const context = try factory
            .withTeamCount(2)
            .withCharactersPerTeam(4)
            .withMaxTicks(6000)
            .withVerbosity(.normal)
            .withTelemetryFile("match_telemetry_4v4.json")
            .build();

        var runner = SimulationRunner.init(context, factory.config);
        _ = try runner.run();
        runner.deinit();
    }

    // ==========================================================================
    // TEST 2: 2v2 Skirmish with Verbose Output (Combat Feed)
    // ==========================================================================
    std.debug.print("\n\x1b[33m━━━ TEST 2: 2v2 Skirmish (Verbose - Combat Feed) ━━━\x1b[0m\n", .{});

    {
        var factory = SimulationFactory.init(allocator, &rng, &id_gen);
        defer factory.deinit();

        const context = try factory
            .withTeamCount(2)
            .withCharactersPerTeam(2)
            .withMaxTicks(3000)
            .withVerbosity(.verbose)
            .withTelemetryFile("match_telemetry_2v2.json")
            .build();

        var runner = SimulationRunner.init(context, factory.config);
        _ = try runner.run();
        runner.deinit();
    }

    // ==========================================================================
    // TEST 3: Quick 3v3 (Quiet Mode)
    // ==========================================================================
    std.debug.print("\n\x1b[33m━━━ TEST 3: 3v3 Battle (Quiet Mode) ━━━\x1b[0m\n", .{});

    {
        var factory = SimulationFactory.init(allocator, &rng, &id_gen);
        defer factory.deinit();

        const context = try factory
            .withTeamCount(2)
            .withCharactersPerTeam(3)
            .withMaxTicks(5000)
            .withVerbosity(.quiet)
            .withJsonExport(false)
            .build();

        var runner = SimulationRunner.init(context, factory.config);
        const result = try runner.run();
        runner.deinit();

        // Can still access result programmatically
        std.debug.print("  (Duration was {d} ticks)\n", .{result.duration_ticks});
    }

    // ==========================================================================
    // TEST 4: Batch Testing (10 quick battles)
    // ==========================================================================
    std.debug.print("\n\x1b[33m━━━ TEST 4: Batch Testing (10x 4v4) ━━━\x1b[0m\n", .{});

    _ = try simulation_factory.batchBattle(allocator, &rng, &id_gen, 4, 10);

    // ==========================================================================
    // DONE
    // ==========================================================================
    std.debug.print("\x1b[32m╔════════════════════════════════════════════════════════════╗\x1b[0m\n", .{});
    std.debug.print("\x1b[32m║\x1b[0m \x1b[1m              All tests completed successfully!            \x1b[0m \x1b[32m║\x1b[0m\n", .{});
    std.debug.print("\x1b[32m╚════════════════════════════════════════════════════════════╝\x1b[0m\n\n", .{});
}
