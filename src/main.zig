const std = @import("std");
const rl = @import("raylib");
const game_state = @import("game_state.zig");
const game_mode = @import("game_mode.zig");
const render = @import("render.zig");

const GameState = game_state.GameState;
const GameMode = game_mode.GameMode;
const ModeType = game_mode.ModeType;

pub fn main() !void {
    const screenWidth = 1280;
    const screenHeight = 720;

    rl.initWindow(screenWidth, screenHeight, "Snow - Snowball Warfare");
    defer rl.closeWindow();

    // Initialize outline shader
    render.initOutlineShader(screenWidth, screenHeight) catch |err| {
        std.log.err("Failed to initialize outline shader: {}", .{err});
        return err;
    };
    defer render.deinitRenderResources();

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

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.log.err("Memory leak detected!", .{});
        }
    }
    const allocator = gpa.allocator();

    // Start with main menu
    var current_mode = GameMode.init(allocator, .main_menu);
    defer current_mode.deinit();

    // Track previous window size for resize detection
    var prev_width: i32 = screenWidth;
    var prev_height: i32 = screenHeight;

    while (!rl.windowShouldClose()) {
        // Toggle fullscreen with F11
        if (rl.isKeyPressed(rl.KeyboardKey.f11)) {
            rl.toggleFullscreen();
        }

        // Handle window resize
        const current_width = rl.getScreenWidth();
        const current_height = rl.getScreenHeight();
        if (current_width != prev_width or current_height != prev_height) {
            render.handleWindowResize(current_width, current_height);
            prev_width = current_width;
            prev_height = current_height;
        }

        // Update current mode
        current_mode.update();

        // Handle mode transitions
        if (current_mode.getTargetMode()) |target| {
            current_mode.deinit();
            current_mode = GameMode.init(allocator, target);
        }

        // Render
        rl.beginDrawing();
        defer rl.endDrawing();

        current_mode.draw();
        current_mode.drawUI();
    }
}
