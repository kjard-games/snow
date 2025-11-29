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

// ============================================================================
// KID SCALE SYSTEM
// ============================================================================
//
// We're 10-year-old kids in this game! Everything should feel BIG.
// Real-world scale is exaggerated 3x to give that childhood perspective
// where houses tower over you and streets feel impossibly wide.
//
// Reference: A 10-year-old is ~1.4m tall (4'6")
// In game units: 1 meter ≈ 6.67 units (2000 unit arena = 300m real)
// With 3x scale: 1 meter ≈ 20 units (making world feel 3x larger)

/// The kid scale factor - everything in the world is scaled up by this much
/// to make it feel like you're a small kid in a big world
pub const KID_SCALE: f32 = 2.2;

/// Real height of a 10-year-old in meters
pub const KID_HEIGHT_METERS: f32 = 1.4;

/// Kid height in game units (without scale applied - this is what the player model is)
/// Base: 6.67 units per meter * 1.4m = ~9.3 units
pub const KID_HEIGHT_UNITS: f32 = 9.3;

/// Kid eye level in game units (roughly 90% of height)
pub const KID_EYE_LEVEL: f32 = KID_HEIGHT_UNITS * 0.9;

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
    /// Scaled by KID_SCALE (3x) to make buildings tower over kid characters
    /// Base scale: ~6.67 game units per real meter, then 3x for kid perspective
    pub fn getDefaultHeight(self: BuildingType) f32 {
        // Base heights (real-world accurate at 6.67 units/meter)
        const base_height: f32 = switch (self) {
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
        // Apply kid scale - buildings are 3x taller from a kid's perspective!
        return base_height * KID_SCALE;
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
// EAR CLIPPING TRIANGULATION
// ============================================================================
//
// The ear clipping algorithm triangulates arbitrary simple polygons (including
// concave ones like U-shaped or L-shaped buildings). It works by repeatedly
// finding "ears" - triangles formed by three consecutive vertices where:
// 1. The middle vertex is convex (interior angle < 180°)
// 2. No other vertices lie inside the triangle
//
// Each ear can be "clipped" (removed), reducing the polygon by one vertex.
// Repeat until only 3 vertices remain (one final triangle).

/// Maximum triangles for a polygon (n-2 triangles for n vertices)
const MAX_TRIANGLES: usize = MAX_BUILDING_VERTICES - 2;

/// A triangle defined by three vertex indices
const Triangle = struct {
    a: usize,
    b: usize,
    c: usize,
};

/// Result of ear clipping triangulation
const TriangulationResult = struct {
    triangles: [MAX_TRIANGLES]Triangle,
    count: usize,
};

/// Cross product of 2D vectors (returns Z component, positive = counter-clockwise)
fn cross2D(ax: f32, az: f32, bx: f32, bz: f32) f32 {
    return ax * bz - az * bx;
}

/// Check if polygon vertices are in counter-clockwise order
/// Uses signed area: positive = CCW, negative = CW
fn isCounterClockwise(vertices: []const WorldVertex) bool {
    var signed_area: f32 = 0;
    const n = vertices.len;
    for (0..n) |i| {
        const v0 = vertices[i];
        const v1 = vertices[(i + 1) % n];
        signed_area += (v1.x - v0.x) * (v1.z + v0.z);
    }
    return signed_area < 0; // Negative in our coord system = CCW
}

/// Check if vertex at index 'b' is convex (interior angle < 180°)
/// For CCW polygon, convex means the cross product of edges is positive
fn isConvex(vertices: []const WorldVertex, indices: []const usize, idx: usize) bool {
    const n = indices.len;
    const i_prev = indices[(idx + n - 1) % n];
    const i_curr = indices[idx];
    const i_next = indices[(idx + 1) % n];

    const prev = vertices[i_prev];
    const curr = vertices[i_curr];
    const next = vertices[i_next];

    // Vector from prev to curr
    const ax = curr.x - prev.x;
    const az = curr.z - prev.z;
    // Vector from curr to next
    const bx = next.x - curr.x;
    const bz = next.z - curr.z;

    // Cross product: positive means left turn (convex for CCW polygon)
    return cross2D(ax, az, bx, bz) > 0;
}

/// Check if point p is inside triangle abc (using barycentric coordinates)
fn pointInTriangle(p: WorldVertex, a: WorldVertex, b: WorldVertex, c: WorldVertex) bool {
    // Compute vectors
    const v0x = c.x - a.x;
    const v0z = c.z - a.z;
    const v1x = b.x - a.x;
    const v1z = b.z - a.z;
    const v2x = p.x - a.x;
    const v2z = p.z - a.z;

    // Compute dot products
    const dot00 = v0x * v0x + v0z * v0z;
    const dot01 = v0x * v1x + v0z * v1z;
    const dot02 = v0x * v2x + v0z * v2z;
    const dot11 = v1x * v1x + v1z * v1z;
    const dot12 = v1x * v2x + v1z * v2z;

    // Compute barycentric coordinates
    const denom = dot00 * dot11 - dot01 * dot01;
    if (@abs(denom) < 0.0001) return false; // Degenerate triangle

    const inv_denom = 1.0 / denom;
    const u = (dot11 * dot02 - dot01 * dot12) * inv_denom;
    const v = (dot00 * dot12 - dot01 * dot02) * inv_denom;

    // Check if point is in triangle (with small epsilon for edge cases)
    const epsilon: f32 = 0.0001;
    return (u >= -epsilon) and (v >= -epsilon) and (u + v <= 1.0 + epsilon);
}

/// Check if the triangle at vertex idx is an "ear" (can be clipped)
/// An ear is a convex vertex where no other polygon vertices are inside the triangle
fn isEar(vertices: []const WorldVertex, indices: []const usize, idx: usize) bool {
    // Must be convex
    if (!isConvex(vertices, indices, idx)) return false;

    const n = indices.len;
    const i_prev = indices[(idx + n - 1) % n];
    const i_curr = indices[idx];
    const i_next = indices[(idx + 1) % n];

    const a = vertices[i_prev];
    const b = vertices[i_curr];
    const c = vertices[i_next];

    // Check that no other vertices are inside this triangle
    for (0..n) |i| {
        if (i == (idx + n - 1) % n or i == idx or i == (idx + 1) % n) continue;
        const p = vertices[indices[i]];
        if (pointInTriangle(p, a, b, c)) return false;
    }

    return true;
}

/// Triangulate a polygon using ear clipping algorithm
/// Returns array of triangles (vertex indices into original vertices array)
fn triangulatePolygon(vertices: []const WorldVertex, vertex_count: usize) TriangulationResult {
    var result = TriangulationResult{
        .triangles = undefined,
        .count = 0,
    };

    if (vertex_count < 3) return result;
    if (vertex_count == 3) {
        // Simple case: already a triangle
        result.triangles[0] = .{ .a = 0, .b = 1, .c = 2 };
        result.count = 1;
        return result;
    }

    // Working list of vertex indices (we remove vertices as we clip ears)
    var indices: [MAX_BUILDING_VERTICES]usize = undefined;
    var n = vertex_count;
    for (0..n) |i| {
        indices[i] = i;
    }

    // Ensure polygon is counter-clockwise (required for convexity test)
    const ccw = isCounterClockwise(vertices[0..vertex_count]);
    if (!ccw) {
        // Reverse the indices to make it CCW
        var left: usize = 0;
        var right: usize = n - 1;
        while (left < right) {
            const tmp = indices[left];
            indices[left] = indices[right];
            indices[right] = tmp;
            left += 1;
            right -= 1;
        }
    }

    // Ear clipping loop
    var idx: usize = 0;
    var consecutive_failures: usize = 0;

    while (n > 3) {
        // Safety: if we've gone around the whole polygon without finding an ear,
        // the polygon might be degenerate - fall back to fan triangulation
        if (consecutive_failures >= n) {
            // Fallback: just create remaining triangles from first vertex
            while (n > 2 and result.count < MAX_TRIANGLES) {
                result.triangles[result.count] = .{
                    .a = indices[0],
                    .b = indices[1],
                    .c = indices[2],
                };
                result.count += 1;
                // Remove middle vertex
                for (1..n - 1) |i| {
                    indices[i] = indices[i + 1];
                }
                n -= 1;
            }
            break;
        }

        if (isEar(vertices, indices[0..n], idx)) {
            // Clip this ear: add triangle and remove middle vertex
            const prev_idx = (idx + n - 1) % n;
            const next_idx = (idx + 1) % n;

            result.triangles[result.count] = .{
                .a = indices[prev_idx],
                .b = indices[idx],
                .c = indices[next_idx],
            };
            result.count += 1;

            // Remove vertex at idx by shifting remaining vertices
            for (idx..n - 1) |i| {
                indices[i] = indices[i + 1];
            }
            n -= 1;

            // Stay at same index (or wrap if at end)
            if (idx >= n) idx = 0;
            consecutive_failures = 0;
        } else {
            // Move to next vertex
            idx = (idx + 1) % n;
            consecutive_failures += 1;
        }
    }

    // Add final triangle
    if (n == 3 and result.count < MAX_TRIANGLES) {
        result.triangles[result.count] = .{
            .a = indices[0],
            .b = indices[1],
            .c = indices[2],
        };
        result.count += 1;
    }

    return result;
}

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

    // Draw roof using ear clipping triangulation
    // This correctly handles concave polygons (U-shaped, L-shaped buildings)
    // Also double-sided so roof is visible from below (if camera clips inside)
    const triangulation = triangulatePolygon(building.vertices[0..building.vertex_count], building.vertex_count);

    for (0..triangulation.count) |i| {
        const tri = triangulation.triangles[i];
        const va = building.vertices[tri.a];
        const vb = building.vertices[tri.b];
        const vc = building.vertices[tri.c];

        const ra = rl.Vector3{ .x = va.x, .y = top_y, .z = va.z };
        const rb = rl.Vector3{ .x = vb.x, .y = top_y, .z = vb.z };
        const rc = rl.Vector3{ .x = vc.x, .y = top_y, .z = vc.z };

        // Top face (visible from above)
        rl.drawTriangle3D(ra, rb, rc, roof_color);
        // Bottom face (visible from below)
        rl.drawTriangle3D(ra, rc, rb, roof_color);
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

test "ear clipping - simple square" {
    // Square polygon - should produce 2 triangles
    const verts = [_]WorldVertex{
        .{ .x = 0, .z = 0 },
        .{ .x = 10, .z = 0 },
        .{ .x = 10, .z = 10 },
        .{ .x = 0, .z = 10 },
    };

    const result = triangulatePolygon(&verts, 4);
    try std.testing.expectEqual(@as(usize, 2), result.count);
}

test "ear clipping - triangle" {
    // Triangle - should produce 1 triangle
    const verts = [_]WorldVertex{
        .{ .x = 0, .z = 0 },
        .{ .x = 10, .z = 0 },
        .{ .x = 5, .z = 10 },
    };

    const result = triangulatePolygon(&verts, 3);
    try std.testing.expectEqual(@as(usize, 1), result.count);
}

test "ear clipping - L-shaped (concave)" {
    // L-shaped polygon (6 vertices) - should produce 4 triangles
    //   +--+
    //   |  |
    // +-+  |
    // |    |
    // +----+
    const verts = [_]WorldVertex{
        .{ .x = 0, .z = 0 }, // bottom-left
        .{ .x = 20, .z = 0 }, // bottom-right
        .{ .x = 20, .z = 20 }, // top-right
        .{ .x = 10, .z = 20 }, // inner top-right
        .{ .x = 10, .z = 10 }, // inner corner
        .{ .x = 0, .z = 10 }, // left middle
    };

    const result = triangulatePolygon(&verts, 6);
    // 6 vertices -> 4 triangles (n-2 rule)
    try std.testing.expectEqual(@as(usize, 4), result.count);
}

test "ear clipping - U-shaped (concave)" {
    // U-shaped polygon (8 vertices) - should produce 6 triangles
    // +--+  +--+
    // |  |  |  |
    // |  +--+  |
    // |        |
    // +--------+
    const verts = [_]WorldVertex{
        .{ .x = 0, .z = 0 }, // bottom-left
        .{ .x = 30, .z = 0 }, // bottom-right
        .{ .x = 30, .z = 20 }, // top-right outer
        .{ .x = 20, .z = 20 }, // top-right inner
        .{ .x = 20, .z = 10 }, // right inner bottom
        .{ .x = 10, .z = 10 }, // left inner bottom
        .{ .x = 10, .z = 20 }, // top-left inner
        .{ .x = 0, .z = 20 }, // top-left outer
    };

    const result = triangulatePolygon(&verts, 8);
    // 8 vertices -> 6 triangles (n-2 rule)
    try std.testing.expectEqual(@as(usize, 6), result.count);
}

test "point in triangle" {
    const a = WorldVertex{ .x = 0, .z = 0 };
    const b = WorldVertex{ .x = 10, .z = 0 };
    const c = WorldVertex{ .x = 5, .z = 10 };

    // Center should be inside
    try std.testing.expect(pointInTriangle(.{ .x = 5, .z = 3 }, a, b, c));

    // Outside points
    try std.testing.expect(!pointInTriangle(.{ .x = -1, .z = 0 }, a, b, c));
    try std.testing.expect(!pointInTriangle(.{ .x = 5, .z = 15 }, a, b, c));
}
