// ============================================================================
// NEIGHBORHOOD PROFILE - Statistical DNA for Procedural Arena Generation
// ============================================================================
//
// Extracts statistical distributions from real-world GIS data (OSM/GeoJSON)
// that can be used to generate infinite procedural arenas that "feel" like
// the source neighborhoods.
//
// The system works with any city's data - Calgary, Copenhagen, NYC, Montreal, etc.
// The key insight is that we extract universal urban metrics, not city-specific data.
//
// Pipeline:
//   1. Load GeoJSON from curated neighborhoods
//   2. Extract statistical distributions (building density, footprints, roads, etc.)
//   3. Store as NeighborhoodProfile
//   4. Procedural generator samples from these distributions
//   5. FantasyAmplification layer ("juj") transforms for game feel
//
// ============================================================================

const std = @import("std");
const arena_gen = @import("arena_gen.zig");
const gis_loader = @import("gis_loader.zig");
const terrain_mod = @import("terrain.zig");
const buildings = @import("buildings.zig");

const Allocator = std.mem.Allocator;
const NormalizedPos = arena_gen.NormalizedPos;
const GeoFeature = gis_loader.GeoFeature;
const GeoBounds = gis_loader.GeoBounds;
const GeoPoint = gis_loader.GeoPoint;
const FeatureClass = gis_loader.FeatureClass;
const TerrainType = terrain_mod.TerrainType;
const BuildingType = buildings.BuildingType;

// ============================================================================
// STATISTICAL DISTRIBUTION TYPES
// ============================================================================

/// A simple statistical distribution for f32 values
pub const Distribution = struct {
    min: f32 = 0.0,
    max: f32 = 1.0,
    mean: f32 = 0.5,
    std_dev: f32 = 0.2,
    /// Number of samples used to create this distribution
    sample_count: u32 = 0,

    /// Sample a value from this distribution using the RNG
    pub fn sample(self: Distribution, rng: std.Random) f32 {
        // Box-Muller transform for normal distribution
        const rand1 = rng.float(f32);
        const rand2 = rng.float(f32);
        const z = @sqrt(-2.0 * @log(rand1 + 0.0001)) * @cos(2.0 * std.math.pi * rand2);
        const value = self.mean + z * self.std_dev;
        return std.math.clamp(value, self.min, self.max);
    }

    /// Sample uniformly between min and max (ignores mean/std_dev)
    pub fn sampleUniform(self: Distribution, rng: std.Random) f32 {
        return self.min + rng.float(f32) * (self.max - self.min);
    }

    /// Create from a slice of values
    pub fn fromSamples(values: []const f32) Distribution {
        if (values.len == 0) return .{};

        var min_val: f32 = values[0];
        var max_val: f32 = values[0];
        var sum: f32 = 0.0;

        for (values) |v| {
            min_val = @min(min_val, v);
            max_val = @max(max_val, v);
            sum += v;
        }

        const mean = sum / @as(f32, @floatFromInt(values.len));

        // Calculate standard deviation
        var variance_sum: f32 = 0.0;
        for (values) |v| {
            const diff = v - mean;
            variance_sum += diff * diff;
        }
        const std_dev = @sqrt(variance_sum / @as(f32, @floatFromInt(values.len)));

        return .{
            .min = min_val,
            .max = max_val,
            .mean = mean,
            .std_dev = std_dev,
            .sample_count = @intCast(values.len),
        };
    }
};

/// Distribution per building type
/// Note: Matches BuildingType enum in buildings.zig
pub const BuildingTypeDistribution = struct {
    residential_house: Distribution = .{ .min = 50.0, .max = 200.0, .mean = 100.0, .std_dev = 30.0 },
    residential_garage: Distribution = .{ .min = 20.0, .max = 60.0, .mean = 35.0, .std_dev = 10.0 },
    apartment_low: Distribution = .{ .min = 150.0, .max = 400.0, .mean = 250.0, .std_dev = 60.0 },
    apartment_mid: Distribution = .{ .min = 300.0, .max = 800.0, .mean = 500.0, .std_dev = 100.0 },
    commercial_small: Distribution = .{ .min = 100.0, .max = 500.0, .mean = 250.0, .std_dev = 80.0 },
    commercial_large: Distribution = .{ .min = 500.0, .max = 3000.0, .mean = 1200.0, .std_dev = 400.0 },
    school: Distribution = .{ .min = 1000.0, .max = 5000.0, .mean = 2500.0, .std_dev = 800.0 },
    church: Distribution = .{ .min = 200.0, .max = 1000.0, .mean = 500.0, .std_dev = 150.0 },
    industrial: Distribution = .{ .min = 500.0, .max = 5000.0, .mean = 2000.0, .std_dev = 800.0 },
    shed: Distribution = .{ .min = 10.0, .max = 40.0, .mean = 20.0, .std_dev = 8.0 },
    unknown: Distribution = .{ .min = 30.0, .max = 300.0, .mean = 100.0, .std_dev = 50.0 },

    pub fn getForType(self: *const BuildingTypeDistribution, building_type: BuildingType) Distribution {
        return switch (building_type) {
            .residential_house => self.residential_house,
            .residential_garage => self.residential_garage,
            .apartment_low => self.apartment_low,
            .apartment_mid => self.apartment_mid,
            .commercial_small => self.commercial_small,
            .commercial_large => self.commercial_large,
            .school => self.school,
            .church => self.church,
            .industrial => self.industrial,
            .shed => self.shed,
            .unknown => self.unknown,
        };
    }
};

/// Building height distributions (in METERS - real-world heights before KID_SCALE)
pub const BuildingHeightDistribution = struct {
    residential_house: Distribution = .{ .min = 6.0, .max = 10.0, .mean = 8.0, .std_dev = 1.0 },
    residential_garage: Distribution = .{ .min = 3.0, .max = 5.0, .mean = 4.0, .std_dev = 0.5 },
    apartment_low: Distribution = .{ .min = 8.0, .max = 12.0, .mean = 10.0, .std_dev = 1.5 },
    apartment_mid: Distribution = .{ .min = 15.0, .max = 25.0, .mean = 20.0, .std_dev = 3.0 },
    commercial_small: Distribution = .{ .min = 4.0, .max = 8.0, .mean = 6.0, .std_dev = 1.0 },
    commercial_large: Distribution = .{ .min = 6.0, .max = 12.0, .mean = 8.0, .std_dev = 1.5 },
    school: Distribution = .{ .min = 10.0, .max = 15.0, .mean = 12.0, .std_dev = 1.5 },
    church: Distribution = .{ .min = 12.0, .max = 20.0, .mean = 15.0, .std_dev = 2.0 },
    industrial: Distribution = .{ .min = 8.0, .max = 15.0, .mean = 10.0, .std_dev = 2.0 },
    shed: Distribution = .{ .min = 2.5, .max = 4.0, .mean = 3.0, .std_dev = 0.4 },
    unknown: Distribution = .{ .min = 5.0, .max = 10.0, .mean = 7.5, .std_dev = 1.5 },

    pub fn getForType(self: *const BuildingHeightDistribution, building_type: BuildingType) Distribution {
        return switch (building_type) {
            .residential_house => self.residential_house,
            .residential_garage => self.residential_garage,
            .apartment_low => self.apartment_low,
            .apartment_mid => self.apartment_mid,
            .commercial_small => self.commercial_small,
            .commercial_large => self.commercial_large,
            .school => self.school,
            .church => self.church,
            .industrial => self.industrial,
            .shed => self.shed,
            .unknown => self.unknown,
        };
    }
};

// ============================================================================
// NEIGHBORHOOD PROFILE
// ============================================================================

