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

// Camera constants
pub const DEFAULT_CAMERA_PITCH: f32 = 0.6; // ~34 degrees, good default viewing angle
pub const DEFAULT_CAMERA_DISTANCE: f32 = 250.0;
pub const MIN_CAMERA_PITCH: f32 = 0.1; // Nearly horizontal
pub const MAX_CAMERA_PITCH: f32 = 1.4; // Nearly straight down
pub const MIN_CAMERA_DISTANCE: f32 = 50.0;
pub const MAX_CAMERA_DISTANCE: f32 = 400.0;
pub const CAMERA_ZOOM_SPEED: f32 = 20.0; // Units per mouse wheel increment

// Input sensitivity constants
pub const MOUSE_SENSITIVITY: f32 = 0.003; // Radians per pixel
pub const GAMEPAD_CAMERA_SPEED: f32 = 0.05; // Radians per frame with gamepad
pub const GAMEPAD_DEADZONE_MOVEMENT: f32 = 0.15; // Deadzone for movement sticks
pub const GAMEPAD_DEADZONE_MENU: f32 = 0.3; // Higher deadzone for menu navigation

pub const InputState = struct {
    shift_held: bool = false,
    camera_angle: f32 = 0.0,
    camera_pitch: f32 = DEFAULT_CAMERA_PITCH,
    camera_distance: f32 = DEFAULT_CAMERA_DISTANCE,
    autorun: bool = false,
    move_target: ?rl.Vector3 = null, // Click-to-move destination
    last_click_time: f32 = 0.0, // For double-click detection
    last_click_target: ?EntityId = null, // For double-click on enemies
    action_camera: bool = false, // GW2 Action Camera mode

    // Input buffering (sampled every frame at 60fps, consumed every tick at 20Hz)
    // This prevents missing inputs that happen between ticks
    buffered_tab_forward: bool = false,
    buffered_tab_backward: bool = false,
    buffered_ally_forward: bool = false,
    buffered_ally_backward: bool = false,
    buffered_self_target: bool = false,
    buffered_nearest_enemy: bool = false,
    buffered_nearest_ally: bool = false,
    buffered_lowest_health_ally: bool = false,
    buffered_click_entity: ?EntityId = null,
    buffered_click_terrain: ?rl.Vector3 = null,
    buffered_skills: [8]bool = [_]bool{false} ** 8, // Skill buttons 1-8
    buffered_spacebar: bool = false, // Auto-attack toggle

    // Cancel-by-movement safeguards
    prev_stick_magnitude: f32 = 0.0, // Track previous frame's stick position

    // Skill tooltip state (updated every frame)
    hovered_skill_index: ?u8 = null, // Mouse hover detection
    inspected_skill_index: ?u8 = null, // Controller inspection (Q/E to cycle)
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

// pollInput - Called EVERY FRAME (60fps) to capture all inputs
// Buffers inputs for consumption by handleInput() at tick rate (20Hz)
pub fn pollInput(
    entities: []const Character,
    camera: *const rl.Camera,
    input_state: *InputState,
) void {
    // === TAB TARGETING (buffered) ===
    // Multiple targeting modes for different situations
    var cycle_enemies_forward = false;
    var cycle_enemies_backward = false;
    var cycle_allies_forward = false;
    var cycle_allies_backward = false;
    var target_self = false;
    var target_nearest_enemy = false;
    var target_nearest_ally = false;
    var target_lowest_health_ally = false;

    // Keyboard targeting
    const ctrl_held = rl.isKeyDown(.left_control) or rl.isKeyDown(.right_control);
    const shift_held = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);

    if (rl.isKeyPressed(.tab)) {
        if (ctrl_held and shift_held) {
            cycle_allies_backward = true; // CTRL+SHIFT+TAB
        } else if (ctrl_held) {
            cycle_allies_forward = true; // CTRL+TAB
        } else if (shift_held) {
            cycle_enemies_backward = true; // SHIFT+TAB
        } else {
            cycle_enemies_forward = true; // TAB (default)
        }
    }

    // T = target nearest enemy (common MMO binding)
    if (rl.isKeyPressed(.t)) {
        target_nearest_enemy = true;
    }

    // Y = target nearest ally
    if (rl.isKeyPressed(.y)) {
        target_nearest_ally = true;
    }

    // H = target lowest health ally (H for "heal")
    if (rl.isKeyPressed(.h)) {
        target_lowest_health_ally = true;
    }

    // F1 = self-target (common MMO binding)
    if (rl.isKeyPressed(.f1)) {
        target_self = true;
    }

    // Gamepad targeting
    if (rl.isGamepadAvailable(0)) {
        const l1_held = rl.isGamepadButtonDown(0, .left_trigger_1);
        const r1_held = rl.isGamepadButtonDown(0, .right_trigger_1);

        // R2/L2 = Enemy targeting (default)
        if (rl.isGamepadButtonPressed(0, .right_trigger_2)) {
            if (l1_held) {
                cycle_allies_forward = true; // L1+R2
            } else {
                cycle_enemies_forward = true; // R2
            }
        }

        if (rl.isGamepadButtonPressed(0, .left_trigger_2)) {
            if (l1_held) {
                cycle_allies_backward = true; // L1+L2
            } else {
                cycle_enemies_backward = true; // L2
            }
        }

        // D-pad Up = self-target (quick self-cast)
        if (rl.isGamepadButtonPressed(0, .left_face_up)) {
            target_self = true;
        }

        // D-pad Left/Right = quick targeting
        if (rl.isGamepadButtonPressed(0, .left_face_right)) {
            if (r1_held) {
                target_nearest_enemy = true; // R1+D-Right = nearest enemy
            } else {
                cycle_allies_forward = true; // D-Right = cycle allies forward
            }
        }
        if (rl.isGamepadButtonPressed(0, .left_face_left)) {
            if (r1_held) {
                target_nearest_ally = true; // R1+D-Left = nearest ally
            } else {
                cycle_allies_backward = true; // D-Left = cycle allies backward
            }
        }

        // R1+D-Down = target lowest health ally
        if (r1_held and rl.isGamepadButtonPressed(0, .left_face_down)) {
            target_lowest_health_ally = true;
        }
    }

    // Buffer the targeting commands
    if (cycle_enemies_forward) input_state.buffered_tab_forward = true;
    if (cycle_enemies_backward) input_state.buffered_tab_backward = true;
    if (target_nearest_enemy) input_state.buffered_nearest_enemy = true;
    if (target_nearest_ally) input_state.buffered_nearest_ally = true;
    if (target_lowest_health_ally) input_state.buffered_lowest_health_ally = true;

    // Store ally cycling and self-target in input state
    input_state.buffered_ally_forward = cycle_allies_forward;
    input_state.buffered_ally_backward = cycle_allies_backward;
    input_state.buffered_self_target = target_self;

    // === SKILL BUTTON PRESSES (buffered) ===
    // Pattern: Face buttons (ABXY) = Skills 1-4, L1 + Face buttons = Skills 5-8
    if (rl.isGamepadAvailable(0)) {
        const l1_held = rl.isGamepadButtonDown(0, .left_trigger_1);

        if (l1_held) {
            // L1 + Face buttons = Skills 5-8
            if (rl.isGamepadButtonPressed(0, .right_face_down)) input_state.buffered_skills[4] = true;
            if (rl.isGamepadButtonPressed(0, .right_face_right)) input_state.buffered_skills[5] = true;
            if (rl.isGamepadButtonPressed(0, .right_face_left)) input_state.buffered_skills[6] = true;
            if (rl.isGamepadButtonPressed(0, .right_face_up)) input_state.buffered_skills[7] = true;
        } else {
            // Face buttons alone = Skills 1-4
            if (rl.isGamepadButtonPressed(0, .right_face_down)) input_state.buffered_skills[0] = true;
            if (rl.isGamepadButtonPressed(0, .right_face_right)) input_state.buffered_skills[1] = true;
            if (rl.isGamepadButtonPressed(0, .right_face_left)) input_state.buffered_skills[2] = true;
            if (rl.isGamepadButtonPressed(0, .right_face_up)) input_state.buffered_skills[3] = true;
        }
    }

    if (rl.isKeyPressed(.one)) input_state.buffered_skills[0] = true;
    if (rl.isKeyPressed(.two)) input_state.buffered_skills[1] = true;
    if (rl.isKeyPressed(.three)) input_state.buffered_skills[2] = true;
    if (rl.isKeyPressed(.four)) input_state.buffered_skills[3] = true;
    if (rl.isKeyPressed(.five)) input_state.buffered_skills[4] = true;
    if (rl.isKeyPressed(.six)) input_state.buffered_skills[5] = true;
    if (rl.isKeyPressed(.seven)) input_state.buffered_skills[6] = true;
    if (rl.isKeyPressed(.eight)) input_state.buffered_skills[7] = true;

    // === AUTO-ATTACK TOGGLE (buffered) ===
    // Gamepad: R1 (right bumper) - feels natural as primary attack button
    if (rl.isGamepadAvailable(0)) {
        if (rl.isGamepadButtonPressed(0, .right_trigger_1)) input_state.buffered_spacebar = true;
    }

    // Keyboard: Spacebar
    if (rl.isKeyPressed(.space)) input_state.buffered_spacebar = true;

    // === SKILL TOOLTIP INSPECTION ===
    // Controller: D-pad Down to enter inspection mode (starts at skill 1), then Right Stick Left/Right to navigate
    // Keyboard: [ and ] to cycle through skill tooltips
    if (rl.isGamepadAvailable(0)) {
        // D-pad Down: Toggle inspection mode (enters at skill 1, or exits if already inspecting)
        if (rl.isGamepadButtonPressed(0, .left_face_down)) {
            if (input_state.inspected_skill_index) |_| {
                // Already inspecting - exit inspection mode
                input_state.inspected_skill_index = null;
            } else {
                // Enter inspection mode - start at skill 1
                input_state.inspected_skill_index = 0;
            }
        }

        // Right stick left/right: Navigate through skills when in inspection mode
        if (input_state.inspected_skill_index) |idx| {
            const right_x = rl.getGamepadAxisMovement(0, .right_x);
            const deadzone = GAMEPAD_DEADZONE_MENU; // Higher deadzone for discrete navigation

            // Track if we've already moved (prevent rapid cycling)
            const stick_neutral = @abs(right_x) < deadzone;

            // Use a static to track previous frame's stick state
            const prev_neutral = blk: {
                const State = struct {
                    var was_neutral: bool = true;
                };
                const result = State.was_neutral;
                State.was_neutral = stick_neutral;
                break :blk result;
            };

            // Only cycle when stick crosses threshold (was neutral, now active)
            if (prev_neutral and !stick_neutral) {
                if (right_x < -deadzone) {
                    // Left: Previous skill
                    if (idx > 0) {
                        input_state.inspected_skill_index = idx - 1;
                    } else {
                        input_state.inspected_skill_index = 7; // Wrap to skill 8
                    }
                } else if (right_x > deadzone) {
                    // Right: Next skill
                    if (idx < 7) {
                        input_state.inspected_skill_index = idx + 1;
                    } else {
                        input_state.inspected_skill_index = 0; // Wrap to skill 1
                    }
                }
            }
        }
    }

    // Keyboard: [ and ] to cycle through skill tooltips
    if (rl.isKeyPressed(.left_bracket)) {
        // [ = cycle backward
        if (input_state.inspected_skill_index) |idx| {
            if (idx > 0) {
                input_state.inspected_skill_index = idx - 1;
            } else {
                input_state.inspected_skill_index = 7; // Wrap to skill 8
            }
        } else {
            input_state.inspected_skill_index = 0; // Enter inspection at skill 1
        }
    }

    if (rl.isKeyPressed(.right_bracket)) {
        // ] = cycle forward
        if (input_state.inspected_skill_index) |idx| {
            if (idx < 7) {
                input_state.inspected_skill_index = idx + 1;
            } else {
                input_state.inspected_skill_index = 0; // Wrap to skill 1
            }
        } else {
            input_state.inspected_skill_index = 0; // Enter inspection at skill 1
        }
    }

    // === CAMERA SYSTEM (every frame for smooth camera movement) ===
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

    // Camera rotation and pitch (processed every frame!)
    var camera_rotation: f32 = 0.0;
    var camera_pitch_delta: f32 = 0.0;

    // Gamepad right stick (first-class)
    if (rl.isGamepadAvailable(0)) {
        const right_x = rl.getGamepadAxisMovement(0, .right_x);
        const right_y = rl.getGamepadAxisMovement(0, .right_y);

        if (@abs(right_x) > GAMEPAD_DEADZONE_MOVEMENT) {
            camera_rotation = right_x * GAMEPAD_CAMERA_SPEED;
        }
        if (@abs(right_y) > GAMEPAD_DEADZONE_MOVEMENT) {
            camera_pitch_delta = -right_y * GAMEPAD_CAMERA_SPEED; // Inverted Y
        }
    }

    // Mouse camera control
    if (input_state.action_camera) {
        // Action Camera: Always mouse-look (like GW2)
        const mouse_delta = rl.getMouseDelta();
        camera_rotation = mouse_delta.x * MOUSE_SENSITIVITY;
        camera_pitch_delta = -mouse_delta.y * MOUSE_SENSITIVITY; // Inverted Y
    } else if (rl.isMouseButtonDown(.right)) {
        // Traditional: Right-click to mouse-look
        const mouse_delta = rl.getMouseDelta();
        camera_rotation = mouse_delta.x * MOUSE_SENSITIVITY;
        camera_pitch_delta = -mouse_delta.y * MOUSE_SENSITIVITY; // Inverted Y
    }

    // Mouse wheel zoom
    const wheel = rl.getMouseWheelMove();
    if (wheel != 0.0) {
        input_state.camera_distance -= wheel * CAMERA_ZOOM_SPEED;
        // Clamp zoom distance
        input_state.camera_distance = @max(MIN_CAMERA_DISTANCE, @min(MAX_CAMERA_DISTANCE, input_state.camera_distance));
    }

    // Apply camera rotation and pitch (every frame!)
    input_state.camera_angle += camera_rotation;
    input_state.camera_pitch += camera_pitch_delta;
    // Clamp pitch
    input_state.camera_pitch = @max(MIN_CAMERA_PITCH, @min(MAX_CAMERA_PITCH, input_state.camera_pitch));

    // === CLICK-TO-TARGET & CLICK-TO-MOVE (buffered) ===
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
                    clicked_entity = entity.id;
                }
            }
        }

        if (clicked_entity) |entity_id| {
            // Clicked on an entity - buffer it
            input_state.buffered_click_entity = entity_id;
        } else {
            // Clicked on terrain - buffer click-to-move
            if (ray.direction.y != 0.0) {
                const t = -ray.position.y / ray.direction.y;
                if (t > 0.0) {
                    const hit_point = rl.Vector3{
                        .x = ray.position.x + ray.direction.x * t,
                        .y = 0.0,
                        .z = ray.position.z + ray.direction.z * t,
                    };
                    input_state.buffered_click_terrain = hit_point;
                }
            }
        }
    }
}

