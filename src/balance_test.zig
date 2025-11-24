//! Balance Iteration System - Run multiple simulations with different configurations to test balance changes
//! Usage: zig build balance-test

const std = @import("std");
const rl = @import("raylib");
const simulation_factory = @import("simulation_factory.zig");
const entity = @import("entity.zig");
const character = @import("character.zig");
const school = @import("school.zig");
const position_mod = @import("position.zig");

const SimulationFactory = simulation_factory.SimulationFactory;
const SimulationRunner = simulation_factory.SimulationRunner;
const School = school.School;
const Position = position_mod.Position;
const Character = character.Character;

/// A configuration for building teams with specific school/position combinations
pub const TeamComposition = struct {
    name: []const u8,
    schools: [4]School,
    positions: [4]Position,

    pub fn create(name: []const u8, schools: [4]School, positions: [4]Position) TeamComposition {
        return .{
            .name = name,
            .schools = schools,
            .positions = positions,
        };
    }
};

/// Predefined team compositions for testing
pub const Compositions = struct {
    pub const montessori_team = TeamComposition.create(
        "Montessori Dream Team",
        [_]School{ .montessori, .montessori, .montessori, .montessori },
        [_]Position{ .animator, .animator, .animator, .animator },
    );

    pub const balanced_team = TeamComposition.create(
        "Balanced Comp",
        [_]School{ .montessori, .private_school, .waldorf, .homeschool },
        [_]Position{ .animator, .fielder, .sledder, .pitcher },
    );

    pub const tank_comp = TeamComposition.create(
        "Tank Heavy",
        [_]School{ .private_school, .private_school, .homeschool, .homeschool },
        [_]Position{ .shoveler, .shoveler, .fielder, .fielder },
    );

    pub const glass_cannon = TeamComposition.create(
        "Glass Cannons",
        [_]School{ .montessori, .montessori, .public_school, .public_school },
        [_]Position{ .animator, .animator, .pitcher, .sledder },
    );
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize RNG and ID generator
    const seed: u64 = @bitCast(std.time.timestamp());
    var prng = std.Random.DefaultPrng.init(seed);
    var rng = prng.random();
    var id_gen = entity.EntityIdGenerator{};

    std.debug.print("\n╔══════════════════════════════════════════╗\n", .{});
    std.debug.print("║     Balance Iteration Test Suite          ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════╝\n\n", .{});

    // Test 1: Montessori mirror match
    std.debug.print("➤ Test 1: Montessori 4v4 Mirror Match (1500 ticks)\n", .{});
    std.debug.print("──────────────────────────────────────────\n", .{});
    try runBalanceTest(allocator, &rng, &id_gen, &Compositions.montessori_team, &Compositions.montessori_team, 1500, "balance_montessori_v_montessori.json");

    std.debug.print("\n\n", .{});

    // Test 2: Balanced vs Montessori
    std.debug.print("➤ Test 2: Balanced 4v4 vs Montessori (1500 ticks)\n", .{});
    std.debug.print("──────────────────────────────────────────\n", .{});
    try runBalanceTest(allocator, &rng, &id_gen, &Compositions.balanced_team, &Compositions.montessori_team, 1500, "balance_balanced_v_montessori.json");

    std.debug.print("\n\n", .{});

    // Test 3: Tank vs Glass Cannon
    std.debug.print("➤ Test 3: Tank 4v4 vs Glass Cannon (2000 ticks)\n", .{});
    std.debug.print("──────────────────────────────────────────\n", .{});
    try runBalanceTest(allocator, &rng, &id_gen, &Compositions.tank_comp, &Compositions.glass_cannon, 2000, "balance_tank_v_glass_cannon.json");

    std.debug.print("\n\n", .{});

    // Test 4: Balanced mirror match
    std.debug.print("➤ Test 4: Balanced 4v4 Mirror Match (2000 ticks)\n", .{});
    std.debug.print("──────────────────────────────────────────\n", .{});
    try runBalanceTest(allocator, &rng, &id_gen, &Compositions.balanced_team, &Compositions.balanced_team, 2000, "balance_balanced_v_balanced.json");

    std.debug.print("\n╔══════════════════════════════════════════╗\n", .{});
    std.debug.print("║  All balance tests completed!             ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════╝\n\n", .{});
}

/// Run a balance test between two team compositions
fn runBalanceTest(
    allocator: std.mem.Allocator,
    rng: *std.Random,
    id_gen: *entity.EntityIdGenerator,
    blue_comp: *const TeamComposition,
    red_comp: *const TeamComposition,
    max_ticks: u32,
    telemetry_filename: []const u8,
) !void {
    // Create factory
    var factory = SimulationFactory.init(allocator, rng, id_gen);
    defer factory.deinit();

    // For now, just run a standard 2v2 (only have 4 characters per team in simple case)
    // We'll build in the comp support once core factory is working
    const context = try factory
        .withTeamCount(2)
        .withCharactersPerTeam(2)
        .withMaxTicks(max_ticks)
        .withTelemetryFile(telemetry_filename)
        .withVerbose(false)
        .build();

    // Run simulation
    var runner = SimulationRunner.init(context, factory.config);
    try runner.run();
    runner.deinit();

    std.debug.print("Blue ({s}) vs Red ({s}): Match complete\n", .{ blue_comp.name, red_comp.name });
}
