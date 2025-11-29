//! Skill Capture - Post-boss reward screen (Signet of Capture equivalent)
//!
//! After defeating a boss, the player is presented with a choice:
//! - Option A: One powerful AP (elite) skill (if elite tier)
//! - Option B: A bundle of 2-3 regular skills
//!
//! This creates meaningful decisions - do you take the single powerful skill
//! or diversify with multiple options?
//!
//! Design Philosophy (from GW1):
//! - Elite skills are build-defining - you can only have ONE equipped
//! - Regular skills provide utility and combo potential
//! - The choice should feel impactful and permanent for this run

const std = @import("std");
const rl = @import("raylib");
const campaign = @import("campaign.zig");
const skills = @import("skills.zig");
const skill_icons = @import("skill_icons.zig");
const palette = @import("color_palette.zig");
const school = @import("school.zig");
const position = @import("position.zig");

const SkillCaptureChoice = campaign.SkillCaptureChoice;
const SkillCaptureTier = campaign.SkillCaptureTier;
const CampaignState = campaign.CampaignState;
const Skill = skills.Skill;
const School = school.School;
const Position = position.Position;

// ============================================================================
// CONSTANTS
// ============================================================================

const CARD_WIDTH: f32 = 280;
const CARD_HEIGHT: f32 = 380;
const CARD_SPACING: f32 = 40;
const SKILL_ICON_SIZE: f32 = 64;

// ============================================================================
// SKILL CAPTURE UI STATE
// ============================================================================

pub const SkillCaptureUIState = struct {
    /// The choice being presented
    choice: SkillCaptureChoice,

    /// Which option is currently hovered (0 = AP, 1 = bundle)
    hovered_option: ?u8 = null,

    /// Which option is selected (confirmed)
    selected_option: ?u8 = null,

    /// Animation timer for entrance
    animation_timer: f32 = 0,

    /// Has the player confirmed their choice?
    confirmed: bool = false,

    /// School of the defeated boss (for theming)
    boss_school: School = .public_school,

    /// Position for icon rendering context
    player_position: Position = .fielder,

    pub fn init(choice: SkillCaptureChoice, boss_school: School, player_position: Position) SkillCaptureUIState {
        return .{
            .choice = choice,
            .boss_school = boss_school,
            .player_position = player_position,
        };
    }

    pub fn reset(self: *SkillCaptureUIState) void {
        self.hovered_option = null;
        self.selected_option = null;
        self.animation_timer = 0;
        self.confirmed = false;
    }

    pub fn update(self: *SkillCaptureUIState, delta_time: f32) void {
        self.animation_timer += delta_time;
    }

    pub fn hasChoice(self: SkillCaptureUIState) bool {
        return self.choice.hasApOption() or self.choice.hasBundleOption();
    }
};

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

inline fn toI32(val: f32) i32 {
    return @intFromFloat(val);
}

fn easeOutBack(t: f32) f32 {
    const c1: f32 = 1.70158;
    const c3: f32 = c1 + 1;
    return 1 + c3 * std.math.pow(f32, t - 1, 3) + c1 * std.math.pow(f32, t - 1, 2);
}

// ============================================================================
// MAIN DRAW FUNCTION
// ============================================================================

