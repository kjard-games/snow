const std = @import("std");
const skills = @import("skills.zig");

pub const Skill = skills.Skill;

pub const Position = enum {
    pitcher,
    fielder,
    sledder,
    digger,
    runner,
    catcher,
    waldorf,

    pub fn getSkills(self: Position) []const Skill {
        return switch (self) {
            .pitcher => &pitcher_skills,
            .fielder => &fielder_skills,
            .sledder => &sledder_skills,
            .digger => &digger_skills,
            .runner => &runner_skills,
            .catcher => &catcher_skills,
            .waldorf => &waldorf_skills,
        };
    }
};

// Pitcher skills
const pitcher_skills = [_]Skill{
    .{ .name = "Fastball" },
    .{ .name = "Curveball" },
    .{ .name = "Changeup" },
    .{ .name = "Slider" },
};

// Fielder skills
const fielder_skills = [_]Skill{
    .{ .name = "Catch" },
    .{ .name = "Throw" },
    .{ .name = "Dive" },
    .{ .name = "Scoop" },
};

// Sledder skills
const sledder_skills = [_]Skill{
    .{ .name = "Push" },
    .{ .name = "Brake" },
    .{ .name = "Drift" },
    .{ .name = "Boost" },
};

// Digger skills
const digger_skills = [_]Skill{
    .{ .name = "Dig" },
    .{ .name = "Excavate" },
    .{ .name = "Tunnel" },
    .{ .name = "Fortify" },
};

// Runner skills
const runner_skills = [_]Skill{
    .{ .name = "Sprint" },
    .{ .name = "Slide" },
    .{ .name = "Jump" },
    .{ .name = "Dash" },
};

// Catcher skills
const catcher_skills = [_]Skill{
    .{ .name = "Frame" },
    .{ .name = "Block" },
    .{ .name = "Throw Out" },
    .{ .name = "Signal" },
};

// Waldorf skills
const waldorf_skills = [_]Skill{
    .{ .name = "Forbidden Lore" },
    .{ .name = "Dark Pact" },
    .{ .name = "Blood Magic" },
    .{ .name = "Soul Drain" },
};
