// ============================================================================
// ARENA PROPS - Placeable Environment Objects
// ============================================================================
//
// Props are discrete 3D objects placed on top of the terrain heightmap.
// They provide cover, obstacles, and visual flavor for arena environments.
//
// Design:
// - PropType: What kind of object (snow_covered_car, mailbox, tree, etc.)
// - PropPlacement: A single prop instance with position, rotation, scale
// - PropCollection: Pre-configured groups of props (parked_cars, playground, yard_stuff)
// - PropInstance: Runtime state for a placed prop (for destruction, interaction)
//
// Placeholder rendering uses simple Raylib primitives until Blender models exist.
// When models are ready, swap placeholder draws for rl.drawModel() calls.
//
// ============================================================================

const std = @import("std");
const rl = @import("raylib");
const arena_gen = @import("arena_gen.zig");
const terrain_mod = @import("terrain.zig");

const NormalizedPos = arena_gen.NormalizedPos;
const TerrainGrid = terrain_mod.TerrainGrid;

// ============================================================================
// PROP TYPES - What can be placed
// ============================================================================

/// Categories of props for organization
pub const PropCategory = enum {
    vehicle, // Cars, sleds, bikes
    structure, // Fences, walls, sheds
    nature, // Trees, bushes, rocks
    playground, // Swings, slides, jungle gym
    furniture, // Benches, tables, grills
    decoration, // Snowmen, lawn ornaments
    cover, // Snow forts, barriers, dumpsters
};