/// The statistical signature of a neighborhood
/// Captures the "DNA" that can be used to procedurally generate similar areas
pub const NeighborhoodProfile = struct {
    // ========================================================================
    // METADATA
    // ========================================================================

    /// Name of this profile (e.g., "Calgary Suburbs", "Copenhagen Karrer")
    name: []const u8 = "Unnamed Profile",

    /// Source city/region
    source_city: []const u8 = "Unknown",

    /// Region type classification
    region_type: RegionType = .suburban_residential,

    // ========================================================================
    // BUILDING DISTRIBUTIONS
    // ========================================================================

    /// Building density - buildings per 10,000 square meters (100m x 100m)
    building_density: Distribution = .{ .min = 5.0, .max = 30.0, .mean = 15.0, .std_dev = 5.0 },

    /// Building footprint areas (square meters)
    footprint_area: BuildingTypeDistribution = .{},

    /// Building heights by type (meters, real-world before KID_SCALE)
    building_height: BuildingHeightDistribution = .{},

    /// Probability weights for building types (0.0 to 1.0)
    building_type_weights: BuildingTypeWeights = .{},

    /// Spacing between buildings (meters)
    building_spacing: Distribution = .{ .min = 3.0, .max = 20.0, .mean = 8.0, .std_dev = 4.0 },

    // ========================================================================
    // STREET PATTERN DISTRIBUTIONS
    // ========================================================================

    /// Road sinuosity (1.0 = straight, 2.0+ = very curvy)
    /// Calculated as path_length / straight_line_distance
    road_sinuosity: Distribution = .{ .min = 1.0, .max = 1.5, .mean = 1.1, .std_dev = 0.1 },

    /// Road width (meters)
    road_width_primary: Distribution = .{ .min = 10.0, .max = 20.0, .mean = 14.0, .std_dev = 2.0 },
    road_width_secondary: Distribution = .{ .min = 8.0, .max = 14.0, .mean = 10.0, .std_dev = 1.5 },
    road_width_residential: Distribution = .{ .min = 6.0, .max = 10.0, .mean = 8.0, .std_dev = 1.0 },

    /// Intersection density - intersections per 100m of road
    intersection_density: Distribution = .{ .min = 0.5, .max = 2.0, .mean = 1.0, .std_dev = 0.3 },

    /// Block size (meters) - distance between intersections
    block_size: Distribution = .{ .min = 50.0, .max = 200.0, .mean = 100.0, .std_dev = 30.0 },

    /// Street grid regularity (0.0 = organic/medieval, 1.0 = perfect grid)
    grid_regularity: f32 = 0.3,

    // ========================================================================
    // TERRAIN CHARACTERISTICS
    // ========================================================================

    /// Elevation variance (meters)
    elevation_variance: Distribution = .{ .min = 0.0, .max = 10.0, .mean = 3.0, .std_dev = 2.0 },

    /// Percentage of area covered by parks/green space
    green_space_coverage: f32 = 0.15,

    /// Percentage of area covered by water features
    water_coverage: f32 = 0.0,

    /// Yard size (square meters) - space around buildings
    yard_size: Distribution = .{ .min = 50.0, .max = 500.0, .mean = 200.0, .std_dev = 100.0 },

    // ========================================================================
    // DERIVED METRICS
    // ========================================================================

    /// Total area analyzed (square meters)
    analyzed_area_m2: f32 = 0.0,

    /// Total number of buildings in source data
    total_buildings: u32 = 0,

    /// Total road length in source data (meters)
    total_road_length_m: f32 = 0.0,

    // ========================================================================
    // METHODS
    // ========================================================================

    /// Generate building count for a given area
    pub fn sampleBuildingCount(self: *const NeighborhoodProfile, area_m2: f32, rng: std.Random) u32 {
        const density = self.building_density.sample(rng);
        const expected_count = (area_m2 / 10000.0) * density;
        // Add some randomness around the expected count
        const variance = expected_count * 0.2;
        const count = expected_count + (rng.float(f32) - 0.5) * variance * 2.0;
        return @intFromFloat(@max(1.0, count));
    }

    /// Sample a building type based on weights
    pub fn sampleBuildingType(self: *const NeighborhoodProfile, rng: std.Random) BuildingType {
        return self.building_type_weights.sample(rng);
    }

    /// Sample footprint area for a building type
    pub fn sampleFootprintArea(self: *const NeighborhoodProfile, building_type: BuildingType, rng: std.Random) f32 {
        return self.footprint_area.getForType(building_type).sample(rng);
    }

    /// Sample building height for a type
    pub fn sampleBuildingHeight(self: *const NeighborhoodProfile, building_type: BuildingType, rng: std.Random) f32 {
        return self.building_height.getForType(building_type).sample(rng);
    }
};

/// Region type classification for different urban patterns
pub const RegionType = enum {
    suburban_residential, // Calgary, US suburbs - spread out, curvy streets
    urban_grid, // NYC, Chicago - dense grid pattern
    european_historic, // Copenhagen, Amsterdam - organic medieval core
    courtyard_blocks, // Berlin, Barcelona - perimeter block buildings
    mixed_use, // Mixed commercial/residential
    industrial, // Warehouses, factories
    campus, // Schools, universities, office parks

    /// Get default profile values for this region type
    pub fn getDefaults(self: RegionType) NeighborhoodProfile {
        return switch (self) {
            .suburban_residential => .{
                .region_type = self,
                .building_density = .{ .min = 8.0, .max = 25.0, .mean = 15.0, .std_dev = 4.0 },
                .road_sinuosity = .{ .min = 1.0, .max = 1.8, .mean = 1.2, .std_dev = 0.2 },
                .grid_regularity = 0.2,
                .green_space_coverage = 0.2,
                .yard_size = .{ .min = 100.0, .max = 600.0, .mean = 300.0, .std_dev = 120.0 },
            },
            .urban_grid => .{
                .region_type = self,
                .building_density = .{ .min = 30.0, .max = 80.0, .mean = 50.0, .std_dev = 12.0 },
                .road_sinuosity = .{ .min = 1.0, .max = 1.1, .mean = 1.02, .std_dev = 0.02 },
                .grid_regularity = 0.95,
                .green_space_coverage = 0.05,
                .yard_size = .{ .min = 0.0, .max = 50.0, .mean = 10.0, .std_dev = 15.0 },
            },
            .european_historic => .{
                .region_type = self,
                .building_density = .{ .min = 40.0, .max = 100.0, .mean = 65.0, .std_dev = 15.0 },
                .road_sinuosity = .{ .min = 1.2, .max = 2.5, .mean = 1.6, .std_dev = 0.3 },
                .grid_regularity = 0.1,
                .green_space_coverage = 0.08,
                .yard_size = .{ .min = 0.0, .max = 30.0, .mean = 5.0, .std_dev = 8.0 },
            },
            .courtyard_blocks => .{
                .region_type = self,
                .building_density = .{ .min = 35.0, .max = 70.0, .mean = 50.0, .std_dev = 10.0 },
                .road_sinuosity = .{ .min = 1.0, .max = 1.3, .mean = 1.1, .std_dev = 0.08 },
                .grid_regularity = 0.7,
                .green_space_coverage = 0.12,
                .yard_size = .{ .min = 20.0, .max = 100.0, .mean = 50.0, .std_dev = 25.0 },
            },
            .mixed_use => .{
                .region_type = self,
                .building_density = .{ .min = 20.0, .max = 60.0, .mean = 40.0, .std_dev = 12.0 },
                .road_sinuosity = .{ .min = 1.0, .max = 1.4, .mean = 1.15, .std_dev = 0.1 },
                .grid_regularity = 0.5,
                .green_space_coverage = 0.1,
            },
            .industrial => .{
                .region_type = self,
                .building_density = .{ .min = 5.0, .max = 20.0, .mean = 10.0, .std_dev = 4.0 },
                .road_sinuosity = .{ .min = 1.0, .max = 1.2, .mean = 1.05, .std_dev = 0.05 },
                .grid_regularity = 0.6,
                .green_space_coverage = 0.02,
            },
            .campus => .{
                .region_type = self,
                .building_density = .{ .min = 5.0, .max = 15.0, .mean = 8.0, .std_dev = 3.0 },
                .road_sinuosity = .{ .min = 1.1, .max = 1.5, .mean = 1.25, .std_dev = 0.12 },
                .grid_regularity = 0.4,
                .green_space_coverage = 0.35,
            },
        };
    }
};

