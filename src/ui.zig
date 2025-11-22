const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const input = @import("input.zig");
const entity_types = @import("entity.zig");
const skill_icons = @import("skill_icons.zig");

const Character = character.Character;
const InputState = input.InputState;
const EntityId = entity_types.EntityId;

// Helper to convert float coordinates to integer screen positions
inline fn toI32(val: f32) i32 {
    return @intFromFloat(val);
}

// Draw an MTG/GW1-style skill tooltip card
fn drawSkillTooltip(skill: character.Skill, player_position: character.Position, player_school: character.School, x: f32, y: f32) void {
    const card_width: f32 = 320;
    const card_height: f32 = 240;
    const padding: f32 = 12;
    const glyph_size: f32 = 20;

    const xi = toI32(x);
    const yi = toI32(y);
    const card_width_i = toI32(card_width);
    const card_height_i = toI32(card_height);

    // Card background (dark with border)
    rl.drawRectangle(xi, yi, card_width_i, card_height_i, rl.Color{ .r = 20, .g = 20, .b = 25, .a = 250 });
    rl.drawRectangleLines(xi, yi, card_width_i, card_height_i, rl.Color{ .r = 200, .g = 180, .b = 100, .a = 255 });

    var current_y = y + padding;

    // TOP ROW: Skill name (left) + Cost glyphs (right)
    // Skill name
    rl.drawText(skill.name, toI32(x + padding), toI32(current_y), 18, .white);

    // Cost glyphs (right-aligned)
    var glyph_x = x + card_width - padding - glyph_size;

    // Recharge glyph (clock icon with number)
    const recharge_sec = @as(f32, @floatFromInt(skill.recharge_time_ms)) / 1000.0;
    drawCostGlyph(glyph_x, current_y, glyph_size, rl.Color{ .r = 100, .g = 100, .b = 255, .a = 255 }, recharge_sec);
    glyph_x -= glyph_size + 4;

    // Activation glyph (hourglass with number) - only if not instant
    if (skill.activation_time_ms > 0) {
        const activation_sec = @as(f32, @floatFromInt(skill.activation_time_ms)) / 1000.0;
        drawCostGlyph(glyph_x, current_y, glyph_size, rl.Color{ .r = 255, .g = 200, .b = 100, .a = 255 }, activation_sec);
        glyph_x -= glyph_size + 4;
    }

    // Energy glyph (lightning bolt with number)
    if (skill.energy_cost > 0) {
        drawCostGlyph(glyph_x, current_y, glyph_size, rl.Color{ .r = 100, .g = 200, .b = 255, .a = 255 }, @as(f32, @floatFromInt(skill.energy_cost)));
    }

    current_y += 28;

    // ICON (centered, large)
    const icon_size: f32 = 60;
    const icon_x = x + (card_width - icon_size) / 2.0;
    skill_icons.drawSkillIcon(icon_x, current_y, icon_size, &skill, player_school, player_position, true);
    current_y += icon_size + 8;

    // SKILL TYPE (centered, italic-style)
    const type_name = @tagName(skill.skill_type);
    const type_text_width = rl.measureText(type_name, 12);
    const type_x = x + (card_width - @as(f32, @floatFromInt(type_text_width))) / 2.0;
    rl.drawText(type_name, toI32(type_x), toI32(current_y), 12, rl.Color{ .r = 180, .g = 180, .b = 180, .a = 255 });
    current_y += 18;

    // Separator line
    rl.drawLine(toI32(x + padding), toI32(current_y), toI32(x + card_width - padding), toI32(current_y), rl.Color{ .r = 100, .g = 100, .b = 100, .a = 255 });
    current_y += 8;

    // DESCRIPTION / ORACLE TEXT (word-wrapped, multiple lines)
    // Debug: Show description length
    var debug_buf: [64]u8 = undefined;
    const debug_text = std.fmt.bufPrintZ(
        &debug_buf,
        "Desc len: {d}",
        .{skill.description.len},
    ) catch unreachable;
    rl.drawText(debug_text, toI32(x + padding), toI32(current_y), 10, .yellow);
    current_y += 14;

    if (skill.description.len > 0) {
        const text_width = card_width - (padding * 2);
        drawWrappedText(skill.description, x + padding, current_y, text_width, 11, rl.Color{ .r = 220, .g = 220, .b = 220, .a = 255 });
    } else {
        // Fallback: show basic stats if no description
        rl.drawText("(No description available)", toI32(x + padding), toI32(current_y), 10, rl.Color{ .r = 150, .g = 150, .b = 150, .a = 255 });
    }
}

