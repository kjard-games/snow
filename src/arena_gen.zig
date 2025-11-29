// ============================================================================
// ARENA GENERATION - Composable Atomic Terrain Primitives
// ============================================================================
//
// Philosophy: Arenas are composed of layered atomic operations, just like
// the effects system composes WHAT/WHEN/WHO/IF.
//
// Two independent height systems that compose:
//   1. ELEVATION (heightmap) - Base terrain shape, affects LoS, movement paths
//   2. SNOW LAYER (TerrainType) - Surface conditions, affects movement speed
//
// Arena = Base Shape + Elevation Features + Snow Zones + Obstacles
//
// THEME: Low-fantasy snowball war in an endless suburb
// Locations: cul-de-sacs, school yards, snowy streets, courtyard blocks,
//            forested clearings, parking lots, playgrounds, backyards
//
// Each primitive is a pure function that modifies a region of the heightmap
// or terrain grid. Primitives can be layered, blended, and combined.
//
// ============================================================================

const std = @import("std");
const rl = @import("raylib");
const terrain_mod = @import("terrain.zig");
const props = @import("arena_props.zig");

const TerrainGrid = terrain_mod.TerrainGrid;
const TerrainType = terrain_mod.TerrainType;
const TerrainCell = terrain_mod.TerrainCell;
const PropPlacement = props.PropPlacement;
const CollectionPlacement = props.CollectionPlacement;
const PropCollection = props.PropCollection;

// ============================================================================
// COORDINATE HELPERS
// ============================================================================

/// Normalized position within arena (0.0 to 1.0)
pub const NormalizedPos = struct {
    x: f32,
    z: f32,

    pub fn distanceTo(self: NormalizedPos, other: NormalizedPos) f32 {
        const dx = self.x - other.x;
        const dz = self.z - other.z;
        return @sqrt(dx * dx + dz * dz);
    }

    pub fn distanceToCenter(self: NormalizedPos) f32 {
        return self.distanceTo(.{ .x = 0.5, .z = 0.5 });
    }

    /// Distance to nearest edge (0 at edge, 0.5 at center)
    pub fn distanceToEdge(self: NormalizedPos) f32 {
        const dx = @min(self.x, 1.0 - self.x);
        const dz = @min(self.z, 1.0 - self.z);
        return @min(dx, dz);
    }
};

// ============================================================================
// ELEVATION PRIMITIVES - Atomic heightmap operations
// ============================================================================

/// How elevation primitives combine with existing terrain
pub const BlendMode = enum {
    replace, // Overwrite existing height
    add, // Add to existing height
    subtract, // Subtract from existing height
    max, // Take maximum of existing and new
    min, // Take minimum of existing and new
    multiply, // Multiply existing by factor
    smooth_blend, // Weighted average based on falloff
};

/// Interpolation mode for external heightmap sampling
pub const HeightmapInterpolation = enum {
    nearest, // Nearest neighbor (blocky)
    bilinear, // Bilinear interpolation (smooth)
};

/// An atomic elevation modification
pub const ElevationPrimitive = union(enum) {
    // === BASIC SHAPES ===

    /// Flat plane at a given height
    flat: struct {
        height: f32 = 0.0,
    },

    /// Circular hill or pit
    mound: struct {
        center: NormalizedPos = .{ .x = 0.5, .z = 0.5 },
        radius: f32 = 0.3, // Normalized radius
        height: f32 = 30.0, // Peak height (negative for pit)
        falloff: Falloff = .smooth,
    },

    /// Ridge/valley running in a direction
    ridge: struct {
        start: NormalizedPos = .{ .x = 0.0, .z = 0.5 },
        end: NormalizedPos = .{ .x = 1.0, .z = 0.5 },
        width: f32 = 0.15, // Normalized width
        height: f32 = 25.0, // Ridge height (negative for valley)
        falloff: Falloff = .smooth,
    },

    /// Rectangular plateau or trench
    plateau: struct {
        min: NormalizedPos = .{ .x = 0.3, .z = 0.3 },
        max: NormalizedPos = .{ .x = 0.7, .z = 0.7 },
        height: f32 = 15.0,
        edge_falloff: f32 = 0.05, // How far the edges slope
    },

    /// Ramp connecting two heights
    ramp: struct {
        start: NormalizedPos = .{ .x = 0.2, .z = 0.5 },
        end: NormalizedPos = .{ .x = 0.8, .z = 0.5 },
        width: f32 = 0.2,
        start_height: f32 = 0.0,
        end_height: f32 = 30.0,
    },

    // === NOISE/ORGANIC ===

    /// Procedural noise-based terrain
    noise: struct {
        seed: u64 = 0,
        octaves: u8 = 3, // Number of noise layers
        amplitude: f32 = 20.0, // Base amplitude
        frequency: f32 = 2.0, // Base frequency
        persistence: f32 = 0.5, // Amplitude multiplier per octave
        lacunarity: f32 = 2.0, // Frequency multiplier per octave
    },

    /// Terracing - creates stepped terrain
    terrace: struct {
        step_height: f32 = 10.0, // Height of each step
        smoothing: f32 = 0.3, // 0 = sharp steps, 1 = smooth ramps
    },

    // === BOUNDARY/ARENA ===

    /// Arena boundary walls (snowdrift style)
    boundary_wall: struct {
        thickness: f32 = 0.08, // Normalized wall thickness
        height: f32 = 100.0, // Wall height
        irregularity: f32 = 0.5, // 0 = smooth, 1 = very jagged
        seed: u64 = 0,
    },

    /// Central arena flattening
    arena_flatten: struct {
        center: NormalizedPos = .{ .x = 0.5, .z = 0.5 },
        radius: f32 = 0.4, // Normalized radius of flat area
        target_height: f32 = 0.0, // Height to flatten toward
        strength: f32 = 0.8, // 0 = no effect, 1 = fully flat
    },

    // === FEATURES ===

    /// Crater/bowl depression
    crater: struct {
        center: NormalizedPos = .{ .x = 0.5, .z = 0.5 },
        outer_radius: f32 = 0.25,
        inner_radius: f32 = 0.15, // Flat bottom radius
        depth: f32 = 20.0,
        rim_height: f32 = 5.0, // Raised rim around edge
    },

    /// Cliff/drop-off
    cliff: struct {
        /// Line defining the cliff edge
        start: NormalizedPos = .{ .x = 0.0, .z = 0.5 },
        end: NormalizedPos = .{ .x = 1.0, .z = 0.5 },
        drop: f32 = 40.0, // Height difference
        steepness: f32 = 0.02, // Normalized width of transition
    },

    // === GIS/EXTERNAL DATA ===

    /// External heightmap data from GIS source (DEM/GeoTIFF)
    /// Data is expected to be normalized 0.0-1.0, scaled by amplitude
    external_heightmap: struct {
        /// Pointer to heightmap data (row-major, normalized 0-1)
        data: []const f32,
        /// Dimensions of source data
        source_width: usize,
        source_height: usize,
        /// Scale factor for height values (world units)
        amplitude: f32 = 50.0,
        /// Offset added after scaling
        base_height: f32 = 0.0,
        /// Interpolation mode
        interpolation: HeightmapInterpolation = .bilinear,
    },

    /// Polygon extrusion - for building footprints from OSM
    /// Vertices define a closed polygon in normalized coordinates
    polygon: struct {
        /// Vertices of the polygon (normalized 0-1 coordinates)
        /// Must be at least 3 vertices, implicitly closed
        vertices: []const NormalizedPos,
        /// Height of the extruded polygon
        height: f32 = 40.0,
        /// Falloff distance from edges (0 = sharp, >0 = sloped)
        edge_falloff: f32 = 0.01,
    },

    /// Polyline as a path/road with width - for streets from OSM
    polyline: struct {
        /// Points along the path (normalized 0-1 coordinates)
        points: []const NormalizedPos,
        /// Width of the path (normalized)
        width: f32 = 0.05,
        /// Height offset (negative for depressed roads)
        height: f32 = -3.0,
        /// Falloff at edges
        falloff: Falloff = .smooth,
    },

    pub fn apply(
        self: ElevationPrimitive,
        heightmap: []f32,
        width: usize,
        height: usize,
        blend: BlendMode,
    ) void {
        for (0..height) |gz| {
            for (0..width) |gx| {
                const idx = gz * width + gx;
                const pos = NormalizedPos{
                    .x = @as(f32, @floatFromInt(gx)) / @as(f32, @floatFromInt(width - 1)),
                    .z = @as(f32, @floatFromInt(gz)) / @as(f32, @floatFromInt(height - 1)),
                };

                const new_height = self.sampleAt(pos);
                heightmap[idx] = applyBlend(heightmap[idx], new_height, blend);
            }
        }
    }

    /// Sample elevation at a normalized position
    pub fn sampleAt(self: ElevationPrimitive, pos: NormalizedPos) f32 {
        return switch (self) {
            .flat => |f| f.height,
            .mound => |m| sampleMound(pos, m),
            .ridge => |r| sampleRidge(pos, r),
            .plateau => |p| samplePlateau(pos, p),
            .ramp => |r| sampleRamp(pos, r),
            .noise => |n| sampleNoise(pos, n),
            .terrace => 0.0, // Terrace is a post-process, needs existing height
            .boundary_wall => |b| sampleBoundaryWall(pos, b),
            .arena_flatten => 0.0, // Flatten is a blend operation
            .crater => |c| sampleCrater(pos, c),
            .cliff => |c| sampleCliff(pos, c),
            .external_heightmap => |e| sampleExternalHeightmap(pos, e),
            .polygon => |p| samplePolygon(pos, p),
            .polyline => |p| samplePolyline(pos, p),
        };
    }
};

/// How values fall off from center
pub const Falloff = enum {
    linear, // Straight line falloff
    smooth, // Smooth S-curve (smoothstep)
    sharp, // Quick falloff then flat
    plateau, // Flat top then falloff

    pub fn apply(self: Falloff, t: f32) f32 {
        const clamped = @max(0.0, @min(1.0, t));
        return switch (self) {
            .linear => 1.0 - clamped,
            .smooth => {
                const s = 1.0 - clamped;
                return s * s * (3.0 - 2.0 * s); // smoothstep
            },
            .sharp => {
                const s = 1.0 - clamped;
                return s * s * s;
            },
            .plateau => {
                if (clamped < 0.5) return 1.0;
                const s = (clamped - 0.5) * 2.0;
                return 1.0 - s * s;
            },
        };
    }
};

// === ELEVATION SAMPLING FUNCTIONS ===

fn sampleMound(pos: NormalizedPos, m: anytype) f32 {
    const dist = pos.distanceTo(m.center);
    if (dist >= m.radius) return 0.0;
    const t = dist / m.radius;
    return m.height * m.falloff.apply(t);
}

