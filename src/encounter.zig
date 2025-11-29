// ============================================================================
// ENCOUNTER PRIMITIVE SYSTEM
// ============================================================================
//
// Composable encounter definitions for dungeons, arenas, and boss fights.
// Follows the same compositional philosophy as effects.zig:
// - WHAT: Enemy composition (waves, bosses)
// - WHERE: Arena setup (bounds, terrain, hazards)
// - WHEN: Timing/pacing (engagement rules, phase triggers)
// - IF: Victory/failure conditions (objectives)
//
// Design Goals:
// - 15-minute dungeon experiences (WoW Mythic+ / GW2 Fractals style)
// - Continuous-flow encounters (enemies on map from start, aggro management)
// - Boss skills = Player skills (capturable on defeat)
// - Phase transitions via auto_cast_condition on skills
// - Difficulty scales logarithmically with distance from map center
//
// ============================================================================

const std = @import("std");
const rl = @import("raylib");
const entity = @import("entity.zig");
const school_mod = @import("school.zig");
const position_mod = @import("position.zig");
const terrain_mod = @import("terrain.zig");
const skills = @import("skills.zig");

const EntityId = entity.EntityId;
const Team = entity.Team;
const School = school_mod.School;
const Position = position_mod.Position;
const Skill = skills.Skill;
const TerrainType = terrain_mod.TerrainType;

// ============================================================================
// ENEMY SPECIFICATION
// ============================================================================

/// Defines a single enemy type (used in waves and boss configs)
pub const EnemySpec = struct {
    /// Display name for this enemy
    name: [:0]const u8 = "Enemy",

    /// School determines resource mechanics and skill access
    school: School = .public_school,

    /// Position determines base skills and combat role
    position: Position = .pitcher,

    /// Optional skill bar override (null = use position/school defaults)
    /// Skills are pointers to comptime skill definitions - capturable!
    skill_overrides: ?[8]?*const Skill = null,

    /// Stat multipliers (1.0 = player equivalent)
    warmth_multiplier: f32 = 1.0,
    energy_multiplier: f32 = 1.0,
    damage_multiplier: f32 = 1.0,

    /// Visual customization
    scale: f32 = 1.0, // Size multiplier
    color_tint: ?rl.Color = null, // Optional color override

    /// Difficulty rating (affects scaling calculations)
    /// 1 = trash mob, 5 = mini-boss, 10 = boss
    difficulty_rating: u8 = 1,

    /// Is this a "champion" enemy? (stronger, may have affixes)
    is_champion: bool = false,

    /// Is this enemy immune to certain effects?
    immune_to_knockdown: bool = false,
    immune_to_daze: bool = false,
};

// ============================================================================
// ENEMY WAVE
// ============================================================================

/// A group of enemies that exist on the map and engage together
pub const EnemyWave = struct {
    /// Enemies in this wave
    enemies: []const EnemySpec,

    /// Spawn position (center of wave)
    spawn_position: rl.Vector3 = .{ .x = 0, .y = 0, .z = 0 },

    /// Spread radius for spawning enemies in wave
    spawn_radius: f32 = 50.0,

    /// Optional patrol path (enemies walk this when not engaged)
    patrol_path: ?[]const rl.Vector3 = null,

    /// Patrol speed multiplier (1.0 = normal walk speed)
    patrol_speed: f32 = 0.5,

    /// How close a player must be to trigger aggro
    engagement_radius: f32 = 150.0,

    /// How far enemies will chase before leashing back
    leash_radius: f32 = 400.0,

    /// Link groups - wave indices that will aggro when this wave is pulled
    /// Example: [1, 3] means waves 1 and 3 will join if this wave is pulled
    link_groups: []const u8 = &[_]u8{},

    /// Does this wave respawn after wipe? (false for boss adds, true for trash)
    respawns_on_wipe: bool = true,

    /// Delay before wave engages after aggro (for dramatic effect)
    engagement_delay_ms: u32 = 0,

    /// Optional name for this wave group (for callouts)
    name: ?[:0]const u8 = null,
};

// ============================================================================
// BOSS PHASE SYSTEM
// ============================================================================

