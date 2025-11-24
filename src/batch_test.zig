//! Batch Testing Framework - Run multiple simulations and collect aggregate statistics
//! Usage: zig build batch-test

const std = @import("std");
const rl = @import("raylib");
const simulation_factory = @import("simulation_factory.zig");
const entity = @import("entity.zig");
const telemetry = @import("telemetry.zig");

const SimulationFactory = simulation_factory.SimulationFactory;
const SimulationRunner = simulation_factory.SimulationRunner;
const MatchTelemetry = telemetry.MatchTelemetry;

/// Aggregate statistics collected from multiple simulations
pub const AggregateStats = struct {
    sim_count: usize,
    total_duration_ticks: u64,
    avg_duration_ticks: f32,
    min_duration_ticks: u32,
    max_duration_ticks: u32,

    total_damage_dealt_ally: f32,
    total_damage_dealt_enemy: f32,
    avg_damage_dealt_ally: f32,
    avg_damage_dealt_enemy: f32,

    total_healing_ally: f32,
    total_healing_enemy: f32,
    avg_healing_ally: f32,
    avg_healing_enemy: f32,

    ally_wins: usize,
    enemy_wins: usize,
    ties: usize,

    pub fn print(self: AggregateStats) void {
        std.debug.print("\n╔════════════════════════════════════════╗\n", .{});
        std.debug.print("║       AGGREGATE STATISTICS ({d} runs)    ║\n", .{self.sim_count});
        std.debug.print("╚════════════════════════════════════════╝\n\n", .{});

        std.debug.print("Duration:\n", .{});
        std.debug.print("  Average: {d:.1} ticks\n", .{self.avg_duration_ticks});
        std.debug.print("  Range:   {d}-{d} ticks\n", .{ self.min_duration_ticks, self.max_duration_ticks });

        std.debug.print("\nDamage:\n", .{});
        std.debug.print("  Allies:  {d:.1} avg / match\n", .{self.avg_damage_dealt_ally});
        std.debug.print("  Enemies: {d:.1} avg / match\n", .{self.avg_damage_dealt_enemy});
        std.debug.print("  Ratio:   {d:.2}x\n", .{
            if (self.avg_damage_dealt_enemy > 0) self.avg_damage_dealt_ally / self.avg_damage_dealt_enemy else 0,
        });

        std.debug.print("\nHealing:\n", .{});
        std.debug.print("  Allies:  {d:.1} avg / match\n", .{self.avg_healing_ally});
        std.debug.print("  Enemies: {d:.1} avg / match\n", .{self.avg_healing_enemy});

        std.debug.print("\nWin Distribution:\n", .{});
        std.debug.print("  Allies:  {d} ({d:.1}%)\n", .{ self.ally_wins, @as(f32, @floatFromInt(self.ally_wins)) / @as(f32, @floatFromInt(self.sim_count)) * 100 });
        std.debug.print("  Enemies: {d} ({d:.1}%)\n", .{ self.enemy_wins, @as(f32, @floatFromInt(self.enemy_wins)) / @as(f32, @floatFromInt(self.sim_count)) * 100 });
        std.debug.print("  Ties:    {d}\n\n", .{self.ties});
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize RNG and ID generator
    const seed: u64 = @bitCast(std.time.timestamp());
    var prng = std.Random.DefaultPrng.init(seed);
    var rng = prng.random();

    std.debug.print("\n╔══════════════════════════════════════════╗\n", .{});
    std.debug.print("║      Batch Testing Framework              ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════╝\n\n", .{});

    // Run 5 simulations of 2v2
    std.debug.print("Running 5 simulations of 2v2 (1500 ticks each)...\n\n", .{});
    var stats_2v2 = try runBatchTest(allocator, &rng, 5, 2, 2, 1500, false);
    stats_2v2.print();

    // Run 3 simulations of 3v3v3
    std.debug.print("\n", .{});
    std.debug.print("Running 3 simulations of 3v3v3 (3000 ticks each)...\n\n", .{});
    var stats_3v3v3 = try runBatchTest(allocator, &rng, 3, 3, 3, 3000, false);
    stats_3v3v3.print();

    std.debug.print("╔══════════════════════════════════════════╗\n", .{});
    std.debug.print("║    All batch tests completed!             ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════╝\n\n", .{});
}

/// Run a batch of simulations and collect aggregate statistics
fn runBatchTest(
    allocator: std.mem.Allocator,
    rng: *std.Random,
    sim_count: usize,
    team_count: usize,
    characters_per_team: usize,
    max_ticks: u32,
    verbose: bool,
) !AggregateStats {
    var stats = AggregateStats{
        .sim_count = sim_count,
        .total_duration_ticks = 0,
        .avg_duration_ticks = 0,
        .min_duration_ticks = std.math.maxInt(u32),
        .max_duration_ticks = 0,
        .total_damage_dealt_ally = 0,
        .total_damage_dealt_enemy = 0,
        .avg_damage_dealt_ally = 0,
        .avg_damage_dealt_enemy = 0,
        .total_healing_ally = 0,
        .total_healing_enemy = 0,
        .avg_healing_ally = 0,
        .avg_healing_enemy = 0,
        .ally_wins = 0,
        .enemy_wins = 0,
        .ties = 0,
    };

    for (0..sim_count) |sim_idx| {
        std.debug.print("  Sim {d}/{d}... ", .{ sim_idx + 1, sim_count });

        var id_gen = entity.EntityIdGenerator{};
        var factory = SimulationFactory.init(allocator, rng, &id_gen);
        defer factory.deinit();

        const filename_buf = try allocator.alloc(u8, 256);
        defer allocator.free(filename_buf);
        const filename = try std.fmt.bufPrint(filename_buf, "batch_sim_{d}.json", .{sim_idx});

        const context = try factory
            .withTeamCount(team_count)
            .withCharactersPerTeam(characters_per_team)
            .withMaxTicks(max_ticks)
            .withTelemetryFile(filename)
            .withVerbose(verbose)
            .build();

        var runner = SimulationRunner.init(context, factory.config);
        try runner.run();
        runner.deinit();

        // Collect statistics from telemetry
        const duration = context.telemetry.match_duration_ticks;
        stats.total_duration_ticks += duration;
        if (duration < stats.min_duration_ticks) stats.min_duration_ticks = duration;
        if (duration > stats.max_duration_ticks) stats.max_duration_ticks = duration;

        stats.total_damage_dealt_ally += context.telemetry.total_damage_dealt_ally;
        stats.total_damage_dealt_enemy += context.telemetry.total_damage_dealt_enemy;
        stats.total_healing_ally += context.telemetry.total_healing_ally;
        stats.total_healing_enemy += context.telemetry.total_healing_enemy;

        // Determine winner
        if (context.telemetry.total_damage_dealt_ally > context.telemetry.total_damage_dealt_enemy) {
            stats.ally_wins += 1;
        } else if (context.telemetry.total_damage_dealt_enemy > context.telemetry.total_damage_dealt_ally) {
            stats.enemy_wins += 1;
        } else {
            stats.ties += 1;
        }

        std.debug.print("done\n", .{});
    }

    // Calculate averages
    const sim_count_f32 = @as(f32, @floatFromInt(sim_count));
    stats.avg_duration_ticks = @as(f32, @floatFromInt(stats.total_duration_ticks)) / sim_count_f32;
    stats.avg_damage_dealt_ally = stats.total_damage_dealt_ally / sim_count_f32;
    stats.avg_damage_dealt_enemy = stats.total_damage_dealt_enemy / sim_count_f32;
    stats.avg_healing_ally = stats.total_healing_ally / sim_count_f32;
    stats.avg_healing_enemy = stats.total_healing_enemy / sim_count_f32;

    return stats;
}