fn sampleRidge(pos: NormalizedPos, r: anytype) f32 {
    // Distance to line segment
    const dx = r.end.x - r.start.x;
    const dz = r.end.z - r.start.z;
    const len_sq = dx * dx + dz * dz;

    if (len_sq < 0.0001) return 0.0;

    // Project point onto line
    const t = @max(0.0, @min(1.0, ((pos.x - r.start.x) * dx + (pos.z - r.start.z) * dz) / len_sq));
    const proj_x = r.start.x + t * dx;
    const proj_z = r.start.z + t * dz;

    const dist = @sqrt((pos.x - proj_x) * (pos.x - proj_x) + (pos.z - proj_z) * (pos.z - proj_z));
    if (dist >= r.width) return 0.0;

    const falloff_t = dist / r.width;
    return r.height * r.falloff.apply(falloff_t);
}

fn samplePlateau(pos: NormalizedPos, p: anytype) f32 {
    // Distance to rectangle (negative inside, positive outside)
    const dx = @max(p.min.x - pos.x, pos.x - p.max.x);
    const dz = @max(p.min.z - pos.z, pos.z - p.max.z);
    const dist = @max(dx, dz);

    if (dist >= p.edge_falloff) return 0.0;
    if (dist <= 0.0) return p.height;

    const t = dist / p.edge_falloff;
    return p.height * (1.0 - t);
}

fn sampleRamp(pos: NormalizedPos, r: anytype) f32 {
    // Similar to ridge but height varies along length
    const dx = r.end.x - r.start.x;
    const dz = r.end.z - r.start.z;
    const len_sq = dx * dx + dz * dz;

    if (len_sq < 0.0001) return 0.0;

    const t = @max(0.0, @min(1.0, ((pos.x - r.start.x) * dx + (pos.z - r.start.z) * dz) / len_sq));
    const proj_x = r.start.x + t * dx;
    const proj_z = r.start.z + t * dz;

    const dist = @sqrt((pos.x - proj_x) * (pos.x - proj_x) + (pos.z - proj_z) * (pos.z - proj_z));
    if (dist >= r.width) return 0.0;

    const height_at_t = r.start_height + (r.end_height - r.start_height) * t;
    const width_falloff = 1.0 - (dist / r.width);
    return height_at_t * width_falloff;
}

fn sampleNoise(pos: NormalizedPos, n: anytype) f32 {
    var total: f32 = 0.0;
    var amplitude = n.amplitude;
    var frequency = n.frequency;

    // Simple pseudo-noise using sin combinations
    var octave: u8 = 0;
    while (octave < n.octaves) : (octave += 1) {
        const seed_offset = @as(f32, @floatFromInt(n.seed +% @as(u64, octave) * 1000));
        const nx = pos.x * frequency * std.math.pi + seed_offset;
        const nz = pos.z * frequency * std.math.pi + seed_offset * 0.7;

        const noise_val = @sin(nx) * @cos(nz * 1.3) +
            @sin(nx * 1.7 + nz) * 0.5 +
            @cos(nx * 0.8 - nz * 1.1) * 0.3;

        total += noise_val * amplitude;
        amplitude *= n.persistence;
        frequency *= n.lacunarity;
    }

    return total;
}

fn sampleBoundaryWall(pos: NormalizedPos, b: anytype) f32 {
    const edge_dist = pos.distanceToEdge();

    // Add irregularity using noise
    const seed_f = @as(f32, @floatFromInt(b.seed));
    const noise = @sin(pos.x * 23.0 + seed_f) * @cos(pos.z * 17.0 + seed_f * 0.5) * b.irregularity * 0.03;
    const threshold = b.thickness + noise;

    if (edge_dist >= threshold) return 0.0;

    // Wall height increases toward edge
    const wall_factor = 1.0 - (edge_dist / threshold);
    const height_noise = @sin(pos.x * 19.0 + seed_f) * @sin(pos.z * 23.0) * 20.0 * b.irregularity;

    return b.height * wall_factor + height_noise * wall_factor;
}

fn sampleCrater(pos: NormalizedPos, c: anytype) f32 {
    const dist = pos.distanceTo(c.center);

    if (dist >= c.outer_radius) return 0.0;

    if (dist <= c.inner_radius) {
        // Flat bottom
        return -c.depth;
    }

    // Rim zone
    const rim_start = c.outer_radius - (c.outer_radius - c.inner_radius) * 0.3;
    if (dist >= rim_start) {
        // Raised rim
        const rim_t = (dist - rim_start) / (c.outer_radius - rim_start);
        return c.rim_height * (1.0 - rim_t);
    }

    // Slope from bottom to rim
    const slope_t = (dist - c.inner_radius) / (rim_start - c.inner_radius);
    return -c.depth + (c.depth + c.rim_height) * slope_t;
}

fn sampleCliff(pos: NormalizedPos, c: anytype) f32 {
    // Signed distance to line (positive on one side, negative on other)
    const dx = c.end.x - c.start.x;
    const dz = c.end.z - c.start.z;
    const len = @sqrt(dx * dx + dz * dz);

    if (len < 0.0001) return 0.0;

    // Perpendicular distance (signed)
    const perp_dist = ((pos.x - c.start.x) * (-dz) + (pos.z - c.start.z) * dx) / len;

    // Map to height
    if (perp_dist <= -c.steepness) return 0.0;
    if (perp_dist >= c.steepness) return -c.drop;

    const t = (perp_dist + c.steepness) / (c.steepness * 2.0);
    return -c.drop * t;
}

// === GIS SAMPLING FUNCTIONS ===

fn sampleExternalHeightmap(pos: NormalizedPos, e: anytype) f32 {
    // Map normalized position to source heightmap coordinates
    const src_x = pos.x * @as(f32, @floatFromInt(e.source_width - 1));
    const src_z = pos.z * @as(f32, @floatFromInt(e.source_height - 1));

    const height_value = switch (e.interpolation) {
        .nearest => blk: {
            const ix = @as(usize, @intFromFloat(@round(src_x)));
            const iz = @as(usize, @intFromFloat(@round(src_z)));
            const clamped_x = @min(ix, e.source_width - 1);
            const clamped_z = @min(iz, e.source_height - 1);
            break :blk e.data[clamped_z * e.source_width + clamped_x];
        },
        .bilinear => blk: {
            // Get the four nearest samples
            const x0 = @as(usize, @intFromFloat(@floor(src_x)));
            const z0 = @as(usize, @intFromFloat(@floor(src_z)));
            const x1 = @min(x0 + 1, e.source_width - 1);
            const z1 = @min(z0 + 1, e.source_height - 1);

            // Interpolation weights
            const tx = src_x - @floor(src_x);
            const tz = src_z - @floor(src_z);

            // Sample four corners
            const h00 = e.data[z0 * e.source_width + x0];
            const h10 = e.data[z0 * e.source_width + x1];
            const h01 = e.data[z1 * e.source_width + x0];
            const h11 = e.data[z1 * e.source_width + x1];

            // Bilinear interpolation
            const h0 = h00 * (1.0 - tx) + h10 * tx;
            const h1 = h01 * (1.0 - tx) + h11 * tx;
            break :blk h0 * (1.0 - tz) + h1 * tz;
        },
    };

    return e.base_height + height_value * e.amplitude;
}

fn samplePolygon(pos: NormalizedPos, p: anytype) f32 {
    if (p.vertices.len < 3) return 0.0;

    // Check if point is inside polygon using ray casting
    const inside = pointInPolygon(pos, p.vertices);

    if (p.edge_falloff <= 0.0) {
        // Sharp edges - just return height if inside
        return if (inside) p.height else 0.0;
    }

    // Calculate distance to nearest edge for falloff
    const edge_dist = distanceToPolygonEdge(pos, p.vertices);

    if (inside) {
        // Inside: full height, with falloff near edges
        if (edge_dist < p.edge_falloff) {
            const t = edge_dist / p.edge_falloff;
            return p.height * t; // Ramp up from edge
        }
        return p.height;
    } else {
        // Outside: falloff from edge
        if (edge_dist < p.edge_falloff) {
            const t = 1.0 - (edge_dist / p.edge_falloff);
            return p.height * t; // Ramp down from edge
        }
        return 0.0;
    }
}

fn samplePolyline(pos: NormalizedPos, p: anytype) f32 {
    if (p.points.len < 2) return 0.0;

    // Find minimum distance to any segment
    var min_dist: f32 = std.math.floatMax(f32);

    for (0..p.points.len - 1) |i| {
        const dist = distanceToSegment(pos, p.points[i], p.points[i + 1]);
        min_dist = @min(min_dist, dist);
    }

    if (min_dist >= p.width) return 0.0;

    // Apply falloff
    const t = min_dist / p.width;
    return p.height * p.falloff.apply(t);
}

// === POLYGON HELPER FUNCTIONS ===

/// Point-in-polygon test using ray casting algorithm
fn pointInPolygon(pos: NormalizedPos, vertices: []const NormalizedPos) bool {
    var inside = false;
    const n = vertices.len;

    var j = n - 1;
    for (0..n) |i| {
        const vi = vertices[i];
        const vj = vertices[j];

        // Check if ray from pos going right crosses this edge
        if ((vi.z > pos.z) != (vj.z > pos.z)) {
            // Calculate x coordinate of intersection
            const slope = (vj.x - vi.x) / (vj.z - vi.z);
            const intersect_x = vi.x + slope * (pos.z - vi.z);

            if (pos.x < intersect_x) {
                inside = !inside;
            }
        }
        j = i;
    }

    return inside;
}

/// Calculate minimum distance from point to polygon edge
fn distanceToPolygonEdge(pos: NormalizedPos, vertices: []const NormalizedPos) f32 {
    var min_dist: f32 = std.math.floatMax(f32);
    const n = vertices.len;

    var j = n - 1;
    for (0..n) |i| {
        const dist = distanceToSegment(pos, vertices[j], vertices[i]);
        min_dist = @min(min_dist, dist);
        j = i;
    }

    return min_dist;
}

/// Calculate distance from point to line segment
fn distanceToSegment(pos: NormalizedPos, a: NormalizedPos, b: NormalizedPos) f32 {
    const dx = b.x - a.x;
    const dz = b.z - a.z;
    const len_sq = dx * dx + dz * dz;

    if (len_sq < 0.0001) {
        // Degenerate segment (point)
        return pos.distanceTo(a);
    }

    // Project point onto line, clamped to segment
    const t = @max(0.0, @min(1.0, ((pos.x - a.x) * dx + (pos.z - a.z) * dz) / len_sq));
    const proj = NormalizedPos{
        .x = a.x + t * dx,
        .z = a.z + t * dz,
    };

    return pos.distanceTo(proj);
}

fn applyBlend(existing: f32, new: f32, mode: BlendMode) f32 {
    return switch (mode) {
        .replace => new,
        .add => existing + new,
        .subtract => existing - new,
        .max => @max(existing, new),
        .min => @min(existing, new),
        .multiply => existing * new,
        .smooth_blend => existing * 0.5 + new * 0.5, // Simple average
    };
}

// ============================================================================
// SNOW ZONE PRIMITIVES - Atomic terrain type operations
// ============================================================================

