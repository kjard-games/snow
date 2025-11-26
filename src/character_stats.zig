const std = @import("std");
const rl = @import("raylib");
const effects = @import("effects.zig");
const gear_slot = @import("gear_slot.zig");

const Gear = gear_slot.Gear;

// ============================================================================
// CHARACTER STATS - Core resource pools and regeneration systems
// ============================================================================
// This module handles the fundamental stats that all characters share:
// - Warmth (health) with pip-based regeneration (GW1-style)
// - Energy with school-based regeneration
// - Gear stat aggregation
//
// Design: Follows GW1's pip system where 1 pip = 2 resource/second

// ============================================================================
// CONSTANTS
// ============================================================================

/// Maximum regeneration/degeneration pips (GW1: -10 to +10)
pub const MAX_REGEN_PIPS: i8 = 10;
pub const MIN_REGEN_PIPS: i8 = -10;

/// Warmth per pip per second (GW1: 2 health per pip per second)
pub const WARMTH_PER_PIP_PER_SECOND: f32 = 2.0;

/// Default maximum warmth for characters
pub const DEFAULT_MAX_WARMTH: f32 = 200.0;

/// Default maximum energy (overridden by school)
pub const DEFAULT_MAX_ENERGY: u8 = 25;

// ============================================================================
// WARMTH SYSTEM - Health with pip-based regeneration
// ============================================================================

/// Warmth (health) state with GW1-style pip regeneration
pub const WarmthState = struct {
    current: f32,
    maximum: f32,
    regen_pips: i8 = 0, // -10 to +10 pips
    pip_accumulator: f32 = 0.0, // Tracks fractional warmth for smooth ticking

    /// Create a new warmth state at full health
    pub fn init(max_warmth: f32) WarmthState {
        return .{
            .current = max_warmth,
            .maximum = max_warmth,
        };
    }

    /// Create warmth state with specific current value
    pub fn initWith(current: f32, max_warmth: f32) WarmthState {
        return .{
            .current = current,
            .maximum = max_warmth,
        };
    }

    /// Get warmth as a percentage (0.0 to 1.0)
    pub fn percent(self: WarmthState) f32 {
        if (self.maximum <= 0) return 0;
        return self.current / self.maximum;
    }

    /// Check if at or below a warmth threshold
    pub fn isBelow(self: WarmthState, threshold_percent: f32) bool {
        return self.percent() < threshold_percent;
    }

    /// Check if above a warmth threshold
    pub fn isAbove(self: WarmthState, threshold_percent: f32) bool {
        return self.percent() >= threshold_percent;
    }

    /// Check if freezing (below 25% - causes penalties)
    pub fn isFreezing(self: WarmthState) bool {
        return self.isBelow(0.25);
    }

    /// Check if dead (at or below 0)
    pub fn isDepleted(self: WarmthState) bool {
        return self.current <= 0;
    }

    /// Apply damage, returning true if this caused death
    pub fn takeDamage(self: *WarmthState, damage: f32) bool {
        if (damage >= self.current) {
            self.current = 0;
            return true; // Died
        }
        self.current -= damage;
        return false;
    }

    /// Apply healing (capped at maximum)
    pub fn heal(self: *WarmthState, amount: f32) void {
        self.current = @min(self.maximum, self.current + amount);
    }

    /// Update warmth based on pip regeneration (call every tick)
    /// Returns true if warmth reached zero (death)
    pub fn update(self: *WarmthState, delta_time: f32) bool {
        const warmth_per_second = @as(f32, @floatFromInt(self.regen_pips)) * WARMTH_PER_PIP_PER_SECOND;
        const warmth_delta = warmth_per_second * delta_time;

        self.pip_accumulator += warmth_delta;

        // Apply whole points of warmth change
        if (@abs(self.pip_accumulator) >= 1.0) {
            const warmth_to_apply = self.pip_accumulator;
            self.current = @max(0.0, @min(self.maximum, self.current + warmth_to_apply));
            self.pip_accumulator -= warmth_to_apply;

            if (self.current <= 0) {
                return true; // Died from degeneration
            }
        }
        return false;
    }

    /// Set regeneration pips (clamped to valid range)
    pub fn setPips(self: *WarmthState, pips: i16) void {
        self.regen_pips = @intCast(@max(MIN_REGEN_PIPS, @min(MAX_REGEN_PIPS, pips)));
    }

    /// Add to current pips (clamped to valid range)
    pub fn addPips(self: *WarmthState, pips: i8) void {
        const new_pips = @as(i16, self.regen_pips) + @as(i16, pips);
        self.setPips(new_pips);
    }
};