/// Building type probability weights
/// Note: Matches BuildingType enum in buildings.zig
pub const BuildingTypeWeights = struct {
    residential_house: f32 = 0.60,
    residential_garage: f32 = 0.15,
    apartment_low: f32 = 0.05,
    apartment_mid: f32 = 0.02,
    commercial_small: f32 = 0.05,
    commercial_large: f32 = 0.02,
    school: f32 = 0.02,
    church: f32 = 0.01,
    industrial: f32 = 0.02,
    shed: f32 = 0.06,

    /// Sample a building type based on weights
    pub fn sample(self: BuildingTypeWeights, rng: std.Random) BuildingType {
        const total = self.residential_house + self.residential_garage +
            self.apartment_low + self.apartment_mid +
            self.commercial_small + self.commercial_large +
            self.school + self.church + self.industrial + self.shed;

        var r = rng.float(f32) * total;

        if (r < self.residential_house) return .residential_house;
        r -= self.residential_house;
        if (r < self.residential_garage) return .residential_garage;
        r -= self.residential_garage;
        if (r < self.apartment_low) return .apartment_low;
        r -= self.apartment_low;
        if (r < self.apartment_mid) return .apartment_mid;
        r -= self.apartment_mid;
        if (r < self.commercial_small) return .commercial_small;
        r -= self.commercial_small;
        if (r < self.commercial_large) return .commercial_large;
        r -= self.commercial_large;
        if (r < self.school) return .school;
        r -= self.school;
        if (r < self.church) return .church;
        r -= self.church;
        if (r < self.industrial) return .industrial;
        r -= self.industrial;

        return .shed;
    }

    /// Create from building type counts
    pub fn fromCounts(counts: *const std.EnumArray(BuildingType, u32)) BuildingTypeWeights {
        var total: f32 = 0;
        var type_iter = std.enums.EnumIndexer(BuildingType).init();
        while (type_iter.next()) |bt| {
            total += @floatFromInt(counts.get(bt));
        }

        if (total == 0) return .{}; // Return defaults

        return .{
            .residential_house = @as(f32, @floatFromInt(counts.get(.residential_house))) / total,
            .residential_garage = @as(f32, @floatFromInt(counts.get(.residential_garage))) / total,
            .apartment_low = @as(f32, @floatFromInt(counts.get(.apartment_low))) / total,
            .apartment_mid = @as(f32, @floatFromInt(counts.get(.apartment_mid))) / total,
            .commercial_small = @as(f32, @floatFromInt(counts.get(.commercial_small))) / total,
            .commercial_large = @as(f32, @floatFromInt(counts.get(.commercial_large))) / total,
            .school = @as(f32, @floatFromInt(counts.get(.school))) / total,
            .church = @as(f32, @floatFromInt(counts.get(.church))) / total,
            .industrial = @as(f32, @floatFromInt(counts.get(.industrial))) / total,
            .shed = @as(f32, @floatFromInt(counts.get(.shed))) / total,
        };
    }
};

// ============================================================================
// FANTASY AMPLIFICATION ("JUJ" LAYER)
// ============================================================================

/// Fantasy amplification transforms applied after generation
/// These make the procedural neighborhoods feel more game-like while
/// retaining the urban DNA of the source data
pub const FantasyAmplification = struct {
    // ========================================================================
    // ELEVATION AMPLIFICATION
    // ========================================================================

    /// Multiplier for hill heights (1.0 = realistic, 2.0 = double height)
    hill_amplitude: f32 = 1.5,

    /// Multiplier for valley/depression depths
    valley_depth: f32 = 1.3,

    /// Additional noise amplitude to add for variation
    noise_amplitude: f32 = 5.0,

    /// Noise frequency for added terrain variation
    noise_frequency: f32 = 3.0,

    // ========================================================================
    // STREET CURVATURE
    // ========================================================================

    /// Multiplier for road sinuosity (1.0 = as sampled, 1.5 = 50% more curvy)
    street_sinuosity_multiplier: f32 = 1.4,

    /// Perlin displacement applied to street segments (world units)
    street_perlin_displacement: f32 = 15.0,

    /// How often streets curve (lower = more curves per length)
    street_curve_frequency: f32 = 0.3,

    // ========================================================================
    // BUILDING DRAMA
    // ========================================================================

    /// Multiplier for building height variance
    height_variance_boost: f32 = 1.2,

    /// How much buildings cluster together (1.0 = as sampled, 2.0 = very clustered)
    cluster_intensity: f32 = 1.3,

    /// Probability of adding dramatic "looming" buildings
    dramatic_building_chance: f32 = 0.05,

    /// Height multiplier for dramatic buildings (kept modest to avoid sky-scraper heights)
    dramatic_building_height: f32 = 1.5,

    // ========================================================================
    // SNOW DRAMA
    // ========================================================================

    /// Multiplier for snow drift heights
    drift_height_multiplier: f32 = 1.5,

    /// How deep kid-worn paths are carved
    kid_path_depth: f32 = 2.0,

    /// Multiplier for drift coverage area
    drift_coverage_multiplier: f32 = 1.3,

    /// Extra thick snow probability in open areas
    thick_snow_bonus: f32 = 0.2,

    // ========================================================================
    // TACTICAL FEATURES
    // ========================================================================

    /// Probability of adding snow fort remnants
    snow_fort_chance: f32 = 0.15,

    /// Probability of adding elevated "sniper spots"
    elevated_spot_chance: f32 = 0.1,

    /// Probability of adding connecting tunnels/trenches
    trench_chance: f32 = 0.08,

    // ========================================================================
    // PRESETS
    // ========================================================================

    /// Realistic - minimal amplification
    pub const realistic = FantasyAmplification{
        .hill_amplitude = 1.0,
        .valley_depth = 1.0,
        .noise_amplitude = 2.0,
        .street_sinuosity_multiplier = 1.0,
        .street_perlin_displacement = 5.0,
        .height_variance_boost = 1.0,
        .cluster_intensity = 1.0,
        .drift_height_multiplier = 1.0,
        .kid_path_depth = 1.0,
        .snow_fort_chance = 0.05,
        .elevated_spot_chance = 0.02,
        .trench_chance = 0.02,
    };

    /// Standard game amplification
    pub const standard = FantasyAmplification{};

    /// High drama for exciting arenas
    pub const dramatic = FantasyAmplification{
        .hill_amplitude = 2.0,
        .valley_depth = 1.8,
        .noise_amplitude = 10.0,
        .street_sinuosity_multiplier = 1.8,
        .street_perlin_displacement = 25.0,
        .height_variance_boost = 1.5,
        .cluster_intensity = 1.8,
        .dramatic_building_chance = 0.15,
        .drift_height_multiplier = 2.0,
        .kid_path_depth = 3.0,
        .snow_fort_chance = 0.25,
        .elevated_spot_chance = 0.2,
        .trench_chance = 0.15,
    };

    /// Kid's imagination mode - maximum fantasy
    pub const imagination = FantasyAmplification{
        .hill_amplitude = 3.0,
        .valley_depth = 2.5,
        .noise_amplitude = 15.0,
        .street_sinuosity_multiplier = 2.5,
        .street_perlin_displacement = 40.0,
        .height_variance_boost = 2.0,
        .cluster_intensity = 2.5,
        .dramatic_building_chance = 0.3,
        .dramatic_building_height = 3.0,
        .drift_height_multiplier = 3.0,
        .kid_path_depth = 4.0,
        .drift_coverage_multiplier = 2.0,
        .thick_snow_bonus = 0.4,
        .snow_fort_chance = 0.4,
        .elevated_spot_chance = 0.3,
        .trench_chance = 0.25,
    };

    // ========================================================================
    // METHODS
    // ========================================================================

    /// Apply hill amplitude to a height value
    pub fn amplifyHeight(self: FantasyAmplification, height: f32) f32 {
        if (height > 0) {
            return height * self.hill_amplitude;
        } else {
            return height * self.valley_depth;
        }
    }

    /// Apply sinuosity multiplier
    pub fn amplifySinuosity(self: FantasyAmplification, sinuosity: f32) f32 {
        // Sinuosity of 1.0 stays 1.0, higher values get amplified more
        if (sinuosity <= 1.0) return sinuosity;
        const excess = sinuosity - 1.0;
        return 1.0 + excess * self.street_sinuosity_multiplier;
    }

    /// Should we add a dramatic building?
    pub fn shouldAddDramaticBuilding(self: FantasyAmplification, rng: std.Random) bool {
        return rng.float(f32) < self.dramatic_building_chance;
    }

    /// Should we add a snow fort?
    pub fn shouldAddSnowFort(self: FantasyAmplification, rng: std.Random) bool {
        return rng.float(f32) < self.snow_fort_chance;
    }

    /// Should we add an elevated spot?
    pub fn shouldAddElevatedSpot(self: FantasyAmplification, rng: std.Random) bool {
        return rng.float(f32) < self.elevated_spot_chance;
    }

    /// Should we add a trench?
    pub fn shouldAddTrench(self: FantasyAmplification, rng: std.Random) bool {
        return rng.float(f32) < self.trench_chance;
    }
};

// ============================================================================
// PROFILE EXTRACTOR
// ============================================================================

