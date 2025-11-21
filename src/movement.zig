const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");

const Character = character.Character;

// Movement speed constants (Guild Wars style)
pub const BASE_MOVE_SPEED: f32 = 3.0; // Base units per frame
pub const BACKPEDAL_SPEED: f32 = 0.6; // 60% speed when backing up
pub const STRAFE_SPEED: f32 = 0.85; // 85% speed when strafing

/// Movement intent - what an entity wants to do this frame
pub const MovementIntent = struct {
    // Movement direction in local space (relative to facing/camera)
    // x: -1 = left, +1 = right
    // z: -1 = forward, +1 = backward
    local_x: f32 = 0.0,
    local_z: f32 = 0.0,

    // Facing direction (angle in radians) for calculating relative movement
    facing_angle: f32,

    // Whether to apply movement penalties (backpedal/strafe)
    apply_penalties: bool = true,
};

/// Apply movement to a character with collision detection
pub fn applyMovement(
    entity: *Character,
    intent: MovementIntent,
    all_entities: []Character,
    player: ?*Character,
    entity_index: ?usize,
) void {
    // Skip if no movement
    if (intent.local_x == 0.0 and intent.local_z == 0.0) return;

    // Normalize diagonal movement
    const magnitude = @sqrt(intent.local_x * intent.local_x + intent.local_z * intent.local_z);
    const norm_x = intent.local_x / magnitude;
    const norm_z = intent.local_z / magnitude;

    // Calculate speed multiplier based on movement direction
    var speed_multiplier: f32 = 1.0;

    if (intent.apply_penalties) {
        // Determine if moving backward (relative to facing direction)
        const forward_component = norm_z; // Positive = backward, negative = forward
        const lateral_component = @abs(norm_x);

        if (forward_component > 0.7) {
            // Moving primarily backward
            speed_multiplier = BACKPEDAL_SPEED; // 60% speed
        } else if (lateral_component > 0.7) {
            // Moving primarily sideways (strafe)
            speed_multiplier = STRAFE_SPEED; // 85% speed
        } else if (forward_component > 0.3 and lateral_component > 0.3) {
            // Diagonal backward movement
            speed_multiplier = 0.75; // 75% speed
        }
    }

    // Rotate movement by facing angle to world space
    const cos_angle = @cos(intent.facing_angle);
    const sin_angle = @sin(intent.facing_angle);
    const world_x = norm_x * cos_angle + norm_z * sin_angle;
    const world_z = -norm_x * sin_angle + norm_z * cos_angle;

    // Calculate new position
    const new_x = entity.position.x + world_x * BASE_MOVE_SPEED * speed_multiplier;
    const new_z = entity.position.z + world_z * BASE_MOVE_SPEED * speed_multiplier;

    // Store old position for collision resolution
    const old_x = entity.position.x;
    const old_z = entity.position.z;

    // Apply movement tentatively
    entity.position.x = new_x;
    entity.position.z = new_z;

    // Check collisions with all other entities
    var has_collision = false;

    // Check collision with player (if entity is not the player)
    if (player) |p| {
        if (entity != p) {
            if (entity.overlaps(p.*)) {
                has_collision = true;
                entity.resolveCollision(p.*);
            }
        }
    }

    // Check collision with all entities in the array
    for (all_entities, 0..) |*other, i| {
        // Skip self
        if (entity_index) |idx| {
            if (i == idx) continue;
        }

        // Skip dead entities
        if (!other.isAlive()) continue;

        // Skip if this is the same entity as the one we're moving
        if (entity.position.x == other.position.x and
            entity.position.z == other.position.z and
            entity == other) continue;

        if (entity.overlaps(other.*)) {
            has_collision = true;
            entity.resolveCollision(other.*);
        }
    }

    // If collision resolution pushed us too far, just revert to old position
    // This prevents entities from being pushed through walls or too far away
    const pushed_distance = @sqrt((entity.position.x - new_x) * (entity.position.x - new_x) +
        (entity.position.z - new_z) * (entity.position.z - new_z));

    if (pushed_distance > BASE_MOVE_SPEED * 2.0) {
        // Pushed too far, just stop at the collision point
        entity.position.x = old_x;
        entity.position.z = old_z;
    }
}
