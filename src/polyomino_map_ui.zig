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
const VisibilityLayer = polyomino_map.VisibilityLayer;
const CELL_SIZE = polyomino_map.CELL_SIZE;
const Faction = campaign.Faction;
const EncounterType = campaign.EncounterType;

// ============================================================================
// CONSTANTS
// ============================================================================

const EXTERIOR_BORDER_THICKNESS: f32 = 4.0; // Thick border on faction exterior
const INTERIOR_BORDER_THICKNESS: f32 = 1.5; // Thin border between same-faction blocks
const HOVER_BORDER_THICKNESS: f32 = 5.0;
const SELECTED_BORDER_THICKNESS: f32 = 6.0;

const FOG_COLOR = rl.Color.init(20, 25, 35, 255);
const GRID_LINE_COLOR = rl.Color.init(50, 55, 65, 100);

// Interior border dimming factor (how dim same-faction interior borders are)
const INTERIOR_BORDER_DIM: u8 = 60; // Very dim

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

            drawBlock(block, map, ui_state, area_x, area_y, is_hovered, is_selected);

            // Check hover
            if (isMouseOverBlock(block, ui_state, mouse_pos, area_x, area_y)) {
                ui_state.hovered_block_id = block.id;
            }
        }
    }

    // Draw grid lines (subtle, for reference)
    drawGridLines(ui_state, area_x, area_y, area_width, area_height);
}

/// Border type for territory edges
const BorderType = enum {
    none, // Deep interior, no border needed
    interior_frontier, // Same faction at frontier - dim dashed
    solid, // Different factions meet (both visible)
    solid_foggy, // Different factions meet but neighbor is in fog - solid with foggy fade
    dashed, // Frontier edge into fog/unexplored (same faction)
    squiggly, // Edge into true fog
};

