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
    .{ .name = "Fastball", .energy_cost = 5, .damage = 15.0, .cast_range = 250.0 },
    .{ .name = "Curveball", .energy_cost = 7, .damage = 12.0, .cast_range = 200.0 },
    .{ .name = "Changeup", .energy_cost = 6, .damage = 10.0, .cast_range = 220.0 },
    .{ .name = "Knuckleball", .energy_cost = 8, .damage = 18.0, .cast_range = 230.0 },
};

// Fielder skills - balanced
const fielder_skills = [_]Skill{
    .{ .name = "Diving Catch", .energy_cost = 4, .damage = 8.0, .cast_range = 150.0 },
    .{ .name = "Quick Throw", .energy_cost = 3, .damage = 10.0, .cast_range = 180.0 },
    .{ .name = "Scoop", .energy_cost = 5, .damage = 12.0, .cast_range = 160.0 },
    .{ .name = "Long Toss", .energy_cost = 7, .damage = 14.0, .cast_range = 280.0 },
};

// Sledder skills - close range, high damage
const sledder_skills = [_]Skill{
    .{ .name = "Downhill Rush", .energy_cost = 8, .damage = 20.0, .cast_range = 100.0 },
    .{ .name = "Snow Spray", .energy_cost = 6, .damage = 8.0, .cast_range = 120.0 },
    .{ .name = "Jump", .energy_cost = 5, .damage = 12.0, .cast_range = 150.0 },
    .{ .name = "Drift Turn", .energy_cost = 7, .damage = 15.0, .cast_range = 110.0 },
};

// Shoveler skills - defensive, moderate damage
const shoveler_skills = [_]Skill{
    .{ .name = "Dig In", .energy_cost = 4, .damage = 6.0, .cast_range = 140.0 },
    .{ .name = "Wall Up", .energy_cost = 6, .damage = 5.0, .cast_range = 100.0 },
    .{ .name = "Shovel Toss", .energy_cost = 5, .damage = 13.0, .cast_range = 170.0 },
    .{ .name = "Pack Snow", .energy_cost = 7, .damage = 11.0, .cast_range = 160.0 },
};

// Skater skills - fast, low energy
const skater_skills = [_]Skill{
    .{ .name = "Speed Burst", .energy_cost = 3, .damage = 7.0, .cast_range = 150.0 },
    .{ .name = "Crossover", .energy_cost = 4, .damage = 9.0, .cast_range = 140.0 },
    .{ .name = "Stop-and-Go", .energy_cost = 5, .damage = 11.0, .cast_range = 160.0 },
    .{ .name = "Breakaway", .energy_cost = 6, .damage = 16.0, .cast_range = 190.0 },
};

// Goalie skills - defensive counters
const goalie_skills = [_]Skill{
    .{ .name = "Glove Save", .energy_cost = 4, .damage = 8.0, .cast_range = 120.0 },
    .{ .name = "Blocker", .energy_cost = 5, .damage = 10.0, .cast_range = 130.0 },
    .{ .name = "Butterfly", .energy_cost = 6, .damage = 7.0, .cast_range = 110.0 },
    .{ .name = "Poke Check", .energy_cost = 3, .damage = 12.0, .cast_range = 100.0 },
};

// Summoner skills - high cost, high damage
const summoner_skills = [_]Skill{
    .{ .name = "Call Snowman", .energy_cost = 10, .damage = 8.0, .cast_range = 200.0 },
    .{ .name = "Frost Servant", .energy_cost = 8, .damage = 12.0, .cast_range = 220.0 },
    .{ .name = "Ice Golem", .energy_cost = 15, .damage = 25.0, .cast_range = 180.0 },
    .{ .name = "Winter's Army", .energy_cost = 12, .damage = 15.0, .cast_range = 240.0 },
};
