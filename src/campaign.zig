//! Campaign Mode - Roguelike overworld for "Saving Private Ryan in a snowball war"
//!
//! The campaign is a turn-based overworld where you navigate an endless suburban warzone,
//! choosing encounters to: capture skills, find your brother, and shift the war in your faction's favor.
//!
//! Design Philosophy:
//! The campaign has four dimensions, mirroring the effects system:
//! - WHAT: What kind of encounter (skirmish, boss, intel, strategic)
//! - WHERE: Position in the overworld, faction territory
//! - WHEN: Time pressure, expiration, turn-based progression
//! - WHY: Campaign goal (find brother, territorial control, survival)
//!
//! Core loop:
//! 1. View overworld map with encounter nodes
//! 2. Choose a node (skirmish, boss, intel, strategic)
//! 3. Fight the encounter using existing combat system
//! 4. Receive rewards (skills, party members, quest progress)
//! 5. War state updates based on outcome
//! 6. Repeat until campaign goal achieved or party wipes
//!
//! Framing: "Saving Private Ryan" in a snowball war
//! You are tasked by your mother to get your younger brother home safe.
//! You turn around and he's gone. You traverse an endless multi-belligerent war
//! searching for your lost brother so you don't get grounded.

const std = @import("std");
const rl = @import("raylib");
const skills = @import("skills.zig");
const school = @import("school.zig");
const position = @import("position.zig");
const entity = @import("entity.zig");
const character = @import("character.zig");
const palette = @import("color_palette.zig");
const polyomino_map = @import("polyomino_map.zig");

const Skill = skills.Skill;
const School = school.School;
const Position = position.Position;
const Character = character.Character;
const Team = entity.Team;
const PolyominoMap = polyomino_map.PolyominoMap;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Returns a random AP skill from a specific school's skill pool
fn getRandomAPSkillFromSchool(s: School, rng: *std.Random) ?*const Skill {
    const school_skills = s.getSkills();

    // Count AP skills
    var ap_count: usize = 0;
    for (school_skills) |skill| {
        if (skill.is_ap) ap_count += 1;
    }

    if (ap_count == 0) return null;

    // Pick a random AP skill
    var target_idx = rng.intRangeAtMost(usize, 0, ap_count - 1);
    for (school_skills) |*skill| {
        if (skill.is_ap) {
            if (target_idx == 0) return skill;
            target_idx -= 1;
        }
    }

    return null;
}

// ============================================================================
// CONSTANTS
// ============================================================================

pub const MAX_PARTY_SIZE: usize = 6;
pub const MAX_SKILL_POOL_SIZE: usize = 64;
pub const MAX_OVERWORLD_NODES: usize = 32;
pub const SKILL_BAR_SIZE: usize = 8;

// ============================================================================
// FACTIONS - The multi-belligerent war
// ============================================================================

/// Factions in the endless suburban snowball war
/// Each controls territory and has their own battle lines
pub const Faction = enum(u8) {
    blue = 0, // Your faction - the neighborhood kids
    red = 1, // Primary rivals - the kids from across the park
    yellow = 2, // Third party - the homeschool collective
    green = 3, // Fourth party - the after-school program kids
    purple = 4, // Fifth party - the private school kids
    orange = 5, // Sixth party - the sports league kids

    pub fn isEnemy(self: Faction, other: Faction) bool {
        return self != other;
    }

    pub fn isAlly(self: Faction, other: Faction) bool {
        return self == other;
    }

    pub fn getName(self: Faction) [:0]const u8 {
        return switch (self) {
            .blue => "Maple Street Gang",
            .red => "Oak Park Crew",
            .yellow => "Homeschool Collective",
            .green => "After-School Alliance",
            .purple => "St. Augustine Prep",
            .orange => "Little League Legends",
        };
    }

    pub fn getColor(self: Faction) u32 {
        return switch (self) {
            .blue => 0x4488FF,
            .red => 0xFF4444,
            .yellow => 0xFFCC00,
            .green => 0x44CC44,
            .purple => 0x9944FF,
            .orange => 0xFF8844,
        };
    }
};

// ============================================================================
// ENCOUNTER TYPES - WHAT you're fighting
// ============================================================================

/// The type of encounter determines rewards and difficulty curve
/// This is the "WHAT" dimension of campaign encounters
pub const EncounterType = enum {
    /// Quick fight against a patrol or small group
    /// Rewards: Minor skills, consumables, small faction influence
    /// Challenge: Low to medium, scales slowly
    skirmish,

    /// Assault on a defended position with a boss
    /// Rewards: Skill capture (pick 1 of 3 or AP skill)
    /// Challenge: Medium to high, requires preparation
    boss_capture,

    /// Gather information about your quest target
    /// Rewards: Quest progress, sometimes allies
    /// Challenge: Variable, sometimes social/puzzle
    intel,

    /// Fight for control of a key location
    /// Rewards: Major faction influence, territorial control
    /// Challenge: High, often timed or multi-wave
    strategic,

    /// Rescue or recruit a potential party member
    /// Rewards: New party member joins (if successful)
    /// Challenge: Medium, often escort-style
    recruitment,

    pub fn getName(self: EncounterType) [:0]const u8 {
        return switch (self) {
            .skirmish => "Neighborhood Scuffle",
            .boss_capture => "Fort Assault",
            .intel => "Last Seen Here",
            .strategic => "Critical Intersection",
            .recruitment => "Kid Needs Help",
        };
    }

    pub fn getDescription(self: EncounterType) [:0]const u8 {
        return switch (self) {
            .skirmish => "A small fight - good for warming up and grabbing basic supplies",
            .boss_capture => "Storm a defended position - defeat the leader to capture their skills",
            .intel => "Someone here might know where your brother went",
            .strategic => "Control this location to shift the war in your favor",
            .recruitment => "Help this kid out and they might join your party",
        };
    }

    /// Base challenge rating range for this encounter type
    pub fn getChallengeRange(self: EncounterType) struct { min: u8, max: u8 } {
        return switch (self) {
            .skirmish => .{ .min = 1, .max = 4 },
            .boss_capture => .{ .min = 4, .max = 8 },
            .intel => .{ .min = 2, .max = 5 },
            .strategic => .{ .min = 3, .max = 7 },
            .recruitment => .{ .min = 2, .max = 4 },
        };
    }

    /// Does this encounter type offer skill capture?
    pub fn offersSkillCapture(self: EncounterType) bool {
        return self == .boss_capture;
    }

    /// Does this encounter type offer quest progress?
    pub fn offersQuestProgress(self: EncounterType) bool {
        return self == .intel;
    }

    /// Does this encounter type offer recruitment?
    pub fn offersRecruitment(self: EncounterType) bool {
        return self == .recruitment;
    }

    /// Base faction influence gained on victory
    pub fn getBaseFactionInfluence(self: EncounterType) i8 {
        return switch (self) {
            .skirmish => 1,
            .boss_capture => 3,
            .intel => 1,
            .strategic => 5,
            .recruitment => 2,
        };
    }
};

// ============================================================================
// CAMPAIGN GOALS - WHY you're fighting
// ============================================================================

