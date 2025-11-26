const std = @import("std");
const skills = @import("skills.zig");
const effects = @import("effects.zig");
const entity = @import("entity.zig");

const Skill = skills.Skill;
const EntityId = entity.EntityId;

// ============================================================================
// CHARACTER CASTING - Skill activation and cast state management
// ============================================================================
// This module handles the GW1-accurate skill casting system:
// - Cast states (idle, activating, aftercast)
// - Cast timing and interrupts
// - Skill queuing for out-of-range targets
// - Cooldown management
//
// Design: GW1's casting system has three phases:
// 1. Activation - The cast bar fills, can be interrupted/cancelled
// 2. Skill fires - Effect/projectile launches (instantaneous)
// 3. Aftercast - Animation recovery, can't start new skills

// ============================================================================
// CONSTANTS
// ============================================================================

/// Maximum number of skills in a skill bar
pub const MAX_SKILLS: usize = 8;

// Compile-time safety: ensure MAX_SKILLS fits in u8 for skill indexing
comptime {
    if (MAX_SKILLS > 255) {
        @compileError("MAX_SKILLS must fit in u8 for skill bar indexing");
    }
}

// ============================================================================
// CAST STATE - The three phases of skill use
// ============================================================================

/// GW1-accurate cast state phases
pub const CastState = enum {
    idle, // Not casting or in aftercast - can start new skills
    activating, // Cast bar filling - can be interrupted/cancelled
    aftercast, // Recovery animation - locked out of new skills

    /// Check if character can start a new skill
    pub fn canStartSkill(self: CastState) bool {
        return self == .idle;
    }

    /// Check if character is interruptible
    pub fn isInterruptible(self: CastState) bool {
        return self == .activating;
    }

    /// Check if character is doing anything skill-related
    pub fn isBusy(self: CastState) bool {
        return self != .idle;
    }
};

// ============================================================================
// SKILL QUEUE - GW1-style "run into range then cast"
// ============================================================================

/// Queued skill waiting to be cast when in range
pub const QueuedSkill = struct {
    skill_index: u8,
    target_id: EntityId,

    pub fn init(skill_index: u8, target_id: EntityId) QueuedSkill {
        return .{
            .skill_index = skill_index,
            .target_id = target_id,
        };
    }
};

// ============================================================================
// CASTING STATE - Full casting context for a character
// ============================================================================

