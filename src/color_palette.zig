// Color palette for consistent UI/VFX styling
// Centralizes all color definitions for easy tweaking and theming
const rl = @import("raylib");

// UI Colors
pub const UI = struct {
    pub const BACKGROUND = rl.Color{ .r = 20, .g = 20, .b = 25, .a = 250 };
    pub const BORDER = rl.Color{ .r = 200, .g = 180, .b = 100, .a = 255 };
    pub const BORDER_ACTIVE = rl.Color.orange;
    pub const BORDER_HOVER = rl.Color.yellow;
    pub const TEXT_PRIMARY = rl.Color.white;
    pub const TEXT_SECONDARY = rl.Color{ .r = 180, .g = 180, .b = 180, .a = 255 };
    pub const TEXT_DISABLED = rl.Color{ .r = 150, .g = 150, .b = 150, .a = 255 };
    pub const SEPARATOR_LINE = rl.Color{ .r = 100, .g = 100, .b = 100, .a = 255 };

    pub const SKILL_SLOT_READY = rl.Color{ .r = 0, .g = 0, .b = 0, .a = 100 };
    pub const SKILL_SLOT_COOLDOWN = rl.Color{ .r = 40, .g = 40, .b = 40, .a = 200 };
    pub const COOLDOWN_OVERLAY = rl.Color{ .r = 0, .g = 0, .b = 0, .a = 180 };

    pub const CASTING_BAR = rl.Color.yellow;
    pub const HEALTH_BAR = rl.Color{ .r = 200, .g = 0, .b = 0, .a = 255 };
    pub const ENERGY_BAR = rl.Color{ .r = 0, .g = 100, .b = 255, .a = 255 };
    pub const EMPTY_BAR_BG = rl.Color{ .r = 0, .g = 0, .b = 0, .a = 255 };

    pub const BUFF_BG = rl.Color{ .r = 0, .g = 100, .b = 0, .a = 200 };
    pub const BUFF_BORDER = rl.Color.green;
    pub const DEBUFF_BG = rl.Color{ .r = 100, .g = 0, .b = 0, .a = 200 };
    pub const DEBUFF_BORDER = rl.Color.red;
};

// Team/Entity Colors
pub const TEAM = struct {
    pub const ALLY = rl.Color.blue;
    pub const ENEMY = rl.Color.red;
    pub const PLAYER = rl.Color.lime;
    pub const DEAD = rl.Color.gray;
    pub const SELECTION = rl.Color.yellow;
};

// Outline Colors (for ally/enemy distinction - doesn't collide with school/position)
pub const OUTLINE = struct {
    pub const ALLY = rl.Color{ .r = 0, .g = 255, .b = 0, .a = 255 }; // Green
    pub const ENEMY = rl.Color{ .r = 255, .g = 0, .b = 0, .a = 255 }; // Red
    pub const PLAYER = rl.Color{ .r = 0, .g = 255, .b = 0, .a = 255 }; // Green (player is ally)
};

// Visual Effects Colors
pub const VFX = struct {
    pub const DAMAGE_TEXT = rl.Color.red;
    pub const HEAL_TEXT = rl.Color.lime;
    pub const MISS_TEXT = rl.Color.gray;
    pub const TEXT_OUTLINE = rl.Color.black;

    pub const PROJECTILE_ALLY = rl.Color.sky_blue;
    pub const PROJECTILE_ENEMY = rl.Color.red;
    pub const PROJECTILE_AUTO_ALLY = rl.Color.white;
    pub const PROJECTILE_AUTO_ENEMY = rl.Color.orange;

    pub const IMPACT_DEFAULT = rl.Color.red;
    pub const HEAL_PARTICLE = rl.Color.lime;
};

// Cost Glyph Colors (for skill tooltips)
pub const COST = struct {
    pub const RECHARGE = rl.Color{ .r = 100, .g = 100, .b = 255, .a = 255 };
    pub const ACTIVATION = rl.Color{ .r = 255, .g = 200, .b = 100, .a = 255 };
    pub const ENERGY = rl.Color{ .r = 100, .g = 200, .b = 255, .a = 255 };
    pub const GLYPH_TEXT = rl.Color.black;
    pub const GLYPH_BORDER = rl.Color.white;
};

// Skill Icon Colors (for procedural generation)
pub const SCHOOL = struct {
    pub const PRIVATE = rl.Color{ .r = 255, .g = 220, .b = 100, .a = 255 }; // Bright Gold
    pub const PUBLIC = rl.Color{ .r = 255, .g = 50, .b = 50, .a = 255 }; // Bright Red
    pub const MONTESSORI = rl.Color{ .r = 50, .g = 220, .b = 50, .a = 255 }; // Bright Green
    pub const HOMESCHOOL = rl.Color{ .r = 180, .g = 80, .b = 220, .a = 255 }; // Bright Purple
    pub const WALDORF = rl.Color{ .r = 80, .g = 150, .b = 255, .a = 255 }; // Bright Blue
};

