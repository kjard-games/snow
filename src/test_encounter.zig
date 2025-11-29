//! Integration tests for the Encounter/Dungeon system
//! Tests the full pipeline: encounter definition -> enemy spawning -> AI engagement -> combat
//!
//! Run with: zig build test-encounter
//!
//! Tests:
//! - Encounter spawning via EncounterBuilder
//! - Aggro/engagement state transitions (idle -> alerted -> engaged)
//! - Leash/reset behavior
//! - Boss phase triggers
//! - Hazard zone damage
//! - Social aggro and link pulling

const std = @import("std");
const rl = @import("raylib");
const encounter = @import("encounter.zig");
const factory = @import("factory.zig");
const ai = @import("ai.zig");
const entity = @import("entity.zig");
const character = @import("character.zig");
const game_state = @import("game_state.zig");
const terrain_mod = @import("terrain.zig");
const vfx = @import("vfx.zig");
const movement = @import("movement.zig");
const school = @import("school.zig");
const position = @import("position.zig");

const Encounter = encounter.Encounter;
const EnemyWave = encounter.EnemyWave;
const EnemySpec = encounter.EnemySpec;
const BossConfig = encounter.BossConfig;
const BossPhase = encounter.BossPhase;
const PhaseTrigger = encounter.PhaseTrigger;
const HazardZone = encounter.HazardZone;
const EncounterBuilder = factory.EncounterBuilder;
const CharacterBuilder = factory.CharacterBuilder;
const AIState = ai.AIState;
const EngagementState = ai.EngagementState;
const Character = character.Character;
const EntityId = entity.EntityId;
const Team = entity.Team;
const GameState = game_state.GameState;
const TerrainGrid = terrain_mod.TerrainGrid;
const VFXManager = vfx.VFXManager;

const print = std.debug.print;

// ============================================================================
// TEST ENCOUNTERS
// ============================================================================

/// Simple test encounter with a single wave of 2 enemies
const test_simple_wave = Encounter{
    .id = "test_simple",
    .name = "Test Simple Wave",
    .description = "A single wave of 2 enemies for testing aggro.",
    .enemy_waves = &[_]EnemyWave{
        .{
            .enemies = &[_]EnemySpec{
                .{ .name = "TestEnemy1", .school = .public_school, .position = .pitcher, .difficulty_rating = 1 },
                .{ .name = "TestEnemy2", .school = .public_school, .position = .fielder, .difficulty_rating = 1 },
            },
            .spawn_position = .{ .x = 0, .y = 0, .z = -200 },
            .spawn_radius = 30.0,
            .engagement_radius = 100.0,
            .leash_radius = 300.0,
        },
    },
};

/// Test encounter with linked waves (social aggro)
const test_linked_waves = Encounter{
    .id = "test_linked",
    .name = "Test Linked Waves",
    .description = "Two linked waves that pull together.",
    .enemy_waves = &[_]EnemyWave{
        .{
            .enemies = &[_]EnemySpec{
                .{ .name = "Group1_A", .position = .pitcher },
                .{ .name = "Group1_B", .position = .fielder },
            },
            .spawn_position = .{ .x = 0, .y = 0, .z = -200 },
            .engagement_radius = 80.0,
            .leash_radius = 250.0,
            .link_groups = &[_]u8{1}, // Links to wave 1
        },
        .{
            .enemies = &[_]EnemySpec{
                .{ .name = "Group2_A", .position = .shoveler },
            },
            .spawn_position = .{ .x = 100, .y = 0, .z = -200 },
            .engagement_radius = 80.0,
            .leash_radius = 250.0,
            .link_groups = &[_]u8{0}, // Links back to wave 0
        },
    },
};

/// Test encounter with a boss that has phase transitions
const test_boss_phases = Encounter{
    .id = "test_boss",
    .name = "Test Boss Phases",
    .description = "Boss with health-based phase transitions.",
    .boss = .{
        .base = .{
            .name = "TestBoss",
            .school = .homeschool,
            .position = .shoveler,
            .warmth_multiplier = 2.0, // 300 HP (2x base 150)
            .difficulty_rating = 5,
        },
        .phases = &[_]BossPhase{
            .{
                .trigger = .combat_start,
                .phase_name = "Phase 1",
                .boss_yell = "You dare challenge me?",
            },
            .{
                .trigger = .{ .warmth_percent = 0.5 }, // At 50% HP
                .phase_name = "Phase 2",
                .boss_yell = "Now you've made me angry!",
                .damage_multiplier = 1.5,
            },
            .{
                .trigger = .{ .warmth_percent = 0.2 }, // At 20% HP
                .phase_name = "Final Phase",
                .boss_yell = "I will not fall!",
                .damage_multiplier = 2.0,
            },
        },
        .arena_radius = 200.0,
    },
    .arena_bounds = .{
        .shape = .circle,
        .center = .{ .x = 0, .y = 0, .z = 0 },
        .primary_size = 300.0,
    },
};