/// What triggers a phase transition?
pub const PhaseTrigger = union(enum) {
    /// Transition at health threshold (0.0 to 1.0)
    warmth_percent: f32,

    /// Transition after time in combat
    time_in_combat_ms: u32,

    /// Transition when add count reaches threshold
    adds_killed: u8,

    /// Transition when specific skill is interrupted
    skill_interrupted: [:0]const u8,

    /// Transition on combat start
    combat_start,

    /// Manual trigger (via script/event)
    manual,

    // Helper constructors
    pub fn atHealth(percent: f32) PhaseTrigger {
        return .{ .warmth_percent = percent };
    }

    pub fn afterTime(ms: u32) PhaseTrigger {
        return .{ .time_in_combat_ms = ms };
    }

    pub fn afterKills(count: u8) PhaseTrigger {
        return .{ .adds_killed = count };
    }
};

/// Changes to the arena during a phase transition
pub const ArenaMod = union(enum) {
    /// Add a terrain patch
    add_terrain: TerrainPatch,

    /// Add a hazard zone
    add_hazard: HazardZone,

    /// Remove terrain in area
    clear_terrain: struct {
        center: rl.Vector3,
        radius: f32,
    },

    /// Modify arena bounds
    shrink_bounds: struct {
        new_radius: f32,
        transition_time_ms: u32,
    },

    /// Spawn environmental obstacle
    spawn_obstacle: struct {
        position: rl.Vector3,
        obstacle_type: ObstacleType,
    },
};

/// Types of environmental obstacles
pub const ObstacleType = enum {
    ice_pillar, // Blocks LoS, can be destroyed
    snow_drift, // Blocks movement, can be cleared
    frozen_tree, // Permanent obstacle
    snowman_statue, // Decorative, may come alive
};

/// A single boss phase
pub const BossPhase = struct {
    /// What triggers this phase
    trigger: PhaseTrigger,

    /// New skill bar for this phase (null = keep previous)
    skill_bar_override: ?[8]?*const Skill = null,

    /// Arena modifications when entering this phase
    arena_changes: []const ArenaMod = &[_]ArenaMod{},

    /// Enemies that spawn when entering this phase
    add_spawn: []const EnemySpec = &[_]EnemySpec{},

    /// Position where adds spawn (null = around boss)
    add_spawn_position: ?rl.Vector3 = null,

    /// Stat changes for this phase
    damage_multiplier: f32 = 1.0,
    speed_multiplier: f32 = 1.0,

    /// Visual/audio cues
    phase_name: ?[:0]const u8 = null, // "Enrage!", "Ice Storm!", etc.
    boss_yell: ?[:0]const u8 = null, // What the boss says

    /// Does boss become immune during transition?
    immune_during_transition: bool = false,
    transition_duration_ms: u32 = 0,
};

/// Full boss configuration
pub const BossConfig = struct {
    /// Base enemy specification
    base: EnemySpec,

    /// Phase definitions (in order of activation)
    phases: []const BossPhase = &[_]BossPhase{},

    /// Signature skills unique to this boss (capturable on defeat!)
    /// These are the skills players can learn by defeating this boss
    signature_skills: []const *const Skill = &[_]*const Skill{},

    /// Does the boss have a dedicated arena area?
    dedicated_arena: bool = true,

    /// Arena radius if dedicated
    arena_radius: f32 = 300.0,

    /// Is boss immune to pulls/knockback?
    immune_to_displacement: bool = true,

    /// Enrage timer (0 = no enrage)
    enrage_timer_ms: u32 = 0,

    /// What happens on enrage
    enrage_damage_multiplier: f32 = 2.0,
};

// ============================================================================
// ARENA SETUP
// ============================================================================

/// Shape of the playable arena
pub const ArenaShape = enum {
    circle,
    rectangle,
    polygon, // Custom shape defined by vertices
    infinite, // No bounds (open world)
};

/// Defines the playable area boundaries
pub const ArenaBounds = struct {
    shape: ArenaShape = .circle,

    /// Center of the arena
    center: rl.Vector3 = .{ .x = 0, .y = 0, .z = 0 },

    /// For circle: radius. For rectangle: half-width
    primary_size: f32 = 500.0,

    /// For rectangle: half-height (ignored for circle)
    secondary_size: f32 = 500.0,

    /// For polygon: vertices (ignored for other shapes)
    vertices: []const rl.Vector3 = &[_]rl.Vector3{},

    /// What happens at the boundary?
    boundary_behavior: BoundaryBehavior = .soft_wall,

    /// Damage per second if boundary is damaging
    boundary_damage: f32 = 10.0,
};

/// What happens when players reach arena boundary
pub const BoundaryBehavior = enum {
    soft_wall, // Gently pushed back
    hard_wall, // Blocked completely
    damaging, // Takes damage while outside
    instant_death, // Killed if outside (cliff, void)
    teleport_back, // Teleported to center
};

