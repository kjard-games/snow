//! SimulationFactory - Builds complete battle simulations with configured teams, telemetry, and game state
//! Uses factory patterns all the way down: arena -> teams -> characters -> game state -> telemetry
//!
//! Features:
//! - Live combat feed with damage/healing events
//! - Progress bar for long simulations
//! - Compact scoreboard summaries
//! - Quick mode for batch balance testing

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

const print = std.debug.print;

// ============================================================================
// DISPLAY HELPERS
// ============================================================================

const TeamColors = struct {
    const BLUE = "\x1b[34m";
    const RED = "\x1b[31m";
    const YELLOW = "\x1b[33m";
    const GREEN = "\x1b[32m";
    const RESET = "\x1b[0m";
    const BOLD = "\x1b[1m";
    const DIM = "\x1b[2m";
    const CYAN = "\x1b[36m";
    const MAGENTA = "\x1b[35m";
    const WHITE = "\x1b[37m";
};

fn teamColor(team: entity.Team) []const u8 {
    return switch (team) {
        .blue => TeamColors.BLUE,
        .red => TeamColors.RED,
        .yellow => TeamColors.YELLOW,
        .green => TeamColors.GREEN,
        .none => TeamColors.WHITE,
    };
}

fn healthBar(current: f32, max: f32, width: u8) void {
    const pct = current / max;
    const filled: u8 = @intFromFloat(pct * @as(f32, @floatFromInt(width)));

    print("[", .{});
    var i: u8 = 0;
    while (i < width) : (i += 1) {
        if (i < filled) {
            if (pct > 0.6) {
                print("{s}={s}", .{ TeamColors.GREEN, TeamColors.RESET });
            } else if (pct > 0.3) {
                print("{s}={s}", .{ TeamColors.YELLOW, TeamColors.RESET });
            } else {
                print("{s}={s}", .{ TeamColors.RED, TeamColors.RESET });
            }
        } else {
            print("{s}-{s}", .{ TeamColors.DIM, TeamColors.RESET });
        }
    }
    print("] {d:.0}/{d:.0}", .{ current, max });
}

fn progressBar(current: u32, total: u32, width: u8) void {
    const pct = @as(f32, @floatFromInt(current)) / @as(f32, @floatFromInt(total));
    const filled: u8 = @intFromFloat(pct * @as(f32, @floatFromInt(width)));

    print("\r{s}[", .{TeamColors.DIM});
    var i: u8 = 0;
    while (i < width) : (i += 1) {
        if (i < filled) {
            print("{s}#{s}", .{ TeamColors.CYAN, TeamColors.DIM });
        } else {
            print(".", .{});
        }
    }
    print("]{s} {d}/{d} ticks ({d:.1}%)", .{ TeamColors.RESET, current, total, pct * 100.0 });
}

// ============================================================================
// SIMULATION CONTEXT
// ============================================================================

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

// ============================================================================
// SIMULATION CONFIG
// ============================================================================

/// Output verbosity levels
pub const Verbosity = enum {
    silent, // No output at all
    quiet, // Just final result
    normal, // Progress + summary
    verbose, // Progress + combat feed + full summary
    debug, // Everything including AI decisions
};

/// Configuration for building a simulation scenario
pub const SimulationConfig = struct {
    // Arena composition
    team_count: usize = 2, // 2, 3, etc.
    characters_per_team: usize = 4,

    // Telemetry options
    enable_telemetry: bool = true,
    telemetry_filename: []const u8 = "match_telemetry.json",
    export_json: bool = true,

    // Simulation execution
    max_ticks: u32 = 15000,
    verbosity: Verbosity = .normal,

    // Display options
    show_combat_feed: bool = false, // Show damage/healing as it happens
    show_progress: bool = true, // Show progress bar
    progress_interval: u32 = 100, // Update progress every N ticks
    feed_cooldown: u32 = 10, // Minimum ticks between feed messages

    // Legacy compat
    verbose: bool = false,
};

// ============================================================================
// MATCH RESULT
// ============================================================================

