const rl = @import("raylib");
const std = @import("std");
const print = std.debug.print;

const Entity = struct {
    position: rl.Vector3,
    radius: f32,
    color: rl.Color,
    name: [:0]const u8,
    health: f32,
    max_health: f32,
    is_enemy: bool,

    // Skill system components
    background: Background,
    player_position: Position,
    energy: u8,
    max_energy: u8,
    adrenaline: u8,
    max_adrenaline: u8,
    skill_bar: [8]?*Skill,
    selected_skill: u8 = 0,
};

const Background = enum {
    private_school,
    public_school,
    montessori,
    homeschool,
};

const Position = enum {
    pitcher,
    fielder,
    sledder,
    digger,
    runner,
    catcher,

    pub fn getSkills(self: Position) []const Skill {
        return switch (self) {
            .pitcher => &pitcher_skills,
            .fielder => &fielder_skills,
            .sledder => &sledder_skills,
            .digger => &digger_skills,
            .runner => &runner_skills,
            .catcher => &catcher_skills,
        };
    }
};

const Skill = struct {
    name: [:0]const u8,
};

// Pitcher skills
const pitcher_skills = [_]Skill{
    .{ .name = "Fastball" },
    .{ .name = "Curveball" },
    .{ .name = "Changeup" },
    .{ .name = "Slider" },
};

// Fielder skills
const fielder_skills = [_]Skill{
    .{ .name = "Catch" },
    .{ .name = "Throw" },
    .{ .name = "Dive" },
    .{ .name = "Scoop" },
};

// Sledder skills
const sledder_skills = [_]Skill{
    .{ .name = "Push" },
    .{ .name = "Brake" },
    .{ .name = "Drift" },
    .{ .name = "Boost" },
};

// Digger skills
const digger_skills = [_]Skill{
    .{ .name = "Dig" },
    .{ .name = "Excavate" },
    .{ .name = "Tunnel" },
    .{ .name = "Fortify" },
};

// Runner skills
const runner_skills = [_]Skill{
    .{ .name = "Sprint" },
    .{ .name = "Slide" },
    .{ .name = "Jump" },
    .{ .name = "Dash" },
};

// Catcher skills
const catcher_skills = [_]Skill{
    .{ .name = "Frame" },
    .{ .name = "Block" },
    .{ .name = "Throw Out" },
    .{ .name = "Signal" },
};