/// Draw a single block (polyomino)
/// Border rendering follows territory map conventions:
/// - NO borders deep inside same-faction contiguous territory
/// - DIM DASHED lines between same-faction blocks at the frontier
/// - SOLID lines where two different factions meet
/// - DASHED lines at frontier (edge of explored into less-explored)
/// - SQUIGGLY lines fading into true unexplored fog
fn drawBlock(
    block: *Block,
    map: *PolyominoMap,
    ui_state: *PolyominoMapUIState,
    area_x: f32,
    area_y: f32,
    is_hovered: bool,
    is_selected: bool,
) void {
    // Get alpha based on visibility layer
    const layer_alpha = block.visibility_layer.getAlpha();

    if (layer_alpha == 0) return;

    // Block interior: subtle neutral fill (will eventually be illustrated)
    // Brightness varies by visibility layer
    const base_brightness: u8 = switch (block.visibility_layer) {
        .conquered => 45,
        .layer_1 => 40,
        .layer_2 => 32,
        .layer_3 => 25,
        .fogged => 20,
    };
    const fill_color = rl.Color.init(base_brightness, base_brightness + 5, base_brightness + 15, layer_alpha);

    // Draw each cell of the block - neutral fill only
    for (block.getCells()) |cell| {
        const world_pos = cell.toWorldPos();
        const screen_pos = ui_state.worldToScreen(world_pos.x - CELL_SIZE / 2, world_pos.y - CELL_SIZE / 2);

        const cell_x = area_x + screen_pos.x;
        const cell_y = area_y + screen_pos.y;
        const cell_size = CELL_SIZE * ui_state.zoom;

        // Neutral fill (placeholder for future illustration)
        rl.drawRectangle(toI32(cell_x), toI32(cell_y), toI32(cell_size), toI32(cell_size), fill_color);
    }

    // Draw territory borders - only at faction boundaries and frontiers
    for (block.getCells()) |cell| {
        const world_pos = cell.toWorldPos();
        const screen_pos = ui_state.worldToScreen(world_pos.x - CELL_SIZE / 2, world_pos.y - CELL_SIZE / 2);

        const cell_x = area_x + screen_pos.x;
        const cell_y = area_y + screen_pos.y;
        const cell_size = CELL_SIZE * ui_state.zoom;

        // Check each edge (N, E, S, W)
        const neighbors = cell.neighbors();

        for (neighbors, 0..) |neighbor, edge_idx| {
            // Skip if neighbor is part of this same block (internal edge)
            if (block.containsCell(neighbor)) continue;

            // Get the neighbor block info
            const neighbor_chunk_coord = neighbor.toChunkCoord();
            const neighbor_block: ?*Block = blk: {
                if (map.getChunk(neighbor_chunk_coord)) |chunk| {
                    break :blk chunk.getBlockAt(neighbor);
                }
                break :blk null;
            };

            // Determine border type based on neighbor
            const border_type = determineBorderType(block, neighbor_block, map);

            // Skip if no border needed (deep interior)
            if (border_type == .none) continue;

            // Get faction color for this border
            const border_color = getFactionColor(block.faction, 255);

            // Draw the appropriate border style
            switch (border_type) {
                .none => {},
                .interior_frontier => {
                    // Dim dashed lines for same-faction frontier blocks
                    const dim_color = rl.Color.init(border_color.r, border_color.g, border_color.b, 80);
                    drawDashedBorder(cell_x, cell_y, cell_size, edge_idx, dim_color, ui_state.zoom * 0.5);
                },
                .solid => drawSolidBorder(cell_x, cell_y, cell_size, edge_idx, border_color, ui_state.zoom),
                .solid_foggy => drawSolidFoggyBorder(cell_x, cell_y, cell_size, edge_idx, border_color, ui_state.zoom),
                .dashed => drawDashedBorder(cell_x, cell_y, cell_size, edge_idx, border_color, ui_state.zoom),
                .squiggly => drawSquigglyBorder(cell_x, cell_y, cell_size, edge_idx, border_color, ui_state.zoom),
            }
        }
    }

    // Draw selection/hover highlight
    if (is_selected or is_hovered) {
        const highlight_color = if (is_selected) rl.Color.yellow else rl.Color.white;
        for (block.getCells()) |cell| {
            const world_pos = cell.toWorldPos();
            const screen_pos = ui_state.worldToScreen(world_pos.x - CELL_SIZE / 2, world_pos.y - CELL_SIZE / 2);
            const cell_x = area_x + screen_pos.x;
            const cell_y = area_y + screen_pos.y;
            const cell_size = CELL_SIZE * ui_state.zoom;

            // Draw highlight on edges that are block boundaries
            const neighbors = cell.neighbors();
            for (neighbors, 0..) |neighbor, edge_idx| {
                if (!block.containsCell(neighbor)) {
                    const thickness = if (is_selected) SELECTED_BORDER_THICKNESS else HOVER_BORDER_THICKNESS;
                    drawSolidBorder(cell_x, cell_y, cell_size, edge_idx, highlight_color, ui_state.zoom * thickness / EXTERIOR_BORDER_THICKNESS);
                }
            }
        }
    }

    // Draw flag marker at centroid for blocks with encounters that can be engaged
    if (ui_state.zoom > 0.4 and (block.visibility_layer == .layer_1 or block.visibility_layer == .conquered)) {
        const centroid = block.getCentroid();
        const screen_centroid = ui_state.worldToScreen(centroid.x, centroid.y);
        const label_x = area_x + screen_centroid.x;
        const label_y = area_y + screen_centroid.y;

        // Check if this is the tutorial target (starting block in tutorial mode)
        const is_tutorial_target = map.in_tutorial_mode and
            map.start_block_id != null and
            block.id == map.start_block_id.?;

        if (block.encounter) |encounter| {
            // Draw flag marker for:
            // 1. Tutorial target ONLY during tutorial mode
            // 2. Unconquered blocks when NOT in tutorial mode (normal gameplay)
            const should_show_flag = if (map.in_tutorial_mode)
                is_tutorial_target
            else
                block.state != .conquered;

            if (should_show_flag) {
                drawFlagMarker(label_x, label_y, encounter.encounter_type, ui_state.zoom, layer_alpha);
            }
        }

        // Draw name below marker if zoomed in enough
        if (ui_state.zoom > 0.8) {
            const name_size: i32 = @intFromFloat(10 * ui_state.zoom);
            var name_buf: [64:0]u8 = [_:0]u8{0} ** 64;
            const copy_len = @min(block.name.len, 63);
            @memcpy(name_buf[0..copy_len], block.name[0..copy_len]);
            const name_width = rl.measureText(&name_buf, name_size);
            const name_color = if (block.state == .conquered and !is_tutorial_target) rl.Color.init(255, 255, 255, layer_alpha) else rl.Color.init(200, 200, 200, layer_alpha);
            const marker_offset: f32 = if (block.state == .conquered and !is_tutorial_target) 0 else 18 * ui_state.zoom;
            rl.drawText(&name_buf, toI32(label_x) - @divTrunc(name_width, 2), toI32(label_y + marker_offset), name_size, name_color);
        }
    }
}

