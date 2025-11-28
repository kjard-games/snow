const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const targeting = @import("targeting.zig");
const combat = @import("combat.zig");
const skills = @import("skills.zig");
const movement = @import("movement.zig");
const entity_types = @import("entity.zig");
const position = @import("position.zig");
const vfx = @import("vfx.zig");
const terrain_mod = @import("terrain.zig");
const telemetry = @import("telemetry.zig");

const Character = character.Character;
const Skill = character.Skill;
const MovementIntent = movement.MovementIntent;
const EntityId = entity_types.EntityId;
const Position = position.Position;
const TerrainGrid = terrain_mod.TerrainGrid;
const VFXManager = vfx.VFXManager;
const MatchTelemetry = telemetry.MatchTelemetry;

// ============================================================================
// UTILITY AI SYSTEM
// ============================================================================
//
// Each tick, the AI:
// 1. Builds a snapshot of the combat situation (WorldState)
// 2. Evaluates utility of all possible skill actions
// 3. Executes the highest-utility action (or queues it if out of range)
// 4. Calculates tactical movement based on role and situation
//
// Utility scoring replaces rigid behavior trees - every action competes
// on equal footing, weighted by role preferences.
//
// ============================================================================

// ============================================================================
// CONFIGURATION
// ============================================================================

pub const Config = struct {
    pub const DECISION_INTERVAL_SEC: f32 = 0.15;
    pub const MIN_UTILITY_THRESHOLD: f32 = 0.1;

    // Health thresholds (percentage)
    pub const CRITICAL_HEALTH: f32 = 0.25;
    pub const LOW_HEALTH: f32 = 0.40;
    pub const WOUNDED: f32 = 0.60;
    pub const HEALTHY: f32 = 0.80;

    // Range thresholds
    pub const MELEE_RANGE: f32 = 100.0;
    pub const THREAT_RANGE: f32 = 150.0;
    pub const BACKLINE_SAFE_DIST: f32 = 180.0;

    // Movement
    pub const SPREAD_RADIUS: f32 = 35.0;
};

// ============================================================================
// AI ROLE
// ============================================================================

pub const AIRole = enum {
    damage_dealer,
    support,
    disruptor,

    pub fn fromPosition(pos: Position) AIRole {
        return switch (pos) {
            .pitcher, .fielder, .sledder => .damage_dealer,
            .thermos => .support,
            .animator, .shoveler => .disruptor,
        };
    }

    fn damageWeight(self: AIRole) f32 {
        return switch (self) {
            .damage_dealer => 1.2,
            .support => 0.5,
            .disruptor => 0.9,
        };
    }

    fn healingWeight(self: AIRole) f32 {
        return switch (self) {
            .damage_dealer => 0.8,
            .support => 1.5,
            .disruptor => 0.7,
        };
    }

    fn interruptWeight(self: AIRole) f32 {
        return switch (self) {
            .damage_dealer => 0.9,
            .support => 0.6,
            .disruptor => 1.4,
        };
    }
};

// ============================================================================
// FORMATION ROLE
// ============================================================================

pub const FormationRole = enum {
    frontline,
    midline,
    backline,

    pub fn fromPosition(pos: Position) FormationRole {
        return switch (pos) {
            .sledder, .shoveler => .frontline,
            .pitcher, .fielder => .midline,
            .animator, .thermos => .backline,
        };
    }

    fn preferredRange(self: FormationRole, pos: Position) f32 {
        const min_range = pos.getRangeMin();
        const max_range = pos.getRangeMax();
        return switch (self) {
            .frontline => min_range,
            .midline => (min_range + max_range) / 2.0,
            .backline => max_range * 0.85,
        };
    }
};

// ============================================================================
// AI STATE
// ============================================================================

pub const AIState = struct {
    role: AIRole = .damage_dealer,
    formation: FormationRole = .midline,
    next_decision_tick: u32 = 0,
    focus_target_id: ?EntityId = null,
    is_kiting: bool = false,

    pub fn init(pos: Position) AIState {
        return .{
            .role = AIRole.fromPosition(pos),
            .formation = FormationRole.fromPosition(pos),
        };
    }
};

// ============================================================================
// WORLD STATE - Combat snapshot for decision making
// ============================================================================

const MAX_ENTITIES: usize = 12;