/// Extracts a NeighborhoodProfile from GeoJSON features
pub const ProfileExtractor = struct {
    allocator: Allocator,

    // Temporary storage for analysis
    building_areas: std.ArrayListUnmanaged(f32),
    building_type_counts: std.EnumArray(BuildingType, u32),
    road_lengths: std.ArrayListUnmanaged(f32),
    road_sinuosities: std.ArrayListUnmanaged(f32),
    building_spacings: std.ArrayListUnmanaged(f32),
    building_centers: std.ArrayListUnmanaged(GeoPoint),

    pub fn init(allocator: Allocator) ProfileExtractor {
        return .{
            .allocator = allocator,
            .building_areas = .empty,
            .building_type_counts = std.EnumArray(BuildingType, u32).initFill(0),
            .road_lengths = .empty,
            .road_sinuosities = .empty,
            .building_spacings = .empty,
            .building_centers = .empty,
        };
    }

    pub fn deinit(self: *ProfileExtractor) void {
        self.building_areas.deinit(self.allocator);
        self.road_lengths.deinit(self.allocator);
        self.road_sinuosities.deinit(self.allocator);
        self.building_spacings.deinit(self.allocator);
        self.building_centers.deinit(self.allocator);
    }

    /// Reset for a new extraction
    pub fn reset(self: *ProfileExtractor) void {
        self.building_areas.clearRetainingCapacity();
        self.building_type_counts = std.EnumArray(BuildingType, u32).initFill(0);
        self.road_lengths.clearRetainingCapacity();
        self.road_sinuosities.clearRetainingCapacity();
        self.building_spacings.clearRetainingCapacity();
        self.building_centers.clearRetainingCapacity();
    }

    /// Analyze features and extract a profile
    pub fn extractProfile(
        self: *ProfileExtractor,
        features: []const GeoFeature,
        bounds: GeoBounds,
        name: []const u8,
        source_city: []const u8,
    ) !NeighborhoodProfile {
        self.reset();

        // Calculate area of bounds
        const area_m2 = @as(f32, @floatCast(bounds.widthMeters() * bounds.heightMeters()));

        // Process each feature
        for (features) |feature| {
            try self.processFeature(feature);
        }

        // Calculate building spacings from centers
        try self.calculateBuildingSpacings();

        // Build the profile
        var profile = NeighborhoodProfile{
            .name = name,
            .source_city = source_city,
            .analyzed_area_m2 = area_m2,
            .total_buildings = @intCast(self.building_areas.items.len),
        };

        // Set distributions from collected data
        if (self.building_areas.items.len > 0) {
            profile.footprint_area.residential_house = Distribution.fromSamples(self.building_areas.items);

            // Calculate building density
            const buildings_per_10k = @as(f32, @floatFromInt(self.building_areas.items.len)) / (area_m2 / 10000.0);
            profile.building_density = .{
                .min = buildings_per_10k * 0.5,
                .max = buildings_per_10k * 1.5,
                .mean = buildings_per_10k,
                .std_dev = buildings_per_10k * 0.2,
                .sample_count = @intCast(self.building_areas.items.len),
            };
        }

        // Set building type weights
        profile.building_type_weights = BuildingTypeWeights.fromCounts(&self.building_type_counts);

        // Set road sinuosity distribution
        if (self.road_sinuosities.items.len > 0) {
            profile.road_sinuosity = Distribution.fromSamples(self.road_sinuosities.items);
        }

        // Set building spacing distribution
        if (self.building_spacings.items.len > 0) {
            profile.building_spacing = Distribution.fromSamples(self.building_spacings.items);
        }

        // Calculate total road length
        var total_road: f32 = 0;
        for (self.road_lengths.items) |len| {
            total_road += len;
        }
        profile.total_road_length_m = total_road;

        return profile;
    }

    fn processFeature(self: *ProfileExtractor, feature: GeoFeature) !void {
        switch (feature.feature_class) {
            .building => {
                if (feature.geometry_type == .polygon and feature.coordinates.len >= 3) {
                    // Calculate polygon area
                    const area = calculatePolygonArea(feature.coordinates);
                    try self.building_areas.append(self.allocator, area);

                    // Track building type
                    const current = self.building_type_counts.get(feature.building_type);
                    self.building_type_counts.set(feature.building_type, current + 1);

                    // Store center for spacing calculation
                    const center = calculatePolygonCenter(feature.coordinates);
                    try self.building_centers.append(self.allocator, center);
                }
            },
            .highway_primary, .highway_secondary, .highway_residential => {
                if (feature.geometry_type == .line_string and feature.coordinates.len >= 2) {
                    // Calculate path length
                    const path_length = calculatePathLength(feature.coordinates);
                    try self.road_lengths.append(self.allocator, path_length);

                    // Calculate sinuosity (path length / straight line distance)
                    const straight_dist = feature.coordinates[0].distanceMeters(
                        feature.coordinates[feature.coordinates.len - 1],
                    );
                    if (straight_dist > 1.0) { // Avoid division by tiny numbers
                        const sinuosity = path_length / @as(f32, @floatCast(straight_dist));
                        try self.road_sinuosities.append(self.allocator, sinuosity);
                    }
                }
            },
            else => {},
        }
    }

    fn calculateBuildingSpacings(self: *ProfileExtractor) !void {
        const centers = self.building_centers.items;
        if (centers.len < 2) return;

        // For each building, find distance to nearest neighbor
        for (centers, 0..) |center, i| {
            var min_dist: f32 = std.math.floatMax(f32);
            for (centers, 0..) |other, j| {
                if (i == j) continue;
                const dist: f32 = @floatCast(center.distanceMeters(other));
                min_dist = @min(min_dist, dist);
            }
            if (min_dist < std.math.floatMax(f32)) {
                try self.building_spacings.append(self.allocator, min_dist);
            }
        }
    }
};

// ============================================================================
// GEOMETRY HELPERS
// ============================================================================

/// Calculate the area of a polygon in square meters using the shoelace formula
fn calculatePolygonArea(points: []const GeoPoint) f32 {
    if (points.len < 3) return 0;

    // Use shoelace formula with Mercator approximation for area
    // First convert to approximate meters from first point
    const ref = points[0];
    const lat_scale: f64 = 111320.0; // meters per degree latitude
    const lon_scale: f64 = 111320.0 * @cos(ref.lat * std.math.pi / 180.0);

    var area: f64 = 0.0;
    const n = points.len;

    for (0..n) |i| {
        const j = (i + 1) % n;
        const x1 = (points[i].lon - ref.lon) * lon_scale;
        const y1 = (points[i].lat - ref.lat) * lat_scale;
        const x2 = (points[j].lon - ref.lon) * lon_scale;
        const y2 = (points[j].lat - ref.lat) * lat_scale;

        area += x1 * y2 - x2 * y1;
    }

    return @floatCast(@abs(area) / 2.0);
}

/// Calculate the center of a polygon
fn calculatePolygonCenter(points: []const GeoPoint) GeoPoint {
    if (points.len == 0) return .{ .lon = 0, .lat = 0 };

    var sum_lon: f64 = 0;
    var sum_lat: f64 = 0;

    for (points) |p| {
        sum_lon += p.lon;
        sum_lat += p.lat;
    }

    const n = @as(f64, @floatFromInt(points.len));
    return .{
        .lon = sum_lon / n,
        .lat = sum_lat / n,
    };
}

/// Calculate the length of a path in meters
fn calculatePathLength(points: []const GeoPoint) f32 {
    if (points.len < 2) return 0;

    var total: f64 = 0;
    for (0..points.len - 1) |i| {
        total += points[i].distanceMeters(points[i + 1]);
    }
    return @floatCast(total);
}

// ============================================================================
// BUILT-IN CITY PROFILES
// ============================================================================

