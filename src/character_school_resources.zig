const std = @import("std");
const school = @import("school.zig");
const skills = @import("skills.zig");

const School = school.School;
const SkillType = skills.SkillType;

// ============================================================================
// CHARACTER SCHOOL RESOURCES - School-specific secondary mechanics
// ============================================================================
// This module handles the unique resource systems for each school:
// - Private School: Credit/Debt system (spend max energy for power)
// - Public School: Grit stacks (build from combat, spend for abilities)
// - Homeschool: Sacrifice system (trade warmth for energy/power)
// - Waldorf: Rhythm system (timing-based bonuses)
// - Montessori: Variety bonus (rewards using different skill types)
//
// Design: Each school has a unique secondary resource that synergizes with
// their energy system and color pie identity.

// ============================================================================
// CONSTANTS
// ============================================================================

/// Maximum grit stacks (Public School)
pub const MAX_GRIT_STACKS: u8 = 5;

/// Maximum rhythm charge (Waldorf)
pub const MAX_RHYTHM_CHARGE: u8 = 5;

/// Number of recent skills to track for variety bonus (Montessori)
pub const MAX_RECENT_SKILLS: usize = 5;

/// Credit recovery rate (Private School) - seconds per point
pub const CREDIT_RECOVERY_SECONDS: f32 = 3.0;

/// Grit decay rate (Public School) - seconds of no combat before decay
pub const GRIT_DECAY_DELAY: f32 = 5.0;

/// Rhythm decay rate (Waldorf) - seconds until rhythm starts decaying
pub const RHYTHM_DECAY_DELAY: f32 = 3.0;

// ============================================================================
// PRIVATE SCHOOL - Credit/Debt System
// ============================================================================

/// Private School's Credit/Debt resource system
/// Mechanic: Spend max energy (credit) for powerful effects, then slowly recover
pub const CreditDebtState = struct {
    /// How much max energy is currently locked away (debt)
    debt: u8 = 0,

    /// Time until next credit recovery (1 point per CREDIT_RECOVERY_SECONDS)
    recovery_timer: f32 = 0.0,

    /// Take on debt (reduce max energy temporarily)
    pub fn takeCredit(self: *CreditDebtState, amount: u8, current_max_energy: u8) u8 {
        // Can't go below 5 max energy
        const max_debt = if (current_max_energy > 5) current_max_energy - 5 else 0;
        const actual_amount = @min(amount, max_debt - self.debt);
        self.debt += actual_amount;
        return actual_amount;
    }

    /// Get current effective max energy (base max - debt)
    pub fn getEffectiveMaxEnergy(self: CreditDebtState, base_max_energy: u8) u8 {
        return if (self.debt >= base_max_energy) 5 else base_max_energy - self.debt;
    }

    /// Check if character is "in debt" (for bonus effects)
    pub fn isInDebt(self: CreditDebtState) bool {
        return self.debt > 0;
    }

    /// Update credit recovery
    pub fn update(self: *CreditDebtState, delta_time: f32) void {
        if (self.debt > 0) {
            self.recovery_timer += delta_time;
            if (self.recovery_timer >= CREDIT_RECOVERY_SECONDS) {
                self.debt -= 1;
                self.recovery_timer = 0.0;
            }
        } else {
            self.recovery_timer = 0.0;
        }
    }

    /// Clear all debt (resurrection, etc.)
    pub fn clear(self: *CreditDebtState) void {
        self.debt = 0;
        self.recovery_timer = 0.0;
    }
};

// ============================================================================
// PUBLIC SCHOOL - Grit Stacks
// ============================================================================

