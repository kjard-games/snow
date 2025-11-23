const std = @import("std");

// ========================================
// GEAR SLOT SYSTEM
// ========================================

pub const GearSlot = enum {
    toque, // Head
    scarf, // Neck
    jacket, // Torso
    gloves, // Hands
    pants, // Legs
    boots, // Feet
};

pub const SLOT_COUNT: usize = 6;

pub const Gear = struct {
    name: [:0]const u8,
    slot: GearSlot,

    // Defensive stats
    padding: f32, // Armor value (0-35+)

    // Bonus stats
    warmth_regen_bonus: f32 = 0.0, // Passive warmth/sec
    energy_regen_bonus: f32 = 0.0, // Passive energy/sec
    speed_modifier: f32 = 1.0, // Movement multiplier (0.5 to 1.5)
};

// ========================================
// GEAR DEFINITIONS - LIGHT TIER (5-10 padding)
// ========================================

pub const WoolCap = Gear{
    .name = "Wool Cap",
    .slot = .toque,
    .padding = 5.0,
};

pub const LightScarf = Gear{
    .name = "Light Scarf",
    .slot = .scarf,
    .padding = 8.0,
};

pub const Hoodie = Gear{
    .name = "Hoodie",
    .slot = .jacket,
    .padding = 15.0,
    .energy_regen_bonus = 0.3,
    .speed_modifier = 1.05,
};

pub const Mittens = Gear{
    .name = "Mittens",
    .slot = .gloves,
    .padding = 10.0,
    .warmth_regen_bonus = 0.5,
};

pub const Joggers = Gear{
    .name = "Joggers",
    .slot = .pants,
    .padding = 10.0,
    .speed_modifier = 1.1,
};

pub const Sneakers = Gear{
    .name = "Sneakers",
    .slot = .boots,
    .padding = 8.0,
    .speed_modifier = 1.15,
};

// ========================================
// GEAR DEFINITIONS - MEDIUM TIER (10-20 padding)
// ========================================

pub const SkiBeanie = Gear{
    .name = "Ski Beanie",
    .slot = .toque,
    .padding = 10.0,
    .warmth_regen_bonus = 1.0,
};

pub const PuffyScarf = Gear{
    .name = "Puffy Scarf",
    .slot = .scarf,
    .padding = 12.0,
    .warmth_regen_bonus = 1.0,
};

pub const SkiJacket = Gear{
    .name = "Ski Jacket",
    .slot = .jacket,
    .padding = 25.0,
    .warmth_regen_bonus = 2.0,
    .speed_modifier = 0.95,
};

pub const InsulatedGloves = Gear{
    .name = "Insulated Gloves",
    .slot = .gloves,
    .padding = 15.0,
    .warmth_regen_bonus = 1.5,
    .speed_modifier = 0.95,
};

pub const SnowPants = Gear{
    .name = "Snow Pants",
    .slot = .pants,
    .padding = 20.0,
    .warmth_regen_bonus = 1.5,
    .speed_modifier = 0.9,
};

pub const InsulatedBoots = Gear{
    .name = "Insulated Boots",
    .slot = .boots,
    .padding = 15.0,
    .warmth_regen_bonus = 1.0,
    .speed_modifier = 0.9,
};

// ========================================
// GEAR DEFINITIONS - HEAVY TIER (15-35 padding)
// ========================================

pub const WinterParkaHood = Gear{
    .name = "Winter Parka Hood",
    .slot = .toque,
    .padding = 15.0,
    .warmth_regen_bonus = 2.0,
    .speed_modifier = 0.9,
};

pub const WoolNeckGuard = Gear{
    .name = "Wool Neck Guard",
    .slot = .scarf,
    .padding = 18.0,
    .warmth_regen_bonus = 1.5,
};

pub const HeavyParka = Gear{
    .name = "Heavy Parka",
    .slot = .jacket,
    .padding = 35.0,
    .warmth_regen_bonus = 3.0,
    .speed_modifier = 0.8,
};

pub const ThermalGauntlets = Gear{
    .name = "Thermal Gauntlets",
    .slot = .gloves,
    .padding = 22.0,
    .warmth_regen_bonus = 2.0,
    .speed_modifier = 0.85,
};

pub const ThermalLeggings = Gear{
    .name = "Thermal Leggings",
    .slot = .pants,
    .padding = 28.0,
    .warmth_regen_bonus = 2.0,
    .speed_modifier = 0.8,
};

pub const IceClimbingBoots = Gear{
    .name = "Ice Climbing Boots",
    .slot = .boots,
    .padding = 22.0,
    .warmth_regen_bonus = 1.5,
    .speed_modifier = 0.75,
};

// ========================================
// UTILITY FUNCTIONS
// ========================================

/// Get all gear of a specific slot
pub fn getGearBySlot(slot: GearSlot) [3]*const Gear {
    return switch (slot) {
        .toque => [3]*const Gear{ &WoolCap, &SkiBeanie, &WinterParkaHood },
        .scarf => [3]*const Gear{ &LightScarf, &PuffyScarf, &WoolNeckGuard },
        .jacket => [3]*const Gear{ &Hoodie, &SkiJacket, &HeavyParka },
        .gloves => [3]*const Gear{ &Mittens, &InsulatedGloves, &ThermalGauntlets },
        .pants => [3]*const Gear{ &Joggers, &SnowPants, &ThermalLeggings },
        .boots => [3]*const Gear{ &Sneakers, &InsulatedBoots, &IceClimbingBoots },
    };
}

/// Get all gear (for random selection during character creation)
pub fn getAllGear() [18]*const Gear {
    return [18]*const Gear{
        &WoolCap,
        &LightScarf,
        &Hoodie,
        &Mittens,
        &Joggers,
        &Sneakers,
        &SkiBeanie,
        &PuffyScarf,
        &SkiJacket,
        &InsulatedGloves,
        &SnowPants,
        &InsulatedBoots,
        &WinterParkaHood,
        &WoolNeckGuard,
        &HeavyParka,
        &ThermalGauntlets,
        &ThermalLeggings,
        &IceClimbingBoots,
    };
}