// Draw a cost glyph (circle with number)
fn drawCostGlyph(x: f32, y: f32, size: f32, color: rl.Color, value: f32) void {
    const center_x = x + size / 2.0;
    const center_y = y + size / 2.0;
    const radius = size / 2.0;

    // Draw circle background
    rl.drawCircle(toI32(center_x), toI32(center_y), radius, color);
    rl.drawCircleLines(toI32(center_x), toI32(center_y), radius, .white);

    // Draw number (centered)
    var value_buf: [16]u8 = undefined;
    const value_text = if (value == @floor(value))
        std.fmt.bufPrintZ(&value_buf, "{d}", .{@as(i32, @intFromFloat(value))}) catch unreachable
    else
        std.fmt.bufPrintZ(&value_buf, "{d:.1}", .{value}) catch unreachable;

    const text_width = rl.measureText(value_text, 12);
    const text_x = center_x - @as(f32, @floatFromInt(text_width)) / 2.0;
    const text_y = center_y - 6;
    rl.drawText(value_text, toI32(text_x), toI32(text_y), 12, .black);
}

// Draw word-wrapped text (simple implementation for skill descriptions)
fn drawWrappedText(text: [:0]const u8, x: f32, y: f32, max_width: f32, font_size: i32, color: rl.Color) void {
    _ = max_width; // TODO: Implement proper word wrapping

    // For now, just draw the text as-is (will implement proper wrapping later)
    // Split on periods for basic line breaks
    var current_y = y;
    const line_height = @as(f32, @floatFromInt(font_size)) + 4;

    var start: usize = 0;
    for (text, 0..) |c, i| {
        if (c == '.' and i + 1 < text.len) {
            // Draw line including the period
            var line_buf: [256]u8 = undefined;
            const line_len = i - start + 1;
            if (line_len < line_buf.len) {
                @memcpy(line_buf[0..line_len], text[start .. i + 1]);
                line_buf[line_len] = 0;
                const line_z: [:0]const u8 = line_buf[0..line_len :0];
                rl.drawText(line_z, toI32(x), toI32(current_y), font_size, color);
                current_y += line_height;

                // Skip spaces after period
                start = i + 1;
                while (start < text.len and text[start] == ' ') {
                    start += 1;
                }
            }
        }
    }

    // Draw remaining text
    if (start < text.len) {
        const remaining = text[start..];
        rl.drawText(remaining, toI32(x), toI32(current_y), font_size, color);
    }
}

