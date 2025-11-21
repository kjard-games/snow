const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const school = @import("school.zig");
const position = @import("position.zig");
const input = @import("input.zig");
const render = @import("render.zig");
const ui = @import("ui.zig");
const ai = @import("ai.zig");

const Character = character.Character;
const School = school.School;
const Position = position.Position;
const Skill = character.Skill;
const AIState = ai.AIState;
const print = std.debug.print;

pub const GameState = struct {
    player: Character,
    entities: [4]Character,
    selected_target: ?usize,
    camera: rl.Camera,
    delta_time: f32,
    input_state: input.InputState,
    ai_states: [4]AIState,

    pub fn init() GameState {
        // Initialize player with school and position
        const player_school = School.waldorf;
        const player_position = Position.summoner;

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
            .skill_bar = [_]?*const Skill{null} ** 8,
            .selected_skill = 0,
        };

        // Load skills from position into skill bar
        const position_skills = player_position.getSkills();
        const skill_count = @min(position_skills.len, player.skill_bar.len);

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
                .skill_bar = [_]?*const Skill{null} ** 8,
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
                .player_position = .skater,
                .energy = School.montessori.getMaxEnergy(),
                .max_energy = School.montessori.getMaxEnergy(),
                .skill_bar = [_]?*const Skill{null} ** 8,
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
                .skill_bar = [_]?*const Skill{null} ** 8,
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
                .skill_bar = [_]?*const Skill{null} ** 8,
                .selected_skill = 0,
            },
        };

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
            .input_state = .{},
            .ai_states = [_]AIState{.{}} ** 4,
        };
    }

    pub fn update(self: *GameState) void {
        self.delta_time = rl.getFrameTime();

        // Update energy regeneration for all entities
        self.player.updateEnergy(self.delta_time);
        for (&self.entities) |*ent| {
            ent.updateEnergy(self.delta_time);
        }

        // Update AI
        ai.updateAI(&self.entities, self.player, self.delta_time, &self.ai_states);

        // Handle input
        input.handleInput(&self.player, &self.entities, &self.selected_target, &self.camera, &self.input_state);
    }

    pub fn draw(self: GameState) void {
        render.draw(self.player, &self.entities, self.selected_target, self.camera);
    }

    pub fn drawUI(self: GameState) void {
        ui.drawUI(self.player, &self.entities, self.selected_target, self.input_state, self.camera);
    }
};
