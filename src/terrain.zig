const std = @import("std");
const rl = @import("raylib");
const entity = @import("entity.zig");

const Team = entity.Team;

// Terrain types for snow battle environment
pub const TerrainType = enum {
    thick_snow, // Deep unpacked snow - slow movement
    packed_snow, // Packed down snow - normal speed
    icy_ground, // Very packed/frozen - fast but slippery
    deep_powder, // Very deep fresh snow - very slow
    cleared_ground, // Shoveled/cleared - fastest
    slushy, // Wet melting snow - slow and applies soggy

    pub fn getMovementSpeedMultiplier(self: TerrainType) f32 {
        return switch (self) {
            .thick_snow => 0.7, // 70% speed
            .packed_snow => 1.0, // Normal speed
            .icy_ground => 1.2, // 120% speed (but slippery)
            .deep_powder => 0.5, // 50% speed
            .cleared_ground => 1.1, // 110% speed
            .slushy => 0.8, // 80% speed
        };
    }

    pub fn getColor(self: TerrainType) rl.Color {
        return switch (self) {
            .thick_snow => rl.Color{ .r = 240, .g = 240, .b = 255, .a = 255 }, // Soft white
            .packed_snow => rl.Color{ .r = 200, .g = 210, .b = 220, .a = 255 }, // Grayish white
            .icy_ground => rl.Color{ .r = 180, .g = 200, .b = 230, .a = 255 }, // Blue-white
            .deep_powder => rl.Color{ .r = 255, .g = 255, .b = 255, .a = 255 }, // Pure white
            .cleared_ground => rl.Color{ .r = 140, .g = 140, .b = 140, .a = 255 }, // Gray
            .slushy => rl.Color{ .r = 190, .g = 200, .b = 210, .a = 255 }, // Dull white-gray
        };
    }

    // Get visual height/depth of snow (in world units)
    // Characters are radius 10-12 (diameter ~20-24), so these depths are relative to that scale
    pub fn getSnowHeight(self: TerrainType) f32 {
        return switch (self) {
            .cleared_ground => 0.0, // Ground level (no snow)
            .icy_ground => 2.0, // Very thin compressed layer
            .slushy => 5.0, // Shallow slush
            .packed_snow => 8.0, // Ankle-deep (characters sink in slightly)
            .thick_snow => 15.0, // Knee-deep (characters sink in noticeably)
            .deep_powder => 25.0, // Thigh-deep (characters wade through)
        };
    }

    // How far a character sinks into the snow (affects rendering position)
    pub fn getSinkDepth(self: TerrainType) f32 {
        return switch (self) {
            .cleared_ground => 0.0, // No sinking
            .icy_ground => 0.5, // Barely sink
            .slushy => 3.0, // Sink a bit
            .packed_snow => 4.0, // Sink ankle-deep
            .thick_snow => 10.0, // Sink knee-deep
            .deep_powder => 18.0, // Sink thigh-deep (almost half the character height)
        };
    }

    pub fn canBePackedBy(self: TerrainType, traffic_amount: f32) ?TerrainType {
        // Returns what terrain becomes after being walked on
        // Much easier to pack - repeated movement creates paths quickly
        return switch (self) {
            .deep_powder => if (traffic_amount > 0.15) .thick_snow else null, // Pack quickly
            .thick_snow => if (traffic_amount > 0.3) .packed_snow else null, // Pack fairly quickly
            .packed_snow => if (traffic_amount > 1.0) .icy_ground else null, // Takes more traffic to ice over
            .icy_ground, .cleared_ground, .slushy => null, // Can't pack further
        };
    }

    pub fn canAccumulateSnow(self: TerrainType) bool {
        // Returns whether this terrain can have snow accumulate on it
        return switch (self) {
            .cleared_ground => true, // Can become thick_snow
            .slushy => true, // Can become thick_snow
            .icy_ground => false, // Too hard/frozen
            .packed_snow => true, // Can become thick_snow
            .thick_snow => true, // Can become deep_powder
            .deep_powder => false, // Already max depth
        };
    }

    pub fn getAccumulatedType(self: TerrainType) TerrainType {
        // Returns what this terrain becomes after snow accumulates
        return switch (self) {
            .cleared_ground => .thick_snow,
            .slushy => .thick_snow,
            .packed_snow => .thick_snow,
            .thick_snow => .deep_powder,
            .icy_ground, .deep_powder => self, // No change
        };
    }
};

