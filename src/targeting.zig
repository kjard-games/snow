const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const entity_types = @import("entity.zig");

const Character = character.Character;
const EntityId = entity_types.EntityId;
const print = std.debug.print;

/// Cycle through enemies only (default tab behavior)
pub fn cycleEnemies(player: Character, entities: []const Character, selected_target: ?EntityId, forward: bool) ?EntityId {
    if (entities.len == 0) return null;

    // Build list of alive enemies, sorted by distance
    var enemies: [32]struct { id: EntityId, dist: f32 } = undefined;
    var enemy_count: usize = 0;

    for (entities) |ent| {
        if (ent.id == player.id) continue; // Skip self
        if (!ent.is_enemy) continue; // Only enemies
        if (!ent.isAlive()) continue; // Only alive

        const dx = ent.position.x - player.position.x;
        const dy = ent.position.y - player.position.y;
        const dz = ent.position.z - player.position.z;
        const dist = @sqrt(dx * dx + dy * dy + dz * dz);

        enemies[enemy_count] = .{ .id = ent.id, .dist = dist };
        enemy_count += 1;
        if (enemy_count >= 32) break;
    }

    if (enemy_count == 0) return null;

    // Sort by distance (bubble sort is fine for small arrays)
    for (0..enemy_count) |i| {
        for (i + 1..enemy_count) |j| {
            if (enemies[j].dist < enemies[i].dist) {
                const tmp = enemies[i];
                enemies[i] = enemies[j];
                enemies[j] = tmp;
            }
        }
    }

    // Find current target in sorted list
    var current_idx: ?usize = null;
    if (selected_target) |target_id| {
        for (enemies[0..enemy_count], 0..) |enemy, i| {
            if (enemy.id == target_id) {
                current_idx = i;
                break;
            }
        }
    }

    // Select next/previous/first
    const next_idx = if (current_idx) |idx|
        if (forward)
            (idx + 1) % enemy_count
        else if (idx == 0)
            enemy_count - 1
        else
            idx - 1
    else
        0; // Default to closest

    const result_id = enemies[next_idx].id;

    // Find name for print
    for (entities) |ent| {
        if (ent.id == result_id) {
            print("Target: {s} (enemy, {d:.1}m)\n", .{ ent.name, enemies[next_idx].dist });
            break;
        }
    }

    return result_id;
}

/// Cycle through allies only (for healing/support)
pub fn cycleAllies(player: Character, entities: []const Character, selected_target: ?EntityId, forward: bool) ?EntityId {
    if (entities.len == 0) return null;

    // Build list of alive allies (including self), sorted by distance
    var allies: [32]struct { id: EntityId, dist: f32, is_self: bool } = undefined;
    var ally_count: usize = 0;

    for (entities) |ent| {
        if (ent.is_enemy) continue; // Only allies
        if (!ent.isAlive()) continue; // Only alive

        const dx = ent.position.x - player.position.x;
        const dy = ent.position.y - player.position.y;
        const dz = ent.position.z - player.position.z;
        const dist = @sqrt(dx * dx + dy * dy + dz * dz);
        const is_self = ent.id == player.id;

        allies[ally_count] = .{ .id = ent.id, .dist = dist, .is_self = is_self };
        ally_count += 1;
        if (ally_count >= 32) break;
    }

    if (ally_count == 0) return null;

    // Sort by distance
    for (0..ally_count) |i| {
        for (i + 1..ally_count) |j| {
            if (allies[j].dist < allies[i].dist) {
                const tmp = allies[i];
                allies[i] = allies[j];
                allies[j] = tmp;
            }
        }
    }

    // Find current target in sorted list
    var current_idx: ?usize = null;
    if (selected_target) |target_id| {
        for (allies[0..ally_count], 0..) |ally, i| {
            if (ally.id == target_id) {
                current_idx = i;
                break;
            }
        }
    }

    // Select next/previous/first
    const next_idx = if (current_idx) |idx|
        if (forward)
            (idx + 1) % ally_count
        else if (idx == 0)
            ally_count - 1
        else
            idx - 1
    else
        0; // Default to closest (usually self)

    const result_id = allies[next_idx].id;

    // Find name for print
    for (entities) |ent| {
        if (ent.id == result_id) {
            const self_str = if (allies[next_idx].is_self) " (self)" else "";
            print("Target: {s} (ally{s}, {d:.1}m)\n", .{ ent.name, self_str, allies[next_idx].dist });
            break;
        }
    }

    return result_id;
}

// Legacy function - kept for compatibility but deprecated
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
        return entities[0].id;
    }

    // Cycle to next/previous
    const current = current_idx.?;
    const next_idx = if (forward)
        (current + 1) % entities.len
    else if (current == 0)
        entities.len - 1
    else
        current - 1;

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
