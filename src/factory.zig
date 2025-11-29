const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const school = @import("school.zig");
const position = @import("position.zig");
const skills = @import("skills.zig");
const equipment = @import("equipment.zig");
const gear_slot = @import("gear_slot.zig");
const entity = @import("entity.zig");
const campaign = @import("campaign.zig");
const encounter = @import("encounter.zig");
const ai = @import("ai.zig");

const Character = character.Character;
const School = school.School;
const Position = position.Position;
const Skill = character.Skill;
const Equipment = equipment.Equipment;
const Gear = gear_slot.Gear;
const EntityId = entity.EntityId;
const Team = entity.Team;
const SkillPool = campaign.SkillPool;
const Encounter = encounter.Encounter;
const EnemySpec = encounter.EnemySpec;
const EnemyWave = encounter.EnemyWave;
const BossConfig = encounter.BossConfig;
const AIState = ai.AIState;

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
    any_ap, // Any AP skill from the AP pool
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

    // Optional skill pool (if provided, skills are drawn from pool instead of school/position defaults)
    skill_pool: ?*const SkillPool = null,

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

    pub fn withAPSkillInSlot(self: *CharacterBuilder, slot: u8) *CharacterBuilder {
        return self.withSkillInSlot(slot, .any_ap);
    }

    pub fn withSkillPool(self: *CharacterBuilder, pool: *const SkillPool) *CharacterBuilder {
        self.skill_pool = pool;
        return self;
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
            .stats = .{
                .warmth = self.warmth,
                .max_warmth = self.max_warmth,
                .energy = selected_school.getMaxEnergy(),
                .max_energy = selected_school.getMaxEnergy(),
            },
            .team = self.team,
            .school = selected_school,
            .player_position = selected_position,
            .casting = .{
                .skills = [_]?*const Skill{null} ** character.MAX_SKILLS,
                .selected_index = 0,
            },
            .gear = [_]?*const character.Gear{null} ** 6,
        };

        // Apply equipment constraints
        self.equipCharacter(&char);

        // Apply skill constraints
        self.skillCharacter(&char);

        // Recalculate totals
        char.recalculateGearStats();

        return char;
    }

    fn generateName(self: *CharacterBuilder) [:0]const u8 {
        // Generate names based on position for better combat log readability
        // Use team letter prefix (B=Blue, R=Red, Y=Yellow, G=Green) + position abbreviation
        const team_prefix: u8 = switch (self.team) {
            .blue => 'B',
            .red => 'R',
            .yellow => 'Y',
            .green => 'G',
            .none => 'N',
        };

        const pos = self.position_override orelse pickRandomPosition(self.rng);

        // Return position-based names with team indicator
        // These are comptime strings so they're valid for the lifetime
        return switch (pos) {
            .pitcher => switch (team_prefix) {
                'B' => "BluePitcher",
                'R' => "RedPitcher",
                'Y' => "YellowPitcher",
                'G' => "GreenPitcher",
                else => "Pitcher",
            },
            .fielder => switch (team_prefix) {
                'B' => "BlueFielder",
                'R' => "RedFielder",
                'Y' => "YellowFielder",
                'G' => "GreenFielder",
                else => "Fielder",
            },
            .sledder => switch (team_prefix) {
                'B' => "BlueSledder",
                'R' => "RedSledder",
                'Y' => "YellowSledder",
                'G' => "GreenSledder",
                else => "Sledder",
            },
            .shoveler => switch (team_prefix) {
                'B' => "BlueShoveler",
                'R' => "RedShoveler",
                'Y' => "YellowShoveler",
                'G' => "GreenShoveler",
                else => "Shoveler",
            },
            .animator => switch (team_prefix) {
                'B' => "BlueAnimator",
                'R' => "RedAnimator",
                'Y' => "YellowAnimator",
                'G' => "GreenAnimator",
                else => "Animator",
            },
            .thermos => switch (team_prefix) {
                'B' => "BlueThermos",
                'R' => "RedThermos",
                'Y' => "YellowThermos",
                'G' => "GreenThermos",
                else => "Thermos",
            },
        };
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
        // If using a skill pool, draw skills from the pool instead of default pools
        if (self.skill_pool) |pool| {
            self.skillCharacterFromPool(char, pool);
            return;
        }

        // Default behavior: use position and school skill pools
        const position_skills = char.player_position.getSkills();
        const school_skills = char.school.getSkills();

        for (self.skill_constraints, 0..) |constraint, slot| {
            if (slot >= character.MAX_SKILLS) break;

            if (constraint != .none) {
                char.casting.skills[slot] = self.resolveSkillConstraint(constraint, position_skills, school_skills);
            }
        }

        // Fill remaining slots with random skills
        var filled_count: usize = 0;
        for (char.casting.skills) |maybe_skill| {
            if (maybe_skill != null) filled_count += 1;
        }

        // Guarantee at least 1 wall skill in slot 0 if not set
        if (char.casting.skills[0] == null) {
            var wall_skill_idx: ?usize = null;
            for (position_skills, 0..) |skill, idx| {
                if (skill.creates_wall) {
                    wall_skill_idx = idx;
                    break;
                }
            }
            if (wall_skill_idx) |idx| {
                char.casting.skills[0] = &position_skills[idx];
                filled_count += 1;
            }
        }

        // Fill slots 1-3 with position skills
        var attempts: usize = 0;
        var slot_idx: usize = 1;
        while (slot_idx < 4 and attempts < position_skills.len * 3) : (attempts += 1) {
            if (position_skills.len == 0) break;
            if (char.casting.skills[slot_idx] != null) {
                slot_idx += 1;
                continue;
            }

            const random_idx = self.rng.intRangeAtMost(usize, 0, position_skills.len - 1);
            const skill = &position_skills[random_idx];

            // Check not already loaded
            var already_loaded = false;
            for (0..slot_idx) |check_idx| {
                if (char.casting.skills[check_idx] == skill) {
                    already_loaded = true;
                    break;
                }
            }

            if (!already_loaded) {
                char.casting.skills[slot_idx] = skill;
                slot_idx += 1;
            }
        }

        // Fill slots 4-6 with school skills (reserve slot 7 for AP)
        attempts = 0;
        slot_idx = 4;
        while (slot_idx < 7 and attempts < school_skills.len * 3) : (attempts += 1) {
            if (school_skills.len == 0) break;
            if (char.casting.skills[slot_idx] != null) {
                slot_idx += 1;
                continue;
            }

            const random_idx = self.rng.intRangeAtMost(usize, 0, school_skills.len - 1);
            const skill = &school_skills[random_idx];

            // Check not already loaded
            var already_loaded = false;
            for (4..slot_idx) |check_idx| {
                if (char.casting.skills[check_idx] == skill) {
                    already_loaded = true;
                    break;
                }
            }

            if (!already_loaded) {
                char.casting.skills[slot_idx] = skill;
                slot_idx += 1;
            }
        }

        // Slot 7: Assign a random AP skill from character's school+position pools
        if (char.casting.skills[7] == null) {
            char.casting.skills[7] = getRandomAPSkillFromPools(position_skills, school_skills, self.rng);
        }
    }

    /// Fill skill bar from a skill pool (campaign mode)
    fn skillCharacterFromPool(self: *CharacterBuilder, char: *Character, pool: *const SkillPool) void {
        // First, apply any specific skill constraints
        for (self.skill_constraints, 0..) |constraint, slot| {
            if (slot >= character.MAX_SKILLS) break;

            if (constraint != .none) {
                // Try to resolve constraint from pool
                char.casting.skills[slot] = self.resolveSkillConstraintFromPool(constraint, pool);
            }
        }

        // Fill remaining slots with random skills from pool
        var slot_idx: usize = 0;
        while (slot_idx < character.MAX_SKILLS) : (slot_idx += 1) {
            if (char.casting.skills[slot_idx] != null) continue; // Already filled
            if (pool.count == 0) break;

            // Pick a random skill from pool
            var attempts: usize = 0;
            while (attempts < pool.count * 3) : (attempts += 1) {
                const random_idx = self.rng.intRangeAtMost(u16, 0, pool.count - 1);
                if (pool.get(random_idx)) |skill| {
                    // Check if already in skill bar
                    var already_loaded = false;
                    for (0..slot_idx) |check_idx| {
                        if (char.casting.skills[check_idx]) |existing| {
                            if (std.mem.eql(u8, existing.name, skill.name)) {
                                already_loaded = true;
                                break;
                            }
                        }
                    }

                    if (!already_loaded) {
                        char.casting.skills[slot_idx] = skill;
                        break;
                    }
                }
            }
        }

        // Ensure slot 7 has an AP skill if available in pool
        if (char.casting.skills[7] != null) {
            if (char.casting.skills[7].?.is_ap) {
                return; // Already has AP skill
            }
        }

        // Try to find an AP skill in pool for slot 7
        for (0..pool.count) |i| {
            if (pool.get(@intCast(i))) |skill| {
                if (skill.is_ap) {
                    // Check if already loaded
                    var already_loaded = false;
                    for (0..7) |check_idx| {
                        if (char.casting.skills[check_idx]) |existing| {
                            if (std.mem.eql(u8, existing.name, skill.name)) {
                                already_loaded = true;
                                break;
                            }
                        }
                    }

                    if (!already_loaded) {
                        char.casting.skills[7] = skill;
                        break;
                    }
                }
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
            .any_ap => getRandomAPSkillFromPools(position_skills, school_skills, self.rng),
            .in_slot => null, // Handled separately
        };
    }

    fn resolveSkillConstraintFromPool(self: *CharacterBuilder, constraint: SkillConstraint, pool: *const SkillPool) ?*const Skill {
        return switch (constraint) {
            .none => null,
            .specific => |sk| sk,
            .creates_wall => findWallSkillInPool(pool),
            .destroys_wall => findWallBreakerSkillInPool(pool),
            .any_from_school, .any_from_position => {
                // When using a skill pool, we can't filter by school/position
                // since skills don't store that metadata. Just pick a random skill.
                if (pool.count == 0) return null;
                const idx = self.rng.intRangeAtMost(u16, 0, pool.count - 1);
                return pool.get(idx);
            },
            .any_ap => getRandomAPSkillFromPool(pool, self.rng),
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

/// Returns a random AP skill from the character's school and position skill pools
fn getRandomAPSkillFromPools(position_skills: []const Skill, school_skills: []const Skill, rng: *std.Random) ?*const Skill {
    // Count AP skills in both pools
    var ap_count: usize = 0;
    for (position_skills) |skill| {
        if (skill.is_ap) ap_count += 1;
    }
    for (school_skills) |skill| {
        if (skill.is_ap) ap_count += 1;
    }

    if (ap_count == 0) return null;

    // Pick a random AP skill
    var target_idx = rng.intRangeAtMost(usize, 0, ap_count - 1);

    // Find it in position skills first
    for (position_skills) |*skill| {
        if (skill.is_ap) {
            if (target_idx == 0) return skill;
            target_idx -= 1;
        }
    }

    // Then in school skills
    for (school_skills) |*skill| {
        if (skill.is_ap) {
            if (target_idx == 0) return skill;
            target_idx -= 1;
        }
    }

    return null;
}

// ============================================
// SKILL POOL HELPER FUNCTIONS
// ============================================

/// Find a wall-creating skill in a skill pool
fn findWallSkillInPool(pool: *const SkillPool) ?*const Skill {
    for (0..pool.count) |i| {
        if (pool.get(@intCast(i))) |skill| {
            if (skill.creates_wall) return skill;
        }
    }
    return null;
}

/// Find a wall-breaking skill in a skill pool
fn findWallBreakerSkillInPool(pool: *const SkillPool) ?*const Skill {
    for (0..pool.count) |i| {
        if (pool.get(@intCast(i))) |skill| {
            if (skill.destroys_walls) return skill;
        }
    }
    return null;
}

/// Returns a random AP skill from a skill pool
fn getRandomAPSkillFromPool(pool: *const SkillPool, rng: *std.Random) ?*const Skill {
    const ap_count = pool.countApSkills();
    if (ap_count == 0) return null;

    // Pick a random AP skill
    var target_idx = rng.intRangeAtMost(u8, 0, ap_count - 1);

    for (0..pool.count) |i| {
        if (pool.get(@intCast(i))) |skill| {
            if (skill.is_ap) {
                if (target_idx == 0) return skill;
                target_idx -= 1;
            }
        }
    }

    return null;
}

// ============================================
// ENCOUNTER BUILDER
// ============================================
//
// Builds characters and AI states from an Encounter definition.
// Handles enemy waves, bosses, and initializes AI with proper
// engagement parameters (aggro radius, leash, spawn positions).
//

/// Result of building an encounter - includes both characters and their AI states
pub const EncounterBuildResult = struct {
    /// All spawned enemy characters
    enemies: []Character,
    /// AI states for each enemy (parallel array)
    ai_states: []AIState,
    /// Index of the boss character (-1 if no boss)
    boss_index: i32,
    /// Total enemy count
    count: usize,
};

pub const EncounterBuilder = struct {
    allocator: std.mem.Allocator,
    rng: *std.Random,
    id_gen: *entity.EntityIdGenerator,

    /// The encounter definition to build from
    enc: *const Encounter,

    /// Team for spawned enemies (default: red = enemy team)
    enemy_team: Team = .red,

    /// Difficulty multiplier (affects stats)
    difficulty_multiplier: f32 = 1.0,

    /// Active affixes to apply
    active_affixes: []const encounter.ActiveAffix = &[_]encounter.ActiveAffix{},

    pub fn init(
        allocator: std.mem.Allocator,
        rng: *std.Random,
        id_gen: *entity.EntityIdGenerator,
        enc: *const Encounter,
    ) EncounterBuilder {
        return .{
            .allocator = allocator,
            .rng = rng,
            .id_gen = id_gen,
            .enc = enc,
        };
    }

    pub fn withEnemyTeam(self: *EncounterBuilder, team: Team) *EncounterBuilder {
        self.enemy_team = team;
        return self;
    }

    pub fn withDifficulty(self: *EncounterBuilder, mult: f32) *EncounterBuilder {
        self.difficulty_multiplier = mult;
        return self;
    }

    pub fn withAffixes(self: *EncounterBuilder, affixes: []const encounter.ActiveAffix) *EncounterBuilder {
        self.active_affixes = affixes;
        return self;
    }

    /// Build all enemies from the encounter definition
    /// Returns characters and their corresponding AI states
    pub fn build(self: *EncounterBuilder) !EncounterBuildResult {
        // Count total enemies
        var total_count: usize = 0;
        for (self.enc.enemy_waves) |wave| {
            total_count += wave.enemies.len;
        }
        if (self.enc.boss != null) {
            total_count += 1;
        }

        // Allocate arrays
        var enemies = try self.allocator.alloc(Character, total_count);
        var ai_states = try self.allocator.alloc(AIState, total_count);

        var idx: usize = 0;
        var boss_index: i32 = -1;

        // Spawn enemy waves
        for (self.enc.enemy_waves, 0..) |wave, wave_idx| {
            for (wave.enemies, 0..) |enemy_spec, enemy_idx| {
                // Calculate spawn position within wave
                const spawn_pos = self.calculateSpawnPosition(wave, enemy_idx);

                // Build the character
                enemies[idx] = self.buildEnemyFromSpec(enemy_spec, spawn_pos);

                // Build the AI state with engagement parameters
                ai_states[idx] = self.buildAIStateForWave(wave, @intCast(wave_idx), spawn_pos, enemy_spec);

                idx += 1;
            }
        }

        // Spawn boss if present
        if (self.enc.boss) |boss_config| {
            boss_index = @intCast(idx);

            const boss_pos = self.enc.arena_bounds.center;
            enemies[idx] = self.buildBossFromConfig(boss_config, boss_pos);
            ai_states[idx] = self.buildAIStateForBoss(boss_config, boss_pos);

            idx += 1;
        }

        return .{
            .enemies = enemies,
            .ai_states = ai_states,
            .boss_index = boss_index,
            .count = idx,
        };
    }

    /// Build a single enemy character from an EnemySpec
    fn buildEnemyFromSpec(self: *EncounterBuilder, spec: EnemySpec, spawn_pos: rl.Vector3) Character {
        const base_warmth: f32 = 150.0;
        const scaled_warmth = base_warmth * spec.warmth_multiplier * self.difficulty_multiplier * self.getAffixHealthMultiplier();

        var char = Character{
            .id = self.id_gen.generate(),
            .position = spawn_pos,
            .previous_position = spawn_pos,
            .radius = 10.0 * spec.scale,
            .color = spec.color_tint orelse getTeamColor(self.enemy_team),
            .school_color = getTeamColor(self.enemy_team),
            .position_color = getTeamColor(self.enemy_team),
            .name = spec.name,
            .stats = .{
                .warmth = scaled_warmth,
                .max_warmth = scaled_warmth,
                .energy = spec.school.getMaxEnergy(),
                .max_energy = @intFromFloat(@as(f32, @floatFromInt(spec.school.getMaxEnergy())) * spec.energy_multiplier),
            },
            .team = self.enemy_team,
            .school = spec.school,
            .player_position = spec.position,
            .casting = .{
                .skills = [_]?*const Skill{null} ** character.MAX_SKILLS,
                .selected_index = 0,
            },
            .gear = [_]?*const character.Gear{null} ** 6,
        };

        // Apply skill overrides or use defaults
        if (spec.skill_overrides) |overrides| {
            for (overrides, 0..) |maybe_skill, slot| {
                char.casting.skills[slot] = maybe_skill;
            }
        } else {
            // Use default skills from position/school
            self.applyDefaultSkills(&char);
        }

        return char;
    }

    /// Build a boss character from BossConfig
    fn buildBossFromConfig(self: *EncounterBuilder, config: BossConfig, spawn_pos: rl.Vector3) Character {
        var char = self.buildEnemyFromSpec(config.base, spawn_pos);

        // Bosses get additional scaling from tyrannical affix
        if (self.hasAffix(.tyrannical)) {
            char.stats.warmth *= 1.3;
            char.stats.max_warmth *= 1.3;
        }

        // Apply signature skills if present
        for (config.signature_skills, 0..) |skill, idx| {
            if (idx < character.MAX_SKILLS) {
                char.casting.skills[idx] = skill;
            }
        }

        return char;
    }

    /// Build AI state for a wave enemy
    fn buildAIStateForWave(self: *EncounterBuilder, wave: EnemyWave, wave_idx: u8, spawn_pos: rl.Vector3, spec: EnemySpec) AIState {
        var ai_state = AIState.initForEncounter(spec.position, spawn_pos, wave_idx);

        // Set engagement parameters from wave config
        ai_state.aggro_radius = wave.engagement_radius;
        ai_state.leash_radius = wave.leash_radius;

        // Start in idle state (not engaged)
        ai_state.engagement = .idle;

        // Apply engagement rules from encounter
        if (self.enc.engagement_rules.default_aggro_radius > 0 and wave.engagement_radius == 0) {
            ai_state.aggro_radius = self.enc.engagement_rules.default_aggro_radius;
        }
        if (self.enc.engagement_rules.default_leash_radius > 0 and wave.leash_radius == 0) {
            ai_state.leash_radius = self.enc.engagement_rules.default_leash_radius;
        }

        return ai_state;
    }

    /// Build AI state for a boss
    fn buildAIStateForBoss(self: *EncounterBuilder, config: BossConfig, spawn_pos: rl.Vector3) AIState {
        _ = self; // Encounter rules applied via config
        var ai_state = AIState.initForEncounter(config.base.position, spawn_pos, 255); // Wave 255 = boss

        // Bosses have larger aggro radius (their arena)
        ai_state.aggro_radius = config.arena_radius;
        ai_state.leash_radius = config.arena_radius * 1.5;

        // Bosses start idle until players enter their arena
        ai_state.engagement = .idle;

        // Initialize phase tracking
        ai_state.current_phase = 0;
        ai_state.triggered_phases = 0;

        return ai_state;
    }

    /// Calculate spawn position for an enemy within a wave
    fn calculateSpawnPosition(self: *EncounterBuilder, wave: EnemyWave, enemy_idx: usize) rl.Vector3 {
        const base = wave.spawn_position;

        if (wave.enemies.len <= 1) {
            return base;
        }

        // Spread enemies in a circle around the spawn point
        const angle = (@as(f32, @floatFromInt(enemy_idx)) / @as(f32, @floatFromInt(wave.enemies.len))) * std.math.pi * 2.0;
        const radius = wave.spawn_radius * (0.5 + self.rng.float(f32) * 0.5);

        return .{
            .x = base.x + @cos(angle) * radius,
            .y = base.y,
            .z = base.z + @sin(angle) * radius,
        };
    }

    /// Apply default skills from position and school
    fn applyDefaultSkills(self: *EncounterBuilder, char: *Character) void {
        const position_skills = char.player_position.getSkills();
        const school_skills = char.school.getSkills();

        // Slot 0: Wall skill if available
        for (position_skills) |*skill| {
            if (skill.creates_wall) {
                char.casting.skills[0] = skill;
                break;
            }
        }

        // Slots 1-3: Position skills
        var slot: usize = 1;
        for (position_skills, 0..) |*skill, idx| {
            if (slot >= 4) break;
            if (idx == 0 and skill.creates_wall) continue; // Skip wall skill
            char.casting.skills[slot] = skill;
            slot += 1;
        }

        // Slots 4-6: School skills
        slot = 4;
        for (school_skills) |*skill| {
            if (slot >= 7) break;
            char.casting.skills[slot] = skill;
            slot += 1;
        }

        // Slot 7: Random AP skill
        char.casting.skills[7] = getRandomAPSkillFromPools(position_skills, school_skills, self.rng);
    }

    /// Get health multiplier from active affixes
    fn getAffixHealthMultiplier(self: *EncounterBuilder) f32 {
        var mult: f32 = 1.0;
        for (self.active_affixes) |active| {
            switch (active.affix) {
                .fortified => mult *= 1.2 * active.intensity,
                .fortified_trash => mult *= 1.2 * active.intensity,
                else => {},
            }
        }
        return mult;
    }

    /// Check if an affix is active
    fn hasAffix(self: *EncounterBuilder, affix: encounter.EncounterAffix) bool {
        for (self.active_affixes) |active| {
            if (active.affix == affix) return true;
        }
        return false;
    }
};

/// Get team color
fn getTeamColor(team: Team) rl.Color {
    return switch (team) {
        .red => rl.Color{ .r = 220, .g = 60, .b = 60, .a = 255 },
        .blue => rl.Color{ .r = 60, .g = 120, .b = 220, .a = 255 },
        .yellow => rl.Color{ .r = 220, .g = 200, .b = 60, .a = 255 },
        .green => rl.Color{ .r = 60, .g = 180, .b = 80, .a = 255 },
        .none => rl.Color{ .r = 128, .g = 128, .b = 128, .a = 255 },
    };
}

// ============================================
// ENCOUNTER SPAWNING HELPERS
// ============================================

/// Spawn enemies from an encounter into existing entity arrays
/// Returns the number of enemies spawned
pub fn spawnEncounterEnemies(
    enc: *const Encounter,
    entities: []Character,
    ai_states: []AIState,
    start_index: usize,
    allocator: std.mem.Allocator,
    rng: *std.Random,
    id_gen: *entity.EntityIdGenerator,
) !usize {
    var builder = EncounterBuilder.init(allocator, rng, id_gen, enc);
    const result = try builder.build();
    defer allocator.free(result.enemies);
    defer allocator.free(result.ai_states);

    // Copy into destination arrays
    const copy_count = @min(result.count, entities.len - start_index);
    for (0..copy_count) |i| {
        entities[start_index + i] = result.enemies[i];
        if (start_index + i < ai_states.len) {
            ai_states[start_index + i] = result.ai_states[i];
        }
    }

    return copy_count;
}