/// Public School's Grit resource system
/// Mechanic: Build grit from combat (hitting enemies, taking damage), spend for powerful abilities
pub const GritState = struct {
    /// Current grit stacks (0 to MAX_GRIT_STACKS)
    stacks: u8 = 0,

    /// Time since last combat action (for decay)
    time_since_combat: f32 = 0.0,

    /// Gain grit stacks (from hitting enemies, etc.)
    pub fn gain(self: *GritState, amount: u8) void {
        self.stacks = @min(MAX_GRIT_STACKS, self.stacks + amount);
        self.time_since_combat = 0.0; // Reset decay timer
    }

    /// Spend grit stacks (for abilities)
    /// Returns true if successful (had enough grit)
    pub fn spend(self: *GritState, amount: u8) bool {
        if (self.stacks >= amount) {
            self.stacks -= amount;
            return true;
        }
        return false;
    }

    /// Check if character has enough grit
    pub fn has(self: GritState, amount: u8) bool {
        return self.stacks >= amount;
    }

    /// Check if grit is at max (for UI indicators)
    pub fn isFull(self: GritState) bool {
        return self.stacks >= MAX_GRIT_STACKS;
    }

    /// Update grit decay (stacks decay after period of no combat)
    pub fn update(self: *GritState, delta_time: f32, in_combat: bool) void {
        if (in_combat) {
            self.time_since_combat = 0.0;
        } else {
            self.time_since_combat += delta_time;

            // Decay 1 stack per second after delay
            if (self.time_since_combat >= GRIT_DECAY_DELAY and self.stacks > 0) {
                // Decay 1 stack per second
                if (self.time_since_combat >= GRIT_DECAY_DELAY + 1.0) {
                    self.stacks -= 1;
                    self.time_since_combat = GRIT_DECAY_DELAY; // Reset to decay delay
                }
            }
        }
    }

    /// Clear all grit (death, etc.)
    pub fn clear(self: *GritState) void {
        self.stacks = 0;
        self.time_since_combat = 0.0;
    }

    /// Mark combat action (hitting or being hit)
    pub fn onCombatAction(self: *GritState) void {
        self.time_since_combat = 0.0;
    }
};

// ============================================================================
// HOMESCHOOL - Sacrifice System
// ============================================================================

/// Homeschool's Sacrifice resource system
/// Mechanic: Trade warmth (health) for energy or powerful effects
pub const SacrificeState = struct {
    /// Cooldown on sacrifice ability (seconds)
    cooldown: f32 = 0.0,

    /// Check if sacrifice is available
    pub fn canSacrifice(self: SacrificeState) bool {
        return self.cooldown <= 0;
    }

    /// Alias for canSacrifice (used by UI)
    pub fn isReady(self: SacrificeState) bool {
        return self.canSacrifice();
    }

    /// Start sacrifice cooldown
    pub fn startCooldown(self: *SacrificeState, duration: f32) void {
        self.cooldown = duration;
    }

    /// Update cooldown
    pub fn update(self: *SacrificeState, delta_time: f32) void {
        if (self.cooldown > 0) {
            self.cooldown = @max(0, self.cooldown - delta_time);
        }
    }

    /// Calculate warmth cost for a sacrifice (percentage of max warmth)
    pub fn calculateWarmthCost(percent: f32, max_warmth: f32) f32 {
        return max_warmth * percent;
    }

    /// Check if character can afford a warmth sacrifice
    pub fn canAffordSacrifice(current_warmth: f32, max_warmth: f32, cost_percent: f32, min_warmth_percent: f32) bool {
        const cost = max_warmth * cost_percent;
        const min_warmth = max_warmth * min_warmth_percent;
        return current_warmth >= cost + min_warmth;
    }

    /// Clear cooldown (resurrection, etc.)
    pub fn clear(self: *SacrificeState) void {
        self.cooldown = 0.0;
    }
};

// ============================================================================
// WALDORF - Rhythm System
// ============================================================================