const GameState = struct {
    player: Entity,
    entities: []const Entity,
    selected_target: ?usize,
    camera: rl.Camera,
    shift_held: bool,
    camera_angle: f32,
    camera_distance: f32,

    // Skill system state
    delta_time: f32,

    fn init() GameState {
        // Initialize player with background and position
        const player_background = Background.private_school;
        const player_position = Position.pitcher;

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
            .energy = 20,
            .max_energy = 20,
            .adrenaline = 0,
            .max_adrenaline = 10,
            .skill_bar = [_]?*Skill{null} ** 8,
            .selected_skill = 0,
        };

        // Load skills from position into skill bar
        const position_skills = player_position.getSkills();
        const skill_count = @min(position_skills.len, player.skill_bar.len);

        for (0..skill_count) |i| {
            player.skill_bar[i] = @constCast(&position_skills[i]);
        }

        // Clear remaining slots
        for (skill_count..player.skill_bar.len) |i| {
            player.skill_bar[i] = null;
        }

        print("Player {s} initialized with background: {s}, position: {s}\n", .{ player.name, @tagName(player_background), @tagName(player_position) });
        print("Loaded {d} skills into skill bar\n", .{skill_count});

        return GameState{
            .player = player,
            .entities = &[_]Entity{
                Entity{
                    .position = .{ .x = -100, .y = 0, .z = -100 },
                    .radius = 18,
                    .color = .red,
                    .name = "Enemy Dummy",
                    .health = 50,
                    .max_health = 50,
                    .is_enemy = true,
                    // Skill components for enemies
                    .background = .public_school,
                    .player_position = .fielder,
                    .energy = 15,
                    .max_energy = 15,
                    .adrenaline = 0,
                    .max_adrenaline = 8,
                    .skill_bar = [_]?*Skill{null} ** 8,
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
                    .energy = 18,
                    .max_energy = 18,
                    .adrenaline = 0,
                    .max_adrenaline = 12,
                    .skill_bar = [_]?*Skill{null} ** 8,
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
                    .energy = 25,
                    .max_energy = 25,
                    .adrenaline = 0,
                    .max_adrenaline = 6,
                    .skill_bar = [_]?*Skill{null} ** 8,
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
                    .energy = 15,
                    .max_energy = 15,
                    .adrenaline = 0,
                    .max_adrenaline = 10,
                    .skill_bar = [_]?*Skill{null} ** 8,
                    .selected_skill = 0,
                },
            },
            .selected_target = null,
            .shift_held = false,
            .camera_angle = 0.0,
            .camera_distance = 250.0,
            .camera = rl.Camera{
                .position = .{ .x = 0, .y = 200, .z = 200 },
                .target = .{ .x = 0, .y = 0, .z = 0 },
                .up = .{ .x = 0, .y = 1, .z = 0 },
                .fovy = 45.0,
                .projection = .perspective,
            },
            .delta_time = 0.0,
        };
    }

    fn cycleTarget(self: *GameState, forward: bool) void {
        if (self.entities.len == 0) return;

        if (self.selected_target == null) {
            self.selected_target = 0;
            print("First target selected: 0\n", .{});
            return;
        }

        const current = self.selected_target.?;
        var next = current;

        if (forward) {
            next = (current + 1) % self.entities.len;
        } else {
            next = if (current == 0) self.entities.len - 1 else current - 1;
        }

        self.selected_target = next;

        // Print entity list and current selection
        print("=== ENTITY LIST ===\n", .{});
        for (self.entities, 0..) |entity, i| {
            const marker = if (i == self.selected_target) ">>> " else "    ";
            const type_str = if (entity.is_enemy) "ENEMY" else "ALLY";
            print("{s}[{d}] {s} - {s}\n", .{ marker, i, type_str, entity.name });
        }
        print("==================\n", .{});
    }

    fn getNearestEnemy(self: *GameState) ?usize {
        var nearest: ?usize = null;
        var min_dist: f32 = std.math.floatMax(f32);

        for (self.entities, 0..) |entity, i| {
            if (!entity.is_enemy) continue;

            const dx = entity.position.x - self.player.position.x;
            const dy = entity.position.y - self.player.position.y;
            const dz = entity.position.z - self.player.position.z;
            const dist = @sqrt(dx * dx + dy * dy + dz * dz);

            if (dist < min_dist) {
                min_dist = dist;
                nearest = i;
            }
        }

        return nearest;
    }

    fn getNearestAlly(self: *GameState) ?usize {
        var nearest: ?usize = null;
        var min_dist: f32 = std.math.floatMax(f32);

        for (self.entities, 0..) |entity, i| {
            if (entity.is_enemy) continue;

            const dx = entity.position.x - self.player.position.x;
            const dy = entity.position.y - self.player.position.y;
            const dz = entity.position.z - self.player.position.z;
            const dist = @sqrt(dx * dx + dy * dy + dz * dz);

            if (dist < min_dist) {
                min_dist = dist;
                nearest = i;
            }
        }

        return nearest;
    }

    fn useSkill(self: *GameState, skill_index: u8) void {
        if (skill_index >= self.player.skill_bar.len) return;

        if (self.player.skill_bar[skill_index]) |skill| {
            print("Using skill: {s}\n", .{skill.name});
        } else {
            print("No skill in slot {d}\n", .{skill_index});
        }
    }

    fn handleInput(self: *GameState) void {
        // Track Shift key state
        if (rl.isKeyPressed(.left_shift)) {
            self.shift_held = true;
        } else if (rl.isKeyReleased(.left_shift)) {
            self.shift_held = false;
        }

        // === SKILL USAGE ===
        // Face buttons for skills (1-4)
        if (rl.isGamepadAvailable(0)) {
            if (rl.isGamepadButtonPressed(0, .right_face_down)) { // A button
                self.useSkill(0);
            }
            if (rl.isGamepadButtonPressed(0, .right_face_right)) { // B button
                self.useSkill(1);
            }
            if (rl.isGamepadButtonPressed(0, .right_face_left)) { // X button
                self.useSkill(2);
            }
            if (rl.isGamepadButtonPressed(0, .right_face_up)) { // Y button
                self.useSkill(3);
            }

            // Shoulder buttons for skills 5-8
            if (rl.isGamepadButtonPressed(0, .right_trigger_1)) { // RB
                self.useSkill(4);
            }
            if (rl.isGamepadButtonPressed(0, .left_trigger_1)) { // LB
                self.useSkill(5);
            }
            // Could use trigger pulls for skills 6-7
        }

        // Keyboard skill usage (1-8 keys)
        if (rl.isKeyPressed(.one)) self.useSkill(0);
        if (rl.isKeyPressed(.two)) self.useSkill(1);
        if (rl.isKeyPressed(.three)) self.useSkill(2);
        if (rl.isKeyPressed(.four)) self.useSkill(3);
        if (rl.isKeyPressed(.five)) self.useSkill(4);
        if (rl.isKeyPressed(.six)) self.useSkill(5);
        if (rl.isKeyPressed(.seven)) self.useSkill(6);
        if (rl.isKeyPressed(.eight)) self.useSkill(7);

        // Skill selection (for UI/highlighting)
        if (rl.isKeyPressed(.q)) {
            self.player.selected_skill = (self.player.selected_skill + 7) % 8; // -1 wrap
        }
        if (rl.isKeyPressed(.e)) {
            self.player.selected_skill = (self.player.selected_skill + 1) % 8;
        }

        // === TARGET CYCLING ===
        // Gamepad shoulder buttons (first-class)
        var cycle_forward = false;
        var cycle_backward = false;

        if (rl.isGamepadAvailable(0)) {
            if (rl.isGamepadButtonPressed(0, .right_trigger_2)) cycle_forward = true;
            if (rl.isGamepadButtonPressed(0, .left_trigger_2)) cycle_backward = true;
        }

        // Keyboard Tab/Shift+Tab (secondary)
        if (rl.isKeyDown(.left_shift) and rl.isKeyPressed(.tab)) {
            cycle_backward = true;
        } else if (rl.isKeyPressed(.tab)) {
            cycle_forward = true;
        }

        if (cycle_backward) {
            print("Cycling backward\n", .{});
            self.cycleTarget(false);
        } else if (cycle_forward) {
            print("Cycling forward\n", .{});
            self.cycleTarget(true);
        }

        // === MOVEMENT SYSTEM ===
        // Gamepad is first-class: left stick controls movement
        const move_speed = 3.0;
        var move_x: f32 = 0.0;
        var move_z: f32 = 0.0;

        // Gamepad input (first-class)
        if (rl.isGamepadAvailable(0)) {
            const left_x = rl.getGamepadAxisMovement(0, .left_x);
            const left_y = rl.getGamepadAxisMovement(0, .left_y);

            // Apply deadzone
            const deadzone = 0.15;
            if (@abs(left_x) > deadzone) move_x = left_x;
            if (@abs(left_y) > deadzone) move_z = left_y;
        }

        // Keyboard input (WASD) - fallback/secondary
        if (rl.isKeyDown(.w)) move_z -= 1.0;
        if (rl.isKeyDown(.s)) move_z += 1.0;
        if (rl.isKeyDown(.a)) move_x -= 1.0;
        if (rl.isKeyDown(.d)) move_x += 1.0;

        // Apply movement relative to camera angle
        if (move_x != 0.0 or move_z != 0.0) {
            // Normalize diagonal movement
            const magnitude = @sqrt(move_x * move_x + move_z * move_z);
            const norm_x = move_x / magnitude;
            const norm_z = move_z / magnitude;

            // Rotate movement by camera angle
            // Camera looks from behind the player, so we rotate the input by the camera angle
            const cos_angle = @cos(self.camera_angle);
            const sin_angle = @sin(self.camera_angle);
            const rotated_x = norm_x * cos_angle + norm_z * sin_angle;
            const rotated_z = -norm_x * sin_angle + norm_z * cos_angle;

            self.player.position.x += rotated_x * move_speed;
            self.player.position.z += rotated_z * move_speed;
        }

        // === CAMERA SYSTEM ===
        // Gamepad right stick (first-class)
        var camera_rotation: f32 = 0.0;
        const camera_speed = 0.05;

        if (rl.isGamepadAvailable(0)) {
            const right_x = rl.getGamepadAxisMovement(0, .right_x);
            const deadzone = 0.15;
            if (@abs(right_x) > deadzone) {
                camera_rotation = right_x * camera_speed;
            }
        }

        // Mouse camera control (secondary)
        if (rl.isMouseButtonDown(.right)) {
            const mouse_delta = rl.getMouseDelta();
            camera_rotation = mouse_delta.x * 0.003;
        }

        // Apply camera rotation
        self.camera_angle += camera_rotation;

        // Update camera to follow player
        const cam_height: f32 = 200.0;
        const cam_x = self.player.position.x + @sin(self.camera_angle) * self.camera_distance;
        const cam_z = self.player.position.z + @cos(self.camera_angle) * self.camera_distance;

        self.camera.position = .{ .x = cam_x, .y = cam_height, .z = cam_z };
        self.camera.target = self.player.position;
    }

    fn draw(self: GameState) void {
        rl.clearBackground(.dark_gray);

        rl.beginMode3D(self.camera);
        defer rl.endMode3D();

        // Draw ground plane
        rl.drawGrid(20, 50);

        // Draw entities
        for (self.entities) |entity| {
            // Draw entity as sphere
            rl.drawSphere(entity.position, entity.radius, entity.color);
            rl.drawSphereWires(entity.position, entity.radius, 8, 8, .black);

            // Draw name above entity (convert 3D to 2D)
            const name_3d_pos = rl.Vector3{
                .x = entity.position.x,
                .y = entity.position.y + entity.radius + 10,
                .z = entity.position.z,
            };
            const name_2d_pos = rl.getWorldToScreen(name_3d_pos, self.camera);
            rl.drawText(entity.name, @intFromFloat(name_2d_pos.x), @intFromFloat(name_2d_pos.y), 10, .white);
        }

        // Draw player
        rl.drawSphere(self.player.position, self.player.radius, self.player.color);
        rl.drawSphereWires(self.player.position, self.player.radius, 8, 8, .black);

        // Draw player name
        const player_name_3d_pos = rl.Vector3{
            .x = self.player.position.x,
            .y = self.player.position.y + self.player.radius + 10,
            .z = self.player.position.z,
        };
        const player_name_2d_pos = rl.getWorldToScreen(player_name_3d_pos, self.camera);
        rl.drawText(self.player.name, @intFromFloat(player_name_2d_pos.x), @intFromFloat(player_name_2d_pos.y), 12, .white);

        // Draw target selection indicator
        if (self.selected_target) |target_index| {
            const target = self.entities[target_index];

            // Draw selection ring around target
            const ring_pos = rl.Vector3{
                .x = target.position.x,
                .y = target.position.y,
                .z = target.position.z,
            };
            rl.drawCylinder(ring_pos, target.radius + 5, target.radius + 5, 2, 16, .yellow);

            // Draw selection arrow above target
            const arrow_pos = rl.Vector3{
                .x = target.position.x,
                .y = target.position.y + target.radius + 15,
                .z = target.position.z,
            };
            rl.drawCube(arrow_pos, 5, 5, 5, .yellow);
        }
    }

    fn drawUI(self: GameState) void {
        // Debug info
        const shift_text = if (self.shift_held) "Shift Held: true" else "Shift Held: false";
        rl.drawText(shift_text, 10, 10, 16, .yellow);

        if (self.selected_target) |_| {
            rl.drawText("Target: some", 10, 30, 16, .sky_blue);
        } else {
            rl.drawText("Target: null", 10, 30, 16, .sky_blue);
        }

        // Draw controls help
        rl.drawText("Controls:", 10, 60, 20, .white);

        // Show gamepad controls if available
        if (rl.isGamepadAvailable(0)) {
            rl.drawText("Left Stick: Move", 10, 85, 16, .lime);
            rl.drawText("Right Stick: Rotate camera", 10, 105, 16, .lime);
            rl.drawText("Face Buttons: Use skills 1-4", 10, 125, 16, .lime);
            rl.drawText("Shoulders: Target cycle / skills 5-8", 10, 145, 16, .lime);
            rl.drawText("Q/E: Select skill", 10, 165, 16, .lime);
            rl.drawText("(Keyboard: 1-8 skills, Tab target, WASD move)", 10, 185, 14, .dark_gray);
        } else {
            rl.drawText("1-8: Use skills", 10, 85, 16, .light_gray);
            rl.drawText("Q/E: Select skill", 10, 105, 16, .light_gray);
            rl.drawText("Tab/Shift+Tab: Cycle targets", 10, 125, 16, .light_gray);
            rl.drawText("WASD: Move", 10, 145, 16, .light_gray);
            rl.drawText("Right Mouse: Rotate camera", 10, 165, 16, .light_gray);
        }

        rl.drawText("ESC: Exit", 10, 205, 16, .light_gray);

        // Draw current target info
        if (self.selected_target) |target_index| {
            const target = self.entities[target_index];
            rl.drawText("Current Target:", 10, 230, 18, .white);
            rl.drawText(target.name, 10, 250, 16, target.color);

            const target_type_text = if (target.is_enemy) "Enemy" else "Ally";
            rl.drawText(target_type_text, 10, 270, 14, .light_gray);

            var health_buf: [32]u8 = undefined;
            const health_text = std.fmt.bufPrintZ(
                &health_buf,
                "Health: {d:.0}/{d:.0}",
                .{ target.health, target.max_health },
            ) catch "Health: ???";
            rl.drawText(health_text, 10, 250, 14, .light_gray);
        }

        // Draw health bars in 2D overlay
        for (self.entities) |entity| {
            const health_percentage = entity.health / entity.max_health;
            const health_bar_width = 40;
            const health_bar_height = 4;

            // Convert 3D position to 2D screen coordinates
            const screen_pos = rl.getWorldToScreen(entity.position, self.camera);

            const health_bar_pos = rl.Rectangle{
                .x = screen_pos.x - health_bar_width / 2,
                .y = screen_pos.y - 30,
                .width = health_bar_width,
                .height = health_bar_height,
            };

            // Health bar background
            rl.drawRectangleRec(health_bar_pos, .black);

            // Health bar fill
            rl.drawRectangleRec(
                rl.Rectangle{
                    .x = health_bar_pos.x,
                    .y = health_bar_pos.y,
                    .width = health_bar_width * health_percentage,
                    .height = health_bar_height,
                },
                if (entity.is_enemy) .red else .green,
            );
        }

        // Draw skill bar
        drawSkillBar(self);
    }
};

