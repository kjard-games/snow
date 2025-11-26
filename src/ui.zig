const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const input = @import("input.zig");
const entity_types = @import("entity.zig");
const skill_icons = @import("skill_icons.zig");
const palette = @import("color_palette.zig");

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
    rl.drawRectangle(xi, yi, card_width_i, card_height_i, palette.UI.BACKGROUND);
    rl.drawRectangleLines(xi, yi, card_width_i, card_height_i, palette.UI.BORDER);

    var current_y = y + padding;

    // TOP ROW: Skill name (left) + Cost glyphs (right)
    // Skill name
    rl.drawText(skill.name, toI32(x + padding), toI32(current_y), 18, .white);

    // Cost glyphs (right-aligned)
    var glyph_x = x + card_width - padding - glyph_size;

    // Recharge glyph (clock icon with number)
    const recharge_sec = @as(f32, @floatFromInt(skill.recharge_time_ms)) / 1000.0;
    drawCostGlyph(glyph_x, current_y, glyph_size, palette.COST.RECHARGE, recharge_sec);
    glyph_x -= glyph_size + 4;

    // Activation glyph (hourglass with number) - only if not instant
    if (skill.activation_time_ms > 0) {
        const activation_sec = @as(f32, @floatFromInt(skill.activation_time_ms)) / 1000.0;
        drawCostGlyph(glyph_x, current_y, glyph_size, palette.COST.ACTIVATION, activation_sec);
        glyph_x -= glyph_size + 4;
    }

    // Energy glyph (lightning bolt with number)
    if (skill.energy_cost > 0) {
        drawCostGlyph(glyph_x, current_y, glyph_size, palette.COST.ENERGY, @as(f32, @floatFromInt(skill.energy_cost)));
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
    rl.drawText(type_name, toI32(type_x), toI32(current_y), 12, palette.UI.TEXT_SECONDARY);
    current_y += 18;

    // Separator line
    rl.drawLine(toI32(x + padding), toI32(current_y), toI32(x + card_width - padding), toI32(current_y), palette.UI.SEPARATOR_LINE);
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
        drawWrappedText(skill.description, x + padding, current_y, text_width, 11, palette.UI.TEXT_PRIMARY);
    } else {
        // Fallback: show basic stats if no description
        rl.drawText("(No description available)", toI32(x + padding), toI32(current_y), 10, palette.UI.TEXT_DISABLED);
    }
}