/// Campaign goal type determines win condition
/// This is the "WHY" dimension - what you're trying to accomplish
pub const GoalType = enum {
    /// Find your lost brother - the canonical "Saving Private Ryan" goal
    /// Progress: Gather intel, each node increases chance of finding him
    /// Win: Brother found (probabilistic based on progress)
    find_brother,

    /// Conquer territory for your faction
    /// Progress: Win strategic encounters
    /// Win: Control X nodes
    territorial_control,

    /// Survive the winter war
    /// Progress: Each turn survived
    /// Win: Survive N turns
    survival,

    /// Collect a set of powerful skills
    /// Progress: Capture skills from bosses
    /// Win: Capture X skills (or specific AP skills)
    skill_collection,

    pub fn getName(self: GoalType) [:0]const u8 {
        return switch (self) {
            .find_brother => "Find Your Brother",
            .territorial_control => "Win the War",
            .survival => "Survive the Winter",
            .skill_collection => "Master of Snow",
        };
    }

    pub fn getDescription(self: GoalType) [:0]const u8 {
        return switch (self) {
            .find_brother => "Your mom told you to bring your brother home. He wandered off. Find him before you both get grounded.",
            .territorial_control => "Your faction is losing ground. Turn the tide by capturing strategic positions.",
            .survival => "The war is endless. Just try to make it through without getting too cold.",
            .skill_collection => "Prove your mastery by capturing the most powerful skills in the neighborhood.",
        };
    }
};

// ============================================================================
// SKILL CAPTURE - Signet of Capture equivalent
// ============================================================================

/// Skill capture tier determines what skills are available
/// Higher tiers offer more powerful options
pub const SkillCaptureTier = enum(u8) {
    none = 0, // No skill capture
    basic = 1, // Common skills from the school pools
    advanced = 2, // Stronger skills, position-specific
    elite = 3, // AP skills available as an option

    /// Get the number of skills offered in the "bundle" option
    pub fn getBundleSize(self: SkillCaptureTier) u8 {
        return switch (self) {
            .none => 0,
            .basic => 2,
            .advanced => 3,
            .elite => 3,
        };
    }

    /// Does this tier offer an AP skill option?
    pub fn offersApSkill(self: SkillCaptureTier) bool {
        return self == .elite;
    }
};

/// A skill capture choice presented after defeating a boss
/// Player picks EITHER the AP skill OR the bundle (not both)
pub const SkillCaptureChoice = struct {
    /// Option A: One powerful AP skill (only at elite tier)
    ap_skill: ?*const Skill = null,

    /// Option B: Bundle of 2-3 regular skills
    skill_bundle: [3]?*const Skill = [_]?*const Skill{null} ** 3,
    bundle_size: u8 = 0,

    /// The tier that generated this choice
    tier: SkillCaptureTier = .none,

    pub fn hasApOption(self: SkillCaptureChoice) bool {
        return self.ap_skill != null;
    }

    pub fn hasBundleOption(self: SkillCaptureChoice) bool {
        return self.bundle_size > 0;
    }

    /// Generate a skill capture choice for a given tier
    pub fn generate(tier: SkillCaptureTier, rng: std.Random, boss_school: ?School) SkillCaptureChoice {
        var choice = SkillCaptureChoice{ .tier = tier };

        if (tier == .none) return choice;

        // AP skill option (elite tier only) - from boss's school
        if (tier.offersApSkill()) {
            if (boss_school) |s| {
                choice.ap_skill = getRandomAPSkillFromSchool(s, @constCast(&rng));
            }
        }

        // Skill bundle option
        const bundle_size = tier.getBundleSize();
        choice.bundle_size = bundle_size;

        // Pull skills from boss's school if available, otherwise random
        const skill_source = if (boss_school) |s| s.getSkills() else school.School.public_school.getSkills();

        for (0..bundle_size) |i| {
            if (i < skill_source.len) {
                const idx = rng.intRangeAtMost(usize, 0, skill_source.len - 1);
                choice.skill_bundle[i] = &skill_source[idx];
            }
        }

        return choice;
    }
};

// ============================================================================
// ENCOUNTER NODE - A point on the overworld map
// ============================================================================

/// An encounter node on the overworld map
/// Represents a location where combat/events can occur
pub const EncounterNode = struct {
    /// What type of encounter this is
    encounter_type: EncounterType,

    /// Display name (can be customized)
    name: [:0]const u8,

    /// Difficulty (1-10 scale, affects enemy count/stats)
    challenge_rating: u8,

    /// Turns until this node expires (null = permanent)
    expires_in_turns: ?u8,

    /// Which faction currently controls this area
    controlling_faction: Faction,

    /// Position on the overworld map
    x: i16,
    y: i16,

    /// Unique ID for this node
    id: u16,

    /// Preview of rewards (shown before selecting)
    skill_capture_tier: SkillCaptureTier = .none,
    offers_quest_progress: bool = false,
    offers_recruitment: bool = false,
    faction_influence: i8 = 0,

    /// Generate a random encounter node
    pub fn random(rng: std.Random, node_id: u16) EncounterNode {
        const encounter_type = rng.enumValue(EncounterType);
        const cr_range = encounter_type.getChallengeRange();

        return EncounterNode{
            .encounter_type = encounter_type,
            .name = encounter_type.getName(),
            .challenge_rating = rng.intRangeAtMost(u8, cr_range.min, cr_range.max),
            .expires_in_turns = if (rng.boolean()) rng.intRangeAtMost(u8, 2, 5) else null,
            .controlling_faction = rng.enumValue(Faction),
            .x = rng.intRangeAtMost(i16, -100, 100),
            .y = rng.intRangeAtMost(i16, -100, 100),
            .id = node_id,
            .skill_capture_tier = generateSkillTier(encounter_type, rng),
            .offers_quest_progress = encounter_type.offersQuestProgress(),
            .offers_recruitment = encounter_type.offersRecruitment(),
            .faction_influence = encounter_type.getBaseFactionInfluence(),
        };
    }

    fn generateSkillTier(encounter_type: EncounterType, rng: std.Random) SkillCaptureTier {
        if (!encounter_type.offersSkillCapture()) {
            // Non-boss encounters have small chance of basic skills
            return if (rng.intRangeAtMost(u8, 0, 10) > 8) .basic else .none;
        }

        // Boss encounters: 70% advanced, 30% elite
        return if (rng.intRangeAtMost(u8, 0, 10) > 7) .elite else .advanced;
    }

    /// Check if this node is expired
    pub fn isExpired(self: EncounterNode) bool {
        if (self.expires_in_turns) |turns| {
            return turns == 0;
        }
        return false;
    }

    /// Decrement expiration timer
    pub fn tick(self: *EncounterNode) void {
        if (self.expires_in_turns) |*turns| {
            if (turns.* > 0) turns.* -= 1;
        }
    }
};

// ============================================================================
// PARTY MEMBER - A character in your party
// ============================================================================

