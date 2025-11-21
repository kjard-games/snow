const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const targeting = @import("targeting.zig");
const combat = @import("combat.zig");
const movement = @import("movement.zig");
const entity_types = @import("entity.zig");

const Character = character.Character;
const Skill = character.Skill;
const MovementIntent = movement.MovementIntent;
const EntityId = entity_types.EntityId;
const print = std.debug.print;

pub const InputState = struct {
    shift_held: bool = false,
    camera_angle: f32 = 0.0,
    camera_pitch: f32 = 0.6, // Pitch angle in radians (0.6 ≈ 34 degrees, good default)
    camera_distance: f32 = 250.0,
    autorun: bool = false,
    move_target: ?rl.Vector3 = null, // Click-to-move destination
    last_click_time: f32 = 0.0, // For double-click detection
    last_click_target: ?EntityId = null, // For double-click on enemies
    action_camera: bool = false, // GW2 Action Camera mode
};

// Input Command - Represents player input for ONE tick
// In multiplayer, this is the data sent from client → server
// Server validates and applies this at a specific tick number
pub const InputCommand = struct {
    // Movement intent (WASD + facing direction)
    movement: MovementIntent,

    // Skill usage (which skill button was pressed)
    skill_use: ?u8 = null, // null = no skill, 0-7 = skill index

    // Target selection (tab-targeting)
    target_id: ?EntityId = null,

    // Tick number (for client-side prediction / server reconciliation)
    // In single-player, this isn't strictly needed, but shows the intent
    tick: u64 = 0,
};

