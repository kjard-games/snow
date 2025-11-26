const std = @import("std");
const skills = @import("skills.zig");
const effects = @import("effects.zig");
const entity = @import("entity.zig");

const EntityId = entity.EntityId;

// ============================================================================
// CHARACTER CONDITIONS - Chill, Cozy, and Effect Management
// ============================================================================
// This module handles GW1-style condition/buff systems:
// - Chills (debuffs) - negative effects from enemy skills
// - Cozies (buffs) - positive effects from ally skills
// - Effects (composable) - new unified effect system
// - Warmth pip regeneration/degeneration
//
// Design: GW1's condition system tracks:
// - Effect type (which buff/debuff)
// - Duration remaining
// - Stack intensity (for stackable effects)
// - Source (who applied it)

// ============================================================================
// CONSTANTS
// ============================================================================

/// Maximum number of active conditions (chills, cozies, or effects)
pub const MAX_ACTIVE_CONDITIONS: usize = 10;

/// Maximum warmth regen/degen pips (GW1 limits: -10 to +10)
pub const MAX_WARMTH_PIPS: i8 = 10;
pub const MIN_WARMTH_PIPS: i8 = -10;

/// Warmth per second per pip (GW1: 2 health per second per pip)
pub const WARMTH_PER_PIP_PER_SECOND: f32 = 2.0;

// ============================================================================
// CHILL STATE - Active debuffs
// ============================================================================

/// State for tracking active chills (debuffs)
pub const ChillState = struct {
    chills: [MAX_ACTIVE_CONDITIONS]?skills.ActiveChill = [_]?skills.ActiveChill{null} ** MAX_ACTIVE_CONDITIONS,
    count: u8 = 0,

    /// Check if a specific chill is active
    pub fn has(self: ChillState, chill: skills.Chill) bool {
        for (self.chills[0..self.count]) |maybe_active| {
            if (maybe_active) |active| {
                if (active.chill == chill) return true;
            }
        }
        return false;
    }

    /// Get active chill data (for UI, calculations)
    pub fn get(self: ChillState, chill: skills.Chill) ?*const skills.ActiveChill {
        for (self.chills[0..self.count]) |*maybe_active| {
            if (maybe_active.*) |*active| {
                if (active.chill == chill) return active;
            }
        }
        return null;
    }

    /// Add or stack a chill effect
    /// Returns true if the chill was added/stacked
    pub fn add(self: *ChillState, effect: skills.ChillEffect, source_id: ?EntityId) bool {
        // Check if chill already exists (stack or refresh)
        for (self.chills[0..self.count]) |*maybe_active| {
            if (maybe_active.*) |*active| {
                if (active.chill == effect.chill) {
                    // Refresh duration and stack intensity
                    active.time_remaining_ms = @max(active.time_remaining_ms, effect.duration_ms);
                    active.stack_intensity = @min(255, active.stack_intensity + effect.stack_intensity);
                    return true;
                }
            }
        }

        // Add new chill if we have space
        if (self.count < MAX_ACTIVE_CONDITIONS) {
            self.chills[self.count] = .{
                .chill = effect.chill,
                .time_remaining_ms = effect.duration_ms,
                .stack_intensity = effect.stack_intensity,
                .source_character_id = source_id,
            };
            self.count += 1;
            return true;
        }

        return false; // Array full
    }

    /// Remove a specific chill
    pub fn remove(self: *ChillState, chill: skills.Chill) bool {
        for (self.chills[0..self.count], 0..) |maybe_active, i| {
            if (maybe_active) |active| {
                if (active.chill == chill) {
                    // Swap with last and decrement count
                    self.count -= 1;
                    self.chills[i] = self.chills[self.count];
                    self.chills[self.count] = null;
                    return true;
                }
            }
        }
        return false;
    }

    /// Update all chills, removing expired ones
    /// Returns true if any chills were removed (for pip recalculation)
    pub fn update(self: *ChillState, delta_time_ms: u32) bool {
        var any_removed = false;
        var i: usize = 0;

        while (i < self.count) {
            if (self.chills[i]) |*chill| {
                if (chill.time_remaining_ms <= delta_time_ms) {
                    // Chill expired - swap with last
                    self.count -= 1;
                    self.chills[i] = self.chills[self.count];
                    self.chills[self.count] = null;
                    any_removed = true;
                    // Don't increment i - check swapped element
                } else {
                    chill.time_remaining_ms -= delta_time_ms;
                    i += 1;
                }
            } else {
                i += 1;
            }
        }

        return any_removed;
    }

    /// Clear all chills
    pub fn clear(self: *ChillState) void {
        for (&self.chills) |*chill| {
            chill.* = null;
        }
        self.count = 0;
    }
};

