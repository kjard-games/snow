//! Polyomino Map UI - Renders the tessellating neighborhood map
//!
//! Handles:
//! - Drawing polyomino blocks with faction colors
//! - Camera panning/zooming constrained to territory
//! - Block selection and hover states
//! - Fog of war visualization
//! - Block labels and encounter icons

const std = @import("std");
const rl = @import("raylib");
const polyomino_map = @import("polyomino_map.zig");
const campaign = @import("campaign.zig");
const palette = @import("color_palette.zig");

const PolyominoMap = polyomino_map.PolyominoMap;
const Block = polyomino_map.Block;
const GridCoord = polyomino_map.GridCoord;
const ChunkCoord = polyomino_map.ChunkCoord;
const BlockState = polyomino_map.BlockState;
const CELL_SIZE = polyomino_map.CELL_SIZE;
const Faction = campaign.Faction;
const EncounterType = campaign.EncounterType;

// ============================================================================
// CONSTANTS
// ============================================================================

const BORDER_THICKNESS: f32 = 2.0;
const HOVER_BORDER_THICKNESS: f32 = 3.0;
const SELECTED_BORDER_THICKNESS: f32 = 4.0;

const FOG_COLOR = rl.Color.init(20, 25, 35, 255);
const REVEALED_DIM: u8 = 180; // Alpha for revealed but not conquered
const GRID_LINE_COLOR = rl.Color.init(50, 55, 65, 100);

// ============================================================================
// UI STATE
// ============================================================================

/// State for the polyomino map UI
pub const PolyominoMapUIState = struct {
    /// Camera offset (pan)
    camera_x: f32 = 0,
    camera_y: f32 = 0,

    /// Camera zoom level (1.0 = default)
    zoom: f32 = 1.0,

    /// Currently hovered block ID
    hovered_block_id: ?u32 = null,

    /// Currently selected block ID
    selected_block_id: ?u32 = null,

    /// Is the user dragging to pan?
    is_panning: bool = false,
    pan_start_x: f32 = 0,
    pan_start_y: f32 = 0,
    camera_start_x: f32 = 0,
    camera_start_y: f32 = 0,

    /// Min/max zoom levels
    const MIN_ZOOM: f32 = 0.3;
    const MAX_ZOOM: f32 = 2.0;

    pub fn reset(self: *PolyominoMapUIState) void {
        self.camera_x = 0;
        self.camera_y = 0;
        self.zoom = 1.0;
        self.hovered_block_id = null;
        self.selected_block_id = null;
        self.is_panning = false;
    }

    /// Clamp camera to map bounds
    pub fn clampCamera(self: *PolyominoMapUIState, map: *PolyominoMap, screen_width: f32, screen_height: f32) void {
        const bounds = map.camera_bounds;
        const view_width = screen_width / self.zoom;
        const view_height = screen_height / self.zoom;

        // Clamp so we can't pan outside the bounds
        const min_cam_x = bounds.min_x;
        const max_cam_x = bounds.max_x - view_width;
        const min_cam_y = bounds.min_y;
        const max_cam_y = bounds.max_y - view_height;

        if (max_cam_x > min_cam_x) {
            self.camera_x = std.math.clamp(self.camera_x, min_cam_x, max_cam_x);
        } else {
            // Map smaller than screen - center it
            self.camera_x = (bounds.min_x + bounds.max_x) / 2 - view_width / 2;
        }

        if (max_cam_y > min_cam_y) {
            self.camera_y = std.math.clamp(self.camera_y, min_cam_y, max_cam_y);
        } else {
            self.camera_y = (bounds.min_y + bounds.max_y) / 2 - view_height / 2;
        }
    }

    /// Convert screen coordinates to world coordinates
    pub fn screenToWorld(self: PolyominoMapUIState, screen_x: f32, screen_y: f32) struct { x: f32, y: f32 } {
        return .{
            .x = screen_x / self.zoom + self.camera_x,
            .y = screen_y / self.zoom + self.camera_y,
        };
    }

    /// Convert world coordinates to screen coordinates
    pub fn worldToScreen(self: PolyominoMapUIState, world_x: f32, world_y: f32) struct { x: f32, y: f32 } {
        return .{
            .x = (world_x - self.camera_x) * self.zoom,
            .y = (world_y - self.camera_y) * self.zoom,
        };
    }
};

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