/// An atomic snow zone modification
pub const SnowZonePrimitive = union(enum) {
    /// Fill entire area with terrain type
    fill: struct {
        terrain_type: TerrainType = .packed_snow,
    },

    /// Circular zone of terrain
    circle: struct {
        center: NormalizedPos = .{ .x = 0.5, .z = 0.5 },
        radius: f32 = 0.2,
        terrain_type: TerrainType = .icy_ground,
        falloff_type: ?TerrainType = null, // Optional different type at edges
        falloff_radius: f32 = 0.05,
    },

    /// Rectangular zone
    rect: struct {
        min: NormalizedPos = .{ .x = 0.3, .z = 0.3 },
        max: NormalizedPos = .{ .x = 0.7, .z = 0.7 },
        terrain_type: TerrainType = .cleared_ground,
    },

    /// Path/trail between two points
    path: struct {
        start: NormalizedPos = .{ .x = 0.2, .z = 0.5 },
        end: NormalizedPos = .{ .x = 0.8, .z = 0.5 },
        width: f32 = 0.08,
        terrain_type: TerrainType = .packed_snow,
    },

    /// Noise-based zone distribution
    noise_zones: struct {
        seed: u64 = 0,
        frequency: f32 = 3.0,
        /// Terrain types mapped by noise threshold
        low_terrain: TerrainType = .icy_ground, // noise < -0.3
        mid_terrain: TerrainType = .packed_snow, // -0.3 <= noise < 0.3
        high_terrain: TerrainType = .thick_snow, // noise >= 0.3
    },

    /// Elevation-based zones (reads from heightmap)
    elevation_zones: struct {
        low_threshold: f32 = -10.0,
        high_threshold: f32 = 20.0,
        low_terrain: TerrainType = .icy_ground,
        mid_terrain: TerrainType = .packed_snow,
        high_terrain: TerrainType = .deep_powder,
    },

    /// Ring/donut shape
    ring: struct {
        center: NormalizedPos = .{ .x = 0.5, .z = 0.5 },
        inner_radius: f32 = 0.15,
        outer_radius: f32 = 0.25,
        terrain_type: TerrainType = .slushy,
    },

    pub fn apply(
        self: SnowZonePrimitive,
        cells: []TerrainCell,
        heightmap: []const f32,
        width: usize,
        height: usize,
    ) void {
        for (0..height) |gz| {
            for (0..width) |gx| {
                const idx = gz * width + gx;
                const pos = NormalizedPos{
                    .x = @as(f32, @floatFromInt(gx)) / @as(f32, @floatFromInt(width - 1)),
                    .z = @as(f32, @floatFromInt(gz)) / @as(f32, @floatFromInt(height - 1)),
                };

                if (self.getTerrainAt(pos, heightmap[idx])) |new_type| {
                    cells[idx].type = new_type;
                    // Adjust snow depth based on type
                    cells[idx].snow_depth = switch (new_type) {
                        .cleared_ground => 0.1,
                        .icy_ground => 0.3,
                        .slushy => 0.5,
                        .packed_snow => 0.8,
                        .thick_snow => 1.2,
                        .deep_powder => 1.8,
                    };
                }
            }
        }
    }

    /// Get terrain type at position (null = don't modify)
    pub fn getTerrainAt(self: SnowZonePrimitive, pos: NormalizedPos, elevation: f32) ?TerrainType {
        return switch (self) {
            .fill => |f| f.terrain_type,
            .circle => |c| getCircleTerrain(pos, c),
            .rect => |r| getRectTerrain(pos, r),
            .path => |p| getPathTerrain(pos, p),
            .noise_zones => |n| getNoiseTerrain(pos, n),
            .elevation_zones => |e| getElevationTerrain(elevation, e),
            .ring => |r| getRingTerrain(pos, r),
        };
    }
};

fn getCircleTerrain(pos: NormalizedPos, c: anytype) ?TerrainType {
    const dist = pos.distanceTo(c.center);

    if (dist <= c.radius) return c.terrain_type;

    if (c.falloff_type) |falloff_terrain| {
        if (dist <= c.radius + c.falloff_radius) {
            return falloff_terrain;
        }
    }

    return null;
}

fn getRectTerrain(pos: NormalizedPos, r: anytype) ?TerrainType {
    if (pos.x >= r.min.x and pos.x <= r.max.x and
        pos.z >= r.min.z and pos.z <= r.max.z)
    {
        return r.terrain_type;
    }
    return null;
}

fn getPathTerrain(pos: NormalizedPos, p: anytype) ?TerrainType {
    const dx = p.end.x - p.start.x;
    const dz = p.end.z - p.start.z;
    const len_sq = dx * dx + dz * dz;

    if (len_sq < 0.0001) return null;

    const t = @max(0.0, @min(1.0, ((pos.x - p.start.x) * dx + (pos.z - p.start.z) * dz) / len_sq));
    const proj_x = p.start.x + t * dx;
    const proj_z = p.start.z + t * dz;

    const dist = @sqrt((pos.x - proj_x) * (pos.x - proj_x) + (pos.z - proj_z) * (pos.z - proj_z));

    if (dist <= p.width) return p.terrain_type;
    return null;
}

fn getNoiseTerrain(pos: NormalizedPos, n: anytype) ?TerrainType {
    const seed_f = @as(f32, @floatFromInt(n.seed));
    const noise = @sin(pos.x * n.frequency * std.math.pi + seed_f) *
        @cos(pos.z * n.frequency * std.math.pi + seed_f * 0.7);

    if (noise < -0.3) return n.low_terrain;
    if (noise < 0.3) return n.mid_terrain;
    return n.high_terrain;
}

fn getElevationTerrain(elevation: f32, e: anytype) ?TerrainType {
    if (elevation < e.low_threshold) return e.low_terrain;
    if (elevation < e.high_threshold) return e.mid_terrain;
    return e.high_terrain;
}

fn getRingTerrain(pos: NormalizedPos, r: anytype) ?TerrainType {
    const dist = pos.distanceTo(r.center);
    if (dist >= r.inner_radius and dist <= r.outer_radius) {
        return r.terrain_type;
    }
    return null;
}

// ============================================================================
// ARENA RECIPE - A complete arena definition
// ============================================================================

/// Maximum primitives per layer
pub const MAX_ELEVATION_PRIMITIVES = 16;
pub const MAX_SNOW_ZONE_PRIMITIVES = 16;
pub const MAX_PROP_PLACEMENTS = 32;
pub const MAX_COLLECTION_PLACEMENTS = 8;

/// A complete arena recipe composed of layered primitives
pub const ArenaRecipe = struct {
    name: [:0]const u8 = "Unnamed Arena",

    /// Elevation primitives applied in order
    elevation_ops: []const ElevationOp = &[_]ElevationOp{},

    /// Snow zone primitives applied in order
    snow_ops: []const SnowZonePrimitive = &[_]SnowZonePrimitive{},

    /// Individual prop placements
    prop_placements: []const PropPlacement = &[_]PropPlacement{},

    /// Prop collection placements (groups of props)
    collection_placements: []const CollectionPlacement = &[_]CollectionPlacement{},

    /// Final smoothing passes for heightmap
    smoothing_passes: u8 = 2,

    /// Seed for procedural elements
    seed: u64 = 0,
};

/// Elevation operation with blend mode
pub const ElevationOp = struct {
    primitive: ElevationPrimitive,
    blend: BlendMode = .add,
};

// ============================================================================
// SUBURBAN ARENA TEMPLATES - The endless neighborhood warzone
// ============================================================================
// These templates represent typical suburban locations where snowball
// battles take place. Each has distinct tactical characteristics.

// ----------------------------------------------------------------------------
// CUL-DE-SAC - Dead end street with houses around the curve
// Tactical: Central open area, elevated yards on perimeter, one exit
// ----------------------------------------------------------------------------
pub const template_cul_de_sac = ArenaRecipe{
    .name = "Cul-de-Sac",
    .elevation_ops = &[_]ElevationOp{
        // Flat street base
        .{ .primitive = .{ .flat = .{ .height = 0.0 } }, .blend = .replace },
        // Raised yards around the curve (the "houses" side) - using mounds
        .{
            .primitive = .{
                .mound = .{
                    .center = .{ .x = 0.2, .z = 0.3 },
                    .radius = 0.15,
                    .height = 12.0, // Elevated front yard
                    .falloff = .plateau,
                },
            },
            .blend = .add,
        },
        .{ .primitive = .{ .mound = .{
            .center = .{ .x = 0.8, .z = 0.3 },
            .radius = 0.15,
            .height = 12.0,
            .falloff = .plateau,
        } }, .blend = .add },
        .{ .primitive = .{ .mound = .{
            .center = .{ .x = 0.2, .z = 0.7 },
            .radius = 0.15,
            .height = 12.0,
            .falloff = .plateau,
        } }, .blend = .add },
        .{ .primitive = .{ .mound = .{
            .center = .{ .x = 0.8, .z = 0.7 },
            .radius = 0.15,
            .height = 12.0,
            .falloff = .plateau,
        } }, .blend = .add },
        // Entry street depression
        .{
            .primitive = .{
                .ridge = .{
                    .start = .{ .x = 0.5, .z = 0.0 },
                    .end = .{ .x = 0.5, .z = 0.35 },
                    .width = 0.12,
                    .height = -3.0, // Slightly lower street
                },
            },
            .blend = .add,
        },
        // Snowdrift boundary (represents fences, hedges, deeper yards)
        .{ .primitive = .{ .boundary_wall = .{ .height = 50.0, .thickness = 0.06, .irregularity = 0.7 } }, .blend = .max },
    },
    .snow_ops = &[_]SnowZonePrimitive{
        // Yards have thicker snow (less traffic)
        .{ .fill = .{ .terrain_type = .thick_snow } },
        // Street is packed from cars/walking
        .{ .path = .{ .start = .{ .x = 0.5, .z = 0.0 }, .end = .{ .x = 0.5, .z = 0.4 }, .width = 0.1, .terrain_type = .packed_snow } },
        // Central turnaround is icy (cars turning)
        .{ .circle = .{ .center = .{ .x = 0.5, .z = 0.5 }, .radius = 0.18, .terrain_type = .icy_ground } },
        // Driveways are cleared/packed
        .{ .path = .{ .start = .{ .x = 0.2, .z = 0.3 }, .end = .{ .x = 0.35, .z = 0.45 }, .width = 0.06, .terrain_type = .cleared_ground } },
        .{ .path = .{ .start = .{ .x = 0.8, .z = 0.3 }, .end = .{ .x = 0.65, .z = 0.45 }, .width = 0.06, .terrain_type = .cleared_ground } },
    },
    // Props: parked cars, mailboxes, yard stuff
    .collection_placements = &[_]CollectionPlacement{
        .{ .collection = &props.collection_driveway, .position = .{ .x = 0.2, .z = 0.35 }, .rotation = 0.5 },
        .{ .collection = &props.collection_driveway, .position = .{ .x = 0.8, .z = 0.35 }, .rotation = -0.5 },
        .{ .collection = &props.collection_front_yard, .position = .{ .x = 0.15, .z = 0.25 } },
        .{ .collection = &props.collection_front_yard, .position = .{ .x = 0.85, .z = 0.25 } },
        .{ .collection = &props.collection_snowman_family, .position = .{ .x = 0.5, .z = 0.6 } },
    },
    .prop_placements = &[_]PropPlacement{
        // Street lamp at entrance
        .{ .prop_type = .lamppost, .position = .{ .x = 0.4, .z = 0.15 } },
        .{ .prop_type = .lamppost, .position = .{ .x = 0.6, .z = 0.15 } },
        // Trash bins out for pickup
        .{ .prop_type = .trash_can, .position = .{ .x = 0.35, .z = 0.4 } },
        .{ .prop_type = .recycling_bin, .position = .{ .x = 0.36, .z = 0.42 } },
    },
    .smoothing_passes = 2,
};