/// Complete casting state for a character
pub const CastingState = struct {
    // Current cast state
    state: CastState = .idle,

    // What's being cast
    casting_skill_index: u8 = 0,
    cast_target_id: ?EntityId = null,

    // Timing
    cast_time_remaining: f32 = 0.0, // Seconds remaining in activation
    aftercast_time_remaining: f32 = 0.0, // Seconds remaining in aftercast

    // Flags
    skill_executed: bool = false, // Has the skill effect fired?

    // Skill queue (GW1-style run-into-range)
    queued_skill: ?QueuedSkill = null,
    is_approaching_for_skill: bool = false,

    // Cooldowns for all skills
    cooldowns: [MAX_SKILLS]f32 = [_]f32{0.0} ** MAX_SKILLS,

    // ========== STATE QUERIES ==========

    /// Check if character can start casting a new skill
    pub fn canStartCast(self: CastingState) bool {
        return self.state.canStartSkill();
    }

    /// Check if character is currently casting (in any phase)
    pub fn isCasting(self: CastingState) bool {
        return self.state.isBusy();
    }

    /// Check if the current cast can be cancelled
    /// Only skills with activation time > 0 can be cancelled
    pub fn canCancelCast(self: CastingState, skill_bar: []const ?*const Skill) bool {
        if (self.state != .activating) return false;
        if (self.casting_skill_index >= skill_bar.len) return false;

        const skill = skill_bar[self.casting_skill_index] orelse return false;
        return skill.activation_time_ms > 0;
    }

    /// Check if a specific skill is on cooldown
    pub fn isOnCooldown(self: CastingState, skill_index: u8) bool {
        if (skill_index >= MAX_SKILLS) return true;
        return self.cooldowns[skill_index] > 0;
    }

    /// Get remaining cooldown for a skill
    pub fn getCooldown(self: CastingState, skill_index: u8) f32 {
        if (skill_index >= MAX_SKILLS) return 0;
        return self.cooldowns[skill_index];
    }

    /// Check if character has a queued skill
    pub fn hasQueuedSkill(self: CastingState) bool {
        return self.queued_skill != null;
    }

    // ========== CAST LIFECYCLE ==========

    /// Start casting a skill
    /// Returns false if already casting
    pub fn startCast(self: *CastingState, skill_index: u8, skill: *const Skill, target_id: ?EntityId) bool {
        if (!self.canStartCast()) return false;

        self.state = .activating;
        self.casting_skill_index = skill_index;
        self.cast_target_id = target_id;
        self.cast_time_remaining = @as(f32, @floatFromInt(skill.activation_time_ms)) / 1000.0;
        self.skill_executed = false;

        return true;
    }

    /// Complete a cast (called when cast_time_remaining reaches 0)
    /// Transitions to aftercast phase
    pub fn completeCast(self: *CastingState, skill: *const Skill, cooldown_reduction: f32) void {
        // Set cooldown (with reduction applied)
        var cooldown_time = @as(f32, @floatFromInt(skill.recharge_time_ms)) / 1000.0;
        cooldown_time *= (1.0 - cooldown_reduction);
        self.cooldowns[self.casting_skill_index] = cooldown_time;

        // Transition to aftercast
        self.state = .aftercast;
        self.aftercast_time_remaining = @as(f32, @floatFromInt(skill.aftercast_ms)) / 1000.0;
        self.skill_executed = true;
    }

    /// Cancel the current cast (GW1-accurate)
    /// - Only works during activation phase
    /// - Energy is NOT refunded (already spent)
    /// - Skill does NOT go on cooldown
    /// - No aftercast delay
    pub fn cancelCast(self: *CastingState) void {
        if (self.state == .activating) {
            self.state = .idle;
            self.cast_time_remaining = 0;
            self.skill_executed = false;
            self.cast_target_id = null;
        }
    }

    /// Interrupt the current cast (from enemy skill or condition)
    /// Same as cancel but triggered externally
    pub fn interrupt(self: *CastingState) bool {
        if (self.state == .activating) {
            self.cancelCast();
            return true;
        }
        return false;
    }

    // ========== SKILL QUEUE ==========

    /// Queue a skill to cast when in range (GW1 behavior)
    pub fn queueSkill(self: *CastingState, skill_index: u8, target_id: EntityId) void {
        self.queued_skill = QueuedSkill.init(skill_index, target_id);
        self.is_approaching_for_skill = true;
    }

    /// Clear the skill queue
    pub fn clearQueue(self: *CastingState) void {
        self.queued_skill = null;
        self.is_approaching_for_skill = false;
    }

    // ========== UPDATE ==========

    /// Update casting state timers (call every tick)
    /// Returns .cast_complete if a cast just finished (skill should be executed)
    pub fn update(self: *CastingState, delta_time: f32) CastUpdateResult {
        var result = CastUpdateResult.none;

        // Update cooldowns
        for (&self.cooldowns) |*cooldown| {
            if (cooldown.* > 0) {
                cooldown.* = @max(0, cooldown.* - delta_time);
            }
        }

        // Update activation phase
        if (self.state == .activating) {
            self.cast_time_remaining = @max(0, self.cast_time_remaining - delta_time);
            if (self.cast_time_remaining <= 0 and !self.skill_executed) {
                result = .cast_complete;
                // Note: Caller must call completeCast() to transition to aftercast
            }
        }

        // Update aftercast phase
        if (self.state == .aftercast) {
            self.aftercast_time_remaining = @max(0, self.aftercast_time_remaining - delta_time);
            if (self.aftercast_time_remaining <= 0) {
                self.state = .idle;
                self.cast_target_id = null;
            }
        }

        return result;
    }

    /// Force transition to idle (used on death, etc.)
    pub fn forceIdle(self: *CastingState) void {
        self.state = .idle;
        self.cast_time_remaining = 0;
        self.aftercast_time_remaining = 0;
        self.skill_executed = false;
        self.cast_target_id = null;
        self.clearQueue();
    }
};