/// Waldorf's Rhythm resource system
/// Mechanic: Build rhythm by alternating skill types, spend for powerful abilities
pub const RhythmState = struct {
    /// Current rhythm charge (0 to MAX_RHYTHM_CHARGE)
    charge: u8 = 0,

    /// Time remaining in perfect timing window
    perfect_window: f32 = 0.0,

    /// Last skill type used (for alternation tracking)
    last_skill_type: ?SkillType = null,

    /// Time accumulator for decay (counts up when not in perfect window)
    decay_timer: f32 = 0.0,

    /// Rhythm consumed by the last skill cast (for damage calculation)
    /// Reset after damage is calculated
    last_consumed: u8 = 0,

    /// Attempt to build rhythm (returns true if rhythm was gained)
    pub fn attemptBuild(self: *RhythmState, skill_type: SkillType) bool {
        const gained = if (self.last_skill_type) |last_type| blk: {
            // Gain rhythm if alternating skill types
            break :blk skill_type != last_type;
        } else blk: {
            // First skill always builds rhythm
            break :blk true;
        };

        self.last_skill_type = skill_type;

        if (gained) {
            self.charge = @min(MAX_RHYTHM_CHARGE, self.charge + 1);
            self.perfect_window = RHYTHM_DECAY_DELAY; // Reset perfect window
            return true;
        }

        // Same skill type breaks rhythm
        self.perfect_window = 0.0;
        return false;
    }

    /// Spend rhythm (for abilities like Perfect Pitch)
    /// Returns true if successful
    pub fn spend(self: *RhythmState, amount: u8) bool {
        if (self.charge >= amount) {
            self.charge -= amount;
            return true;
        }
        return false;
    }

    /// Consume all rhythm and return the amount (for Crescendo)
    pub fn consumeAll(self: *RhythmState) u8 {
        const amount = self.charge;
        self.charge = 0;
        return amount;
    }

    /// Check if in perfect timing window
    pub fn isInPerfectWindow(self: RhythmState) bool {
        return self.perfect_window > 0;
    }

    /// Check if has enough rhythm
    pub fn has(self: RhythmState, amount: u8) bool {
        return self.charge >= amount;
    }

    /// Check if at max rhythm
    pub fn isFull(self: RhythmState) bool {
        return self.charge >= MAX_RHYTHM_CHARGE;
    }

    /// Update rhythm state
    pub fn update(self: *RhythmState, delta_time: f32) void {
        if (self.perfect_window > 0) {
            self.perfect_window = @max(0, self.perfect_window - delta_time);
            self.decay_timer = 0.0; // Reset decay while in perfect window
        } else if (self.charge > 0) {
            // Rhythm decays when not maintaining perfect window
            self.decay_timer += delta_time;

            // Decay 1 stack per second after perfect window expires
            if (self.decay_timer >= 1.0) {
                self.charge -= 1;
                self.decay_timer = 0.0;
            }
        }
    }

    /// Clear rhythm (death, etc.)
    pub fn clear(self: *RhythmState) void {
        self.charge = 0;
        self.perfect_window = 0.0;
        self.last_skill_type = null;
        self.decay_timer = 0.0;
        self.last_consumed = 0;
    }

    /// Grant rhythm directly (from skills like "Find Your Rhythm")
    pub fn grant(self: *RhythmState, amount: u8) void {
        self.charge = @min(MAX_RHYTHM_CHARGE, self.charge + amount);
    }
};

// ============================================================================
// MONTESSORI - Variety Bonus System
// ============================================================================

