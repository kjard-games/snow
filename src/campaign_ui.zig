//! Campaign UI - Overworld map display, node selection, skill bar building
//!
//! This module handles all campaign-specific UI rendering:
//! - Overworld map with encounter nodes
//! - Party status display
//! - Skill bar management interface
//! - War state / faction territory display
//! - Quest progress tracking
//!
//! Design: GW1-style overworld meets roguelike node selection
//! - Nodes appear as icons on a stylized map
//! - Click/select to see details, confirm to engage
//! - Skill bar building between encounters

const std = @import("std");
const rl = @import("raylib");
const campaign = @import("campaign.zig");
const skills = @import("skills.zig");
const school = @import("school.zig");
const skill_icons = @import("skill_icons.zig");
const palette = @import("color_palette.zig");
const position = @import("position.zig");
const polyomino_map = @import("polyomino_map.zig");
const polyomino_map_ui = @import("polyomino_map_ui.zig");

const CampaignState = campaign.CampaignState;
const EncounterNode = campaign.EncounterNode;
const EncounterType = campaign.EncounterType;
const PartyMember = campaign.PartyMember;
const PartyState = campaign.PartyState;
const SkillPool = campaign.SkillPool;
const WarState = campaign.WarState;
const QuestProgress = campaign.QuestProgress;
const Faction = campaign.Faction;
const Skill = skills.Skill;
const School = school.School;
const Position = position.Position;
const PolyominoMapUIState = polyomino_map_ui.PolyominoMapUIState;

// ============================================================================
// CONSTANTS
// ============================================================================

const SKILL_SLOT_SIZE: f32 = 48;
const SKILL_SLOT_SPACING: f32 = 4;
const NODE_ICON_SIZE: f32 = 40;
const PARTY_FRAME_WIDTH: f32 = 220;
const PARTY_FRAME_HEIGHT: f32 = 60;

// ============================================================================
// UI STATE - Tracks current UI focus and selections
// ============================================================================

/// Current UI focus mode in campaign
pub const CampaignUIMode = enum {
    overworld, // Viewing/selecting encounter nodes
    skill_bar_edit, // Editing a party member's skill bar
    skill_capture_reward, // Choosing skill capture reward
    party_inspect, // Viewing party member details
    character_creation, // Creating initial party
};

/// Campaign UI state
pub const CampaignUIState = struct {
    mode: CampaignUIMode = .overworld,

    // Overworld selection (legacy)
    selected_node_index: ?usize = null,
    hovered_node_index: ?usize = null,

    // Polyomino map UI state (new)
    poly_ui: PolyominoMapUIState = .{},

    // Skill bar editing
    editing_member_index: ?usize = null,
    editing_slot_index: ?usize = null,
    hovered_pool_skill_index: ?usize = null,

    // Skill capture choice
    capture_chose_ap: bool = false,

    // Scrolling for skill pool
    skill_pool_scroll: f32 = 0,

    // Character creation state
    creation_step: u8 = 0, // 0=player school, 1=player position, 2=friend school, 3=friend position, 4=confirm
    selected_school: School = .public_school,
    selected_position: Position = .fielder,
    friend_school: School = .waldorf,
    friend_position: Position = .thermos,

    pub fn reset(self: *CampaignUIState) void {
        self.mode = .overworld;
        self.selected_node_index = null;
        self.hovered_node_index = null;
        self.poly_ui.reset();
        self.editing_member_index = null;
        self.editing_slot_index = null;
        self.hovered_pool_skill_index = null;
        self.capture_chose_ap = false;
        self.skill_pool_scroll = 0;
        self.creation_step = 0;
        self.selected_school = .public_school;
        self.selected_position = .fielder;
        self.friend_school = .waldorf;
        self.friend_position = .thermos;
    }

    pub fn startSkillBarEdit(self: *CampaignUIState, member_index: usize) void {
        self.mode = .skill_bar_edit;
        self.editing_member_index = member_index;
        self.editing_slot_index = null;
    }

    pub fn exitSkillBarEdit(self: *CampaignUIState) void {
        self.mode = .overworld;
        self.editing_member_index = null;
        self.editing_slot_index = null;
    }

    pub fn startCharacterCreation(self: *CampaignUIState) void {
        self.mode = .character_creation;
        self.creation_step = 0;
    }
};

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

inline fn toI32(val: f32) i32 {
    return @intFromFloat(val);
}

fn drawHealthBar(current: f32, max: f32, x: f32, y: f32, width: f32, height: f32) void {
    const xi = toI32(x);
    const yi = toI32(y);
    const widthi = toI32(width);
    const heighti = toI32(height);

    // Background
    rl.drawRectangle(xi, yi, widthi, heighti, palette.UI.EMPTY_BAR_BG);

    // Fill
    const fill_percent = current / max;
    const fill_width = (width - 2) * fill_percent;
    rl.drawRectangle(xi + 1, yi + 1, toI32(fill_width), heighti - 2, palette.UI.HEALTH_BAR);

    // Border
    rl.drawRectangleLines(xi, yi, widthi, heighti, palette.UI.BORDER);
}

fn drawProgressBar(progress: u8, x: f32, y: f32, width: f32, height: f32, fill_color: rl.Color) void {
    const xi = toI32(x);
    const yi = toI32(y);
    const widthi = toI32(width);
    const heighti = toI32(height);

    // Background
    rl.drawRectangle(xi, yi, widthi, heighti, palette.UI.EMPTY_BAR_BG);

    // Fill
    const fill_width = (width - 2) * (@as(f32, @floatFromInt(progress)) / 100.0);
    rl.drawRectangle(xi + 1, yi + 1, toI32(fill_width), heighti - 2, fill_color);

    // Border
    rl.drawRectangleLines(xi, yi, widthi, heighti, palette.UI.BORDER);
}

/// Get color for encounter type icon
fn getEncounterTypeColor(encounter_type: EncounterType) rl.Color {
    return switch (encounter_type) {
        .skirmish => rl.Color.init(100, 180, 100, 255), // Green - easy
        .boss_capture => rl.Color.init(255, 180, 50, 255), // Gold - boss
        .intel => rl.Color.init(100, 150, 255, 255), // Blue - info
        .strategic => rl.Color.init(255, 100, 100, 255), // Red - important
        .recruitment => rl.Color.init(200, 100, 255, 255), // Purple - special
    };
}

/// Get icon character for encounter type
fn getEncounterTypeIcon(encounter_type: EncounterType) [:0]const u8 {
    return switch (encounter_type) {
        .skirmish => "S",
        .boss_capture => "B",
        .intel => "?",
        .strategic => "!",
        .recruitment => "+",
    };
}

// ============================================================================
// OVERWORLD MAP RENDERING
// ============================================================================