/// Result of casting state update
pub const CastUpdateResult = enum {
    none, // Nothing special happened
    cast_complete, // Activation finished, skill should execute
};

// ============================================================================
// SKILL BAR - Equipped skills and validation
// ============================================================================

/// Skill bar state with AP (elite) skill validation
pub const SkillBar = struct {
    skills: [MAX_SKILLS]?*const Skill = [_]?*const Skill{null} ** MAX_SKILLS,
    selected_index: u8 = 0,

    /// Equip a skill to a slot (enforces one-AP rule)
    /// Returns false if skill can't be equipped (e.g., second AP skill)
    pub fn equip(self: *SkillBar, skill: *const Skill, slot_index: u8) bool {
        if (slot_index >= MAX_SKILLS) return false;

        // Check AP (elite) rule
        if (skill.is_ap) {
            // Check all slots except target for existing AP
            for (self.skills, 0..) |maybe_existing, i| {
                if (i == slot_index) continue;
                if (maybe_existing) |existing| {
                    if (existing.is_ap) {
                        return false; // Already have an AP skill
                    }
                }
            }
        }

        self.skills[slot_index] = skill;
        return true;
    }

    /// Unequip a skill from a slot
    pub fn unequip(self: *SkillBar, slot_index: u8) void {
        if (slot_index < MAX_SKILLS) {
            self.skills[slot_index] = null;
        }
    }

    /// Get skill at index (or null)
    pub fn get(self: SkillBar, index: u8) ?*const Skill {
        if (index >= MAX_SKILLS) return null;
        return self.skills[index];
    }

    /// Get the currently selected skill
    pub fn getSelected(self: SkillBar) ?*const Skill {
        return self.get(self.selected_index);
    }

    /// Count equipped AP skills
    pub fn countApSkills(self: SkillBar) u8 {
        var count: u8 = 0;
        for (self.skills) |maybe_skill| {
            if (maybe_skill) |skill| {
                if (skill.is_ap) count += 1;
            }
        }
        return count;
    }

    /// Check if an AP skill is equipped
    pub fn hasApSkill(self: SkillBar) bool {
        return self.countApSkills() > 0;
    }

    /// Find the index of the equipped AP skill (if any)
    pub fn getApSkillIndex(self: SkillBar) ?u8 {
        for (self.skills, 0..) |maybe_skill, i| {
            if (maybe_skill) |skill| {
                if (skill.is_ap) return @intCast(i);
            }
        }
        return null;
    }

    /// Validate skill bar (at most one AP skill)
    pub fn isValid(self: SkillBar) bool {
        return self.countApSkills() <= 1;
    }

    /// Swap an AP skill with a new one (convenience for UI)
    /// Returns the slot where the new skill was equipped, or null if failed
    pub fn swapApSkill(self: *SkillBar, new_ap_skill: *const Skill) ?u8 {
        if (!new_ap_skill.is_ap) return null;

        // Find and replace existing AP skill
        if (self.getApSkillIndex()) |slot| {
            self.skills[slot] = new_ap_skill;
            return slot;
        }

        // No existing AP - find first empty slot
        for (self.skills, 0..) |maybe_skill, i| {
            if (maybe_skill == null) {
                self.skills[i] = new_ap_skill;
                return @intCast(i);
            }
        }

        return null; // No slots available
    }
};

// ============================================================================
// SKILL VALIDATION HELPERS
// ============================================================================

/// Check result for skill usage
pub const SkillCheckResult = enum {
    can_use,
    on_cooldown,
    not_enough_energy,
    already_casting,
    no_skill_equipped,
    invalid_index,
};

