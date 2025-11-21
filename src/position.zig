const std = @import("std");
const skills = @import("skills.zig");

pub const Skill = skills.Skill;

pub const Position = enum {
    pitcher,
    fielder,
    sledder,
    shoveler,
    skater,
    goalie,
    summoner,

    pub fn getSkills(self: Position) []const Skill {
        return switch (self) {
            .pitcher => &pitcher_skills,
            .fielder => &fielder_skills,
            .sledder => &sledder_skills,
            .shoveler => &shoveler_skills,
            .skater => &skater_skills,
            .goalie => &goalie_skills,
            .summoner => &summoner_skills,
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

// Skater skills - fast, low energy
const skater_skills = [_]Skill{
    .{ .name = "Speed Burst", .skill_type = .stance, .energy_cost = 3, .damage = 7.0, .cast_range = 150.0 },
    .{ .name = "Crossover", .skill_type = .throw, .energy_cost = 4, .damage = 9.0, .cast_range = 140.0 },
    .{ .name = "Stop-and-Go", .skill_type = .throw, .energy_cost = 5, .damage = 11.0, .cast_range = 160.0 },
    .{ .name = "Breakaway", .skill_type = .throw, .energy_cost = 6, .damage = 16.0, .cast_range = 190.0 },
};

// Goalie skills - defensive counters
const goalie_skills = [_]Skill{
    .{ .name = "Glove Save", .skill_type = .stance, .energy_cost = 4, .damage = 8.0, .cast_range = 120.0 },
    .{ .name = "Blocker", .skill_type = .stance, .energy_cost = 5, .damage = 10.0, .cast_range = 130.0 },
    .{ .name = "Butterfly", .skill_type = .stance, .energy_cost = 6, .damage = 7.0, .cast_range = 110.0 },
    .{ .name = "Poke Check", .skill_type = .throw, .energy_cost = 3, .damage = 12.0, .cast_range = 100.0 },
};

// Summoner skills - high cost, high damage
const summoner_skills = [_]Skill{
    .{ .name = "Call Snowman", .skill_type = .trick, .energy_cost = 10, .damage = 8.0, .cast_range = 200.0 },
    .{ .name = "Frost Servant", .skill_type = .trick, .energy_cost = 8, .damage = 12.0, .cast_range = 220.0 },
    .{ .name = "Ice Golem", .skill_type = .trick, .energy_cost = 15, .damage = 25.0, .cast_range = 180.0 },
    .{ .name = "Winter's Army", .skill_type = .trick, .energy_cost = 12, .damage = 15.0, .cast_range = 240.0 },
};
