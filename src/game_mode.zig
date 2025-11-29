const std = @import("std");
const rl = @import("raylib");
const game_state = @import("game_state.zig");
const factory = @import("factory.zig");
const skills = @import("skills.zig");
const school = @import("school.zig");
const campaign = @import("campaign.zig");
const campaign_ui = @import("campaign_ui.zig");
const skill_capture = @import("skill_capture.zig");
const entity = @import("entity.zig");
const palette = @import("color_palette.zig");
const encounter = @import("encounter.zig");
const ai = @import("ai.zig");
const affix_processor = @import("affix_processor.zig");

const GameState = game_state.GameState;
const Character = @import("character.zig").Character;
const CampaignState = campaign.CampaignState;
const CampaignUIState = campaign_ui.CampaignUIState;
const SkillCaptureUIState = skill_capture.SkillCaptureUIState;
const FirstRewardUIState = skill_capture.FirstRewardUIState;
const SkillCaptureChoice = campaign.SkillCaptureChoice;
const EncounterNode = campaign.EncounterNode;
const EncounterConfig = campaign.EncounterConfig;
const GoalType = campaign.GoalType;
const School = school.School;
const Position = @import("position.zig").Position;
const Encounter = encounter.Encounter;
const EnemySpec = encounter.EnemySpec;
const EnemyWave = encounter.EnemyWave;
const BossConfig = encounter.BossConfig;
const HazardZone = encounter.HazardZone;
const HazardZoneState = ai.HazardZoneState;
const AIState = ai.AIState;
const AffixProcessor = affix_processor.AffixProcessor;
const ActiveAffix = encounter.ActiveAffix;

const MAX_COMBAT_CHARS: usize = 16; // Max characters in a single encounter
const MAX_HAZARD_ZONES: usize = 8; // Max active hazard zones per encounter

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

    // Roguelike phases (legacy - being replaced by campaign)
    run_start, // New run begins
    encounter_select, // Choose next encounter
    encounter_active, // In combat
    upgrade_select, // Choose upgrades/rewards
    shop, // Buy items
    run_complete, // Successfully completed
    run_failed, // Permadeath

    // Campaign phases (new roguelike with overworld)
    campaign_setup, // Choose goal, name party
    campaign_overworld, // Viewing map, selecting encounters
    campaign_encounter, // In combat encounter
    campaign_skill_capture, // Post-boss skill capture reward
    campaign_first_reward, // Post-tutorial first bundle selection
    campaign_victory, // Goal achieved
    campaign_defeat, // Party wiped or faction lost

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
// ENCOUNTER GENERATION FROM NODE
// ============================================
// Creates proper Encounter definitions from campaign EncounterNodes.
// This bridges the campaign system with the encounter.zig primitives.

/// Runtime encounter storage - holds generated encounter data
/// Since Encounter uses slices, we need stable storage for runtime-generated encounters
const RuntimeEncounter = struct {
    /// The encounter definition
    enc: Encounter,

    /// Storage for enemy waves (runtime-allocated)
    waves_storage: [4]EnemyWave = undefined,
    wave_count: usize = 0,

    /// Storage for enemies within waves (runtime-allocated)
    enemies_storage: [8]EnemySpec = undefined,
    enemy_count: usize = 0,

    /// Storage for affixes (runtime-generated based on CR)
    affixes_storage: [4]ActiveAffix = undefined,
    affix_count: usize = 0,

    /// Get the encounter with proper slices
    pub fn getEncounter(self: *RuntimeEncounter) *const Encounter {
        // Wire up the slices to our storage
        if (self.wave_count > 0) {
            self.waves_storage[0].enemies = self.enemies_storage[0..self.enemy_count];
            self.enc.enemy_waves = self.waves_storage[0..self.wave_count];
        }
        if (self.affix_count > 0) {
            self.enc.affixes = self.affixes_storage[0..self.affix_count];
        }
        return &self.enc;
    }

    /// Get affixes slice for AffixProcessor
    pub fn getAffixes(self: *RuntimeEncounter) []const ActiveAffix {
        return self.affixes_storage[0..self.affix_count];
    }
};