// ============================================================================
// ENERGY SYSTEM - Resource for skills
// ============================================================================

/// Energy state with regeneration tracking
pub const EnergyState = struct {
    current: u8,
    maximum: u8,
    base_regen_per_second: f32, // From school
    accumulator: f32 = 0.0, // Tracks fractional energy

    /// Create energy state at full
    pub fn init(max_energy: u8, regen_rate: f32) EnergyState {
        return .{
            .current = max_energy,
            .maximum = max_energy,
            .base_regen_per_second = regen_rate,
        };
    }

    /// Create energy state with specific values
    pub fn initWith(current: u8, max_energy: u8, regen_rate: f32) EnergyState {
        return .{
            .current = current,
            .maximum = max_energy,
            .base_regen_per_second = regen_rate,
        };
    }

    /// Check if we have enough energy for a cost
    pub fn canAfford(self: EnergyState, cost: u8) bool {
        return self.current >= cost;
    }

    /// Check if we have enough energy for a modified cost
    pub fn canAffordModified(self: EnergyState, base_cost: u8, multiplier: f32) bool {
        const adjusted_cost = @as(f32, @floatFromInt(base_cost)) * multiplier;
        return @as(f32, @floatFromInt(self.current)) >= adjusted_cost;
    }

    /// Spend energy (returns false if insufficient)
    pub fn spend(self: *EnergyState, cost: u8) bool {
        if (self.current < cost) return false;
        self.current -= cost;
        return true;
    }

    /// Spend energy with a modifier applied to cost
    pub fn spendModified(self: *EnergyState, base_cost: u8, multiplier: f32) bool {
        const adjusted_cost = @as(u8, @intFromFloat(@as(f32, @floatFromInt(base_cost)) * multiplier));
        return self.spend(adjusted_cost);
    }

    /// Grant energy (capped at maximum)
    pub fn grant(self: *EnergyState, amount: u8) void {
        self.current = @min(self.maximum, self.current + amount);
    }

    /// Update energy regeneration (call every tick)
    /// gear_bonus: additional regen from gear
    /// effect_multiplier: multiplier from active effects
    pub fn update(self: *EnergyState, delta_time: f32, gear_bonus: f32, effect_multiplier: f32) void {
        var regen = self.base_regen_per_second + gear_bonus;
        regen *= effect_multiplier;

        const energy_delta = regen * delta_time;
        self.accumulator += energy_delta;

        // Convert whole points to energy
        if (self.accumulator >= 1.0) {
            const energy_to_add = @as(u8, @intFromFloat(self.accumulator));
            self.current = @min(self.maximum, self.current + energy_to_add);
            self.accumulator -= @as(f32, @floatFromInt(energy_to_add));
        }
    }

    /// Get energy as a percentage (0.0 to 1.0)
    pub fn percent(self: EnergyState) f32 {
        if (self.maximum == 0) return 0;
        return @as(f32, @floatFromInt(self.current)) / @as(f32, @floatFromInt(self.maximum));
    }
};

// ============================================================================
// GEAR STATS - Aggregated bonuses from equipped gear
// ============================================================================

/// Aggregated stat bonuses from all equipped gear
pub const GearStats = struct {
    total_padding: f32 = 0.0,
    warmth_regen_bonus: f32 = 0.0,
    energy_regen_bonus: f32 = 0.0,
    speed_multiplier: f32 = 1.0,

    /// Recalculate all stats from equipped gear array
    pub fn recalculate(gear_slots: []const ?*const Gear) GearStats {
        var stats = GearStats{};

        for (gear_slots) |maybe_gear| {
            if (maybe_gear) |g| {
                stats.total_padding += g.padding;
                stats.warmth_regen_bonus += g.warmth_regen_bonus;
                stats.energy_regen_bonus += g.energy_regen_bonus;
                stats.speed_multiplier *= g.speed_modifier;
            }
        }

        return stats;
    }

    /// Get warmth regen as pips (rounded down)
    /// 1 pip = 2 warmth/sec, so gear_regen / 2 = pips
    pub fn warmthRegenPips(self: GearStats) i8 {
        return @intFromFloat(self.warmth_regen_bonus / WARMTH_PER_PIP_PER_SECOND);
    }
};

// ============================================================================
// MOVEMENT STATS - Speed calculation helpers
// ============================================================================