/// Individual prop types - each will eventually have a Blender model
pub const PropType = enum {
    // === VEHICLES ===
    snow_covered_car, // Sedan-shaped lump, good cover
    snow_covered_suv, // Taller vehicle lump
    snow_covered_truck, // Pickup truck shape
    parked_sled, // Kid's sled leaning or flat
    bike_in_snow, // Bicycle half-buried
    wagon, // Red wagon, partially visible

    // === STRUCTURES ===
    wooden_fence_section, // 2m fence segment
    chain_link_fence, // See-through fence
    picket_fence, // White picket fence segment
    shed_small, // Garden shed (blocks LoS)
    shed_large, // Larger storage shed
    garage_door, // Closed garage (wall segment)
    porch_stairs, // Small elevated platform
    deck, // Raised wooden deck area

    // === NATURE ===
    pine_tree_small, // 2-3m evergreen
    pine_tree_medium, // 4-5m evergreen
    pine_tree_large, // 6-8m evergreen
    bare_tree, // Deciduous without leaves
    bush_snow_covered, // Round snowy shrub
    rock_small, // Boulder ~0.5m
    rock_medium, // Boulder ~1m
    rock_large, // Boulder ~2m
    log_fallen, // Fallen tree trunk
    stump, // Tree stump

    // === PLAYGROUND ===
    swing_set, // A-frame with swings
    slide, // Playground slide
    jungle_gym, // Climbing structure
    merry_go_round, // Spinning platform
    seesaw, // Teeter-totter
    sandbox, // Sand pit (snow-filled)
    basketball_hoop, // Driveway hoop

    // === FURNITURE ===
    bench_park, // Wooden park bench
    bench_picnic, // Picnic table
    grill, // BBQ grill
    lawn_chair, // Folding chair
    trash_can, // Garbage bin
    recycling_bin, // Blue bin
    mailbox, // Standard mailbox on post
    lamppost, // Street light

    // === DECORATION ===
    snowman_small, // Kid-sized snowman
    snowman_large, // Classic 3-ball snowman
    snow_fort_wall, // Player-built style wall segment
    snow_fort_corner, // Corner piece
    snow_angel, // Impression in snow (flat)
    lawn_ornament, // Garden gnome etc under snow
    christmas_lights, // Decorative (on other props)
    inflatable_deflated, // Sad deflated yard decoration

    // === COVER ===
    dumpster, // Large metal dumpster
    hay_bale, // Decorative hay bale
    snow_pile_small, // Plowed snow pile
    snow_pile_large, // Big plow drift
    barrier_concrete, // Jersey barrier
    crate_wooden, // Wooden shipping crate
    tire_stack, // Stack of old tires

    /// Get the category for this prop type
    pub fn getCategory(self: PropType) PropCategory {
        return switch (self) {
            .snow_covered_car, .snow_covered_suv, .snow_covered_truck, .parked_sled, .bike_in_snow, .wagon => .vehicle,
            .wooden_fence_section, .chain_link_fence, .picket_fence, .shed_small, .shed_large, .garage_door, .porch_stairs, .deck => .structure,
            .pine_tree_small, .pine_tree_medium, .pine_tree_large, .bare_tree, .bush_snow_covered, .rock_small, .rock_medium, .rock_large, .log_fallen, .stump => .nature,
            .swing_set, .slide, .jungle_gym, .merry_go_round, .seesaw, .sandbox, .basketball_hoop => .playground,
            .bench_park, .bench_picnic, .grill, .lawn_chair, .trash_can, .recycling_bin, .mailbox, .lamppost => .furniture,
            .snowman_small, .snowman_large, .snow_fort_wall, .snow_fort_corner, .snow_angel, .lawn_ornament, .christmas_lights, .inflatable_deflated => .decoration,
            .dumpster, .hay_bale, .snow_pile_small, .snow_pile_large, .barrier_concrete, .crate_wooden, .tire_stack => .cover,
        };
    }

    /// Get approximate collision radius for gameplay
    pub fn getCollisionRadius(self: PropType) f32 {
        return switch (self) {
            // Vehicles - car-sized
            .snow_covered_car => 25.0,
            .snow_covered_suv => 28.0,
            .snow_covered_truck => 30.0,
            .parked_sled => 8.0,
            .bike_in_snow => 10.0,
            .wagon => 8.0,

            // Structures
            .wooden_fence_section, .chain_link_fence, .picket_fence => 5.0, // Thin
            .shed_small => 30.0,
            .shed_large => 45.0,
            .garage_door => 10.0,
            .porch_stairs => 20.0,
            .deck => 40.0,

            // Nature
            .pine_tree_small => 8.0,
            .pine_tree_medium => 12.0,
            .pine_tree_large => 18.0,
            .bare_tree => 10.0,
            .bush_snow_covered => 12.0,
            .rock_small => 6.0,
            .rock_medium => 12.0,
            .rock_large => 20.0,
            .log_fallen => 15.0,
            .stump => 8.0,

            // Playground
            .swing_set => 25.0,
            .slide => 15.0,
            .jungle_gym => 35.0,
            .merry_go_round => 20.0,
            .seesaw => 18.0,
            .sandbox => 25.0,
            .basketball_hoop => 8.0,

            // Furniture - small
            .bench_park => 12.0,
            .bench_picnic => 18.0,
            .grill => 8.0,
            .lawn_chair => 6.0,
            .trash_can => 6.0,
            .recycling_bin => 6.0,
            .mailbox => 4.0,
            .lamppost => 5.0,

            // Decoration
            .snowman_small => 8.0,
            .snowman_large => 12.0,
            .snow_fort_wall => 15.0,
            .snow_fort_corner => 12.0,
            .snow_angel => 0.0, // No collision
            .lawn_ornament => 4.0,
            .christmas_lights => 0.0,
            .inflatable_deflated => 10.0,

            // Cover
            .dumpster => 25.0,
            .hay_bale => 15.0,
            .snow_pile_small => 18.0,
            .snow_pile_large => 35.0,
            .barrier_concrete => 20.0,
            .crate_wooden => 15.0,
            .tire_stack => 12.0,
        };
    }

    /// Get approximate height for LoS calculations
    pub fn getHeight(self: PropType) f32 {
        return switch (self) {
            // Vehicles
            .snow_covered_car => 18.0,
            .snow_covered_suv => 22.0,
            .snow_covered_truck => 20.0,
            .parked_sled => 3.0,
            .bike_in_snow => 12.0,
            .wagon => 5.0,

            // Structures
            .wooden_fence_section => 20.0,
            .chain_link_fence => 25.0,
            .picket_fence => 12.0,
            .shed_small => 35.0,
            .shed_large => 45.0,
            .garage_door => 35.0,
            .porch_stairs => 15.0,
            .deck => 12.0,

            // Nature
            .pine_tree_small => 40.0,
            .pine_tree_medium => 70.0,
            .pine_tree_large => 100.0,
            .bare_tree => 80.0,
            .bush_snow_covered => 15.0,
            .rock_small => 6.0,
            .rock_medium => 12.0,
            .rock_large => 25.0,
            .log_fallen => 8.0,
            .stump => 6.0,

            // Playground
            .swing_set => 40.0,
            .slide => 30.0,
            .jungle_gym => 45.0,
            .merry_go_round => 8.0,
            .seesaw => 12.0,
            .sandbox => 4.0,
            .basketball_hoop => 50.0,

            // Furniture
            .bench_park => 12.0,
            .bench_picnic => 15.0,
            .grill => 14.0,
            .lawn_chair => 10.0,
            .trash_can => 14.0,
            .recycling_bin => 12.0,
            .mailbox => 16.0,
            .lamppost => 60.0,

            // Decoration
            .snowman_small => 15.0,
            .snowman_large => 25.0,
            .snow_fort_wall => 18.0,
            .snow_fort_corner => 18.0,
            .snow_angel => 0.5,
            .lawn_ornament => 8.0,
            .christmas_lights => 2.0,
            .inflatable_deflated => 8.0,

            // Cover
            .dumpster => 20.0,
            .hay_bale => 15.0,
            .snow_pile_small => 15.0,
            .snow_pile_large => 30.0,
            .barrier_concrete => 12.0,
            .crate_wooden => 18.0,
            .tire_stack => 16.0,
        };
    }

    /// Does this prop block line of sight?
    pub fn blocksLoS(self: PropType) bool {
        return switch (self) {
            .snow_angel, .christmas_lights, .sandbox, .lawn_chair => false,
            else => true,
        };
    }

    /// Can this prop be destroyed during combat?
    pub fn isDestructible(self: PropType) bool {
        return switch (self) {
            .snowman_small, .snowman_large, .snow_fort_wall, .snow_fort_corner, .snow_pile_small, .snow_pile_large, .inflatable_deflated => true,
            else => false,
        };
    }
};

