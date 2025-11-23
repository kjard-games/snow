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
            // EMPHASIZED layer differences - dramatic color shifts as snow is displaced
            // GoW approach: clear visual feedback shows player impact on terrain
            .cleared_ground => rl.Color{ .r = 75, .g = 60, .b = 50, .a = 255 }, // DARK brown ground (clear contrast)
            .icy_ground => rl.Color{ .r = 220, .g = 230, .b = 240, .a = 255 }, // Light blue ice (compressed to glass)
            .slushy => rl.Color{ .r = 180, .g = 185, .b = 180, .a = 255 }, // Medium gray slush (dirty/wet)
            .packed_snow => rl.Color{ .r = 235, .g = 240, .b = 240, .a = 255 }, // Light gray-white (visibly compressed)
            .thick_snow => rl.Color{ .r = 250, .g = 252, .b = 250, .a = 255 }, // Nearly white (slightly trampled)
            .deep_powder => rl.Color{ .r = 255, .g = 255, .b = 255, .a = 255 }, // PURE WHITE (pristine untouched)
        };
    }

    // Get visual height/depth of snow (in world units)
    // EMPHASIZED height differences - dramatic visual displacement as snow is trampled
    // GoW approach: height changes reinforce the layer system
    pub fn getSnowHeight(self: TerrainType) f32 {
        return switch (self) {
            .cleared_ground => 0.0, // Ground level (completely cleared - HUGE difference)
            .icy_ground => 3.0, // Very thin compressed layer (packed flat)
            .slushy => 6.0, // Shallow slush (compressed but wet)
            .packed_snow => 10.0, // Ankle-deep (visibly trampled down)
            .thick_snow => 18.0, // Knee-deep (slightly packed)
            .deep_powder => 28.0, // Thigh-deep (pristine, untouched - MAXIMUM height)
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

    pub fn applyTraffic(self: *TerrainCell, amount: f32) ?TerrainType {
        self.traffic_accumulator += amount;
        self.last_traffic_time = 0.0; // Reset idle timer when walked on

        // Check if terrain should transition to more packed state
        if (self.type.canBePackedBy(self.traffic_accumulator)) |new_type| {
            self.type = new_type;
            self.traffic_accumulator = 0.0; // Reset after transition
            return new_type; // Return new type to signal mesh needs updating
        }
        return null; // No change
    }

    pub fn updateAccumulation(self: *TerrainCell, dt: f32, accumulation_rate: f32) bool {
        self.last_traffic_time += dt;

        // Only accumulate in areas that haven't been walked on recently
        const idle_threshold = 30.0; // 30 seconds without traffic
        if (self.last_traffic_time < idle_threshold) return false;

        if (!self.type.canAccumulateSnow()) return false;

        self.accumulation_timer += dt;

        // Accumulate snow MUCH slower (every 60-120 seconds instead of 10)
        const accumulation_interval = 60.0 / accumulation_rate; // seconds
        if (self.accumulation_timer >= accumulation_interval) {
            self.accumulation_timer = 0.0;
            self.type = self.type.getAccumulatedType();
            self.snow_depth = @min(2.0, self.snow_depth + 0.05); // Slower depth increase
            return true; // Changed - signal mesh update needed
        }
        return false;
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

    // Mesh-based rendering (GoW-style approach)
    terrain_mesh: ?rl.Mesh = null, // Single mesh for entire terrain base
    mesh_dirty: bool = true, // Track if mesh needs rebuilding

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

                // Create gentle rolling hills with smooth, natural slopes (GoW-style)
                // Use multiple octaves of sine waves for natural terrain
                // Keep frequencies LOW for smooth, rolling hills
                const wave1 = @sin(nx * 3.14159 * 1.5) * @cos(nz * 3.14159 * 1.5);
                const wave2 = @sin(nx * 3.14159 * 2.5 + 1.5) * @cos(nz * 3.14159 * 2.0);
                const wave3 = @sin(nx * 3.14159 * 3.5) * @sin(nz * 3.14159 * 3.0);

                // Blend waves with decreasing amplitude (octaves)
                // Reduced amplitudes for gentler terrain
                var elevation = wave1 * 20.0; // Main gentle hills (±20 units)
                elevation += wave2 * 8.0; // Medium detail (±8 units)
                elevation += wave3 * 3.0; // Fine detail (±3 units)

                // Minimal randomness - just enough to break up patterns
                elevation += (random.float(f32) - 0.5) * 2.0; // Reduced from 8.0 to 2.0

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

        // Multiple smoothing passes for very gentle, rolling terrain (GoW-style)
        // GoW emphasizes smooth, natural slopes that feel hand-sculpted
        const smoothed_heightmap = try allocator.alloc(f32, width * height);
        defer allocator.free(smoothed_heightmap);

        // Run 3 smoothing passes for extremely gentle terrain
        var pass: usize = 0;
        while (pass < 3) : (pass += 1) {
            for (0..height) |z| {
                for (0..width) |x| {
                    const index = z * width + x;

                    // Skip boundary walls - keep them sharp
                    if (heightmap[index] > 70.0) {
                        smoothed_heightmap[index] = heightmap[index];
                        continue;
                    }

                    var sum: f32 = 0.0;
                    var count: f32 = 0.0;

                    // Larger 5x5 kernel for more aggressive smoothing
                    const x_start = if (x > 1) x - 2 else x;
                    const x_end = if (x < width - 2) x + 2 else x;
                    const z_start = if (z > 1) z - 2 else z;
                    const z_end = if (z < height - 2) z + 2 else z;

                    var nz = z_start;
                    while (nz <= z_end) : (nz += 1) {
                        var nx = x_start;
                        while (nx <= x_end) : (nx += 1) {
                            const neighbor_idx = nz * width + nx;
                            // Weight by distance (Gaussian-like)
                            const dx = @as(f32, @floatFromInt(if (nx > x) nx - x else x - nx));
                            const dz = @as(f32, @floatFromInt(if (nz > z) nz - z else z - nz));
                            const weight = 1.0 / (1.0 + dx + dz);
                            sum += heightmap[neighbor_idx] * weight;
                            count += weight;
                        }
                    }

                    smoothed_heightmap[index] = sum / count;
                }
            }

            // Copy smoothed heights back for next pass
            for (0..height) |z| {
                for (0..width) |x| {
                    const index = z * width + x;
                    if (heightmap[index] < 70.0) {
                        heightmap[index] = smoothed_heightmap[index];
                    }
                }
            }
        }

        // Initialize terrain cells based on elevation
        for (0..height) |z| {
            for (0..width) |x| {
                const index = z * width + x;
                const elevation = heightmap[index];

                // Start with pristine deep powder everywhere (GoW-style fresh snowfall)
                // Players will pack it down as they move, revealing layers
                // Boundary walls (high elevation) are impassable
                if (elevation > 70.0) {
                    cells[index] = TerrainCell{
                        .type = .deep_powder, // Impassable boundary walls
                        .snow_depth = 3.0, // Extra deep
                    };
                } else {
                    // Playable area: all pristine deep powder
                    cells[index] = TerrainCell{
                        .type = .deep_powder, // Pure white pristine snow
                        .snow_depth = 1.5, // Deep fresh snow
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

    /// Mark mesh as dirty (needs regeneration)
    pub fn markMeshDirty(self: *TerrainGrid) void {
        self.mesh_dirty = true;
    }

    /// Generate a single mesh from the entire terrain grid (GoW-style approach)
    /// Uses raylib's genMeshPlane and modifies vertices based on heightmap
    pub fn generateTerrainMesh(self: *TerrainGrid) void {
        // Clean up existing mesh
        if (self.terrain_mesh) |mesh| {
            rl.unloadMesh(mesh);
            self.terrain_mesh = null;
        }

        // Generate a plane mesh with our grid resolution
        // genMeshPlane parameters: width, length, resX, resZ
        const world_width = @as(f32, @floatFromInt(self.width)) * self.grid_size;
        const world_length = @as(f32, @floatFromInt(self.height)) * self.grid_size;

        // Generate a plane mesh (this will auto-upload to GPU WITHOUT colors)
        var mesh = rl.genMeshPlane(
            world_width,
            world_length,
            @intCast(self.width),
            @intCast(self.height),
        );

        // genMeshPlane auto-uploads, but without color data
        // We need to unload that GPU data and re-upload with colors
        if (mesh.vaoId > 0) {
            // Create a temporary mesh struct with just the GPU IDs to unload
            var temp_mesh = std.mem.zeroes(rl.Mesh);
            temp_mesh.vaoId = mesh.vaoId;
            temp_mesh.vboId = mesh.vboId;
            rl.unloadMesh(temp_mesh); // Unload GPU data only

            // Reset IDs so uploadMesh will create new VAO with all attributes
            mesh.vaoId = 0;
            mesh.vboId = null;
        }

        // Mesh is centered at origin, we need to translate it to our world offset
        // and modify Y coordinates based on heightmap + snow
        const vertex_count = @as(usize, @intCast(mesh.vertexCount));

        // Modify vertices to match our terrain heightmap and snow
        var i: usize = 0;
        while (i < vertex_count) : (i += 1) {
            // Get vertex position (XYZ)
            const vx = mesh.vertices[i * 3 + 0];
            const vz = mesh.vertices[i * 3 + 2];

            // Transform from centered plane coordinates to our grid coordinates
            // genMeshPlane creates a plane from -width/2 to width/2, -length/2 to length/2
            const world_x = vx + self.world_offset_x + world_width * 0.5;
            const world_z = vz + self.world_offset_z + world_length * 0.5;

            // Get elevation, snow height, and wall height at this position
            const elevation = self.getElevationAt(world_x, world_z);
            const snow_height = self.getSnowHeightAt(world_x, world_z);
            const wall_height = self.getWallHeightAt(world_x, world_z);

            // Set Y coordinate to elevation + snow height + wall height
            // GoW approach: walls are just snow displacement (height field)
            mesh.vertices[i * 3 + 1] = elevation + snow_height + wall_height;

            // Update X and Z to world coordinates
            mesh.vertices[i * 3 + 0] = world_x;
            mesh.vertices[i * 3 + 2] = world_z;
        }

        // Allocate and set vertex colors based on terrain type
        mesh.colors = @ptrCast(@alignCast(rl.memAlloc(@intCast(vertex_count * 4 * @sizeOf(u8)))));

        // First pass: find min/max height for normalization
        var min_height: f32 = std.math.floatMax(f32);
        var max_height: f32 = std.math.floatMin(f32);
        i = 0;
        while (i < vertex_count) : (i += 1) {
            const vy = mesh.vertices[i * 3 + 1];
            min_height = @min(min_height, vy);
            max_height = @max(max_height, vy);
        }
        const height_range = max_height - min_height;

        i = 0;
        while (i < vertex_count) : (i += 1) {
            const vx = mesh.vertices[i * 3 + 0];
            const vy = mesh.vertices[i * 3 + 1];
            const vz = mesh.vertices[i * 3 + 2];

            // Get terrain cell color
            if (self.getCellAtConst(vx, vz)) |cell| {
                var color = cell.type.getColor();

                // GoW approach: Walls are just tinted snow (very subtle team color)
                if (cell.wall_height > 5.0) {
                    // Apply subtle team tint to wall snow (5% influence)
                    switch (cell.wall_team) {
                        .red => {
                            color.r = @min(255, @as(u16, color.r) + 8);
                            color.g = if (color.g > 4) color.g - 4 else 0;
                            color.b = if (color.b > 4) color.b - 4 else 0;
                        },
                        .blue => {
                            color.r = if (color.r > 4) color.r - 4 else 0;
                            color.g = if (color.g > 4) color.g - 4 else 0;
                            color.b = @min(255, @as(u16, color.b) + 8);
                        },
                        .yellow => {
                            color.r = @min(255, @as(u16, color.r) + 8);
                            color.g = @min(255, @as(u16, color.g) + 8);
                            color.b = if (color.b > 4) color.b - 4 else 0;
                        },
                        .green => {
                            color.r = if (color.r > 4) color.r - 4 else 0;
                            color.g = @min(255, @as(u16, color.g) + 8);
                            color.b = if (color.b > 4) color.b - 4 else 0;
                        },
                        .none => {},
                    }

                    // Darken slightly based on wall age (weathering)
                    const age_factor = @min(1.0, cell.wall_age / 30.0);
                    const age_darken = @as(u8, @intFromFloat(10.0 * age_factor));
                    color.r = if (color.r > age_darken) color.r - age_darken else 0;
                    color.g = if (color.g > age_darken) color.g - age_darken else 0;
                    color.b = if (color.b > age_darken) color.b - age_darken else 0;
                }

                // GoW approach: Keep vertex colors BRIGHT, let the shader handle lighting!
                // Only VERY minimal variation to break up flatness

                // 1. MINIMAL height-based variation (just a hint of AO in deep valleys)
                if (height_range > 10.0) { // Only apply if significant height variation
                    const normalized_height = (vy - min_height) / height_range;
                    // Much less darkening: 0.95 to 1.0 (max 5% darkening)
                    const height_factor = 0.95 + normalized_height * 0.05;
                    color.r = @intFromFloat(@as(f32, @floatFromInt(color.r)) * height_factor);
                    color.g = @intFromFloat(@as(f32, @floatFromInt(color.g)) * height_factor);
                    color.b = @intFromFloat(@as(f32, @floatFromInt(color.b)) * height_factor);
                }

                // 2. VERY subtle position variation (1% variation max)
                const pos_hash = @sin(vx * 0.1) * @cos(vz * 0.15) + @sin(vx * 0.3 + vz * 0.2);
                const variation = 0.99 + (pos_hash * 0.5 + 0.5) * 0.02; // Range: 0.99 to 1.01
                color.r = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(color.r)) * variation));
                color.g = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(color.g)) * variation));
                color.b = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(color.b)) * variation));

                mesh.colors[i * 4 + 0] = color.r;
                mesh.colors[i * 4 + 1] = color.g;
                mesh.colors[i * 4 + 2] = color.b;
                mesh.colors[i * 4 + 3] = color.a;
            } else {
                // Default white for out-of-bounds
                mesh.colors[i * 4 + 0] = 255;
                mesh.colors[i * 4 + 1] = 255;
                mesh.colors[i * 4 + 2] = 255;
                mesh.colors[i * 4 + 3] = 255;
            }
        }

        // Calculate proper per-vertex normals for terrain shading
        // genMeshPlane generates normals, but we modified vertices so they're invalid
        if (mesh.normals == null) {
            mesh.normals = @ptrCast(@alignCast(rl.memAlloc(@intCast(vertex_count * 3 * @sizeOf(f32)))));
        }

        // Initialize all normals to zero
        var v_idx: usize = 0;
        while (v_idx < vertex_count) : (v_idx += 1) {
            mesh.normals[v_idx * 3 + 0] = 0.0;
            mesh.normals[v_idx * 3 + 1] = 0.0;
            mesh.normals[v_idx * 3 + 2] = 0.0;
        }

        // Calculate face normals and accumulate to vertex normals
        // genMeshPlane creates triangles with indices, but we can calculate from vertex positions
        const triangle_count = @as(usize, @intCast(mesh.triangleCount));
        var tri_idx: usize = 0;
        while (tri_idx < triangle_count) : (tri_idx += 1) {
            // Get the three vertex indices for this triangle
            const idx0 = @as(usize, @intCast(mesh.indices[tri_idx * 3 + 0]));
            const idx1 = @as(usize, @intCast(mesh.indices[tri_idx * 3 + 1]));
            const idx2 = @as(usize, @intCast(mesh.indices[tri_idx * 3 + 2]));

            // Get vertex positions
            const v0x = mesh.vertices[idx0 * 3 + 0];
            const v0y = mesh.vertices[idx0 * 3 + 1];
            const v0z = mesh.vertices[idx0 * 3 + 2];

            const v1x = mesh.vertices[idx1 * 3 + 0];
            const v1y = mesh.vertices[idx1 * 3 + 1];
            const v1z = mesh.vertices[idx1 * 3 + 2];

            const v2x = mesh.vertices[idx2 * 3 + 0];
            const v2y = mesh.vertices[idx2 * 3 + 1];
            const v2z = mesh.vertices[idx2 * 3 + 2];

            // Calculate edge vectors
            const e1x = v1x - v0x;
            const e1y = v1y - v0y;
            const e1z = v1z - v0z;

            const e2x = v2x - v0x;
            const e2y = v2y - v0y;
            const e2z = v2z - v0z;

            // Calculate face normal (cross product)
            const nx = e1y * e2z - e1z * e2y;
            const ny = e1z * e2x - e1x * e2z;
            const nz = e1x * e2y - e1y * e2x;

            // Accumulate to all three vertices (weighted by area)
            mesh.normals[idx0 * 3 + 0] += nx;
            mesh.normals[idx0 * 3 + 1] += ny;
            mesh.normals[idx0 * 3 + 2] += nz;

            mesh.normals[idx1 * 3 + 0] += nx;
            mesh.normals[idx1 * 3 + 1] += ny;
            mesh.normals[idx1 * 3 + 2] += nz;

            mesh.normals[idx2 * 3 + 0] += nx;
            mesh.normals[idx2 * 3 + 1] += ny;
            mesh.normals[idx2 * 3 + 2] += nz;
        }

        // Normalize all vertex normals
        v_idx = 0;
        while (v_idx < vertex_count) : (v_idx += 1) {
            const nx = mesh.normals[v_idx * 3 + 0];
            const ny = mesh.normals[v_idx * 3 + 1];
            const nz = mesh.normals[v_idx * 3 + 2];

            const length = @sqrt(nx * nx + ny * ny + nz * nz);
            if (length > 0.0001) {
                mesh.normals[v_idx * 3 + 0] = nx / length;
                mesh.normals[v_idx * 3 + 1] = ny / length;
                mesh.normals[v_idx * 3 + 2] = nz / length;
            } else {
                // Degenerate normal, point up
                mesh.normals[v_idx * 3 + 0] = 0.0;
                mesh.normals[v_idx * 3 + 1] = 1.0;
                mesh.normals[v_idx * 3 + 2] = 0.0;
            }
        }

        // Now upload mesh to GPU with ALL vertex data including colors
        rl.uploadMesh(&mesh, false);

        std.log.info("Terrain mesh generated: {} vertices, {} triangles", .{ vertex_count, mesh.triangleCount });

        self.terrain_mesh = mesh;
        self.mesh_dirty = false;
    }

    pub fn deinit(self: *TerrainGrid) void {
        self.allocator.free(self.cells);
        self.allocator.free(self.heightmap);

        // Clean up mesh if allocated
        if (self.terrain_mesh) |mesh| {
            rl.unloadMesh(mesh);
        }
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
            if (cell.applyTraffic(traffic_amount)) |_| {
                // Terrain type changed - mark mesh for regeneration
                self.markMeshDirty();
            }
        }
    }

    // Update all terrain (accumulation, melting, walls, etc.)
    pub fn update(self: *TerrainGrid, dt: f32) void {
        var any_changed = false;
        for (self.cells) |*cell| {
            if (cell.updateAccumulation(dt, self.accumulation_rate)) {
                any_changed = true;
            }
            cell.updateWall(dt);
        }

        // Mark mesh dirty if any cell changed
        if (any_changed) {
            self.markMeshDirty();
        }

        // Rebuild mesh if dirty (during update phase, not render phase)
        if (self.mesh_dirty) {
            self.generateTerrainMesh();
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
            self.markMeshDirty(); // Mesh needs rebuilding
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

        self.markMeshDirty(); // Mesh needs rebuilding
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

        self.markMeshDirty(); // Mesh needs rebuilding
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

        // Walls are height displacement in the mesh (GoW approach)
        // Mark mesh for regeneration to include new wall geometry
        self.markMeshDirty();
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
