const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");

const Character = character.Character;
const print = std.debug.print;

pub fn draw(player: *const Character, entities: []const Character, selected_target: ?usize, camera: rl.Camera) void {
    rl.clearBackground(.dark_gray);

    // === 3D RENDERING ===
    rl.beginMode3D(camera);

    // Draw ground plane
    rl.drawGrid(20, 50);

    // Draw entities
    for (entities) |ent| {
        // Skip dead entities
        if (!ent.isAlive()) continue;

        // Draw entity as sphere
        const color = if (ent.is_dead) rl.Color.gray else ent.color;
        rl.drawSphere(ent.position, ent.radius, color);
        rl.drawSphereWires(ent.position, ent.radius, 8, 8, .black);
    }

    // Draw player
    const player_color = if (player.*.is_dead) rl.Color.gray else player.*.color;
    rl.drawSphere(player.*.position, player.*.radius, player_color);
    rl.drawSphereWires(player.*.position, player.*.radius, 8, 8, .black);

    // Draw target selection indicator
    if (selected_target) |target_index| {
        if (target_index < entities.len) {
            const target = entities[target_index];

            // Skip if target is dead
            if (!target.isAlive()) {
                rl.endMode3D();
                return;
            }

            // Draw selection ring around target
            const ring_pos = rl.Vector3{
                .x = target.position.x,
                .y = target.position.y,
                .z = target.position.z,
            };
            rl.drawCylinder(ring_pos, target.radius + 5, target.radius + 5, 2, 16, .yellow);

            // Draw selection arrow above target
            const arrow_pos = rl.Vector3{
                .x = target.position.x,
                .y = target.position.y + target.radius + 15,
                .z = target.position.z,
            };
            rl.drawCube(arrow_pos, 5, 5, 5, .yellow);
        }
    }

    rl.endMode3D();

    // === 2D RENDERING (names, labels) ===
    // Draw entity names
    for (entities) |ent| {
        if (!ent.isAlive()) continue;

        const name_3d_pos = rl.Vector3{
            .x = ent.position.x,
            .y = ent.position.y + ent.radius + 10,
            .z = ent.position.z,
        };
        const name_2d_pos = rl.getWorldToScreen(name_3d_pos, camera);

        // Only draw if on screen
        if (name_2d_pos.x >= 0 and name_2d_pos.y >= 0) {
            const text_width = rl.measureText(ent.name, 10);
            const x_pos: i32 = @intFromFloat(name_2d_pos.x);
            const y_pos: i32 = @intFromFloat(name_2d_pos.y);
            rl.drawText(ent.name, x_pos - @divTrunc(text_width, 2), y_pos, 10, .white);
        }
    }

    // Draw player name
    const player_name_3d_pos = rl.Vector3{
        .x = player.*.position.x,
        .y = player.*.position.y + player.*.radius + 10,
        .z = player.*.position.z,
    };
    const player_name_2d_pos = rl.getWorldToScreen(player_name_3d_pos, camera);

    if (player_name_2d_pos.x >= 0 and player_name_2d_pos.y >= 0) {
        const text_width = rl.measureText(player.*.name, 12);
        const x_pos: i32 = @intFromFloat(player_name_2d_pos.x);
        const y_pos: i32 = @intFromFloat(player_name_2d_pos.y);
        rl.drawText(player.*.name, x_pos - @divTrunc(text_width, 2), y_pos, 12, .lime);
    }
}