// ============================================================================
// PROP PLACEMENT - Individual prop instances
// ============================================================================

/// A single prop placement in normalized arena coordinates
pub const PropPlacement = struct {
    prop_type: PropType,
    position: NormalizedPos, // 0-1 normalized position
    rotation: f32 = 0.0, // Rotation in radians around Y axis
    scale: f32 = 1.0, // Uniform scale multiplier
    variation: u8 = 0, // Visual variation index (for props with multiple looks)
};

// ============================================================================
// PROP COLLECTIONS - Pre-configured groups
// ============================================================================

/// A collection of props that form a logical group
/// Collections use relative positioning from a center point
pub const PropCollection = struct {
    name: [:0]const u8,
    props: []const RelativeProp,
    /// Footprint radius for placement validation
    footprint_radius: f32 = 50.0,
};

/// A prop with position relative to collection center
pub const RelativeProp = struct {
    prop_type: PropType,
    offset_x: f32 = 0.0, // Offset from collection center (normalized)
    offset_z: f32 = 0.0,
    rotation: f32 = 0.0,
    scale: f32 = 1.0,
    variation: u8 = 0,
};

/// Placement of a collection in the arena
pub const CollectionPlacement = struct {
    collection: *const PropCollection,
    position: NormalizedPos, // Center position
    rotation: f32 = 0.0, // Rotate entire collection
    scale: f32 = 1.0, // Scale entire collection
};

// ============================================================================
// PRE-DEFINED COLLECTIONS - Ready to place
// ============================================================================

// --- PARKING ---

/// Row of parked cars along a curb
pub const collection_parked_cars_row = PropCollection{
    .name = "Parked Cars Row",
    .footprint_radius = 80.0,
    .props = &[_]RelativeProp{
        .{ .prop_type = .snow_covered_car, .offset_x = -0.06, .offset_z = 0.0, .rotation = 0.0 },
        .{ .prop_type = .snow_covered_suv, .offset_x = 0.0, .offset_z = 0.0, .rotation = 0.0 },
        .{ .prop_type = .snow_covered_car, .offset_x = 0.06, .offset_z = 0.0, .rotation = 0.0, .variation = 1 },
    },
};

/// Parking lot cluster (2x2 cars)
pub const collection_parking_cluster = PropCollection{
    .name = "Parking Cluster",
    .footprint_radius = 60.0,
    .props = &[_]RelativeProp{
        .{ .prop_type = .snow_covered_car, .offset_x = -0.03, .offset_z = -0.03 },
        .{ .prop_type = .snow_covered_suv, .offset_x = 0.03, .offset_z = -0.03 },
        .{ .prop_type = .snow_covered_car, .offset_x = -0.03, .offset_z = 0.03, .variation = 1 },
        .{ .prop_type = .snow_covered_truck, .offset_x = 0.03, .offset_z = 0.03 },
    },
};

// --- PLAYGROUND ---