pub fn drawUI(player: *const Character, entities: []const Character, selected_target: ?EntityId, input_state: *InputState, camera: rl.Camera) void {
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
    if (selected_target) |target_id| {
        // Find target by ID
        var target: ?Character = null;
        if (player.*.id == target_id) {
            target = player.*;
        } else {
            for (entities) |ent| {
                if (ent.id == target_id) {
                    target = ent;
                    break;
                }
            }
        }

        if (target) |tgt| {
            rl.drawText("Current Target:", 10, 70, 18, .white);
            // TODO: Fix target.name drawing - string issue
            rl.drawText("Target Name", 10, 90, 16, tgt.color);

            const target_type_text = if (tgt.is_enemy) "Enemy" else "Ally";
            rl.drawText(target_type_text, 10, 110, 14, .light_gray);

            var warmth_buf: [64]u8 = undefined;
            const warmth_text = std.fmt.bufPrintZ(
                &warmth_buf,
                "Warmth: {d:.1}/{d:.1}",
                .{ tgt.warmth, tgt.max_warmth },
            ) catch unreachable; // Buffer is large enough
            rl.drawText(warmth_text, 10, 130, 14, .light_gray);

            var energy_buf: [64]u8 = undefined;
            const energy_text = std.fmt.bufPrintZ(
                &energy_buf,
                "Energy: {d}/{d}",
                .{ tgt.energy, tgt.max_energy },
            ) catch unreachable; // Buffer is large enough
            rl.drawText(energy_text, 10, 150, 14, .light_gray);
        }
    }

    // Draw skill bar (and detect mouse hover)
    drawSkillBar(player, input_state);

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

fn drawSkillSlot(player: *const Character, index: usize, x: f32, y: f32, size: f32, input_state: *InputState) void {
    const xi = toI32(x);
    const yi = toI32(y);
    const sizei = toI32(size);

    // Check for mouse hover
    const mouse_pos = rl.getMousePosition();
    const is_hovered = mouse_pos.x >= x and mouse_pos.x <= x + size and
        mouse_pos.y >= y and mouse_pos.y <= y + size;

    if (is_hovered) {
        input_state.hovered_skill_index = @intCast(index);
    }

    // Draw skill slot background
    const bg_color = if (player.skill_cooldowns[index] > 0)
        rl.Color{ .r = 40, .g = 40, .b = 40, .a = 200 }
    else
        rl.Color{ .r = 0, .g = 0, .b = 0, .a = 100 };
    rl.drawRectangle(xi, yi, sizei, sizei, bg_color);

    // Draw border - highlight if currently casting this skill OR if inspected
    const is_casting_this = player.cast_state == .activating and player.casting_skill_index == index;
    const is_inspected = if (input_state.inspected_skill_index) |idx| idx == index else false;
    const final_border = if (is_casting_this)
        rl.Color.orange
    else if (is_inspected or is_hovered)
        rl.Color.yellow
    else
        rl.Color.white;
    rl.drawRectangleLines(xi, yi, sizei, sizei, final_border);

    // Draw skill icon (centered in slot) if available
    if (player.skill_bar[index]) |skill| {
        const icon_size: f32 = size * 0.8; // Icon takes 80% of slot (larger now, no text)
        const icon_x = x + (size - icon_size) / 2.0;
        const icon_y = y + (size - icon_size) / 2.0;

        // Check if player can afford this skill
        const can_afford = player.energy >= skill.energy_cost;

        skill_icons.drawSkillIcon(icon_x, icon_y, icon_size, skill, player.school, player.player_position, can_afford);

        // Draw cooldown overlay (visual only, no text)
        if (player.skill_cooldowns[index] > 0) {
            const cooldown_total = @as(f32, @floatFromInt(skill.recharge_time_ms)) / 1000.0;
            const cooldown_progress = player.skill_cooldowns[index] / cooldown_total;
            const overlay_height = size * cooldown_progress;

            // Dark overlay showing cooldown progress (drains from top)
            rl.drawRectangle(xi, toI32(y + (size - overlay_height)), sizei, toI32(overlay_height), rl.Color{ .r = 0, .g = 0, .b = 0, .a = 180 });
        }
    }
}

fn drawWarmthOrb(player: *const Character, x: f32, y: f32, width: f32, height: f32) void {
    // Calculate circle parameters
    const center_x = x + width / 2.0;
    const center_y = y + height / 2.0;
    const radius = @min(width, height) / 2.0;

    const center_xi = toI32(center_x);
    const center_yi = toI32(center_y);

    // Draw orb border
    rl.drawCircleLines(center_xi, center_yi, radius, .white);

    // Calculate fill percentage (drains from bottom to top)
    const fill_percent = player.warmth / player.max_warmth;

    // Draw filled circle portion (bottom to top)
    // We'll draw the circle in red, then cover the top unfilled portion with black
    const health_color = rl.Color{ .r = 200, .g = 0, .b = 0, .a = 255 }; // Red

    // Draw full circle
    rl.drawCircle(center_xi, center_yi, radius - 2, health_color);

    // Cover the empty portion with a black rectangle from top
    if (fill_percent < 1.0) {
        const empty_height = (1.0 - fill_percent) * (radius * 2.0);
        const rect_y = center_y - radius;
        rl.drawRectangle(toI32(center_x - radius), toI32(rect_y), toI32(radius * 2.0), toI32(empty_height), rl.Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
    }

    // Redraw border to clean up edges
    rl.drawCircleLines(center_xi, center_yi, radius, .white);

    // Draw warmth text below orb
    var warmth_buf: [32]u8 = undefined;
    const warmth_text = std.fmt.bufPrintZ(
        &warmth_buf,
        "{d:.0}/{d:.0}",
        .{ player.warmth, player.max_warmth },
    ) catch unreachable;

    const text_width = rl.measureText(warmth_text, 12);
    rl.drawText(warmth_text, center_xi - @divTrunc(text_width, 2), toI32(y + height + 5), 12, .white);
}

fn drawEnergyBar(player: *const Character, x: f32, y: f32, width: f32, height: f32) void {
    const xi = toI32(x);
    const yi = toI32(y);
    const widthi = toI32(width);
    const heighti = toI32(height);

    // Draw border
    rl.drawRectangleLines(xi, yi, widthi, heighti, .white);

    // Calculate fill
    const fill_percent = @as(f32, @floatFromInt(player.energy)) / @as(f32, @floatFromInt(player.max_energy));
    const fill_width = (width - 4) * fill_percent;

    // Draw energy fill (blue)
    rl.drawRectangle(xi + 2, yi + 2, toI32(fill_width), heighti - 4, rl.Color{ .r = 0, .g = 100, .b = 255, .a = 255 });

    // Draw energy text
    var energy_buf: [32]u8 = undefined;
    const energy_text = std.fmt.bufPrintZ(
        &energy_buf,
        "{d}/{d}",
        .{ player.energy, player.max_energy },
    ) catch unreachable;

    const text_width = rl.measureText(energy_text, 10);
    rl.drawText(energy_text, toI32(x + width / 2.0) - @divTrunc(text_width, 2), yi + 2, 10, .white);
}

fn drawConditionIcons(player: *const Character, x: f32, y: f32, icon_size: f32, spacing: f32) void {
    const yi = toI32(y);
    const sizei = toI32(icon_size);

    // Draw buffs (cozies) - first row
    var buff_x = x;
    for (player.active_cozies[0..player.active_cozy_count]) |maybe_cozy| {
        if (maybe_cozy) |cozy| {
            const buff_xi = toI32(buff_x);

            // Draw buff icon background
            rl.drawRectangle(buff_xi, yi, sizei, sizei, rl.Color{ .r = 0, .g = 100, .b = 0, .a = 200 });
            rl.drawRectangleLines(buff_xi, yi, sizei, sizei, .green);

            // Draw first letter of buff name
            const name = @tagName(cozy.cozy);
            var letter_buf: [2]u8 = undefined;
            letter_buf[0] = std.ascii.toUpper(name[0]);
            letter_buf[1] = 0;
            rl.drawText(@ptrCast(&letter_buf), buff_xi + 5, yi + 5, 12, .white);

            // Draw time remaining
            const seconds = cozy.time_remaining_ms / 1000;
            var time_buf: [8]u8 = undefined;
            const time_text = std.fmt.bufPrintZ(&time_buf, "{d}", .{seconds}) catch unreachable;
            rl.drawText(time_text, buff_xi + 2, toI32(y + icon_size - 10), 8, .white);

            buff_x += icon_size + spacing;
        }
    }

    // Draw debuffs (chills) - second row
    var debuff_x = x;
    const debuff_y = y + icon_size + spacing;
    const debuff_yi = toI32(debuff_y);

    for (player.active_chills[0..player.active_chill_count]) |maybe_chill| {
        if (maybe_chill) |chill| {
            const debuff_xi = toI32(debuff_x);

            // Draw debuff icon background
            rl.drawRectangle(debuff_xi, debuff_yi, sizei, sizei, rl.Color{ .r = 100, .g = 0, .b = 0, .a = 200 });
            rl.drawRectangleLines(debuff_xi, debuff_yi, sizei, sizei, .red);

            // Draw first letter of debuff name
            const name = @tagName(chill.chill);
            var letter_buf: [2]u8 = undefined;
            letter_buf[0] = std.ascii.toUpper(name[0]);
            letter_buf[1] = 0;
            rl.drawText(@ptrCast(&letter_buf), debuff_xi + 5, debuff_yi + 5, 12, .white);

            // Draw time remaining
            const seconds = chill.time_remaining_ms / 1000;
            var time_buf: [8]u8 = undefined;
            const time_text = std.fmt.bufPrintZ(&time_buf, "{d}", .{seconds}) catch unreachable;
            rl.drawText(time_text, debuff_xi + 2, toI32(debuff_y + icon_size - 10), 8, .white);

            debuff_x += icon_size + spacing;
        }
    }
}

fn drawSkillBar(player: *const Character, input_state: *InputState) void {
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

    // Reset hover state (will be set if mouse is over a skill)
    input_state.hovered_skill_index = null;

    // Draw casting bar if casting (centered above entire skill bar)
    if (player.cast_state == .activating) {
        const casting_skill = player.skill_bar[player.casting_skill_index];
        if (casting_skill) |skill| {
            const cast_time_total = @as(f32, @floatFromInt(skill.activation_time_ms)) / 1000.0;
            const progress = 1.0 - (player.cast_time_remaining / cast_time_total);

            const cast_bar_y = start_y - 40;
            const cast_bar_width: f32 = 400;
            const cast_bar_x = (@as(f32, @floatFromInt(screen_width)) - cast_bar_width) / 2.0;

            const cast_bar_xi = toI32(cast_bar_x);
            const cast_bar_yi = toI32(cast_bar_y);

            rl.drawRectangleLines(cast_bar_xi, cast_bar_yi, toI32(cast_bar_width), 20, .white);
            rl.drawRectangle(cast_bar_xi + 2, cast_bar_yi + 2, toI32((cast_bar_width - 4) * progress), 16, .yellow);

            // Show skill name being cast
            rl.drawText(skill.name, cast_bar_xi + 5, cast_bar_yi - 20, 14, .white);
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
        drawSkillSlot(player, i, skill_x, skill_y, skill_size, input_state);
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
        drawSkillSlot(player, i, skill_x, skill_y, skill_size, input_state);
        skill_x += skill_size + skill_spacing;
    }

    // Draw tooltip if hovering or inspecting a skill
    const tooltip_skill_index = input_state.hovered_skill_index orelse input_state.inspected_skill_index;
    if (tooltip_skill_index) |idx| {
        if (player.skill_bar[idx]) |skill| {
            // Position tooltip above the skill bar, centered on screen
            const tooltip_x = (@as(f32, @floatFromInt(screen_width)) - 320) / 2.0;
            const tooltip_y = start_y - 260; // Above the skill bar
            drawSkillTooltip(skill.*, player.player_position, player.school, tooltip_x, tooltip_y);
        }
    }
}
