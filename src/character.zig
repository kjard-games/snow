const std = @import("std");
const rl = @import("raylib");
const school = @import("school.zig");
const position = @import("position.zig");
const skills = @import("skills.zig");
const equipment = @import("equipment.zig");
const entity = @import("entity.zig");

const print = std.debug.print;

pub const School = school.School;
pub const Position = position.Position;
pub const Skill = skills.Skill;
pub const Equipment = equipment.Equipment;
pub const EntityId = entity.EntityId;

// Character configuration constants
pub const MAX_SKILLS: usize = 8;
pub const MAX_ACTIVE_CONDITIONS: usize = 10;
pub const MAX_RECENT_SKILLS: usize = 5;
pub const MAX_GRIT_STACKS: u8 = 5;
pub const MAX_RHYTHM_CHARGE: u8 = 10;

// Cast state for GW1-accurate skill timing
pub const CastState = enum {
    idle, // Not casting or in aftercast
    activating, // Currently casting (activation phase)
    aftercast, // Skill fired, but locked in aftercast animation
};

// Compile-time safety: ensure MAX_SKILLS fits in u8 for skill indexing
comptime {
    if (MAX_SKILLS > 255) {
        @compileError("MAX_SKILLS must fit in u8 for skill bar indexing");
    }
}

pub const Character = struct {
    id: EntityId, // Unique identifier for this entity (stable across ticks)
    position: rl.Vector3, // Current tick position (authoritative)
    previous_position: rl.Vector3 = .{ .x = 0, .y = 0, .z = 0 }, // Previous tick position (for interpolation)
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

    // Skill cooldowns and activation tracking (GW1-accurate)
    skill_cooldowns: [MAX_SKILLS]f32 = [_]f32{0.0} ** MAX_SKILLS, // time remaining in seconds

    // Cast state tracking
    cast_state: CastState = .idle,
    casting_skill_index: u8 = 0,
    cast_time_remaining: f32 = 0.0, // seconds remaining on current cast phase
    skill_executed: bool = false, // Has skill effect/projectile been fired?
    cast_target_id: ?EntityId = null, // Target entity ID for cast completion

    // Aftercast tracking
    aftercast_time_remaining: f32 = 0.0, // seconds remaining in aftercast

    // Auto-attack state (Guild Wars style)
    is_auto_attacking: bool = false, // Whether auto-attack loop is active
    auto_attack_timer: f32 = 0.0, // Time until next auto-attack
    auto_attack_target_id: ?EntityId = null, // Current auto-attack target

    // Skill queue (GW1 style: run into range and cast)
    queued_skill_index: ?u8 = null, // Which skill to cast when in range
    queued_skill_target_id: ?EntityId = null, // Target for queued skill
    is_approaching_for_skill: bool = false, // Moving toward target to cast

    // Active chills (debuffs) on this character
    active_chills: [MAX_ACTIVE_CONDITIONS]?skills.ActiveChill = [_]?skills.ActiveChill{null} ** MAX_ACTIVE_CONDITIONS,
    active_chill_count: u8 = 0,

    // Active cozies (buffs) on this character
    active_cozies: [MAX_ACTIVE_CONDITIONS]?skills.ActiveCozy = [_]?skills.ActiveCozy{null} ** MAX_ACTIVE_CONDITIONS,
    active_cozy_count: u8 = 0,

    // Death state
    is_dead: bool = false,

    // Warmth regeneration/degeneration system (GW1-style pips)
    warmth_regen_pips: i8 = 0, // -10 to +10 pips (like GW1 health regen/degen)
    warmth_pip_accumulator: f32 = 0.0, // Tracks fractional warmth for pip ticking

    // TODO: Natural warmth regeneration (GW1 out-of-combat regen)
    // Tracks time since last warmth loss for natural regen scaling
    // time_since_last_warmth_loss: f32 = 0.0,
    // time_safe_for_natural_regen: f32 = 0.0,

    // TODO: Combat tracking for natural regen (future)
    // last_attacked_time: f32 = 0.0,
    // last_damaged_time: f32 = 0.0,
    // last_offensive_skill_time: f32 = 0.0,
    // last_targeted_by_offensive_skill_time: f32 = 0.0,

    pub fn isAlive(self: Character) bool {
        return !self.is_dead and self.warmth > 0;
    }

    /// Check if character is freezing (below 25% warmth)
    /// Causes movement speed penalty and slower skill activation
    pub fn isFreezing(self: Character) bool {
        return (self.warmth / self.max_warmth) < 0.25;
    }

    /// Get movement speed multiplier based on warmth
    pub fn getMovementSpeedMultiplier(self: Character) f32 {
        if (self.isFreezing()) {
            return 0.75; // -25% movement speed when freezing
        }

        // TODO: Apply slippery chill slow
        // TODO: Apply sure_footed cozy speed boost

        return 1.0;
    }

    /// Get interpolated position for smooth rendering between ticks
    pub fn getInterpolatedPosition(self: Character, alpha: f32) rl.Vector3 {
        // Lerp between previous and current position
        // alpha = 0.0 → previous position (tick just happened)
        // alpha = 1.0 → current position (about to tick)
        const result = rl.Vector3{
            .x = self.previous_position.x + (self.position.x - self.previous_position.x) * alpha,
            .y = self.previous_position.y + (self.position.y - self.previous_position.y) * alpha,
            .z = self.previous_position.z + (self.position.z - self.previous_position.z) * alpha,
        };

        return result;
    }

    pub fn takeDamage(self: *Character, damage: f32) void {
        // Clamp warmth to 0 minimum (avoid negative health)
        if (damage >= self.warmth) {
            self.warmth = 0.0;
        } else {
            self.warmth -= damage;
        }

        if (self.warmth <= 0) {
            self.is_dead = true;
            // Death interrupts casting
            if (self.cast_state != .idle) {
                self.cancelCasting();
            }
        }
    }

    /// Interrupt current cast (from interrupt skills, dazed condition, etc)
    pub fn interrupt(self: *Character) void {
        if (self.cast_state == .activating) {
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

    /// Update warmth regeneration/degeneration (GW1-style pips)
    /// Call this every tick (50ms) for accurate pip timing
    pub fn updateWarmth(self: *Character, delta_time: f32) void {
        // Calculate warmth change per second from pips
        // In GW1: 1 pip of regen/degen = 2 health per second
        // We'll use the same ratio: 1 pip = 2 warmth per second
        const warmth_per_second = @as(f32, @floatFromInt(self.warmth_regen_pips)) * 2.0;
        const warmth_delta = warmth_per_second * delta_time;

        // Accumulate fractional warmth
        self.warmth_pip_accumulator += warmth_delta;

        // Apply whole points of warmth
        if (@abs(self.warmth_pip_accumulator) >= 1.0) {
            const warmth_to_apply = self.warmth_pip_accumulator;
            self.warmth = @max(0.0, @min(self.max_warmth, self.warmth + warmth_to_apply));
            self.warmth_pip_accumulator -= warmth_to_apply;

            // Check for death
            if (self.warmth <= 0) {
                self.is_dead = true;
                if (self.cast_state != .idle) {
                    self.cancelCasting();
                }
            }
        }
    }

    /// Recalculate warmth regen/degen pips from active conditions
    /// Call this whenever conditions change (add/remove/expire)
    pub fn recalculateWarmthPips(self: *Character) void {
        var total_pips: i16 = 0; // Use i16 to detect overflow before clamping

        // Add regeneration from cozies
        for (self.active_cozies[0..self.active_cozy_count]) |maybe_cozy| {
            if (maybe_cozy) |cozy| {
                const pips = switch (cozy.cozy) {
                    .hot_cocoa => @as(i16, 2) * @as(i16, cozy.stack_intensity), // +2 per stack
                    .fire_inside => @as(i16, 1) * @as(i16, cozy.stack_intensity), // +1 per stack
                    else => 0,
                };
                total_pips += pips;
            }
        }

        // Add degeneration from chills
        for (self.active_chills[0..self.active_chill_count]) |maybe_chill| {
            if (maybe_chill) |chill| {
                const pips = switch (chill.chill) {
                    .soggy => -@as(i16, 2) * @as(i16, chill.stack_intensity), // -2 per stack (DoT)
                    .windburn => -@as(i16, 3) * @as(i16, chill.stack_intensity), // -3 per stack (DoT)
                    .brain_freeze => -@as(i16, 1) * @as(i16, chill.stack_intensity), // -1 per stack
                    else => 0,
                };
                total_pips += pips;
            }
        }

        // TODO: Add natural regeneration pips (GW1 out-of-combat regen)
        // if (self.time_safe_for_natural_regen >= 5.0) {
        //     const natural_pips = calculateNaturalRegenPips(self.time_safe_for_natural_regen);
        //     total_pips += natural_pips;
        // }

        // Clamp to GW1 limits: -10 to +10
        self.warmth_regen_pips = @intCast(@max(-10, @min(10, total_pips)));
    }

    pub fn updateCooldowns(self: *Character, delta_time: f32) void {
        // Update skill cooldowns
        for (&self.skill_cooldowns) |*cooldown| {
            if (cooldown.* > 0) {
                cooldown.* = @max(0, cooldown.* - delta_time);
            }
        }

        // Update casting state (activation phase)
        if (self.cast_state == .activating) {
            self.cast_time_remaining = @max(0, self.cast_time_remaining - delta_time);
            if (self.cast_time_remaining <= 0) {
                // Cast is complete - will be executed by game_state.finishCasts()
                // Don't change state here - game_state handles transition to aftercast
            }
        }

        // Update aftercast state
        if (self.cast_state == .aftercast) {
            self.aftercast_time_remaining = @max(0, self.aftercast_time_remaining - delta_time);
            if (self.aftercast_time_remaining <= 0) {
                self.cast_state = .idle;
            }
        }
    }

    pub fn updateConditions(self: *Character, delta_time_ms: u32) void {
        var conditions_changed = false;

        // Update active chills (debuffs), removing expired ones
        // Use swap-with-last pattern for efficient removal (order doesn't matter for conditions)
        var i: usize = 0;
        while (i < self.active_chill_count) {
            if (self.active_chills[i]) |*chill| {
                if (chill.time_remaining_ms <= delta_time_ms) {
                    // Chill expired, remove it by swapping with last element
                    self.active_chill_count -= 1;
                    self.active_chills[i] = self.active_chills[self.active_chill_count];
                    self.active_chills[self.active_chill_count] = null;
                    conditions_changed = true;
                    // Don't increment i since we need to check the swapped element
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
                    // Cozy expired, remove it by swapping with last element
                    self.active_cozy_count -= 1;
                    self.active_cozies[i] = self.active_cozies[self.active_cozy_count];
                    self.active_cozies[self.active_cozy_count] = null;
                    conditions_changed = true;
                    // Don't increment i since we need to check the swapped element
                } else {
                    cozy.time_remaining_ms -= delta_time_ms;
                    i += 1;
                }
            } else {
                i += 1;
            }
        }

        // Recalculate warmth pips if any conditions expired
        if (conditions_changed) {
            self.recalculateWarmthPips();
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
                    self.recalculateWarmthPips(); // Pips changed!
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
            self.recalculateWarmthPips(); // New chill added!
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
                    self.recalculateWarmthPips(); // Pips changed!
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
            self.recalculateWarmthPips(); // New cozy added!
        }
        // Silently ignore if array is full - this is a game, not critical
    }

    pub fn canUseSkill(self: Character, skill_index: u8) bool {
        if (skill_index >= MAX_SKILLS) return false;
        // Can't use skills while casting or in aftercast
        if (self.cast_state != .idle) return false;
        if (self.skill_cooldowns[skill_index] > 0) return false;

        const skill = self.skill_bar[skill_index] orelse return false;
        if (self.energy < skill.energy_cost) return false;

        return true;
    }

    pub fn startCasting(self: *Character, skill_index: u8) void {
        const skill = self.skill_bar[skill_index] orelse return;

        self.cast_state = .activating;
        self.casting_skill_index = skill_index;
        self.cast_time_remaining = @as(f32, @floatFromInt(skill.activation_time_ms)) / 1000.0;
        self.skill_executed = false;

        // Consume energy immediately (even if cancelled later)
        self.energy -= skill.energy_cost;
    }

    /// Cancel current cast (GW1-accurate)
    /// Only works during activation phase (not aftercast)
    /// Only works on skills with activation_time_ms > 0 (instant skills can't be cancelled)
    /// Results:
    /// - Energy cost is STILL incurred (no refund)
    /// - Skill does NOT go on cooldown
    /// - No aftercast delay
    /// - Skill effect does NOT happen
    pub fn cancelCasting(self: *Character) void {
        if (self.cast_state == .activating) {
            // No energy refund (costs are incurred)
            // No cooldown set (skill doesn't go on recharge)

            self.cast_state = .idle;
            self.cast_time_remaining = 0;
            self.skill_executed = false;
            self.cast_target_id = null;
        }
    }

    /// Check if character can cancel their current cast
    pub fn canCancelCast(self: Character) bool {
        if (self.cast_state != .activating) return false;

        const skill = self.skill_bar[self.casting_skill_index] orelse return false;
        // Only skills with activation time can be cancelled
        // NOTE: In GW1, instant attack skills (0 activation) can be cancelled by weapon swapping
        // We could implement this later if needed for advanced play
        return skill.activation_time_ms > 0;
    }

    /// Check if character is casting (activating or in aftercast)
    pub fn isCasting(self: Character) bool {
        return self.cast_state != .idle;
    }

    // === SKILL QUEUE SYSTEM (GW1-style auto-approach) ===

    /// Queue a skill to cast when in range (GW1 behavior)
    pub fn queueSkill(self: *Character, skill_index: u8, target_id: EntityId) void {
        self.queued_skill_index = skill_index;
        self.queued_skill_target_id = target_id;
        self.is_approaching_for_skill = true;
    }

    /// Clear the skill queue
    pub fn clearSkillQueue(self: *Character) void {
        self.queued_skill_index = null;
        self.queued_skill_target_id = null;
        self.is_approaching_for_skill = false;
    }

    /// Check if character has a queued skill
    pub fn hasQueuedSkill(self: Character) bool {
        return self.queued_skill_index != null;
    }

    // === AUTO-ATTACK SYSTEM (Guild Wars style) ===

    /// Start auto-attacking a target (spacebar default in GW1)
    pub fn startAutoAttack(self: *Character, target_id: EntityId) void {
        self.is_auto_attacking = true;
        self.auto_attack_target_id = target_id;
        // Reset timer to attack immediately
        self.auto_attack_timer = 0.0;
    }

    /// Stop auto-attacking
    pub fn stopAutoAttack(self: *Character) void {
        self.is_auto_attacking = false;
        self.auto_attack_target_id = null;
    }

    /// Get the attack interval for this character's equipped weapon
    pub fn getAttackInterval(self: Character) f32 {
        // Use main hand weapon if equipped, otherwise default
        if (self.main_hand) |weapon| {
            return weapon.attack_interval;
        }
        // Default unarmed attack speed
        return 2.0;
    }

    /// Calculate auto-attack damage based on weapon and attributes
    pub fn getAutoAttackDamage(self: Character) f32 {
        var base_damage: f32 = 5.0; // Unarmed damage

        if (self.main_hand) |weapon| {
            base_damage = weapon.damage;
        }

        // TODO: Apply attribute bonuses (like GW1's weapon mastery)
        // TODO: Apply buffs/debuffs

        return base_damage;
    }

    /// Get auto-attack range
    pub fn getAutoAttackRange(self: Character) f32 {
        if (self.main_hand) |weapon| {
            return weapon.range;
        }
        return 50.0; // Default melee range
    }
};
