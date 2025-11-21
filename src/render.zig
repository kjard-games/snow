const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");

const Character = character.Character;
const print = std.debug.print;

pub fn draw(player: Character, entities: []const Character, selected_target: ?usize, camera: rl.Camera) void {
    rl.clearBackground(.dark_gray);

    rl.beginMode3D(camera);
    defer rl.endMode3D();

    // Draw ground plane
    rl.drawGrid(20, 50);

    // Draw entities
    for (entities, 0..) |ent, i| {
        // Skip dead entities
        if (!ent.isAlive()) continue;

        // Draw entity as sphere
        const color = if (ent.is_dead) rl.Color.gray else ent.color;
        rl.drawSphere(ent.position, ent.radius, color);
        rl.drawSphereWires(ent.position, ent.radius, 8, 8, .black);

        // Debug: print entity positions
        if (i == 0) {
            print("Character 0 at ({d:.1}, {d:.1}, {d:.1})\n", .{ ent.position.x, ent.position.y, ent.position.z });
        }

        // TODO: Fix entity name drawing - getWorldToScreen causing crashes
        // Draw name above entity (convert 3D to 2D)
        // const name_3d_pos = rl.Vector3{
        //     .x = entity.position.x,
        //     .y = entity.position.y + entity.radius + 10,
        //     .z = entity.position.z,
        // };
        // const name_2d_pos = rl.getWorldToScreen(name_3d_pos, self.camera);
        // rl.drawText(entity.name, @intFromFloat(name_2d_pos.x), @intFromFloat(name_2d_pos.y), 10, .white);
    }

    // Draw player
    const player_color = if (player.is_dead) rl.Color.gray else player.color;
    rl.drawSphere(player.position, player.radius, player_color);
    rl.drawSphereWires(player.position, player.radius, 8, 8, .black);

    // TODO: Fix player name drawing - getWorldToScreen causing crashes
    // Draw player name
    // const player_name_3d_pos = rl.Vector3{
    //     .x = self.player.position.x,
    //     .y = self.player.position.y + self.player.radius + 10,
    //     .z = self.player.position.z,
    // };
    // const player_name_2d_pos = rl.getWorldToScreen(player_name_3d_pos, self.camera);
    // rl.drawText(self.player.name, @intFromFloat(player_name_2d_pos.x), @intFromFloat(player_name_2d_pos.y), 12, .white);

    // Draw target selection indicator
    if (selected_target) |target_index| {
        if (target_index < entities.len) {
            const target = entities[target_index];

            // Skip if target is dead
            if (!target.isAlive()) return;

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
}