/// Calculate final movement speed multiplier from all sources
pub fn calculateMoveSpeedMultiplier(
    warmth: WarmthState,
    gear_stats: GearStats,
    active_effects: []const ?effects.ActiveEffect,
    effect_count: u8,
) f32 {
    var speed_mult: f32 = 1.0;

    // Freezing penalty
    if (warmth.isFreezing()) {
        speed_mult *= 0.75; // -25% when freezing
    }

    // Gear modifiers
    speed_mult *= gear_stats.speed_multiplier;

    // Active effect modifiers
    const effect_speed_mult = effects.calculateMoveSpeedMultiplier(active_effects, effect_count);
    speed_mult *= effect_speed_mult;

    return speed_mult;
}

// ============================================================================
// PADDING/ARMOR HELPERS
// ============================================================================

/// Calculate effective padding with effect modifiers
pub fn calculateEffectivePadding(
    base_padding: f32,
    active_effects: []const ?effects.ActiveEffect,
    effect_count: u8,
) f32 {
    const armor_mult = effects.calculateArmorMultiplier(active_effects, effect_count);
    return base_padding * armor_mult;
}

/// Calculate damage reduction from padding (GW1-inspired formula)
/// damage_reduction = padding / (padding + 100)
/// final_damage = base_damage * (1 - damage_reduction)
pub fn calculateDamageReduction(padding: f32) f32 {
    return padding / (padding + 100.0);
}

/// Apply padding-based damage reduction to incoming damage
pub fn applyPaddingReduction(damage: f32, padding: f32) f32 {
    const reduction = calculateDamageReduction(padding);
    return damage * (1.0 - reduction);
}

// ============================================================================
// TESTS
// ============================================================================

test "warmth state basics" {
    var warmth = WarmthState.init(100.0);

    try std.testing.expectEqual(@as(f32, 100.0), warmth.current);
    try std.testing.expectEqual(@as(f32, 1.0), warmth.percent());
    try std.testing.expect(!warmth.isFreezing());

    // Take damage
    const died = warmth.takeDamage(80.0);
    try std.testing.expect(!died);
    try std.testing.expectEqual(@as(f32, 20.0), warmth.current);
    try std.testing.expect(warmth.isFreezing()); // Below 25%

    // Heal
    warmth.heal(50.0);
    try std.testing.expectEqual(@as(f32, 70.0), warmth.current);
    try std.testing.expect(!warmth.isFreezing());

    // Overheal caps at max
    warmth.heal(100.0);
    try std.testing.expectEqual(@as(f32, 100.0), warmth.current);
}

test "warmth regeneration" {
    var warmth = WarmthState.initWith(50.0, 100.0);
    warmth.regen_pips = 5; // +10 warmth/sec

    // Simulate 1 second
    _ = warmth.update(1.0);
    try std.testing.expect(warmth.current > 50.0);
}

test "energy state basics" {
    var energy = EnergyState.init(25, 1.0);

    try std.testing.expect(energy.canAfford(10));
    try std.testing.expect(energy.spend(10));
    try std.testing.expectEqual(@as(u8, 15), energy.current);
    try std.testing.expect(!energy.spend(20)); // Can't afford
    try std.testing.expectEqual(@as(u8, 15), energy.current); // Unchanged

    energy.grant(20);
    try std.testing.expectEqual(@as(u8, 25), energy.current); // Capped at max
}

test "gear stats aggregation" {
    // Simulate gear array
    const gear1 = Gear{
        .name = "Test Jacket",
        .slot = .jacket,
        .padding = 20.0,
        .warmth_regen_bonus = 2.0,
        .energy_regen_bonus = 0.5,
        .speed_modifier = 0.9,
    };
    const gear2 = Gear{
        .name = "Test Boots",
        .slot = .boots,
        .padding = 10.0,
        .warmth_regen_bonus = 1.0,
        .energy_regen_bonus = 0.0,
        .speed_modifier = 1.1,
    };

    const gear_array = [_]?*const Gear{ &gear1, &gear2, null, null, null, null };
    const stats = GearStats.recalculate(&gear_array);

    try std.testing.expectEqual(@as(f32, 30.0), stats.total_padding);
    try std.testing.expectEqual(@as(f32, 3.0), stats.warmth_regen_bonus);
    try std.testing.expectEqual(@as(f32, 0.5), stats.energy_regen_bonus);
    try std.testing.expect(@abs(stats.speed_multiplier - 0.99) < 0.01); // 0.9 * 1.1
}

test "damage reduction calculation" {
    // 0 padding = 0% reduction
    try std.testing.expectEqual(@as(f32, 0.0), calculateDamageReduction(0.0));

    // 100 padding = 50% reduction (100 / 200)
    try std.testing.expectEqual(@as(f32, 0.5), calculateDamageReduction(100.0));

    // 50 padding = 33% reduction (50 / 150)
    const reduction = calculateDamageReduction(50.0);
    try std.testing.expect(@abs(reduction - 0.333) < 0.01);
}
