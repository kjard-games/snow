const rl = @import("raylib");
const game_state = @import("game_state.zig");

const GameState = game_state.GameState;

pub fn main() void {
    const screenWidth = 800;
    const screenHeight = 600;

    rl.initWindow(screenWidth, screenHeight, "Snow - GW1-Style 3D Tab Targeting");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    var state = GameState.init();

    while (!rl.windowShouldClose()) {
        state.update();

        rl.beginDrawing();
        defer rl.endDrawing();

        state.draw();
        state.drawUI(); // Note: drawUI now takes *GameState (mutable) for input_state updates
    }
}
