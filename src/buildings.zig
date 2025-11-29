const std = @import("std");
const rl = @import("raylib");
const terrain = @import("terrain.zig");
const TerrainGrid = terrain.TerrainGrid;

// ============================================================================
// BUILDINGS - 3D Building Geometry from OSM Data
// ============================================================================
//
// Buildings are rendered as extruded polygons (prisms) with:
// - Footprint from OSM building polygons
// - Height based on building type or OSM tags
// - Roofs (flat for now, pitched later)
// - Collision for gameplay
// - LoS blocking
//
// This is separate from TerrainGrid (which handles ground elevation/snow)
// and PropManager (which handles point-based objects like trees/cars).

/// Building types affect height, color, and gameplay
pub const BuildingType = enum {
    residential_house, // Single family home (~8m)
    residential_garage, // Detached garage (~4m)
    apartment_low, // 2-3 story (~10m)
    apartment_mid, // 4-6 story (~20m)
    commercial_small, // Small shop (~5m)
    commercial_large, // Big box store (~8m)
    school, // School building (~12m)
    church, // Church (~15m + steeple)
    industrial, // Warehouse (~10m)
    shed, // Small shed (~3m)
    unknown, // Default

    /// Get typical height in world units for this building type
    /// Scale: ~6.7 game units per real meter (2000 unit arena = 300m real)
    pub fn getDefaultHeight(self: BuildingType) f32 {
        return switch (self) {
            .residential_house => 55.0, // ~8m real
            .residential_garage => 27.0, // ~4m real
            .apartment_low => 70.0, // ~10m real
            .apartment_mid => 135.0, // ~20m real
            .commercial_small => 40.0, // ~6m real
            .commercial_large => 55.0, // ~8m real
            .school => 80.0, // ~12m real, prominent landmark
            .church => 100.0, // ~15m real
            .industrial => 65.0, // ~10m real
            .shed => 20.0, // ~3m real
            .unknown => 50.0, // ~7.5m default
        };
    }

    /// Get wall color for this building type (distinct, easily identifiable)
    pub fn getWallColor(self: BuildingType) rl.Color {
        return switch (self) {
            .residential_house => rl.Color.init(210, 180, 140, 255), // Tan/beige
            .residential_garage => rl.Color.init(180, 170, 160, 255), // Gray
            .apartment_low, .apartment_mid => rl.Color.init(200, 200, 210, 255), // Light blue-gray
            .commercial_small => rl.Color.init(220, 200, 170, 255), // Cream
            .commercial_large => rl.Color.init(190, 190, 200, 255), // Steel gray
            .school => rl.Color.init(180, 100, 90, 255), // Brick red
            .church => rl.Color.init(240, 235, 220, 255), // Off-white
            .industrial => rl.Color.init(160, 165, 170, 255), // Industrial gray
            .shed => rl.Color.init(140, 110, 80, 255), // Brown wood
            .unknown => rl.Color.init(185, 175, 165, 255), // Neutral
        };
    }

    /// Get roof color for this building type
    pub fn getRoofColor(self: BuildingType) rl.Color {
        return switch (self) {
            .residential_house => rl.Color.init(70, 60, 50, 255), // Dark brown shingles
            .residential_garage => rl.Color.init(65, 60, 55, 255),
            .apartment_low, .apartment_mid => rl.Color.init(50, 55, 60, 255), // Dark gray
            .commercial_small, .commercial_large => rl.Color.init(45, 45, 50, 255), // Near black
            .school => rl.Color.init(55, 45, 40, 255), // Dark brown
            .church => rl.Color.init(60, 65, 70, 255), // Slate
            .industrial => rl.Color.init(75, 75, 80, 255), // Metal gray
            .shed => rl.Color.init(55, 45, 35, 255), // Dark brown
            .unknown => rl.Color.init(65, 60, 55, 255),
        };
    }

    /// Get legend color (brighter version for UI visibility)
    pub fn getLegendColor(self: BuildingType) rl.Color {
        const wall = self.getWallColor();
        return rl.Color.init(
            @min(255, @as(u16, wall.r) + 30),
            @min(255, @as(u16, wall.g) + 30),
            @min(255, @as(u16, wall.b) + 30),
            255,
        );
    }

    /// Get human-readable name for legend
    pub fn getName(self: BuildingType) [:0]const u8 {
        return switch (self) {
            .residential_house => "House",
            .residential_garage => "Garage",
            .apartment_low => "Low-Rise Apt",
            .apartment_mid => "Mid-Rise Apt",
            .commercial_small => "Shop",
            .commercial_large => "Store",
            .school => "School",
            .church => "Church",
            .industrial => "Industrial",
            .shed => "Shed",
            .unknown => "Building",
        };
    }
};

