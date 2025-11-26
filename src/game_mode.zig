const std = @import("std");
const rl = @import("raylib");
const game_state = @import("game_state.zig");
const factory = @import("factory.zig");
const skills = @import("skills.zig");
const school = @import("school.zig");

const GameState = game_state.GameState;
const Character = @import("character.zig").Character;

// ============================================
// GAME MODE INTERFACE
// ============================================
// Modes sit ABOVE GameState - they orchestrate matches, handle meta-game,
// and manage progression. GameState is the combat/match engine.

/// Result of a completed mode or phase transition
pub const ModeResult = union(enum) {
    /// Mode is still running
    running,
    /// Player won - advance
    victory: VictoryData,
    /// Player lost - handle based on mode
    defeat: DefeatData,
    /// Player quit/aborted
    aborted,
    /// Transition to another mode
    transition: TransitionData,

    pub const VictoryData = struct {
        score: u32 = 0,
        // Loot, rewards, etc. can go here
    };

    pub const DefeatData = struct {
        final_score: u32 = 0,
        rounds_survived: u32 = 0,
    };

    pub const TransitionData = struct {
        target_mode: ModeType,
        // Could carry state between modes
    };
};

/// Phase within a mode (modes can have sub-phases)
pub const Phase = enum {
    // Shared phases
    initializing,

    // Arena phases
    lobby, // Team selection, loadout
    draft, // For limited/draft modes
    match_ready, // Countdown before match
    match_active, // Combat in progress
    match_result, // Victory/defeat screen

    // Roguelike phases
    run_start, // New run begins
    encounter_select, // Choose next encounter
    encounter_active, // In combat
    upgrade_select, // Choose upgrades/rewards
    shop, // Buy items
    run_complete, // Successfully completed
    run_failed, // Permadeath

    // Arc (Nightreign) phases
    act_intro, // Story/cutscene
    exploration, // Moving through world
    boss_encounter, // Major fight
    act_complete, // End of act
    finale, // Final boss
};

/// Types of game modes
pub const ModeType = enum {
    main_menu,
    arena_quickplay, // Jump into a match
    arena_limited, // Limited skill pool
    arena_constructed, // Bring your own build
    roguelike, // Endless campaign
    arc, // Nightreign 3-act
};

// ============================================
// ARENA CONFIGURATION
// ============================================

/// Arena format configuration
pub const ArenaFormat = enum {
    duel_1v1,
    teams_2v2,
    teams_3v3,
    teams_4v4,
    ffa_3way, // 1v1v1
    ffa_4way, // 1v1v1v1
    team_ffa_2v2v2, // Three 2-player teams
    team_ffa_2v2v2v2, // Four 2-player teams

    pub fn teamCount(self: ArenaFormat) usize {
        return switch (self) {
            .duel_1v1, .teams_2v2, .teams_3v3, .teams_4v4 => 2,
            .ffa_3way, .team_ffa_2v2v2 => 3,
            .ffa_4way, .team_ffa_2v2v2v2 => 4,
        };
    }

    pub fn charactersPerTeam(self: ArenaFormat) usize {
        return switch (self) {
            .duel_1v1, .ffa_3way, .ffa_4way => 1,
            .teams_2v2, .team_ffa_2v2v2, .team_ffa_2v2v2v2 => 2,
            .teams_3v3 => 3,
            .teams_4v4 => 4,
        };
    }
};

/// Arena draft rules
pub const DraftRules = enum {
    none, // Quickplay - random or preset
    limited, // Pick from random pool
    constructed, // Bring your build
    ban_pick, // Competitive draft with bans
};

// ============================================
// ROGUELIKE CONFIGURATION
// ============================================

/// Encounter types for roguelike mode
pub const EncounterType = enum {
    combat_easy,
    combat_normal,
    combat_elite,
    combat_boss,
    event, // Non-combat choice
    shop,
    rest, // Heal up
    treasure, // Free reward
};

/// Roguelike run state (persists across encounters)
pub const RunState = struct {
    current_floor: u32 = 1,
    gold: u32 = 100,
    score: u32 = 0,

    // Character progression within run
    // TODO: skill unlocks, stat upgrades, items

    pub fn reset(self: *RunState) void {
        self.current_floor = 1;
        self.gold = 100;
        self.score = 0;
    }
};