/// Draw the overworld map with encounter nodes
pub fn drawOverworldMap(state: *const CampaignState, ui_state: *CampaignUIState) void {
    const screen_width = rl.getScreenWidth();
    const screen_height = rl.getScreenHeight();

    // Map area (central portion of screen)
    const map_x: f32 = 250;
    const map_y: f32 = 80;
    const map_width = @as(f32, @floatFromInt(screen_width)) - 500;
    const map_height = @as(f32, @floatFromInt(screen_height)) - 200;

    // Draw map background
    rl.drawRectangle(toI32(map_x), toI32(map_y), toI32(map_width), toI32(map_height), rl.Color.init(30, 35, 45, 255));
    rl.drawRectangleLines(toI32(map_x), toI32(map_y), toI32(map_width), toI32(map_height), palette.UI.BORDER);

    // Map title
    const title = "NEIGHBORHOOD MAP";
    const title_width = rl.measureText(title, 20);
    rl.drawText(title, toI32(map_x + map_width / 2) - @divTrunc(title_width, 2), toI32(map_y + 10), 20, rl.Color.white);

    // Get mouse position for hover detection
    const mouse_pos = rl.getMousePosition();
    ui_state.hovered_node_index = null;

    // Draw encounter nodes
    // Use a non-const copy of the overworld to access nodes
    const nodes = @constCast(&state.overworld).getNodes();
    for (nodes, 0..) |node, i| {
        // Convert node position to screen position
        // Node positions are -100 to 100, map to map area
        const node_x = map_x + map_width / 2 + (@as(f32, @floatFromInt(node.x)) / 100.0) * (map_width / 2 - NODE_ICON_SIZE);
        const node_y = map_y + map_height / 2 + (@as(f32, @floatFromInt(node.y)) / 100.0) * (map_height / 2 - NODE_ICON_SIZE);

        // Check hover
        const is_hovered = mouse_pos.x >= node_x and mouse_pos.x <= node_x + NODE_ICON_SIZE and
            mouse_pos.y >= node_y and mouse_pos.y <= node_y + NODE_ICON_SIZE;
        if (is_hovered) {
            ui_state.hovered_node_index = i;
        }

        const is_selected = if (ui_state.selected_node_index) |sel| sel == i else false;

        // Draw node
        drawEncounterNode(node, node_x, node_y, is_hovered, is_selected);
    }

    // Draw selected node details (right side panel)
    if (ui_state.selected_node_index) |sel_idx| {
        if (sel_idx < nodes.len) {
            drawNodeDetails(nodes[sel_idx], @as(f32, @floatFromInt(screen_width)) - 240, map_y);
        }
    } else if (ui_state.hovered_node_index) |hover_idx| {
        if (hover_idx < nodes.len) {
            drawNodeDetails(nodes[hover_idx], @as(f32, @floatFromInt(screen_width)) - 240, map_y);
        }
    }
}

/// Draw a single encounter node on the map
fn drawEncounterNode(node: EncounterNode, x: f32, y: f32, is_hovered: bool, is_selected: bool) void {
    const xi = toI32(x);
    const yi = toI32(y);
    const sizei = toI32(NODE_ICON_SIZE);

    // Background color based on controlling faction
    const faction_color = rl.Color.init(
        @truncate((node.controlling_faction.getColor() >> 16) & 0xFF),
        @truncate((node.controlling_faction.getColor() >> 8) & 0xFF),
        @truncate(node.controlling_faction.getColor() & 0xFF),
        80,
    );
    rl.drawRectangle(xi, yi, sizei, sizei, faction_color);

    // Icon background (encounter type color)
    const type_color = getEncounterTypeColor(node.encounter_type);
    rl.drawRectangle(xi + 4, yi + 4, sizei - 8, sizei - 8, type_color);

    // Icon letter
    const icon = getEncounterTypeIcon(node.encounter_type);
    const icon_width = rl.measureText(icon, 20);
    rl.drawText(icon, xi + @divTrunc(sizei, 2) - @divTrunc(icon_width, 2), yi + 10, 20, rl.Color.white);

    // Challenge rating indicator (small dots)
    const dot_y = yi + sizei - 8;
    var dot_x = xi + 4;
    const dots_to_draw = @min(node.challenge_rating, 5);
    for (0..dots_to_draw) |_| {
        rl.drawCircle(dot_x + 2, dot_y, 2, rl.Color.white);
        dot_x += 6;
    }

    // Expiration indicator (if timed)
    if (node.expires_in_turns) |turns| {
        var buf: [8]u8 = undefined;
        const text = std.fmt.bufPrintZ(&buf, "{d}", .{turns}) catch "?";
        rl.drawText(text, xi + sizei - 12, yi + 2, 10, rl.Color.yellow);
    }

    // Border (highlight if hovered or selected)
    const border_color = if (is_selected)
        rl.Color.yellow
    else if (is_hovered)
        rl.Color.white
    else
        palette.UI.BORDER;
    rl.drawRectangleLines(xi, yi, sizei, sizei, border_color);

    // Selection glow
    if (is_selected) {
        rl.drawRectangleLinesEx(.{ .x = x - 2, .y = y - 2, .width = NODE_ICON_SIZE + 4, .height = NODE_ICON_SIZE + 4 }, 2, rl.Color.yellow);
    }
}

/// Draw detailed info for a selected/hovered node
fn drawNodeDetails(node: EncounterNode, x: f32, y: f32) void {
    const panel_width: f32 = 230;
    const panel_height: f32 = 280;
    const padding: f32 = 10;

    const xi = toI32(x);
    const yi = toI32(y);

    // Panel background
    rl.drawRectangle(xi, yi, toI32(panel_width), toI32(panel_height), palette.UI.BACKGROUND);
    rl.drawRectangleLines(xi, yi, toI32(panel_width), toI32(panel_height), palette.UI.BORDER);

    var current_y = y + padding;

    // Encounter name
    rl.drawText(node.name, xi + toI32(padding), toI32(current_y), 16, rl.Color.white);
    current_y += 22;

    // Encounter type description
    const type_desc = node.encounter_type.getDescription();
    // Draw wrapped (simple truncation for now)
    rl.drawText(type_desc, xi + toI32(padding), toI32(current_y), 10, palette.UI.TEXT_SECONDARY);
    current_y += 40;

    // Challenge rating
    var cr_buf: [32]u8 = undefined;
    const cr_text = std.fmt.bufPrintZ(&cr_buf, "Difficulty: {d}/10", .{node.challenge_rating}) catch "Difficulty: ?";
    rl.drawText(cr_text, xi + toI32(padding), toI32(current_y), 12, rl.Color.white);
    current_y += 18;

    // Controlling faction
    var faction_buf: [64]u8 = undefined;
    const faction_text = std.fmt.bufPrintZ(&faction_buf, "Territory: {s}", .{node.controlling_faction.getName()}) catch "Territory: ?";
    const faction_color = rl.Color.init(
        @truncate((node.controlling_faction.getColor() >> 16) & 0xFF),
        @truncate((node.controlling_faction.getColor() >> 8) & 0xFF),
        @truncate(node.controlling_faction.getColor() & 0xFF),
        255,
    );
    rl.drawText(faction_text, xi + toI32(padding), toI32(current_y), 11, faction_color);
    current_y += 20;

    // Expiration
    if (node.expires_in_turns) |turns| {
        var exp_buf: [32]u8 = undefined;
        const exp_text = std.fmt.bufPrintZ(&exp_buf, "Expires in: {d} turns", .{turns}) catch "Expires: ?";
        rl.drawText(exp_text, xi + toI32(padding), toI32(current_y), 11, rl.Color.yellow);
        current_y += 18;
    }

    current_y += 10;

    // Rewards section
    rl.drawText("Rewards:", xi + toI32(padding), toI32(current_y), 12, rl.Color.white);
    current_y += 16;

    // Skill capture tier
    if (node.skill_capture_tier != .none) {
        const tier_name = switch (node.skill_capture_tier) {
            .none => "",
            .basic => "Basic Skills",
            .advanced => "Advanced Skills",
            .elite => "ELITE SKILL!",
        };
        const tier_color = if (node.skill_capture_tier == .elite) rl.Color.gold else rl.Color.green;
        rl.drawText(tier_name, xi + toI32(padding) + 10, toI32(current_y), 10, tier_color);
        current_y += 14;
    }

    // Quest progress
    if (node.offers_quest_progress) {
        rl.drawText("Quest Progress", xi + toI32(padding) + 10, toI32(current_y), 10, rl.Color.init(100, 150, 255, 255));
        current_y += 14;
    }

    // Recruitment
    if (node.offers_recruitment) {
        rl.drawText("Potential Ally", xi + toI32(padding) + 10, toI32(current_y), 10, rl.Color.init(200, 100, 255, 255));
        current_y += 14;
    }

    // Faction influence
    if (node.faction_influence > 0) {
        var inf_buf: [32]u8 = undefined;
        const inf_text = std.fmt.bufPrintZ(&inf_buf, "+{d} Faction Influence", .{node.faction_influence}) catch "+? Influence";
        rl.drawText(inf_text, xi + toI32(padding) + 10, toI32(current_y), 10, rl.Color.init(100, 255, 100, 255));
    }

    // Action prompt at bottom
    rl.drawText("[Enter] Engage", xi + toI32(padding), yi + toI32(panel_height) - 25, 12, rl.Color.white);
}