/// A vertex in world coordinates
pub const WorldVertex = struct {
    x: f32,
    z: f32,
};

/// Maximum vertices per building polygon
pub const MAX_BUILDING_VERTICES: usize = 32;

/// A single building instance
pub const Building = struct {
    /// Polygon vertices in world coordinates (closed loop)
    vertices: [MAX_BUILDING_VERTICES]WorldVertex,
    vertex_count: usize,

    /// Building properties
    building_type: BuildingType,
    height: f32, // Total height in world units
    base_elevation: f32, // Ground level (from terrain)

    /// Cached bounding box for fast culling
    min_x: f32,
    max_x: f32,
    min_z: f32,
    max_z: f32,

    /// Initialize from a slice of vertices
    pub fn init(verts: []const WorldVertex, btype: BuildingType, height_override: ?f32) Building {
        var b = Building{
            .vertices = undefined,
            .vertex_count = @min(verts.len, MAX_BUILDING_VERTICES),
            .building_type = btype,
            .height = height_override orelse btype.getDefaultHeight(),
            .base_elevation = 0.0,
            .min_x = std.math.floatMax(f32),
            .max_x = std.math.floatMin(f32),
            .min_z = std.math.floatMax(f32),
            .max_z = std.math.floatMin(f32),
        };

        // Copy vertices and compute bounds
        for (0..b.vertex_count) |i| {
            b.vertices[i] = verts[i];
            b.min_x = @min(b.min_x, verts[i].x);
            b.max_x = @max(b.max_x, verts[i].x);
            b.min_z = @min(b.min_z, verts[i].z);
            b.max_z = @max(b.max_z, verts[i].z);
        }

        return b;
    }

    /// Check if a point is inside this building's footprint (2D)
    pub fn containsPoint(self: *const Building, x: f32, z: f32) bool {
        // Quick AABB check first
        if (x < self.min_x or x > self.max_x or z < self.min_z or z > self.max_z) {
            return false;
        }

        // Ray casting algorithm for point-in-polygon
        var inside = false;
        var j: usize = self.vertex_count - 1;
        for (0..self.vertex_count) |i| {
            const vi = self.vertices[i];
            const vj = self.vertices[j];

            if ((vi.z > z) != (vj.z > z) and
                x < (vj.x - vi.x) * (z - vi.z) / (vj.z - vi.z) + vi.x)
            {
                inside = !inside;
            }
            j = i;
        }
        return inside;
    }

    /// Get center point of building
    pub fn getCenter(self: *const Building) WorldVertex {
        var cx: f32 = 0;
        var cz: f32 = 0;
        for (0..self.vertex_count) |i| {
            cx += self.vertices[i].x;
            cz += self.vertices[i].z;
        }
        const n = @as(f32, @floatFromInt(self.vertex_count));
        return .{ .x = cx / n, .z = cz / n };
    }
};

/// Maximum buildings per arena
pub const MAX_BUILDINGS: usize = 256;

