//! Polyomino Map System - Infinite tessellating neighborhood blocks
//!
//! The campaign map is an infinite plane of tessellating polyomino shapes (like Tetris pieces
//! that perfectly tile with no gaps). Each polyomino is a "neighborhood block" containing
//! one encounter.
//!
//! Key concepts:
//! - Grid cells are grouped into polyominoes (3-6 cells each)
//! - Polyominoes tile perfectly with no gaps
//! - Map generates in chunks as player explores
//! - Camera/pan is constrained to conquered + adjacent territory
//! - Factions control contiguous regions of polyominoes
//!
//! Generation algorithm:
//! 1. Start with a grid of unit cells in a chunk
//! 2. Randomly "carve" polyominoes by flood-fill grouping adjacent cells
//! 3. Ensure all cells are assigned (perfect tiling)
//! 4. Calculate adjacency between polyominoes (shared edges)
//! 5. Assign faction control and encounter types

const std = @import("std");
const campaign = @import("campaign.zig");

const Faction = campaign.Faction;
const EncounterType = campaign.EncounterType;
const EncounterNode = campaign.EncounterNode;

// ============================================================================
// HELPER TYPES
// ============================================================================

/// Local coordinate within a chunk
pub const LocalCoord = struct {
    x: usize,
    y: usize,
};

/// Block location in chunk
pub const BlockLocation = struct {
    chunk_hash: u64,
    block_idx: usize,
};

/// Direction delta for neighbor iteration
const Delta = struct {
    dx: i32,
    dy: i32,
};

// ============================================================================
// CONSTANTS
// ============================================================================

/// Size of each chunk in grid cells
pub const CHUNK_SIZE: i32 = 16;

/// Minimum cells per polyomino block
pub const MIN_BLOCK_SIZE: usize = 2;

/// Maximum cells per polyomino block
pub const MAX_BLOCK_SIZE: usize = 6;

/// Target average block size (for generation tuning)
pub const TARGET_BLOCK_SIZE: usize = 4;

/// Size of each grid cell in world units (for rendering)
pub const CELL_SIZE: f32 = 60.0;

/// Maximum cells in a single block
pub const MAX_CELLS_PER_BLOCK: usize = 8;

/// Maximum adjacent blocks
pub const MAX_ADJACENT_BLOCKS: usize = 16;

/// Maximum blocks per chunk
pub const MAX_BLOCKS_PER_CHUNK: usize = 128;

// ============================================================================
// GRID COORDINATES
// ============================================================================

/// A coordinate in the infinite grid (cell-level)
pub const GridCoord = struct {
    x: i32,
    y: i32,

    pub fn init(x: i32, y: i32) GridCoord {
        return .{ .x = x, .y = y };
    }

    pub fn eql(self: GridCoord, other: GridCoord) bool {
        return self.x == other.x and self.y == other.y;
    }

    pub fn hash(self: GridCoord) u64 {
        // Combine x and y into a single hash
        const ux: u64 = @bitCast(@as(i64, self.x));
        const uy: u64 = @bitCast(@as(i64, self.y));
        return ux *% 31 +% uy;
    }

    /// Get the chunk this cell belongs to
    pub fn toChunkCoord(self: GridCoord) ChunkCoord {
        return ChunkCoord{
            .x = @divFloor(self.x, CHUNK_SIZE),
            .y = @divFloor(self.y, CHUNK_SIZE),
        };
    }

    /// Get position relative to chunk origin
    pub fn toLocalCoord(self: GridCoord) struct { x: u32, y: u32 } {
        const local_x = @mod(self.x, CHUNK_SIZE);
        const local_y = @mod(self.y, CHUNK_SIZE);
        return .{
            .x = @intCast(local_x),
            .y = @intCast(local_y),
        };
    }

    /// Get the 4 cardinal neighbors
    pub fn neighbors(self: GridCoord) [4]GridCoord {
        return .{
            GridCoord.init(self.x, self.y - 1), // North
            GridCoord.init(self.x + 1, self.y), // East
            GridCoord.init(self.x, self.y + 1), // South
            GridCoord.init(self.x - 1, self.y), // West
        };
    }

    /// Convert to world position (center of cell)
    pub fn toWorldPos(self: GridCoord) struct { x: f32, y: f32 } {
        return .{
            .x = @as(f32, @floatFromInt(self.x)) * CELL_SIZE + CELL_SIZE / 2,
            .y = @as(f32, @floatFromInt(self.y)) * CELL_SIZE + CELL_SIZE / 2,
        };
    }
};

/// A coordinate identifying a chunk
pub const ChunkCoord = struct {
    x: i32,
    y: i32,

    pub fn init(x: i32, y: i32) ChunkCoord {
        return .{ .x = x, .y = y };
    }

    pub fn eql(self: ChunkCoord, other: ChunkCoord) bool {
        return self.x == other.x and self.y == other.y;
    }

    pub fn hash(self: ChunkCoord) u64 {
        const ux: u64 = @bitCast(@as(i64, self.x));
        const uy: u64 = @bitCast(@as(i64, self.y));
        return ux *% 73 +% uy;
    }

    /// Get the origin cell of this chunk
    pub fn toGridOrigin(self: ChunkCoord) GridCoord {
        return GridCoord{
            .x = self.x * CHUNK_SIZE,
            .y = self.y * CHUNK_SIZE,
        };
    }

    /// Get all 8 neighboring chunks (cardinal + diagonal)
    pub fn getNeighbors(self: ChunkCoord) [8]ChunkCoord {
        return .{
            ChunkCoord.init(self.x, self.y - 1), // N
            ChunkCoord.init(self.x + 1, self.y - 1), // NE
            ChunkCoord.init(self.x + 1, self.y), // E
            ChunkCoord.init(self.x + 1, self.y + 1), // SE
            ChunkCoord.init(self.x, self.y + 1), // S
            ChunkCoord.init(self.x - 1, self.y + 1), // SW
            ChunkCoord.init(self.x - 1, self.y), // W
            ChunkCoord.init(self.x - 1, self.y - 1), // NW
        };
    }
};

// ============================================================================
// BLOCK STATE
// ============================================================================

/// Visibility/conquest state of a block
pub const BlockState = enum {
    /// Not yet visible to player (in fog)
    fogged,
    /// Visible but not conquered (adjacent to territory)
    revealed,
    /// Conquered by a faction
    conquered,
};

/// Visibility layer - how far from conquered territory
/// Layer 1 = adjacent to conquered (brightest revealed)
/// Layer 2 = 2 steps away (dimmer)
/// Layer 3 = 3 steps away (dimmest, fade lines only)
pub const VisibilityLayer = enum(u8) {
    conquered = 0, // Full brightness, owned
    layer_1 = 1, // Adjacent to conquered - bright
    layer_2 = 2, // 2 steps out - dim
    layer_3 = 3, // 3 steps out - very dim, fade lines
    fogged = 255, // Not visible

    pub fn getAlpha(self: VisibilityLayer) u8 {
        return switch (self) {
            .conquered => 255,
            .layer_1 => 200,
            .layer_2 => 120,
            .layer_3 => 60,
            .fogged => 0,
        };
    }

    pub fn getBorderAlpha(self: VisibilityLayer) u8 {
        return switch (self) {
            .conquered => 255,
            .layer_1 => 180,
            .layer_2 => 100,
            .layer_3 => 40,
            .fogged => 0,
        };
    }
};