/// A member of the player's party
/// Persists between encounters, can be player-controlled or AI
pub const PartyMember = struct {
    /// Display name
    name: [:0]const u8,

    /// School (determines energy mechanics and skill access)
    school_type: School,

    /// Position (determines base skills and role)
    position_type: Position,

    /// Skill bar - indexes into the campaign's skill pool
    /// null = empty slot
    skill_bar: [SKILL_BAR_SIZE]?u16 = [_]?u16{null} ** SKILL_BAR_SIZE,

    /// Is this the player character?
    is_player: bool = false,

    /// Current warmth as percentage (0.0 to 1.0)
    /// Persists between encounters (partial healing between fights)
    warmth_percent: f32 = 1.0,

    /// Is this member alive?
    is_alive: bool = true,

    /// Was this member recruited during the campaign?
    is_recruited: bool = false,

    /// Unique ID within the party
    id: u8,

    pub fn isHealthy(self: PartyMember) bool {
        return self.is_alive and self.warmth_percent > 0.5;
    }

    pub fn isWounded(self: PartyMember) bool {
        return self.is_alive and self.warmth_percent <= 0.5 and self.warmth_percent > 0.0;
    }

    pub fn isDead(self: PartyMember) bool {
        return !self.is_alive or self.warmth_percent <= 0.0;
    }

    /// Heal between encounters (partial recovery)
    pub fn restoreBetweenEncounters(self: *PartyMember) void {
        if (self.is_alive) {
            // Recover 25% warmth between encounters, cap at 100%
            self.warmth_percent = @min(1.0, self.warmth_percent + 0.25);
        }
    }
};

// ============================================================================
// PARTY STATE - Your team of snowball warriors
// ============================================================================

/// State of the player's party throughout the campaign
pub const PartyState = struct {
    /// Party members (index 0 is always the player)
    members: [MAX_PARTY_SIZE]?PartyMember = [_]?PartyMember{null} ** MAX_PARTY_SIZE,

    /// Which faction the party belongs to
    faction: Faction = .blue,

    /// Next member ID to assign
    next_member_id: u8 = 0,

    /// Add the player character
    pub fn addPlayer(self: *PartyState, name: [:0]const u8, player_school: School) void {
        self.members[0] = PartyMember{
            .name = name,
            .school_type = player_school,
            .position_type = .fielder, // Default, chosen after first encounter
            .is_player = true,
            .id = self.next_member_id,
        };
        self.next_member_id += 1;
    }

    /// Add the player character with position
    pub fn addPlayerWithPosition(self: *PartyState, name: [:0]const u8, player_school: School, player_position: Position) void {
        self.members[0] = PartyMember{
            .name = name,
            .school_type = player_school,
            .position_type = player_position,
            .is_player = true,
            .id = self.next_member_id,
        };
        self.next_member_id += 1;
    }

    /// Add the starting best friend
    pub fn addBestFriend(self: *PartyState, name: [:0]const u8, friend_school: School) void {
        self.members[1] = PartyMember{
            .name = name,
            .school_type = friend_school,
            .position_type = .fielder, // Default, chosen after first encounter
            .is_player = false,
            .id = self.next_member_id,
        };
        self.next_member_id += 1;
    }

    /// Add the starting best friend with position
    pub fn addBestFriendWithPosition(self: *PartyState, name: [:0]const u8, friend_school: School, friend_position: Position) void {
        self.members[1] = PartyMember{
            .name = name,
            .school_type = friend_school,
            .position_type = friend_position,
            .is_player = false,
            .id = self.next_member_id,
        };
        self.next_member_id += 1;
    }

    /// Add player with auto-equipped starter skills
    pub fn addPlayerWithStarterSkills(self: *PartyState, name: [:0]const u8, player_school: School, player_position: Position, skill_pool: *SkillPool) void {
        const equipped = skill_pool.addStarterSkillsForCharacter(player_school, player_position);
        self.members[0] = PartyMember{
            .name = name,
            .school_type = player_school,
            .position_type = player_position,
            .is_player = true,
            .id = self.next_member_id,
            .skill_bar = .{
                @as(?u16, equipped[0]),
                @as(?u16, equipped[1]),
                @as(?u16, equipped[2]),
                @as(?u16, equipped[3]),
                null,
                null,
                null,
                null,
            },
        };
        self.next_member_id += 1;
    }

    /// Add best friend with auto-equipped starter skills
    pub fn addBestFriendWithStarterSkills(self: *PartyState, name: [:0]const u8, friend_school: School, friend_position: Position, skill_pool: *SkillPool) void {
        const equipped = skill_pool.addStarterSkillsForCharacter(friend_school, friend_position);
        self.members[1] = PartyMember{
            .name = name,
            .school_type = friend_school,
            .position_type = friend_position,
            .is_player = false,
            .id = self.next_member_id,
            .skill_bar = .{
                @as(?u16, equipped[0]),
                @as(?u16, equipped[1]),
                @as(?u16, equipped[2]),
                @as(?u16, equipped[3]),
                null,
                null,
                null,
                null,
            },
        };
        self.next_member_id += 1;
    }

    /// Recruit a new party member
    pub fn recruit(self: *PartyState, name: [:0]const u8, member_school: School, member_position: Position) bool {
        for (&self.members, 0..) |*slot, i| {
            if (i < 2) continue; // Skip player and best friend slots
            if (slot.* == null) {
                slot.* = PartyMember{
                    .name = name,
                    .school_type = member_school,
                    .position_type = member_position,
                    .is_player = false,
                    .is_recruited = true,
                    .id = self.next_member_id,
                };
                self.next_member_id += 1;
                return true;
            }
        }
        return false; // Party full
    }

    /// Count living members
    pub fn livingCount(self: PartyState) usize {
        var count: usize = 0;
        for (self.members) |maybe_member| {
            if (maybe_member) |member| {
                if (member.is_alive) count += 1;
            }
        }
        return count;
    }

    /// Check if party is wiped
    pub fn isWiped(self: PartyState) bool {
        return self.livingCount() == 0;
    }

    /// Get total party size (including dead)
    pub fn totalCount(self: PartyState) usize {
        var count: usize = 0;
        for (self.members) |maybe_member| {
            if (maybe_member != null) count += 1;
        }
        return count;
    }

    /// Restore all living members between encounters
    pub fn restoreBetweenEncounters(self: *PartyState) void {
        for (&self.members) |*maybe_member| {
            if (maybe_member.*) |*member| {
                member.restoreBetweenEncounters();
            }
        }
    }

    /// Create combat Characters from party members for an encounter
    /// Returns slice of characters (caller owns the memory)
    /// skill_pool is used to resolve skill bar indices to actual skills
    pub fn createCombatCharacters(
        self: *const PartyState,
        skill_pool: *const SkillPool,
        team: Team,
        id_gen: *entity.EntityIdGenerator,
    ) []Character {
        // Use static buffer for characters (max party size)
        const S = struct {
            var chars: [MAX_PARTY_SIZE]Character = undefined;
        };

        var count: usize = 0;

        // Spawn positions for allies
        const spawn_positions = [_]rl.Vector3{
            .{ .x = -80, .y = 0, .z = 400 },
            .{ .x = 80, .y = 0, .z = 400 },
            .{ .x = -120, .y = 0, .z = 500 },
            .{ .x = 0, .y = 0, .z = 550 },
            .{ .x = 120, .y = 0, .z = 500 },
            .{ .x = -160, .y = 0, .z = 600 },
        };

        for (self.members) |maybe_member| {
            if (maybe_member) |member| {
                if (!member.is_alive) continue;
                if (count >= MAX_PARTY_SIZE) break;

                const pos = spawn_positions[@min(count, spawn_positions.len - 1)];

                // Create base character
                var char = Character{
                    .id = id_gen.generate(),
                    .name = member.name,
                    .team = team,
                    .position = pos,
                    .previous_position = pos,
                    .radius = 10,
                    .color = palette.getCharacterColor(member.school_type, member.position_type),
                    .school_color = palette.getSchoolColor(member.school_type),
                    .position_color = palette.getPositionColor(member.position_type),
                    .school = member.school_type,
                    .player_position = member.position_type,
                };

                // Set stats based on warmth_percent
                const max_warmth: f32 = 150.0;
                char.stats.max_warmth = max_warmth;
                char.stats.warmth = max_warmth * member.warmth_percent;
                char.stats.energy = member.school_type.getMaxEnergy();
                char.stats.max_energy = member.school_type.getMaxEnergy();

                // Load skill bar from party member's equipped skills
                for (member.skill_bar, 0..) |maybe_skill_idx, slot| {
                    if (maybe_skill_idx) |skill_idx| {
                        if (skill_pool.get(skill_idx)) |skill_ptr| {
                            char.casting.skills[slot] = skill_ptr;
                        }
                    }
                }

                // If skill bar is empty, load default skills from position/school
                if (char.casting.skills[0] == null) {
                    loadDefaultSkills(&char);
                }

                S.chars[count] = char;
                count += 1;
            }
        }

        return S.chars[0..count];
    }
};