pub fn handleInput(
    player: *Character,
    entities: []Character,
    selected_target: *?EntityId,
    camera: *rl.Camera,
    input_state: *InputState,
    rng: *std.Random,
) MovementIntent {
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
            useSkill(player, entities, selected_target.*, 0, rng);
        }
        if (rl.isGamepadButtonPressed(0, .right_face_right)) { // B button
            useSkill(player, entities, selected_target.*, 1, rng);
        }
        if (rl.isGamepadButtonPressed(0, .right_face_left)) { // X button
            useSkill(player, entities, selected_target.*, 2, rng);
        }
        if (rl.isGamepadButtonPressed(0, .right_face_up)) { // Y button
            useSkill(player, entities, selected_target.*, 3, rng);
        }

        // Shoulder buttons for skills 5-8
        if (rl.isGamepadButtonPressed(0, .right_trigger_1)) { // RB
            useSkill(player, entities, selected_target.*, 4, rng);
        }
        if (rl.isGamepadButtonPressed(0, .left_trigger_1)) { // LB
            useSkill(player, entities, selected_target.*, 5, rng);
        }
        // Could use trigger pulls for skills 6-7
    }

    // Keyboard skill usage (1-8 keys)
    if (rl.isKeyPressed(.one)) useSkill(player, entities, selected_target.*, 0, rng);
    if (rl.isKeyPressed(.two)) useSkill(player, entities, selected_target.*, 1, rng);
    if (rl.isKeyPressed(.three)) useSkill(player, entities, selected_target.*, 2, rng);
    if (rl.isKeyPressed(.four)) useSkill(player, entities, selected_target.*, 3, rng);
    if (rl.isKeyPressed(.five)) useSkill(player, entities, selected_target.*, 4, rng);
    if (rl.isKeyPressed(.six)) useSkill(player, entities, selected_target.*, 5, rng);
    if (rl.isKeyPressed(.seven)) useSkill(player, entities, selected_target.*, 6, rng);
    if (rl.isKeyPressed(.eight)) useSkill(player, entities, selected_target.*, 7, rng);

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
    // R key = Toggle autorun
    if (rl.isKeyPressed(.r)) {
        input_state.autorun = !input_state.autorun;
        print("Autorun: {}\n", .{input_state.autorun});
    }

    // X key = Quick 180° turn (panic button)
    if (rl.isKeyPressed(.x)) {
        input_state.camera_angle += std.math.pi; // 180 degrees
        print("Quick turn 180°\n", .{});
    }

    // Gather movement input
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

        // Any stick movement cancels autorun
        if (move_x != 0.0 or move_z != 0.0) {
            input_state.autorun = false;
        }
    }

    // Keyboard input (WASD) - fallback/secondary
    var has_keyboard_input = false;
    if (rl.isKeyDown(.w)) {
        move_z -= 1.0;
        has_keyboard_input = true;
    }
    if (rl.isKeyDown(.s)) {
        move_z += 1.0;
        has_keyboard_input = true;
        input_state.autorun = false; // Backward cancels autorun
    }
    if (rl.isKeyDown(.a)) {
        move_x -= 1.0;
        has_keyboard_input = true;
    }
    if (rl.isKeyDown(.d)) {
        move_x += 1.0;
        has_keyboard_input = true;
    }

    // Autorun = forward movement
    if (input_state.autorun and !has_keyboard_input) {
        move_z -= 1.0;
    }

    // === CLICK-TO-MOVE ===
    // Check if we should use click-to-move instead
    if (input_state.move_target) |target| {
        const dx = target.x - player.position.x;
        const dz = target.z - player.position.z;
        const distance = @sqrt(dx * dx + dz * dz);

        // Stop when close enough (within 2 units)
        if (distance < 2.0) {
            input_state.move_target = null;
            print("Reached click target\n", .{});
        } else {
            // Move toward target (only if no manual input occurred)
            if (move_x == 0.0 and move_z == 0.0 and !has_keyboard_input) {
                // Calculate world-space movement direction
                // Then convert to local space for MovementIntent
                const move_dir_x = dx / distance;
                const move_dir_z = dz / distance;

                // Convert world movement to local space (inverse of camera rotation)
                const cos_angle = @cos(input_state.camera_angle);
                const sin_angle = @sin(input_state.camera_angle);
                move_x = move_dir_x * cos_angle - move_dir_z * sin_angle;
                move_z = move_dir_x * sin_angle + move_dir_z * cos_angle;
            } else {
                // Manual input cancels click-to-move
                input_state.move_target = null;
                print("Click-to-move cancelled by manual input\n", .{});
            }
        }
    }

    // === CLICK-TO-TARGET & CLICK-TO-MOVE SYSTEM ===
    // Left click for targeting entities or moving
    // In Action Camera: left-click still works for targeting/movement
    if (rl.isMouseButtonPressed(.left)) {
        const mouse_pos = rl.getMousePosition();
        const ray = rl.getScreenToWorldRay(mouse_pos, camera.*);

        // First, check if we clicked on an entity
        var clicked_entity: ?EntityId = null;
        var closest_distance: f32 = std.math.inf(f32);

        for (entities, 0..) |entity, i| {
            // Skip the player
            if (i == 0) continue;

            // Ray-sphere intersection test
            const to_sphere = rl.Vector3{
                .x = entity.position.x - ray.position.x,
                .y = entity.position.y - ray.position.y,
                .z = entity.position.z - ray.position.z,
            };

            const t_ca = to_sphere.x * ray.direction.x + to_sphere.y * ray.direction.y + to_sphere.z * ray.direction.z;
            if (t_ca < 0.0) continue; // Sphere is behind ray

            const d_squared = (to_sphere.x * to_sphere.x + to_sphere.y * to_sphere.y + to_sphere.z * to_sphere.z) - (t_ca * t_ca);
            const radius_squared = entity.radius * entity.radius;

            if (d_squared <= radius_squared) {
                const t_hc = @sqrt(radius_squared - d_squared);
                const t = t_ca - t_hc;

                if (t < closest_distance) {
                    closest_distance = t;
                    clicked_entity = entity.id; // Use EntityId instead of array index
                }
            }
        }

        // Check for double-click on same target
        const current_time = @as(f32, @floatCast(rl.getTime()));
        const is_double_click = if (clicked_entity) |ce| blk: {
            if (input_state.last_click_target) |lct| {
                break :blk (current_time - input_state.last_click_time) < 0.3 and ce == lct;
            }
            break :blk false;
        } else false;

        if (clicked_entity) |entity_id| {
            // Clicked on an entity - target it
            selected_target.* = entity_id;
            print("Targeted entity ID {d}\n", .{entity_id});

            if (is_double_click) {
                // Double-click: move to range and attack
                // Find entity by ID to get position
                for (entities) |e| {
                    if (e.id == entity_id) {
                        input_state.move_target = e.position;
                        print("Double-click: move to target and attack\n", .{});
                        break;
                    }
                }
            }

            input_state.last_click_target = entity_id;
        } else {
            // Clicked on terrain - click-to-move
            // Raycast to ground plane (y = 0)
            if (ray.direction.y != 0.0) {
                const t = -ray.position.y / ray.direction.y;
                if (t > 0.0) {
                    const hit_point = rl.Vector3{
                        .x = ray.position.x + ray.direction.x * t,
                        .y = 0.0,
                        .z = ray.position.z + ray.direction.z * t,
                    };

                    input_state.move_target = hit_point;
                    input_state.autorun = false;
                    print("Click-to-move target: ({d:.1}, {d:.1})\n", .{ hit_point.x, hit_point.z });
                }
            }

            input_state.last_click_target = null;
        }

        input_state.last_click_time = current_time;
    }

    // === CAMERA SYSTEM ===
    // Toggle Action Camera mode with C key or gamepad L3 (left stick click)
    var toggle_action_camera = false;
    if (rl.isKeyPressed(.c)) {
        toggle_action_camera = true;
    }
    if (rl.isGamepadAvailable(0) and rl.isGamepadButtonPressed(0, .left_thumb)) {
        toggle_action_camera = true;
    }

    if (toggle_action_camera) {
        input_state.action_camera = !input_state.action_camera;
        if (input_state.action_camera) {
            rl.disableCursor();
            print("Action Camera: ON (mouse-look active)\n", .{});
        } else {
            rl.enableCursor();
            print("Action Camera: OFF\n", .{});
        }
    }

    // Camera rotation and pitch
    var camera_rotation: f32 = 0.0;
    var camera_pitch_delta: f32 = 0.0;
    const camera_speed = 0.05;

    // Gamepad right stick (first-class)
    if (rl.isGamepadAvailable(0)) {
        const right_x = rl.getGamepadAxisMovement(0, .right_x);
        const right_y = rl.getGamepadAxisMovement(0, .right_y);
        const deadzone = 0.15;

        if (@abs(right_x) > deadzone) {
            camera_rotation = right_x * camera_speed;
        }
        if (@abs(right_y) > deadzone) {
            camera_pitch_delta = -right_y * camera_speed; // Inverted Y
        }
    }

    // Mouse camera control
    if (input_state.action_camera) {
        // Action Camera: Always mouse-look (like GW2)
        const mouse_delta = rl.getMouseDelta();
        camera_rotation = mouse_delta.x * 0.003;
        camera_pitch_delta = -mouse_delta.y * 0.003; // Inverted Y
    } else if (rl.isMouseButtonDown(.right)) {
        // Traditional: Right-click to mouse-look
        const mouse_delta = rl.getMouseDelta();
        camera_rotation = mouse_delta.x * 0.003;
        camera_pitch_delta = -mouse_delta.y * 0.003; // Inverted Y
    }

    // Mouse wheel zoom
    const wheel = rl.getMouseWheelMove();
    if (wheel != 0.0) {
        input_state.camera_distance -= wheel * 20.0;
        // Clamp zoom distance
        input_state.camera_distance = @max(50.0, @min(400.0, input_state.camera_distance));
    }

    // Apply camera rotation
    input_state.camera_angle += camera_rotation;

    // Apply camera pitch with limits
    input_state.camera_pitch += camera_pitch_delta;
    // Clamp pitch: 0.1 (nearly horizontal) to 1.4 (nearly straight down)
    input_state.camera_pitch = @max(0.1, @min(1.4, input_state.camera_pitch));

    // NOTE: Camera position is now updated every frame in updateCamera()
    // using interpolated player position for smooth visuals

    // Return movement intent for movement system to process
    return MovementIntent{
        .local_x = move_x,
        .local_z = move_z,
        .facing_angle = input_state.camera_angle,
        .apply_penalties = true,
    };
}

