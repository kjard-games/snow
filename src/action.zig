/// Action execution system - deterministic, input-agnostic action handling
/// This module is the central point where player input commands and AI decisions
/// are executed against game state. By going through this system, both player and AI
/// use identical code paths, enabling headless simulation.
const std = @import("std");
const rl = @import("raylib");

const character = @import("character.zig");
const input = @import("input.zig");
const movement = @import("movement.zig");
const combat = @import("combat.zig");
const entity_types = @import("entity.zig");

const Character = character.Character;
const InputCommand = input.InputCommand;
const MovementIntent = movement.MovementIntent;
const EntityId = entity_types.EntityId;

const print = std.debug.print;

/// Execute a single InputCommand for a character
/// This is the canonical way both player and AI apply their actions
pub fn executeCommand(
    actor: *Character,
    command: InputCommand,
    entities: []Character,
    selected_target: *?EntityId,
    rng: *std.Random,
    vfx_manager: *@import("vfx.zig").VFXManager,
    terrain_grid: *@import("terrain.zig").TerrainGrid,
) void {
    // === SKILL USAGE ===
    if (command.skill_use) |skill_index| {
        if (skill_index < actor.skill_bar.len) {
            if (actor.skill_bar[skill_index]) |skill| {
                // Determine target
                const target = if (command.target_id) |tid|
                    findEntityById(entities, tid)
                else if (skill.target_type == .self)
                    actor
                else
                    null;

                // Try to cast the skill
                if (target) |tgt| {
                    _ = combat.tryStartCast(actor, skill_index, tgt, tgt.id, rng, vfx_manager, terrain_grid);
                }
            }
        }
    }

    // === TARGET UPDATES ===
    if (command.target_id) |tid| {
        selected_target.* = tid;
    }
}

/// Find an entity by ID in the entities list
fn findEntityById(entities: []Character, id: EntityId) ?*Character {
    for (entities) |*ent| {
        if (ent.id == id) return ent;
    }
    return null;
}

/// Generate an InputCommand from player input
/// This is the player input → command conversion
pub fn playerInputToCommand(
    _: *const Character,
    _: []const Character,
    selected_target: ?EntityId,
    input_state: *const input.InputState,
) InputCommand {
    var command = InputCommand{
        .movement = MovementIntent{
            .local_x = 0,
            .local_z = 0,
            .facing_angle = input_state.camera_angle,
            .apply_penalties = true,
        },
        .skill_use = null,
        .target_id = selected_target,
    };

    // Find first buffered skill press
    for (input_state.buffered_skills, 0..) |pressed, i| {
        if (pressed) {
            command.skill_use = @intCast(i);
            break;
        }
    }

    return command;
}

/// Generate an InputCommand from AI decision-making
/// This is the AI logic → command conversion
pub fn aiDecisionToCommand(
    _: *const Character,
    target: ?*const Character,
    _: []const Character,
) InputCommand {
    return InputCommand{
        .movement = MovementIntent{
            .local_x = 0,
            .local_z = 0,
            .facing_angle = 0,
            .apply_penalties = true,
        },
        .skill_use = null,
        .target_id = if (target) |t| t.id else null,
    };
}