/// A patch of modified terrain within the arena
pub const TerrainPatch = struct {
    /// Center position
    center: rl.Vector3,

    /// Radius of the patch
    radius: f32,

    /// What terrain type to apply
    terrain_type: TerrainType,

    /// Is this terrain permanent or temporary?
    duration_ms: u32 = 0, // 0 = permanent

    /// Does this patch expand/contract over time?
    growth_rate: f32 = 0.0, // Units per second (negative = shrink)

    /// Maximum radius if growing
    max_radius: f32 = 0.0,
};

/// A zone that applies effects to characters inside
pub const HazardZone = struct {
    /// Center position
    center: rl.Vector3,

    /// Radius of effect
    radius: f32,

    /// Shape of the hazard
    shape: HazardShape = .circle,

    /// What type of hazard
    hazard_type: HazardType,

    /// Damage per tick (if damaging)
    damage_per_tick: f32 = 0.0,

    /// Tick rate in ms
    tick_rate_ms: u32 = 1000,

    /// Does this hazard affect allies, enemies, or both?
    affects_players: bool = true,
    affects_enemies: bool = false,

    /// Duration (0 = permanent)
    duration_ms: u32 = 0,

    /// Visual indicator
    visual_type: HazardVisual = .ground_marker,

    /// Warning time before hazard activates
    warning_time_ms: u32 = 0,
};

pub const HazardShape = enum {
    circle,
    cone, // Emanates from a direction
    line, // Straight line
    ring, // Donut shape
    moving_line, // Avalanche-style
};

pub const HazardType = enum {
    damage, // Direct damage
    slow, // Movement speed reduction
    knockback, // Pushes characters
    knockdown, // Knocks characters down
    freeze, // Applies frozen/immobilized
    blind, // Applies blind effect
    pull, // Pulls toward center
    safe_zone, // Inverted - safe INSIDE, dangerous outside
};

pub const HazardVisual = enum {
    ground_marker, // Glowing circle on ground
    particles, // Particle effect
    terrain_change, // Visible terrain modification
    none, // Invisible (surprise!)
};

// ============================================================================
// ENGAGEMENT RULES
// ============================================================================

/// Rules for how enemies engage and disengage
pub const EngagementRules = struct {
    /// Default aggro radius for enemies without override
    default_aggro_radius: f32 = 150.0,

    /// Default leash radius
    default_leash_radius: f32 = 400.0,

    /// Do enemies share aggro with nearby enemies?
    social_aggro: bool = true,

    /// Radius for social aggro
    social_aggro_radius: f32 = 100.0,

    /// Do enemies call for help when attacked?
    call_for_help: bool = true,

    /// Radius for call for help
    call_for_help_radius: f32 = 200.0,

    /// Do enemies prioritize healers?
    smart_targeting: bool = true,

    /// How quickly do enemies switch targets? (0 = never, 1 = immediately)
    target_switch_rate: f32 = 0.3,

    /// Do enemies reset health when leashing?
    reset_on_leash: bool = true,

    /// Can enemies be body-pulled (aggro by proximity)?
    body_pull_enabled: bool = true,

    /// Can enemies be face-pulled (aggro by looking at them)?
    face_pull_enabled: bool = false,
};

// ============================================================================
// OBJECTIVES AND CONDITIONS
// ============================================================================

/// Victory/failure objective types
pub const ObjectiveType = enum {
    kill_all, // Kill all enemies
    kill_boss, // Kill the boss (ignore remaining adds)
    survive_time, // Survive for X seconds
    protect_npc, // Keep an NPC alive
    collect_items, // Gather X items
    reach_location, // Get to a specific point
    no_deaths, // Complete without any party deaths (bonus objective)
};

/// A single objective
pub const Objective = struct {
    objective_type: ObjectiveType,

    /// For kill objectives: which enemies count
    target_wave_indices: []const u8 = &[_]u8{},

    /// For survive/timer objectives
    time_ms: u32 = 0,

    /// For collect objectives
    required_count: u8 = 0,

    /// For location objectives
    target_position: ?rl.Vector3 = null,
    target_radius: f32 = 50.0,

    /// Is this a bonus objective? (optional for completion)
    is_bonus: bool = false,

    /// Description shown to players
    description: [:0]const u8 = "",
};

/// Conditions that cause encounter failure
pub const FailureCondition = union(enum) {
    /// All players dead
    party_wipe,

    /// Timer expires
    timer_expired: u32,

    /// Protected NPC dies
    npc_death,

    /// Too many deaths
    death_count: u8,

    /// Boss enrages (soft fail - can still complete but harder)
    boss_enrage,
};

