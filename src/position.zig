const std = @import("std");
const types = @import("skills/types.zig");
const school_mod = @import("school.zig");

// Import position skill modules
const pitcher_mod = @import("skills/positions/pitcher.zig");
const fielder_mod = @import("skills/positions/fielder.zig");
const sledder_mod = @import("skills/positions/sledder.zig");
const shoveler_mod = @import("skills/positions/shoveler.zig");
const animator_mod = @import("skills/positions/animator.zig");
const thermos_mod = @import("skills/positions/thermos.zig");

pub const Skill = types.Skill;
pub const School = school_mod.School;

pub const Position = enum {
    pitcher, // Pure Damage Dealer - the kid with the cannon arm
    fielder, // Balanced Generalist - athletic all-rounder
    sledder, // Aggressive Skirmisher - sled charge attacks
    shoveler, // Tank/Defender - digs in, builds walls
    animator, // Summoner/Necromancer - brings snowmen to life (Calvin & Hobbes style)
    thermos, // Healer/Support - brings hot cocoa and hand warmers

    pub fn getSkills(self: Position) []const Skill {
        return switch (self) {
            .pitcher => &pitcher_mod.skills,
            .fielder => &fielder_mod.skills,
            .sledder => &sledder_mod.skills,
            .shoveler => &shoveler_mod.skills,
            .animator => &animator_mod.skills,
            .thermos => &thermos_mod.skills,
        };
    }

    pub fn getDescription(self: Position) [:0]const u8 {
        return switch (self) {
            .pitcher => "Pure Damage Dealer - high damage, long range, fragile",
            .fielder => "Balanced Generalist - adapts to any situation",
            .sledder => "Aggressive Skirmisher - high mobility, in-your-face combat",
            .shoveler => "Tank/Defender - absorbs damage, protects others",
            .animator => "Summoner/Necromancer - brings grotesque snowmen to life",
            .thermos => "Healer/Support - shares cocoa, hand warmers, and comfort",
        };
    }

    pub fn getPrimarySchools(self: Position) []const School {
        return switch (self) {
            .pitcher => &[_]School{ .public_school, .homeschool },
            .fielder => &[_]School{ .montessori, .public_school },
            .sledder => &[_]School{ .public_school, .waldorf },
            .shoveler => &[_]School{ .private_school, .homeschool },
            .animator => &[_]School{ .homeschool, .waldorf },
            .thermos => &[_]School{ .waldorf, .private_school },
        };
    }

    pub fn getRangeMin(self: Position) f32 {
        return switch (self) {
            .pitcher => 200.0,
            .fielder => 150.0,
            .sledder => 80.0,
            .shoveler => 100.0,
            .animator => 180.0,
            .thermos => 150.0,
        };
    }

    pub fn getRangeMax(self: Position) f32 {
        return switch (self) {
            .pitcher => 300.0,
            .fielder => 220.0,
            .sledder => 150.0,
            .shoveler => 160.0,
            .animator => 240.0,
            .thermos => 200.0,
        };
    }
};