/// Basic playground setup
pub const collection_playground_basic = PropCollection{
    .name = "Basic Playground",
    .footprint_radius = 100.0,
    .props = &[_]RelativeProp{
        .{ .prop_type = .swing_set, .offset_x = -0.04, .offset_z = 0.0 },
        .{ .prop_type = .slide, .offset_x = 0.04, .offset_z = -0.02, .rotation = 0.5 },
        .{ .prop_type = .sandbox, .offset_x = 0.0, .offset_z = 0.04 },
        .{ .prop_type = .bench_park, .offset_x = -0.06, .offset_z = 0.04, .rotation = -0.3 },
    },
};

/// Full playground with jungle gym
pub const collection_playground_full = PropCollection{
    .name = "Full Playground",
    .footprint_radius = 140.0,
    .props = &[_]RelativeProp{
        .{ .prop_type = .jungle_gym, .offset_x = 0.0, .offset_z = 0.0 },
        .{ .prop_type = .swing_set, .offset_x = -0.06, .offset_z = 0.0 },
        .{ .prop_type = .slide, .offset_x = 0.05, .offset_z = -0.03, .rotation = 0.8 },
        .{ .prop_type = .merry_go_round, .offset_x = 0.04, .offset_z = 0.04 },
        .{ .prop_type = .seesaw, .offset_x = -0.04, .offset_z = 0.05 },
        .{ .prop_type = .sandbox, .offset_x = -0.02, .offset_z = -0.05 },
        .{ .prop_type = .bench_park, .offset_x = -0.08, .offset_z = 0.02 },
        .{ .prop_type = .bench_park, .offset_x = 0.08, .offset_z = 0.02, .rotation = 3.14 },
        .{ .prop_type = .trash_can, .offset_x = 0.07, .offset_z = -0.04 },
    },
};

// --- YARD ---

/// Typical front yard setup
pub const collection_front_yard = PropCollection{
    .name = "Front Yard",
    .footprint_radius = 70.0,
    .props = &[_]RelativeProp{
        .{ .prop_type = .mailbox, .offset_x = -0.04, .offset_z = 0.03 },
        .{ .prop_type = .bush_snow_covered, .offset_x = 0.02, .offset_z = -0.02 },
        .{ .prop_type = .bush_snow_covered, .offset_x = 0.04, .offset_z = -0.02, .scale = 0.8 },
        .{ .prop_type = .pine_tree_small, .offset_x = -0.03, .offset_z = -0.03 },
        .{ .prop_type = .lamppost, .offset_x = -0.05, .offset_z = 0.02 },
    },
};

/// Backyard with shed and grill
pub const collection_backyard = PropCollection{
    .name = "Backyard",
    .footprint_radius = 90.0,
    .props = &[_]RelativeProp{
        .{ .prop_type = .shed_small, .offset_x = 0.05, .offset_z = -0.04 },
        .{ .prop_type = .grill, .offset_x = -0.03, .offset_z = -0.03 },
        .{ .prop_type = .bench_picnic, .offset_x = -0.02, .offset_z = 0.02 },
        .{ .prop_type = .lawn_chair, .offset_x = 0.0, .offset_z = 0.04 },
        .{ .prop_type = .lawn_chair, .offset_x = 0.02, .offset_z = 0.04, .rotation = 0.3 },
        .{ .prop_type = .trash_can, .offset_x = 0.04, .offset_z = -0.02 },
        .{ .prop_type = .recycling_bin, .offset_x = 0.045, .offset_z = -0.015 },
    },
};

// --- SNOW FORT ---

/// Basic snow fort (L-shaped walls)
pub const collection_snow_fort_basic = PropCollection{
    .name = "Basic Snow Fort",
    .footprint_radius = 50.0,
    .props = &[_]RelativeProp{
        .{ .prop_type = .snow_fort_wall, .offset_x = -0.02, .offset_z = 0.0 },
        .{ .prop_type = .snow_fort_wall, .offset_x = 0.02, .offset_z = 0.0 },
        .{ .prop_type = .snow_fort_corner, .offset_x = 0.0, .offset_z = -0.02 },
        .{ .prop_type = .snowman_small, .offset_x = 0.0, .offset_z = 0.02 },
    },
};