inline fn toI32(val: f32) i32 {
    return @intFromFloat(val);
}

/// Get color for a faction
fn getFactionColor(faction: ?Faction, alpha: u8) rl.Color {
    if (faction) |f| {
        const color_hex = f.getColor();
        return rl.Color.init(
            @truncate((color_hex >> 16) & 0xFF),
            @truncate((color_hex >> 8) & 0xFF),
            @truncate(color_hex & 0xFF),
            alpha,
        );
    } else {
        // Contested/neutral - gray
        return rl.Color.init(100, 100, 100, alpha);
    }
}

/// Get encounter type icon
fn getEncounterIcon(encounter_type: EncounterType) [:0]const u8 {
    return switch (encounter_type) {
        .skirmish => "S",
        .boss_capture => "B",
        .intel => "?",
        .strategic => "!",
        .recruitment => "+",
    };
}

/// Get encounter type color
fn getEncounterColor(encounter_type: EncounterType) rl.Color {
    return switch (encounter_type) {
        .skirmish => rl.Color.init(100, 180, 100, 255),
        .boss_capture => rl.Color.init(255, 180, 50, 255),
        .intel => rl.Color.init(100, 150, 255, 255),
        .strategic => rl.Color.init(255, 100, 100, 255),
        .recruitment => rl.Color.init(200, 100, 255, 255),
    };
}

// ============================================================================
// DRAWING FUNCTIONS
// ============================================================================

/// Draw the entire polyomino map
pub fn drawPolyominoMap(
    map: *PolyominoMap,
    ui_state: *PolyominoMapUIState,
    area_x: f32,
    area_y: f32,
    area_width: f32,
    area_height: f32,
) void {
    // Set up scissor for map area
    rl.beginScissorMode(toI32(area_x), toI32(area_y), toI32(area_width), toI32(area_height));
    defer rl.endScissorMode();

    // Draw background
    rl.drawRectangle(toI32(area_x), toI32(area_y), toI32(area_width), toI32(area_height), FOG_COLOR);

    // Get mouse position for hover detection
    const mouse_pos = rl.getMousePosition();
    ui_state.hovered_block_id = null;

    // Draw all visible blocks
    var block_buffer: [256]?*Block = [_]?*Block{null} ** 256;
    const visible_count = map.getVisibleBlocks(&block_buffer);

    for (block_buffer[0..visible_count]) |maybe_block| {
        if (maybe_block) |block| {
            const is_hovered = if (ui_state.hovered_block_id) |hid| hid == block.id else false;
            const is_selected = if (ui_state.selected_block_id) |sid| sid == block.id else false;

            drawBlock(block, ui_state, area_x, area_y, is_hovered, is_selected);

            // Check hover
            if (isMouseOverBlock(block, ui_state, mouse_pos, area_x, area_y)) {
                ui_state.hovered_block_id = block.id;
            }
        }
    }

    // Draw grid lines (subtle, for reference)
    drawGridLines(ui_state, area_x, area_y, area_width, area_height);
}

