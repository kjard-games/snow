const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const school = @import("school.zig");
const position = @import("position.zig");
const skills = @import("skills.zig");
const equipment = @import("equipment.zig");
const gear_slot = @import("gear_slot.zig");
const entity = @import("entity.zig");

const Character = character.Character;
const School = school.School;
const Position = position.Position;
const Skill = character.Skill;
const Equipment = equipment.Equipment;
const Gear = gear_slot.Gear;
const EntityId = entity.EntityId;
const Team = entity.Team;

const print = std.debug.print;

// ============================================
// CONSTRAINT SYSTEM
// ============================================

/// Equipment constraint: specify what equipment a character should have
pub const EquipmentConstraint = union(enum) {
    none,
    specific: *const Equipment, // Exact equipment
    category: equipment.EquipmentCategory, // Any equipment of this category
    hand_requirement: equipment.HandRequirement, // Any equipment with this hand requirement
};

/// Skill constraint: specify skill requirements
pub const SkillConstraint = union(enum) {
    none,
    specific: *const Skill, // Exact skill
    creates_wall, // Skill that creates a wall
    destroys_wall, // Skill that destroys a wall
    any_from_school: School, // Any skill from a specific school
    any_from_position: Position, // Any skill from a specific position
    in_slot: u8, // Must be in specific skill bar slot (0-7)
};

/// Character composition constraint: how many of each type
pub const CharacterCompositionConstraint = struct {
    school: ?School = null, // Exact school, or null for any
    position: ?Position = null, // Exact position, or null for any
    min_count: u32 = 0,
    max_count: u32 = 1,
    equipment_constraints: [3]EquipmentConstraint = [_]EquipmentConstraint{.none} ** 3, // [main_hand, off_hand, worn]
    skill_constraints: [8]SkillConstraint = [_]SkillConstraint{.none} ** 8, // One per slot
};

// ============================================
// CHARACTER BUILDER
// ============================================

