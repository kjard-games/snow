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
};

const GameState = struct {
    player: Entity,
    entities: []const Entity,
    selected_target: ?usize,
    camera: rl.Camera,
    shift_held: bool,
    camera_angle: f32,
    camera_distance: f32,

    fn init() GameState {
        return GameState{
            .player = Entity{
                .position = .{ .x = 0, .y = 0, .z = 0 },
                .radius = 20,
                .color = .blue,
                .name = "Player",
                .health = 100,
                .max_health = 100,
                .is_enemy = false,
            },
            .entities = &[_]Entity{
                Entity{
                    .position = .{ .x = -100, .y = 0, .z = -100 },
                    .radius = 18,
                    .color = .red,
                    .name = "Enemy Dummy",
                    .health = 50,
                    .max_health = 50,
                    .is_enemy = true,
                },
                Entity{
                    .position = .{ .x = 100, .y = 0, .z = -100 },
                    .radius = 18,
                    .color = .green,
                    .name = "Friendly Dummy",
                    .health = 50,
                    .max_health = 50,
                    .is_enemy = false,
                },
                Entity{
                    .position = .{ .x = 0, .y = 0, .z = -150 },
                    .radius = 18,
                    .color = .red,
                    .name = "Enemy Dummy 2",
                    .health = 50,
                    .max_health = 50,
                    .is_enemy = true,
                },
                Entity{
                    .position = .{ .x = 150, .y = 0, .z = -100 },
                    .radius = 18,
                    .color = .red,
                    .name = "Enemy Dummy 3",
                    .health = 50,
                    .max_health = 50,
                    .is_enemy = true,
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

    fn handleInput(self: *GameState) void {
        // Track Shift key state
        if (rl.isKeyPressed(.left_shift)) {
            self.shift_held = true;
        } else if (rl.isKeyReleased(.left_shift)) {
            self.shift_held = false;
        }

        // === TARGET CYCLING ===
        // Gamepad shoulder buttons (first-class)
        var cycle_forward = false;
        var cycle_backward = false;

        if (rl.isGamepadAvailable(0)) {
            if (rl.isGamepadButtonPressed(0, .right_trigger_1)) cycle_forward = true;
            if (rl.isGamepadButtonPressed(0, .left_trigger_1)) cycle_backward = true;
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
            rl.drawText("RB/LB: Cycle targets", 10, 125, 16, .lime);
            rl.drawText("(Keyboard: WASD/Mouse/Tab)", 10, 145, 14, .dark_gray);
        } else {
            rl.drawText("Left Stick: Move", 10, 85, 16, .dark_gray);
            rl.drawText("Right Stick: Rotate camera", 10, 105, 16, .dark_gray);
            rl.drawText("RB/LB: Cycle targets", 10, 125, 16, .dark_gray);
            rl.drawText("WASD: Move", 10, 145, 16, .light_gray);
            rl.drawText("Right Mouse: Rotate camera", 10, 165, 16, .light_gray);
            rl.drawText("Tab/Shift+Tab: Cycle targets", 10, 185, 16, .light_gray);
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

        // Draw player health bar
        const player_health_percentage = self.player.health / self.player.max_health;
        const player_health_bar_width = 50;
        const player_health_bar_height = 6;

        const player_screen_pos = rl.getWorldToScreen(self.player.position, self.camera);

        const player_health_bar_pos = rl.Rectangle{
            .x = player_screen_pos.x - player_health_bar_width / 2,
            .y = player_screen_pos.y - 35,
            .width = player_health_bar_width,
            .height = player_health_bar_height,
        };

        rl.drawRectangleRec(player_health_bar_pos, .black);
        rl.drawRectangleRec(
            rl.Rectangle{
                .x = player_health_bar_pos.x,
                .y = player_health_bar_pos.y,
                .width = player_health_bar_width * player_health_percentage,
                .height = player_health_bar_height,
            },
            .blue,
        );
    }
};

pub fn main() anyerror!void {
    const screenWidth = 800;
    const screenHeight = 600;

    rl.initWindow(screenWidth, screenHeight, "Snow - GW1-Style 3D Tab Targeting");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    var game_state = GameState.init();

    while (!rl.windowShouldClose()) {
        game_state.handleInput();

        rl.beginDrawing();
        defer rl.endDrawing();

        game_state.draw();
        game_state.drawUI();
    }
}
