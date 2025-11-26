const std = @import("std");
const skills = @import("skills.zig");
const entity = @import("entity.zig");
const equipment = @import("equipment.zig");

const Skill = skills.Skill;
const EntityId = entity.EntityId;
const Equipment = equipment.Equipment;

// ============================================================================
// CHARACTER COMBAT - Auto-attack, damage tracking, and melee systems
// ============================================================================
// This module handles GW1-style combat mechanics:
// - Auto-attack loop (spacebar to attack, continues until interrupted)
// - Damage monitor (tracks recent damage sources like GW1)
// - Melee lunge animations
// - Attack calculations based on equipment
//
// Design: GW1's auto-attack is always active when a target is selected.
// Skills are used between auto-attacks during the "aftercast" window.

// ============================================================================
// CONSTANTS
// ============================================================================

/// Maximum number of damage sources to track (GW1 damage monitor size)
pub const MAX_DAMAGE_SOURCES: usize = 6;

/// Default auto-attack interval (bare-hand snowball throw)
pub const DEFAULT_ATTACK_INTERVAL: f32 = 1.5;

/// Default auto-attack damage (bare-hand snowball)
pub const DEFAULT_ATTACK_DAMAGE: f32 = 10.0;

/// Default auto-attack range (snowball throw)
pub const DEFAULT_ATTACK_RANGE: f32 = 80.0;

/// Minimum attack range (melee distance)
pub const MIN_ATTACK_RANGE: f32 = 30.0;

/// Duration for damage sources before they fade (seconds)
pub const DAMAGE_SOURCE_TIMEOUT: f32 = 10.0;

/// Melee lunge duration (seconds)
pub const MELEE_LUNGE_DURATION: f32 = 0.15;

// ============================================================================
// DAMAGE SOURCE - Tracking damage for the damage monitor UI
// ============================================================================

/// Tracks a source of damage for the GW1-style damage monitor
pub const DamageSource = struct {
    skill_name: [:0]const u8,
    skill_ptr: ?*const Skill, // For displaying icon
    source_id: EntityId, // Who dealt the damage
    hit_count: u32, // How many times this source hit us
    time_since_last_hit: f32, // Fade out if not hit recently

    pub fn init(skill: *const Skill, source_id: EntityId) DamageSource {
        return .{
            .skill_name = skill.name,
            .skill_ptr = skill,
            .source_id = source_id,
            .hit_count = 1,
            .time_since_last_hit = 0.0,
        };
    }

    /// Record another hit from this source
    pub fn recordHit(self: *DamageSource) void {
        self.hit_count += 1;
        self.time_since_last_hit = 0.0;
    }

    /// Check if this source should be removed (timeout)
    pub fn isExpired(self: DamageSource) bool {
        return self.time_since_last_hit > DAMAGE_SOURCE_TIMEOUT;
    }
};

// ============================================================================
// DAMAGE MONITOR - GW1-style damage tracking
// ============================================================================