// Individual terrain cell in the grid
pub const TerrainCell = struct {
    type: TerrainType,
    traffic_accumulator: f32 = 0.0, // Tracks how much this cell has been walked on
    snow_depth: f32 = 1.0, // 0.0 = cleared, 1.0 = normal, 2.0 = deep
    accumulation_timer: f32 = 0.0, // Time until next snow accumulation
    last_traffic_time: f32 = 0.0, // Time since last traffic (for restoration)

    // Wall substrate layer - player-built structures
    wall_height: f32 = 0.0, // Height of wall structure (0 = no wall)
    wall_hp: f32 = 0.0, // Durability of wall (when 0, wall crumbles)
    wall_age: f32 = 0.0, // Time since wall built (for decay/effects)
    wall_team: Team = .none, // Which team built this wall

    pub fn applyTraffic(self: *TerrainCell, amount: f32) void {
        self.traffic_accumulator += amount;
        self.last_traffic_time = 0.0; // Reset idle timer when walked on

        // Check if terrain should transition to more packed state
        if (self.type.canBePackedBy(self.traffic_accumulator)) |new_type| {
            self.type = new_type;
            self.traffic_accumulator = 0.0; // Reset after transition
        }
    }

    pub fn updateAccumulation(self: *TerrainCell, dt: f32, accumulation_rate: f32) void {
        self.last_traffic_time += dt;

        // Only accumulate in areas that haven't been walked on recently
        const idle_threshold = 30.0; // 30 seconds without traffic
        if (self.last_traffic_time < idle_threshold) return;

        if (!self.type.canAccumulateSnow()) return;

        self.accumulation_timer += dt;

        // Accumulate snow MUCH slower (every 60-120 seconds instead of 10)
        const accumulation_interval = 60.0 / accumulation_rate; // seconds
        if (self.accumulation_timer >= accumulation_interval) {
            self.accumulation_timer = 0.0;
            self.type = self.type.getAccumulatedType();
            self.snow_depth = @min(2.0, self.snow_depth + 0.05); // Slower depth increase
        }
    }

    // Get total height of this cell (base + wall + snow)
    pub fn getTotalHeight(self: TerrainCell, base_elevation: f32) f32 {
        var height = base_elevation;
        height += self.wall_height;
        height += self.type.getSnowHeight() * self.snow_depth;
        return height;
    }

    // Get movement speed multiplier (terrain + wall climbing penalty)
    pub fn getMovementSpeedMultiplier(self: TerrainCell) f32 {
        var speed = self.type.getMovementSpeedMultiplier();

        // Major penalty for climbing walls
        if (self.wall_height > 20.0) {
            speed *= 0.2; // 80% slow while climbing tall walls
        } else if (self.wall_height > 10.0) {
            speed *= 0.5; // 50% slow for low walls
        }

        return speed;
    }

    // Update wall (erosion, decay)
    pub fn updateWall(self: *TerrainCell, dt: f32) void {
        if (self.wall_height <= 0.0) return; // No wall here

        self.wall_age += dt;

        // Walls naturally settle/erode slowly
        const erosion_rate = 0.5; // units per second
        self.wall_height = @max(0.0, self.wall_height - erosion_rate * dt);

        // Wall completely eroded
        if (self.wall_height <= 0.0) {
            self.wall_hp = 0.0;
            self.wall_age = 0.0;
        }
    }

    // Damage the wall structure (from skills)
    pub fn damageWall(self: *TerrainCell, damage: f32) void {
        if (self.wall_height <= 0.0) return; // No wall to damage

        self.wall_hp -= damage;

        // Wall destroyed - crumbles significantly
        if (self.wall_hp <= 0.0) {
            self.wall_height = @max(0.0, self.wall_height * 0.3); // 70% reduction
            self.wall_hp = self.wall_height * 10.0; // Rebuild HP if any height remains

            if (self.wall_height < 5.0) {
                // Completely destroyed
                self.wall_height = 0.0;
                self.wall_hp = 0.0;
                self.wall_age = 0.0;
            }
        }
    }
};

