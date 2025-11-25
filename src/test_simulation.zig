const std = @import("std");
const game_state = @import("game_state.zig");
const telemetry = @import("telemetry.zig");

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

    // Initialize game state in pure AI vs AI mode (4v4, no player)
    // Using the new builder-based API for headless simulations
    var state = try GameState.initHeadlessSimulation(allocator);
    defer state.deinit();

    // Link telemetry to game state
    state.match_telemetry = &telem;

    // Register all entities for telemetry tracking
    for (state.entities) |ent| {
        try telem.registerEntity(
            ent.id,
            ent.name,
            @tagName(ent.school),
            @tagName(ent.player_position),
            if (ent.team == .blue) 0 else 1, // Blue = team 0 (allies), Red = team 1 (enemies)
            ent.id == state.controlled_entity_id,
        );
    }

    std.debug.print("\n=== SIMULATION MODE ENABLED ===\n", .{});
    std.debug.print("Running AI-only battle simulation with telemetry...\n\n", .{});

    // Run ticks until combat ends
    for (0..12000) |tick| { // EXTENDED to 10k ticks to see full engagement
        // Manually accumulate time for the update loop
        state.tick_accumulator = game_state.TICK_RATE_SEC;

        // Call processTick directly (in simulation mode, no raylib)
        state.processTick();
        state.current_tick += 1;
        state.current_tick += 1;
        state.current_tick += 1;

        // Update telemetry tick counters
        for (state.entities) |ent| {
            if (telem.getEntityStats(ent.id)) |stats| {
                if (ent.isAlive()) {
                    stats.time_alive_ticks += 1;
                } else {
                    stats.time_dead_ticks += 1;
                }
            }
        }

        // Print status every 20 ticks (1 second)
        if (tick % 20 == 0) {
            var alive_allies: u32 = 0;
            var alive_enemies: u32 = 0;

            // In AI-only mode, use first entity's team as reference
            const ref_team = state.entities[0].team;

            for (state.entities) |ent| {
                if (ent.isAlive()) {
                    if (ent.team == ref_team) {
                        alive_allies += 1;
                    } else {
                        alive_enemies += 1;
                    }
                }
            }

            std.debug.print("Tick {d:>3}: Allies={d} Enemies={d} | State={s}\n", .{
                tick,
                alive_allies,
                alive_enemies,
                @tagName(state.combat_state),
            });
        }

        // Stop if combat ended
        if (state.combat_state != .active) {
            std.debug.print("\n=== COMBAT ENDED at tick {d} ({s}) ===\n", .{ tick, @tagName(state.combat_state) });

            // Record match duration and winning team
            telem.match_duration_ticks = @intCast(tick);
            telem.winning_team = switch (state.combat_state) {
                .victory => 0, // Player (allies) won
                .defeat => 1, // Enemies won
                .active => null,
            };

            // Print final results
            std.debug.print("Final Results:\n", .{});
            for (state.entities) |ent| {
                if (ent.isAlive()) {
                    std.debug.print("  {s}: {d:.0}/{d:.0} HP\n", .{ ent.name, ent.warmth, ent.max_warmth });
                } else {
                    std.debug.print("  {s}: DEAD\n", .{ent.name});
                }
            }
            break;
        }
    }

    std.debug.print("\n=== SIMULATION COMPLETE ===\n\n", .{});

    // Set match duration if it wasn't set by combat ending
    if (telem.match_duration_ticks == 0) {
        telem.match_duration_ticks = 6000;
    }

    // Print telemetry summary
    telem.printSummary();

    // Export telemetry to JSON
    try telem.exportJSON(allocator, "match_telemetry.json");
    std.debug.print("\nTelemetry exported to match_telemetry.json\n", .{});
}