/// Tracks recent damage sources for the damage monitor UI
pub const DamageMonitor = struct {
    sources: [MAX_DAMAGE_SOURCES]?DamageSource = [_]?DamageSource{null} ** MAX_DAMAGE_SOURCES,
    count: u8 = 0,
    frozen: bool = false, // Freeze on death until resurrection

    /// Record damage from a skill
    pub fn recordDamage(self: *DamageMonitor, skill: *const Skill, source_id: EntityId) void {
        if (self.frozen) return;

        // Check if this source already exists
        for (self.sources[0..self.count]) |*maybe_source| {
            if (maybe_source.*) |*source| {
                // Match by skill name and source
                if (std.mem.eql(u8, source.skill_name, skill.name) and source.source_id == source_id) {
                    source.recordHit();
                    return;
                }
            }
        }

        // Add new damage source
        if (self.count < MAX_DAMAGE_SOURCES) {
            self.sources[self.count] = DamageSource.init(skill, source_id);
            self.count += 1;
        } else {
            // Replace oldest source (shift all left)
            var i: usize = 0;
            while (i < MAX_DAMAGE_SOURCES - 1) : (i += 1) {
                self.sources[i] = self.sources[i + 1];
            }
            self.sources[MAX_DAMAGE_SOURCES - 1] = DamageSource.init(skill, source_id);
        }
    }

    /// Update timers and remove expired sources
    pub fn update(self: *DamageMonitor, delta_time: f32) void {
        if (self.frozen) return;

        var i: usize = 0;
        while (i < self.count) {
            if (self.sources[i]) |*source| {
                source.time_since_last_hit += delta_time;

                if (source.isExpired()) {
                    // Shift remaining sources down
                    var j: usize = i;
                    while (j < self.count - 1) : (j += 1) {
                        self.sources[j] = self.sources[j + 1];
                    }
                    self.sources[self.count - 1] = null;
                    self.count -= 1;
                    continue; // Don't increment i, check this slot again
                }
            }
            i += 1;
        }
    }

    /// Freeze the monitor (on death)
    pub fn freeze(self: *DamageMonitor) void {
        self.frozen = true;
    }

    /// Unfreeze the monitor (on resurrection)
    pub fn unfreeze(self: *DamageMonitor) void {
        self.frozen = false;
    }

    /// Clear all damage sources (resurrection, new match)
    pub fn clear(self: *DamageMonitor) void {
        for (&self.sources) |*source| {
            source.* = null;
        }
        self.count = 0;
        self.frozen = false;
    }
};

// ============================================================================
// AUTO-ATTACK STATE - GW1-style auto-attack loop
// ============================================================================

/// Auto-attack state for GW1-style combat
pub const AutoAttackState = struct {
    /// Whether auto-attack loop is active
    is_active: bool = false,

    /// Time until next auto-attack
    timer: f32 = 0.0,

    /// Current auto-attack target
    target_id: ?EntityId = null,

    /// Start auto-attacking a target
    pub fn start(self: *AutoAttackState, target: EntityId) void {
        self.is_active = true;
        self.target_id = target;
        self.timer = 0.0; // Attack immediately
    }

    /// Stop auto-attacking
    pub fn stop(self: *AutoAttackState) void {
        self.is_active = false;
        self.target_id = null;
    }

    /// Check if ready to attack
    pub fn isReady(self: AutoAttackState) bool {
        return self.is_active and self.timer <= 0 and self.target_id != null;
    }

    /// Reset timer for next attack
    pub fn resetTimer(self: *AutoAttackState, attack_interval: f32) void {
        self.timer = attack_interval;
    }

    /// Update timer
    pub fn update(self: *AutoAttackState, delta_time: f32) void {
        if (self.timer > 0) {
            self.timer = @max(0, self.timer - delta_time);
        }
    }

    /// Clear state (death, etc.)
    pub fn clear(self: *AutoAttackState) void {
        self.is_active = false;
        self.timer = 0.0;
        self.target_id = null;
    }
};

// ============================================================================
// MELEE LUNGE STATE - Animation for melee attacks
// ============================================================================

/// Melee lunge animation state
pub const MeleeLungeState = struct {
    /// Time remaining in lunge animation
    time_remaining: f32 = 0.0,

    /// Position to return to after lunge
    return_position_x: f32 = 0.0,
    return_position_y: f32 = 0.0,
    return_position_z: f32 = 0.0,

    /// Check if currently lunging
    pub fn isLunging(self: MeleeLungeState) bool {
        return self.time_remaining > 0;
    }

    /// Start a lunge animation
    pub fn start(self: *MeleeLungeState, current_x: f32, current_y: f32, current_z: f32) void {
        self.time_remaining = MELEE_LUNGE_DURATION;
        self.return_position_x = current_x;
        self.return_position_y = current_y;
        self.return_position_z = current_z;
    }

    /// Update lunge timer
    pub fn update(self: *MeleeLungeState, delta_time: f32) void {
        if (self.time_remaining > 0) {
            self.time_remaining = @max(0, self.time_remaining - delta_time);
        }
    }

    /// Clear lunge state
    pub fn clear(self: *MeleeLungeState) void {
        self.time_remaining = 0.0;
    }
};