// ============================================================================
// COZY STATE - Active buffs
// ============================================================================

/// State for tracking active cozies (buffs)
pub const CozyState = struct {
    cozies: [MAX_ACTIVE_CONDITIONS]?skills.ActiveCozy = [_]?skills.ActiveCozy{null} ** MAX_ACTIVE_CONDITIONS,
    count: u8 = 0,

    /// Check if a specific cozy is active
    pub fn has(self: CozyState, cozy: skills.Cozy) bool {
        for (self.cozies[0..self.count]) |maybe_active| {
            if (maybe_active) |active| {
                if (active.cozy == cozy) return true;
            }
        }
        return false;
    }

    /// Get active cozy data (for UI, calculations)
    pub fn get(self: CozyState, cozy: skills.Cozy) ?*const skills.ActiveCozy {
        for (self.cozies[0..self.count]) |*maybe_active| {
            if (maybe_active.*) |*active| {
                if (active.cozy == cozy) return active;
            }
        }
        return null;
    }

    /// Add or stack a cozy effect
    /// Returns true if the cozy was added/stacked
    pub fn add(self: *CozyState, effect: skills.CozyEffect, source_id: ?EntityId) bool {
        // Check if cozy already exists (stack or refresh)
        for (self.cozies[0..self.count]) |*maybe_active| {
            if (maybe_active.*) |*active| {
                if (active.cozy == effect.cozy) {
                    // Refresh duration and stack intensity
                    active.time_remaining_ms = @max(active.time_remaining_ms, effect.duration_ms);
                    active.stack_intensity = @min(255, active.stack_intensity + effect.stack_intensity);
                    return true;
                }
            }
        }

        // Add new cozy if we have space
        if (self.count < MAX_ACTIVE_CONDITIONS) {
            self.cozies[self.count] = .{
                .cozy = effect.cozy,
                .time_remaining_ms = effect.duration_ms,
                .stack_intensity = effect.stack_intensity,
                .source_character_id = source_id,
            };
            self.count += 1;
            return true;
        }

        return false; // Array full
    }

    /// Remove a specific cozy
    pub fn remove(self: *CozyState, cozy: skills.Cozy) bool {
        for (self.cozies[0..self.count], 0..) |maybe_active, i| {
            if (maybe_active) |active| {
                if (active.cozy == cozy) {
                    // Swap with last and decrement count
                    self.count -= 1;
                    self.cozies[i] = self.cozies[self.count];
                    self.cozies[self.count] = null;
                    return true;
                }
            }
        }
        return false;
    }

    /// Update all cozies, removing expired ones
    /// Returns true if any cozies were removed (for pip recalculation)
    pub fn update(self: *CozyState, delta_time_ms: u32) bool {
        var any_removed = false;
        var i: usize = 0;

        while (i < self.count) {
            if (self.cozies[i]) |*cozy| {
                if (cozy.time_remaining_ms <= delta_time_ms) {
                    // Cozy expired - swap with last
                    self.count -= 1;
                    self.cozies[i] = self.cozies[self.count];
                    self.cozies[self.count] = null;
                    any_removed = true;
                    // Don't increment i - check swapped element
                } else {
                    cozy.time_remaining_ms -= delta_time_ms;
                    i += 1;
                }
            } else {
                i += 1;
            }
        }

        return any_removed;
    }

    /// Clear all cozies
    pub fn clear(self: *CozyState) void {
        for (&self.cozies) |*cozy| {
            cozy.* = null;
        }
        self.count = 0;
    }
};

// ============================================================================
// EFFECT STATE - New composable effect system
// ============================================================================

