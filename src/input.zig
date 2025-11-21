const std = @import("std");
const rl = @import("raylib");
const entity = @import("entity.zig");
const targeting = @import("targeting.zig");

const Entity = entity.Entity;
const Skill = entity.Skill;
const print = std.debug.print;

pub const InputState = struct {
    shift_held: bool = false,
    camera_angle: f32 = 0.0,
    camera_distance: f32 = 250.0,
};

pub fn handleInput(
    player: *Entity,
    entities: []const Entity,
    selected_target: *?usize,
    camera: *rl.Camera,
    input_state: *InputState,
) void {
    // Track Shift key state
    if (rl.isKeyPressed(.left_shift)) {
        input_state.shift_held = true;
    } else if (rl.isKeyReleased(.left_shift)) {
        input_state.shift_held = false;
    }

    // === SKILL USAGE ===
    // Face buttons for skills (1-4)
    if (rl.isGamepadAvailable(0)) {
        if (rl.isGamepadButtonPressed(0, .right_face_down)) { // A button
            useSkill(player, 0);
        }
        if (rl.isGamepadButtonPressed(0, .right_face_right)) { // B button
            useSkill(player, 1);
        }
        if (rl.isGamepadButtonPressed(0, .right_face_left)) { // X button
            useSkill(player, 2);
        }
        if (rl.isGamepadButtonPressed(0, .right_face_up)) { // Y button
            useSkill(player, 3);
        }

        // Shoulder buttons for skills 5-8
        if (rl.isGamepadButtonPressed(0, .right_trigger_1)) { // RB
            useSkill(player, 4);
        }
        if (rl.isGamepadButtonPressed(0, .left_trigger_1)) { // LB
            useSkill(player, 5);
        }
        // Could use trigger pulls for skills 6-7
    }

    // Keyboard skill usage (1-8 keys)
    if (rl.isKeyPressed(.one)) useSkill(player, 0);
    if (rl.isKeyPressed(.two)) useSkill(player, 1);
    if (rl.isKeyPressed(.three)) useSkill(player, 2);
    if (rl.isKeyPressed(.four)) useSkill(player, 3);
    if (rl.isKeyPressed(.five)) useSkill(player, 4);
    if (rl.isKeyPressed(.six)) useSkill(player, 5);
    if (rl.isKeyPressed(.seven)) useSkill(player, 6);
    if (rl.isKeyPressed(.eight)) useSkill(player, 7);

    // Skill selection (for UI/highlighting)
    if (rl.isKeyPressed(.q)) {
        player.selected_skill = (player.selected_skill + 7) % 8; // -1 wrap
    }
    if (rl.isKeyPressed(.e)) {
        player.selected_skill = (player.selected_skill + 1) % 8;
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
        selected_target.* = targeting.cycleTarget(entities, selected_target.*, false);
    } else if (cycle_forward) {
        print("Cycling forward\n", .{});
        selected_target.* = targeting.cycleTarget(entities, selected_target.*, true);
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
        const cos_angle = @cos(input_state.camera_angle);
        const sin_angle = @sin(input_state.camera_angle);
        const rotated_x = norm_x * cos_angle + norm_z * sin_angle;
        const rotated_z = -norm_x * sin_angle + norm_z * cos_angle;

        player.position.x += rotated_x * move_speed;
        player.position.z += rotated_z * move_speed;
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
    input_state.camera_angle += camera_rotation;

    // Update camera to follow player
    const cam_height: f32 = 200.0;
    const cam_x = player.position.x + @sin(input_state.camera_angle) * input_state.camera_distance;
    const cam_z = player.position.z + @cos(input_state.camera_angle) * input_state.camera_distance;

    camera.position = .{ .x = cam_x, .y = cam_height, .z = cam_z };
    camera.target = player.position;
}

fn useSkill(player: *Entity, skill_index: u8) void {
    if (skill_index >= player.skill_bar.len) return;

    if (player.skill_bar[skill_index]) |skill| {
        print("Using skill: {s}\n", .{skill.name});
        // TODO: Check energy cost and consume
        // TODO: Apply background-specific effects
    } else {
        print("No skill in slot {d}\n", .{skill_index});
    }
}