/// Check if a character can use a skill (pre-cast validation)
pub fn canUseSkill(
    casting: CastingState,
    skill_bar: SkillBar,
    skill_index: u8,
    current_energy: u8,
    energy_cost_multiplier: f32,
) SkillCheckResult {
    if (skill_index >= MAX_SKILLS) return .invalid_index;
    if (!casting.canStartCast()) return .already_casting;
    if (casting.isOnCooldown(skill_index)) return .on_cooldown;

    const skill = skill_bar.get(skill_index) orelse return .no_skill_equipped;

    // Check energy with modifier
    const adjusted_cost = @as(f32, @floatFromInt(skill.energy_cost)) * energy_cost_multiplier;
    if (@as(f32, @floatFromInt(current_energy)) < adjusted_cost) {
        return .not_enough_energy;
    }

    return .can_use;
}

// ============================================================================
// TESTS
// ============================================================================

test "cast state transitions" {
    const test_skill = Skill{
        .name = "Test Skill",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 5,
        .activation_time_ms = 1000,
        .aftercast_ms = 500,
        .recharge_time_ms = 5000,
    };

    var casting = CastingState{};

    // Should start idle
    try std.testing.expect(casting.canStartCast());
    try std.testing.expect(!casting.isCasting());

    // Start cast
    try std.testing.expect(casting.startCast(0, &test_skill, null));
    try std.testing.expect(!casting.canStartCast());
    try std.testing.expect(casting.isCasting());
    try std.testing.expectEqual(CastState.activating, casting.state);

    // Update until cast completes
    var result = casting.update(0.5);
    try std.testing.expectEqual(CastUpdateResult.none, result);

    result = casting.update(0.5);
    try std.testing.expectEqual(CastUpdateResult.cast_complete, result);

    // Complete cast
    casting.completeCast(&test_skill, 0.0);
    try std.testing.expectEqual(CastState.aftercast, casting.state);
    try std.testing.expect(casting.skill_executed);
    try std.testing.expect(casting.cooldowns[0] > 0);

    // Update through aftercast
    _ = casting.update(0.5);
    try std.testing.expectEqual(CastState.idle, casting.state);
}

test "cast cancellation" {
    const test_skill = Skill{
        .name = "Test Skill",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 5,
        .activation_time_ms = 1000,
        .aftercast_ms = 500,
        .recharge_time_ms = 5000,
    };

    var casting = CastingState{};
    _ = casting.startCast(0, &test_skill, null);

    // Cancel during activation
    casting.cancelCast();
    try std.testing.expectEqual(CastState.idle, casting.state);
    try std.testing.expect(!casting.skill_executed);
    try std.testing.expectEqual(@as(f32, 0.0), casting.cooldowns[0]); // No cooldown on cancel
}

test "skill bar AP validation" {
    const normal_skill = Skill{
        .name = "Normal",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 5,
        .is_ap = false,
    };
    const ap_skill1 = Skill{
        .name = "Elite 1",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 10,
        .is_ap = true,
    };
    const ap_skill2 = Skill{
        .name = "Elite 2",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 10,
        .is_ap = true,
    };

    var bar = SkillBar{};

    // Normal skills should equip fine
    try std.testing.expect(bar.equip(&normal_skill, 0));
    try std.testing.expect(bar.equip(&normal_skill, 1));

    // First AP skill should equip
    try std.testing.expect(bar.equip(&ap_skill1, 2));
    try std.testing.expect(bar.hasApSkill());
    try std.testing.expectEqual(@as(?u8, 2), bar.getApSkillIndex());

    // Second AP skill should fail
    try std.testing.expect(!bar.equip(&ap_skill2, 3));

    // Replacing AP slot should work
    try std.testing.expect(bar.equip(&ap_skill2, 2));
    try std.testing.expectEqual(@as(u8, 1), bar.countApSkills());
}

test "skill queue" {
    var casting = CastingState{};

    try std.testing.expect(!casting.hasQueuedSkill());

    casting.queueSkill(3, 42);
    try std.testing.expect(casting.hasQueuedSkill());
    try std.testing.expect(casting.is_approaching_for_skill);
    try std.testing.expectEqual(@as(u8, 3), casting.queued_skill.?.skill_index);
    try std.testing.expectEqual(@as(EntityId, 42), casting.queued_skill.?.target_id);

    casting.clearQueue();
    try std.testing.expect(!casting.hasQueuedSkill());
    try std.testing.expect(!casting.is_approaching_for_skill);
}