// ============================================================================
// NEIGHBORHOOD BLOCK
// ============================================================================

/// A neighborhood block - one polyomino shape on the map
/// Each block is one "node" the player can interact with
pub const Block = struct {
    /// Unique identifier
    id: u32,

    /// Grid cells that make up this polyomino (fixed-size array)
    cells: [MAX_CELLS_PER_BLOCK]GridCoord = undefined,
    cell_count: usize = 0,

    /// Which faction controls this block (null = neutral/contested)
    faction: ?Faction = null,

    /// Current state (fogged/revealed/conquered)
    state: BlockState = .fogged,

    /// Visibility layer (distance from conquered territory)
    visibility_layer: VisibilityLayer = .fogged,

    /// The encounter at this block (null if conquered)
    encounter: ?EncounterNode = null,

    /// Display name for this neighborhood
    name: []const u8 = "",

    /// IDs of adjacent blocks (fixed-size array)
    adjacent_blocks: [MAX_ADJACENT_BLOCKS]u32 = undefined,
    adjacent_count: usize = 0,

    /// Bounding box for quick culling (in grid coords)
    bounds_min: GridCoord = GridCoord.init(std.math.maxInt(i32), std.math.maxInt(i32)),
    bounds_max: GridCoord = GridCoord.init(std.math.minInt(i32), std.math.minInt(i32)),

    pub fn init(id: u32) Block {
        return Block{ .id = id };
    }

    /// Add a cell to this block
    pub fn addCell(self: *Block, coord: GridCoord) void {
        if (self.cell_count >= MAX_CELLS_PER_BLOCK) return;
        self.cells[self.cell_count] = coord;
        self.cell_count += 1;
        // Update bounding box
        self.bounds_min.x = @min(self.bounds_min.x, coord.x);
        self.bounds_min.y = @min(self.bounds_min.y, coord.y);
        self.bounds_max.x = @max(self.bounds_max.x, coord.x);
        self.bounds_max.y = @max(self.bounds_max.y, coord.y);
    }

    /// Check if this block contains a specific cell
    pub fn containsCell(self: Block, coord: GridCoord) bool {
        for (self.cells[0..self.cell_count]) |cell| {
            if (cell.eql(coord)) return true;
        }
        return false;
    }

    /// Get the cells slice
    pub fn getCells(self: *const Block) []const GridCoord {
        return self.cells[0..self.cell_count];
    }

    /// Get the adjacent blocks slice
    pub fn getAdjacentBlocks(self: *const Block) []const u32 {
        return self.adjacent_blocks[0..self.adjacent_count];
    }

    /// Add an adjacent block ID
    pub fn addAdjacent(self: *Block, adj_id: u32) void {
        if (self.adjacent_count >= MAX_ADJACENT_BLOCKS) return;
        // Check not already present
        for (self.adjacent_blocks[0..self.adjacent_count]) |existing| {
            if (existing == adj_id) return;
        }
        self.adjacent_blocks[self.adjacent_count] = adj_id;
        self.adjacent_count += 1;
    }

    /// Get the centroid of this block (for label placement)
    pub fn getCentroid(self: Block) struct { x: f32, y: f32 } {
        if (self.cell_count == 0) return .{ .x = 0, .y = 0 };

        var sum_x: i64 = 0;
        var sum_y: i64 = 0;
        for (self.cells[0..self.cell_count]) |cell| {
            sum_x += cell.x;
            sum_y += cell.y;
        }
        const count: f32 = @floatFromInt(self.cell_count);
        const avg_x = @as(f32, @floatFromInt(sum_x)) / count;
        const avg_y = @as(f32, @floatFromInt(sum_y)) / count;

        return .{
            .x = avg_x * CELL_SIZE + CELL_SIZE / 2,
            .y = avg_y * CELL_SIZE + CELL_SIZE / 2,
        };
    }

    /// Get total area in cells
    pub fn getArea(self: Block) usize {
        return self.cell_count;
    }
};

// ============================================================================
// CHUNK
// ============================================================================

/// A chunk of the infinite map
/// Contains multiple polyomino blocks
pub const Chunk = struct {
    /// Chunk coordinate
    coord: ChunkCoord,

    /// Blocks in this chunk (fixed-size array)
    blocks: [MAX_BLOCKS_PER_CHUNK]Block = undefined,
    block_count: usize = 0,

    /// Grid mapping cell -> block index for fast lookup
    /// Index into blocks array, 255 = unassigned
    cell_to_block: [CHUNK_SIZE][CHUNK_SIZE]u8 = [_][CHUNK_SIZE]u8{[_]u8{255} ** CHUNK_SIZE} ** CHUNK_SIZE,

    /// Has this chunk been fully generated?
    generated: bool = false,

    pub fn init(coord: ChunkCoord) Chunk {
        return Chunk{ .coord = coord };
    }

    /// Get block index at a cell coordinate (if it exists in this chunk)
    pub fn getBlockIndexAt(self: *const Chunk, coord: GridCoord) ?usize {
        const local = coord.toLocalCoord();
        if (local.x >= CHUNK_SIZE or local.y >= CHUNK_SIZE) return null;
        const idx = self.cell_to_block[local.y][local.x];
        if (idx == 255) return null;
        return idx;
    }

    /// Get block at a cell coordinate
    pub fn getBlockAt(self: *Chunk, coord: GridCoord) ?*Block {
        const idx = self.getBlockIndexAt(coord) orelse return null;
        if (idx >= self.block_count) return null;
        return &self.blocks[idx];
    }

    /// Add a block to this chunk
    pub fn addBlock(self: *Chunk, block: Block) ?usize {
        if (self.block_count >= MAX_BLOCKS_PER_CHUNK) return null;
        const idx = self.block_count;
        self.blocks[idx] = block;
        self.block_count += 1;
        return idx;
    }

    /// Set cell to block mapping
    pub fn setCellBlock(self: *Chunk, coord: GridCoord, block_idx: usize) void {
        const local = coord.toLocalCoord();
        if (local.x >= CHUNK_SIZE or local.y >= CHUNK_SIZE) return;
        if (block_idx >= 255) return;
        self.cell_to_block[local.y][local.x] = @intCast(block_idx);
    }
};

// ============================================================================
// POLYOMINO MAP
// ============================================================================

