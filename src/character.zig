const std = @import("std");
const rl = @import("raylib");
const school = @import("school.zig");
const position = @import("position.zig");
const skills = @import("skills.zig");
const equipment = @import("equipment.zig");
const gear_slot = @import("gear_slot.zig");
const entity = @import("entity.zig");
const effects = @import("effects.zig");

// Component modules
const character_stats = @import("character_stats.zig");
const character_casting = @import("character_casting.zig");
const character_conditions = @import("character_conditions.zig");
const character_school_resources = @import("character_school_resources.zig");
const character_combat = @import("character_combat.zig");

const print = std.debug.print;

// Re-export types for backward compatibility
pub const School = school.School;
pub const Position = position.Position;
pub const Skill = skills.Skill;
pub const Equipment = equipment.Equipment;
pub const Gear = gear_slot.Gear;
pub const GearSlot = gear_slot.GearSlot;
pub const EntityId = entity.EntityId;
pub const Team = entity.Team;

// Re-export component types
pub const WarmthState = character_stats.WarmthState;
pub const EnergyState = character_stats.EnergyState;
pub const GearStats = character_stats.GearStats;
pub const CastState = character_casting.CastState;
pub const CastingState = character_casting.CastingState;
pub const SkillBar = character_casting.SkillBar;
pub const QueuedSkill = character_casting.QueuedSkill;
pub const ChillState = character_conditions.ChillState;
pub const CozyState = character_conditions.CozyState;
pub const EffectState = character_conditions.EffectState;
pub const ConditionState = character_conditions.ConditionState;
pub const SchoolResourceState = character_school_resources.SchoolResourceState;
pub const CombatState = character_combat.CombatState;
pub const DamageSource = character_combat.DamageSource;
pub const DamageMonitor = character_combat.DamageMonitor;
pub const AutoAttackState = character_combat.AutoAttackState;
pub const MeleeLungeState = character_combat.MeleeLungeState;

// Re-export constants for backward compatibility
pub const MAX_SKILLS: usize = character_casting.MAX_SKILLS;
pub const MAX_ACTIVE_CONDITIONS: usize = character_conditions.MAX_ACTIVE_CONDITIONS;
pub const MAX_RECENT_SKILLS: usize = character_school_resources.MAX_RECENT_SKILLS;
pub const MAX_GRIT_STACKS: u8 = character_school_resources.MAX_GRIT_STACKS;
pub const MAX_RHYTHM_CHARGE: u8 = character_school_resources.MAX_RHYTHM_CHARGE;
pub const MAX_DAMAGE_SOURCES: usize = character_combat.MAX_DAMAGE_SOURCES;

