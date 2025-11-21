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

// Pitcher skills
const pitcher_skills = [_]Skill{
    .{ .name = "Fastball" },
    .{ .name = "Curveball" },
    .{ .name = "Changeup" },
    .{ .name = "Knuckleball" },
};

// Fielder skills
const fielder_skills = [_]Skill{
    .{ .name = "Diving Catch" },
    .{ .name = "Quick Throw" },
    .{ .name = "Scoop" },
    .{ .name = "Long Toss" },
};

// Sledder skills
const sledder_skills = [_]Skill{
    .{ .name = "Downhill Rush" },
    .{ .name = "Snow Spray" },
    .{ .name = "Jump" },
    .{ .name = "Drift Turn" },
};

// Shoveler skills
const shoveler_skills = [_]Skill{
    .{ .name = "Dig In" },
    .{ .name = "Wall Up" },
    .{ .name = "Shovel Toss" },
    .{ .name = "Pack Snow" },
};

// Skater skills
const skater_skills = [_]Skill{
    .{ .name = "Speed Burst" },
    .{ .name = "Crossover" },
    .{ .name = "Stop-and-Go" },
    .{ .name = "Breakaway" },
};

// Goalie skills
const goalie_skills = [_]Skill{
    .{ .name = "Glove Save" },
    .{ .name = "Blocker" },
    .{ .name = "Butterfly" },
    .{ .name = "Poke Check" },
};

// Summoner skills
const summoner_skills = [_]Skill{
    .{ .name = "Call Snowman" },
    .{ .name = "Frost Servant" },
    .{ .name = "Ice Golem" },
    .{ .name = "Winter's Army" },
};