/// Pre-built profiles for different city types
/// These can be used directly or as starting points for custom profiles
pub const profiles = struct {
    /// Calgary suburban profile (default, most tested)
    pub const calgary_suburbs = NeighborhoodProfile{
        .name = "Calgary Suburbs",
        .source_city = "Calgary, AB, Canada",
        .region_type = .suburban_residential,
        .building_density = .{ .min = 8.0, .max = 20.0, .mean = 12.0, .std_dev = 3.0 },
        .road_sinuosity = .{ .min = 1.0, .max = 1.6, .mean = 1.15, .std_dev = 0.15 },
        .grid_regularity = 0.25,
        .green_space_coverage = 0.18,
        .yard_size = .{ .min = 150.0, .max = 500.0, .mean = 280.0, .std_dev = 90.0 },
        .building_type_weights = .{
            .residential_house = 0.65,
            .residential_garage = 0.18,
            .shed = 0.08,
            .apartment_low = 0.03,
            .commercial_small = 0.02,
            .school = 0.02,
            .church = 0.01,
            .commercial_large = 0.01,
        },
    };

    /// Copenhagen profile (European historic)
    pub const copenhagen = NeighborhoodProfile{
        .name = "Copenhagen Districts",
        .source_city = "Copenhagen, Denmark",
        .region_type = .european_historic,
        .building_density = .{ .min = 45.0, .max = 90.0, .mean = 65.0, .std_dev = 12.0 },
        .road_sinuosity = .{ .min = 1.1, .max = 2.2, .mean = 1.5, .std_dev = 0.25 },
        .grid_regularity = 0.15,
        .green_space_coverage = 0.12,
        .yard_size = .{ .min = 0.0, .max = 50.0, .mean = 15.0, .std_dev = 12.0 },
        .building_type_weights = .{
            .apartment_low = 0.35,
            .apartment_mid = 0.25,
            .residential_house = 0.15,
            .commercial_small = 0.10,
            .commercial_large = 0.05,
            .church = 0.03,
            .school = 0.03,
            .industrial = 0.02,
            .shed = 0.02,
        },
    };

    /// NYC Brooklyn profile (urban grid)
    pub const brooklyn = NeighborhoodProfile{
        .name = "Brooklyn Neighborhoods",
        .source_city = "Brooklyn, NY, USA",
        .region_type = .urban_grid,
        .building_density = .{ .min = 50.0, .max = 100.0, .mean = 70.0, .std_dev = 15.0 },
        .road_sinuosity = .{ .min = 1.0, .max = 1.05, .mean = 1.02, .std_dev = 0.015 },
        .grid_regularity = 0.92,
        .green_space_coverage = 0.05,
        .yard_size = .{ .min = 0.0, .max = 30.0, .mean = 8.0, .std_dev = 8.0 },
        .building_type_weights = .{
            .apartment_low = 0.30,
            .apartment_mid = 0.20,
            .residential_house = 0.20,
            .commercial_small = 0.12,
            .commercial_large = 0.08,
            .industrial = 0.05,
            .school = 0.03,
            .church = 0.02,
        },
    };

    /// Montreal Plateau profile (mixed use, triplexes)
    pub const montreal_plateau = NeighborhoodProfile{
        .name = "Montreal Plateau",
        .source_city = "Montreal, QC, Canada",
        .region_type = .mixed_use,
        .building_density = .{ .min = 35.0, .max = 70.0, .mean = 50.0, .std_dev = 10.0 },
        .road_sinuosity = .{ .min = 1.0, .max = 1.15, .mean = 1.05, .std_dev = 0.04 },
        .grid_regularity = 0.85,
        .green_space_coverage = 0.08,
        .yard_size = .{ .min = 10.0, .max = 80.0, .mean = 35.0, .std_dev = 20.0 },
        .building_type_weights = .{
            .apartment_low = 0.50, // Triplexes
            .residential_house = 0.20,
            .commercial_small = 0.15, // Ground floor shops
            .apartment_mid = 0.05,
            .school = 0.03,
            .church = 0.03,
            .commercial_large = 0.02,
            .shed = 0.02,
        },
    };

    /// Berlin courtyard blocks
    pub const berlin_blocks = NeighborhoodProfile{
        .name = "Berlin Courtyard Blocks",
        .source_city = "Berlin, Germany",
        .region_type = .courtyard_blocks,
        .building_density = .{ .min = 40.0, .max = 75.0, .mean = 55.0, .std_dev = 10.0 },
        .road_sinuosity = .{ .min = 1.0, .max = 1.2, .mean = 1.08, .std_dev = 0.06 },
        .grid_regularity = 0.7,
        .green_space_coverage = 0.15,
        .yard_size = .{ .min = 30.0, .max = 150.0, .mean = 70.0, .std_dev = 35.0 },
        .building_type_weights = .{
            .apartment_mid = 0.40,
            .apartment_low = 0.25,
            .commercial_small = 0.15,
            .residential_house = 0.08,
            .commercial_large = 0.05,
            .school = 0.03,
            .industrial = 0.02,
            .church = 0.02,
        },
    };
};

// ============================================================================
// PROCEDURAL ARENA GENERATOR
// ============================================================================

/// Generated building placement for procedural arenas
pub const GeneratedBuilding = struct {
    /// Center position (normalized 0-1)
    center: NormalizedPos,
    /// Building type
    building_type: BuildingType,
    /// Footprint area (square meters, before any scaling)
    footprint_area_m2: f32,
    /// Building height (meters, before KID_SCALE)
    height_m: f32,
    /// Rotation (radians)
    rotation: f32,
    /// Footprint shape (normalized vertices relative to center)
    footprint: FootprintShape,
};

/// Simple footprint shapes for procedural buildings
pub const FootprintShape = enum {
    rectangle, // Standard rectangular building
    l_shape, // L-shaped building
    u_shape, // U-shaped courtyard building
    t_shape, // T-shaped building
    square, // Square building

    /// Get vertices for this shape (normalized, centered at origin)
    /// Width and depth are the overall bounding dimensions
    pub fn getVertices(self: FootprintShape, width: f32, depth: f32) [12]NormalizedPos {
        const hw = width / 2.0;
        const hd = depth / 2.0;

        return switch (self) {
            .rectangle, .square => .{
                .{ .x = -hw, .z = -hd },
                .{ .x = hw, .z = -hd },
                .{ .x = hw, .z = hd },
                .{ .x = -hw, .z = hd },
                // Padding (unused)
                .{ .x = 0, .z = 0 },
                .{ .x = 0, .z = 0 },
                .{ .x = 0, .z = 0 },
                .{ .x = 0, .z = 0 },
                .{ .x = 0, .z = 0 },
                .{ .x = 0, .z = 0 },
                .{ .x = 0, .z = 0 },
                .{ .x = 0, .z = 0 },
            },
            .l_shape => .{
                // L-shape: main rectangle with extension
                .{ .x = -hw, .z = -hd },
                .{ .x = 0, .z = -hd },
                .{ .x = 0, .z = 0 },
                .{ .x = hw, .z = 0 },
                .{ .x = hw, .z = hd },
                .{ .x = -hw, .z = hd },
                // Padding
                .{ .x = 0, .z = 0 },
                .{ .x = 0, .z = 0 },
                .{ .x = 0, .z = 0 },
                .{ .x = 0, .z = 0 },
                .{ .x = 0, .z = 0 },
                .{ .x = 0, .z = 0 },
            },
            .u_shape => .{
                // U-shape: courtyard building
                .{ .x = -hw, .z = -hd },
                .{ .x = hw, .z = -hd },
                .{ .x = hw, .z = hd },
                .{ .x = hw * 0.3, .z = hd },
                .{ .x = hw * 0.3, .z = 0 },
                .{ .x = -hw * 0.3, .z = 0 },
                .{ .x = -hw * 0.3, .z = hd },
                .{ .x = -hw, .z = hd },
                // Padding
                .{ .x = 0, .z = 0 },
                .{ .x = 0, .z = 0 },
                .{ .x = 0, .z = 0 },
                .{ .x = 0, .z = 0 },
            },
            .t_shape => .{
                // T-shape
                .{ .x = -hw, .z = -hd },
                .{ .x = hw, .z = -hd },
                .{ .x = hw, .z = -hd * 0.3 },
                .{ .x = hw * 0.3, .z = -hd * 0.3 },
                .{ .x = hw * 0.3, .z = hd },
                .{ .x = -hw * 0.3, .z = hd },
                .{ .x = -hw * 0.3, .z = -hd * 0.3 },
                .{ .x = -hw, .z = -hd * 0.3 },
                // Padding
                .{ .x = 0, .z = 0 },
                .{ .x = 0, .z = 0 },
                .{ .x = 0, .z = 0 },
                .{ .x = 0, .z = 0 },
            },
        };
    }

    /// Get the number of vertices for this shape
    pub fn vertexCount(self: FootprintShape) usize {
        return switch (self) {
            .rectangle, .square => 4,
            .l_shape => 6,
            .u_shape => 8,
            .t_shape => 8,
        };
    }

    /// Sample a random footprint shape based on building type
    pub fn sampleForType(building_type: BuildingType, rng: std.Random) FootprintShape {
        const r = rng.float(f32);
        return switch (building_type) {
            .residential_house => if (r < 0.7) .rectangle else if (r < 0.9) .l_shape else .t_shape,
            .residential_garage, .shed => .rectangle,
            .apartment_low, .apartment_mid => if (r < 0.5) .rectangle else if (r < 0.8) .l_shape else .u_shape,
            .commercial_small => if (r < 0.8) .rectangle else .l_shape,
            .commercial_large => if (r < 0.4) .rectangle else if (r < 0.7) .l_shape else .u_shape,
            .school => if (r < 0.3) .rectangle else if (r < 0.6) .l_shape else if (r < 0.8) .u_shape else .t_shape,
            .church => if (r < 0.6) .rectangle else .t_shape,
            .industrial => if (r < 0.7) .rectangle else .l_shape,
            .unknown => .rectangle,
        };
    }
};