// ============================================================================
// PARTY DISPLAY
// ============================================================================

/// Draw party frames on the left side
pub fn drawPartyPanel(state: *const CampaignState, ui_state: *CampaignUIState) void {
    const padding: f32 = 10;
    var current_y: f32 = 80;

    // Panel title
    rl.drawText("PARTY", toI32(padding), toI32(current_y - 25), 16, rl.Color.white);

    for (state.party.members, 0..) |maybe_member, i| {
        if (maybe_member) |member| {
            const is_editing = if (ui_state.editing_member_index) |idx| idx == i else false;
            drawPartyMemberFrame(member, padding, current_y, is_editing);
            current_y += PARTY_FRAME_HEIGHT + 5;
        }
    }

    // Add "Edit Skills" hint
    rl.drawText("[E] Edit Skills", toI32(padding), toI32(current_y + 10), 10, palette.UI.TEXT_SECONDARY);
}

/// Draw a single party member frame
fn drawPartyMemberFrame(member: PartyMember, x: f32, y: f32, is_editing: bool) void {
    const xi = toI32(x);
    const yi = toI32(y);
    const widthi = toI32(PARTY_FRAME_WIDTH);
    const heighti = toI32(PARTY_FRAME_HEIGHT);
    const padding: f32 = 6;

    // Background
    const bg_color = if (is_editing) rl.Color.init(50, 60, 80, 255) else palette.UI.BACKGROUND;
    rl.drawRectangle(xi, yi, widthi, heighti, bg_color);
    rl.drawRectangleLines(xi, yi, widthi, heighti, if (is_editing) rl.Color.yellow else palette.UI.BORDER);

    var text_y = y + padding;

    // Name and role
    const role_text = if (member.is_player) "(You)" else if (member.is_recruited) "(Recruited)" else "(Friend)";
    var name_buf: [64]u8 = undefined;
    const name_text = std.fmt.bufPrintZ(&name_buf, "{s} {s}", .{ member.name, role_text }) catch member.name;
    rl.drawText(name_text, xi + toI32(padding), toI32(text_y), 11, rl.Color.white);
    text_y += 14;

    // School/Position
    const school_name = @tagName(member.school_type);
    const pos_name = @tagName(member.position_type);
    var build_buf: [32]u8 = undefined;
    const build_text = std.fmt.bufPrintZ(&build_buf, "{s} / {s}", .{ school_name, pos_name }) catch "?/?";
    rl.drawText(build_text, xi + toI32(padding), toI32(text_y), 9, palette.UI.TEXT_SECONDARY);
    text_y += 12;

    // Warmth bar
    const bar_width = PARTY_FRAME_WIDTH - padding * 2;
    drawHealthBar(member.warmth_percent * 100, 100, x + padding, text_y, bar_width, 10);

    // Status indicator
    const status_color = if (member.isHealthy())
        rl.Color.green
    else if (member.isWounded())
        rl.Color.yellow
    else
        rl.Color.red;
    rl.drawCircle(xi + widthi - 12, yi + 12, 5, status_color);
}

// ============================================================================
// WAR STATE DISPLAY
// ============================================================================

/// Draw war state / faction territory panel
pub fn drawWarPanel(state: *const CampaignState) void {
    const screen_width = rl.getScreenWidth();
    const panel_x = @as(f32, @floatFromInt(screen_width)) - 240;
    const panel_y: f32 = 400;
    const panel_width: f32 = 230;
    const panel_height: f32 = 150;
    const padding: f32 = 10;

    const xi = toI32(panel_x);
    const yi = toI32(panel_y);

    // Panel background
    rl.drawRectangle(xi, yi, toI32(panel_width), toI32(panel_height), palette.UI.BACKGROUND);
    rl.drawRectangleLines(xi, yi, toI32(panel_width), toI32(panel_height), palette.UI.BORDER);

    var current_y = panel_y + padding;

    // Title
    rl.drawText("WAR STATUS", xi + toI32(padding), toI32(current_y), 14, rl.Color.white);
    current_y += 20;

    // Territory bars for each faction
    const factions = [_]Faction{ .blue, .red, .yellow, .green };
    for (factions) |faction| {
        const territory = state.war.getTerritory(faction);
        const momentum = state.war.getMomentum(faction);

        // Faction name (abbreviated)
        const faction_name = faction.getName();
        rl.drawText(faction_name, xi + toI32(padding), toI32(current_y), 9, rl.Color.init(
            @truncate((faction.getColor() >> 16) & 0xFF),
            @truncate((faction.getColor() >> 8) & 0xFF),
            @truncate(faction.getColor() & 0xFF),
            255,
        ));

        // Territory bar
        const bar_x = panel_x + 100;
        const bar_width: f32 = 80;
        const bar_height: f32 = 10;

        rl.drawRectangle(toI32(bar_x), toI32(current_y), toI32(bar_width), toI32(bar_height), palette.UI.EMPTY_BAR_BG);
        const fill_width = bar_width * (@as(f32, @floatFromInt(territory)) / 100.0);
        rl.drawRectangle(toI32(bar_x), toI32(current_y), toI32(fill_width), toI32(bar_height), rl.Color.init(
            @truncate((faction.getColor() >> 16) & 0xFF),
            @truncate((faction.getColor() >> 8) & 0xFF),
            @truncate(faction.getColor() & 0xFF),
            200,
        ));

        // Momentum indicator
        var mom_buf: [8]u8 = undefined;
        const mom_text = if (momentum >= 0)
            std.fmt.bufPrintZ(&mom_buf, "+{d}", .{momentum}) catch "?"
        else
            std.fmt.bufPrintZ(&mom_buf, "{d}", .{momentum}) catch "?";
        const mom_color = if (momentum > 0) rl.Color.green else if (momentum < 0) rl.Color.red else rl.Color.gray;
        rl.drawText(mom_text, toI32(bar_x + bar_width + 5), toI32(current_y), 9, mom_color);

        current_y += 14;
    }

    // Player faction highlight
    const player_territory = state.war.getTerritory(state.party.faction);
    var status_buf: [64]u8 = undefined;
    const status_text = std.fmt.bufPrintZ(&status_buf, "Your territory: {d}%", .{player_territory}) catch "Your territory: ?%";
    rl.drawText(status_text, xi + toI32(padding), toI32(current_y + 5), 10, rl.Color.white);
}

