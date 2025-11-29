// ============================================================================
// GIS LOADER - OpenStreetMap and Elevation Data Integration
// ============================================================================
//
// Converts real-world geographic data into arena primitives:
// - GeoJSON (from OpenStreetMap exports) -> polygons, polylines, points
// - DEM/heightmap data -> elevation primitives
//
// Pipeline:
//   1. Define a GeoBounds (lat/lon bounding box)
//   2. Load GeoJSON features within bounds
//   3. Convert features to normalized arena primitives
//   4. Compose into ArenaRecipe
//
// Coordinate Systems:
// - GeoJSON uses WGS84 (longitude, latitude) in degrees
// - Arena uses normalized coordinates (0.0 to 1.0)
// - Conversion handles the mapping between these systems
//
// ============================================================================

const std = @import("std");
const arena_gen = @import("arena_gen.zig");
const terrain_mod = @import("terrain.zig");
const props = @import("arena_props.zig");
const buildings = @import("buildings.zig");

const Allocator = std.mem.Allocator;
const NormalizedPos = arena_gen.NormalizedPos;
const ElevationPrimitive = arena_gen.ElevationPrimitive;
const ElevationOp = arena_gen.ElevationOp;
const SnowZonePrimitive = arena_gen.SnowZonePrimitive;
const BlendMode = arena_gen.BlendMode;
const Falloff = arena_gen.Falloff;
const TerrainType = terrain_mod.TerrainType;
const PropPlacement = props.PropPlacement;
const PropType = props.PropType;

// ============================================================================
// GEOGRAPHIC COORDINATES
// ============================================================================

/// A point in WGS84 coordinates (longitude, latitude in degrees)
pub const GeoPoint = struct {
    lon: f64, // Longitude (-180 to 180)
    lat: f64, // Latitude (-90 to 90)

    /// Calculate approximate distance in meters using Haversine formula
    pub fn distanceMeters(self: GeoPoint, other: GeoPoint) f64 {
        const R = 6371000.0; // Earth radius in meters
        const lat1 = self.lat * std.math.pi / 180.0;
        const lat2 = other.lat * std.math.pi / 180.0;
        const dlat = (other.lat - self.lat) * std.math.pi / 180.0;
        const dlon = (other.lon - self.lon) * std.math.pi / 180.0;

        const a = @sin(dlat / 2.0) * @sin(dlat / 2.0) +
            @cos(lat1) * @cos(lat2) * @sin(dlon / 2.0) * @sin(dlon / 2.0);
        const c = 2.0 * std.math.atan2(@sqrt(a), @sqrt(1.0 - a));

        return R * c;
    }
};

/// A bounding box in geographic coordinates
pub const GeoBounds = struct {
    min_lon: f64,
    min_lat: f64,
    max_lon: f64,
    max_lat: f64,

    /// Create bounds from center point and radius in meters
    pub fn fromCenterRadius(center: GeoPoint, radius_meters: f64) GeoBounds {
        // Approximate degrees per meter at this latitude
        const lat_deg_per_meter = 1.0 / 111320.0;
        const lon_deg_per_meter = 1.0 / (111320.0 * @cos(center.lat * std.math.pi / 180.0));

        const lat_delta = radius_meters * lat_deg_per_meter;
        const lon_delta = radius_meters * lon_deg_per_meter;

        return .{
            .min_lon = center.lon - lon_delta,
            .min_lat = center.lat - lat_delta,
            .max_lon = center.lon + lon_delta,
            .max_lat = center.lat + lat_delta,
        };
    }

    /// Get width in meters (approximate)
    pub fn widthMeters(self: GeoBounds) f64 {
        const center_lat = (self.min_lat + self.max_lat) / 2.0;
        const p1 = GeoPoint{ .lon = self.min_lon, .lat = center_lat };
        const p2 = GeoPoint{ .lon = self.max_lon, .lat = center_lat };
        return p1.distanceMeters(p2);
    }

    /// Get height in meters (approximate)
    pub fn heightMeters(self: GeoBounds) f64 {
        const center_lon = (self.min_lon + self.max_lon) / 2.0;
        const p1 = GeoPoint{ .lon = center_lon, .lat = self.min_lat };
        const p2 = GeoPoint{ .lon = center_lon, .lat = self.max_lat };
        return p1.distanceMeters(p2);
    }

    /// Convert a geographic point to normalized arena coordinates (0-1)
    /// Note: Z is flipped so that north (higher latitude) maps to -Z (into screen)
    /// This matches typical game coordinate conventions where camera looks "north"
    pub fn toNormalized(self: GeoBounds, point: GeoPoint) NormalizedPos {
        return .{
            .x = @floatCast((point.lon - self.min_lon) / (self.max_lon - self.min_lon)),
            // Flip Z: higher latitude (north) -> lower Z value
            .z = @floatCast(1.0 - (point.lat - self.min_lat) / (self.max_lat - self.min_lat)),
        };
    }

    /// Check if a point is within bounds
    pub fn contains(self: GeoBounds, point: GeoPoint) bool {
        return point.lon >= self.min_lon and point.lon <= self.max_lon and
            point.lat >= self.min_lat and point.lat <= self.max_lat;
    }
};

// ============================================================================
// GEOJSON PARSING
// ============================================================================

/// Types of GeoJSON geometry we care about
pub const GeometryType = enum {
    point,
    line_string,
    polygon,
    multi_polygon,
    unknown,

    pub fn fromString(s: []const u8) GeometryType {
        if (std.mem.eql(u8, s, "Point")) return .point;
        if (std.mem.eql(u8, s, "LineString")) return .line_string;
        if (std.mem.eql(u8, s, "Polygon")) return .polygon;
        if (std.mem.eql(u8, s, "MultiPolygon")) return .multi_polygon;
        return .unknown;
    }
};

/// OSM feature types we recognize
pub const FeatureClass = enum {
    building,
    highway_primary,
    highway_secondary,
    highway_residential,
    highway_footway,
    water,
    park,
    parking,
    tree,
    unknown,

    /// Determine feature class from OSM tags
    pub fn fromTags(tags: ?std.json.Value) FeatureClass {
        if (tags == null) return .unknown;
        const obj = tags.?.object;

        // Check building tag
        if (obj.get("building")) |_| return .building;

        // Check highway tag
        if (obj.get("highway")) |highway| {
            if (highway == .string) {
                const hw = highway.string;
                if (std.mem.eql(u8, hw, "primary") or std.mem.eql(u8, hw, "trunk")) return .highway_primary;
                if (std.mem.eql(u8, hw, "secondary") or std.mem.eql(u8, hw, "tertiary")) return .highway_secondary;
                if (std.mem.eql(u8, hw, "residential") or std.mem.eql(u8, hw, "unclassified")) return .highway_residential;
                if (std.mem.eql(u8, hw, "footway") or std.mem.eql(u8, hw, "path") or std.mem.eql(u8, hw, "pedestrian")) return .highway_footway;
            }
        }

        // Check natural tag
        if (obj.get("natural")) |natural| {
            if (natural == .string) {
                if (std.mem.eql(u8, natural.string, "water")) return .water;
                if (std.mem.eql(u8, natural.string, "tree")) return .tree;
            }
        }

        // Check landuse tag
        if (obj.get("landuse")) |landuse| {
            if (landuse == .string) {
                if (std.mem.eql(u8, landuse.string, "grass") or std.mem.eql(u8, landuse.string, "recreation_ground")) return .park;
            }
        }

        // Check leisure tag
        if (obj.get("leisure")) |leisure| {
            if (leisure == .string) {
                if (std.mem.eql(u8, leisure.string, "park") or std.mem.eql(u8, leisure.string, "playground")) return .park;
            }
        }

        // Check amenity tag
        if (obj.get("amenity")) |amenity| {
            if (amenity == .string) {
                if (std.mem.eql(u8, amenity.string, "parking")) return .parking;
            }
        }

        return .unknown;
    }
};