pub const CharacterBuilder = struct {
    allocator: std.mem.Allocator,
    rng: *std.Random,
    id_gen: *entity.EntityIdGenerator,

    // Build parameters
    school_override: ?School = null,
    position_override: ?Position = null,
    name: ?[:0]const u8 = null,
    team: Team = .blue,
    position: rl.Vector3 = .{ .x = 0, .y = 0, .z = 0 },
    warmth: f32 = 150.0,
    max_warmth: f32 = 150.0,
    radius: f32 = 10.0,
    color: rl.Color = .blue,

    // Equipment constraints
    main_hand_constraint: EquipmentConstraint = .none,
    off_hand_constraint: EquipmentConstraint = .none,
    worn_constraint: EquipmentConstraint = .none,

    // Skill constraints
    skill_constraints: [character.MAX_SKILLS]SkillConstraint = [_]SkillConstraint{.none} ** character.MAX_SKILLS,

    pub fn init(allocator: std.mem.Allocator, rng: *std.Random, id_gen: *entity.EntityIdGenerator) CharacterBuilder {
        return .{
            .allocator = allocator,
            .rng = rng,
            .id_gen = id_gen,
        };
    }

    pub fn withSchool(self: *CharacterBuilder, s: School) *CharacterBuilder {
        self.school_override = s;
        return self;
    }

    pub fn withPosition(self: *CharacterBuilder, p: Position) *CharacterBuilder {
        self.position_override = p;
        return self;
    }

    pub fn withName(self: *CharacterBuilder, name: [:0]const u8) *CharacterBuilder {
        self.name = name;
        return self;
    }

    pub fn withTeam(self: *CharacterBuilder, t: Team) *CharacterBuilder {
        self.team = t;
        return self;
    }

    pub fn withPosition3D(self: *CharacterBuilder, pos: rl.Vector3) *CharacterBuilder {
        self.position = pos;
        return self;
    }

    pub fn withColor(self: *CharacterBuilder, c: rl.Color) *CharacterBuilder {
        self.color = c;
        return self;
    }

    pub fn withWarmth(self: *CharacterBuilder, w: f32) *CharacterBuilder {
        self.warmth = w;
        return self;
    }

    pub fn withRadius(self: *CharacterBuilder, r: f32) *CharacterBuilder {
        self.radius = r;
        return self;
    }

    pub fn withMainHand(self: *CharacterBuilder, constraint: EquipmentConstraint) *CharacterBuilder {
        self.main_hand_constraint = constraint;
        return self;
    }

    pub fn withOffHand(self: *CharacterBuilder, constraint: EquipmentConstraint) *CharacterBuilder {
        self.off_hand_constraint = constraint;
        return self;
    }

    pub fn withWorn(self: *CharacterBuilder, constraint: EquipmentConstraint) *CharacterBuilder {
        self.worn_constraint = constraint;
        return self;
    }

    pub fn withSkillInSlot(self: *CharacterBuilder, slot: u8, constraint: SkillConstraint) *CharacterBuilder {
        if (slot < character.MAX_SKILLS) {
            self.skill_constraints[slot] = constraint;
        }
        return self;
    }

    pub fn withWallSkillInSlot(self: *CharacterBuilder, slot: u8) *CharacterBuilder {
        return self.withSkillInSlot(slot, .creates_wall);
    }

    /// Build and return the character
    pub fn build(self: *CharacterBuilder) Character {
        // Select school
        const selected_school = self.school_override orelse pickRandomSchool(self.rng);

        // Select position
        const selected_position = self.position_override orelse pickRandomPosition(self.rng);

        // Select or generate name
        const selected_name = self.name orelse self.generateName();

        var char = Character{
            .id = self.id_gen.generate(),
            .position = self.position,
            .previous_position = self.position,
            .radius = self.radius,
            .color = self.color,
            .school_color = self.color,
            .position_color = self.color,
            .name = selected_name,
            .warmth = self.warmth,
            .max_warmth = self.max_warmth,
            .team = self.team,
            .school = selected_school,
            .player_position = selected_position,
            .energy = selected_school.getMaxEnergy(),
            .max_energy = selected_school.getMaxEnergy(),
            .skill_bar = [_]?*const Skill{null} ** character.MAX_SKILLS,
            .gear = [_]?*const character.Gear{null} ** 6,
            .selected_skill = 0,
        };

        // Apply equipment constraints
        self.equipCharacter(&char);

        // Apply skill constraints
        self.skillCharacter(&char);

        // Recalculate totals
        char.recalculatePadding();

        return char;
    }

    fn generateName(_: *CharacterBuilder) [:0]const u8 {
        // In a real system, we'd allocate a unique name
        // For now, return a static string
        return "Character";
    }

    fn equipCharacter(self: *CharacterBuilder, char: *Character) void {
        // Apply main hand constraint
        char.main_hand = self.resolveEquipmentConstraint(self.main_hand_constraint, true);

        // Apply off hand constraint
        char.off_hand = self.resolveEquipmentConstraint(self.off_hand_constraint, false);

        // Apply worn constraint
        char.worn = self.resolveEquipmentConstraint(self.worn_constraint, false);

        // If no equipment specified, randomly assign
        if (char.main_hand == null and char.off_hand == null and char.worn == null) {
            assignRandomEquipment(char, self.rng);
        }
    }

    fn skillCharacter(self: *CharacterBuilder, char: *Character) void {
        const position_skills = char.player_position.getSkills();
        const school_skills = char.school.getSkills();

        for (self.skill_constraints, 0..) |constraint, slot| {
            if (slot >= character.MAX_SKILLS) break;

            if (constraint != .none) {
                char.skill_bar[slot] = self.resolveSkillConstraint(constraint, position_skills, school_skills);
            }
        }

        // Fill remaining slots with random skills
        var filled_count: usize = 0;
        for (char.skill_bar) |maybe_skill| {
            if (maybe_skill != null) filled_count += 1;
        }

        // Guarantee at least 1 wall skill in slot 0 if not set
        if (char.skill_bar[0] == null) {
            var wall_skill_idx: ?usize = null;
            for (position_skills, 0..) |skill, idx| {
                if (skill.creates_wall) {
                    wall_skill_idx = idx;
                    break;
                }
            }
            if (wall_skill_idx) |idx| {
                char.skill_bar[0] = &position_skills[idx];
                filled_count += 1;
            }
        }

        // Fill slots 1-3 with position skills
        var attempts: usize = 0;
        var slot_idx: usize = 1;
        while (slot_idx < 4 and attempts < position_skills.len * 3) : (attempts += 1) {
            if (position_skills.len == 0) break;
            if (char.skill_bar[slot_idx] != null) {
                slot_idx += 1;
                continue;
            }

            const random_idx = self.rng.intRangeAtMost(usize, 0, position_skills.len - 1);
            const skill = &position_skills[random_idx];

            // Check not already loaded
            var already_loaded = false;
            for (0..slot_idx) |check_idx| {
                if (char.skill_bar[check_idx] == skill) {
                    already_loaded = true;
                    break;
                }
            }

            if (!already_loaded) {
                char.skill_bar[slot_idx] = skill;
                slot_idx += 1;
            }
        }

        // Fill slots 4-7 with school skills
        attempts = 0;
        slot_idx = 4;
        while (slot_idx < 8 and attempts < school_skills.len * 3) : (attempts += 1) {
            if (school_skills.len == 0) break;
            if (char.skill_bar[slot_idx] != null) {
                slot_idx += 1;
                continue;
            }

            const random_idx = self.rng.intRangeAtMost(usize, 0, school_skills.len - 1);
            const skill = &school_skills[random_idx];

            // Check not already loaded
            var already_loaded = false;
            for (4..slot_idx) |check_idx| {
                if (char.skill_bar[check_idx] == skill) {
                    already_loaded = true;
                    break;
                }
            }

            if (!already_loaded) {
                char.skill_bar[slot_idx] = skill;
                slot_idx += 1;
            }
        }
    }

    fn resolveEquipmentConstraint(self: *CharacterBuilder, constraint: EquipmentConstraint, include_none: bool) ?*const Equipment {
        return switch (constraint) {
            .none => if (include_none) null else pickRandomEquipmentOfCategory(self.rng, .utility),
            .specific => |eq| eq,
            .category => |cat| pickRandomEquipmentOfCategory(self.rng, cat),
            .hand_requirement => |hr| pickRandomEquipmentOfHandRequirement(self.rng, hr),
        };
    }

    fn resolveSkillConstraint(self: *CharacterBuilder, constraint: SkillConstraint, position_skills: []const Skill, school_skills: []const Skill) ?*const Skill {
        return switch (constraint) {
            .none => null,
            .specific => |sk| sk,
            .creates_wall => findWallSkill(position_skills),
            .destroys_wall => findWallBreakerSkill(position_skills),
            .any_from_school => |_| if (school_skills.len > 0)
                &school_skills[self.rng.intRangeAtMost(usize, 0, school_skills.len - 1)]
            else
                null,
            .any_from_position => |_| if (position_skills.len > 0)
                &position_skills[self.rng.intRangeAtMost(usize, 0, position_skills.len - 1)]
            else
                null,
            .in_slot => null, // Handled separately
        };
    }
};