// ============================================================================
// QUEST PROGRESS DISPLAY
// ============================================================================

/// Draw quest progress panel
pub fn drawQuestPanel(state: *const CampaignState) void {
    const screen_height = rl.getScreenHeight();
    const panel_x: f32 = 10;
    const panel_y = @as(f32, @floatFromInt(screen_height)) - 120;
    const panel_width: f32 = 230;
    const panel_height: f32 = 110;
    const padding: f32 = 10;

    const xi = toI32(panel_x);
    const yi = toI32(panel_y);

    // Panel background
    rl.drawRectangle(xi, yi, toI32(panel_width), toI32(panel_height), palette.UI.BACKGROUND);
    rl.drawRectangleLines(xi, yi, toI32(panel_width), toI32(panel_height), palette.UI.BORDER);

    var current_y = panel_y + padding;

    // Goal name
    const goal_name = state.goal_type.getName();
    rl.drawText(goal_name, xi + toI32(padding), toI32(current_y), 14, rl.Color.gold);
    current_y += 18;

    // Goal description (truncated)
    const goal_desc = state.goal_type.getDescription();
    rl.drawText(goal_desc, xi + toI32(padding), toI32(current_y), 8, palette.UI.TEXT_SECONDARY);
    current_y += 30;

    // Progress bar
    const progress = state.quest.getProgressPercent();
    drawProgressBar(progress, panel_x + padding, current_y, panel_width - padding * 2, 14, rl.Color.gold);

    // Progress text
    var prog_buf: [32]u8 = undefined;
    const prog_text = std.fmt.bufPrintZ(&prog_buf, "{d}%", .{progress}) catch "?%";
    const text_width = rl.measureText(prog_text, 10);
    rl.drawText(prog_text, xi + toI32(panel_width / 2) - @divTrunc(text_width, 2), toI32(current_y + 2), 10, rl.Color.white);
    current_y += 20;

    // Turn counter
    var turn_buf: [32]u8 = undefined;
    const turn_text = std.fmt.bufPrintZ(&turn_buf, "Turn: {d}", .{state.turn}) catch "Turn: ?";
    rl.drawText(turn_text, xi + toI32(padding), toI32(current_y), 10, rl.Color.white);
}

// ============================================================================
// SKILL BAR EDITING UI
// ============================================================================

/// Draw skill bar editing interface
pub fn drawSkillBarEditor(state: *const CampaignState, ui_state: *CampaignUIState) void {
    const screen_width = rl.getScreenWidth();
    const screen_height = rl.getScreenHeight();
    const center_x = @as(f32, @floatFromInt(screen_width)) / 2;

    // Semi-transparent overlay
    rl.drawRectangle(0, 0, screen_width, screen_height, rl.Color.init(0, 0, 0, 180));

    // Editor panel
    const panel_width: f32 = 700;
    const panel_height: f32 = 500;
    const panel_x = center_x - panel_width / 2;
    const panel_y: f32 = 80;
    const padding: f32 = 15;

    rl.drawRectangle(toI32(panel_x), toI32(panel_y), toI32(panel_width), toI32(panel_height), palette.UI.BACKGROUND);
    rl.drawRectangleLines(toI32(panel_x), toI32(panel_y), toI32(panel_width), toI32(panel_height), palette.UI.BORDER);

    // Get editing member
    const member_idx = ui_state.editing_member_index orelse return;
    const maybe_member = state.party.members[member_idx];
    const member = maybe_member orelse return;

    var current_y = panel_y + padding;

    // Title
    var title_buf: [64]u8 = undefined;
    const title = std.fmt.bufPrintZ(&title_buf, "Edit Skill Bar - {s}", .{member.name}) catch "Edit Skill Bar";
    const title_width = rl.measureText(title, 20);
    rl.drawText(title, toI32(center_x) - @divTrunc(title_width, 2), toI32(current_y), 20, rl.Color.white);
    current_y += 35;

    // Current skill bar
    rl.drawText("Equipped Skills:", toI32(panel_x + padding), toI32(current_y), 12, rl.Color.white);
    current_y += 18;

    const bar_start_x = panel_x + padding;
    for (0..campaign.SKILL_BAR_SIZE) |i| {
        const slot_x = bar_start_x + @as(f32, @floatFromInt(i)) * (SKILL_SLOT_SIZE + SKILL_SLOT_SPACING);
        const is_selected = if (ui_state.editing_slot_index) |sel| sel == i else false;

        drawSkillSlot(member.skill_bar[i], state.skill_pool, slot_x, current_y, member.school_type, member.position_type, is_selected);

        // Slot number
        var num_buf: [4]u8 = undefined;
        const num_text = std.fmt.bufPrintZ(&num_buf, "{d}", .{i + 1}) catch "?";
        rl.drawText(num_text, toI32(slot_x + SKILL_SLOT_SIZE / 2 - 4), toI32(current_y + SKILL_SLOT_SIZE + 2), 10, palette.UI.TEXT_SECONDARY);
    }
    current_y += SKILL_SLOT_SIZE + 25;

    // Skill pool (available skills)
    rl.drawText("Available Skills:", toI32(panel_x + padding), toI32(current_y), 12, rl.Color.white);
    current_y += 18;

    // Draw skill pool in a grid
    const skills_per_row: usize = 10;
    var pool_x = panel_x + padding;
    var pool_y = current_y;

    for (0..state.skill_pool.count) |i| {
        if (state.skill_pool.pool[i]) |skill| {
            const mouse_pos = rl.getMousePosition();
            const is_hovered = mouse_pos.x >= pool_x and mouse_pos.x <= pool_x + SKILL_SLOT_SIZE and
                mouse_pos.y >= pool_y and mouse_pos.y <= pool_y + SKILL_SLOT_SIZE;

            if (is_hovered) {
                ui_state.hovered_pool_skill_index = i;
            }

            drawPoolSkill(skill, pool_x, pool_y, member.school_type, member.position_type, is_hovered);

            pool_x += SKILL_SLOT_SIZE + SKILL_SLOT_SPACING;
            if ((i + 1) % skills_per_row == 0) {
                pool_x = panel_x + padding;
                pool_y += SKILL_SLOT_SIZE + SKILL_SLOT_SPACING;
            }
        }
    }

    // Instructions
    rl.drawText("[1-8] Select Slot  [Click] Equip Skill  [Esc] Done", toI32(panel_x + padding), toI32(panel_y + panel_height - 30), 11, palette.UI.TEXT_SECONDARY);
}

