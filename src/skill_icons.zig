const std = @import("std");
const rl = @import("raylib");
const school_mod = @import("school.zig");
const position_mod = @import("position.zig");
const skills_mod = @import("skills.zig");
const palette = @import("color_palette.zig");

const School = school_mod.School;
const Position = position_mod.Position;
const Skill = skills_mod.Skill;
const SkillType = skills_mod.SkillType;

// Glyph archetypes - determines the primary shape
const GlyphArchetype = enum {
    diamond, // throw skills - aggressive, pointed
    circle, // trick skills - magical, flowing
    square, // stance skills - stable, grounded
    triangle_up, // call skills - projecting outward
    hexagon, // gesture skills - quick, efficient
};

// =============================================================================
// SDF (Signed Distance Field) Shape Functions
// Returns negative inside shape, positive outside, zero at edge
// =============================================================================

fn sdfDiamond(px: f32, py: f32, cx: f32, cy: f32, size: f32) f32 {
    // Diamond: |x| + |y| = size
    const dx = @abs(px - cx);
    const dy = @abs(py - cy);
    return (dx + dy) - size;
}

fn sdfCircle(px: f32, py: f32, cx: f32, cy: f32, radius: f32) f32 {
    const dx = px - cx;
    const dy = py - cy;
    return @sqrt(dx * dx + dy * dy) - radius;
}

fn sdfSquare(px: f32, py: f32, cx: f32, cy: f32, half_size: f32) f32 {
    // Square: max(|x|, |y|) = half_size
    const dx = @abs(px - cx);
    const dy = @abs(py - cy);
    return @max(dx, dy) - half_size;
}

fn sdfTriangleUp(px: f32, py: f32, cx: f32, cy: f32, size: f32) f32 {
    // Equilateral triangle pointing up
    const dx = px - cx;
    const dy = py - cy;

    // Triangle vertices at top, bottom-left, bottom-right
    // Using simplified SDF for equilateral triangle
    const k: f32 = @sqrt(3.0);
    var qx = @abs(dx) - size;
    const qy = dy + size / k;
    if (qx + k * qy > 0.0) {
        const new_x = (qx - k * qy) / 2.0;
        const new_y = (-k * qx - qy) / 2.0;
        qx = new_x;
        _ = new_y;
    }
    qx = qx - @min(@max(qx, -2.0 * size), 0.0);
    return -@sqrt(qx * qx + qy * qy) * std.math.sign(qy);
}

fn sdfHexagon(px: f32, py: f32, cx: f32, cy: f32, size: f32) f32 {
    // Regular hexagon
    const dx = @abs(px - cx);
    const dy = @abs(py - cy);
    const k: f32 = @sqrt(3.0) / 2.0;
    // Hexagon SDF
    const qx = dx;
    const qy = dy;
    return @max((qx * k + qy * 0.5), qy) - size;
}

fn sdfStar(px: f32, py: f32, cx: f32, cy: f32, outer_r: f32, points: u32) f32 {
    // Approximate star with multiple rotated triangles
    const dx = px - cx;
    const dy = py - cy;
    const angle = std.math.atan2(dy, dx);
    const dist = @sqrt(dx * dx + dy * dy);

    // Create star shape by modulating radius with angle
    const n = @as(f32, @floatFromInt(points));
    const mod_angle = @mod(angle + std.math.pi, std.math.pi * 2.0 / n) - std.math.pi / n;
    const star_factor = 0.5 + 0.5 * @cos(mod_angle * n);
    const inner_r = outer_r * 0.4;
    const target_r = inner_r + (outer_r - inner_r) * star_factor;

    return dist - target_r;
}

// =============================================================================
// Archetype Mapping & Zone Detection
// =============================================================================

// Map SkillType to glyph archetype
fn getArchetype(skill_type: SkillType) GlyphArchetype {
    return switch (skill_type) {
        .throw => .diamond, // Aggressive, pointed shapes for attacks
        .trick => .circle, // Magical, flowing shapes for spells
        .stance => .square, // Stable, grounded shapes for stances
        .call => .triangle_up, // Projecting outward for shouts
        .gesture => .hexagon, // Quick, efficient shapes for signets
    };
}

// Zone types for pixel classification
const PixelZone = enum {
    background,
    glyph_body,
    glyph_edge,
    accent,
    inner_detail,
};