const WorldState = struct {
    self: *Character,
    entities: []Character,

    // Categorized entity lists
    allies: [MAX_ENTITIES]*Character = undefined,
    ally_count: usize = 0,
    enemies: [MAX_ENTITIES]*Character = undefined,
    enemy_count: usize = 0,

    // Key targets
    lowest_ally: ?*Character = null,
    lowest_ally_health: f32 = 1.0,
    nearest_enemy: ?*Character = null,
    nearest_enemy_dist: f32 = std.math.floatMax(f32),
    casting_enemy: ?*Character = null,

    // Focus fire target (lowest HP enemy) - for coordinated attacks
    lowest_enemy: ?*Character = null,
    lowest_enemy_health: f32 = 1.0,

    // Enemy healer (priority target)
    enemy_healer: ?*Character = null,

    // Positions
    enemy_center: rl.Vector3 = .{ .x = 0, .y = 0, .z = 0 },

    // External systems
    terrain: *const TerrainGrid,
    vfx_mgr: *VFXManager,
    rng: *std.Random,
    telem: ?*MatchTelemetry,
    dt: f32,

    fn build(
        self_char: *Character,
        all_entities: []Character,
        terrain: *const TerrainGrid,
        vfx_mgr: *VFXManager,
        rng: *std.Random,
        telem: ?*MatchTelemetry,
        dt: f32,
    ) WorldState {
        var state = WorldState{
            .self = self_char,
            .entities = all_entities,
            .terrain = terrain,
            .vfx_mgr = vfx_mgr,
            .rng = rng,
            .telem = telem,
            .dt = dt,
        };

        var enemy_pos_sum = rl.Vector3{ .x = 0, .y = 0, .z = 0 };

        for (all_entities) |*ent| {
            if (!ent.isAlive()) continue;

            if (self_char.isAlly(ent.*)) {
                if (state.ally_count < MAX_ENTITIES) {
                    state.allies[state.ally_count] = ent;
                    state.ally_count += 1;

                    const hp = ent.stats.warmth / ent.stats.max_warmth;
                    if (hp < state.lowest_ally_health) {
                        state.lowest_ally_health = hp;
                        state.lowest_ally = ent;
                    }
                }
            } else {
                if (state.enemy_count < MAX_ENTITIES) {
                    state.enemies[state.enemy_count] = ent;
                    state.enemy_count += 1;

                    enemy_pos_sum.x += ent.position.x;
                    enemy_pos_sum.z += ent.position.z;

                    const dist = self_char.distanceTo(ent.*);
                    if (dist < state.nearest_enemy_dist) {
                        state.nearest_enemy_dist = dist;
                        state.nearest_enemy = ent;
                    }

                    if (ent.casting.state == .activating) {
                        state.casting_enemy = ent;
                    }

                    // Track lowest HP enemy for focus fire
                    const enemy_hp = ent.stats.warmth / ent.stats.max_warmth;
                    if (enemy_hp < state.lowest_enemy_health) {
                        state.lowest_enemy_health = enemy_hp;
                        state.lowest_enemy = ent;
                    }

                    // Track enemy healer (thermos) as priority target
                    if (ent.player_position == .thermos) {
                        state.enemy_healer = ent;
                    }
                }
            }
        }

        if (state.enemy_count > 0) {
            const n = @as(f32, @floatFromInt(state.enemy_count));
            state.enemy_center.x = enemy_pos_sum.x / n;
            state.enemy_center.z = enemy_pos_sum.z / n;
        }

        return state;
    }

    fn selfHealth(self: *const WorldState) f32 {
        return self.self.stats.warmth / self.self.stats.max_warmth;
    }

    fn hasWallTo(self: *const WorldState, target: *const Character) bool {
        return self.terrain.hasWallBetween(
            self.self.position.x,
            self.self.position.z,
            target.position.x,
            target.position.z,
            10.0,
        );
    }

    // ========== TERRAIN EVALUATION HELPERS ==========

    /// Get terrain speed modifier at a world position
    fn getTerrainSpeedAt(self: *const WorldState, x: f32, z: f32) f32 {
        return self.terrain.getMovementSpeedAt(x, z);
    }

    /// Get terrain speed modifier at character's current position
    fn getSelfTerrainSpeed(self: *const WorldState) f32 {
        return self.getTerrainSpeedAt(self.self.position.x, self.self.position.z);
    }

    /// Check if terrain at position is icy (slippery - knockdown risk when hit while moving)
    fn isIcyAt(self: *const WorldState, x: f32, z: f32) bool {
        if (self.terrain.getCellAtConst(x, z)) |cell| {
            return cell.type == .icy_ground;
        }
        return false;
    }

    /// Check if self is standing on icy terrain
    fn selfOnIce(self: *const WorldState) bool {
        return self.isIcyAt(self.self.position.x, self.self.position.z);
    }

    /// Check if terrain at position is slow (speed < 1.0)
    fn isSlowTerrainAt(self: *const WorldState, x: f32, z: f32) bool {
        return self.getTerrainSpeedAt(x, z) < 0.95;
    }

    /// Check if terrain at position is fast (speed > 1.0)
    fn isFastTerrainAt(self: *const WorldState, x: f32, z: f32) bool {
        return self.getTerrainSpeedAt(x, z) > 1.05;
    }

    /// Sample terrain speed in a direction from current position
    /// Returns average speed modifier along the path
    fn sampleTerrainInDirection(self: *const WorldState, dir_x: f32, dir_z: f32, sample_dist: f32) f32 {
        const sample_count: usize = 3;
        var total_speed: f32 = 0.0;

        for (1..sample_count + 1) |i| {
            const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(sample_count));
            const sample_x = self.self.position.x + dir_x * sample_dist * t;
            const sample_z = self.self.position.z + dir_z * sample_dist * t;
            total_speed += self.getTerrainSpeedAt(sample_x, sample_z);
        }

        return total_speed / @as(f32, @floatFromInt(sample_count));
    }

    /// Evaluate terrain quality in a direction (higher = better for movement)
    /// Considers: speed modifier, ice risk (if enemies nearby), wall obstacles
    fn evalTerrainDirection(self: *const WorldState, dir_x: f32, dir_z: f32, sample_dist: f32) f32 {
        var score: f32 = 0.0;

        // Base score from average speed along path
        const avg_speed = self.sampleTerrainInDirection(dir_x, dir_z, sample_dist);
        score += avg_speed; // 0.5 to 1.2 typically

        // Penalty for ice when enemies are nearby (knockdown risk)
        if (self.nearest_enemy_dist < Config.THREAT_RANGE) {
            const check_x = self.self.position.x + dir_x * sample_dist * 0.5;
            const check_z = self.self.position.z + dir_z * sample_dist * 0.5;
            if (self.isIcyAt(check_x, check_z)) {
                score -= 0.3; // Significant penalty for ice when threatened
            }
        }

        // Check for walls blocking the path
        const end_x = self.self.position.x + dir_x * sample_dist;
        const end_z = self.self.position.z + dir_z * sample_dist;
        const wall_height = self.terrain.getWallHeightAt(end_x, end_z);
        if (wall_height > 15.0) {
            score -= 0.5; // Big penalty for running into walls
        } else if (wall_height > 5.0) {
            score -= 0.2; // Smaller penalty for low walls
        }

        return score;
    }
};