/// Generated street segment
pub const GeneratedStreet = struct {
    /// Start point (normalized 0-1)
    start: NormalizedPos,
    /// End point (normalized 0-1)
    end: NormalizedPos,
    /// Width (normalized)
    width: f32,
    /// Road type
    road_type: RoadType,
    /// Intermediate points for curved streets
    waypoints: [8]NormalizedPos,
    /// Number of valid waypoints
    waypoint_count: u8,

    pub const RoadType = enum {
        primary,
        secondary,
        residential,
        footpath,
    };
};

/// Procedural arena generator using neighborhood profiles
pub const ProceduralArenaGenerator = struct {
    allocator: Allocator,
    prng: std.Random.DefaultPrng,
    seed: u64,

    // Generated content
    buildings: std.ArrayListUnmanaged(GeneratedBuilding),
    streets: std.ArrayListUnmanaged(GeneratedStreet),

    // Configuration
    profile: *const NeighborhoodProfile,
    amplification: FantasyAmplification,

    // Arena bounds (normalized, typically 0-1)
    arena_width: f32,
    arena_height: f32,

    pub fn init(
        allocator: Allocator,
        seed: u64,
        profile: *const NeighborhoodProfile,
        amplification: FantasyAmplification,
    ) ProceduralArenaGenerator {
        return .{
            .allocator = allocator,
            .prng = std.Random.DefaultPrng.init(seed),
            .seed = seed,
            .buildings = .empty,
            .streets = .empty,
            .profile = profile,
            .amplification = amplification,
            .arena_width = 1.0,
            .arena_height = 1.0,
        };
    }

    /// Get the random number generator
    fn rng(self: *ProceduralArenaGenerator) std.Random {
        return self.prng.random();
    }

    pub fn deinit(self: *ProceduralArenaGenerator) void {
        self.buildings.deinit(self.allocator);
        self.streets.deinit(self.allocator);
    }

    /// Generate a complete procedural neighborhood
    pub fn generate(self: *ProceduralArenaGenerator, arena_size_meters: f32) !void {
        // Clear previous generation
        self.buildings.clearRetainingCapacity();
        self.streets.clearRetainingCapacity();

        // Calculate area
        const area_m2 = arena_size_meters * arena_size_meters;

        // Generate street network first (buildings go between streets)
        try self.generateStreetNetwork(arena_size_meters);

        // Generate buildings using Poisson disk sampling
        try self.generateBuildings(area_m2, arena_size_meters);

        // Add tactical features based on amplification
        try self.addTacticalFeatures();
    }

    /// Generate the street network
    fn generateStreetNetwork(self: *ProceduralArenaGenerator, arena_size_meters: f32) !void {
        const profile = self.profile;

        // Determine grid vs organic layout based on regularity
        if (profile.grid_regularity > 0.7) {
            try self.generateGridStreets(arena_size_meters);
        } else if (profile.grid_regularity > 0.3) {
            try self.generateMixedStreets(arena_size_meters);
        } else {
            try self.generateOrganicStreets(arena_size_meters);
        }
    }

    /// Generate grid-based streets (NYC, Montreal style)
    fn generateGridStreets(self: *ProceduralArenaGenerator, arena_size_meters: f32) !void {
        const profile = self.profile;
        const block_size_normalized = profile.block_size.mean / arena_size_meters;

        // Main roads
        var x: f32 = 0.1;
        while (x < 0.9) : (x += block_size_normalized) {
            try self.streets.append(self.allocator, .{
                .start = .{ .x = x, .z = 0.05 },
                .end = .{ .x = x, .z = 0.95 },
                .width = profile.road_width_residential.mean / arena_size_meters,
                .road_type = if (x > 0.45 and x < 0.55) .primary else .residential,
                .waypoints = undefined,
                .waypoint_count = 0,
            });
        }

        // Cross roads
        var z: f32 = 0.1;
        while (z < 0.9) : (z += block_size_normalized) {
            try self.streets.append(self.allocator, .{
                .start = .{ .x = 0.05, .z = z },
                .end = .{ .x = 0.95, .z = z },
                .width = profile.road_width_residential.mean / arena_size_meters,
                .road_type = if (z > 0.45 and z < 0.55) .secondary else .residential,
                .waypoints = undefined,
                .waypoint_count = 0,
            });
        }
    }

    /// Generate mixed grid/organic streets (suburban with some structure)
    fn generateMixedStreets(self: *ProceduralArenaGenerator, arena_size_meters: f32) !void {
        const profile = self.profile;
        const sinuosity = self.amplification.amplifySinuosity(profile.road_sinuosity.sample(self.rng()));

        // Main arterial road (less curvy)
        try self.streets.append(self.allocator, .{
            .start = .{ .x = 0.5, .z = 0.0 },
            .end = .{ .x = 0.5, .z = 1.0 },
            .width = profile.road_width_primary.mean / arena_size_meters,
            .road_type = .primary,
            .waypoints = undefined,
            .waypoint_count = 0,
        });

        // Cross street
        try self.streets.append(self.allocator, .{
            .start = .{ .x = 0.0, .z = 0.5 },
            .end = .{ .x = 1.0, .z = 0.5 },
            .width = profile.road_width_secondary.mean / arena_size_meters,
            .road_type = .secondary,
            .waypoints = undefined,
            .waypoint_count = 0,
        });

        // Residential streets with curves
        const num_res_streets = 4 + self.rng().intRangeAtMost(u8, 0, 4);
        for (0..num_res_streets) |_| {
            const start_x = 0.1 + self.rng().float(f32) * 0.3;
            const start_z = self.rng().float(f32);
            const end_x = 0.6 + self.rng().float(f32) * 0.3;
            const end_z = self.rng().float(f32);

            var street = GeneratedStreet{
                .start = .{ .x = start_x, .z = start_z },
                .end = .{ .x = end_x, .z = end_z },
                .width = profile.road_width_residential.mean / arena_size_meters,
                .road_type = .residential,
                .waypoints = undefined,
                .waypoint_count = 0,
            };

            // Add curve waypoints based on sinuosity
            if (sinuosity > 1.1) {
                street.waypoint_count = @min(4, @as(u8, @intFromFloat((sinuosity - 1.0) * 10)));
                for (0..street.waypoint_count) |i| {
                    const t = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(street.waypoint_count + 1));
                    const base_x = start_x + (end_x - start_x) * t;
                    const base_z = start_z + (end_z - start_z) * t;
                    const offset = (self.rng().float(f32) - 0.5) * self.amplification.street_perlin_displacement / arena_size_meters;
                    street.waypoints[i] = .{
                        .x = std.math.clamp(base_x + offset, 0.05, 0.95),
                        .z = std.math.clamp(base_z + offset, 0.05, 0.95),
                    };
                }
            }

            try self.streets.append(self.allocator, street);
        }
    }

    /// Generate organic streets (Copenhagen, medieval style)
    fn generateOrganicStreets(self: *ProceduralArenaGenerator, arena_size_meters: f32) !void {
        const profile = self.profile;
        const sinuosity = self.amplification.amplifySinuosity(profile.road_sinuosity.sample(self.rng()));

        // Generate radial-ish pattern from center
        const num_streets = 5 + self.rng().intRangeAtMost(u8, 0, 5);

        for (0..num_streets) |i| {
            const angle = @as(f32, @floatFromInt(i)) * std.math.pi * 2.0 / @as(f32, @floatFromInt(num_streets));
            const angle_offset = (self.rng().float(f32) - 0.5) * 0.5;

            const start_x = 0.5 + @cos(angle + angle_offset) * 0.1;
            const start_z = 0.5 + @sin(angle + angle_offset) * 0.1;
            const end_x = 0.5 + @cos(angle + angle_offset) * 0.45;
            const end_z = 0.5 + @sin(angle + angle_offset) * 0.45;

            var street = GeneratedStreet{
                .start = .{ .x = start_x, .z = start_z },
                .end = .{ .x = end_x, .z = end_z },
                .width = profile.road_width_residential.mean / arena_size_meters,
                .road_type = if (i % 3 == 0) .secondary else .residential,
                .waypoints = undefined,
                .waypoint_count = 0,
            };

            // More curves for organic streets
            street.waypoint_count = @min(6, @as(u8, @intFromFloat((sinuosity - 1.0) * 15)));
            for (0..street.waypoint_count) |wi| {
                const t = @as(f32, @floatFromInt(wi + 1)) / @as(f32, @floatFromInt(street.waypoint_count + 1));
                const base_x = start_x + (end_x - start_x) * t;
                const base_z = start_z + (end_z - start_z) * t;
                const offset_x = (self.rng().float(f32) - 0.5) * self.amplification.street_perlin_displacement * 1.5 / arena_size_meters;
                const offset_z = (self.rng().float(f32) - 0.5) * self.amplification.street_perlin_displacement * 1.5 / arena_size_meters;
                street.waypoints[wi] = .{
                    .x = std.math.clamp(base_x + offset_x, 0.05, 0.95),
                    .z = std.math.clamp(base_z + offset_z, 0.05, 0.95),
                };
            }

            try self.streets.append(self.allocator, street);
        }
    }

    /// Generate buildings using Poisson disk sampling
    fn generateBuildings(self: *ProceduralArenaGenerator, area_m2: f32, arena_size_meters: f32) !void {
        const profile = self.profile;
        const num_buildings = profile.sampleBuildingCount(area_m2, self.rng());

        // Use simple rejection sampling for building placement
        // (A real implementation would use proper Poisson disk sampling)
        const min_spacing_normalized = profile.building_spacing.min / arena_size_meters;

        var attempts: u32 = 0;
        const max_attempts = num_buildings * 20;

        while (self.buildings.items.len < num_buildings and attempts < max_attempts) {
            attempts += 1;

            // Sample random position (avoiding edges and streets)
            const x = 0.1 + self.rng().float(f32) * 0.8;
            const z = 0.1 + self.rng().float(f32) * 0.8;
            const pos = NormalizedPos{ .x = x, .z = z };

            // Check if too close to existing buildings
            var too_close = false;
            for (self.buildings.items) |existing| {
                if (pos.distanceTo(existing.center) < min_spacing_normalized) {
                    too_close = true;
                    break;
                }
            }
            if (too_close) continue;

            // Check if on a street
            var on_street = false;
            for (self.streets.items) |street| {
                if (distanceToStreet(pos, street) < street.width * 1.5) {
                    on_street = true;
                    break;
                }
            }
            if (on_street) continue;

            // Generate building
            const building_type = profile.sampleBuildingType(self.rng());
            var footprint_area = profile.sampleFootprintArea(building_type, self.rng());
            var height = profile.sampleBuildingHeight(building_type, self.rng());

            // Apply amplification for dramatic buildings
            if (self.amplification.shouldAddDramaticBuilding(self.rng())) {
                height *= self.amplification.dramatic_building_height;
                footprint_area *= 1.3;
            }

            try self.buildings.append(self.allocator, .{
                .center = pos,
                .building_type = building_type,
                .footprint_area_m2 = footprint_area,
                .height_m = height,
                .rotation = self.rng().float(f32) * std.math.pi * 2.0,
                .footprint = FootprintShape.sampleForType(building_type, self.rng()),
            });
        }
    }

    /// Add tactical features (snow forts, elevated spots, etc.)
    fn addTacticalFeatures(self: *ProceduralArenaGenerator) !void {
        _ = self;
        // TODO: Add snow forts, elevated spots, trenches based on amplification settings
        // These would be separate from buildings - special game features
    }

    /// Convert generated content to arena primitives
    pub fn toArenaRecipe(
        self: *const ProceduralArenaGenerator,
        allocator: Allocator,
        arena_size_meters: f32,
    ) !*arena_gen.ArenaRecipe {
        var elevation_ops = std.ArrayListUnmanaged(arena_gen.ElevationOp).empty;
        errdefer elevation_ops.deinit(allocator);

        var snow_ops = std.ArrayListUnmanaged(arena_gen.SnowZonePrimitive).empty;
        errdefer snow_ops.deinit(allocator);

        // Start with flat base (like all working templates)
        try elevation_ops.append(allocator, .{
            .primitive = .{ .flat = .{ .height = 0.0 } },
            .blend = .replace,
        });

        // Add subtle terrain noise
        try elevation_ops.append(allocator, .{
            .primitive = .{ .noise = .{
                .seed = self.seed,
                .amplitude = self.amplification.noise_amplitude,
                .frequency = self.amplification.noise_frequency,
                .octaves = 3,
            } },
            .blend = .add,
        });

        // Base snow
        try snow_ops.append(allocator, .{ .fill = .{ .terrain_type = .thick_snow } });

        // Add streets as depressions and packed snow
        for (self.streets.items) |street| {
            // Street depression
            const points = try allocator.alloc(NormalizedPos, 2 + street.waypoint_count);
            points[0] = street.start;
            for (0..street.waypoint_count) |i| {
                points[i + 1] = street.waypoints[i];
            }
            points[points.len - 1] = street.end;

            try elevation_ops.append(allocator, .{
                .primitive = .{ .polyline = .{
                    .points = points,
                    .width = street.width,
                    .height = -3.0,
                    .falloff = .smooth,
                } },
                .blend = .add,
            });

            // Street snow type
            const terrain_type: TerrainType = switch (street.road_type) {
                .primary, .secondary => .icy_ground,
                .residential => .packed_snow,
                .footpath => .packed_snow,
            };

            try snow_ops.append(allocator, .{ .path = .{
                .start = street.start,
                .end = street.end,
                .width = street.width,
                .terrain_type = terrain_type,
            } });
        }

        // Add buildings as elevation and snow
        for (self.buildings.items) |building| {
            // Building footprint size (normalized)
            const footprint_side = @sqrt(building.footprint_area_m2) / arena_size_meters;

            // Convert height from meters to game units
            // buildings.zig uses: 6.67 units per meter * KID_SCALE (2.2)
            const units_per_meter: f32 = 6.67;
            const raw_height = building.height_m * units_per_meter * buildings.KID_SCALE;
            const amplified_height = self.amplification.amplifyHeight(raw_height);
            // Cap building heights to prevent absurdly tall structures (max ~30m real height)
            const max_building_height: f32 = 450.0;
            const height_in_units = @min(amplified_height, max_building_height);

            // Building mound (simplified - real implementation would use polygon)
            // Use very small edge_falloff for sharp building edges (falloff < footprint size)
            try elevation_ops.append(allocator, .{
                .primitive = .{
                    .plateau = .{
                        .min = .{
                            .x = building.center.x - footprint_side / 2,
                            .z = building.center.z - footprint_side / 2,
                        },
                        .max = .{
                            .x = building.center.x + footprint_side / 2,
                            .z = building.center.z + footprint_side / 2,
                        },
                        .height = height_in_units,
                        .edge_falloff = 0.001, // Much smaller than footprint (~0.006) for flat tops
                    },
                },
                .blend = .max,
            });

            // Building perimeter snow
            try snow_ops.append(allocator, .{ .rect = .{
                .min = .{
                    .x = building.center.x - footprint_side / 2 - 0.02,
                    .z = building.center.z - footprint_side / 2 - 0.02,
                },
                .max = .{
                    .x = building.center.x + footprint_side / 2 + 0.02,
                    .z = building.center.z + footprint_side / 2 + 0.02,
                },
                .terrain_type = .packed_snow,
            } });
        }

        // Boundary walls
        try elevation_ops.append(allocator, .{
            .primitive = .{ .boundary_wall = .{
                .height = 60.0,
                .thickness = 0.06,
                .irregularity = 0.5,
                .seed = self.seed,
            } },
            .blend = .max,
        });

        // Create recipe
        const recipe = try allocator.create(arena_gen.ArenaRecipe);
        recipe.* = .{
            .name = "Procedural Neighborhood",
            .elevation_ops = try elevation_ops.toOwnedSlice(allocator),
            .snow_ops = try snow_ops.toOwnedSlice(allocator),
            .smoothing_passes = 2,
            .seed = self.seed,
        };

        return recipe;
    }
};