/// Draw the skill capture reward screen
pub fn drawSkillCaptureScreen(ui_state: *SkillCaptureUIState) void {
    const screen_width = rl.getScreenWidth();
    const screen_height = rl.getScreenHeight();
    const center_x = @as(f32, @floatFromInt(screen_width)) / 2;
    const center_y = @as(f32, @floatFromInt(screen_height)) / 2;

    // Full screen overlay
    rl.drawRectangle(0, 0, screen_width, screen_height, rl.Color.init(0, 0, 0, 220));

    // Entrance animation
    const anim_progress = @min(1.0, ui_state.animation_timer / 0.5);
    const scale = easeOutBack(anim_progress);

    // Title
    const title = "SKILL CAPTURE";
    const title_size: i32 = 40;
    const title_width = rl.measureText(title, title_size);
    const title_y = center_y - 250 * scale;
    rl.drawText(title, toI32(center_x) - @divTrunc(title_width, 2), toI32(title_y), title_size, rl.Color.gold);

    // Subtitle based on tier
    const subtitle = switch (ui_state.choice.tier) {
        .none => "No skills available",
        .basic => "Choose your reward",
        .advanced => "Choose your reward",
        .elite => "ELITE SKILL AVAILABLE!",
    };
    const subtitle_color = if (ui_state.choice.tier == .elite) rl.Color.gold else rl.Color.white;
    const subtitle_width = rl.measureText(subtitle, 20);
    rl.drawText(subtitle, toI32(center_x) - @divTrunc(subtitle_width, 2), toI32(title_y + 50), 20, subtitle_color);

    // Calculate card positions
    const has_ap = ui_state.choice.hasApOption();
    const has_bundle = ui_state.choice.hasBundleOption();
    const num_cards: f32 = if (has_ap and has_bundle) 2 else 1;
    const total_width = num_cards * CARD_WIDTH + (num_cards - 1) * CARD_SPACING;
    var card_x = center_x - total_width / 2;
    const card_y = center_y - CARD_HEIGHT / 2 + 30;

    // Get mouse position for hover
    const mouse_pos = rl.getMousePosition();
    ui_state.hovered_option = null;

    // Draw AP skill card (Option A)
    if (has_ap) {
        const is_hovered = mouse_pos.x >= card_x and mouse_pos.x <= card_x + CARD_WIDTH and
            mouse_pos.y >= card_y and mouse_pos.y <= card_y + CARD_HEIGHT;
        if (is_hovered) {
            ui_state.hovered_option = 0;
        }
        const is_selected = if (ui_state.selected_option) |sel| sel == 0 else false;

        drawApSkillCard(ui_state.choice.ap_skill, card_x, card_y, scale, is_hovered, is_selected, ui_state.boss_school, ui_state.player_position);
        card_x += CARD_WIDTH + CARD_SPACING;
    }

    // Draw bundle card (Option B)
    if (has_bundle) {
        const is_hovered = mouse_pos.x >= card_x and mouse_pos.x <= card_x + CARD_WIDTH and
            mouse_pos.y >= card_y and mouse_pos.y <= card_y + CARD_HEIGHT;
        if (is_hovered) {
            ui_state.hovered_option = 1;
        }
        const is_selected = if (ui_state.selected_option) |sel| sel == 1 else false;

        drawBundleCard(ui_state.choice.skill_bundle, ui_state.choice.bundle_size, card_x, card_y, scale, is_hovered, is_selected, ui_state.boss_school, ui_state.player_position);
    }

    // Instructions
    const instructions = if (ui_state.selected_option != null)
        "[Enter] Confirm Selection  [Esc] Cancel"
    else
        "[Click] Select Option  [1] AP Skill  [2] Bundle";
    const inst_width = rl.measureText(instructions, 16);
    rl.drawText(instructions, toI32(center_x) - @divTrunc(inst_width, 2), screen_height - 60, 16, palette.UI.TEXT_SECONDARY);

    // "OR" divider between cards
    if (has_ap and has_bundle) {
        const or_x = center_x;
        const or_y = card_y + CARD_HEIGHT / 2;
        rl.drawCircle(toI32(or_x), toI32(or_y), 25, rl.Color.init(40, 45, 55, 255));
        rl.drawCircleLines(toI32(or_x), toI32(or_y), 25, palette.UI.BORDER);
        const or_text = "OR";
        const or_width = rl.measureText(or_text, 16);
        rl.drawText(or_text, toI32(or_x) - @divTrunc(or_width, 2), toI32(or_y) - 8, 16, rl.Color.white);
    }
}