/// Load default skills for a character if their skill bar is empty
fn loadDefaultSkills(char: *Character) void {
    const position_skills = char.player_position.getSkills();
    const school_skills = char.school.getSkills();

    // Load position skills in slots 0-3
    for (position_skills, 0..) |*skill, i| {
        if (i >= 4) break;
        char.casting.skills[i] = skill;
    }

    // Load school skills in slots 4-7
    for (school_skills, 0..) |*skill, i| {
        if (i >= 4) break;
        char.casting.skills[4 + i] = skill;
    }
}

// ============================================================================
// SKILL POOL - Campaign-wide unlocked skills
// ============================================================================

/// BOG SIMPLE starter skill indices for each school
/// These are the simplest, most intuitive skills for new players
/// Rule: 2 skills per school, no AP skills, no complex conditions
pub const StarterSkillIndices = struct {
    // Public School (Red/Grit): 0=Scrap (basic damage+grit), 2=Dirty Snowball (damage+DoT)
    pub const public_school = [2]usize{ 0, 2 };

    // Private School (Gold/Credit): 0=Icy Loan (basic damage), 1=Cold Calculation (heal)
    pub const private_school = [2]usize{ 0, 1 };

    // Montessori (Green/Variety): 0=Explore (damage), 1=Discover (heal/support)
    pub const montessori = [2]usize{ 0, 1 };

    // Homeschool (Black/Sacrifice): 0=Self-Study (basic), 1=Dark Library (buff)
    pub const homeschool = [2]usize{ 0, 1 };

    // Waldorf (Blue/Rhythm): 0=Opening Note (basic rhythm), 1=Tempo (buff)
    pub const waldorf = [2]usize{ 0, 1 };

    // Position starter skill indices (same logic - 2 simple skills each)
    // Pitcher: 0=Fastball (basic damage), 7=Quick Toss (spam)
    pub const pitcher = [2]usize{ 0, 7 };

    // Fielder: 0=Catch (basic), 1=Quick Catch (fast)
    pub const fielder = [2]usize{ 0, 1 };

    // Sledder: 0=Ram (basic melee), 1=Slide By (mobility)
    pub const sledder = [2]usize{ 0, 1 };

    // Shoveler: 0=Dig In (basic), 1=Shovel Toss (ranged option)
    pub const shoveler = [2]usize{ 0, 1 };

    // Animator: 0=Build Snowman (summon), 1=Snow Fort (wall)
    pub const animator = [2]usize{ 0, 1 };

    // Thermos: 0=Share Cocoa (heal), 12=Quick Refill (fast heal)
    pub const thermos = [2]usize{ 0, 12 };

    /// Get starter indices for a school
    pub fn forSchool(s: School) [2]usize {
        return switch (s) {
            .public_school => public_school,
            .private_school => private_school,
            .montessori => montessori,
            .homeschool => homeschool,
            .waldorf => waldorf,
        };
    }

    /// Get starter indices for a position
    pub fn forPosition(p: Position) [2]usize {
        return switch (p) {
            .pitcher => pitcher,
            .fielder => fielder,
            .sledder => sledder,
            .shoveler => shoveler,
            .animator => animator,
            .thermos => thermos,
        };
    }
};

// ============================================================================
// FIRST REWARD BUNDLES - Post-tutorial skill selection
// ============================================================================

/// Maximum skills per bundle
pub const FIRST_BUNDLE_SIZE: usize = 8;

/// A bundle of skills offered as the first reward after tutorial
/// Each bundle has 8 skills: 2 from each of the 4 pools
/// (player school, player position, friend school, friend position)
pub const FirstRewardBundle = struct {
    /// Display name for this bundle
    name: [:0]const u8,
    /// Brief description of the bundle's theme
    description: [:0]const u8,
    /// The 8 skills in this bundle (pointers to comptime skills)
    skills: [FIRST_BUNDLE_SIZE]?*const Skill = [_]?*const Skill{null} ** FIRST_BUNDLE_SIZE,
    /// Number of skills actually in the bundle
    skill_count: u8 = 0,
};

