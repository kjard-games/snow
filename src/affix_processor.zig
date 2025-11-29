// ============================================================================
// AFFIX PROCESSOR
// ============================================================================
//
// Runtime processing for encounter affixes. Affixes modify combat in various ways:
// - Enemy stat bonuses (fortified, tyrannical) - applied at spawn time
// - Death triggers (bolstering, bursting, sanguine) - processed on enemy death
// - Combat modifiers (raging, grievous, necrotic) - checked each tick
// - Environmental effects (volcanic, quaking, storming) - spawn hazards periodically
//
// ============================================================================

const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const encounter = @import("encounter.zig");
const ai = @import("ai.zig");
const entity = @import("entity.zig");

const Character = character.Character;
const EncounterAffix = encounter.EncounterAffix;
const ActiveAffix = encounter.ActiveAffix;
const HazardZone = encounter.HazardZone;
const HazardType = encounter.HazardType;
const Team = entity.Team;

// ============================================================================
// CONSTANTS
// ============================================================================

const VOLCANIC_SPAWN_INTERVAL_MS: u32 = 8000; // Spawn volcanic patch every 8 seconds
const QUAKING_INTERVAL_MS: u32 = 12000; // Quake every 12 seconds
const STORMING_SPAWN_INTERVAL_MS: u32 = 6000; // Spawn tornado every 6 seconds
const RAGING_THRESHOLD: f32 = 0.30; // Enemies enrage below 30% health
const BOLSTERING_HEAL_PERCENT: f32 = 0.15; // Heal 15% of max HP when ally dies
const BURSTING_DAMAGE: f32 = 20.0; // Damage per stack on burst
const SANGUINE_POOL_DURATION_MS: u32 = 10000; // Healing pool lasts 10 seconds
const SANGUINE_HEAL_PER_TICK: f32 = 8.0; // Heal per tick in pool
const NECROTIC_HEALING_REDUCTION: f32 = 0.5; // 50% healing reduction

// ============================================================================
// AFFIX STATE
// ============================================================================