/// State for tracking active composable effects
pub const EffectState = struct {
    active: [MAX_ACTIVE_CONDITIONS]?effects.ActiveEffect = [_]?effects.ActiveEffect{null} ** MAX_ACTIVE_CONDITIONS,
    count: u8 = 0,

    /// Check if a specific effect is active
    pub fn has(self: EffectState, effect: *const effects.Effect) bool {
        for (self.active[0..self.count]) |maybe_active| {
            if (maybe_active) |active| {
                if (active.effect == effect) return true;
            }
        }
        return false;
    }

    /// Get active effect data
    pub fn get(self: EffectState, effect: *const effects.Effect) ?*const effects.ActiveEffect {
        for (self.active[0..self.count]) |*maybe_active| {
            if (maybe_active.*) |*active| {
                if (active.effect == effect) return active;
            }
        }
        return null;
    }

    /// Add an effect with proper stacking behavior
    pub fn add(self: *EffectState, effect: *const effects.Effect, source_id: ?EntityId) bool {
        // Check if effect already exists (handle stacking)
        for (self.active[0..self.count]) |*maybe_active| {
            if (maybe_active.*) |*active| {
                if (active.effect == effect) {
                    switch (effect.stack_behavior) {
                        .refresh_duration => {
                            active.time_remaining_ms = @max(active.time_remaining_ms, effect.duration_ms);
                        },
                        .add_intensity => {
                            active.stack_count = @min(effect.max_stacks, active.stack_count + 1);
                            active.time_remaining_ms = effect.duration_ms;
                        },
                        .ignore_if_active => {
                            // Do nothing
                        },
                    }
                    return true;
                }
            }
        }

        // Add new effect if space
        if (self.count < MAX_ACTIVE_CONDITIONS) {
            self.active[self.count] = .{
                .effect = effect,
                .time_remaining_ms = effect.duration_ms,
                .stack_count = 1,
                .source_character_id = source_id,
            };
            self.count += 1;
            return true;
        }

        return false;
    }

    /// Update all effects, removing expired ones
    pub fn update(self: *EffectState, delta_time_ms: u32) void {
        var i: usize = 0;

        while (i < self.count) {
            if (self.active[i]) |*effect| {
                if (effect.time_remaining_ms <= delta_time_ms) {
                    // Effect expired - swap with last
                    self.count -= 1;
                    self.active[i] = self.active[self.count];
                    self.active[self.count] = null;
                    // Don't increment i
                } else {
                    effect.time_remaining_ms -= delta_time_ms;
                    i += 1;
                }
            } else {
                i += 1;
            }
        }
    }

    /// Calculate move speed multiplier from all active effects
    pub fn getMoveSpeedMultiplier(self: EffectState) f32 {
        return effects.calculateMoveSpeedMultiplier(&self.active, self.count);
    }

    /// Calculate energy regen multiplier from all active effects
    pub fn getEnergyRegenMultiplier(self: EffectState) f32 {
        return effects.calculateEnergyRegenMultiplier(&self.active, self.count);
    }

    /// Calculate energy cost multiplier from all active effects
    pub fn getEnergyCostMultiplier(self: EffectState) f32 {
        return effects.calculateEnergyCostMultiplier(&self.active, self.count);
    }

    /// Clear all effects
    pub fn clear(self: *EffectState) void {
        for (&self.active) |*eff| {
            eff.* = null;
        }
        self.count = 0;
    }
};

// ============================================================================
// WARMTH PIP STATE - GW1-style health regen/degen
// ============================================================================

/// Warmth regeneration/degeneration state using GW1-style pips
pub const WarmthPipState = struct {
    pips: i8 = 0, // -10 to +10
    accumulator: f32 = 0.0, // Fractional warmth

    /// Set pips directly (clamped to valid range)
    pub fn setPips(self: *WarmthPipState, value: i16) void {
        self.pips = @intCast(@max(MIN_WARMTH_PIPS, @min(MAX_WARMTH_PIPS, value)));
    }

    /// Add pips (clamped)
    pub fn addPips(self: *WarmthPipState, delta: i16) void {
        const new_value = @as(i16, self.pips) + delta;
        self.setPips(new_value);
    }

    /// Calculate warmth change per second
    pub fn getWarmthPerSecond(self: WarmthPipState) f32 {
        return @as(f32, @floatFromInt(self.pips)) * WARMTH_PER_PIP_PER_SECOND;
    }

    /// Update and return warmth delta to apply
    /// Returns the integer warmth change (can be negative for degen)
    pub fn update(self: *WarmthPipState, delta_time: f32) f32 {
        const warmth_delta = self.getWarmthPerSecond() * delta_time;
        self.accumulator += warmth_delta;

        // Extract whole warmth to apply
        if (@abs(self.accumulator) >= 1.0) {
            const warmth_to_apply = self.accumulator;
            // Keep only fractional part
            self.accumulator -= @trunc(self.accumulator);
            return warmth_to_apply;
        }

        return 0.0;
    }

    /// Reset accumulator (on death, etc.)
    pub fn resetAccumulator(self: *WarmthPipState) void {
        self.accumulator = 0.0;
    }
};

