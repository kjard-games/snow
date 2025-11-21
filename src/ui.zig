const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const input = @import("input.zig");

const Character = character.Character;
const InputState = input.InputState;

pub fn drawUI(player: *const Character, entities: []const Character, selected_target: ?usize, input_state: InputState, camera: rl.Camera) void {
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

    // Draw current target info
    if (selected_target) |target_index| {
        if (target_index >= entities.len) return; // Bounds check
        const target = entities[target_index];
        rl.drawText("Current Target:", 10, 70, 18, .white);
        // TODO: Fix target.name drawing - string issue
        rl.drawText("Target Name", 10, 90, 16, target.color);

        const target_type_text = if (target.is_enemy) "Enemy" else "Ally";
        rl.drawText(target_type_text, 10, 110, 14, .light_gray);

        var warmth_buf: [64]u8 = undefined;
        const warmth_text = std.fmt.bufPrintZ(
            &warmth_buf,
            "Warmth: {d:.1}/{d:.1}",
            .{ target.warmth, target.max_warmth },
        ) catch unreachable; // Buffer is large enough
        rl.drawText(warmth_text, 10, 130, 14, .light_gray);

        var energy_buf: [64]u8 = undefined;
        const energy_text = std.fmt.bufPrintZ(
            &energy_buf,
            "Energy: {d}/{d}",
            .{ target.energy, target.max_energy },
        ) catch unreachable; // Buffer is large enough
        rl.drawText(energy_text, 10, 150, 14, .light_gray);
    }

    // Draw skill bar
    drawSkillBar(player);

    // Draw secondary info (bottom right)
    const secondary_x = rl.getScreenWidth() - 200;
    const secondary_y = rl.getScreenHeight() - 100;

    // Draw player info
    var energy_buf: [64]u8 = undefined;
    const energy_text = std.fmt.bufPrintZ(
        &energy_buf,
        "Energy: {d}/{d}",
        .{ player.energy, player.max_energy },
    ) catch unreachable; // Buffer is large enough
    rl.drawText(energy_text, secondary_x, secondary_y, 16, .red);

    var warmth_buf: [64]u8 = undefined;
    const warmth_text = std.fmt.bufPrintZ(
        &warmth_buf,
        "Warmth: {d:.1}/{d:.1}",
        .{ player.warmth, player.max_warmth },
    ) catch unreachable; // Buffer is large enough
    rl.drawText(warmth_text, secondary_x, secondary_y + 20, 16, .orange);

    // Draw school info
    const school_name = @tagName(player.school);
    rl.drawText(school_name, secondary_x, secondary_y + 40, 12, .light_gray);
}

fn drawSkillSlot(player: *const Character, index: usize, x: f32, y: f32, size: f32) void {
    // Draw skill slot background
    const bg_color = if (player.skill_cooldowns[index] > 0)
        rl.Color{ .r = 40, .g = 40, .b = 40, .a = 200 }
    else
        rl.Color{ .r = 0, .g = 0, .b = 0, .a = 100 };
    rl.drawRectangle(@intFromFloat(x), @intFromFloat(y), @intFromFloat(size), @intFromFloat(size), bg_color);

    // Draw border - highlight if currently casting this skill
    const is_casting_this = player.is_casting and player.casting_skill_index == index;
    const final_border = if (is_casting_this) rl.Color.orange else rl.Color.white;
    rl.drawRectangleLines(@intFromFloat(x), @intFromFloat(y), @intFromFloat(size), @intFromFloat(size), final_border);

    // Draw skill number
    var num_buf: [8]u8 = undefined;
    const num_text = std.fmt.bufPrintZ(&num_buf, "{}", .{index + 1}) catch unreachable;
    rl.drawText(num_text, @intFromFloat(x + 2), @intFromFloat(y + 2), 10, .white);

    // Draw skill name if available
    if (player.skill_bar[index]) |skill| {
        const name_color = if (player.skill_cooldowns[index] > 0) rl.Color.dark_gray else rl.Color.yellow;
        rl.drawText(skill.name, @intFromFloat(x + 2), @intFromFloat(y + 25), 6, name_color);

        // Draw cooldown overlay
        if (player.skill_cooldowns[index] > 0) {
            const cooldown_total = @as(f32, @floatFromInt(skill.recharge_time_ms)) / 1000.0;
            const cooldown_progress = player.skill_cooldowns[index] / cooldown_total;
            const overlay_height = size * cooldown_progress;

            rl.drawRectangle(@intFromFloat(x), @intFromFloat(y + (size - overlay_height)), @intFromFloat(size), @intFromFloat(overlay_height), rl.Color{ .r = 0, .g = 0, .b = 0, .a = 150 });

            // Draw cooldown time
            var cd_buf: [16]u8 = undefined;
            const cd_text = std.fmt.bufPrintZ(&cd_buf, "{d:.1}", .{player.skill_cooldowns[index]}) catch unreachable;
            rl.drawText(cd_text, @intFromFloat(x + 10), @intFromFloat(y + 15), 12, .red);
        }

        // Draw energy cost
        var cost_buf: [8]u8 = undefined;
        const cost_text = std.fmt.bufPrintZ(&cost_buf, "{d}", .{skill.energy_cost}) catch unreachable;
        const cost_color = if (player.energy >= skill.energy_cost) rl.Color.sky_blue else rl.Color.red;
        rl.drawText(cost_text, @intFromFloat(x + size - 15), @intFromFloat(y + 2), 10, cost_color);
    }
}

