//! Example demonstrating the factory system to build custom character teams
//! This shows how to compose characters and teams with specific constraints

const std = @import("std");
const factory = @import("factory.zig");
const character = @import("character.zig");
const equipment = @import("equipment.zig");
const school = @import("school.zig");
const position = @import("position.zig");
const entity = @import("entity.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("Memory leak detected!\n", .{});
        }
    }
    const allocator = gpa.allocator();

    // Initialize RNG and ID generator
    const timestamp = std.time.timestamp();
    const seed: u64 = @bitCast(timestamp);
    var prng = std.Random.DefaultPrng.init(seed);
    var rng = prng.random();

    var id_gen = entity.EntityIdGenerator{};

    std.debug.print("\n=== FACTORY EXAMPLES ===\n\n", .{});

    // Example 1: Single character with constraints
    std.debug.print("1. Building a single Waldorf thermos healer:\n", .{});
    {
        var builder = factory.CharacterBuilder.init(allocator, &rng, &id_gen);
        const char = builder
            .withSchool(.waldorf)
            .withPosition(.thermos)
            .withTeam(.blue)
            .withColor(.blue)
            .withName("Waldorf Healer")
            .build();

        std.debug.print("   {s} - {s}/{s}\n", .{ char.name, @tagName(char.school), @tagName(char.player_position) });
    }

    // Example 2: Character with equipment constraints
    std.debug.print("\n2. Building a Big Shovel melee fighter:\n", .{});
    {
        var builder = factory.CharacterBuilder.init(allocator, &rng, &id_gen);
        const char = builder
            .withMainHand(.{ .specific = &equipment.BigShovel })
            .withTeam(.blue)
            .withColor(.blue)
            .withName("Shovel Knight")
            .build();

        std.debug.print("   {s} - Main: {s}\n", .{ char.name, if (char.main_hand) |eq| eq.name else "none" });
    }

    // Example 3: Character with wall skill requirement
    std.debug.print("\n3. Building a defender with wall skill in slot 0:\n", .{});
    {
        var builder = factory.CharacterBuilder.init(allocator, &rng, &id_gen);
        const char = builder
            .withWallSkillInSlot(0)
            .withTeam(.blue)
            .withColor(.blue)
            .withName("Wall Builder")
            .build();

        const has_wall = if (char.casting.skills[0]) |skill| skill.creates_wall else false;
        std.debug.print("   {s} - Slot 0 creates wall: {}\n", .{ char.name, has_wall });
    }

    // Example 4: Building a team (4v4)
    std.debug.print("\n4. Building a full ally team (4v4 configuration):\n", .{});
    {
        var team = factory.TeamBuilder.init(allocator, &rng, &id_gen);
        defer team.deinit();

        team
            .withTeam(.blue)
            .withColor(.blue)
            .withBasePosition(.{ .x = 0, .y = 0, .z = 400 })
            .withSpacing(100.0);

        // Add 3 random damage dealers
        for (0..3) |_| {
            var builder = factory.CharacterBuilder.init(allocator, &rng, &id_gen);
            builder.withTeam(.blue).withColor(.blue);
            try team.addCharacter(&builder);
        }

        // Add 1 healer
        var healer_builder = factory.CharacterBuilder.init(allocator, &rng, &id_gen);
        healer_builder
            .withTeam(.blue)
            .withColor(.blue)
            .withPosition(.thermos);
        try team.addCharacter(&healer_builder);

        const characters = try team.build();
        for (characters, 0..) |char, i| {
            std.debug.print("   [{d}] {s} ({s}/{s}) at {d:.0}, {d:.0}\n", .{
                i,
                char.name,
                @tagName(char.school),
                @tagName(char.player_position),
                char.position.x,
                char.position.z,
            });
        }
    }

    // Example 5: Arena with 3 teams
    std.debug.print("\n5. Building arena with 3 teams (4v4 vs 4-neutral):\n", .{});
    {
        var arena = factory.ArenaBuilder.init(allocator, &rng, &id_gen);
        defer arena.deinit();

        // Ally team
        if (try arena.addTeam()) |ally_team| {
            ally_team
                .withTeam(.blue)
                .withColor(.blue)
                .withBasePosition(.{ .x = 0, .y = 0, .z = 400 })
                .withSpacing(80.0);

            for (0..4) |_| {
                var builder = factory.CharacterBuilder.init(allocator, &rng, &id_gen);
                builder.withTeam(.blue).withColor(.blue);
                try ally_team.addCharacter(&builder);
            }
        }

        // Enemy team
        if (try arena.addTeam()) |enemy_team| {
            enemy_team
                .withTeam(.red)
                .withColor(.red)
                .withBasePosition(.{ .x = 0, .y = 0, .z = -400 })
                .withSpacing(80.0);

            for (0..4) |_| {
                var builder = factory.CharacterBuilder.init(allocator, &rng, &id_gen);
                builder.withTeam(.red).withColor(.red);
                try enemy_team.addCharacter(&builder);
            }
        }

        // Neutral/3rd team (4 characters positioned to the side)
        if (try arena.addTeam()) |neutral_team| {
            neutral_team
                .withTeam(.blue) // Use blue but different color for visual distinction
                .withColor(.yellow)
                .withBasePosition(.{ .x = -500, .y = 0, .z = 0 })
                .withSpacing(80.0);

            for (0..4) |_| {
                var builder = factory.CharacterBuilder.init(allocator, &rng, &id_gen);
                builder.withTeam(.blue).withColor(.yellow);
                try neutral_team.addCharacter(&builder);
            }
        }

        std.debug.print("   Arena teams: {d}\n", .{arena.teamCount()});
        std.debug.print("   Total characters: \n", .{});

        for (0..arena.teamCount()) |team_idx| {
            if (arena.getTeam(team_idx)) |team| {
                std.debug.print("     Team {d}: {d} characters\n", .{ team_idx, team.characters.items.len });
            }
        }
    }

    std.debug.print("\n=== EXAMPLES COMPLETE ===\n\n", .{});
}