/// Draw a skill bar slot (equipped skill or empty)
fn drawSkillSlot(skill_index: ?u16, pool: SkillPool, x: f32, y: f32, member_school: School, member_position: Position, is_selected: bool) void {
    const xi = toI32(x);
    const yi = toI32(y);
    const sizei = toI32(SKILL_SLOT_SIZE);

    // Background
    rl.drawRectangle(xi, yi, sizei, sizei, palette.UI.SKILL_SLOT_READY);

    // Draw skill icon if equipped
    if (skill_index) |idx| {
        if (pool.get(idx)) |skill| {
            skill_icons.drawSkillIcon(x + 4, y + 4, SKILL_SLOT_SIZE - 8, skill, member_school, member_position, true);
        }
    } else {
        // Empty slot indicator
        rl.drawText("-", xi + toI32(SKILL_SLOT_SIZE / 2) - 4, yi + toI32(SKILL_SLOT_SIZE / 2) - 8, 16, palette.UI.TEXT_SECONDARY);
    }

    // Border
    const border_color = if (is_selected) rl.Color.yellow else palette.UI.BORDER;
    rl.drawRectangleLines(xi, yi, sizei, sizei, border_color);
}

/// Draw a skill in the pool (available to equip)
fn drawPoolSkill(skill: *const Skill, x: f32, y: f32, member_school: School, member_position: Position, is_hovered: bool) void {
    const xi = toI32(x);
    const yi = toI32(y);
    const sizei = toI32(SKILL_SLOT_SIZE);

    // Background (dim if AP skill already equipped)
    rl.drawRectangle(xi, yi, sizei, sizei, palette.UI.SKILL_SLOT_READY);

    // Skill icon
    skill_icons.drawSkillIcon(x + 4, y + 4, SKILL_SLOT_SIZE - 8, skill, member_school, member_position, true);

    // AP indicator
    if (skill.is_ap) {
        rl.drawText("AP", xi + 2, yi + 2, 8, rl.Color.gold);
    }

    // Border
    const border_color = if (is_hovered) rl.Color.white else palette.UI.BORDER;
    rl.drawRectangleLines(xi, yi, sizei, sizei, border_color);
}

// ============================================================================
// CHARACTER CREATION UI
// ============================================================================

/// Draw character creation screen
pub fn drawCharacterCreation(ui_state: *CampaignUIState) void {
    const screen_width = rl.getScreenWidth();
    const screen_height = rl.getScreenHeight();
    const center_x = @as(f32, @floatFromInt(screen_width)) / 2;

    // Background
    rl.clearBackground(rl.Color.init(25, 30, 40, 255));

    // Title
    const title = "CREATE YOUR PARTY";
    const title_width = rl.measureText(title, 40);
    rl.drawText(title, toI32(center_x) - @divTrunc(title_width, 2), 40, 40, rl.Color.white);

    // Subtitle based on step
    const step_titles = [_][:0]const u8{
        "Choose Your School",
        "Choose Your Position",
        "Choose Friend's School",
        "Choose Friend's Position",
        "Confirm Your Party",
    };
    const subtitle = step_titles[@min(ui_state.creation_step, 4)];
    const subtitle_width = rl.measureText(subtitle, 24);
    rl.drawText(subtitle, toI32(center_x) - @divTrunc(subtitle_width, 2), 90, 24, rl.Color.yellow);

    // Draw step indicator
    const step_y: f32 = 130;
    for (0..5) |i| {
        const step_x = center_x - 100 + @as(f32, @floatFromInt(i)) * 50;
        const is_current = i == ui_state.creation_step;
        const is_complete = i < ui_state.creation_step;
        const color = if (is_current) rl.Color.yellow else if (is_complete) rl.Color.green else rl.Color.gray;
        rl.drawCircle(toI32(step_x), toI32(step_y), if (is_current) 12 else 8, color);
        if (i < 4) {
            rl.drawLine(toI32(step_x + 12), toI32(step_y), toI32(step_x + 38), toI32(step_y), rl.Color.gray);
        }
    }

    const content_y: f32 = 170;

    switch (ui_state.creation_step) {
        0 => drawSchoolSelection(ui_state.selected_school, center_x, content_y, true),
        1 => drawPositionSelection(ui_state.selected_position, center_x, content_y, true),
        2 => drawSchoolSelection(ui_state.friend_school, center_x, content_y, false),
        3 => drawPositionSelection(ui_state.friend_position, center_x, content_y, false),
        4 => drawPartyConfirmation(ui_state, center_x, content_y),
        else => {},
    }

    // Navigation instructions
    const nav_y = screen_height - 60;
    if (ui_state.creation_step < 4) {
        rl.drawText("[W/S or Up/Down] Select  [Enter] Confirm  [Esc] Back", toI32(center_x) - 220, nav_y, 16, palette.UI.TEXT_SECONDARY);
    } else {
        rl.drawText("[Enter] Start Campaign  [Esc] Go Back", toI32(center_x) - 150, nav_y, 16, palette.UI.TEXT_SECONDARY);
    }
}

/// Draw school selection options
fn drawSchoolSelection(current: School, center_x: f32, start_y: f32, is_player: bool) void {
    const schools = [_]School{ .public_school, .private_school, .montessori, .homeschool, .waldorf };
    const card_width: f32 = 180;
    const card_height: f32 = 200;
    const spacing: f32 = 20;
    const total_width = 5 * card_width + 4 * spacing;
    var x = center_x - total_width / 2;

    for (schools) |s| {
        const is_selected = s == current;
        drawSchoolCard(s, x, start_y, card_width, card_height, is_selected);
        x += card_width + spacing;
    }

    // Description of selected school
    const desc_y = start_y + card_height + 20;
    const identity = current.getColorIdentity();
    const identity_width = rl.measureText(identity, 16);
    rl.drawText(identity, toI32(center_x) - @divTrunc(identity_width, 2), toI32(desc_y), 16, rl.Color.white);

    // Resource info
    var res_buf: [64]u8 = undefined;
    const res_text = std.fmt.bufPrintZ(&res_buf, "Resource: {s} (Max: {d}, Regen: {d:.1}/s)", .{
        current.getResourceName(),
        current.getMaxEnergy(),
        current.getEnergyRegen(),
    }) catch "Resource info";
    const res_width = rl.measureText(res_text, 14);
    rl.drawText(res_text, toI32(center_x) - @divTrunc(res_width, 2), toI32(desc_y + 25), 14, palette.UI.TEXT_SECONDARY);

    _ = is_player;
}