// Get SDF value for a given archetype
fn getArchetypeSdf(archetype: GlyphArchetype, px: f32, py: f32, cx: f32, cy: f32, size: f32, rotation: f32) f32 {
    // Apply rotation around center
    const cos_r = @cos(rotation);
    const sin_r = @sin(rotation);
    const dx = px - cx;
    const dy = py - cy;
    const rpx = cx + dx * cos_r - dy * sin_r;
    const rpy = cy + dx * sin_r + dy * cos_r;

    return switch (archetype) {
        .diamond => sdfDiamond(rpx, rpy, cx, cy, size * 0.7),
        .circle => sdfCircle(rpx, rpy, cx, cy, size * 0.6),
        .square => sdfSquare(rpx, rpy, cx, cy, size * 0.55),
        .triangle_up => sdfTriangleUp(rpx, rpy, cx, cy, size * 0.6),
        .hexagon => sdfHexagon(rpx, rpy, cx, cy, size * 0.55),
    };
}

// Classify a pixel into a zone based on SDF distance
fn getPixelZone(sdf_dist: f32, size: f32) PixelZone {
    const edge_width = size * 0.08; // Edge thickness
    const accent_dist = size * 0.15; // Accent zone outside shape

    if (sdf_dist < -edge_width) {
        return .glyph_body; // Inside, away from edge
    } else if (sdf_dist < 0.0) {
        return .glyph_edge; // Inside, near edge (crisp)
    } else if (sdf_dist < accent_dist) {
        return .accent; // Just outside, for decorations
    } else {
        return .background;
    }
}

// Stipple pattern for accents - deterministic based on position and seed
fn stipplePattern(px: f32, py: f32, seed: u32, density: f32) bool {
    // Create a grid-based stipple with some randomization
    const grid_size: f32 = 3.0;
    const gx = @floor(px / grid_size);
    const gy = @floor(py / grid_size);

    // Hash grid position to get deterministic "random" value
    const grid_hash = @as(u32, @intFromFloat(@abs(gx * 73.0 + gy * 157.0))) ^ seed;
    const stipple_val = @as(f32, @floatFromInt(grid_hash % 100)) / 100.0;

    return stipple_val < density;
}

// Inner detail pattern - creates decorative marks inside the glyph
fn innerDetailPattern(px: f32, py: f32, cx: f32, cy: f32, seed: u32, detail_type: u32) bool {
    const dx = px - cx;
    const dy = py - cy;
    const dist = @sqrt(dx * dx + dy * dy);
    const angle = std.math.atan2(dy, dx);

    return switch (detail_type % 4) {
        0 => {
            // Radial lines
            const num_rays: f32 = 4.0 + @as(f32, @floatFromInt(seed % 4));
            const ray_angle = @mod(angle + std.math.pi, std.math.pi * 2.0 / num_rays);
            return ray_angle < 0.15 and dist > 2.0;
        },
        1 => {
            // Concentric ring
            const ring_dist = @mod(dist, 6.0);
            return ring_dist < 1.5 and dist > 4.0;
        },
        2 => {
            // Cross pattern
            return (@abs(dx) < 1.5 or @abs(dy) < 1.5) and dist > 3.0;
        },
        else => {
            // Dots at cardinal directions
            const dot_dist: f32 = 8.0;
            const d1 = @sqrt((dx - dot_dist) * (dx - dot_dist) + dy * dy);
            const d2 = @sqrt((dx + dot_dist) * (dx + dot_dist) + dy * dy);
            const d3 = @sqrt(dx * dx + (dy - dot_dist) * (dy - dot_dist));
            const d4 = @sqrt(dx * dx + (dy + dot_dist) * (dy + dot_dist));
            return d1 < 2.0 or d2 < 2.0 or d3 < 2.0 or d4 < 2.0;
        },
    };
}

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

// Get color for a school (MTG color pie inspired) - VERY SATURATED
pub fn getSchoolColor(school: School) rl.Color {
    return switch (school) {
        .private_school => palette.SCHOOL.PRIVATE,
        .public_school => palette.SCHOOL.PUBLIC,
        .montessori => palette.SCHOOL.MONTESSORI,
        .homeschool => palette.SCHOOL.HOMESCHOOL,
        .waldorf => palette.SCHOOL.WALDORF,
    };
}