// ============================================
// TEAM BUILDER
// ============================================

pub const TeamBuilder = struct {
    allocator: std.mem.Allocator,
    rng: *std.Random,
    id_gen: *entity.EntityIdGenerator,

    characters: std.array_list.Aligned(Character, null),
    team: Team = .blue,
    base_position: rl.Vector3 = .{ .x = 0, .y = 0, .z = 0 },
    spacing: f32 = 100.0,
    color: rl.Color = .blue,

    pub fn init(allocator: std.mem.Allocator, rng: *std.Random, id_gen: *entity.EntityIdGenerator) TeamBuilder {
        return .{
            .allocator = allocator,
            .rng = rng,
            .id_gen = id_gen,
            .characters = .{},
        };
    }

    pub fn deinit(self: *TeamBuilder) void {
        self.characters.deinit(self.allocator);
    }

    pub fn withTeam(self: *TeamBuilder, t: Team) *TeamBuilder {
        self.team = t;
        return self;
    }

    pub fn withColor(self: *TeamBuilder, c: rl.Color) *TeamBuilder {
        self.color = c;
        return self;
    }

    pub fn withBasePosition(self: *TeamBuilder, pos: rl.Vector3) *TeamBuilder {
        self.base_position = pos;
        return self;
    }

    pub fn withSpacing(self: *TeamBuilder, s: f32) *TeamBuilder {
        self.spacing = s;
        return self;
    }

    /// Add a character built with a builder
    pub fn addCharacter(self: *TeamBuilder, builder: *CharacterBuilder) !void {
        _ = builder.withTeam(self.team).withColor(self.color);

        // Position the character based on team count
        const char_count = self.characters.items.len;
        _ = builder.withPosition3D(.{
            .x = self.base_position.x + (@as(f32, @floatFromInt(char_count)) - 1.5) * self.spacing,
            .y = self.base_position.y,
            .z = self.base_position.z,
        });

        const char = builder.build();
        try self.characters.append(self.allocator, char);
    }

    /// Add multiple characters with a composition constraint
    pub fn addComposition(self: *TeamBuilder, constraint: CharacterCompositionConstraint, count: u32) !void {
        for (0..count) |_| {
            var builder = CharacterBuilder.init(self.allocator, self.rng, self.id_gen);

            if (constraint.school) |s| {
                _ = builder.withSchool(s);
            }
            if (constraint.position) |p| {
                _ = builder.withPosition(p);
            }

            for (constraint.equipment_constraints, 0..) |eq_constraint, eq_idx| {
                if (eq_idx == 0) {
                    _ = builder.withMainHand(eq_constraint);
                } else if (eq_idx == 1) {
                    _ = builder.withOffHand(eq_constraint);
                } else if (eq_idx == 2) {
                    _ = builder.withWorn(eq_constraint);
                }
            }

            for (constraint.skill_constraints, 0..) |skill_constraint, skill_idx| {
                if (skill_idx < character.MAX_SKILLS) {
                    _ = builder.withSkillInSlot(@intCast(skill_idx), skill_constraint);
                }
            }

            try self.addCharacter(&builder);
        }
    }

    pub fn build(self: *TeamBuilder) ![]Character {
        return self.characters.items;
    }

    pub fn buildInto(self: *TeamBuilder, dest: []Character) !usize {
        const count = @min(self.characters.items.len, dest.len);
        for (0..count) |i| {
            dest[i] = self.characters.items[i];
        }
        return count;
    }
};