/// Determine what type of border to draw between this block and its neighbor
/// Based on the matrix:
/// - L0: hard border with rivals, dashed interiors
/// - L1: hard border with rivals (solid if neighbor L0/L1, solid_foggy if neighbor L2/L3), dashed interior with L2
/// - L2: squiggly with rivals, no internal borders
/// - L3: squiggly with rivals, no internal borders, squiggly with outside
fn determineBorderType(block: *Block, neighbor_block: ?*Block, map: *PolyominoMap) BorderType {
    _ = map;

    // No neighbor block = edge into outside/unexplored
    if (neighbor_block == null) {
        return switch (block.visibility_layer) {
            .conquered => .none, // L0 doesn't border outside
            .layer_1 => .dashed, // L1 frontier into unknown
            .layer_2 => .squiggly, // L2 fog edge
            .layer_3 => .squiggly, // L3 fog edge into outside
            .fogged => .none,
        };
    }

    const neighbor = neighbor_block.?;

    // If neighbor is completely fogged (not visible at all)
    if (neighbor.visibility_layer == .fogged) {
        return switch (block.visibility_layer) {
            .conquered => .none,
            .layer_1 => .dashed,
            .layer_2, .layer_3 => .squiggly,
            .fogged => .none,
        };
    }

    // Same faction check
    const same_faction = (block.faction != null and neighbor.faction != null and block.faction.? == neighbor.faction.?);

    // === L0 (Conquered) ===
    if (block.visibility_layer == .conquered) {
        if (!same_faction) {
            return .solid; // Hard border with all rival teams
        }
        // Same faction - dashed interiors (but only if neighbor is also L0, otherwise let neighbor draw)
        if (neighbor.visibility_layer == .conquered) {
            return .interior_frontier; // Dashed interior
        }
        return .none; // Let the other block handle it
    }

    // === L1 ===
    if (block.visibility_layer == .layer_1) {
        if (!same_faction) {
            // Hard line with rivals, but style depends on neighbor visibility
            return switch (neighbor.visibility_layer) {
                .conquered, .layer_1 => .solid, // Clear faction boundary
                .layer_2, .layer_3 => .solid_foggy, // Faction boundary fading into fog
                .fogged => .dashed,
            };
        }
        // Same faction
        return switch (neighbor.visibility_layer) {
            .conquered => .interior_frontier, // Dashed interior with L0
            .layer_1 => .interior_frontier, // Dashed interior with other L1
            .layer_2 => .dashed, // Dotted interior with L2
            .layer_3 => .squiggly, // Fog transition
            .fogged => .dashed,
        };
    }

    // === L2 ===
    if (block.visibility_layer == .layer_2) {
        if (!same_faction) {
            return .squiggly; // Foggy line with rivals
        }
        // Same faction - no internal borders
        return .none;
    }

    // === L3 ===
    if (block.visibility_layer == .layer_3) {
        if (!same_faction) {
            return .squiggly; // Foggy line with rivals
        }
        // Same faction - no internal borders (squiggly with outside handled above)
        return .none;
    }

    return .none;
}

/// Draw a solid border line
fn drawSolidBorder(cell_x: f32, cell_y: f32, cell_size: f32, edge_idx: usize, color: rl.Color, zoom: f32) void {
    const thickness = EXTERIOR_BORDER_THICKNESS * zoom;
    const edge_rect = getEdgeRect(cell_x, cell_y, cell_size, edge_idx, thickness);
    rl.drawRectangle(toI32(edge_rect.x), toI32(edge_rect.y), toI32(edge_rect.w), toI32(edge_rect.h), color);
}

/// Draw a dashed border line
fn drawDashedBorder(cell_x: f32, cell_y: f32, cell_size: f32, edge_idx: usize, color: rl.Color, zoom: f32) void {
    const thickness = EXTERIOR_BORDER_THICKNESS * zoom;
    const dash_len: f32 = 8.0 * zoom;
    const gap_len: f32 = 6.0 * zoom;

    const is_horizontal = (edge_idx == 0 or edge_idx == 2);
    const total_len = cell_size;

    // Get starting position for this edge
    var start_x: f32 = cell_x;
    var start_y: f32 = cell_y;

    switch (edge_idx) {
        0 => {}, // Top - start at top-left
        1 => start_x = cell_x + cell_size - thickness, // Right
        2 => start_y = cell_y + cell_size - thickness, // Bottom
        3 => {}, // Left - start at top-left
        else => {},
    }

    // Draw dashes
    var pos: f32 = 0;
    while (pos < total_len) {
        const dash_actual = @min(dash_len, total_len - pos);

        if (is_horizontal) {
            rl.drawRectangle(toI32(start_x + pos), toI32(start_y), toI32(dash_actual), toI32(thickness), color);
        } else {
            rl.drawRectangle(toI32(start_x), toI32(start_y + pos), toI32(thickness), toI32(dash_actual), color);
        }

        pos += dash_len + gap_len;
    }
}

