const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const skills = @import("skills.zig");
const effects = @import("effects.zig");
const entity = @import("entity.zig");
const vfx = @import("vfx.zig");

const Character = character.Character;
const Skill = skills.Skill;
const Behavior = skills.Behavior;
const BehaviorTrigger = skills.BehaviorTrigger;
const BehaviorResponse = skills.BehaviorResponse;
const EntityId = entity.EntityId;
const EffectTarget = effects.EffectTarget;
const print = std.debug.print;

// ============================================================================
// COMBAT BEHAVIOR - Runtime Behavior Execution System
// ============================================================================
// This module handles the execution of Skill Behaviors at runtime.
// Behaviors intercept game events and respond with actions:
// - Death prevention (Golden Parachute)
// - Damage redirection (Guardian Angel, Conflict Resolution)
// - Damage splitting (Spirit Link)
// - Buff stealing (Hostile Takeover)
// - Summon creation (Living Igloo)
//
// Philosophy: Effects modify stats. Behaviors intercept and redirect game flow.

// ============================================================================
// ACTIVE BEHAVIOR STATE - Tracks behaviors currently in effect
// ============================================================================

pub const MAX_ACTIVE_BEHAVIORS: usize = 5;

/// An active behavior instance on a character
pub const ActiveBehavior = struct {
    behavior: *const Behavior,
    time_remaining_ms: u32,
    activations_remaining: u8, // 0 = unlimited
    source_skill: ?*const Skill = null,
    source_character_id: ?EntityId = null,
    cooldown_remaining_ms: u32 = 0,

    /// Check if this behavior can trigger
    pub fn canTrigger(self: ActiveBehavior) bool {
        if (self.cooldown_remaining_ms > 0) return false;
        if (self.activations_remaining == 0) return true; // unlimited
        return self.activations_remaining > 0;
    }

    /// Consume one activation (if limited)
    pub fn consumeActivation(self: *ActiveBehavior) void {
        if (self.activations_remaining > 0) {
            self.activations_remaining -= 1;
        }
        self.cooldown_remaining_ms = self.behavior.cooldown_ms;
    }
};

/// State for tracking active behaviors on a character
pub const BehaviorState = struct {
    active: [MAX_ACTIVE_BEHAVIORS]?ActiveBehavior = [_]?ActiveBehavior{null} ** MAX_ACTIVE_BEHAVIORS,
    count: u8 = 0,

    /// Add a behavior from a skill
    pub fn addFromSkill(self: *BehaviorState, skill_with_behavior: *const Skill, source_id: ?EntityId) bool {
        const behavior = skill_with_behavior.behavior orelse return false;

        if (self.count >= MAX_ACTIVE_BEHAVIORS) return false;

        self.active[self.count] = .{
            .behavior = behavior,
            .time_remaining_ms = behavior.duration_ms,
            .activations_remaining = behavior.max_activations,
            .source_skill = skill_with_behavior,
            .source_character_id = source_id,
        };
        self.count += 1;
        return true;
    }

    /// Update all behaviors, removing expired ones
    pub fn update(self: *BehaviorState, delta_time_ms: u32) void {
        var i: usize = 0;
        while (i < self.count) {
            if (self.active[i]) |*behavior| {
                // Update cooldown
                if (behavior.cooldown_remaining_ms > delta_time_ms) {
                    behavior.cooldown_remaining_ms -= delta_time_ms;
                } else {
                    behavior.cooldown_remaining_ms = 0;
                }

                // Check expiration
                const should_remove = blk: {
                    // Duration-based expiration (0 = permanent until activations consumed)
                    if (behavior.behavior.duration_ms > 0) {
                        if (behavior.time_remaining_ms <= delta_time_ms) {
                            break :blk true;
                        }
                        behavior.time_remaining_ms -= delta_time_ms;
                    }

                    // Activation-based expiration (for one-shot behaviors)
                    if (behavior.behavior.max_activations > 0 and behavior.activations_remaining == 0) {
                        break :blk true;
                    }

                    break :blk false;
                };

                if (should_remove) {
                    self.count -= 1;
                    self.active[i] = self.active[self.count];
                    self.active[self.count] = null;
                    // Don't increment i - check swapped element
                } else {
                    i += 1;
                }
            } else {
                i += 1;
            }
        }
    }

    /// Find behaviors that match a specific trigger
    pub fn findByTrigger(self: *BehaviorState, trigger: BehaviorTrigger) ?*ActiveBehavior {
        for (self.active[0..self.count]) |*maybe_behavior| {
            if (maybe_behavior.*) |*behavior| {
                if (behavior.behavior.trigger == trigger and behavior.canTrigger()) {
                    return behavior;
                }
            }
        }
        return null;
    }

    /// Clear all behaviors
    pub fn clear(self: *BehaviorState) void {
        for (&self.active) |*b| {
            b.* = null;
        }
        self.count = 0;
    }
};