// ============================================
// ARENA BUILDER (for 3+ teams)
// ============================================

pub const ArenaBuilder = struct {
    allocator: std.mem.Allocator,
    rng: *std.Random,
    id_gen: *entity.EntityIdGenerator,

    teams: std.array_list.Aligned(TeamBuilder, null),

    pub fn init(allocator: std.mem.Allocator, rng: *std.Random, id_gen: *entity.EntityIdGenerator) ArenaBuilder {
        return .{
            .allocator = allocator,
            .rng = rng,
            .id_gen = id_gen,
            .teams = .{},
        };
    }

    pub fn deinit(self: *ArenaBuilder) void {
        for (self.teams.items) |*team| {
            team.deinit();
        }
        self.teams.deinit(self.allocator);
    }

    pub fn addTeam(self: *ArenaBuilder) !*TeamBuilder {
        const team = TeamBuilder.init(self.allocator, self.rng, self.id_gen);
        try self.teams.append(self.allocator, team);
        return &self.teams.items[self.teams.items.len - 1];
    }

    pub fn teamCount(self: *const ArenaBuilder) usize {
        return self.teams.items.len;
    }

    pub fn getTeam(self: *ArenaBuilder, idx: usize) ?*TeamBuilder {
        if (idx < self.teams.items.len) {
            return &self.teams.items[idx];
        }
        return null;
    }

    /// Collect all characters from all teams into a flat array
    pub fn buildAll(self: *ArenaBuilder, allocator: std.mem.Allocator) ![]Character {
        var all_chars: std.array_list.Aligned(Character, null) = .{};
        defer all_chars.deinit(allocator);

        for (self.teams.items) |team| {
            try all_chars.appendSlice(allocator, team.characters.items);
        }

        return all_chars.toOwnedSlice();
    }
};

// ============================================
// HELPER FUNCTIONS
// ============================================

fn pickRandomSchool(rng: *std.Random) School {
    const all_schools = [_]School{ .private_school, .public_school, .montessori, .homeschool, .waldorf };
    const idx = rng.intRangeAtMost(usize, 0, all_schools.len - 1);
    return all_schools[idx];
}

fn pickRandomPosition(rng: *std.Random) Position {
    const non_healer_positions = [_]Position{ .pitcher, .fielder, .sledder, .shoveler, .animator };
    const idx = rng.intRangeAtMost(usize, 0, non_healer_positions.len - 1);
    return non_healer_positions[idx];
}