/// Draw a single block (polyomino)
fn drawBlock(
    block: *Block,
    ui_state: *PolyominoMapUIState,
    area_x: f32,
    area_y: f32,
    is_hovered: bool,
    is_selected: bool,
) void {
    // Determine colors based on state
    const alpha: u8 = switch (block.state) {
        .fogged => 0, // Shouldn't render fogged blocks
        .revealed => REVEALED_DIM,
        .conquered => 255,
    };

    if (alpha == 0) return;

    const fill_color = getFactionColor(block.faction, alpha);
    const border_color = if (is_selected)
        rl.Color.yellow
    else if (is_hovered)
        rl.Color.white
    else
        rl.Color.init(30, 35, 45, 255);

    const border_thickness = if (is_selected)
        SELECTED_BORDER_THICKNESS
    else if (is_hovered)
        HOVER_BORDER_THICKNESS
    else
        BORDER_THICKNESS;

    // Draw each cell of the block
    for (block.getCells()) |cell| {
        const world_pos = cell.toWorldPos();
        const screen_pos = ui_state.worldToScreen(world_pos.x - CELL_SIZE / 2, world_pos.y - CELL_SIZE / 2);

        const cell_x = area_x + screen_pos.x;
        const cell_y = area_y + screen_pos.y;
        const cell_size = CELL_SIZE * ui_state.zoom;

        // Fill
        rl.drawRectangle(toI32(cell_x), toI32(cell_y), toI32(cell_size), toI32(cell_size), fill_color);
    }

    // Draw borders (only on edges that don't connect to same block)
    for (block.getCells()) |cell| {
        const world_pos = cell.toWorldPos();
        const screen_pos = ui_state.worldToScreen(world_pos.x - CELL_SIZE / 2, world_pos.y - CELL_SIZE / 2);

        const cell_x = area_x + screen_pos.x;
        const cell_y = area_y + screen_pos.y;
        const cell_size = CELL_SIZE * ui_state.zoom;

        // Check each edge
        const neighbors = cell.neighbors();
        const edges = [_]struct { nx: f32, ny: f32, w: f32, h: f32 }{
            .{ .nx = cell_x, .ny = cell_y, .w = cell_size, .h = border_thickness }, // Top
            .{ .nx = cell_x + cell_size - border_thickness, .ny = cell_y, .w = border_thickness, .h = cell_size }, // Right
            .{ .nx = cell_x, .ny = cell_y + cell_size - border_thickness, .w = cell_size, .h = border_thickness }, // Bottom
            .{ .nx = cell_x, .ny = cell_y, .w = border_thickness, .h = cell_size }, // Left
        };

        for (neighbors, edges) |neighbor, edge| {
            // Only draw border if neighbor is not part of this block
            if (!block.containsCell(neighbor)) {
                rl.drawRectangle(toI32(edge.nx), toI32(edge.ny), toI32(edge.w), toI32(edge.h), border_color);
            }
        }
    }

    // Draw block label at centroid
    if (ui_state.zoom > 0.5) {
        const centroid = block.getCentroid();
        const screen_centroid = ui_state.worldToScreen(centroid.x, centroid.y);
        const label_x = area_x + screen_centroid.x;
        const label_y = area_y + screen_centroid.y;

        // Draw encounter icon if block has encounter
        if (block.encounter) |encounter| {
            const icon = getEncounterIcon(encounter.encounter_type);
            const icon_color = if (block.state == .conquered) rl.Color.gray else getEncounterColor(encounter.encounter_type);
            const icon_size: i32 = @intFromFloat(20 * ui_state.zoom);
            const icon_width = rl.measureText(icon, icon_size);
            rl.drawText(icon, toI32(label_x) - @divTrunc(icon_width, 2), toI32(label_y) - @divTrunc(icon_size, 2), icon_size, icon_color);
        }

        // Draw name below icon if zoomed in enough
        if (ui_state.zoom > 0.8) {
            const name_size: i32 = @intFromFloat(10 * ui_state.zoom);
            // Create null-terminated buffer for raylib
            var name_buf: [64:0]u8 = [_:0]u8{0} ** 64;
            const copy_len = @min(block.name.len, 63);
            @memcpy(name_buf[0..copy_len], block.name[0..copy_len]);
            const name_width = rl.measureText(&name_buf, name_size);
            const name_color = if (block.state == .conquered) rl.Color.white else rl.Color.init(200, 200, 200, REVEALED_DIM);
            rl.drawText(&name_buf, toI32(label_x) - @divTrunc(name_width, 2), toI32(label_y) + toI32(12 * ui_state.zoom), name_size, name_color);
        }
    }
}

