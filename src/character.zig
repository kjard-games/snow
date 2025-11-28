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
pub const character_stats = @import("character_stats.zig");
pub const character_casting = @import("character_casting.zig");
pub const character_conditions = @import("character_conditions.zig");
pub const character_school_resources = @import("character_school_resources.zig");
pub const character_combat = @import("character_combat.zig");
pub const combat_behavior = @import("combat_behavior.zig");

const print = std.debug.print;

// Re-export types for convenience
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
pub const WarmthPipState = character_conditions.WarmthPipState;
pub const SchoolResourceState = character_school_resources.SchoolResourceState;
pub const CreditDebtState = character_school_resources.CreditDebtState;
pub const GritState = character_school_resources.GritState;
pub const SacrificeState = character_school_resources.SacrificeState;
pub const RhythmState = character_school_resources.RhythmState;
pub const VarietyState = character_school_resources.VarietyState;
pub const CombatState = character_combat.CombatState;
pub const DamageSource = character_combat.DamageSource;
pub const DamageMonitor = character_combat.DamageMonitor;
pub const AutoAttackState = character_combat.AutoAttackState;
pub const MeleeLungeState = character_combat.MeleeLungeState;
pub const BehaviorState = combat_behavior.BehaviorState;
pub const ActiveBehavior = combat_behavior.ActiveBehavior;

// Re-export constants
pub const MAX_SKILLS: usize = character_casting.MAX_SKILLS;
pub const MAX_ACTIVE_CONDITIONS: usize = character_conditions.MAX_ACTIVE_CONDITIONS;
pub const MAX_RECENT_SKILLS: usize = character_school_resources.MAX_RECENT_SKILLS;
pub const MAX_GRIT_STACKS: u8 = character_school_resources.MAX_GRIT_STACKS;
pub const MAX_RHYTHM_CHARGE: u8 = character_school_resources.MAX_RHYTHM_CHARGE;
pub const MAX_DAMAGE_SOURCES: usize = character_combat.MAX_DAMAGE_SOURCES;

