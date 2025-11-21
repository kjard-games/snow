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

const print = std.debug.print;

// Type aliases
const Character = character.Character;
const School = school.School;
const Position = position.Position;
const Skill = character.Skill;
const AIState = ai.AIState;

// Special index value to represent player as target (player is not in entities array)
pub const PLAYER_TARGET_INDEX: usize = std.math.maxInt(usize);

// Game configuration constants
pub const MAX_ENTITIES: usize = 4;

pub const CombatState = enum {
    active,
    victory,
    defeat,
};

pub const GameState = struct {
    player: Character,
    entities: [MAX_ENTITIES]Character,
    selected_target: ?usize,
    camera: rl.Camera,
    delta_time: f32,
    input_state: input.InputState,
    ai_states: [MAX_ENTITIES]AIState,
    rng: std.Random.DefaultPrng,
    combat_state: CombatState,

    pub fn init() GameState {
        // Initialize player with school and position
        const player_school = School.waldorf;
        const player_position = Position.animator;

        var player = Character{
            .position = .{ .x = 0, .y = 0, .z = 0 },
            .radius = 20,
            .color = .blue,
            .name = "Player",
            .warmth = 100,
            .max_warmth = 100,
            .is_enemy = false,

            // Skill system components
            .school = player_school,
            .player_position = player_position,
            .energy = player_school.getMaxEnergy(),
            .max_energy = player_school.getMaxEnergy(),
            .skill_bar = [_]?*const Skill{null} ** character.MAX_SKILLS,
            .selected_skill = 0,
        };

        // Load skills from position into skill bar
        const position_skills = player_position.getSkills();
        const skill_count = @min(position_skills.len, character.MAX_SKILLS);

        for (0..skill_count) |i| {
            player.skill_bar[i] = &position_skills[i];
        }

        print("Player {s} initialized with school: {s}, position: {s}\n", .{ player.name, @tagName(player_school), @tagName(player_position) });
        print("Loaded {d} skills into skill bar\n", .{skill_count});

        const entities = [_]Character{
            Character{
                .position = .{ .x = -100, .y = 0, .z = -100 },
                .radius = 18,
                .color = .red,
                .name = "Enemy Dummy",
                .warmth = 50,
                .max_warmth = 50,
                .is_enemy = true,
                .school = .public_school,
                .player_position = .fielder,
                .energy = School.public_school.getMaxEnergy(),
                .max_energy = School.public_school.getMaxEnergy(),
                .skill_bar = [_]?*const Skill{null} ** character.MAX_SKILLS,
                .selected_skill = 0,
            },
            Character{
                .position = .{ .x = 100, .y = 0, .z = -100 },
                .radius = 18,
                .color = .green,
                .name = "Friendly Dummy",
                .warmth = 50,
                .max_warmth = 50,
                .is_enemy = false,
                .school = .montessori,
                .player_position = .thermos,
                .energy = School.montessori.getMaxEnergy(),
                .max_energy = School.montessori.getMaxEnergy(),
                .skill_bar = [_]?*const Skill{null} ** character.MAX_SKILLS,
                .selected_skill = 0,
            },
            Character{
                .position = .{ .x = 0, .y = 0, .z = -150 },
                .radius = 18,
                .color = .red,
                .name = "Enemy Dummy 2",
                .warmth = 50,
                .max_warmth = 50,
                .is_enemy = true,
                .school = .homeschool,
                .player_position = .shoveler,
                .energy = School.homeschool.getMaxEnergy(),
                .max_energy = School.homeschool.getMaxEnergy(),
                .skill_bar = [_]?*const Skill{null} ** character.MAX_SKILLS,
                .selected_skill = 0,
            },
            Character{
                .position = .{ .x = 150, .y = 0, .z = -100 },
                .radius = 18,
                .color = .red,
                .name = "Enemy Dummy 3",
                .warmth = 50,
                .max_warmth = 50,
                .is_enemy = true,
                .school = .public_school,
                .player_position = .pitcher,
                .energy = School.public_school.getMaxEnergy(),
                .max_energy = School.public_school.getMaxEnergy(),
                .skill_bar = [_]?*const Skill{null} ** character.MAX_SKILLS,
                .selected_skill = 0,
            },
        };

        // Initialize RNG with current time as seed
        const rng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));

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
            .player = player,
            .entities = entities,
            .selected_target = null,
            .camera = rl.Camera{
                .position = .{ .x = 0, .y = 200, .z = 200 },
                .target = .{ .x = 0, .y = 0, .z = 0 },
                .up = .{ .x = 0, .y = 1, .z = 0 },
                .fovy = 45.0,
                .projection = .perspective,
            },
            .delta_time = 0.0,
            .input_state = input.InputState{
                .action_camera = use_action_camera,
            },
            .ai_states = [_]AIState{.{}} ** MAX_ENTITIES,
            .rng = rng,
            .combat_state = .active,
        };
    }

    pub fn update(self: *GameState) void {
        self.delta_time = rl.getFrameTime();
        const delta_time_ms = @as(u32, @intFromFloat(self.delta_time * 1000.0));

        // Update energy regeneration for all entities
        self.player.updateEnergy(self.delta_time);
        self.player.updateCooldowns(self.delta_time);
        self.player.updateConditions(delta_time_ms);

        for (&self.entities) |*ent| {
            ent.updateEnergy(self.delta_time);
            ent.updateCooldowns(self.delta_time);
            ent.updateConditions(delta_time_ms);
        }

        // Handle input and AI with RNG (only if combat is active)
        var random_state = self.rng.random();
        if (self.combat_state == .active) {
            input.handleInput(&self.player, &self.entities, &self.selected_target, &self.camera, &self.input_state, &random_state);
            ai.updateAI(&self.entities, &self.player, self.delta_time, &self.ai_states, &random_state);

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
        if (!self.player.isAlive()) {
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

        // Check player cast completion
        if (self.player.is_casting and self.player.cast_time_remaining <= 0) {
            const skill = self.player.skill_bar[self.player.casting_skill_index];
            var target: ?*Character = null;
            var target_valid = false;

            if (self.player.cast_target_index) |idx| {
                if (idx < self.entities.len) {
                    target = &self.entities[idx];
                    // Check if target is still alive
                    if (target.?.isAlive()) {
                        target_valid = true;
                    } else {
                        print("{s}'s target died during cast!\n", .{self.player.name});
                    }
                }
            } else if (skill.?.target_type == .self) {
                // Self-targeted skills always succeed
                target_valid = true;
            }

            if (target_valid) {
                combat.executeSkill(&self.player, skill.?, target, self.player.casting_skill_index, rng);
            }
            self.player.cast_target_index = null;
        }

        // Check entity cast completions
        for (&self.entities) |*ent| {
            if (ent.is_casting and ent.cast_time_remaining <= 0) {
                const skill = ent.skill_bar[ent.casting_skill_index];
                var target: ?*Character = null;
                var target_valid = false;

                // Entity might be targeting player (index would be out of bounds)
                if (ent.cast_target_index) |idx| {
                    if (idx == PLAYER_TARGET_INDEX) {
                        target = &self.player;
                        if (target.?.isAlive()) {
                            target_valid = true;
                        } else {
                            print("{s}'s target died during cast!\n", .{ent.name});
                        }
                    } else if (idx < self.entities.len) {
                        target = &self.entities[idx];
                        if (target.?.isAlive()) {
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
                ent.cast_target_index = null;
            }
        }
    }

    pub fn draw(self: *const GameState) void {
        render.draw(&self.player, &self.entities, self.selected_target, self.camera);
    }

    pub fn drawUI(self: *const GameState) void {
        ui.drawUI(&self.player, &self.entities, self.selected_target, self.input_state, self.camera);
    }
};