// ============================================================================
// ENCOUNTER AFFIXES
// ============================================================================

/// Modifiers that can be applied to encounters for difficulty variation
pub const EncounterAffix = enum {
    // Enemy affixes
    fortified, // Enemies have +20% health
    bolstering, // Enemies heal when allies die
    raging, // Enemies enrage below 30% health
    sanguine, // Enemies leave healing pools on death
    bursting, // Enemies explode on death (damage players)
    inspiring, // Enemies buff nearby allies

    // Environmental affixes
    volcanic, // Random fire patches spawn
    quaking, // Periodic knockdowns
    storming, // Random tornadoes that push players
    grievous, // Wounds don't heal naturally
    necrotic, // Healing is reduced
    tyrannical, // Bosses are empowered
    fortified_trash, // Trash mobs are empowered

    // Player affixes (positive)
    prideful, // Players get buff for killing enemies
    shrouded, // Some enemies are invisible until attacked
    encrypted, // Enemies drop buffs that empower players
};

/// Active affix with its configuration
pub const ActiveAffix = struct {
    affix: EncounterAffix,

    /// Strength multiplier (1.0 = standard)
    intensity: f32 = 1.0,

    /// Custom parameters based on affix type
    custom_value: f32 = 0.0,
};

// ============================================================================
// ENCOUNTER PRIMITIVE - THE MAIN STRUCT
// ============================================================================

/// Complete encounter definition - composes all primitives
pub const Encounter = struct {
    /// Unique identifier for this encounter
    id: [:0]const u8,

    /// Display name
    name: [:0]const u8,

    /// Description shown in UI
    description: [:0]const u8 = "",

    // ========== WHAT - Enemy Composition ==========

    /// Enemy waves present in the encounter
    enemy_waves: []const EnemyWave = &[_]EnemyWave{},

    /// Optional boss configuration
    boss: ?BossConfig = null,

    // ========== WHERE - Arena Setup ==========

    /// Arena boundaries
    arena_bounds: ArenaBounds = .{},

    /// Pre-placed terrain modifications
    terrain_patches: []const TerrainPatch = &[_]TerrainPatch{},

    /// Hazard zones active at start
    hazard_zones: []const HazardZone = &[_]HazardZone{},

    /// Spawn point for players
    player_spawn: rl.Vector3 = .{ .x = 0, .y = 0, .z = 200 },

    /// Spawn spread radius for party
    player_spawn_radius: f32 = 30.0,

    // ========== WHEN - Timing/Pacing ==========

    /// Engagement and aggro rules
    engagement_rules: EngagementRules = .{},

    /// Global phase triggers (not boss-specific)
    phase_triggers: []const EncounterPhase = &[_]EncounterPhase{},

    /// Time limit for encounter (0 = no limit)
    time_limit_ms: u32 = 0,

    /// Warmup time before enemies activate
    warmup_time_ms: u32 = 3000,

    // ========== IF - Victory/Failure ==========

    /// Objectives to complete
    objectives: []const Objective = &[_]Objective{},

    /// Ways to fail the encounter
    failure_conditions: []const FailureCondition = &[_]FailureCondition{.party_wipe},

    // ========== DIFFICULTY/SCALING ==========

    /// Base difficulty rating (1-10)
    difficulty_rating: u8 = 1,

    /// Active affixes
    affixes: []const ActiveAffix = &[_]ActiveAffix{},

    /// Minimum party size
    min_party_size: u8 = 1,

    /// Maximum party size
    max_party_size: u8 = 4,

    /// Recommended party size
    recommended_party_size: u8 = 4,

    // ========== REWARDS ==========

    /// Skills that can be captured from this encounter
    capturable_skills: []const *const Skill = &[_]*const Skill{},

    /// Does completing this unlock something?
    unlocks_encounter_id: ?[:0]const u8 = null,

    // ========================================================================
    // HELPER METHODS
    // ========================================================================

    /// Calculate total enemy count
    pub fn getTotalEnemyCount(self: *const Encounter) usize {
        var count: usize = 0;
        for (self.enemy_waves) |wave| {
            count += wave.enemies.len;
        }
        if (self.boss) |boss| {
            _ = boss;
            count += 1;
            // TODO: count adds from all phases
        }
        return count;
    }

    /// Check if encounter has a boss
    pub fn hasBoss(self: *const Encounter) bool {
        return self.boss != null;
    }

    /// Get estimated duration in seconds
    pub fn getEstimatedDuration(self: *const Encounter) u32 {
        // Rough estimate: 30 seconds per enemy + 60 seconds per boss phase
        var duration: u32 = @intCast(self.getTotalEnemyCount() * 30);
        if (self.boss) |boss| {
            duration += @as(u32, @intCast(boss.phases.len)) * 60;
        }
        return duration;
    }
};