// ----------------------------------------------------------------------------
// SCHOOL YARD - Open field with playground equipment areas
// Tactical: Large open center, equipment provides cover on sides
// ----------------------------------------------------------------------------
pub const template_school_yard = ArenaRecipe{
    .name = "School Yard",
    .elevation_ops = &[_]ElevationOp{
        // Mostly flat - school yards are leveled
        .{ .primitive = .{ .flat = .{ .height = 0.0 } }, .blend = .replace },
        // Gentle slope toward one side (drainage)
        .{ .primitive = .{ .ramp = .{
            .start = .{ .x = 0.0, .z = 0.5 },
            .end = .{ .x = 1.0, .z = 0.5 },
            .width = 0.5,
            .start_height = 3.0,
            .end_height = -3.0,
        } }, .blend = .add },
        // Playground mound (slides, jungle gym base)
        .{ .primitive = .{ .mound = .{
            .center = .{ .x = 0.25, .z = 0.75 },
            .radius = 0.12,
            .height = 15.0,
            .falloff = .plateau,
        } }, .blend = .add },
        // Baseball backstop area (raised pitcher's mound feel)
        .{ .primitive = .{ .mound = .{
            .center = .{ .x = 0.75, .z = 0.25 },
            .radius = 0.08,
            .height = 5.0,
            .falloff = .smooth,
        } }, .blend = .add },
        // School building wall (one edge is the school)
        .{
            .primitive = .{
                .ridge = .{
                    .start = .{ .x = 0.0, .z = 0.9 },
                    .end = .{ .x = 1.0, .z = 0.9 },
                    .width = 0.08,
                    .height = 40.0, // Impassable - it's the school
                },
            },
            .blend = .max,
        },
        // Fence boundaries
        .{ .primitive = .{ .boundary_wall = .{ .height = 45.0, .thickness = 0.05, .irregularity = 0.3 } }, .blend = .max },
    },
    .snow_ops = &[_]SnowZonePrimitive{
        // Main field is packed from constant use
        .{ .fill = .{ .terrain_type = .packed_snow } },
        // Playground area has deep powder (kids playing, digging)
        .{ .circle = .{ .center = .{ .x = 0.25, .z = 0.75 }, .radius = 0.15, .terrain_type = .thick_snow } },
        // Baseball diamond area is icy (wind-swept, packed)
        .{ .circle = .{ .center = .{ .x = 0.75, .z = 0.35 }, .radius = 0.2, .terrain_type = .icy_ground } },
        // Entry paths from school doors
        .{ .path = .{ .start = .{ .x = 0.3, .z = 0.9 }, .end = .{ .x = 0.3, .z = 0.5 }, .width = 0.08, .terrain_type = .cleared_ground } },
        .{ .path = .{ .start = .{ .x = 0.7, .z = 0.9 }, .end = .{ .x = 0.7, .z = 0.5 }, .width = 0.08, .terrain_type = .cleared_ground } },
    },
    // Props: playground equipment and benches
    .collection_placements = &[_]CollectionPlacement{
        .{ .collection = &props.collection_playground_full, .position = .{ .x = 0.25, .z = 0.75 } },
        .{ .collection = &props.collection_bus_stop, .position = .{ .x = 0.15, .z = 0.5 } },
    },
    .prop_placements = &[_]PropPlacement{
        // Basketball hoop by the field
        .{ .prop_type = .basketball_hoop, .position = .{ .x = 0.65, .z = 0.6 } },
        // Benches along the path
        .{ .prop_type = .bench_park, .position = .{ .x = 0.4, .z = 0.7 }, .rotation = 1.57 },
        .{ .prop_type = .bench_park, .position = .{ .x = 0.6, .z = 0.7 }, .rotation = 1.57 },
        // Trash cans
        .{ .prop_type = .trash_can, .position = .{ .x = 0.35, .z = 0.85 } },
        .{ .prop_type = .trash_can, .position = .{ .x = 0.65, .z = 0.85 } },
        // Backstop area - could have a bench
        .{ .prop_type = .bench_park, .position = .{ .x = 0.85, .z = 0.25 } },
    },
    .smoothing_passes = 1,
};

// ----------------------------------------------------------------------------
// SNOWY STREET - Linear street with parked cars (as snow mounds) and yards
// Tactical: Long sightlines, cover on sides, flanking through yards
// ----------------------------------------------------------------------------
pub const template_snowy_street = ArenaRecipe{
    .name = "Snowy Street",
    .elevation_ops = &[_]ElevationOp{
        // Street is slightly depressed
        .{ .primitive = .{ .ridge = .{
            .start = .{ .x = 0.5, .z = 0.0 },
            .end = .{ .x = 0.5, .z = 1.0 },
            .width = 0.15,
            .height = -4.0,
        } }, .blend = .add },
        // Sidewalks/yards on both sides (elevated)
        .{ .primitive = .{ .ridge = .{
            .start = .{ .x = 0.2, .z = 0.0 },
            .end = .{ .x = 0.2, .z = 1.0 },
            .width = 0.15,
            .height = 6.0,
        } }, .blend = .add },
        .{ .primitive = .{ .ridge = .{
            .start = .{ .x = 0.8, .z = 0.0 },
            .end = .{ .x = 0.8, .z = 1.0 },
            .width = 0.15,
            .height = 6.0,
        } }, .blend = .add },
        // Parked cars (snow-covered lumps) - cover!
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.38, .z = 0.2 }, .radius = 0.06, .height = 10.0, .falloff = .smooth } }, .blend = .add },
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.62, .z = 0.35 }, .radius = 0.06, .height = 10.0, .falloff = .smooth } }, .blend = .add },
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.38, .z = 0.5 }, .radius = 0.06, .height = 10.0, .falloff = .smooth } }, .blend = .add },
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.62, .z = 0.65 }, .radius = 0.06, .height = 10.0, .falloff = .smooth } }, .blend = .add },
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.38, .z = 0.8 }, .radius = 0.06, .height = 10.0, .falloff = .smooth } }, .blend = .add },
        // House walls at edges
        .{ .primitive = .{ .boundary_wall = .{ .height = 55.0, .thickness = 0.06, .irregularity = 0.4 } }, .blend = .max },
    },
    .snow_ops = &[_]SnowZonePrimitive{
        // Yards have fresh snow
        .{ .fill = .{ .terrain_type = .thick_snow } },
        // Street is packed/plowed
        .{ .path = .{ .start = .{ .x = 0.5, .z = 0.0 }, .end = .{ .x = 0.5, .z = 1.0 }, .width = 0.12, .terrain_type = .packed_snow } },
        // Tire tracks are icy
        .{ .path = .{ .start = .{ .x = 0.45, .z = 0.0 }, .end = .{ .x = 0.45, .z = 1.0 }, .width = 0.03, .terrain_type = .icy_ground } },
        .{ .path = .{ .start = .{ .x = 0.55, .z = 0.0 }, .end = .{ .x = 0.55, .z = 1.0 }, .width = 0.03, .terrain_type = .icy_ground } },
        // Sidewalks are shoveled
        .{ .path = .{ .start = .{ .x = 0.28, .z = 0.0 }, .end = .{ .x = 0.28, .z = 1.0 }, .width = 0.04, .terrain_type = .cleared_ground } },
        .{ .path = .{ .start = .{ .x = 0.72, .z = 0.0 }, .end = .{ .x = 0.72, .z = 1.0 }, .width = 0.04, .terrain_type = .cleared_ground } },
    },
    // Props: parked cars (the snow mounds), mailboxes, lampposts
    .collection_placements = &[_]CollectionPlacement{
        .{ .collection = &props.collection_front_yard, .position = .{ .x = 0.15, .z = 0.25 } },
        .{ .collection = &props.collection_front_yard, .position = .{ .x = 0.85, .z = 0.25 } },
        .{ .collection = &props.collection_front_yard, .position = .{ .x = 0.15, .z = 0.75 } },
        .{ .collection = &props.collection_front_yard, .position = .{ .x = 0.85, .z = 0.75 } },
    },
    .prop_placements = &[_]PropPlacement{
        // Lampposts along the street
        .{ .prop_type = .lamppost, .position = .{ .x = 0.35, .z = 0.1 } },
        .{ .prop_type = .lamppost, .position = .{ .x = 0.65, .z = 0.3 } },
        .{ .prop_type = .lamppost, .position = .{ .x = 0.35, .z = 0.5 } },
        .{ .prop_type = .lamppost, .position = .{ .x = 0.65, .z = 0.7 } },
        .{ .prop_type = .lamppost, .position = .{ .x = 0.35, .z = 0.9 } },
        // Mailboxes on yards
        .{ .prop_type = .mailbox, .position = .{ .x = 0.25, .z = 0.2 } },
        .{ .prop_type = .mailbox, .position = .{ .x = 0.75, .z = 0.4 } },
        .{ .prop_type = .mailbox, .position = .{ .x = 0.25, .z = 0.6 } },
        .{ .prop_type = .mailbox, .position = .{ .x = 0.75, .z = 0.8 } },
        // Trash bins out for collection
        .{ .prop_type = .trash_can, .position = .{ .x = 0.32, .z = 0.25 } },
        .{ .prop_type = .recycling_bin, .position = .{ .x = 0.33, .z = 0.27 } },
        .{ .prop_type = .trash_can, .position = .{ .x = 0.68, .z = 0.55 } },
    },
    .smoothing_passes = 2,
};