/// A parsed GeoJSON feature
pub const GeoFeature = struct {
    geometry_type: GeometryType,
    feature_class: FeatureClass,
    /// For polygons: outer ring coordinates
    /// For lines: line coordinates
    /// For points: single coordinate
    coordinates: []GeoPoint,
    /// For polygons with holes: inner rings
    holes: [][]GeoPoint,
    /// For buildings: classified building type (from OSM tags)
    building_type: buildings.BuildingType = .unknown,

    pub fn deinit(self: *GeoFeature, allocator: Allocator) void {
        allocator.free(self.coordinates);
        for (self.holes) |hole| {
            allocator.free(hole);
        }
        allocator.free(self.holes);
    }
};

/// Classify OSM building/amenity tags to our BuildingType enum
fn classifyBuildingType(osm_building: ?[]const u8, osm_amenity: ?[]const u8) buildings.BuildingType {
    // First check amenity tag for special buildings
    if (osm_amenity) |amenity| {
        if (std.mem.eql(u8, amenity, "school")) return .school;
        if (std.mem.eql(u8, amenity, "place_of_worship")) return .church;
        if (std.mem.eql(u8, amenity, "community_centre")) return .school; // Similar scale
    }

    // Then check building tag
    if (osm_building) |building| {
        // Residential
        if (std.mem.eql(u8, building, "house")) return .residential_house;
        if (std.mem.eql(u8, building, "detached")) return .residential_house;
        if (std.mem.eql(u8, building, "semidetached_house")) return .residential_house;
        if (std.mem.eql(u8, building, "residential")) return .residential_house;

        // Garages and sheds
        if (std.mem.eql(u8, building, "garage")) return .residential_garage;
        if (std.mem.eql(u8, building, "garages")) return .residential_garage;
        if (std.mem.eql(u8, building, "shed")) return .shed;

        // Apartments
        if (std.mem.eql(u8, building, "apartments")) return .apartment_low;
        if (std.mem.eql(u8, building, "apartment")) return .apartment_low;

        // Commercial
        if (std.mem.eql(u8, building, "commercial")) return .commercial_small;
        if (std.mem.eql(u8, building, "retail")) return .commercial_small;
        if (std.mem.eql(u8, building, "shop")) return .commercial_small;
        if (std.mem.eql(u8, building, "supermarket")) return .commercial_large;
        if (std.mem.eql(u8, building, "warehouse")) return .commercial_large;

        // Institutional
        if (std.mem.eql(u8, building, "school")) return .school;
        if (std.mem.eql(u8, building, "church")) return .church;
        if (std.mem.eql(u8, building, "chapel")) return .church;

        // Industrial
        if (std.mem.eql(u8, building, "industrial")) return .industrial;
        if (std.mem.eql(u8, building, "train_station")) return .industrial;

        // Generic building tag (yes, roof) - default to residential house for Calgary suburbs
        if (std.mem.eql(u8, building, "yes")) return .residential_house;
        if (std.mem.eql(u8, building, "roof")) return .shed;
    }

    return .unknown;
}

/// Parse a GeoJSON FeatureCollection from file
pub fn parseGeoJsonFile(allocator: Allocator, path: []const u8, bounds: GeoBounds) ![]GeoFeature {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 50 * 1024 * 1024); // 50MB max
    defer allocator.free(content);

    return parseGeoJson(allocator, content, bounds);
}

/// Parse GeoJSON from string
pub fn parseGeoJson(allocator: Allocator, json_str: []const u8, bounds: GeoBounds) ![]GeoFeature {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    return parseGeoJsonValue(allocator, parsed.value, bounds);
}

/// Parse GeoJSON from already-parsed JSON value
pub fn parseGeoJsonValue(allocator: Allocator, root: std.json.Value, bounds: GeoBounds) ![]GeoFeature {
    var features: std.ArrayListUnmanaged(GeoFeature) = .empty;
    errdefer {
        for (features.items) |*f| f.deinit(allocator);
        features.deinit(allocator);
    }

    // Handle FeatureCollection
    if (root.object.get("type")) |type_val| {
        if (type_val == .string and std.mem.eql(u8, type_val.string, "FeatureCollection")) {
            if (root.object.get("features")) |features_array| {
                if (features_array == .array) {
                    for (features_array.array.items) |feature| {
                        if (try parseFeature(allocator, feature, bounds)) |geo_feature| {
                            try features.append(allocator, geo_feature);
                        }
                    }
                }
            }
        }
    }

    return features.toOwnedSlice(allocator);
}

/// Parse a single GeoJSON feature
fn parseFeature(allocator: Allocator, feature: std.json.Value, bounds: GeoBounds) !?GeoFeature {
    if (feature != .object) return null;

    const obj = feature.object;

    // Get geometry
    const geometry = obj.get("geometry") orelse return null;
    if (geometry != .object) return null;

    // Get geometry type
    const geom_type_val = geometry.object.get("type") orelse return null;
    if (geom_type_val != .string) return null;
    const geom_type = GeometryType.fromString(geom_type_val.string);
    if (geom_type == .unknown) return null;

    // Get coordinates
    const coords_val = geometry.object.get("coordinates") orelse return null;

    // Get properties/tags for classification
    const properties = obj.get("properties");
    const feature_class = FeatureClass.fromTags(properties);

    // Extract OSM building and amenity tags for building classification
    // Classify NOW while we still have access to the JSON strings
    var building_type: buildings.BuildingType = .unknown;
    if (properties) |props_obj| {
        if (props_obj == .object) {
            var osm_building_tag: ?[]const u8 = null;
            var osm_amenity_tag: ?[]const u8 = null;

            if (props_obj.object.get("building")) |building| {
                if (building == .string) {
                    osm_building_tag = building.string;
                }
            }
            if (props_obj.object.get("amenity")) |amenity| {
                if (amenity == .string) {
                    osm_amenity_tag = amenity.string;
                }
            }

            // Classify while strings are still valid
            building_type = classifyBuildingType(osm_building_tag, osm_amenity_tag);
        }
    }

    // Parse coordinates based on geometry type
    var result: ?GeoFeature = switch (geom_type) {
        .point => try parsePointGeometry(allocator, coords_val, bounds, feature_class),
        .line_string => try parseLineStringGeometry(allocator, coords_val, bounds, feature_class),
        .polygon => try parsePolygonGeometry(allocator, coords_val, bounds, feature_class),
        .multi_polygon => null, // TODO: implement multi-polygon
        .unknown => null,
    };

    // Attach classified building type to the result
    if (result) |*r| {
        r.building_type = building_type;
    }

    return result;
}

