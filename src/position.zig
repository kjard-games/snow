const std = @import("std");
const skills = @import("skills.zig");
const school_mod = @import("school.zig");

pub const Skill = skills.Skill;
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
            .pitcher => &pitcher_skills,
            .fielder => &fielder_skills,
            .sledder => &sledder_skills,
            .shoveler => &shoveler_skills,
            .animator => &animator_skills,
            .thermos => &thermos_skills,
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

// Pitcher skills - high damage, long range
const pitcher_skills = [_]Skill{
    .{ .name = "Fastball", .skill_type = .throw, .energy_cost = 5, .damage = 15.0, .cast_range = 250.0 },
    .{ .name = "Curveball", .skill_type = .throw, .energy_cost = 7, .damage = 12.0, .cast_range = 200.0 },
    .{ .name = "Changeup", .skill_type = .throw, .energy_cost = 6, .damage = 10.0, .cast_range = 220.0 },
    .{ .name = "Knuckleball", .skill_type = .throw, .energy_cost = 8, .damage = 18.0, .cast_range = 230.0 },
};

// Fielder skills - balanced
const fielder_skills = [_]Skill{
    .{ .name = "Diving Catch", .skill_type = .throw, .energy_cost = 4, .damage = 8.0, .cast_range = 150.0 },
    .{ .name = "Quick Throw", .skill_type = .throw, .energy_cost = 3, .damage = 10.0, .cast_range = 180.0 },
    .{ .name = "Scoop", .skill_type = .throw, .energy_cost = 5, .damage = 12.0, .cast_range = 160.0 },
    .{ .name = "Long Toss", .skill_type = .throw, .energy_cost = 7, .damage = 14.0, .cast_range = 280.0 },
};

// Sledder skills - close range, high damage
const sledder_skills = [_]Skill{
    .{ .name = "Downhill Rush", .skill_type = .throw, .energy_cost = 8, .damage = 20.0, .cast_range = 100.0 },
    .{ .name = "Snow Spray", .skill_type = .throw, .energy_cost = 6, .damage = 8.0, .cast_range = 120.0 },
    .{ .name = "Jump", .skill_type = .throw, .energy_cost = 5, .damage = 12.0, .cast_range = 150.0 },
    .{ .name = "Drift Turn", .skill_type = .throw, .energy_cost = 7, .damage = 15.0, .cast_range = 110.0 },
};

// Shoveler skills - defensive, moderate damage
const shoveler_skills = [_]Skill{
    .{ .name = "Dig In", .skill_type = .stance, .energy_cost = 4, .damage = 6.0, .cast_range = 140.0 },
    .{ .name = "Wall Up", .skill_type = .stance, .energy_cost = 6, .damage = 5.0, .cast_range = 100.0 },
    .{ .name = "Shovel Toss", .skill_type = .throw, .energy_cost = 5, .damage = 13.0, .cast_range = 170.0 },
    .{ .name = "Pack Snow", .skill_type = .throw, .energy_cost = 7, .damage = 11.0, .cast_range = 160.0 },
};

// Animator skills - summons (Calvin & Hobbes grotesque snowmen)
// TODO: Implement proper summon mechanics
const animator_skills = [_]Skill{
    .{ .name = "Deranged Snowman", .skill_type = .trick, .energy_cost = 10, .damage = 8.0, .cast_range = 200.0 },
    .{ .name = "Snow Family", .skill_type = .trick, .energy_cost = 8, .damage = 12.0, .cast_range = 220.0 },
    .{ .name = "Abomination", .skill_type = .trick, .energy_cost = 15, .damage = 25.0, .cast_range = 180.0 },
    .{ .name = "Snowman Sentinel", .skill_type = .trick, .energy_cost = 12, .damage = 15.0, .cast_range = 240.0 },
};

// Thermos skills - healer/support (hot cocoa themed)
// TODO: Implement proper healing and buff mechanics
const thermos_skills = [_]Skill{
    .{ .name = "Share Cocoa", .skill_type = .gesture, .energy_cost = 5, .healing = 20.0, .cast_range = 150.0, .target_type = .ally },
    .{ .name = "Hand Warmers", .skill_type = .gesture, .energy_cost = 4, .cast_range = 180.0, .target_type = .ally },
    .{ .name = "Extra Scarf", .skill_type = .gesture, .energy_cost = 6, .cast_range = 160.0, .target_type = .ally },
    .{ .name = "Cocoa Break", .skill_type = .call, .energy_cost = 10, .healing = 15.0, .cast_range = 200.0, .target_type = .ally, .aoe_type = .area, .aoe_radius = 150.0 },
};