/// Generate 3 bundles for the first reward choice
/// Each bundle is themed and draws 2 skills from each of the 4 pools:
/// - Player's school skills
/// - Player's position skills
/// - Friend's school skills
/// - Friend's position skills
pub const FirstRewardGenerator = struct {
    /// Bundle skill indices for each theme
    /// These are indices into each pool's skill list (skipping starter skills)
    /// Theme 0: Aggressive - damage-focused skills
    /// Theme 1: Defensive - survival and support skills
    /// Theme 2: Utility - buffs, debuffs, and control skills
    pub const bundle_themes = [3][:0]const u8{
        "Snowball Fight",
        "Cozy Defense",
        "Winter Tactics",
    };

    pub const bundle_descriptions = [3][:0]const u8{
        "More ways to pelt your enemies",
        "Keep your team warm and safe",
        "Outmaneuver the opposition",
    };

    /// Generate bundles based on party composition
    pub fn generateBundles(
        player_school: School,
        player_position: Position,
        friend_school: School,
        friend_position: Position,
    ) [3]FirstRewardBundle {
        var bundles: [3]FirstRewardBundle = undefined;

        // Get all skill pools
        const ps_skills = player_school.getSkills();
        const pp_skills = player_position.getSkills();
        const fs_skills = friend_school.getSkills();
        const fp_skills = friend_position.getSkills();

        // Get starter indices to skip them
        const ps_starters = StarterSkillIndices.forSchool(player_school);
        const pp_starters = StarterSkillIndices.forPosition(player_position);
        const fs_starters = StarterSkillIndices.forSchool(friend_school);
        const fp_starters = StarterSkillIndices.forPosition(friend_position);

        // Generate each themed bundle
        for (0..3) |theme_idx| {
            bundles[theme_idx] = FirstRewardBundle{
                .name = bundle_themes[theme_idx],
                .description = bundle_descriptions[theme_idx],
            };

            var slot: u8 = 0;

            // Pick 2 skills from each pool, offset by theme to get different skills
            // Skip starter skills and AP skills (is_ap = true)

            // Player school skills (2)
            slot = addSkillsFromPool(&bundles[theme_idx], ps_skills, ps_starters, theme_idx, slot, 2);

            // Player position skills (2)
            slot = addSkillsFromPool(&bundles[theme_idx], pp_skills, pp_starters, theme_idx, slot, 2);

            // Friend school skills (2)
            slot = addSkillsFromPool(&bundles[theme_idx], fs_skills, fs_starters, theme_idx, slot, 2);

            // Friend position skills (2)
            _ = addSkillsFromPool(&bundles[theme_idx], fp_skills, fp_starters, theme_idx, slot, 2);
        }

        return bundles;
    }

    /// Add skills from a pool to a bundle, skipping starters and AP skills
    fn addSkillsFromPool(
        bundle: *FirstRewardBundle,
        skill_pool: []const Skill,
        starters: [2]usize,
        theme_offset: usize,
        start_slot: u8,
        count: u8,
    ) u8 {
        var slot = start_slot;
        var added: u8 = 0;
        var pool_idx: usize = theme_offset * 2; // Offset by theme to get different skills

        while (added < count and pool_idx < skill_pool.len) {
            // Skip starter skills
            if (pool_idx == starters[0] or pool_idx == starters[1]) {
                pool_idx += 1;
                continue;
            }

            // Skip AP skills (they should be captured from bosses)
            if (skill_pool[pool_idx].is_ap) {
                pool_idx += 1;
                continue;
            }

            // Add this skill
            if (slot < FIRST_BUNDLE_SIZE) {
                bundle.skills[slot] = &skill_pool[pool_idx];
                bundle.skill_count = slot + 1;
                slot += 1;
                added += 1;
            }

            pool_idx += 1;
        }

        // If we didn't find enough, wrap around and try again from start
        pool_idx = 0;
        while (added < count and pool_idx < skill_pool.len) {
            if (pool_idx == starters[0] or pool_idx == starters[1]) {
                pool_idx += 1;
                continue;
            }
            if (skill_pool[pool_idx].is_ap) {
                pool_idx += 1;
                continue;
            }

            // Check if we already added this skill
            var already_added = false;
            for (bundle.skills[0..slot]) |maybe_skill| {
                if (maybe_skill) |s| {
                    if (std.mem.eql(u8, s.name, skill_pool[pool_idx].name)) {
                        already_added = true;
                        break;
                    }
                }
            }

            if (!already_added) {
                if (slot < FIRST_BUNDLE_SIZE) {
                    bundle.skills[slot] = &skill_pool[pool_idx];
                    bundle.skill_count = slot + 1;
                    slot += 1;
                    added += 1;
                }
            }

            pool_idx += 1;
        }

        return slot;
    }
};

/// Pool of all skills unlocked during this campaign run
/// Party members' skill bars reference skills by index into this pool
pub const SkillPool = struct {
    /// All unlocked skills
    pool: [MAX_SKILL_POOL_SIZE]?*const Skill = [_]?*const Skill{null} ** MAX_SKILL_POOL_SIZE,

    /// Number of skills in the pool
    count: u16 = 0,

    /// Add BOG SIMPLE starting skills for a character (2 school + 2 position)
    /// Returns the 4 skill indices in the pool for immediate equipping
    pub fn addStarterSkillsForCharacter(self: *SkillPool, s: School, p: Position) [4]u16 {
        var equipped: [4]u16 = [_]u16{ 0, 0, 0, 0 };
        var slot: usize = 0;

        // Add 2 school skills
        const school_indices = StarterSkillIndices.forSchool(s);
        const school_skills = s.getSkills();
        for (school_indices) |idx| {
            if (idx < school_skills.len) {
                const pool_idx = self.addSkillAndGetIndex(&school_skills[idx]);
                if (pool_idx) |pi| {
                    if (slot < 4) {
                        equipped[slot] = pi;
                        slot += 1;
                    }
                }
            }
        }

        // Add 2 position skills
        const pos_indices = StarterSkillIndices.forPosition(p);
        const pos_skills = p.getSkills();
        for (pos_indices) |idx| {
            if (idx < pos_skills.len) {
                const pool_idx = self.addSkillAndGetIndex(&pos_skills[idx]);
                if (pool_idx) |pi| {
                    if (slot < 4) {
                        equipped[slot] = pi;
                        slot += 1;
                    }
                }
            }
        }

        return equipped;
    }

    /// Add a skill and return its pool index (or existing index if duplicate)
    pub fn addSkillAndGetIndex(self: *SkillPool, skill: *const Skill) ?u16 {
        // Check for duplicates first
        for (self.pool[0..self.count], 0..) |maybe_skill, i| {
            if (maybe_skill) |existing| {
                if (std.mem.eql(u8, existing.name, skill.name)) {
                    return @intCast(i); // Already have it, return existing index
                }
            }
        }

        // Add new skill
        if (self.count >= MAX_SKILL_POOL_SIZE) return null;
        self.pool[self.count] = skill;
        const idx = self.count;
        self.count += 1;
        return idx;
    }

    /// Add starting skills based on player's school (legacy - kept for compatibility)
    pub fn addStartingSkills(self: *SkillPool, player_school: School) void {
        // Add 4 skills from player's school
        const school_skills = player_school.getSkills();
        const to_add = @min(school_skills.len, 6); // Add first 6 skills from school
        for (0..to_add) |i| {
            self.pool[self.count] = &school_skills[i];
            self.count += 1;
        }
    }

    /// Add skills from a specific school (for friend's school contribution)
    pub fn addStartingSkillsFromSchool(self: *SkillPool, from_school: School) void {
        const school_skills = from_school.getSkills();
        const to_add = @min(school_skills.len, 3); // Add 3 from friend's school
        for (0..to_add) |i| {
            _ = self.addSkill(&school_skills[i]); // Uses addSkill to avoid duplicates
        }
    }

    /// Apply a first reward bundle (add all 8 skills to the pool)
    pub fn applyFirstRewardBundle(self: *SkillPool, bundle: *const FirstRewardBundle) void {
        for (bundle.skills[0..bundle.skill_count]) |maybe_skill| {
            if (maybe_skill) |skill| {
                _ = self.addSkill(skill);
            }
        }
    }

    /// Add a captured skill
    pub fn addSkill(self: *SkillPool, skill: *const Skill) bool {
        if (self.count >= MAX_SKILL_POOL_SIZE) return false;

        // Check for duplicates
        for (self.pool[0..self.count]) |maybe_skill| {
            if (maybe_skill) |existing| {
                if (std.mem.eql(u8, existing.name, skill.name)) {
                    return false; // Already have it
                }
            }
        }

        self.pool[self.count] = skill;
        self.count += 1;
        return true;
    }

    /// Add multiple skills from a capture choice
    pub fn addFromBundle(self: *SkillPool, bundle: [3]?*const Skill) u8 {
        var added: u8 = 0;
        for (bundle) |maybe_skill| {
            if (maybe_skill) |skill| {
                if (self.addSkill(skill)) added += 1;
            }
        }
        return added;
    }

    /// Get skill by pool index
    pub fn get(self: SkillPool, index: u16) ?*const Skill {
        if (index >= self.count) return null;
        return self.pool[index];
    }

    /// Find index of a skill by name
    pub fn findByName(self: SkillPool, name: []const u8) ?u16 {
        for (self.pool[0..self.count], 0..) |maybe_skill, i| {
            if (maybe_skill) |skill| {
                if (std.mem.eql(u8, skill.name, name)) {
                    return @intCast(i);
                }
            }
        }
        return null;
    }

    /// Check if pool contains any AP skills
    pub fn hasApSkill(self: SkillPool) bool {
        for (self.pool[0..self.count]) |maybe_skill| {
            if (maybe_skill) |skill| {
                if (skill.is_ap) return true;
            }
        }
        return false;
    }

    /// Count AP skills in pool
    pub fn countApSkills(self: SkillPool) u8 {
        var count: u8 = 0;
        for (self.pool[0..self.count]) |maybe_skill| {
            if (maybe_skill) |skill| {
                if (skill.is_ap) count += 1;
            }
        }
        return count;
    }
};

