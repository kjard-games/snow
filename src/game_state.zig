const std = @import("std");
const rl = @import("raylib");
const entity = @import("entity.zig");
const background = @import("background.zig");
const position = @import("position.zig");
const input = @import("input.zig");
const render = @import("render.zig");
const ui = @import("ui.zig");

const Entity = entity.Entity;
const Background = background.Background;
const Position = position.Position;
const Skill = entity.Skill;
const print = std.debug.print;

pub const GameState = struct {
    player: Entity,
    entities: [4]Entity,
    selected_target: ?usize,
    camera: rl.Camera,
    delta_time: f32,
    input_state: input.InputState,

    pub fn init() GameState {
        // Initialize player with background and position
        const player_background = Background.waldorf;
        const player_position = Position.waldorf;

        var player = Entity{
            .position = .{ .x = 0, .y = 0, .z = 0 },
            .radius = 20,
            .color = .blue,
            .name = "Player",
            .health = 100,
            .max_health = 100,
            .is_enemy = false,

            // Skill system components
            .background = player_background,
            .player_position = player_position,
            .energy = player_background.getMaxEnergy(),
            .max_energy = player_background.getMaxEnergy(),
            .skill_bar = [_]?*const Skill{null} ** 8,
            .selected_skill = 0,
        };

        // Load skills from position into skill bar
        const position_skills = player_position.getSkills();
        const skill_count = @min(position_skills.len, player.skill_bar.len);

        for (0..skill_count) |i| {
            player.skill_bar[i] = &position_skills[i];
        }

        print("Player {s} initialized with background: {s}, position: {s}\n", .{ player.name, @tagName(player_background), @tagName(player_position) });
        print("Loaded {d} skills into skill bar\n", .{skill_count});

        const entities = [_]Entity{
            Entity{
                .position = .{ .x = -100, .y = 0, .z = -100 },
                .radius = 18,
                .color = .red,
                .name = "Enemy Dummy",
                .health = 50,
                .max_health = 50,
                .is_enemy = true,
                .background = .public_school,
                .player_position = .fielder,
                .energy = Background.public_school.getMaxEnergy(),
                .max_energy = Background.public_school.getMaxEnergy(),
                .skill_bar = [_]?*const Skill{null} ** 8,
                .selected_skill = 0,
            },
            Entity{
                .position = .{ .x = 100, .y = 0, .z = -100 },
                .radius = 18,
                .color = .green,
                .name = "Friendly Dummy",
                .health = 50,
                .max_health = 50,
                .is_enemy = false,
                .background = .montessori,
                .player_position = .runner,
                .energy = Background.montessori.getMaxEnergy(),
                .max_energy = Background.montessori.getMaxEnergy(),
                .skill_bar = [_]?*const Skill{null} ** 8,
                .selected_skill = 0,
            },
            Entity{
                .position = .{ .x = 0, .y = 0, .z = -150 },
                .radius = 18,
                .color = .red,
                .name = "Enemy Dummy 2",
                .health = 50,
                .max_health = 50,
                .is_enemy = true,
                .background = .homeschool,
                .player_position = .digger,
                .energy = Background.homeschool.getMaxEnergy(),
                .max_energy = Background.homeschool.getMaxEnergy(),
                .skill_bar = [_]?*const Skill{null} ** 8,
                .selected_skill = 0,
            },
            Entity{
                .position = .{ .x = 150, .y = 0, .z = -100 },
                .radius = 18,
                .color = .red,
                .name = "Enemy Dummy 3",
                .health = 50,
                .max_health = 50,
                .is_enemy = true,
                .background = .public_school,
                .player_position = .pitcher,
                .energy = Background.public_school.getMaxEnergy(),
                .max_energy = Background.public_school.getMaxEnergy(),
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
        };
    }

    pub fn update(self: *GameState) void {
        self.delta_time = rl.getFrameTime();

        // Update energy regeneration
        self.player.updateEnergy(self.delta_time);

        // Handle input
        input.handleInput(&self.player, &self.entities, &self.selected_target, &self.camera, &self.input_state);
    }

    pub fn draw(self: GameState) void {
        render.draw(self.player, &self.entities, self.selected_target, self.camera);
    }

    pub fn drawUI(self: GameState) void {
        ui.drawUI(self.player, &self.entities, self.selected_target, self.input_state.shift_held, self.camera);
    }
};