fn drawSkillBar(game_state: GameState) void {
    const skill_bar_width = 400;
    const skill_bar_height = 50;
    const skill_size = 40;
    const skill_spacing = 5;
    const start_x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2.0 - @as(f32, @floatFromInt(skill_bar_width)) / 2.0;
    const start_y = @as(f32, @floatFromInt(rl.getScreenHeight())) - 80.0;

    // Draw skill bar background
    rl.drawRectangle(@intFromFloat(start_x - 5), @intFromFloat(start_y - 5), @intFromFloat(skill_bar_width + 10), @intFromFloat(skill_bar_height + 10), .black);

    for (game_state.player.skill_bar, 0..) |maybe_skill, i| {
        const skill_x = start_x + @as(f32, @floatFromInt(i)) * (skill_size + skill_spacing);
        const skill_y = start_y;

        // Draw skill slot
        const slot_color: rl.Color = if (i == game_state.player.selected_skill) .yellow else .dark_gray;
        rl.drawRectangleLines(@intFromFloat(skill_x), @intFromFloat(skill_y), @intFromFloat(skill_size), @intFromFloat(skill_size), slot_color);

        if (maybe_skill) |skill| {
            // Draw skill background
            const skill_color: rl.Color = .blue;
            rl.drawRectangle(@intFromFloat(skill_x + 2), @intFromFloat(skill_y + 2), @intFromFloat(skill_size - 4), @intFromFloat(skill_size - 4), skill_color);

            // Draw skill name
            rl.drawText(skill.name, @intFromFloat(skill_x + 2), @intFromFloat(skill_y + 2), 10, .white);
        } else {
            // Empty slot
            rl.drawRectangle(@intFromFloat(skill_x + 2), @intFromFloat(skill_y + 2), @intFromFloat(skill_size - 4), @intFromFloat(skill_size - 4), .dark_gray);
            var key_buf: [8]u8 = undefined;
            const key_text = std.fmt.bufPrintZ(&key_buf, "{d}", .{i + 1}) catch "?";
            rl.drawText(key_text, @intFromFloat(skill_x + 2), @intFromFloat(skill_y + 2), 10, .white);
        }
    }

    // Draw player resources
    const resource_y = start_y + skill_bar_height + 15;

    // Energy bar
    rl.drawText("Energy:", @intFromFloat(start_x), @intFromFloat(resource_y), 16, .white);
    rl.drawRectangle(@intFromFloat(start_x + 60), @intFromFloat(resource_y), 100, 16, .black);
    rl.drawRectangle(@intFromFloat(start_x + 60), @intFromFloat(resource_y), @intFromFloat(@as(f32, @floatFromInt(game_state.player.energy)) / @as(f32, @floatFromInt(game_state.player.max_energy)) * 100), 16, .blue);
    var energy_buf: [16]u8 = undefined;
    const energy_text = std.fmt.bufPrintZ(&energy_buf, "{d}/{d}", .{ game_state.player.energy, game_state.player.max_energy }) catch "?";
    rl.drawText(energy_text, @intFromFloat(start_x + 165), @intFromFloat(resource_y), 14, .white);

    // Adrenaline bar
    rl.drawText("Adr:", @intFromFloat(start_x + 220), @intFromFloat(resource_y), 16, .white);
    rl.drawRectangle(@intFromFloat(start_x + 260), @intFromFloat(resource_y), 100, 16, .black);
    rl.drawRectangle(@intFromFloat(start_x + 260), @intFromFloat(resource_y), @intFromFloat(@as(f32, @floatFromInt(game_state.player.adrenaline)) / @as(f32, @floatFromInt(game_state.player.max_adrenaline)) * 100), 16, .red);
    var adr_buf: [16]u8 = undefined;
    const adr_text = std.fmt.bufPrintZ(&adr_buf, "{d}/{d}", .{ game_state.player.adrenaline, game_state.player.max_adrenaline }) catch "?";
    rl.drawText(adr_text, @intFromFloat(start_x + 365), @intFromFloat(resource_y), 14, .white);

    // Draw background info
    const background_name = @tagName(game_state.player.background);
    rl.drawText(background_name, 10, @intFromFloat(resource_y + 25), 12, .light_gray);
}

pub fn main() anyerror!void {
    const screenWidth = 800;
    const screenHeight = 600;

    rl.initWindow(screenWidth, screenHeight, "Snow - GW1-Style 3D Tab Targeting");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    var game_state = GameState.init();

    while (!rl.windowShouldClose()) {
        game_state.delta_time = rl.getFrameTime();

        // Update skill cooldowns
        // TODO: implement skill cooldown updates

        game_state.handleInput();

        rl.beginDrawing();
        defer rl.endDrawing();

        game_state.draw();
        game_state.drawUI();
    }
}