/// Draw the AP (elite) skill card
fn drawApSkillCard(maybe_skill: ?*const Skill, x: f32, y: f32, scale: f32, is_hovered: bool, is_selected: bool, boss_school: School, player_position: Position) void {
    const skill = maybe_skill orelse return;

    const scaled_height = CARD_HEIGHT * scale;
    const xi = toI32(x);
    const yi = toI32(y + (CARD_HEIGHT - scaled_height) / 2);
    const widthi = toI32(CARD_WIDTH);
    const heighti = toI32(scaled_height);

    // Card background - gold tint for elite
    const bg_color = if (is_selected)
        rl.Color.init(80, 70, 40, 255)
    else if (is_hovered)
        rl.Color.init(60, 55, 35, 255)
    else
        rl.Color.init(45, 42, 30, 255);
    rl.drawRectangle(xi, yi, widthi, heighti, bg_color);

    // Gold border for elite
    const border_color = if (is_selected) rl.Color.yellow else if (is_hovered) rl.Color.gold else rl.Color.init(180, 150, 50, 255);
    rl.drawRectangleLines(xi, yi, widthi, heighti, border_color);
    if (is_selected or is_hovered) {
        rl.drawRectangleLinesEx(.{ .x = x - 2, .y = y + (CARD_HEIGHT - scaled_height) / 2 - 2, .width = CARD_WIDTH + 4, .height = scaled_height + 4 }, 2, border_color);
    }

    const padding: f32 = 15;
    var content_y = y + (CARD_HEIGHT - scaled_height) / 2 + padding;

    // "ELITE" badge
    const elite_text = "ELITE SKILL";
    const elite_width = rl.measureText(elite_text, 14);
    rl.drawRectangle(xi + toI32(CARD_WIDTH / 2) - @divTrunc(elite_width, 2) - 10, toI32(content_y), elite_width + 20, 22, rl.Color.gold);
    rl.drawText(elite_text, xi + toI32(CARD_WIDTH / 2) - @divTrunc(elite_width, 2), toI32(content_y + 4), 14, rl.Color.init(40, 30, 10, 255));
    content_y += 35;

    // Skill icon (large, centered)
    const icon_x = x + (CARD_WIDTH - SKILL_ICON_SIZE) / 2;
    skill_icons.drawSkillIcon(icon_x, content_y, SKILL_ICON_SIZE, skill, boss_school, player_position, true);
    content_y += SKILL_ICON_SIZE + 15;

    // Skill name
    const name_width = rl.measureText(skill.name, 18);
    rl.drawText(skill.name, xi + toI32(CARD_WIDTH / 2) - @divTrunc(name_width, 2), toI32(content_y), 18, rl.Color.white);
    content_y += 25;

    // Skill type
    const type_name = @tagName(skill.skill_type);
    const type_width = rl.measureText(type_name, 12);
    rl.drawText(type_name, xi + toI32(CARD_WIDTH / 2) - @divTrunc(type_width, 2), toI32(content_y), 12, palette.UI.TEXT_SECONDARY);
    content_y += 20;

    // Stats row
    var stats_buf: [64]u8 = undefined;
    const stats_text = std.fmt.bufPrintZ(&stats_buf, "Energy: {d}  Cast: {d:.1}s  CD: {d:.1}s", .{
        skill.energy_cost,
        @as(f32, @floatFromInt(skill.activation_time_ms)) / 1000.0,
        @as(f32, @floatFromInt(skill.recharge_time_ms)) / 1000.0,
    }) catch "???";
    const stats_width = rl.measureText(stats_text, 10);
    rl.drawText(stats_text, xi + toI32(CARD_WIDTH / 2) - @divTrunc(stats_width, 2), toI32(content_y), 10, palette.UI.TEXT_SECONDARY);
    content_y += 20;

    // Description (if available)
    if (skill.description.len > 0) {
        // Simple centered description (truncated)
        rl.drawText(skill.description, xi + toI32(padding), toI32(content_y), 10, rl.Color.white);
    }

    // Selection indicator
    if (is_selected) {
        const check_text = "SELECTED";
        const check_width = rl.measureText(check_text, 16);
        rl.drawText(check_text, xi + toI32(CARD_WIDTH / 2) - @divTrunc(check_width, 2), yi + heighti - 30, 16, rl.Color.yellow);
    }
}

