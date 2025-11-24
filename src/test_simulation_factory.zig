//! Test program for SimulationFactory - demonstrates different simulation configurations
//! Usage: zig build test-factory

const std = @import("std");
const rl = @import("raylib");
const simulation_factory = @import("simulation_factory.zig");
const entity = @import("entity.zig");
const game_state = @import("game_state.zig");
const telemetry = @import("telemetry.zig");

const SimulationFactory = simulation_factory.SimulationFactory;
const SimulationRunner = simulation_factory.SimulationRunner;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize RNG and ID generator
    const seed: u64 = @bitCast(std.time.timestamp());
    var prng = std.Random.DefaultPrng.init(seed);
    var rng = prng.random();
    var id_gen = entity.EntityIdGenerator{};

    std.debug.print("\n╔════════════════════════════════════════╗\n", .{});
    std.debug.print("║  SimulationFactory Test Suite          ║\n", .{});
    std.debug.print("╚════════════════════════════════════════╝\n\n", .{});

    // Test 1: 2v2 Small Skirmish
    std.debug.print("➤ Test 1: 2v2 Small Skirmish (1500 ticks)\n", .{});
    std.debug.print("─────────────────────────────────────────\n", .{});
    try runSimulation(allocator, &rng, &id_gen, 2, 2, 1500, "match_telemetry_2v2.json", true);

    std.debug.print("\n\n", .{});

    // Test 2: 3v3v3 Three-Way Battle
    std.debug.print("➤ Test 2: 3v3v3 Three-Way Battle (5000 ticks)\n", .{});
    std.debug.print("─────────────────────────────────────────\n", .{});
    try runSimulation(allocator, &rng, &id_gen, 3, 3, 5000, "match_telemetry_3v3v3.json", true);

    std.debug.print("\n\n", .{});

    // Test 3: 4v4 Large Team Battle
    std.debug.print("➤ Test 3: 4v4 Large Team Battle (5000 ticks)\n", .{});
    std.debug.print("─────────────────────────────────────────\n", .{});
    try runSimulation(allocator, &rng, &id_gen, 2, 4, 5000, "match_telemetry_4v4.json", true);

    std.debug.print("\n\n", .{});

    // Test 4: 2v2v2v2 Four-Way Battle (limited to MAX_ENTITIES=12)
    std.debug.print("➤ Test 4: 2v2v2v2 Four-Way Battle (4000 ticks)\n", .{});
    std.debug.print("─────────────────────────────────────────\n", .{});
    try runSimulation(allocator, &rng, &id_gen, 4, 2, 4000, "match_telemetry_2v2v2v2.json", true);

    std.debug.print("\n╔════════════════════════════════════════╗\n", .{});
    std.debug.print("║  All tests completed successfully!     ║\n", .{});
    std.debug.print("╚════════════════════════════════════════╝\n\n", .{});
}

/// Helper function to run a simulation with given parameters
fn runSimulation(
    allocator: std.mem.Allocator,
    rng: *std.Random,
    id_gen: *entity.EntityIdGenerator,
    team_count: usize,
    characters_per_team: usize,
    max_ticks: u32,
    telemetry_filename: []const u8,
    verbose: bool,
) !void {
    // Create factory
    var factory = SimulationFactory.init(allocator, rng, id_gen);
    defer factory.deinit();

    // Configure and build simulation
    const context = try factory
        .withTeamCount(team_count)
        .withCharactersPerTeam(characters_per_team)
        .withMaxTicks(max_ticks)
        .withTelemetryFile(telemetry_filename)
        .withVerbose(verbose)
        .build();

    // Run simulation
    var runner = SimulationRunner.init(context, factory.config);
    try runner.run();
    runner.deinit();
}
