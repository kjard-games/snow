//! SimulationFactory - Builds complete battle simulations with configured teams, telemetry, and game state
//! Uses factory patterns all the way down: arena -> teams -> characters -> game state -> telemetry

const std = @import("std");
const rl = @import("raylib");
const game_state = @import("game_state.zig");
const telemetry = @import("telemetry.zig");
const factory = @import("factory.zig");
const entity = @import("entity.zig");
const character = @import("character.zig");

const GameState = game_state.GameState;
const MatchTelemetry = telemetry.MatchTelemetry;
const ArenaBuilder = factory.ArenaBuilder;
const TeamBuilder = factory.TeamBuilder;
const CharacterBuilder = factory.CharacterBuilder;

/// Complete simulation context with game state, telemetry, and arena configuration
pub const SimulationContext = struct {
    allocator: std.mem.Allocator,
    game_state: GameState,
    telemetry: MatchTelemetry,
    character_count: usize,

    pub fn deinit(self: *SimulationContext) void {
        self.game_state.deinit();
        self.telemetry.deinit();
    }
};

/// Configuration for building a simulation scenario
pub const SimulationConfig = struct {
    // Arena composition
    team_count: usize = 2, // 2, 3, etc.
    characters_per_team: usize = 4,

    // Telemetry options
    enable_telemetry: bool = true,
    telemetry_filename: []const u8 = "match_telemetry.json",

    // Simulation execution
    max_ticks: u32 = 15000,
    verbose: bool = false,
};

/// Builds complete simulations with fluent configuration
pub const SimulationFactory = struct {
    allocator: std.mem.Allocator,
    rng: *std.Random,
    id_gen: *entity.EntityIdGenerator,
    arena: ArenaBuilder,
    config: SimulationConfig,

    pub fn init(allocator: std.mem.Allocator, rng: *std.Random, id_gen: *entity.EntityIdGenerator) SimulationFactory {
        return .{
            .allocator = allocator,
            .rng = rng,
            .id_gen = id_gen,
            .arena = ArenaBuilder.init(allocator, rng, id_gen),
            .config = SimulationConfig{},
        };
    }

    pub fn deinit(self: *SimulationFactory) void {
        self.arena.deinit();
    }

    /// Set the number of teams in the simulation
    pub fn withTeamCount(self: *SimulationFactory, count: usize) *SimulationFactory {
        self.config.team_count = count;
        return self;
    }

    /// Set characters per team
    pub fn withCharactersPerTeam(self: *SimulationFactory, count: usize) *SimulationFactory {
        self.config.characters_per_team = count;
        return self;
    }

    /// Set maximum simulation duration in ticks
    pub fn withMaxTicks(self: *SimulationFactory, ticks: u32) *SimulationFactory {
        self.config.max_ticks = ticks;
        return self;
    }

    /// Enable/disable telemetry
    pub fn withTelemetry(self: *SimulationFactory, enabled: bool) *SimulationFactory {
        self.config.enable_telemetry = enabled;
        return self;
    }

    /// Set telemetry output filename
    pub fn withTelemetryFile(self: *SimulationFactory, filename: []const u8) *SimulationFactory {
        self.config.telemetry_filename = filename;
        return self;
    }

    /// Set verbose output
    pub fn withVerbose(self: *SimulationFactory, verbose: bool) *SimulationFactory {
        self.config.verbose = verbose;
        return self;
    }

    /// Build the complete simulation (arena with teams and game state)
    pub fn build(self: *SimulationFactory) !SimulationContext {
        // Build teams in the arena
        for (0..self.config.team_count) |team_idx| {
            const team = try self.arena.addTeam();
            const team_color = switch (team_idx) {
                0 => rl.Color.blue,
                1 => rl.Color.red,
                else => rl.Color.yellow,
            };
            const team_enum = switch (team_idx) {
                0 => entity.Team.blue,
                else => entity.Team.red, // All non-first teams are "red" for team enum purposes
            };

            _ = team
                .withTeam(team_enum)
                .withColor(team_color)
                .withBasePosition(.{
                    .x = @as(f32, @floatFromInt(@as(i32, @intCast(team_idx)) - 1)) * 250.0,
                    .y = 0,
                    .z = @as(f32, @floatFromInt(@as(i32, @intCast(team_idx)) - 1)) * -300.0,
                })
                .withSpacing(100.0);

            // Add random characters to team
            for (0..self.config.characters_per_team) |_| {
                var builder = CharacterBuilder.init(self.allocator, self.rng, self.id_gen);
                _ = builder.withTeam(team_enum).withColor(team_color);
                try team.addCharacter(&builder);
            }

            if (self.config.verbose) {
                std.debug.print("Team {d}: {d} characters\n", .{ team_idx, self.config.characters_per_team });
            }
        }

        // Collect all characters from arena
        var all_chars: std.array_list.Aligned(character.Character, null) = .{};
        defer all_chars.deinit(self.allocator);

        for (0..self.arena.teamCount()) |team_idx| {
            if (self.arena.getTeam(team_idx)) |team| {
                for (team.characters.items) |char| {
                    try all_chars.append(self.allocator, char);
                }
            }
        }

        if (self.config.verbose) {
            std.debug.print("Total characters: {d}\n\n", .{all_chars.items.len});
        }

        // Initialize telemetry
        var telem = try MatchTelemetry.init(self.allocator);

        // Initialize game state with built characters
        const gs = try initGameStateFromCharacters(self.allocator, all_chars.items);
        var mutable_gs = gs;

        // Link telemetry to game state
        mutable_gs.match_telemetry = if (self.config.enable_telemetry) &telem else null;

        // Register all characters with telemetry
        if (self.config.enable_telemetry) {
            for (mutable_gs.entities[0..all_chars.items.len]) |ent| {
                try telem.registerEntity(
                    ent.id,
                    ent.name,
                    @tagName(ent.school),
                    @tagName(ent.player_position),
                    if (ent.team == .blue) 0 else 1,
                    ent.id == mutable_gs.controlled_entity_id,
                );
            }
        }

        return SimulationContext{
            .allocator = self.allocator,
            .game_state = mutable_gs,
            .telemetry = telem,
            .character_count = all_chars.items.len,
        };
    }
};