/// Draw the skill bundle card
fn drawBundleCard(bundle: [3]?*const Skill, bundle_size: u8, x: f32, y: f32, scale: f32, is_hovered: bool, is_selected: bool, boss_school: School, player_position: Position) void {
    const scaled_height = CARD_HEIGHT * scale;
    const xi = toI32(x);
    const yi = toI32(y + (CARD_HEIGHT - scaled_height) / 2);
    const widthi = toI32(CARD_WIDTH);
    const heighti = toI32(scaled_height);

    // Card background - blue tint for bundle
    const bg_color = if (is_selected)
        rl.Color.init(40, 50, 80, 255)
    else if (is_hovered)
        rl.Color.init(35, 45, 70, 255)
    else
        rl.Color.init(30, 38, 55, 255);
    rl.drawRectangle(xi, yi, widthi, heighti, bg_color);

    // Border
    const border_color = if (is_selected) rl.Color.yellow else if (is_hovered) rl.Color.white else palette.UI.BORDER;
    rl.drawRectangleLines(xi, yi, widthi, heighti, border_color);
    if (is_selected or is_hovered) {
        rl.drawRectangleLinesEx(.{ .x = x - 2, .y = y + (CARD_HEIGHT - scaled_height) / 2 - 2, .width = CARD_WIDTH + 4, .height = scaled_height + 4 }, 2, border_color);
    }

    const padding: f32 = 15;
    var content_y = y + (CARD_HEIGHT - scaled_height) / 2 + padding;

    // "SKILL BUNDLE" header
    var header_buf: [32]u8 = undefined;
    const header_text = std.fmt.bufPrintZ(&header_buf, "SKILL BUNDLE ({d})", .{bundle_size}) catch "SKILL BUNDLE";
    const header_width = rl.measureText(header_text, 14);
    rl.drawRectangle(xi + toI32(CARD_WIDTH / 2) - @divTrunc(header_width, 2) - 10, toI32(content_y), header_width + 20, 22, rl.Color.init(60, 100, 180, 255));
    rl.drawText(header_text, xi + toI32(CARD_WIDTH / 2) - @divTrunc(header_width, 2), toI32(content_y + 4), 14, rl.Color.white);
    content_y += 35;

    // Draw each skill in the bundle
    const small_icon_size: f32 = 48;
    const skill_row_height: f32 = 70;

    for (0..bundle_size) |i| {
        if (bundle[i]) |skill| {
            // Icon
            skill_icons.drawSkillIcon(x + padding, content_y, small_icon_size, skill, boss_school, player_position, true);

            // Name and type
            rl.drawText(skill.name, xi + toI32(padding + small_icon_size + 10), toI32(content_y + 5), 14, rl.Color.white);

            const type_name = @tagName(skill.skill_type);
            rl.drawText(type_name, xi + toI32(padding + small_icon_size + 10), toI32(content_y + 22), 10, palette.UI.TEXT_SECONDARY);

            // Brief stats
            var stats_buf: [32]u8 = undefined;
            const stats_text = std.fmt.bufPrintZ(&stats_buf, "E:{d} CD:{d:.0}s", .{
                skill.energy_cost,
                @as(f32, @floatFromInt(skill.recharge_time_ms)) / 1000.0,
            }) catch "???";
            rl.drawText(stats_text, xi + toI32(padding + small_icon_size + 10), toI32(content_y + 38), 9, palette.UI.TEXT_SECONDARY);

            content_y += skill_row_height;
        }
    }

    // Selection indicator
    if (is_selected) {
        const check_text = "SELECTED";
        const check_width = rl.measureText(check_text, 16);
        rl.drawText(check_text, xi + toI32(CARD_WIDTH / 2) - @divTrunc(check_width, 2), yi + heighti - 30, 16, rl.Color.yellow);
    }
}

// ============================================================================
// INPUT HANDLING
// ============================================================================

/// Handle input for skill capture screen
/// Returns true if a choice was confirmed
pub fn handleSkillCaptureInput(ui_state: *SkillCaptureUIState) bool {
    // Click to select
    if (rl.isMouseButtonPressed(.left)) {
        if (ui_state.hovered_option) |opt| {
            ui_state.selected_option = opt;
        }
    }

    // Number keys to select
    if (rl.isKeyPressed(.one) and ui_state.choice.hasApOption()) {
        ui_state.selected_option = 0;
    }
    if (rl.isKeyPressed(.two) and ui_state.choice.hasBundleOption()) {
        ui_state.selected_option = 1;
    }

    // Confirm selection
    if (rl.isKeyPressed(.enter) or rl.isKeyPressed(.space)) {
        if (ui_state.selected_option != null) {
            ui_state.confirmed = true;
            return true;
        }
    }

    // Cancel selection (not the screen, just deselect)
    if (rl.isKeyPressed(.escape)) {
        if (ui_state.selected_option != null) {
            ui_state.selected_option = null;
        }
    }

    return false;
}

