const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const entity_types = @import("entity.zig");

const Character = character.Character;
const EntityId = entity_types.EntityId;
const print = std.debug.print;

pub fn cycleTarget(entities: []const Character, selected_target: ?EntityId, forward: bool) ?EntityId {
    if (entities.len == 0) return null;

    // Find current selection index
    var current_idx: ?usize = null;
    if (selected_target) |target_id| {
        for (entities, 0..) |ent, i| {
            if (ent.id == target_id) {
                current_idx = i;
                break;
            }
        }
    }

    // If no selection or not found, select first
    if (current_idx == null) {
        print("First target selected: {s}\n", .{entities[0].name});
        return entities[0].id;
    }

    // Cycle to next/previous
    const current = current_idx.?;
    var next_idx: usize = undefined;

    if (forward) {
        next_idx = (current + 1) % entities.len;
    } else {
        next_idx = if (current == 0) entities.len - 1 else current - 1;
    }

    // Print entity list and current selection
    print("=== ENTITY LIST ===\n", .{});
    for (entities, 0..) |ent, i| {
        const marker = if (i == next_idx) ">>> " else "    ";
        const type_str = if (ent.is_enemy) "ENEMY" else "ALLY";
        print("{s}ID:{d} {s} - {s}\n", .{ marker, ent.id, type_str, ent.name });
    }
    print("==================\n", .{});

    return entities[next_idx].id;
}

pub fn getNearestEnemy(player: Character, entities: []const Character) ?EntityId {
    var nearest: ?EntityId = null;
    var min_dist: f32 = std.math.floatMax(f32);

    for (entities) |ent| {
        if (!ent.is_enemy) continue;
        if (!ent.isAlive()) continue; // Skip dead entities

        const dx = ent.position.x - player.position.x;
        const dy = ent.position.y - player.position.y;
        const dz = ent.position.z - player.position.z;
        const dist = @sqrt(dx * dx + dy * dy + dz * dz);

        if (dist < min_dist) {
            min_dist = dist;
            nearest = ent.id;
        }
    }

    return nearest;
}

pub fn getNearestAlly(player: Character, entities: []const Character) ?EntityId {
    var nearest: ?EntityId = null;
    var min_dist: f32 = std.math.floatMax(f32);

    for (entities) |ent| {
        if (ent.is_enemy) continue;
        if (!ent.isAlive()) continue; // Skip dead entities

        const dx = ent.position.x - player.position.x;
        const dy = ent.position.y - player.position.y;
        const dz = ent.position.z - player.position.z;
        const dist = @sqrt(dx * dx + dy * dy + dz * dz);

        if (dist < min_dist) {
            min_dist = dist;
            nearest = ent.id;
        }
    }

    return nearest;
}