pub const Character = struct {
    // === IDENTITY ===
    id: EntityId,
    name: [:0]const u8,
    team: Team,

    // === POSITION & PHYSICS ===
    position: rl.Vector3,
    previous_position: rl.Vector3 = .{ .x = 0, .y = 0, .z = 0 },
    radius: f32,
    facing_angle: f32 = 0.0,

    // === VISUAL ===
    color: rl.Color,
    school_color: rl.Color,
    position_color: rl.Color,

    // === SCHOOL & POSITION ===
    school: School,
    player_position: Position,

    // === CORE STATS (embedded component) ===
    stats: Stats = .{},

    // === GEAR SYSTEM ===
    gear: [gear_slot.SLOT_COUNT]?*const Gear = [_]?*const Gear{null} ** gear_slot.SLOT_COUNT,
    gear_stats: GearStats = .{},

    // === EQUIPMENT SYSTEM (hand slots + worn) ===
    main_hand: ?*const equipment.Equipment = null,
    off_hand: ?*const equipment.Equipment = null,
    worn: ?*const equipment.Equipment = null,

    // === CASTING STATE (embedded component) ===
    casting: CastingState = .{},

    // === CONDITIONS (embedded component) ===
    conditions: ConditionState = .{},

    // === SCHOOL RESOURCES (embedded component) ===
    school_resources: SchoolResourceState = .{},

    // === COMBAT STATE (embedded component) ===
    combat: CombatState = .{},

    // === BEHAVIOR STATE (embedded component) ===
    behaviors: BehaviorState = .{},

    // === DEATH STATE ===
    is_dead: bool = false,

    /// Core stats that all characters share
    pub const Stats = struct {
        warmth: f32 = 200.0,
        max_warmth: f32 = 200.0,
        energy: u8 = 25,
        max_energy: u8 = 25,
        energy_accumulator: f32 = 0.0,
    };

    // ========================================================================
    // BASIC QUERIES
    // ========================================================================

    pub fn isAlive(self: Character) bool {
        return !self.is_dead and self.stats.warmth > 0;
    }

    pub fn isAlly(self: Character, other: Character) bool {
        return self.team.isAlly(other.team);
    }

    pub fn isEnemy(self: Character, other: Character) bool {
        return self.team.isEnemy(other.team);
    }

    pub fn isFreezing(self: Character) bool {
        return (self.stats.warmth / self.stats.max_warmth) < 0.25;
    }

    /// Check if character is knocked down (can't move or use skills)
    /// Checks both the knocked_down chill AND the knockdown effect modifier
    pub fn isKnockedDown(self: Character) bool {
        // Check the knocked_down chill
        if (self.conditions.hasChill(.knocked_down)) return true;

        // Check the knockdown effect modifier
        return effects.isKnockedDown(&self.conditions.effects.active, self.conditions.effects.count);
    }

    // ========================================================================
    // MOVEMENT
    // ========================================================================

    pub fn getMovementSpeedMultiplier(self: Character) f32 {
        // Can't move when knocked down
        if (self.isKnockedDown()) {
            return 0.0;
        }

        if (self.isFreezing()) {
            return 0.75;
        }

        var speed_mult = self.gear_stats.speed_multiplier;

        const effect_speed_mult = self.conditions.getMoveSpeedMultiplier();
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

    /// Check if character moved since last tick (for ice slip mechanic)
    /// Returns true if the character has moved a meaningful distance
    pub fn isMoving(self: Character) bool {
        const dx = self.position.x - self.previous_position.x;
        const dz = self.position.z - self.previous_position.z;
        const distance_sq = dx * dx + dz * dz;
        // Consider "moving" if moved more than 1 unit (prevents float precision issues)
        return distance_sq > 1.0;
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

    pub fn recalculateGearStats(self: *Character) void {
        self.gear_stats = GearStats.recalculate(&self.gear);
    }

    pub fn getTotalPadding(self: Character) f32 {
        return self.gear_stats.total_padding;
    }

    pub fn equipGear(self: *Character, gear_to_equip: *const Gear) void {
        const slot_index = @intFromEnum(gear_to_equip.slot);
        self.gear[slot_index] = gear_to_equip;
        self.recalculateGearStats();
    }

    pub fn unequipGear(self: *Character, slot: GearSlot) void {
        const slot_index = @intFromEnum(slot);
        self.gear[slot_index] = null;
        self.recalculateGearStats();
    }

    pub fn getGearInSlot(self: Character, slot: GearSlot) ?*const Gear {
        const slot_index = @intFromEnum(slot);
        return self.gear[slot_index];
    }

    // ========================================================================
    // DAMAGE & DEATH
    // ========================================================================

    pub fn takeDamage(self: *Character, damage: f32) void {
        if (damage >= self.stats.warmth) {
            self.stats.warmth = 0.0;
        } else {
            self.stats.warmth -= damage;
        }

        if (self.stats.warmth <= 0) {
            self.is_dead = true;
            self.combat.onDeath();
            if (self.casting.state != .idle) {
                self.casting.cancelCast();
            }
        }
    }

    pub fn interrupt(self: *Character) void {
        if (self.casting.interrupt()) {
            print("{s}'s cast was interrupted!\n", .{self.name});
        }
    }

    // ========================================================================
    // ENERGY SYSTEM
    // ========================================================================

    pub fn updateEnergy(self: *Character, delta_time: f32) void {
        var regen = self.school.getEnergyRegen();
        regen += self.gear_stats.energy_regen_bonus;

        const regen_mult = self.conditions.getEnergyRegenMultiplier();
        regen *= regen_mult;

        const energy_delta = regen * delta_time;
        self.stats.energy_accumulator += energy_delta;

        if (self.stats.energy_accumulator >= 1.0) {
            const energy_to_add = @as(u8, @intFromFloat(self.stats.energy_accumulator));
            self.stats.energy = @min(self.stats.max_energy, self.stats.energy + energy_to_add);
            self.stats.energy_accumulator -= @as(f32, @floatFromInt(energy_to_add));
        }

        // Update school-specific mechanics
        self.school_resources.update(self.school, delta_time, false);
    }

    // ========================================================================
    // WARMTH SYSTEM
    // ========================================================================

    pub fn updateWarmth(self: *Character, delta_time: f32) void {
        const warmth_delta = self.conditions.getWarmthDelta(delta_time);

        if (@abs(warmth_delta) >= 0.01) {
            self.stats.warmth = @max(0.0, @min(self.stats.max_warmth, self.stats.warmth + warmth_delta));

            if (self.stats.warmth <= 0) {
                self.is_dead = true;
                if (self.casting.state != .idle) {
                    self.casting.cancelCast();
                }
            }
        }
    }

    pub fn recalculateWarmthPips(self: *Character) void {
        self.conditions.recalculateWarmthPips(self.gear_stats.warmth_regen_bonus);
    }

    // ========================================================================
    // COOLDOWNS & CASTING
    // ========================================================================

    pub fn updateCooldowns(self: *Character, delta_time: f32) void {
        const result = self.casting.update(delta_time);
        _ = result; // Caller handles cast completion via finishCasts
    }

    pub fn canUseSkill(self: Character, skill_index: u8) bool {
        if (skill_index >= MAX_SKILLS) return false;
        if (!self.casting.canStartCast()) return false;
        if (self.casting.isOnCooldown(skill_index)) return false;

        // Can't use skills when knocked down
        if (self.isKnockedDown()) return false;

        const skill_to_check = self.casting.skills[skill_index] orelse return false;
        if (self.stats.energy < skill_to_check.energy_cost) return false;

        // Check school-specific resources (silently - no print spam)
        // Waldorf: Check rhythm requirement
        if (skill_to_check.requires_rhythm_stacks > 0 and self.school == .waldorf) {
            if (!self.school_resources.rhythm.has(skill_to_check.requires_rhythm_stacks)) {
                return false;
            }
        }

        // Private School: Check credit room
        if (skill_to_check.credit_cost > 0 and self.school == .private_school) {
            const current_effective_max = self.school_resources.credit_debt.getEffectiveMaxEnergy(self.stats.max_energy);
            if (current_effective_max <= 5) return false;
            const max_additional_credit = current_effective_max - 5;
            if (skill_to_check.credit_cost > max_additional_credit) return false;
        }

        // Homeschool: Check warmth sacrifice affordability
        if (skill_to_check.warmth_cost_percent > 0 and self.school == .homeschool) {
            if (!character_school_resources.SacrificeState.canAffordSacrifice(
                self.stats.warmth,
                self.stats.max_warmth,
                skill_to_check.warmth_cost_percent,
                skill_to_check.min_warmth_percent,
            )) {
                return false;
            }
        }

        // Public School: Check grit cost
        if (skill_to_check.grit_cost > 0 and self.school == .public_school) {
            if (!self.school_resources.grit.has(skill_to_check.grit_cost)) {
                return false;
            }
        }

        return true;
    }

    pub fn startCasting(self: *Character, skill_index: u8) void {
        const skill_to_cast = self.casting.skills[skill_index] orelse return;

        if (self.casting.startCast(skill_index, skill_to_cast, null)) {
            const energy_cost_mult = self.conditions.getEnergyCostMultiplier();
            const energy_cost = @as(u8, @intFromFloat(@as(f32, @floatFromInt(skill_to_cast.energy_cost)) * energy_cost_mult));
            self.stats.energy -= energy_cost;
        }
    }

    pub fn cancelCasting(self: *Character) void {
        self.casting.cancelCast();
    }

    pub fn canCancelCast(self: Character) bool {
        return self.casting.canCancelCast();
    }

    pub fn isCasting(self: Character) bool {
        return self.casting.isCasting();
    }

    // ========================================================================
    // SKILL QUEUE
    // ========================================================================

    pub fn queueSkill(self: *Character, skill_index: u8, target_id: EntityId) void {
        self.casting.queueSkill(skill_index, target_id);
    }

    pub fn clearSkillQueue(self: *Character) void {
        self.casting.clearQueue();
    }

    pub fn hasQueuedSkill(self: Character) bool {
        return self.casting.hasQueuedSkill();
    }

    // ========================================================================
    // CONDITIONS
    // ========================================================================

    pub fn updateConditions(self: *Character, delta_time_ms: u32) void {
        self.conditions.update(delta_time_ms, self.gear_stats.warmth_regen_bonus);
    }

    pub fn hasChill(self: Character, chill: skills.Chill) bool {
        return self.conditions.hasChill(chill);
    }

    pub fn hasCozy(self: Character, cozy: skills.Cozy) bool {
        return self.conditions.hasCozy(cozy);
    }

    pub fn addChill(self: *Character, effect: skills.ChillEffect, source_id: ?u32) void {
        _ = self.conditions.addChill(effect, source_id);
    }

    pub fn addCozy(self: *Character, effect: skills.CozyEffect, source_id: ?u32) void {
        _ = self.conditions.addCozy(effect, source_id);
    }

    pub fn addEffect(self: *Character, effect: *const effects.Effect, source_id: ?u32) void {
        _ = self.conditions.addEffect(effect, source_id);
    }

    /// Apply a knockdown effect for the specified duration (in milliseconds)
    /// Knockdown prevents movement and skill use
    pub fn applyKnockdown(self: *Character, duration_ms: u32, source_id: ?u32) void {
        _ = self.conditions.applyKnockdown(duration_ms, source_id);
        // If we were casting, interrupt it
        if (self.casting.state == .activating) {
            self.casting.cancelCast();
            std.debug.print("{s} was knocked down!\n", .{self.name});
        }
    }

    // ========================================================================
    // TRAIL EFFECTS
    // ========================================================================

    /// Start a trail effect that drops terrain as the character moves
    pub fn startTrailEffect(self: *Character, terrain_type: @import("terrain.zig").TerrainType, duration_ms: u32, trail_radius: f32, skill_name: [:0]const u8) void {
        self.conditions.startTrailEffect(terrain_type, duration_ms, trail_radius, skill_name);
    }

    /// Check if the character has an active trail effect
    pub fn hasActiveTrail(self: Character) bool {
        return self.conditions.hasActiveTrail();
    }

    /// Get the active trail effect (for applying terrain during movement)
    pub fn getActiveTrail(self: Character) ?character_conditions.ActiveTrailEffect {
        return self.conditions.getActiveTrail();
    }

    /// Stop any active trail effect
    pub fn stopTrailEffect(self: *Character) void {
        self.conditions.stopTrailEffect();
    }

    // ========================================================================
    // SKILL BAR / AP VALIDATION
    // ========================================================================

    pub fn countApSkills(self: Character) u8 {
        var count: u8 = 0;
        for (self.casting.skills) |maybe_skill| {
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
        for (self.casting.skills, 0..) |maybe_skill, i| {
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
            for (self.casting.skills, 0..) |maybe_existing, i| {
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

        self.casting.skills[slot_index] = skill_to_equip;
        return true;
    }

    pub fn unequipSkill(self: *Character, slot_index: u8) void {
        if (slot_index < MAX_SKILLS) {
            self.casting.skills[slot_index] = null;
        }
    }

    pub fn swapApSkill(self: *Character, new_ap_skill: *const Skill) ?u8 {
        if (!new_ap_skill.is_ap) return null;

        const existing_slot = self.getApSkillIndex();
        if (existing_slot) |slot| {
            self.casting.skills[slot] = new_ap_skill;
            return slot;
        }

        for (self.casting.skills, 0..) |maybe_skill, i| {
            if (maybe_skill == null) {
                self.casting.skills[i] = new_ap_skill;
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
        self.combat.damage_monitor.recordDamage(skill_source, source_id);
    }

    pub fn updateDamageMonitor(self: *Character, delta_time: f32) void {
        self.combat.damage_monitor.update(delta_time);
    }

    // ========================================================================
    // AUTO-ATTACK
    // ========================================================================

    pub fn startAutoAttack(self: *Character, target_id: EntityId) void {
        self.combat.auto_attack.start(target_id);
    }

    pub fn stopAutoAttack(self: *Character) void {
        self.combat.auto_attack.stop();
    }

    pub fn getAttackInterval(self: Character) f32 {
        return character_combat.getAttackInterval(self.main_hand, self.off_hand);
    }

    pub fn getAutoAttackDamage(self: Character) f32 {
        return character_combat.getAutoAttackDamage(self.main_hand, self.worn);
    }

    pub fn getAutoAttackRange(self: Character) f32 {
        return character_combat.getAutoAttackRange(self.main_hand, self.worn);
    }

    pub fn hasRangedAutoAttack(self: Character) bool {
        return character_combat.hasRangedAutoAttack(self.main_hand);
    }

    // ========================================================================
    // BEHAVIORS
    // ========================================================================

    pub fn addBehaviorFromSkill(self: *Character, skill_with_behavior: *const Skill, source_id: ?EntityId) bool {
        return self.behaviors.addFromSkill(skill_with_behavior, source_id);
    }

    pub fn updateBehaviors(self: *Character, delta_time_ms: u32) void {
        self.behaviors.update(delta_time_ms);
    }

    pub fn clearBehaviors(self: *Character) void {
        self.behaviors.clear();
    }
};