/// Manager for all buildings in an arena
pub const BuildingManager = struct {
    buildings: [MAX_BUILDINGS]Building,
    building_count: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) BuildingManager {
        return .{
            .buildings = undefined,
            .building_count = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BuildingManager) void {
        _ = self;
        // No dynamic allocations in fixed-size array approach
    }

    /// Add a building from world-coordinate vertices
    pub fn addBuilding(
        self: *BuildingManager,
        vertices: []const WorldVertex,
        building_type: BuildingType,
        height_override: ?f32,
    ) ?*Building {
        if (self.building_count >= MAX_BUILDINGS) return null;
        if (vertices.len < 3) return null;

        self.buildings[self.building_count] = Building.init(vertices, building_type, height_override);
        const result = &self.buildings[self.building_count];
        self.building_count += 1;
        return result;
    }

    /// Update base elevations from terrain
    pub fn updateElevations(self: *BuildingManager, terrain_grid: *const TerrainGrid) void {
        for (0..self.building_count) |i| {
            const b = &self.buildings[i];
            const center = b.getCenter();
            b.base_elevation = terrain_grid.getElevationAt(center.x, center.z);
        }
    }

    /// Check if a point collides with any building
    pub fn checkCollision(self: *const BuildingManager, x: f32, z: f32) ?*const Building {
        for (0..self.building_count) |i| {
            if (self.buildings[i].containsPoint(x, z)) {
                return &self.buildings[i];
            }
        }
        return null;
    }

    /// Check if line of sight is blocked by any building
    pub fn checkLoS(self: *const BuildingManager, x1: f32, z1: f32, x2: f32, z2: f32) bool {
        // Sample points along the line
        const dx = x2 - x1;
        const dz = z2 - z1;
        const dist = @sqrt(dx * dx + dz * dz);
        const steps = @as(usize, @intFromFloat(dist / 10.0)) + 1; // Check every 10 units

        for (0..steps) |s| {
            const t = @as(f32, @floatFromInt(s)) / @as(f32, @floatFromInt(steps));
            const px = x1 + dx * t;
            const pz = z1 + dz * t;
            if (self.checkCollision(px, pz) != null) {
                return false; // Blocked
            }
        }
        return true; // Clear LoS
    }

    /// Clear all buildings
    pub fn clear(self: *BuildingManager) void {
        self.building_count = 0;
    }
};

// ============================================================================
// RENDERING
// ============================================================================

/// Draw all buildings
pub fn drawAllBuildings(manager: *const BuildingManager, terrain_grid: *const TerrainGrid) void {
    for (0..manager.building_count) |i| {
        drawBuilding(&manager.buildings[i], terrain_grid);
    }
}

/// Draw a single building as extruded polygon
fn drawBuilding(building: *const Building, terrain_grid: *const TerrainGrid) void {
    if (building.vertex_count < 3) return;

    const wall_color = building.building_type.getWallColor();
    const roof_color = building.building_type.getRoofColor();
    const outline_color = rl.Color.init(40, 35, 30, 255);

    // Get base elevation at building center
    const center = building.getCenter();
    const base_y = terrain_grid.getElevationAt(center.x, center.z);
    const top_y = base_y + building.height;

    // Draw walls (quads between each pair of vertices)
    // IMPORTANT: Draw both sides of each triangle for double-sided rendering
    // Raylib's drawTriangle3D uses backface culling, so we draw each triangle twice
    // with opposite winding order to make walls visible from inside AND outside
    var j: usize = building.vertex_count - 1;
    for (0..building.vertex_count) |i| {
        const v0 = building.vertices[j];
        const v1 = building.vertices[i];

        // Get terrain elevation at each corner for ground-conforming base
        const y0_base = terrain_grid.getElevationAt(v0.x, v0.z);
        const y1_base = terrain_grid.getElevationAt(v1.x, v1.z);

        // Define the four corners of this wall quad
        const bl = rl.Vector3{ .x = v0.x, .y = y0_base, .z = v0.z }; // bottom-left
        const br = rl.Vector3{ .x = v1.x, .y = y1_base, .z = v1.z }; // bottom-right
        const tr = rl.Vector3{ .x = v1.x, .y = top_y, .z = v1.z }; // top-right
        const tl = rl.Vector3{ .x = v0.x, .y = top_y, .z = v0.z }; // top-left

        // Draw wall quad - OUTSIDE face (counter-clockwise from outside)
        rl.drawTriangle3D(bl, br, tr, wall_color);
        rl.drawTriangle3D(bl, tr, tl, wall_color);

        // Draw wall quad - INSIDE face (clockwise from outside = counter-clockwise from inside)
        rl.drawTriangle3D(bl, tr, br, wall_color);
        rl.drawTriangle3D(bl, tl, tr, wall_color);

        // Draw wall outline
        rl.drawLine3D(bl, br, outline_color);
        rl.drawLine3D(tl, tr, outline_color);
        rl.drawLine3D(bl, tl, outline_color);

        j = i;
    }

    // Draw roof (flat for now - fan triangulation from center)
    // Also double-sided so roof is visible from below (if camera clips inside)
    const roof_center = rl.Vector3{ .x = center.x, .y = top_y, .z = center.z };
    for (0..building.vertex_count) |i| {
        const v0 = building.vertices[i];
        const v1 = building.vertices[(i + 1) % building.vertex_count];
        const rv0 = rl.Vector3{ .x = v0.x, .y = top_y, .z = v0.z };
        const rv1 = rl.Vector3{ .x = v1.x, .y = top_y, .z = v1.z };

        // Top face (visible from above)
        rl.drawTriangle3D(roof_center, rv0, rv1, roof_color);
        // Bottom face (visible from below)
        rl.drawTriangle3D(roof_center, rv1, rv0, roof_color);
    }
}

