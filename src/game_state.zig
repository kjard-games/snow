const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const school = @import("school.zig");
const position = @import("position.zig");
const input = @import("input.zig");
const ai = @import("ai.zig");
const render = @import("render.zig");
const ui = @import("ui.zig");
const combat = @import("combat.zig");
const skills = @import("skills.zig");
const movement = @import("movement.zig");
const entity = @import("entity.zig");
const auto_attack = @import("auto_attack.zig");
const vfx = @import("vfx.zig");
const terrain = @import("terrain.zig");
const ground_targeting = @import("ground_targeting.zig");
const equipment = @import("equipment.zig");
const gear_slot = @import("gear_slot.zig");
const palette = @import("color_palette.zig");
const telemetry = @import("telemetry.zig");
const factory = @import("factory.zig");
const arena_props = @import("arena_props.zig");
const buildings_mod = @import("buildings.zig");

const print = std.debug.print;

// ============================================
// GAME STATE BUILDER
// ============================================

/// Configuration for building a GameState instance.
/// Use GameStateBuilder for a fluent API to construct this.
pub const GameStateConfig = struct {
    /// Enable rendering (false for headless simulations)
    rendering: bool = true,
    /// Enable player control (false for AI-only simulations)
    player_controlled: bool = true,
    /// Enable telemetry recording
    telemetry: bool = false,
    /// RNG seed (null = use current timestamp)
    seed: ?u64 = null,
    /// Pre-built characters (null = generate random teams)
    characters: ?[]const Character = null,
    /// Pre-built AI states (null = generate from characters)
    ai_states: ?[]const AIState = null,
    /// Number of characters per team (used when generating random teams)
    characters_per_team: usize = 4,
    /// Terrain grid dimensions
    terrain_width: usize = 100,
    terrain_height: usize = 100,
    terrain_cell_size: f32 = 20.0,
};

