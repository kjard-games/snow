const std = @import("std");
const character = @import("character.zig");
const targeting = @import("targeting.zig");
const combat = @import("combat.zig");
const game_state = @import("game_state.zig");
const skills = @import("skills.zig");
const movement = @import("movement.zig");
const entity_types = @import("entity.zig");

const Character = character.Character;
const Skill = character.Skill;
const MovementIntent = movement.MovementIntent;
const EntityId = entity_types.EntityId;
const print = std.debug.print;

pub const AIRole = enum {
    damage_dealer, // Focus on dealing damage
    support, // Focus on healing/buffing allies
    disruptor, // Focus on interrupts and debuffs
};

pub const AIState = struct {
    next_skill_time: f32 = 0.0,
    skill_cooldown: f32 = 1.5, // seconds between AI skill casts (faster = more dangerous)
    role: AIRole = .damage_dealer,
};

pub const SkillDecision = struct {
    skill_idx: u8,
    target_ally: bool, // true = target ally, false = target enemy
};

// Behavior tree decision making
// Returns skill index and whether to target ally (true) or enemy (false)
fn selectSkillWithBehaviorTree(
    caster: *Character,
    target: *Character,
    all_entities: []Character,
    role: AIRole,
    rng: *std.Random,
) ?SkillDecision {
    switch (role) {
        .damage_dealer => {
            if (selectDamageSkill(caster, target, rng)) |idx| {
                return SkillDecision{ .skill_idx = idx, .target_ally = false };
            }
            return null;
        },
        .support => return selectSupportSkill(caster, all_entities, rng),
        .disruptor => {
            if (selectDisruptorSkill(caster, target, rng)) |idx| {
                return SkillDecision{ .skill_idx = idx, .target_ally = false };
            }
            return null;
        },
    }
}

// Damage dealer: prioritize high damage, use interrupts on casting targets
fn selectDamageSkill(caster: *Character, target: *Character, _: *std.Random) ?u8 {
    // Check if target is casting - use interrupt if available
    if (target.is_casting) {
        for (caster.skill_bar, 0..) |maybe_skill, idx| {
            if (maybe_skill) |skill| {
                if (skill.interrupts and caster.canUseSkill(@intCast(idx))) {
                    return @intCast(idx);
                }
            }
        }
    }

    // Use highest damage skill available
    var best_skill: ?u8 = null;
    var best_damage: f32 = 0.0;

    for (caster.skill_bar, 0..) |maybe_skill, idx| {
        if (maybe_skill) |skill| {
            if (skill.damage > best_damage and caster.canUseSkill(@intCast(idx))) {
                best_damage = skill.damage;
                best_skill = @intCast(idx);
            }
        }
    }

    // Fallback: any available damage skill
    if (best_skill == null) {
        for (caster.skill_bar, 0..) |maybe_skill, idx| {
            if (maybe_skill) |skill| {
                if (skill.damage > 0 and caster.canUseSkill(@intCast(idx))) {
                    return @intCast(idx);
                }
            }
        }
    }

    return best_skill;
}

// Support: heal low health allies, buff team
// Returns skill index and whether it should be cast on an ally (true) or enemy (false)
fn selectSupportSkill(caster: *Character, all_entities: []Character, _: *std.Random) ?SkillDecision {

    // Find lowest health ally (check all entities - player is in entities array now!)
    var lowest_health_pct: f32 = 1.0;
    var needs_healing = false;

    // Check all allies in entities
    for (all_entities) |ent| {
        if (!ent.is_enemy and ent.isAlive()) {
            const health_pct = ent.warmth / ent.max_warmth;
            if (health_pct < lowest_health_pct) {
                lowest_health_pct = health_pct;
            }
            if (health_pct < 0.6) {
                needs_healing = true;
            }
        }
    }

    // Prioritize healing if ally is below 60% health
    if (needs_healing) {
        for (caster.skill_bar, 0..) |maybe_skill, idx| {
            if (maybe_skill) |skill| {
                if (skill.healing > 0 and caster.canUseSkill(@intCast(idx))) {
                    return SkillDecision{ .skill_idx = @intCast(idx), .target_ally = true };
                }
            }
        }
    }

    // Otherwise use buffs or damage
    for (caster.skill_bar, 0..) |maybe_skill, idx| {
        if (maybe_skill) |skill| {
            if ((skill.cozies.len > 0 or skill.damage > 0) and caster.canUseSkill(@intCast(idx))) {
                // Buffs should target allies, damage should target enemies
                const target_ally = skill.cozies.len > 0;
                return SkillDecision{ .skill_idx = @intCast(idx), .target_ally = target_ally };
            }
        }
    }

    return null;
}