/// Calculate distance from a point to a street segment
fn distanceToStreet(pos: NormalizedPos, street: GeneratedStreet) f32 {
    // Simple version - just distance to line segment
    // TODO: Handle waypoints for curved streets
    const dx = street.end.x - street.start.x;
    const dz = street.end.z - street.start.z;
    const len_sq = dx * dx + dz * dz;

    if (len_sq < 0.0001) return pos.distanceTo(street.start);

    const t = std.math.clamp(
        ((pos.x - street.start.x) * dx + (pos.z - street.start.z) * dz) / len_sq,
        0.0,
        1.0,
    );

    const proj = NormalizedPos{
        .x = street.start.x + t * dx,
        .z = street.start.z + t * dz,
    };

    return pos.distanceTo(proj);
}

// ============================================================================
// HIGH-LEVEL API
// ============================================================================

/// Generate a procedural arena from a neighborhood profile
pub fn generateProceduralArena(
    allocator: Allocator,
    profile: *const NeighborhoodProfile,
    amplification: FantasyAmplification,
    seed: u64,
    arena_size_meters: f32,
) !*arena_gen.ArenaRecipe {
    var generator = ProceduralArenaGenerator.init(allocator, seed, profile, amplification);
    defer generator.deinit();

    try generator.generate(arena_size_meters);
    return generator.toArenaRecipe(allocator, arena_size_meters);
}

