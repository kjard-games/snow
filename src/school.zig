const std = @import("std");

pub const School = enum {
    private_school,
    public_school,
    montessori,
    homeschool,
    waldorf,

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
};
