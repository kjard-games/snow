const std = @import("std");

pub const EquipmentType = enum {
    two_handed,
    one_handed,
    shield,
    offhand,
};

pub const Equipment = struct {
    name: [:0]const u8,
    type: EquipmentType,
    damage: f32 = 0.0,
    armor: f32 = 0.0,
    speed_modifier: f32 = 1.0,
    range: f32 = 50.0, // melee range
};

// Equipment definitions
pub const BigShovel = Equipment{
    .name = "Big Shovel",
    .type = .two_handed,
    .damage = 25.0,
    .armor = 5.0,
    .speed_modifier = 0.8,
    .range = 80.0,
};

pub const IceScraper = Equipment{
    .name = "Ice Scraper",
    .type = .one_handed,
    .damage = 12.0,
    .armor = 2.0,
    .speed_modifier = 1.2,
    .range = 60.0,
};

pub const SaucerSled = Equipment{
    .name = "Saucer Sled",
    .type = .shield,
    .damage = 0.0,
    .armor = 15.0,
    .speed_modifier = 0.9,
    .range = 40.0,
};

pub const LacrosseStick = Equipment{
    .name = "Lacrosse Stick",
    .type = .two_handed,
    .damage = 12.0,
    .armor = 2.0,
    .speed_modifier = 1.1,
    .range = 80.0,
};

pub const Toboggan = Equipment{
    .name = "Toboggan",
    .type = .two_handed,
    .damage = 0.0,
    .armor = 20.0,
    .speed_modifier = 0.8,
    .range = 40.0,
};
