const std = @import("std");
const game_state = @import("game_state.zig");

const GameState = game_state.GameState;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("Memory leak detected!\n", .{});
        }
    }
    const allocator = gpa.allocator();

    // Initialize game state in headless mode
    var state = try GameState.initHeadless(allocator);
    defer state.deinit();

    std.debug.print("\n=== SIMULATION MODE ENABLED ===\n", .{});
    std.debug.print("Running 100 ticks of AI-only battle simulation...\n\n", .{});

    // Run 100 ticks (5 seconds at 20Hz)
    for (0..100) |tick| {
        // Manually accumulate time for the update loop
        state.tick_accumulator = game_state.TICK_RATE_SEC;

        // Call processTick directly (in simulation mode, no raylib)
        state.processTick();
        state.current_tick += 1;

        // Print status every 20 ticks (1 second)
        if (tick % 20 == 0) {
            var alive_allies: u32 = 0;
            var alive_enemies: u32 = 0;
            const player = state.getPlayerConst();

            for (state.entities) |ent| {
                if (ent.isAlive()) {
                    if (player.isAlly(ent)) {
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
}