/// Builder for constructing GameState instances with various configurations.
/// Consolidates init(), initHeadless(), initHeadlessAIOnly(), and initWithFactory().
pub const GameStateBuilder = struct {
    allocator: std.mem.Allocator,
    config: GameStateConfig,

    pub fn init(allocator: std.mem.Allocator) GameStateBuilder {
        return .{
            .allocator = allocator,
            .config = .{},
        };
    }

    /// Enable/disable rendering (disabling creates a headless simulation)
    pub fn withRendering(self: *GameStateBuilder, enabled: bool) *GameStateBuilder {
        self.config.rendering = enabled;
        return self;
    }

    /// Enable/disable player control (disabling creates AI-only simulation)
    pub fn withPlayerControl(self: *GameStateBuilder, enabled: bool) *GameStateBuilder {
        self.config.player_controlled = enabled;
        return self;
    }

    /// Enable/disable telemetry recording
    pub fn withTelemetry(self: *GameStateBuilder, enabled: bool) *GameStateBuilder {
        self.config.telemetry = enabled;
        return self;
    }

    /// Set RNG seed (for reproducible simulations)
    pub fn withSeed(self: *GameStateBuilder, seed: u64) *GameStateBuilder {
        self.config.seed = seed;
        return self;
    }

    /// Provide pre-built characters (skips random team generation)
    pub fn withCharacters(self: *GameStateBuilder, characters: []const Character) *GameStateBuilder {
        self.config.characters = characters;
        return self;
    }

    /// Provide pre-built AI states (skips automatic AI state generation)
    pub fn withAIStates(self: *GameStateBuilder, ai_states: []const AIState) *GameStateBuilder {
        self.config.ai_states = ai_states;
        return self;
    }

    /// Set number of characters per team (when generating random teams)
    pub fn withCharactersPerTeam(self: *GameStateBuilder, count: usize) *GameStateBuilder {
        self.config.characters_per_team = count;
        return self;
    }

    /// Set terrain grid dimensions
    pub fn withTerrainSize(self: *GameStateBuilder, width: usize, height: usize, cell_size: f32) *GameStateBuilder {
        self.config.terrain_width = width;
        self.config.terrain_height = height;
        self.config.terrain_cell_size = cell_size;
        return self;
    }

    /// Build the GameState with the configured options
    pub fn build(self: *GameStateBuilder) !GameState {
        // Initialize RNG
        const seed = self.config.seed orelse blk: {
            const timestamp = std.time.timestamp();
            break :blk @as(u64, @bitCast(timestamp));
        };
        var prng = std.Random.DefaultPrng.init(seed);
        var rng = prng.random();

        var id_gen = EntityIdGenerator{};

        // Build or use provided characters
        var entities: [MAX_ENTITIES]Character = undefined;
        var active_entity_count: usize = 0;

        if (self.config.characters) |chars| {
            // Use provided characters
            for (chars, 0..) |char, i| {
                if (i >= MAX_ENTITIES) break;
                entities[i] = char;
                active_entity_count += 1;
            }
        } else {
            // Generate random teams
            active_entity_count = try self.generateRandomTeams(&entities, &rng, &id_gen);
        }

        // Fill remaining slots with dummy characters
        for (active_entity_count..MAX_ENTITIES) |i| {
            entities[i] = createDummyCharacter(&id_gen);
        }

        // Determine controlled entity
        const controlled_id: EntityId = if (self.config.player_controlled)
            entities[0].id // Player controls first entity
        else
            999; // Invalid ID = no player control

        // Initialize terrain
        const terrain_grid = if (self.config.rendering)
            try TerrainGrid.init(
                self.allocator,
                self.config.terrain_width,
                self.config.terrain_height,
                self.config.terrain_cell_size,
                -@as(f32, @floatFromInt(self.config.terrain_width)) * self.config.terrain_cell_size / 2.0,
                -@as(f32, @floatFromInt(self.config.terrain_height)) * self.config.terrain_cell_size / 2.0,
            )
        else
            try TerrainGrid.initHeadless(
                self.allocator,
                self.config.terrain_width,
                self.config.terrain_height,
                self.config.terrain_cell_size,
                -@as(f32, @floatFromInt(self.config.terrain_width)) * self.config.terrain_cell_size / 2.0,
                -@as(f32, @floatFromInt(self.config.terrain_height)) * self.config.terrain_cell_size / 2.0,
            );

        // Generate terrain mesh only if rendering
        if (self.config.rendering) {
            var mutable_grid = terrain_grid;
            mutable_grid.generateTerrainMesh();
        }

        // Handle cursor state for rendering mode
        if (self.config.rendering and self.config.player_controlled) {
            // Check for gamepad and set cursor state
            if (rl.isGamepadAvailable(0)) {
                rl.disableCursor();
            } else {
                rl.enableCursor();
            }
        }

        // Build AI states - use provided or generate from entities
        var ai_states: [MAX_ENTITIES]AIState = undefined;
        if (self.config.ai_states) |provided_ai| {
            // Use provided AI states
            for (provided_ai, 0..) |ai_state, i| {
                if (i >= MAX_ENTITIES) break;
                ai_states[i] = ai_state;
            }
            // Fill remaining with defaults
            for (provided_ai.len..MAX_ENTITIES) |i| {
                ai_states[i] = AIState.init(entities[i].player_position);
            }
        } else {
            // Generate from entities - healers get support role, others get damage_dealer
            for (entities, 0..) |ent, i| {
                ai_states[i] = AIState.init(ent.player_position);
            }
        }

        return GameState{
            .entities = entities,
            .controlled_entity_id = controlled_id,
            .selected_target = null,
            .camera = rl.Camera{
                .position = .{ .x = 0, .y = 50, .z = 80 }, // Start closer, lower (kid perspective)
                .target = .{ .x = 0, .y = 8, .z = 0 }, // Target at kid eye level
                .up = .{ .x = 0, .y = 1, .z = 0 },
                .fovy = 70.0, // Wider FOV for more immersive feel (was 55)
                .projection = .perspective,
            },
            .input_state = input.InputState{
                .action_camera = self.config.rendering and rl.isGamepadAvailable(0),
            },
            .ai_states = ai_states,
            .rng = prng,
            .combat_state = .active,
            .entity_id_gen = id_gen,
            .vfx_manager = vfx.VFXManager.init(),
            .terrain_grid = terrain_grid,
            .allocator = self.allocator,
            .simulation_mode = !self.config.rendering,
            .prop_manager = PropManager.init(self.allocator),
            .building_manager = BuildingManager.init(self.allocator),
        };
    }

    /// Generate random 4v4 teams (blue vs red)
    fn generateRandomTeams(self: *GameStateBuilder, entities: *[MAX_ENTITIES]Character, rng: *std.Random, id_gen: *EntityIdGenerator) !usize {
        const chars_per_team = self.config.characters_per_team;
        var entity_idx: usize = 0;

        // Ally team positions
        const ally_positions = [_]rl.Vector3{
            .{ .x = -80, .y = 0, .z = 400 },
            .{ .x = 80, .y = 0, .z = 400 },
            .{ .x = -120, .y = 0, .z = 500 },
            .{ .x = 0, .y = 0, .z = 550 },
        };

        // Enemy team positions
        const enemy_positions = [_]rl.Vector3{
            .{ .x = -80, .y = 0, .z = -400 },
            .{ .x = 80, .y = 0, .z = -400 },
            .{ .x = -120, .y = 0, .z = -500 },
            .{ .x = 0, .y = 0, .z = -550 },
        };

        // Generate ally team (blue)
        for (0..chars_per_team) |i| {
            if (entity_idx >= MAX_ENTITIES) break;
            const pos_idx = @min(i, ally_positions.len - 1);
            const is_healer = i == chars_per_team - 1; // Last character is healer

            entities[entity_idx] = createRandomCharacter(
                id_gen,
                rng,
                .blue,
                ally_positions[pos_idx],
                if (i == 0) "Player" else if (is_healer) "Ally Healer" else "Ally",
                is_healer,
            );
            entity_idx += 1;
        }

        // Generate enemy team (red)
        for (0..chars_per_team) |i| {
            if (entity_idx >= MAX_ENTITIES) break;
            const pos_idx = @min(i, enemy_positions.len - 1);
            const is_healer = i == chars_per_team - 1;

            entities[entity_idx] = createRandomCharacter(
                id_gen,
                rng,
                .red,
                enemy_positions[pos_idx],
                if (is_healer) "Enemy Healer" else "Enemy",
                is_healer,
            );
            entity_idx += 1;
        }

        return entity_idx;
    }
};