// ============================================================================
// WAR STATE - The multi-faction conflict
// ============================================================================

/// State of the multi-faction war
/// Territory shifts based on encounter outcomes
pub const WarState = struct {
    /// Territory control per faction (0-100, should sum to ~100)
    territory: [4]u8 = [_]u8{ 25, 25, 25, 25 },

    /// Momentum per faction (-10 to +10, affects territory shifts)
    momentum: [4]i8 = [_]i8{ 0, 0, 0, 0 },

    /// Initialize with some variance
    pub fn initRandom(rng: std.Random) WarState {
        var state = WarState{};

        // Add variance to starting territory
        for (&state.territory) |*t| {
            const variance: i8 = rng.intRangeAtMost(i8, -5, 5);
            t.* = @intCast(@max(10, @min(40, @as(i16, t.*) + variance)));
        }

        // Normalize to 100
        var total: u16 = 0;
        for (state.territory) |t| total += t;
        if (total != 100) {
            const diff: i16 = 100 - @as(i16, @intCast(total));
            state.territory[0] = @intCast(@max(10, @as(i16, state.territory[0]) + diff));
        }

        return state;
    }

    /// Apply encounter result to war state
    pub fn applyResult(self: *WarState, winning_faction: Faction, influence: i8) void {
        const idx = @intFromEnum(winning_faction);

        // Update momentum
        self.momentum[idx] = @min(10, @max(-10, self.momentum[idx] + influence));

        // Transfer territory based on influence
        if (influence > 0) {
            // Take from faction with most territory
            var max_idx: usize = 0;
            var max_val: u8 = 0;
            for (self.territory, 0..) |t, i| {
                if (i != idx and t > max_val) {
                    max_val = t;
                    max_idx = i;
                }
            }

            const transfer: u8 = @intCast(@min(max_val - 10, @as(u8, @intCast(@abs(influence)))));
            self.territory[idx] += transfer;
            self.territory[max_idx] -= transfer;
        }
    }

    /// Called each turn - momentum decays toward 0
    pub fn tick(self: *WarState) void {
        for (&self.momentum) |*m| {
            if (m.* > 0) m.* -= 1;
            if (m.* < 0) m.* += 1;
        }
    }

    /// Check if a faction has been eliminated
    pub fn isFactionEliminated(self: WarState, faction: Faction) bool {
        return self.territory[@intFromEnum(faction)] < 5;
    }

    /// Get the faction with most territory
    pub fn getLeader(self: WarState) Faction {
        var max_idx: usize = 0;
        var max_val: u8 = 0;
        for (self.territory, 0..) |t, i| {
            if (t > max_val) {
                max_val = t;
                max_idx = i;
            }
        }
        return @enumFromInt(max_idx);
    }

    /// Get territory percentage for a faction
    pub fn getTerritory(self: WarState, faction: Faction) u8 {
        return self.territory[@intFromEnum(faction)];
    }

    /// Get momentum for a faction
    pub fn getMomentum(self: WarState, faction: Faction) i8 {
        return self.momentum[@intFromEnum(faction)];
    }
};

// ============================================================================
// QUEST PROGRESS - Tracking progress toward campaign goal
// ============================================================================

/// Progress toward the campaign goal
pub const QuestProgress = struct {
    goal_type: GoalType,

    // Find Brother goal state
    intel_gathered: u8 = 0,
    search_progress: u8 = 0, // 0-100, brother found when roll succeeds
    brother_found: bool = false,

    // Territorial Control goal state
    nodes_required: u8 = 0,
    nodes_captured: u8 = 0,

    // Survival goal state
    turns_required: u32 = 0,
    turns_survived: u32 = 0,

    // Skill Collection goal state
    skills_required: u8 = 0,
    skills_captured: u8 = 0,

    /// Create progress tracker for a goal type
    pub fn init(goal_type: GoalType) QuestProgress {
        var progress = QuestProgress{ .goal_type = goal_type };

        // Set requirements based on goal type
        switch (goal_type) {
            .find_brother => {}, // Progress is probabilistic
            .territorial_control => progress.nodes_required = 5,
            .survival => progress.turns_required = 20,
            .skill_collection => progress.skills_required = 10,
        }

        return progress;
    }

    /// Check if goal is complete
    pub fn isComplete(self: QuestProgress) bool {
        return switch (self.goal_type) {
            .find_brother => self.brother_found,
            .territorial_control => self.nodes_captured >= self.nodes_required,
            .survival => self.turns_survived >= self.turns_required,
            .skill_collection => self.skills_captured >= self.skills_required,
        };
    }

    /// Get progress as percentage (0-100)
    pub fn getProgressPercent(self: QuestProgress) u8 {
        return switch (self.goal_type) {
            .find_brother => self.search_progress,
            .territorial_control => if (self.nodes_required > 0) (self.nodes_captured * 100) / self.nodes_required else 0,
            .survival => if (self.turns_required > 0) @intCast((self.turns_survived * 100) / self.turns_required) else 0,
            .skill_collection => if (self.skills_required > 0) (self.skills_captured * 100) / self.skills_required else 0,
        };
    }

    /// Process completing an intel node (for find_brother goal)
    /// Returns true if brother was found
    pub fn processIntel(self: *QuestProgress, rng: std.Random) bool {
        if (self.goal_type != .find_brother) return false;

        self.intel_gathered += 1;

        // Each intel increases progress by 10-20
        const gain = rng.intRangeAtMost(u8, 10, 20);
        self.search_progress = @min(100, self.search_progress + gain);

        // Roll to find brother - chance equals search_progress
        const roll = rng.intRangeAtMost(u8, 1, 100);
        if (roll <= self.search_progress) {
            self.brother_found = true;
            return true;
        }

        return false;
    }

    /// Process winning a strategic node
    pub fn processStrategicWin(self: *QuestProgress) void {
        if (self.goal_type == .territorial_control) {
            self.nodes_captured += 1;
        }
    }

    /// Process capturing skills
    pub fn processSkillCapture(self: *QuestProgress, count: u8) void {
        if (self.goal_type == .skill_collection) {
            self.skills_captured += count;
        }
    }

    /// Process a turn passing
    pub fn processTurn(self: *QuestProgress) void {
        if (self.goal_type == .survival) {
            self.turns_survived += 1;
        }
    }
};