// ----------------------------------------------------------------------------
// COURTYARD - Apartment complex courtyard, enclosed on multiple sides
// Tactical: Enclosed space, multiple entry points, elevated balcony areas
// ----------------------------------------------------------------------------
pub const template_courtyard = ArenaRecipe{
    .name = "Courtyard",
    .elevation_ops = &[_]ElevationOp{
        // Flat central courtyard
        .{ .primitive = .{ .flat = .{ .height = 0.0 } }, .blend = .replace },
        // Building walls on three sides (tall, impassable)
        .{ .primitive = .{ .ridge = .{
            .start = .{ .x = 0.0, .z = 0.1 },
            .end = .{ .x = 0.0, .z = 0.9 },
            .width = 0.08,
            .height = 60.0,
        } }, .blend = .max },
        .{ .primitive = .{ .ridge = .{
            .start = .{ .x = 1.0, .z = 0.1 },
            .end = .{ .x = 1.0, .z = 0.9 },
            .width = 0.08,
            .height = 60.0,
        } }, .blend = .max },
        .{ .primitive = .{ .ridge = .{
            .start = .{ .x = 0.1, .z = 1.0 },
            .end = .{ .x = 0.9, .z = 1.0 },
            .width = 0.08,
            .height = 60.0,
        } }, .blend = .max },
        // Small landscaping mounds (bushes under snow)
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.25, .z = 0.25 }, .radius = 0.08, .height = 8.0, .falloff = .smooth } }, .blend = .add },
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.75, .z = 0.25 }, .radius = 0.08, .height = 8.0, .falloff = .smooth } }, .blend = .add },
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.25, .z = 0.75 }, .radius = 0.08, .height = 8.0, .falloff = .smooth } }, .blend = .add },
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.75, .z = 0.75 }, .radius = 0.08, .height = 8.0, .falloff = .smooth } }, .blend = .add },
        // Central feature (fountain/statue base under snow)
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.5, .z = 0.5 }, .radius = 0.1, .height = 12.0, .falloff = .plateau } }, .blend = .add },
        // Open entrance side
        .{ .primitive = .{ .boundary_wall = .{ .height = 40.0, .thickness = 0.04, .irregularity = 0.2 } }, .blend = .max },
    },
    .snow_ops = &[_]SnowZonePrimitive{
        // Courtyard gets foot traffic
        .{ .fill = .{ .terrain_type = .packed_snow } },
        // Building entrances are cleared
        .{ .rect = .{ .min = .{ .x = 0.08, .z = 0.4 }, .max = .{ .x = 0.15, .z = 0.6 }, .terrain_type = .cleared_ground } },
        .{ .rect = .{ .min = .{ .x = 0.85, .z = 0.4 }, .max = .{ .x = 0.92, .z = 0.6 }, .terrain_type = .cleared_ground } },
        // Main path through
        .{ .path = .{ .start = .{ .x = 0.5, .z = 0.0 }, .end = .{ .x = 0.5, .z = 0.5 }, .width = 0.08, .terrain_type = .cleared_ground } },
        // Landscaping areas are undisturbed
        .{ .circle = .{ .center = .{ .x = 0.25, .z = 0.25 }, .radius = 0.1, .terrain_type = .thick_snow } },
        .{ .circle = .{ .center = .{ .x = 0.75, .z = 0.25 }, .radius = 0.1, .terrain_type = .thick_snow } },
        .{ .circle = .{ .center = .{ .x = 0.25, .z = 0.75 }, .radius = 0.1, .terrain_type = .thick_snow } },
        .{ .circle = .{ .center = .{ .x = 0.75, .z = 0.75 }, .radius = 0.1, .terrain_type = .thick_snow } },
    },
    // Props: benches, lampposts, decorative elements
    .collection_placements = &[_]CollectionPlacement{
        // Tree clusters in landscaping areas
        .{ .collection = &props.collection_tree_cluster, .position = .{ .x = 0.25, .z = 0.25 }, .scale = 0.8 },
        .{ .collection = &props.collection_tree_cluster, .position = .{ .x = 0.75, .z = 0.75 }, .scale = 0.8 },
    },
    .prop_placements = &[_]PropPlacement{
        // Central fountain/statue (covered in snow)
        .{ .prop_type = .lawn_ornament, .position = .{ .x = 0.5, .z = 0.5 }, .scale = 2.0 },
        // Benches around the courtyard
        .{ .prop_type = .bench_park, .position = .{ .x = 0.35, .z = 0.5 }, .rotation = 1.57 },
        .{ .prop_type = .bench_park, .position = .{ .x = 0.65, .z = 0.5 }, .rotation = -1.57 },
        .{ .prop_type = .bench_park, .position = .{ .x = 0.5, .z = 0.35 } },
        .{ .prop_type = .bench_park, .position = .{ .x = 0.5, .z = 0.65 }, .rotation = 3.14 },
        // Lampposts at corners
        .{ .prop_type = .lamppost, .position = .{ .x = 0.15, .z = 0.15 } },
        .{ .prop_type = .lamppost, .position = .{ .x = 0.85, .z = 0.15 } },
        .{ .prop_type = .lamppost, .position = .{ .x = 0.15, .z = 0.85 } },
        .{ .prop_type = .lamppost, .position = .{ .x = 0.85, .z = 0.85 } },
        // Trash cans near entrances
        .{ .prop_type = .trash_can, .position = .{ .x = 0.12, .z = 0.5 } },
        .{ .prop_type = .trash_can, .position = .{ .x = 0.88, .z = 0.5 } },
        // Bushes in landscaping
        .{ .prop_type = .bush_snow_covered, .position = .{ .x = 0.75, .z = 0.25 } },
        .{ .prop_type = .bush_snow_covered, .position = .{ .x = 0.25, .z = 0.75 } },
    },
    .smoothing_passes = 1,
};

// ----------------------------------------------------------------------------
// FOREST CLEARING - Open area surrounded by trees (tall snow drifts)
// Tactical: Circular arena, tree cover on perimeter, natural terrain
// ----------------------------------------------------------------------------
pub const template_forest_clearing = ArenaRecipe{
    .name = "Forest Clearing",
    .elevation_ops = &[_]ElevationOp{
        // Natural undulating terrain
        .{ .primitive = .{ .noise = .{ .amplitude = 8.0, .frequency = 2.5, .octaves = 3, .seed = 42 } }, .blend = .add },
        // Central clearing is flatter
        .{ .primitive = .{ .arena_flatten = .{ .center = .{ .x = 0.5, .z = 0.5 }, .radius = 0.3, .strength = 0.6 } }, .blend = .smooth_blend },
        // Fallen log (long low mound)
        .{ .primitive = .{ .ridge = .{
            .start = .{ .x = 0.3, .z = 0.6 },
            .end = .{ .x = 0.6, .z = 0.7 },
            .width = 0.04,
            .height = 8.0,
        } }, .blend = .add },
        // Tree stumps / snow-covered rocks
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.35, .z = 0.35 }, .radius = 0.05, .height = 6.0, .falloff = .sharp } }, .blend = .add },
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.7, .z = 0.4 }, .radius = 0.04, .height = 5.0, .falloff = .sharp } }, .blend = .add },
        // Forest edge (trees = tall irregular boundary)
        .{ .primitive = .{ .boundary_wall = .{ .height = 70.0, .thickness = 0.1, .irregularity = 0.9, .seed = 123 } }, .blend = .max },
    },
    .snow_ops = &[_]SnowZonePrimitive{
        // Forest floor has deep powder (sheltered)
        .{ .fill = .{ .terrain_type = .deep_powder } },
        // Clearing has some packing from activity
        .{ .circle = .{ .center = .{ .x = 0.5, .z = 0.5 }, .radius = 0.25, .terrain_type = .thick_snow } },
        // Animal trails / paths through
        .{ .path = .{ .start = .{ .x = 0.1, .z = 0.3 }, .end = .{ .x = 0.5, .z = 0.5 }, .width = 0.04, .terrain_type = .packed_snow } },
        .{ .path = .{ .start = .{ .x = 0.9, .z = 0.7 }, .end = .{ .x = 0.5, .z = 0.5 }, .width = 0.04, .terrain_type = .packed_snow } },
        // Icy patch where snow melted and refroze (stream bed?)
        .{ .path = .{ .start = .{ .x = 0.2, .z = 0.8 }, .end = .{ .x = 0.4, .z = 0.2 }, .width = 0.06, .terrain_type = .icy_ground } },
    },
    // Props: trees, fallen logs, rocks, stumps - natural forest debris
    .collection_placements = &[_]CollectionPlacement{
        // Tree clusters around the perimeter
        .{ .collection = &props.collection_tree_cluster, .position = .{ .x = 0.15, .z = 0.2 } },
        .{ .collection = &props.collection_tree_cluster, .position = .{ .x = 0.85, .z = 0.3 } },
        .{ .collection = &props.collection_tree_cluster, .position = .{ .x = 0.2, .z = 0.8 } },
        .{ .collection = &props.collection_tree_cluster, .position = .{ .x = 0.8, .z = 0.75 } },
        // Fallen tree for cover
        .{ .collection = &props.collection_fallen_tree, .position = .{ .x = 0.45, .z = 0.65 }, .rotation = 0.4 },
        // Rocky outcrop
        .{ .collection = &props.collection_rocks, .position = .{ .x = 0.7, .z = 0.4 } },
    },
    .prop_placements = &[_]PropPlacement{
        // Additional scattered trees
        .{ .prop_type = .pine_tree_large, .position = .{ .x = 0.1, .z = 0.5 } },
        .{ .prop_type = .pine_tree_medium, .position = .{ .x = 0.9, .z = 0.5 } },
        .{ .prop_type = .pine_tree_small, .position = .{ .x = 0.5, .z = 0.1 } },
        .{ .prop_type = .bare_tree, .position = .{ .x = 0.5, .z = 0.85 } },
        // Stumps from felled trees
        .{ .prop_type = .stump, .position = .{ .x = 0.35, .z = 0.35 } },
        .{ .prop_type = .stump, .position = .{ .x = 0.65, .z = 0.55 } },
        // Snow-covered bushes
        .{ .prop_type = .bush_snow_covered, .position = .{ .x = 0.25, .z = 0.45 } },
        .{ .prop_type = .bush_snow_covered, .position = .{ .x = 0.75, .z = 0.6 } },
        .{ .prop_type = .bush_snow_covered, .position = .{ .x = 0.4, .z = 0.25 } },
        // Small rocks scattered
        .{ .prop_type = .rock_small, .position = .{ .x = 0.55, .z = 0.45 } },
        .{ .prop_type = .rock_small, .position = .{ .x = 0.3, .z = 0.6 } },
        .{ .prop_type = .rock_medium, .position = .{ .x = 0.6, .z = 0.3 } },
    },
    .smoothing_passes = 2,
};