/// Create a random character with the given team and position
fn createRandomCharacter(
    id_gen: *EntityIdGenerator,
    rng: *std.Random,
    team: entity.Team,
    pos: rl.Vector3,
    name: [:0]const u8,
    force_healer: bool,
) Character {
    const all_schools = [_]School{ .private_school, .public_school, .montessori, .homeschool, .waldorf };
    const non_healer_positions = [_]Position{ .pitcher, .fielder, .sledder, .shoveler, .animator };

    const selected_school = all_schools[rng.intRangeAtMost(usize, 0, all_schools.len - 1)];
    const selected_position: Position = if (force_healer)
        .thermos
    else
        non_healer_positions[rng.intRangeAtMost(usize, 0, non_healer_positions.len - 1)];

    var char = Character{
        .id = id_gen.generate(),
        .position = pos,
        .previous_position = pos,
        .radius = 10,
        .color = if (team == .blue) .blue else .red,
        .school_color = palette.getSchoolColor(selected_school),
        .position_color = palette.getPositionColor(selected_position),
        .name = name,
        .team = team,
        .school = selected_school,
        .player_position = selected_position,
    };

    // Initialize stats
    char.stats.warmth = 150;
    char.stats.max_warmth = 150;
    char.stats.energy = selected_school.getMaxEnergy();
    char.stats.max_energy = selected_school.getMaxEnergy();

    // Set character color based on school + position
    char.color = palette.getCharacterColor(selected_school, selected_position);

    // Load skills
    loadRandomSkills(&char, rng);

    // Assign random equipment
    assignRandomEquipment(&char, rng);

    return char;
}

/// Load random skills into a character's skill bar
fn loadRandomSkills(char: *Character, rng: *std.Random) void {
    const position_skills = char.player_position.getSkills();
    const school_skills = char.school.getSkills();

    // Find and load a wall skill into slot 0 (if available)
    var wall_skill_loaded = false;
    for (position_skills) |*skill| {
        if (skill.creates_wall) {
            char.casting.skills[0] = skill;
            wall_skill_loaded = true;
            break;
        }
    }

    // Fallback: use first position skill if no wall skill
    if (!wall_skill_loaded and position_skills.len > 0) {
        char.casting.skills[0] = &position_skills[0];
    }

    // Fill slots 1-3 with random position skills
    var slot_idx: usize = 1;
    var attempts: usize = 0;
    while (slot_idx < 4 and attempts < position_skills.len * 3) : (attempts += 1) {
        if (position_skills.len == 0) break;

        const random_idx = rng.intRangeAtMost(usize, 0, position_skills.len - 1);
        const skill = &position_skills[random_idx];

        // Check not already loaded
        var already_loaded = false;
        for (0..slot_idx) |check_idx| {
            if (char.casting.skills[check_idx] == skill) {
                already_loaded = true;
                break;
            }
        }

        if (!already_loaded) {
            char.casting.skills[slot_idx] = skill;
            slot_idx += 1;
        }
    }

    // Fill slots 4-7 with random school skills
    slot_idx = 4;
    attempts = 0;
    while (slot_idx < 8 and attempts < school_skills.len * 3) : (attempts += 1) {
        if (school_skills.len == 0) break;

        const random_idx = rng.intRangeAtMost(usize, 0, school_skills.len - 1);
        const skill = &school_skills[random_idx];

        // Check not already loaded
        var already_loaded = false;
        for (4..slot_idx) |check_idx| {
            if (char.casting.skills[check_idx] == skill) {
                already_loaded = true;
                break;
            }
        }

        if (!already_loaded) {
            char.casting.skills[slot_idx] = skill;
            slot_idx += 1;
        }
    }
}