/// Draw a single school card
fn drawSchoolCard(s: School, x: f32, y: f32, width: f32, height: f32, is_selected: bool) void {
    const xi = toI32(x);
    const yi = toI32(y);
    const wi = toI32(width);
    const hi = toI32(height);

    // Background
    const bg_color = if (is_selected) rl.Color.init(50, 60, 80, 255) else palette.UI.BACKGROUND;
    rl.drawRectangle(xi, yi, wi, hi, bg_color);

    // Border
    const border_color = if (is_selected) rl.Color.yellow else palette.UI.BORDER;
    rl.drawRectangleLines(xi, yi, wi, hi, border_color);
    if (is_selected) {
        rl.drawRectangleLinesEx(.{ .x = x - 2, .y = y - 2, .width = width + 4, .height = height + 4 }, 2, rl.Color.yellow);
    }

    // School name
    const name = @tagName(s);
    const name_width = rl.measureText(name, 14);
    rl.drawText(name, xi + @divTrunc(wi, 2) - @divTrunc(name_width, 2), yi + 15, 14, rl.Color.white);

    // Resource name
    const resource = s.getResourceName();
    const res_width = rl.measureText(resource, 12);
    rl.drawText(resource, xi + @divTrunc(wi, 2) - @divTrunc(res_width, 2), yi + 40, 12, rl.Color.gold);

    // Stats
    var energy_buf: [32]u8 = undefined;
    const energy_text = std.fmt.bufPrintZ(&energy_buf, "Energy: {d}", .{s.getMaxEnergy()}) catch "?";
    rl.drawText(energy_text, xi + 10, yi + 70, 11, palette.UI.TEXT_SECONDARY);

    var regen_buf: [32]u8 = undefined;
    const regen_text = std.fmt.bufPrintZ(&regen_buf, "Regen: {d:.1}/s", .{s.getEnergyRegen()}) catch "?";
    rl.drawText(regen_text, xi + 10, yi + 85, 11, palette.UI.TEXT_SECONDARY);

    // Secondary mechanic
    const mechanic = s.getSecondaryMechanicName();
    rl.drawText(mechanic, xi + 10, yi + 110, 10, rl.Color.init(150, 200, 150, 255));
}

/// Draw position selection options
fn drawPositionSelection(current: Position, center_x: f32, start_y: f32, is_player: bool) void {
    const positions = [_]Position{ .pitcher, .fielder, .sledder, .shoveler, .animator, .thermos };
    const card_width: f32 = 150;
    const card_height: f32 = 180;
    const spacing: f32 = 15;
    const total_width = 6 * card_width + 5 * spacing;
    var x = center_x - total_width / 2;

    for (positions) |p| {
        const is_selected = p == current;
        drawPositionCard(p, x, start_y, card_width, card_height, is_selected);
        x += card_width + spacing;
    }

    // Description of selected position
    const desc_y = start_y + card_height + 20;
    const desc = current.getDescription();
    const desc_width = rl.measureText(desc, 14);
    rl.drawText(desc, toI32(center_x) - @divTrunc(desc_width, 2), toI32(desc_y), 14, rl.Color.white);

    _ = is_player;
}

/// Draw a single position card
fn drawPositionCard(p: Position, x: f32, y: f32, width: f32, height: f32, is_selected: bool) void {
    const xi = toI32(x);
    const yi = toI32(y);
    const wi = toI32(width);
    const hi = toI32(height);

    // Background
    const bg_color = if (is_selected) rl.Color.init(50, 60, 80, 255) else palette.UI.BACKGROUND;
    rl.drawRectangle(xi, yi, wi, hi, bg_color);

    // Border
    const border_color = if (is_selected) rl.Color.yellow else palette.UI.BORDER;
    rl.drawRectangleLines(xi, yi, wi, hi, border_color);
    if (is_selected) {
        rl.drawRectangleLinesEx(.{ .x = x - 2, .y = y - 2, .width = width + 4, .height = height + 4 }, 2, rl.Color.yellow);
    }

    // Position name
    const name = @tagName(p);
    const name_width = rl.measureText(name, 14);
    rl.drawText(name, xi + @divTrunc(wi, 2) - @divTrunc(name_width, 2), yi + 15, 14, rl.Color.white);

    // Role description (short)
    const role = switch (p) {
        .pitcher => "Damage",
        .fielder => "Balanced",
        .sledder => "Skirmisher",
        .shoveler => "Tank",
        .animator => "Summoner",
        .thermos => "Healer",
    };
    const role_width = rl.measureText(role, 12);
    rl.drawText(role, xi + @divTrunc(wi, 2) - @divTrunc(role_width, 2), yi + 40, 12, rl.Color.gold);

    // Range info
    var range_buf: [32]u8 = undefined;
    const range_text = std.fmt.bufPrintZ(&range_buf, "Range: {d:.0}-{d:.0}", .{ p.getRangeMin(), p.getRangeMax() }) catch "?";
    rl.drawText(range_text, xi + 10, yi + 70, 10, palette.UI.TEXT_SECONDARY);

    // Primary schools
    const primary = p.getPrimarySchools();
    if (primary.len > 0) {
        rl.drawText("Synergy:", xi + 10, yi + 95, 9, palette.UI.TEXT_SECONDARY);
        var school_y: i32 = yi + 108;
        for (primary) |s| {
            const school_name = @tagName(s);
            rl.drawText(school_name, xi + 15, school_y, 9, rl.Color.init(150, 200, 150, 255));
            school_y += 12;
        }
    }
}

/// Draw party confirmation screen
fn drawPartyConfirmation(ui_state: *CampaignUIState, center_x: f32, start_y: f32) void {
    // Player card
    const card_width: f32 = 300;
    const card_height: f32 = 200;
    const spacing: f32 = 50;

    const player_x = center_x - card_width - spacing / 2;
    const friend_x = center_x + spacing / 2;

    // Player
    drawConfirmationCard("YOU", ui_state.selected_school, ui_state.selected_position, player_x, start_y, card_width, card_height);

    // Friend
    drawConfirmationCard("BEST FRIEND", ui_state.friend_school, ui_state.friend_position, friend_x, start_y, card_width, card_height);

    // Mission briefing
    const brief_y = start_y + card_height + 30;
    const brief = "MISSION: Find your little brother in the neighborhood snowball war";
    const brief_width = rl.measureText(brief, 16);
    rl.drawText(brief, toI32(center_x) - @divTrunc(brief_width, 2), toI32(brief_y), 16, rl.Color.gold);

    const brief2 = "Mom said to bring him home. He wandered off. Don't get grounded.";
    const brief2_width = rl.measureText(brief2, 14);
    rl.drawText(brief2, toI32(center_x) - @divTrunc(brief2_width, 2), toI32(brief_y + 25), 14, palette.UI.TEXT_SECONDARY);
}