/// Apply the confirmed choice to campaign state
pub fn applySkillCaptureChoice(campaign_state: *CampaignState, ui_state: *const SkillCaptureUIState) void {
    if (!ui_state.confirmed) return;

    const chose_ap = if (ui_state.selected_option) |sel| sel == 0 else false;
    campaign_state.applySkillCapture(ui_state.choice, chose_ap);
}

// ============================================================================
// TESTS
// ============================================================================

test "skill capture ui state" {
    var prng = std.Random.DefaultPrng.init(123);
    const rng = prng.random();

    const choice = campaign.SkillCaptureChoice.generate(.elite, rng, .public_school);
    var ui_state = SkillCaptureUIState.init(choice, .public_school, .fielder);

    try std.testing.expect(ui_state.hasChoice());
    try std.testing.expect(ui_state.selected_option == null);
    try std.testing.expect(!ui_state.confirmed);

    ui_state.selected_option = 0;
    try std.testing.expect(ui_state.selected_option == 0);
}

// ============================================================================
// FIRST REWARD UI - Post-tutorial bundle selection
// ============================================================================

const FirstRewardBundle = campaign.FirstRewardBundle;
const FirstRewardGenerator = campaign.FirstRewardGenerator;
const FIRST_BUNDLE_SIZE = campaign.FIRST_BUNDLE_SIZE;

/// Constants for first reward UI
const BUNDLE_CARD_WIDTH: f32 = 300;
const BUNDLE_CARD_HEIGHT: f32 = 450;
const BUNDLE_CARD_SPACING: f32 = 30;

/// UI state for the first reward selection screen
pub const FirstRewardUIState = struct {
    /// The 3 bundles to choose from
    bundles: [3]FirstRewardBundle,

    /// Which bundle is currently hovered (0, 1, or 2)
    hovered_bundle: ?u8 = null,

    /// Which bundle is selected
    selected_bundle: ?u8 = null,

    /// Animation timer
    animation_timer: f32 = 0,

    /// Has the player confirmed their choice?
    confirmed: bool = false,

    /// Player's school (for icon rendering)
    player_school: School = .public_school,

    /// Player's position (for icon rendering)
    player_position: Position = .fielder,

    /// Friend's school (for icon rendering - bundles include friend's skills)
    friend_school: School = .waldorf,

    /// Friend's position (for icon rendering - bundles include friend's skills)
    friend_position: Position = .thermos,

    pub fn init(
        player_school: School,
        player_position: Position,
        friend_school: School,
        friend_position: Position,
    ) FirstRewardUIState {
        return .{
            .bundles = FirstRewardGenerator.generateBundles(
                player_school,
                player_position,
                friend_school,
                friend_position,
            ),
            .player_school = player_school,
            .player_position = player_position,
            .friend_school = friend_school,
            .friend_position = friend_position,
        };
    }

    pub fn reset(self: *FirstRewardUIState) void {
        self.hovered_bundle = null;
        self.selected_bundle = null;
        self.animation_timer = 0;
        self.confirmed = false;
    }

    pub fn update(self: *FirstRewardUIState, delta_time: f32) void {
        self.animation_timer += delta_time;
    }

    pub fn getSelectedBundle(self: *const FirstRewardUIState) ?*const FirstRewardBundle {
        if (self.selected_bundle) |idx| {
            return &self.bundles[idx];
        }
        return null;
    }
};