/// Assign random equipment to a character
fn assignRandomEquipment(char: *Character, rng: *std.Random) void {
    const melee_weapons = [_]*const equipment.Equipment{ &equipment.BigShovel, &equipment.IceScraper };
    const throwing_tools = [_]*const equipment.Equipment{ &equipment.LacrosseStick, &equipment.JaiAlaiScoop, &equipment.Slingshot };
    const shields = [_]*const equipment.Equipment{ &equipment.SaucerSled, &equipment.GarbageCanLid };
    const utility_items = [_]*const equipment.Equipment{ &equipment.Thermos, &equipment.Toboggan };
    const worn_items = [_]*const equipment.Equipment{ &equipment.Mittens, &equipment.Blanket };

    const roll = rng.intRangeAtMost(u8, 0, 100);

    if (roll < 30) {
        const melee = melee_weapons[rng.intRangeAtMost(usize, 0, melee_weapons.len - 1)];
        char.main_hand = melee;
        if (melee.hand_requirement == .one_hand and rng.boolean()) {
            char.off_hand = shields[rng.intRangeAtMost(usize, 0, shields.len - 1)];
        }
    } else if (roll < 60) {
        const thrower = throwing_tools[rng.intRangeAtMost(usize, 0, throwing_tools.len - 1)];
        char.main_hand = thrower;
        if (thrower.hand_requirement == .one_hand and rng.boolean()) {
            if (rng.boolean()) {
                char.off_hand = shields[rng.intRangeAtMost(usize, 0, shields.len - 1)];
            } else {
                char.off_hand = &equipment.Thermos;
            }
        }
    } else if (roll < 80) {
        if (rng.boolean()) {
            char.main_hand = utility_items[rng.intRangeAtMost(usize, 0, utility_items.len - 1)];
        } else {
            char.main_hand = shields[rng.intRangeAtMost(usize, 0, shields.len - 1)];
            if (rng.boolean()) {
                char.off_hand = &equipment.JaiAlaiScoop;
            }
        }
    }

    if (rng.boolean()) {
        char.worn = worn_items[rng.intRangeAtMost(usize, 0, worn_items.len - 1)];
    }

    // Assign gear (armor padding)
    assignRandomGear(char, rng);
}

/// Assign random gear to a character's 6 gear slots
fn assignRandomGear(char: *Character, rng: *std.Random) void {
    const head_pieces = [_]*const gear_slot.Gear{ &gear_slot.WoolCap, &gear_slot.SkiBeanie, &gear_slot.WinterParkaHood };
    const neck_pieces = [_]*const gear_slot.Gear{ &gear_slot.LightScarf, &gear_slot.PuffyScarf, &gear_slot.WoolNeckGuard };
    const torso_pieces = [_]*const gear_slot.Gear{ &gear_slot.Hoodie, &gear_slot.SkiJacket, &gear_slot.HeavyParka };
    const hands_pieces = [_]*const gear_slot.Gear{ &gear_slot.Mittens, &gear_slot.InsulatedGloves, &gear_slot.ThermalGauntlets };
    const legs_pieces = [_]*const gear_slot.Gear{ &gear_slot.Joggers, &gear_slot.SnowPants, &gear_slot.ThermalLeggings };
    const feet_pieces = [_]*const gear_slot.Gear{ &gear_slot.Sneakers, &gear_slot.InsulatedBoots, &gear_slot.IceClimbingBoots };

    char.gear[0] = head_pieces[rng.intRangeAtMost(usize, 0, head_pieces.len - 1)];
    char.gear[1] = neck_pieces[rng.intRangeAtMost(usize, 0, neck_pieces.len - 1)];
    char.gear[2] = torso_pieces[rng.intRangeAtMost(usize, 0, torso_pieces.len - 1)];
    char.gear[3] = hands_pieces[rng.intRangeAtMost(usize, 0, hands_pieces.len - 1)];
    char.gear[4] = legs_pieces[rng.intRangeAtMost(usize, 0, legs_pieces.len - 1)];
    char.gear[5] = feet_pieces[rng.intRangeAtMost(usize, 0, feet_pieces.len - 1)];

    char.recalculateGearStats();
}