fn pickRandomEquipmentOfCategory(rng: *std.Random, cat: equipment.EquipmentCategory) *const Equipment {
    const all_equipment = [_]*const Equipment{
        &equipment.BigShovel,
        &equipment.IceScraper,
        &equipment.LacrosseStick,
        &equipment.JaiAlaiScoop,
        &equipment.Slingshot,
        &equipment.SaucerSled,
        &equipment.GarbageCanLid,
        &equipment.Thermos,
        &equipment.Toboggan,
        &equipment.Mittens,
        &equipment.Blanket,
    };

    var matching: [all_equipment.len]*const Equipment = undefined;
    var matching_count: usize = 0;

    for (all_equipment) |eq| {
        if (eq.category == cat) {
            matching[matching_count] = eq;
            matching_count += 1;
        }
    }

    if (matching_count == 0) return &equipment.Thermos; // Fallback
    const idx = rng.intRangeAtMost(usize, 0, matching_count - 1);
    return matching[idx];
}

fn pickRandomEquipmentOfHandRequirement(rng: *std.Random, hr: equipment.HandRequirement) *const Equipment {
    const all_equipment = [_]*const Equipment{
        &equipment.BigShovel,
        &equipment.IceScraper,
        &equipment.LacrosseStick,
        &equipment.JaiAlaiScoop,
        &equipment.Slingshot,
        &equipment.SaucerSled,
        &equipment.GarbageCanLid,
        &equipment.Thermos,
        &equipment.Toboggan,
        &equipment.Mittens,
        &equipment.Blanket,
    };

    var matching: [all_equipment.len]*const Equipment = undefined;
    var matching_count: usize = 0;

    for (all_equipment) |eq| {
        if (eq.hand_requirement == hr) {
            matching[matching_count] = eq;
            matching_count += 1;
        }
    }

    if (matching_count == 0) return &equipment.Thermos; // Fallback
    const idx = rng.intRangeAtMost(usize, 0, matching_count - 1);
    return matching[idx];
}

fn assignRandomEquipment(char: *Character, rng: *std.Random) void {
    const melee_weapons = [_]*const equipment.Equipment{ &equipment.BigShovel, &equipment.IceScraper };
    const throwing_tools = [_]*const equipment.Equipment{ &equipment.LacrosseStick, &equipment.JaiAlaiScoop, &equipment.Slingshot };
    const shields = [_]*const equipment.Equipment{ &equipment.SaucerSled, &equipment.GarbageCanLid };
    const utility_items = [_]*const equipment.Equipment{ &equipment.Thermos, &equipment.Toboggan };
    const worn_items = [_]*const equipment.Equipment{ &equipment.Mittens, &equipment.Blanket };

    const roll = rng.intRangeAtMost(u8, 0, 100);

    if (roll < 30) {
        const melee = melee_weapons[rng.intRangeAtMost(usize, 0, melee_weapons.len - 1)];
        char.main_hand = melee;
        if (melee.hand_requirement == .one_hand and rng.boolean()) {
            char.off_hand = shields[rng.intRangeAtMost(usize, 0, shields.len - 1)];
        }
    } else if (roll < 60) {
        const thrower = throwing_tools[rng.intRangeAtMost(usize, 0, throwing_tools.len - 1)];
        char.main_hand = thrower;
        if (thrower.hand_requirement == .one_hand and rng.boolean()) {
            if (rng.boolean()) {
                char.off_hand = shields[rng.intRangeAtMost(usize, 0, shields.len - 1)];
            } else {
                char.off_hand = &equipment.Thermos;
            }
        }
    } else if (roll < 80) {
        if (rng.boolean()) {
            char.main_hand = utility_items[rng.intRangeAtMost(usize, 0, utility_items.len - 1)];
        } else {
            char.main_hand = shields[rng.intRangeAtMost(usize, 0, shields.len - 1)];
            if (rng.boolean()) {
                char.off_hand = &equipment.JaiAlaiScoop;
            }
        }
    }

    if (rng.boolean()) {
        char.worn = worn_items[rng.intRangeAtMost(usize, 0, worn_items.len - 1)];
    }
}

fn findWallSkill(position_skills: []const Skill) ?*const Skill {
    for (position_skills) |*skill| {
        if (skill.creates_wall) {
            return skill;
        }
    }
    return null;
}

fn findWallBreakerSkill(position_skills: []const Skill) ?*const Skill {
    for (position_skills) |*skill| {
        if (skill.destroys_walls) {
            return skill;
        }
    }
    return null;
}