pub const POSITION = struct {
    pub const PITCHER = rl.Color{ .r = 255, .g = 140, .b = 0, .a = 255 }; // Bright Orange
    pub const FIELDER = rl.Color{ .r = 180, .g = 180, .b = 180, .a = 255 }; // Light Gray
    pub const SLEDDER = rl.Color{ .r = 255, .g = 50, .b = 200, .a = 255 }; // Hot Pink
    pub const SHOVELER = rl.Color{ .r = 100, .g = 200, .b = 255, .a = 255 }; // Cyan
    pub const ANIMATOR = rl.Color{ .r = 180, .g = 255, .b = 50, .a = 255 }; // Lime Green
    pub const THERMOS = rl.Color{ .r = 255, .g = 100, .b = 100, .a = 255 }; // Salmon/Pink
    pub const FALLBACK = rl.Color{ .r = 150, .g = 150, .b = 150, .a = 255 }; // Gray fallback
};

// Debug/Development Colors
pub const DEBUG = struct {
    pub const INFO = rl.Color.yellow;
    pub const WARNING = rl.Color.orange;
    pub const ERROR = rl.Color.red;
    pub const SUCCESS = rl.Color.lime;
};

// Helper functions for color manipulation
pub fn getSchoolColor(school: @import("school.zig").School) rl.Color {
    return switch (school) {
        .private_school => SCHOOL.PRIVATE,
        .public_school => SCHOOL.PUBLIC,
        .montessori => SCHOOL.MONTESSORI,
        .homeschool => SCHOOL.HOMESCHOOL,
        .waldorf => SCHOOL.WALDORF,
    };
}

pub fn getPositionColor(position: @import("position.zig").Position) rl.Color {
    return switch (position) {
        .pitcher => POSITION.PITCHER,
        .fielder => POSITION.FIELDER,
        .sledder => POSITION.SLEDDER,
        .shoveler => POSITION.SHOVELER,
        .animator => POSITION.ANIMATOR,
        .thermos => POSITION.THERMOS,
    };
}

/// Mix two colors with a gradient ratio (0.0 = all color1, 1.0 = all color2)
pub fn mixColors(color1: rl.Color, color2: rl.Color, ratio: f32) rl.Color {
    const t = @max(0.0, @min(1.0, ratio));
    return rl.Color{
        .r = @intFromFloat(@as(f32, @floatFromInt(color1.r)) * (1.0 - t) + @as(f32, @floatFromInt(color2.r)) * t),
        .g = @intFromFloat(@as(f32, @floatFromInt(color1.g)) * (1.0 - t) + @as(f32, @floatFromInt(color2.g)) * t),
        .b = @intFromFloat(@as(f32, @floatFromInt(color1.b)) * (1.0 - t) + @as(f32, @floatFromInt(color2.b)) * t),
        .a = @intFromFloat(@as(f32, @floatFromInt(color1.a)) * (1.0 - t) + @as(f32, @floatFromInt(color2.a)) * t),
    };
}

/// Create a halftone/dithered mix of two colors
/// Uses a 50/50 average to create a unified halftone appearance
pub fn halftoneColors(color1: rl.Color, color2: rl.Color) rl.Color {
    return rl.Color{
        .r = @intFromFloat((@as(f32, @floatFromInt(color1.r)) + @as(f32, @floatFromInt(color2.r))) / 2.0),
        .g = @intFromFloat((@as(f32, @floatFromInt(color1.g)) + @as(f32, @floatFromInt(color2.g))) / 2.0),
        .b = @intFromFloat((@as(f32, @floatFromInt(color1.b)) + @as(f32, @floatFromInt(color2.b))) / 2.0),
        .a = 255,
    };
}

/// Get character body color as a halftone of school + position
pub fn getCharacterColor(school: @import("school.zig").School, position: @import("position.zig").Position) rl.Color {
    const school_color = getSchoolColor(school);
    const position_color = getPositionColor(position);
    // 50/50 halftone mix
    return halftoneColors(school_color, position_color);
}

/// Get outline color for character based on team
pub fn getOutlineColor(is_enemy: bool, is_player: bool) rl.Color {
    if (is_player) return OUTLINE.PLAYER;
    if (is_enemy) return OUTLINE.ENEMY;
    return OUTLINE.ALLY;
}