// handleInput - Called EVERY TICK (20Hz) to process game logic
// Consumes buffered inputs and applies them to game state
pub fn handleInput(
    player: *Character,
    entities: []Character,
    selected_target: *?EntityId,
    camera: *rl.Camera,
    input_state: *InputState,
    rng: *std.Random,
    vfx_manager: *@import("vfx.zig").VFXManager,
    terrain_grid: *@import("terrain.zig").TerrainGrid,
) MovementIntent {
    // Track Shift key state
    if (rl.isKeyPressed(.left_shift)) {
        input_state.shift_held = true;
    } else if (rl.isKeyReleased(.left_shift)) {
        input_state.shift_held = false;
    }

    // === CANCEL CASTING ===
    // GW1-accurate: Press ESC (or gamepad B button) to cancel current cast
    var cancel_pressed = false;

    if (rl.isKeyPressed(.escape)) {
        cancel_pressed = true;
    }

    // Gamepad B button (right_face_down) also cancels - feels natural
    if (rl.isGamepadAvailable(0) and rl.isGamepadButtonPressed(0, .right_face_down)) {
        cancel_pressed = true;
    }

    if (cancel_pressed and player.canCancelCast()) {
        print("{s} cancelled cast!\n", .{player.name});
        player.cancelCasting();
    }

    // === SKILL USAGE (from buffered inputs) ===
    for (input_state.buffered_skills, 0..) |pressed, i| {
        if (pressed) {
            useSkill(player, entities, selected_target.*, @intCast(i), rng, vfx_manager, terrain_grid, input_state, camera);
            input_state.buffered_skills[i] = false; // Consume the input
        }
    }

    // === AUTO-ATTACK TOGGLE (from buffered inputs) ===
    if (input_state.buffered_spacebar) {
        if (player.is_auto_attacking) {
            player.stopAutoAttack();
            print("Auto-attack: OFF\n", .{});
        } else if (selected_target.*) |target_id| {
            player.startAutoAttack(target_id);
            print("Auto-attack: ON (target ID {d})\n", .{target_id});
        } else {
            print("No target selected for auto-attack\n", .{});
        }
        input_state.buffered_spacebar = false; // Consume the input
    }

    // Skill selection (for UI/highlighting)
    if (rl.isKeyPressed(.q)) {
        player.selected_skill = (player.selected_skill + 7) % 8; // -1 wrap
    }
    if (rl.isKeyPressed(.e)) {
        player.selected_skill = (player.selected_skill + 1) % 8;
    }

    // === TARGET CYCLING (from buffered inputs) ===
    // Enemy targeting
    if (input_state.buffered_tab_backward) {
        selected_target.* = targeting.cycleEnemies(player.*, entities, selected_target.*, false);
        input_state.buffered_tab_backward = false;
    } else if (input_state.buffered_tab_forward) {
        selected_target.* = targeting.cycleEnemies(player.*, entities, selected_target.*, true);
        input_state.buffered_tab_forward = false;
    }

    // Ally targeting
    if (input_state.buffered_ally_backward) {
        selected_target.* = targeting.cycleAllies(player.*, entities, selected_target.*, false);
        input_state.buffered_ally_backward = false;
    } else if (input_state.buffered_ally_forward) {
        selected_target.* = targeting.cycleAllies(player.*, entities, selected_target.*, true);
        input_state.buffered_ally_forward = false;
    }

    // Quick targeting modes
    if (input_state.buffered_nearest_enemy) {
        selected_target.* = targeting.getNearestEnemy(player.*, entities);
        input_state.buffered_nearest_enemy = false;
    }

    if (input_state.buffered_nearest_ally) {
        selected_target.* = targeting.getNearestAlly(player.*, entities);
        input_state.buffered_nearest_ally = false;
    }

    if (input_state.buffered_lowest_health_ally) {
        selected_target.* = targeting.getLowestHealthAlly(player.*, entities);
        input_state.buffered_lowest_health_ally = false;
    }

    // Self-target
    if (input_state.buffered_self_target) {
        selected_target.* = player.id;
        print("Target: {s} (self)\n", .{player.name});
        input_state.buffered_self_target = false;
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

        // Calculate stick magnitude
        const stick_magnitude = @sqrt(left_x * left_x + left_y * left_y);

        // Apply deadzone
        const deadzone = 0.15;
        if (@abs(left_x) > deadzone) move_x = left_x;
        if (@abs(left_y) > deadzone) move_z = left_y;

        // Any stick movement cancels autorun
        if (move_x != 0.0 or move_z != 0.0) {
            input_state.autorun = false;

            // GW1-accurate: Movement cancels casting
            // BUT: Require DELIBERATE movement - a strong push or new movement
            // This prevents accidental cancels from small stick drift or adjustments
            if (player.canCancelCast()) {
                const cancel_threshold = 0.5; // Require 50% stick push to cancel

                // Cancel if: strong push OR fresh movement (from near-zero to active)
                const is_strong_push = stick_magnitude > cancel_threshold;
                const is_fresh_movement = input_state.prev_stick_magnitude < deadzone and stick_magnitude > cancel_threshold;

                if (is_strong_push or is_fresh_movement) {
                    print("{s} cancelled cast by moving!\n", .{player.name});
                    player.cancelCasting();
                }
            }
        }

        // Track stick position for next frame
        input_state.prev_stick_magnitude = stick_magnitude;
    }

    // Keyboard input (WASD) - fallback/secondary
    var has_keyboard_input = false;

    // Check for movement key PRESSES (not just held) to cancel casting
    const movement_key_pressed = rl.isKeyPressed(.w) or rl.isKeyPressed(.s) or
        rl.isKeyPressed(.a) or rl.isKeyPressed(.d);

    if (movement_key_pressed and player.canCancelCast()) {
        print("{s} cancelled cast by moving!\n", .{player.name});
        player.cancelCasting();
    }

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

    // === AUTO-ATTACK CHASE ===
    // If auto-attacking and out of range, move towards target automatically
    // BUT: Don't move if casting (would cancel the cast!)
    var auto_chase_active = false;
    if (player.is_auto_attacking and player.auto_attack_target_id != null and !player.isCasting()) {
        const target_id = player.auto_attack_target_id.?;

        // Find the target entity
        for (entities) |*ent| {
            if (ent.id == target_id) {
                if (ent.isAlive()) {
                    const distance = player.distanceTo(ent.*);
                    const attack_range = player.getAutoAttackRange();

                    // If out of range and no manual input, chase
                    if (distance > attack_range and move_x == 0.0 and move_z == 0.0 and !has_keyboard_input) {
                        const dx = ent.position.x - player.position.x;
                        const dz = ent.position.z - player.position.z;

                        // Calculate world-space movement direction
                        const move_dir_x = dx / distance;
                        const move_dir_z = dz / distance;

                        // Convert world movement to local space (inverse of camera rotation)
                        const cos_angle = @cos(input_state.camera_angle);
                        const sin_angle = @sin(input_state.camera_angle);
                        move_x = move_dir_x * cos_angle - move_dir_z * sin_angle;
                        move_z = move_dir_x * sin_angle + move_dir_z * cos_angle;

                        auto_chase_active = true;
                    }
                }
                break;
            }
        }
    }

    // === SKILL QUEUE APPROACH (GW1-style: run into range to cast) ===
    // If we have a queued skill and we're out of range, approach the target
    var skill_approach_active = false;
    skill_queue_block: {
        if (!auto_chase_active and player.hasQueuedSkill() and !player.isCasting()) {
            if (player.queued_skill_index) |skill_idx| {
                if (player.queued_skill_target_id) |target_id| {
                    // Get skill or clear queue if invalid (defensive programming - shouldn't happen)
                    const skill = player.skill_bar[skill_idx] orelse {
                        player.clearSkillQueue();
                        break :skill_queue_block;
                    };

                    // Find the target entity
                    for (entities) |*ent| {
                        if (ent.id == target_id) {
                            if (!ent.isAlive()) {
                                print("Queued skill target died\n", .{});
                                player.clearSkillQueue();
                                break;
                            }

                            const distance = player.distanceTo(ent.*);

                            // Check if we're in range now
                            if (distance <= skill.cast_range) {
                                // In range! Try to cast the queued skill
                                print("In range - casting queued skill: {s}\n", .{skill.name});
                                const result = combat.tryStartCast(player, skill_idx, ent, target_id, rng, vfx_manager, terrain_grid);
                                player.clearSkillQueue();

                                if (result == .out_of_range) {
                                    // Still somehow out of range? (shouldn't happen)
                                    print("Still out of range after approach?\n", .{});
                                }
                            } else {
                                // Still out of range - keep approaching (only if no manual input)
                                if (move_x == 0.0 and move_z == 0.0 and !has_keyboard_input) {
                                    const dx = ent.position.x - player.position.x;
                                    const dz = ent.position.z - player.position.z;

                                    // Calculate world-space movement direction
                                    const move_dir_x = dx / distance;
                                    const move_dir_z = dz / distance;

                                    // Convert world movement to local space (inverse of camera rotation)
                                    const cos_angle = @cos(input_state.camera_angle);
                                    const sin_angle = @sin(input_state.camera_angle);
                                    move_x = move_dir_x * cos_angle - move_dir_z * sin_angle;
                                    move_z = move_dir_x * sin_angle + move_dir_z * cos_angle;

                                    skill_approach_active = true;
                                } else {
                                    // Manual input cancels skill queue
                                    print("Skill queue cancelled by manual input\n", .{});
                                    player.clearSkillQueue();
                                }
                            }
                            break;
                        }
                    }
                }
            }
        }
    }

    // === CLICK-TO-MOVE ===
    // Check if we should use click-to-move instead (unless auto-chasing or skill-approaching)
    if (!auto_chase_active and !skill_approach_active) {
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
    }

    // === CLICK-TO-TARGET & CLICK-TO-MOVE (from buffered inputs) ===
    if (input_state.buffered_click_entity) |entity_id| {
        // Check for double-click on same target
        const current_time = @as(f32, @floatCast(rl.getTime()));
        const is_double_click = if (input_state.last_click_target) |lct| blk: {
            break :blk (current_time - input_state.last_click_time) < 0.3 and entity_id == lct;
        } else false;

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
        input_state.last_click_time = current_time;
        input_state.buffered_click_entity = null; // Consume the input
    } else if (input_state.buffered_click_terrain) |hit_point| {
        // Clicked on terrain - click-to-move
        input_state.move_target = hit_point;
        input_state.autorun = false;
        input_state.last_click_target = null;
        input_state.last_click_time = @as(f32, @floatCast(rl.getTime()));
        print("Click-to-move target: ({d:.1}, {d:.1})\n", .{ hit_point.x, hit_point.z });
        input_state.buffered_click_terrain = null; // Consume the input
    }

    // NOTE: Camera rotation/pitch are now updated every frame in pollInput()
    // This prevents jitter from tick-rate vs frame-rate mismatch

    // Return movement intent for movement system to process
    return MovementIntent{
        .local_x = move_x,
        .local_z = move_z,
        .facing_angle = input_state.camera_angle,
        .apply_penalties = true,
    };
}