/// Draw a confirmation card for a party member
fn drawConfirmationCard(label: [:0]const u8, s: School, p: Position, x: f32, y: f32, width: f32, height: f32) void {
    const xi = toI32(x);
    const yi = toI32(y);
    const wi = toI32(width);
    const hi = toI32(height);

    // Background
    rl.drawRectangle(xi, yi, wi, hi, palette.UI.BACKGROUND);
    rl.drawRectangleLines(xi, yi, wi, hi, palette.UI.BORDER);

    // Label
    const label_width = rl.measureText(label, 18);
    rl.drawText(label, xi + @divTrunc(wi, 2) - @divTrunc(label_width, 2), yi + 15, 18, rl.Color.white);

    // School
    const school_name = @tagName(s);
    var school_buf: [64]u8 = undefined;
    const school_text = std.fmt.bufPrintZ(&school_buf, "School: {s}", .{school_name}) catch "School: ?";
    rl.drawText(school_text, xi + 20, yi + 50, 14, rl.Color.gold);

    // Resource
    var res_buf: [64]u8 = undefined;
    const res_text = std.fmt.bufPrintZ(&res_buf, "  {s} ({d} max, {d:.1}/s regen)", .{
        s.getResourceName(),
        s.getMaxEnergy(),
        s.getEnergyRegen(),
    }) catch "?";
    rl.drawText(res_text, xi + 20, yi + 70, 11, palette.UI.TEXT_SECONDARY);

    // Position
    const pos_name = @tagName(p);
    var pos_buf: [64]u8 = undefined;
    const pos_text = std.fmt.bufPrintZ(&pos_buf, "Position: {s}", .{pos_name}) catch "Position: ?";
    rl.drawText(pos_text, xi + 20, yi + 100, 14, rl.Color.gold);

    // Description
    const desc = p.getDescription();
    rl.drawText(desc, xi + 20, yi + 120, 10, palette.UI.TEXT_SECONDARY);

    // Range
    var range_buf: [64]u8 = undefined;
    const range_text = std.fmt.bufPrintZ(&range_buf, "  Range: {d:.0} - {d:.0}", .{ p.getRangeMin(), p.getRangeMax() }) catch "?";
    rl.drawText(range_text, xi + 20, yi + 145, 11, palette.UI.TEXT_SECONDARY);
}

/// Handle input for character creation
/// Returns true if creation is complete and should start campaign
pub fn handleCharacterCreationInput(ui_state: *CampaignUIState) bool {
    switch (ui_state.creation_step) {
        0 => {
            // School selection for player
            if (rl.isKeyPressed(.up) or rl.isKeyPressed(.w)) {
                ui_state.selected_school = prevSchool(ui_state.selected_school);
            }
            if (rl.isKeyPressed(.down) or rl.isKeyPressed(.s)) {
                ui_state.selected_school = nextSchool(ui_state.selected_school);
            }
            if (rl.isKeyPressed(.left) or rl.isKeyPressed(.a)) {
                ui_state.selected_school = prevSchool(ui_state.selected_school);
            }
            if (rl.isKeyPressed(.right) or rl.isKeyPressed(.d)) {
                ui_state.selected_school = nextSchool(ui_state.selected_school);
            }
            if (rl.isKeyPressed(.enter) or rl.isKeyPressed(.space)) {
                ui_state.creation_step = 1;
            }
        },
        1 => {
            // Position selection for player
            if (rl.isKeyPressed(.up) or rl.isKeyPressed(.w) or rl.isKeyPressed(.left) or rl.isKeyPressed(.a)) {
                ui_state.selected_position = prevPosition(ui_state.selected_position);
            }
            if (rl.isKeyPressed(.down) or rl.isKeyPressed(.s) or rl.isKeyPressed(.right) or rl.isKeyPressed(.d)) {
                ui_state.selected_position = nextPosition(ui_state.selected_position);
            }
            if (rl.isKeyPressed(.enter) or rl.isKeyPressed(.space)) {
                ui_state.creation_step = 2;
            }
            if (rl.isKeyPressed(.escape)) {
                ui_state.creation_step = 0;
            }
        },
        2 => {
            // School selection for friend
            if (rl.isKeyPressed(.up) or rl.isKeyPressed(.w) or rl.isKeyPressed(.left) or rl.isKeyPressed(.a)) {
                ui_state.friend_school = prevSchool(ui_state.friend_school);
            }
            if (rl.isKeyPressed(.down) or rl.isKeyPressed(.s) or rl.isKeyPressed(.right) or rl.isKeyPressed(.d)) {
                ui_state.friend_school = nextSchool(ui_state.friend_school);
            }
            if (rl.isKeyPressed(.enter) or rl.isKeyPressed(.space)) {
                ui_state.creation_step = 3;
            }
            if (rl.isKeyPressed(.escape)) {
                ui_state.creation_step = 1;
            }
        },
        3 => {
            // Position selection for friend
            if (rl.isKeyPressed(.up) or rl.isKeyPressed(.w) or rl.isKeyPressed(.left) or rl.isKeyPressed(.a)) {
                ui_state.friend_position = prevPosition(ui_state.friend_position);
            }
            if (rl.isKeyPressed(.down) or rl.isKeyPressed(.s) or rl.isKeyPressed(.right) or rl.isKeyPressed(.d)) {
                ui_state.friend_position = nextPosition(ui_state.friend_position);
            }
            if (rl.isKeyPressed(.enter) or rl.isKeyPressed(.space)) {
                ui_state.creation_step = 4;
            }
            if (rl.isKeyPressed(.escape)) {
                ui_state.creation_step = 2;
            }
        },
        4 => {
            // Confirmation
            if (rl.isKeyPressed(.enter) or rl.isKeyPressed(.space)) {
                return true; // Start campaign
            }
            if (rl.isKeyPressed(.escape)) {
                ui_state.creation_step = 3;
            }
        },
        else => {},
    }
    return false;
}

fn nextSchool(current: School) School {
    return switch (current) {
        .public_school => .private_school,
        .private_school => .montessori,
        .montessori => .homeschool,
        .homeschool => .waldorf,
        .waldorf => .public_school,
    };
}

fn prevSchool(current: School) School {
    return switch (current) {
        .public_school => .waldorf,
        .private_school => .public_school,
        .montessori => .private_school,
        .homeschool => .montessori,
        .waldorf => .homeschool,
    };
}

fn nextPosition(current: Position) Position {
    return switch (current) {
        .pitcher => .fielder,
        .fielder => .sledder,
        .sledder => .shoveler,
        .shoveler => .animator,
        .animator => .thermos,
        .thermos => .pitcher,
    };
}

fn prevPosition(current: Position) Position {
    return switch (current) {
        .pitcher => .thermos,
        .fielder => .pitcher,
        .sledder => .fielder,
        .shoveler => .sledder,
        .animator => .shoveler,
        .thermos => .animator,
    };
}

// ============================================================================
// TOP BAR / HUD
// ============================================================================

