const std = @import("std");
const rl = @import("raylib");
const entity = @import("entity.zig");

const Entity = entity.Entity;

pub fn drawUI(player: Entity, entities: []const Entity, selected_target: ?usize, shift_held: bool, camera: rl.Camera) void {
    // Debug info
    const shift_text = if (shift_held) "Shift Held: true" else "Shift Held: false";
    rl.drawText(shift_text, 10, 10, 16, .yellow);

    if (selected_target) |_| {
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
    if (selected_target) |target_index| {
        const target = entities[target_index];
        rl.drawText("Current Target:", 10, 230, 18, .white);
        // TODO: Fix target.name drawing - string issue
        rl.drawText("Target Name", 10, 250, 16, target.color);

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
    for (entities) |ent| {
        const health_percentage = ent.health / ent.max_health;
        const health_bar_width = 40;
        const health_bar_height = 4;

        // Convert 3D position to 2D screen coordinates
        const screen_pos = rl.getWorldToScreen(ent.position, camera);

        // Only draw if on screen and valid coordinates
        const screen_width = @as(f32, @floatFromInt(rl.getScreenWidth()));
        const screen_height = @as(f32, @floatFromInt(rl.getScreenHeight()));
        if (screen_pos.x >= 0 and screen_pos.x < screen_width and
            screen_pos.y >= 0 and screen_pos.y < screen_height and
            std.math.isFinite(screen_pos.x) and std.math.isFinite(screen_pos.y))
        {
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
                if (ent.is_enemy) .red else .green,
            );
        }
    }

    // Draw skill bar
    drawSkillBar(player);
}

fn drawSkillBar(player: Entity) void {
    const skill_bar_width = 400;
    const skill_bar_height = 50;
    const skill_size = 40;
    const skill_spacing = 5;
    const start_x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2.0 - @as(f32, @floatFromInt(skill_bar_width)) / 2.0;
    const start_y = @as(f32, @floatFromInt(rl.getScreenHeight())) - 80.0;

    // Draw skill bar background
    rl.drawRectangle(@intFromFloat(start_x - 5), @intFromFloat(start_y - 5), @intFromFloat(skill_bar_width + 10), @intFromFloat(skill_bar_height + 10), .black);

    for (player.skill_bar, 0..) |maybe_skill, i| {
        const skill_x = start_x + @as(f32, @floatFromInt(i)) * (skill_size + skill_spacing);
        const skill_y = start_y;

        // Draw skill slot
        const slot_color: rl.Color = if (i == player.selected_skill) .yellow else .dark_gray;
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

    // Primary resource bar (Universal Energy)
    const resource_name = switch (player.background) {
        .private_school => "Allowance",
        .public_school => "Grit",
        .montessori => "Focus",
        .homeschool => "Life Force",
        .waldorf => "Rhythm",
    };
    rl.drawText(resource_name, @intFromFloat(start_x), @intFromFloat(resource_y), 16, .white);
    rl.drawRectangle(@intFromFloat(start_x + 80), @intFromFloat(resource_y), 100, 16, .black);
    rl.drawRectangle(@intFromFloat(start_x + 80), @intFromFloat(resource_y), @intFromFloat(@as(f32, @floatFromInt(player.energy)) / @as(f32, @floatFromInt(player.max_energy)) * 100), 16, .blue);
    var energy_buf: [16]u8 = undefined;
    const energy_text = std.fmt.bufPrintZ(&energy_buf, "{d}/{d}", .{ player.energy, player.max_energy }) catch "?";
    rl.drawText(energy_text, @intFromFloat(start_x + 185), @intFromFloat(resource_y), 14, .white);

    // Secondary mechanic display
    const secondary_y = resource_y + 20;
    const secondary_name = switch (player.background) {
        .private_school => "Steady Income",
        .public_school => "Grit Stacks",
        .montessori => "Variety Bonus",
        .homeschool => "Sacrifice",
        .waldorf => "Perfect Timing",
    };
    rl.drawText(secondary_name, @intFromFloat(start_x), @intFromFloat(secondary_y), 12, .light_gray);

    // Display background-specific secondary state
    switch (player.background) {
        .private_school => {
            const regen = player.background.getEnergyRegen();
            var regen_buf: [32]u8 = undefined;
            const regen_text = std.fmt.bufPrintZ(&regen_buf, "+{d:.1}/sec", .{regen}) catch "?";
            rl.drawText(regen_text, @intFromFloat(start_x + 110), @intFromFloat(secondary_y), 12, .green);
        },
        .public_school => {
            var grit_buf: [16]u8 = undefined;
            const grit_text = std.fmt.bufPrintZ(&grit_buf, "{d}/{d}", .{ player.grit_stacks, player.max_grit_stacks }) catch "?";
            rl.drawText(grit_text, @intFromFloat(start_x + 110), @intFromFloat(secondary_y), 12, .red);
        },
        .montessori => {
            var variety_buf: [16]u8 = undefined;
            const variety_pct = @as(u8, @intFromFloat(player.variety_bonus_damage * 100));
            const variety_text = std.fmt.bufPrintZ(&variety_buf, "+{d}% dmg", .{variety_pct}) catch "?";
            rl.drawText(variety_text, @intFromFloat(start_x + 110), @intFromFloat(secondary_y), 12, .orange);
        },
        .homeschool => {
            if (player.sacrifice_cooldown > 0) {
                var cd_buf: [16]u8 = undefined;
                const cd_text = std.fmt.bufPrintZ(&cd_buf, "CD: {d:.1}s", .{player.sacrifice_cooldown}) catch "?";
                rl.drawText(cd_text, @intFromFloat(start_x + 110), @intFromFloat(secondary_y), 12, .gray);
            } else {
                rl.drawText("Ready!", @intFromFloat(start_x + 110), @intFromFloat(secondary_y), 12, .green);
            }
        },
        .waldorf => {
            var rhythm_buf: [16]u8 = undefined;
            const rhythm_text = std.fmt.bufPrintZ(&rhythm_buf, "{d}/{d}", .{ player.rhythm_charge, player.max_rhythm_charge }) catch "?";
            rl.drawText(rhythm_text, @intFromFloat(start_x + 110), @intFromFloat(secondary_y), 12, .purple);
        },
    }

    // Draw background info
    const background_name = @tagName(player.background);
    rl.drawText(background_name, 10, @intFromFloat(secondary_y + 20), 12, .light_gray);
}