// ============================================================================
// BEHAVIOR EXECUTION CONTEXT
// ============================================================================

/// Context for executing a behavior
pub const BehaviorContext = struct {
    /// The character that has the behavior
    owner: *Character,
    /// The character that triggered the behavior (if different from owner)
    trigger_source: ?*Character = null,
    /// Incoming damage amount (for damage-related triggers)
    incoming_damage: f32 = 0,
    /// All characters in the match (for AoE targeting)
    all_characters: []Character,
    /// VFX manager for visual feedback
    vfx_manager: *vfx.VFXManager,
};

/// Result of behavior execution
pub const BehaviorResult = struct {
    /// Was the behavior executed?
    executed: bool = false,
    /// Should the triggering event be prevented?
    prevent_event: bool = false,
    /// Modified damage amount (for damage interception)
    modified_damage: f32 = 0,
    /// Characters that received redirected damage
    redirected_to: ?*Character = null,
    /// Amount of damage that was redirected
    redirected_damage: f32 = 0,
};

// ============================================================================
// BEHAVIOR EXECUTION
// ============================================================================

/// Execute a death prevention behavior
/// Returns true if death should be prevented
pub fn executeDeathPrevention(
    ctx: BehaviorContext,
    behavior: *ActiveBehavior,
) BehaviorResult {
    var result = BehaviorResult{};

    switch (behavior.behavior.response) {
        .prevent => {
            // Simply prevent death
            result.executed = true;
            result.prevent_event = true;
            behavior.consumeActivation();
            print("{s}'s death was prevented!\n", .{ctx.owner.name});
        },
        .heal_percent => |heal| {
            // Heal to percentage of max warmth
            const heal_amount = ctx.owner.stats.max_warmth * heal.percent;
            ctx.owner.stats.warmth = heal_amount;
            result.executed = true;
            result.prevent_event = true;
            behavior.consumeActivation();
            print("{s} survived with {d:.0} warmth!\n", .{ ctx.owner.name, heal_amount });

            // Spawn heal VFX
            ctx.vfx_manager.spawnDamageNumber(heal_amount, ctx.owner.position, .heal);

            // If there's an effect to grant (like invulnerability), apply it
            if (heal.grant_effect) |effect| {
                ctx.owner.addEffect(effect, ctx.owner.id);
                print("{s} gained {s}!\n", .{ ctx.owner.name, effect.name });
            }
        },
        .grant_effect => |effect| {
            // Apply an effect (like invulnerability) and prevent death
            ctx.owner.addEffect(effect, ctx.owner.id);
            ctx.owner.stats.warmth = 1; // Survive with 1 warmth
            result.executed = true;
            result.prevent_event = true;
            behavior.consumeActivation();
            print("{s} survived and gained {s}!\n", .{ ctx.owner.name, effect.name });
        },
        else => {},
    }

    return result;
}