// Disruptor: interrupt casts, apply debuffs
fn selectDisruptorSkill(caster: *Character, target: *Character, rng: *std.Random) ?u8 {

    // Always interrupt if target is casting
    if (target.is_casting) {
        for (caster.skill_bar, 0..) |maybe_skill, idx| {
            if (maybe_skill) |skill| {
                // Prefer interrupt skills, but also use daze-applying skills
                if ((skill.interrupts or skill.chills.len > 0) and caster.canUseSkill(@intCast(idx))) {
                    return @intCast(idx);
                }
            }
        }
    }

    // Apply debuffs if available
    for (caster.skill_bar, 0..) |maybe_skill, idx| {
        if (maybe_skill) |skill| {
            if (skill.chills.len > 0 and caster.canUseSkill(@intCast(idx))) {
                return @intCast(idx);
            }
        }
    }

    // Fallback to damage
    return selectDamageSkill(caster, target, rng);
}

// Calculate movement intent for AI based on role and target
fn calculateMovementIntent(
    ent: *const Character,
    target: *const Character,
    role: AIRole,
) MovementIntent {
    const distance = ent.distanceTo(target.*);
    const optimal_range = ent.player_position.getRangeMin();
    const max_range = ent.player_position.getRangeMax();

    // Calculate direction to target (world space)
    const dx = target.position.x - ent.position.x;
    const dz = target.position.z - ent.position.z;
    const dist_xz = @sqrt(dx * dx + dz * dz);

    if (dist_xz < 0.1) {
        // Too close to calculate direction, no movement
        return MovementIntent{
            .local_x = 0.0,
            .local_z = 0.0,
            .facing_angle = 0.0,
            .apply_penalties = false,
        };
    }

    // Normalized direction to target
    const dir_to_target_x = dx / dist_xz;
    const dir_to_target_z = dz / dist_xz;

    // Decide movement based on role and distance
    // Add dead zones to prevent jitter when at good range
    var move_world_x: f32 = 0.0;
    var move_world_z: f32 = 0.0;

    switch (role) {
        .damage_dealer => {
            // Maintain optimal range (kite if too close, advance if too far)
            const close_threshold = optimal_range * 0.7;
            const far_threshold = max_range * 0.9;
            const comfort_zone = 20.0; // Dead zone to prevent jitter

            if (distance < close_threshold - comfort_zone) {
                // Too close, back away from target
                move_world_x = -dir_to_target_x;
                move_world_z = -dir_to_target_z;
            } else if (distance > far_threshold + comfort_zone) {
                // Too far, move toward target
                move_world_x = dir_to_target_x;
                move_world_z = dir_to_target_z;
            } else if (distance >= close_threshold + comfort_zone and distance <= far_threshold - comfort_zone) {
                // At good range, occasional strafe (not every frame)
                const pos_hash = @abs(ent.position.x * 100 + ent.position.z * 100);
                const strafe_chance = @mod(@as(u32, @intFromFloat(pos_hash)), 120);
                if (strafe_chance < 30) { // Only strafe 25% of the time
                    // Strafe perpendicular to target direction
                    const strafe_dir: f32 = if (@mod(@as(i32, @intFromFloat(ent.position.x * 10)), 2) == 0) 1.0 else -1.0;
                    move_world_x = -dir_to_target_z * strafe_dir;
                    move_world_z = dir_to_target_x * strafe_dir;
                }
            }
        },
        .support => {
            // Stay at medium range (can heal anyone)
            const support_range: f32 = 150.0;
            const comfort_zone = 30.0;

            if (distance > support_range * 1.3 + comfort_zone) {
                move_world_x = dir_to_target_x;
                move_world_z = dir_to_target_z;
            } else if (distance < support_range * 0.5 - comfort_zone) {
                move_world_x = -dir_to_target_x;
                move_world_z = -dir_to_target_z;
            } else if (distance >= support_range * 0.6 and distance <= support_range * 1.2) {
                // Occasional strafe when at good range
                const pos_hash = @abs(ent.position.x * 100 + ent.position.z * 100);
                const strafe_chance = @mod(@as(u32, @intFromFloat(pos_hash)), 120);
                if (strafe_chance < 20) {
                    const strafe_dir: f32 = if (@mod(@as(i32, @intFromFloat(ent.position.x * 10)), 2) == 0) 1.0 else -1.0;
                    move_world_x = -dir_to_target_z * strafe_dir;
                    move_world_z = dir_to_target_x * strafe_dir;
                }
            }
        },
        .disruptor => {
            // Stay at medium-close range for interrupts
            const comfort_zone = 25.0;

            if (distance > optimal_range * 1.3 + comfort_zone) {
                move_world_x = dir_to_target_x;
                move_world_z = dir_to_target_z;
            } else if (distance < optimal_range * 0.4 - comfort_zone) {
                move_world_x = -dir_to_target_x;
                move_world_z = -dir_to_target_z;
            } else if (distance >= optimal_range * 0.5 and distance <= optimal_range * 1.2) {
                // Occasional strafe
                const pos_hash = @abs(ent.position.x * 100 + ent.position.z * 100);
                const strafe_chance = @mod(@as(u32, @intFromFloat(pos_hash)), 120);
                if (strafe_chance < 25) {
                    const strafe_dir: f32 = if (@mod(@as(i32, @intFromFloat(ent.position.x * 10)), 2) == 0) 1.0 else -1.0;
                    move_world_x = -dir_to_target_z * strafe_dir;
                    move_world_z = dir_to_target_x * strafe_dir;
                }
            }
        },
    }

    // For AI, we use world-space movement directly
    // Set facing_angle to 0 and put world movement in local_x/local_z
    // This way the movement system's rotation (by facing_angle=0) becomes identity
    return MovementIntent{
        .local_x = move_world_x,
        .local_z = move_world_z,
        .facing_angle = 0.0, // No rotation needed - already in world space
        .apply_penalties = false, // AI doesn't have backpedal/strafe penalties
    };
}