/// Compact match result for batch analysis
pub const MatchResult = struct {
    winner: ?entity.Team,
    duration_ticks: u32,
    blue_survivors: u8,
    red_survivors: u8,
    total_damage: f32,
    total_healing: f32,
    mvp_id: ?u32,
    mvp_damage: f32,

    pub fn format(self: MatchResult) void {
        const winner_str = if (self.winner) |w|
            switch (w) {
                .blue => "BLUE",
                .red => "RED",
                .yellow => "YELLOW",
                .green => "GREEN",
                .none => "NONE",
            }
        else
            "DRAW";

        print("{s}{s}{s} wins in {d} ticks | ", .{
            TeamColors.BOLD,
            winner_str,
            TeamColors.RESET,
            self.duration_ticks,
        });
        print("{s}BLUE{s}:{d} vs {s}RED{s}:{d} | ", .{
            TeamColors.BLUE,
            TeamColors.RESET,
            self.blue_survivors,
            TeamColors.RED,
            TeamColors.RESET,
            self.red_survivors,
        });
        print("DMG:{d:.0} HEAL:{d:.0}", .{ self.total_damage, self.total_healing });
        if (self.mvp_id) |_| {
            print(" | MVP:{d:.0}dmg", .{self.mvp_damage});
        }
        print("\n", .{});
    }
};