/// Create a dummy dead character for unused entity slots
fn createDummyCharacter(id_gen: *EntityIdGenerator) Character {
    var char = Character{
        .id = id_gen.generate(),
        .position = .{ .x = 0, .y = -1000, .z = 0 },
        .previous_position = .{ .x = 0, .y = -1000, .z = 0 },
        .radius = 1.0,
        .color = .black,
        .school_color = .black,
        .position_color = .black,
        .name = "Unused",
        .team = .blue,
        .school = school.School.montessori,
        .player_position = position.Position.pitcher,
        .gear = [_]?*const character.Gear{null} ** 6,
    };
    char.stats.warmth = 0;
    char.stats.max_warmth = 1;
    char.stats.energy = 0;
    char.stats.max_energy = 1;
    return char;
}

// Type aliases
const Character = character.Character;
const School = school.School;
const Position = position.Position;
const Skill = character.Skill;
const AIState = ai.AIState;
const EntityId = entity.EntityId;
const EntityIdGenerator = entity.EntityIdGenerator;
pub const TerrainGrid = terrain.TerrainGrid;
const MatchTelemetry = telemetry.MatchTelemetry;
const SkillRangePreviewState = ground_targeting.SkillRangePreviewState;
const PropManager = arena_props.PropManager;
const BuildingManager = buildings_mod.BuildingManager;

// Game configuration constants
pub const MAX_ENTITIES: usize = 128; // Support dungeon encounters with many enemies (4 player party + up to 124 enemies/NPCs)

// Tick-based game loop (Guild Wars / tab-targeting style)
pub const TICK_RATE_HZ: u32 = 20; // 20 ticks per second
pub const TICK_RATE_MS: u32 = 50; // 50 milliseconds per tick
pub const TICK_RATE_SEC: f32 = 0.05; // 0.05 seconds per tick

pub const CombatState = enum {
    active,
    victory,
    defeat,
};

