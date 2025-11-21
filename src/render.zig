const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const entity_types = @import("entity.zig");

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

pub fn draw(player: *const Character, entities: []const Character, selected_target: ?EntityId, camera: rl.Camera, interpolation_alpha: f32) void {
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
        const color = if (ent.is_dead) rl.Color.gray else ent.color;
        rl.drawSphere(render_pos, ent.radius, color);
        rl.drawSphereWires(render_pos, ent.radius, 8, 8, .black);
    }

    // Draw player (interpolated)
    const player_render_pos = player.*.getInterpolatedPosition(interpolation_alpha);
    const player_color = if (player.*.is_dead) rl.Color.gray else player.*.color;
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
                rl.drawCylinder(target_render_pos, tgt.radius + 5, tgt.radius + 5, 2, 16, .yellow);

                // Draw selection arrow above target
                const arrow_pos = rl.Vector3{
                    .x = target_render_pos.x,
                    .y = target_render_pos.y + tgt.radius + 15,
                    .z = target_render_pos.z,
                };
                rl.drawCube(arrow_pos, 5, 5, 5, .yellow);
            }
        }
    }

    rl.endMode3D();

    // === 2D RENDERING (names, labels) ===
    // Draw entity names (interpolated positions)
    const screen_width = rl.getScreenWidth();
    const screen_height = rl.getScreenHeight();

    for (entities) |ent| {
        if (!ent.isAlive()) continue;

        const render_pos = ent.getInterpolatedPosition(interpolation_alpha);
        const name_3d_pos = rl.Vector3{
            .x = render_pos.x,
            .y = render_pos.y + ent.radius + 10,
            .z = render_pos.z,
        };
        const name_2d_pos = rl.getWorldToScreen(name_3d_pos, camera);

        // Only draw if on screen (check all bounds)
        if (name_2d_pos.x >= 0 and name_2d_pos.x < @as(f32, @floatFromInt(screen_width)) and
            name_2d_pos.y >= 0 and name_2d_pos.y < @as(f32, @floatFromInt(screen_height)))
        {
            const text_width = rl.measureText(ent.name, 10);
            const screen_pos = toScreenPos(name_2d_pos);
            rl.drawText(ent.name, screen_pos.x - @divTrunc(text_width, 2), screen_pos.y, 10, .white);
        }
    }

    // Draw player name (interpolated)
    const player_name_3d_pos = rl.Vector3{
        .x = player_render_pos.x,
        .y = player_render_pos.y + player.*.radius + 10,
        .z = player_render_pos.z,
    };
    const player_name_2d_pos = rl.getWorldToScreen(player_name_3d_pos, camera);

    if (player_name_2d_pos.x >= 0 and player_name_2d_pos.x < @as(f32, @floatFromInt(screen_width)) and
        player_name_2d_pos.y >= 0 and player_name_2d_pos.y < @as(f32, @floatFromInt(screen_height)))
    {
        const text_width = rl.measureText(player.*.name, 12);
        const screen_pos = toScreenPos(player_name_2d_pos);
        rl.drawText(player.*.name, screen_pos.x - @divTrunc(text_width, 2), screen_pos.y, 12, .lime);
    }
}