// Grid-based terrain system
pub const TerrainGrid = struct {
    cells: []TerrainCell,
    heightmap: []f32, // Base elevation at each grid point (in world units)
    allocator: std.mem.Allocator,
    grid_size: f32, // Size of each cell in world units
    width: usize, // Number of cells wide
    height: usize, // Number of cells tall
    world_offset_x: f32, // World position of grid origin
    world_offset_z: f32,

    // Snow accumulation settings
    accumulation_rate: f32 = 0.1, // Multiplier for how fast snow falls (0.0 = off, 0.1 = light, 1.0 = heavy, 2.0 = blizzard)

    pub fn init(
        allocator: std.mem.Allocator,
        width: usize,
        height: usize,
        grid_size: f32,
        world_offset_x: f32,
        world_offset_z: f32,
    ) !TerrainGrid {
        const cells = try allocator.alloc(TerrainCell, width * height);
        const heightmap = try allocator.alloc(f32, width * height);

        // Initialize all cells with random terrain distribution
        var prng = std.Random.DefaultPrng.init(@bitCast(std.time.timestamp()));
        const random = prng.random();

        // Generate interesting heightmap with hills and valleys
        // Use multiple octaves of Perlin-like noise (simplified)
        for (0..height) |z| {
            for (0..width) |x| {
                const index = z * width + x;

                // Normalized coordinates (0.0 to 1.0)
                const nx = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(width));
                const nz = @as(f32, @floatFromInt(z)) / @as(f32, @floatFromInt(height));

                // Create gentle rolling hills
                // Combine sine waves at different frequencies for natural terrain
                const wave1 = @sin(nx * 3.14159 * 2.0) * @cos(nz * 3.14159 * 2.0);
                const wave2 = @sin(nx * 3.14159 * 4.0 + 1.5) * @cos(nz * 3.14159 * 3.0);
                const wave3 = @sin(nx * 3.14159 * 6.0) * @sin(nz * 3.14159 * 5.0);

                // Blend waves with decreasing amplitude (octaves)
                var elevation = wave1 * 30.0; // Main hills (±30 units)
                elevation += wave2 * 15.0; // Medium detail (±15 units)
                elevation += wave3 * 5.0; // Fine detail (±5 units)

                // Add some randomness for texture
                elevation += (random.float(f32) - 0.5) * 8.0;

                // Make center arena flatter (for gameplay)
                const center_x = 0.5;
                const center_z = 0.5;
                const dist_to_center = @sqrt((nx - center_x) * (nx - center_x) + (nz - center_z) * (nz - center_z));
                const flatten_factor = @max(0.0, 1.0 - dist_to_center * 2.5); // Flatten center 40%
                elevation = elevation * (1.0 - flatten_factor * 0.7); // Reduce elevation in center

                // Create massive irregular snowdrift walls at edges (natural arena boundary)
                // Use distance from edge with noise to make it organic
                const edge_dist_x = @min(nx, 1.0 - nx); // Distance to nearest X edge (0-0.5)
                const edge_dist_z = @min(nz, 1.0 - nz); // Distance to nearest Z edge (0-0.5)
                const edge_dist = @min(edge_dist_x, edge_dist_z); // Distance to nearest edge

                // Create irregular boundary with noise
                const boundary_noise = @sin(nx * 23.0 + nz * 17.0) * 0.03 +
                    @cos(nx * 31.0 - nz * 29.0) * 0.02;
                const boundary_threshold = 0.08 + boundary_noise; // ~8% from edge with variation

                if (edge_dist < boundary_threshold) {
                    // Inside boundary zone - create massive snowdrifts
                    const wall_factor = 1.0 - (edge_dist / boundary_threshold);

                    // Add wavy variation to wall height for natural look
                    const wall_variation = @sin(nx * 19.0) * @cos(nz * 23.0) * 20.0 +
                        @sin(nx * 37.0 + nz * 41.0) * 15.0;

                    // Massive snowdrift walls (80-150 units high)
                    const wall_height = 80.0 + wall_factor * 70.0 + wall_variation;
                    elevation = @max(elevation, wall_height);
                }

                heightmap[index] = elevation;
            }
        }

        // Initialize terrain cells based on elevation
        for (0..height) |z| {
            for (0..width) |x| {
                const index = z * width + x;
                const elevation = heightmap[index];

                // High elevation = massive snowdrift walls (impassable)
                if (elevation > 70.0) {
                    cells[index] = TerrainCell{
                        .type = .deep_powder, // Impassable deep snow
                        .snow_depth = 3.0, // Extra deep
                    };
                } else {
                    // Normal playable area - start with mostly thick snow (70%), some packed (20%), some deep powder (10%)
                    const rand = random.float(f32);
                    cells[index] = TerrainCell{
                        .type = if (rand < 0.7)
                            .thick_snow
                        else if (rand < 0.9)
                            .packed_snow
                        else
                            .deep_powder,
                        .snow_depth = 1.0 + random.float(f32) * 0.5, // 1.0 to 1.5 depth
                    };
                }
            }
        }

        return TerrainGrid{
            .cells = cells,
            .heightmap = heightmap,
            .allocator = allocator,
            .grid_size = grid_size,
            .width = width,
            .height = height,
            .world_offset_x = world_offset_x,
            .world_offset_z = world_offset_z,
        };
    }

    pub fn deinit(self: *TerrainGrid) void {
        self.allocator.free(self.cells);
        self.allocator.free(self.heightmap);
    }

    // Convert world position to grid coordinates
    pub fn worldToGrid(self: TerrainGrid, world_x: f32, world_z: f32) ?struct { x: usize, z: usize } {
        const local_x = world_x - self.world_offset_x;
        const local_z = world_z - self.world_offset_z;

        if (local_x < 0 or local_z < 0) return null;

        const grid_x = @as(usize, @intFromFloat(local_x / self.grid_size));
        const grid_z = @as(usize, @intFromFloat(local_z / self.grid_size));

        if (grid_x >= self.width or grid_z >= self.height) return null;

        return .{ .x = grid_x, .z = grid_z };
    }

    // Convert grid coordinates to world position (center of cell)
    pub fn gridToWorld(self: TerrainGrid, grid_x: usize, grid_z: usize) rl.Vector3 {
        return rl.Vector3{
            .x = self.world_offset_x + (@as(f32, @floatFromInt(grid_x)) + 0.5) * self.grid_size,
            .y = 0,
            .z = self.world_offset_z + (@as(f32, @floatFromInt(grid_z)) + 0.5) * self.grid_size,
        };
    }

    // Get terrain cell at world position
    pub fn getCellAt(self: *TerrainGrid, world_x: f32, world_z: f32) ?*TerrainCell {
        const coords = self.worldToGrid(world_x, world_z) orelse return null;
        const index = coords.z * self.width + coords.x;
        if (index >= self.cells.len) return null;
        return &self.cells[index];
    }

    // Get terrain cell at world position (const version)
    pub fn getCellAtConst(self: *const TerrainGrid, world_x: f32, world_z: f32) ?*const TerrainCell {
        const coords = self.worldToGrid(world_x, world_z) orelse return null;
        const index = coords.z * self.width + coords.x;
        if (index >= self.cells.len) return null;
        return &self.cells[index];
    }

    // Apply traffic from entity movement (packs snow down over time)
    pub fn applyMovementTraffic(self: *TerrainGrid, world_x: f32, world_z: f32, traffic_amount: f32) void {
        if (self.getCellAt(world_x, world_z)) |cell| {
            cell.applyTraffic(traffic_amount);
        }
    }

    // Update all terrain (accumulation, melting, walls, etc.)
    pub fn update(self: *TerrainGrid, dt: f32) void {
        for (self.cells) |*cell| {
            cell.updateAccumulation(dt, self.accumulation_rate);
            cell.updateWall(dt);
        }
    }

    // Get terrain movement speed multiplier at world position
    pub fn getMovementSpeedAt(self: *const TerrainGrid, world_x: f32, world_z: f32) f32 {
        if (self.getCellAtConst(world_x, world_z)) |cell| {
            return cell.getMovementSpeedMultiplier();
        }
        return 1.0; // Default if out of bounds
    }

    // Get how much a character should sink into snow at this position
    pub fn getSinkDepthAt(self: *const TerrainGrid, world_x: f32, world_z: f32) f32 {
        if (self.getCellAtConst(world_x, world_z)) |cell| {
            return cell.type.getSinkDepth();
        }
        return 0.0; // Default if out of bounds
    }

    // Get the visual height of snow at this position
    pub fn getSnowHeightAt(self: *const TerrainGrid, world_x: f32, world_z: f32) f32 {
        if (self.getCellAtConst(world_x, world_z)) |cell| {
            return cell.type.getSnowHeight();
        }
        return 0.0; // Default if out of bounds
    }

    // Get base terrain elevation at world position (bilinear interpolation)
    pub fn getElevationAt(self: *const TerrainGrid, world_x: f32, world_z: f32) f32 {
        const local_x = world_x - self.world_offset_x;
        const local_z = world_z - self.world_offset_z;

        if (local_x < 0 or local_z < 0) return 0.0;

        // Get fractional grid coordinates
        const fx = local_x / self.grid_size;
        const fz = local_z / self.grid_size;

        // Get integer grid coordinates (bottom-left corner)
        const x0 = @as(usize, @intFromFloat(@floor(fx)));
        const z0 = @as(usize, @intFromFloat(@floor(fz)));
        const x1 = x0 + 1;
        const z1 = z0 + 1;

        // Check bounds
        if (x1 >= self.width or z1 >= self.height) {
            // On edge, just return nearest cell
            if (x0 >= self.width or z0 >= self.height) return 0.0;
            return self.heightmap[z0 * self.width + x0];
        }

        // Get interpolation weights
        const tx = fx - @floor(fx);
        const tz = fz - @floor(fz);

        // Get heights at four corners
        const h00 = self.heightmap[z0 * self.width + x0];
        const h10 = self.heightmap[z0 * self.width + x1];
        const h01 = self.heightmap[z1 * self.width + x0];
        const h11 = self.heightmap[z1 * self.width + x1];

        // Bilinear interpolation
        const h0 = h00 * (1.0 - tx) + h10 * tx;
        const h1 = h01 * (1.0 - tx) + h11 * tx;
        return h0 * (1.0 - tz) + h1 * tz;
    }

    // Get total ground Y position (elevation + snow height - sink depth)
    pub fn getGroundYAt(self: *const TerrainGrid, world_x: f32, world_z: f32) f32 {
        const elevation = self.getElevationAt(world_x, world_z);
        const snow_height = self.getSnowHeightAt(world_x, world_z);
        return elevation + snow_height;
    }

    // Check if a position is blocked by boundary walls (massive snowdrifts)
    pub fn isBlocked(self: *const TerrainGrid, world_x: f32, world_z: f32) bool {
        const elevation = self.getElevationAt(world_x, world_z);
        // Boundary walls are 70+ units high - impassable
        return elevation > 70.0;
    }

    // === TERRAIN MODIFICATION API (for skills) ===

    // Set terrain type at a specific position (for skill effects)
    pub fn setTerrainAt(self: *TerrainGrid, world_x: f32, world_z: f32, terrain_type: TerrainType) void {
        if (self.getCellAt(world_x, world_z)) |cell| {
            cell.type = terrain_type;
            cell.traffic_accumulator = 0.0; // Reset traffic
            cell.last_traffic_time = 0.0; // Mark as recently modified
        }
    }

    // Create a circle of terrain (for AoE effects like ice walls, cleared zones)
    pub fn setTerrainInRadius(
        self: *TerrainGrid,
        center_x: f32,
        center_z: f32,
        radius: f32,
        terrain_type: TerrainType,
    ) void {
        const radius_sq = radius * radius;

        // Find grid bounds for the circle
        const min_x = center_x - radius;
        const max_x = center_x + radius;
        const min_z = center_z - radius;
        const max_z = center_z + radius;

        // Get grid coordinates for bounds
        const min_grid = self.worldToGrid(min_x, min_z);
        const max_grid = self.worldToGrid(max_x, max_z);

        if (min_grid == null or max_grid == null) return;

        const min_gx = min_grid.?.x;
        const min_gz = min_grid.?.z;
        const max_gx = @min(max_grid.?.x + 1, self.width);
        const max_gz = @min(max_grid.?.z + 1, self.height);

        // Iterate through cells in the bounding box
        var gz = min_gz;
        while (gz < max_gz) : (gz += 1) {
            var gx = min_gx;
            while (gx < max_gx) : (gx += 1) {
                const cell_world_pos = self.gridToWorld(gx, gz);
                const dx = cell_world_pos.x - center_x;
                const dz = cell_world_pos.z - center_z;
                const dist_sq = dx * dx + dz * dz;

                // If cell is within radius, modify it
                if (dist_sq <= radius_sq) {
                    const index = gz * self.width + gx;
                    if (index < self.cells.len) {
                        self.cells[index].type = terrain_type;
                        self.cells[index].traffic_accumulator = 0.0;
                        self.cells[index].last_traffic_time = 0.0;
                    }
                }
            }
        }
    }

    // Create a rectangular wall of terrain (for ice walls, snow barriers)
    pub fn setTerrainInRect(
        self: *TerrainGrid,
        min_x: f32,
        min_z: f32,
        max_x: f32,
        max_z: f32,
        terrain_type: TerrainType,
    ) void {
        const min_grid = self.worldToGrid(min_x, min_z);
        const max_grid = self.worldToGrid(max_x, max_z);

        if (min_grid == null or max_grid == null) return;

        const min_gx = min_grid.?.x;
        const min_gz = min_grid.?.z;
        const max_gx = @min(max_grid.?.x + 1, self.width);
        const max_gz = @min(max_grid.?.z + 1, self.height);

        var gz = min_gz;
        while (gz < max_gz) : (gz += 1) {
            var gx = min_gx;
            while (gx < max_gx) : (gx += 1) {
                const index = gz * self.width + gx;
                if (index < self.cells.len) {
                    self.cells[index].type = terrain_type;
                    self.cells[index].traffic_accumulator = 0.0;
                    self.cells[index].last_traffic_time = 0.0;
                }
            }
        }
    }

    // Clear terrain in an area (for explosions, shoveling)
    pub fn clearTerrainInRadius(self: *TerrainGrid, center_x: f32, center_z: f32, radius: f32) void {
        self.setTerrainInRadius(center_x, center_z, radius, .cleared_ground);
    }

    // Create snow pile/wall in an area
    pub fn createSnowPileInRadius(self: *TerrainGrid, center_x: f32, center_z: f32, radius: f32) void {
        self.setTerrainInRadius(center_x, center_z, radius, .deep_powder);
    }

    // Create ice in an area (for ice wall skills)
    pub fn createIceInRadius(self: *TerrainGrid, center_x: f32, center_z: f32, radius: f32) void {
        self.setTerrainInRadius(center_x, center_z, radius, .icy_ground);
    }

    // === WALL BUILDING API ===

    /// Build a wall from point A to point B
    /// Walls are substrate layer - composed with terrain
    pub fn buildWall(
        self: *TerrainGrid,
        start_x: f32,
        start_z: f32,
        end_x: f32,
        end_z: f32,
        wall_height: f32,
        wall_thickness: f32,
        team: Team,
    ) void {
        // Walk along line from start to end
        const dx = end_x - start_x;
        const dz = end_z - start_z;
        const length = @sqrt(dx * dx + dz * dz);
        const steps = @as(usize, @intFromFloat(@ceil(length / (self.grid_size * 0.5))));

        if (steps == 0) return;

        // Normalized direction
        const dir_x = dx / length;
        const dir_z = dz / length;

        // Perpendicular direction (for thickness)
        const perp_x = -dir_z;
        const perp_z = dir_x;

        // For each step along the line
        var i: usize = 0;
        while (i <= steps) : (i += 1) {
            const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
            const center_x = start_x + dx * t;
            const center_z = start_z + dz * t;

            // For thickness, modify cells perpendicular to line
            const thickness_steps = @as(usize, @intFromFloat(@ceil(wall_thickness / (self.grid_size * 0.5))));

            var j: usize = 0;
            while (j <= thickness_steps) : (j += 1) {
                const offset = (@as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(@max(1, thickness_steps))) - 0.5) * wall_thickness;
                const cell_x = center_x + perp_x * offset;
                const cell_z = center_z + perp_z * offset;

                if (self.getCellAt(cell_x, cell_z)) |cell| {
                    // Set wall properties (additive - can stack walls)
                    cell.wall_height = @max(cell.wall_height, wall_height);
                    cell.wall_team = team;
                    cell.wall_hp = wall_height * 10.0; // HP scales with height
                    cell.wall_age = 0.0;

                    // Reset snow on top (fresh wall surface)
                    cell.type = .packed_snow; // Wall surface is packed
                    cell.snow_depth = 0.5; // Minimal snow initially
                    cell.last_traffic_time = 0.0; // Fresh surface
                }
            }
        }
    }

    /// Build wall perpendicular to facing direction (for skills)
    /// This is the main skill-casting interface
    pub fn buildWallPerpendicular(
        self: *TerrainGrid,
        caster_x: f32,
        caster_z: f32,
        facing_angle: f32, // radians
        distance_from_caster: f32,
        wall_length: f32,
        wall_height: f32,
        wall_thickness: f32,
        team: Team,
    ) void {
        // Position wall in front of caster
        const wall_center_x = caster_x + @cos(facing_angle) * distance_from_caster;
        const wall_center_z = caster_z + @sin(facing_angle) * distance_from_caster;

        // Wall runs perpendicular to facing
        const wall_angle = facing_angle + std.math.pi / 2.0;
        const half_length = wall_length * 0.5;

        const start_x = wall_center_x - @cos(wall_angle) * half_length;
        const start_z = wall_center_z - @sin(wall_angle) * half_length;
        const end_x = wall_center_x + @cos(wall_angle) * half_length;
        const end_z = wall_center_z + @sin(wall_angle) * half_length;

        self.buildWall(start_x, start_z, end_x, end_z, wall_height, wall_thickness, team);
    }

    /// Damage walls in an area (for wall-breaker skills)
    pub fn damageWallsInRadius(
        self: *TerrainGrid,
        center_x: f32,
        center_z: f32,
        radius: f32,
        damage: f32,
    ) void {
        const radius_sq = radius * radius;

        const min_grid = self.worldToGrid(center_x - radius, center_z - radius);
        const max_grid = self.worldToGrid(center_x + radius, center_z + radius);

        if (min_grid == null or max_grid == null) return;

        const min_gx = min_grid.?.x;
        const min_gz = min_grid.?.z;
        const max_gx = @min(max_grid.?.x + 1, self.width);
        const max_gz = @min(max_grid.?.z + 1, self.height);

        var gz = min_gz;
        while (gz < max_gz) : (gz += 1) {
            var gx = min_gx;
            while (gx < max_gx) : (gx += 1) {
                const cell_world_pos = self.gridToWorld(gx, gz);
                const dx = cell_world_pos.x - center_x;
                const dz = cell_world_pos.z - center_z;
                const dist_sq = dx * dx + dz * dz;

                if (dist_sq <= radius_sq) {
                    const index = gz * self.width + gx;
                    if (index < self.cells.len) {
                        self.cells[index].damageWall(damage);
                    }
                }
            }
        }
    }

    /// Check if there's a wall between two points (for cover/LOS calculation)
    pub fn hasWallBetween(
        self: *const TerrainGrid,
        from_x: f32,
        from_z: f32,
        to_x: f32,
        to_z: f32,
        min_wall_height: f32,
    ) bool {
        // Raycast along line, check for walls
        const dx = to_x - from_x;
        const dz = to_z - from_z;
        const distance = @sqrt(dx * dx + dz * dz);
        const steps = @as(usize, @intFromFloat(@ceil(distance / (self.grid_size * 0.5))));

        if (steps == 0) return false;

        var i: usize = 1; // Skip starting point
        while (i < steps) : (i += 1) { // Skip ending point too
            const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
            const check_x = from_x + dx * t;
            const check_z = from_z + dz * t;

            if (self.getCellAtConst(check_x, check_z)) |cell| {
                if (cell.wall_height >= min_wall_height) {
                    return true; // Wall blocking line
                }
            }
        }

        return false;
    }

    /// Get wall height at position (for rendering, collision, etc.)
    pub fn getWallHeightAt(self: *const TerrainGrid, world_x: f32, world_z: f32) f32 {
        if (self.getCellAtConst(world_x, world_z)) |cell| {
            return cell.wall_height;
        }
        return 0.0;
    }
};