// Get color for a position - VERY SATURATED AND DISTINCT
pub fn getPositionColor(position: Position) rl.Color {
    return switch (position) {
        .pitcher => palette.POSITION.PITCHER,
        .fielder => palette.POSITION.FIELDER,
        .sledder => palette.POSITION.SLEDDER,
        .shoveler => palette.POSITION.SHOVELER,
        .animator => palette.POSITION.ANIMATOR,
        .thermos => palette.POSITION.THERMOS,
    };
}

// Simple noise function for procedural variation
fn noise2d(px: f32, py: f32, seed_offset: f32) f32 {
    const sx = @sin(px * 12.9898 + py * 78.233 + seed_offset) * 43758.5453;
    return sx - @floor(sx);
}

// Apply noise to a color value (returns modified color channel)
fn applyNoise(base: u8, noise_val: f32, intensity: f32) u8 {
    const base_f = @as(f32, @floatFromInt(base));
    // Noise ranges -1 to 1, scaled by intensity
    const delta = (noise_val * 2.0 - 1.0) * intensity * 255.0;
    const result = @max(0.0, @min(255.0, base_f + delta));
    return @intFromFloat(result);
}

// =============================================================================
// HYBRID GLYPH ICON - Combines structured shapes with textured noise fills
// =============================================================================

pub fn drawHybridGlyphIcon(
    x: f32,
    y: f32,
    size: f32,
    skill_name: []const u8,
    skill_type: SkillType,
    base_color: rl.Color,
) void {
    const seed = hashString(skill_name);
    const archetype = getArchetype(skill_type);

    // Generate variation parameters from hash
    const rotation = getHashFloat(seed, 0) * std.math.pi * 0.5; // 0-90 degree rotation
    const noise_seed = getHashFloat(seed, 1) * 1000.0;
    const stipple_density = 0.2 + getHashFloat(seed, 2) * 0.3; // 0.2-0.5 density
    const detail_type = seed % 4;
    const gradient_angle = getHashFloat(seed, 3) * std.math.pi * 2.0;

    // Create color palette from base color
    const dark_color = rl.Color{
        .r = @intFromFloat(@as(f32, @floatFromInt(base_color.r)) * 0.25),
        .g = @intFromFloat(@as(f32, @floatFromInt(base_color.g)) * 0.25),
        .b = @intFromFloat(@as(f32, @floatFromInt(base_color.b)) * 0.25),
        .a = 255,
    };

    const mid_color = rl.Color{
        .r = @intFromFloat(@as(f32, @floatFromInt(base_color.r)) * 0.7),
        .g = @intFromFloat(@as(f32, @floatFromInt(base_color.g)) * 0.7),
        .b = @intFromFloat(@as(f32, @floatFromInt(base_color.b)) * 0.7),
        .a = 255,
    };

    const light_color = rl.Color{
        .r = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(base_color.r)) + 60.0)),
        .g = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(base_color.g)) + 60.0)),
        .b = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(base_color.b)) + 60.0)),
        .a = 255,
    };

    const accent_color = rl.Color{
        .r = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(base_color.r)) * 0.5 + 80.0)),
        .g = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(base_color.g)) * 0.5 + 80.0)),
        .b = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(base_color.b)) * 0.5 + 80.0)),
        .a = 255,
    };

    // Center of icon
    const cx = x + size / 2.0;
    const cy = y + size / 2.0;
    const half_size = size / 2.0;

    // Gradient direction
    const grad_dx = @cos(gradient_angle);
    const grad_dy = @sin(gradient_angle);

    // Draw pixel by pixel
    const xi = @as(i32, @intFromFloat(x));
    const yi = @as(i32, @intFromFloat(y));
    const sizei = @as(i32, @intFromFloat(size));

    var py: i32 = 0;
    while (py < sizei) : (py += 1) {
        var px: i32 = 0;
        while (px < sizei) : (px += 1) {
            const pixel_x = x + @as(f32, @floatFromInt(px));
            const pixel_y = y + @as(f32, @floatFromInt(py));

            // Get SDF distance for this pixel
            const sdf_dist = getArchetypeSdf(archetype, pixel_x, pixel_y, cx, cy, half_size, rotation);

            // Classify pixel zone
            const zone = getPixelZone(sdf_dist, size);

            // Calculate base noise for this pixel
            const noise_val = noise2d(pixel_x * 0.3, pixel_y * 0.3, noise_seed);

            // Calculate gradient value for directional shading
            const nx = (pixel_x - cx) / half_size;
            const ny = (pixel_y - cy) / half_size;
            const grad_t = (nx * grad_dx + ny * grad_dy + 1.0) / 2.0;

            var final_color: rl.Color = undefined;

            switch (zone) {
                .background => {
                    // Dark background with very subtle grain
                    final_color = rl.Color{
                        .r = applyNoise(dark_color.r, noise_val, 0.08),
                        .g = applyNoise(dark_color.g, noise_val, 0.08),
                        .b = applyNoise(dark_color.b, noise_val, 0.08),
                        .a = 255,
                    };
                },
                .accent => {
                    // Stippled accent zone
                    if (stipplePattern(pixel_x, pixel_y, seed, stipple_density)) {
                        final_color = accent_color;
                    } else {
                        // Background with subtle grain
                        final_color = rl.Color{
                            .r = applyNoise(dark_color.r, noise_val, 0.08),
                            .g = applyNoise(dark_color.g, noise_val, 0.08),
                            .b = applyNoise(dark_color.b, noise_val, 0.08),
                            .a = 255,
                        };
                    }
                },
                .glyph_edge => {
                    // Crisp edge - bright, minimal noise for readability
                    final_color = light_color;
                },
                .glyph_body => {
                    // Textured fill with gradient
                    const base_grad_color = lerpColor(mid_color, light_color, grad_t);

                    // Check for inner detail pattern
                    if (innerDetailPattern(pixel_x, pixel_y, cx, cy, seed, detail_type)) {
                        // Inner detail uses contrasting color
                        final_color = lerpColor(dark_color, mid_color, 0.5);
                    } else {
                        // Apply medium grain to body
                        final_color = rl.Color{
                            .r = applyNoise(base_grad_color.r, noise_val, 0.15),
                            .g = applyNoise(base_grad_color.g, noise_val, 0.15),
                            .b = applyNoise(base_grad_color.b, noise_val, 0.15),
                            .a = 255,
                        };
                    }
                },
                .inner_detail => {
                    // Shouldn't reach here, handled in glyph_body
                    final_color = dark_color;
                },
            }

            rl.drawPixel(xi + px, yi + py, final_color);
        }
    }

    // Draw border
    rl.drawRectangleLines(xi, yi, sizei, sizei, rl.Color.white);
}

