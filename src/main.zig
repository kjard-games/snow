const std = @import("std");
const rl = @import("raylib");
const game_state = @import("game_state.zig");
const render = @import("render.zig");

const GameState = game_state.GameState;

pub fn main() !void {
    const screenWidth = 1280;
    const screenHeight = 720;

    rl.initWindow(screenWidth, screenHeight, "Snow - GW1-Style 3D Tab Targeting");
    defer rl.closeWindow();

    // Initialize outline shader
    render.initOutlineShader(screenWidth, screenHeight) catch |err| {
        std.log.err("Failed to initialize outline shader: {}", .{err});
        return err;
    };
    defer render.deinitOutlineShader();

    // Initialize terrain material with vertex color shader
    render.initTerrainMaterial() catch |err| {
        std.log.err("Failed to initialize terrain material: {}", .{err});
        return err;
    };

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
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.log.err("Memory leak detected!", .{});
        }
    }
    const allocator = gpa.allocator();

    const state = try GameState.init(allocator);
    var mutable_state = state;
    defer mutable_state.deinit();

    while (!rl.windowShouldClose()) {
        // Toggle fullscreen with F11
        if (rl.isKeyPressed(rl.KeyboardKey.f11)) {
            rl.toggleFullscreen();
        }

        mutable_state.update();

        rl.beginDrawing();
        defer rl.endDrawing();

        mutable_state.draw();
        mutable_state.drawUI();
    }
}