// ============================================================================
// SIMULATION FACTORY
// ============================================================================

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

    /// Set verbosity level
    pub fn withVerbosity(self: *SimulationFactory, level: Verbosity) *SimulationFactory {
        self.config.verbosity = level;
        // Update legacy flags
        self.config.verbose = (level == .verbose or level == .debug);
        self.config.show_combat_feed = (level == .verbose or level == .debug);
        self.config.show_progress = (level != .silent and level != .quiet);
        return self;
    }

    /// Legacy: Set verbose output
    pub fn withVerbose(self: *SimulationFactory, verbose: bool) *SimulationFactory {
        self.config.verbose = verbose;
        if (verbose) {
            self.config.verbosity = .verbose;
            self.config.show_combat_feed = true;
        }
        return self;
    }

    /// Enable live combat feed
    pub fn withCombatFeed(self: *SimulationFactory, enabled: bool) *SimulationFactory {
        self.config.show_combat_feed = enabled;
        return self;
    }

    /// Enable/disable JSON export
    pub fn withJsonExport(self: *SimulationFactory, enabled: bool) *SimulationFactory {
        self.config.export_json = enabled;
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
                2 => rl.Color.yellow,
                else => rl.Color.green,
            };
            const team_enum: entity.Team = switch (team_idx) {
                0 => .blue,
                1 => .red,
                2 => .yellow,
                else => .green,
            };

            // Position teams on opposite sides of arena
            // Team 0 (blue): z = +400 (south side)
            // Team 1 (red): z = -400 (north side)
            // Additional teams spread to east/west
            const base_z: f32 = switch (team_idx) {
                0 => 400.0, // Blue team south
                1 => -400.0, // Red team north
                2 => 0.0, // Third team center-east
                else => 0.0, // Fourth team center-west
            };
            const base_x: f32 = switch (team_idx) {
                0, 1 => 0.0, // Main teams centered
                2 => 400.0, // Third team east
                else => -400.0, // Fourth team west
            };

            _ = team
                .withTeam(team_enum)
                .withColor(team_color)
                .withBasePosition(.{
                    .x = base_x,
                    .y = 0,
                    .z = base_z,
                })
                .withSpacing(80.0);

            // Add random characters to team
            for (0..self.config.characters_per_team) |_| {
                var builder = CharacterBuilder.init(self.allocator, self.rng, self.id_gen);
                _ = builder.withTeam(team_enum).withColor(team_color);
                try team.addCharacter(&builder);
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

        // Initialize telemetry
        var telem = try MatchTelemetry.init(self.allocator);

        // Initialize game state with built characters using the builder
        var gs_builder = game_state.GameStateBuilder.init(self.allocator);
        const gs = try gs_builder
            .withRendering(false)
            .withPlayerControl(false)
            .withCharacters(all_chars.items)
            .build();
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

// ============================================================================
// SIMULATION RUNNER
// ============================================================================

/// Executes a simulation and returns match statistics
pub const SimulationRunner = struct {
    context: SimulationContext,
    config: SimulationConfig,

    // Runtime state
    last_feed_tick: u32 = 0,

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
    pub fn run(self: *SimulationRunner) !MatchResult {
        const show_any = self.config.verbosity != .silent;
        const show_header = self.config.verbosity != .silent and self.config.verbosity != .quiet;

        if (show_header) {
            self.printHeader();
        }

        var tick_count: u32 = 0;
        var last_progress_tick: u32 = 0;

        // Track previous health for death detection
        var prev_health: [12]f32 = undefined;
        for (self.context.game_state.entities[0..self.context.character_count], 0..) |ent, i| {
            prev_health[i] = ent.stats.warmth;
        }

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

            // Detect deaths for combat feed
            if (self.config.show_combat_feed) {
                for (self.context.game_state.entities[0..self.context.character_count], 0..) |ent, i| {
                    if (prev_health[i] > 0 and ent.stats.warmth <= 0) {
                        print("{s}  [KILL]{s} {s}{s}{s} has been eliminated!\n", .{
                            TeamColors.RED,
                            TeamColors.RESET,
                            teamColor(ent.team),
                            ent.name,
                            TeamColors.RESET,
                        });
                    }
                    prev_health[i] = ent.stats.warmth;
                }
            }

            // Progress update
            if (self.config.show_progress and tick_count - last_progress_tick >= self.config.progress_interval) {
                progressBar(tick_count, self.config.max_ticks, 30);
                last_progress_tick = tick_count;
            }

            // Check if combat is over
            var blue_alive: u8 = 0;
            var red_alive: u8 = 0;

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
                break;
            }
        }

        // Clear progress line
        if (self.config.show_progress) {
            print("\r{s:50}\r", .{""});
        }

        // Build result
        var result = self.buildResult(tick_count);

        // Record winner in telemetry
        if (self.config.enable_telemetry) {
            self.context.telemetry.match_duration_ticks = tick_count;
            if (result.winner) |w| {
                self.context.telemetry.winning_team = if (w == .blue) 0 else 1;
            }
        }

        // Output based on verbosity
        if (show_any) {
            if (self.config.verbosity == .quiet) {
                result.format();
            } else {
                self.printScoreboard(tick_count, result);
            }
        }

        if (self.config.verbosity == .verbose or self.config.verbosity == .debug) {
            self.context.telemetry.printSummary();
        }

        // Export JSON
        if (self.config.enable_telemetry and self.config.export_json) {
            try self.context.telemetry.exportJSON(self.context.allocator, self.config.telemetry_filename);
            if (self.config.verbosity == .verbose or self.config.verbosity == .debug) {
                print("\n{s}Telemetry exported to: {s}{s}\n", .{ TeamColors.DIM, self.config.telemetry_filename, TeamColors.RESET });
            }
        }

        return result;
    }

    fn printHeader(self: *SimulationRunner) void {
        const format_str = switch (self.config.team_count) {
            2 => if (self.config.characters_per_team == 4) "4v4" else if (self.config.characters_per_team == 3) "3v3" else "2v2",
            3 => "3-WAY",
            4 => "4-WAY",
            else => "BATTLE",
        };

        print("\n{s}╔══════════════════════════════════════════════════╗{s}\n", .{ TeamColors.CYAN, TeamColors.RESET });
        print("{s}║{s}  SNOW BATTLE SIMULATION - {s:<6} {s}║{s}\n", .{
            TeamColors.CYAN,
            TeamColors.WHITE,
            format_str,
            TeamColors.CYAN,
            TeamColors.RESET,
        });
        print("{s}╚══════════════════════════════════════════════════╝{s}\n\n", .{ TeamColors.CYAN, TeamColors.RESET });

        // Show teams
        print("{s}Teams:{s}\n", .{ TeamColors.BOLD, TeamColors.RESET });
        var blue_count: u8 = 0;
        var red_count: u8 = 0;
        for (self.context.game_state.entities[0..self.context.character_count]) |ent| {
            if (ent.team == .blue) blue_count += 1 else red_count += 1;
        }
        print("  {s}BLUE{s}: {d} fighters\n", .{ TeamColors.BLUE, TeamColors.RESET, blue_count });
        print("  {s}RED{s}:  {d} fighters\n\n", .{ TeamColors.RED, TeamColors.RESET, red_count });
    }

    fn printScoreboard(self: *SimulationRunner, tick_count: u32, result: MatchResult) void {
        print("\n{s}═══════════════════ MATCH COMPLETE ═══════════════════{s}\n\n", .{ TeamColors.CYAN, TeamColors.RESET });

        // Winner announcement
        if (result.winner) |winner| {
            const color = teamColor(winner);
            const name = switch (winner) {
                .blue => "BLUE",
                .red => "RED",
                .yellow => "YELLOW",
                .green => "GREEN",
                .none => "NONE",
            };
            print("  {s}{s}*** {s} TEAM WINS ***{s}\n\n", .{ TeamColors.BOLD, color, name, TeamColors.RESET });
        } else {
            print("  {s}*** DRAW ***{s}\n\n", .{ TeamColors.DIM, TeamColors.RESET });
        }

        // Match stats
        print("  Duration: {d} ticks ({d:.1}s)\n", .{ tick_count, @as(f32, @floatFromInt(tick_count)) * 0.05 });
        print("  Survivors: {s}BLUE{s} {d} | {s}RED{s} {d}\n\n", .{
            TeamColors.BLUE,
            TeamColors.RESET,
            result.blue_survivors,
            TeamColors.RED,
            TeamColors.RESET,
            result.red_survivors,
        });

        // Scoreboard
        print("  {s}┌─────────────────┬────────┬────────┬─────────┬─────────┐{s}\n", .{ TeamColors.DIM, TeamColors.RESET });
        print("  {s}│{s} {s}Name{s}            {s}│{s} School {s}│{s}  DMG   {s}│{s}  HEAL  {s}│{s}  K/D   {s}│{s}\n", .{
            TeamColors.DIM,
            TeamColors.RESET,
            TeamColors.BOLD,
            TeamColors.RESET,
            TeamColors.DIM,
            TeamColors.RESET,
            TeamColors.DIM,
            TeamColors.RESET,
            TeamColors.DIM,
            TeamColors.RESET,
            TeamColors.DIM,
            TeamColors.RESET,
            TeamColors.DIM,
            TeamColors.RESET,
        });
        print("  {s}├─────────────────┼────────┼────────┼─────────┼─────────┤{s}\n", .{ TeamColors.DIM, TeamColors.RESET });

        for (self.context.telemetry.entities_array[0..self.context.telemetry.entities_count]) |stat| {
            const color = if (stat.team == 0) TeamColors.BLUE else TeamColors.RED;
            const alive = stat.deaths == 0;
            const status = if (alive) " " else "X";

            print("  {s}│{s} {s}{s}{s:<14}{s}{s} {s}│{s} {s:<6} {s}│{s} {d:>6.0} {s}│{s} {d:>7.0} {s}│{s} {d}/{d}     {s}│{s}\n", .{
                TeamColors.DIM,
                TeamColors.RESET,
                color,
                status,
                stat.name,
                TeamColors.RESET,
                if (!alive) TeamColors.DIM else "",
                TeamColors.DIM,
                TeamColors.RESET,
                stat.school[0..@min(6, stat.school.len)],
                TeamColors.DIM,
                TeamColors.RESET,
                stat.damage_dealt,
                TeamColors.DIM,
                TeamColors.RESET,
                stat.healing_dealt,
                TeamColors.DIM,
                TeamColors.RESET,
                stat.kills,
                stat.deaths,
                TeamColors.DIM,
                TeamColors.RESET,
            });
        }

        print("  {s}└─────────────────┴────────┴────────┴─────────┴─────────┘{s}\n\n", .{ TeamColors.DIM, TeamColors.RESET });

        // MVP
        if (result.mvp_id) |_| {
            print("  {s}MVP:{s} {d:.0} damage dealt\n\n", .{ TeamColors.MAGENTA, TeamColors.RESET, result.mvp_damage });
        }
    }

    fn buildResult(self: *SimulationRunner, tick_count: u32) MatchResult {
        var blue_alive: u8 = 0;
        var red_alive: u8 = 0;
        var total_damage: f32 = 0;
        var total_healing: f32 = 0;
        var mvp_id: ?u32 = null;
        var mvp_damage: f32 = 0;

        for (self.context.game_state.entities[0..self.context.character_count]) |ch| {
            if (ch.isAlive()) {
                if (ch.team == .blue) blue_alive += 1 else red_alive += 1;
            }
        }

        for (self.context.telemetry.entities_array[0..self.context.telemetry.entities_count]) |stat| {
            total_damage += stat.damage_dealt;
            total_healing += stat.healing_dealt;

            if (stat.damage_dealt > mvp_damage) {
                mvp_damage = stat.damage_dealt;
                mvp_id = stat.entity_id;
            }
        }

        const winner: ?entity.Team = if (blue_alive > 0 and red_alive == 0)
            .blue
        else if (red_alive > 0 and blue_alive == 0)
            .red
        else
            null;

        return .{
            .winner = winner,
            .duration_ticks = tick_count,
            .blue_survivors = blue_alive,
            .red_survivors = red_alive,
            .total_damage = total_damage,
            .total_healing = total_healing,
            .mvp_id = mvp_id,
            .mvp_damage = mvp_damage,
        };
    }
};