// ----------------------------------------------------------------------------
// PARKING LOT - Wide open space with car mounds in rows
// Tactical: Grid-based cover, long sightlines between rows
// ----------------------------------------------------------------------------
pub const template_parking_lot = ArenaRecipe{
    .name = "Parking Lot",
    .elevation_ops = &[_]ElevationOp{
        // Flat asphalt base
        .{ .primitive = .{ .flat = .{ .height = 0.0 } }, .blend = .replace },
        // Slight crown in center for drainage
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.5, .z = 0.5 }, .radius = 0.5, .height = 2.0, .falloff = .linear } }, .blend = .add },
        // Row 1 of parked cars
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.2, .z = 0.25 }, .radius = 0.06, .height = 10.0, .falloff = .smooth } }, .blend = .add },
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.4, .z = 0.25 }, .radius = 0.06, .height = 10.0, .falloff = .smooth } }, .blend = .add },
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.6, .z = 0.25 }, .radius = 0.06, .height = 10.0, .falloff = .smooth } }, .blend = .add },
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.8, .z = 0.25 }, .radius = 0.06, .height = 10.0, .falloff = .smooth } }, .blend = .add },
        // Row 2 of parked cars
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.2, .z = 0.75 }, .radius = 0.06, .height = 10.0, .falloff = .smooth } }, .blend = .add },
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.4, .z = 0.75 }, .radius = 0.06, .height = 10.0, .falloff = .smooth } }, .blend = .add },
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.6, .z = 0.75 }, .radius = 0.06, .height = 10.0, .falloff = .smooth } }, .blend = .add },
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.8, .z = 0.75 }, .radius = 0.06, .height = 10.0, .falloff = .smooth } }, .blend = .add },
        // Light pole bases
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.15, .z = 0.5 }, .radius = 0.03, .height = 4.0, .falloff = .sharp } }, .blend = .add },
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.85, .z = 0.5 }, .radius = 0.03, .height = 4.0, .falloff = .sharp } }, .blend = .add },
        // Store wall on one side
        .{ .primitive = .{ .ridge = .{
            .start = .{ .x = 0.0, .z = 0.0 },
            .end = .{ .x = 0.0, .z = 1.0 },
            .width = 0.06,
            .height = 50.0,
        } }, .blend = .max },
        // Snow plow berms at edges
        .{ .primitive = .{ .boundary_wall = .{ .height = 35.0, .thickness = 0.05, .irregularity = 0.6 } }, .blend = .max },
    },
    .snow_ops = &[_]SnowZonePrimitive{
        // Lot is mostly packed/plowed
        .{ .fill = .{ .terrain_type = .packed_snow } },
        // Driving lanes are icy
        .{ .path = .{ .start = .{ .x = 0.0, .z = 0.5 }, .end = .{ .x = 1.0, .z = 0.5 }, .width = 0.1, .terrain_type = .icy_ground } },
        // Parking spots have some accumulation
        .{ .rect = .{ .min = .{ .x = 0.15, .z = 0.15 }, .max = .{ .x = 0.85, .z = 0.35 }, .terrain_type = .thick_snow } },
        .{ .rect = .{ .min = .{ .x = 0.15, .z = 0.65 }, .max = .{ .x = 0.85, .z = 0.85 }, .terrain_type = .thick_snow } },
        // Handicap spots are cleared
        .{ .rect = .{ .min = .{ .x = 0.02, .z = 0.4 }, .max = .{ .x = 0.12, .z = 0.6 }, .terrain_type = .cleared_ground } },
    },
    // Props: parked cars in rows, shopping carts, dumpster, light poles
    .collection_placements = &[_]CollectionPlacement{
        // Row 1 parking cluster
        .{ .collection = &props.collection_parking_cluster, .position = .{ .x = 0.3, .z = 0.25 } },
        .{ .collection = &props.collection_parking_cluster, .position = .{ .x = 0.7, .z = 0.25 } },
        // Row 2 parking cluster
        .{ .collection = &props.collection_parking_cluster, .position = .{ .x = 0.3, .z = 0.75 } },
        .{ .collection = &props.collection_parking_cluster, .position = .{ .x = 0.7, .z = 0.75 } },
    },
    .prop_placements = &[_]PropPlacement{
        // Light poles
        .{ .prop_type = .lamppost, .position = .{ .x = 0.15, .z = 0.5 } },
        .{ .prop_type = .lamppost, .position = .{ .x = 0.85, .z = 0.5 } },
        .{ .prop_type = .lamppost, .position = .{ .x = 0.5, .z = 0.15 } },
        .{ .prop_type = .lamppost, .position = .{ .x = 0.5, .z = 0.85 } },
        // Dumpster near store
        .{ .prop_type = .dumpster, .position = .{ .x = 0.08, .z = 0.2 } },
        // Shopping cart return (just carts scattered)
        .{ .prop_type = .wagon, .position = .{ .x = 0.5, .z = 0.5 } },
        .{ .prop_type = .wagon, .position = .{ .x = 0.52, .z = 0.48 } },
        // Snow piles from plowing
        .{ .prop_type = .snow_pile_large, .position = .{ .x = 0.92, .z = 0.15 } },
        .{ .prop_type = .snow_pile_large, .position = .{ .x = 0.92, .z = 0.85 } },
        .{ .prop_type = .snow_pile_small, .position = .{ .x = 0.08, .z = 0.85 } },
        // Concrete barriers at entrance
        .{ .prop_type = .barrier_concrete, .position = .{ .x = 0.08, .z = 0.35 } },
        .{ .prop_type = .barrier_concrete, .position = .{ .x = 0.08, .z = 0.65 } },
    },
    .smoothing_passes = 1,
};

// ----------------------------------------------------------------------------
// BACKYARD - Someone's backyard with a fort, swing set, and shed
// Tactical: Intimate space, built cover, home field advantage
// ----------------------------------------------------------------------------
pub const template_backyard = ArenaRecipe{
    .name = "Backyard",
    .elevation_ops = &[_]ElevationOp{
        // Gentle yard slope
        .{
            .primitive = .{
                .ramp = .{
                    .start = .{ .x = 0.5, .z = 1.0 },
                    .end = .{ .x = 0.5, .z = 0.0 },
                    .width = 0.6,
                    .start_height = 5.0, // House side higher
                    .end_height = 0.0,
                },
            },
            .blend = .add,
        },
        // Snow fort! (the prize)
        .{ .primitive = .{ .plateau = .{
            .min = .{ .x = 0.6, .z = 0.6 },
            .max = .{ .x = 0.85, .z = 0.85 },
            .height = 18.0,
            .edge_falloff = 0.03,
        } }, .blend = .add },
        // Swing set mound
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.25, .z = 0.4 }, .radius = 0.1, .height = 4.0, .falloff = .smooth } }, .blend = .add },
        // Shed
        .{ .primitive = .{ .plateau = .{
            .min = .{ .x = 0.1, .z = 0.75 },
            .max = .{ .x = 0.25, .z = 0.9 },
            .height = 25.0,
            .edge_falloff = 0.02,
        } }, .blend = .add },
        // House wall (back of yard)
        .{ .primitive = .{ .ridge = .{
            .start = .{ .x = 0.0, .z = 0.95 },
            .end = .{ .x = 1.0, .z = 0.95 },
            .width = 0.05,
            .height = 60.0,
        } }, .blend = .max },
        // Fence boundaries
        .{ .primitive = .{ .boundary_wall = .{ .height = 40.0, .thickness = 0.04, .irregularity = 0.3 } }, .blend = .max },
    },
    .snow_ops = &[_]SnowZonePrimitive{
        // Yard has good snow coverage
        .{ .fill = .{ .terrain_type = .thick_snow } },
        // Path from house to fort
        .{ .path = .{ .start = .{ .x = 0.5, .z = 0.95 }, .end = .{ .x = 0.7, .z = 0.6 }, .width = 0.06, .terrain_type = .packed_snow } },
        // Fort interior is packed from building
        .{ .rect = .{ .min = .{ .x = 0.62, .z = 0.62 }, .max = .{ .x = 0.83, .z = 0.83 }, .terrain_type = .packed_snow } },
        // Under swing set is icy (worn down)
        .{ .circle = .{ .center = .{ .x = 0.25, .z = 0.4 }, .radius = 0.08, .terrain_type = .icy_ground } },
        // Patio area by house
        .{ .rect = .{ .min = .{ .x = 0.35, .z = 0.85 }, .max = .{ .x = 0.65, .z = 0.95 }, .terrain_type = .cleared_ground } },
    },
    // Props: snow fort, shed, swing set, grill, outdoor furniture
    .collection_placements = &[_]CollectionPlacement{
        // The epic snow fort
        .{ .collection = &props.collection_snow_fort_elaborate, .position = .{ .x = 0.72, .z = 0.72 } },
        // Backyard amenities near the patio
        .{ .collection = &props.collection_backyard, .position = .{ .x = 0.5, .z = 0.85 }, .scale = 0.8 },
    },
    .prop_placements = &[_]PropPlacement{
        // Swing set
        .{ .prop_type = .swing_set, .position = .{ .x = 0.25, .z = 0.4 } },
        // Shed in corner
        .{ .prop_type = .shed_small, .position = .{ .x = 0.15, .z = 0.82 } },
        // Kid's toys scattered
        .{ .prop_type = .parked_sled, .position = .{ .x = 0.4, .z = 0.5 } },
        .{ .prop_type = .wagon, .position = .{ .x = 0.55, .z = 0.45 } },
        // Fence sections along property line
        .{ .prop_type = .wooden_fence_section, .position = .{ .x = 0.05, .z = 0.3 }, .rotation = 1.57 },
        .{ .prop_type = .wooden_fence_section, .position = .{ .x = 0.05, .z = 0.5 }, .rotation = 1.57 },
        .{ .prop_type = .wooden_fence_section, .position = .{ .x = 0.95, .z = 0.3 }, .rotation = 1.57 },
        .{ .prop_type = .wooden_fence_section, .position = .{ .x = 0.95, .z = 0.5 }, .rotation = 1.57 },
        // Trees along fence
        .{ .prop_type = .pine_tree_medium, .position = .{ .x = 0.1, .z = 0.15 } },
        .{ .prop_type = .bare_tree, .position = .{ .x = 0.9, .z = 0.15 } },
        // Snowman the kids built
        .{ .prop_type = .snowman_large, .position = .{ .x = 0.35, .z = 0.3 } },
    },
    .smoothing_passes = 2,
};