fn drawWarmthOrb(player: *const Character, x: f32, y: f32, width: f32, height: f32) void {
    // Calculate circle parameters
    const center_x = x + width / 2.0;
    const center_y = y + height / 2.0;
    const radius = @min(width, height) / 2.0;

    // Draw orb border
    rl.drawCircleLines(@intFromFloat(center_x), @intFromFloat(center_y), radius, .white);

    // Calculate fill percentage (drains from bottom to top)
    const fill_percent = player.warmth / player.max_warmth;

    // Draw filled circle portion (bottom to top)
    // We'll draw the circle in red, then cover the top unfilled portion with black
    const health_color = rl.Color{ .r = 200, .g = 0, .b = 0, .a = 255 }; // Red

    // Draw full circle
    rl.drawCircle(@intFromFloat(center_x), @intFromFloat(center_y), radius - 2, health_color);

    // Cover the empty portion with a black rectangle from top
    if (fill_percent < 1.0) {
        const empty_height = (1.0 - fill_percent) * (radius * 2.0);
        const rect_y = center_y - radius;
        rl.drawRectangle(@intFromFloat(center_x - radius), @intFromFloat(rect_y), @intFromFloat(radius * 2.0), @intFromFloat(empty_height), rl.Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
    }

    // Redraw border to clean up edges
    rl.drawCircleLines(@intFromFloat(center_x), @intFromFloat(center_y), radius, .white);

    // Draw warmth text below orb
    var warmth_buf: [32]u8 = undefined;
    const warmth_text = std.fmt.bufPrintZ(
        &warmth_buf,
        "{d:.0}/{d:.0}",
        .{ player.warmth, player.max_warmth },
    ) catch unreachable;

    const text_width = rl.measureText(warmth_text, 12);
    const text_x: i32 = @intFromFloat(center_x);
    rl.drawText(warmth_text, text_x - @divTrunc(text_width, 2), @intFromFloat(y + height + 5), 12, .white);
}

fn drawEnergyBar(player: *const Character, x: f32, y: f32, width: f32, height: f32) void {
    // Draw border
    rl.drawRectangleLines(@intFromFloat(x), @intFromFloat(y), @intFromFloat(width), @intFromFloat(height), .white);

    // Calculate fill
    const fill_percent = @as(f32, @floatFromInt(player.energy)) / @as(f32, @floatFromInt(player.max_energy));
    const fill_width = (width - 4) * fill_percent;

    // Draw energy fill (blue)
    rl.drawRectangle(@intFromFloat(x + 2), @intFromFloat(y + 2), @intFromFloat(fill_width), @intFromFloat(height - 4), rl.Color{ .r = 0, .g = 100, .b = 255, .a = 255 });

    // Draw energy text
    var energy_buf: [32]u8 = undefined;
    const energy_text = std.fmt.bufPrintZ(
        &energy_buf,
        "{d}/{d}",
        .{ player.energy, player.max_energy },
    ) catch unreachable;

    const text_width = rl.measureText(energy_text, 10);
    const text_x: i32 = @intFromFloat(x + width / 2.0);
    rl.drawText(energy_text, text_x - @divTrunc(text_width, 2), @intFromFloat(y + 2), 10, .white);
}

fn drawConditionIcons(player: *const Character, x: f32, y: f32, icon_size: f32, spacing: f32) void {
    // Draw buffs (cozies) - first row
    var buff_x = x;
    for (player.active_cozies[0..player.active_cozy_count]) |maybe_cozy| {
        if (maybe_cozy) |cozy| {
            // Draw buff icon background
            rl.drawRectangle(@intFromFloat(buff_x), @intFromFloat(y), @intFromFloat(icon_size), @intFromFloat(icon_size), rl.Color{ .r = 0, .g = 100, .b = 0, .a = 200 });
            rl.drawRectangleLines(@intFromFloat(buff_x), @intFromFloat(y), @intFromFloat(icon_size), @intFromFloat(icon_size), .green);

            // Draw first letter of buff name
            const name = @tagName(cozy.cozy);
            var letter_buf: [2]u8 = undefined;
            letter_buf[0] = std.ascii.toUpper(name[0]);
            letter_buf[1] = 0;
            rl.drawText(@ptrCast(&letter_buf), @intFromFloat(buff_x + 5), @intFromFloat(y + 5), 12, .white);

            // Draw time remaining
            const seconds = cozy.time_remaining_ms / 1000;
            var time_buf: [8]u8 = undefined;
            const time_text = std.fmt.bufPrintZ(&time_buf, "{d}", .{seconds}) catch unreachable;
            rl.drawText(time_text, @intFromFloat(buff_x + 2), @intFromFloat(y + icon_size - 10), 8, .white);

            buff_x += icon_size + spacing;
        }
    }

    // Draw debuffs (chills) - second row
    var debuff_x = x;
    const debuff_y = y + icon_size + spacing;
    for (player.active_chills[0..player.active_chill_count]) |maybe_chill| {
        if (maybe_chill) |chill| {
            // Draw debuff icon background
            rl.drawRectangle(@intFromFloat(debuff_x), @intFromFloat(debuff_y), @intFromFloat(icon_size), @intFromFloat(icon_size), rl.Color{ .r = 100, .g = 0, .b = 0, .a = 200 });
            rl.drawRectangleLines(@intFromFloat(debuff_x), @intFromFloat(debuff_y), @intFromFloat(icon_size), @intFromFloat(icon_size), .red);

            // Draw first letter of debuff name
            const name = @tagName(chill.chill);
            var letter_buf: [2]u8 = undefined;
            letter_buf[0] = std.ascii.toUpper(name[0]);
            letter_buf[1] = 0;
            rl.drawText(@ptrCast(&letter_buf), @intFromFloat(debuff_x + 5), @intFromFloat(debuff_y + 5), 12, .white);

            // Draw time remaining
            const seconds = chill.time_remaining_ms / 1000;
            var time_buf: [8]u8 = undefined;
            const time_text = std.fmt.bufPrintZ(&time_buf, "{d}", .{seconds}) catch unreachable;
            rl.drawText(time_text, @intFromFloat(debuff_x + 2), @intFromFloat(debuff_y + icon_size - 10), 8, .white);

            debuff_x += icon_size + spacing;
        }
    }
}

fn drawSkillBar(player: *const Character) void {
    const screen_width = rl.getScreenWidth();
    const screen_height = rl.getScreenHeight();

    // Layout constants
    const skill_size: f32 = 50;
    const skill_spacing: f32 = 8;
    const orb_width: f32 = 50;
    const orb_height: f32 = 120;
    const icon_size: f32 = 20;
    const icon_spacing: f32 = 4;

    // Calculate total width and center position
    const total_width = (skill_size * 8) + (skill_spacing * 7) + orb_width + (skill_spacing * 2);
    const start_x = (@as(f32, @floatFromInt(screen_width)) - total_width) / 2.0;
    const start_y = @as(f32, @floatFromInt(screen_height)) - orb_height - 30;

    // Draw casting bar if casting (centered above entire skill bar)
    if (player.is_casting) {
        const casting_skill = player.skill_bar[player.casting_skill_index];
        if (casting_skill) |skill| {
            const cast_time_total = @as(f32, @floatFromInt(skill.activation_time_ms)) / 1000.0;
            const progress = 1.0 - (player.cast_time_remaining / cast_time_total);

            const cast_bar_y = start_y - 40;
            const cast_bar_width: f32 = 400;
            const cast_bar_x = (@as(f32, @floatFromInt(screen_width)) - cast_bar_width) / 2.0;

            rl.drawRectangleLines(@intFromFloat(cast_bar_x), @intFromFloat(cast_bar_y), @intFromFloat(cast_bar_width), 20, .white);
            rl.drawRectangle(@intFromFloat(cast_bar_x + 2), @intFromFloat(cast_bar_y + 2), @intFromFloat((cast_bar_width - 4) * progress), 16, .yellow);

            // Show skill name being cast
            rl.drawText(skill.name, @intFromFloat(cast_bar_x + 5), @intFromFloat(cast_bar_y - 20), 14, .white);
        }
    }

    // Skills 1-4 on left
    var skill_x = start_x;
    const skill_y = start_y + orb_height - skill_size; // Align bottom with orb

    // Draw energy bar above skills 1-4
    const energy_bar_width = (skill_size * 4) + (skill_spacing * 3);
    const energy_bar_height: f32 = 15;
    const energy_bar_y = skill_y - energy_bar_height - 5;
    drawEnergyBar(player, skill_x, energy_bar_y, energy_bar_width, energy_bar_height);

    for (0..4) |i| {
        drawSkillSlot(player, i, skill_x, skill_y, skill_size);
        skill_x += skill_size + skill_spacing;
    }

    // Warmth orb in center
    const orb_x = skill_x + skill_spacing;
    const orb_y = start_y;
    drawWarmthOrb(player, orb_x, orb_y, orb_width, orb_height);

    // Skills 5-8 on right
    skill_x = orb_x + orb_width + skill_spacing;

    // Draw buffs/debuffs above skills 5-8
    const conditions_y = skill_y - (icon_size * 2) - icon_spacing - 5;
    drawConditionIcons(player, skill_x, conditions_y, icon_size, icon_spacing);

    for (4..8) |i| {
        drawSkillSlot(player, i, skill_x, skill_y, skill_size);
        skill_x += skill_size + skill_spacing;
    }
}