// ============================================================================
// SKILL ACTION
// ============================================================================

const SkillAction = struct {
    skill_idx: u8,
    target: ?*Character,
    target_id: ?EntityId,
    utility: f32,
    in_range: bool,
};

// ============================================================================
// UTILITY CALCULATIONS
// ============================================================================

fn evalDamageSkill(
    skill: *const Skill,
    target: *const Character,
    world: *const WorldState,
    ai: *const AIState,
) f32 {
    var util: f32 = 0.4;

    // Damage scaling
    util += @min(skill.damage / 60.0, 0.3);

    // Focus fire bonus - strong preference for lowest HP enemy
    const target_hp = target.stats.warmth / target.stats.max_warmth;
    if (world.lowest_enemy) |low| {
        if (target.id == low.id) {
            // Big bonus for attacking the focus target
            util += 0.35;
        }
    }

    // Execute bonus - targets below 40% HP
    if (target_hp < Config.LOW_HEALTH) {
        util += 0.25;
        if (skill.damage >= target.stats.warmth) {
            util += 0.20; // Kill shot - even bigger bonus
        }
    } else if (target_hp < Config.WOUNDED) {
        // Medium bonus for wounded targets (below 60%)
        util += 0.15;
    }

    // Priority target: enemy healer (thermos)
    if (target.player_position == .thermos) {
        util += 0.20; // Healers are high-value targets
    }

    // Arcing projectiles beat cover
    if (world.hasWallTo(target)) {
        if (skill.projectile_type == .arcing) {
            util += 0.15;
        } else {
            util -= 0.3;
        }
    }

    // Terrain-aware targeting: bonus for hitting targets on ice while they're moving
    // (ice slip mechanic: moving targets on ice get knocked down when hit)
    if (world.isIcyAt(target.position.x, target.position.z)) {
        if (target.isMoving()) {
            util += 0.25; // Big bonus - will trigger knockdown!
        } else {
            util += 0.05; // Small bonus - they might start moving
        }
    }

    return std.math.clamp(util * ai.role.damageWeight(), 0.0, 1.0);
}