/// Execute a damage interception behavior
/// Returns the result with potentially modified damage
pub fn executeDamageInterception(
    ctx: BehaviorContext,
    behavior: *ActiveBehavior,
) BehaviorResult {
    var result = BehaviorResult{
        .modified_damage = ctx.incoming_damage,
    };

    switch (behavior.behavior.response) {
        .prevent => {
            // Block the damage entirely
            result.executed = true;
            result.modified_damage = 0;
            behavior.consumeActivation();
            print("{s} blocked {d:.0} damage!\n", .{ ctx.owner.name, ctx.incoming_damage });
        },
        .redirect_to_self => {
            // Redirect damage from ally to self
            if (ctx.trigger_source) |ally| {
                result.executed = true;
                result.prevent_event = true; // Prevent damage to ally
                result.redirected_to = ctx.owner;
                result.redirected_damage = ctx.incoming_damage;
                behavior.consumeActivation();
                print("{s} redirected {d:.0} damage from {s} to self!\n", .{
                    ctx.owner.name,
                    ctx.incoming_damage,
                    ally.name,
                });
            }
        },
        .redirect_to_source => {
            // Reflect damage back to attacker
            if (ctx.trigger_source) |attacker| {
                result.executed = true;
                result.modified_damage = 0; // No damage to owner
                result.redirected_to = attacker;
                result.redirected_damage = ctx.incoming_damage;
                behavior.consumeActivation();
                print("{s} reflected {d:.0} damage back to {s}!\n", .{
                    ctx.owner.name,
                    ctx.incoming_damage,
                    attacker.name,
                });
            }
        },
        .split_damage => |split| {
            // Split damage among linked allies
            const targets = findTargets(ctx.all_characters, ctx.owner, split.among);
            if (targets.count > 0) {
                const share_amount = ctx.incoming_damage * split.share_percent;
                const per_target = switch (split.split_type) {
                    .equal => share_amount / @as(f32, @floatFromInt(targets.count + 1)), // +1 for owner
                    .proportional_max_warmth => share_amount / @as(f32, @floatFromInt(targets.count + 1)), // TODO: proper proportional
                    .absorb_remainder => share_amount / @as(f32, @floatFromInt(targets.count)),
                };

                // Apply split damage to each target
                for (targets.characters[0..targets.count]) |maybe_target| {
                    if (maybe_target) |target| {
                        target.takeDamage(per_target);
                        ctx.vfx_manager.spawnDamageNumber(per_target, target.position, .damage);
                        print("{s} shared {d:.0} damage with {s}!\n", .{
                            ctx.owner.name,
                            per_target,
                            target.name,
                        });
                    }
                }

                // Owner takes their share
                result.executed = true;
                result.modified_damage = per_target;
                behavior.consumeActivation();
            }
        },
        .deal_damage => |dmg| {
            // Deal damage to source (thorns-style)
            if (ctx.trigger_source) |source| {
                source.takeDamage(dmg.amount);
                ctx.vfx_manager.spawnDamageNumber(dmg.amount, source.position, .damage);
                result.executed = true;
                print("{s} dealt {d:.0} retaliatory damage to {s}!\n", .{
                    ctx.owner.name,
                    dmg.amount,
                    source.name,
                });
            }
        },
        else => {},
    }

    return result;
}

/// Execute a taunt behavior
pub fn executeTaunt(
    ctx: BehaviorContext,
    behavior: *ActiveBehavior,
) BehaviorResult {
    var result = BehaviorResult{};

    if (behavior.behavior.response == .force_target_self) {
        // Find all enemies in range and force them to target owner
        const targets = findTargets(ctx.all_characters, ctx.owner, .foes_in_earshot);
        for (targets.characters[0..targets.count]) |maybe_foe| {
            if (maybe_foe) |foe| {
                // The AI system should check for forced targets
                // For now, we just mark that taunt is active
                print("{s} is taunting {s}!\n", .{ ctx.owner.name, foe.name });
            }
        }
        result.executed = true;
        // Don't consume activation - taunt is continuous
    }

    return result;
}

// ============================================================================
// TARGET FINDING
// ============================================================================

pub const TargetList = struct {
    characters: [12]?*Character = [_]?*Character{null} ** 12,
    count: u8 = 0,
};