/// Montessori's Variety resource system
/// Mechanic: Rewards using different skill types with damage and energy bonuses
pub const VarietyState = struct {
    /// Recent skill types used (circular buffer)
    recent_types: [MAX_RECENT_SKILLS]?SkillType = [_]?SkillType{null} ** MAX_RECENT_SKILLS,

    /// Current index in circular buffer
    buffer_index: u8 = 0,

    /// Current variety bonus damage (0.0 to 0.5 = 0% to 50%)
    bonus_damage: f32 = 0.0,

    /// Record a skill type used
    pub fn recordSkillType(self: *VarietyState, skill_type: SkillType) void {
        self.recent_types[self.buffer_index] = skill_type;
        self.buffer_index = @intCast((@as(usize, self.buffer_index) + 1) % MAX_RECENT_SKILLS);
        self.recalculateBonus();
    }

    /// Count unique skill types in recent history
    pub fn countUniqueTypes(self: VarietyState) u8 {
        var seen: [8]bool = [_]bool{false} ** 8; // SkillType has 8 variants
        var count: u8 = 0;

        for (self.recent_types) |maybe_type| {
            if (maybe_type) |skill_type| {
                const index = @intFromEnum(skill_type);
                if (!seen[index]) {
                    seen[index] = true;
                    count += 1;
                }
            }
        }

        return count;
    }

    /// Alias for countUniqueTypes (used by UI)
    pub fn countUnique(self: VarietyState) u8 {
        return self.countUniqueTypes();
    }

    /// Check if a skill type has been used recently (in the buffer)
    pub fn hasUsedRecently(self: VarietyState, skill_type: SkillType) bool {
        for (self.recent_types) |maybe_type| {
            if (maybe_type) |recorded_type| {
                if (recorded_type == skill_type) {
                    return true;
                }
            }
        }
        return false;
    }

    /// Recalculate variety bonus based on unique skill types
    fn recalculateBonus(self: *VarietyState) void {
        const unique_count = self.countUniqueTypes();
        // 0 unique = 0%, 1 = 0%, 2 = 10%, 3 = 20%, 4 = 30%, 5 = 40-50%
        self.bonus_damage = if (unique_count <= 1)
            0.0
        else
            @min(0.5, @as(f32, @floatFromInt(unique_count - 1)) * 0.10);
    }

    /// Get damage multiplier (1.0 + bonus)
    pub fn getDamageMultiplier(self: VarietyState) f32 {
        return 1.0 + self.bonus_damage;
    }

    /// Check if last skill was different type (for bonus energy)
    pub fn wasLastTypeDifferent(self: VarietyState, skill_type: SkillType) bool {
        // Check the most recent recorded type
        const last_index = if (self.buffer_index == 0) MAX_RECENT_SKILLS - 1 else self.buffer_index - 1;
        if (self.recent_types[last_index]) |last_type| {
            return last_type != skill_type;
        }
        return true; // First skill counts as "different"
    }

    /// Clear variety tracking (death, etc.)
    pub fn clear(self: *VarietyState) void {
        for (&self.recent_types) |*t| {
            t.* = null;
        }
        self.buffer_index = 0;
        self.bonus_damage = 0.0;
    }
};

// ============================================================================
// SCHOOL RESOURCE STATE - Combined state for all schools
// ============================================================================

