// ============================================================================
// AFFIX PROCESSOR
// ============================================================================
//
// Runtime processing for encounter affixes (field conditions in a kids' snowball war).
// Affixes modify combat in various ways:
//
// ENEMY AFFIXES (how the other kids fight):
// - bundled: Enemies have extra warmth (wearing more layers)
// - rally: Enemies get fired up when allies go down (applies fire_inside cozy)
// - tantrum: Enemies throw harder when losing (enrage below 30% warmth)
// - snow_angels: Defeated enemies leave cozy zones that heal their team
// - powder_burst: Defeated enemies throw one last desperate volley
// - pep_talk: Enemies buff nearby allies (applies bundled_up cozy)
//
// ENVIRONMENTAL AFFIXES (weather and field conditions):
// - slush_pits: Random slush puddles spawn (applies slippery chill)
// - icy_patches: Periodic mass slip-and-fall (applies knocked_down chill)
// - blizzard: Gusts of wind push players around
// - soaked: Everyone's clothes are wet - healing reduced (healing_reduction)
// - freezing: Bitter cold - warmth recovery reduced (applies soggy DoT)
// - snowpocalypse: Bosses/leaders are extra tough
// - horde: More enemies than usual
//
// PLAYER AFFIXES (positive field conditions):
// - momentum: Players get fired up from victories (buff on kill)
// - ambush: Some enemies hidden in snow until engaged
// - supply_drops: Defeated enemies drop hot cocoa power-ups
//
// ============================================================================

const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const encounter = @import("encounter.zig");
const ai = @import("ai.zig");
const entity = @import("entity.zig");
const skills = @import("skills.zig");

const Character = character.Character;
const EncounterAffix = encounter.EncounterAffix;
const ActiveAffix = encounter.ActiveAffix;
const HazardZone = encounter.HazardZone;
const HazardType = encounter.HazardType;
const Team = entity.Team;
const Chill = skills.Chill;
const Cozy = skills.Cozy;

// ============================================================================
// CONSTANTS
// ============================================================================

// Environmental affix timings
const SLUSH_PITS_SPAWN_INTERVAL_MS: u32 = 8000; // Spawn slush pit every 8 seconds
const ICY_PATCHES_INTERVAL_MS: u32 = 12000; // Mass slip every 12 seconds
const BLIZZARD_SPAWN_INTERVAL_MS: u32 = 6000; // Wind gust every 6 seconds

// Combat modifier thresholds
const TANTRUM_THRESHOLD: f32 = 0.30; // Enemies enrage below 30% warmth

// Death trigger values
const RALLY_BUFF_DURATION_MS: u32 = 10000; // fire_inside lasts 10 seconds
const RALLY_BUFF_STACKS: u8 = 2; // 2 stacks of fire_inside
const POWDER_BURST_DAMAGE: f32 = 20.0; // Damage per stack on burst
const SNOW_ANGELS_POOL_DURATION_MS: u32 = 10000; // Healing pool lasts 10 seconds
const SNOW_ANGELS_HEAL_PER_TICK: f32 = 8.0; // Heal per tick in pool

// Healing reduction affixes
const WET_CLOTHES_HEALING_REDUCTION: f32 = 0.5; // 50% healing reduction when clothes are wet

// ============================================================================
// AFFIX STATE
// ============================================================================