/// Draw building outlines only (for debugging/overview)
pub fn drawBuildingOutlines(manager: *const BuildingManager, terrain_grid: *const TerrainGrid) void {
    const outline_color = rl.Color.init(255, 100, 100, 255);

    for (0..manager.building_count) |bi| {
        const building = &manager.buildings[bi];
        if (building.vertex_count < 3) continue;

        const center = building.getCenter();
        const base_y = terrain_grid.getElevationAt(center.x, center.z);
        const top_y = base_y + building.height;

        // Draw base outline
        var j: usize = building.vertex_count - 1;
        for (0..building.vertex_count) |i| {
            const v0 = building.vertices[j];
            const v1 = building.vertices[i];
            const y0 = terrain_grid.getElevationAt(v0.x, v0.z);
            const y1 = terrain_grid.getElevationAt(v1.x, v1.z);

            rl.drawLine3D(
                .{ .x = v0.x, .y = y0, .z = v0.z },
                .{ .x = v1.x, .y = y1, .z = v1.z },
                outline_color,
            );
            rl.drawLine3D(
                .{ .x = v0.x, .y = top_y, .z = v0.z },
                .{ .x = v1.x, .y = top_y, .z = v1.z },
                outline_color,
            );
            j = i;
        }
    }
}

// ============================================================================
// TESTS
// ============================================================================

test "building contains point" {
    // Simple square building
    const verts = [_]WorldVertex{
        .{ .x = 0, .z = 0 },
        .{ .x = 10, .z = 0 },
        .{ .x = 10, .z = 10 },
        .{ .x = 0, .z = 10 },
    };
    const b = Building.init(&verts, .residential_house, null);

    try std.testing.expect(b.containsPoint(5, 5)); // Center
    try std.testing.expect(b.containsPoint(1, 1)); // Inside corner
    try std.testing.expect(!b.containsPoint(-1, 5)); // Outside left
    try std.testing.expect(!b.containsPoint(15, 5)); // Outside right
}

test "building manager" {
    const allocator = std.testing.allocator;
    var manager = BuildingManager.init(allocator);
    defer manager.deinit();

    const verts = [_]WorldVertex{
        .{ .x = 0, .z = 0 },
        .{ .x = 10, .z = 0 },
        .{ .x = 10, .z = 10 },
        .{ .x = 0, .z = 10 },
    };

    const b = manager.addBuilding(&verts, .residential_house, null);
    try std.testing.expect(b != null);
    try std.testing.expect(manager.building_count == 1);
    try std.testing.expect(manager.checkCollision(5, 5) != null);
    try std.testing.expect(manager.checkCollision(20, 20) == null);
}