/// Draw a squiggly/wavy border line (for fog edge)
fn drawSquigglyBorder(cell_x: f32, cell_y: f32, cell_size: f32, edge_idx: usize, color: rl.Color, zoom: f32) void {
    const thickness = 2.0 * zoom;
    const wave_amplitude: f32 = 4.0 * zoom;
    const wave_frequency: f32 = 0.15 / zoom; // Adjust for zoom
    const step: f32 = 3.0 * zoom;

    const is_horizontal = (edge_idx == 0 or edge_idx == 2);
    const total_len = cell_size;

    // Fade alpha for fog edge
    const faded_color = rl.Color.init(color.r, color.g, color.b, 120);

    // Get base position for this edge
    var base_x: f32 = cell_x;
    var base_y: f32 = cell_y;

    switch (edge_idx) {
        0 => {}, // Top
        1 => base_x = cell_x + cell_size, // Right
        2 => base_y = cell_y + cell_size, // Bottom
        3 => {}, // Left
        else => {},
    }

    // Draw wavy line
    var pos: f32 = 0;
    while (pos < total_len) {
        const wave_offset = wave_amplitude * @sin(pos * wave_frequency);

        if (is_horizontal) {
            const x = base_x + pos;
            const y = base_y + wave_offset;
            rl.drawCircle(toI32(x), toI32(y), thickness, faded_color);
        } else {
            const x = base_x + wave_offset;
            const y = base_y + pos;
            rl.drawCircle(toI32(x), toI32(y), thickness, faded_color);
        }

        pos += step;
    }
}

/// Draw a solid border with foggy fade on the outer edge
/// Used when L1 faction boundary meets L2/L3 fog - shows hard line fading into mist
fn drawSolidFoggyBorder(cell_x: f32, cell_y: f32, cell_size: f32, edge_idx: usize, color: rl.Color, zoom: f32) void {
    // First draw the solid border line (on the inside)
    const thickness = EXTERIOR_BORDER_THICKNESS * zoom;
    const edge_rect = getEdgeRect(cell_x, cell_y, cell_size, edge_idx, thickness);
    rl.drawRectangle(toI32(edge_rect.x), toI32(edge_rect.y), toI32(edge_rect.w), toI32(edge_rect.h), color);

    // Then draw a foggy/squiggly effect on the outside (into the fog)
    const wave_thickness = 2.0 * zoom;
    const wave_amplitude: f32 = 3.0 * zoom;
    const wave_frequency: f32 = 0.2 / zoom;
    const step: f32 = 3.0 * zoom;
    const fog_offset: f32 = thickness + 2.0 * zoom; // Offset into the fog side

    const is_horizontal = (edge_idx == 0 or edge_idx == 2);
    const total_len = cell_size;

    // Faded color for the fog side
    const faded_color = rl.Color.init(color.r, color.g, color.b, 80);

    // Get base position - offset into the neighbor (fog) side
    var base_x: f32 = cell_x;
    var base_y: f32 = cell_y;

    switch (edge_idx) {
        0 => base_y = cell_y - fog_offset, // Top edge - fog is above
        1 => base_x = cell_x + cell_size + fog_offset, // Right edge - fog is to right
        2 => base_y = cell_y + cell_size + fog_offset, // Bottom edge - fog is below
        3 => base_x = cell_x - fog_offset, // Left edge - fog is to left
        else => {},
    }

    // Draw wavy line in the fog
    var pos: f32 = 0;
    while (pos < total_len) {
        const wave_offset = wave_amplitude * @sin(pos * wave_frequency);

        if (is_horizontal) {
            const x = base_x + pos;
            const y = base_y + wave_offset;
            rl.drawCircle(toI32(x), toI32(y), wave_thickness, faded_color);
        } else {
            const x = base_x + wave_offset;
            const y = base_y + pos;
            rl.drawCircle(toI32(x), toI32(y), wave_thickness, faded_color);
        }

        pos += step;
    }
}

