const std = @import("std");
const rl = @import("raylib");
const school_mod = @import("school.zig");
const position_mod = @import("position.zig");
const skills_mod = @import("skills.zig");

const School = school_mod.School;
const Position = position_mod.Position;
const Skill = skills_mod.Skill;

// Hash a string to get a seed for procedural generation
fn hashString(s: []const u8) u32 {
    var hash: u32 = 2166136261; // FNV-1a offset basis
    for (s) |byte| {
        hash ^= byte;
        hash = hash *% 16777619; // FNV-1a prime
    }
    return hash;
}

// Get a pseudo-random value from 0.0 to 1.0 based on seed and index
fn getHashFloat(seed: u32, index: u32) f32 {
    const combined = seed *% 2654435761 +% index *% 2246822519;
    return @as(f32, @floatFromInt(combined % 10000)) / 10000.0;
}

// Interpolate between two colors
fn lerpColor(a: rl.Color, b: rl.Color, t: f32) rl.Color {
    const t_clamped = @max(0.0, @min(1.0, t));
    return rl.Color{
        .r = @intFromFloat(@as(f32, @floatFromInt(a.r)) * (1.0 - t_clamped) + @as(f32, @floatFromInt(b.r)) * t_clamped),
        .g = @intFromFloat(@as(f32, @floatFromInt(a.g)) * (1.0 - t_clamped) + @as(f32, @floatFromInt(b.g)) * t_clamped),
        .b = @intFromFloat(@as(f32, @floatFromInt(a.b)) * (1.0 - t_clamped) + @as(f32, @floatFromInt(b.b)) * t_clamped),
        .a = 255,
    };
}

// Get color for a school (MTG color pie inspired)
pub fn getSchoolColor(school: School) rl.Color {
    return switch (school) {
        .private_school => rl.Color{ .r = 255, .g = 245, .b = 200, .a = 255 }, // White/Gold
        .public_school => rl.Color{ .r = 255, .g = 80, .b = 80, .a = 255 }, // Red
        .montessori => rl.Color{ .r = 80, .g = 200, .b = 80, .a = 255 }, // Green
        .homeschool => rl.Color{ .r = 120, .g = 80, .b = 160, .a = 255 }, // Purple/Black
        .waldorf => rl.Color{ .r = 100, .g = 150, .b = 255, .a = 255 }, // Blue
    };
}

// Get color for a position (lighter variants)
pub fn getPositionColor(position: Position) rl.Color {
    return switch (position) {
        .pitcher => rl.Color{ .r = 255, .g = 200, .b = 100, .a = 255 }, // Orange
        .fielder => rl.Color{ .r = 200, .g = 200, .b = 200, .a = 255 }, // Gray
        .sledder => rl.Color{ .r = 255, .g = 100, .b = 255, .a = 255 }, // Pink
        .shoveler => rl.Color{ .r = 150, .g = 150, .b = 255, .a = 255 }, // Light Blue
        .animator => rl.Color{ .r = 200, .g = 255, .b = 100, .a = 255 }, // Yellow-Green
        .thermos => rl.Color{ .r = 255, .g = 150, .b = 150, .a = 255 }, // Light Red
    };
}

// Draw a procedurally generated icon based on skill name hash
pub fn drawProceduralIcon(x: f32, y: f32, size: f32, skill_name: []const u8, base_color: rl.Color) void {
    const seed = hashString(skill_name);

    // Generate color variations based on seed
    const color_var1 = getHashFloat(seed, 0);
    const color_var2 = getHashFloat(seed, 1);

    // Create darker and lighter versions with MORE variation
    const dark_factor = 0.1 + color_var1 * 0.4; // 0.1-0.5 (darker range)
    const light_factor = 0.5 + color_var2 * 0.5; // 0.5-1.0 (much brighter)

    const dark_color = rl.Color{
        .r = @intFromFloat(@as(f32, @floatFromInt(base_color.r)) * dark_factor),
        .g = @intFromFloat(@as(f32, @floatFromInt(base_color.g)) * dark_factor),
        .b = @intFromFloat(@as(f32, @floatFromInt(base_color.b)) * dark_factor),
        .a = 255,
    };

    const light_color = rl.Color{
        .r = @min(255, @as(u8, @intFromFloat(@as(f32, @floatFromInt(base_color.r)) + (255.0 - @as(f32, @floatFromInt(base_color.r))) * light_factor))),
        .g = @min(255, @as(u8, @intFromFloat(@as(f32, @floatFromInt(base_color.g)) + (255.0 - @as(f32, @floatFromInt(base_color.g))) * light_factor))),
        .b = @min(255, @as(u8, @intFromFloat(@as(f32, @floatFromInt(base_color.b)) + (255.0 - @as(f32, @floatFromInt(base_color.b))) * light_factor))),
        .a = 255,
    };

    // Generate gradient parameters from hash - make them more extreme for visibility
    const gradient_angle = getHashFloat(seed, 3) * std.math.pi * 2.0; // 0-360 degrees
    const wave_freq = 1.0 + getHashFloat(seed, 4) * 10.0; // 1-11 waves (more range)
    const wave_amp = 0.2 + getHashFloat(seed, 5) * 0.6; // 0.2-0.8 amplitude (stronger)
    const noise_scale = 0.3 + getHashFloat(seed, 6) * 3.0; // 0.3-3.3 noise scale (more range)
    const gradient_offset = getHashFloat(seed, 7) * 0.8 - 0.4; // -0.4 to 0.4 (can shift either way)

    // Draw the unique procedural gradient
    drawUniqueGradient(x, y, size, dark_color, base_color, light_color, gradient_angle, wave_freq, wave_amp, noise_scale, gradient_offset);

    // Draw white border
    const xi = @as(i32, @intFromFloat(x));
    const yi = @as(i32, @intFromFloat(y));
    const sizei = @as(i32, @intFromFloat(size));
    rl.drawRectangleLines(xi, yi, sizei, sizei, rl.Color.white);
}

