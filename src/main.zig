const rl = @import("raylib");

pub fn main() anyerror!void {
    const screenWidth = 800;
    const screenHeight = 600;

    rl.initWindow(screenWidth, screenHeight, "Snow - Game Prototype");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.black);

        rl.drawText("Snow Game Prototype", 190, 200, 20, .white);
        rl.drawText("Press ESC to exit", 190, 230, 20, .light_gray);
    }
}