fn evalHealSkill(
    skill: *const Skill,
    target: *const Character,
    world: *const WorldState,
    ai: *const AIState,
) f32 {
    const hp = target.stats.warmth / target.stats.max_warmth;

    // Don't heal healthy targets
    if (hp > Config.HEALTHY) return 0.0;

    var util: f32 = 0.35;

    // Urgency-based scaling - very aggressive healing for critical targets
    if (hp < Config.CRITICAL_HEALTH) {
        util += 0.65; // CRITICAL - top priority
    } else if (hp < Config.LOW_HEALTH) {
        util += 0.45; // LOW - urgent
    } else if (hp < Config.WOUNDED) {
        util += 0.25;
    }

    // Bonus for healing the lowest HP ally (focus heal)
    if (world.lowest_ally) |low| {
        if (target.id == low.id) {
            util += 0.20; // Extra bonus for the most wounded ally
        }
    }

    // Efficiency - prefer not to overheal, but don't let efficiency block urgent heals
    const missing = target.stats.max_warmth - target.stats.warmth;
    const efficiency = @min(missing, skill.healing) / skill.healing;
    if (hp > Config.LOW_HEALTH) {
        // Only apply efficiency penalty for non-urgent heals
        util *= (0.6 + efficiency * 0.4);
    }

    // Priority heal the healer (keep healer alive is critical)
    if (target.player_position == .thermos) {
        util += 0.15;
    }

    // Priority heal damage dealers who are being focused
    if (target.player_position == .pitcher or target.player_position == .sledder) {
        if (hp < Config.WOUNDED) {
            util += 0.10;
        }
    }

    return std.math.clamp(util * ai.role.healingWeight() * 1.3, 0.0, 1.0);
}

fn evalInterruptSkill(
    target: *const Character,
    ai: *const AIState,
) f32 {
    if (target.casting.state != .activating) return 0.0;

    var util: f32 = 0.6;

    // Check what they're casting
    if (target.casting.skills[target.casting.casting_skill_index]) |enemy_skill| {
        if (enemy_skill.healing > 0) util += 0.3;
        if (enemy_skill.damage > 35) util += 0.15;
    }

    return std.math.clamp(util * ai.role.interruptWeight(), 0.0, 1.0);
}

fn evalDebuffSkill(skill: *const Skill, target: *const Character) f32 {
    var util: f32 = 0.25;

    for (skill.chills) |chill| {
        util += switch (chill.chill) {
            .dazed => 0.3,
            .slippery => 0.15,
            .brain_freeze => 0.15,
            else => 0.08,
        };
    }

    // Debuff healers
    if (target.player_position == .thermos) {
        util += 0.15;
    }

    return std.math.clamp(util, 0.0, 1.0);
}

fn evalBuffSkill(skill: *const Skill, target: *const Character) f32 {
    var util: f32 = 0.2;

    for (skill.cozies) |cozy| {
        util += switch (cozy.cozy) {
            .fire_inside => if (target.player_position == .pitcher) 0.25 else 0.15,
            .bundled_up => 0.15,
            .hot_cocoa => 0.1,
            else => 0.08,
        };
    }

    return std.math.clamp(util, 0.0, 1.0);
}

fn evalTerrainSkill(skill: *const Skill, world: *const WorldState) f32 {
    var util: f32 = 0.1;

    if (skill.terrain_effect.heals_allies and world.lowest_ally_health < Config.WOUNDED) {
        util += 0.25;
    }

    if (skill.terrain_effect.damages_enemies and world.enemy_count >= 2) {
        util += 0.2;
    }

    // Randomize to prevent spam
    if (world.rng.float(f32) > 0.35) {
        util *= 0.4;
    }

    return std.math.clamp(util, 0.0, 1.0);
}