/// Non-boss phase changes (environmental, encounter-wide)
pub const EncounterPhase = struct {
    trigger: PhaseTrigger,
    arena_changes: []const ArenaMod = &[_]ArenaMod{},
    spawn_wave_indices: []const u8 = &[_]u8{}, // Additional waves to activate
    announcement: ?[:0]const u8 = null,
};

// ============================================================================
// EXAMPLE ENCOUNTERS (for reference/testing)
// ============================================================================

/// Simple arena encounter - just waves of enemies
pub const example_trash_pull = Encounter{
    .id = "tutorial_trash",
    .name = "Training Grounds",
    .description = "A simple encounter to learn the basics.",
    .enemy_waves = &[_]EnemyWave{
        .{
            .enemies = &[_]EnemySpec{
                .{ .name = "Snowball Scout", .position = .pitcher, .difficulty_rating = 1 },
                .{ .name = "Snowball Scout", .position = .pitcher, .difficulty_rating = 1 },
            },
            .spawn_position = .{ .x = 0, .y = 0, .z = -100 },
            .engagement_radius = 120.0,
        },
    },
    .objectives = &[_]Objective{
        .{ .objective_type = .kill_all, .description = "Defeat all enemies" },
    },
};

/// Boss encounter with phases
pub const example_boss_encounter = Encounter{
    .id = "frost_giant",
    .name = "The Frost Giant's Lair",
    .description = "Face the ancient Frost Giant in his frozen domain.",
    .arena_bounds = .{
        .shape = .circle,
        .primary_size = 400.0,
        .boundary_behavior = .damaging,
        .boundary_damage = 20.0,
    },
    .terrain_patches = &[_]TerrainPatch{
        .{ .center = .{ .x = 0, .y = 0, .z = 0 }, .radius = 100.0, .terrain_type = .icy_ground },
    },
    .hazard_zones = &[_]HazardZone{
        .{
            .center = .{ .x = -200, .y = 0, .z = 0 },
            .radius = 50.0,
            .hazard_type = .damage,
            .damage_per_tick = 15.0,
            .tick_rate_ms = 1000,
        },
    },
    .boss = .{
        .base = .{
            .name = "Frost Giant",
            .school = .homeschool,
            .position = .shoveler,
            .warmth_multiplier = 5.0,
            .damage_multiplier = 1.5,
            .scale = 2.0,
            .difficulty_rating = 10,
            .immune_to_knockdown = true,
        },
        .phases = &[_]BossPhase{
            .{
                .trigger = .combat_start,
                .phase_name = "The Giant Awakens",
                .boss_yell = "WHO DISTURBS MY SLUMBER?!",
            },
            .{
                .trigger = .{ .warmth_percent = 0.5 },
                .phase_name = "Frozen Rage",
                .boss_yell = "YOU WILL FREEZE!",
                .damage_multiplier = 1.3,
                .add_spawn = &[_]EnemySpec{
                    .{ .name = "Ice Sprite", .position = .pitcher, .difficulty_rating = 2 },
                    .{ .name = "Ice Sprite", .position = .pitcher, .difficulty_rating = 2 },
                },
            },
            .{
                .trigger = .{ .warmth_percent = 0.2 },
                .phase_name = "Final Stand",
                .boss_yell = "I WILL NOT FALL!",
                .damage_multiplier = 1.5,
                .speed_multiplier = 1.2,
                .arena_changes = &[_]ArenaMod{
                    .{ .add_hazard = .{
                        .center = .{ .x = 0, .y = 0, .z = 0 },
                        .radius = 150.0,
                        .hazard_type = .damage,
                        .damage_per_tick = 5.0,
                        .tick_rate_ms = 2000,
                        .shape = .ring,
                    } },
                },
            },
        },
        .arena_radius = 350.0,
        .enrage_timer_ms = 300000, // 5 minute enrage
    },
    .objectives = &[_]Objective{
        .{ .objective_type = .kill_boss, .description = "Defeat the Frost Giant" },
        .{ .objective_type = .no_deaths, .description = "No party deaths", .is_bonus = true },
    },
    .difficulty_rating = 5,
    .time_limit_ms = 600000, // 10 minute hard limit
};