/// Tracks runtime state for active affixes
pub const AffixProcessor = struct {
    /// Active affixes for this encounter
    affixes: []const ActiveAffix,

    /// Timers for periodic effects (indexed by affix)
    volcanic_timer_ms: u32 = 0,
    quaking_timer_ms: u32 = 0,
    storming_timer_ms: u32 = 0,

    /// Track which enemies have enraged (for raging affix)
    /// Bitfield - supports up to 64 enemies
    enraged_enemies: u64 = 0,

    /// Bursting stacks accumulated this encounter
    bursting_stacks: u8 = 0,

    /// Bursting timer (stacks fall off after time)
    bursting_decay_timer_ms: u32 = 0,

    /// RNG for hazard spawning
    rng_seed: u64,

    pub fn init(affixes: []const ActiveAffix, seed: u64) AffixProcessor {
        return .{
            .affixes = affixes,
            .rng_seed = seed,
        };
    }

    /// Check if a specific affix is active
    pub fn hasAffix(self: *const AffixProcessor, affix: EncounterAffix) bool {
        for (self.affixes) |active| {
            if (active.affix == affix) return true;
        }
        return false;
    }

    /// Get affix intensity (1.0 if not found)
    pub fn getAffixIntensity(self: *const AffixProcessor, affix: EncounterAffix) f32 {
        for (self.affixes) |active| {
            if (active.affix == affix) return active.intensity;
        }
        return 1.0;
    }

    /// Process affix effects for a single tick
    /// Returns any new hazard zones to spawn
    pub fn processTick(
        self: *AffixProcessor,
        entities: []Character,
        player_team: Team,
        delta_time_ms: u32,
        arena_center: rl.Vector3,
        arena_radius: f32,
    ) AffixTickResult {
        var result = AffixTickResult{};

        // Process environmental affixes
        if (self.hasAffix(.volcanic)) {
            self.volcanic_timer_ms += delta_time_ms;
            if (self.volcanic_timer_ms >= VOLCANIC_SPAWN_INTERVAL_MS) {
                self.volcanic_timer_ms = 0;
                result.spawn_hazard = self.createVolcanicHazard(arena_center, arena_radius);
                result.has_hazard = true;
            }
        }

        if (self.hasAffix(.quaking)) {
            self.quaking_timer_ms += delta_time_ms;
            if (self.quaking_timer_ms >= QUAKING_INTERVAL_MS) {
                self.quaking_timer_ms = 0;
                // Quaking applies knockdown to all players
                for (entities) |*ent| {
                    if (!ent.isAlive()) continue;
                    if (ent.team == player_team) {
                        _ = ent.conditions.addChill(.{
                            .chill = .knocked_down,
                            .duration_ms = 1500,
                            .stack_intensity = 1,
                        }, null);
                    }
                }
            }
        }

        if (self.hasAffix(.storming)) {
            self.storming_timer_ms += delta_time_ms;
            if (self.storming_timer_ms >= STORMING_SPAWN_INTERVAL_MS) {
                self.storming_timer_ms = 0;
                result.spawn_hazard = self.createStormingHazard(entities, player_team, arena_center, arena_radius);
                result.has_hazard = true;
            }
        }

        // Process combat modifier affixes
        if (self.hasAffix(.raging)) {
            self.processRaging(entities, player_team);
        }

        // Decay bursting stacks over time
        if (self.bursting_stacks > 0) {
            self.bursting_decay_timer_ms += delta_time_ms;
            if (self.bursting_decay_timer_ms >= 4000) { // 4 second decay
                self.bursting_stacks = @max(0, self.bursting_stacks -| 1);
                self.bursting_decay_timer_ms = 0;
            }
        }

        return result;
    }

    /// Process enemy death - handles bolstering, bursting, sanguine
    /// Returns any hazard zones to spawn (e.g., sanguine pools)
    pub fn processEnemyDeath(
        self: *AffixProcessor,
        dead_enemy: *const Character,
        entities: []Character,
        player_team: Team,
    ) ?HazardZone {
        var result_hazard: ?HazardZone = null;

        // Bolstering: heal nearby allies when enemy dies
        if (self.hasAffix(.bolstering)) {
            const intensity = self.getAffixIntensity(.bolstering);
            const heal_percent = BOLSTERING_HEAL_PERCENT * intensity;

            for (entities) |*ent| {
                if (!ent.isAlive()) continue;
                if (ent.team == dead_enemy.team and ent.id != dead_enemy.id) {
                    // Check if nearby (within 150 units)
                    const dist = distanceXZ(ent.position, dead_enemy.position);
                    if (dist <= 150.0) {
                        const heal_amount = ent.stats.max_warmth * heal_percent;
                        ent.stats.warmth = @min(ent.stats.max_warmth, ent.stats.warmth + heal_amount);
                    }
                }
            }
        }

        // Bursting: add a stack, damage players when stacks are high
        if (self.hasAffix(.bursting)) {
            self.bursting_stacks +|= 1;
            self.bursting_decay_timer_ms = 0;

            // Apply burst damage to all players
            const intensity = self.getAffixIntensity(.bursting);
            const damage = BURSTING_DAMAGE * intensity * @as(f32, @floatFromInt(self.bursting_stacks));

            for (entities) |*ent| {
                if (!ent.isAlive()) continue;
                if (ent.team == player_team) {
                    ent.stats.warmth = @max(0, ent.stats.warmth - damage);
                }
            }
        }

        // Sanguine: leave healing pool on death
        if (self.hasAffix(.sanguine)) {
            const intensity = self.getAffixIntensity(.sanguine);
            result_hazard = .{
                .center = dead_enemy.position,
                .radius = 40.0,
                .shape = .circle,
                .hazard_type = .safe_zone, // "Safe zone" inverted = heals enemies inside
                .damage_per_tick = -SANGUINE_HEAL_PER_TICK * intensity, // Negative = healing
                .tick_rate_ms = 500,
                .affects_players = false,
                .affects_enemies = true, // Heals enemies!
                .duration_ms = SANGUINE_POOL_DURATION_MS,
                .visual_type = .ground_marker,
                .warning_time_ms = 0,
            };
        }

        return result_hazard;
    }

    /// Get healing modifier for grievous/necrotic affixes
    /// Returns multiplier (1.0 = normal, 0.5 = 50% reduced)
    pub fn getHealingModifier(self: *const AffixProcessor, target: *const Character, player_team: Team) f32 {
        // Necrotic reduces all healing received by players
        if (self.hasAffix(.necrotic) and target.team == player_team) {
            return 1.0 - (NECROTIC_HEALING_REDUCTION * self.getAffixIntensity(.necrotic));
        }

        // Grievous: wounded targets (below 90% HP) receive less healing
        if (self.hasAffix(.grievous) and target.team == player_team) {
            const hp_percent = target.stats.warmth / target.stats.max_warmth;
            if (hp_percent < 0.9) {
                // More wounded = less healing
                const reduction = (0.9 - hp_percent) * self.getAffixIntensity(.grievous);
                return @max(0.2, 1.0 - reduction); // Cap at 80% reduction
            }
        }

        return 1.0;
    }

    /// Check if an entity should get damage bonus from raging
    pub fn getRagingDamageBonus(self: *const AffixProcessor, entity_index: usize) f32 {
        if (!self.hasAffix(.raging)) return 1.0;

        const mask: u64 = @as(u64, 1) << @intCast(@min(entity_index, 63));
        if ((self.enraged_enemies & mask) != 0) {
            return 1.0 + (0.5 * self.getAffixIntensity(.raging)); // 50% damage bonus when enraged
        }
        return 1.0;
    }

    // ========================================================================
    // INTERNAL HELPERS
    // ========================================================================

    fn processRaging(self: *AffixProcessor, entities: []Character, player_team: Team) void {
        for (entities, 0..) |*ent, idx| {
            if (!ent.isAlive()) continue;
            if (ent.team == player_team) continue; // Only enemies can enrage

            const hp_percent = ent.stats.warmth / ent.stats.max_warmth;
            const mask: u64 = @as(u64, 1) << @intCast(@min(idx, 63));

            // Check if should enrage
            if (hp_percent <= RAGING_THRESHOLD and (self.enraged_enemies & mask) == 0) {
                // First time below threshold - enrage!
                self.enraged_enemies |= mask;

                // Apply visual indicator via cozy (speed boost)
                _ = ent.conditions.addCozy(.{
                    .cozy = .fire_inside,
                    .duration_ms = 60000, // Permanent for encounter
                    .stack_intensity = 2,
                }, null);
            }
        }
    }

    fn createVolcanicHazard(self: *AffixProcessor, arena_center: rl.Vector3, arena_radius: f32) HazardZone {
        // Random position within arena
        var prng = std.Random.DefaultPrng.init(self.rng_seed +% self.volcanic_timer_ms);
        const rng = prng.random();

        const angle = rng.float(f32) * std.math.pi * 2.0;
        const dist = rng.float(f32) * arena_radius * 0.8;

        return .{
            .center = .{
                .x = arena_center.x + @cos(angle) * dist,
                .y = arena_center.y,
                .z = arena_center.z + @sin(angle) * dist,
            },
            .radius = 35.0,
            .shape = .circle,
            .hazard_type = .damage,
            .damage_per_tick = 25.0 * self.getAffixIntensity(.volcanic),
            .tick_rate_ms = 500,
            .affects_players = true,
            .affects_enemies = false,
            .duration_ms = 5000, // 5 second duration
            .visual_type = .ground_marker,
            .warning_time_ms = 1500, // 1.5 second warning
        };
    }

    fn createStormingHazard(self: *AffixProcessor, entities: []const Character, player_team: Team, arena_center: rl.Vector3, arena_radius: f32) HazardZone {
        // Spawn near a random player
        var target_pos = arena_center;

        var prng = std.Random.DefaultPrng.init(self.rng_seed +% self.storming_timer_ms);
        const rng = prng.random();

        // Find a random player to target
        var player_count: usize = 0;
        for (entities) |ent| {
            if (ent.isAlive() and ent.team == player_team) {
                player_count += 1;
            }
        }

        if (player_count > 0) {
            var target_idx = rng.intRangeAtMost(usize, 0, player_count - 1);
            for (entities) |ent| {
                if (ent.isAlive() and ent.team == player_team) {
                    if (target_idx == 0) {
                        // Spawn tornado near this player (offset slightly)
                        const offset_angle = rng.float(f32) * std.math.pi * 2.0;
                        target_pos = .{
                            .x = ent.position.x + @cos(offset_angle) * 50.0,
                            .y = ent.position.y,
                            .z = ent.position.z + @sin(offset_angle) * 50.0,
                        };
                        break;
                    }
                    target_idx -= 1;
                }
            }
        }

        _ = arena_radius; // Unused for storming

        return .{
            .center = target_pos,
            .radius = 30.0,
            .shape = .circle,
            .hazard_type = .knockback,
            .damage_per_tick = 0.0, // Knockback only
            .tick_rate_ms = 300,
            .affects_players = true,
            .affects_enemies = false,
            .duration_ms = 4000, // 4 second duration
            .visual_type = .particles,
            .warning_time_ms = 1000,
        };
    }
};