/// Tracks runtime state for active affixes
pub const AffixProcessor = struct {
    /// Active affixes for this encounter
    affixes: []const ActiveAffix,

    /// Timers for periodic effects (indexed by affix)
    slush_pits_timer_ms: u32 = 0,
    icy_patches_timer_ms: u32 = 0,
    blizzard_timer_ms: u32 = 0,

    /// Track which enemies have entered tantrum (for tantrum affix)
    /// Bitfield - supports up to 64 enemies
    tantrum_enemies: u64 = 0,

    /// Powder burst stacks accumulated this encounter
    powder_burst_stacks: u8 = 0,

    /// Powder burst timer (stacks fall off after time)
    powder_burst_decay_timer_ms: u32 = 0,

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

        // slush_pits: Random slush puddles spawn that apply slippery chill
        if (self.hasAffix(.slush_pits)) {
            self.slush_pits_timer_ms += delta_time_ms;
            if (self.slush_pits_timer_ms >= SLUSH_PITS_SPAWN_INTERVAL_MS) {
                self.slush_pits_timer_ms = 0;
                result.spawn_hazard = self.createSlushPitHazard(arena_center, arena_radius);
                result.has_hazard = true;
            }
        }

        // icy_patches: Periodic mass slip-and-fall (applies knocked_down chill)
        if (self.hasAffix(.icy_patches)) {
            self.icy_patches_timer_ms += delta_time_ms;
            if (self.icy_patches_timer_ms >= ICY_PATCHES_INTERVAL_MS) {
                self.icy_patches_timer_ms = 0;
                // Everyone slips and falls!
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

        // blizzard: Wind gusts push players around
        if (self.hasAffix(.blizzard)) {
            self.blizzard_timer_ms += delta_time_ms;
            if (self.blizzard_timer_ms >= BLIZZARD_SPAWN_INTERVAL_MS) {
                self.blizzard_timer_ms = 0;
                result.spawn_hazard = self.createBlizzardHazard(entities, player_team, arena_center, arena_radius);
                result.has_hazard = true;
            }
        }

        // Process combat modifier affixes

        // tantrum: Enemies throw harder when losing (enrage below 30% warmth)
        if (self.hasAffix(.tantrum)) {
            self.processTantrum(entities, player_team);
        }

        // Decay powder_burst stacks over time
        if (self.powder_burst_stacks > 0) {
            self.powder_burst_decay_timer_ms += delta_time_ms;
            if (self.powder_burst_decay_timer_ms >= 4000) { // 4 second decay
                self.powder_burst_stacks = @max(0, self.powder_burst_stacks -| 1);
                self.powder_burst_decay_timer_ms = 0;
            }
        }

        return result;
    }

    /// Process enemy death - handles rally, powder_burst, snow_angels
    /// Returns any hazard zones to spawn (e.g., snow_angels healing pools)
    pub fn processEnemyDeath(
        self: *AffixProcessor,
        dead_enemy: *const Character,
        entities: []Character,
        player_team: Team,
    ) ?HazardZone {
        var result_hazard: ?HazardZone = null;

        // rally: Nearby allies get fired up when friend goes down (applies fire_inside cozy)
        if (self.hasAffix(.rally)) {
            const intensity = self.getAffixIntensity(.rally);
            const buff_stacks: u8 = @intFromFloat(@as(f32, @floatFromInt(RALLY_BUFF_STACKS)) * intensity);

            for (entities) |*ent| {
                if (!ent.isAlive()) continue;
                if (ent.team == dead_enemy.team and ent.id != dead_enemy.id) {
                    // Check if nearby (within 150 units)
                    const dist = distanceXZ(ent.position, dead_enemy.position);
                    if (dist <= 150.0) {
                        // Apply fire_inside cozy - they're fighting mad!
                        _ = ent.conditions.addCozy(.{
                            .cozy = .fire_inside,
                            .duration_ms = RALLY_BUFF_DURATION_MS,
                            .stack_intensity = buff_stacks,
                        }, null);
                    }
                }
            }
        }

        // powder_burst: One last desperate volley - damage players when enemy dies
        if (self.hasAffix(.powder_burst)) {
            self.powder_burst_stacks +|= 1;
            self.powder_burst_decay_timer_ms = 0;

            // Apply burst damage to all players
            const intensity = self.getAffixIntensity(.powder_burst);
            const damage = POWDER_BURST_DAMAGE * intensity * @as(f32, @floatFromInt(self.powder_burst_stacks));

            for (entities) |*ent| {
                if (!ent.isAlive()) continue;
                if (ent.team == player_team) {
                    ent.stats.warmth = @max(0, ent.stats.warmth - damage);
                }
            }
        }

        // snow_angels: Defeated enemies leave cozy zones that heal their team
        if (self.hasAffix(.snow_angels)) {
            const intensity = self.getAffixIntensity(.snow_angels);
            result_hazard = .{
                .center = dead_enemy.position,
                .radius = 40.0,
                .shape = .circle,
                .hazard_type = .safe_zone, // "Safe zone" inverted = heals enemies inside
                .damage_per_tick = -SNOW_ANGELS_HEAL_PER_TICK * intensity, // Negative = healing
                .tick_rate_ms = 500,
                .affects_players = false,
                .affects_enemies = true, // Heals enemies!
                .duration_ms = SNOW_ANGELS_POOL_DURATION_MS,
                .visual_type = .ground_marker,
                .warning_time_ms = 0,
            };
        }

        return result_hazard;
    }

    /// Get healing modifier for wet_clothes/bitter_cold affixes
    /// Returns multiplier (1.0 = normal, 0.5 = 50% reduced)
    pub fn getHealingModifier(self: *const AffixProcessor, target: *const Character, player_team: Team) f32 {
        // wet_clothes: Everyone's clothes are wet - harder to warm up (healing reduced)
        if (self.hasAffix(.wet_clothes) and target.team == player_team) {
            return 1.0 - (WET_CLOTHES_HEALING_REDUCTION * self.getAffixIntensity(.wet_clothes));
        }

        // bitter_cold: Bitter cold - wounded targets receive less healing
        if (self.hasAffix(.bitter_cold) and target.team == player_team) {
            const warmth_percent = target.stats.warmth / target.stats.max_warmth;
            if (warmth_percent < 0.9) {
                // Colder you are, harder to warm up
                const reduction = (0.9 - warmth_percent) * self.getAffixIntensity(.bitter_cold);
                return @max(0.2, 1.0 - reduction); // Cap at 80% reduction
            }
        }

        return 1.0;
    }

    /// Check if an entity should get damage bonus from tantrum
    pub fn getTantrumDamageBonus(self: *const AffixProcessor, entity_index: usize) f32 {
        if (!self.hasAffix(.tantrum)) return 1.0;

        const mask: u64 = @as(u64, 1) << @intCast(@min(entity_index, 63));
        if ((self.tantrum_enemies & mask) != 0) {
            return 1.0 + (0.5 * self.getAffixIntensity(.tantrum)); // 50% damage bonus when in tantrum
        }
        return 1.0;
    }

    // ========================================================================
    // INTERNAL HELPERS
    // ========================================================================

    fn processTantrum(self: *AffixProcessor, entities: []Character, player_team: Team) void {
        for (entities, 0..) |*ent, idx| {
            if (!ent.isAlive()) continue;
            if (ent.team == player_team) continue; // Only enemies can throw tantrums

            const warmth_percent = ent.stats.warmth / ent.stats.max_warmth;
            const mask: u64 = @as(u64, 1) << @intCast(@min(idx, 63));

            // Check if should enter tantrum
            if (warmth_percent <= TANTRUM_THRESHOLD and (self.tantrum_enemies & mask) == 0) {
                // First time below threshold - tantrum!
                self.tantrum_enemies |= mask;

                // Apply fire_inside cozy (they're MAD)
                _ = ent.conditions.addCozy(.{
                    .cozy = .fire_inside,
                    .duration_ms = 60000, // Permanent for encounter
                    .stack_intensity = 2,
                }, null);
            }
        }
    }

    fn createSlushPitHazard(self: *AffixProcessor, arena_center: rl.Vector3, arena_radius: f32) HazardZone {
        // Random position within arena
        var prng = std.Random.DefaultPrng.init(self.rng_seed +% self.slush_pits_timer_ms);
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
            .hazard_type = .slow, // Slush pits slow you down
            .damage_per_tick = 5.0 * self.getAffixIntensity(.slush_pits), // Minor warmth loss
            .tick_rate_ms = 500,
            .affects_players = true,
            .affects_enemies = false,
            .duration_ms = 5000, // 5 second duration
            .visual_type = .ground_marker,
            .warning_time_ms = 1500, // 1.5 second warning
        };
    }

    fn createBlizzardHazard(self: *AffixProcessor, entities: []const Character, player_team: Team, arena_center: rl.Vector3, arena_radius: f32) HazardZone {
        // Spawn near a random player
        var target_pos = arena_center;

        var prng = std.Random.DefaultPrng.init(self.rng_seed +% self.blizzard_timer_ms);
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
                        // Spawn wind gust near this player (offset slightly)
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

        _ = arena_radius; // Unused for blizzard

        return .{
            .center = target_pos,
            .radius = 30.0,
            .shape = .circle,
            .hazard_type = .knockback, // Wind pushes you
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
        .{ .affix = .layered_up, .intensity = 1.0 },
        .{ .affix = .slush_pits, .intensity = 1.5 },
    };

    const processor = AffixProcessor.init(&affixes, 12345);

    try std.testing.expect(processor.hasAffix(.layered_up));
    try std.testing.expect(processor.hasAffix(.slush_pits));
    try std.testing.expect(!processor.hasAffix(.rally));
    try std.testing.expectApproxEqAbs(@as(f32, 1.5), processor.getAffixIntensity(.slush_pits), 0.001);
}

test "affix processor - healing modifier" {
    const affixes = [_]ActiveAffix{
        .{ .affix = .wet_clothes, .intensity = 1.0 },
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