/// The infinite tessellating map
pub const PolyominoMap = struct {
    allocator: std.mem.Allocator,

    /// All chunks (generated on demand)
    chunks: std.AutoHashMap(u64, *Chunk),

    /// Global block ID -> (chunk_hash, block_index) mapping
    block_locations: std.AutoHashMap(u32, BlockLocation),

    /// Next block ID to assign
    next_block_id: u32 = 1, // 0 reserved for null

    /// Seed for procedural generation
    seed: u64,

    /// Player's starting block ID
    start_block_id: ?u32 = null,

    /// Set of block IDs the player has conquered
    conquered_blocks: std.AutoHashMap(u32, void),

    /// Set of block IDs that are revealed (adjacent to conquered) - LEGACY, use visibility layers
    revealed_blocks: std.AutoHashMap(u32, void),

    /// Blocks at each visibility layer (for efficient rendering)
    layer_1_blocks: std.AutoHashMap(u32, void),
    layer_2_blocks: std.AutoHashMap(u32, void),
    layer_3_blocks: std.AutoHashMap(u32, void),

    /// Current round/turn (affects loss penalty scaling)
    current_round: u32 = 0,

    /// Player's faction
    player_faction: Faction = .blue,

    /// Tutorial mode: starting block looks conquered but is the engagement target
    /// This is the "defend your home" tutorial encounter at game start
    in_tutorial_mode: bool = false,

    /// Camera bounds (in world coordinates) - constrained to territory
    camera_bounds: struct {
        min_x: f32 = -CELL_SIZE * 4,
        min_y: f32 = -CELL_SIZE * 4,
        max_x: f32 = CELL_SIZE * 4,
        max_y: f32 = CELL_SIZE * 4,
    } = .{},

    pub fn init(allocator: std.mem.Allocator, seed: u64) PolyominoMap {
        return .{
            .allocator = allocator,
            .chunks = std.AutoHashMap(u64, *Chunk).init(allocator),
            .block_locations = std.AutoHashMap(u32, BlockLocation).init(allocator),
            .seed = seed,
            .conquered_blocks = std.AutoHashMap(u32, void).init(allocator),
            .revealed_blocks = std.AutoHashMap(u32, void).init(allocator),
            .layer_1_blocks = std.AutoHashMap(u32, void).init(allocator),
            .layer_2_blocks = std.AutoHashMap(u32, void).init(allocator),
            .layer_3_blocks = std.AutoHashMap(u32, void).init(allocator),
        };
    }

    pub fn deinit(self: *PolyominoMap) void {
        var chunk_iter = self.chunks.valueIterator();
        while (chunk_iter.next()) |chunk_ptr| {
            self.allocator.destroy(chunk_ptr.*);
        }
        self.chunks.deinit();
        self.block_locations.deinit();
        self.conquered_blocks.deinit();
        self.revealed_blocks.deinit();
        self.layer_1_blocks.deinit();
        self.layer_2_blocks.deinit();
        self.layer_3_blocks.deinit();
    }

    /// Generate the starting area - player's first encounter is their home block
    /// Unlike later gameplay, the starting block is revealed but NOT conquered yet
    /// First encounter is always an easy intel mission (tutorial + narrative hook)
    pub fn generateStartingArea(self: *PolyominoMap, player_faction: Faction) !void {
        self.player_faction = player_faction;

        // Generate the center chunk and its neighbors for initial map
        const center = ChunkCoord.init(0, 0);
        try self.ensureChunkGenerated(center);

        // Generate neighboring chunks for a fuller starting map
        for (center.getNeighbors()) |neighbor| {
            try self.ensureChunkGenerated(neighbor);
        }

        // Compute adjacencies across all chunks
        var all_chunks_iter = self.chunks.valueIterator();
        while (all_chunks_iter.next()) |chunk_ptr| {
            self.computeChunkAdjacencies(chunk_ptr.*);
        }

        // Find a good starting block:
        // - Should be a 5-cell polyomino (or close to it)
        // - Should have many adjacent blocks (for faction diversity)
        const start_block = self.findBestStartingBlock() orelse blk: {
            // Fallback to first block in center chunk
            if (self.getChunk(center)) |center_chunk| {
                if (center_chunk.block_count > 0) {
                    break :blk &center_chunk.blocks[0];
                }
            }
            return; // No blocks at all - shouldn't happen
        };

        self.start_block_id = start_block.id;

        // Tutorial mode: starting block LOOKS conquered but IS the engagement target
        // Player "owns" this territory visually, but must defend it in the tutorial fight
        self.in_tutorial_mode = true;

        // Mark starting block as conquered for rendering purposes
        // (it will look like owned territory with solid borders against enemies)
        start_block.state = .conquered;
        start_block.visibility_layer = .conquered;
        try self.conquered_blocks.put(start_block.id, {});

        // But it still has an encounter - the tutorial "defend your home" mission
        start_block.encounter = EncounterNode{
            .encounter_type = .intel,
            .name = "Last Seen Here",
            .challenge_rating = 1,
            .expires_in_turns = null,
            .controlling_faction = player_faction,
            .x = 0,
            .y = 0,
            .id = 0,
            .skill_capture_tier = .basic,
            .offers_quest_progress = true,
            .offers_recruitment = false,
            .faction_influence = 1,
        };
        start_block.faction = player_faction;
        start_block.name = "Home Base";

        // Assign contiguous faction territories, ensuring at least 3 factions border the start
        try self.assignContiguousFactions(player_faction);

        // Verify we have at least 3 adjacent factions, regenerate if not
        var attempts: u32 = 0;
        while (attempts < 10) {
            const adjacent_faction_count = self.countAdjacentFactions(start_block.id);
            if (adjacent_faction_count >= 3) break;

            // Re-seed factions with different seed
            attempts += 1;
            self.seed +%= attempts * 12345;

            // Clear all faction assignments except player's start block
            var chunks_iter = self.chunks.valueIterator();
            while (chunks_iter.next()) |chunk_ptr| {
                for (0..chunk_ptr.*.block_count) |i| {
                    const block = &chunk_ptr.*.blocks[i];
                    if (block.id != start_block.id) {
                        block.faction = null;
                    }
                }
            }

            try self.assignContiguousFactions(player_faction);
        }

        // Update camera to show starting area
        self.updateCameraBounds();

        // Compute visibility layers to reveal surrounding territory
        try self.recomputeVisibilityLayers();
    }

    /// Find the best starting block: ideally 5 cells with many neighbors
    fn findBestStartingBlock(self: *PolyominoMap) ?*Block {
        var best_block: ?*Block = null;
        var best_score: i32 = -1000;

        const center = ChunkCoord.init(0, 0);

        // Check center chunk and immediate neighbors
        const chunks_to_check = [_]ChunkCoord{
            center,
            ChunkCoord.init(0, -1),
            ChunkCoord.init(1, 0),
            ChunkCoord.init(0, 1),
            ChunkCoord.init(-1, 0),
        };

        for (chunks_to_check) |chunk_coord| {
            if (self.getChunk(chunk_coord)) |chunk| {
                for (0..chunk.block_count) |i| {
                    const block = &chunk.blocks[i];

                    // Score based on:
                    // - Prefer 5 cells (ideal), penalize deviation
                    // - More adjacent blocks = better (more faction diversity potential)
                    const size_score: i32 = -@as(i32, @intCast(@abs(@as(i32, @intCast(block.cell_count)) - 5))) * 10;
                    const neighbor_score: i32 = @intCast(block.adjacent_count * 5);

                    // Prefer blocks closer to center (0,0)
                    const centroid = block.getCentroid();
                    const dist_from_center = @abs(centroid.x) + @abs(centroid.y);
                    const center_score: i32 = -@as(i32, @intFromFloat(dist_from_center / 100.0));

                    const total_score = size_score + neighbor_score + center_score;

                    if (total_score > best_score) {
                        best_score = total_score;
                        best_block = block;
                    }
                }
            }
        }

        return best_block;
    }

    /// Count how many distinct factions are adjacent to a block
    fn countAdjacentFactions(self: *PolyominoMap, block_id: u32) usize {
        const block = self.getBlock(block_id) orelse return 0;

        var factions_seen: [16]?Faction = [_]?Faction{null} ** 16;
        var faction_count: usize = 0;

        for (block.getAdjacentBlocks()) |adj_id| {
            if (self.getBlock(adj_id)) |adj_block| {
                if (adj_block.faction) |faction| {
                    // Skip player's faction
                    if (faction == self.player_faction) continue;

                    // Check if we've already seen this faction
                    var seen = false;
                    for (factions_seen[0..faction_count]) |f| {
                        if (f == faction) {
                            seen = true;
                            break;
                        }
                    }

                    if (!seen and faction_count < 16) {
                        factions_seen[faction_count] = faction;
                        faction_count += 1;
                    }
                }
            }
        }

        return faction_count;
    }

    /// Ensure a chunk is generated
    pub fn ensureChunkGenerated(self: *PolyominoMap, coord: ChunkCoord) !void {
        const hash = coord.hash();
        if (self.chunks.contains(hash)) return;

        // Create and generate the chunk
        const chunk = try self.allocator.create(Chunk);
        chunk.* = Chunk.init(coord);

        try self.generateChunk(chunk);
        try self.chunks.put(hash, chunk);
    }

    /// Get a chunk by coordinate (if it exists)
    pub fn getChunk(self: *PolyominoMap, coord: ChunkCoord) ?*Chunk {
        return self.chunks.get(coord.hash());
    }

    /// Get a block by ID
    pub fn getBlock(self: *PolyominoMap, id: u32) ?*Block {
        const loc = self.block_locations.get(id) orelse return null;
        const chunk = self.chunks.get(loc.chunk_hash) orelse return null;
        if (loc.block_idx >= chunk.block_count) return null;
        return &chunk.blocks[loc.block_idx];
    }

    /// Get block at a world position
    pub fn getBlockAtWorld(self: *PolyominoMap, world_x: f32, world_y: f32) ?*Block {
        const grid_x: i32 = @intFromFloat(@floor(world_x / CELL_SIZE));
        const grid_y: i32 = @intFromFloat(@floor(world_y / CELL_SIZE));
        const coord = GridCoord.init(grid_x, grid_y);

        const chunk_coord = coord.toChunkCoord();
        const chunk = self.getChunk(chunk_coord) orelse return null;

        return chunk.getBlockAt(coord);
    }

    /// Conquer a block for a faction
    pub fn conquerBlock(self: *PolyominoMap, block_id: u32, faction: Faction) !void {
        const block = self.getBlock(block_id) orelse return;

        block.faction = faction;
        block.state = .conquered;
        block.encounter = null;

        // Track player faction
        self.player_faction = faction;

        // End tutorial mode when starting block is fully conquered
        if (self.in_tutorial_mode and self.start_block_id != null and block_id == self.start_block_id.?) {
            self.in_tutorial_mode = false;
        }

        try self.conquered_blocks.put(block_id, {});
        _ = self.revealed_blocks.remove(block_id);
        _ = self.layer_1_blocks.remove(block_id);
        _ = self.layer_2_blocks.remove(block_id);
        _ = self.layer_3_blocks.remove(block_id);
        block.visibility_layer = .conquered;

        // Recompute all visibility layers (this will reveal adjacent blocks properly)
        try self.recomputeVisibilityLayers();

        // Update camera bounds
        self.updateCameraBounds();
    }

    /// Lose territory when player is defeated
    /// Returns number of blocks lost, or null if game over (lost starting block)
    pub fn loseTerritory(self: *PolyominoMap, blocks_to_lose: u32) !?u32 {
        var lost: u32 = 0;
        var blocks_to_process = blocks_to_lose;

        // Can't lose the starting block - that's game over
        const start_id = self.start_block_id orelse return 0;

        while (blocks_to_process > 0) {
            // Find a frontier block (conquered block adjacent to non-conquered)
            var frontier_block_id: ?u32 = null;

            var conquered_iter = self.conquered_blocks.keyIterator();
            while (conquered_iter.next()) |block_id_ptr| {
                const block_id = block_id_ptr.*;

                // Don't lose the starting block
                if (block_id == start_id) continue;

                if (self.getBlock(block_id)) |block| {
                    // Check if this block is on the frontier (has unconquered neighbors)
                    for (block.getAdjacentBlocks()) |adj_id| {
                        if (!self.conquered_blocks.contains(adj_id)) {
                            frontier_block_id = block_id;
                            break;
                        }
                    }
                }

                if (frontier_block_id != null) break;
            }

            if (frontier_block_id) |block_id| {
                // Lose this block
                try self.unconquerBlock(block_id);
                lost += 1;
                blocks_to_process -= 1;
            } else {
                // No frontier blocks left (only starting block remains)
                if (self.conquered_blocks.count() <= 1) {
                    // Game over - would lose starting block
                    return null;
                }
                break;
            }
        }

        self.updateCameraBounds();

        // Recompute visibility layers after losing territory
        try self.recomputeVisibilityLayers();

        return lost;
    }

    /// Un-conquer a block (enemy takes it back)
    fn unconquerBlock(self: *PolyominoMap, block_id: u32) !void {
        const block = self.getBlock(block_id) orelse return;

        // Remove from conquered, add back to revealed
        _ = self.conquered_blocks.remove(block_id);

        // Set state back to revealed and assign enemy faction
        block.state = .revealed;
        block.faction = self.getRandomEnemyFaction(block_id);

        // Regenerate an encounter for this block
        var prng = std.Random.DefaultPrng.init(self.seed +% block_id +% self.current_round);
        const rng = prng.random();
        block.encounter = campaign.EncounterNode.random(rng, @intCast(block_id));
        if (block.encounter) |*enc| {
            if (block.faction) |f| {
                enc.controlling_faction = f;
            }
        }

        try self.revealed_blocks.put(block_id, {});

        // Check if any conquered blocks are now disconnected from start
        // (For now, we don't handle this - could be future feature)
    }

    /// Get a random enemy faction (not player's faction)
    fn getRandomEnemyFaction(self: *PolyominoMap, seed_val: u32) Faction {
        var prng = std.Random.DefaultPrng.init(self.seed +% seed_val);
        const rng = prng.random();

        const enemy_factions = [_]Faction{ .red, .yellow, .green, .purple, .orange };
        const filtered = blk: {
            var count: usize = 0;
            var result: [5]Faction = undefined;
            for (enemy_factions) |f| {
                if (f != self.player_faction) {
                    result[count] = f;
                    count += 1;
                }
            }
            break :blk result[0..count];
        };

        if (filtered.len == 0) return .red;
        return filtered[rng.intRangeAtMost(usize, 0, filtered.len - 1)];
    }

    /// Calculate how many blocks to lose based on current round
    /// Scales up: round 1-3 = 1, round 4-6 = 2, round 7-9 = 3, etc.
    pub fn getLossPenalty(self: *PolyominoMap) u32 {
        return 1 + (self.current_round / 3);
    }

    /// Check if player has any territory left
    pub fn hasTerritory(self: *PolyominoMap) bool {
        return self.conquered_blocks.count() > 0;
    }

    /// Check if player only has starting block left
    pub fn isLastStand(self: *PolyominoMap) bool {
        return self.conquered_blocks.count() == 1;
    }

    /// Expand the map by generating chunks adjacent to current territory
    pub fn expandFrontier(self: *PolyominoMap) !void {
        // Collect unique chunk coords from conquered territory
        var chunks_set = std.AutoHashMap(u64, ChunkCoord).init(self.allocator);
        defer chunks_set.deinit();

        var conquered_iter = self.conquered_blocks.keyIterator();
        while (conquered_iter.next()) |block_id_ptr| {
            if (self.getBlock(block_id_ptr.*)) |block| {
                for (block.getCells()) |cell| {
                    const chunk_coord = cell.toChunkCoord();
                    try chunks_set.put(chunk_coord.hash(), chunk_coord);
                }
            }
        }

        // Generate neighbors for each chunk in territory
        var chunk_iter = chunks_set.valueIterator();
        while (chunk_iter.next()) |chunk_coord| {
            for (chunk_coord.getNeighbors()) |neighbor| {
                try self.ensureChunkGenerated(neighbor);
            }
        }

        // Recompute adjacencies for all chunks
        var all_chunks_iter = self.chunks.valueIterator();
        while (all_chunks_iter.next()) |chunk_ptr| {
            self.computeChunkAdjacencies(chunk_ptr.*);
        }

        // Re-reveal adjacent blocks based on new adjacencies
        conquered_iter = self.conquered_blocks.keyIterator();
        while (conquered_iter.next()) |block_id_ptr| {
            if (self.getBlock(block_id_ptr.*)) |block| {
                for (block.getAdjacentBlocks()) |adj_id| {
                    if (!self.conquered_blocks.contains(adj_id) and !self.revealed_blocks.contains(adj_id)) {
                        try self.revealBlock(adj_id);
                    }
                }
            }
        }

        self.updateCameraBounds();

        // Recompute visibility layers for all blocks
        try self.recomputeVisibilityLayers();
    }

    /// Reveal a block (make it visible but not conquered)
    pub fn revealBlock(self: *PolyominoMap, block_id: u32) !void {
        if (self.conquered_blocks.contains(block_id)) return;

        const block = self.getBlock(block_id) orelse return;
        if (block.state == .fogged) {
            block.state = .revealed;
            try self.revealed_blocks.put(block_id, {});
        }
    }

    /// Check if a block is visible (conquered or revealed)
    pub fn isBlockVisible(self: *PolyominoMap, block_id: u32) bool {
        return self.conquered_blocks.contains(block_id) or
            self.revealed_blocks.contains(block_id) or
            self.layer_1_blocks.contains(block_id) or
            self.layer_2_blocks.contains(block_id) or
            self.layer_3_blocks.contains(block_id);
    }

    /// Recompute visibility layers for all blocks based on distance from conquered territory
    /// Layer 1: Adjacent to conquered (or the starting block if nothing conquered yet)
    /// Layer 2: Adjacent to layer 1
    /// Layer 3: Adjacent to layer 2
    pub fn recomputeVisibilityLayers(self: *PolyominoMap) !void {
        // Clear existing layers
        self.layer_1_blocks.clearRetainingCapacity();
        self.layer_2_blocks.clearRetainingCapacity();
        self.layer_3_blocks.clearRetainingCapacity();

        // Also clear revealed_blocks and rebuild it from layers
        self.revealed_blocks.clearRetainingCapacity();

        // Reset all non-conquered blocks to fogged first
        var all_chunks_iter = self.chunks.valueIterator();
        while (all_chunks_iter.next()) |chunk_ptr| {
            for (0..chunk_ptr.*.block_count) |i| {
                const block = &chunk_ptr.*.blocks[i];
                if (block.state != .conquered) {
                    block.state = .fogged;
                    block.visibility_layer = .fogged;
                }
            }
        }

        // Set conquered blocks
        var conquered_iter = self.conquered_blocks.keyIterator();
        while (conquered_iter.next()) |block_id_ptr| {
            if (self.getBlock(block_id_ptr.*)) |block| {
                block.visibility_layer = .conquered;
            }
        }

        // Special case: if no conquered blocks yet, the starting block IS layer 1
        // This handles the initial game state where player hasn't won their first fight
        if (self.conquered_blocks.count() == 0) {
            if (self.start_block_id) |start_id| {
                if (self.getBlock(start_id)) |start_block| {
                    try self.layer_1_blocks.put(start_id, {});
                    try self.revealed_blocks.put(start_id, {});
                    start_block.state = .revealed;
                    start_block.visibility_layer = .layer_1;
                }
            }
        } else {
            // Layer 1: All blocks adjacent to conquered
            conquered_iter = self.conquered_blocks.keyIterator();
            while (conquered_iter.next()) |block_id_ptr| {
                if (self.getBlock(block_id_ptr.*)) |block| {
                    for (block.getAdjacentBlocks()) |adj_id| {
                        if (!self.conquered_blocks.contains(adj_id) and !self.layer_1_blocks.contains(adj_id)) {
                            try self.layer_1_blocks.put(adj_id, {});
                            try self.revealed_blocks.put(adj_id, {}); // Also track in revealed for compatibility
                            if (self.getBlock(adj_id)) |adj_block| {
                                adj_block.state = .revealed;
                                adj_block.visibility_layer = .layer_1;
                            }
                        }
                    }
                }
            }
        }

        // Generate chunks for layer 2 and 3 (need to ensure they exist)
        try self.ensureLayerChunksGenerated();

        // Layer 2: All blocks adjacent to layer 1 (that aren't conquered or layer 1)
        var layer1_iter = self.layer_1_blocks.keyIterator();
        while (layer1_iter.next()) |block_id_ptr| {
            if (self.getBlock(block_id_ptr.*)) |block| {
                for (block.getAdjacentBlocks()) |adj_id| {
                    if (!self.conquered_blocks.contains(adj_id) and
                        !self.layer_1_blocks.contains(adj_id) and
                        !self.layer_2_blocks.contains(adj_id))
                    {
                        try self.layer_2_blocks.put(adj_id, {});
                        if (self.getBlock(adj_id)) |adj_block| {
                            adj_block.state = .revealed;
                            adj_block.visibility_layer = .layer_2;
                        }
                    }
                }
            }
        }

        // Layer 3: All blocks adjacent to layer 2 (that aren't in any other layer)
        var layer2_iter = self.layer_2_blocks.keyIterator();
        while (layer2_iter.next()) |block_id_ptr| {
            if (self.getBlock(block_id_ptr.*)) |block| {
                for (block.getAdjacentBlocks()) |adj_id| {
                    if (!self.conquered_blocks.contains(adj_id) and
                        !self.layer_1_blocks.contains(adj_id) and
                        !self.layer_2_blocks.contains(adj_id) and
                        !self.layer_3_blocks.contains(adj_id))
                    {
                        try self.layer_3_blocks.put(adj_id, {});
                        if (self.getBlock(adj_id)) |adj_block| {
                            adj_block.state = .revealed;
                            adj_block.visibility_layer = .layer_3;
                        }
                    }
                }
            }
        }
    }

    /// Ensure chunks exist for blocks up to layer 3
    fn ensureLayerChunksGenerated(self: *PolyominoMap) !void {
        // Collect chunks we need to generate from layer 1 blocks
        var chunks_to_gen = std.AutoHashMap(u64, ChunkCoord).init(self.allocator);
        defer chunks_to_gen.deinit();

        // Get chunks from layer 1 blocks and their neighbors
        var layer1_iter = self.layer_1_blocks.keyIterator();
        while (layer1_iter.next()) |block_id_ptr| {
            if (self.getBlock(block_id_ptr.*)) |block| {
                for (block.getCells()) |cell| {
                    const chunk_coord = cell.toChunkCoord();
                    // Add neighboring chunks
                    for (chunk_coord.getNeighbors()) |neighbor| {
                        if (!self.chunks.contains(neighbor.hash())) {
                            try chunks_to_gen.put(neighbor.hash(), neighbor);
                        }
                    }
                }
            }
        }

        // Generate the chunks
        var gen_iter = chunks_to_gen.valueIterator();
        while (gen_iter.next()) |chunk_coord| {
            try self.ensureChunkGenerated(chunk_coord.*);
        }

        // Recompute adjacencies for all chunks
        var all_chunks_iter = self.chunks.valueIterator();
        while (all_chunks_iter.next()) |chunk_ptr| {
            self.computeChunkAdjacencies(chunk_ptr.*);
        }
    }

    /// Update camera bounds based on conquered territory
    fn updateCameraBounds(self: *PolyominoMap) void {
        var min_x: f32 = std.math.floatMax(f32);
        var min_y: f32 = std.math.floatMax(f32);
        var max_x: f32 = std.math.floatMin(f32);
        var max_y: f32 = std.math.floatMin(f32);

        // Include all conquered blocks
        var conquered_iter = self.conquered_blocks.keyIterator();
        while (conquered_iter.next()) |block_id_ptr| {
            if (self.getBlock(block_id_ptr.*)) |block| {
                for (block.getCells()) |cell| {
                    const world_pos = cell.toWorldPos();
                    min_x = @min(min_x, world_pos.x - CELL_SIZE);
                    min_y = @min(min_y, world_pos.y - CELL_SIZE);
                    max_x = @max(max_x, world_pos.x + CELL_SIZE);
                    max_y = @max(max_y, world_pos.y + CELL_SIZE);
                }
            }
        }

        // Include all revealed blocks
        var revealed_iter = self.revealed_blocks.keyIterator();
        while (revealed_iter.next()) |block_id_ptr| {
            if (self.getBlock(block_id_ptr.*)) |block| {
                for (block.getCells()) |cell| {
                    const world_pos = cell.toWorldPos();
                    min_x = @min(min_x, world_pos.x - CELL_SIZE);
                    min_y = @min(min_y, world_pos.y - CELL_SIZE);
                    max_x = @max(max_x, world_pos.x + CELL_SIZE);
                    max_y = @max(max_y, world_pos.y + CELL_SIZE);
                }
            }
        }

        // Add some padding
        const padding = CELL_SIZE * 2;
        if (min_x < std.math.floatMax(f32)) {
            self.camera_bounds = .{
                .min_x = min_x - padding,
                .min_y = min_y - padding,
                .max_x = max_x + padding,
                .max_y = max_y + padding,
            };
        }
    }

    /// Generate polyominoes for a chunk
    fn generateChunk(self: *PolyominoMap, chunk: *Chunk) !void {
        // Create RNG seeded by chunk coordinate
        const chunk_seed = self.seed +%
            @as(u64, @bitCast(@as(i64, chunk.coord.x) *% 1000000)) +%
            @as(u64, @bitCast(@as(i64, chunk.coord.y)));
        var prng = std.Random.DefaultPrng.init(chunk_seed);
        const rng = prng.random();

        // Track which cells are unassigned (using a simple grid)
        var unassigned: [CHUNK_SIZE][CHUNK_SIZE]bool = [_][CHUNK_SIZE]bool{[_]bool{true} ** CHUNK_SIZE} ** CHUNK_SIZE;
        var unassigned_count: usize = @intCast(CHUNK_SIZE * CHUNK_SIZE);

        const origin = chunk.coord.toGridOrigin();

        // Carve polyominoes until all cells are assigned
        while (unassigned_count > 0) {
            // Pick a random starting cell
            var start_local: ?LocalCoord = null;
            const skip = rng.intRangeAtMost(usize, 0, unassigned_count - 1);
            var count: usize = 0;
            outer: for (0..CHUNK_SIZE) |y| {
                for (0..CHUNK_SIZE) |x| {
                    if (unassigned[y][x]) {
                        if (count == skip) {
                            start_local = LocalCoord{ .x = x, .y = y };
                            break :outer;
                        }
                        count += 1;
                    }
                }
            }

            if (start_local) |start| {
                // Determine target size for this polyomino
                const target_size = if (unassigned_count <= MAX_BLOCK_SIZE)
                    unassigned_count
                else
                    rng.intRangeAtMost(usize, MIN_BLOCK_SIZE, @min(MAX_BLOCK_SIZE, unassigned_count));

                // Create new block
                var block = Block.init(self.next_block_id);
                self.next_block_id += 1;

                // Grow polyomino from start cell
                self.growPolyomino(&block, start, target_size, &unassigned, &unassigned_count, origin, rng);

                // Register block in chunk
                const block_idx = chunk.addBlock(block) orelse continue;

                // Map cells to block
                for (chunk.blocks[block_idx].getCells()) |cell| {
                    chunk.setCellBlock(cell, block_idx);
                }

                // Register in global lookup
                try self.block_locations.put(chunk.blocks[block_idx].id, BlockLocation{
                    .chunk_hash = chunk.coord.hash(),
                    .block_idx = block_idx,
                });

                // Assign random encounter and faction
                self.assignBlockProperties(&chunk.blocks[block_idx], rng);
            }
        }

        chunk.generated = true;

        // Compute adjacencies within this chunk
        self.computeChunkAdjacencies(chunk);
    }

    /// Grow a polyomino from a starting cell using flood fill
    fn growPolyomino(
        self: *PolyominoMap,
        block: *Block,
        start: LocalCoord,
        target_size: usize,
        unassigned: *[CHUNK_SIZE][CHUNK_SIZE]bool,
        unassigned_count: *usize,
        origin: GridCoord,
        rng: std.Random,
    ) void {
        _ = self;

        // Add starting cell
        const start_coord = GridCoord.init(
            origin.x + @as(i32, @intCast(start.x)),
            origin.y + @as(i32, @intCast(start.y)),
        );
        block.addCell(start_coord);
        unassigned[start.y][start.x] = false;
        unassigned_count.* -= 1;

        // Frontier of local coords we can expand to
        var frontier: [64]LocalCoord = undefined;
        var frontier_count: usize = 0;

        // Add neighbors of start to frontier
        const deltas = [_]Delta{
            Delta{ .dx = 0, .dy = -1 },
            Delta{ .dx = 1, .dy = 0 },
            Delta{ .dx = 0, .dy = 1 },
            Delta{ .dx = -1, .dy = 0 },
        };

        for (deltas) |d| {
            const nx: i32 = @as(i32, @intCast(start.x)) + d.dx;
            const ny: i32 = @as(i32, @intCast(start.y)) + d.dy;
            if (nx >= 0 and nx < CHUNK_SIZE and ny >= 0 and ny < CHUNK_SIZE) {
                const ux: usize = @intCast(nx);
                const uy: usize = @intCast(ny);
                if (unassigned[uy][ux] and frontier_count < 64) {
                    frontier[frontier_count] = LocalCoord{ .x = ux, .y = uy };
                    frontier_count += 1;
                }
            }
        }

        // Grow until we reach target size or can't expand
        while (block.cell_count < target_size and frontier_count > 0) {
            // Pick a random frontier cell
            const idx = rng.intRangeAtMost(usize, 0, frontier_count - 1);
            const next = frontier[idx];

            // Remove from frontier by swapping with last
            frontier[idx] = frontier[frontier_count - 1];
            frontier_count -= 1;

            // Check if still unassigned
            if (!unassigned[next.y][next.x]) continue;

            // Add to block
            const next_coord = GridCoord.init(
                origin.x + @as(i32, @intCast(next.x)),
                origin.y + @as(i32, @intCast(next.y)),
            );
            block.addCell(next_coord);
            unassigned[next.y][next.x] = false;
            unassigned_count.* -= 1;

            // Add new neighbors to frontier
            for (deltas) |d| {
                const nx: i32 = @as(i32, @intCast(next.x)) + d.dx;
                const ny: i32 = @as(i32, @intCast(next.y)) + d.dy;
                if (nx >= 0 and nx < CHUNK_SIZE and ny >= 0 and ny < CHUNK_SIZE) {
                    const ux: usize = @intCast(nx);
                    const uy: usize = @intCast(ny);
                    if (unassigned[uy][ux]) {
                        // Check not already in frontier
                        var in_frontier = false;
                        for (frontier[0..frontier_count]) |f| {
                            if (f.x == ux and f.y == uy) {
                                in_frontier = true;
                                break;
                            }
                        }
                        if (!in_frontier and frontier_count < 64) {
                            frontier[frontier_count] = LocalCoord{ .x = ux, .y = uy };
                            frontier_count += 1;
                        }
                    }
                }
            }
        }
    }

    /// Assign faction, encounter type, and name to a block
    /// NOTE: Faction is assigned later via assignContiguousFactions for better territories
    fn assignBlockProperties(self: *PolyominoMap, block: *Block, rng: std.Random) void {
        _ = self;

        // Faction assigned later via assignContiguousFactions()
        block.faction = null;

        // Generate encounter
        block.encounter = EncounterNode.random(rng, @intCast(block.id));

        // Generate name
        block.name = generateNeighborhoodName(rng);
    }

    /// Assign factions to blocks using flood-fill to create contiguous territories
    /// Called after chunks are generated to ensure proper adjacency information
    pub fn assignContiguousFactions(self: *PolyominoMap, player_faction: Faction) !void {
        // Collect all blocks that need faction assignment
        var unassigned = std.AutoHashMap(u32, void).init(self.allocator);
        defer unassigned.deinit();

        var all_chunks_iter = self.chunks.valueIterator();
        while (all_chunks_iter.next()) |chunk_ptr| {
            for (0..chunk_ptr.*.block_count) |i| {
                const block = &chunk_ptr.*.blocks[i];
                // Skip the starting block (player's territory)
                if (self.start_block_id != null and block.id == self.start_block_id.?) {
                    block.faction = player_faction;
                    continue;
                }
                // Mark as needing assignment
                if (block.faction == null) {
                    try unassigned.put(block.id, {});
                }
            }
        }

        // Create seed points for each non-player faction
        const enemy_factions = [_]Faction{ .red, .yellow, .green, .purple, .orange };
        var faction_seeds = std.AutoHashMap(u32, Faction).init(self.allocator);
        defer faction_seeds.deinit();

        // Pick seed blocks for each faction (spread them out)
        var seed_rng_state = std.Random.DefaultPrng.init(self.seed +% 999);
        const seed_rng = seed_rng_state.random();

        // Get list of unassigned block IDs
        var unassigned_list = std.ArrayListUnmanaged(u32){};
        defer unassigned_list.deinit(self.allocator);

        var unassigned_iter = unassigned.keyIterator();
        while (unassigned_iter.next()) |id_ptr| {
            try unassigned_list.append(self.allocator, id_ptr.*);
        }

        // Shuffle and pick seeds
        seed_rng.shuffle(u32, unassigned_list.items);

        // Assign seed blocks (one per faction, plus some extras for larger territories)
        const seeds_per_faction = @max(1, unassigned_list.items.len / (enemy_factions.len * 4));
        var seed_idx: usize = 0;
        for (enemy_factions) |faction| {
            var seeds_assigned: usize = 0;
            while (seeds_assigned < seeds_per_faction and seed_idx < unassigned_list.items.len) {
                const block_id = unassigned_list.items[seed_idx];
                try faction_seeds.put(block_id, faction);
                seed_idx += 1;
                seeds_assigned += 1;
            }
        }

        // Flood-fill from seeds to create contiguous territories
        // Process in rounds - each round, each faction expands to adjacent unassigned blocks
        var changed = true;
        while (changed) {
            changed = false;

            // For each faction seed, try to expand
            var seeds_iter = faction_seeds.iterator();
            while (seeds_iter.next()) |entry| {
                const block_id = entry.key_ptr.*;
                const faction = entry.value_ptr.*;

                if (self.getBlock(block_id)) |block| {
                    // Assign faction if not yet assigned
                    if (block.faction == null) {
                        block.faction = faction;
                        _ = unassigned.remove(block_id);

                        // Update encounter's controlling faction
                        if (block.encounter) |*enc| {
                            enc.controlling_faction = faction;
                        }
                        changed = true;
                    }

                    // Try to expand to adjacent unassigned blocks
                    for (block.getAdjacentBlocks()) |adj_id| {
                        if (unassigned.contains(adj_id)) {
                            // Claim this adjacent block for our faction
                            try faction_seeds.put(adj_id, faction);
                        }
                    }
                }
            }
        }

        // Assign any remaining unassigned blocks to nearest faction (or contested)
        var remaining_iter = unassigned.keyIterator();
        while (remaining_iter.next()) |id_ptr| {
            if (self.getBlock(id_ptr.*)) |block| {
                // Find adjacent faction or mark as contested
                var found_faction: ?Faction = null;
                for (block.getAdjacentBlocks()) |adj_id| {
                    if (self.getBlock(adj_id)) |adj_block| {
                        if (adj_block.faction != null and adj_block.faction != player_faction) {
                            found_faction = adj_block.faction;
                            break;
                        }
                    }
                }
                block.faction = found_faction; // null = contested

                if (block.encounter) |*enc| {
                    if (found_faction) |f| {
                        enc.controlling_faction = f;
                    }
                }
            }
        }
    }

    /// Compute adjacencies between blocks in a chunk
    fn computeChunkAdjacencies(self: *PolyominoMap, chunk: *Chunk) void {
        // For each block, find adjacent blocks
        for (0..chunk.block_count) |block_idx| {
            const block = &chunk.blocks[block_idx];
            for (block.getCells()) |cell| {
                for (cell.neighbors()) |neighbor| {
                    // Check if neighbor belongs to a different block
                    const neighbor_chunk_coord = neighbor.toChunkCoord();

                    // If neighbor is in same chunk
                    if (neighbor_chunk_coord.eql(chunk.coord)) {
                        if (chunk.getBlockAt(neighbor)) |neighbor_block| {
                            if (neighbor_block.id != block.id) {
                                block.addAdjacent(neighbor_block.id);
                            }
                        }
                    } else {
                        // Neighbor is in different chunk
                        if (self.getChunk(neighbor_chunk_coord)) |neighbor_chunk| {
                            if (neighbor_chunk.getBlockAt(neighbor)) |neighbor_block| {
                                block.addAdjacent(neighbor_block.id);
                                // Also add reverse adjacency
                                neighbor_block.addAdjacent(block.id);
                            }
                        }
                    }
                }
            }
        }
    }

    /// Get all visible blocks as a slice (caller provides buffer)
    /// Returns blocks in order: conquered, layer_1, layer_2, layer_3
    pub fn getVisibleBlocks(self: *PolyominoMap, buffer: []?*Block) usize {
        var count: usize = 0;

        // Add all conquered blocks
        var conquered_iter = self.conquered_blocks.keyIterator();
        while (conquered_iter.next()) |id_ptr| {
            if (count >= buffer.len) break;
            if (self.getBlock(id_ptr.*)) |block| {
                buffer[count] = block;
                count += 1;
            }
        }

        // Add layer 1 blocks (revealed, adjacent to conquered)
        var layer1_iter = self.layer_1_blocks.keyIterator();
        while (layer1_iter.next()) |id_ptr| {
            if (count >= buffer.len) break;
            if (self.getBlock(id_ptr.*)) |block| {
                buffer[count] = block;
                count += 1;
            }
        }

        // Add layer 2 blocks
        var layer2_iter = self.layer_2_blocks.keyIterator();
        while (layer2_iter.next()) |id_ptr| {
            if (count >= buffer.len) break;
            if (self.getBlock(id_ptr.*)) |block| {
                buffer[count] = block;
                count += 1;
            }
        }

        // Add layer 3 blocks
        var layer3_iter = self.layer_3_blocks.keyIterator();
        while (layer3_iter.next()) |id_ptr| {
            if (count >= buffer.len) break;
            if (self.getBlock(id_ptr.*)) |block| {
                buffer[count] = block;
                count += 1;
            }
        }

        return count;
    }

    /// Get count of visible blocks
    pub fn getVisibleBlockCount(self: *PolyominoMap) usize {
        return self.conquered_blocks.count() +
            self.layer_1_blocks.count() +
            self.layer_2_blocks.count() +
            self.layer_3_blocks.count();
    }

    /// Check if two blocks are adjacent and share the same faction
    pub fn areBlocksSameFactionAdjacent(self: *PolyominoMap, block_a_id: u32, block_b_id: u32) bool {
        const block_a = self.getBlock(block_a_id) orelse return false;
        const block_b = self.getBlock(block_b_id) orelse return false;

        // Must have same faction (and both must have a faction)
        if (block_a.faction == null or block_b.faction == null) return false;
        if (block_a.faction != block_b.faction) return false;

        // Must be adjacent
        for (block_a.getAdjacentBlocks()) |adj_id| {
            if (adj_id == block_b_id) return true;
        }
        return false;
    }

    /// Check if a block edge is an exterior edge (adjacent to different faction or fog)
    pub fn isExteriorEdge(self: *PolyominoMap, block_id: u32, neighbor_block_id: u32) bool {
        const block = self.getBlock(block_id) orelse return true;
        const neighbor = self.getBlock(neighbor_block_id) orelse return true;

        // If neighbor is fogged, it's exterior
        if (neighbor.visibility_layer == .fogged) return true;

        // If different factions (or one is null), it's exterior
        if (block.faction == null or neighbor.faction == null) return true;
        if (block.faction != neighbor.faction) return true;

        return false;
    }
};