pub fn updateAI(
    entities: []Character,
    controlled_entity_id: EntityId,
    delta_time: f32,
    ai_states: []AIState,
    rng: *std.Random,
    vfx_manager: *@import("vfx.zig").VFXManager,
) void {
    // Find the controlled player entity
    var player_ent: ?*Character = null;
    for (entities) |*e| {
        if (e.id == controlled_entity_id) {
            player_ent = e;
            break;
        }
    }

    for (entities, 0..) |*ent, i| {
        // Skip dead entities
        if (!ent.isAlive()) continue;

        // Skip the player-controlled entity (no AI for player!)
        if (ent.id == controlled_entity_id) continue;

        // Skip if no AI state for this entity
        if (i >= ai_states.len) continue;

        const ai_state = &ai_states[i];

        // Find target for movement and skills
        var target: ?*Character = null;
        var target_id: ?EntityId = null;

        if (ent.is_enemy) {
            // Enemies target player
            if (player_ent) |player| {
                target = player;
                target_id = player.id;
            }
        } else {
            // Allies target nearest enemy
            if (targeting.getNearestEnemy(ent.*, entities)) |enemy_id| {
                // Find entity by ID
                for (entities) |*e| {
                    if (e.id == enemy_id) {
                        target = e;
                        target_id = enemy_id;
                        break;
                    }
                }
            } else {
                // No enemies, follow player
                target = player_ent;
            }
        }

        // Calculate and apply movement every tick
        if (target) |tgt| {
            const move_intent = calculateMovementIntent(ent, tgt, ai_state.role);
            movement.applyMovement(ent, move_intent, entities, null, null, delta_time);
        }

        // Update skill casting timer
        ai_state.next_skill_time -= delta_time;

        // Time to cast a skill?
        if (ai_state.next_skill_time <= 0 and target != null) {
            // Use behavior tree to select skill and target type
            const skill_decision = selectSkillWithBehaviorTree(ent, target.?, entities, ai_state.role, rng);

            if (skill_decision) |decision| {
                var actual_target: ?*Character = null;
                var actual_target_id: ?EntityId = null;

                if (decision.target_ally) {
                    // Find ally to heal/buff (prioritize lowest health)
                    var lowest_health_pct: f32 = 1.0;

                    // Check player (if we're an ally)
                    if (!ent.is_enemy and player_ent.?.isAlive()) {
                        const player_health_pct = player_ent.?.warmth / player_ent.?.max_warmth;
                        if (player_health_pct < lowest_health_pct) {
                            lowest_health_pct = player_health_pct;
                            actual_target = player_ent.?;
                            actual_target_id = player_ent.?.id;
                        }
                    }

                    // Check other allies in entities
                    for (entities, 0..) |*ally_ent, ally_idx| {
                        if (!ally_ent.is_enemy and ally_ent.isAlive() and ally_idx != i) {
                            const ally_health_pct = ally_ent.warmth / ally_ent.max_warmth;
                            if (ally_health_pct < lowest_health_pct) {
                                lowest_health_pct = ally_health_pct;
                                actual_target = ally_ent;
                                actual_target_id = ally_ent.id;
                            }
                        }
                    }

                    // If no one needs healing, target self
                    if (actual_target == null) {
                        actual_target = ent;
                        actual_target_id = ent.id;
                    }
                } else {
                    // Target enemy
                    actual_target = target;
                    actual_target_id = target_id;
                }

                const result = combat.tryStartCast(ent, decision.skill_idx, actual_target, actual_target_id, rng, vfx_manager);
                if (result == .success or result == .casting_started) {
                    // Reset AI timer
                    ai_state.next_skill_time = ai_state.skill_cooldown;
                }
            }

            // If no skill was cast, reset timer anyway
            if (ai_state.next_skill_time <= 0) {
                ai_state.next_skill_time = ai_state.skill_cooldown;
            }
        }
    }
}