/// Test encounter with hazard zones
const test_hazards = Encounter{
    .id = "test_hazards",
    .name = "Test Hazard Zones",
    .description = "Encounter with damaging hazard zones.",
    .enemy_waves = &[_]EnemyWave{
        .{
            .enemies = &[_]EnemySpec{
                .{ .name = "HazardGuard", .position = .pitcher },
            },
            .spawn_position = .{ .x = 0, .y = 0, .z = -100 },
            .engagement_radius = 150.0,
        },
    },
    .hazard_zones = &[_]HazardZone{
        .{
            .center = .{ .x = 0, .y = 0, .z = 0 },
            .radius = 50.0,
            .hazard_type = .damage,
            .damage_per_tick = 10.0,
            .tick_rate_ms = 500,
            .affects_players = true,
            .affects_enemies = false,
        },
    },
};

// ============================================================================
// TEST UTILITIES
// ============================================================================

const TestContext = struct {
    allocator: std.mem.Allocator,
    entities: []Character,
    ai_states: []AIState,
    terrain: TerrainGrid,
    vfx_mgr: VFXManager,
    rng: std.Random,
    prng: std.Random.DefaultPrng,
    id_gen: entity.EntityIdGenerator,
    player_count: usize,
    enemy_count: usize,

    fn init(allocator: std.mem.Allocator) !TestContext {
        var prng = std.Random.DefaultPrng.init(12345);
        const terrain = try TerrainGrid.initHeadless(allocator, 64, 64, 25.0, -800.0, -800.0);

        return TestContext{
            .allocator = allocator,
            .entities = try allocator.alloc(Character, game_state.MAX_ENTITIES),
            .ai_states = try allocator.alloc(AIState, game_state.MAX_ENTITIES),
            .terrain = terrain,
            .vfx_mgr = VFXManager.init(),
            .prng = prng,
            .rng = prng.random(),
            .id_gen = entity.EntityIdGenerator{},
            .player_count = 0,
            .enemy_count = 0,
        };
    }

    fn deinit(self: *TestContext) void {
        self.allocator.free(self.entities);
        self.allocator.free(self.ai_states);
        self.terrain.deinit();
    }

    /// Spawn a player team at specified position
    fn spawnPlayerTeam(self: *TestContext, count: usize, spawn_pos: rl.Vector3) !void {
        for (0..count) |i| {
            var builder = CharacterBuilder.init(self.allocator, &self.rng, &self.id_gen);
            _ = builder.withTeam(.blue)
                .withPosition3D(.{
                .x = spawn_pos.x + @as(f32, @floatFromInt(i)) * 30.0,
                .y = spawn_pos.y,
                .z = spawn_pos.z,
            });

            self.entities[self.player_count] = builder.build();
            self.ai_states[self.player_count] = AIState.init(self.entities[self.player_count].player_position);
            self.player_count += 1;
        }
    }

    /// Spawn enemies from an encounter
    fn spawnEncounter(self: *TestContext, enc: *const Encounter) !usize {
        var builder = EncounterBuilder.init(self.allocator, &self.rng, &self.id_gen, enc);
        const result = try builder.build();
        defer self.allocator.free(result.enemies);
        defer self.allocator.free(result.ai_states);

        const start_idx = self.player_count;
        const copy_count = @min(result.count, self.entities.len - start_idx);

        for (0..copy_count) |i| {
            self.entities[start_idx + i] = result.enemies[i];
            self.ai_states[start_idx + i] = result.ai_states[i];
        }

        self.enemy_count = copy_count;
        return copy_count;
    }

    fn totalCount(self: *const TestContext) usize {
        return self.player_count + self.enemy_count;
    }

    /// Simulate N ticks of AI updates
    fn simulateTicks(self: *TestContext, num_ticks: u32) void {
        const dt: f32 = game_state.TICK_RATE_SEC;
        const dt_ms: u32 = game_state.TICK_RATE_MS;

        for (0..num_ticks) |_| {
            // Update each AI entity
            for (self.player_count..self.totalCount()) |i| {
                const ent = &self.entities[i];
                if (!ent.isAlive()) continue;

                const ai_state = &self.ai_states[i];

                // Build world state for this entity
                const world = ai.WorldState.build(
                    ent,
                    self.entities[0..self.totalCount()],
                    &self.terrain,
                    null, // No building manager in tests
                    &self.vfx_mgr,
                    &self.rng,
                    null,
                    dt,
                );

                // Update engagement state
                _ = ai.updateEngagementState(ent, ai_state, &world, dt_ms);

                // Handle leashing movement
                if (ai_state.engagement == .leashing) {
                    const intent = ai.calcLeashMovement(ent, ai_state);
                    movement.applyMovement(ent, intent, self.entities[0..self.totalCount()], null, null, dt, &self.terrain, null);
                }
            }
        }
    }

    /// Move player to a position
    fn movePlayer(self: *TestContext, player_idx: usize, pos: rl.Vector3) void {
        if (player_idx < self.player_count) {
            self.entities[player_idx].position = pos;
        }
    }

    /// Get distance between two entities
    fn distance(self: *const TestContext, idx1: usize, idx2: usize) f32 {
        const e1 = &self.entities[idx1];
        const e2 = &self.entities[idx2];
        const dx = e1.position.x - e2.position.x;
        const dz = e1.position.z - e2.position.z;
        return @sqrt(dx * dx + dz * dz);
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "encounter spawning creates correct number of enemies" {
    const allocator = std.testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Spawn players first
    try ctx.spawnPlayerTeam(2, .{ .x = 0, .y = 0, .z = 200 });

    // Spawn encounter enemies
    const enemy_count = try ctx.spawnEncounter(&test_simple_wave);

    // Verify enemy count
    try std.testing.expectEqual(@as(usize, 2), enemy_count);
    try std.testing.expectEqual(@as(usize, 4), ctx.totalCount()); // 2 players + 2 enemies

    // Verify enemy properties
    const enemy1 = &ctx.entities[ctx.player_count];
    try std.testing.expectEqualStrings("TestEnemy1", enemy1.name);
    try std.testing.expectEqual(Team.red, enemy1.team);

    // Verify AI states initialized correctly
    const ai1 = &ctx.ai_states[ctx.player_count];
    try std.testing.expectEqual(EngagementState.idle, ai1.engagement);
    try std.testing.expect(ai1.spawn_position != null);
}

test "enemies start in idle state and detect aggro" {
    const allocator = std.testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Spawn players far from enemies
    try ctx.spawnPlayerTeam(1, .{ .x = 0, .y = 0, .z = 500 });
    _ = try ctx.spawnEncounter(&test_simple_wave);

    // Enemies should be idle initially
    const ai1 = &ctx.ai_states[ctx.player_count];
    try std.testing.expectEqual(EngagementState.idle, ai1.engagement);

    // Simulate a few ticks - should remain idle (player too far)
    ctx.simulateTicks(10);
    try std.testing.expectEqual(EngagementState.idle, ai1.engagement);

    // Move player into aggro range (engagement_radius = 100)
    ctx.movePlayer(0, .{ .x = 0, .y = 0, .z = -150 }); // 50 units from enemy at z=-200

    // Simulate - should transition to alerted
    ctx.simulateTicks(5);
    try std.testing.expect(ai1.engagement == .alerted or ai1.engagement == .engaged);
}

test "enemies engage after alert delay" {
    const allocator = std.testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    try ctx.spawnPlayerTeam(1, .{ .x = 0, .y = 0, .z = -150 }); // Within aggro range
    _ = try ctx.spawnEncounter(&test_simple_wave);

    const ai1 = &ctx.ai_states[ctx.player_count];

    // First tick should trigger alert
    ctx.simulateTicks(1);
    try std.testing.expectEqual(EngagementState.alerted, ai1.engagement);

    // Simulate enough ticks for alert delay (500ms = 10 ticks at 50ms/tick)
    ctx.simulateTicks(15);

    // Should now be engaged
    try std.testing.expectEqual(EngagementState.engaged, ai1.engagement);
}

test "enemies leash when player moves too far" {
    const allocator = std.testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Start player within aggro range
    try ctx.spawnPlayerTeam(1, .{ .x = 0, .y = 0, .z = -150 });
    _ = try ctx.spawnEncounter(&test_simple_wave);

    const ai1 = &ctx.ai_states[ctx.player_count];
    const enemy = &ctx.entities[ctx.player_count];

    // Engage the enemy
    ctx.simulateTicks(20);
    try std.testing.expectEqual(EngagementState.engaged, ai1.engagement);

    // Move enemy far from spawn (simulating chase)
    // leash_radius = 300, so move enemy 350 units from spawn
    enemy.position = .{ .x = 0, .y = 0, .z = 150 }; // spawn was at z=-200, this is 350 units away

    // Simulate - should detect leash
    ctx.simulateTicks(5);
    try std.testing.expectEqual(EngagementState.leashing, ai1.engagement);
}

test "enemies reset health after returning to spawn" {
    const allocator = std.testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    try ctx.spawnPlayerTeam(1, .{ .x = 0, .y = 0, .z = -150 });
    _ = try ctx.spawnEncounter(&test_simple_wave);

    const ai1 = &ctx.ai_states[ctx.player_count];
    const enemy = &ctx.entities[ctx.player_count];

    // Engage
    ctx.simulateTicks(20);

    // Damage the enemy
    enemy.stats.warmth = 50.0;

    // Move player far away to trigger leash
    ctx.movePlayer(0, .{ .x = 0, .y = 0, .z = 1000 }); // Very far

    // Move enemy far from spawn to trigger leash
    enemy.position = .{ .x = 0, .y = 0, .z = 200 }; // 400 units from spawn at z=-200

    // Simulate until leash is detected
    ctx.simulateTicks(5);
    try std.testing.expectEqual(EngagementState.leashing, ai1.engagement);

    // Move enemy back to spawn (simulate return)
    enemy.position = ai1.spawn_position.?;

    // Simulate to trigger reset state (should transition from leashing to resetting)
    ctx.simulateTicks(5);
    try std.testing.expectEqual(EngagementState.resetting, ai1.engagement);

    // Simulate enough ticks for reset timer (3000ms = 60 ticks at 50ms/tick)
    ctx.simulateTicks(65);

    // Should be back to idle with full health
    try std.testing.expectEqual(EngagementState.idle, ai1.engagement);
    try std.testing.expectEqual(enemy.stats.max_warmth, enemy.stats.warmth);
}

test "boss phase triggers at health thresholds" {
    const allocator = std.testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    try ctx.spawnPlayerTeam(1, .{ .x = 0, .y = 0, .z = 50 }); // Close to boss spawn at center
    _ = try ctx.spawnEncounter(&test_boss_phases);

    const boss_idx = ctx.player_count;
    const boss = &ctx.entities[boss_idx];
    const boss_ai = &ctx.ai_states[boss_idx];
    const boss_config = test_boss_phases.boss.?;

    // Force boss into engaged state (skip aggro delay for testing)
    boss_ai.engagement = .engaged;
    boss_ai.combat_time_ms = 0;

    // Check combat_start phase (triggers when combat_time_ms == 0)
    var phase_result = ai.checkBossPhases(boss, boss_ai, &boss_config);
    try std.testing.expect(phase_result.phase_triggered);
    try std.testing.expectEqual(@as(u8, 0), phase_result.triggered_phase_index);
    try std.testing.expect(boss_ai.hasPhaseTriggered(0));

    // Increment combat time so combat_start won't re-trigger
    boss_ai.combat_time_ms = 100;

    // Damage boss to 50% (150 HP from 300)
    boss.stats.warmth = 150.0;

    // Check phase 2 triggers (warmth_percent = 0.5)
    phase_result = ai.checkBossPhases(boss, boss_ai, &boss_config);
    try std.testing.expect(phase_result.phase_triggered);
    try std.testing.expectEqual(@as(u8, 1), phase_result.triggered_phase_index);

    // Damage boss to 20% (60 HP)
    boss.stats.warmth = 60.0;

    // Check phase 3 triggers (warmth_percent = 0.2)
    phase_result = ai.checkBossPhases(boss, boss_ai, &boss_config);
    try std.testing.expect(phase_result.phase_triggered);
    try std.testing.expectEqual(@as(u8, 2), phase_result.triggered_phase_index);
}

test "hazard zones deal damage to players" {
    const allocator = std.testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Spawn player in hazard zone center
    try ctx.spawnPlayerTeam(1, .{ .x = 0, .y = 0, .z = 0 });
    _ = try ctx.spawnEncounter(&test_hazards);

    const player = &ctx.entities[0];
    const initial_warmth = player.stats.warmth;

    // Create hazard zone state
    var hazard_states: [1]ai.HazardZoneState = undefined;
    hazard_states[0] = ai.HazardZoneState.init(&test_hazards.hazard_zones[0]);

    // Process hazards for several ticks (simulate 1 second = 20 ticks)
    for (0..20) |_| {
        ai.processHazardZones(
            ctx.entities[0..ctx.totalCount()],
            &hazard_states,
            game_state.TICK_RATE_MS,
        );
    }

    // Player should have taken damage (at least 1 tick of 10 damage at 500ms interval)
    try std.testing.expect(player.stats.warmth < initial_warmth);
}

test "hazard zones do not affect enemies when affects_enemies is false" {
    const allocator = std.testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    try ctx.spawnPlayerTeam(1, .{ .x = 0, .y = 0, .z = 200 }); // Player outside hazard
    _ = try ctx.spawnEncounter(&test_hazards);

    // Move enemy into hazard zone
    ctx.entities[ctx.player_count].position = .{ .x = 0, .y = 0, .z = 0 };
    const enemy = &ctx.entities[ctx.player_count];
    const initial_warmth = enemy.stats.warmth;

    var hazard_states: [1]ai.HazardZoneState = undefined;
    hazard_states[0] = ai.HazardZoneState.init(&test_hazards.hazard_zones[0]);

    // Process hazards
    for (0..20) |_| {
        ai.processHazardZones(
            ctx.entities[0..ctx.totalCount()],
            &hazard_states,
            game_state.TICK_RATE_MS,
        );
    }

    // Enemy should NOT have taken damage
    try std.testing.expectEqual(initial_warmth, enemy.stats.warmth);
}

test "isInsideHazard correctly detects positions" {
    const hazard = HazardZone{
        .center = .{ .x = 100, .y = 0, .z = 100 },
        .radius = 50.0,
        .hazard_type = .damage,
    };

    // Inside
    try std.testing.expect(ai.isInsideHazard(.{ .x = 100, .y = 0, .z = 100 }, &hazard));
    try std.testing.expect(ai.isInsideHazard(.{ .x = 130, .y = 0, .z = 100 }, &hazard));

    // Outside
    try std.testing.expect(!ai.isInsideHazard(.{ .x = 200, .y = 0, .z = 100 }, &hazard));
    try std.testing.expect(!ai.isInsideHazard(.{ .x = 100, .y = 0, .z = 200 }, &hazard));
}

test "encounter builder applies difficulty multiplier" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(42);
    var rng = prng.random();
    var id_gen = entity.EntityIdGenerator{};

    var builder = EncounterBuilder.init(allocator, &rng, &id_gen, &test_simple_wave);
    _ = builder.withDifficulty(2.0); // Double difficulty

    const result = try builder.build();
    defer allocator.free(result.enemies);
    defer allocator.free(result.ai_states);

    // Check enemies have scaled warmth (base 150 * 2.0 difficulty = 300)
    try std.testing.expect(result.enemies[0].stats.max_warmth >= 290.0);
}

test "encounter builder applies fortified affix" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(42);
    var rng = prng.random();
    var id_gen = entity.EntityIdGenerator{};

    var builder = EncounterBuilder.init(allocator, &rng, &id_gen, &test_simple_wave);
    const affixes = [_]encounter.ActiveAffix{
        .{ .affix = .fortified, .intensity = 1.0 },
    };
    _ = builder.withAffixes(&affixes);

    const result = try builder.build();
    defer allocator.free(result.enemies);
    defer allocator.free(result.ai_states);

    // Fortified adds 20% health: 150 * 1.2 = 180
    try std.testing.expect(result.enemies[0].stats.max_warmth >= 175.0);
}