/// Elaborate snow fort with multiple walls
pub const collection_snow_fort_elaborate = PropCollection{
    .name = "Elaborate Snow Fort",
    .footprint_radius = 80.0,
    .props = &[_]RelativeProp{
        // Front wall
        .{ .prop_type = .snow_fort_wall, .offset_x = -0.03, .offset_z = 0.03 },
        .{ .prop_type = .snow_fort_wall, .offset_x = 0.0, .offset_z = 0.03 },
        .{ .prop_type = .snow_fort_wall, .offset_x = 0.03, .offset_z = 0.03 },
        // Side walls
        .{ .prop_type = .snow_fort_wall, .offset_x = -0.04, .offset_z = 0.0, .rotation = 1.57 },
        .{ .prop_type = .snow_fort_wall, .offset_x = 0.04, .offset_z = 0.0, .rotation = 1.57 },
        // Corners
        .{ .prop_type = .snow_fort_corner, .offset_x = -0.04, .offset_z = 0.03 },
        .{ .prop_type = .snow_fort_corner, .offset_x = 0.04, .offset_z = 0.03 },
        // Snowmen guards
        .{ .prop_type = .snowman_large, .offset_x = -0.02, .offset_z = -0.02 },
        .{ .prop_type = .snowman_large, .offset_x = 0.02, .offset_z = -0.02 },
        // Snow pile ammo dump
        .{ .prop_type = .snow_pile_small, .offset_x = 0.0, .offset_z = 0.0 },
    },
};

// --- FOREST ---

/// Cluster of pine trees
pub const collection_tree_cluster = PropCollection{
    .name = "Tree Cluster",
    .footprint_radius = 60.0,
    .props = &[_]RelativeProp{
        .{ .prop_type = .pine_tree_large, .offset_x = 0.0, .offset_z = 0.0 },
        .{ .prop_type = .pine_tree_medium, .offset_x = -0.03, .offset_z = 0.02 },
        .{ .prop_type = .pine_tree_small, .offset_x = 0.02, .offset_z = -0.02 },
        .{ .prop_type = .bush_snow_covered, .offset_x = -0.02, .offset_z = -0.02 },
        .{ .prop_type = .bush_snow_covered, .offset_x = 0.03, .offset_z = 0.01 },
    },
};

/// Fallen tree with stumps
pub const collection_fallen_tree = PropCollection{
    .name = "Fallen Tree",
    .footprint_radius = 45.0,
    .props = &[_]RelativeProp{
        .{ .prop_type = .log_fallen, .offset_x = 0.0, .offset_z = 0.0, .rotation = 0.3 },
        .{ .prop_type = .stump, .offset_x = -0.03, .offset_z = 0.0 },
        .{ .prop_type = .rock_small, .offset_x = 0.02, .offset_z = 0.015 },
        .{ .prop_type = .bush_snow_covered, .offset_x = 0.025, .offset_z = -0.015, .scale = 0.7 },
    },
};

/// Rocky outcrop
pub const collection_rocks = PropCollection{
    .name = "Rocky Outcrop",
    .footprint_radius = 50.0,
    .props = &[_]RelativeProp{
        .{ .prop_type = .rock_large, .offset_x = 0.0, .offset_z = 0.0 },
        .{ .prop_type = .rock_medium, .offset_x = -0.025, .offset_z = 0.015 },
        .{ .prop_type = .rock_small, .offset_x = 0.02, .offset_z = -0.01 },
        .{ .prop_type = .rock_small, .offset_x = 0.015, .offset_z = 0.02 },
    },
};

// --- STREET FURNITURE ---

/// Bus stop
pub const collection_bus_stop = PropCollection{
    .name = "Bus Stop",
    .footprint_radius = 40.0,
    .props = &[_]RelativeProp{
        .{ .prop_type = .bench_park, .offset_x = 0.0, .offset_z = 0.0 },
        .{ .prop_type = .lamppost, .offset_x = -0.02, .offset_z = 0.0 },
        .{ .prop_type = .trash_can, .offset_x = 0.025, .offset_z = 0.0 },
    },
};

/// Street corner with lamp and fire hydrant stand-in
pub const collection_street_corner = PropCollection{
    .name = "Street Corner",
    .footprint_radius = 35.0,
    .props = &[_]RelativeProp{
        .{ .prop_type = .lamppost, .offset_x = 0.0, .offset_z = 0.0 },
        .{ .prop_type = .snow_pile_small, .offset_x = 0.02, .offset_z = 0.015 },
        .{ .prop_type = .mailbox, .offset_x = -0.025, .offset_z = 0.01 },
    },
};

// --- DRIVEWAY ---