/// Draw the top bar with campaign stats
pub fn drawTopBar(state: *const CampaignState) void {
    const screen_width = rl.getScreenWidth();
    const bar_height: f32 = 50;

    // Background
    rl.drawRectangle(0, 0, screen_width, toI32(bar_height), palette.UI.BACKGROUND);
    rl.drawLine(0, toI32(bar_height), screen_width, toI32(bar_height), palette.UI.BORDER);

    // Campaign title
    rl.drawText("SNOWBALL CAMPAIGN", 15, 15, 20, rl.Color.white);

    // Stats
    var stats_buf: [128]u8 = undefined;
    const stats_text = std.fmt.bufPrintZ(&stats_buf, "Won: {d}  Lost: {d}  Skills: {d}  Turn: {d}", .{
        state.encounters_won,
        state.encounters_lost,
        state.skills_captured,
        state.turn,
    }) catch "Stats unavailable";
    const stats_width = rl.measureText(stats_text, 14);
    rl.drawText(stats_text, screen_width - stats_width - 15, 18, 14, palette.UI.TEXT_SECONDARY);
}

// ============================================================================
// MAIN DRAW FUNCTION
// ============================================================================

/// Main campaign UI draw function - call from game_mode
pub fn drawCampaignUI(state: *CampaignState, ui_state: *CampaignUIState) void {
    // Clear background
    rl.clearBackground(rl.Color.init(25, 30, 40, 255));

    // Always draw base UI
    drawTopBar(state);

    const screen_width = rl.getScreenWidth();
    const screen_height = rl.getScreenHeight();

    // Map area (central portion of screen)
    const map_x: f32 = 250;
    const map_y: f32 = 60;
    const map_width = @as(f32, @floatFromInt(screen_width)) - 500;
    const map_height = @as(f32, @floatFromInt(screen_height)) - 180;

    switch (ui_state.mode) {
        .overworld => {
            // Draw new polyomino map
            polyomino_map_ui.drawPolyominoMap(
                &state.poly_map,
                &ui_state.poly_ui,
                map_x,
                map_y,
                map_width,
                map_height,
            );

            // Draw block details panel on the right
            polyomino_map_ui.drawBlockDetails(
                &state.poly_map,
                &ui_state.poly_ui,
                @as(f32, @floatFromInt(screen_width)) - 240,
                map_y,
                230,
            );

            // Draw minimap in corner
            polyomino_map_ui.drawMinimap(
                &state.poly_map,
                &ui_state.poly_ui,
                @as(f32, @floatFromInt(screen_width)) - 240,
                @as(f32, @floatFromInt(screen_height)) - 180,
                120,
            );

            drawPartyPanel(state, ui_state);
            drawWarPanel(state);
            drawQuestPanel(state);
        },
        .skill_bar_edit => {
            // Draw map dimmed underneath
            polyomino_map_ui.drawPolyominoMap(
                &state.poly_map,
                &ui_state.poly_ui,
                map_x,
                map_y,
                map_width,
                map_height,
            );
            drawPartyPanel(state, ui_state);
            // Draw editor overlay
            drawSkillBarEditor(state, ui_state);
        },
        .skill_capture_reward => {
            // TODO: Draw skill capture choice UI
            polyomino_map_ui.drawPolyominoMap(
                &state.poly_map,
                &ui_state.poly_ui,
                map_x,
                map_y,
                map_width,
                map_height,
            );
        },
        .party_inspect => {
            // TODO: Draw party inspection UI
            polyomino_map_ui.drawPolyominoMap(
                &state.poly_map,
                &ui_state.poly_ui,
                map_x,
                map_y,
                map_width,
                map_height,
            );
            drawPartyPanel(state, ui_state);
        },
        .character_creation => {
            // Character creation is handled separately (before campaign state exists)
            // This case shouldn't normally be reached via drawCampaignUI
        },
    }
}

// ============================================================================
// INPUT HANDLING
// ============================================================================

/// Handle input for campaign UI
/// Returns a block ID (u32) if an encounter should be started, null otherwise
/// Note: Return type changed from ?u16 to ?u32 to accommodate polyomino block IDs
pub fn handleCampaignInput(state: *CampaignState, ui_state: *CampaignUIState) ?u32 {
    const screen_width = rl.getScreenWidth();
    const screen_height = rl.getScreenHeight();

    // Map area (central portion of screen) - must match drawCampaignUI
    const map_x: f32 = 250;
    const map_y: f32 = 60;
    const map_width = @as(f32, @floatFromInt(screen_width)) - 500;
    const map_height = @as(f32, @floatFromInt(screen_height)) - 180;

    switch (ui_state.mode) {
        .overworld => {
            // Handle polyomino map input (panning, zooming, selection)
            const engaged_block = polyomino_map_ui.handlePolyominoMapInput(
                &state.poly_map,
                &ui_state.poly_ui,
                map_x,
                map_y,
                map_width,
                map_height,
            );

            if (engaged_block) |block_id| {
                return block_id;
            }

            // Edit skills
            if (rl.isKeyPressed(.e)) {
                // Default to player (index 0)
                ui_state.startSkillBarEdit(0);
            }

            // Number keys to select party member for editing
            if (rl.isKeyPressed(.one)) ui_state.startSkillBarEdit(0);
            if (rl.isKeyPressed(.two)) ui_state.startSkillBarEdit(1);
            if (rl.isKeyPressed(.three)) ui_state.startSkillBarEdit(2);
            if (rl.isKeyPressed(.four)) ui_state.startSkillBarEdit(3);
        },
        .skill_bar_edit => {
            // Exit editing
            if (rl.isKeyPressed(.escape)) {
                ui_state.exitSkillBarEdit();
            }

            // Select slot with number keys
            if (rl.isKeyPressed(.one)) ui_state.editing_slot_index = 0;
            if (rl.isKeyPressed(.two)) ui_state.editing_slot_index = 1;
            if (rl.isKeyPressed(.three)) ui_state.editing_slot_index = 2;
            if (rl.isKeyPressed(.four)) ui_state.editing_slot_index = 3;
            if (rl.isKeyPressed(.five)) ui_state.editing_slot_index = 4;
            if (rl.isKeyPressed(.six)) ui_state.editing_slot_index = 5;
            if (rl.isKeyPressed(.seven)) ui_state.editing_slot_index = 6;
            if (rl.isKeyPressed(.eight)) ui_state.editing_slot_index = 7;

            // Click to equip skill from pool
            if (rl.isMouseButtonPressed(.left)) {
                if (ui_state.hovered_pool_skill_index) |pool_idx| {
                    if (ui_state.editing_slot_index) |slot_idx| {
                        if (ui_state.editing_member_index) |member_idx| {
                            // Equip skill
                            if (state.party.members[member_idx]) |*member| {
                                member.skill_bar[slot_idx] = @intCast(pool_idx);
                            }
                        }
                    }
                }
            }
        },
        .skill_capture_reward => {
            // TODO: Handle skill capture choice input
            if (rl.isKeyPressed(.escape)) {
                ui_state.mode = .overworld;
            }
        },
        .party_inspect => {
            if (rl.isKeyPressed(.escape)) {
                ui_state.mode = .overworld;
            }
        },
        .character_creation => {
            // Character creation input is handled by handleCharacterCreationInput
            // This case shouldn't normally be reached via handleCampaignInput
        },
    }

    return null;
}
