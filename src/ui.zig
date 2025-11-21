const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const input = @import("input.zig");

const Character = character.Character;
const InputState = input.InputState;

pub fn drawUI(player: Character, entities: []const Character, selected_target: ?usize, input_state: InputState, camera: rl.Camera) void {
    _ = camera; // Suppress unused parameter warning

    // Debug info
    const shift_text = if (input_state.shift_held) "Shift Held: true" else "Shift Held: false";
    rl.drawText(shift_text, 10, 10, 16, .yellow);

    // Action Camera indicator
    if (input_state.action_camera) {
        rl.drawText("ACTION CAMERA", 10, 30, 16, .orange);
        // Draw center reticle
        const screen_width = rl.getScreenWidth();
        const screen_height = rl.getScreenHeight();
        const center_x = @divTrunc(screen_width, 2);
        const center_y = @divTrunc(screen_height, 2);

        // Draw crosshair
        rl.drawLine(center_x - 10, center_y, center_x + 10, center_y, .white);
        rl.drawLine(center_x, center_y - 10, center_x, center_y + 10, .white);
        rl.drawCircleLines(center_x, center_y, 5, .white);
    }

    if (selected_target) |_| {
        rl.drawText("Target: some", 10, 50, 16, .sky_blue);
    } else {
        rl.drawText("Target: null", 10, 50, 16, .sky_blue);
    }

    // Draw controls help
    rl.drawText("Controls:", 10, 80, 20, .white);

    // Show gamepad controls if available
    if (rl.isGamepadAvailable(0)) {
        rl.drawText("Left Stick: Move", 10, 105, 16, .lime);
        rl.drawText("Right Stick: Camera (pitch+yaw)", 10, 125, 16, .lime);
        rl.drawText("Face Buttons: Use skills 1-4", 10, 145, 16, .lime);
        rl.drawText("Shoulders: Target cycle / skills 5-8", 10, 165, 16, .lime);
    } else {
        rl.drawText("1-8: Use skills", 10, 105, 16, .light_gray);
        rl.drawText("WASD: Move (strafe/backward penalty)", 10, 125, 16, .light_gray);
        rl.drawText("R: Autorun | X: Quick 180", 10, 145, 16, .light_gray);
        rl.drawText("C: Toggle Action Camera", 10, 165, 16, .light_gray);
        rl.drawText("Right Mouse: Camera | Wheel: Zoom", 10, 185, 16, .light_gray);
        rl.drawText("Left Click: Move/Target", 10, 205, 16, .light_gray);
    }

    rl.drawText("ESC: Exit", 10, 225, 16, .light_gray);

    // Draw current target info
    if (selected_target) |target_index| {
        const target = entities[target_index];
        rl.drawText("Current Target:", 10, 250, 18, .white);
        // TODO: Fix target.name drawing - string issue
        rl.drawText("Target Name", 10, 270, 16, target.color);

        const target_type_text = if (target.is_enemy) "Enemy" else "Ally";
        rl.drawText(target_type_text, 10, 290, 14, .light_gray);

        var warmth_buf: [32]u8 = undefined;
        const warmth_text = std.fmt.bufPrintZ(
            &warmth_buf,
            "Warmth: {d}/{d}",
            .{ target.warmth, target.max_warmth },
        ) catch "Warmth: ???";
        rl.drawText(warmth_text, 10, 310, 14, .light_gray);

        var energy_buf: [32]u8 = undefined;
        const energy_text = std.fmt.bufPrintZ(
            &energy_buf,
            "Energy: {d}/{d}",
            .{ target.energy, target.max_energy },
        ) catch "Energy: ???";
        rl.drawText(energy_text, 10, 330, 14, .light_gray);
    }

    // Draw skill bar
    drawSkillBar(player);

    // Draw secondary info (bottom right)
    const secondary_x = 800;
    const secondary_y = 500;

    // Draw player info
    var energy_buf: [32]u8 = undefined;
    const energy_text = std.fmt.bufPrintZ(
        &energy_buf,
        "Energy: {d}/{d}",
        .{ player.energy, player.max_energy },
    ) catch "Energy: ???";
    rl.drawText(energy_text, secondary_x, secondary_y, 16, .red);

    var warmth_buf: [32]u8 = undefined;
    const warmth_text = std.fmt.bufPrintZ(
        &warmth_buf,
        "Warmth: {d}/{d}",
        .{ player.warmth, player.max_warmth },
    ) catch "Warmth: ???";
    rl.drawText(warmth_text, secondary_x, secondary_y + 20, 16, .orange);

    // Draw school info
    const school_name = @tagName(player.school);
    rl.drawText(school_name, secondary_x, secondary_y + 40, 12, .light_gray);
}

