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

    /// Set of block IDs that are revealed (adjacent to conquered)
    revealed_blocks: std.AutoHashMap(u32, void),

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
    }

    /// Generate the starting area and place player
    pub fn generateStartingArea(self: *PolyominoMap, player_faction: Faction) !void {
        // Generate just the center chunk first
        const center = ChunkCoord.init(0, 0);
        try self.ensureChunkGenerated(center);

        // Find a block near the center to be the starting block
        if (self.getChunk(center)) |center_chunk| {
            if (center_chunk.block_count > 0) {
                const start_block = &center_chunk.blocks[0];
                self.start_block_id = start_block.id;

                // Conquer the starting block
                try self.conquerBlock(start_block.id, player_faction);

                // Now expand frontier to generate adjacent chunks and reveal neighbors
                try self.expandFrontier();
            }
        }
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

        try self.conquered_blocks.put(block_id, {});
        _ = self.revealed_blocks.remove(block_id);

        // Reveal adjacent blocks (only those already generated)
        for (block.getAdjacentBlocks()) |adj_id| {
            if (!self.conquered_blocks.contains(adj_id)) {
                try self.revealBlock(adj_id);
            }
        }

        // Update camera bounds
        self.updateCameraBounds();
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
            self.revealed_blocks.contains(block_id);
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
    fn assignBlockProperties(self: *PolyominoMap, block: *Block, rng: std.Random) void {
        _ = self;

        // Random faction (or null for contested)
        const faction_roll = rng.intRangeAtMost(u8, 0, 10);
        block.faction = if (faction_roll < 8)
            rng.enumValue(Faction)
        else
            null;

        // Generate encounter
        block.encounter = EncounterNode.random(rng, @intCast(block.id));

        // Override encounter's faction to match block
        if (block.encounter) |*enc| {
            if (block.faction) |f| {
                enc.controlling_faction = f;
            }
        }

        // Generate name
        block.name = generateNeighborhoodName(rng);
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

        // Add all revealed blocks
        var revealed_iter = self.revealed_blocks.keyIterator();
        while (revealed_iter.next()) |id_ptr| {
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
        return self.conquered_blocks.count() + self.revealed_blocks.count();
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

    // Starting block should be conquered
    try std.testing.expect(map.conquered_blocks.count() == 1);
}

test "block adjacency" {
    const allocator = std.testing.allocator;
    var map = PolyominoMap.init(allocator, 54321);
    defer map.deinit();

    try map.generateStartingArea(.blue);

    // Get starting block
    const start_id = map.start_block_id.?;
    const start_block = map.getBlock(start_id).?;

    // Starting block should have adjacent blocks
    try std.testing.expect(start_block.adjacent_count > 0);

    // Adjacent blocks should be revealed
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