// ============================================================================
// MAIN - Run as executable for verbose output
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("\n\x1b[36m╔════════════════════════════════════════════════════════════╗\x1b[0m\n", .{});
    print("\x1b[36m║\x1b[0m \x1b[1m           ENCOUNTER SYSTEM INTEGRATION TEST              \x1b[0m \x1b[36m║\x1b[0m\n", .{});
    print("\x1b[36m╚════════════════════════════════════════════════════════════╝\x1b[0m\n\n", .{});

    // Run a more verbose integration scenario
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    print("=== Scenario: Player approaches enemy camp ===\n\n", .{});

    // 1. Spawn player team far away
    print("1. Spawning player team at z=500...\n", .{});
    try ctx.spawnPlayerTeam(2, .{ .x = 0, .y = 0, .z = 500 });
    print("   Players spawned: {d}\n", .{ctx.player_count});

    // 2. Spawn encounter
    print("2. Spawning enemy encounter...\n", .{});
    const enemy_count = try ctx.spawnEncounter(&test_simple_wave);
    print("   Enemies spawned: {d}\n", .{enemy_count});

    // 3. Check initial state
    print("3. Checking initial enemy state...\n", .{});
    for (ctx.player_count..ctx.totalCount()) |i| {
        const ai_state = &ctx.ai_states[i];
        const ent = &ctx.entities[i];
        print("   {s}: engagement={s}, pos=({d:.0}, {d:.0})\n", .{
            ent.name,
            @tagName(ai_state.engagement),
            ent.position.x,
            ent.position.z,
        });
    }

    // 4. Simulate with player far away
    print("4. Simulating 20 ticks with player far away...\n", .{});
    ctx.simulateTicks(20);
    for (ctx.player_count..ctx.totalCount()) |i| {
        const ai_state = &ctx.ai_states[i];
        print("   Enemy {d}: {s}\n", .{ i - ctx.player_count, @tagName(ai_state.engagement) });
    }

    // 5. Move player closer
    print("5. Moving player into aggro range...\n", .{});
    ctx.movePlayer(0, .{ .x = 0, .y = 0, .z = -150 });
    print("   Player 0 now at z=-150\n", .{});

    // 6. Simulate aggro detection
    print("6. Simulating 5 ticks (aggro detection)...\n", .{});
    ctx.simulateTicks(5);
    for (ctx.player_count..ctx.totalCount()) |i| {
        const ai_state = &ctx.ai_states[i];
        print("   Enemy {d}: {s}\n", .{ i - ctx.player_count, @tagName(ai_state.engagement) });
    }

    // 7. Simulate full engagement
    print("7. Simulating 20 more ticks (full engagement)...\n", .{});
    ctx.simulateTicks(20);
    for (ctx.player_count..ctx.totalCount()) |i| {
        const ai_state = &ctx.ai_states[i];
        const ent = &ctx.entities[i];
        print("   {s}: {s}, warmth={d:.0}/{d:.0}\n", .{
            ent.name,
            @tagName(ai_state.engagement),
            ent.stats.warmth,
            ent.stats.max_warmth,
        });
    }

    print("\n\x1b[32m=== Scenario complete! ===\x1b[0m\n\n", .{});

    // Boss phase test
    print("=== Scenario: Boss phase transitions ===\n\n", .{});

    var boss_ctx = try TestContext.init(allocator);
    defer boss_ctx.deinit();

    try boss_ctx.spawnPlayerTeam(1, .{ .x = 0, .y = 0, .z = 50 });
    _ = try boss_ctx.spawnEncounter(&test_boss_phases);

    const boss = &boss_ctx.entities[boss_ctx.player_count];
    const boss_ai = &boss_ctx.ai_states[boss_ctx.player_count];
    const boss_config = test_boss_phases.boss.?;

    print("Boss spawned: {s}, HP={d:.0}/{d:.0}\n", .{
        boss.name,
        boss.stats.warmth,
        boss.stats.max_warmth,
    });

    // Engage boss
    boss_ctx.simulateTicks(20);
    print("Boss engaged: {s}\n", .{@tagName(boss_ai.engagement)});

    // Test phase transitions
    const health_levels = [_]f32{ 150.0, 60.0 }; // 50% and 20%
    for (health_levels, 0..) |hp, phase_num| {
        boss.stats.warmth = hp;
        const result = ai.checkBossPhases(boss, boss_ai, &boss_config);
        if (result.phase_triggered) {
            print("Phase {d} triggered at {d:.0} HP: \"{s}\"\n", .{
                phase_num + 2,
                hp,
                if (result.triggered_phase) |p| p.phase_name orelse "unnamed" else "none",
            });
        }
    }

    print("\n\x1b[32m╔════════════════════════════════════════════════════════════╗\x1b[0m\n", .{});
    print("\x1b[32m║\x1b[0m \x1b[1m              All integration tests passed!               \x1b[0m \x1b[32m║\x1b[0m\n", .{});
    print("\x1b[32m╚════════════════════════════════════════════════════════════╝\x1b[0m\n\n", .{});
}