// ============================================================================
// NEIGHBORHOOD NAME GENERATOR
// ============================================================================

/// Generate a random neighborhood name
fn generateNeighborhoodName(rng: std.Random) []const u8 {
    const prefixes = [_][]const u8{
        "Maple",     "Oak",       "Pine",   "Cedar",
        "Elm",       "Willow",    "Cherry", "Birch",
        "Spruce",    "Hickory",   "Sunny",  "Shady",
        "Green",     "Pleasant",  "Fair",   "Snow",
        "Frost",     "Winter",    "North",  "South",
        "Riverside", "Hillcrest", "Meadow", "Valley",
        "Park",      "Forest",    "Lake",   "Mountain",
    };

    const prefix_idx = rng.intRangeAtMost(usize, 0, prefixes.len - 1);
    return prefixes[prefix_idx];
}

// ============================================================================
// TESTS
// ============================================================================

test "grid coord to chunk coord" {
    const coord1 = GridCoord.init(5, 10);
    const chunk1 = coord1.toChunkCoord();
    try std.testing.expect(chunk1.x == 0);
    try std.testing.expect(chunk1.y == 0);

    const coord2 = GridCoord.init(20, 35);
    const chunk2 = coord2.toChunkCoord();
    try std.testing.expect(chunk2.x == 1);
    try std.testing.expect(chunk2.y == 2);

    const coord3 = GridCoord.init(-5, -20);
    const chunk3 = coord3.toChunkCoord();
    try std.testing.expect(chunk3.x == -1);
    try std.testing.expect(chunk3.y == -2);
}