/// Core game state managing all entities, combat systems, and game loop timing.
/// Uses fixed-timestep update (20Hz) with interpolated rendering for smooth visuals.
pub const GameState = struct {
    entities: [MAX_ENTITIES]Character, // All entities including player
    controlled_entity_id: EntityId, // Which entity the local player controls
    selected_target: ?EntityId, // Target referenced by ID, not array index
    camera: rl.Camera,
    input_state: input.InputState,
    ai_states: [MAX_ENTITIES]AIState,
    rng: std.Random.DefaultPrng,
    combat_state: CombatState,

    // Entity ID management
    entity_id_gen: EntityIdGenerator = .{},

    // Tick-based game loop state
    tick_accumulator: f32 = 0.0,
    current_tick: u64 = 0,

    // Visual effects
    vfx_manager: vfx.VFXManager,

    // Terrain system
    terrain_grid: TerrainGrid,
    allocator: std.mem.Allocator,

    // Telemetry system (optional - null for interactive play, Some for recording)
    match_telemetry: ?*MatchTelemetry = null,

    // Simulation mode: when true, skip raylib input polling (for headless battle simulation)
    simulation_mode: bool = false,

    // Skill range preview state (for hover and cast previews)
    skill_range_preview: SkillRangePreviewState = .{},

    // Arena props system (placed environment objects)
    prop_manager: ?PropManager = null,

    // Building system (3D buildings from OSM data)
    building_manager: ?BuildingManager = null,

    // ============================================
    // INITIALIZATION METHODS
    // ============================================
    // Use GameStateBuilder or the convenience methods below:
    // - initWithFactory() - for interactive play with rendering
    // - initHeadlessSimulation() - for AI-only simulations
    // - initWithCharacters() - for simulations with custom characters

    /// Initialize game state using the builder pattern.
    /// This is the recommended way to create a GameState for interactive play.
    pub fn initWithFactory(allocator: std.mem.Allocator) !GameState {
        var builder = GameStateBuilder.init(allocator);
        return builder
            .withRendering(true)
            .withPlayerControl(true)
            .build();
    }

    /// Initialize headless simulation (AI-only, no rendering)
    /// Use this for balance testing and automated simulations.
    pub fn initHeadlessSimulation(allocator: std.mem.Allocator) !GameState {
        var builder = GameStateBuilder.init(allocator);
        return builder
            .withRendering(false)
            .withPlayerControl(false)
            .build();
    }

    /// Initialize headless simulation with pre-built characters.
    /// Use this when you want full control over team composition.
    pub fn initWithCharacters(allocator: std.mem.Allocator, characters: []const Character) !GameState {
        var builder = GameStateBuilder.init(allocator);
        return builder
            .withRendering(false)
            .withPlayerControl(false)
            .withCharacters(characters)
            .build();
    }

    /// Clean up allocated resources. Must be called before GameState goes out of scope.
    pub fn deinit(self: *GameState) void {
        self.terrain_grid.deinit();
        if (self.building_manager) |*bm| {
            bm.deinit();
        }
    }

    // ============================================
    // ENTITY ACCESS HELPERS
    // ============================================

    // Entity lookup helpers for tab-targeting
    pub fn getEntityById(self: *GameState, id: EntityId) ?*Character {
        // Search entities array (player is now in here too!)
        for (&self.entities) |*ent| {
            if (ent.id == id) return ent;
        }
        return null;
    }

    pub fn getEntityByIdConst(self: *const GameState, id: EntityId) ?*const Character {
        // Search entities array (player is now in here too!)
        for (&self.entities) |*ent| {
            if (ent.id == id) return ent;
        }
        return null;
    }

    // Get the player-controlled entity
    pub fn getPlayer(self: *GameState) *Character {
        return self.getEntityById(self.controlled_entity_id).?;
    }

    pub fn getPlayerConst(self: *const GameState) *const Character {
        return self.getEntityByIdConst(self.controlled_entity_id).?;
    }

    /// Main update loop. Accumulates frame time and processes fixed-timestep ticks at 20Hz.
    /// Input is polled every frame (60fps) but game logic runs at 20fps for determinism.
    pub fn update(self: *GameState) void {
        // Clamp frame time to prevent spiral of death (e.g., after breakpoint or long pause)
        // Max 250ms ensures we don't process too many ticks at once
        const raw_frame_time = rl.getFrameTime();
        const frame_time = @min(raw_frame_time, 0.25);

        // Poll input EVERY FRAME (60fps) to buffer all inputs
        // This prevents missing rapid inputs like Tab presses between ticks
        // In simulation mode, skip polling to avoid raylib calls
        if (!self.simulation_mode) {
            input.pollInput(&self.entities, &self.camera, &self.input_state);
        }

        // Accumulate time for tick loop
        self.tick_accumulator += frame_time;

        // Fixed timestep tick loop (love the tick!)
        // Process game logic at exactly 20Hz (50ms per tick)
        while (self.tick_accumulator >= TICK_RATE_SEC) {
            self.processTick();
            self.tick_accumulator -= TICK_RATE_SEC;
            self.current_tick += 1;
        }
    }

    pub fn processTick(self: *GameState) void {
        // ALL game logic runs here at fixed 20Hz tick rate (50ms per tick)
        // This makes the game deterministic and multiplayer-ready

        // Save previous positions for interpolation BEFORE any movement this tick
        // Update energy, cooldowns, conditions, warmth for ALL entities (including player!)
        for (&self.entities) |*ent| {
            ent.previous_position = ent.position;
            ent.updateEnergy(TICK_RATE_SEC);
            ent.updateCooldowns(TICK_RATE_SEC);
            ent.updateConditions(TICK_RATE_MS);
            ent.updateBehaviors(TICK_RATE_MS); // Update active behaviors (duration, cooldowns)
            ent.updateWarmth(TICK_RATE_SEC); // Warmth regen/degen from pips
            ent.updateDamageMonitor(TICK_RATE_SEC); // Update damage monitor timers
        }

        // Handle input and AI (only if combat is active)
        var random_state = self.rng.random();
        if (self.combat_state == .active) {
            // In simulation mode (AI-only), skip player input handling
            if (!self.simulation_mode) {
                // Get player-controlled entity (only in interactive mode)
                const player = self.getPlayer();

                // Update player's facing angle from camera (camera is player-specific)
                player.facing_angle = self.input_state.camera_angle;

                // Get player movement intent from input
                const player_movement = input.handleInput(player, &self.entities, &self.selected_target, &self.camera, &self.input_state, &random_state, &self.vfx_manager, &self.terrain_grid);

                // Only apply movement if not casting (GW1 rule: can't move while casting)
                if (player.casting.state == .idle) {
                    movement.applyMovement(player, player_movement, &self.entities, null, null, TICK_RATE_SEC, &self.terrain_grid, if (self.building_manager) |*bm| bm else null);
                }
            }

            // Update AI for all entities (in AI-only mode) or non-player entities (in interactive mode)
            ai.updateAI(&self.entities, self.controlled_entity_id, TICK_RATE_SEC, &self.ai_states, &random_state, &self.vfx_manager, &self.terrain_grid, self.match_telemetry, if (self.building_manager) |*bm| bm else null);

            // Update auto-attacks for all entities
            auto_attack.updateAutoAttacks(&self.entities, TICK_RATE_SEC, &random_state, &self.vfx_manager);

            // Finish any completed casts
            self.finishCasts(&random_state);

            // Check for victory/defeat
            self.checkCombatStatus();
        }

        // Apply terrain traffic from entity movement (packs snow down over time)
        for (self.entities) |ent| {
            if (ent.isAlive()) {
                // Check if entity moved this tick
                const moved_distance = @sqrt(
                    (ent.position.x - ent.previous_position.x) * (ent.position.x - ent.previous_position.x) +
                        (ent.position.z - ent.previous_position.z) * (ent.position.z - ent.previous_position.z),
                );

                // Apply traffic proportional to distance moved (more movement = more packing)
                // Higher multiplier means paths form faster from repeated movement
                if (moved_distance > 0.1) {
                    const traffic_amount = moved_distance / 50.0; // Increased from /100.0 - packs faster
                    self.terrain_grid.applyMovementTraffic(ent.position.x, ent.position.z, traffic_amount);
                }
            }
        }

        // Apply trail terrain effects (e.g., Sled Carve drops ice as character moves)
        for (&self.entities) |*ent| {
            if (ent.isAlive()) {
                if (ent.getActiveTrail()) |trail| {
                    // Only apply trail if character is moving
                    if (ent.isMoving()) {
                        // Apply terrain at current position
                        self.terrain_grid.setTerrainInRadius(
                            ent.position.x,
                            ent.position.z,
                            trail.trail_radius,
                            trail.terrain_type,
                        );
                    }
                }
            }
        }

        // Update terrain (snow accumulation)
        self.terrain_grid.update(TICK_RATE_SEC);

        // Update visual effects (every tick)
        var entity_positions: [MAX_ENTITIES]vfx.EntityPosition = undefined;
        for (self.entities, 0..) |ent, i| {
            entity_positions[i] = vfx.EntityPosition{
                .id = ent.id,
                .position = ent.position,
            };
        }
        self.vfx_manager.update(TICK_RATE_SEC, &entity_positions);
    }

    pub fn checkCombatStatus(self: *GameState) void {
        // Only check if combat is still active
        if (self.combat_state != .active) return;

        if (self.simulation_mode) {
            // AI-only mode: Check if all allies or all enemies are dead
            // Use entity[0] as reference for team determination
            var all_allies_dead = true;
            var all_enemies_dead = true;

            const ref_team = self.entities[0].team;

            for (self.entities) |ent| {
                if (!ent.isAlive()) continue;

                if (ent.team == ref_team) {
                    all_allies_dead = false;
                } else {
                    all_enemies_dead = false;
                }
            }

            if (all_allies_dead) {
                print("=== DEFEAT! ===\n", .{});
                print("All allies defeated!\n", .{});
                self.combat_state = .defeat;
            } else if (all_enemies_dead) {
                print("=== VICTORY! ===\n", .{});
                print("All enemies defeated!\n", .{});
                self.combat_state = .victory;
            }
        } else {
            // Interactive mode: Check if player is dead
            const player = self.getPlayerConst();
            if (!player.isAlive()) {
                print("=== DEFEAT! ===\n", .{});
                print("Player has been defeated!\n", .{});
                self.combat_state = .defeat;
                return;
            }

            // Check if all enemies are dead
            var all_enemies_dead = true;
            var alive_enemy_count: u32 = 0;
            for (self.entities) |ent| {
                if (player.isEnemy(ent) and ent.isAlive()) {
                    all_enemies_dead = false;
                    alive_enemy_count += 1;
                }
            }

            if (all_enemies_dead) {
                print("=== VICTORY! ===\n", .{});
                print("All enemies defeated!\n", .{});
                self.combat_state = .victory;
            }
        }
    }

    fn finishCasts(self: *GameState, rng: *std.Random) void {
        // Check cast completions for ALL entities (including player!)
        for (&self.entities) |*ent| {
            if (ent.casting.state == .activating) {
                const skill = ent.casting.skills[ent.casting.casting_skill_index] orelse continue;

                // Check for attack skills that execute at half activation
                const half_activation_time = @as(f32, @floatFromInt(skill.activation_time_ms)) / 2000.0;
                const total_activation_time = @as(f32, @floatFromInt(skill.activation_time_ms)) / 1000.0;

                // Execute attack skills at half activation time
                if (skill.mechanic.executesAtHalfActivation() and !ent.casting.skill_executed) {
                    const time_elapsed = total_activation_time - ent.casting.cast_time_remaining;
                    if (time_elapsed >= half_activation_time) {
                        self.executeSkillEffect(ent, skill, rng);
                        ent.casting.skill_executed = true;
                    }
                }

                // Check if activation phase is complete
                if (ent.casting.cast_time_remaining <= 0) {
                    // Execute non-attack skills at end of activation
                    if (!skill.mechanic.executesAtHalfActivation() and !ent.casting.skill_executed) {
                        self.executeSkillEffect(ent, skill, rng);
                        ent.casting.skill_executed = true;
                    }

                    // Transition to aftercast if skill has one
                    if (skill.mechanic.hasAftercast()) {
                        ent.casting.state = .aftercast;
                        ent.casting.aftercast_time_remaining = @as(f32, @floatFromInt(skill.aftercast_ms)) / 1000.0;
                    } else {
                        ent.casting.state = .idle;
                    }

                    ent.casting.cast_target_id = null;
                    ent.casting.cast_ground_position = null;
                    ent.casting.skill_executed = false;
                }
            }
        }
    }

    fn executeSkillEffect(self: *GameState, ent: *Character, skill: *const Skill, rng: *std.Random) void {
        // Check for ground-targeted skills first
        if (ent.casting.cast_ground_position) |ground_pos| {
            // Execute ground-targeted skill at stored position
            combat.executeSkillAtGround(ent, skill, ground_pos, ent.casting.casting_skill_index, rng, &self.vfx_manager, &self.terrain_grid, self.match_telemetry);
            return;
        }

        var target: ?*Character = null;
        var target_valid = false;

        if (ent.casting.cast_target_id) |target_id| {
            // Look up target by ID (could be player or another entity)
            target = self.getEntityById(target_id);
            if (target) |tgt| {
                if (tgt.isAlive()) {
                    target_valid = true;
                } else {
                    print("{s}'s target died during cast!\n", .{ent.name});
                }
            }
        } else if (skill.target_type == .self) {
            target_valid = true;
        }

        if (target_valid) {
            combat.executeSkill(ent, skill, target, ent.casting.casting_skill_index, rng, &self.vfx_manager, &self.terrain_grid, self.match_telemetry);
        }
    }

    /// Render the game world with interpolated positions for smooth visuals between ticks.
    pub fn draw(self: *GameState) void {
        // Calculate interpolation alpha for smooth rendering between ticks
        // alpha = 0.0 means just after a tick, alpha = 1.0 means about to tick
        const alpha = self.tick_accumulator / TICK_RATE_SEC;

        // Update camera to follow interpolated player position (smooth every frame!)
        const player = self.getPlayerConst();
        const player_render_pos = player.getInterpolatedPosition(alpha);
        input.updateCamera(&self.camera, player_render_pos, self.input_state);

        // Update skill range preview state from UI hover
        self.skill_range_preview.updateFromUI(
            self.input_state.hovered_skill_index,
            player,
            &self.entities,
            self.selected_target,
        );

        render.draw(player, &self.entities, self.selected_target, self.camera, alpha, &self.vfx_manager, &self.terrain_grid, &self.input_state.ground_targeting, &self.skill_range_preview, if (self.prop_manager) |*pm| pm else null, if (self.building_manager) |*bm| bm else null);
    }

    /// Render UI elements (skill bars, target info, etc.) on top of the 3D scene.
    pub fn drawUI(self: *GameState) void {
        const player = self.getPlayerConst();
        ui.drawUI(player, &self.entities, self.selected_target, &self.input_state, self.camera, &self.terrain_grid);

        // Draw building legend (only shown when buildings are present)
        ui.drawBuildingLegend(if (self.building_manager) |*bm| bm else null);
    }
};