// ============================================
// ARC (NIGHTREIGN) CONFIGURATION
// ============================================

/// Acts in the Nightreign-style campaign
pub const Act = enum {
    act_1, // Playground Politics
    act_2, // Neighborhood Wars
    act_3, // The Final Bell
};

/// Arc campaign state
pub const ArcState = struct {
    current_act: Act = .act_1,
    checkpoints_reached: u8 = 0,
    story_flags: u32 = 0, // Bitfield for story decisions

    pub fn reset(self: *ArcState) void {
        self.current_act = .act_1;
        self.checkpoints_reached = 0;
        self.story_flags = 0;
    }
};

// ============================================
// GAME MODE STRUCT
// ============================================

/// GameMode manages the meta-game loop around combat
/// It owns GameState instances and orchestrates matches
pub const GameMode = struct {
    allocator: std.mem.Allocator,
    mode_type: ModeType,
    phase: Phase,
    result: ModeResult,

    // The current combat instance (null between matches)
    game_state: ?*GameState,

    // Mode-specific state
    arena_format: ArenaFormat,
    draft_rules: DraftRules,
    run_state: RunState,
    arc_state: ArcState,

    // Match tracking
    matches_played: u32,
    matches_won: u32,

    // UI state
    selected_menu_item: usize,
    countdown_timer: f32,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, mode_type: ModeType) Self {
        return .{
            .allocator = allocator,
            .mode_type = mode_type,
            .phase = .initializing,
            .result = .running,
            .game_state = null,
            .arena_format = .teams_4v4,
            .draft_rules = .none,
            .run_state = .{},
            .arc_state = .{},
            .matches_played = 0,
            .matches_won = 0,
            .selected_menu_item = 0,
            .countdown_timer = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.game_state) |gs| {
            gs.deinit();
            self.allocator.destroy(gs);
            self.game_state = null;
        }
    }

    // ========================================
    // CORE UPDATE LOOP
    // ========================================

    pub fn update(self: *Self) void {
        switch (self.mode_type) {
            .main_menu => self.updateMainMenu(),
            .arena_quickplay, .arena_limited, .arena_constructed => self.updateArena(),
            .roguelike => self.updateRoguelike(),
            .arc => self.updateArc(),
        }
    }

    pub fn draw(self: *Self) void {
        switch (self.mode_type) {
            .main_menu => self.drawMainMenu(),
            .arena_quickplay, .arena_limited, .arena_constructed => self.drawArena(),
            .roguelike => self.drawRoguelike(),
            .arc => self.drawArc(),
        }
    }

    pub fn drawUI(self: *Self) void {
        switch (self.mode_type) {
            .main_menu => self.drawMainMenuUI(),
            .arena_quickplay, .arena_limited, .arena_constructed => self.drawArenaUI(),
            .roguelike => self.drawRoguelikeUI(),
            .arc => self.drawArcUI(),
        }
    }

    // ========================================
    // MAIN MENU
    // ========================================

    fn updateMainMenu(self: *Self) void {
        // Handle menu navigation
        if (rl.isKeyPressed(.up) or rl.isKeyPressed(.w)) {
            if (self.selected_menu_item > 0) {
                self.selected_menu_item -= 1;
            }
        }
        if (rl.isKeyPressed(.down) or rl.isKeyPressed(.s)) {
            if (self.selected_menu_item < 3) {
                self.selected_menu_item += 1;
            }
        }

        // Handle selection
        if (rl.isKeyPressed(.enter) or rl.isKeyPressed(.space)) {
            self.result = switch (self.selected_menu_item) {
                0 => .{ .transition = .{ .target_mode = .arena_quickplay } },
                1 => .{ .transition = .{ .target_mode = .roguelike } },
                2 => .{ .transition = .{ .target_mode = .arc } },
                else => .running,
            };
        }
    }

    fn drawMainMenu(self: *Self) void {
        _ = self;
        rl.clearBackground(rl.Color.init(40, 44, 52, 255));
    }

    fn drawMainMenuUI(self: *Self) void {
        const screen_width = rl.getScreenWidth();
        const screen_height = rl.getScreenHeight();
        const center_x = @divTrunc(screen_width, 2);
        const center_y = @divTrunc(screen_height, 2);

        // Title
        const title = "SNOW";
        const title_width = rl.measureText(title, 80);
        rl.drawText(title, center_x - @divTrunc(title_width, 2), center_y - 200, 80, rl.Color.white);

        // Subtitle - the vibe
        const subtitle = "\"Saving Private Ryan\" meets Recess";
        const subtitle_width = rl.measureText(subtitle, 20);
        rl.drawText(subtitle, center_x - @divTrunc(subtitle_width, 2), center_y - 110, 20, rl.Color.gray);

        // Menu items
        const menu_items = [_][]const u8{
            "Arena Battle",
            "Roguelike Campaign",
            "The Arc (3-Act)",
            "Quit",
        };

        const item_height: i32 = 40;
        const start_y = center_y - 20;

        for (menu_items, 0..) |item, i| {
            const y = start_y + @as(i32, @intCast(i)) * item_height;
            const color = if (i == self.selected_menu_item) rl.Color.yellow else rl.Color.white;
            const prefix: []const u8 = if (i == self.selected_menu_item) "> " else "  ";

            var buf: [64:0]u8 = undefined;
            const text = std.fmt.bufPrintZ(&buf, "{s}{s}", .{ prefix, item }) catch "???";
            const text_width = rl.measureText(text, 30);
            rl.drawText(text, center_x - @divTrunc(text_width, 2), y, 30, color);
        }

        // Instructions
        const instructions = "[W/S or Arrows] Navigate  [Enter/Space] Select";
        const inst_width = rl.measureText(instructions, 16);
        rl.drawText(instructions, center_x - @divTrunc(inst_width, 2), screen_height - 50, 16, rl.Color.gray);
    }

    // ========================================
    // ARENA MODE
    // ========================================

    fn updateArena(self: *Self) void {
        switch (self.phase) {
            .initializing => {
                self.phase = .lobby;
            },
            .lobby => {
                // For quickplay, just start immediately
                if (self.mode_type == .arena_quickplay) {
                    if (rl.isKeyPressed(.enter) or rl.isKeyPressed(.space)) {
                        self.startArenaMatch();
                    }
                }
                // Format selection
                if (rl.isKeyPressed(.one)) self.arena_format = .duel_1v1;
                if (rl.isKeyPressed(.two)) self.arena_format = .teams_2v2;
                if (rl.isKeyPressed(.three)) self.arena_format = .teams_3v3;
                if (rl.isKeyPressed(.four)) self.arena_format = .teams_4v4;

                // Back to menu
                if (rl.isKeyPressed(.escape)) {
                    self.result = .{ .transition = .{ .target_mode = .main_menu } };
                }
            },
            .match_active => {
                if (self.game_state) |gs| {
                    gs.update();

                    // Check if match ended
                    if (gs.combat_state != .active) {
                        self.phase = .match_result;
                        self.matches_played += 1;
                        if (gs.combat_state == .victory) {
                            self.matches_won += 1;
                        }
                    }
                }
            },
            .match_result => {
                // Press any key to continue
                if (rl.isKeyPressed(.enter) or rl.isKeyPressed(.space)) {
                    self.cleanupMatch();
                    self.phase = .lobby;
                }
                if (rl.isKeyPressed(.escape)) {
                    self.cleanupMatch();
                    self.result = .{ .transition = .{ .target_mode = .main_menu } };
                }
            },
            else => {},
        }
    }

    fn startArenaMatch(self: *Self) void {
        // Clean up any existing match
        self.cleanupMatch();

        // Create new GameState for this match
        const gs_ptr = self.allocator.create(GameState) catch {
            std.log.err("Failed to allocate GameState", .{});
            return;
        };

        var builder = game_state.GameStateBuilder.init(self.allocator);
        _ = builder.withRendering(true);
        _ = builder.withPlayerControl(true);
        _ = builder.withCharactersPerTeam(self.arena_format.charactersPerTeam());
        // TODO: Support team_count in builder for FFA modes

        gs_ptr.* = builder.build() catch {
            std.log.err("Failed to build GameState", .{});
            self.allocator.destroy(gs_ptr);
            return;
        };

        self.game_state = gs_ptr;
        self.phase = .match_active;
    }

    fn cleanupMatch(self: *Self) void {
        if (self.game_state) |gs| {
            gs.deinit();
            self.allocator.destroy(gs);
            self.game_state = null;
        }
    }

    fn drawArena(self: *Self) void {
        switch (self.phase) {
            .match_active => {
                if (self.game_state) |gs| {
                    gs.draw();
                }
            },
            else => {
                rl.clearBackground(rl.Color.init(30, 35, 45, 255));
            },
        }
    }

    fn drawArenaUI(self: *Self) void {
        switch (self.phase) {
            .lobby => self.drawArenaLobbyUI(),
            .match_active => {
                if (self.game_state) |gs| {
                    gs.drawUI();
                }
            },
            .match_result => self.drawArenaResultUI(),
            else => {},
        }
    }

    fn drawArenaLobbyUI(self: *Self) void {
        const screen_width = rl.getScreenWidth();
        const screen_height = rl.getScreenHeight();
        const center_x = @divTrunc(screen_width, 2);

        // Title
        const title = "ARENA BATTLE";
        const title_width = rl.measureText(title, 50);
        rl.drawText(title, center_x - @divTrunc(title_width, 2), 50, 50, rl.Color.white);

        // Format display
        const format_name = switch (self.arena_format) {
            .duel_1v1 => "1v1 Duel",
            .teams_2v2 => "2v2 Teams",
            .teams_3v3 => "3v3 Teams",
            .teams_4v4 => "4v4 Teams",
            .ffa_3way => "Free-for-All (3)",
            .ffa_4way => "Free-for-All (4)",
            .team_ffa_2v2v2 => "2v2v2 Team FFA",
            .team_ffa_2v2v2v2 => "2v2v2v2 Team FFA",
        };

        var format_buf: [64:0]u8 = undefined;
        const format_text = std.fmt.bufPrintZ(&format_buf, "Format: {s}", .{format_name}) catch "Format: ???";
        const format_width = rl.measureText(format_text, 30);
        rl.drawText(format_text, center_x - @divTrunc(format_width, 2), 150, 30, rl.Color.yellow);

        // Instructions
        rl.drawText("[1] 1v1  [2] 2v2  [3] 3v3  [4] 4v4", center_x - 180, 220, 20, rl.Color.gray);
        rl.drawText("[Enter/Space] Start Match", center_x - 130, 260, 20, rl.Color.white);
        rl.drawText("[Esc] Back to Menu", center_x - 90, 300, 20, rl.Color.gray);

        // Stats
        var stats_buf: [128:0]u8 = undefined;
        const stats_text = std.fmt.bufPrintZ(&stats_buf, "Record: {d}W - {d}L", .{
            self.matches_won,
            self.matches_played - self.matches_won,
        }) catch "Record: ???";
        rl.drawText(stats_text, 20, screen_height - 40, 20, rl.Color.gray);
    }

    fn drawArenaResultUI(self: *Self) void {
        const screen_width = rl.getScreenWidth();
        const screen_height = rl.getScreenHeight();
        const center_x = @divTrunc(screen_width, 2);
        const center_y = @divTrunc(screen_height, 2);

        // Dim overlay
        rl.drawRectangle(0, 0, screen_width, screen_height, rl.Color.init(0, 0, 0, 180));

        // Result text
        const result_text = if (self.game_state) |gs|
            (if (gs.combat_state == .victory) "VICTORY!" else "DEFEAT")
        else
            "MATCH OVER";

        const result_color = if (self.game_state) |gs|
            (if (gs.combat_state == .victory) rl.Color.green else rl.Color.red)
        else
            rl.Color.white;

        const result_width = rl.measureText(result_text, 60);
        rl.drawText(result_text, center_x - @divTrunc(result_width, 2), center_y - 50, 60, result_color);

        // Continue prompt
        const continue_text = "[Enter] Play Again  [Esc] Menu";
        const continue_width = rl.measureText(continue_text, 20);
        rl.drawText(continue_text, center_x - @divTrunc(continue_width, 2), center_y + 50, 20, rl.Color.white);
    }

    // ========================================
    // ROGUELIKE MODE
    // ========================================

    fn updateRoguelike(self: *Self) void {
        switch (self.phase) {
            .initializing => {
                self.run_state.reset();
                self.phase = .run_start;
            },
            .run_start => {
                // Press to begin run
                if (rl.isKeyPressed(.enter) or rl.isKeyPressed(.space)) {
                    self.phase = .encounter_select;
                }
                if (rl.isKeyPressed(.escape)) {
                    self.result = .{ .transition = .{ .target_mode = .main_menu } };
                }
            },
            .encounter_select => {
                // For prototype: auto-start combat encounter
                if (rl.isKeyPressed(.enter) or rl.isKeyPressed(.space)) {
                    self.startRoguelikeEncounter();
                }
                if (rl.isKeyPressed(.escape)) {
                    self.result = .{ .transition = .{ .target_mode = .main_menu } };
                }
            },
            .encounter_active => {
                if (self.game_state) |gs| {
                    gs.update();

                    if (gs.combat_state != .active) {
                        if (gs.combat_state == .victory) {
                            self.run_state.score += 100;
                            self.run_state.current_floor += 1;
                            self.cleanupMatch();
                            self.phase = .upgrade_select;
                        } else {
                            // Permadeath!
                            self.phase = .run_failed;
                        }
                    }
                }
            },
            .upgrade_select => {
                // TODO: Show upgrade choices
                // For now, just continue
                if (rl.isKeyPressed(.enter) or rl.isKeyPressed(.space)) {
                    self.phase = .encounter_select;
                }
            },
            .run_failed => {
                if (rl.isKeyPressed(.enter) or rl.isKeyPressed(.space)) {
                    self.cleanupMatch();
                    self.run_state.reset();
                    self.phase = .run_start;
                }
                if (rl.isKeyPressed(.escape)) {
                    self.cleanupMatch();
                    self.result = .{ .transition = .{ .target_mode = .main_menu } };
                }
            },
            else => {},
        }
    }

    fn startRoguelikeEncounter(self: *Self) void {
        self.cleanupMatch();

        const gs_ptr = self.allocator.create(GameState) catch {
            std.log.err("Failed to allocate GameState", .{});
            return;
        };

        // Scale difficulty with floor
        const enemies_per_team: usize = @min(4, 1 + self.run_state.current_floor / 3);

        var builder = game_state.GameStateBuilder.init(self.allocator);
        _ = builder.withRendering(true);
        _ = builder.withPlayerControl(true);
        _ = builder.withCharactersPerTeam(enemies_per_team);

        gs_ptr.* = builder.build() catch {
            std.log.err("Failed to build GameState", .{});
            self.allocator.destroy(gs_ptr);
            return;
        };

        self.game_state = gs_ptr;
        self.phase = .encounter_active;
    }

    fn drawRoguelike(self: *Self) void {
        switch (self.phase) {
            .encounter_active => {
                if (self.game_state) |gs| {
                    gs.draw();
                }
            },
            else => {
                rl.clearBackground(rl.Color.init(25, 30, 40, 255));
            },
        }
    }

    fn drawRoguelikeUI(self: *Self) void {
        const screen_width = rl.getScreenWidth();
        const screen_height = rl.getScreenHeight();
        const center_x = @divTrunc(screen_width, 2);

        switch (self.phase) {
            .run_start => {
                const title = "ENDLESS CAMPAIGN";
                const title_width = rl.measureText(title, 50);
                rl.drawText(title, center_x - @divTrunc(title_width, 2), 100, 50, rl.Color.white);

                const desc = "Survive as long as you can. Death is permanent.";
                const desc_width = rl.measureText(desc, 20);
                rl.drawText(desc, center_x - @divTrunc(desc_width, 2), 180, 20, rl.Color.gray);

                rl.drawText("[Enter] Begin Run", center_x - 80, 300, 20, rl.Color.white);
                rl.drawText("[Esc] Back", center_x - 50, 340, 20, rl.Color.gray);
            },
            .encounter_select => {
                var floor_buf: [64:0]u8 = undefined;
                const floor_text = std.fmt.bufPrintZ(&floor_buf, "Floor {d}", .{self.run_state.current_floor}) catch "Floor ???";
                const floor_width = rl.measureText(floor_text, 40);
                rl.drawText(floor_text, center_x - @divTrunc(floor_width, 2), 100, 40, rl.Color.white);

                var score_buf: [64:0]u8 = undefined;
                const score_text = std.fmt.bufPrintZ(&score_buf, "Score: {d}", .{self.run_state.score}) catch "Score: ???";
                rl.drawText(score_text, 20, 20, 20, rl.Color.yellow);

                rl.drawText("[Enter] Next Encounter", center_x - 100, 200, 20, rl.Color.white);
            },
            .encounter_active => {
                if (self.game_state) |gs| {
                    gs.drawUI();
                }
                // Overlay run info
                var floor_buf: [64:0]u8 = undefined;
                const floor_text = std.fmt.bufPrintZ(&floor_buf, "Floor {d} | Score: {d}", .{
                    self.run_state.current_floor,
                    self.run_state.score,
                }) catch "Floor ???";
                rl.drawText(floor_text, 20, 20, 20, rl.Color.yellow);
            },
            .upgrade_select => {
                const title = "VICTORY!";
                const title_width = rl.measureText(title, 50);
                rl.drawText(title, center_x - @divTrunc(title_width, 2), 100, 50, rl.Color.green);

                rl.drawText("(Upgrades coming soon)", center_x - 100, 200, 20, rl.Color.gray);
                rl.drawText("[Enter] Continue", center_x - 70, 280, 20, rl.Color.white);
            },
            .run_failed => {
                const title = "RUN OVER";
                const title_width = rl.measureText(title, 50);
                rl.drawText(title, center_x - @divTrunc(title_width, 2), 100, 50, rl.Color.red);

                var score_buf: [128:0]u8 = undefined;
                const score_text = std.fmt.bufPrintZ(&score_buf, "Final Score: {d} | Reached Floor {d}", .{
                    self.run_state.score,
                    self.run_state.current_floor,
                }) catch "Final Score: ???";
                const score_width = rl.measureText(score_text, 25);
                rl.drawText(score_text, center_x - @divTrunc(score_width, 2), 180, 25, rl.Color.white);

                rl.drawText("[Enter] Try Again  [Esc] Menu", center_x - 140, screen_height - 100, 20, rl.Color.gray);
            },
            else => {},
        }
    }

    // ========================================
    // ARC (NIGHTREIGN) MODE
    // ========================================

    fn updateArc(self: *Self) void {
        switch (self.phase) {
            .initializing => {
                self.arc_state.reset();
                self.phase = .act_intro;
            },
            .act_intro => {
                if (rl.isKeyPressed(.enter) or rl.isKeyPressed(.space)) {
                    self.startArcEncounter();
                }
                if (rl.isKeyPressed(.escape)) {
                    self.result = .{ .transition = .{ .target_mode = .main_menu } };
                }
            },
            .boss_encounter => {
                if (self.game_state) |gs| {
                    gs.update();

                    if (gs.combat_state != .active) {
                        if (gs.combat_state == .victory) {
                            self.cleanupMatch();
                            self.advanceArc();
                        } else {
                            // Can retry in arc mode (checkpoint)
                            self.phase = .act_intro;
                            self.cleanupMatch();
                        }
                    }
                }
            },
            .act_complete => {
                if (rl.isKeyPressed(.enter) or rl.isKeyPressed(.space)) {
                    self.advanceToNextAct();
                }
            },
            .finale => {
                // Completed the game!
                if (rl.isKeyPressed(.enter) or rl.isKeyPressed(.space)) {
                    self.result = .{ .transition = .{ .target_mode = .main_menu } };
                }
            },
            else => {},
        }
    }

    fn startArcEncounter(self: *Self) void {
        self.cleanupMatch();

        const gs_ptr = self.allocator.create(GameState) catch {
            std.log.err("Failed to allocate GameState", .{});
            return;
        };

        // Act determines difficulty
        const team_size: usize = switch (self.arc_state.current_act) {
            .act_1 => 2,
            .act_2 => 3,
            .act_3 => 4,
        };

        var builder = game_state.GameStateBuilder.init(self.allocator);
        _ = builder.withRendering(true);
        _ = builder.withPlayerControl(true);
        _ = builder.withCharactersPerTeam(team_size);

        gs_ptr.* = builder.build() catch {
            std.log.err("Failed to build GameState", .{});
            self.allocator.destroy(gs_ptr);
            return;
        };

        self.game_state = gs_ptr;
        self.phase = .boss_encounter;
    }

    fn advanceArc(self: *Self) void {
        self.arc_state.checkpoints_reached += 1;
        self.phase = .act_complete;
    }

    fn advanceToNextAct(self: *Self) void {
        switch (self.arc_state.current_act) {
            .act_1 => {
                self.arc_state.current_act = .act_2;
                self.phase = .act_intro;
            },
            .act_2 => {
                self.arc_state.current_act = .act_3;
                self.phase = .act_intro;
            },
            .act_3 => {
                self.phase = .finale;
            },
        }
    }

    fn drawArc(self: *Self) void {
        switch (self.phase) {
            .boss_encounter => {
                if (self.game_state) |gs| {
                    gs.draw();
                }
            },
            else => {
                rl.clearBackground(rl.Color.init(20, 25, 35, 255));
            },
        }
    }

    fn drawArcUI(self: *Self) void {
        const screen_width = rl.getScreenWidth();
        const screen_height = rl.getScreenHeight();
        const center_x = @divTrunc(screen_width, 2);
        const center_y = @divTrunc(screen_height, 2);

        switch (self.phase) {
            .act_intro => {
                // Get act-specific text
                const title: [:0]const u8 = switch (self.arc_state.current_act) {
                    .act_1 => "ACT I",
                    .act_2 => "ACT II",
                    .act_3 => "ACT III",
                };
                const subtitle: [:0]const u8 = switch (self.arc_state.current_act) {
                    .act_1 => "Playground Politics",
                    .act_2 => "Neighborhood Wars",
                    .act_3 => "The Final Bell",
                };
                const desc: [:0]const u8 = switch (self.arc_state.current_act) {
                    .act_1 => "The first snowfall of winter. Tensions rise on the playground.",
                    .act_2 => "The conflict spreads beyond school grounds.",
                    .act_3 => "Everything comes down to this moment.",
                };

                const title_width = rl.measureText(title, 60);
                rl.drawText(title, center_x - @divTrunc(title_width, 2), center_y - 100, 60, rl.Color.white);

                const subtitle_width = rl.measureText(subtitle, 30);
                rl.drawText(subtitle, center_x - @divTrunc(subtitle_width, 2), center_y - 30, 30, rl.Color.yellow);

                const desc_width = rl.measureText(desc, 18);
                rl.drawText(desc, center_x - @divTrunc(desc_width, 2), center_y + 30, 18, rl.Color.gray);

                rl.drawText("[Enter] Begin", center_x - 60, center_y + 100, 20, rl.Color.white);
                rl.drawText("[Esc] Back", center_x - 45, center_y + 130, 16, rl.Color.gray);
            },
            .boss_encounter => {
                if (self.game_state) |gs| {
                    gs.drawUI();
                }
                // Act indicator
                const act_text = switch (self.arc_state.current_act) {
                    .act_1 => "Act I - Playground Politics",
                    .act_2 => "Act II - Neighborhood Wars",
                    .act_3 => "Act III - The Final Bell",
                };
                rl.drawText(act_text, 20, 20, 20, rl.Color.yellow);
            },
            .act_complete => {
                const title = "ACT COMPLETE";
                const title_width = rl.measureText(title, 50);
                rl.drawText(title, center_x - @divTrunc(title_width, 2), center_y - 50, 50, rl.Color.green);

                rl.drawText("[Enter] Continue", center_x - 80, center_y + 50, 20, rl.Color.white);
            },
            .finale => {
                const title = "THE END";
                const title_width = rl.measureText(title, 60);
                rl.drawText(title, center_x - @divTrunc(title_width, 2), center_y - 80, 60, rl.Color.gold);

                const desc = "You survived the snowball war.";
                const desc_width = rl.measureText(desc, 25);
                rl.drawText(desc, center_x - @divTrunc(desc_width, 2), center_y, 25, rl.Color.white);

                rl.drawText("[Enter] Main Menu", center_x - 80, screen_height - 100, 20, rl.Color.gray);
            },
            else => {},
        }
    }

    // ========================================
    // HELPERS
    // ========================================

    pub fn isComplete(self: *const Self) bool {
        return self.result != .running;
    }

    pub fn getTargetMode(self: *const Self) ?ModeType {
        return switch (self.result) {
            .transition => |t| t.target_mode,
            else => null,
        };
    }
};