test "polyomino map initialization" {
    const allocator = std.testing.allocator;
    var map = PolyominoMap.init(allocator, 12345);
    defer map.deinit();

    try map.generateStartingArea(.blue);

    // Should have generated center chunk and neighbors (9 chunks)
    try std.testing.expect(map.chunks.count() >= 1);

    // Should have a starting block
    try std.testing.expect(map.start_block_id != null);

    // Starting block should be revealed (not conquered yet - player must win first fight)
    try std.testing.expect(map.revealed_blocks.count() == 1);
    try std.testing.expect(map.conquered_blocks.count() == 0);
}

test "block adjacency" {
    const allocator = std.testing.allocator;
    var map = PolyominoMap.init(allocator, 54321);
    defer map.deinit();

    try map.generateStartingArea(.blue);

    // Get starting block
    const start_id = map.start_block_id.?;
    const start_block = map.getBlock(start_id).?;

    // Starting block should have adjacent blocks (computed during generation)
    try std.testing.expect(start_block.adjacent_count > 0);

    // Starting block is revealed but not conquered yet
    try std.testing.expect(start_block.state == .revealed);

    // Simulate winning the first fight - conquer the starting block
    try map.conquerBlock(start_id, .blue);

    // Now adjacent blocks should be revealed
    for (start_block.getAdjacentBlocks()) |adj_id| {
        try std.testing.expect(map.revealed_blocks.contains(adj_id));
    }
}

test "chunk generation produces valid polyominoes" {
    const allocator = std.testing.allocator;
    var map = PolyominoMap.init(allocator, 99999);
    defer map.deinit();

    // Generate a single chunk
    try map.ensureChunkGenerated(ChunkCoord.init(0, 0));

    const chunk = map.getChunk(ChunkCoord.init(0, 0)).?;

    // All cells should be assigned
    var total_cells: usize = 0;
    for (0..chunk.block_count) |i| {
        const block = &chunk.blocks[i];
        total_cells += block.cell_count;
        // Each block should have at least 1 cell, and no more than max
        try std.testing.expect(block.cell_count >= 1);
        try std.testing.expect(block.cell_count <= MAX_BLOCK_SIZE);
    }

    // Total cells should equal chunk size squared
    const expected_cells: usize = @intCast(CHUNK_SIZE * CHUNK_SIZE);
    try std.testing.expect(total_cells == expected_cells);
}
