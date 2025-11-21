const std = @import("std");
const rl = @import("raylib");
const school = @import("school.zig");
const position = @import("position.zig");
const skills = @import("skills.zig");
const equipment = @import("equipment.zig");

const print = std.debug.print;

pub const School = school.School;
pub const Position = position.Position;
pub const Skill = skills.Skill;
pub const Equipment = equipment.Equipment;

// Character configuration constants
pub const MAX_SKILLS: usize = 8;
pub const MAX_ACTIVE_CONDITIONS: usize = 10;
pub const MAX_RECENT_SKILLS: usize = 5;
pub const MAX_GRIT_STACKS: u8 = 5;
pub const MAX_RHYTHM_CHARGE: u8 = 10;

pub const Character = struct {
    position: rl.Vector3,
    radius: f32,
    color: rl.Color,
    name: [:0]const u8,
    warmth: f32,
    max_warmth: f32,
    is_enemy: bool,

    // Skill system components
    school: School,
    player_position: Position,

    // Equipment system
    main_hand: ?*const equipment.Equipment = null,
    off_hand: ?*const equipment.Equipment = null,
    shield: ?*const equipment.Equipment = null,

    // Universal primary resource
    energy: u8,
    max_energy: u8,
    energy_accumulator: f32 = 0.0, // Tracks fractional energy for smooth regen

    // School-specific secondary mechanics
    // Private School: Passive regen (no extra state needed)

    // Public School: Grit stacks
    grit_stacks: u8 = 0, // Every 5 stacks = free skill
    max_grit_stacks: u8 = MAX_GRIT_STACKS,

    // Homeschool: Warmth-to-Energy conversion (cooldown tracker)
    sacrifice_cooldown: f32 = 0.0, // seconds until can sacrifice again

    // Waldorf: Rhythm timing
    rhythm_charge: u8 = 0, // 0-10, builds with skill casts
    rhythm_perfect_window: f32 = 0.0, // timing window tracker
    max_rhythm_charge: u8 = MAX_RHYTHM_CHARGE,

    // Montessori: Skill variety bonus
    last_skills_used: [MAX_RECENT_SKILLS]?u8 = [_]?u8{null} ** MAX_RECENT_SKILLS, // tracks last 5 skills
    variety_bonus_damage: f32 = 0.0, // 0.0 to 0.5 (0% to 50% bonus)

    skill_bar: [MAX_SKILLS]?*const Skill,
    selected_skill: u8 = 0,

    // Skill cooldowns and activation tracking
    skill_cooldowns: [MAX_SKILLS]f32 = [_]f32{0.0} ** MAX_SKILLS, // time remaining in seconds
    is_casting: bool = false,
    casting_skill_index: u8 = 0,
    cast_time_remaining: f32 = 0.0, // seconds remaining on current cast
    cast_target_index: ?usize = null, // Target entity index for cast completion

    // Active chills (debuffs) on this character
    active_chills: [MAX_ACTIVE_CONDITIONS]?skills.ActiveChill = [_]?skills.ActiveChill{null} ** MAX_ACTIVE_CONDITIONS,
    active_chill_count: u8 = 0,

    // Active cozies (buffs) on this character
    active_cozies: [MAX_ACTIVE_CONDITIONS]?skills.ActiveCozy = [_]?skills.ActiveCozy{null} ** MAX_ACTIVE_CONDITIONS,
    active_cozy_count: u8 = 0,

    // Death state
    is_dead: bool = false,

    pub fn isAlive(self: Character) bool {
        return !self.is_dead and self.warmth > 0;
    }

    pub fn takeDamage(self: *Character, damage: f32) void {
        self.warmth = @max(0, self.warmth - damage);
        if (self.warmth <= 0) {
            self.is_dead = true;
            // Death interrupts casting
            if (self.is_casting) {
                self.cancelCasting();
            }
        }
    }

    /// Interrupt current cast (from interrupt skills, dazed condition, etc)
    pub fn interrupt(self: *Character) void {
        if (self.is_casting) {
            print("{s}'s cast was interrupted!\n", .{self.name});
            self.cancelCasting();
        }
    }

    pub fn distanceTo(self: Character, other: Character) f32 {
        const dx = self.position.x - other.position.x;
        const dy = self.position.y - other.position.y;
        const dz = self.position.z - other.position.z;
        return @sqrt(dx * dx + dy * dy + dz * dz);
    }

    /// Check if this character overlaps with another (for collision detection)
    pub fn overlaps(self: Character, other: Character) bool {
        const distance = self.distanceTo(other);
        const min_distance = self.radius + other.radius;
        return distance < min_distance;
    }

    /// Push this character away from another to resolve overlap
    pub fn resolveCollision(self: *Character, other: Character) void {
        const dx = self.position.x - other.position.x;
        const dz = self.position.z - other.position.z;
        const distance = @sqrt(dx * dx + dz * dz);

        if (distance < 0.1) return; // Avoid division by zero

        const min_distance = self.radius + other.radius;
        if (distance < min_distance) {
            // Push away to maintain minimum distance
            const overlap = min_distance - distance;
            const push_x = (dx / distance) * overlap;
            const push_z = (dz / distance) * overlap;

            self.position.x += push_x;
            self.position.z += push_z;
        }
    }

    pub fn updateEnergy(self: *Character, delta_time: f32) void {
        // Passive energy regeneration based on school
        const regen = self.school.getEnergyRegen() * delta_time;

        // Accumulate fractional energy
        self.energy_accumulator += regen;

        // Convert whole points to energy
        if (self.energy_accumulator >= 1.0) {
            const energy_to_add = @as(u8, @intFromFloat(self.energy_accumulator));
            self.energy = @min(self.max_energy, self.energy + energy_to_add);
            self.energy_accumulator -= @as(f32, @floatFromInt(energy_to_add));
        }

        // Update school-specific mechanics
        switch (self.school) {
            .private_school => {
                // Private school has steady regen (already handled above)
            },
            .public_school => {
                // Grit stacks decay over time if not in combat
                // TODO: implement combat state tracking
            },
            .montessori => {
                // Update variety bonus based on recent skill usage
                // TODO: implement when skills are used
            },
            .homeschool => {
                // Reduce sacrifice cooldown
                if (self.sacrifice_cooldown > 0) {
                    self.sacrifice_cooldown = @max(0, self.sacrifice_cooldown - delta_time);
                }
            },
            .waldorf => {
                // Rhythm charge decays slowly
                if (self.rhythm_perfect_window > 0) {
                    self.rhythm_perfect_window = @max(0, self.rhythm_perfect_window - delta_time);
                }
            },
        }
    }

    pub fn updateCooldowns(self: *Character, delta_time: f32) void {
        // Update skill cooldowns
        for (&self.skill_cooldowns) |*cooldown| {
            if (cooldown.* > 0) {
                cooldown.* = @max(0, cooldown.* - delta_time);
            }
        }

        // Update casting state
        if (self.is_casting) {
            self.cast_time_remaining = @max(0, self.cast_time_remaining - delta_time);
            if (self.cast_time_remaining <= 0) {
                self.is_casting = false;
                // Cast is complete - will be executed by game_state.finishCasts()
            }
        }
    }

    pub fn updateConditions(self: *Character, delta_time_ms: u32) void {
        // Update active chills (debuffs), removing expired ones
        var i: usize = 0;
        while (i < self.active_chill_count) {
            if (self.active_chills[i]) |*chill| {
                if (chill.time_remaining_ms <= delta_time_ms) {
                    // Chill expired, remove it
                    self.active_chills[i] = null;
                    // Compact the array
                    var j = i;
                    while (j < self.active_chill_count - 1) : (j += 1) {
                        self.active_chills[j] = self.active_chills[j + 1];
                    }
                    self.active_chills[self.active_chill_count - 1] = null;
                    self.active_chill_count -= 1;
                    // Don't increment i since we shifted
                } else {
                    chill.time_remaining_ms -= delta_time_ms;
                    i += 1;
                }
            } else {
                i += 1;
            }
        }

        // Update active cozies (buffs), removing expired ones
        i = 0;
        while (i < self.active_cozy_count) {
            if (self.active_cozies[i]) |*cozy| {
                if (cozy.time_remaining_ms <= delta_time_ms) {
                    // Cozy expired, remove it
                    self.active_cozies[i] = null;
                    // Compact the array
                    var j = i;
                    while (j < self.active_cozy_count - 1) : (j += 1) {
                        self.active_cozies[j] = self.active_cozies[j + 1];
                    }
                    self.active_cozies[self.active_cozy_count - 1] = null;
                    self.active_cozy_count -= 1;
                    // Don't increment i since we shifted
                } else {
                    cozy.time_remaining_ms -= delta_time_ms;
                    i += 1;
                }
            } else {
                i += 1;
            }
        }
    }

    pub fn hasChill(self: Character, chill: skills.Chill) bool {
        for (self.active_chills[0..self.active_chill_count]) |maybe_active| {
            if (maybe_active) |active| {
                if (active.chill == chill) {
                    return true;
                }
            }
        }
        return false;
    }

    pub fn hasCozy(self: Character, cozy: skills.Cozy) bool {
        for (self.active_cozies[0..self.active_cozy_count]) |maybe_active| {
            if (maybe_active) |active| {
                if (active.cozy == cozy) {
                    return true;
                }
            }
        }
        return false;
    }

    pub fn addChill(self: *Character, effect: skills.ChillEffect, source_id: ?u32) void {
        // Check if chill already exists (stack or refresh)
        for (self.active_chills[0..self.active_chill_count]) |*maybe_active| {
            if (maybe_active.*) |*active| {
                if (active.chill == effect.chill) {
                    // Refresh duration and stack intensity
                    active.time_remaining_ms = @max(active.time_remaining_ms, effect.duration_ms);
                    active.stack_intensity = @min(255, active.stack_intensity + effect.stack_intensity);
                    return;
                }
            }
        }

        // Add new chill if we have space
        if (self.active_chill_count < self.active_chills.len) {
            self.active_chills[self.active_chill_count] = .{
                .chill = effect.chill,
                .time_remaining_ms = effect.duration_ms,
                .stack_intensity = effect.stack_intensity,
                .source_character_id = source_id,
            };
            self.active_chill_count += 1;
        }
        // Silently ignore if array is full - this is a game, not critical
    }

    pub fn addCozy(self: *Character, effect: skills.CozyEffect, source_id: ?u32) void {
        // Check if cozy already exists (stack or refresh)
        for (self.active_cozies[0..self.active_cozy_count]) |*maybe_active| {
            if (maybe_active.*) |*active| {
                if (active.cozy == effect.cozy) {
                    // Refresh duration and stack intensity
                    active.time_remaining_ms = @max(active.time_remaining_ms, effect.duration_ms);
                    active.stack_intensity = @min(255, active.stack_intensity + effect.stack_intensity);
                    return;
                }
            }
        }

        // Add new cozy if we have space
        if (self.active_cozy_count < self.active_cozies.len) {
            self.active_cozies[self.active_cozy_count] = .{
                .cozy = effect.cozy,
                .time_remaining_ms = effect.duration_ms,
                .stack_intensity = effect.stack_intensity,
                .source_character_id = source_id,
            };
            self.active_cozy_count += 1;
        }
        // Silently ignore if array is full - this is a game, not critical
    }

    pub fn canUseSkill(self: Character, skill_index: u8) bool {
        if (skill_index >= MAX_SKILLS) return false;
        if (self.is_casting) return false;
        if (self.skill_cooldowns[skill_index] > 0) return false;

        const skill = self.skill_bar[skill_index] orelse return false;
        if (self.energy < skill.energy_cost) return false;

        return true;
    }

    pub fn startCasting(self: *Character, skill_index: u8) void {
        const skill = self.skill_bar[skill_index] orelse return;

        self.is_casting = true;
        self.casting_skill_index = skill_index;
        self.cast_time_remaining = @as(f32, @floatFromInt(skill.activation_time_ms)) / 1000.0;

        // Consume energy immediately
        self.energy -= skill.energy_cost;
    }

    pub fn cancelCasting(self: *Character) void {
        if (self.is_casting) {
            // Return partial energy on cancel?
            const skill = self.skill_bar[self.casting_skill_index] orelse return;
            const refund = skill.energy_cost / 2;
            self.energy = @min(self.max_energy, self.energy + refund);

            self.is_casting = false;
            self.cast_time_remaining = 0;
        }
    }
};