fn useSkill(player: *Character, entities: []Character, selected_target: ?EntityId, skill_index: u8, rng: *std.Random) void {
    if (skill_index >= player.skill_bar.len) return;

    if (player.skill_bar[skill_index] == null) {
        print("No skill in slot {d}\n", .{skill_index});
        return;
    }

    // Get target entity by ID
    var target: ?*Character = null;
    if (selected_target) |target_id| {
        // Check if targeting player
        if (player.id == target_id) {
            target = player;
        } else {
            // Search entities array
            for (entities) |*entity| {
                if (entity.id == target_id) {
                    target = entity;
                    break;
                }
            }
        }
    }

    _ = combat.tryStartCast(player, skill_index, target, selected_target, rng);
}

// Update camera to follow player (called every frame for smooth interpolation)
pub fn updateCamera(camera: *rl.Camera, player_pos: rl.Vector3, input_state: InputState) void {
    // Update camera to follow player with pitch
    // Use spherical coordinates: distance, angle (yaw), pitch
    const horizontal_distance = input_state.camera_distance * @cos(input_state.camera_pitch);
    const cam_height = player_pos.y + input_state.camera_distance * @sin(input_state.camera_pitch);

    const cam_x = player_pos.x + @sin(input_state.camera_angle) * horizontal_distance;
    const cam_z = player_pos.z + @cos(input_state.camera_angle) * horizontal_distance;

    camera.position = .{ .x = cam_x, .y = cam_height, .z = cam_z };

    // Offset camera target up and slightly to the side for over-shoulder view
    // This prevents the reticle from aiming through the player character
    const target_offset_y: f32 = 50.0; // Height offset (up)
    const target_offset_x: f32 = 20.0; // Shoulder offset (right)

    camera.target = .{
        .x = player_pos.x + target_offset_x,
        .y = player_pos.y + target_offset_y,
        .z = player_pos.z,
    };
}