/// Combined school resource state (union-like, but all fields always present for simplicity)
/// The character only uses the fields relevant to their school
pub const SchoolResourceState = struct {
    credit_debt: CreditDebtState = .{},
    grit: GritState = .{},
    sacrifice: SacrificeState = .{},
    rhythm: RhythmState = .{},
    variety: VarietyState = .{},

    /// Update school-specific resources based on school
    pub fn update(self: *SchoolResourceState, char_school: School, delta_time: f32, in_combat: bool) void {
        switch (char_school) {
            .private_school => self.credit_debt.update(delta_time),
            .public_school => self.grit.update(delta_time, in_combat),
            .homeschool => self.sacrifice.update(delta_time),
            .waldorf => self.rhythm.update(delta_time),
            .montessori => {
                // Variety doesn't need time-based updates
            },
        }
    }

    /// Clear all resources (death, resurrection)
    pub fn clearAll(self: *SchoolResourceState) void {
        self.credit_debt.clear();
        self.grit.clear();
        self.sacrifice.clear();
        self.rhythm.clear();
        self.variety.clear();
    }

    /// Record skill use for appropriate school mechanics
    pub fn onSkillUse(self: *SchoolResourceState, char_school: School, skill_type: SkillType) void {
        switch (char_school) {
            .waldorf => _ = self.rhythm.attemptBuild(skill_type),
            .montessori => self.variety.recordSkillType(skill_type),
            else => {},
        }
    }

    /// Handle hit landing (for grit building)
    pub fn onHitLanded(self: *SchoolResourceState, char_school: School, grit_on_hit: u8) void {
        if (char_school == .public_school and grit_on_hit > 0) {
            self.grit.gain(grit_on_hit);
        }
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "credit debt basic operations" {
    var credit = CreditDebtState{};

    // Start with no debt
    try std.testing.expect(!credit.isInDebt());
    try std.testing.expectEqual(@as(u8, 30), credit.getEffectiveMaxEnergy(30));

    // Take credit
    _ = credit.takeCredit(10, 30);
    try std.testing.expect(credit.isInDebt());
    try std.testing.expectEqual(@as(u8, 20), credit.getEffectiveMaxEnergy(30));

    // Can't take credit below 5 max energy
    _ = credit.takeCredit(20, 30); // Would bring to 30-10-20 = 0, clamped to 5
    try std.testing.expect(credit.getEffectiveMaxEnergy(30) >= 5);
}

test "credit debt recovery" {
    var credit = CreditDebtState{};
    _ = credit.takeCredit(5, 30);
    try std.testing.expectEqual(@as(u8, 5), credit.debt);

    // Update for recovery time
    credit.update(CREDIT_RECOVERY_SECONDS);
    try std.testing.expectEqual(@as(u8, 4), credit.debt);

    credit.update(CREDIT_RECOVERY_SECONDS);
    try std.testing.expectEqual(@as(u8, 3), credit.debt);
}

test "grit basic operations" {
    var grit = GritState{};

    // Start empty
    try std.testing.expect(!grit.has(1));
    try std.testing.expect(!grit.isFull());

    // Gain grit
    grit.gain(3);
    try std.testing.expect(grit.has(3));
    try std.testing.expectEqual(@as(u8, 3), grit.stacks);

    // Spend grit
    try std.testing.expect(grit.spend(2));
    try std.testing.expectEqual(@as(u8, 1), grit.stacks);

    // Can't overspend
    try std.testing.expect(!grit.spend(5));
    try std.testing.expectEqual(@as(u8, 1), grit.stacks);

    // Max cap
    grit.gain(100);
    try std.testing.expectEqual(MAX_GRIT_STACKS, grit.stacks);
    try std.testing.expect(grit.isFull());
}

test "rhythm alternation" {
    var rhythm = RhythmState{};

    // First skill always builds
    try std.testing.expect(rhythm.attemptBuild(.throw));
    try std.testing.expectEqual(@as(u8, 1), rhythm.charge);

    // Same type doesn't build
    try std.testing.expect(!rhythm.attemptBuild(.throw));
    try std.testing.expectEqual(@as(u8, 1), rhythm.charge);

    // Different type builds
    try std.testing.expect(rhythm.attemptBuild(.trick));
    try std.testing.expectEqual(@as(u8, 2), rhythm.charge);

    // Alternate back
    try std.testing.expect(rhythm.attemptBuild(.throw));
    try std.testing.expectEqual(@as(u8, 3), rhythm.charge);
}

test "rhythm spending" {
    var rhythm = RhythmState{};
    rhythm.grant(5);
    try std.testing.expect(rhythm.isFull());

    // Spend some
    try std.testing.expect(rhythm.spend(3));
    try std.testing.expectEqual(@as(u8, 2), rhythm.charge);

    // Can't overspend
    try std.testing.expect(!rhythm.spend(3));

    // Consume all
    const consumed = rhythm.consumeAll();
    try std.testing.expectEqual(@as(u8, 2), consumed);
    try std.testing.expectEqual(@as(u8, 0), rhythm.charge);
}

test "variety bonus calculation" {
    var variety = VarietyState{};

    // No variety initially
    try std.testing.expectEqual(@as(f32, 1.0), variety.getDamageMultiplier());

    // One skill type = no bonus
    variety.recordSkillType(.throw);
    try std.testing.expectEqual(@as(f32, 1.0), variety.getDamageMultiplier());

    // Two types = 10% bonus
    variety.recordSkillType(.trick);
    try std.testing.expectEqual(@as(f32, 1.1), variety.getDamageMultiplier());

    // Three types = 20% bonus
    variety.recordSkillType(.stance);
    try std.testing.expectEqual(@as(f32, 1.2), variety.getDamageMultiplier());

    // Four types = 30% bonus
    variety.recordSkillType(.gesture);
    try std.testing.expectEqual(@as(f32, 1.3), variety.getDamageMultiplier());
}

test "sacrifice cost calculation" {
    // 15% of 100 max warmth ≈ 15
    const cost = SacrificeState.calculateWarmthCost(0.15, 100.0);
    try std.testing.expect(cost > 14.9 and cost < 15.1);

    // Can afford: 50 warmth, 15% cost (15), 20% min (20) -> 50 >= 15 + 20 = 35
    try std.testing.expect(SacrificeState.canAffordSacrifice(50.0, 100.0, 0.15, 0.20));

    // Can't afford: 30 warmth, 15% cost (15), 20% min (20) -> 30 < 15 + 20 = 35
    try std.testing.expect(!SacrificeState.canAffordSacrifice(30.0, 100.0, 0.15, 0.20));
}