/// Find characters matching a target specification
pub fn findTargets(
    all_characters: []Character,
    owner: *Character,
    target_type: EffectTarget,
) TargetList {
    var result = TargetList{};
    const EARSHOT_RANGE: f32 = 200.0;
    const ADJACENT_RANGE: f32 = 50.0;

    for (all_characters) |*char| {
        if (char.id == owner.id) continue;
        if (!char.isAlive()) continue;

        const distance = owner.distanceTo(char.*);
        const is_ally = owner.team.isAlly(char.team);
        const is_enemy = owner.team.isEnemy(char.team);

        const should_include = switch (target_type) {
            .self => false, // Already skipped
            .target => false, // Requires explicit target
            .adjacent_to_self => is_enemy and distance <= ADJACENT_RANGE,
            .adjacent_to_target => false, // Requires target position
            .allies_in_earshot => is_ally and distance <= EARSHOT_RANGE,
            .foes_in_earshot => is_enemy and distance <= EARSHOT_RANGE,
            .allies_near_target => false, // Requires target
            .foes_near_target => false, // Requires target
            .source_of_damage => false, // Requires context
            .pet => false, // TODO: summon system
            .all_summons => false, // TODO: summon system
            .linked_allies => is_ally and distance <= EARSHOT_RANGE, // Simplified: treat as allies in range
        };

        if (should_include and result.count < 12) {
            result.characters[result.count] = char;
            result.count += 1;
        }
    }

    return result;
}

// ============================================================================
// INTEGRATION HOOKS - Call these from combat.zig
// ============================================================================

/// Check for death prevention behaviors when a character would die
/// Returns true if death should be prevented
pub fn checkDeathPrevention(
    character_with_behavior: *Character,
    all_characters: []Character,
    vfx_manager: *vfx.VFXManager,
    behavior_state: *BehaviorState,
) bool {
    const maybe_behavior = behavior_state.findByTrigger(.on_would_die);
    if (maybe_behavior) |behavior| {
        const ctx = BehaviorContext{
            .owner = character_with_behavior,
            .all_characters = all_characters,
            .vfx_manager = vfx_manager,
        };
        const result = executeDeathPrevention(ctx, behavior);
        return result.prevent_event;
    }
    return false;
}

/// Check for damage interception behaviors when damage is about to be applied
/// Returns the modified damage amount
pub fn checkDamageInterception(
    target: *Character,
    attacker: ?*Character,
    incoming_damage: f32,
    all_characters: []Character,
    vfx_manager: *vfx.VFXManager,
    behavior_state: *BehaviorState,
) f32 {
    const maybe_behavior = behavior_state.findByTrigger(.on_take_damage);
    if (maybe_behavior) |behavior| {
        const ctx = BehaviorContext{
            .owner = target,
            .trigger_source = attacker,
            .incoming_damage = incoming_damage,
            .all_characters = all_characters,
            .vfx_manager = vfx_manager,
        };
        const result = executeDamageInterception(ctx, behavior);
        if (result.executed) {
            return result.modified_damage;
        }
    }
    return incoming_damage;
}

/// Check for ally damage interception (Guardian Angel style)
/// Called when an ally takes damage to see if this character wants to intercept
pub fn checkAllyDamageInterception(
    protector: *Character,
    protected_ally: *Character,
    attacker: ?*Character,
    incoming_damage: f32,
    all_characters: []Character,
    vfx_manager: *vfx.VFXManager,
    behavior_state: *BehaviorState,
) ?BehaviorResult {
    const maybe_behavior = behavior_state.findByTrigger(.on_ally_take_damage);
    if (maybe_behavior) |behavior| {
        const ctx = BehaviorContext{
            .owner = protector,
            .trigger_source = protected_ally,
            .incoming_damage = incoming_damage,
            .all_characters = all_characters,
            .vfx_manager = vfx_manager,
        };
        _ = attacker; // TODO: use for redirect_to_source
        const result = executeDamageInterception(ctx, behavior);
        if (result.executed) {
            return result;
        }
    }
    return null;
}

// ============================================================================
// TESTS
// ============================================================================

test "behavior state basic operations" {
    var state = BehaviorState{};

    // Start empty
    try std.testing.expectEqual(@as(u8, 0), state.count);
    try std.testing.expect(state.findByTrigger(.on_would_die) == null);
}
