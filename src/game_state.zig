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

const print = std.debug.print;

// Type aliases
const Character = character.Character;
const School = school.School;
const Position = position.Position;
const Skill = character.Skill;
const AIState = ai.AIState;
const EntityId = entity.EntityId;
const EntityIdGenerator = entity.EntityIdGenerator;

// Game configuration constants
pub const MAX_ENTITIES: usize = 5; // Player + allies + enemies

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

    pub fn init() GameState {
        var id_gen = EntityIdGenerator{};

        // Setup positions for all entities
        const player_start_pos = rl.Vector3{ .x = 0, .y = 0, .z = 0 };
        const ally_pos = rl.Vector3{ .x = 60, .y = 0, .z = 20 };
        const enemy1_pos = rl.Vector3{ .x = -80, .y = 0, .z = -120 };
        const enemy2_pos = rl.Vector3{ .x = 80, .y = 0, .z = -120 };
        const empty_pos = rl.Vector3{ .x = 0, .y = 0, .z = 0 };

        // Create entities array with player at index 0
        // In multiplayer: "controlled_entity_id" determines which one is "yours"
        var entities = [_]Character{
            // Index 0: Player (Waldorf Animator)
            Character{
                .id = id_gen.generate(),
                .position = player_start_pos,
                .previous_position = player_start_pos,
                .radius = 20,
                .color = .blue,
                .name = "Player",
                .warmth = 100,
                .max_warmth = 100,
                .is_enemy = false,
                .school = .waldorf,
                .player_position = .animator,
                .energy = School.waldorf.getMaxEnergy(),
                .max_energy = School.waldorf.getMaxEnergy(),
                .skill_bar = [_]?*const Skill{null} ** character.MAX_SKILLS,
                .selected_skill = 0,
            },
            // Index 1: Ally (Waldorf Thermos - Support/Healer)
            Character{
                .id = id_gen.generate(),
                .position = ally_pos,
                .previous_position = ally_pos,
                .radius = 18,
                .color = .green,
                .name = "Ally Healer",
                .warmth = 100,
                .max_warmth = 100,
                .is_enemy = false,
                .school = .waldorf,
                .player_position = .thermos,
                .energy = School.waldorf.getMaxEnergy(),
                .max_energy = School.waldorf.getMaxEnergy(),
                .skill_bar = [_]?*const Skill{null} ** character.MAX_SKILLS,
                .selected_skill = 0,
            },
            // Index 2: Enemy 1 (Public School Pitcher - Pure Damage)
            Character{
                .id = id_gen.generate(),
                .position = enemy1_pos,
                .previous_position = enemy1_pos,
                .radius = 18,
                .color = .red,
                .name = "Enemy Ranger",
                .warmth = 100,
                .max_warmth = 100,
                .is_enemy = true,
                .school = .public_school,
                .player_position = .pitcher,
                .energy = School.public_school.getMaxEnergy(),
                .max_energy = School.public_school.getMaxEnergy(),
                .skill_bar = [_]?*const Skill{null} ** character.MAX_SKILLS,
                .selected_skill = 0,
            },
            // Index 3: Enemy 2 (Homeschool Animator - Burst Damage + Disruption)
            Character{
                .id = id_gen.generate(),
                .position = enemy2_pos,
                .previous_position = enemy2_pos,
                .radius = 18,
                .color = .red,
                .name = "Enemy Caster",
                .warmth = 100,
                .max_warmth = 100,
                .is_enemy = true,
                .school = .homeschool,
                .player_position = .animator,
                .energy = School.homeschool.getMaxEnergy(),
                .max_energy = School.homeschool.getMaxEnergy(),
                .skill_bar = [_]?*const Skill{null} ** character.MAX_SKILLS,
                .selected_skill = 0,
            },
            // Index 4: Empty slot
            Character{
                .id = id_gen.generate(),
                .position = empty_pos,
                .previous_position = empty_pos,
                .radius = 0,
                .color = .black,
                .name = "Empty",
                .warmth = 0,
                .max_warmth = 1,
                .is_enemy = false,
                .is_dead = true,
                .school = .waldorf,
                .player_position = .animator,
                .energy = 0,
                .max_energy = 1,
                .skill_bar = [_]?*const Skill{null} ** character.MAX_SKILLS,
                .selected_skill = 0,
            },
        };

        // Store player's entity ID
        const player_entity_id = entities[0].id;

        // Load skills from position definitions for all entities
        for (&entities, 0..) |*ent, i| {
            if (i >= 4) break; // Skip empty slot (index 4)
            const ent_skills = ent.player_position.getSkills();
            const ent_skill_count = @min(ent_skills.len, character.MAX_SKILLS);
            for (0..ent_skill_count) |skill_idx| {
                ent.skill_bar[skill_idx] = &ent_skills[skill_idx];
            }
            print("Loaded {d} skills for {s} ({s}/{s})\n", .{
                ent_skill_count,
                ent.name,
                @tagName(ent.school),
                @tagName(ent.player_position),
            });
        }

        // Initialize RNG with current time as seed
        const timestamp = std.time.timestamp();
        const seed: u64 = @bitCast(timestamp); // Convert i64 to u64 safely
        const rng = std.Random.DefaultPrng.init(seed);

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

        return GameState{
            .entities = entities,
            .controlled_entity_id = player_entity_id, // Track which entity is "ours"
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
                .{ .role = .support }, // Ally Thermos - healer/support
                .{ .role = .damage_dealer }, // Enemy Pitcher - ranged DPS
                .{ .role = .disruptor }, // Enemy Animator - burst/control
                .{}, // Empty slot
            },
            .rng = rng,
            .combat_state = .active,
            .entity_id_gen = id_gen,
        };
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
        // Update energy, cooldowns, conditions for ALL entities (including player!)
        for (&self.entities) |*ent| {
            ent.previous_position = ent.position;
            ent.updateEnergy(TICK_RATE_SEC);
            ent.updateCooldowns(TICK_RATE_SEC);
            ent.updateConditions(TICK_RATE_MS);
        }

        // Handle input and AI (only if combat is active)
        var random_state = self.rng.random();
        if (self.combat_state == .active) {
            // Get player-controlled entity
            const player = self.getPlayer();

            // Get player movement intent from input and apply it
            const player_movement = input.handleInput(player, &self.entities, &self.selected_target, &self.camera, &self.input_state, &random_state);
            movement.applyMovement(player, player_movement, &self.entities, null, null, TICK_RATE_SEC);

            // Update AI for non-player entities
            ai.updateAI(&self.entities, self.controlled_entity_id, TICK_RATE_SEC, &self.ai_states, &random_state);

            // Finish any completed casts
            self.finishCasts(&random_state);

            // Check for victory/defeat
            self.checkCombatStatus();
        }
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
            if (ent.is_casting and ent.cast_time_remaining <= 0) {
                const skill = ent.skill_bar[ent.casting_skill_index];
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
                } else if (skill.?.target_type == .self) {
                    target_valid = true;
                }

                if (target_valid) {
                    combat.executeSkill(ent, skill.?, target, ent.casting_skill_index, rng);
                }
                ent.cast_target_id = null;
            }
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

        render.draw(player, &self.entities, self.selected_target, self.camera, alpha);
    }

    pub fn drawUI(self: *const GameState) void {
        const player = self.getPlayerConst();
        ui.drawUI(player, &self.entities, self.selected_target, self.input_state, self.camera);
    }
};
