const std = @import("std");
const color_pie = @import("color_pie.zig");

pub const School = enum {
    private_school, // White: Order, Privilege, Resources
    public_school, // Red: Aggression, Grit, Combat
    montessori, // Green: Adaptation, Variety, Growth
    homeschool, // Black: Sacrifice, Power, Isolation
    waldorf, // Blue: Rhythm, Timing, Harmony

    // Energy generation rates and mechanics
    pub fn getEnergyRegen(self: School) f32 {
        return switch (self) {
            .private_school => 2.0, // Allowance: steady passive regen
            .public_school => 0.0, // Grit: no passive regen, combat only
            .montessori => 1.0, // Balanced regen
            .homeschool => 0.5, // Low regen, can sacrifice warmth
            .waldorf => 1.5, // Rhythm: moderate regen
        };
    }

    pub fn getMaxEnergy(self: School) u8 {
        return switch (self) {
            .private_school => 30, // High energy pool
            .public_school => 20, // Lower pool, gains from combat
            .montessori => 25, // Balanced
            .homeschool => 25, // Can convert warmth
            .waldorf => 25, // Rhythm-based
        };
    }

    pub fn getResourceName(self: School) [:0]const u8 {
        return switch (self) {
            .private_school => "Allowance",
            .public_school => "Grit",
            .montessori => "Focus",
            .homeschool => "Life Force",
            .waldorf => "Rhythm",
        };
    }

    pub fn getSecondaryMechanicName(self: School) [:0]const u8 {
        return switch (self) {
            .private_school => "Steady Income",
            .public_school => "Grit Stacks",
            .montessori => "Variety Bonus",
            .homeschool => "Sacrifice",
            .waldorf => "Perfect Timing",
        };
    }

    // Color pie access methods
    pub fn getChillAccess(self: School) color_pie.ChillAccess {
        return color_pie.getChillAccess(self);
    }

    pub fn getCozyAccess(self: School) color_pie.CozyAccess {
        return color_pie.getCozyAccess(self);
    }

    pub fn getSkillTypeAccess(self: School) color_pie.SkillTypeAccess {
        return color_pie.getSkillTypeAccess(self);
    }

    pub fn getDamageRange(self: School) color_pie.DamageRange {
        return color_pie.getDamageRange(self);
    }

    pub fn getCooldownRange(self: School) color_pie.CooldownRange {
        return color_pie.getCooldownRange(self);
    }

    pub fn getColorIdentity(self: School) [:0]const u8 {
        return switch (self) {
            .private_school => "White: Order, Privilege, Resources",
            .public_school => "Red: Aggression, Grit, Combat",
            .montessori => "Green: Adaptation, Variety, Growth",
            .homeschool => "Black: Sacrifice, Power, Isolation",
            .waldorf => "Blue: Rhythm, Timing, Harmony",
        };
    }
};
