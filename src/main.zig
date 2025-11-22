const std = @import("std");
const rl = @import("raylib");
const game_state = @import("game_state.zig");

const GameState = game_state.GameState;

pub fn main() !void {
    const screenWidth = 1280;
    const screenHeight = 720;

    rl.initWindow(screenWidth, screenHeight, "Snow - GW1-Style 3D Tab Targeting");
    defer rl.closeWindow();

    // Enable window resizing and toggling fullscreen
    rl.setWindowState(rl.ConfigFlags{ .window_resizable = true });

    // Set minimum window size
    rl.setWindowMinSize(800, 600);

    // Set target FPS to monitor refresh rate (or 60 if unavailable)
    const monitor_refresh = rl.getMonitorRefreshRate(0);
    const target_fps = if (monitor_refresh > 0) monitor_refresh else 60;
    rl.setTargetFPS(target_fps);

    // Initialize allocator for terrain system
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var state = try GameState.init(allocator);
    defer state.deinit();

    while (!rl.windowShouldClose()) {
        // Toggle fullscreen with F11
        if (rl.isKeyPressed(rl.KeyboardKey.f11)) {
            rl.toggleFullscreen();
        }

        state.update();

        rl.beginDrawing();
        defer rl.endDrawing();

        state.draw();
        state.drawUI(); // Note: drawUI now takes *GameState (mutable) for input_state updates
    }
}