/// Residential driveway
pub const collection_driveway = PropCollection{
    .name = "Driveway",
    .footprint_radius = 55.0,
    .props = &[_]RelativeProp{
        .{ .prop_type = .snow_covered_car, .offset_x = 0.0, .offset_z = 0.0 },
        .{ .prop_type = .basketball_hoop, .offset_x = 0.04, .offset_z = -0.02 },
        .{ .prop_type = .trash_can, .offset_x = -0.04, .offset_z = 0.02 },
        .{ .prop_type = .recycling_bin, .offset_x = -0.035, .offset_z = 0.025 },
        .{ .prop_type = .bike_in_snow, .offset_x = 0.03, .offset_z = 0.03 },
    },
};

// --- DECORATIVE ---

/// Snowman family
pub const collection_snowman_family = PropCollection{
    .name = "Snowman Family",
    .footprint_radius = 30.0,
    .props = &[_]RelativeProp{
        .{ .prop_type = .snowman_large, .offset_x = 0.0, .offset_z = 0.0 },
        .{ .prop_type = .snowman_small, .offset_x = -0.02, .offset_z = 0.015 },
        .{ .prop_type = .snowman_small, .offset_x = 0.02, .offset_z = 0.015, .scale = 0.8 },
    },
};

/// Sad deflated decorations
pub const collection_deflated_decorations = PropCollection{
    .name = "Deflated Decorations",
    .footprint_radius = 40.0,
    .props = &[_]RelativeProp{
        .{ .prop_type = .inflatable_deflated, .offset_x = 0.0, .offset_z = 0.0 },
        .{ .prop_type = .inflatable_deflated, .offset_x = 0.03, .offset_z = 0.01, .rotation = 1.2 },
        .{ .prop_type = .lawn_ornament, .offset_x = -0.02, .offset_z = 0.02 },
    },
};

// ============================================================================
// RUNTIME PROP STATE
// ============================================================================

/// Maximum props per arena
pub const MAX_PROPS: usize = 64;

/// Runtime state for a placed prop
pub const PropInstance = struct {
    prop_type: PropType,
    world_pos: rl.Vector3, // World position (after terrain height)
    rotation: f32,
    scale: f32,
    variation: u8,
    health: f32 = 100.0, // For destructible props
    is_destroyed: bool = false,

    /// Check if a point is within this prop's collision radius
    pub fn containsPoint(self: *const PropInstance, point: rl.Vector3) bool {
        const dx = point.x - self.world_pos.x;
        const dz = point.z - self.world_pos.z;
        const dist_sq = dx * dx + dz * dz;
        const radius = self.prop_type.getCollisionRadius() * self.scale;
        return dist_sq <= radius * radius;
    }
};

/// Manager for all props in an arena
pub const PropManager = struct {
    props: [MAX_PROPS]PropInstance = undefined,
    prop_count: usize = 0,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PropManager {
        return .{ .allocator = allocator };
    }

    /// Place a single prop
    pub fn placeProp(
        self: *PropManager,
        placement: PropPlacement,
        terrain: *const TerrainGrid,
    ) ?*PropInstance {
        if (self.prop_count >= MAX_PROPS) return null;

        // Convert normalized position to world position
        const world_x = terrain.world_offset_x + placement.position.x * @as(f32, @floatFromInt(terrain.width)) * terrain.grid_size;
        const world_z = terrain.world_offset_z + placement.position.z * @as(f32, @floatFromInt(terrain.height)) * terrain.grid_size;
        // Get terrain elevation + snow height for proper prop placement
        const world_y = terrain.getElevationAt(world_x, world_z) + terrain.getSnowHeightAt(world_x, world_z);

        self.props[self.prop_count] = .{
            .prop_type = placement.prop_type,
            .world_pos = .{ .x = world_x, .y = world_y, .z = world_z },
            .rotation = placement.rotation,
            .scale = placement.scale,
            .variation = placement.variation,
            .health = if (placement.prop_type.isDestructible()) 100.0 else 1000000.0,
        };

        self.prop_count += 1;
        return &self.props[self.prop_count - 1];
    }

    /// Place a collection of props
    pub fn placeCollection(
        self: *PropManager,
        placement: CollectionPlacement,
        terrain: *const TerrainGrid,
    ) usize {
        var placed: usize = 0;
        const cos_r = @cos(placement.rotation);
        const sin_r = @sin(placement.rotation);

        for (placement.collection.props) |rel_prop| {
            // Rotate offset around collection center
            const rotated_x = rel_prop.offset_x * cos_r - rel_prop.offset_z * sin_r;
            const rotated_z = rel_prop.offset_x * sin_r + rel_prop.offset_z * cos_r;

            const prop_placement = PropPlacement{
                .prop_type = rel_prop.prop_type,
                .position = .{
                    .x = placement.position.x + rotated_x * placement.scale,
                    .z = placement.position.z + rotated_z * placement.scale,
                },
                .rotation = rel_prop.rotation + placement.rotation,
                .scale = rel_prop.scale * placement.scale,
                .variation = rel_prop.variation,
            };

            if (self.placeProp(prop_placement, terrain)) |_| {
                placed += 1;
            }
        }

        return placed;
    }

    /// Clear all props
    pub fn clear(self: *PropManager) void {
        self.prop_count = 0;
    }

    /// Get collision check for a point
    pub fn checkCollision(self: *const PropManager, point: rl.Vector3) ?*const PropInstance {
        for (self.props[0..self.prop_count]) |*prop| {
            if (!prop.is_destroyed and prop.containsPoint(point)) {
                return prop;
            }
        }
        return null;
    }
};

