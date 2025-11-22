const rl = @import("raylib");
const game_state = @import("game_state.zig");

const GameState = game_state.GameState;

pub fn main() void {
    const screenWidth = 800;
    const screenHeight = 600;

    rl.initWindow(screenWidth, screenHeight, "Snow - GW1-Style 3D Tab Targeting");
    defer rl.closeWindow();

    // Set target FPS to monitor refresh rate (or 60 if unavailable)
    const monitor_refresh = rl.getMonitorRefreshRate(0);
    const target_fps = if (monitor_refresh > 0) monitor_refresh else 60;
    rl.setTargetFPS(target_fps);

    var state = GameState.init();

    while (!rl.windowShouldClose()) {
        state.update();

        rl.beginDrawing();
        defer rl.endDrawing();

        state.draw();
        state.drawUI(); // Note: drawUI now takes *GameState (mutable) for input_state updates
    }
}
