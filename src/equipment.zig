const std = @import("std");

// How many hands does this equipment require?
pub const HandRequirement = enum {
    two_hands, // Shovel, Lacrosse Stick, Toboggan, Jai Alai
    one_hand, // Ice Scraper, Saucer Sled, Thermos, Slingshot, Garbage Can Lid
    worn, // Mittens, Blanket (doesn't occupy hand slots, worn on body)
};

// What is the primary function of this equipment?
pub const EquipmentCategory = enum {
    throwing_tool, // Modifies snowball throws (Lacrosse Stick, Jai Alai, Slingshot)
    melee_weapon, // Changes to melee auto-attack (Shovel, Ice Scraper)
    shield, // Defensive blocking (Saucer Sled, Garbage Can Lid)
    utility, // Passive effects, minimal/no combat (Thermos, Blanket)
    mobility, // Movement/positioning focused (Toboggan)
};

pub const Equipment = struct {
    name: [:0]const u8,
    hand_requirement: HandRequirement,
    category: EquipmentCategory,

    // Combat stats
    damage: f32 = 0.0,
    armor: f32 = 0.0,
    speed_modifier: f32 = 1.0,
    range: f32 = 50.0,
    attack_interval: f32 = 1.5, // seconds between auto-attacks
    is_ranged: bool = false, // Projectile-based or melee

    // Utility effects (optional)
    warmth_regen_bonus: f32 = 0.0, // Passive warmth regeneration per second
};

// ========================================
// EQUIPMENT DEFINITIONS
// ========================================

// --- MELEE WEAPONS ---

pub const BigShovel = Equipment{
    .name = "Big Shovel",
    .hand_requirement = .two_hands,
    .category = .melee_weapon,
    .damage = 25.0,
    .armor = 5.0,
    .speed_modifier = 0.8,
    .range = 80.0, // Melee with good reach
    .attack_interval = 1.75, // Slow but powerful swings
    .is_ranged = false,
};

pub const IceScraper = Equipment{
    .name = "Ice Scraper",
    .hand_requirement = .one_hand,
    .category = .melee_weapon,
    .damage = 12.0,
    .armor = 2.0,
    .speed_modifier = 1.2,
    .range = 60.0, // Close melee
    .attack_interval = 1.33, // Fast attacks
    .is_ranged = false,
};

// --- THROWING TOOLS ---

pub const LacrosseStick = Equipment{
    .name = "Lacrosse Stick",
    .hand_requirement = .two_hands,
    .category = .throwing_tool,
    .damage = 15.0, // Modified snowball throw
    .armor = 2.0,
    .speed_modifier = 1.1,
    .range = 120.0, // Long arc throw
    .attack_interval = 2.0, // Moderate reload
    .is_ranged = true,
};

pub const JaiAlaiScoop = Equipment{
    .name = "Jai Alai Scoop",
    .hand_requirement = .two_hands,
    .category = .throwing_tool,
    .damage = 18.0, // High velocity throw
    .armor = 0.0,
    .speed_modifier = 1.0,
    .range = 100.0, // Good range but not arcing
    .attack_interval = 2.2, // Long wind-up
    .is_ranged = true,
};

pub const Slingshot = Equipment{
    .name = "Slingshot",
    .hand_requirement = .one_hand,
    .category = .throwing_tool,
    .damage = 8.0, // Low damage, high range
    .armor = 0.0,
    .speed_modifier = 1.0,
    .range = 150.0, // Extreme range
    .attack_interval = 1.5, // Quick reload
    .is_ranged = true,
};

// --- SHIELDS / DEFENSIVE ---

pub const SaucerSled = Equipment{
    .name = "Saucer Sled",
    .hand_requirement = .one_hand,
    .category = .shield,
    .damage = 0.0, // Can't attack while blocking
    .armor = 15.0,
    .speed_modifier = 0.9,
    .range = 40.0,
    .attack_interval = 2.0,
    .is_ranged = false,
};

pub const GarbageCanLid = Equipment{
    .name = "Garbage Can Lid",
    .hand_requirement = .one_hand,
    .category = .shield,
    .damage = 0.0,
    .armor = 20.0, // Higher armor than saucer sled
    .speed_modifier = 0.75, // Slower movement
    .range = 40.0,
    .attack_interval = 2.5,
    .is_ranged = false,
};

// --- MOBILITY ---

pub const Toboggan = Equipment{
    .name = "Toboggan",
    .hand_requirement = .two_hands,
    .category = .mobility,
    .damage = 5.0, // Can ram while moving
    .armor = 20.0, // Mobile cover
    .speed_modifier = 0.8, // Slow to carry, but enables sliding
    .range = 40.0,
    .attack_interval = 2.5,
    .is_ranged = false,
};

// --- UTILITY ---

pub const Thermos = Equipment{
    .name = "Thermos",
    .hand_requirement = .one_hand,
    .category = .utility,
    .damage = 0.0,
    .armor = 0.0,
    .speed_modifier = 1.0,
    .range = 40.0,
    .attack_interval = 2.0,
    .is_ranged = false,
    .warmth_regen_bonus = 2.0, // +2 warmth per second
};

// --- WORN (doesn't occupy hands) ---

pub const Mittens = Equipment{
    .name = "Mittens",
    .hand_requirement = .worn,
    .category = .utility,
    .damage = 5.0, // Bonus to bare-hand snowball damage
    .armor = 0.0,
    .speed_modifier = 0.95, // Slightly slower (bulky)
    .range = -10.0, // Penalty to throw range (offset from base)
    .attack_interval = 0.0, // Doesn't change attack speed
    .is_ranged = true,
};

pub const Blanket = Equipment{
    .name = "Blanket",
    .hand_requirement = .worn,
    .category = .utility,
    .damage = 0.0,
    .armor = 5.0, // Passive armor bonus
    .speed_modifier = 0.9, // Slows you down
    .range = 0.0,
    .attack_interval = 0.0,
    .is_ranged = false,
    .warmth_regen_bonus = 1.5, // +1.5 warmth per second
};