// ============================================================================
// OVERWORLD MAP - The suburban warzone
// ============================================================================

/// The overworld map containing encounter nodes
pub const OverworldMap = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayListUnmanaged(EncounterNode),
    next_node_id: u16 = 0,
    seed: u64,

    pub fn init(allocator: std.mem.Allocator, seed: u64) OverworldMap {
        return OverworldMap{
            .allocator = allocator,
            .nodes = .{},
            .seed = seed,
        };
    }

    pub fn deinit(self: *OverworldMap) void {
        self.nodes.deinit(self.allocator);
    }

    /// Generate initial nodes
    pub fn generateInitialNodes(self: *OverworldMap, count: usize) !void {
        var prng = std.Random.DefaultPrng.init(self.seed);
        const rng = prng.random();

        for (0..count) |_| {
            const node = EncounterNode.random(rng, self.next_node_id);
            self.next_node_id += 1;
            try self.nodes.append(self.allocator, node);
        }
    }

    /// Tick all nodes and remove expired ones, generate new ones if needed
    pub fn tick(self: *OverworldMap, turn: u32) void {
        // Tick and remove expired
        var i: usize = 0;
        while (i < self.nodes.items.len) {
            self.nodes.items[i].tick();
            if (self.nodes.items[i].isExpired()) {
                _ = self.nodes.swapRemove(i);
                continue;
            }
            i += 1;
        }

        // Generate new nodes if running low
        if (self.nodes.items.len < 5) {
            var prng = std.Random.DefaultPrng.init(self.seed +% turn);
            const rng = prng.random();

            const to_generate = 8 - self.nodes.items.len;
            for (0..to_generate) |_| {
                const node = EncounterNode.random(rng, self.next_node_id);
                self.next_node_id += 1;
                self.nodes.append(self.allocator, node) catch break;
            }
        }
    }

    /// Remove a node by ID (after completing it)
    pub fn removeNode(self: *OverworldMap, node_id: u16) void {
        for (self.nodes.items, 0..) |node, i| {
            if (node.id == node_id) {
                _ = self.nodes.swapRemove(i);
                return;
            }
        }
    }

    /// Get node by ID
    pub fn getNode(self: OverworldMap, node_id: u16) ?EncounterNode {
        for (self.nodes.items) |node| {
            if (node.id == node_id) return node;
        }
        return null;
    }

    /// Get all available nodes
    pub fn getNodes(self: *OverworldMap) []EncounterNode {
        return self.nodes.items;
    }
};

// ============================================================================
// CAMPAIGN STATUS - Current state of the campaign
// ============================================================================

pub const CampaignStatus = enum {
    /// Campaign in progress
    in_progress,

    /// Campaign won (goal achieved)
    victory,

    /// Campaign lost (party wiped)
    defeat_party_wiped,

    /// Campaign lost (faction eliminated from war)
    defeat_faction_lost,

    pub fn isTerminal(self: CampaignStatus) bool {
        return self != .in_progress;
    }

    pub fn isVictory(self: CampaignStatus) bool {
        return self == .victory;
    }

    pub fn isDefeat(self: CampaignStatus) bool {
        return self == .defeat_party_wiped or self == .defeat_faction_lost;
    }
};

// ============================================================================
// CAMPAIGN STATE - The root state for a campaign run
// ============================================================================

/// Complete state for a campaign run
pub const CampaignState = struct {
    allocator: std.mem.Allocator,

    // Core subsystems
    party: PartyState,
    skill_pool: SkillPool,
    overworld: OverworldMap,
    war: WarState,
    quest: QuestProgress,

    /// Polyomino-based tessellating map (new map system)
    poly_map: PolyominoMap,

    // Campaign metadata
    goal_type: GoalType,
    seed: u64,
    turn: u32 = 0,

    // Statistics
    encounters_won: u32 = 0,
    encounters_lost: u32 = 0,
    skills_captured: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, seed: u64, goal_type: GoalType) !CampaignState {
        var prng = std.Random.DefaultPrng.init(seed);
        const rng = prng.random();

        var state = CampaignState{
            .allocator = allocator,
            .party = PartyState{},
            .skill_pool = SkillPool{},
            .overworld = OverworldMap.init(allocator, seed),
            .war = WarState.initRandom(rng),
            .quest = QuestProgress.init(goal_type),
            .poly_map = PolyominoMap.init(allocator, seed),
            .goal_type = goal_type,
            .seed = seed,
        };

        // Generate initial overworld nodes (legacy system)
        try state.overworld.generateInitialNodes(8);

        // Generate polyomino starting area (new system)
        try state.poly_map.generateStartingArea(.blue);

        return state;
    }

    pub fn deinit(self: *CampaignState) void {
        self.overworld.deinit();
        self.poly_map.deinit();
    }

    /// Set up the player and best friend
    pub fn setupParty(
        self: *CampaignState,
        player_name: [:0]const u8,
        player_school: School,
        friend_name: [:0]const u8,
        friend_school: School,
    ) void {
        self.party.addPlayer(player_name, player_school);
        self.party.addBestFriend(friend_name, friend_school);
        self.skill_pool.addStartingSkills(player_school);
    }

    /// Set up the player and best friend with positions
    pub fn setupPartyWithPositions(
        self: *CampaignState,
        player_name: [:0]const u8,
        player_school: School,
        player_position: Position,
        friend_name: [:0]const u8,
        friend_school: School,
        friend_position: Position,
    ) void {
        self.party.addPlayerWithPosition(player_name, player_school, player_position);
        self.party.addBestFriendWithPosition(friend_name, friend_school, friend_position);
        self.skill_pool.addStartingSkills(player_school);
        // Also add some skills from friend's school
        self.skill_pool.addStartingSkillsFromSchool(friend_school);
    }

    /// Set up the player and best friend with auto-equipped BOG SIMPLE starter skills
    /// This is the new simplified flow: 4 skills each (2 school + 2 position)
    pub fn setupPartyWithStarterSkills(
        self: *CampaignState,
        player_name: [:0]const u8,
        player_school: School,
        player_position: Position,
        friend_name: [:0]const u8,
        friend_school: School,
        friend_position: Position,
    ) void {
        // Add player with auto-equipped skills
        self.party.addPlayerWithStarterSkills(player_name, player_school, player_position, &self.skill_pool);
        // Add friend with auto-equipped skills
        self.party.addBestFriendWithStarterSkills(friend_name, friend_school, friend_position, &self.skill_pool);
    }

    /// Advance the campaign by one turn
    pub fn advanceTurn(self: *CampaignState) void {
        self.turn += 1;
        self.overworld.tick(self.turn);
        self.war.tick();
        self.quest.processTurn();
        self.party.restoreBetweenEncounters();
    }

    /// Get current campaign status
    pub fn getStatus(self: CampaignState) CampaignStatus {
        if (self.quest.isComplete()) return .victory;
        if (self.party.isWiped()) return .defeat_party_wiped;
        if (self.war.isFactionEliminated(self.party.faction)) return .defeat_faction_lost;
        return .in_progress;
    }

    /// Process the result of completing an encounter
    pub fn processEncounterResult(self: *CampaignState, node: EncounterNode, victory: bool, rng: std.Random) void {
        if (victory) {
            self.encounters_won += 1;

            // Apply faction influence
            self.war.applyResult(self.party.faction, node.faction_influence);

            // Process quest-specific effects
            if (node.offers_quest_progress) {
                _ = self.quest.processIntel(rng);
            }
            if (node.encounter_type == .strategic) {
                self.quest.processStrategicWin();
            }
        } else {
            self.encounters_lost += 1;
        }

        // Remove the completed node
        self.overworld.removeNode(node.id);
    }

    /// Apply a skill capture choice to the campaign
    pub fn applySkillCapture(self: *CampaignState, choice: SkillCaptureChoice, chose_ap: bool) void {
        if (chose_ap) {
            if (choice.ap_skill) |skill| {
                if (self.skill_pool.addSkill(skill)) {
                    self.skills_captured += 1;
                    self.quest.processSkillCapture(1);
                }
            }
        } else {
            const added = self.skill_pool.addFromBundle(choice.skill_bundle);
            self.skills_captured += added;
            self.quest.processSkillCapture(added);
        }
    }

    /// Process the result of completing a polyomino block encounter
    /// Returns the campaign status after processing (may be game over on loss)
    pub fn processPolyBlockResult(self: *CampaignState, block_id: u32, victory: bool, rng: std.Random) !CampaignStatus {
        // Advance the round counter for loss penalty scaling
        self.poly_map.current_round = self.turn;

        if (self.poly_map.getBlock(block_id)) |block| {
            if (block.encounter) |node| {
                if (victory) {
                    self.encounters_won += 1;

                    // Apply faction influence
                    self.war.applyResult(self.party.faction, node.faction_influence);

                    // Process quest-specific effects
                    if (node.offers_quest_progress) {
                        _ = self.quest.processIntel(rng);
                    }
                    if (node.encounter_type == .strategic) {
                        self.quest.processStrategicWin();
                    }

                    // Conquer the block
                    try self.poly_map.conquerBlock(block_id, self.party.faction);

                    // Expand frontier to generate new adjacent chunks
                    try self.poly_map.expandFrontier();
                } else {
                    self.encounters_lost += 1;

                    // LOSS PENALTY: Lose frontier territory based on current round
                    // Early game (rounds 1-3): lose 1 block
                    // Mid game (rounds 4-6): lose 2 blocks
                    // Late game: scales up further
                    const penalty = self.poly_map.getLossPenalty();
                    const lost_result = try self.poly_map.loseTerritory(penalty);

                    if (lost_result == null) {
                        // Lost the starting block - GAME OVER
                        return .defeat_faction_lost;
                    }

                    // Check if party is also wiped
                    if (self.party.isWiped()) {
                        return .defeat_party_wiped;
                    }
                }
            }
        }

        return self.getStatus();
    }

    /// Get encounter from a polyomino block
    pub fn getPolyBlockEncounter(self: *CampaignState, block_id: u32) ?EncounterNode {
        if (self.poly_map.getBlock(block_id)) |block| {
            return block.encounter;
        }
        return null;
    }
};