/// Generate an Encounter definition from an EncounterNode
/// Returns a RuntimeEncounter that owns its data
fn generateEncounterFromNode(node: EncounterNode, party_size: usize, rng: std.Random) RuntimeEncounter {
    var runtime_enc = RuntimeEncounter{
        .enc = Encounter{
            .id = "campaign_encounter",
            .name = node.name,
            .description = "Campaign encounter",
            .difficulty_rating = node.challenge_rating,
            .min_party_size = 1,
            .max_party_size = 6,
            .recommended_party_size = @intCast(@min(party_size, 4)),
        },
    };

    const cr = node.challenge_rating;
    const is_boss = node.encounter_type == .boss_capture;

    // Tutorial encounter (CR 1) is extra easy - just one weak enemy to learn the ropes
    const is_tutorial = cr == 1;

    // Generate affixes based on challenge rating
    // Higher CR = more/stronger affixes (field conditions get tougher!)
    // Tutorial (CR 1) and CR 2: No affixes - keep it simple for newcomers
    var affix_idx: usize = 0;
    if (cr >= 3) {
        // CR 3+: Add layered_up (enemies wearing more layers = tankier)
        runtime_enc.affixes_storage[affix_idx] = .{
            .affix = .layered_up,
            .intensity = 0.8 + (@as(f32, @floatFromInt(cr)) * 0.05),
        };
        affix_idx += 1;
    }
    if (cr >= 5) {
        // CR 5+: Add a random combat modifier (how the other kids fight)
        const combat_affixes = [_]encounter.EncounterAffix{ .rally, .tantrum, .snow_angels };
        const selected = combat_affixes[rng.intRangeAtMost(usize, 0, combat_affixes.len - 1)];
        runtime_enc.affixes_storage[affix_idx] = .{
            .affix = selected,
            .intensity = 1.0,
        };
        affix_idx += 1;
    }
    if (cr >= 7) {
        // CR 7+: Add an environmental affix (weather/field conditions)
        const env_affixes = [_]encounter.EncounterAffix{ .slush_pits, .icy_patches, .blizzard };
        const selected = env_affixes[rng.intRangeAtMost(usize, 0, env_affixes.len - 1)];
        runtime_enc.affixes_storage[affix_idx] = .{
            .affix = selected,
            .intensity = 1.0 + (@as(f32, @floatFromInt(cr - 7)) * 0.1),
        };
        affix_idx += 1;
    }
    if (is_boss) {
        // Bosses always get snowpocalypse (they're THE challenge)
        if (affix_idx < 4) {
            runtime_enc.affixes_storage[affix_idx] = .{
                .affix = .snowpocalypse,
                .intensity = 1.2,
            };
            affix_idx += 1;
        }
    }
    runtime_enc.affix_count = affix_idx;

    // Calculate enemy count based on challenge rating and party size
    // Tutorial: Just 1 enemy so player can learn without feeling overwhelmed
    // Normal: party_size + (cr / 3), capped at 6
    const base_enemies: usize = if (is_boss) 1 else if (is_tutorial) 1 else @min(6, party_size + (cr / 3));

    // Generate enemy specs
    var enemy_idx: usize = 0;
    for (0..base_enemies) |i| {
        if (enemy_idx >= 8) break;

        const is_boss_enemy = is_boss and i == 0;
        const difficulty: u8 = if (is_boss_enemy) 10 else if (is_tutorial) 1 else @min(5, 1 + cr / 2);

        // Vary schools and positions based on challenge rating
        // Tutorial enemy: always a Fielder (straightforward attacker, no heals)
        const enemy_school: School = if (is_tutorial) .public_school else switch (i % 5) {
            0 => .public_school,
            1 => .private_school,
            2 => .montessori,
            3 => .homeschool,
            else => .waldorf,
        };
        const enemy_position: Position = if (is_tutorial) .fielder else switch (i % 6) {
            0 => .pitcher,
            1 => .fielder,
            2 => .shoveler,
            3 => .sledder,
            4 => .animator,
            else => .thermos,
        };

        // Tutorial enemy: significantly weaker (60% warmth, 50% damage)
        // This ensures players can win even with basic starter skills
        const warmth_mult: f32 = if (is_boss_enemy) 3.0 else if (is_tutorial) 0.6 else 0.8 + (@as(f32, @floatFromInt(cr)) * 0.1);
        const damage_mult: f32 = if (is_boss_enemy) 1.5 else if (is_tutorial) 0.5 else 0.8 + (@as(f32, @floatFromInt(cr)) * 0.05);

        runtime_enc.enemies_storage[enemy_idx] = EnemySpec{
            .name = if (is_boss_enemy) "Boss" else if (is_tutorial) "Lost Kid" else "Enemy",
            .school = enemy_school,
            .position = enemy_position,
            .warmth_multiplier = warmth_mult,
            .damage_multiplier = damage_mult,
            .scale = if (is_boss_enemy) 1.5 else 1.0,
            .difficulty_rating = difficulty,
            .is_champion = is_boss_enemy,
            .immune_to_knockdown = is_boss_enemy,
        };
        enemy_idx += 1;
    }
    runtime_enc.enemy_count = enemy_idx;

    // Create a single wave containing all enemies
    if (enemy_idx > 0) {
        runtime_enc.waves_storage[0] = EnemyWave{
            .enemies = &[_]EnemySpec{}, // Will be wired up in getEncounter()
            .spawn_position = .{ .x = 0, .y = 0, .z = -400 },
            .spawn_radius = 80.0,
            .engagement_radius = 200.0,
            .leash_radius = 500.0,
            .respawns_on_wipe = false,
        };
        runtime_enc.wave_count = 1;
    }

    return runtime_enc;
}

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

    // Campaign state (new roguelike system)
    campaign_state: ?*CampaignState,
    campaign_ui_state: CampaignUIState,
    skill_capture_ui_state: ?SkillCaptureUIState,
    first_reward_ui_state: ?FirstRewardUIState,
    current_encounter_node: ?EncounterNode,
    current_encounter_block_id: ?u32,

    // Active encounter data (for boss phase tracking)
    current_runtime_encounter: ?RuntimeEncounter,
    boss_entity_index: ?usize, // Index of boss in entities array (if present)

    // Active hazard zones during combat
    active_hazard_zones: [MAX_HAZARD_ZONES]?HazardZoneState,
    active_hazard_count: usize,

    // Active affix processor for encounters
    affix_processor: ?AffixProcessor,

    // Match tracking
    matches_played: u32,
    matches_won: u32,

    // UI state
    selected_menu_item: usize,
    countdown_timer: f32,

    // RNG for campaign
    prng: std.Random.DefaultPrng,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, mode_type: ModeType) Self {
        // Use timestamp or fixed seed for RNG
        const seed: u64 = @intCast(std.time.milliTimestamp() & 0xFFFFFFFF);

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
            .campaign_state = null,
            .campaign_ui_state = .{},
            .skill_capture_ui_state = null,
            .first_reward_ui_state = null,
            .current_encounter_node = null,
            .current_encounter_block_id = null,
            .current_runtime_encounter = null,
            .boss_entity_index = null,
            .active_hazard_zones = [_]?HazardZoneState{null} ** MAX_HAZARD_ZONES,
            .active_hazard_count = 0,
            .affix_processor = null,
            .matches_played = 0,
            .matches_won = 0,
            .selected_menu_item = 0,
            .countdown_timer = 0,
            .prng = std.Random.DefaultPrng.init(seed),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.game_state) |gs| {
            gs.deinit();
            self.allocator.destroy(gs);
            self.game_state = null;
        }
        if (self.campaign_state) |cs| {
            cs.deinit();
            self.allocator.destroy(cs);
            self.campaign_state = null;
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
        // Clear encounter tracking
        self.current_runtime_encounter = null;
        self.boss_entity_index = null;
        // Clear hazard zones
        self.active_hazard_zones = [_]?HazardZoneState{null} ** MAX_HAZARD_ZONES;
        self.active_hazard_count = 0;
        // Clear affix processor
        self.affix_processor = null;
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
    // ROGUELIKE MODE (Campaign System)
    // ========================================

    fn updateRoguelike(self: *Self) void {
        switch (self.phase) {
            .initializing => {
                // Initialize campaign state
                self.initCampaign() catch {
                    std.log.err("Failed to initialize campaign", .{});
                    self.result = .{ .transition = .{ .target_mode = .main_menu } };
                    return;
                };
                // Start character creation
                self.campaign_ui_state.startCharacterCreation();
                self.phase = .campaign_setup;
            },
            .campaign_setup => {
                // Character creation UI
                if (campaign_ui.handleCharacterCreationInput(&self.campaign_ui_state)) {
                    // Creation complete - setup party with selected options and auto-equipped starter skills
                    if (self.campaign_state) |cs| {
                        cs.setupPartyWithStarterSkills(
                            "Hero",
                            self.campaign_ui_state.selected_school,
                            self.campaign_ui_state.selected_position,
                            "Buddy",
                            self.campaign_ui_state.friend_school,
                            self.campaign_ui_state.friend_position,
                        );
                    }
                    self.campaign_ui_state.mode = .overworld;
                    self.phase = .campaign_overworld;
                }

                // Back to menu
                if (rl.isKeyPressed(.escape) and self.campaign_ui_state.creation_step == 0) {
                    self.cleanupCampaign();
                    self.result = .{ .transition = .{ .target_mode = .main_menu } };
                }
            },
            .campaign_overworld, .run_start, .encounter_select => {
                // Handle campaign UI input
                if (self.campaign_state) |cs| {
                    if (campaign_ui.handleCampaignInput(cs, &self.campaign_ui_state)) |block_id| {
                        // Player selected a polyomino block encounter - start it
                        if (cs.getPolyBlockEncounter(block_id)) |node| {
                            self.current_encounter_node = node;
                            self.current_encounter_block_id = block_id;
                            self.startCampaignEncounter(node);
                        }
                    }
                }

                // Back to menu
                if (rl.isKeyPressed(.escape)) {
                    self.cleanupCampaign();
                    self.result = .{ .transition = .{ .target_mode = .main_menu } };
                }
            },
            .campaign_encounter, .encounter_active => {
                // Update combat
                if (self.game_state) |gs| {
                    // Track which enemies were alive before update (for death processing)
                    var was_alive: [game_state.MAX_ENTITIES]bool = [_]bool{false} ** game_state.MAX_ENTITIES;
                    for (&gs.entities, 0..) |*ent, i| {
                        was_alive[i] = ent.isAlive() and ent.team != .blue;
                    }

                    gs.update();

                    // Check boss phase transitions (if we have a boss)
                    self.checkBossPhaseTransitions(gs);

                    // Process hazard zones (at tick rate ~50ms)
                    // We use frame time here; hazard zones have their own tick timers
                    const frame_time_ms: u32 = @intFromFloat(rl.getFrameTime() * 1000.0);
                    self.processHazardZones(gs, frame_time_ms);

                    // Process encounter affixes (environmental effects, etc.)
                    self.processAffixes(gs, frame_time_ms);

                    // Process enemy deaths for affix effects (bolstering, bursting, sanguine)
                    self.processEnemyDeaths(gs, &was_alive);

                    // Check if combat ended
                    if (gs.combat_state != .active) {
                        self.handleEncounterResult(gs.combat_state == .victory);
                    }
                }
            },
            .campaign_skill_capture, .upgrade_select => {
                // Update skill capture UI animation
                if (self.skill_capture_ui_state) |*ui_state| {
                    ui_state.update(rl.getFrameTime());

                    // Handle input
                    if (skill_capture.handleSkillCaptureInput(ui_state)) {
                        // Choice confirmed - apply it
                        if (self.campaign_state) |cs| {
                            skill_capture.applySkillCaptureChoice(cs, ui_state);
                        }
                        self.skill_capture_ui_state = null;
                        self.advanceCampaignTurn();
                    }
                } else {
                    // No skill capture, just advance
                    self.advanceCampaignTurn();
                }
            },
            .campaign_first_reward => {
                // Update first reward UI animation
                if (self.first_reward_ui_state) |*ui_state| {
                    ui_state.update(rl.getFrameTime());

                    // Handle input
                    if (skill_capture.handleFirstRewardInput(ui_state)) {
                        // Choice confirmed - apply it
                        if (self.campaign_state) |cs| {
                            skill_capture.applyFirstRewardChoice(cs, ui_state);
                        }
                        self.first_reward_ui_state = null;
                        self.advanceCampaignTurn();
                    }
                } else {
                    // No first reward UI, just advance
                    self.advanceCampaignTurn();
                }
            },
            .campaign_victory, .run_complete => {
                if (rl.isKeyPressed(.enter) or rl.isKeyPressed(.space)) {
                    self.cleanupCampaign();
                    self.result = .{ .transition = .{ .target_mode = .main_menu } };
                }
            },
            .campaign_defeat, .run_failed => {
                if (rl.isKeyPressed(.enter) or rl.isKeyPressed(.space)) {
                    // Restart campaign
                    self.cleanupCampaign();
                    self.phase = .initializing;
                }
                if (rl.isKeyPressed(.escape)) {
                    self.cleanupCampaign();
                    self.result = .{ .transition = .{ .target_mode = .main_menu } };
                }
            },
            else => {},
        }
    }

    /// Initialize a new campaign
    fn initCampaign(self: *Self) !void {
        // Clean up any existing campaign
        self.cleanupCampaign();

        // Create campaign state
        const cs_ptr = try self.allocator.create(CampaignState);
        const seed = self.prng.random().int(u64);
        cs_ptr.* = try CampaignState.init(self.allocator, seed, .find_brother);

        self.campaign_state = cs_ptr;
        self.campaign_ui_state.reset();
    }

    /// Clean up campaign state
    fn cleanupCampaign(self: *Self) void {
        self.cleanupMatch();
        if (self.campaign_state) |cs| {
            cs.deinit();
            self.allocator.destroy(cs);
            self.campaign_state = null;
        }
        self.campaign_ui_state.reset();
        self.skill_capture_ui_state = null;
        self.first_reward_ui_state = null;
        self.current_encounter_node = null;
    }

    /// Start a campaign encounter from a node
    /// Uses EncounterBuilder to spawn enemies with proper AI states
    fn startCampaignEncounter(self: *Self, node: EncounterNode) void {
        self.cleanupMatch();

        const cs = self.campaign_state orelse {
            std.log.err("No campaign state for encounter", .{});
            return;
        };

        const gs_ptr = self.allocator.create(GameState) catch {
            std.log.err("Failed to allocate GameState for encounter", .{});
            return;
        };

        // Build combined character and AI state arrays
        var id_gen = entity.EntityIdGenerator{};
        var all_chars: [MAX_COMBAT_CHARS]Character = undefined;
        var all_ai_states: [MAX_COMBAT_CHARS]AIState = undefined;
        var char_count: usize = 0;

        // Create party characters (blue team) with their skill bars
        const party_chars = cs.party.createCombatCharacters(
            &cs.skill_pool,
            .blue,
            &id_gen,
        );

        for (party_chars) |char| {
            if (char_count >= MAX_COMBAT_CHARS) break;
            all_chars[char_count] = char;
            // Party members get basic AI states (player-controlled or ally AI)
            all_ai_states[char_count] = AIState.init(char.player_position);
            char_count += 1;
        }

        const party_size = char_count;

        // Generate encounter from node and use EncounterBuilder
        var rng = self.prng.random();
        var runtime_enc = generateEncounterFromNode(node, party_size, rng);
        const enc_def = runtime_enc.getEncounter();

        var enc_builder = factory.EncounterBuilder.init(
            self.allocator,
            &rng,
            &id_gen,
            enc_def,
        );
        _ = enc_builder.withEnemyTeam(.red);
        _ = enc_builder.withDifficulty(1.0 + (@as(f32, @floatFromInt(node.challenge_rating)) * 0.1));

        // Build enemies using EncounterBuilder
        const enc_result = enc_builder.build() catch {
            std.log.err("Failed to build encounter enemies", .{});
            self.allocator.destroy(gs_ptr);
            return;
        };
        defer self.allocator.free(enc_result.enemies);
        defer self.allocator.free(enc_result.ai_states);

        // Track boss index if present
        var boss_idx: ?usize = null;
        if (enc_result.boss_index >= 0) {
            boss_idx = party_size + @as(usize, @intCast(enc_result.boss_index));
        }

        // Copy enemies and AI states to our arrays
        for (enc_result.enemies, 0..) |enemy, i| {
            if (char_count >= MAX_COMBAT_CHARS) break;
            all_chars[char_count] = enemy;
            all_ai_states[char_count] = enc_result.ai_states[i];
            char_count += 1;
        }

        // Build game state with our characters and AI states
        var builder = game_state.GameStateBuilder.init(self.allocator);
        _ = builder.withRendering(true);
        _ = builder.withPlayerControl(true);
        _ = builder.withCharacters(all_chars[0..char_count]);
        _ = builder.withAIStates(all_ai_states[0..char_count]);

        gs_ptr.* = builder.build() catch {
            std.log.err("Failed to build GameState for encounter", .{});
            self.allocator.destroy(gs_ptr);
            return;
        };

        self.game_state = gs_ptr;
        self.current_runtime_encounter = runtime_enc;
        self.boss_entity_index = boss_idx;

        // Initialize hazard zones from encounter definition
        self.initializeHazardZones(enc_def);

        // Initialize affix processor from generated affixes
        self.initializeAffixProcessor(&runtime_enc);

        self.phase = .campaign_encounter;
    }

    /// Initialize hazard zones from an encounter definition
    fn initializeHazardZones(self: *Self, enc_def: *const Encounter) void {
        self.active_hazard_zones = [_]?HazardZoneState{null} ** MAX_HAZARD_ZONES;
        self.active_hazard_count = 0;

        // Add hazard zones from encounter definition
        for (enc_def.hazard_zones) |*hazard| {
            if (self.active_hazard_count >= MAX_HAZARD_ZONES) break;
            self.active_hazard_zones[self.active_hazard_count] = HazardZoneState.init(hazard);
            self.active_hazard_count += 1;
        }
    }

    /// Initialize affix processor from RuntimeEncounter's generated affixes
    fn initializeAffixProcessor(self: *Self, runtime_enc: *RuntimeEncounter) void {
        const affixes = runtime_enc.getAffixes();
        if (affixes.len > 0) {
            const seed = self.prng.random().int(u64);
            self.affix_processor = AffixProcessor.init(affixes, seed);

            // Log active affixes for debugging
            std.log.info("Encounter affixes active:", .{});
            for (affixes) |affix| {
                std.log.info("  - {s} (intensity: {d:.1})", .{ @tagName(affix.affix), affix.intensity });
            }
        } else {
            self.affix_processor = null;
        }
    }

    /// Add a hazard zone during combat (e.g., from boss phase transition)
    fn addHazardZone(self: *Self, hazard: *const HazardZone) void {
        if (self.active_hazard_count >= MAX_HAZARD_ZONES) {
            std.log.warn("Cannot add hazard zone: max zones reached", .{});
            return;
        }
        self.active_hazard_zones[self.active_hazard_count] = HazardZoneState.init(hazard);
        self.active_hazard_count += 1;
    }

    /// Process all active hazard zones for the current tick
    fn processHazardZones(self: *Self, gs: *GameState, delta_time_ms: u32) void {
        // Build array of active hazard states for processing
        var active_states: [MAX_HAZARD_ZONES]HazardZoneState = undefined;
        var active_count: usize = 0;

        // Collect active (non-null) hazard states
        for (&self.active_hazard_zones) |*maybe_state| {
            if (maybe_state.*) |state| {
                active_states[active_count] = state;
                active_count += 1;
            }
        }

        if (active_count == 0) return;

        // Process hazards against all entities
        ai.processHazardZones(&gs.entities, active_states[0..active_count], delta_time_ms);

        // Update hazard zone timers and remove expired ones
        for (&self.active_hazard_zones) |*maybe_state| {
            if (maybe_state.*) |*state| {
                const expired = state.update(delta_time_ms);
                if (expired) {
                    maybe_state.* = null;
                    self.active_hazard_count -|= 1;
                }
            }
        }
    }

    /// Process encounter affixes for the current tick
    /// Handles environmental effects (volcanic, storming, etc.) and combat modifiers
    fn processAffixes(self: *Self, gs: *GameState, delta_time_ms: u32) void {
        var processor = &(self.affix_processor orelse return);

        // Get arena bounds for spawning hazards
        const arena_center = rl.Vector3{ .x = 0, .y = 0, .z = 0 };
        const arena_radius: f32 = 600.0; // Default arena radius

        // Process tick - may spawn new hazards from environmental affixes
        const result = processor.processTick(
            &gs.entities,
            .blue, // Player team
            delta_time_ms,
            arena_center,
            arena_radius,
        );

        // If affix spawned a hazard (volcanic, storming), add it
        if (result.has_hazard) {
            self.addHazardZoneFromAffix(result.spawn_hazard);
        }
    }

    /// Add a hazard zone spawned by an affix (needs storage since HazardZoneState needs pointer)
    /// We use a static buffer since affix-spawned hazards are temporary
    var affix_hazard_storage: [4]HazardZone = undefined;
    var affix_hazard_idx: usize = 0;

    fn addHazardZoneFromAffix(self: *Self, hazard: HazardZone) void {
        if (self.active_hazard_count >= MAX_HAZARD_ZONES) {
            std.log.warn("Cannot add affix hazard: max zones reached", .{});
            return;
        }
        // Store in static buffer (wraps around)
        const storage_idx = affix_hazard_idx % affix_hazard_storage.len;
        affix_hazard_storage[storage_idx] = hazard;
        affix_hazard_idx +%= 1;

        self.active_hazard_zones[self.active_hazard_count] = HazardZoneState.init(&affix_hazard_storage[storage_idx]);
        self.active_hazard_count += 1;
    }

    /// Process enemy deaths for affix effects (bolstering, bursting, sanguine)
    /// Compares current alive state with previous state to detect deaths this frame
    fn processEnemyDeaths(self: *Self, gs: *GameState, was_alive: *const [game_state.MAX_ENTITIES]bool) void {
        var processor = &(self.affix_processor orelse return);

        // Check each entity for deaths
        for (&gs.entities, 0..) |*ent, i| {
            // Skip if wasn't alive before or is still alive
            if (!was_alive[i]) continue;
            if (ent.isAlive()) continue;

            // This entity died this frame - process affix effects
            const maybe_hazard = processor.processEnemyDeath(
                ent,
                &gs.entities,
                .blue, // Player team
            );

            // If affix created a hazard (sanguine pool), add it
            if (maybe_hazard) |hazard| {
                self.addHazardZoneFromAffix(hazard);
            }
        }
    }

    /// Load default skills for enemy characters (kept for backwards compatibility)
    fn loadEnemySkills(char: *Character) void {
        const position_skills = char.player_position.getSkills();
        const school_skills = char.school.getSkills();

        // Load position skills in slots 0-3
        for (position_skills, 0..) |*skill, i| {
            if (i >= 4) break;
            char.casting.skills[i] = skill;
        }

        // Load school skills in slots 4-7
        for (school_skills, 0..) |*skill, i| {
            if (i >= 4) break;
            char.casting.skills[4 + i] = skill;
        }
    }

    /// Check and apply boss phase transitions during combat
    /// Called every frame during campaign encounters
    fn checkBossPhaseTransitions(self: *Self, gs: *GameState) void {
        // Skip if no boss in this encounter
        const boss_idx = self.boss_entity_index orelse return;

        // Get boss and AI state
        if (boss_idx >= gs.entities.len) return;
        const boss = &gs.entities[boss_idx];
        const boss_ai = &gs.ai_states[boss_idx];

        // Only check phases if boss is engaged and alive
        if (boss_ai.engagement != .engaged or boss.is_dead) return;

        // For now, we create a simple boss config from the encounter node
        // In a full implementation, the RuntimeEncounter would store the BossConfig
        const node = self.current_encounter_node orelse return;
        if (node.encounter_type != .boss_capture) return;

        // Create a minimal boss config for phase checking
        // This is a simplified version - full implementation would store phases in RuntimeEncounter
        const boss_phases = [_]encounter.BossPhase{
            .{
                .trigger = .combat_start,
                .phase_name = "Engage!",
            },
            .{
                .trigger = .{ .warmth_percent = 0.5 },
                .phase_name = "Phase 2",
                .damage_multiplier = 1.3,
            },
            .{
                .trigger = .{ .warmth_percent = 0.2 },
                .phase_name = "Final Stand",
                .damage_multiplier = 1.5,
            },
        };

        const boss_config = encounter.BossConfig{
            .base = .{
                .name = "Boss",
                .school = boss.school,
                .position = boss.player_position,
                .warmth_multiplier = 2.0,
                .difficulty_rating = @intCast(node.challenge_rating),
            },
            .phases = &boss_phases,
        };

        // Check for phase transitions
        const phase_result = ai.checkBossPhases(boss, boss_ai, &boss_config);

        if (phase_result.phase_triggered) {
            if (phase_result.triggered_phase) |phase| {
                // Apply the phase transition
                ai.applyBossPhase(boss, phase);

                // Handle arena modifications from phase.arena_changes
                for (phase.arena_changes) |arena_mod| {
                    switch (arena_mod) {
                        .add_hazard => |hazard| {
                            self.addHazardZone(&hazard);
                        },
                        // TODO: Handle other arena modifications
                        .add_terrain, .clear_terrain, .shrink_bounds, .spawn_obstacle => {},
                    }
                }

                // TODO: Handle add spawning from phase.add_spawn
            }
        }
    }

    /// Sync warmth from combat characters back to party members
    fn syncWarmthToParty(self: *Self) void {
        const gs = self.game_state orelse return;
        const cs = self.campaign_state orelse return;

        // Find blue team characters and match them to party members by index
        var blue_idx: usize = 0;
        for (&gs.entities) |*combat_char| {
            if (combat_char.team != .blue) continue;

            // Match to party member by index (party members spawn in order)
            var party_idx: usize = 0;
            for (&cs.party.members) |*maybe_member| {
                if (maybe_member.*) |*member| {
                    if (!member.is_alive) continue;

                    if (party_idx == blue_idx) {
                        // Sync warmth as percentage
                        if (combat_char.is_dead or combat_char.stats.warmth <= 0) {
                            member.warmth_percent = 0;
                            member.is_alive = false;
                        } else {
                            member.warmth_percent = combat_char.stats.warmth / combat_char.stats.max_warmth;
                        }
                        break;
                    }
                    party_idx += 1;
                }
            }
            blue_idx += 1;
        }
    }

    /// Handle the result of a completed encounter
    fn handleEncounterResult(self: *Self, victory: bool) void {
        // Sync warmth from combat back to party BEFORE cleanup
        self.syncWarmthToParty();

        const node = self.current_encounter_node orelse {
            // No node context, just go back to overworld
            self.cleanupMatch();
            self.phase = .campaign_overworld;
            return;
        };

        if (self.campaign_state) |cs| {
            // Process result using polyomino block system (if we have a block_id)
            if (self.current_encounter_block_id) |block_id| {
                const status = cs.processPolyBlockResult(block_id, victory, self.prng.random()) catch cs.getStatus();

                // Check for game over from territory loss
                if (status == .victory) {
                    self.cleanupMatch();
                    self.phase = .campaign_victory;
                    return;
                } else if (status.isDefeat()) {
                    self.cleanupMatch();
                    self.phase = .campaign_defeat;
                    return;
                }
            } else {
                // Fallback to legacy system
                cs.processEncounterResult(node, victory, self.prng.random());

                // Check campaign status
                const status = cs.getStatus();
                if (status == .victory) {
                    self.cleanupMatch();
                    self.phase = .campaign_victory;
                    return;
                } else if (status.isDefeat()) {
                    self.cleanupMatch();
                    self.phase = .campaign_defeat;
                    return;
                }
            }

            if (victory) {
                // Check if this is the first victory (tutorial encounter)
                // If so, show the first reward bundle selection instead of normal skill capture
                const is_first_victory = self.matches_won == 0;

                self.matches_won += 1;

                // First victory gets the special "pick 1 of 3 bundles" reward
                if (is_first_victory) {
                    // Get player and friend info from party
                    const player = cs.party.members[0] orelse {
                        self.cleanupMatch();
                        self.advanceCampaignTurn();
                        return;
                    };
                    const friend = cs.party.members[1] orelse {
                        self.cleanupMatch();
                        self.advanceCampaignTurn();
                        return;
                    };

                    self.first_reward_ui_state = FirstRewardUIState.init(
                        player.school_type,
                        player.position_type,
                        friend.school_type,
                        friend.position_type,
                    );
                    self.cleanupMatch();
                    self.phase = .campaign_first_reward;
                    return;
                }

                // Check for skill capture reward (normal encounters)
                if (node.skill_capture_tier != .none) {
                    const choice = SkillCaptureChoice.generate(
                        node.skill_capture_tier,
                        self.prng.random(),
                        if (node.encounter_type == .boss_capture) .public_school else null,
                    );

                    if (choice.hasApOption() or choice.hasBundleOption()) {
                        self.skill_capture_ui_state = SkillCaptureUIState.init(
                            choice,
                            .public_school,
                            .fielder,
                        );
                        self.cleanupMatch();
                        self.phase = .campaign_skill_capture;
                        return;
                    }
                }

                // No skill capture, advance turn
                self.cleanupMatch();
                self.advanceCampaignTurn();
            } else {
                // Lost encounter - in campaign mode, party persists (with damage)
                // For now, check if party wiped
                if (cs.party.isWiped()) {
                    self.cleanupMatch();
                    self.phase = .campaign_defeat;
                } else {
                    self.cleanupMatch();
                    self.advanceCampaignTurn();
                }
            }
        } else {
            self.cleanupMatch();
            self.phase = .campaign_overworld;
        }

        self.matches_played += 1;
        self.current_encounter_node = null;
        self.current_encounter_block_id = null;
    }

    /// Advance the campaign by one turn and return to overworld
    fn advanceCampaignTurn(self: *Self) void {
        if (self.campaign_state) |cs| {
            cs.advanceTurn();

            // Check campaign status after turn advancement
            const status = cs.getStatus();
            if (status == .victory) {
                self.phase = .campaign_victory;
                return;
            } else if (status.isDefeat()) {
                self.phase = .campaign_defeat;
                return;
            }
        }
        self.phase = .campaign_overworld;
    }

    fn drawRoguelike(self: *Self) void {
        switch (self.phase) {
            .campaign_encounter, .encounter_active => {
                if (self.game_state) |gs| {
                    gs.draw();
                }
            },
            else => {
                // Campaign UI handles its own background
            },
        }
    }

    fn drawRoguelikeUI(self: *Self) void {
        const screen_width = rl.getScreenWidth();
        const screen_height = rl.getScreenHeight();
        const center_x = @divTrunc(screen_width, 2);
        const center_y = @divTrunc(screen_height, 2);

        switch (self.phase) {
            .initializing, .run_start => {
                rl.clearBackground(rl.Color.init(25, 30, 40, 255));
                const title = "SNOWBALL CAMPAIGN";
                const title_width = rl.measureText(title, 50);
                rl.drawText(title, center_x - @divTrunc(title_width, 2), 100, 50, rl.Color.white);

                const subtitle = "\"Saving Private Ryan\" in a snowball war";
                const subtitle_width = rl.measureText(subtitle, 20);
                rl.drawText(subtitle, center_x - @divTrunc(subtitle_width, 2), 160, 20, rl.Color.gray);

                const desc = "Find your brother in an endless suburban warzone";
                const desc_width = rl.measureText(desc, 16);
                rl.drawText(desc, center_x - @divTrunc(desc_width, 2), 200, 16, rl.Color.init(180, 180, 180, 255));

                rl.drawText("Loading...", center_x - 40, 300, 20, rl.Color.white);
            },
            .campaign_setup => {
                // Character creation UI
                campaign_ui.drawCharacterCreation(&self.campaign_ui_state);
            },
            .campaign_overworld, .encounter_select => {
                // Use campaign UI system
                if (self.campaign_state) |cs| {
                    campaign_ui.drawCampaignUI(cs, &self.campaign_ui_state);
                } else {
                    rl.clearBackground(rl.Color.init(25, 30, 40, 255));
                    rl.drawText("Campaign not initialized", center_x - 100, center_y, 20, rl.Color.red);
                }
            },
            .campaign_encounter, .encounter_active => {
                if (self.game_state) |gs| {
                    gs.drawUI();
                }
                // Overlay encounter info
                if (self.current_encounter_node) |node| {
                    var buf: [128:0]u8 = undefined;
                    const text = std.fmt.bufPrintZ(&buf, "{s} - Difficulty {d}", .{
                        node.name,
                        node.challenge_rating,
                    }) catch "Encounter";
                    rl.drawText(text, 20, 20, 20, rl.Color.yellow);
                }
            },
            .campaign_skill_capture, .upgrade_select => {
                // Draw overworld dimmed in background
                if (self.campaign_state) |cs| {
                    campaign_ui.drawCampaignUI(cs, &self.campaign_ui_state);
                }
                // Draw skill capture overlay
                if (self.skill_capture_ui_state) |*ui_state| {
                    skill_capture.drawSkillCaptureScreen(ui_state);
                } else {
                    // Fallback: simple "continue" message
                    rl.drawRectangle(0, 0, screen_width, screen_height, rl.Color.init(0, 0, 0, 180));
                    const title = "VICTORY!";
                    const title_width = rl.measureText(title, 50);
                    rl.drawText(title, center_x - @divTrunc(title_width, 2), center_y - 50, 50, rl.Color.green);
                    rl.drawText("[Enter] Continue", center_x - 70, center_y + 30, 20, rl.Color.white);
                }
            },
            .campaign_first_reward => {
                // Draw overworld dimmed in background
                if (self.campaign_state) |cs| {
                    campaign_ui.drawCampaignUI(cs, &self.campaign_ui_state);
                }
                // Draw first reward selection overlay
                if (self.first_reward_ui_state) |*ui_state| {
                    skill_capture.drawFirstRewardScreen(ui_state);
                } else {
                    // Fallback: simple "continue" message
                    rl.drawRectangle(0, 0, screen_width, screen_height, rl.Color.init(0, 0, 0, 180));
                    const title = "FIRST VICTORY!";
                    const title_width = rl.measureText(title, 50);
                    rl.drawText(title, center_x - @divTrunc(title_width, 2), center_y - 50, 50, rl.Color.gold);
                    rl.drawText("[Enter] Continue", center_x - 70, center_y + 30, 20, rl.Color.white);
                }
            },
            .campaign_victory, .run_complete => {
                rl.clearBackground(rl.Color.init(25, 30, 40, 255));
                const title = "CAMPAIGN COMPLETE!";
                const title_width = rl.measureText(title, 50);
                rl.drawText(title, center_x - @divTrunc(title_width, 2), center_y - 80, 50, rl.Color.gold);

                if (self.campaign_state) |cs| {
                    const goal_name = cs.goal_type.getName();
                    var goal_buf: [128:0]u8 = undefined;
                    const goal_text = std.fmt.bufPrintZ(&goal_buf, "Goal: {s} - ACHIEVED!", .{goal_name}) catch "Goal Achieved!";
                    const goal_width = rl.measureText(goal_text, 20);
                    rl.drawText(goal_text, center_x - @divTrunc(goal_width, 2), center_y - 20, 20, rl.Color.green);

                    var stats_buf: [128:0]u8 = undefined;
                    const stats_text = std.fmt.bufPrintZ(&stats_buf, "Turns: {d}  Encounters Won: {d}  Skills Captured: {d}", .{
                        cs.turn,
                        cs.encounters_won,
                        cs.skills_captured,
                    }) catch "Stats unavailable";
                    const stats_width = rl.measureText(stats_text, 16);
                    rl.drawText(stats_text, center_x - @divTrunc(stats_width, 2), center_y + 20, 16, rl.Color.white);
                }

                rl.drawText("[Enter] Main Menu", center_x - 80, screen_height - 100, 20, rl.Color.gray);
            },
            .campaign_defeat, .run_failed => {
                rl.clearBackground(rl.Color.init(25, 30, 40, 255));
                const title = "CAMPAIGN OVER";
                const title_width = rl.measureText(title, 50);
                rl.drawText(title, center_x - @divTrunc(title_width, 2), center_y - 80, 50, rl.Color.red);

                if (self.campaign_state) |cs| {
                    const status = cs.getStatus();
                    const reason = switch (status) {
                        .defeat_party_wiped => "Your party was wiped out.",
                        .defeat_faction_lost => "Your faction was eliminated from the war.",
                        else => "The campaign has ended.",
                    };
                    const reason_width = rl.measureText(reason, 20);
                    rl.drawText(reason, center_x - @divTrunc(reason_width, 2), center_y - 20, 20, rl.Color.init(200, 100, 100, 255));

                    var stats_buf: [128:0]u8 = undefined;
                    const stats_text = std.fmt.bufPrintZ(&stats_buf, "Turns Survived: {d}  Encounters: {d}W / {d}L", .{
                        cs.turn,
                        cs.encounters_won,
                        cs.encounters_lost,
                    }) catch "Stats unavailable";
                    const stats_width = rl.measureText(stats_text, 16);
                    rl.drawText(stats_text, center_x - @divTrunc(stats_width, 2), center_y + 20, 16, rl.Color.white);
                }

                rl.drawText("[Enter] Try Again  [Esc] Menu", center_x - 130, screen_height - 100, 20, rl.Color.gray);
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
