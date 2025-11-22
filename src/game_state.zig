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

const print = std.debug.print;

// Type aliases
const Character = character.Character;
const School = school.School;
const Position = position.Position;
const Skill = character.Skill;
const AIState = ai.AIState;
const EntityId = entity.EntityId;
const EntityIdGenerator = entity.EntityIdGenerator;
const TerrainGrid = terrain.TerrainGrid;

// Game configuration constants
pub const MAX_ENTITIES: usize = 8; // 4v4 combat (4 allies + 4 enemies)

// Tick-based game loop (Guild Wars / tab-targeting style)
pub const TICK_RATE_HZ: u32 = 20; // 20 ticks per second
pub const TICK_RATE_MS: u32 = 50; // 50 milliseconds per tick
pub const TICK_RATE_SEC: f32 = 0.05; // 0.05 seconds per tick

pub const CombatState = enum {
    active,
    victory,
    defeat,
};

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

    pub fn init(allocator: std.mem.Allocator) !GameState {
        var id_gen = EntityIdGenerator{};

        // Initialize RNG with current time as seed (needed for random team generation)
        const timestamp = std.time.timestamp();
        const seed: u64 = @bitCast(timestamp);
        var prng = std.Random.DefaultPrng.init(seed);
        var random = prng.random();

        // Helper to pick random school
        const all_schools = [_]School{ .private_school, .public_school, .montessori, .homeschool, .waldorf };
        const pickRandomSchool = struct {
            fn pick(rng: *std.Random) School {
                const idx = rng.intRangeAtMost(usize, 0, all_schools.len - 1);
                return all_schools[idx];
            }
        }.pick;

        // Helper to pick random non-healer position
        const non_healer_positions = [_]Position{ .pitcher, .fielder, .sledder, .shoveler, .animator };
        const pickRandomPosition = struct {
            fn pick(rng: *std.Random) Position {
                const idx = rng.intRangeAtMost(usize, 0, non_healer_positions.len - 1);
                return non_healer_positions[idx];
            }
        }.pick;

        // === 4v4 Team Setup ===
        // Ally team (blue): [Player, Ally1, Ally2, Healer]
        // Enemy team (red): [Enemy1, Enemy2, Enemy3, Healer]

        // Ally team positions (front line, spread out)
        const ally_positions = [_]rl.Vector3{
            .{ .x = -40, .y = 0, .z = 50 }, // Player (left-front)
            .{ .x = 40, .y = 0, .z = 50 }, // Ally1 (right-front)
            .{ .x = -60, .y = 0, .z = 100 }, // Ally2 (left-back)
            .{ .x = 0, .y = 0, .z = 120 }, // Healer (center-back)
        };

        // Enemy team positions (opposite side)
        const enemy_positions = [_]rl.Vector3{
            .{ .x = -40, .y = 0, .z = -220 }, // Enemy1
            .{ .x = 40, .y = 0, .z = -220 }, // Enemy2
            .{ .x = -60, .y = 0, .z = -270 }, // Enemy3
            .{ .x = 0, .y = 0, .z = -290 }, // Enemy Healer
        };

        // Generate random builds for player + 2 allies + 3 enemies (6 random, 2 healer)
        const player_school = pickRandomSchool(&random);
        const player_position = pickRandomPosition(&random);

        var entities = [_]Character{
            // ===== ALLY TEAM (Blue) =====
            // Index 0: Player (random school/position)
            Character{
                .id = id_gen.generate(),
                .position = ally_positions[0],
                .previous_position = ally_positions[0],
                .radius = 20,
                .color = .blue,
                .name = "Player",
                .warmth = 100,
                .max_warmth = 100,
                .is_enemy = false,
                .school = player_school,
                .player_position = player_position,
                .energy = player_school.getMaxEnergy(),
                .max_energy = player_school.getMaxEnergy(),
                .skill_bar = [_]?*const Skill{null} ** character.MAX_SKILLS,
                .selected_skill = 0,
            },
            // Index 1: Ally 1 (random)
            Character{
                .id = id_gen.generate(),
                .position = ally_positions[1],
                .previous_position = ally_positions[1],
                .radius = 18,
                .color = .blue,
                .name = "Ally 1",
                .warmth = 100,
                .max_warmth = 100,
                .is_enemy = false,
                .school = pickRandomSchool(&random),
                .player_position = pickRandomPosition(&random),
                .energy = 0, // Set after school
                .max_energy = 0, // Set after school
                .skill_bar = [_]?*const Skill{null} ** character.MAX_SKILLS,
                .selected_skill = 0,
            },
            // Index 2: Ally 2 (random)
            Character{
                .id = id_gen.generate(),
                .position = ally_positions[2],
                .previous_position = ally_positions[2],
                .radius = 18,
                .color = .blue,
                .name = "Ally 2",
                .warmth = 100,
                .max_warmth = 100,
                .is_enemy = false,
                .school = pickRandomSchool(&random),
                .player_position = pickRandomPosition(&random),
                .energy = 0,
                .max_energy = 0,
                .skill_bar = [_]?*const Skill{null} ** character.MAX_SKILLS,
                .selected_skill = 0,
            },
            // Index 3: Ally Healer (always Thermos)
            Character{
                .id = id_gen.generate(),
                .position = ally_positions[3],
                .previous_position = ally_positions[3],
                .radius = 18,
                .color = .blue,
                .name = "Ally Healer",
                .warmth = 100,
                .max_warmth = 100,
                .is_enemy = false,
                .school = pickRandomSchool(&random),
                .player_position = .thermos, // Always healer
                .energy = 0,
                .max_energy = 0,
                .skill_bar = [_]?*const Skill{null} ** character.MAX_SKILLS,
                .selected_skill = 0,
            },

            // ===== ENEMY TEAM (Red) =====
            // Index 4: Enemy 1 (random)
            Character{
                .id = id_gen.generate(),
                .position = enemy_positions[0],
                .previous_position = enemy_positions[0],
                .radius = 18,
                .color = .red,
                .name = "Enemy 1",
                .warmth = 100,
                .max_warmth = 100,
                .is_enemy = true,
                .school = pickRandomSchool(&random),
                .player_position = pickRandomPosition(&random),
                .energy = 0,
                .max_energy = 0,
                .skill_bar = [_]?*const Skill{null} ** character.MAX_SKILLS,
                .selected_skill = 0,
            },
            // Index 6: Enemy 2 (random)
            Character{
                .id = id_gen.generate(),
                .position = enemy_positions[1],
                .previous_position = enemy_positions[1],
                .radius = 18,
                .color = .red,
                .name = "Enemy 2",
                .warmth = 100,
                .max_warmth = 100,
                .is_enemy = true,
                .school = pickRandomSchool(&random),
                .player_position = pickRandomPosition(&random),
                .energy = 0,
                .max_energy = 0,
                .skill_bar = [_]?*const Skill{null} ** character.MAX_SKILLS,
                .selected_skill = 0,
            },
            // Index 6: Enemy 3 (random)
            Character{
                .id = id_gen.generate(),
                .position = enemy_positions[2],
                .previous_position = enemy_positions[2],
                .radius = 18,
                .color = .red,
                .name = "Enemy 3",
                .warmth = 100,
                .max_warmth = 100,
                .is_enemy = true,
                .school = pickRandomSchool(&random),
                .player_position = pickRandomPosition(&random),
                .energy = 0,
                .max_energy = 0,
                .skill_bar = [_]?*const Skill{null} ** character.MAX_SKILLS,
                .selected_skill = 0,
            },
            // Index 7: Enemy Healer (always Thermos)
            Character{
                .id = id_gen.generate(),
                .position = enemy_positions[3],
                .previous_position = enemy_positions[3],
                .radius = 18,
                .color = .red,
                .name = "Enemy Healer",
                .warmth = 100,
                .max_warmth = 100,
                .is_enemy = true,
                .school = pickRandomSchool(&random),
                .player_position = .thermos, // Always healer
                .energy = 0,
                .max_energy = 0,
                .skill_bar = [_]?*const Skill{null} ** character.MAX_SKILLS,
                .selected_skill = 0,
            },
        };

        // Store player's entity ID
        const player_entity_id = entities[0].id;

        // Set energy pools based on school and load skills for all entities
        for (&entities, 0..) |*ent, i| {
            // Set energy based on school
            ent.energy = ent.school.getMaxEnergy();
            ent.max_energy = ent.school.getMaxEnergy();

            // Load skills: First 4 from position, last 4 from school
            const position_skills = ent.player_position.getSkills();
            const school_skills = ent.school.getSkills();

            const position_skill_count = @min(position_skills.len, 4);
            const school_skill_count = @min(school_skills.len, 4);

            // Slots 1-4: Position-specific skills
            for (0..position_skill_count) |skill_idx| {
                ent.skill_bar[skill_idx] = &position_skills[skill_idx];
            }

            // Slots 5-8: School-specific skills
            for (0..school_skill_count) |skill_idx| {
                ent.skill_bar[4 + skill_idx] = &school_skills[skill_idx];
            }

            // Count how many skills were loaded
            var skill_count: usize = 0;
            for (ent.skill_bar) |maybe_skill| {
                if (maybe_skill != null) skill_count += 1;
            }

            print("#{d} {s}: {s}/{s} ({d} skills)\n", .{
                i,
                ent.name,
                @tagName(ent.school),
                @tagName(ent.player_position),
                skill_count,
            });
        }

        print("\n=== 4v4 MATCH START ===\n", .{});
        print("ALLY TEAM (Blue): Player, Ally 1, Ally 2, Ally Healer\n", .{});
        print("ENEMY TEAM (Red): Enemy 1, Enemy 2, Enemy 3, Enemy Healer\n", .{});
        print("======================\n\n", .{});

        // Check if gamepad is available and default to Action Camera if so
        const has_gamepad = rl.isGamepadAvailable(0);
        const use_action_camera = has_gamepad;

        // Set cursor state based on Action Camera
        if (use_action_camera) {
            rl.disableCursor();
            print("Gamepad detected - Action Camera enabled by default\n", .{});
        } else {
            rl.enableCursor();
            print("Keyboard/Mouse mode - Action Camera disabled by default\n", .{});
        }

        // Initialize terrain grid
        // Create a 20x20 grid with 50 unit cells, covering 1000x1000 world space
        // Centered around the battlefield (offset by -500, -500)
        const terrain_grid = TerrainGrid.init(
            allocator,
            20, // width
            20, // height
            50.0, // grid_size (each cell is 50 units)
            -500.0, // world_offset_x
            -500.0, // world_offset_z
        ) catch |err| {
            print("Failed to initialize terrain grid: {}\n", .{err});
            @panic("Terrain initialization failed");
        };

        print("=== TERRAIN SYSTEM INITIALIZED ===\n", .{});
        print("Grid: 20x20 cells (50 units each)\n", .{});
        print("Coverage: 1000x1000 world units\n", .{});
        print("Snow accumulation: Active\n", .{});
        print("==================================\n\n", .{});

        return GameState{
            .entities = entities,
            .controlled_entity_id = player_entity_id,
            .selected_target = null,
            .camera = rl.Camera{
                .position = .{ .x = 0, .y = 200, .z = 200 },
                .target = .{ .x = 0, .y = 0, .z = 0 },
                .up = .{ .x = 0, .y = 1, .z = 0 },
                .fovy = 45.0,
                .projection = .perspective,
            },
            .input_state = input.InputState{
                .action_camera = use_action_camera,
            },
            .ai_states = [_]AIState{
                .{}, // Player (no AI)
                .{ .role = .damage_dealer }, // Ally 1
                .{ .role = .damage_dealer }, // Ally 2
                .{ .role = .support }, // Ally Healer
                .{ .role = .damage_dealer }, // Enemy 1
                .{ .role = .damage_dealer }, // Enemy 2
                .{ .role = .damage_dealer }, // Enemy 3
                .{ .role = .support }, // Enemy Healer
            },
            .rng = prng,
            .combat_state = .active,
            .entity_id_gen = id_gen,
            .vfx_manager = vfx.VFXManager.init(),
            .terrain_grid = terrain_grid,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GameState) void {
        self.terrain_grid.deinit();
    }

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

    pub fn update(self: *GameState) void {
        const frame_time = rl.getFrameTime();

        // Poll input EVERY FRAME (60fps) to buffer all inputs
        // This prevents missing rapid inputs like Tab presses between ticks
        input.pollInput(&self.entities, &self.camera, &self.input_state);

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

    fn processTick(self: *GameState) void {
        // ALL game logic runs here at fixed 20Hz tick rate (50ms per tick)
        // This makes the game deterministic and multiplayer-ready

        // Save previous positions for interpolation BEFORE any movement this tick
        // Update energy, cooldowns, conditions, warmth for ALL entities (including player!)
        for (&self.entities) |*ent| {
            ent.previous_position = ent.position;
            ent.updateEnergy(TICK_RATE_SEC);
            ent.updateCooldowns(TICK_RATE_SEC);
            ent.updateConditions(TICK_RATE_MS);
            ent.updateWarmth(TICK_RATE_SEC); // Warmth regen/degen from pips
            ent.updateDamageMonitor(TICK_RATE_SEC); // Update damage monitor timers
        }

        // Handle input and AI (only if combat is active)
        var random_state = self.rng.random();
        if (self.combat_state == .active) {
            // Get player-controlled entity
            const player = self.getPlayer();

            // Get player movement intent from input
            const player_movement = input.handleInput(player, &self.entities, &self.selected_target, &self.camera, &self.input_state, &random_state, &self.vfx_manager, &self.terrain_grid);

            // Only apply movement if not casting (GW1 rule: can't move while casting)
            if (player.cast_state == .idle) {
                movement.applyMovement(player, player_movement, &self.entities, null, null, TICK_RATE_SEC, &self.terrain_grid);
            }

            // Update AI for non-player entities
            ai.updateAI(&self.entities, self.controlled_entity_id, TICK_RATE_SEC, &self.ai_states, &random_state, &self.vfx_manager, &self.terrain_grid);

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

        // Check if player is dead
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
            if (ent.is_enemy and ent.isAlive()) {
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

    fn finishCasts(self: *GameState, rng: *std.Random) void {
        // Check cast completions for ALL entities (including player!)
        for (&self.entities) |*ent| {
            if (ent.cast_state == .activating) {
                const skill = ent.skill_bar[ent.casting_skill_index] orelse continue;

                // Check for attack skills that execute at half activation
                const half_activation_time = @as(f32, @floatFromInt(skill.activation_time_ms)) / 2000.0;
                const total_activation_time = @as(f32, @floatFromInt(skill.activation_time_ms)) / 1000.0;

                // Execute attack skills at half activation time
                if (skill.mechanic.executesAtHalfActivation() and !ent.skill_executed) {
                    const time_elapsed = total_activation_time - ent.cast_time_remaining;
                    if (time_elapsed >= half_activation_time) {
                        self.executeSkillEffect(ent, skill, rng);
                        ent.skill_executed = true;
                    }
                }

                // Check if activation phase is complete
                if (ent.cast_time_remaining <= 0) {
                    // Execute non-attack skills at end of activation
                    if (!skill.mechanic.executesAtHalfActivation() and !ent.skill_executed) {
                        self.executeSkillEffect(ent, skill, rng);
                        ent.skill_executed = true;
                    }

                    // Transition to aftercast if skill has one
                    if (skill.mechanic.hasAftercast()) {
                        ent.cast_state = .aftercast;
                        ent.aftercast_time_remaining = @as(f32, @floatFromInt(skill.aftercast_ms)) / 1000.0;
                    } else {
                        ent.cast_state = .idle;
                    }

                    ent.cast_target_id = null;
                    ent.skill_executed = false;
                }
            }
        }
    }

    fn executeSkillEffect(self: *GameState, ent: *Character, skill: *const Skill, rng: *std.Random) void {
        var target: ?*Character = null;
        var target_valid = false;

        if (ent.cast_target_id) |target_id| {
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
            combat.executeSkill(ent, skill, target, ent.casting_skill_index, rng, &self.vfx_manager, &self.terrain_grid);
        }
    }

    pub fn draw(self: *GameState) void {
        // Calculate interpolation alpha for smooth rendering between ticks
        // alpha = 0.0 means just after a tick, alpha = 1.0 means about to tick
        const alpha = self.tick_accumulator / TICK_RATE_SEC;

        // Update camera to follow interpolated player position (smooth every frame!)
        const player = self.getPlayerConst();
        const player_render_pos = player.getInterpolatedPosition(alpha);
        input.updateCamera(&self.camera, player_render_pos, self.input_state);

        render.draw(player, &self.entities, self.selected_target, self.camera, alpha, &self.vfx_manager, &self.terrain_grid);
    }

    pub fn drawUI(self: *GameState) void {
        const player = self.getPlayerConst();
        ui.drawUI(player, &self.entities, self.selected_target, &self.input_state, self.camera);
    }
};