// ============================================================================
// QUICK SIMULATION - For rapid batch testing
// ============================================================================

/// Run a quick simulation and return just the result
pub fn quickBattle(allocator: std.mem.Allocator, rng: *std.Random, id_gen: *entity.EntityIdGenerator, team_size: usize) !MatchResult {
    var sim_factory = SimulationFactory.init(allocator, rng, id_gen);
    defer sim_factory.deinit();

    const context = try sim_factory
        .withTeamCount(2)
        .withCharactersPerTeam(team_size)
        .withMaxTicks(10000)
        .withVerbosity(.silent)
        .withJsonExport(false)
        .build();

    var runner = SimulationRunner.init(context, sim_factory.config);
    defer runner.deinit();

    return try runner.run();
}

/// Run multiple battles and aggregate results
pub fn batchBattle(
    allocator: std.mem.Allocator,
    rng: *std.Random,
    id_gen: *entity.EntityIdGenerator,
    team_size: usize,
    num_battles: u32,
) !BatchResult {
    var result = BatchResult{};

    print("\n{s}Running {d} battles...{s}\n", .{ TeamColors.CYAN, num_battles, TeamColors.RESET });

    var i: u32 = 0;
    while (i < num_battles) : (i += 1) {
        const match = try quickBattle(allocator, rng, id_gen, team_size);

        result.total_battles += 1;
        result.total_ticks += match.duration_ticks;
        result.total_damage += match.total_damage;

        if (match.winner) |w| {
            if (w == .blue) {
                result.blue_wins += 1;
            } else {
                result.red_wins += 1;
            }
        } else {
            result.draws += 1;
        }

        // Progress
        if ((i + 1) % 10 == 0 or i + 1 == num_battles) {
            print("\r  Progress: {d}/{d} battles", .{ i + 1, num_battles });
        }
    }

    print("\n\n", .{});
    result.display();

    return result;
}