/// Draw the first reward selection screen
pub fn drawFirstRewardScreen(ui_state: *FirstRewardUIState) void {
    const screen_width = rl.getScreenWidth();
    const screen_height = rl.getScreenHeight();
    const center_x = @as(f32, @floatFromInt(screen_width)) / 2;
    const center_y = @as(f32, @floatFromInt(screen_height)) / 2;

    // Full screen overlay
    rl.drawRectangle(0, 0, screen_width, screen_height, rl.Color.init(0, 0, 0, 230));

    // Entrance animation
    const anim_progress = @min(1.0, ui_state.animation_timer / 0.5);
    const scale = easeOutBack(anim_progress);

    // Title
    const title = "FIRST VICTORY!";
    const title_size: i32 = 44;
    const title_width = rl.measureText(title, title_size);
    const title_y = center_y - 280 * scale;
    rl.drawText(title, toI32(center_x) - @divTrunc(title_width, 2), toI32(title_y), title_size, rl.Color.gold);

    // Subtitle
    const subtitle = "Choose your reward - 8 new skills to expand your arsenal!";
    const subtitle_width = rl.measureText(subtitle, 18);
    rl.drawText(subtitle, toI32(center_x) - @divTrunc(subtitle_width, 2), toI32(title_y + 55), 18, rl.Color.white);

    // Calculate card positions (3 cards centered)
    const total_width = 3 * BUNDLE_CARD_WIDTH + 2 * BUNDLE_CARD_SPACING;
    var card_x = center_x - total_width / 2;
    const card_y = center_y - BUNDLE_CARD_HEIGHT / 2 + 50;

    // Get mouse position for hover
    const mouse_pos = rl.getMousePosition();
    ui_state.hovered_bundle = null;

    // Draw each bundle card
    for (0..3) |i| {
        const is_hovered = mouse_pos.x >= card_x and mouse_pos.x <= card_x + BUNDLE_CARD_WIDTH and
            mouse_pos.y >= card_y and mouse_pos.y <= card_y + BUNDLE_CARD_HEIGHT;
        if (is_hovered) {
            ui_state.hovered_bundle = @intCast(i);
        }
        const is_selected = if (ui_state.selected_bundle) |sel| sel == i else false;

        drawBundleSelectionCard(
            &ui_state.bundles[i],
            card_x,
            card_y,
            scale,
            is_hovered,
            is_selected,
            ui_state.player_school,
            ui_state.player_position,
            ui_state.friend_school,
            ui_state.friend_position,
            @intCast(i + 1), // Card number (1, 2, 3)
        );
        card_x += BUNDLE_CARD_WIDTH + BUNDLE_CARD_SPACING;
    }

    // Instructions
    const instructions = if (ui_state.selected_bundle != null)
        "[Enter] Confirm Selection  [Esc] Cancel"
    else
        "[Click] or [1] [2] [3] to Select";
    const inst_width = rl.measureText(instructions, 16);
    rl.drawText(instructions, toI32(center_x) - @divTrunc(inst_width, 2), screen_height - 50, 16, palette.UI.TEXT_SECONDARY);
}