/// Executes a simulation and returns match statistics
pub const SimulationRunner = struct {
    context: SimulationContext,
    config: SimulationConfig,

    pub fn init(context: SimulationContext, config: SimulationConfig) SimulationRunner {
        return .{
            .context = context,
            .config = config,
        };
    }

    pub fn deinit(self: *SimulationRunner) void {
        self.context.deinit();
    }

    /// Run the simulation until completion or max ticks reached
    pub fn run(self: *SimulationRunner) !void {
        if (self.config.verbose) {
            std.debug.print("\n=== SIMULATION RUNNING ===\n", .{});
            std.debug.print("Max ticks: {d}\n", .{self.config.max_ticks});
            std.debug.print("Teams: {d}, Characters: {d}\n\n", .{ self.config.team_count, self.context.character_count });
        }

        var tick_count: u32 = 0;

        while (tick_count < self.config.max_ticks) : (tick_count += 1) {
            // Accumulate time for update loop
            self.context.game_state.tick_accumulator = game_state.TICK_RATE_SEC;

            // Process one tick of combat
            self.context.game_state.processTick();

            // Update telemetry
            if (self.config.enable_telemetry) {
                for (self.context.game_state.entities[0..self.context.character_count]) |ent| {
                    if (self.context.telemetry.getEntityStats(ent.id)) |stats| {
                        if (ent.isAlive()) {
                            stats.time_alive_ticks += 1;
                        } else {
                            stats.time_dead_ticks += 1;
                        }
                    }
                }
            }

            // Check if combat is over (teams determined by team enum)
            var blue_alive: u32 = 0;
            var red_alive: u32 = 0;

            for (self.context.game_state.entities[0..self.context.character_count]) |ch| {
                if (ch.isAlive()) {
                    if (ch.team == .blue) {
                        blue_alive += 1;
                    } else {
                        red_alive += 1;
                    }
                }
            }

            // Stop if only one team remains
            if ((blue_alive == 0 or red_alive == 0) and (blue_alive + red_alive > 0)) {
                if (self.config.verbose) {
                    std.debug.print("Combat ended at tick {d}\n", .{tick_count});
                }
                break;
            }
        }

        if (self.config.enable_telemetry) {
            self.context.telemetry.match_duration_ticks = tick_count;

            if (self.config.verbose) {
                std.debug.print("=== SIMULATION COMPLETE ===\n", .{});
                std.debug.print("Ticks run: {d}\n\n", .{tick_count});

                // Print summary
                self.context.telemetry.printSummary();

                // Export telemetry
                std.debug.print("\n=== EXPORTING TELEMETRY ===\n", .{});
                try self.context.telemetry.exportJSON(self.context.allocator, self.config.telemetry_filename);
                std.debug.print("Telemetry exported to: {s}\n\n", .{self.config.telemetry_filename});
            }
        }
    }
};