pub const Character = struct {
    // === IDENTITY ===
    id: EntityId, // Unique identifier for this entity (stable across ticks)
    name: [:0]const u8,
    team: Team, // Which team this character belongs to

    // === POSITION & PHYSICS ===
    position: rl.Vector3, // Current tick position (authoritative)
    previous_position: rl.Vector3 = .{ .x = 0, .y = 0, .z = 0 }, // Previous tick position (for interpolation)
    radius: f32,
    facing_angle: f32 = 0.0, // Entity's actual facing direction (decoupled from camera)

    // === VISUAL ===
    color: rl.Color,
    school_color: rl.Color, // For halftone rendering
    position_color: rl.Color, // For halftone rendering

    // === SCHOOL & POSITION ===
    school: School,
    player_position: Position,

    // === CORE STATS (component) ===
    warmth: f32,
    max_warmth: f32,
    energy: u8,
    max_energy: u8,
    energy_accumulator: f32 = 0.0, // Tracks fractional energy for smooth regen
    warmth_regen_pips: i8 = 0, // -10 to +10 pips (like GW1 health regen/degen)
    warmth_pip_accumulator: f32 = 0.0, // Tracks fractional warmth for pip ticking

    // === GEAR SYSTEM (6 slots: toque, scarf, jacket, gloves, pants, boots) ===
    gear: [gear_slot.SLOT_COUNT]?*const Gear = [_]?*const Gear{null} ** gear_slot.SLOT_COUNT,
    total_padding: f32 = 0.0, // Cached total armor value from equipped gear

    // === EQUIPMENT SYSTEM (flexible hand slots + worn) ===
    main_hand: ?*const equipment.Equipment = null,
    off_hand: ?*const equipment.Equipment = null,
    worn: ?*const equipment.Equipment = null, // Mittens, Blanket, etc.

    // === SKILL SYSTEM (component) ===
    skill_bar: [MAX_SKILLS]?*const Skill,
    selected_skill: u8 = 0,
    skill_cooldowns: [MAX_SKILLS]f32 = [_]f32{0.0} ** MAX_SKILLS, // time remaining in seconds

    // === CASTING STATE (component) ===
    cast_state: CastState = .idle,
    casting_skill_index: u8 = 0,
    cast_time_remaining: f32 = 0.0, // seconds remaining on current cast phase
    skill_executed: bool = false, // Has skill effect/projectile been fired?
    cast_target_id: ?EntityId = null, // Target entity ID for cast completion
    aftercast_time_remaining: f32 = 0.0, // seconds remaining in aftercast

    // === SKILL QUEUE (GW1 style: run into range and cast) ===
    queued_skill_index: ?u8 = null, // Which skill to cast when in range
    queued_skill_target_id: ?EntityId = null, // Target for queued skill
    is_approaching_for_skill: bool = false, // Moving toward target to cast

    // === CONDITIONS (component) ===
    active_chills: [MAX_ACTIVE_CONDITIONS]?skills.ActiveChill = [_]?skills.ActiveChill{null} ** MAX_ACTIVE_CONDITIONS,
    active_chill_count: u8 = 0,
    active_cozies: [MAX_ACTIVE_CONDITIONS]?skills.ActiveCozy = [_]?skills.ActiveCozy{null} ** MAX_ACTIVE_CONDITIONS,
    active_cozy_count: u8 = 0,
    active_effects: [MAX_ACTIVE_CONDITIONS]?effects.ActiveEffect = [_]?effects.ActiveEffect{null} ** MAX_ACTIVE_CONDITIONS,
    active_effect_count: u8 = 0,

    // === SCHOOL RESOURCES (component) ===
    // Private School: Credit/Debt
    credit_debt: u8 = 0,
    credit_recovery_timer: f32 = 0.0,
    // Public School: Grit
    grit_stacks: u8 = 0,
    max_grit_stacks: u8 = MAX_GRIT_STACKS,
    // Homeschool: Sacrifice
    sacrifice_cooldown: f32 = 0.0,
    // Waldorf: Rhythm
    rhythm_charge: u8 = 0,
    rhythm_perfect_window: f32 = 0.0,
    max_rhythm_charge: u8 = MAX_RHYTHM_CHARGE,
    last_skill_type_for_rhythm: ?skills.SkillType = null,
    // Montessori: Variety
    last_skill_types_used: [MAX_RECENT_SKILLS]?skills.SkillType = [_]?skills.SkillType{null} ** MAX_RECENT_SKILLS,
    last_skill_type_index: u8 = 0,
    variety_bonus_damage: f32 = 0.0,

    // === COMBAT STATE (component) ===
    is_auto_attacking: bool = false,
    auto_attack_timer: f32 = 0.0,
    auto_attack_target_id: ?EntityId = null,
    lunge_time_remaining: f32 = 0.0,
    lunge_return_position: rl.Vector3 = .{ .x = 0, .y = 0, .z = 0 },

    // === DAMAGE MONITOR (component) ===
    damage_sources: [MAX_DAMAGE_SOURCES]?DamageSource = [_]?DamageSource{null} ** MAX_DAMAGE_SOURCES,
    damage_source_count: u8 = 0,
    damage_monitor_frozen: bool = false, // Freeze on death until resurrection

    // === DEATH STATE ===
    is_dead: bool = false,

    // ========================================================================
    // BASIC QUERIES
    // ========================================================================

    pub fn isAlive(self: Character) bool {
        return !self.is_dead and self.warmth > 0;
    }

    pub fn isAlly(self: Character, other: Character) bool {
        return self.team.isAlly(other.team);
    }

    pub fn isEnemy(self: Character, other: Character) bool {
        return self.team.isEnemy(other.team);
    }

    /// Check if character is freezing (below 25% warmth)
    pub fn isFreezing(self: Character) bool {
        return (self.warmth / self.max_warmth) < 0.25;
    }

    // ========================================================================
    // MOVEMENT
    // ========================================================================

    pub fn getMovementSpeedMultiplier(self: Character) f32 {
        if (self.isFreezing()) {
            return 0.75; // -25% movement speed when freezing
        }

        // Apply gear speed modifiers
        var speed_mult: f32 = 1.0;
        for (self.gear) |maybe_gear| {
            if (maybe_gear) |g| {
                speed_mult *= g.speed_modifier;
            }
        }

        // Apply active effect move speed multipliers
        const effect_speed_mult = effects.calculateMoveSpeedMultiplier(&self.active_effects, self.active_effect_count);
        speed_mult *= effect_speed_mult;

        return speed_mult;
    }

    pub fn getInterpolatedPosition(self: Character, alpha: f32) rl.Vector3 {
        return rl.Vector3{
            .x = self.previous_position.x + (self.position.x - self.previous_position.x) * alpha,
            .y = self.previous_position.y + (self.position.y - self.previous_position.y) * alpha,
            .z = self.previous_position.z + (self.position.z - self.previous_position.z) * alpha,
        };
    }

    pub fn distanceTo(self: Character, other: Character) f32 {
        const dx = self.position.x - other.position.x;
        const dy = self.position.y - other.position.y;
        const dz = self.position.z - other.position.z;
        return @sqrt(dx * dx + dy * dy + dz * dz);
    }

    pub fn overlaps(self: Character, other: Character) bool {
        const distance = self.distanceTo(other);
        const min_distance = self.radius + other.radius;
        return distance < min_distance;
    }

    pub fn resolveCollision(self: *Character, other: Character) void {
        const dx = self.position.x - other.position.x;
        const dz = self.position.z - other.position.z;
        const distance = @sqrt(dx * dx + dz * dz);

        if (distance < 0.1) return;

        const min_distance = self.radius + other.radius;
        if (distance < min_distance) {
            const overlap = min_distance - distance;
            const push_x = (dx / distance) * overlap;
            const push_z = (dz / distance) * overlap;

            self.position.x += push_x;
            self.position.z += push_z;
        }
    }

    // ========================================================================
    // GEAR SYSTEM
    // ========================================================================

    pub fn recalculatePadding(self: *Character) void {
        var total: f32 = 0.0;
        for (self.gear) |maybe_gear| {
            if (maybe_gear) |g| {
                total += g.padding;
            }
        }
        self.total_padding = total;
    }

    pub fn getTotalPadding(self: Character) f32 {
        return self.total_padding;
    }

    pub fn equipGear(self: *Character, gear_to_equip: *const Gear) void {
        const slot_index = @intFromEnum(gear_to_equip.slot);
        self.gear[slot_index] = gear_to_equip;
        self.recalculatePadding();
    }

    pub fn unequipGear(self: *Character, slot: GearSlot) void {
        const slot_index = @intFromEnum(slot);
        self.gear[slot_index] = null;
        self.recalculatePadding();
    }

    pub fn getGearInSlot(self: Character, slot: GearSlot) ?*const Gear {
        const slot_index = @intFromEnum(slot);
        return self.gear[slot_index];
    }

    pub fn getGearWarmthRegen(self: Character) f32 {
        var total: f32 = 0.0;
        for (self.gear) |maybe_gear| {
            if (maybe_gear) |g| {
                total += g.warmth_regen_bonus;
            }
        }
        return total;
    }

    pub fn getGearEnergyRegen(self: Character) f32 {
        var total: f32 = 0.0;
        for (self.gear) |maybe_gear| {
            if (maybe_gear) |g| {
                total += g.energy_regen_bonus;
            }
        }
        return total;
    }

    // ========================================================================
    // DAMAGE & DEATH
    // ========================================================================

    pub fn takeDamage(self: *Character, damage: f32) void {
        if (damage >= self.warmth) {
            self.warmth = 0.0;
        } else {
            self.warmth -= damage;
        }

        if (self.warmth <= 0) {
            self.is_dead = true;
            self.damage_monitor_frozen = true;
            if (self.cast_state != .idle) {
                self.cancelCasting();
            }
        }
    }

    pub fn interrupt(self: *Character) void {
        if (self.cast_state == .activating) {
            print("{s}'s cast was interrupted!\n", .{self.name});
            self.cancelCasting();
        }
    }

    // ========================================================================
    // ENERGY SYSTEM
    // ========================================================================

    pub fn updateEnergy(self: *Character, delta_time: f32) void {
        var regen = self.school.getEnergyRegen();
        regen += self.getGearEnergyRegen();

        const regen_mult = effects.calculateEnergyRegenMultiplier(&self.active_effects, self.active_effect_count);
        regen *= regen_mult;

        const energy_delta = regen * delta_time;
        self.energy_accumulator += energy_delta;

        if (self.energy_accumulator >= 1.0) {
            const energy_to_add = @as(u8, @intFromFloat(self.energy_accumulator));
            self.energy = @min(self.max_energy, self.energy + energy_to_add);
            self.energy_accumulator -= @as(f32, @floatFromInt(energy_to_add));
        }

        // Update school-specific mechanics
        switch (self.school) {
            .private_school => {
                if (self.credit_debt > 0) {
                    self.credit_recovery_timer += delta_time;
                    if (self.credit_recovery_timer >= 3.0) {
                        self.credit_debt -= 1;
                        self.credit_recovery_timer = 0.0;
                    }
                }
            },
            .public_school => {},
            .montessori => {},
            .homeschool => {
                if (self.sacrifice_cooldown > 0) {
                    self.sacrifice_cooldown = @max(0, self.sacrifice_cooldown - delta_time);
                }
            },
            .waldorf => {
                if (self.rhythm_perfect_window > 0) {
                    self.rhythm_perfect_window = @max(0, self.rhythm_perfect_window - delta_time);
                }
            },
        }
    }

    // ========================================================================
    // WARMTH SYSTEM
    // ========================================================================

    pub fn updateWarmth(self: *Character, delta_time: f32) void {
        const warmth_per_second = @as(f32, @floatFromInt(self.warmth_regen_pips)) * 2.0;
        const warmth_delta = warmth_per_second * delta_time;

        self.warmth_pip_accumulator += warmth_delta;

        if (@abs(self.warmth_pip_accumulator) >= 1.0) {
            const warmth_to_apply = self.warmth_pip_accumulator;
            self.warmth = @max(0.0, @min(self.max_warmth, self.warmth + warmth_to_apply));
            self.warmth_pip_accumulator -= warmth_to_apply;

            if (self.warmth <= 0) {
                self.is_dead = true;
                if (self.cast_state != .idle) {
                    self.cancelCasting();
                }
            }
        }
    }

    pub fn recalculateWarmthPips(self: *Character) void {
        var total_pips: i16 = 0;

        // Add regeneration from cozies
        for (self.active_cozies[0..self.active_cozy_count]) |maybe_cozy| {
            if (maybe_cozy) |cozy| {
                const pips = switch (cozy.cozy) {
                    .hot_cocoa => @as(i16, 2) * @as(i16, cozy.stack_intensity),
                    .fire_inside => @as(i16, 1) * @as(i16, cozy.stack_intensity),
                    else => 0,
                };
                total_pips += pips;
            }
        }

        // Add degeneration from chills
        for (self.active_chills[0..self.active_chill_count]) |maybe_chill| {
            if (maybe_chill) |chill| {
                const pips = switch (chill.chill) {
                    .soggy => -@as(i16, 2) * @as(i16, chill.stack_intensity),
                    .windburn => -@as(i16, 3) * @as(i16, chill.stack_intensity),
                    .brain_freeze => -@as(i16, 1) * @as(i16, chill.stack_intensity),
                    else => 0,
                };
                total_pips += pips;
            }
        }

        // Add gear warmth regen bonus
        const gear_warmth_regen = self.getGearWarmthRegen();
        const gear_warmth_pips = @as(i16, @intFromFloat(gear_warmth_regen / 2.0));
        total_pips += gear_warmth_pips;

        self.warmth_regen_pips = @intCast(@max(-10, @min(10, total_pips)));
    }

    // ========================================================================
    // COOLDOWNS & CASTING
    // ========================================================================

    pub fn updateCooldowns(self: *Character, delta_time: f32) void {
        for (&self.skill_cooldowns) |*cooldown| {
            if (cooldown.* > 0) {
                cooldown.* = @max(0, cooldown.* - delta_time);
            }
        }

        if (self.cast_state == .activating) {
            self.cast_time_remaining = @max(0, self.cast_time_remaining - delta_time);
        }

        if (self.cast_state == .aftercast) {
            self.aftercast_time_remaining = @max(0, self.aftercast_time_remaining - delta_time);
            if (self.aftercast_time_remaining <= 0) {
                self.cast_state = .idle;
            }
        }
    }

    pub fn canUseSkill(self: Character, skill_index: u8) bool {
        if (skill_index >= MAX_SKILLS) return false;
        if (self.cast_state != .idle) return false;
        if (self.skill_cooldowns[skill_index] > 0) return false;

        const skill_to_check = self.skill_bar[skill_index] orelse return false;
        if (self.energy < skill_to_check.energy_cost) return false;

        return true;
    }

    pub fn startCasting(self: *Character, skill_index: u8) void {
        const skill_to_cast = self.skill_bar[skill_index] orelse return;

        self.cast_state = .activating;
        self.casting_skill_index = skill_index;
        self.cast_time_remaining = @as(f32, @floatFromInt(skill_to_cast.activation_time_ms)) / 1000.0;
        self.skill_executed = false;

        const energy_cost_mult = effects.calculateEnergyCostMultiplier(&self.active_effects, self.active_effect_count);
        const energy_cost = @as(u8, @intFromFloat(@as(f32, @floatFromInt(skill_to_cast.energy_cost)) * energy_cost_mult));
        self.energy -= energy_cost;
    }

    pub fn cancelCasting(self: *Character) void {
        if (self.cast_state == .activating) {
            self.cast_state = .idle;
            self.cast_time_remaining = 0;
            self.skill_executed = false;
            self.cast_target_id = null;
        }
    }

    pub fn canCancelCast(self: Character) bool {
        if (self.cast_state != .activating) return false;

        const skill_to_check = self.skill_bar[self.casting_skill_index] orelse return false;
        return skill_to_check.activation_time_ms > 0;
    }

    pub fn isCasting(self: Character) bool {
        return self.cast_state != .idle;
    }

    // ========================================================================
    // SKILL QUEUE
    // ========================================================================

    pub fn queueSkill(self: *Character, skill_index: u8, target_id: EntityId) void {
        self.queued_skill_index = skill_index;
        self.queued_skill_target_id = target_id;
        self.is_approaching_for_skill = true;
    }

    pub fn clearSkillQueue(self: *Character) void {
        self.queued_skill_index = null;
        self.queued_skill_target_id = null;
        self.is_approaching_for_skill = false;
    }

    pub fn hasQueuedSkill(self: Character) bool {
        return self.queued_skill_index != null;
    }

    // ========================================================================
    // CONDITIONS
    // ========================================================================

    pub fn updateConditions(self: *Character, delta_time_ms: u32) void {
        var conditions_changed = false;

        // Update active chills
        var i: usize = 0;
        while (i < self.active_chill_count) {
            if (self.active_chills[i]) |*chill| {
                if (chill.time_remaining_ms <= delta_time_ms) {
                    self.active_chill_count -= 1;
                    self.active_chills[i] = self.active_chills[self.active_chill_count];
                    self.active_chills[self.active_chill_count] = null;
                    conditions_changed = true;
                } else {
                    chill.time_remaining_ms -= delta_time_ms;
                    i += 1;
                }
            } else {
                i += 1;
            }
        }

        // Update active cozies
        i = 0;
        while (i < self.active_cozy_count) {
            if (self.active_cozies[i]) |*cozy| {
                if (cozy.time_remaining_ms <= delta_time_ms) {
                    self.active_cozy_count -= 1;
                    self.active_cozies[i] = self.active_cozies[self.active_cozy_count];
                    self.active_cozies[self.active_cozy_count] = null;
                    conditions_changed = true;
                } else {
                    cozy.time_remaining_ms -= delta_time_ms;
                    i += 1;
                }
            } else {
                i += 1;
            }
        }

        // Update active effects
        i = 0;
        while (i < self.active_effect_count) {
            if (self.active_effects[i]) |*effect| {
                if (effect.time_remaining_ms <= delta_time_ms) {
                    self.active_effect_count -= 1;
                    self.active_effects[i] = self.active_effects[self.active_effect_count];
                    self.active_effects[self.active_effect_count] = null;
                } else {
                    effect.time_remaining_ms -= delta_time_ms;
                    i += 1;
                }
            } else {
                i += 1;
            }
        }

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
        for (self.active_chills[0..self.active_chill_count]) |*maybe_active| {
            if (maybe_active.*) |*active| {
                if (active.chill == effect.chill) {
                    active.time_remaining_ms = @max(active.time_remaining_ms, effect.duration_ms);
                    active.stack_intensity = @min(255, active.stack_intensity + effect.stack_intensity);
                    self.recalculateWarmthPips();
                    return;
                }
            }
        }

        if (self.active_chill_count < self.active_chills.len) {
            self.active_chills[self.active_chill_count] = .{
                .chill = effect.chill,
                .time_remaining_ms = effect.duration_ms,
                .stack_intensity = effect.stack_intensity,
                .source_character_id = source_id,
            };
            self.active_chill_count += 1;
            self.recalculateWarmthPips();
        }
    }

    pub fn addCozy(self: *Character, effect: skills.CozyEffect, source_id: ?u32) void {
        for (self.active_cozies[0..self.active_cozy_count]) |*maybe_active| {
            if (maybe_active.*) |*active| {
                if (active.cozy == effect.cozy) {
                    active.time_remaining_ms = @max(active.time_remaining_ms, effect.duration_ms);
                    active.stack_intensity = @min(255, active.stack_intensity + effect.stack_intensity);
                    self.recalculateWarmthPips();
                    return;
                }
            }
        }

        if (self.active_cozy_count < self.active_cozies.len) {
            self.active_cozies[self.active_cozy_count] = .{
                .cozy = effect.cozy,
                .time_remaining_ms = effect.duration_ms,
                .stack_intensity = effect.stack_intensity,
                .source_character_id = source_id,
            };
            self.active_cozy_count += 1;
            self.recalculateWarmthPips();
        }
    }

    pub fn addEffect(self: *Character, effect: *const effects.Effect, source_id: ?u32) void {
        for (self.active_effects[0..self.active_effect_count]) |*maybe_active| {
            if (maybe_active.*) |*active| {
                if (active.effect == effect) {
                    switch (effect.stack_behavior) {
                        .refresh_duration => {
                            active.time_remaining_ms = @max(active.time_remaining_ms, effect.duration_ms);
                        },
                        .add_intensity => {
                            active.stack_count = @min(effect.max_stacks, active.stack_count + 1);
                            active.time_remaining_ms = effect.duration_ms;
                        },
                        .ignore_if_active => {
                            return;
                        },
                    }
                    return;
                }
            }
        }

        if (self.active_effect_count < self.active_effects.len) {
            self.active_effects[self.active_effect_count] = .{
                .effect = effect,
                .time_remaining_ms = effect.duration_ms,
                .stack_count = 1,
                .source_character_id = source_id,
            };
            self.active_effect_count += 1;
        }
    }

    // ========================================================================
    // SKILL BAR / AP VALIDATION
    // ========================================================================

    pub fn countApSkills(self: Character) u8 {
        var count: u8 = 0;
        for (self.skill_bar) |maybe_skill| {
            if (maybe_skill) |skill_item| {
                if (skill_item.is_ap) {
                    count += 1;
                }
            }
        }
        return count;
    }

    pub fn hasApSkill(self: Character) bool {
        return self.countApSkills() > 0;
    }

    pub fn getApSkillIndex(self: Character) ?u8 {
        for (self.skill_bar, 0..) |maybe_skill, i| {
            if (maybe_skill) |skill_item| {
                if (skill_item.is_ap) {
                    return @intCast(i);
                }
            }
        }
        return null;
    }

    pub fn canEquipSkill(self: Character, skill_to_equip: *const Skill, slot_index: u8) bool {
        if (slot_index >= MAX_SKILLS) return false;

        if (skill_to_equip.is_ap) {
            for (self.skill_bar, 0..) |maybe_existing, i| {
                if (i == slot_index) continue;
                if (maybe_existing) |existing| {
                    if (existing.is_ap) {
                        return false;
                    }
                }
            }
        }

        return true;
    }

    pub fn equipSkill(self: *Character, skill_to_equip: *const Skill, slot_index: u8) bool {
        if (!self.canEquipSkill(skill_to_equip, slot_index)) {
            return false;
        }

        self.skill_bar[slot_index] = skill_to_equip;
        return true;
    }

    pub fn unequipSkill(self: *Character, slot_index: u8) void {
        if (slot_index < MAX_SKILLS) {
            self.skill_bar[slot_index] = null;
        }
    }

    pub fn swapApSkill(self: *Character, new_ap_skill: *const Skill) ?u8 {
        if (!new_ap_skill.is_ap) return null;

        const existing_slot = self.getApSkillIndex();
        if (existing_slot) |slot| {
            self.skill_bar[slot] = new_ap_skill;
            return slot;
        }

        for (self.skill_bar, 0..) |maybe_skill, i| {
            if (maybe_skill == null) {
                self.skill_bar[i] = new_ap_skill;
                return @intCast(i);
            }
        }

        return null;
    }

    pub fn validateSkillBar(self: Character) bool {
        return self.countApSkills() <= 1;
    }

    // ========================================================================
    // DAMAGE MONITOR
    // ========================================================================

    pub fn recordDamageSource(self: *Character, skill_source: *const Skill, source_id: EntityId) void {
        if (self.damage_monitor_frozen) return;

        for (self.damage_sources[0..self.damage_source_count]) |*maybe_source| {
            if (maybe_source.*) |*source| {
                if (std.mem.eql(u8, source.skill_name, skill_source.name) and source.source_id == source_id) {
                    source.hit_count += 1;
                    source.time_since_last_hit = 0.0;
                    return;
                }
            }
        }

        if (self.damage_source_count < self.damage_sources.len) {
            self.damage_sources[self.damage_source_count] = DamageSource{
                .skill_name = skill_source.name,
                .skill_ptr = skill_source,
                .source_id = source_id,
                .hit_count = 1,
                .time_since_last_hit = 0.0,
            };
            self.damage_source_count += 1;
        } else {
            for (1..self.damage_sources.len) |j| {
                self.damage_sources[j - 1] = self.damage_sources[j];
            }
            self.damage_sources[self.damage_sources.len - 1] = DamageSource{
                .skill_name = skill_source.name,
                .skill_ptr = skill_source,
                .source_id = source_id,
                .hit_count = 1,
                .time_since_last_hit = 0.0,
            };
        }
    }

    pub fn updateDamageMonitor(self: *Character, delta_time: f32) void {
        if (self.damage_monitor_frozen) return;

        var i: usize = 0;
        while (i < self.damage_source_count) {
            if (self.damage_sources[i]) |*source| {
                source.time_since_last_hit += delta_time;

                if (source.time_since_last_hit > 10.0) {
                    for (i + 1..self.damage_source_count) |j| {
                        self.damage_sources[j - 1] = self.damage_sources[j];
                    }
                    self.damage_sources[self.damage_source_count - 1] = null;
                    self.damage_source_count -= 1;
                    continue;
                }
            }
            i += 1;
        }
    }

    // ========================================================================
    // AUTO-ATTACK
    // ========================================================================

    pub fn startAutoAttack(self: *Character, target_id: EntityId) void {
        self.is_auto_attacking = true;
        self.auto_attack_target_id = target_id;
        self.auto_attack_timer = 0.0;
    }

    pub fn stopAutoAttack(self: *Character) void {
        self.is_auto_attacking = false;
        self.auto_attack_target_id = null;
    }

    pub fn getAttackInterval(self: Character) f32 {
        if (self.main_hand) |main| {
            if (main.hand_requirement == .two_hands) {
                return main.attack_interval;
            }
        }

        if (self.main_hand) |main| {
            if (main.hand_requirement == .one_hand) {
                return main.attack_interval;
            }
        }

        return 1.5;
    }

    pub fn getAutoAttackDamage(self: Character) f32 {
        var base_damage: f32 = 10.0;

        if (self.main_hand) |main| {
            if (main.hand_requirement == .two_hands) {
                return main.damage;
            }
        }

        if (self.main_hand) |main| {
            if (main.hand_requirement == .one_hand) {
                if (main.category == .melee_weapon) {
                    return main.damage;
                }
                if (main.category == .throwing_tool) {
                    return main.damage;
                }
            }
        }

        if (self.worn) |worn_item| {
            base_damage += worn_item.damage;
        }

        return base_damage;
    }

    pub fn getAutoAttackRange(self: Character) f32 {
        const base_range: f32 = 80.0;

        if (self.main_hand) |main| {
            if (main.hand_requirement == .two_hands) {
                return main.range;
            }
        }

        if (self.main_hand) |main| {
            if (main.hand_requirement == .one_hand) {
                if (main.category == .melee_weapon or main.category == .throwing_tool) {
                    return main.range;
                }
            }
        }

        var final_range = base_range;
        if (self.worn) |worn_item| {
            final_range += worn_item.range;
        }

        return @max(30.0, final_range);
    }

    pub fn hasRangedAutoAttack(self: Character) bool {
        if (self.main_hand) |main| {
            if (main.hand_requirement == .two_hands) {
                return main.is_ranged;
            }
        }

        if (self.main_hand) |main| {
            if (main.hand_requirement == .one_hand) {
                if (main.category == .melee_weapon) {
                    return false;
                }
                if (main.category == .throwing_tool) {
                    return true;
                }
            }
        }

        return true;
    }
};