fn parsePointGeometry(allocator: Allocator, coords: std.json.Value, bounds: GeoBounds, feature_class: FeatureClass) !?GeoFeature {
    if (coords != .array or coords.array.items.len < 2) return null;

    const point = GeoPoint{
        .lon = coords.array.items[0].float,
        .lat = coords.array.items[1].float,
    };

    if (!bounds.contains(point)) return null;

    const coords_arr = try allocator.alloc(GeoPoint, 1);
    coords_arr[0] = point;

    return GeoFeature{
        .geometry_type = .point,
        .feature_class = feature_class,
        .coordinates = coords_arr,
        .holes = &[_][]GeoPoint{},
    };
}

fn parseLineStringGeometry(allocator: Allocator, coords: std.json.Value, bounds: GeoBounds, feature_class: FeatureClass) !?GeoFeature {
    if (coords != .array) return null;

    var points: std.ArrayListUnmanaged(GeoPoint) = .empty;
    errdefer points.deinit(allocator);

    var any_in_bounds = false;
    for (coords.array.items) |coord| {
        if (coord != .array or coord.array.items.len < 2) continue;

        const point = GeoPoint{
            .lon = getFloat(coord.array.items[0]),
            .lat = getFloat(coord.array.items[1]),
        };

        // Track if any point is near bounds
        if (bounds.contains(point)) {
            any_in_bounds = true;
        }

        // Include all points (for lines that cross boundary)
        try points.append(allocator, point);
    }

    // Skip lines that are completely outside bounds
    if (!any_in_bounds) {
        points.deinit(allocator);
        return null;
    }

    if (points.items.len < 2) {
        points.deinit(allocator);
        return null;
    }

    return GeoFeature{
        .geometry_type = .line_string,
        .feature_class = feature_class,
        .coordinates = try points.toOwnedSlice(allocator),
        .holes = &[_][]GeoPoint{},
    };
}

fn parsePolygonGeometry(allocator: Allocator, coords: std.json.Value, bounds: GeoBounds, feature_class: FeatureClass) !?GeoFeature {
    if (coords != .array or coords.array.items.len == 0) return null;

    // First ring is outer boundary
    const outer_ring = coords.array.items[0];
    if (outer_ring != .array) return null;

    var outer_points: std.ArrayListUnmanaged(GeoPoint) = .empty;
    errdefer outer_points.deinit(allocator);

    for (outer_ring.array.items) |coord| {
        if (coord != .array or coord.array.items.len < 2) continue;

        const point = GeoPoint{
            .lon = getFloat(coord.array.items[0]),
            .lat = getFloat(coord.array.items[1]),
        };

        try outer_points.append(allocator, point);
    }

    if (outer_points.items.len < 3) {
        outer_points.deinit(allocator);
        return null;
    }

    // Check if polygon intersects bounds (simplified: check if any point is in bounds)
    var in_bounds = false;
    for (outer_points.items) |p| {
        if (bounds.contains(p)) {
            in_bounds = true;
            break;
        }
    }
    if (!in_bounds) {
        outer_points.deinit(allocator);
        return null;
    }

    // Parse holes (inner rings)
    var holes: std.ArrayListUnmanaged([]GeoPoint) = .empty;
    errdefer {
        for (holes.items) |h| allocator.free(h);
        holes.deinit(allocator);
    }

    if (coords.array.items.len > 1) {
        for (coords.array.items[1..]) |ring| {
            if (ring != .array) continue;

            var hole_points: std.ArrayListUnmanaged(GeoPoint) = .empty;
            for (ring.array.items) |coord| {
                if (coord != .array or coord.array.items.len < 2) continue;
                try hole_points.append(allocator, .{
                    .lon = getFloat(coord.array.items[0]),
                    .lat = getFloat(coord.array.items[1]),
                });
            }

            if (hole_points.items.len >= 3) {
                try holes.append(allocator, try hole_points.toOwnedSlice(allocator));
            } else {
                hole_points.deinit(allocator);
            }
        }
    }

    return GeoFeature{
        .geometry_type = .polygon,
        .feature_class = feature_class,
        .coordinates = try outer_points.toOwnedSlice(allocator),
        .holes = try holes.toOwnedSlice(allocator),
    };
}

/// Helper to get float from JSON number (handles both int and float)
fn getFloat(val: std.json.Value) f64 {
    return switch (val) {
        .float => val.float,
        .integer => @floatFromInt(val.integer),
        else => 0.0,
    };
}

// ============================================================================
// FEATURE TO PRIMITIVE CONVERSION
// ============================================================================

/// Configuration for converting GIS features to arena primitives
pub const ConversionConfig = struct {
    /// Height of buildings in world units
    building_height: f32 = 50.0,
    /// Edge falloff for buildings
    building_falloff: f32 = 0.005,

    /// Depression depth for primary roads
    primary_road_depth: f32 = -4.0,
    /// Width of primary roads (normalized)
    primary_road_width: f32 = 0.04,

    /// Depression depth for secondary roads
    secondary_road_depth: f32 = -3.0,
    /// Width of secondary roads (normalized)
    secondary_road_width: f32 = 0.03,

    /// Depression depth for residential roads
    residential_road_depth: f32 = -2.0,
    /// Width of residential roads (normalized)
    residential_road_width: f32 = 0.025,

    /// Footpath width (normalized)
    footpath_width: f32 = 0.01,

    // ========================================================================
    // TERRAIN TYPE ASSIGNMENTS - Calgary Winter Patterns
    // ========================================================================

    /// Base terrain for open yards (default before other features applied)
    yard_terrain: TerrainType = .thick_snow,

    /// Roads - plowed but refreezes, cars pack it down
    road_terrain: TerrainType = .icy_ground,

    /// Sidewalks/footpaths - foot traffic packs snow
    footpath_terrain: TerrainType = .packed_snow,

    /// Parking lots - cars compress and polish
    parking_terrain: TerrainType = .icy_ground,

    /// Parks/open fields - untouched pristine snow
    park_terrain: TerrainType = .deep_powder,

    /// Frozen water bodies
    water_terrain: TerrainType = .icy_ground,

    /// Building perimeter - snow cleared/packed near walls
    building_perimeter_terrain: TerrainType = .packed_snow,
    /// Width of cleared zone around buildings (normalized)
    building_perimeter_width: f32 = 0.008,

    /// Building snow taper - thick snow ring outside perimeter
    /// Creates natural accumulation pattern around buildings
    enable_building_snow_taper: bool = true,
    /// Outer ring of thick snow around buildings (normalized width)
    building_taper_width: f32 = 0.02,
    /// Terrain type for taper zone
    building_taper_terrain: TerrainType = .thick_snow,

    /// Building entrance zones - shoveled clear
    entrance_terrain: TerrainType = .cleared_ground,
    /// Size of entrance clearing (normalized)
    entrance_size: f32 = 0.012,

    // ========================================================================
    // WIND DRIFT SETTINGS - Snow piles up on leeward side of buildings
    // ========================================================================

    /// Enable wind drift elevation bumps
    enable_wind_drifts: bool = true,
    /// Prevailing wind direction (radians, 0 = from north, accumulates on south side)
    /// Calgary's prevailing winter winds come from the west/northwest
    wind_direction: f32 = 0.7, // ~40 degrees, from NW (accumulates on SE side)
    /// How far drifts extend from buildings (normalized)
    drift_distance: f32 = 0.015,
    /// Maximum drift height (world units)
    drift_height: f32 = 15.0,

    // ========================================================================
    // KID PATH SETTINGS - Shortcuts through yards
    // ========================================================================

    /// Enable procedural kid shortcuts between buildings
    enable_kid_paths: bool = true,
    /// Terrain type for kid-worn paths
    kid_path_terrain: TerrainType = .packed_snow,
    /// Width of kid paths (normalized)
    kid_path_width: f32 = 0.006,
};