// ============================================================================
// ENCOUNTER CONFIG - Bridge to combat system
// ============================================================================

/// Configuration generated from an EncounterNode to feed into SimulationFactory
pub const EncounterConfig = struct {
    // Team composition
    player_team_size: usize,
    enemy_team_size: usize,

    // Enemy configuration
    enemy_schools: [5]School,
    enemy_positions: [6]Position,

    // Difficulty scaling
    enemy_warmth_multiplier: f32,
    enemy_damage_multiplier: f32,

    // Boss configuration
    has_boss: bool,
    boss_school: ?School,

    // Rewards configuration
    skill_capture_tier: SkillCaptureTier,

    /// Generate config from a node and party state
    pub fn fromNode(node: EncounterNode, party: PartyState) EncounterConfig {
        const cr = node.challenge_rating;
        const party_size = party.livingCount();

        return EncounterConfig{
            .player_team_size = party_size,
            .enemy_team_size = @min(8, party_size + (cr / 3)),
            .enemy_schools = [_]School{.public_school} ** 5,
            .enemy_positions = [_]Position{.fielder} ** 6,
            .enemy_warmth_multiplier = 0.8 + (@as(f32, @floatFromInt(cr)) * 0.1),
            .enemy_damage_multiplier = 0.8 + (@as(f32, @floatFromInt(cr)) * 0.05),
            .has_boss = node.encounter_type == .boss_capture,
            .boss_school = if (node.encounter_type == .boss_capture) .public_school else null,
            .skill_capture_tier = node.skill_capture_tier,
        };
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "campaign state initialization" {
    const allocator = std.testing.allocator;

    var campaign = try CampaignState.init(allocator, 12345, .find_brother);
    defer campaign.deinit();

    // Set up party so isWiped() returns false
    campaign.setupParty("Hero", .public_school, "Buddy", .waldorf);

    try std.testing.expect(campaign.turn == 0);
    try std.testing.expect(campaign.getStatus() == .in_progress);
}

test "party management" {
    var party = PartyState{};

    party.addPlayer("Hero", .public_school);
    party.addBestFriend("Buddy", .waldorf);

    try std.testing.expect(party.livingCount() == 2);
    try std.testing.expect(party.totalCount() == 2);
    try std.testing.expect(!party.isWiped());

    // Kill everyone
    party.members[0].?.is_alive = false;
    party.members[1].?.is_alive = false;

    try std.testing.expect(party.isWiped());
}

test "skill pool management" {
    var pool = SkillPool{};

    pool.addStartingSkills(.public_school);
    try std.testing.expect(pool.count >= 4);

    // Try adding duplicate (first school skill should already be in pool)
    const public_skills = School.public_school.getSkills();
    const added = pool.addSkill(&public_skills[0]);
    try std.testing.expect(!added); // Should fail - already have it
}

test "quest progress - find brother" {
    var prng = std.Random.DefaultPrng.init(99999);
    const rng = prng.random();

    var quest = QuestProgress.init(.find_brother);

    // Gather intel multiple times
    for (0..20) |_| {
        if (quest.processIntel(rng)) break;
    }

    // Progress should have increased
    try std.testing.expect(quest.getProgressPercent() > 0);
}

test "war state" {
    var prng = std.Random.DefaultPrng.init(42);
    const rng = prng.random();

    var war = WarState.initRandom(rng);

    // Total territory should be ~100
    var total: u16 = 0;
    for (war.territory) |t| total += t;
    try std.testing.expect(total >= 95 and total <= 105);

    // Apply encounter result
    war.applyResult(.blue, 5);
    try std.testing.expect(war.momentum[0] == 5);
}

test "encounter node generation" {
    var prng = std.Random.DefaultPrng.init(123);
    const rng = prng.random();

    const node = EncounterNode.random(rng, 0);

    try std.testing.expect(node.challenge_rating >= 1);
    try std.testing.expect(node.challenge_rating <= 10);
    try std.testing.expect(node.id == 0);
}

test "skill capture choice generation" {
    var prng = std.Random.DefaultPrng.init(456);
    const rng = prng.random();

    const choice = SkillCaptureChoice.generate(.elite, rng, .public_school);

    try std.testing.expect(choice.hasApOption());
    try std.testing.expect(choice.hasBundleOption());
    try std.testing.expect(choice.bundle_size == 3);
}