/// Result of processing a tick
pub const AffixTickResult = struct {
    /// Should a new hazard be spawned?
    has_hazard: bool = false,
    /// The hazard to spawn (if has_hazard is true)
    spawn_hazard: HazardZone = undefined,
};

/// Helper: distance in XZ plane
fn distanceXZ(a: rl.Vector3, b: rl.Vector3) f32 {
    const dx = a.x - b.x;
    const dz = a.z - b.z;
    return @sqrt(dx * dx + dz * dz);
}

// ============================================================================
// TESTS
// ============================================================================

test "affix processor - has affix" {
    const affixes = [_]ActiveAffix{
        .{ .affix = .fortified, .intensity = 1.0 },
        .{ .affix = .volcanic, .intensity = 1.5 },
    };

    const processor = AffixProcessor.init(&affixes, 12345);

    try std.testing.expect(processor.hasAffix(.fortified));
    try std.testing.expect(processor.hasAffix(.volcanic));
    try std.testing.expect(!processor.hasAffix(.bolstering));
    try std.testing.expectApproxEqAbs(@as(f32, 1.5), processor.getAffixIntensity(.volcanic), 0.001);
}

test "affix processor - healing modifier" {
    const affixes = [_]ActiveAffix{
        .{ .affix = .necrotic, .intensity = 1.0 },
    };

    const processor = AffixProcessor.init(&affixes, 12345);

    // Create a test character
    var test_char = Character{
        .id = 1,
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .previous_position = .{ .x = 0, .y = 0, .z = 0 },
        .radius = 10,
        .color = .blue,
        .school_color = .blue,
        .position_color = .blue,
        .name = "Test",
        .team = .blue,
        .school = .public_school,
        .player_position = .pitcher,
    };
    test_char.stats.warmth = 100;
    test_char.stats.max_warmth = 100;

    const modifier = processor.getHealingModifier(&test_char, .blue);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), modifier, 0.001); // 50% reduction
}
