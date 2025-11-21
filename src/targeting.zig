const std = @import("std");
const rl = @import("raylib");
const entity = @import("entity.zig");

const Entity = entity.Entity;
const print = std.debug.print;

pub fn cycleTarget(entities: []const Entity, selected_target: ?usize, forward: bool) ?usize {
    if (entities.len == 0) return null;

    if (selected_target == null) {
        print("First target selected: 0\n", .{});
        return 0;
    }

    const current = selected_target.?;
    var next = current;

    if (forward) {
        next = (current + 1) % entities.len;
    } else {
        next = if (current == 0) entities.len - 1 else current - 1;
    }

    // Print entity list and current selection
    print("=== ENTITY LIST ===\n", .{});
    for (entities, 0..) |ent, i| {
        const marker = if (i == next) ">>> " else "    ";
        const type_str = if (ent.is_enemy) "ENEMY" else "ALLY";
        print("{s}[{d}] {s} - {s}\n", .{ marker, i, type_str, ent.name });
    }
    print("==================\n", .{});

    return next;
}

pub fn getNearestEnemy(player: Entity, entities: []const Entity) ?usize {
    var nearest: ?usize = null;
    var min_dist: f32 = std.math.floatMax(f32);

    for (entities, 0..) |ent, i| {
        if (!ent.is_enemy) continue;

        const dx = ent.position.x - player.position.x;
        const dy = ent.position.y - player.position.y;
        const dz = ent.position.z - player.position.z;
        const dist = @sqrt(dx * dx + dy * dy + dz * dz);

        if (dist < min_dist) {
            min_dist = dist;
            nearest = i;
        }
    }

    return nearest;
}

pub fn getNearestAlly(player: Entity, entities: []const Entity) ?usize {
    var nearest: ?usize = null;
    var min_dist: f32 = std.math.floatMax(f32);

    for (entities, 0..) |ent, i| {
        if (ent.is_enemy) continue;

        const dx = ent.position.x - player.position.x;
        const dy = ent.position.y - player.position.y;
        const dz = ent.position.z - player.position.z;
        const dist = @sqrt(dx * dx + dy * dy + dz * dz);

        if (dist < min_dist) {
            min_dist = dist;
            nearest = i;
        }
    }

    return nearest;
}