fn evalWallSkill(world: *const WorldState, ai: *const AIState) f32 {
    var util: f32 = 0.05;

    // Defensive walls when hurt and pressured
    if (world.selfHealth() < Config.LOW_HEALTH and world.self.combat.damage_monitor.count > 0) {
        util += 0.4;
    }

    // Frontline builds walls to protect backline
    if (ai.formation == .frontline and world.lowest_ally_health < Config.WOUNDED) {
        util += 0.2;
    }

    return std.math.clamp(util, 0.0, 1.0);
}

// ============================================================================
// SKILL EVALUATION
// ============================================================================

fn evaluateAllSkills(world: *const WorldState, ai: *const AIState) ?SkillAction {
    var best: ?SkillAction = null;
    var best_util: f32 = Config.MIN_UTILITY_THRESHOLD;

    const caster = world.self;

    for (caster.casting.skills, 0..) |maybe_skill, i| {
        const skill = maybe_skill orelse continue;
        const idx: u8 = @intCast(i);

        if (!caster.canUseSkill(idx)) continue;

        switch (skill.target_type) {
            .enemy => {
                for (world.enemies[0..world.enemy_count]) |enemy| {
                    const dist = caster.distanceTo(enemy.*);
                    const in_range = dist <= skill.cast_range;

                    var util: f32 = 0.0;
                    if (skill.interrupts and enemy.casting.state == .activating) {
                        util = evalInterruptSkill(enemy, ai);
                    } else if (skill.damage > 0) {
                        util = evalDamageSkill(skill, enemy, world, ai);
                    } else if (skill.chills.len > 0) {
                        util = evalDebuffSkill(skill, enemy);
                    }

                    // Range penalty for out-of-range skills
                    if (!in_range) {
                        util *= 0.7;
                    }

                    if (util > best_util) {
                        best_util = util;
                        best = .{
                            .skill_idx = idx,
                            .target = enemy,
                            .target_id = enemy.id,
                            .utility = util,
                            .in_range = in_range,
                        };
                    }
                }
            },
            .ally => {
                for (world.allies[0..world.ally_count]) |ally| {
                    const dist = caster.distanceTo(ally.*);
                    const in_range = dist <= skill.cast_range;

                    var util: f32 = 0.0;
                    if (skill.healing > 0) {
                        util = evalHealSkill(skill, ally, world, ai);
                    } else if (skill.cozies.len > 0) {
                        util = evalBuffSkill(skill, ally);
                    }

                    if (!in_range) {
                        util *= 0.6;
                    }

                    if (util > best_util) {
                        best_util = util;
                        best = .{
                            .skill_idx = idx,
                            .target = ally,
                            .target_id = ally.id,
                            .utility = util,
                            .in_range = in_range,
                        };
                    }
                }
            },
            .self => {
                var util: f32 = 0.0;
                if (skill.healing > 0) {
                    util = evalHealSkill(skill, caster, world, ai);
                } else if (skill.cozies.len > 0) {
                    util = evalBuffSkill(skill, caster);
                } else if (skill.terrain_effect.shape != .none) {
                    util = evalTerrainSkill(skill, world);
                }

                if (util > best_util) {
                    best_util = util;
                    best = .{
                        .skill_idx = idx,
                        .target = caster,
                        .target_id = caster.id,
                        .utility = util,
                        .in_range = true,
                    };
                }
            },
            .ground => {
                var util: f32 = 0.0;
                if (skill.creates_wall) {
                    util = evalWallSkill(world, ai);
                } else if (skill.terrain_effect.shape != .none) {
                    util = evalTerrainSkill(skill, world);
                }

                if (util > best_util) {
                    best_util = util;
                    best = .{
                        .skill_idx = idx,
                        .target = null,
                        .target_id = null,
                        .utility = util,
                        .in_range = true,
                    };
                }
            },
        }
    }

    return best;
}

// ============================================================================
// ACTION EXECUTION
// ============================================================================