pub const BatchResult = struct {
    total_battles: u32 = 0,
    blue_wins: u32 = 0,
    red_wins: u32 = 0,
    draws: u32 = 0,
    total_ticks: u64 = 0,
    total_damage: f64 = 0,

    pub fn blueWinRate(self: BatchResult) f32 {
        if (self.total_battles == 0) return 0;
        return @as(f32, @floatFromInt(self.blue_wins)) / @as(f32, @floatFromInt(self.total_battles)) * 100.0;
    }

    pub fn avgDuration(self: BatchResult) f32 {
        if (self.total_battles == 0) return 0;
        return @as(f32, @floatFromInt(self.total_ticks)) / @as(f32, @floatFromInt(self.total_battles));
    }

    pub fn display(self: BatchResult) void {
        std.debug.print("{s}═══════════════════ BATCH RESULTS ═══════════════════{s}\n\n", .{ TeamColors.CYAN, TeamColors.RESET });
        std.debug.print("  Battles: {d}\n", .{self.total_battles});
        std.debug.print("  {s}BLUE{s} wins: {d} ({d:.1}%%)\n", .{ TeamColors.BLUE, TeamColors.RESET, self.blue_wins, self.blueWinRate() });
        std.debug.print("  {s}RED{s} wins:  {d} ({d:.1}%%)\n", .{ TeamColors.RED, TeamColors.RESET, self.red_wins, 100.0 - self.blueWinRate() - @as(f32, @floatFromInt(self.draws)) / @as(f32, @floatFromInt(self.total_battles)) * 100.0 });
        std.debug.print("  Draws:    {d}\n", .{self.draws});
        std.debug.print("  Avg duration: {d:.0} ticks ({d:.1}s)\n\n", .{ self.avgDuration(), self.avgDuration() * 0.05 });
    }
};
