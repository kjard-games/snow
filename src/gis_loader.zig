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
    pub fn toNormalized(self: GeoBounds, point: GeoPoint) NormalizedPos {
        return .{
            .x = @floatCast((point.lon - self.min_lon) / (self.max_lon - self.min_lon)),
            .z = @floatCast((point.lat - self.min_lat) / (self.max_lat - self.min_lat)),
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

    /// Terrain type for roads
    road_terrain: TerrainType = .packed_snow,
    /// Terrain type for footpaths
    footpath_terrain: TerrainType = .cleared_ground,
    /// Terrain type for water
    water_terrain: TerrainType = .icy_ground,
    /// Terrain type for parks
    park_terrain: TerrainType = .thick_snow,
    /// Terrain type for parking lots
    parking_terrain: TerrainType = .cleared_ground,
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

                    // Also add a snow zone around building footprint (cleared area)
                    const norm_coords = try geoToNormalized(allocator, feature.coordinates, bounds);
                    defer allocator.free(norm_coords);
                    try addPolygonSnowZone(allocator, &snow_ops, norm_coords, .packed_snow);
                }
            },

            .highway_primary, .highway_secondary, .highway_residential => {
                if (feature.geometry_type == .line_string) {
                    const norm_coords = try geoToNormalized(allocator, feature.coordinates, bounds);
                    defer allocator.free(norm_coords);

                    const RoadConfig = struct { depth: f32, width: f32 };
                    const road_config: RoadConfig = switch (feature.feature_class) {
                        .highway_primary => .{ .depth = config.primary_road_depth, .width = config.primary_road_width },
                        .highway_secondary => .{ .depth = config.secondary_road_depth, .width = config.secondary_road_width },
                        else => .{ .depth = config.residential_road_depth, .width = config.residential_road_width },
                    };

                    try elevation_ops.append(allocator, .{
                        .primitive = .{ .polyline = .{
                            .points = try allocator.dupe(NormalizedPos, norm_coords),
                            .width = road_config.width,
                            .height = road_config.depth,
                            .falloff = .smooth,
                        } },
                        .blend = .add,
                    });

                    // Add snow zone for road surface
                    try addPolylineSnowZone(allocator, &snow_ops, norm_coords, road_config.width, config.road_terrain);
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
                    // Water becomes icy ground
                    const norm_coords = try geoToNormalized(allocator, feature.coordinates, bounds);
                    defer allocator.free(norm_coords);

                    // Add as a slight depression
                    try elevation_ops.append(allocator, .{
                        .primitive = .{
                            .polygon = .{
                                .vertices = try allocator.dupe(NormalizedPos, norm_coords),
                                .height = -5.0, // Slight depression
                                .edge_falloff = 0.01,
                            },
                        },
                        .blend = .add,
                    });

                    // Add icy terrain
                    try addPolygonSnowZone(allocator, &snow_ops, norm_coords, config.water_terrain);
                }
            },

            .park => {
                if (feature.geometry_type == .polygon) {
                    const norm_coords = try geoToNormalized(allocator, feature.coordinates, bounds);
                    defer allocator.free(norm_coords);

                    // Parks have thick snow
                    try addPolygonSnowZone(allocator, &snow_ops, norm_coords, config.park_terrain);
                }
            },

            .parking => {
                if (feature.geometry_type == .polygon) {
                    const norm_coords = try geoToNormalized(allocator, feature.coordinates, bounds);
                    defer allocator.free(norm_coords);

                    // Parking lots are cleared/packed
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

/// Convert array of GeoPoints to world coordinate vertices for building geometry
/// World coordinates: centered arena with extent from -arena_size/2 to +arena_size/2
/// Default arena is 2000x2000 units (100 cells * 20 units/cell), so -1000 to +1000
fn geoToWorldVertices(allocator: Allocator, points: []const GeoPoint, bounds: GeoBounds) ![]buildings.WorldVertex {
    const result = try allocator.alloc(buildings.WorldVertex, points.len);

    // Arena dimensions (matching game_state defaults)
    const arena_size: f32 = 2000.0; // 100 cells * 20 units
    const half_size = arena_size / 2.0;

    for (points, 0..) |p, i| {
        const norm = bounds.toNormalized(p);
        // Convert normalized (0-1) to world coords (-1000 to +1000)
        result[i] = .{
            .x = norm.x * arena_size - half_size,
            .z = norm.z * arena_size - half_size,
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

    // Min corner should map to (0, 0)
    const min_corner = bounds.toNormalized(.{ .lon = -71.1, .lat = 42.3 });
    try std.testing.expectApproxEqAbs(min_corner.x, 0.0, 0.001);
    try std.testing.expectApproxEqAbs(min_corner.z, 0.0, 0.001);
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
pub const HAYSBORO_CONFIG = ConversionConfig{
    // Calgary houses are typically single-story with basements
    .building_height = 35.0,
    .building_falloff = 0.003,

    // Calgary streets are wider than average (snow removal)
    .primary_road_depth = -3.0,
    .primary_road_width = 0.05,
    .secondary_road_depth = -2.5,
    .secondary_road_width = 0.04,
    .residential_road_depth = -2.0,
    .residential_road_width = 0.035,

    // Generous sidewalks/paths
    .footpath_width = 0.015,

    // Calgary winter terrain types
    .road_terrain = .packed_snow, // Plowed but snowy
    .footpath_terrain = .packed_snow, // Shoveled paths
    .water_terrain = .icy_ground, // Frozen ponds/streams
    .park_terrain = .deep_powder, // Untouched park snow
    .parking_terrain = .packed_snow, // School parking lots
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

    // Return both recipe and building data
    return HaysboroArenaData{
        .recipe = recipe,
        .building_data = conversion.building_data,
        .allocator = allocator,
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