fn executeAction(action: *const SkillAction, world: *const WorldState) bool {
    const caster = world.self;

    // Ground-targeted skills
    if (action.target == null) {
        const skill = caster.casting.skills[action.skill_idx] orelse return false;
        const pos = if (skill.creates_wall)
            calcWallPos(world)
        else if (skill.terrain_effect.heals_allies)
            if (world.lowest_ally) |ally| ally.position else caster.position
        else
            world.enemy_center;

        const result = combat.tryStartCastAtGround(
            caster,
            action.skill_idx,
            pos,
            world.rng,
            world.vfx_mgr,
            @constCast(world.terrain),
            world.telem,
        );
        return result == .success or result == .casting_started;
    }

    // Targeted skills
    const result = combat.tryStartCast(
        caster,
        action.skill_idx,
        action.target,
        action.target_id,
        world.rng,
        world.vfx_mgr,
        @constCast(world.terrain),
        world.telem,
    );

    // Queue if out of range
    if (result == .out_of_range) {
        if (action.target_id) |tid| {
            caster.queueSkill(action.skill_idx, tid);
            if (world.telem) |t| t.recordQueueSkillCall(caster.id);
        }
        return false;
    }

    return result == .success or result == .casting_started;
}

fn calcWallPos(world: *const WorldState) rl.Vector3 {
    if (world.nearest_enemy) |enemy| {
        const dx = enemy.position.x - world.self.position.x;
        const dz = enemy.position.z - world.self.position.z;
        return .{
            .x = world.self.position.x + dx * 0.4,
            .y = 0,
            .z = world.self.position.z + dz * 0.4,
        };
    }
    return world.self.position;
}

fn tryExecuteQueued(ent: *Character, world: *const WorldState) bool {
    const queued = ent.casting.queued_skill orelse return false;

    // Find target
    var target: ?*Character = null;
    for (world.entities) |*e| {
        if (e.id == queued.target_id) {
            target = e;
            break;
        }
    }

    if (target == null or !target.?.isAlive()) {
        ent.clearSkillQueue();
        if (world.telem) |t| t.recordExecuteQueueTargetDead(ent.id);
        return false;
    }

    const skill = ent.casting.skills[queued.skill_index] orelse {
        ent.clearSkillQueue();
        return false;
    };

    if (ent.distanceTo(target.?.*) > skill.cast_range) {
        if (world.telem) |t| t.recordExecuteQueueOutOfRange(ent.id);
        return false;
    }

    const result = combat.tryStartCast(
        ent,
        queued.skill_index,
        target,
        queued.target_id,
        world.rng,
        world.vfx_mgr,
        @constCast(world.terrain),
        world.telem,
    );

    if (result == .success or result == .casting_started) {
        ent.clearSkillQueue();
        if (world.telem) |t| t.recordExecuteQueueSuccess(ent.id);
        return true;
    }

    if (world.telem) |t| t.recordExecuteQueueNoEnergy(ent.id);
    return false;
}

// ============================================================================
// MOVEMENT
// ============================================================================