// Simple noise function for procedural variation
fn noise2d(px: f32, py: f32, seed_offset: f32) f32 {
    const sx = @sin(px * 12.9898 + py * 78.233 + seed_offset) * 43758.5453;
    return sx - @floor(sx);
}

// Draw a unique procedural gradient for each skill
fn drawUniqueGradient(
    x: f32,
    y: f32,
    size: f32,
    dark: rl.Color,
    mid: rl.Color,
    light: rl.Color,
    angle: f32,
    wave_freq: f32,
    wave_amp: f32,
    noise_scale: f32,
    offset: f32,
) void {
    // Draw with scanlines for better performance
    const xi = @as(i32, @intFromFloat(x));
    const yi = @as(i32, @intFromFloat(y));
    const sizei = @as(i32, @intFromFloat(size));

    // Pre-calculate direction vector for gradient
    const dx = @cos(angle);
    const dy = @sin(angle);

    // Draw horizontal scanlines
    var py: i32 = 0;
    while (py < sizei) : (py += 1) {
        const ny = (@as(f32, @floatFromInt(py)) / size - 0.5) * 2.0;

        var px: i32 = 0;
        while (px < sizei) : (px += 1) {
            const nx = (@as(f32, @floatFromInt(px)) / size - 0.5) * 2.0;

            // Calculate gradient value along the angle direction
            var grad_value = (nx * dx + ny * dy + 1.0) / 2.0; // 0 to 1

            // Add wave distortion for uniqueness (stronger effect)
            const wave_dist = @sin((nx * wave_freq + ny * wave_freq) * std.math.pi) * wave_amp;
            grad_value += wave_dist;

            // Add noise for texture (stronger)
            const noise_val = noise2d(nx * noise_scale, ny * noise_scale, angle) * 0.5;
            grad_value += noise_val;

            // Apply offset for variation
            grad_value += offset;

            // Clamp to 0-1
            grad_value = @max(0.0, @min(1.0, grad_value));

            // Choose color based on gradient value (3 color stops)
            const color = if (grad_value < 0.33)
                lerpColor(dark, mid, grad_value * 3.0)
            else if (grad_value < 0.67)
                lerpColor(mid, light, (grad_value - 0.33) * 3.0)
            else
                light;

            rl.drawPixel(xi + px, yi + py, color);
        }
    }
}

// Draw icon for a skill based on its name (procedural generation)
pub fn drawSkillIcon(x: f32, y: f32, size: f32, skill: *const Skill, school: School, position: Position) void {
    // Determine if skill is from position or generic pool
    const position_skills = position.getSkills();
    var is_position_skill = false;

    for (position_skills) |pos_skill| {
        if (&pos_skill == skill) {
            is_position_skill = true;
            break;
        }
    }

    // Choose base color based on source
    const base_color = if (is_position_skill) blk: {
        // Position skills: blend school and position colors
        const school_color = getSchoolColor(school);
        const pos_color = getPositionColor(position);
        break :blk lerpColor(school_color, pos_color, 0.5);
    } else blk: {
        // Generic skills: use school color (not gray!)
        break :blk getSchoolColor(school);
    };

    // Generate procedural icon from skill name
    drawProceduralIcon(x, y, size, skill.name, base_color);
}
