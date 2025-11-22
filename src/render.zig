const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const entity_types = @import("entity.zig");
const vfx = @import("vfx.zig");
const palette = @import("color_palette.zig");

const Character = character.Character;
const EntityId = entity_types.EntityId;
const print = std.debug.print;

// Helper to convert float coordinates to integer screen positions
inline fn toScreenPos(pos: rl.Vector2) struct { x: i32, y: i32 } {
    return .{
        .x = @intFromFloat(pos.x),
        .y = @intFromFloat(pos.y),
    };
}

pub fn draw(player: *const Character, entities: []const Character, selected_target: ?EntityId, camera: rl.Camera, interpolation_alpha: f32, vfx_manager: *const vfx.VFXManager) void {
    rl.clearBackground(.dark_gray);

    // === 3D RENDERING ===
    rl.beginMode3D(camera);

    // Draw ground plane
    rl.drawGrid(20, 50);

    // Draw entities (interpolated for smooth movement)
    for (entities) |ent| {
        // Skip dead entities
        if (!ent.isAlive()) continue;

        // Draw entity as sphere at interpolated position
        const render_pos = ent.getInterpolatedPosition(interpolation_alpha);
        const color = if (ent.is_dead) palette.TEAM.DEAD else ent.color;
        rl.drawSphere(render_pos, ent.radius, color);
        rl.drawSphereWires(render_pos, ent.radius, 8, 8, .black);
    }

    // Draw player (interpolated)
    const player_render_pos = player.*.getInterpolatedPosition(interpolation_alpha);
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

        const render_pos = ent.getInterpolatedPosition(interpolation_alpha);

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