fn drawSkillBar(player: Character) void {
    const start_x: f32 = 300;
    const start_y: f32 = 500;
    const skill_size: f32 = 40;
    const skill_spacing: f32 = 10;
    const skill_bar_height: f32 = 60;

    // Draw background for skill bar
    rl.drawRectangle(@intFromFloat(start_x - 10), @intFromFloat(start_y - 10), 400, @intFromFloat(skill_bar_height), rl.Color{ .r = 0, .g = 0, .b = 0, .a = 50 });

    // Draw skill slots 1-4 (main row)
    for (0..4) |i| {
        const skill_x = start_x + @as(f32, @floatFromInt(i)) * (skill_size + skill_spacing);
        const skill_y = start_y;

        // Draw skill slot
        rl.drawRectangleLines(@intFromFloat(skill_x), @intFromFloat(skill_y), @intFromFloat(skill_size), @intFromFloat(skill_size), .white);

        // Draw skill number
        var num_buf: [8]u8 = undefined;
        const num_text = std.fmt.bufPrintZ(&num_buf, "{}", .{i + 1}) catch "?";
        rl.drawText(num_text, @intFromFloat(skill_x + 2), @intFromFloat(skill_y + 2), 10, .white);

        // Draw skill name if available
        if (player.skill_bar[i]) |skill| {
            rl.drawText(skill.name, @intFromFloat(skill_x + 15), @intFromFloat(skill_y + 15), 8, .yellow);
        }
    }

    // Draw skill slots 5-8 (secondary row, below)
    for (0..4) |i| {
        const skill_x = start_x + @as(f32, @floatFromInt(i)) * (skill_size + skill_spacing);
        const skill_y = start_y + skill_size + skill_spacing;

        // Draw skill slot
        rl.drawRectangleLines(@intFromFloat(skill_x), @intFromFloat(skill_y), @intFromFloat(skill_size), @intFromFloat(skill_size), .gray);

        // Draw skill number
        var num_buf: [8]u8 = undefined;
        const num_text = std.fmt.bufPrintZ(&num_buf, "{}", .{i + 5}) catch "?";
        rl.drawText(num_text, @intFromFloat(skill_x + 2), @intFromFloat(skill_y + 2), 10, .gray);

        // Draw skill name if available
        if (player.skill_bar[i + 4]) |skill| {
            rl.drawText(skill.name, @intFromFloat(skill_x + 15), @intFromFloat(skill_y + 15), 8, .yellow);
        }
    }

    // Draw equipment slots (slots 4-7)
    const equip_start_y = start_y + skill_bar_height + 10;
    rl.drawText("Equipment:", @intFromFloat(start_x), @intFromFloat(equip_start_y), 12, .white);

    // Main hand (slot 4)
    const main_hand_x = start_x;
    const main_hand_y = equip_start_y + 20;
    rl.drawText("Main:", @intFromFloat(main_hand_x), @intFromFloat(main_hand_y), 10, .white);
    rl.drawRectangleLines(@intFromFloat(main_hand_x + 50), @intFromFloat(main_hand_y), @intFromFloat(skill_size), @intFromFloat(skill_size), .dark_gray);
    if (player.main_hand) |equip| {
        rl.drawText(equip.name, @intFromFloat(main_hand_x + 52), @intFromFloat(main_hand_y + 2), 10, .white);
    } else {
        rl.drawText("Empty", @intFromFloat(main_hand_x + 52), @intFromFloat(main_hand_y + 2), 10, .gray);
    }

    // Off hand (slot 5)
    const off_hand_x = start_x + 120;
    const off_hand_y = equip_start_y + 20;
    rl.drawText("Off:", @intFromFloat(off_hand_x), @intFromFloat(off_hand_y), 10, .white);
    rl.drawRectangleLines(@intFromFloat(off_hand_x + 50), @intFromFloat(off_hand_y), @intFromFloat(skill_size), @intFromFloat(skill_size), .dark_gray);
    if (player.off_hand) |equip| {
        rl.drawText(equip.name, @intFromFloat(off_hand_x + 52), @intFromFloat(off_hand_y + 2), 10, .white);
    } else {
        rl.drawText("Empty", @intFromFloat(off_hand_x + 52), @intFromFloat(off_hand_y + 2), 10, .gray);
    }

    // Shield (slot 6)
    const shield_x = start_x + 240;
    const shield_y = equip_start_y + 20;
    rl.drawText("Shield:", @intFromFloat(shield_x), @intFromFloat(shield_y), 10, .white);
    rl.drawRectangleLines(@intFromFloat(shield_x + 50), @intFromFloat(shield_y), @intFromFloat(skill_size), @intFromFloat(skill_size), .dark_gray);
    if (player.shield) |equip| {
        rl.drawText(equip.name, @intFromFloat(shield_x + 52), @intFromFloat(shield_y + 2), 10, .white);
    } else {
        rl.drawText("Empty", @intFromFloat(shield_x + 52), @intFromFloat(shield_y + 2), 10, .gray);
    }
}