// ============================================================================
// COMBAT STATE - Combined combat state
// ============================================================================

/// Combined combat state for a character
pub const CombatState = struct {
    auto_attack: AutoAttackState = .{},
    damage_monitor: DamageMonitor = .{},
    melee_lunge: MeleeLungeState = .{},

    /// Update all combat systems
    pub fn update(self: *CombatState, delta_time: f32) void {
        self.auto_attack.update(delta_time);
        self.damage_monitor.update(delta_time);
        self.melee_lunge.update(delta_time);
    }

    /// Clear all combat state (death, resurrection)
    pub fn clearAll(self: *CombatState) void {
        self.auto_attack.clear();
        self.damage_monitor.clear();
        self.melee_lunge.clear();
    }

    /// Handle death
    pub fn onDeath(self: *CombatState) void {
        self.auto_attack.stop();
        self.damage_monitor.freeze();
        self.melee_lunge.clear();
    }

    /// Handle resurrection
    pub fn onResurrect(self: *CombatState) void {
        self.damage_monitor.unfreeze();
        self.damage_monitor.clear();
    }
};

// ============================================================================
// ATTACK CALCULATION HELPERS
// ============================================================================

/// Get attack interval based on equipped weapons
pub fn getAttackInterval(main_hand: ?*const Equipment, _: ?*const Equipment) f32 {
    // Two-handed weapon takes priority
    if (main_hand) |main| {
        if (main.hand_requirement == .two_hands) {
            return main.attack_interval;
        }
        // One-handed weapon in main hand
        if (main.hand_requirement == .one_hand) {
            return main.attack_interval;
        }
    }

    return DEFAULT_ATTACK_INTERVAL;
}

/// Get auto-attack damage based on equipment
pub fn getAutoAttackDamage(main_hand: ?*const Equipment, worn: ?*const Equipment) f32 {
    var base_damage = DEFAULT_ATTACK_DAMAGE;

    // Two-handed weapon replaces auto-attack entirely
    if (main_hand) |main| {
        if (main.hand_requirement == .two_hands) {
            return main.damage;
        }
        // One-handed weapon
        if (main.hand_requirement == .one_hand) {
            // Melee weapons replace auto-attack
            if (main.category == .melee_weapon) {
                return main.damage;
            }
            // Throwing tools modify snowball throw
            if (main.category == .throwing_tool) {
                return main.damage;
            }
        }
    }

    // Apply worn equipment bonuses (mittens add damage to bare hands)
    if (worn) |worn_item| {
        base_damage += worn_item.damage;
    }

    return base_damage;
}

/// Get auto-attack range based on equipment
pub fn getAutoAttackRange(main_hand: ?*const Equipment, worn: ?*const Equipment) f32 {
    // Two-handed weapon sets range
    if (main_hand) |main| {
        if (main.hand_requirement == .two_hands) {
            return main.range;
        }
        // One-handed weapon
        if (main.hand_requirement == .one_hand) {
            if (main.category == .melee_weapon or main.category == .throwing_tool) {
                return main.range;
            }
        }
    }

    // Apply worn equipment range modifiers
    var final_range = DEFAULT_ATTACK_RANGE;
    if (worn) |worn_item| {
        final_range += worn_item.range; // Can be negative (mittens penalty)
    }

    return @max(MIN_ATTACK_RANGE, final_range);
}

/// Check if using ranged auto-attacks
pub fn hasRangedAutoAttack(main_hand: ?*const Equipment) bool {
    if (main_hand) |main| {
        // Two-handed weapon determines ranged/melee
        if (main.hand_requirement == .two_hands) {
            return main.is_ranged;
        }
        // One-handed weapon
        if (main.hand_requirement == .one_hand) {
            if (main.category == .melee_weapon) {
                return false;
            }
            if (main.category == .throwing_tool) {
                return true;
            }
        }
    }

    // Default: bare-hand snowball throws are ranged
    return true;
}