fn calcMovement(world: *const WorldState, ai: *AIState, action: ?*const SkillAction) MovementIntent {
    const self = world.self;
    var move_x: f32 = 0.0;
    var move_z: f32 = 0.0;

    // Priority: Move toward queued skill target
    if (self.hasQueuedSkill()) {
        if (self.casting.queued_skill) |queued| {
            for (world.entities) |*e| {
                if (e.id == queued.target_id and e.isAlive()) {
                    const dx = e.position.x - self.position.x;
                    const dz = e.position.z - self.position.z;
                    const dist = @sqrt(dx * dx + dz * dz);
                    if (dist > 1.0) {
                        move_x = dx / dist;
                        move_z = dz / dist;
                    }
                    break;
                }
            }
        }
    }
    // Otherwise: Move toward chosen action target if out of range
    else if (action) |a| {
        if (!a.in_range) {
            if (a.target) |target| {
                const dx = target.position.x - self.position.x;
                const dz = target.position.z - self.position.z;
                const dist = @sqrt(dx * dx + dz * dz);
                if (dist > 1.0) {
                    move_x = dx / dist;
                    move_z = dz / dist;
                }
            }
        }
    }

    // Tactical positioning when no specific target
    if (move_x == 0.0 and move_z == 0.0) {
        if (world.nearest_enemy) |enemy| {
            const dx = enemy.position.x - self.position.x;
            const dz = enemy.position.z - self.position.z;
            const dist = world.nearest_enemy_dist;

            if (dist > 1.0) {
                const dir_x = dx / dist;
                const dir_z = dz / dist;
                const preferred = ai.formation.preferredRange(self.player_position);
                const self_hp = world.selfHealth();

                switch (ai.formation) {
                    .frontline => {
                        if (dist > preferred * 1.2) {
                            move_x = dir_x;
                            move_z = dir_z;
                        }
                    },
                    .midline => {
                        // Kite when hurt
                        if (self_hp < Config.LOW_HEALTH or (dist < Config.MELEE_RANGE and self_hp < Config.WOUNDED)) {
                            move_x = -dir_x;
                            move_z = -dir_z;
                            ai.is_kiting = true;
                        } else if (dist > preferred * 1.5) {
                            // Very far - full speed approach
                            move_x = dir_x;
                            move_z = dir_z;
                            ai.is_kiting = false;
                        } else if (dist > preferred * 1.1) {
                            // Slightly out of range - approach at reduced speed
                            move_x = dir_x * 0.7;
                            move_z = dir_z * 0.7;
                            ai.is_kiting = false;
                        } else if (dist < preferred * 0.7) {
                            move_x = -dir_x * 0.5;
                            move_z = -dir_z * 0.5;
                        } else {
                            ai.is_kiting = false;
                        }
                    },
                    .backline => {
                        // Retreat when threatened
                        if (dist < Config.THREAT_RANGE) {
                            move_x = -dir_x;
                            move_z = -dir_z;
                        } else if (dist < Config.BACKLINE_SAFE_DIST) {
                            move_x = -dir_x * 0.5;
                            move_z = -dir_z * 0.5;
                        } else if (dist > preferred * 1.5) {
                            // Too far from fight - cautiously approach
                            move_x = dir_x * 0.5;
                            move_z = dir_z * 0.5;
                        }
                    },
                }
            }
        }
    }

    // Spread from allies to avoid AoE
    const spread = calcSpread(self, world.allies[0..world.ally_count], world.ally_count);
    move_x += spread.x * 0.25;
    move_z += spread.z * 0.25;

    // ========== TERRAIN-AWARE MOVEMENT ADJUSTMENTS ==========
    // Evaluate terrain quality and adjust movement direction slightly

    // If we have a movement direction, evaluate terrain along that path
    const move_mag = @sqrt(move_x * move_x + move_z * move_z);
    if (move_mag > 0.1) {
        const norm_x = move_x / move_mag;
        const norm_z = move_z / move_mag;

        // Sample terrain quality in intended direction vs perpendicular alternatives
        const sample_dist: f32 = 50.0; // Look ahead 50 units
        const intended_score = world.evalTerrainDirection(norm_x, norm_z, sample_dist);

        // Check perpendicular directions (left and right of intended path)
        const perp_l_x = -norm_z;
        const perp_l_z = norm_x;
        const perp_r_x = norm_z;
        const perp_r_z = -norm_x;

        // Blend directions: 70% intended + 30% perpendicular
        const blend_l_x = norm_x * 0.7 + perp_l_x * 0.3;
        const blend_l_z = norm_z * 0.7 + perp_l_z * 0.3;
        const blend_r_x = norm_x * 0.7 + perp_r_x * 0.3;
        const blend_r_z = norm_z * 0.7 + perp_r_z * 0.3;

        const left_score = world.evalTerrainDirection(blend_l_x, blend_l_z, sample_dist);
        const right_score = world.evalTerrainDirection(blend_r_x, blend_r_z, sample_dist);

        // Only adjust if alternative is significantly better (0.2+ improvement)
        const improvement_threshold: f32 = 0.2;

        if (left_score > intended_score + improvement_threshold and left_score >= right_score) {
            // Shift movement slightly left for better terrain
            move_x = move_x * 0.8 + perp_l_x * move_mag * 0.3;
            move_z = move_z * 0.8 + perp_l_z * move_mag * 0.3;
        } else if (right_score > intended_score + improvement_threshold) {
            // Shift movement slightly right for better terrain
            move_x = move_x * 0.8 + perp_r_x * move_mag * 0.3;
            move_z = move_z * 0.8 + perp_r_z * move_mag * 0.3;
        }

        // Emergency ice avoidance: if we're moving and on ice with nearby enemies, stop or retreat
        if (world.selfOnIce() and world.nearest_enemy_dist < Config.MELEE_RANGE) {
            // On ice with enemies close - reduce movement speed to minimize knockdown risk
            // (Standing still on ice is safer than moving when you might get hit)
            move_x *= 0.3;
            move_z *= 0.3;
        }
    }

    // Normalize
    const mag = @sqrt(move_x * move_x + move_z * move_z);
    if (mag > 1.0) {
        move_x /= mag;
        move_z /= mag;
    }

    // Convert to local space
    const cos_f = @cos(self.facing_angle);
    const sin_f = @sin(self.facing_angle);

    return .{
        .local_x = move_x * cos_f + move_z * sin_f,
        .local_z = -move_x * sin_f + move_z * cos_f,
        .facing_angle = self.facing_angle,
        .apply_penalties = true,
    };
}