// ----------------------------------------------------------------------------
// INTERSECTION - Four-way street intersection
// Tactical: Open center, four approach angles, car cover on corners
// ----------------------------------------------------------------------------
pub const template_intersection = ArenaRecipe{
    .name = "Intersection",
    .elevation_ops = &[_]ElevationOp{
        // Base flat
        .{ .primitive = .{ .flat = .{ .height = 0.0 } }, .blend = .replace },
        // Streets are slightly depressed
        .{ .primitive = .{ .ridge = .{
            .start = .{ .x = 0.5, .z = 0.0 },
            .end = .{ .x = 0.5, .z = 1.0 },
            .width = 0.12,
            .height = -3.0,
        } }, .blend = .add },
        .{ .primitive = .{ .ridge = .{
            .start = .{ .x = 0.0, .z = 0.5 },
            .end = .{ .x = 1.0, .z = 0.5 },
            .width = 0.12,
            .height = -3.0,
        } }, .blend = .add },
        // Corner yards are raised
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.2, .z = 0.2 }, .radius = 0.15, .height = 8.0, .falloff = .plateau } }, .blend = .add },
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.8, .z = 0.2 }, .radius = 0.15, .height = 8.0, .falloff = .plateau } }, .blend = .add },
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.2, .z = 0.8 }, .radius = 0.15, .height = 8.0, .falloff = .plateau } }, .blend = .add },
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.8, .z = 0.8 }, .radius = 0.15, .height = 8.0, .falloff = .plateau } }, .blend = .add },
        // Parked cars on corners
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.35, .z = 0.2 }, .radius = 0.05, .height = 9.0, .falloff = .smooth } }, .blend = .add },
        .{ .primitive = .{ .mound = .{ .center = .{ .x = 0.65, .z = 0.8 }, .radius = 0.05, .height = 9.0, .falloff = .smooth } }, .blend = .add },
        // House boundaries
        .{ .primitive = .{ .boundary_wall = .{ .height = 50.0, .thickness = 0.05, .irregularity = 0.4 } }, .blend = .max },
    },
    .snow_ops = &[_]SnowZonePrimitive{
        // Yards have snow
        .{ .fill = .{ .terrain_type = .thick_snow } },
        // Streets are packed
        .{ .path = .{ .start = .{ .x = 0.5, .z = 0.0 }, .end = .{ .x = 0.5, .z = 1.0 }, .width = 0.1, .terrain_type = .packed_snow } },
        .{ .path = .{ .start = .{ .x = 0.0, .z = 0.5 }, .end = .{ .x = 1.0, .z = 0.5 }, .width = 0.1, .terrain_type = .packed_snow } },
        // Center intersection is icy
        .{ .circle = .{ .center = .{ .x = 0.5, .z = 0.5 }, .radius = 0.12, .terrain_type = .icy_ground } },
        // Crosswalks are cleared
        .{ .rect = .{ .min = .{ .x = 0.35, .z = 0.47 }, .max = .{ .x = 0.42, .z = 0.53 }, .terrain_type = .cleared_ground } },
        .{ .rect = .{ .min = .{ .x = 0.58, .z = 0.47 }, .max = .{ .x = 0.65, .z = 0.53 }, .terrain_type = .cleared_ground } },
        .{ .rect = .{ .min = .{ .x = 0.47, .z = 0.35 }, .max = .{ .x = 0.53, .z = 0.42 }, .terrain_type = .cleared_ground } },
        .{ .rect = .{ .min = .{ .x = 0.47, .z = 0.58 }, .max = .{ .x = 0.53, .z = 0.65 }, .terrain_type = .cleared_ground } },
    },
    // Props: street corners, parked cars, lampposts, mailboxes
    .collection_placements = &[_]CollectionPlacement{
        // Street corners with lamp and mailbox
        .{ .collection = &props.collection_street_corner, .position = .{ .x = 0.35, .z = 0.35 } },
        .{ .collection = &props.collection_street_corner, .position = .{ .x = 0.65, .z = 0.35 } },
        .{ .collection = &props.collection_street_corner, .position = .{ .x = 0.35, .z = 0.65 } },
        .{ .collection = &props.collection_street_corner, .position = .{ .x = 0.65, .z = 0.65 } },
        // Front yards on corners
        .{ .collection = &props.collection_front_yard, .position = .{ .x = 0.2, .z = 0.2 }, .scale = 0.7 },
        .{ .collection = &props.collection_front_yard, .position = .{ .x = 0.8, .z = 0.8 }, .scale = 0.7 },
    },
    .prop_placements = &[_]PropPlacement{
        // Parked cars on streets
        .{ .prop_type = .snow_covered_car, .position = .{ .x = 0.35, .z = 0.2 } },
        .{ .prop_type = .snow_covered_suv, .position = .{ .x = 0.65, .z = 0.8 } },
        // Stop signs (using lampposts as stand-in)
        .{ .prop_type = .lamppost, .position = .{ .x = 0.4, .z = 0.4 } },
        .{ .prop_type = .lamppost, .position = .{ .x = 0.6, .z = 0.6 } },
        // Fire hydrant area (snow pile around it)
        .{ .prop_type = .snow_pile_small, .position = .{ .x = 0.38, .z = 0.62 } },
        // Kids' snow fort on corner
        .{ .prop_type = .snow_fort_wall, .position = .{ .x = 0.22, .z = 0.78 } },
        .{ .prop_type = .snow_fort_corner, .position = .{ .x = 0.25, .z = 0.75 } },
        // Snowman watching the intersection
        .{ .prop_type = .snowman_small, .position = .{ .x = 0.78, .z = 0.22 } },
        // Trash bins
        .{ .prop_type = .trash_can, .position = .{ .x = 0.18, .z = 0.35 } },
        .{ .prop_type = .trash_can, .position = .{ .x = 0.82, .z = 0.65 } },
    },
    .smoothing_passes = 2,
};

// ============================================================================
// LEGACY ALIASES - Keep old names working
// ============================================================================

pub const template_open_arena = template_school_yard;
pub const template_canyon = template_snowy_street;
pub const template_frozen_pond = template_forest_clearing;
pub const template_fortress = template_backyard;
pub const template_crossroads = template_intersection;

// ============================================================================
// ARENA GENERATOR - Applies recipes to terrain grids
// ============================================================================

/// Apply an arena recipe to a terrain grid
pub fn applyRecipe(grid: *TerrainGrid, recipe: ArenaRecipe) void {
    const width = grid.width;
    const height = grid.height;

    // Phase 1: Apply elevation primitives
    for (recipe.elevation_ops) |op| {
        // Handle special cases that need existing heightmap
        switch (op.primitive) {
            .arena_flatten => |af| {
                applyArenaFlatten(grid.heightmap, width, height, af, op.blend);
            },
            .terrace => |t| {
                applyTerrace(grid.heightmap, width * height, t);
            },
            else => {
                op.primitive.apply(grid.heightmap, width, height, op.blend);
            },
        }
    }

    // Phase 2: Smoothing passes
    if (recipe.smoothing_passes > 0) {
        smoothHeightmap(grid.heightmap, width, height, recipe.smoothing_passes, grid.allocator) catch {};
    }

    // Phase 3: Apply snow zone primitives
    for (recipe.snow_ops) |snow_op| {
        snow_op.apply(grid.cells, grid.heightmap, width, height);
    }

    // Mark mesh as needing regeneration
    grid.markMeshDirty();
}

/// Place props from an arena recipe into a PropManager
/// Call this after applyRecipe() to populate the arena with props
pub fn placePropsFromRecipe(
    prop_manager: *props.PropManager,
    recipe: ArenaRecipe,
    terrain: *const TerrainGrid,
) void {
    // Clear any existing props
    prop_manager.clear();

    // Place individual props
    for (recipe.prop_placements) |placement| {
        _ = prop_manager.placeProp(placement, terrain);
    }

    // Place prop collections
    for (recipe.collection_placements) |collection_placement| {
        _ = prop_manager.placeCollection(collection_placement, terrain);
    }
}

fn applyArenaFlatten(heightmap: []f32, width: usize, height: usize, af: anytype, blend: BlendMode) void {
    for (0..height) |gz| {
        for (0..width) |gx| {
            const idx = gz * width + gx;
            const pos = NormalizedPos{
                .x = @as(f32, @floatFromInt(gx)) / @as(f32, @floatFromInt(width - 1)),
                .z = @as(f32, @floatFromInt(gz)) / @as(f32, @floatFromInt(height - 1)),
            };

            const dist = pos.distanceTo(af.center);
            if (dist < af.radius) {
                const t = dist / af.radius;
                const flatten_strength = af.strength * (1.0 - t * t); // Quadratic falloff
                const target = af.target_height;
                const flattened = heightmap[idx] * (1.0 - flatten_strength) + target * flatten_strength;
                heightmap[idx] = applyBlend(heightmap[idx], flattened, blend);
            }
        }
    }
}

fn applyTerrace(heightmap: []f32, len: usize, t: anytype) void {
    for (0..len) |i| {
        const h = heightmap[i];
        const step = @floor(h / t.step_height);
        const frac = (h / t.step_height) - step;

        // Smoothed step transition
        const smooth_frac = if (frac < t.smoothing)
            frac * frac / (2.0 * t.smoothing)
        else if (frac > 1.0 - t.smoothing)
            1.0 - (1.0 - frac) * (1.0 - frac) / (2.0 * t.smoothing)
        else
            frac;

        heightmap[i] = (step + smooth_frac) * t.step_height;
    }
}

fn smoothHeightmap(heightmap: []f32, width: usize, height: usize, passes: u8, allocator: std.mem.Allocator) !void {
    const temp = try allocator.alloc(f32, width * height);
    defer allocator.free(temp);

    var pass: u8 = 0;
    while (pass < passes) : (pass += 1) {
        for (0..height) |z| {
            for (0..width) |x| {
                const idx = z * width + x;

                // Skip boundary walls (high elevation)
                if (heightmap[idx] > 60.0) {
                    temp[idx] = heightmap[idx];
                    continue;
                }

                var sum: f32 = 0.0;
                var count: f32 = 0.0;

                // 3x3 kernel
                const x_start = if (x > 0) x - 1 else x;
                const x_end = if (x < width - 1) x + 1 else x;
                const z_start = if (z > 0) z - 1 else z;
                const z_end = if (z < height - 1) z + 1 else z;

                var nz = z_start;
                while (nz <= z_end) : (nz += 1) {
                    var nx = x_start;
                    while (nx <= x_end) : (nx += 1) {
                        sum += heightmap[nz * width + nx];
                        count += 1.0;
                    }
                }

                temp[idx] = sum / count;
            }
        }

        // Copy back
        @memcpy(heightmap, temp);
    }
}

// ============================================================================
// PROCEDURAL ARENA GENERATOR
// ============================================================================
// Generates random arenas by composing atomic primitives based on parameters.
// Used by the campaign system to create varied encounter arenas.

/// Arena archetype - high-level arena style
pub const ArenaArchetype = enum {
    open_field, // Classic flat arena with boundary walls
    canyon, // Narrow corridor with ridges
    frozen_pond, // Central depression with icy center
    fortress, // Raised central plateau with ramps
    crossroads, // Four-way intersection
    amphitheater, // Tiered/terraced circular arena
    maze, // Multiple walls creating lanes
    hillside, // Sloped terrain with cover

    /// Get the base template for this archetype
    pub fn getTemplate(self: ArenaArchetype) *const ArenaRecipe {
        return switch (self) {
            .open_field => &template_open_arena,
            .canyon => &template_canyon,
            .frozen_pond => &template_frozen_pond,
            .fortress => &template_fortress,
            .crossroads => &template_crossroads,
            .amphitheater => &template_open_arena, // TODO: create amphitheater
            .maze => &template_open_arena, // TODO: create maze
            .hillside => &template_open_arena, // TODO: create hillside
        };
    }
};

/// Parameters for procedural arena generation
pub const ArenaGenParams = struct {
    /// Base archetype to use
    archetype: ArenaArchetype = .open_field,

    /// Seed for procedural elements
    seed: u64 = 0,

    /// Difficulty affects terrain complexity (1-10)
    difficulty: u8 = 5,

    /// How much cover/obstacles to add (0.0 to 1.0)
    cover_density: f32 = 0.3,

    /// How varied the elevation should be (0.0 to 1.0)
    elevation_variance: f32 = 0.5,

    /// How much icy terrain to include (0.0 to 1.0)
    ice_coverage: f32 = 0.2,

    /// Add hazard zones
    include_hazards: bool = true,

    /// Number of distinct terrain zones
    zone_count: u8 = 3,
};