/// Helper: Initialize GameState from character array
fn initGameStateFromCharacters(allocator: std.mem.Allocator, characters: []character.Character) !GameState {
    const id_gen = entity.EntityIdGenerator{};
    const ts = std.time.timestamp();
    const seed: u64 = @bitCast(ts);
    const prng = std.Random.DefaultPrng.init(seed);

    var entities: [12]character.Character = undefined;

    // Copy actual characters into first slots
    for (characters, 0..) |char, i| {
        entities[i] = char;
    }

    // Fill remaining slots with dummy dead characters (so iteration is safe)
    for (characters.len..12) |i| {
        var temp_id_gen = id_gen;
        entities[i] = createDummyCharacter(&temp_id_gen);
    }

    // Create headless terrain grid
    const terrain_grid = try game_state.TerrainGrid.initHeadless(
        allocator,
        100,
        100,
        20.0,
        -1000.0,
        -1000.0,
    );

    return game_state.GameState{
        .entities = entities,
        .controlled_entity_id = 999,
        .selected_target = null,
        .camera = .{
            .position = .{ .x = 0, .y = 600, .z = 700 },
            .target = .{ .x = 0, .y = 0, .z = 0 },
            .up = .{ .x = 0, .y = 1, .z = 0 },
            .fovy = 55.0,
            .projection = .perspective,
        },
        .input_state = @import("input.zig").InputState{
            .action_camera = false,
        },
        .ai_states = [_]@import("ai.zig").AIState{
            .{ .role = .damage_dealer },
            .{ .role = .damage_dealer },
            .{ .role = .damage_dealer },
            .{ .role = .support },
            .{ .role = .damage_dealer },
            .{ .role = .damage_dealer },
            .{ .role = .damage_dealer },
            .{ .role = .support },
            .{ .role = .damage_dealer },
            .{ .role = .damage_dealer },
            .{ .role = .damage_dealer },
            .{ .role = .support },
        },
        .rng = prng,
        .combat_state = .active,
        .entity_id_gen = id_gen,
        .vfx_manager = @import("vfx.zig").VFXManager.init(),
        .terrain_grid = terrain_grid,
        .allocator = allocator,
        .simulation_mode = true,
    };
}

/// Helper: Create a dummy dead character for unused entity slots
fn createDummyCharacter(id_gen: *entity.EntityIdGenerator) character.Character {
    return character.Character{
        .id = id_gen.generate(),
        .position = .{ .x = 0, .y = -1000, .z = 0 },
        .previous_position = .{ .x = 0, .y = -1000, .z = 0 },
        .radius = 1.0,
        .color = .black,
        .school_color = .black,
        .position_color = .black,
        .name = "Dummy",
        .warmth = 0,
        .max_warmth = 1,
        .team = .blue,
        .school = character.School.montessori,
        .player_position = character.Position.pitcher,
        .energy = 0,
        .max_energy = 1,
        .skill_bar = [_]?*const character.Skill{null} ** character.MAX_SKILLS,
        .gear = [_]?*const character.Gear{null} ** 6,
        .selected_skill = 0,
    };
}