fn calcSpread(self: *const Character, allies: []const *Character, count: usize) rl.Vector3 {
    var force = rl.Vector3{ .x = 0, .y = 0, .z = 0 };

    for (allies[0..count]) |ally| {
        if (ally.id == self.id) continue;

        const dx = self.position.x - ally.position.x;
        const dz = self.position.z - ally.position.z;
        const dist = @sqrt(dx * dx + dz * dz);

        if (dist < Config.SPREAD_RADIUS and dist > 0.5) {
            const strength = (Config.SPREAD_RADIUS - dist) / Config.SPREAD_RADIUS;
            force.x += (dx / dist) * strength;
            force.z += (dz / dist) * strength;
        }
    }

    return force;
}

// ============================================================================
// AUTO-ATTACK
// ============================================================================

fn manageAutoAttack(ent: *Character, world: *const WorldState) void {
    if (world.nearest_enemy) |target| {
        if (world.nearest_enemy_dist <= ent.getAutoAttackRange()) {
            if (!ent.combat.auto_attack.is_active or ent.combat.auto_attack.target_id != target.id) {
                if (ent.casting.state == .idle) {
                    ent.startAutoAttack(target.id);
                }
            }
        } else if (ent.combat.auto_attack.is_active) {
            ent.stopAutoAttack();
        }
    } else if (ent.combat.auto_attack.is_active) {
        ent.stopAutoAttack();
    }
}

// ============================================================================
// MAIN UPDATE
// ============================================================================

/// Global tick counter for AI decision timing (incremented each call to updateAI)
var ai_global_tick: u32 = 0;

pub fn updateAI(
    entities: []Character,
    controlled_entity_id: EntityId,
    delta_time: f32,
    ai_states: []AIState,
    rng: *std.Random,
    vfx_manager: *VFXManager,
    terrain_grid: *const TerrainGrid,
    match_telemetry: ?*MatchTelemetry,
) void {
    // Increment global tick counter each update (works for both real-time and headless)
    ai_global_tick +%= 1;

    for (entities, 0..) |*ent, i| {
        if (!ent.isAlive()) continue;
        if (ent.id == controlled_entity_id) continue;
        if (i >= ai_states.len) continue;

        var ai = &ai_states[i];

        // Initialize if needed
        if (ai.role == .damage_dealer and ai.formation == .midline and ent.player_position != .pitcher and ent.player_position != .fielder) {
            ai.* = AIState.init(ent.player_position);
        }

        // Build world state
        var world = WorldState.build(ent, entities, terrain_grid, vfx_manager, rng, match_telemetry, delta_time);

        // Handle queued skills first
        if (ent.hasQueuedSkill()) {
            _ = tryExecuteQueued(ent, &world);
        }

        // Decision making at intervals (every 3 ticks = ~150ms at 20Hz)
        var chosen_action: ?SkillAction = null;
        if (ai_global_tick >= ai.next_decision_tick and !ent.hasQueuedSkill() and ent.casting.state == .idle) {
            ai.next_decision_tick = ai_global_tick + 3;

            chosen_action = evaluateAllSkills(&world, ai);

            if (chosen_action) |*action| {
                if (action.in_range) {
                    _ = executeAction(action, &world);
                }
            }
        }

        // Auto-attack
        manageAutoAttack(ent, &world);

        // Movement - ALWAYS calculate and apply movement when idle (not just when action chosen)
        if (ent.casting.state == .idle) {
            const intent = calcMovement(&world, ai, if (chosen_action) |*a| a else null);
            movement.applyMovement(ent, intent, entities, null, null, delta_time, terrain_grid);
        }
    }
}