// ============================================================================
// TESTS
// ============================================================================

test "auto-attack basic operations" {
    var auto = AutoAttackState{};

    // Start inactive
    try std.testing.expect(!auto.is_active);
    try std.testing.expect(!auto.isReady());

    // Start attacking
    auto.start(42);
    try std.testing.expect(auto.is_active);
    try std.testing.expect(auto.isReady());
    try std.testing.expectEqual(@as(?EntityId, 42), auto.target_id);

    // Reset timer
    auto.resetTimer(1.5);
    try std.testing.expect(!auto.isReady());

    // Update timer
    auto.update(1.0);
    try std.testing.expect(!auto.isReady());
    auto.update(0.5);
    try std.testing.expect(auto.isReady());

    // Stop
    auto.stop();
    try std.testing.expect(!auto.is_active);
}

test "damage monitor tracking" {
    var monitor = DamageMonitor{};

    const test_skill = Skill{
        .name = "Test Hit",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 5,
    };

    // Record first hit
    monitor.recordDamage(&test_skill, 1);
    try std.testing.expectEqual(@as(u8, 1), monitor.count);

    // Record same source again (should increment hit count)
    monitor.recordDamage(&test_skill, 1);
    try std.testing.expectEqual(@as(u8, 1), monitor.count);
    try std.testing.expectEqual(@as(u32, 2), monitor.sources[0].?.hit_count);

    // Record different source
    monitor.recordDamage(&test_skill, 2);
    try std.testing.expectEqual(@as(u8, 2), monitor.count);
}

test "damage monitor expiration" {
    var monitor = DamageMonitor{};

    const test_skill = Skill{
        .name = "Test Hit",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 5,
    };

    monitor.recordDamage(&test_skill, 1);
    try std.testing.expectEqual(@as(u8, 1), monitor.count);

    // Update past timeout
    monitor.update(DAMAGE_SOURCE_TIMEOUT + 1.0);
    try std.testing.expectEqual(@as(u8, 0), monitor.count);
}

test "damage monitor freeze on death" {
    var monitor = DamageMonitor{};

    const test_skill = Skill{
        .name = "Test Hit",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 5,
    };

    monitor.recordDamage(&test_skill, 1);
    try std.testing.expectEqual(@as(u8, 1), monitor.count);

    // Freeze
    monitor.freeze();

    // Should not record new damage while frozen
    monitor.recordDamage(&test_skill, 2);
    try std.testing.expectEqual(@as(u8, 1), monitor.count);

    // Unfreeze
    monitor.unfreeze();
    monitor.recordDamage(&test_skill, 2);
    try std.testing.expectEqual(@as(u8, 2), monitor.count);
}

test "melee lunge state" {
    var lunge = MeleeLungeState{};

    // Start not lunging
    try std.testing.expect(!lunge.isLunging());

    // Start lunge
    lunge.start(10.0, 0.0, 20.0);
    try std.testing.expect(lunge.isLunging());
    try std.testing.expectEqual(@as(f32, 10.0), lunge.return_position_x);
    try std.testing.expectEqual(@as(f32, 20.0), lunge.return_position_z);

    // Update past duration
    lunge.update(MELEE_LUNGE_DURATION + 0.1);
    try std.testing.expect(!lunge.isLunging());
}

test "attack calculation with no equipment" {
    const interval = getAttackInterval(null, null);
    try std.testing.expectEqual(DEFAULT_ATTACK_INTERVAL, interval);

    const damage = getAutoAttackDamage(null, null);
    try std.testing.expectEqual(DEFAULT_ATTACK_DAMAGE, damage);

    const range = getAutoAttackRange(null, null);
    try std.testing.expectEqual(DEFAULT_ATTACK_RANGE, range);

    try std.testing.expect(hasRangedAutoAttack(null));
}