/// Check if mouse is over a block
fn isMouseOverBlock(
    block: *Block,
    ui_state: *PolyominoMapUIState,
    mouse_pos: rl.Vector2,
    area_x: f32,
    area_y: f32,
) bool {
    // Convert mouse to world coordinates
    const relative_x = mouse_pos.x - area_x;
    const relative_y = mouse_pos.y - area_y;

    if (relative_x < 0 or relative_y < 0) return false;

    const world = ui_state.screenToWorld(relative_x, relative_y);

    // Check if world position is within any cell of this block
    for (block.getCells()) |cell| {
        const cell_world = cell.toWorldPos();
        const half_cell = CELL_SIZE / 2;

        if (world.x >= cell_world.x - half_cell and
            world.x < cell_world.x + half_cell and
            world.y >= cell_world.y - half_cell and
            world.y < cell_world.y + half_cell)
        {
            return true;
        }
    }

    return false;
}

/// Draw subtle grid lines
fn drawGridLines(
    ui_state: *PolyominoMapUIState,
    area_x: f32,
    area_y: f32,
    area_width: f32,
    area_height: f32,
) void {
    // Only draw grid if zoomed in enough
    if (ui_state.zoom < 0.6) return;

    // Calculate visible grid range
    const start_world = ui_state.screenToWorld(0, 0);
    const end_world = ui_state.screenToWorld(area_width, area_height);

    const start_grid_x: i32 = @intFromFloat(@floor(start_world.x / CELL_SIZE));
    const start_grid_y: i32 = @intFromFloat(@floor(start_world.y / CELL_SIZE));
    const end_grid_x: i32 = @intFromFloat(@ceil(end_world.x / CELL_SIZE));
    const end_grid_y: i32 = @intFromFloat(@ceil(end_world.y / CELL_SIZE));

    // Vertical lines
    var x = start_grid_x;
    while (x <= end_grid_x) : (x += 1) {
        const world_x = @as(f32, @floatFromInt(x)) * CELL_SIZE;
        const screen = ui_state.worldToScreen(world_x, 0);
        const screen_x = area_x + screen.x;
        rl.drawLine(toI32(screen_x), toI32(area_y), toI32(screen_x), toI32(area_y + area_height), GRID_LINE_COLOR);
    }

    // Horizontal lines
    var y = start_grid_y;
    while (y <= end_grid_y) : (y += 1) {
        const world_y = @as(f32, @floatFromInt(y)) * CELL_SIZE;
        const screen = ui_state.worldToScreen(0, world_y);
        const screen_y = area_y + screen.y;
        rl.drawLine(toI32(area_x), toI32(screen_y), toI32(area_x + area_width), toI32(screen_y), GRID_LINE_COLOR);
    }
}