// Draw a cost glyph (circle with number)
fn drawCostGlyph(x: f32, y: f32, size: f32, color: rl.Color, value: f32) void {
    const center_x = x + size / 2.0;
    const center_y = y + size / 2.0;
    const radius = size / 2.0;

    // Draw circle background
    rl.drawCircle(toI32(center_x), toI32(center_y), radius, color);
    rl.drawCircleLines(toI32(center_x), toI32(center_y), radius, palette.COST.GLYPH_BORDER);

    // Draw number (centered)
    var value_buf: [16]u8 = undefined;
    const value_text = if (value == @floor(value))
        std.fmt.bufPrintZ(&value_buf, "{d}", .{@as(i32, @intFromFloat(value))}) catch unreachable
    else
        std.fmt.bufPrintZ(&value_buf, "{d:.1}", .{value}) catch unreachable;

    const text_width = rl.measureText(value_text, 12);
    const text_x = center_x - @as(f32, @floatFromInt(text_width)) / 2.0;
    const text_y = center_y - 6;
    rl.drawText(value_text, toI32(text_x), toI32(text_y), 12, palette.COST.GLYPH_TEXT);
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

    // Action Camera reticle (keep this - it's functional, not debug)
    if (input_state.action_camera) {
        const screen_width = rl.getScreenWidth();
        const screen_height = rl.getScreenHeight();
        const center_x = @divTrunc(screen_width, 2);
        const center_y = @divTrunc(screen_height, 2);

        // Draw crosshair
        rl.drawLine(center_x - 10, center_y, center_x + 10, center_y, .white);
        rl.drawLine(center_x, center_y - 10, center_x, center_y + 10, .white);
        rl.drawCircleLines(center_x, center_y, 5, .white);
    }

    // Draw target frame
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
            drawTargetFrame(player, &tgt, 10, 10);
        }
    }

    // Draw party frames for all allies
    drawPartyFrames(entities, 10, 120);

    // Draw damage monitor (left side, below party frames)
    drawDamageMonitor(player, 10, 350);

    // Draw effects monitor (above skill bar - player's buffs/debuffs with sources)
    const screen_height = rl.getScreenHeight();
    drawEffectsMonitor(player, 400, @as(f32, @floatFromInt(screen_height)) - 200, input_state, selected_target);

    // Draw skill bar (and detect mouse hover)
    drawSkillBar(player, input_state);
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
    const bg_color = if (player.casting.cooldowns[index] > 0)
        palette.UI.SKILL_SLOT_COOLDOWN
    else
        palette.UI.SKILL_SLOT_READY;
    rl.drawRectangle(xi, yi, sizei, sizei, bg_color);

    // Draw border - highlight if currently casting this skill OR if inspected
    const is_casting_this = player.casting.state == .activating and player.casting.casting_skill_index == index;
    const is_inspected = if (input_state.inspected_skill_index) |idx| idx == index else false;
    const final_border = if (is_casting_this)
        palette.UI.BORDER_ACTIVE
    else if (is_inspected or is_hovered)
        palette.UI.BORDER_HOVER
    else
        palette.UI.TEXT_PRIMARY;
    rl.drawRectangleLines(xi, yi, sizei, sizei, final_border);

    // Draw skill icon (centered in slot) if available
    if (player.casting.skills[index]) |skill| {
        const icon_size: f32 = size * 0.8; // Icon takes 80% of slot (larger now, no text)
        const icon_x = x + (size - icon_size) / 2.0;
        const icon_y = y + (size - icon_size) / 2.0;

        // Check if player can afford this skill
        const can_afford = player.stats.energy >= skill.energy_cost;

        skill_icons.drawSkillIcon(icon_x, icon_y, icon_size, skill, player.school, player.player_position, can_afford);

        // Draw cooldown overlay (visual only, no text)
        if (player.casting.cooldowns[index] > 0) {
            const cooldown_total = @as(f32, @floatFromInt(skill.recharge_time_ms)) / 1000.0;
            const cooldown_progress = player.casting.cooldowns[index] / cooldown_total;
            const overlay_height = size * cooldown_progress;

            // Dark overlay showing cooldown progress (drains from top)
            rl.drawRectangle(xi, toI32(y + (size - overlay_height)), sizei, toI32(overlay_height), palette.UI.COOLDOWN_OVERLAY);
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
    const fill_percent = player.stats.warmth / player.stats.max_warmth;

    // Draw filled circle portion (bottom to top)
    // We'll draw the circle in red, then cover the top unfilled portion with black
    const health_color = palette.UI.HEALTH_BAR;

    // Draw full circle
    rl.drawCircle(center_xi, center_yi, radius - 2, health_color);

    // Cover the empty portion with a black rectangle from top
    if (fill_percent < 1.0) {
        const empty_height = (1.0 - fill_percent) * (radius * 2.0);
        const rect_y = center_y - radius;
        rl.drawRectangle(toI32(center_x - radius), toI32(rect_y), toI32(radius * 2.0), toI32(empty_height), palette.UI.EMPTY_BAR_BG);
    }

    // Redraw border to clean up edges
    rl.drawCircleLines(center_xi, center_yi, radius, .white);

    // Draw warmth text below orb
    var warmth_buf: [32]u8 = undefined;
    const warmth_text = std.fmt.bufPrintZ(
        &warmth_buf,
        "{d:.0}/{d:.0}",
        .{ player.stats.warmth, player.stats.max_warmth },
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

    // Calculate effective max energy (reduced by credit debt)
    const effective_max = player.stats.max_energy - player.school_resources.credit_debt.debt;

    // Calculate fill (based on current energy / effective max)
    const fill_percent = @as(f32, @floatFromInt(player.stats.energy)) / @as(f32, @floatFromInt(effective_max));
    const fill_width = (width - 4) * fill_percent;

    // Draw energy fill (blue)
    rl.drawRectangle(xi + 2, yi + 2, toI32(fill_width), heighti - 4, palette.UI.ENERGY_BAR);

    // Draw credit debt overlay (gray bar showing locked max energy)
    if (player.school_resources.credit_debt.debt > 0) {
        const debt_percent = @as(f32, @floatFromInt(player.school_resources.credit_debt.debt)) / @as(f32, @floatFromInt(player.stats.max_energy));
        const debt_start_x = width - 4 - ((width - 4) * debt_percent);
        const debt_width = (width - 4) * debt_percent;
        rl.drawRectangle(xi + 2 + toI32(debt_start_x), yi + 2, toI32(debt_width), heighti - 4, rl.Color{ .r = 80, .g = 80, .b = 80, .a = 200 });
    }

    // Draw energy text (show effective max, not absolute max)
    var energy_buf: [32]u8 = undefined;
    const energy_text = std.fmt.bufPrintZ(
        &energy_buf,
        "{d}/{d}",
        .{ player.stats.energy, effective_max },
    ) catch unreachable;

    const text_width = rl.measureText(energy_text, 10);
    rl.drawText(energy_text, toI32(x + width / 2.0) - @divTrunc(text_width, 2), yi + 2, 10, .white);
}

// Draw a proper MMO-style target frame
fn drawTargetFrame(player: *const Character, target: *const Character, x: f32, y: f32) void {
    const frame_width: f32 = 280;
    const frame_height: f32 = 110;
    const padding: f32 = 8;

    const xi = toI32(x);
    const yi = toI32(y);
    const frame_width_i = toI32(frame_width);
    const frame_height_i = toI32(frame_height);

    // Frame background
    rl.drawRectangle(xi, yi, frame_width_i, frame_height_i, palette.UI.BACKGROUND);
    rl.drawRectangleLines(xi, yi, frame_width_i, frame_height_i, palette.UI.BORDER);

    var current_y = y + padding;

    // Target name (use target color)
    rl.drawText(target.name, toI32(x + padding), toI32(current_y), 14, target.color);

    // Target type indicator
    const type_x = x + padding + @as(f32, @floatFromInt(rl.measureText(target.name, 14))) + 8;
    const type_text = if (player.isEnemy(target.*)) "Enemy" else "Ally";
    const type_color = if (player.isEnemy(target.*)) palette.UI.TEXT_SECONDARY else rl.Color.green;
    rl.drawText(type_text, toI32(type_x), toI32(current_y), 12, type_color);

    current_y += 20;

    // Warmth bar (health)
    const bar_width = frame_width - (padding * 2);
    const bar_height: f32 = 16;
    drawHealthBar(target.stats.warmth, target.stats.max_warmth, x + padding, current_y, bar_width, bar_height);
    current_y += bar_height + 4;

    // Energy bar
    drawResourceBar(@as(f32, @floatFromInt(target.stats.energy)), @as(f32, @floatFromInt(target.stats.max_energy)), x + padding, current_y, bar_width, 12, palette.UI.ENERGY_BAR);
    current_y += 12 + 4;

    // Cast bar (if casting) - GW1 style skill monitor
    if (target.casting.state == .activating) {
        const casting_skill = target.casting.skills[target.casting.casting_skill_index];
        if (casting_skill) |skill| {
            // Skill icon on left
            const icon_size: f32 = 24;
            skill_icons.drawSkillIcon(x + padding, current_y, icon_size, skill, target.school, target.player_position, true);

            // Cast bar next to icon
            const cast_bar_x = x + padding + icon_size + 4;
            const cast_bar_width = bar_width - icon_size - 4;
            const cast_time_total = @as(f32, @floatFromInt(skill.activation_time_ms)) / 1000.0;
            const progress = 1.0 - (target.casting.cast_time_remaining / cast_time_total);

            const cast_bar_xi = toI32(cast_bar_x);
            const cast_bar_yi = toI32(current_y + 4);

            // Border
            rl.drawRectangleLines(cast_bar_xi, cast_bar_yi, toI32(cast_bar_width), 16, palette.UI.BORDER);
            // Fill (green for activation)
            rl.drawRectangle(cast_bar_xi + 1, cast_bar_yi + 1, toI32((cast_bar_width - 2) * progress), 14, rl.Color.lime);

            // Skill name
            rl.drawText(skill.name, cast_bar_xi + 2, cast_bar_yi + 2, 10, .white);

            current_y += icon_size + 4;
        }
    } else {
        // Just show buffs/debuffs if not casting
        const icon_size: f32 = 16;
        const icon_spacing: f32 = 2;
        drawCompactConditions(target, x + padding, current_y, icon_size, icon_spacing);
    }
}

// Draw party frames for all allies (compact version showing health, name, school/position, conditions)
fn drawPartyFrames(entities: []const Character, x: f32, y: f32) void {
    const frame_width: f32 = 200;
    const frame_height: f32 = 50;
    const frame_spacing: f32 = 4;
    const padding: f32 = 5;

    var current_y = y;

    // Show all allies (first 4 entities are the ally team)
    for (entities[0..4]) |ally| {
        if (!ally.isAlive()) {
            current_y += frame_height + frame_spacing;
            continue;
        }

        const xi = toI32(x);
        const yi = toI32(current_y);
        const frame_width_i = toI32(frame_width);
        const frame_height_i = toI32(frame_height);

        // Frame background
        rl.drawRectangle(xi, yi, frame_width_i, frame_height_i, palette.UI.BACKGROUND);
        rl.drawRectangleLines(xi, yi, frame_width_i, frame_height_i, palette.UI.BORDER);

        var text_y = current_y + padding;

        // Name, abbreviated school/position
        rl.drawText(ally.name, toI32(x + padding), toI32(text_y), 11, ally.color);

        // Abbreviated school (first 3 letters) and position (first 3 letters)
        const school_name = @tagName(ally.school);
        const pos_name = @tagName(ally.player_position);
        var build_buf: [16]u8 = undefined;
        const build_text = std.fmt.bufPrintZ(
            &build_buf,
            "{s}/{s}",
            .{ school_name[0..@min(3, school_name.len)], pos_name[0..@min(3, pos_name.len)] },
        ) catch unreachable;

        const build_x = x + padding + @as(f32, @floatFromInt(rl.measureText(ally.name, 11))) + 6;
        rl.drawText(build_text, toI32(build_x), toI32(text_y), 9, palette.UI.TEXT_SECONDARY);

        text_y += 14;

        // Health bar
        const bar_width = frame_width - (padding * 2);
        const bar_height: f32 = 12;
        drawHealthBar(ally.stats.warmth, ally.stats.max_warmth, x + padding, text_y, bar_width, bar_height);
        text_y += bar_height + 3;

        // Compact conditions (single row)
        const icon_size: f32 = 14;
        const icon_spacing: f32 = 2;
        drawCompactConditions(&ally, x + padding, text_y, icon_size, icon_spacing);

        current_y += frame_height + frame_spacing;
    }
}

// Draw school-specific secondary mechanic
fn drawSchoolMechanic(player: *const Character, x: f32, y: f32, width: f32) void {
    _ = width; // May be used by some schools for sizing
    const yi = toI32(y);

    switch (player.school) {
        .public_school => {
            // Grit stacks (0-5) - show as filled circles
            const grit_text = "Grit:";
            rl.drawText(grit_text, toI32(x), yi, 9, palette.UI.TEXT_PRIMARY);

            const circle_size: f32 = 8;
            const circle_spacing: f32 = 3;
            var circle_x = x + @as(f32, @floatFromInt(rl.measureText(grit_text, 9))) + 4;

            for (0..character.MAX_GRIT_STACKS) |i| {
                const is_filled = i < player.school_resources.grit.stacks;
                const color = if (is_filled) rl.Color.gold else palette.UI.EMPTY_BAR_BG;
                rl.drawCircle(toI32(circle_x + circle_size / 2), yi + 5, circle_size / 2, color);
                rl.drawCircleLines(toI32(circle_x + circle_size / 2), yi + 5, circle_size / 2, palette.UI.BORDER);
                circle_x += circle_size + circle_spacing;
            }
        },
        .waldorf => {
            // Rhythm stacks (0-5) - show as filled musical note symbols
            const rhythm_text = "Rhythm:";
            rl.drawText(rhythm_text, toI32(x), yi, 9, palette.UI.TEXT_PRIMARY);

            const circle_size: f32 = 10;
            const circle_spacing: f32 = 3;
            var circle_x = x + @as(f32, @floatFromInt(rl.measureText(rhythm_text, 9))) + 4;

            // Show up to 5 rhythm stacks (max for our new design)
            const max_rhythm: u8 = 5; // Updated from 10 to match new design
            for (0..max_rhythm) |i| {
                const is_filled = i < player.school_resources.rhythm.charge;
                const color = if (is_filled) rl.Color.purple else palette.UI.EMPTY_BAR_BG;

                // Draw circle for musical note
                rl.drawCircle(toI32(circle_x + circle_size / 2), yi + 5, circle_size / 2, color);
                rl.drawCircleLines(toI32(circle_x + circle_size / 2), yi + 5, circle_size / 2, palette.UI.BORDER);

                circle_x += circle_size + circle_spacing;
            }

            // Show "Perfect!" text if at max rhythm
            if (player.school_resources.rhythm.charge >= max_rhythm) {
                rl.drawText("Perfect!", toI32(circle_x + 4), yi, 9, rl.Color.gold);
            }
        },
        .montessori => {
            // Show last 4 skill types used as icons
            rl.drawText("Variety:", toI32(x), yi, 9, palette.UI.TEXT_PRIMARY);

            var icon_x = x + @as(f32, @floatFromInt(rl.measureText("Variety:", 9))) + 4;
            const icon_size: f32 = 12;
            const icon_spacing: f32 = 2;

            // Draw last 4 skill types (from newest to oldest)
            var count: usize = 0;
            var i: usize = 0;
            while (i < character.MAX_RECENT_SKILLS and count < 4) : (i += 1) {
                const idx = if (player.school_resources.variety.buffer_index >= i)
                    player.school_resources.variety.buffer_index - @as(u8, @intCast(i))
                else
                    @as(u8, @intCast(character.MAX_RECENT_SKILLS)) - @as(u8, @intCast(i - player.school_resources.variety.buffer_index));

                if (player.school_resources.variety.recent_types[idx]) |skill_type| {
                    // Draw colored square for skill type
                    const type_color = switch (skill_type) {
                        .throw => rl.Color.red,
                        .trick => rl.Color.purple,
                        .stance => rl.Color.blue,
                        .call => rl.Color.green,
                        .gesture => rl.Color.orange,
                    };
                    rl.drawRectangle(toI32(icon_x), yi, toI32(icon_size), toI32(icon_size), type_color);
                    rl.drawRectangleLines(toI32(icon_x), yi, toI32(icon_size), toI32(icon_size), .white);

                    icon_x += icon_size + icon_spacing;
                    count += 1;
                }
            }
        },
        .homeschool => {
            // Sacrifice cooldown - show timer if on cooldown
            if (player.school_resources.sacrifice.cooldown > 0) {
                var text_buf: [32]u8 = undefined;
                const text = std.fmt.bufPrintZ(
                    &text_buf,
                    "Sacrifice: {d:.1}s",
                    .{player.school_resources.sacrifice.cooldown},
                ) catch unreachable;
                rl.drawText(text, toI32(x), yi, 9, rl.Color.orange);
            } else {
                rl.drawText("Sacrifice: Ready", toI32(x), yi, 9, rl.Color.green);
            }
        },
        .private_school => {
            // Show credit debt if in debt
            if (player.school_resources.credit_debt.debt > 0) {
                var text_buf: [32]u8 = undefined;
                const text = std.fmt.bufPrintZ(
                    &text_buf,
                    "Debt: {d} (-1/3s)",
                    .{player.school_resources.credit_debt.debt},
                ) catch unreachable;
                rl.drawText(text, toI32(x), yi, 9, rl.Color.red);
            } else {
                rl.drawText("Credit: Available", toI32(x), yi, 9, rl.Color.gold);
            }
        },
    }
}

// Helper: Draw health bar with text overlay
fn drawHealthBar(current: f32, max: f32, x: f32, y: f32, width: f32, height: f32) void {
    const xi = toI32(x);
    const yi = toI32(y);
    const widthi = toI32(width);
    const heighti = toI32(height);

    // Background
    rl.drawRectangle(xi, yi, widthi, heighti, palette.UI.EMPTY_BAR_BG);

    // Fill
    const fill_percent = current / max;
    const fill_width = (width - 2) * fill_percent;
    rl.drawRectangle(xi + 1, yi + 1, toI32(fill_width), heighti - 2, palette.UI.HEALTH_BAR);

    // Border
    rl.drawRectangleLines(xi, yi, widthi, heighti, palette.UI.BORDER);

    // Text (centered)
    var text_buf: [32]u8 = undefined;
    const text = std.fmt.bufPrintZ(
        &text_buf,
        "{d:.0}/{d:.0}",
        .{ current, max },
    ) catch unreachable;

    const text_width = rl.measureText(text, 10);
    rl.drawText(text, toI32(x + width / 2.0) - @divTrunc(text_width, 2), yi + 2, 10, .white);
}

// Helper: Draw resource bar (energy, etc) with text
fn drawResourceBar(current: f32, max: f32, x: f32, y: f32, width: f32, height: f32, color: rl.Color) void {
    const xi = toI32(x);
    const yi = toI32(y);
    const widthi = toI32(width);
    const heighti = toI32(height);

    // Background
    rl.drawRectangle(xi, yi, widthi, heighti, palette.UI.EMPTY_BAR_BG);

    // Fill
    const fill_percent = current / max;
    const fill_width = (width - 2) * fill_percent;
    rl.drawRectangle(xi + 1, yi + 1, toI32(fill_width), heighti - 2, color);

    // Border
    rl.drawRectangleLines(xi, yi, widthi, heighti, palette.UI.BORDER);

    // Text (centered)
    var text_buf: [32]u8 = undefined;
    const text = std.fmt.bufPrintZ(
        &text_buf,
        "{d:.0}/{d:.0}",
        .{ current, max },
    ) catch unreachable;

    const text_width = rl.measureText(text, 8);
    rl.drawText(text, toI32(x + width / 2.0) - @divTrunc(text_width, 2), yi + 1, 8, .white);
}

// Compact condition display (single row, for target/party frames)
fn drawCompactConditions(char: *const Character, x: f32, y: f32, icon_size: f32, spacing: f32) void {
    const yi = toI32(y);
    const sizei = toI32(icon_size);

    var current_x = x;

    // Draw buffs (cozies)
    for (char.conditions.cozies.cozies[0..char.conditions.cozies.count]) |maybe_cozy| {
        if (maybe_cozy) |cozy| {
            const xi = toI32(current_x);

            // Draw buff icon background
            rl.drawRectangle(xi, yi, sizei, sizei, palette.UI.BUFF_BG);
            rl.drawRectangleLines(xi, yi, sizei, sizei, palette.UI.BUFF_BORDER);

            // Draw first letter of buff name
            const name = @tagName(cozy.cozy);
            var letter_buf: [2]u8 = undefined;
            letter_buf[0] = std.ascii.toUpper(name[0]);
            letter_buf[1] = 0;
            rl.drawText(@ptrCast(&letter_buf), xi + 3, yi + 2, 10, .white);

            current_x += icon_size + spacing;
        }
    }

    // Draw debuffs (chills)
    for (char.conditions.chills.chills[0..char.conditions.chills.count]) |maybe_chill| {
        if (maybe_chill) |chill| {
            const xi = toI32(current_x);

            // Draw debuff icon background
            rl.drawRectangle(xi, yi, sizei, sizei, palette.UI.DEBUFF_BG);
            rl.drawRectangleLines(xi, yi, sizei, sizei, palette.UI.DEBUFF_BORDER);

            // Draw first letter of debuff name
            const name = @tagName(chill.chill);
            var letter_buf: [2]u8 = undefined;
            letter_buf[0] = std.ascii.toUpper(name[0]);
            letter_buf[1] = 0;
            rl.drawText(@ptrCast(&letter_buf), xi + 3, yi + 2, 10, .white);

            current_x += icon_size + spacing;
        }
    }
}

// Draw damage monitor (GW1-style recent damage sources)
fn drawDamageMonitor(player: *const Character, x: f32, y: f32) void {
    if (player.combat.damage_monitor.count == 0) return;

    const frame_width: f32 = 200;
    const icon_size: f32 = 32;
    const spacing: f32 = 4;
    const padding: f32 = 6;

    const frame_height = @as(f32, @floatFromInt(player.combat.damage_monitor.count)) * (icon_size + spacing) + (padding * 2);

    const xi = toI32(x);
    const yi = toI32(y);

    // Frame background
    rl.drawRectangle(xi, yi, toI32(frame_width), toI32(frame_height), palette.UI.BACKGROUND);
    rl.drawRectangleLines(xi, yi, toI32(frame_width), toI32(frame_height), palette.UI.BORDER);

    // Title
    rl.drawText("Recent Damage", xi + toI32(padding), yi + toI32(padding), 10, palette.UI.TEXT_SECONDARY);

    var current_y = y + padding + 14;

    // Draw damage sources (most recent at bottom, like GW1)
    for (player.combat.damage_monitor.sources[0..player.combat.damage_monitor.count]) |maybe_source| {
        if (maybe_source) |source| {
            const source_x = x + padding;

            // Skill icon
            if (source.skill_ptr) |skill| {
                skill_icons.drawSkillIcon(source_x, current_y, icon_size, skill, player.school, player.player_position, true);
            } else {
                // Fallback: draw colored square
                rl.drawRectangle(toI32(source_x), toI32(current_y), toI32(icon_size), toI32(icon_size), rl.Color.dark_gray);
                rl.drawRectangleLines(toI32(source_x), toI32(current_y), toI32(icon_size), toI32(icon_size), .white);
            }

            // Skill name
            rl.drawText(source.skill_name, toI32(source_x + icon_size + 4), toI32(current_y + 2), 10, .white);

            // Hit count (like "x66" in GW1 image)
            var count_buf: [16]u8 = undefined;
            const count_text = std.fmt.bufPrintZ(&count_buf, "x{d}", .{source.hit_count}) catch unreachable;
            rl.drawText(count_text, toI32(source_x + icon_size + 4), toI32(current_y + 14), 10, .yellow);

            current_y += icon_size + spacing;
        }
    }

    // "Frozen" indicator if dead
    if (player.combat.damage_monitor.frozen) {
        rl.drawText("(Frozen)", xi + toI32(padding), toI32(y + frame_height - 14), 9, rl.Color.sky_blue);
    }
}

// Draw effects monitor (player's buffs/debuffs above skill bar with sources - clickable)
fn drawEffectsMonitor(player: *const Character, x: f32, y: f32, input_state: *InputState, selected_target: ?EntityId) void {
    _ = input_state; // TODO: implement clicking
    _ = selected_target; // TODO: implement targeting source

    const icon_size: f32 = 28;
    const spacing: f32 = 3;

    var current_x = x;

    // Draw buffs (cozies) with source info
    for (player.conditions.cozies.cozies[0..player.conditions.cozies.count]) |maybe_cozy| {
        if (maybe_cozy) |cozy| {
            const xi = toI32(current_x);
            const yi = toI32(y);
            const sizei = toI32(icon_size);

            // Background
            rl.drawRectangle(xi, yi, sizei, sizei, palette.UI.BUFF_BG);
            rl.drawRectangleLines(xi, yi, sizei, sizei, palette.UI.BUFF_BORDER);

            // Icon letter
            const name = @tagName(cozy.cozy);
            var letter_buf: [2]u8 = undefined;
            letter_buf[0] = std.ascii.toUpper(name[0]);
            letter_buf[1] = 0;
            rl.drawText(@ptrCast(&letter_buf), xi + 8, yi + 8, 12, .white);

            // Time remaining (bar at bottom)
            const seconds = cozy.time_remaining_ms / 1000;
            var time_buf: [8]u8 = undefined;
            const time_text = std.fmt.bufPrintZ(&time_buf, "{d}", .{seconds}) catch unreachable;
            rl.drawText(time_text, xi + 2, toI32(y + icon_size - 10), 8, .white);

            current_x += icon_size + spacing;
        }
    }

    // Draw debuffs (chills)
    for (player.conditions.chills.chills[0..player.conditions.chills.count]) |maybe_chill| {
        if (maybe_chill) |chill| {
            const xi = toI32(current_x);
            const yi = toI32(y);
            const sizei = toI32(icon_size);

            // Background
            rl.drawRectangle(xi, yi, sizei, sizei, palette.UI.DEBUFF_BG);
            rl.drawRectangleLines(xi, yi, sizei, sizei, palette.UI.DEBUFF_BORDER);

            // Icon letter
            const name = @tagName(chill.chill);
            var letter_buf: [2]u8 = undefined;
            letter_buf[0] = std.ascii.toUpper(name[0]);
            letter_buf[1] = 0;
            rl.drawText(@ptrCast(&letter_buf), xi + 8, yi + 8, 12, .white);

            // Time remaining
            const seconds = chill.time_remaining_ms / 1000;
            var time_buf: [8]u8 = undefined;
            const time_text = std.fmt.bufPrintZ(&time_buf, "{d}", .{seconds}) catch unreachable;
            rl.drawText(time_text, xi + 2, toI32(y + icon_size - 10), 8, .white);

            current_x += icon_size + spacing;
        }
    }
}

fn drawConditionIcons(player: *const Character, x: f32, y: f32, icon_size: f32, spacing: f32) void {
    const yi = toI32(y);
    const sizei = toI32(icon_size);

    // Draw buffs (cozies) - first row
    var buff_x = x;
    for (player.conditions.cozies.cozies[0..player.conditions.cozies.count]) |maybe_cozy| {
        if (maybe_cozy) |cozy| {
            const buff_xi = toI32(buff_x);

            // Draw buff icon background
            rl.drawRectangle(buff_xi, yi, sizei, sizei, palette.UI.BUFF_BG);
            rl.drawRectangleLines(buff_xi, yi, sizei, sizei, palette.UI.BUFF_BORDER);

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

    for (player.conditions.chills.chills[0..player.conditions.chills.count]) |maybe_chill| {
        if (maybe_chill) |chill| {
            const debuff_xi = toI32(debuff_x);

            // Draw debuff icon background
            rl.drawRectangle(debuff_xi, debuff_yi, sizei, sizei, palette.UI.DEBUFF_BG);
            rl.drawRectangleLines(debuff_xi, debuff_yi, sizei, sizei, palette.UI.DEBUFF_BORDER);

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
    if (player.casting.state == .activating) {
        const casting_skill = player.casting.skills[player.casting.casting_skill_index];
        if (casting_skill) |skill| {
            const cast_time_total = @as(f32, @floatFromInt(skill.activation_time_ms)) / 1000.0;
            const progress = 1.0 - (player.casting.cast_time_remaining / cast_time_total);

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

    // Draw school-specific mechanic below energy bar
    const mechanic_y = energy_bar_y - 15;
    drawSchoolMechanic(player, skill_x, mechanic_y, energy_bar_width);

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
        if (player.casting.skills[idx]) |skill| {
            // Position tooltip above the skill bar, centered on screen
            const tooltip_x = (@as(f32, @floatFromInt(screen_width)) - 320) / 2.0;
            const tooltip_y = start_y - 260; // Above the skill bar
            drawSkillTooltip(skill.*, player.player_position, player.school, tooltip_x, tooltip_y);
        }
    }
}