/// Get rectangle for a cell edge
fn getEdgeRect(cell_x: f32, cell_y: f32, cell_size: f32, edge_idx: usize, thickness: f32) struct { x: f32, y: f32, w: f32, h: f32 } {
    return switch (edge_idx) {
        0 => .{ .x = cell_x, .y = cell_y, .w = cell_size, .h = thickness }, // Top
        1 => .{ .x = cell_x + cell_size - thickness, .y = cell_y, .w = thickness, .h = cell_size }, // Right
        2 => .{ .x = cell_x, .y = cell_y + cell_size - thickness, .w = cell_size, .h = thickness }, // Bottom
        3 => .{ .x = cell_x, .y = cell_y, .w = thickness, .h = cell_size }, // Left
        else => .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    };
}

/// Draw a map-style flag marker with encounter type glyph
fn drawFlagMarker(x: f32, y: f32, encounter_type: EncounterType, zoom: f32, alpha: u8) void {
    const scale = zoom * 0.8;

    // Flag pole
    const pole_height: f32 = 24 * scale;
    const pole_width: f32 = 2 * scale;
    const pole_x = x;
    const pole_bottom_y = y + 8 * scale;
    const pole_top_y = pole_bottom_y - pole_height;

    // Draw pole (dark gray, with alpha)
    rl.drawRectangle(
        toI32(pole_x - pole_width / 2),
        toI32(pole_top_y),
        toI32(pole_width),
        toI32(pole_height),
        rl.Color.init(60, 60, 70, alpha),
    );

    // Flag banner (colored by encounter type, with alpha)
    const base_flag_color = getEncounterColor(encounter_type);
    const flag_color = rl.Color.init(base_flag_color.r, base_flag_color.g, base_flag_color.b, alpha);
    const flag_width: f32 = 16 * scale;
    const flag_height: f32 = 12 * scale;
    const flag_x = pole_x + pole_width / 2;
    const flag_y = pole_top_y;

    // Draw flag as a small banner shape (rectangle with notch)
    rl.drawRectangle(
        toI32(flag_x),
        toI32(flag_y),
        toI32(flag_width),
        toI32(flag_height),
        flag_color,
    );

    // Draw notch (triangle cut out of right side) - using dark background color
    rl.drawTriangle(
        rl.Vector2{ .x = flag_x + flag_width, .y = flag_y },
        rl.Vector2{ .x = flag_x + flag_width - 4 * scale, .y = flag_y + flag_height / 2 },
        rl.Vector2{ .x = flag_x + flag_width, .y = flag_y + flag_height },
        FOG_COLOR,
    );

    // Draw encounter glyph on flag
    const glyph = getEncounterGlyph(encounter_type);
    const glyph_size: i32 = @intFromFloat(10 * scale);
    if (glyph_size >= 6) {
        const glyph_width = rl.measureText(glyph, glyph_size);
        rl.drawText(
            glyph,
            toI32(flag_x + (flag_width - 4 * scale) / 2) - @divTrunc(glyph_width, 2),
            toI32(flag_y + flag_height / 2) - @divTrunc(glyph_size, 2),
            glyph_size,
            rl.Color.init(255, 255, 255, alpha),
        );
    }

    // Draw small base/pin at bottom
    const base_radius: f32 = 3 * scale;
    rl.drawCircle(toI32(pole_x), toI32(pole_bottom_y), base_radius, rl.Color.init(80, 80, 90, alpha));
}

/// Get encounter type glyph (single character for flag display)
fn getEncounterGlyph(encounter_type: EncounterType) [:0]const u8 {
    return switch (encounter_type) {
        .skirmish => "X", // Crossed swords vibe
        .boss_capture => "!", // Important/dangerous
        .intel => "?", // Unknown/mystery
        .strategic => "*", // Key location
        .recruitment => "+", // Add to party
    };
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
    // Show engage prompt for revealed blocks OR starting block in tutorial mode
    const is_tutorial_target = map.in_tutorial_mode and
        map.start_block_id != null and
        block_id == map.start_block_id.?;

    if (block.state == .revealed or is_tutorial_target) {
        if (block.encounter != null) {
            const prompt_text = if (is_tutorial_target) "[Enter] Defend Home" else "[Enter] Engage";
            rl.drawText(prompt_text, toI32(panel_x + padding), toI32(panel_y + panel_height - 25), 12, rl.Color.white);
        }
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
                // Can engage if:
                // 1. Block is revealed with an encounter (normal case)
                // 2. OR it's the starting block in tutorial mode (defend home tutorial)
                const is_tutorial_target = map.in_tutorial_mode and
                    map.start_block_id != null and
                    selected_id == map.start_block_id.?;
                const is_normal_target = block.state == .revealed and block.encounter != null;

                if ((is_normal_target or is_tutorial_target) and block.encounter != null) {
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