// ============================================================================
// CONDITION STATE - Combined state for all condition systems
// ============================================================================

/// Combined condition state for a character
pub const ConditionState = struct {
    chills: ChillState = .{},
    cozies: CozyState = .{},
    effects: EffectState = .{},
    warmth_pips: WarmthPipState = .{},

    // ========== QUERY HELPERS ==========

    pub fn hasChill(self: ConditionState, chill: skills.Chill) bool {
        return self.chills.has(chill);
    }

    pub fn hasCozy(self: ConditionState, cozy: skills.Cozy) bool {
        return self.cozies.has(cozy);
    }

    pub fn hasEffect(self: ConditionState, effect: *const effects.Effect) bool {
        return self.effects.has(effect);
    }

    // ========== ADD HELPERS ==========

    pub fn addChill(self: *ConditionState, effect: skills.ChillEffect, source_id: ?EntityId) bool {
        const added = self.chills.add(effect, source_id);
        if (added) self.recalculateWarmthPips(0.0);
        return added;
    }

    pub fn addCozy(self: *ConditionState, effect: skills.CozyEffect, source_id: ?EntityId) bool {
        const added = self.cozies.add(effect, source_id);
        if (added) self.recalculateWarmthPips(0.0);
        return added;
    }

    pub fn addEffect(self: *ConditionState, effect: *const effects.Effect, source_id: ?EntityId) bool {
        return self.effects.add(effect, source_id);
    }

    // ========== UPDATE ==========

    /// Update all conditions (call every tick)
    pub fn update(self: *ConditionState, delta_time_ms: u32, gear_warmth_regen: f32) void {
        const chills_changed = self.chills.update(delta_time_ms);
        const cozies_changed = self.cozies.update(delta_time_ms);
        self.effects.update(delta_time_ms);

        // Recalculate warmth pips if any conditions expired
        if (chills_changed or cozies_changed) {
            self.recalculateWarmthPips(gear_warmth_regen);
        }
    }

    /// Recalculate warmth pips from all active conditions and gear
    pub fn recalculateWarmthPips(self: *ConditionState, gear_warmth_regen: f32) void {
        var total_pips: i16 = 0;

        // Add regeneration from cozies
        for (self.cozies.cozies[0..self.cozies.count]) |maybe_cozy| {
            if (maybe_cozy) |cozy| {
                const pips: i16 = switch (cozy.cozy) {
                    .hot_cocoa => @as(i16, 2) * @as(i16, cozy.stack_intensity), // +2 per stack
                    .fire_inside => @as(i16, 1) * @as(i16, cozy.stack_intensity), // +1 per stack
                    else => 0,
                };
                total_pips += pips;
            }
        }

        // Add degeneration from chills
        for (self.chills.chills[0..self.chills.count]) |maybe_chill| {
            if (maybe_chill) |chill| {
                const pips: i16 = switch (chill.chill) {
                    .soggy => -@as(i16, 2) * @as(i16, chill.stack_intensity), // -2 per stack (DoT)
                    .windburn => -@as(i16, 3) * @as(i16, chill.stack_intensity), // -3 per stack (DoT)
                    .brain_freeze => -@as(i16, 1) * @as(i16, chill.stack_intensity), // -1 per stack
                    else => 0,
                };
                total_pips += pips;
            }
        }

        // Add gear warmth regen bonus (convert warmth/sec to pips)
        // 1 pip = 2 warmth/sec, so gear_regen/2 = pips
        const gear_warmth_pips = @as(i16, @intFromFloat(gear_warmth_regen / WARMTH_PER_PIP_PER_SECOND));
        total_pips += gear_warmth_pips;

        self.warmth_pips.setPips(total_pips);
    }

    /// Get warmth delta from pips (call every tick)
    pub fn getWarmthDelta(self: *ConditionState, delta_time: f32) f32 {
        return self.warmth_pips.update(delta_time);
    }

    // ========== EFFECT MULTIPLIERS ==========

    pub fn getMoveSpeedMultiplier(self: ConditionState) f32 {
        return self.effects.getMoveSpeedMultiplier();
    }

    pub fn getEnergyRegenMultiplier(self: ConditionState) f32 {
        return self.effects.getEnergyRegenMultiplier();
    }

    pub fn getEnergyCostMultiplier(self: ConditionState) f32 {
        return self.effects.getEnergyCostMultiplier();
    }

    // ========== CLEAR ==========

    /// Clear all conditions (on death, resurrection, etc.)
    pub fn clearAll(self: *ConditionState) void {
        self.chills.clear();
        self.cozies.clear();
        self.effects.clear();
        self.warmth_pips.pips = 0;
        self.warmth_pips.resetAccumulator();
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "chill state basic operations" {
    var chills = ChillState{};

    // Start empty
    try std.testing.expect(!chills.has(.soggy));
    try std.testing.expectEqual(@as(u8, 0), chills.count);

    // Add a chill
    const effect = skills.ChillEffect{
        .chill = .soggy,
        .duration_ms = 5000,
        .stack_intensity = 1,
    };
    try std.testing.expect(chills.add(effect, 42));
    try std.testing.expect(chills.has(.soggy));
    try std.testing.expectEqual(@as(u8, 1), chills.count);

    // Stack the chill
    try std.testing.expect(chills.add(effect, 42));
    const active = chills.get(.soggy).?;
    try std.testing.expectEqual(@as(u8, 2), active.stack_intensity);

    // Remove
    try std.testing.expect(chills.remove(.soggy));
    try std.testing.expect(!chills.has(.soggy));
    try std.testing.expectEqual(@as(u8, 0), chills.count);
}

test "chill state expiration" {
    var chills = ChillState{};

    const effect = skills.ChillEffect{
        .chill = .slippery,
        .duration_ms = 1000,
        .stack_intensity = 1,
    };
    _ = chills.add(effect, null);

    // Update partially
    const removed1 = chills.update(500);
    try std.testing.expect(!removed1);
    try std.testing.expect(chills.has(.slippery));

    // Update to expiration
    const removed2 = chills.update(600);
    try std.testing.expect(removed2);
    try std.testing.expect(!chills.has(.slippery));
}

test "cozy state basic operations" {
    var cozies = CozyState{};

    const effect = skills.CozyEffect{
        .cozy = .hot_cocoa,
        .duration_ms = 10000,
        .stack_intensity = 2,
    };
    try std.testing.expect(cozies.add(effect, 1));
    try std.testing.expect(cozies.has(.hot_cocoa));

    const active = cozies.get(.hot_cocoa).?;
    try std.testing.expectEqual(@as(u8, 2), active.stack_intensity);
}

test "warmth pip calculations" {
    var pips = WarmthPipState{};

    // Test positive regen
    pips.setPips(5);
    try std.testing.expectEqual(@as(f32, 10.0), pips.getWarmthPerSecond()); // 5 pips * 2 = 10/sec

    // Test negative degen
    pips.setPips(-3);
    try std.testing.expectEqual(@as(f32, -6.0), pips.getWarmthPerSecond()); // -3 pips * 2 = -6/sec

    // Test clamping
    pips.setPips(100);
    try std.testing.expectEqual(@as(i8, 10), pips.pips);

    pips.setPips(-100);
    try std.testing.expectEqual(@as(i8, -10), pips.pips);
}

test "warmth pip update accumulation" {
    var pips = WarmthPipState{};
    pips.setPips(2); // 4 warmth per second

    // First update - 0.2 seconds = 0.8 warmth (accumulated, not applied yet)
    const delta1 = pips.update(0.2);
    try std.testing.expectEqual(@as(f32, 0.0), delta1);

    // Second update - another 0.3 seconds = 1.2 warmth
    // Total accumulated = 0.8 + 1.2 = 2.0 warmth → apply 2.0
    const delta2 = pips.update(0.3);
    try std.testing.expect(delta2 >= 1.0 and delta2 <= 2.1); // Allow some float tolerance
}

test "condition state warmth pip recalculation" {
    var conditions = ConditionState{};

    // Add hot_cocoa cozy (+2 pips per stack)
    const cozy_effect = skills.CozyEffect{
        .cozy = .hot_cocoa,
        .duration_ms = 10000,
        .stack_intensity = 2, // 2 stacks = +4 pips
    };
    _ = conditions.addCozy(cozy_effect, null);

    // Should have +4 pips from 2 stacks of hot_cocoa
    try std.testing.expectEqual(@as(i8, 4), conditions.warmth_pips.pips);

    // Add soggy chill (-2 pips per stack)
    const chill_effect = skills.ChillEffect{
        .chill = .soggy,
        .duration_ms = 5000,
        .stack_intensity = 1, // 1 stack = -2 pips
    };
    _ = conditions.addChill(chill_effect, null);

    // Net: +4 - 2 = +2 pips
    try std.testing.expectEqual(@as(i8, 2), conditions.warmth_pips.pips);
}