/// Runtime arena recipe builder - creates ArenaRecipe at runtime
/// Use this when you need procedurally generated arenas
pub const ArenaBuilder = struct {
    allocator: std.mem.Allocator,
    seed: u64,
    rng: std.Random,

    // Buffers for building the recipe
    elevation_ops: std.ArrayListUnmanaged(ElevationOp),
    snow_ops: std.ArrayListUnmanaged(SnowZonePrimitive),

    pub fn init(allocator: std.mem.Allocator, seed: u64) ArenaBuilder {
        var prng = std.Random.DefaultPrng.init(seed);
        return ArenaBuilder{
            .allocator = allocator,
            .seed = seed,
            .rng = prng.random(),
            .elevation_ops = .empty,
            .snow_ops = .empty,
        };
    }

    pub fn deinit(self: *ArenaBuilder) void {
        self.elevation_ops.deinit(self.allocator);
        self.snow_ops.deinit(self.allocator);
    }

    /// Add base noise terrain
    pub fn addBaseNoise(self: *ArenaBuilder, amplitude: f32, frequency: f32) !void {
        try self.elevation_ops.append(self.allocator, .{
            .primitive = .{ .noise = .{
                .seed = self.seed,
                .amplitude = amplitude,
                .frequency = frequency,
                .octaves = 3,
            } },
            .blend = .add,
        });
    }

    /// Add boundary walls
    pub fn addBoundaryWalls(self: *ArenaBuilder, height: f32, thickness: f32) !void {
        try self.elevation_ops.append(self.allocator, .{
            .primitive = .{ .boundary_wall = .{
                .height = height,
                .thickness = thickness,
                .irregularity = 0.5,
                .seed = self.seed,
            } },
            .blend = .max,
        });
    }

    /// Add a mound at a position
    pub fn addMound(self: *ArenaBuilder, center: NormalizedPos, radius: f32, height: f32) !void {
        try self.elevation_ops.append(self.allocator, .{
            .primitive = .{ .mound = .{
                .center = center,
                .radius = radius,
                .height = height,
                .falloff = .smooth,
            } },
            .blend = .add,
        });
    }

    /// Add a ridge between two points
    pub fn addRidge(self: *ArenaBuilder, start: NormalizedPos, end: NormalizedPos, width: f32, height: f32) !void {
        try self.elevation_ops.append(self.allocator, .{
            .primitive = .{ .ridge = .{
                .start = start,
                .end = end,
                .width = width,
                .height = height,
                .falloff = .smooth,
            } },
            .blend = .add,
        });
    }

    /// Add center flattening
    pub fn addCenterFlatten(self: *ArenaBuilder, radius: f32, strength: f32) !void {
        try self.elevation_ops.append(self.allocator, .{
            .primitive = .{ .arena_flatten = .{
                .center = .{ .x = 0.5, .z = 0.5 },
                .radius = radius,
                .strength = strength,
            } },
            .blend = .smooth_blend,
        });
    }

    /// Add a snow zone
    pub fn addSnowCircle(self: *ArenaBuilder, center: NormalizedPos, radius: f32, terrain: TerrainType) !void {
        try self.snow_ops.append(self.allocator, .{ .circle = .{
            .center = center,
            .radius = radius,
            .terrain_type = terrain,
        } });
    }

    /// Add snow path
    pub fn addSnowPath(self: *ArenaBuilder, start: NormalizedPos, end: NormalizedPos, width: f32, terrain: TerrainType) !void {
        try self.snow_ops.append(self.allocator, .{ .path = .{
            .start = start,
            .end = end,
            .width = width,
            .terrain_type = terrain,
        } });
    }

    /// Generate a procedural arena based on parameters
    pub fn generateFromParams(self: *ArenaBuilder, params: ArenaGenParams) !void {
        // Clear existing operations
        self.elevation_ops.clearRetainingCapacity();
        self.snow_ops.clearRetainingCapacity();

        // Re-seed RNG
        var prng = std.Random.DefaultPrng.init(params.seed);
        self.rng = prng.random();
        self.seed = params.seed;

        // === ELEVATION LAYER ===

        // 1. Base noise (scaled by elevation_variance)
        const noise_amplitude = 5.0 + params.elevation_variance * 15.0;
        try self.addBaseNoise(noise_amplitude, 2.0);

        // 2. Archetype-specific features
        switch (params.archetype) {
            .open_field => {
                // Flatten center more
                try self.addCenterFlatten(0.35, 0.7);
            },
            .canyon => {
                // Add ridges on sides
                try self.addRidge(.{ .x = 0.0, .z = 0.15 }, .{ .x = 1.0, .z = 0.15 }, 0.12, 30.0);
                try self.addRidge(.{ .x = 0.0, .z = 0.85 }, .{ .x = 1.0, .z = 0.85 }, 0.12, 30.0);
            },
            .frozen_pond => {
                // Central depression
                try self.elevation_ops.append(self.allocator, .{
                    .primitive = .{ .crater = .{
                        .center = .{ .x = 0.5, .z = 0.5 },
                        .outer_radius = 0.3,
                        .inner_radius = 0.2,
                        .depth = 10.0,
                        .rim_height = 5.0,
                    } },
                    .blend = .add,
                });
            },
            .fortress => {
                // Central plateau
                try self.elevation_ops.append(self.allocator, .{
                    .primitive = .{ .plateau = .{
                        .min = .{ .x = 0.35, .z = 0.35 },
                        .max = .{ .x = 0.65, .z = 0.65 },
                        .height = 25.0,
                        .edge_falloff = 0.05,
                    } },
                    .blend = .add,
                });
            },
            .crossroads => {
                // Cross valleys
                try self.addRidge(.{ .x = 0.5, .z = 0.0 }, .{ .x = 0.5, .z = 1.0 }, 0.12, -8.0);
                try self.addRidge(.{ .x = 0.0, .z = 0.5 }, .{ .x = 1.0, .z = 0.5 }, 0.12, -8.0);
                try self.addCenterFlatten(0.15, 0.9);
            },
            else => {
                // Default: gentle center flatten
                try self.addCenterFlatten(0.3, 0.5);
            },
        }

        // 3. Random cover mounds based on density
        const num_mounds = @as(usize, @intFromFloat(params.cover_density * 8.0));
        for (0..num_mounds) |_| {
            const mx = 0.15 + self.rng.float(f32) * 0.7; // Avoid edges
            const mz = 0.15 + self.rng.float(f32) * 0.7;
            const mheight = 5.0 + self.rng.float(f32) * 15.0;
            const mradius = 0.05 + self.rng.float(f32) * 0.08;
            try self.addMound(.{ .x = mx, .z = mz }, mradius, mheight);
        }

        // 4. Boundary walls (always)
        const wall_height = 60.0 + @as(f32, @floatFromInt(params.difficulty)) * 5.0;
        try self.addBoundaryWalls(wall_height, 0.07);

        // === SNOW LAYER ===

        // 1. Base fill
        try self.snow_ops.append(self.allocator, .{ .fill = .{ .terrain_type = .packed_snow } });

        // 2. Ice coverage
        if (params.ice_coverage > 0.1) {
            // Add icy zones
            const ice_zones = @as(usize, @intFromFloat(params.ice_coverage * 5.0)) + 1;
            for (0..ice_zones) |_| {
                const ix = 0.2 + self.rng.float(f32) * 0.6;
                const iz = 0.2 + self.rng.float(f32) * 0.6;
                const iradius = 0.08 + params.ice_coverage * 0.1;
                try self.addSnowCircle(.{ .x = ix, .z = iz }, iradius, .icy_ground);
            }
        }

        // 3. Archetype-specific snow
        switch (params.archetype) {
            .frozen_pond => {
                // Central ice
                try self.addSnowCircle(.{ .x = 0.5, .z = 0.5 }, 0.22, .icy_ground);
            },
            .canyon => {
                // Center packed path
                try self.addSnowPath(.{ .x = 0.0, .z = 0.5 }, .{ .x = 1.0, .z = 0.5 }, 0.15, .packed_snow);
            },
            .crossroads => {
                // Roads are packed
                try self.addSnowPath(.{ .x = 0.5, .z = 0.0 }, .{ .x = 0.5, .z = 1.0 }, 0.1, .packed_snow);
                try self.addSnowPath(.{ .x = 0.0, .z = 0.5 }, .{ .x = 1.0, .z = 0.5 }, 0.1, .packed_snow);
                // Center is icy
                try self.addSnowCircle(.{ .x = 0.5, .z = 0.5 }, 0.12, .icy_ground);
            },
            else => {},
        }

        // 4. Deep powder at edges (between arena and boundary)
        try self.snow_ops.append(self.allocator, .{ .ring = .{
            .center = .{ .x = 0.5, .z = 0.5 },
            .inner_radius = 0.38,
            .outer_radius = 0.48,
            .terrain_type = .thick_snow,
        } });
    }

    /// Apply the built operations to a terrain grid
    pub fn applyToGrid(self: *const ArenaBuilder, grid: *TerrainGrid) void {
        const width = grid.width;
        const height = grid.height;

        // Apply elevation operations
        for (self.elevation_ops.items) |op| {
            switch (op.primitive) {
                .arena_flatten => |af| {
                    applyArenaFlatten(grid.heightmap, width, height, af, op.blend);
                },
                .terrace => |t| {
                    applyTerrace(grid.heightmap, width * height, t);
                },
                else => {
                    op.primitive.apply(grid.heightmap, width, height, op.blend);
                },
            }
        }

        // Smoothing
        smoothHeightmap(grid.heightmap, width, height, 2, grid.allocator) catch {};

        // Apply snow operations
        for (self.snow_ops.items) |snow_op| {
            snow_op.apply(grid.cells, grid.heightmap, width, height);
        }

        grid.markMeshDirty();
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "normalized position helpers" {
    const pos = NormalizedPos{ .x = 0.5, .z = 0.5 };
    try std.testing.expectApproxEqAbs(pos.distanceToCenter(), 0.0, 0.001);
    try std.testing.expectApproxEqAbs(pos.distanceToEdge(), 0.5, 0.001);

    const corner = NormalizedPos{ .x = 0.0, .z = 0.0 };
    try std.testing.expectApproxEqAbs(corner.distanceToEdge(), 0.0, 0.001);
}

test "falloff functions" {
    // All falloffs should return 1.0 at t=0 and approach 0 at t=1
    try std.testing.expectApproxEqAbs(Falloff.linear.apply(0.0), 1.0, 0.001);
    try std.testing.expectApproxEqAbs(Falloff.linear.apply(1.0), 0.0, 0.001);

    try std.testing.expectApproxEqAbs(Falloff.smooth.apply(0.0), 1.0, 0.001);
    try std.testing.expectApproxEqAbs(Falloff.smooth.apply(1.0), 0.0, 0.001);
}

test "mound primitive sampling" {
    const mound = ElevationPrimitive{ .mound = .{
        .center = .{ .x = 0.5, .z = 0.5 },
        .radius = 0.3,
        .height = 30.0,
        .falloff = .linear,
    } };

    // Center should be at peak height
    const center_h = mound.sampleAt(.{ .x = 0.5, .z = 0.5 });
    try std.testing.expectApproxEqAbs(center_h, 30.0, 0.001);

    // Outside radius should be 0
    const outside_h = mound.sampleAt(.{ .x = 0.0, .z = 0.0 });
    try std.testing.expectApproxEqAbs(outside_h, 0.0, 0.001);
}

test "snow zone circle" {
    const circle = SnowZonePrimitive{ .circle = .{
        .center = .{ .x = 0.5, .z = 0.5 },
        .radius = 0.2,
        .terrain_type = .icy_ground,
    } };

    // Center should return the terrain type
    const center_type = circle.getTerrainAt(.{ .x = 0.5, .z = 0.5 }, 0.0);
    try std.testing.expect(center_type == .icy_ground);

    // Outside should return null
    const outside_type = circle.getTerrainAt(.{ .x = 0.0, .z = 0.0 }, 0.0);
    try std.testing.expect(outside_type == null);
}
