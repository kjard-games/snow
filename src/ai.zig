const std = @import("std");
const character = @import("character.zig");
const targeting = @import("targeting.zig");
const combat = @import("combat.zig");

const Character = character.Character;
const print = std.debug.print;

pub const AIState = struct {
    next_skill_time: f32 = 0.0,
    skill_cooldown: f32 = 2.0, // seconds between AI skill casts
};

pub fn updateAI(
    entities: []Character,
    player: Character,
    delta_time: f32,
    ai_states: []AIState,
) void {
    for (entities, 0..) |*ent, i| {
        // Skip dead entities
        if (!ent.isAlive()) continue;

        // Skip if no AI state for this entity
        if (i >= ai_states.len) continue;

        const ai_state = &ai_states[i];

        // Update AI timer
        ai_state.next_skill_time -= delta_time;

        // Time to cast a skill?
        if (ai_state.next_skill_time <= 0) {
            // Find target
            var target: ?*Character = null;

            if (ent.is_enemy) {
                // Enemies target player
                target = @constCast(&player);
            } else {
                // Allies target nearest enemy
                if (targeting.getNearestEnemy(ent.*, entities)) |enemy_idx| {
                    target = &entities[enemy_idx];
                }
            }

            // Try to cast first available skill
            if (target) |tgt| {
                for (ent.skill_bar) |maybe_skill| {
                    if (maybe_skill) |skill| {
                        const result = combat.castSkill(ent, skill, tgt);
                        if (result == .success) {
                            // Reset AI timer
                            ai_state.next_skill_time = ai_state.skill_cooldown;
                            break;
                        }
                    }
                }
            }

            // If no skill was cast, reset timer anyway
            if (ai_state.next_skill_time <= 0) {
                ai_state.next_skill_time = ai_state.skill_cooldown;
            }
        }
    }
}