/// Draw the selected block details panel
pub fn drawBlockDetails(
    map: *PolyominoMap,
    ui_state: *PolyominoMapUIState,
    panel_x: f32,
    panel_y: f32,
    panel_width: f32,
) void {
    const block_id = ui_state.selected_block_id orelse ui_state.hovered_block_id orelse return;
    const block = map.getBlock(block_id) orelse return;

    const panel_height: f32 = 250;
    const padding: f32 = 12;

    // Panel background
    rl.drawRectangle(toI32(panel_x), toI32(panel_y), toI32(panel_width), toI32(panel_height), palette.UI.BACKGROUND);
    rl.drawRectangleLines(toI32(panel_x), toI32(panel_y), toI32(panel_width), toI32(panel_height), palette.UI.BORDER);

    var current_y = panel_y + padding;

    // Block name - create null-terminated buffer
    var name_buf: [64:0]u8 = [_:0]u8{0} ** 64;
    const copy_len = @min(block.name.len, 63);
    @memcpy(name_buf[0..copy_len], block.name[0..copy_len]);
    rl.drawText(&name_buf, toI32(panel_x + padding), toI32(current_y), 18, rl.Color.white);
    current_y += 24;

    // State indicator
    const state_text = switch (block.state) {
        .fogged => "FOGGED",
        .revealed => "UNEXPLORED",
        .conquered => "CONQUERED",
    };
    const state_color = switch (block.state) {
        .fogged => rl.Color.gray,
        .revealed => rl.Color.yellow,
        .conquered => rl.Color.green,
    };
    rl.drawText(state_text, toI32(panel_x + padding), toI32(current_y), 12, state_color);
    current_y += 18;

    // Faction
    if (block.faction) |faction| {
        const faction_name = faction.getName();
        const faction_color = getFactionColor(block.faction, 255);
        rl.drawText(faction_name, toI32(panel_x + padding), toI32(current_y), 12, faction_color);
    } else {
        rl.drawText("Contested Territory", toI32(panel_x + padding), toI32(current_y), 12, rl.Color.gray);
    }
    current_y += 20;

    // Encounter info (if not conquered)
    if (block.encounter) |encounter| {
        current_y += 10;
        rl.drawLine(toI32(panel_x + padding), toI32(current_y), toI32(panel_x + panel_width - padding), toI32(current_y), palette.UI.BORDER);
        current_y += 10;

        // Encounter type
        const enc_name = encounter.encounter_type.getName();
        const enc_color = getEncounterColor(encounter.encounter_type);
        rl.drawText(enc_name, toI32(panel_x + padding), toI32(current_y), 14, enc_color);
        current_y += 18;

        // Description
        const enc_desc = encounter.encounter_type.getDescription();
        rl.drawText(enc_desc, toI32(panel_x + padding), toI32(current_y), 9, palette.UI.TEXT_SECONDARY);
        current_y += 35;

        // Challenge rating
        var cr_buf: [32]u8 = undefined;
        const cr_text = std.fmt.bufPrintZ(&cr_buf, "Difficulty: {d}/10", .{encounter.challenge_rating}) catch "Difficulty: ?";
        rl.drawText(cr_text, toI32(panel_x + padding), toI32(current_y), 11, rl.Color.white);
        current_y += 16;

        // Expiration
        if (encounter.expires_in_turns) |turns| {
            var exp_buf: [32]u8 = undefined;
            const exp_text = std.fmt.bufPrintZ(&exp_buf, "Expires in: {d} turns", .{turns}) catch "Expires: ?";
            rl.drawText(exp_text, toI32(panel_x + padding), toI32(current_y), 11, rl.Color.yellow);
        }
    }

    // Action prompt at bottom
    if (block.state == .revealed) {
        rl.drawText("[Enter] Engage", toI32(panel_x + padding), toI32(panel_y + panel_height - 25), 12, rl.Color.white);
    }
}

// ============================================================================
// INPUT HANDLING
// ============================================================================

