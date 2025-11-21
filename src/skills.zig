const std = @import("std");

pub const SkillTarget = enum {
    enemy,
    ally,
    self,
    ground,
};

pub const Skill = struct {
    name: [:0]const u8,
    energy_cost: u8 = 5,
    damage: f32 = 10.0,
    cast_range: f32 = 200.0, // units
    target_type: SkillTarget = .enemy,
};