/// Building data extracted from OSM for 3D rendering
pub const BuildingData = struct {
    /// Vertices in world coordinates
    vertices: []buildings.WorldVertex,
    /// Building type for rendering
    building_type: buildings.BuildingType,
    /// Optional height override (null = use default for type)
    height: ?f32,
};

/// Result of converting GIS features to arena primitives
pub const ConversionResult = struct {
    elevation_ops: []ElevationOp,
    snow_ops: []SnowZonePrimitive,
    prop_placements: []PropPlacement,
    building_data: []BuildingData,
    allocator: Allocator,

    pub fn deinit(self: *ConversionResult) void {
        self.allocator.free(self.elevation_ops);
        self.allocator.free(self.snow_ops);
        self.allocator.free(self.prop_placements);
        for (self.building_data) |bd| {
            self.allocator.free(bd.vertices);
        }
        self.allocator.free(self.building_data);
    }
};

/// Convert GIS features to arena primitives
pub fn convertFeaturesToPrimitives(
    allocator: Allocator,
    features: []const GeoFeature,
    bounds: GeoBounds,
    config: ConversionConfig,
) !ConversionResult {
    var elevation_ops: std.ArrayListUnmanaged(ElevationOp) = .empty;
    errdefer elevation_ops.deinit(allocator);

    var snow_ops: std.ArrayListUnmanaged(SnowZonePrimitive) = .empty;
    errdefer snow_ops.deinit(allocator);

    var prop_placements: std.ArrayListUnmanaged(PropPlacement) = .empty;
    errdefer prop_placements.deinit(allocator);

    var building_data: std.ArrayListUnmanaged(BuildingData) = .empty;
    errdefer {
        for (building_data.items) |bd| allocator.free(bd.vertices);
        building_data.deinit(allocator);
    }

    // Track building centers for kid path generation
    var building_centers: std.ArrayListUnmanaged(NormalizedPos) = .empty;
    defer building_centers.deinit(allocator);

    // ========================================================================
    // PASS 1: Base terrain - everything starts as yard snow
    // ========================================================================
    try snow_ops.append(allocator, .{ .fill = .{ .terrain_type = config.yard_terrain } });

    // ========================================================================
    // PASS 2: Process all features
    // ========================================================================
    for (features) |feature| {
        switch (feature.feature_class) {
            .building => {
                if (feature.geometry_type == .polygon) {
                    // Convert polygon to WORLD coordinates for building geometry
                    const world_verts = try geoToWorldVertices(allocator, feature.coordinates, bounds);
                    errdefer allocator.free(world_verts);

                    // Use pre-classified building type from parsing stage
                    try building_data.append(allocator, .{
                        .vertices = world_verts,
                        .building_type = feature.building_type,
                        .height = null, // Use default for type
                    });

                    // Get normalized coordinates for snow/terrain ops
                    const norm_coords = try geoToNormalized(allocator, feature.coordinates, bounds);
                    defer allocator.free(norm_coords);

                    // Calculate building center for paths
                    const center = calculatePolygonCenter(norm_coords);
                    try building_centers.append(allocator, center);

                    // Add thick snow taper ring around building (before packed perimeter)
                    // This creates the natural snow accumulation pattern
                    if (config.enable_building_snow_taper) {
                        // Add a circle of thick snow around the building center
                        // Size based on building footprint plus taper width
                        const bbox = calculatePolygonBBox(norm_coords);
                        const building_radius = @max(bbox.width, bbox.height) / 2.0;
                        try snow_ops.append(allocator, .{ .circle = .{
                            .center = center,
                            .radius = building_radius + config.building_taper_width,
                            .terrain_type = config.building_taper_terrain,
                        } });
                    }

                    // Building footprint is packed snow (people walk around buildings)
                    try addPolygonSnowZone(allocator, &snow_ops, norm_coords, config.building_perimeter_terrain);

                    // Add entrance clearing (south-facing side typically)
                    // Entrance is on the side facing away from wind (protected)
                    const entrance_offset_x = @sin(config.wind_direction + std.math.pi) * config.entrance_size;
                    const entrance_offset_z = @cos(config.wind_direction + std.math.pi) * config.entrance_size;
                    try snow_ops.append(allocator, .{ .circle = .{
                        .center = .{
                            .x = std.math.clamp(center.x + entrance_offset_x, 0.0, 1.0),
                            .z = std.math.clamp(center.z + entrance_offset_z, 0.0, 1.0),
                        },
                        .radius = config.entrance_size,
                        .terrain_type = config.entrance_terrain,
                    } });

                    // Add wind drift on leeward side (snow piles up)
                    if (config.enable_wind_drifts) {
                        const drift_offset_x = @sin(config.wind_direction) * config.drift_distance;
                        const drift_offset_z = @cos(config.wind_direction) * config.drift_distance;

                        // Drift zone is thick snow / deep powder
                        try snow_ops.append(allocator, .{ .circle = .{
                            .center = .{
                                .x = std.math.clamp(center.x + drift_offset_x, 0.0, 1.0),
                                .z = std.math.clamp(center.z + drift_offset_z, 0.0, 1.0),
                            },
                            .radius = config.drift_distance * 1.5,
                            .terrain_type = .deep_powder,
                        } });

                        // Add elevation bump for the drift
                        try elevation_ops.append(allocator, .{
                            .primitive = .{ .mound = .{
                                .center = .{
                                    .x = std.math.clamp(center.x + drift_offset_x, 0.0, 1.0),
                                    .z = std.math.clamp(center.z + drift_offset_z, 0.0, 1.0),
                                },
                                .radius = config.drift_distance * 1.2,
                                .height = config.drift_height,
                            } },
                            .blend = .add,
                        });
                    }
                }
            },

            .highway_primary, .highway_secondary, .highway_residential => {
                if (feature.geometry_type == .line_string) {
                    const norm_coords = try geoToNormalized(allocator, feature.coordinates, bounds);
                    defer allocator.free(norm_coords);

                    const RoadConfig = struct { depth: f32, width: f32, terrain: TerrainType };
                    const road_config: RoadConfig = switch (feature.feature_class) {
                        .highway_primary => .{
                            .depth = config.primary_road_depth,
                            .width = config.primary_road_width,
                            .terrain = config.road_terrain,
                        },
                        .highway_secondary => .{
                            .depth = config.secondary_road_depth,
                            .width = config.secondary_road_width,
                            .terrain = config.road_terrain,
                        },
                        else => .{
                            .depth = config.residential_road_depth,
                            .width = config.residential_road_width,
                            .terrain = .packed_snow, // Residential roads less icy
                        },
                    };

                    // Road depression
                    try elevation_ops.append(allocator, .{
                        .primitive = .{ .polyline = .{
                            .points = try allocator.dupe(NormalizedPos, norm_coords),
                            .width = road_config.width,
                            .height = road_config.depth,
                            .falloff = .smooth,
                        } },
                        .blend = .add,
                    });

                    // Road surface terrain
                    try addPolylineSnowZone(allocator, &snow_ops, norm_coords, road_config.width, road_config.terrain);

                    // Add sidewalk zones along roads (slightly narrower, packed snow)
                    const sidewalk_offset = road_config.width * 0.6;
                    try addPolylineSnowZone(allocator, &snow_ops, norm_coords, road_config.width + sidewalk_offset, config.footpath_terrain);
                }
            },

            .highway_footway => {
                if (feature.geometry_type == .line_string) {
                    const norm_coords = try geoToNormalized(allocator, feature.coordinates, bounds);
                    defer allocator.free(norm_coords);

                    try addPolylineSnowZone(allocator, &snow_ops, norm_coords, config.footpath_width, config.footpath_terrain);
                }
            },

            .water => {
                if (feature.geometry_type == .polygon) {
                    const norm_coords = try geoToNormalized(allocator, feature.coordinates, bounds);
                    defer allocator.free(norm_coords);

                    // Frozen water - slight depression
                    try elevation_ops.append(allocator, .{
                        .primitive = .{
                            .polygon = .{
                                .vertices = try allocator.dupe(NormalizedPos, norm_coords),
                                .height = -5.0,
                                .edge_falloff = 0.01,
                            },
                        },
                        .blend = .add,
                    });

                    try addPolygonSnowZone(allocator, &snow_ops, norm_coords, config.water_terrain);
                }
            },

            .park => {
                if (feature.geometry_type == .polygon) {
                    const norm_coords = try geoToNormalized(allocator, feature.coordinates, bounds);
                    defer allocator.free(norm_coords);

                    // Parks have pristine deep powder
                    try addPolygonSnowZone(allocator, &snow_ops, norm_coords, config.park_terrain);
                }
            },

            .parking => {
                if (feature.geometry_type == .polygon) {
                    const norm_coords = try geoToNormalized(allocator, feature.coordinates, bounds);
                    defer allocator.free(norm_coords);

                    // Parking lots are icy from car traffic
                    try addPolygonSnowZone(allocator, &snow_ops, norm_coords, config.parking_terrain);
                }
            },

            .tree => {
                if (feature.geometry_type == .point and feature.coordinates.len > 0) {
                    const norm = bounds.toNormalized(feature.coordinates[0]);
                    try prop_placements.append(allocator, .{
                        .prop_type = .pine_tree_medium,
                        .position = norm,
                        .rotation = 0.0,
                        .scale = 1.0,
                    });
                }
            },

            .unknown => {},
        }
    }

    // ========================================================================
    // PASS 3: Generate kid shortcut paths between nearby buildings
    // ========================================================================
    if (config.enable_kid_paths and building_centers.items.len > 1) {
        try generateKidPaths(allocator, &snow_ops, building_centers.items, config);
    }

    return .{
        .elevation_ops = try elevation_ops.toOwnedSlice(allocator),
        .snow_ops = try snow_ops.toOwnedSlice(allocator),
        .prop_placements = try prop_placements.toOwnedSlice(allocator),
        .building_data = try building_data.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

/// Convert array of GeoPoints to normalized coordinates
fn geoToNormalized(allocator: Allocator, points: []const GeoPoint, bounds: GeoBounds) ![]NormalizedPos {
    const result = try allocator.alloc(NormalizedPos, points.len);
    for (points, 0..) |p, i| {
        result[i] = bounds.toNormalized(p);
    }
    return result;
}

/// Calculate the centroid of a polygon
fn calculatePolygonCenter(vertices: []const NormalizedPos) NormalizedPos {
    if (vertices.len == 0) return .{ .x = 0.5, .z = 0.5 };

    var sum_x: f32 = 0;
    var sum_z: f32 = 0;
    for (vertices) |v| {
        sum_x += v.x;
        sum_z += v.z;
    }
    const n = @as(f32, @floatFromInt(vertices.len));
    return .{ .x = sum_x / n, .z = sum_z / n };
}

/// Bounding box result for polygon
const PolygonBBox = struct {
    min_x: f32,
    min_z: f32,
    max_x: f32,
    max_z: f32,
    width: f32,
    height: f32,
};

/// Calculate bounding box of a polygon
fn calculatePolygonBBox(vertices: []const NormalizedPos) PolygonBBox {
    if (vertices.len == 0) return .{
        .min_x = 0.5,
        .min_z = 0.5,
        .max_x = 0.5,
        .max_z = 0.5,
        .width = 0,
        .height = 0,
    };

    var min_x: f32 = 1.0;
    var min_z: f32 = 1.0;
    var max_x: f32 = 0.0;
    var max_z: f32 = 0.0;

    for (vertices) |v| {
        min_x = @min(min_x, v.x);
        min_z = @min(min_z, v.z);
        max_x = @max(max_x, v.x);
        max_z = @max(max_z, v.z);
    }

    return .{
        .min_x = min_x,
        .min_z = min_z,
        .max_x = max_x,
        .max_z = max_z,
        .width = max_x - min_x,
        .height = max_z - min_z,
    };
}

/// Generate kid shortcut paths between nearby buildings
/// Kids don't follow sidewalks - they cut through yards!
fn generateKidPaths(
    allocator: Allocator,
    snow_ops: *std.ArrayListUnmanaged(SnowZonePrimitive),
    building_centers: []const NormalizedPos,
    config: ConversionConfig,
) !void {
    // Connect nearby buildings with diagonal paths
    // These represent the shortcuts kids naturally create walking to friends' houses

    const max_path_distance: f32 = 0.12; // Only connect buildings within this distance
    const min_path_distance: f32 = 0.02; // Don't connect buildings that are too close (same lot)

    for (building_centers, 0..) |center_a, i| {
        // Only check buildings after this one to avoid duplicate paths
        for (building_centers[i + 1 ..]) |center_b| {
            const dx = center_b.x - center_a.x;
            const dz = center_b.z - center_a.z;
            const dist = @sqrt(dx * dx + dz * dz);

            // Check if buildings are at a good distance for a shortcut
            if (dist >= min_path_distance and dist <= max_path_distance) {
                // Add some randomness - not all possible paths exist
                // Use position-based hash for deterministic "randomness"
                const hash = @as(u32, @intFromFloat((center_a.x * 1000 + center_a.z * 100 + center_b.x * 10 + center_b.z) * 12345)) % 100;

                // ~30% of possible paths actually get worn in
                if (hash < 30) {
                    try snow_ops.append(allocator, .{ .path = .{
                        .start = center_a,
                        .end = center_b,
                        .width = config.kid_path_width,
                        .terrain_type = config.kid_path_terrain,
                    } });
                }
            }
        }
    }
}

/// Convert array of GeoPoints to world coordinate vertices for building geometry
/// World coordinates: centered arena with extent from -arena_size/2 to +arena_size/2
/// Default arena is 2000x2000 units (100 cells * 20 units/cell), so -1000 to +1000
///
/// KID SCALE: Coordinates are scaled by 3x (KID_SCALE) to make the world feel
/// bigger from a child's perspective. This means a 150m radius region becomes
/// effectively 50m in "kid perceived" space - everything is 3x larger!
fn geoToWorldVertices(allocator: Allocator, points: []const GeoPoint, bounds: GeoBounds) ![]buildings.WorldVertex {
    const result = try allocator.alloc(buildings.WorldVertex, points.len);

    // Arena dimensions (matching game_state defaults)
    const arena_size: f32 = 2000.0; // 100 cells * 20 units
    const half_size = arena_size / 2.0;

    for (points, 0..) |p, i| {
        const norm = bounds.toNormalized(p);
        // Convert normalized (0-1) to world coords (-1000 to +1000)
        // Then scale by KID_SCALE to make everything bigger!
        result[i] = .{
            .x = (norm.x * arena_size - half_size) * buildings.KID_SCALE,
            .z = (norm.z * arena_size - half_size) * buildings.KID_SCALE,
        };
    }
    return result;
}

/// Add snow zone for a polyline (approximated as series of paths)
fn addPolylineSnowZone(
    allocator: Allocator,
    snow_ops: *std.ArrayListUnmanaged(SnowZonePrimitive),
    points: []const NormalizedPos,
    width: f32,
    terrain: TerrainType,
) !void {
    if (points.len < 2) return;

    // Add a path primitive for each segment
    for (0..points.len - 1) |i| {
        try snow_ops.append(allocator, .{ .path = .{
            .start = points[i],
            .end = points[i + 1],
            .width = width,
            .terrain_type = terrain,
        } });
    }
}

/// Add snow zone for a polygon (approximated as bounding rect for now)
/// TODO: Implement proper polygon snow zones
fn addPolygonSnowZone(
    allocator: Allocator,
    snow_ops: *std.ArrayListUnmanaged(SnowZonePrimitive),
    vertices: []const NormalizedPos,
    terrain: TerrainType,
) !void {
    if (vertices.len < 3) return;

    // Find bounding box
    var min_x: f32 = 1.0;
    var min_z: f32 = 1.0;
    var max_x: f32 = 0.0;
    var max_z: f32 = 0.0;

    for (vertices) |v| {
        min_x = @min(min_x, v.x);
        min_z = @min(min_z, v.z);
        max_x = @max(max_x, v.x);
        max_z = @max(max_z, v.z);
    }

    try snow_ops.append(allocator, .{ .rect = .{
        .min = .{ .x = min_x, .z = min_z },
        .max = .{ .x = max_x, .z = max_z },
        .terrain_type = terrain,
    } });
}

// ============================================================================
// DEM / HEIGHTMAP LOADING
// ============================================================================

/// Load a raw heightmap file (simple binary format)
/// Format: width (u32), height (u32), then width*height f32 values (0.0-1.0)
pub fn loadRawHeightmap(allocator: Allocator, path: []const u8) !struct {
    data: []f32,
    width: usize,
    height: usize,
} {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var reader = file.reader();

    const width = try reader.readInt(u32, .little);
    const height = try reader.readInt(u32, .little);

    const data = try allocator.alloc(f32, @as(usize, width) * @as(usize, height));
    errdefer allocator.free(data);

    const bytes = std.mem.sliceAsBytes(data);
    const bytes_read = try reader.readAll(bytes);
    if (bytes_read != bytes.len) {
        return error.UnexpectedEndOfFile;
    }

    return .{
        .data = data,
        .width = @as(usize, width),
        .height = @as(usize, height),
    };
}

/// Load heightmap from a simple grayscale PGM image (ASCII P2 format)
/// This is easy to export from GIS tools
pub fn loadPgmHeightmap(allocator: Allocator, path: []const u8) !struct {
    data: []f32,
    width: usize,
    height: usize,
} {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 50 * 1024 * 1024);
    defer allocator.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');

    // Skip magic number (P2)
    _ = lines.next();

    // Skip comments
    var line = lines.next() orelse return error.InvalidFormat;
    while (line.len > 0 and line[0] == '#') {
        line = lines.next() orelse return error.InvalidFormat;
    }

    // Parse dimensions
    var dims = std.mem.splitScalar(u8, line, ' ');
    const width = try std.fmt.parseInt(usize, dims.next() orelse return error.InvalidFormat, 10);
    const height = try std.fmt.parseInt(usize, dims.next() orelse return error.InvalidFormat, 10);

    // Parse max value
    const max_val_str = lines.next() orelse return error.InvalidFormat;
    const max_val = try std.fmt.parseInt(u32, std.mem.trim(u8, max_val_str, " \t\r"), 10);
    const max_val_f: f32 = @floatFromInt(max_val);

    // Allocate data
    const data = try allocator.alloc(f32, width * height);
    errdefer allocator.free(data);

    // Parse values
    var idx: usize = 0;
    while (lines.next()) |data_line| {
        var values = std.mem.tokenizeAny(u8, data_line, " \t\r");
        while (values.next()) |val_str| {
            if (idx >= data.len) break;
            const val = try std.fmt.parseInt(u32, val_str, 10);
            data[idx] = @as(f32, @floatFromInt(val)) / max_val_f;
            idx += 1;
        }
    }

    return .{
        .data = data,
        .width = width,
        .height = height,
    };
}

// ============================================================================
// HIGH-LEVEL API
// ============================================================================

/// Load a real-world location and convert to arena primitives
/// This is the main entry point for creating real-location arenas
pub fn loadRealLocation(
    allocator: Allocator,
    geojson_path: []const u8,
    heightmap_path: ?[]const u8,
    bounds: GeoBounds,
    config: ConversionConfig,
) !ConversionResult {
    // Load and parse GeoJSON
    const features = try parseGeoJsonFile(allocator, geojson_path, bounds);
    defer {
        for (features) |*f| {
            var mutable_f = f.*;
            mutable_f.deinit(allocator);
        }
        allocator.free(features);
    }

    // Convert features to primitives
    var result = try convertFeaturesToPrimitives(allocator, features, bounds, config);

    // If heightmap provided, add it as first elevation operation
    if (heightmap_path) |hp| {
        const heightmap = try loadPgmHeightmap(allocator, hp);

        // Create new elevation ops array with heightmap first
        var new_ops = try allocator.alloc(ElevationOp, result.elevation_ops.len + 1);
        new_ops[0] = .{
            .primitive = .{
                .external_heightmap = .{
                    .data = heightmap.data,
                    .source_width = heightmap.width,
                    .source_height = heightmap.height,
                    .amplitude = 30.0, // Adjust based on your terrain scale
                    .base_height = 0.0,
                    .interpolation = .bilinear,
                },
            },
            .blend = .replace,
        };
        @memcpy(new_ops[1..], result.elevation_ops);

        allocator.free(result.elevation_ops);
        result.elevation_ops = new_ops;
    }

    return result;
}

// ============================================================================
// TESTS
// ============================================================================

test "GeoBounds center radius" {
    const center = GeoPoint{ .lon = -71.0589, .lat = 42.3601 }; // Boston
    const bounds = GeoBounds.fromCenterRadius(center, 500.0); // 500m radius

    // Should contain center
    try std.testing.expect(bounds.contains(center));

    // Should be approximately 1km x 1km
    const width = bounds.widthMeters();
    const height = bounds.heightMeters();
    try std.testing.expect(width > 900 and width < 1100);
    try std.testing.expect(height > 900 and height < 1100);
}

test "GeoBounds to normalized" {
    const bounds = GeoBounds{
        .min_lon = -71.1,
        .min_lat = 42.3,
        .max_lon = -71.0,
        .max_lat = 42.4,
    };

    // Center should map to (0.5, 0.5)
    const center = bounds.toNormalized(.{ .lon = -71.05, .lat = 42.35 });
    try std.testing.expectApproxEqAbs(center.x, 0.5, 0.001);
    try std.testing.expectApproxEqAbs(center.z, 0.5, 0.001);

    // Min lat corner maps to (0, 1) because Z is flipped (north = -Z)
    // min_lat = south = high Z value
    const min_corner = bounds.toNormalized(.{ .lon = -71.1, .lat = 42.3 });
    try std.testing.expectApproxEqAbs(min_corner.x, 0.0, 0.001);
    try std.testing.expectApproxEqAbs(min_corner.z, 1.0, 0.001); // Flipped!

    // Max lat corner maps to (1, 0) because Z is flipped
    // max_lat = north = low Z value
    const max_corner = bounds.toNormalized(.{ .lon = -71.0, .lat = 42.4 });
    try std.testing.expectApproxEqAbs(max_corner.x, 1.0, 0.001);
    try std.testing.expectApproxEqAbs(max_corner.z, 0.0, 0.001); // Flipped!
}

test "FeatureClass from tags" {
    // This would need actual JSON parsing to test properly
    // Just verify the enum exists
    try std.testing.expect(FeatureClass.building != FeatureClass.highway_primary);
}

// ============================================================================
// HAYSBORO, CALGARY - A CHILDHOOD SNOWBALL BATTLEGROUND
// ============================================================================
//
// Haysboro is a residential neighborhood in Calgary, Alberta, Canada.
// This module provides pre-configured access to Haysboro GIS data for
// creating arenas based on real-world locations from the neighborhood.
//
// Notable locations in Haysboro:
// - Eugene Coste School
// - Our Lady of the Rockies High School
// - Woodman School
// - Multiple parks and green spaces
// - Classic Calgary residential streets
//
// The neighborhood spans approximately 1.9km x 2.5km centered around
// coordinates (50.9739°N, 114.0852°W)
//
// ============================================================================

/// Full Haysboro neighborhood bounds (from OSM data)
pub const HAYSBORO_BOUNDS = GeoBounds{
    .min_lon = -114.095708,
    .min_lat = 50.962598,
    .max_lon = -114.068574,
    .max_lat = 50.985514,
};

/// Center of Haysboro neighborhood
pub const HAYSBORO_CENTER = GeoPoint{
    .lon = -114.082141,
    .lat = 50.974056,
};

/// Pre-defined sub-regions within Haysboro for smaller arena slices
pub const HaysboroRegion = enum {
    /// The full neighborhood (~2km x 2.5km) - too large for single arena
    full_neighborhood,

    /// Eugene Coste School area - elementary school and surrounding yards
    eugene_coste_school,

    /// Woodman School area - another school grounds
    woodman_school,

    /// Central residential area - classic Calgary streets
    central_streets,

    /// Our Lady of the Rockies area
    our_lady_of_rockies,

    /// Haysboro School area
    haysboro_school,

    pub fn getBounds(self: HaysboroRegion) GeoBounds {
        return switch (self) {
            .full_neighborhood => HAYSBORO_BOUNDS,

            // Eugene Coste School - actual location from OSM
            .eugene_coste_school => GeoBounds.fromCenterRadius(
                .{ .lon = -114.0870, .lat = 50.9677 },
                150.0,
            ),

            // Woodman School area - actual location from OSM
            .woodman_school => GeoBounds.fromCenterRadius(
                .{ .lon = -114.0835, .lat = 50.9753 },
                150.0,
            ),

            // Central residential streets
            .central_streets => GeoBounds.fromCenterRadius(
                HAYSBORO_CENTER,
                200.0,
            ),

            // Our Lady of the Rockies High School
            .our_lady_of_rockies => GeoBounds.fromCenterRadius(
                .{ .lon = -114.0797, .lat = 50.9756 },
                150.0,
            ),

            // Haysboro School
            .haysboro_school => GeoBounds.fromCenterRadius(
                .{ .lon = -114.0895, .lat = 50.9752 },
                150.0,
            ),
        };
    }

    pub fn getName(self: HaysboroRegion) [:0]const u8 {
        return switch (self) {
            .full_neighborhood => "Haysboro",
            .eugene_coste_school => "Eugene Coste School",
            .woodman_school => "Woodman School",
            .central_streets => "Haysboro Streets",
            .our_lady_of_rockies => "Our Lady of the Rockies",
            .haysboro_school => "Haysboro School",
        };
    }

    pub fn getDescription(self: HaysboroRegion) [:0]const u8 {
        return switch (self) {
            .full_neighborhood => "The full Haysboro neighborhood in Calgary",
            .eugene_coste_school => "The schoolyard where it all began",
            .woodman_school => "Another battleground across the neighborhood",
            .central_streets => "Classic Calgary residential streets",
            .our_lady_of_rockies => "The high school grounds - bigger kids territory",
            .haysboro_school => "Elementary school with open fields",
        };
    }
};

/// Configuration optimized for Haysboro's scale and features
/// Tuned for authentic Calgary winter feel
pub const HAYSBORO_CONFIG = ConversionConfig{
    // Calgary houses are typically single-story with basements
    .building_height = 35.0,
    .building_falloff = 0.003,

    // Calgary streets are wider than average (snow removal equipment)
    .primary_road_depth = -3.0,
    .primary_road_width = 0.05,
    .secondary_road_depth = -2.5,
    .secondary_road_width = 0.04,
    .residential_road_depth = -2.0,
    .residential_road_width = 0.035,

    // Generous sidewalks/paths
    .footpath_width = 0.015,

    // ========================================================================
    // CALGARY WINTER TERRAIN - Authentic patterns
    // ========================================================================

    // Yards start as thick snow (gets packed near buildings)
    .yard_terrain = .thick_snow,

    // Main roads are icy (plowed, salted, refreezes)
    .road_terrain = .icy_ground,

    // Sidewalks and footpaths are packed from foot traffic
    .footpath_terrain = .packed_snow,

    // Parking lots are icy (cars polish it)
    .parking_terrain = .icy_ground,

    // Parks and open fields are pristine powder
    .park_terrain = .deep_powder,

    // Frozen ponds
    .water_terrain = .icy_ground,

    // Building perimeters - packed from people walking around
    .building_perimeter_terrain = .packed_snow,
    .building_perimeter_width = 0.008,

    // Snow taper around buildings - thick snow ring before packed zone
    .enable_building_snow_taper = true,
    .building_taper_width = 0.025,
    .building_taper_terrain = .thick_snow,

    // Entrances are shoveled clear
    .entrance_terrain = .cleared_ground,
    .entrance_size = 0.01,

    // ========================================================================
    // CALGARY WIND DRIFTS
    // ========================================================================
    // Prevailing winds from NW create drifts on SE side of buildings
    .enable_wind_drifts = true,
    .wind_direction = 0.7, // ~40 degrees from north (NW wind)
    .drift_distance = 0.012,
    .drift_height = 12.0,

    // ========================================================================
    // KID PATHS - Shortcuts through yards
    // ========================================================================
    .enable_kid_paths = true,
    .kid_path_terrain = .packed_snow,
    .kid_path_width = 0.005,
};

/// Load Haysboro GeoJSON data for a specific region
/// Returns primitives ready to apply to an ArenaRecipe
pub fn loadHaysboroRegion(
    allocator: Allocator,
    region: HaysboroRegion,
) !ConversionResult {
    // Path to the pre-downloaded Haysboro GeoJSON
    const geojson_path = "data/haysboro/haysboro.geojson";

    return loadRealLocation(
        allocator,
        geojson_path,
        null, // No heightmap yet - Calgary is relatively flat
        region.getBounds(),
        HAYSBORO_CONFIG,
    );
}

/// Create a complete ArenaRecipe from Haysboro data
/// This allocates an ArenaRecipe that must be freed with freeHaysboroRecipe
pub fn createHaysboroArenaRecipe(
    allocator: Allocator,
    region: HaysboroRegion,
) !*arena_gen.ArenaRecipe {
    // Load GIS data
    var conversion = try loadHaysboroRegion(allocator, region);
    errdefer conversion.deinit();

    // Allocate the recipe
    const recipe = try allocator.create(arena_gen.ArenaRecipe);

    // Copy name (it's a static string, no allocation needed)
    recipe.* = arena_gen.ArenaRecipe{
        .name = region.getName(),
        .elevation_ops = conversion.elevation_ops,
        .snow_ops = conversion.snow_ops,
        .prop_placements = conversion.prop_placements,
        .collection_placements = &[_]props.CollectionPlacement{},
        .smoothing_passes = 3, // Extra smoothing for real-world data
        .seed = 0,
    };

    // Free building data that won't be used (caller should use loadHaysboroArenaData instead)
    for (conversion.building_data) |bd| {
        allocator.free(bd.vertices);
    }
    allocator.free(conversion.building_data);

    // Transfer ownership - don't deinit conversion
    return recipe;
}

/// Combined arena data including recipe and buildings
pub const HaysboroArenaData = struct {
    recipe: *arena_gen.ArenaRecipe,
    building_data: []BuildingData,
    allocator: Allocator,
    /// Arena dimensions in world units (after KID_SCALE applied)
    arena_width: f32,
    arena_height: f32,

    pub fn deinit(self: *HaysboroArenaData) void {
        freeHaysboroRecipe(self.allocator, self.recipe);
        for (self.building_data) |bd| {
            self.allocator.free(bd.vertices);
        }
        self.allocator.free(self.building_data);
    }
};

/// Load Haysboro arena data including both terrain recipe AND building geometry
/// This is the preferred function when you want full 3D building rendering
pub fn loadHaysboroArenaData(
    allocator: Allocator,
    region: HaysboroRegion,
) !HaysboroArenaData {
    // Calculate arena dimensions (base size scaled by KID_SCALE)
    const base_arena_size: f32 = 2000.0; // Base arena size in world units
    const arena_width = base_arena_size * buildings.KID_SCALE;
    const arena_height = base_arena_size * buildings.KID_SCALE;

    // Load GIS data
    var conversion = try loadHaysboroRegion(allocator, region);
    errdefer conversion.deinit();

    // Allocate the recipe
    const recipe = try allocator.create(arena_gen.ArenaRecipe);
    errdefer allocator.destroy(recipe);

    // Copy name (it's a static string, no allocation needed)
    recipe.* = arena_gen.ArenaRecipe{
        .name = region.getName(),
        .elevation_ops = conversion.elevation_ops,
        .snow_ops = conversion.snow_ops,
        .prop_placements = conversion.prop_placements,
        .collection_placements = &[_]props.CollectionPlacement{},
        .smoothing_passes = 3, // Extra smoothing for real-world data
        .seed = 0,
    };

    // Return both recipe and building data with arena dimensions
    return HaysboroArenaData{
        .recipe = recipe,
        .building_data = conversion.building_data,
        .allocator = allocator,
        .arena_width = arena_width,
        .arena_height = arena_height,
    };
}

/// Free a Haysboro arena recipe created by createHaysboroArenaRecipe
pub fn freeHaysboroRecipe(allocator: Allocator, recipe: *arena_gen.ArenaRecipe) void {
    // Free the dynamic arrays
    for (recipe.elevation_ops) |op| {
        switch (op.primitive) {
            .polygon => |p| allocator.free(p.vertices),
            .polyline => |p| allocator.free(p.points),
            .external_heightmap => |h| allocator.free(h.data),
            else => {},
        }
    }
    allocator.free(recipe.elevation_ops);
    allocator.free(recipe.snow_ops);
    allocator.free(recipe.prop_placements);
    allocator.destroy(recipe);
}

// ============================================================================
// HAYSBORO TESTS
// ============================================================================

test "Haysboro bounds contain center" {
    try std.testing.expect(HAYSBORO_BOUNDS.contains(HAYSBORO_CENTER));
}

test "Haysboro region bounds" {
    // All regions should be within the full neighborhood bounds
    inline for (std.meta.fields(HaysboroRegion)) |field| {
        const region: HaysboroRegion = @enumFromInt(field.value);
        if (region == .full_neighborhood) continue;

        const sub_bounds = region.getBounds();
        // Check that the center of the sub-region is within full bounds
        const center = GeoPoint{
            .lon = (sub_bounds.min_lon + sub_bounds.max_lon) / 2.0,
            .lat = (sub_bounds.min_lat + sub_bounds.max_lat) / 2.0,
        };
        try std.testing.expect(HAYSBORO_BOUNDS.contains(center));
    }
}