fn useSkill(player: *Character, entities: []Character, selected_target: ?EntityId, skill_index: u8, rng: *std.Random, vfx_manager: *@import("vfx.zig").VFXManager, terrain_grid: *@import("terrain.zig").TerrainGrid, input_state: *InputState, camera: *const rl.Camera) void {
    if (skill_index >= player.skill_bar.len) return;

    const skill = player.skill_bar[skill_index] orelse {
        print("No skill in slot {d}\n", .{skill_index});
        return;
    };

    // QUICK-CAST for ground-targeted skills
    if (skill.target_type == .ground) {
        var ground_position: rl.Vector3 = undefined;

        // Determine quick-cast position based on input method
        if (input_state.action_camera or rl.isGamepadAvailable(0)) {
            // Controller/Action Camera: Cast at fixed distance in front of player
            const cast_distance = @min(skill.cast_range * 0.6, 80.0); // 60% of max range or 80 units
            const forward_x = @sin(input_state.camera_angle);
            const forward_z = @cos(input_state.camera_angle);

            ground_position = .{
                .x = player.position.x + forward_x * cast_distance,
                .y = 0,
                .z = player.position.z + forward_z * cast_distance,
            };

            print("Quick-cast {s} at {d:.0} units ahead\n", .{ skill.name, cast_distance });
        } else {
            // Mouse/Keyboard: Cast at mouse cursor position (raycast to ground)
            const mouse_pos = rl.getMousePosition();
            const ray = rl.getScreenToWorldRay(mouse_pos, camera.*);

            if (ray.direction.y != 0.0) {
                const t = -ray.position.y / ray.direction.y;
                if (t > 0.0) {
                    ground_position = .{
                        .x = ray.position.x + ray.direction.x * t,
                        .y = 0.0,
                        .z = ray.position.z + ray.direction.z * t,
                    };

                    // Clamp to max range
                    const dx = ground_position.x - player.position.x;
                    const dz = ground_position.z - player.position.z;
                    const distance = @sqrt(dx * dx + dz * dz);

                    if (distance > skill.cast_range) {
                        // Clamp to max range
                        const scale = skill.cast_range / distance;
                        ground_position.x = player.position.x + dx * scale;
                        ground_position.z = player.position.z + dz * scale;
                        print("Quick-cast {s} at mouse cursor (clamped to {d:.0} range)\n", .{ skill.name, skill.cast_range });
                    } else {
                        print("Quick-cast {s} at mouse cursor ({d:.0} units away)\n", .{ skill.name, distance });
                    }
                } else {
                    // Raycast failed, fall back to in-front position
                    const cast_distance = @min(skill.cast_range * 0.6, 80.0);
                    const forward_x = @sin(input_state.camera_angle);
                    const forward_z = @cos(input_state.camera_angle);
                    ground_position = .{
                        .x = player.position.x + forward_x * cast_distance,
                        .y = 0,
                        .z = player.position.z + forward_z * cast_distance,
                    };
                    print("Quick-cast {s} (raycast failed, using fallback position)\n", .{skill.name});
                }
            } else {
                // Raycast failed, fall back to in-front position
                const cast_distance = @min(skill.cast_range * 0.6, 80.0);
                const forward_x = @sin(input_state.camera_angle);
                const forward_z = @cos(input_state.camera_angle);
                ground_position = .{
                    .x = player.position.x + forward_x * cast_distance,
                    .y = 0,
                    .z = player.position.z + forward_z * cast_distance,
                };
                print("Quick-cast {s} (raycast failed, using fallback position)\n", .{skill.name});
            }
        }

        // Cast immediately at the determined position
        _ = combat.tryStartCastAtGround(player, skill_index, ground_position, rng, vfx_manager, terrain_grid);
        return;
    }

    // Regular targeting (entity-targeted or self-targeted skills)
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

    _ = combat.tryStartCast(player, skill_index, target, selected_target, rng, vfx_manager, terrain_grid);
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
