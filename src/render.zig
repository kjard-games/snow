const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const entity_types = @import("entity.zig");
const vfx = @import("vfx.zig");
const palette = @import("color_palette.zig");
const terrain = @import("terrain.zig");

const Character = character.Character;
const EntityId = entity_types.EntityId;
const TerrainGrid = terrain.TerrainGrid;
const print = std.debug.print;

// Helper to convert float coordinates to integer screen positions
inline fn toScreenPos(pos: rl.Vector2) struct { x: i32, y: i32 } {
    return .{
        .x = @intFromFloat(pos.x),
        .y = @intFromFloat(pos.y),
    };
}

// Draw the terrain grid with 3D snow depth
fn drawTerrainGrid(grid: *const TerrainGrid) void {
    var z: usize = 0;
    while (z < grid.height) : (z += 1) {
        var x: usize = 0;
        while (x < grid.width) : (x += 1) {
            const index = z * grid.width + x;
            const cell = grid.cells[index];
            const world_pos = grid.gridToWorld(x, z);

            const tile_size = grid.grid_size;
            const color = cell.type.getColor();
            const snow_height = cell.type.getSnowHeight();

            // Draw ground base (dark gray ground underneath snow)
            const ground_color = rl.Color{ .r = 80, .g = 80, .b = 80, .a = 255 };
            rl.drawCube(
                rl.Vector3{ .x = world_pos.x, .y = -2.0, .z = world_pos.z },
                tile_size,
                4.0, // Ground thickness
                tile_size,
                ground_color,
            );

            // Draw snow layer with actual height
            if (snow_height > 0.5) {
                // Snow cube positioned so its top is at snow_height/2 and bottom at y=0
                const snow_y = snow_height / 2.0;
                rl.drawCube(
                    rl.Vector3{ .x = world_pos.x, .y = snow_y, .z = world_pos.z },
                    tile_size - 1.0, // Slightly smaller to show gaps between cells
                    snow_height, // Height based on snow depth
                    tile_size - 1.0,
                    color,
                );

                // Draw top surface highlight (slightly brighter for depth perception)
                var top_color = color;
                top_color.r = @min(255, @as(u16, top_color.r) + 15);
                top_color.g = @min(255, @as(u16, top_color.g) + 15);
                top_color.b = @min(255, @as(u16, top_color.b) + 15);

                rl.drawCube(
                    rl.Vector3{ .x = world_pos.x, .y = snow_height + 0.1, .z = world_pos.z },
                    tile_size - 1.0,
                    0.2, // Thin top layer
                    tile_size - 1.0,
                    top_color,
                );

                // Draw subtle border on snow edges (darker for contrast)
                var border_color = color;
                border_color.r = @as(u8, @intFromFloat(@as(f32, @floatFromInt(border_color.r)) * 0.6));
                border_color.g = @as(u8, @intFromFloat(@as(f32, @floatFromInt(border_color.g)) * 0.6));
                border_color.b = @as(u8, @intFromFloat(@as(f32, @floatFromInt(border_color.b)) * 0.6));

                rl.drawCubeWires(
                    rl.Vector3{ .x = world_pos.x, .y = snow_y, .z = world_pos.z },
                    tile_size - 1.0,
                    snow_height,
                    tile_size - 1.0,
                    border_color,
                );
            } else {
                // For cleared/icy ground (minimal snow), just draw a thin layer
                rl.drawCube(
                    rl.Vector3{ .x = world_pos.x, .y = 0.5, .z = world_pos.z },
                    tile_size - 1.0,
                    1.0,
                    tile_size - 1.0,
                    color,
                );
            }
        }
    }
}

