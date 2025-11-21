const std = @import("std");
const rl = @import("raylib");
const background = @import("background.zig");
const position = @import("position.zig");
const skills = @import("skills.zig");

pub const Background = background.Background;
pub const Position = position.Position;
pub const Skill = skills.Skill;

pub const Entity = struct {
    position: rl.Vector3,
    radius: f32,
    color: rl.Color,
    name: [:0]const u8,
    health: f32,
    max_health: f32,
    is_enemy: bool,

    // Skill system components
    background: Background,
    player_position: Position,

    // Universal primary resource
    energy: u8,
    max_energy: u8,

    // Background-specific secondary mechanics
    // Private School: Passive regen (no extra state needed)

    // Public School: Grit stacks
    grit_stacks: u8 = 0, // Every 5 stacks = free skill
    max_grit_stacks: u8 = 5,

    // Homeschool: Health-to-Energy conversion (cooldown tracker)
    sacrifice_cooldown: f32 = 0.0, // seconds until can sacrifice again

    // Waldorf: Rhythm timing
    rhythm_charge: u8 = 0, // 0-10, builds with skill casts
    rhythm_perfect_window: f32 = 0.0, // timing window tracker
    max_rhythm_charge: u8 = 10,

    // Montessori: Skill variety bonus
    last_skills_used: [5]?u8 = [_]?u8{null} ** 5, // tracks last 5 skills
    variety_bonus_damage: f32 = 0.0, // 0.0 to 0.5 (0% to 50% bonus)

    skill_bar: [8]?*const Skill,
    selected_skill: u8 = 0,

    pub fn updateEnergy(self: *Entity, delta_time: f32) void {
        // Passive energy regeneration based on background
        const regen = self.background.getEnergyRegen() * delta_time;
        const new_energy = @min(self.max_energy, @as(u8, @intFromFloat(@as(f32, @floatFromInt(self.energy)) + regen)));
        self.energy = new_energy;

        // Update background-specific mechanics
        switch (self.background) {
            .private_school => {
                // Private school has steady regen (already handled above)
            },
            .public_school => {
                // Grit stacks decay over time if not in combat
                // TODO: implement combat state tracking
            },
            .montessori => {
                // Update variety bonus based on recent skill usage
                // TODO: implement when skills are used
            },
            .homeschool => {
                // Reduce sacrifice cooldown
                if (self.sacrifice_cooldown > 0) {
                    self.sacrifice_cooldown = @max(0, self.sacrifice_cooldown - delta_time);
                }
            },
            .waldorf => {
                // Rhythm charge decays slowly
                if (self.rhythm_perfect_window > 0) {
                    self.rhythm_perfect_window = @max(0, self.rhythm_perfect_window - delta_time);
                }
            },
        }
    }
};
