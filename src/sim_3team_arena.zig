const std = @import("std");
const game_state = @import("game_state.zig");
const telemetry = @import("telemetry.zig");
const factory = @import("factory.zig");
const entity = @import("entity.zig");
const character = @import("character.zig");

const GameState = game_state.GameState;
const MatchTelemetry = telemetry.MatchTelemetry;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("Memory leak detected!\n", .{});
        }
    }
    const allocator = gpa.allocator();

    // Initialize telemetry
    var telem = try MatchTelemetry.init(allocator);
    defer telem.deinit();

    // Initialize RNG and ID generator
    const timestamp = std.time.timestamp();
    const seed: u64 = @bitCast(timestamp);
    var prng = std.Random.DefaultPrng.init(seed);
    var rng = prng.random();

    var id_gen = entity.EntityIdGenerator{};

    // Build 3-team arena using factory
    std.debug.print("\n=== BUILDING 3-TEAM ARENA ===\n", .{});
    var arena = factory.ArenaBuilder.init(allocator, &rng, &id_gen);
    defer arena.deinit();

    // Blue team (allies)
    {
        const blue_team = try arena.addTeam();
        _ = blue_team
            .withTeam(.blue)
            .withColor(.blue)
            .withBasePosition(.{ .x = -200, .y = 0, .z = 300 })
            .withSpacing(100.0);

        for (0..4) |_| {
            var builder = factory.CharacterBuilder.init(allocator, &rng, &id_gen);
            _ = builder.withTeam(.blue).withColor(.blue);
            try blue_team.addCharacter(&builder);
        }
    }

    // Red team (enemies)
    {
        const red_team = try arena.addTeam();
        _ = red_team
            .withTeam(.red)
            .withColor(.red)
            .withBasePosition(.{ .x = 200, .y = 0, .z = -300 })
            .withSpacing(100.0);

        for (0..4) |_| {
            var builder = factory.CharacterBuilder.init(allocator, &rng, &id_gen);
            _ = builder.withTeam(.red).withColor(.red);
            try red_team.addCharacter(&builder);
        }
    }

    // Yellow team (neutral/3rd party)
    {
        const yellow_team = try arena.addTeam();
        _ = yellow_team
            .withTeam(.blue) // Use blue team enum but yellow color for visuals
            .withColor(.yellow)
            .withBasePosition(.{ .x = 0, .y = 0, .z = -400 })
            .withSpacing(100.0);

        for (0..4) |_| {
            var builder = factory.CharacterBuilder.init(allocator, &rng, &id_gen);
            _ = builder.withTeam(.blue).withColor(.yellow);
            try yellow_team.addCharacter(&builder);
        }
    }

    // Collect all characters from arena teams
    var all_chars: std.array_list.Aligned(character.Character, null) = .{};
    defer all_chars.deinit(allocator);

    for (0..arena.teamCount()) |team_idx| {
        if (arena.getTeam(team_idx)) |team| {
            for (team.characters.items) |char| {
                try all_chars.append(allocator, char);
            }
            std.debug.print("Team {d}: {d} characters\n", .{ team_idx, team.characters.items.len });
        }
    }

    std.debug.print("Total characters: {d}\n", .{all_chars.items.len});

    // Initialize game state with built characters using the builder
    var builder = game_state.GameStateBuilder.init(allocator);
    const state = try builder
        .withRendering(false)
        .withPlayerControl(false)
        .withCharacters(all_chars.items)
        .build();
    var mutable_state = state;
    defer mutable_state.deinit();

    // Link telemetry to game state
    mutable_state.match_telemetry = &telem;

    // Register all entities for telemetry tracking
    for (mutable_state.entities[0..all_chars.items.len]) |ent| {
        try telem.registerEntity(
            ent.id,
            ent.name,
            @tagName(ent.school),
            @tagName(ent.player_position),
            if (ent.team == .blue) 0 else 1, // Blue = team 0, Red = team 1
            ent.id == mutable_state.controlled_entity_id,
        );
    }

    std.debug.print("\n=== SIMULATION MODE ENABLED ===\n", .{});
    std.debug.print("Running 3-team battle simulation with telemetry...\n", .{});
    std.debug.print("(Max 15000 ticks, will end early if all teams eliminated)\n\n", .{});

    // Run ticks until combat ends
    var tick_count: u32 = 0;
    const max_ticks = 15000;

    while (tick_count < max_ticks) : (tick_count += 1) {
        // Manually accumulate time for the update loop
        mutable_state.tick_accumulator = game_state.TICK_RATE_SEC;

        // Call processTick directly
        mutable_state.processTick();

        // Update telemetry tick counters
        for (mutable_state.entities[0..all_chars.items.len]) |ent| {
            if (telem.getEntityStats(ent.id)) |stats| {
                if (ent.isAlive()) {
                    stats.time_alive_ticks += 1;
                } else {
                    stats.time_dead_ticks += 1;
                }
            }
        }

        // Check if combat is over (all members of a team dead)
        // For 3v3v3, we need to check all three teams
        var team_counts = [_]u32{ 0, 0, 0 };
        for (mutable_state.entities[0..all_chars.items.len]) |ch| {
            if (ch.isAlive()) {
                const team_id: usize = if (ch.team == .blue) 0 else 1;
                team_counts[team_id] += 1;
            }
        }

        // End if any team is fully eliminated or only one team remains alive
        var teams_alive: u32 = 0;
        for (team_counts) |count| {
            if (count > 0) teams_alive += 1;
        }

        if (teams_alive <= 1) {
            break;
        }
    }

    telem.match_duration_ticks = tick_count;

    std.debug.print("\n=== SIMULATION COMPLETE ===\n", .{});
    std.debug.print("Ticks run: {d}\n\n", .{tick_count});

    // Print telemetry report
    telem.printSummary();

    // Export as JSON for analysis
    std.debug.print("\n=== EXPORTING TELEMETRY ===\n", .{});
    try telem.exportJSON(allocator, "match_telemetry_3team.json");
    std.debug.print("Telemetry exported to: match_telemetry_3team.json\n\n", .{});
}