pub fn draw(player: *const Character, entities: []const Character, selected_target: ?EntityId, camera: rl.Camera, interpolation_alpha: f32, vfx_manager: *const vfx.VFXManager, terrain_grid: *const @import("terrain.zig").TerrainGrid) void {
    rl.clearBackground(.dark_gray);

    // === 3D RENDERING ===
    rl.beginMode3D(camera);

    // Draw terrain grid with 3D snow depth
    drawTerrainGrid(terrain_grid);

    // Draw entities (interpolated for smooth movement, adjusted for snow depth)
    for (entities) |ent| {
        // Skip dead entities
        if (!ent.isAlive()) continue;

        // Get interpolated position
        var render_pos = ent.getInterpolatedPosition(interpolation_alpha);

        // Adjust Y position based on terrain sink depth (characters sink into snow)
        const sink_depth = terrain_grid.getSinkDepthAt(render_pos.x, render_pos.z);
        const snow_height = terrain_grid.getSnowHeightAt(render_pos.x, render_pos.z);

        // Character's center should be at: snow_surface - sink_depth + radius
        // Snow surface is at snow_height, character sinks sink_depth into it
        render_pos.y = snow_height - sink_depth + ent.radius;

        const color = if (ent.is_dead) palette.TEAM.DEAD else ent.color;
        rl.drawSphere(render_pos, ent.radius, color);
        rl.drawSphereWires(render_pos, ent.radius, 8, 8, .black);
    }

    // Draw player (interpolated, adjusted for snow depth)
    var player_render_pos = player.*.getInterpolatedPosition(interpolation_alpha);

    // Adjust player Y position based on terrain
    const player_sink_depth = terrain_grid.getSinkDepthAt(player_render_pos.x, player_render_pos.z);
    const player_snow_height = terrain_grid.getSnowHeightAt(player_render_pos.x, player_render_pos.z);
    player_render_pos.y = player_snow_height - player_sink_depth + player.*.radius;

    const player_color = if (player.*.is_dead) palette.TEAM.DEAD else player.*.color;
    rl.drawSphere(player_render_pos, player.*.radius, player_color);
    rl.drawSphereWires(player_render_pos, player.*.radius, 8, 8, .black);

    // Draw target selection indicator
    if (selected_target) |target_id| {
        // Find target by ID
        var target: ?Character = null;
        if (player.*.id == target_id) {
            target = player.*;
        } else {
            for (entities) |ent| {
                if (ent.id == target_id) {
                    target = ent;
                    break;
                }
            }
        }

        if (target) |tgt| {
            // Only draw selection indicator if target is alive
            if (tgt.isAlive()) {
                // Draw selection ring around target (interpolated)
                const target_render_pos = tgt.getInterpolatedPosition(interpolation_alpha);
                rl.drawCylinder(target_render_pos, tgt.radius + 5, tgt.radius + 5, 2, 16, palette.TEAM.SELECTION);

                // Draw selection arrow above target
                const arrow_pos = rl.Vector3{
                    .x = target_render_pos.x,
                    .y = target_render_pos.y + tgt.radius + 15,
                    .z = target_render_pos.z,
                };
                rl.drawCube(arrow_pos, 5, 5, 5, palette.TEAM.SELECTION);
            }
        }
    }

    // Draw visual effects (projectiles, impacts, heal effects)
    vfx_manager.draw3D();

    rl.endMode3D();

    // === 2D RENDERING (names, health bars, cast bars) ===
    const screen_width = rl.getScreenWidth();
    const screen_height = rl.getScreenHeight();

    // Draw floating UI for all entities
    for (entities) |ent| {
        if (!ent.isAlive()) continue;

        var render_pos = ent.getInterpolatedPosition(interpolation_alpha);

        // Adjust for terrain depth (same as entity rendering)
        const sink_depth = terrain_grid.getSinkDepthAt(render_pos.x, render_pos.z);
        const snow_height = terrain_grid.getSnowHeightAt(render_pos.x, render_pos.z);
        render_pos.y = snow_height - sink_depth + ent.radius;

        // Position above entity
        const ui_3d_pos = rl.Vector3{
            .x = render_pos.x,
            .y = render_pos.y + ent.radius + 10,
            .z = render_pos.z,
        };
        const ui_2d_pos = rl.getWorldToScreen(ui_3d_pos, camera);

        // Only draw if on screen
        if (ui_2d_pos.x >= 0 and ui_2d_pos.x < @as(f32, @floatFromInt(screen_width)) and
            ui_2d_pos.y >= 0 and ui_2d_pos.y < @as(f32, @floatFromInt(screen_height)))
        {
            const screen_pos = toScreenPos(ui_2d_pos);
            var current_y: i32 = screen_pos.y;

            // Name
            const text_width = rl.measureText(ent.name, 10);
            rl.drawText(ent.name, screen_pos.x - @divTrunc(text_width, 2), current_y, 10, .white);
            current_y += 12;

            // Health bar
            const bar_width: i32 = 80;
            const bar_height: i32 = 8;
            const bar_x = screen_pos.x - @divTrunc(bar_width, 2);

            // Background
            rl.drawRectangle(bar_x, current_y, bar_width, bar_height, rl.Color{ .r = 20, .g = 20, .b = 20, .a = 200 });

            // Health fill
            const health_percent = ent.warmth / ent.max_warmth;
            const fill_width = @as(i32, @intFromFloat(@as(f32, @floatFromInt(bar_width - 2)) * health_percent));
            const health_color = if (ent.is_enemy) rl.Color.red else rl.Color.green;
            rl.drawRectangle(bar_x + 1, current_y + 1, fill_width, bar_height - 2, health_color);

            // Border
            rl.drawRectangleLines(bar_x, current_y, bar_width, bar_height, .white);
            current_y += bar_height + 2;

            // Cast bar (if casting)
            if (ent.cast_state == .activating) {
                const casting_skill = ent.skill_bar[ent.casting_skill_index];
                if (casting_skill) |skill| {
                    const cast_time_total = @as(f32, @floatFromInt(skill.activation_time_ms)) / 1000.0;
                    const progress = 1.0 - (ent.cast_time_remaining / cast_time_total);

                    // Cast bar
                    rl.drawRectangle(bar_x, current_y, bar_width, bar_height, rl.Color{ .r = 20, .g = 20, .b = 20, .a = 200 });
                    const cast_fill_width = @as(i32, @intFromFloat(@as(f32, @floatFromInt(bar_width - 2)) * progress));
                    rl.drawRectangle(bar_x + 1, current_y + 1, cast_fill_width, bar_height - 2, rl.Color.gold);
                    rl.drawRectangleLines(bar_x, current_y, bar_width, bar_height, .white);
                }
            }
        }
    }

    // Draw player floating UI (same style)
    // Note: player_render_pos is already adjusted for terrain in the 3D section above
    const player_ui_3d_pos = rl.Vector3{
        .x = player_render_pos.x,
        .y = player_render_pos.y + player.*.radius + 10,
        .z = player_render_pos.z,
    };
    const player_ui_2d_pos = rl.getWorldToScreen(player_ui_3d_pos, camera);

    if (player_ui_2d_pos.x >= 0 and player_ui_2d_pos.x < @as(f32, @floatFromInt(screen_width)) and
        player_ui_2d_pos.y >= 0 and player_ui_2d_pos.y < @as(f32, @floatFromInt(screen_height)))
    {
        const screen_pos = toScreenPos(player_ui_2d_pos);
        var current_y: i32 = screen_pos.y;

        // Name (player name in lime)
        const text_width = rl.measureText(player.*.name, 12);
        rl.drawText(player.*.name, screen_pos.x - @divTrunc(text_width, 2), current_y, 12, .lime);
        current_y += 14;

        // Health bar
        const bar_width: i32 = 80;
        const bar_height: i32 = 8;
        const bar_x = screen_pos.x - @divTrunc(bar_width, 2);

        rl.drawRectangle(bar_x, current_y, bar_width, bar_height, rl.Color{ .r = 20, .g = 20, .b = 20, .a = 200 });
        const health_percent = player.*.warmth / player.*.max_warmth;
        const fill_width = @as(i32, @intFromFloat(@as(f32, @floatFromInt(bar_width - 2)) * health_percent));
        rl.drawRectangle(bar_x + 1, current_y + 1, fill_width, bar_height - 2, rl.Color.green);
        rl.drawRectangleLines(bar_x, current_y, bar_width, bar_height, .white);
        current_y += bar_height + 2;

        // Cast bar (if casting)
        if (player.*.cast_state == .activating) {
            const casting_skill = player.*.skill_bar[player.*.casting_skill_index];
            if (casting_skill) |skill| {
                const cast_time_total = @as(f32, @floatFromInt(skill.activation_time_ms)) / 1000.0;
                const progress = 1.0 - (player.*.cast_time_remaining / cast_time_total);

                rl.drawRectangle(bar_x, current_y, bar_width, bar_height, rl.Color{ .r = 20, .g = 20, .b = 20, .a = 200 });
                const cast_fill_width = @as(i32, @intFromFloat(@as(f32, @floatFromInt(bar_width - 2)) * progress));
                rl.drawRectangle(bar_x + 1, current_y + 1, cast_fill_width, bar_height - 2, rl.Color.gold);
                rl.drawRectangleLines(bar_x, current_y, bar_width, bar_height, .white);
            }
        }
    }

    // Draw visual effects 2D overlay (damage numbers)
    vfx_manager.draw2D(camera);
}