/// Draw a single bundle selection card
fn drawBundleSelectionCard(
    bundle: *const FirstRewardBundle,
    x: f32,
    y: f32,
    scale: f32,
    is_hovered: bool,
    is_selected: bool,
    player_school: School,
    player_position: Position,
    friend_school: School,
    friend_position: Position,
    card_number: u8,
) void {
    const scaled_height = BUNDLE_CARD_HEIGHT * scale;
    const xi = toI32(x);
    const yi = toI32(y + (BUNDLE_CARD_HEIGHT - scaled_height) / 2);
    const widthi = toI32(BUNDLE_CARD_WIDTH);
    const heighti = toI32(scaled_height);

    // Card background - different tint per card
    const base_color: rl.Color = switch (card_number) {
        1 => rl.Color.init(50, 35, 35, 255), // Reddish for aggressive
        2 => rl.Color.init(35, 45, 35, 255), // Greenish for defensive
        else => rl.Color.init(35, 35, 50, 255), // Bluish for tactical
    };

    const bg_color = if (is_selected)
        rl.Color.init(base_color.r + 30, base_color.g + 30, base_color.b + 30, 255)
    else if (is_hovered)
        rl.Color.init(base_color.r + 15, base_color.g + 15, base_color.b + 15, 255)
    else
        base_color;
    rl.drawRectangle(xi, yi, widthi, heighti, bg_color);

    // Border
    const border_color = if (is_selected) rl.Color.gold else if (is_hovered) rl.Color.white else palette.UI.BORDER;
    rl.drawRectangleLines(xi, yi, widthi, heighti, border_color);
    if (is_selected or is_hovered) {
        rl.drawRectangleLinesEx(.{ .x = x - 2, .y = y + (BUNDLE_CARD_HEIGHT - scaled_height) / 2 - 2, .width = BUNDLE_CARD_WIDTH + 4, .height = scaled_height + 4 }, 2, border_color);
    }

    const padding: f32 = 12;
    var content_y = y + (BUNDLE_CARD_HEIGHT - scaled_height) / 2 + padding;

    // Bundle name header
    const name_width = rl.measureText(bundle.name, 18);
    rl.drawText(bundle.name, xi + toI32(BUNDLE_CARD_WIDTH / 2) - @divTrunc(name_width, 2), toI32(content_y), 18, rl.Color.white);
    content_y += 25;

    // Description
    const desc_width = rl.measureText(bundle.description, 12);
    rl.drawText(bundle.description, xi + toI32(BUNDLE_CARD_WIDTH / 2) - @divTrunc(desc_width, 2), toI32(content_y), 12, palette.UI.TEXT_SECONDARY);
    content_y += 25;

    // Divider line
    rl.drawLine(xi + 10, toI32(content_y), xi + widthi - 10, toI32(content_y), palette.UI.BORDER);
    content_y += 10;

    // Draw each skill in the bundle (compact 2-column layout)
    const small_icon_size: f32 = 32;
    const skill_row_height: f32 = 42;
    const col_width: f32 = (BUNDLE_CARD_WIDTH - padding * 2) / 2;

    for (0..bundle.skill_count) |i| {
        if (bundle.skills[i]) |skill| {
            const col: f32 = if (i % 2 == 0) 0 else 1;
            const row: f32 = @floatFromInt(i / 2);
            const skill_x = x + padding + col * col_width;
            const skill_y = content_y + row * skill_row_height;

            // Icon - use multi-source version to check all 4 pools (player + friend)
            skill_icons.drawSkillIconMultiSource(
                skill_x,
                skill_y,
                small_icon_size,
                skill,
                player_school,
                player_position,
                friend_school,
                friend_position,
                true,
            );

            // Name (truncated if needed)
            var name_buf: [20:0]u8 = undefined;
            const display_name = if (skill.name.len > 16)
                std.fmt.bufPrintZ(&name_buf, "{s}...", .{skill.name[0..13]}) catch skill.name
            else
                skill.name;
            rl.drawText(display_name, toI32(skill_x + small_icon_size + 4), toI32(skill_y + 4), 10, rl.Color.white);

            // Type
            const type_name = @tagName(skill.skill_type);
            rl.drawText(type_name, toI32(skill_x + small_icon_size + 4), toI32(skill_y + 18), 8, palette.UI.TEXT_SECONDARY);
        }
    }

    // Selection indicator / key hint
    var key_buf: [8:0]u8 = undefined;
    const key_text = std.fmt.bufPrintZ(&key_buf, "[{d}]", .{card_number}) catch "[?]";

    if (is_selected) {
        const check_text = "SELECTED";
        const check_width = rl.measureText(check_text, 16);
        rl.drawText(check_text, xi + toI32(BUNDLE_CARD_WIDTH / 2) - @divTrunc(check_width, 2), yi + heighti - 30, 16, rl.Color.gold);
    } else {
        const key_width = rl.measureText(key_text, 14);
        rl.drawText(key_text, xi + toI32(BUNDLE_CARD_WIDTH / 2) - @divTrunc(key_width, 2), yi + heighti - 28, 14, palette.UI.TEXT_SECONDARY);
    }
}

/// Handle input for first reward selection
/// Returns true if a choice was confirmed
pub fn handleFirstRewardInput(ui_state: *FirstRewardUIState) bool {
    // Click to select
    if (rl.isMouseButtonPressed(.left)) {
        if (ui_state.hovered_bundle) |idx| {
            ui_state.selected_bundle = idx;
        }
    }

    // Number keys to select
    if (rl.isKeyPressed(.one)) ui_state.selected_bundle = 0;
    if (rl.isKeyPressed(.two)) ui_state.selected_bundle = 1;
    if (rl.isKeyPressed(.three)) ui_state.selected_bundle = 2;

    // Confirm selection
    if (rl.isKeyPressed(.enter) or rl.isKeyPressed(.space)) {
        if (ui_state.selected_bundle != null) {
            ui_state.confirmed = true;
            return true;
        }
    }

    // Cancel selection (deselect)
    if (rl.isKeyPressed(.escape)) {
        if (ui_state.selected_bundle != null) {
            ui_state.selected_bundle = null;
        }
    }

    return false;
}

/// Apply the confirmed first reward to campaign state
pub fn applyFirstRewardChoice(campaign_state: *CampaignState, ui_state: *const FirstRewardUIState) void {
    if (!ui_state.confirmed) return;

    if (ui_state.getSelectedBundle()) |bundle| {
        campaign_state.skill_pool.applyFirstRewardBundle(bundle);
    }
}