/// Handle input for the polyomino map
/// Returns selected block ID if player confirms engagement
pub fn handlePolyominoMapInput(
    map: *PolyominoMap,
    ui_state: *PolyominoMapUIState,
    area_x: f32,
    area_y: f32,
    area_width: f32,
    area_height: f32,
) ?u32 {
    const mouse_pos = rl.getMousePosition();

    // Check if mouse is in map area
    const in_area = mouse_pos.x >= area_x and mouse_pos.x < area_x + area_width and
        mouse_pos.y >= area_y and mouse_pos.y < area_y + area_height;

    // Zoom with scroll wheel
    if (in_area) {
        const wheel = rl.getMouseWheelMove();
        if (wheel != 0) {
            const old_zoom = ui_state.zoom;
            ui_state.zoom = std.math.clamp(
                ui_state.zoom + wheel * 0.1,
                PolyominoMapUIState.MIN_ZOOM,
                PolyominoMapUIState.MAX_ZOOM,
            );

            // Zoom toward mouse position
            if (ui_state.zoom != old_zoom) {
                const mouse_world_before = ui_state.screenToWorld(mouse_pos.x - area_x, mouse_pos.y - area_y);
                // Recalculate after zoom change
                const new_world_x = (mouse_pos.x - area_x) / ui_state.zoom + ui_state.camera_x;
                const new_world_y = (mouse_pos.y - area_y) / ui_state.zoom + ui_state.camera_y;
                // Adjust camera to keep mouse position stable
                ui_state.camera_x += mouse_world_before.x - new_world_x;
                ui_state.camera_y += mouse_world_before.y - new_world_y;
            }
        }
    }

    // Pan with middle mouse or right mouse drag
    if (rl.isMouseButtonPressed(.middle) or rl.isMouseButtonPressed(.right)) {
        if (in_area) {
            ui_state.is_panning = true;
            ui_state.pan_start_x = mouse_pos.x;
            ui_state.pan_start_y = mouse_pos.y;
            ui_state.camera_start_x = ui_state.camera_x;
            ui_state.camera_start_y = ui_state.camera_y;
        }
    }

    if (ui_state.is_panning) {
        if (rl.isMouseButtonDown(.middle) or rl.isMouseButtonDown(.right)) {
            const dx = (mouse_pos.x - ui_state.pan_start_x) / ui_state.zoom;
            const dy = (mouse_pos.y - ui_state.pan_start_y) / ui_state.zoom;
            ui_state.camera_x = ui_state.camera_start_x - dx;
            ui_state.camera_y = ui_state.camera_start_y - dy;
        } else {
            ui_state.is_panning = false;
        }
    }

    // Clamp camera to bounds
    ui_state.clampCamera(map, area_width, area_height);

    // Click to select
    if (rl.isMouseButtonPressed(.left) and in_area) {
        if (ui_state.hovered_block_id) |hovered_id| {
            ui_state.selected_block_id = hovered_id;
        }
    }

    // Enter to engage selected block
    if (rl.isKeyPressed(.enter) or rl.isKeyPressed(.space)) {
        if (ui_state.selected_block_id) |selected_id| {
            if (map.getBlock(selected_id)) |block| {
                if (block.state == .revealed and block.encounter != null) {
                    return selected_id;
                }
            }
        }
    }

    // Escape to deselect
    if (rl.isKeyPressed(.escape)) {
        ui_state.selected_block_id = null;
    }

    return null;
}

// ============================================================================
// MINIMAP
// ============================================================================

/// Draw a minimap showing conquered territory overview
pub fn drawMinimap(
    map: *PolyominoMap,
    ui_state: *PolyominoMapUIState,
    minimap_x: f32,
    minimap_y: f32,
    minimap_size: f32,
) void {
    _ = ui_state;

    // Background
    rl.drawRectangle(toI32(minimap_x), toI32(minimap_y), toI32(minimap_size), toI32(minimap_size), rl.Color.init(20, 25, 35, 200));
    rl.drawRectangleLines(toI32(minimap_x), toI32(minimap_y), toI32(minimap_size), toI32(minimap_size), palette.UI.BORDER);

    // Calculate scale to fit all visible blocks
    const bounds = map.camera_bounds;
    const world_width = bounds.max_x - bounds.min_x;
    const world_height = bounds.max_y - bounds.min_y;
    const scale = @min(minimap_size / world_width, minimap_size / world_height) * 0.9;

    const offset_x = minimap_x + (minimap_size - world_width * scale) / 2;
    const offset_y = minimap_y + (minimap_size - world_height * scale) / 2;

    // Draw blocks as small colored rectangles
    var block_buffer: [256]?*Block = [_]?*Block{null} ** 256;
    const visible_count = map.getVisibleBlocks(&block_buffer);

    for (block_buffer[0..visible_count]) |maybe_block| {
        if (maybe_block) |block| {
            const color = getFactionColor(block.faction, if (block.state == .conquered) 255 else 100);

            for (block.getCells()) |cell| {
                const world = cell.toWorldPos();
                const mini_x = offset_x + (world.x - bounds.min_x) * scale;
                const mini_y = offset_y + (world.y - bounds.min_y) * scale;
                const mini_size = CELL_SIZE * scale;

                rl.drawRectangle(toI32(mini_x - mini_size / 2), toI32(mini_y - mini_size / 2), toI32(mini_size), toI32(mini_size), color);
            }
        }
    }
}
