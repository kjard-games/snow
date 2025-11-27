const std = @import("std");
const color_pie = @import("color_pie.zig");
const types = @import("skills/types.zig");

// Import school skill modules
const private_mod = @import("skills/schools/private.zig");
const public_mod = @import("skills/schools/public.zig");
const montessori_mod = @import("skills/schools/montessori.zig");
const homeschool_mod = @import("skills/schools/homeschool.zig");
const waldorf_mod = @import("skills/schools/waldorf.zig");

pub const Skill = types.Skill;

pub const School = enum {
    private_school, // White: Order, Privilege, Resources
    public_school, // Red: Aggression, Grit, Combat
    montessori, // Green: Adaptation, Variety, Growth
    homeschool, // Black: Sacrifice, Power, Isolation
    waldorf, // Blue: Rhythm, Timing, Harmony

    // Energy generation rates (per second)
    // All schools have base regen, but some are more efficient than others
    pub fn getEnergyRegen(self: School) f32 {
        return switch (self) {
            .private_school => 1.5, // Allowance: high steady passive regen
            .public_school => 1.0, // Grit: standard regen, gains bonus from combat
            .montessori => 1.0, // Focus: balanced regen, bonus from variety
            .homeschool => 0.75, // Life Force: low regen, must sacrifice warmth
            .waldorf => 1.25, // Rhythm: good regen, bonus from rhythm stacks
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

    pub fn getSkills(self: School) []const Skill {
        return switch (self) {
            .private_school => &private_mod.skills,
            .public_school => &public_mod.skills,
            .montessori => &montessori_mod.skills,
            .homeschool => &homeschool_mod.skills,
            .waldorf => &waldorf_mod.skills,
        };
    }
};