/// Extract a profile from GeoJSON and generate an arena from it
pub fn generateArenaFromGeoJson(
    allocator: Allocator,
    geojson_path: []const u8,
    bounds: GeoBounds,
    amplification: FantasyAmplification,
    seed: u64,
    arena_size_meters: f32,
) !*arena_gen.ArenaRecipe {
    // Parse GeoJSON
    const features = try gis_loader.parseGeoJsonFile(allocator, geojson_path, bounds);
    defer {
        for (features) |*f| {
            var mf = f.*;
            mf.deinit(allocator);
        }
        allocator.free(features);
    }

    // Extract profile
    var extractor = ProfileExtractor.init(allocator);
    defer extractor.deinit();

    const profile = try extractor.extractProfile(features, bounds, "Extracted Profile", "Unknown");

    // Generate arena
    return generateProceduralArena(allocator, &profile, amplification, seed, arena_size_meters);
}

// ============================================================================
// TESTS
// ============================================================================

test "Distribution sampling" {
    const dist = Distribution{ .min = 0.0, .max = 100.0, .mean = 50.0, .std_dev = 10.0 };

    var prng = std.Random.DefaultPrng.init(12345);
    const rng = prng.random();

    // Sample multiple times and verify range
    for (0..100) |_| {
        const sample = dist.sample(rng);
        try std.testing.expect(sample >= dist.min);
        try std.testing.expect(sample <= dist.max);
    }
}

test "Distribution from samples" {
    const samples = [_]f32{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    const dist = Distribution.fromSamples(&samples);

    try std.testing.expectApproxEqAbs(dist.min, 1.0, 0.001);
    try std.testing.expectApproxEqAbs(dist.max, 5.0, 0.001);
    try std.testing.expectApproxEqAbs(dist.mean, 3.0, 0.001);
    try std.testing.expect(dist.sample_count == 5);
}

test "BuildingTypeWeights sampling" {
    const weights = BuildingTypeWeights{
        .residential_house = 1.0,
        .residential_garage = 0.0,
        .apartment_low = 0.0,
        .apartment_mid = 0.0,
        .commercial_small = 0.0,
        .commercial_large = 0.0,
        .school = 0.0,
        .church = 0.0,
        .industrial = 0.0,
        .shed = 0.0,
    };

    var prng = std.Random.DefaultPrng.init(12345);
    const rng = prng.random();

    // With only residential_house having weight, all samples should be that type
    for (0..10) |_| {
        const sample = weights.sample(rng);
        try std.testing.expect(sample == .residential_house);
    }
}

test "FantasyAmplification presets exist" {
    // Just verify the presets compile and have reasonable values
    try std.testing.expect(FantasyAmplification.realistic.hill_amplitude == 1.0);
    try std.testing.expect(FantasyAmplification.standard.hill_amplitude > 1.0);
    try std.testing.expect(FantasyAmplification.dramatic.hill_amplitude > FantasyAmplification.standard.hill_amplitude);
    try std.testing.expect(FantasyAmplification.imagination.hill_amplitude > FantasyAmplification.dramatic.hill_amplitude);
}

test "RegionType defaults" {
    const suburban = RegionType.suburban_residential.getDefaults();
    const urban = RegionType.urban_grid.getDefaults();

    // Suburban should have lower density than urban
    try std.testing.expect(suburban.building_density.mean < urban.building_density.mean);

    // Urban grid should have higher regularity
    try std.testing.expect(suburban.grid_regularity < urban.grid_regularity);
}

test "polygon area calculation" {
    // Simple 1 degree x 1 degree square at equator
    const square = [_]GeoPoint{
        .{ .lon = 0.0, .lat = 0.0 },
        .{ .lon = 1.0, .lat = 0.0 },
        .{ .lon = 1.0, .lat = 1.0 },
        .{ .lon = 0.0, .lat = 1.0 },
    };

    const area = calculatePolygonArea(&square);
    // At equator, 1 degree ~ 111km, so area should be ~12,321 km^2 = ~12 billion m^2
    // This is a rough sanity check
    try std.testing.expect(area > 1e10);
}

test "procedural arena generation" {
    // Test that we can generate a procedural arena from a built-in profile
    const allocator = std.testing.allocator;

    const profile = &profiles.calgary_suburbs;
    const amplification = FantasyAmplification.standard;
    const seed: u64 = 42;
    // Arena size in METERS (real-world scale, not game units)
    // A 2000 game unit arena = 2000 / (6.67 * 2.2) ≈ 136 meters
    const arena_size: f32 = 136.0;

    const recipe = try generateProceduralArena(allocator, profile, amplification, seed, arena_size);

    // Verify recipe was generated with some content
    try std.testing.expect(recipe.elevation_ops.len > 0);
    try std.testing.expect(recipe.snow_ops.len > 0);
    try std.testing.expectEqualStrings("Procedural Neighborhood", recipe.name);

    // Debug: print heights to verify they're reasonable
    std.debug.print("\n=== Procedural Arena Debug ===\n", .{});
    std.debug.print("Total elevation ops: {}\n", .{recipe.elevation_ops.len});

    for (recipe.elevation_ops, 0..) |op, i| {
        switch (op.primitive) {
            .flat => |f| std.debug.print("  [{d}] flat: height={d:.1}\n", .{ i, f.height }),
            .noise => |n| std.debug.print("  [{d}] noise: amp={d:.1}\n", .{ i, n.amplitude }),
            .plateau => |p| {
                std.debug.print("  [{d}] plateau: height={d:.1} (min={d:.3},{d:.3} max={d:.3},{d:.3})\n", .{ i, p.height, p.min.x, p.min.z, p.max.x, p.max.z });
                // Verify building heights are reasonable (should be 50-300 range for game units)
                try std.testing.expect(p.height >= 0);
                try std.testing.expect(p.height < 500); // Not insanely tall
            },
            .polyline => |p| std.debug.print("  [{d}] polyline: height={d:.1} width={d:.4}\n", .{ i, p.height, p.width }),
            .boundary_wall => |b| std.debug.print("  [{d}] boundary_wall: height={d:.1}\n", .{ i, b.height }),
            else => std.debug.print("  [{d}] other\n", .{i}),
        }
    }

    // Clean up - free nested allocations in elevation_ops (polyline points)
    for (recipe.elevation_ops) |op| {
        switch (op.primitive) {
            .polyline => |polyline| {
                allocator.free(polyline.points);
            },
            else => {},
        }
    }
    allocator.free(recipe.elevation_ops);
    allocator.free(recipe.snow_ops);
    allocator.destroy(recipe);
}

test "built-in city profiles have valid values" {
    // Verify all built-in profiles have reasonable values
    const all_profiles = [_]*const NeighborhoodProfile{
        &profiles.calgary_suburbs,
        &profiles.copenhagen,
        &profiles.brooklyn,
        &profiles.montreal_plateau,
        &profiles.berlin_blocks,
    };

    for (all_profiles) |profile| {
        // Building density should be positive
        try std.testing.expect(profile.building_density.mean > 0);
        try std.testing.expect(profile.building_density.max >= profile.building_density.min);

        // Grid regularity should be 0-1
        try std.testing.expect(profile.grid_regularity >= 0.0);
        try std.testing.expect(profile.grid_regularity <= 1.0);

        // Green space should be 0-1
        try std.testing.expect(profile.green_space_coverage >= 0.0);
        try std.testing.expect(profile.green_space_coverage <= 1.0);
    }
}