// ============================================================================
// PLACEHOLDER RENDERING
// ============================================================================
// Until Blender models exist, draw simple colored shapes

/// Color scheme for placeholder props by category
fn getCategoryColor(category: PropCategory) rl.Color {
    return switch (category) {
        .vehicle => rl.Color.init(80, 80, 100, 255), // Blue-gray
        .structure => rl.Color.init(139, 90, 43, 255), // Brown
        .nature => rl.Color.init(34, 100, 34, 255), // Forest green
        .playground => rl.Color.init(255, 140, 0, 255), // Orange
        .furniture => rl.Color.init(160, 82, 45, 255), // Sienna
        .decoration => rl.Color.init(255, 255, 255, 255), // White
        .cover => rl.Color.init(200, 200, 220, 255), // Light gray
    };
}

/// Draw a single prop as placeholder geometry
pub fn drawPropPlaceholder(prop: *const PropInstance) void {
    if (prop.is_destroyed) return;

    const color = getCategoryColor(prop.prop_type.getCategory());
    const height = prop.prop_type.getHeight() * prop.scale;
    const radius = prop.prop_type.getCollisionRadius() * prop.scale;
    const pos = prop.world_pos;

    // Different shapes based on category
    switch (prop.prop_type.getCategory()) {
        .vehicle => {
            // Box for vehicles
            rl.drawCube(
                .{ .x = pos.x, .y = pos.y + height / 2, .z = pos.z },
                radius * 1.8,
                height,
                radius * 0.8,
                color,
            );
            rl.drawCubeWires(
                .{ .x = pos.x, .y = pos.y + height / 2, .z = pos.z },
                radius * 1.8,
                height,
                radius * 0.8,
                rl.Color.dark_gray,
            );
        },
        .nature => {
            // Cone for trees, sphere for bushes/rocks
            if (prop.prop_type == .bush_snow_covered or
                prop.prop_type == .rock_small or
                prop.prop_type == .rock_medium or
                prop.prop_type == .rock_large)
            {
                rl.drawSphere(.{ .x = pos.x, .y = pos.y + height / 2, .z = pos.z }, radius, color);
            } else if (prop.prop_type == .log_fallen) {
                // Cylinder on its side
                rl.drawCylinder(
                    .{ .x = pos.x - radius, .y = pos.y + height / 2, .z = pos.z },
                    height / 2,
                    height / 2,
                    radius * 2,
                    8,
                    color,
                );
            } else {
                // Cone for trees
                rl.drawCylinder(
                    .{ .x = pos.x, .y = pos.y, .z = pos.z },
                    radius,
                    0,
                    height,
                    8,
                    color,
                );
                // Brown trunk
                rl.drawCylinder(
                    .{ .x = pos.x, .y = pos.y, .z = pos.z },
                    radius * 0.15,
                    radius * 0.15,
                    height * 0.3,
                    6,
                    rl.Color.init(101, 67, 33, 255),
                );
            }
        },
        .decoration => {
            // Snowmen get stacked spheres
            if (prop.prop_type == .snowman_small or prop.prop_type == .snowman_large) {
                const r = radius * 0.5;
                rl.drawSphere(.{ .x = pos.x, .y = pos.y + r, .z = pos.z }, r, color);
                rl.drawSphere(.{ .x = pos.x, .y = pos.y + r * 2.5, .z = pos.z }, r * 0.75, color);
                rl.drawSphere(.{ .x = pos.x, .y = pos.y + r * 3.7, .z = pos.z }, r * 0.5, color);
            } else if (prop.prop_type == .snow_fort_wall or prop.prop_type == .snow_fort_corner) {
                // Low wall
                rl.drawCube(
                    .{ .x = pos.x, .y = pos.y + height / 2, .z = pos.z },
                    radius * 2,
                    height,
                    radius * 0.5,
                    color,
                );
            } else {
                rl.drawCube(
                    .{ .x = pos.x, .y = pos.y + height / 2, .z = pos.z },
                    radius,
                    height,
                    radius,
                    color,
                );
            }
        },
        .playground => {
            // A-frame for swing set, platform for others
            if (prop.prop_type == .swing_set) {
                // Simple A-frame
                rl.drawCylinder(
                    .{ .x = pos.x, .y = pos.y, .z = pos.z },
                    radius * 0.1,
                    radius * 0.8,
                    height,
                    4,
                    color,
                );
            } else if (prop.prop_type == .slide) {
                // Angled platform
                rl.drawCube(
                    .{ .x = pos.x, .y = pos.y + height / 2, .z = pos.z },
                    radius * 0.4,
                    height,
                    radius * 1.5,
                    color,
                );
            } else {
                rl.drawCube(
                    .{ .x = pos.x, .y = pos.y + height / 2, .z = pos.z },
                    radius * 1.5,
                    height,
                    radius * 1.5,
                    color,
                );
            }
        },
        .structure => {
            // Box for buildings/sheds
            rl.drawCube(
                .{ .x = pos.x, .y = pos.y + height / 2, .z = pos.z },
                radius * 1.5,
                height,
                radius * 1.5,
                color,
            );
            rl.drawCubeWires(
                .{ .x = pos.x, .y = pos.y + height / 2, .z = pos.z },
                radius * 1.5,
                height,
                radius * 1.5,
                rl.Color.dark_gray,
            );
        },
        .furniture => {
            // Small boxes or cylinders
            if (prop.prop_type == .lamppost) {
                rl.drawCylinder(
                    .{ .x = pos.x, .y = pos.y, .z = pos.z },
                    radius * 0.2,
                    radius * 0.2,
                    height,
                    6,
                    rl.Color.gray,
                );
                rl.drawSphere(
                    .{ .x = pos.x, .y = pos.y + height, .z = pos.z },
                    radius * 0.4,
                    rl.Color.yellow,
                );
            } else if (prop.prop_type == .mailbox) {
                // Post + box
                rl.drawCylinder(
                    .{ .x = pos.x, .y = pos.y, .z = pos.z },
                    radius * 0.2,
                    radius * 0.2,
                    height * 0.7,
                    4,
                    rl.Color.init(101, 67, 33, 255),
                );
                rl.drawCube(
                    .{ .x = pos.x, .y = pos.y + height * 0.8, .z = pos.z },
                    radius,
                    height * 0.3,
                    radius * 0.5,
                    rl.Color.init(50, 50, 50, 255),
                );
            } else {
                rl.drawCube(
                    .{ .x = pos.x, .y = pos.y + height / 2, .z = pos.z },
                    radius,
                    height,
                    radius,
                    color,
                );
            }
        },
        .cover => {
            // Irregular lumps
            if (prop.prop_type == .snow_pile_small or prop.prop_type == .snow_pile_large) {
                rl.drawSphere(
                    .{ .x = pos.x, .y = pos.y + height * 0.3, .z = pos.z },
                    radius,
                    color,
                );
            } else {
                rl.drawCube(
                    .{ .x = pos.x, .y = pos.y + height / 2, .z = pos.z },
                    radius * 1.5,
                    height,
                    radius,
                    color,
                );
            }
        },
    }
}

/// Draw all props in a manager
pub fn drawAllProps(manager: *const PropManager) void {
    for (manager.props[0..manager.prop_count]) |*prop| {
        drawPropPlaceholder(prop);
    }
}

// ============================================================================
// TESTS
// ============================================================================

test "prop type properties" {
    const car = PropType.snow_covered_car;
    try std.testing.expect(car.getCategory() == .vehicle);
    try std.testing.expect(car.getCollisionRadius() > 0);
    try std.testing.expect(car.getHeight() > 0);
    try std.testing.expect(car.blocksLoS());
    try std.testing.expect(!car.isDestructible());

    const snowman = PropType.snowman_small;
    try std.testing.expect(snowman.getCategory() == .decoration);
    try std.testing.expect(snowman.isDestructible());
}

test "collection has props" {
    try std.testing.expect(collection_parked_cars_row.props.len == 3);
    try std.testing.expect(collection_playground_full.props.len > 5);
    try std.testing.expect(collection_snow_fort_elaborate.props.len > 5);
}