// Draw icon for a skill based on its name (hybrid glyph generation)
pub fn drawSkillIcon(x: f32, y: f32, size: f32, skill: *const Skill, school: School, position: Position, can_afford: bool) void {
    // Check if skill is from position pool - compare by NAME not pointer
    const position_skills = position.getSkills();
    var is_position_skill = false;

    for (position_skills) |*pos_skill| {
        if (std.mem.eql(u8, pos_skill.name, skill.name)) {
            is_position_skill = true;
            break;
        }
    }

    // Check if skill is from school pool - compare by NAME not pointer
    const school_skills = school.getSkills();
    var is_school_skill = false;

    for (school_skills) |*school_skill| {
        if (std.mem.eql(u8, school_skill.name, skill.name)) {
            is_school_skill = true;
            break;
        }
    }

    // Choose base color based on source (position or school)
    var base_color = if (is_position_skill) blk: {
        // Position skills (slots 1-4): use position color
        break :blk getPositionColor(position);
    } else if (is_school_skill) blk: {
        // School skills (slots 5-8): use school color
        break :blk getSchoolColor(school);
    } else blk: {
        // Fallback (shouldn't happen): gray
        break :blk palette.POSITION.FALLBACK;
    };

    // Dim the color if player can't afford the skill
    if (!can_afford) {
        base_color.r = @intFromFloat(@as(f32, @floatFromInt(base_color.r)) * 0.3);
        base_color.g = @intFromFloat(@as(f32, @floatFromInt(base_color.g)) * 0.3);
        base_color.b = @intFromFloat(@as(f32, @floatFromInt(base_color.b)) * 0.3);
    }

    // Generate hybrid glyph icon from skill name and type
    drawHybridGlyphIcon(x, y, size, skill.name, skill.skill_type, base_color);
}
